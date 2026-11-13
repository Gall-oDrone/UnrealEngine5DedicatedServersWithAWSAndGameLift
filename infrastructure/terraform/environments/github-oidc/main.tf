# GitHub Actions -> AWS, without long-lived keys.
#
# One IAM OIDC provider for token.actions.githubusercontent.com and one role that only a
# workflow of this repository can assume (sub = repo:<owner>/<repo>:*). The role can do what
# .github/workflows/server-image.yml needs and not much more: the dev build box lifecycle
# (environments/dev), SSM Run Command on it, the artifact bucket, the server image repository
# and a new container group definition version. Long-lived and free; separate state so the
# build box's create/destroy cycle never touches it.
#
#   terraform init -backend-config=backend.hcl
#   terraform apply
#   terraform output -raw role_arn      # -> AWS_ROLE_ARN in the workflow

terraform {
  required_version = ">= 1.10"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  backend "s3" {}
}

provider "aws" {
  region = var.aws_region
  default_tags {
    tags = {
      Project     = "FrontendUI"
      Environment = "shared"
      ManagedBy   = "Terraform"
      Purpose     = "GitHubActionsCI"
    }
  }
}

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "github_repository" {
  description = "owner/repo whose workflows may assume the role"
  type        = string
  default     = "Gall-oDrone/UnrealEngine5DedicatedServersWithAWSAndGameLift"
}

variable "role_name" {
  type    = string
  default = "frontendui-github-ci"
}

variable "build_project_name" {
  description = "project_name of environments/dev; scopes the IAM/log/alarm resources the role may touch"
  type        = string
  default     = "ue5-compilation-dev"
}

variable "artifacts_bucket" {
  type    = string
  default = "ue5-artifacts-326105557351-us-east-1"
}

variable "tfstate_bucket" {
  type    = string
  default = "ue5-tfstate-326105557351-us-east-1"
}

variable "tfstate_key_prefix" {
  description = "state key of environments/dev (plus its .tflock)"
  type        = string
  default     = "ue5-compilation/dev/"
}

variable "ecr_repository" {
  type    = string
  default = "frontendui-server"
}

variable "allowed_instance_types" {
  description = "RunInstances is denied for anything else - the one guard-rail Terraform variables cannot give a CI role"
  type        = list(string)
  default     = ["c6i.2xlarge", "c6i.4xlarge", "c6i.8xlarge"]
}

data "aws_caller_identity" "current" {}

locals {
  account = data.aws_caller_identity.current.account_id
  region  = var.aws_region
  p       = var.build_project_name
}

# GitHub's provider. AWS validates the token against GitHub's published keys and ignores the
# thumbprint for this issuer, but the argument is still required.
resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1", "1c58a3a8518e8759bf075b76b750d4f2df264fcd"]
}

data "aws_iam_policy_document" "trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_repository}:*"]
    }
  }
}

resource "aws_iam_role" "ci" {
  name                 = var.role_name
  assume_role_policy   = data.aws_iam_policy_document.trust.json
  max_session_duration = 6 * 3600 # a build session is 1-2.5 h; the workflow times out at 5 h
  description          = "GitHub Actions: build the FrontendUI server image on the dev box and publish it"
}

data "aws_iam_policy_document" "ci" {
  # --- Terraform state of environments/dev ---------------------------------------------------
  statement {
    sid       = "TfStateList"
    actions   = ["s3:ListBucket", "s3:GetBucketLocation"]
    resources = ["arn:aws:s3:::${var.tfstate_bucket}"]
  }
  statement {
    sid       = "TfStateObjects"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["arn:aws:s3:::${var.tfstate_bucket}/${var.tfstate_key_prefix}*"]
  }

  # --- The build box and its network (environments/dev creates a VPC, SG, IGW, subnets, route
  #     tables, flow logs, one instance and one volume; EC2 resource-level scoping does not cover
  #     create calls, so the region and the instance-type guard-rail below do the limiting) -----
  statement {
    sid       = "Ec2InRegion"
    actions   = ["ec2:*"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [local.region]
    }
  }
  statement {
    sid       = "DenyOtherInstanceTypes"
    effect    = "Deny"
    actions   = ["ec2:RunInstances"]
    resources = ["arn:aws:ec2:*:*:instance/*"]
    condition {
      test     = "ForAnyValue:StringNotEquals"
      variable = "ec2:InstanceType"
      values   = var.allowed_instance_types
    }
  }

  # --- IAM pieces of the dev environment (instance role/profile, flow-log role) ---------------
  statement {
    sid = "DevEnvIam"
    actions = [
      "iam:CreateRole", "iam:DeleteRole", "iam:GetRole", "iam:UpdateRole", "iam:TagRole", "iam:UntagRole",
      "iam:ListRolePolicies", "iam:ListAttachedRolePolicies", "iam:ListInstanceProfilesForRole",
      "iam:PutRolePolicy", "iam:GetRolePolicy", "iam:DeleteRolePolicy",
      "iam:AttachRolePolicy", "iam:DetachRolePolicy",
      "iam:CreateInstanceProfile", "iam:DeleteInstanceProfile", "iam:GetInstanceProfile", "iam:TagInstanceProfile",
      "iam:AddRoleToInstanceProfile", "iam:RemoveRoleFromInstanceProfile",
    ]
    resources = [
      "arn:aws:iam::${local.account}:role/${local.p}-*",
      "arn:aws:iam::${local.account}:instance-profile/${local.p}-*",
    ]
  }
  statement {
    sid       = "DevEnvPassRole"
    actions   = ["iam:PassRole"]
    resources = ["arn:aws:iam::${local.account}:role/${local.p}-*"]
    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ec2.amazonaws.com", "vpc-flow-logs.amazonaws.com"]
    }
  }

  # --- Logs, dashboard, alarms of the dev environment -----------------------------------------
  statement {
    sid       = "DevEnvLogs"
    actions   = ["logs:*"]
    resources = ["arn:aws:logs:${local.region}:${local.account}:log-group:*${local.p}*"]
  }
  statement {
    sid       = "LogsDescribe"
    actions   = ["logs:DescribeLogGroups"]
    resources = ["*"]
  }
  statement {
    sid = "DevEnvCloudWatch"
    actions = [
      "cloudwatch:PutDashboard", "cloudwatch:GetDashboard", "cloudwatch:DeleteDashboards",
      "cloudwatch:PutMetricAlarm", "cloudwatch:DescribeAlarms", "cloudwatch:DeleteAlarms", "cloudwatch:TagResource", "cloudwatch:ListTagsForResource",
    ]
    resources = [
      "arn:aws:cloudwatch::${local.account}:dashboard/${local.p}-*",
      "arn:aws:cloudwatch:${local.region}:${local.account}:alarm:${local.p}-*",
    ]
  }
  statement {
    sid       = "CloudWatchDescribe"
    actions   = ["cloudwatch:DescribeAlarms", "cloudwatch:ListDashboards"]
    resources = ["*"]
  }
  statement {
    sid       = "SnsForDevEnv" # enable_sns_notifications=false in ci.tfvars; harmless if turned on
    actions   = ["sns:CreateTopic", "sns:DeleteTopic", "sns:GetTopicAttributes", "sns:SetTopicAttributes", "sns:Subscribe", "sns:Unsubscribe", "sns:ListTagsForResource", "sns:TagResource", "sns:ListSubscriptionsByTopic"]
    resources = ["arn:aws:sns:${local.region}:${local.account}:${local.p}-*"]
  }

  # --- Driving the build over SSM Run Command -------------------------------------------------
  statement {
    sid       = "SsmRunCommand"
    actions   = ["ssm:SendCommand"]
    resources = [
      "arn:aws:ssm:${local.region}::document/AWS-RunPowerShellScript",
      "arn:aws:ec2:${local.region}:${local.account}:instance/*",
    ]
  }
  statement {
    sid       = "SsmRead"
    actions   = ["ssm:GetCommandInvocation", "ssm:ListCommandInvocations", "ssm:ListCommands", "ssm:DescribeInstanceInformation", "ssm:CancelCommand"]
    resources = ["*"]
  }

  # --- Artifacts: the .ps1 the box downloads, the zips and logs it uploads --------------------
  statement {
    sid       = "ArtifactsList"
    actions   = ["s3:ListBucket", "s3:GetBucketLocation"]
    resources = ["arn:aws:s3:::${var.artifacts_bucket}"]
  }
  statement {
    sid       = "ArtifactsObjects"
    actions   = ["s3:GetObject", "s3:PutObject"]
    resources = ["arn:aws:s3:::${var.artifacts_bucket}/builds/*", "arn:aws:s3:::${var.artifacts_bucket}/scripts/*"]
  }

  # --- Server image -----------------------------------------------------------------------------
  statement {
    sid       = "EcrLogin"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }
  statement {
    sid = "EcrPush"
    actions = [
      "ecr:BatchCheckLayerAvailability", "ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer", "ecr:DescribeImages", "ecr:DescribeRepositories",
      "ecr:InitiateLayerUpload", "ecr:UploadLayerPart", "ecr:CompleteLayerUpload", "ecr:PutImage",
    ]
    resources = ["arn:aws:ecr:${local.region}:${local.account}:repository/${var.ecr_repository}"]
  }

  # --- GameLift: a new container group definition version, optional roll-out ------------------
  statement {
    sid = "GameLiftPublish"
    actions = [
      "gamelift:DescribeContainerGroupDefinition", "gamelift:ListContainerGroupDefinitionVersions", "gamelift:UpdateContainerGroupDefinition",
      "gamelift:DescribeContainerFleet", "gamelift:UpdateContainerFleet", "gamelift:DescribeFleetDeployment", "gamelift:DescribeFleetEvents",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "ci" {
  name   = "${var.role_name}-policy"
  role   = aws_iam_role.ci.id
  policy = data.aws_iam_policy_document.ci.json
}

output "role_arn" {
  value = aws_iam_role.ci.arn
}

output "oidc_provider_arn" {
  value = aws_iam_openid_connect_provider.github.arn
}
