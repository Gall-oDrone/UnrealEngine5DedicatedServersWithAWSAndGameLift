# Lambda Module for AWS Lambda Functions and API Gateway

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }
}

# Data sources
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Local values
locals {
  lambda_name_prefix = "${var.project_name}-${var.environment}"
}

# IAM Role for Lambda Execution
resource "aws_iam_role" "lambda_execution_role" {
  name = "${local.lambda_name_prefix}-lambda-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(var.common_tags, {
    Name = "${local.lambda_name_prefix}-lambda-execution-role"
  })
}

# IAM Policy for basic Lambda execution
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# IAM Policy for VPC access (if VPC is configured)
resource "aws_iam_role_policy_attachment" "lambda_vpc_execution" {
  count      = var.vpc_config != null ? 1 : 0
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

# Additional IAM policy for custom permissions
resource "aws_iam_role_policy" "lambda_custom_policy" {
  name = "${local.lambda_name_prefix}-lambda-custom-policy"
  role = aws_iam_role.lambda_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${local.lambda_name_prefix}-*"
      },
      {
        Effect = "Allow"
        Action = [
          "gamelift:ListFleets",
          "gamelift:DescribeFleetAttributes",
          "gamelift:DescribeFleetCapacity",
          "gamelift:DescribeFleetPortSettings",
          "gamelift:DescribeFleetUtilization",
          "gamelift:DescribeGameSessions",
          "gamelift:DescribeRuntimeConfiguration"
        ]
        Resource = "*"
      }
    ]
  })
}

# Build Python Lambda package
resource "null_resource" "build_python_lambda" {
  count = var.enable_python_lambda ? 1 : 0

  triggers = {
    handler_hash = filemd5("${path.module}/python/src/handler.py")
  }

  provisioner "local-exec" {
    command = "${path.module}/scripts/build_python.sh ${path.module}"
  }
}

# Archive Python Lambda
data "archive_file" "python_lambda" {
  count       = var.enable_python_lambda ? 1 : 0
  type        = "zip"
  source_dir  = "${path.module}/python/build"
  output_path = "${path.module}/python_lambda.zip"
  depends_on  = [null_resource.build_python_lambda]
}

# Python Lambda function
resource "aws_lambda_function" "python_lambda" {
  count            = var.enable_python_lambda ? 1 : 0
  filename         = data.archive_file.python_lambda[0].output_path
  function_name    = "${local.lambda_name_prefix}-python"
  role            = aws_iam_role.lambda_execution_role.arn
  handler         = var.python_lambda_handler
  runtime         = var.python_lambda_runtime
  source_code_hash = data.archive_file.python_lambda[0].output_base64sha256

  timeout     = var.lambda_timeout
  memory_size = var.lambda_memory_size

  dynamic "vpc_config" {
    for_each = var.vpc_config != null ? [1] : []
    content {
      subnet_ids         = var.vpc_config.subnet_ids
      security_group_ids = var.vpc_config.security_group_ids
    }
  }

  environment {
    variables = {
      ENVIRONMENT = var.environment
      PROJECT     = var.project_name
    }
  }

  tags = merge(var.common_tags, {
    Name = "${local.lambda_name_prefix}-python-lambda"
  })
}

# Build Go Lambda
resource "null_resource" "build_go_lambda" {
  count = var.enable_go_lambda ? 1 : 0

  triggers = {
    handler_hash = filemd5("${path.module}/go/src/main.go")
  }

  provisioner "local-exec" {
    command = "${path.module}/scripts/build_go.sh ${path.module}"
  }
}

# Archive Go Lambda
data "archive_file" "go_lambda" {
  count       = var.enable_go_lambda ? 1 : 0
  type        = "zip"
  source_file = "${path.module}/go/build/bootstrap"
  output_path = "${path.module}/go_lambda.zip"
  depends_on  = [null_resource.build_go_lambda]
}

# Go Lambda function
resource "aws_lambda_function" "go_lambda" {
  count            = var.enable_go_lambda ? 1 : 0
  filename         = data.archive_file.go_lambda[0].output_path
  function_name    = "${local.lambda_name_prefix}-go"
  role            = aws_iam_role.lambda_execution_role.arn
  handler         = "bootstrap"
  runtime         = "provided.al2023"
  architectures   = ["x86_64"]
  source_code_hash = data.archive_file.go_lambda[0].output_base64sha256

  timeout     = var.lambda_timeout
  memory_size = var.lambda_memory_size

  dynamic "vpc_config" {
    for_each = var.vpc_config != null ? [1] : []
    content {
      subnet_ids         = var.vpc_config.subnet_ids
      security_group_ids = var.vpc_config.security_group_ids
    }
  }

  environment {
    variables = {
      ENVIRONMENT = var.environment
      PROJECT     = var.project_name
    }
  }

  tags = merge(var.common_tags, {
    Name = "${local.lambda_name_prefix}-go-lambda"
  })
}

# Build Python GameLift Lambda package
resource "null_resource" "build_python_gamelift_lambda" {
  count = var.enable_gamelift_lambda && var.enable_python_lambda ? 1 : 0

  triggers = {
    handler_hash = filemd5("${path.module}/python/src/gamelift_handler.py")
  }

  provisioner "local-exec" {
    command = "${path.module}/scripts/build_python_gamelift.sh ${path.module}"
  }
}

# Archive Python GameLift Lambda
data "archive_file" "python_gamelift_lambda" {
  count       = var.enable_gamelift_lambda && var.enable_python_lambda ? 1 : 0
  type        = "zip"
  source_dir  = "${path.module}/python/build_gamelift"
  output_path = "${path.module}/python_gamelift_lambda.zip"
  depends_on  = [null_resource.build_python_gamelift_lambda]
}

# Python GameLift Lambda function
resource "aws_lambda_function" "python_gamelift_lambda" {
  count            = var.enable_gamelift_lambda && var.enable_python_lambda ? 1 : 0
  filename         = data.archive_file.python_gamelift_lambda[0].output_path
  function_name    = "${local.lambda_name_prefix}-python-gamelift"
  role            = aws_iam_role.lambda_execution_role.arn
  handler         = "gamelift_handler.lambda_handler"
  runtime         = var.python_lambda_runtime
  source_code_hash = data.archive_file.python_gamelift_lambda[0].output_base64sha256

  timeout     = var.lambda_timeout
  memory_size = var.lambda_memory_size

  dynamic "vpc_config" {
    for_each = var.vpc_config != null ? [1] : []
    content {
      subnet_ids         = var.vpc_config.subnet_ids
      security_group_ids = var.vpc_config.security_group_ids
    }
  }

  environment {
    variables = {
      ENVIRONMENT = var.environment
      PROJECT     = var.project_name
      AWS_REGION  = var.aws_region
    }
  }

  tags = merge(var.common_tags, {
    Name = "${local.lambda_name_prefix}-python-gamelift-lambda"
  })
}

# Build Go GameLift Lambda
resource "null_resource" "build_go_gamelift_lambda" {
  count = var.enable_gamelift_lambda && var.enable_go_lambda ? 1 : 0

  triggers = {
    handler_hash = filemd5("${path.module}/go_gamelift/src/gamelift_handler.go")
  }

  provisioner "local-exec" {
    command = "${path.module}/scripts/build_go_gamelift.sh ${path.module}"
  }
}

# Archive Go GameLift Lambda
data "archive_file" "go_gamelift_lambda" {
  count       = var.enable_gamelift_lambda && var.enable_go_lambda ? 1 : 0
  type        = "zip"
  source_file = "${path.module}/go_gamelift/build/bootstrap"
  output_path = "${path.module}/go_gamelift_lambda.zip"
  depends_on  = [null_resource.build_go_gamelift_lambda]
}

# Go GameLift Lambda function
resource "aws_lambda_function" "go_gamelift_lambda" {
  count            = var.enable_gamelift_lambda && var.enable_go_lambda ? 1 : 0
  filename         = data.archive_file.go_gamelift_lambda[0].output_path
  function_name    = "${local.lambda_name_prefix}-go-gamelift"
  role            = aws_iam_role.lambda_execution_role.arn
  handler         = "bootstrap"
  runtime         = "provided.al2023"
  architectures   = ["x86_64"]
  source_code_hash = data.archive_file.go_gamelift_lambda[0].output_base64sha256

  timeout     = var.lambda_timeout
  memory_size = var.lambda_memory_size

  dynamic "vpc_config" {
    for_each = var.vpc_config != null ? [1] : []
    content {
      subnet_ids         = var.vpc_config.subnet_ids
      security_group_ids = var.vpc_config.security_group_ids
    }
  }

  environment {
    variables = {
      ENVIRONMENT = var.environment
      PROJECT     = var.project_name
      AWS_REGION  = var.aws_region
    }
  }

  tags = merge(var.common_tags, {
    Name = "${local.lambda_name_prefix}-go-gamelift-lambda"
  })
}

# API Gateway Rest API
resource "aws_api_gateway_rest_api" "api" {
  count       = var.enable_api_gateway ? 1 : 0
  name        = "${local.lambda_name_prefix}-api"
  description = "API Gateway for ${var.project_name} in ${var.environment}"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = merge(var.common_tags, {
    Name = "${local.lambda_name_prefix}-api"
  })
}

# API Gateway Deployment
resource "aws_api_gateway_deployment" "api_deployment" {
  count       = var.enable_api_gateway ? 1 : 0
  rest_api_id = aws_api_gateway_rest_api.api[0].id

  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_rest_api.api[0].body
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [
    aws_api_gateway_method.python_method,
    aws_api_gateway_method.go_method,
    aws_api_gateway_method.python_gamelift_method,
    aws_api_gateway_method.go_gamelift_method
  ]
}

# API Gateway Stage
resource "aws_api_gateway_stage" "api_stage" {
  count       = var.enable_api_gateway ? 1 : 0
  deployment_id = aws_api_gateway_deployment.api_deployment[0].id
  rest_api_id   = aws_api_gateway_rest_api.api[0].id
  stage_name    = var.api_gateway_stage_name

  tags = merge(var.common_tags, {
    Name = "${local.lambda_name_prefix}-api-stage"
  })
}

# OPTIONS method for CORS (if enabled)
resource "aws_api_gateway_method" "options" {
  count        = var.enable_api_gateway && var.api_gateway_enable_cors ? 1 : 0
  rest_api_id  = aws_api_gateway_rest_api.api[0].id
  resource_id  = aws_api_gateway_rest_api.api[0].root_resource_id
  http_method  = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "options" {
  count        = var.enable_api_gateway && var.api_gateway_enable_cors ? 1 : 0
  rest_api_id  = aws_api_gateway_rest_api.api[0].id
  resource_id  = aws_api_gateway_rest_api.api[0].root_resource_id
  http_method  = aws_api_gateway_method.options[0].http_method
  type         = "MOCK"
  request_templates = {
    "application/json" = jsonencode({
      statusCode = 200
    })
  }
}

resource "aws_api_gateway_method_response" "options" {
  count        = var.enable_api_gateway && var.api_gateway_enable_cors ? 1 : 0
  rest_api_id  = aws_api_gateway_rest_api.api[0].id
  resource_id  = aws_api_gateway_rest_api.api[0].root_resource_id
  http_method  = aws_api_gateway_method.options[0].http_method
  status_code  = "200"
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

resource "aws_api_gateway_integration_response" "options" {
  count        = var.enable_api_gateway && var.api_gateway_enable_cors ? 1 : 0
  rest_api_id  = aws_api_gateway_rest_api.api[0].id
  resource_id  = aws_api_gateway_rest_api.api[0].root_resource_id
  http_method  = aws_api_gateway_method.options[0].http_method
  status_code  = aws_api_gateway_method_response.options[0].status_code
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'"
    "method.response.header.Access-Control-Allow-Methods" = "'GET,POST,PUT,DELETE,OPTIONS'"
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }
}

# Python Lambda endpoint
resource "aws_api_gateway_method" "python_method" {
  count         = var.enable_api_gateway && var.enable_python_lambda ? 1 : 0
  rest_api_id   = aws_api_gateway_rest_api.api[0].id
  resource_id   = aws_api_gateway_rest_api.api[0].root_resource_id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "python_integration" {
  count                   = var.enable_api_gateway && var.enable_python_lambda ? 1 : 0
  rest_api_id             = aws_api_gateway_rest_api.api[0].id
  resource_id             = aws_api_gateway_rest_api.api[0].root_resource_id
  http_method             = aws_api_gateway_method.python_method[0].http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.python_lambda[0].invoke_arn
}

resource "aws_lambda_permission" "python_lambda_permission" {
  count         = var.enable_api_gateway && var.enable_python_lambda ? 1 : 0
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.python_lambda[0].function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.api[0].execution_arn}/*/*"
}

# Go Lambda endpoint
resource "aws_api_gateway_method" "go_method" {
  count         = var.enable_api_gateway && var.enable_go_lambda ? 1 : 0
  rest_api_id   = aws_api_gateway_rest_api.api[0].id
  resource_id   = aws_api_gateway_rest_api.api[0].root_resource_id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "go_integration" {
  count                   = var.enable_api_gateway && var.enable_go_lambda ? 1 : 0
  rest_api_id             = aws_api_gateway_rest_api.api[0].id
  resource_id             = aws_api_gateway_rest_api.api[0].root_resource_id
  http_method             = aws_api_gateway_method.go_method[0].http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.go_lambda[0].invoke_arn
}

resource "aws_lambda_permission" "go_lambda_permission" {
  count         = var.enable_api_gateway && var.enable_go_lambda ? 1 : 0
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.go_lambda[0].function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.api[0].execution_arn}/*/*"
}

# GameLift API Resource
resource "aws_api_gateway_resource" "gamelift" {
  count       = var.enable_api_gateway && var.enable_gamelift_lambda ? 1 : 0
  rest_api_id = aws_api_gateway_rest_api.api[0].id
  parent_id   = aws_api_gateway_rest_api.api[0].root_resource_id
  path_part   = "gamelift"
}

# Python GameLift Lambda endpoint
resource "aws_api_gateway_method" "python_gamelift_method" {
  count         = var.enable_api_gateway && var.enable_gamelift_lambda && var.enable_python_lambda ? 1 : 0
  rest_api_id   = aws_api_gateway_rest_api.api[0].id
  resource_id   = aws_api_gateway_resource.gamelift[0].id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "python_gamelift_integration" {
  count                   = var.enable_api_gateway && var.enable_gamelift_lambda && var.enable_python_lambda ? 1 : 0
  rest_api_id             = aws_api_gateway_rest_api.api[0].id
  resource_id             = aws_api_gateway_resource.gamelift[0].id
  http_method             = aws_api_gateway_method.python_gamelift_method[0].http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.python_gamelift_lambda[0].invoke_arn
}

resource "aws_lambda_permission" "python_gamelift_lambda_permission" {
  count         = var.enable_api_gateway && var.enable_gamelift_lambda && var.enable_python_lambda ? 1 : 0
  statement_id  = "AllowAPIGatewayInvokeGameLift"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.python_gamelift_lambda[0].function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.api[0].execution_arn}/*/*"
}

# Go GameLift Lambda endpoint (POST to same resource)
resource "aws_api_gateway_method" "go_gamelift_method" {
  count         = var.enable_api_gateway && var.enable_gamelift_lambda && var.enable_go_lambda ? 1 : 0
  rest_api_id   = aws_api_gateway_rest_api.api[0].id
  resource_id   = aws_api_gateway_resource.gamelift[0].id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "go_gamelift_integration" {
  count                   = var.enable_api_gateway && var.enable_gamelift_lambda && var.enable_go_lambda ? 1 : 0
  rest_api_id             = aws_api_gateway_rest_api.api[0].id
  resource_id             = aws_api_gateway_resource.gamelift[0].id
  http_method             = aws_api_gateway_method.go_gamelift_method[0].http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.go_gamelift_lambda[0].invoke_arn
}

resource "aws_lambda_permission" "go_gamelift_lambda_permission" {
  count         = var.enable_api_gateway && var.enable_gamelift_lambda && var.enable_go_lambda ? 1 : 0
  statement_id  = "AllowAPIGatewayInvokeGameLift"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.go_gamelift_lambda[0].function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.api[0].execution_arn}/*/*"
}

