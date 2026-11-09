# S3 backend settings for environments/dev
# Bucket created 2026-11-05 (versioned, SSE-S3, public access blocked,
# non-current versions expire after 90 days).
bucket       = "ue5-tfstate-326105557351-us-east-1"
key          = "ue5-compilation/dev/terraform.tfstate"
region       = "us-east-1"
encrypt      = true
use_lockfile = true # S3-native locking (Terraform >= 1.10), no DynamoDB table needed
