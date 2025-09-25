variable "project_name" {
  description = "Name of the project"
  type        = string
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
}

variable "vpc_id" {
  description = "ID of the VPC"
  type        = string
}

variable "subnet_id" {
  description = "ID of the subnet where the instance will be launched"
  type        = string
}

variable "availability_zone" {
  description = "Availability zone for the EBS volume"
  type        = string
}

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
}

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

variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "enable_ue5_editor" {
  description = "Whether to enable Unreal Engine 5 Editor compilation"
  type        = bool
  default     = true
}

variable "enable_ue5_server" {
  description = "Whether to enable Unreal Engine 5 Server compilation"
  type        = bool
  default     = true
}

variable "enable_ue5_linux" {
  description = "Whether to enable Unreal Engine 5 Linux compilation"
  type        = bool
  default     = false
}

variable "parallel_build_jobs" {
  description = "Number of parallel build jobs"
  type        = number
  default     = 4
}

variable "build_timeout_hours" {
  description = "Build timeout in hours"
  type        = number
  default     = 24
}

variable "root_volume_type" {
  description = "Type of the root volume"
  type        = string
  default     = "gp3"
}

variable "enable_spot_instance" {
  description = "Whether to use spot instances for cost optimization"
  type        = bool
  default     = false
}

variable "spot_max_price" {
  description = "Maximum price for spot instance (leave empty for on-demand price)"
  type        = string
  default     = ""
}

variable "dcv_port" {
  description = "Port for NICE DCV service"
  type        = number
  default     = 8443
}

variable "admin_password" {
  description = "Windows Administrator password (leave empty for auto-generation)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "root_volume_snapshot_id" {
  description = "Snapshot ID for root volume (leave empty to create new volume)"
  type        = string
  default     = ""
}

variable "data_volume_snapshot_id" {
  description = "Snapshot ID for data volume (leave empty to create new volume)"
  type        = string
  default     = ""
}

variable "custom_ami_id" {
  description = "Custom AMI ID to use instead of the default Windows Server AMI (leave empty to use default)"
  type        = string
  default     = ""
}

variable "data_volume_snapshot_fsr" {
  description = "Enabling Fast Snapshot Restore for data volume (default is false)"
  type        = bool
  default     = false
}