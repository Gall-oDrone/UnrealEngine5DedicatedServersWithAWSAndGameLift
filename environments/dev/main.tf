# Development Environment Configuration
# This file orchestrates the deployment of the Unreal Engine 5 infrastructure for development

terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
  
  default_tags {
    tags = {
      Project     = var.project_name
      Environment = "dev"
      ManagedBy   = "Terraform"
      Purpose     = "UnrealEngine5Compilation"
    }
  }
}

# Data sources
data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Local values
locals {
  common_tags = {
    Project     = var.project_name
    Environment = "dev"
    ManagedBy   = "Terraform"
    Purpose     = "UnrealEngine5Compilation"
    Owner       = var.owner
  }
}

# Networking module
module "networking" {
  source = "../../modules/networking"

  project_name         = var.project_name
  environment          = "dev"
  vpc_cidr_block       = var.vpc_cidr_block
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  availability_zones   = slice(data.aws_availability_zones.available.names, 0, 2)
  enable_nat_gateway   = var.enable_nat_gateway
  common_tags          = local.common_tags
}

# Security module
module "security" {
  source = "../../modules/security"

  project_name        = var.project_name
  environment         = "dev"
  vpc_id              = module.networking.vpc_id
  enable_kms          = var.enable_kms
  enable_vpc_flow_logs = var.enable_vpc_flow_logs
  log_retention_days  = var.log_retention_days
  common_tags         = local.common_tags
}

# Compute module
module "compute" {
  source = "../../modules/compute"

  project_name          = var.project_name
  environment           = "dev"
  vpc_id                = module.networking.vpc_id
  subnet_id             = module.networking.public_subnet_ids[0]
  availability_zone     = data.aws_availability_zones.available.names[0]
  instance_type         = var.instance_type
  key_pair_name         = var.key_pair_name
  root_volume_size      = var.root_volume_size
  data_volume_size      = var.data_volume_size
  allowed_cidr_blocks   = var.allowed_cidr_blocks
  unreal_engine_version = var.unreal_engine_version
  unreal_engine_branch  = var.unreal_engine_branch
  enable_s3_access      = var.enable_s3_access
  s3_bucket_name        = var.s3_bucket_name
  root_volume_snapshot_id = var.root_volume_snapshot_id
  data_volume_snapshot_id = var.data_volume_snapshot_id
  custom_ami_id         = var.custom_ami_id
  common_tags           = local.common_tags
}

# Monitoring module
module "monitoring" {
  source = "../../modules/monitoring"

  project_name              = var.project_name
  environment               = "dev"
  aws_region                = var.aws_region
  instance_id               = module.compute.instance_id
  ebs_volume_id             = module.compute.data_volume_id
  enable_memory_monitoring  = var.enable_memory_monitoring
  enable_disk_monitoring    = var.enable_disk_monitoring
  enable_sns_notifications  = var.enable_sns_notifications
  notification_email        = var.notification_email
  log_retention_days        = var.log_retention_days
  alarm_actions             = var.enable_sns_notifications ? [module.monitoring.sns_topic_arn] : []
  common_tags               = local.common_tags
} 