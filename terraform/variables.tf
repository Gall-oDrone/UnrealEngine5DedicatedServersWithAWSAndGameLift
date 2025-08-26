# Global Configuration
variable "project_name" {
  description = "Name of the project"
  type        = string
  default     = "unreal-engine-5-compilation"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "aws_region" {
  description = "AWS region for deployment"
  type        = string
  default     = "us-east-1"
}

# VPC Configuration
variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "enable_nat_gateway" {
  description = "Enable NAT Gateway for private subnets"
  type        = bool
  default     = true
}

# EC2 Instance Configuration
variable "instance_type" {
  description = "EC2 instance type for Unreal Engine 5 compilation"
  type        = string
  default     = "c5.2xlarge" # 8 vCPUs, 16 GB RAM - minimum recommended
  validation {
    condition     = can(regex("^[a-z0-9]+\\.[a-z0-9]+$", var.instance_type))
    error_message = "Instance type must be in format: type.size (e.g., c5.2xlarge)."
  }
}

variable "instance_name" {
  description = "Name tag for the EC2 instance"
  type        = string
  default     = "ue5-compilation-server"
}

variable "root_volume_size" {
  description = "Size of the root volume in GB"
  type        = number
  default     = 100
  validation {
    condition     = var.root_volume_size >= 50
    error_message = "Root volume size must be at least 50 GB for Unreal Engine compilation."
  }
}

variable "root_volume_type" {
  description = "Type of the root volume"
  type        = string
  default     = "gp3"
  validation {
    condition     = contains(["gp2", "gp3", "io1", "io2"], var.root_volume_type)
    error_message = "Volume type must be one of: gp2, gp3, io1, io2."
  }
}

variable "enable_spot_instance" {
  description = "Use spot instance for cost optimization"
  type        = bool
  default     = false
}

# Security Configuration
variable "allowed_cidr_blocks" {
  description = "List of CIDR blocks allowed to access the instance"
  type        = list(string)
  default     = ["0.0.0.0/0"] # Warning: This allows access from anywhere
}

variable "key_pair_name" {
  description = "Name of the EC2 key pair for SSH access"
  type        = string
  default     = ""
}

# Unreal Engine Configuration
variable "unreal_engine_version" {
  description = "Unreal Engine version to compile"
  type        = string
  default     = "5.4"
  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+$", var.unreal_engine_version))
    error_message = "Unreal Engine version must be in format: major.minor (e.g., 5.4)."
  }
}

variable "unreal_engine_branch" {
  description = "Git branch or tag for Unreal Engine repository"
  type        = string
  default     = "5.4"
}

variable "enable_ue5_editor" {
  description = "Build Unreal Engine 5 editor"
  type        = bool
  default     = true
}

variable "enable_ue5_server" {
  description = "Build Unreal Engine 5 server binaries"
  type        = bool
  default     = true
}

variable "enable_ue5_linux" {
  description = "Build Unreal Engine 5 Linux binaries"
  type        = bool
  default     = false
}

# Build Configuration
variable "parallel_build_jobs" {
  description = "Number of parallel build jobs"
  type        = number
  default     = 0 # 0 means use all available cores
  validation {
    condition     = var.parallel_build_jobs >= 0
    error_message = "Parallel build jobs must be 0 or positive."
  }
}

variable "build_timeout_hours" {
  description = "Timeout for build process in hours"
  type        = number
  default     = 8
  validation {
    condition     = var.build_timeout_hours >= 1
    error_message = "Build timeout must be at least 1 hour."
  }
}

# Tags
variable "additional_tags" {
  description = "Additional tags to apply to resources"
  type        = map(string)
  default     = {}
} 