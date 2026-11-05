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

# Custom AMI Configuration
variable "custom_ami_id" {
  description = "Custom AMI ID to use instead of the default Windows Server AMI (leave empty to use default)"
  type        = string
  default     = "ami-0a382bd9aedeb7bc3"
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
  description = "EC2 instance type. Default is a single-GPU g6.2xlarge (~$1.0/h). Larger GPU types (g5/g6 8xlarge+, p-family) are refused unless allow_expensive_instance_types = true."
  type        = string
  # Previous default was g5.24xlarge (~$8.14/h). Left running for ~6 days in
  # April 2026 it produced a ~$1,160 bill. Keep the default cheap; opt in
  # to bigger types explicitly in terraform.tfvars.
  default = "g6.2xlarge"
}

variable "allow_expensive_instance_types" {
  description = "Must be set to true to launch multi-GPU / very large instance types (g5.24xlarge, g6.48xlarge, p4d, ...)."
  type        = bool
  default     = false
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
  default     = ["0.0.0.0/0"] # WARNING: This should be restricted in production
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

variable "admin_password" {
  description = "Windows Administrator password (leave empty for auto-generation)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "admin_password_ssm_parameter_name" {
  description = "SSM SecureString parameter name for Windows Administrator password (takes precedence when set)"
  type        = string
  default     = ""
}

# Snapshot Configuration
#
# The UE 5.6 build environment (VS2022 + UE 5.6 compiled from GitHub source +
# NVIDIA drivers + installers) is preserved as an EBS snapshot in the ARCHIVE
# tier (~$5/month instead of ~$61/month for volume + standard snapshot).
#
#   snap-0777feef308067690  500 GB  "Unreal Engine 5.6 Data Volume - final pre-archive snapshot 261104"
#
# Before `terraform apply` the snapshot must be restored to the standard tier
# (24-72 h). Use:  ./infrastructure/scripts/snapshot/manage_snapshot.sh restore --wait
# The compute module refuses to create resources while the snapshot is archived.
variable "root_volume_snapshot_id" {
  description = "Snapshot ID for an ADDITIONAL volume attached as /dev/sdg (leave empty to skip). Note: the custom AMI already boots from snap-031ad7508b5e1486d, so this duplicates the OS disk."
  type        = string
  default     = "snap-031ad7508b5e1486d"
}

variable "data_volume_snapshot_id" {
  description = "Snapshot ID for the data volume (UE 5.6 source build). Leave empty to create a blank volume."
  type        = string
  # snap-0c3ad11c9c6b31d3d (Oct 2025) was deleted on 2026-11-04; this is its
  # byte-identical successor, stored in the archive tier.
  default = "snap-0777feef308067690"
}

variable "data_volume_snapshot_fsr" {
  description = "Enable Fast Snapshot Restore for the data volume. WARNING: ~$0.75/h per AZ (~$540/month) while enabled."
  type        = bool
  default     = false
}