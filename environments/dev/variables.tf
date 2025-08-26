# Development Environment Variables

variable "project_name" {
  description = "Name of the project"
  type        = string
  default     = "ue5-compilation-dev"
}

variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-east-1"
}

variable "owner" {
  description = "Owner of the resources"
  type        = string
  default     = "game-dev-team"
}

# Networking variables
variable "vpc_cidr_block" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets"
  type        = list(string)
  default     = ["10.0.0.0/24", "10.0.1.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets"
  type        = list(string)
  default     = ["10.0.10.0/24", "10.0.11.0/24"]
}

variable "enable_nat_gateway" {
  description = "Whether to enable NAT Gateway for private subnets"
  type        = bool
  default     = false
}

# Compute variables
variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "c5.2xlarge"
}

variable "key_pair_name" {
  description = "Name of the EC2 key pair"
  type        = string
  default     = null
}

variable "root_volume_size" {
  description = "Size of the root volume in GB"
  type        = number
  default     = 100
}

variable "data_volume_size" {
  description = "Size of the data volume in GB"
  type        = number
  default     = 500
}

variable "allowed_cidr_blocks" {
  description = "List of CIDR blocks allowed to access the instance"
  type        = list(string)
  default     = ["0.0.0.0/0"]  # WARNING: This should be restricted in production
}

# Unreal Engine variables
variable "unreal_engine_version" {
  description = "Unreal Engine version to install"
  type        = string
  default     = "5.4"
}

variable "unreal_engine_branch" {
  description = "Unreal Engine branch to use"
  type        = string
  default     = "5.4"
}

# Storage variables
variable "enable_s3_access" {
  description = "Whether to enable S3 access for the instance"
  type        = bool
  default     = false
}

variable "s3_bucket_name" {
  description = "Name of the S3 bucket for build artifacts"
  type        = string
  default     = ""
}

# Security variables
variable "enable_kms" {
  description = "Whether to enable KMS encryption"
  type        = bool
  default     = false
}

variable "enable_vpc_flow_logs" {
  description = "Whether to enable VPC Flow Logs"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "Number of days to retain CloudWatch logs"
  type        = number
  default     = 30
}

# Monitoring variables
variable "enable_memory_monitoring" {
  description = "Whether to enable memory monitoring"
  type        = bool
  default     = false
}

variable "enable_disk_monitoring" {
  description = "Whether to enable disk space monitoring"
  type        = bool
  default     = false
}

variable "enable_sns_notifications" {
  description = "Whether to enable SNS notifications for alarms"
  type        = bool
  default     = false
}

variable "notification_email" {
  description = "Email address for SNS notifications"
  type        = string
  default     = ""
} 