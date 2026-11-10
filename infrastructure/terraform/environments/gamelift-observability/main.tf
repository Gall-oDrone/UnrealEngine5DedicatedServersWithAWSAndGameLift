# CloudWatch dashboard + alarms for the FrontendUI GameLift stack. Long-lived, ~free.
#
#   terraform init -backend-config=backend.hcl
#   terraform apply -var alert_email=you@example.com      # confirm the SNS e-mail once
#   terraform output -raw dashboard_url

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
      Purpose     = "GameLiftObservability"
    }
  }
}

# Proxy identifiers from the gamelift-proxy stack's remote state.
data "terraform_remote_state" "proxy" {
  backend = "s3"
  config = {
    bucket = "ue5-tfstate-326105557351-us-east-1"
    key    = "ue5-compilation/gamelift-proxy/terraform.tfstate"
    region = "us-east-1"
  }
}

module "observability" {
  source                 = "../../modules/gamelift-observability"
  proxy_function_name    = data.terraform_remote_state.proxy.outputs.proxy_function_name
  proxy_api_id           = data.terraform_remote_state.proxy.outputs.proxy_api_id
  alert_email            = var.alert_email
  ec2_hours_before_alarm = var.ec2_hours_before_alarm
}

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "alert_email" {
  type    = string
  default = ""
}

variable "ec2_hours_before_alarm" {
  type    = number
  default = 6
}

output "dashboard_url" {
  value = module.observability.dashboard_url
}

output "alerts_topic_arn" {
  value = module.observability.alerts_topic_arn
}
