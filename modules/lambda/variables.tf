# Lambda Module Variables

variable "project_name" {
  description = "Name of the project"
  type        = string
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default     = {}
}

# Python Lambda configuration
variable "enable_python_lambda" {
  description = "Enable Python Lambda functions"
  type        = bool
  default     = true
}

variable "python_lambda_handler" {
  description = "Python Lambda handler path"
  type        = string
  default     = "handler.lambda_handler"
}

variable "python_lambda_runtime" {
  description = "Python Lambda runtime version"
  type        = string
  default     = "python3.12"
}

# Go Lambda configuration
variable "enable_go_lambda" {
  description = "Enable Go Lambda functions"
  type        = bool
  default     = true
}

# GameLift Lambda configuration
variable "enable_gamelift_lambda" {
  description = "Enable GameLift Lambda functions"
  type        = bool
  default     = true
}

# API Gateway configuration
variable "enable_api_gateway" {
  description = "Enable API Gateway integration"
  type        = bool
  default     = true
}

variable "api_gateway_stage_name" {
  description = "API Gateway stage name"
  type        = string
  default     = "v1"
}

variable "api_gateway_enable_cors" {
  description = "Enable CORS for API Gateway"
  type        = bool
  default     = true
}

# Lambda function configuration
variable "lambda_timeout" {
  description = "Lambda function timeout in seconds"
  type        = number
  default     = 30
}

variable "lambda_memory_size" {
  description = "Lambda function memory size in MB"
  type        = number
  default     = 256
}

# VPC configuration (optional)
variable "vpc_config" {
  description = "VPC configuration for Lambda functions"
  type = object({
    vpc_id             = string
    subnet_ids         = list(string)
    security_group_ids = list(string)
  })
  default = null
}

