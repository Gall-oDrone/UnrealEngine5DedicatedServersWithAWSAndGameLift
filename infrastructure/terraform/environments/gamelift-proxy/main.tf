# GameLift client-API proxy (API Gateway HTTP API + Lambda) for Shipping builds.
# Long-lived and ~free while idle; kept in its own state so the build box's
# create/destroy cycle (environments/dev) never touches it.
#
#   terraform init -backend-config=backend.hcl
#   terraform apply -var fleet_id=fleet-xxxxxxxx-...        # or -var alias_id=alias-...
#   terraform output -raw api_endpoint_url                  # -> ApiEndpointUrl in the game

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
  backend "s3" {}
}

provider "aws" {
  region = var.aws_region
  default_tags {
    tags = {
      Project     = "FrontendUI"
      Environment = "shared"
      ManagedBy   = "Terraform"
      Purpose     = "GameLiftClientProxy"
    }
  }
}

module "proxy" {
  source                          = "../../modules/gamelift-proxy"
  fleet_id                        = var.fleet_id
  alias_id                        = var.alias_id
  auth_mode                       = var.auth_mode
  eos_client_id                   = var.eos_client_id
  eos_client_secret_ssm_parameter = var.eos_client_secret_ssm_parameter
  queue_name                      = var.queue_name
}

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "fleet_id" {
  description = "GameLift fleet pinned by the proxy (fleet-... or containerfleet-...). Empty lets the client choose."
  type        = string
  default     = ""
}

variable "alias_id" {
  type    = string
  default = ""
}

variable "auth_mode" {
  description = "\"none\" or \"eos\" (see modules/gamelift-proxy)."
  type        = string
  default     = "none"
}

variable "eos_client_id" {
  type    = string
  default = ""
}

variable "eos_client_secret_ssm_parameter" {
  type    = string
  default = ""
}

variable "queue_name" {
  type    = string
  default = ""
}

output "api_endpoint_url" {
  value = module.proxy.api_endpoint_url
}

output "lambda_log_group" {
  value = module.proxy.lambda_log_group
}

output "proxy_function_name" {
  value = module.proxy.lambda_function_name
}

output "proxy_api_id" {
  value = module.proxy.proxy_api_id
}
