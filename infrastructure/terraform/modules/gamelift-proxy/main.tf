# gamelift-proxy: API Gateway HTTP API + Lambda that fronts the three player-facing GameLift
# calls for Shipping clients (UFrontendGameLiftSettings.ApiEndpointUrl), and optionally a
# read-only leaderboard in DynamoDB (enable_leaderboard).
#
# Cost: effectively $0 at tutorial scale (HTTP API $1 per million requests, Lambda free tier).
# Nothing here bills while idle, so unlike the build box it is meant to stay deployed.

terraform {
  required_version = ">= 1.10"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  name = "${var.project_name}-gamelift-proxy"
  # Resource ARNs the Lambda may act on. GameLift game/player-session ARNs carry the fleet id.
  fleet_arns = var.fleet_id == "" ? ["*"] : [
    "arn:aws:gamelift:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:fleet/${var.fleet_id}",
    "arn:aws:gamelift:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:containerfleet/${var.fleet_id}",
    "arn:aws:gamelift:${data.aws_region.current.name}::gamesession/${var.fleet_id}/*",
  ]
}

data "archive_file" "lambda" {
  type        = "zip"
  source_file = "${path.module}/lambda/proxy.py"
  output_path = "${path.module}/.build/proxy.zip"
}

# ---- IAM -----------------------------------------------------------------------------------

data "aws_iam_policy_document" "assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "gamelift" {
  statement {
    sid = "GameLiftPlayerFacing"
    actions = [
      "gamelift:CreateGameSession",
      "gamelift:DescribeGameSessions",
      "gamelift:CreatePlayerSession",
      "gamelift:StartGameSessionPlacement",
      "gamelift:DescribeGameSessionPlacement",
      "gamelift:StopGameSessionPlacement", # client abandons a PENDING placement
      "gamelift:DescribeAlias",            # alias -> fleet resolution for the session-ownership check
    ]
    # GameLift's resource-level support for these actions is partial; keep "*" for the
    # Describe call and let the Lambda pin the fleet in the payload instead.
    resources = ["*"]
  }
}

resource "aws_iam_role" "lambda" {
  name               = local.name
  assume_role_policy = data.aws_iam_policy_document.assume.json
}

resource "aws_iam_role_policy" "gamelift" {
  name   = "gamelift-player-facing"
  role   = aws_iam_role.lambda.id
  policy = data.aws_iam_policy_document.gamelift.json
}

# Optional: read the EOS client secret (SecureString) for Basic auth on Epic's tokenInfo.
data "aws_iam_policy_document" "ssm" {
  count = var.eos_client_secret_ssm_parameter == "" ? 0 : 1
  statement {
    actions   = ["ssm:GetParameter"]
    resources = ["arn:aws:ssm:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:parameter${var.eos_client_secret_ssm_parameter}"]
  }
  statement {
    actions   = ["kms:Decrypt"]
    resources = ["arn:aws:kms:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:alias/aws/ssm"]
  }
}

resource "aws_iam_role_policy" "ssm" {
  count  = var.eos_client_secret_ssm_parameter == "" ? 0 : 1
  name   = "eos-client-secret"
  role   = aws_iam_role.lambda.id
  policy = data.aws_iam_policy_document.ssm[0].json
}

# ---- Leaderboard (optional) ------------------------------------------------------------------
#
# One item per player per board: Board (S) + PlayerId (S) -> Score (N), DisplayName (S).
# The ByScore index turns "top N of a board" into one Query (descending, Limit N) and "rank of a
# player" into a COUNT of the scores above theirs. On-demand billing: $0 while nobody plays.
# All boards of this size live happily in one index partition; a board with millions of players
# would shard the index key (Board#0..9) and merge the top rows in the Lambda.

resource "aws_dynamodb_table" "leaderboard" {
  count        = var.enable_leaderboard ? 1 : 0
  name         = "${var.project_name}-leaderboard"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "Board"
  range_key    = "PlayerId"

  attribute {
    name = "Board"
    type = "S"
  }
  attribute {
    name = "PlayerId"
    type = "S"
  }
  attribute {
    name = "Score"
    type = "N"
  }

  global_secondary_index {
    name               = "ByScore"
    hash_key           = "Board"
    range_key          = "Score"
    projection_type    = "INCLUDE"
    non_key_attributes = ["DisplayName"]
  }

  point_in_time_recovery {
    enabled = true
  }

  deletion_protection_enabled = var.leaderboard_deletion_protection
}

# Read-only on purpose: nothing a game client sends through the proxy can write a score.
data "aws_iam_policy_document" "leaderboard" {
  count = var.enable_leaderboard ? 1 : 0
  statement {
    sid       = "LeaderboardRead"
    actions   = ["dynamodb:Query", "dynamodb:GetItem"]
    resources = [aws_dynamodb_table.leaderboard[0].arn, "${aws_dynamodb_table.leaderboard[0].arn}/index/ByScore"]
  }
}

resource "aws_iam_role_policy" "leaderboard" {
  count  = var.enable_leaderboard ? 1 : 0
  name   = "leaderboard-read"
  role   = aws_iam_role.lambda.id
  policy = data.aws_iam_policy_document.leaderboard[0].json
}

resource "aws_iam_role_policy_attachment" "logs" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# ---- Lambda --------------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${local.name}"
  retention_in_days = var.log_retention_days
}

resource "aws_lambda_function" "proxy" {
  function_name    = local.name
  role             = aws_iam_role.lambda.arn
  runtime          = "python3.12"
  handler          = "proxy.handler"
  architectures    = ["arm64"]
  filename         = data.archive_file.lambda.output_path
  source_code_hash = data.archive_file.lambda.output_base64sha256
  timeout          = 15
  memory_size      = 256

  environment {
    variables = {
      GAMELIFT_REGION         = data.aws_region.current.name
      FLEET_ID                = var.fleet_id
      ALIAS_ID                = var.alias_id
      QUEUE_NAME              = var.queue_name
      AUTH_MODE               = var.auth_mode
      EOS_CLIENT_ID           = var.eos_client_id
      EOS_CLIENT_SECRET_PARAM = var.eos_client_secret_ssm_parameter
      LEADERBOARD_TABLE       = var.enable_leaderboard ? aws_dynamodb_table.leaderboard[0].name : ""
      LEADERBOARD_INDEX       = "ByScore"
      LEADERBOARD_BOARDS      = join(",", var.leaderboard_boards)
    }
  }

  depends_on = [aws_cloudwatch_log_group.lambda, aws_iam_role_policy_attachment.logs]
}

# ---- HTTP API ------------------------------------------------------------------------------

resource "aws_apigatewayv2_api" "proxy" {
  name          = local.name
  protocol_type = "HTTP"
  description   = "GameLift client-API proxy for FrontendUI Shipping builds"
}

resource "aws_apigatewayv2_integration" "lambda" {
  api_id                 = aws_apigatewayv2_api.proxy.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.proxy.invoke_arn
  payload_format_version = "2.0"
  timeout_milliseconds   = 15000
}

# Single POST route; the operation is selected by the X-Amz-Target header, exactly like GameLift.
resource "aws_apigatewayv2_route" "post" {
  api_id    = aws_apigatewayv2_api.proxy.id
  route_key = "POST /"
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

resource "aws_cloudwatch_log_group" "api" {
  name              = "/aws/apigateway/${local.name}"
  retention_in_days = var.log_retention_days
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.proxy.id
  name        = "$default"
  auto_deploy = true

  default_route_settings {
    throttling_burst_limit = var.throttle_burst
    throttling_rate_limit  = var.throttle_rate
  }

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api.arn
    format = jsonencode({
      requestId = "$context.requestId", ip = "$context.identity.sourceIp", time = "$context.requestTime",
      status    = "$context.status", latency = "$context.responseLatency", target = "$context.integration.error"
    })
  }
}

resource "aws_lambda_permission" "apigw" {
  statement_id  = "AllowInvokeFromHttpApi"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.proxy.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.proxy.execution_arn}/*/*"
}
