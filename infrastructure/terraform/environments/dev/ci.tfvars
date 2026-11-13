# Values the CI workflow (.github/workflows/server-image.yml) applies environments/dev with.
# Same shape as terraform.tfvars.example; nothing secret in here. SSM only - no RDP/DCV, no
# key pair, no public CIDR - and no SNS (alerts for the box are the workflow run itself).
project_name = "ue5-compilation-dev"
aws_region   = "us-east-1"
owner        = "github-actions"

vpc_cidr_block       = "10.0.0.0/16"
public_subnet_cidrs  = ["10.0.0.0/24", "10.0.1.0/24"]
private_subnet_cidrs = ["10.0.10.0/24", "10.0.11.0/24"]
enable_nat_gateway   = false

instance_type                  = "c6i.4xlarge"
allow_expensive_instance_types = false
key_pair_name                  = null
root_volume_size               = 100
data_volume_size               = 500
custom_ami_id                  = "ami-0a382bd9aedeb7bc3"
allowed_cidr_blocks            = ["10.0.0.0/16"]

unreal_engine_version = "5.6"
unreal_engine_branch  = "5.6"

admin_password_ssm_parameter_name = ""
admin_password                    = ""

enable_s3_access = true
s3_bucket_name   = "ue5-artifacts-326105557351-us-east-1"

enable_kms           = false
enable_vpc_flow_logs = true
log_retention_days   = 30

enable_memory_monitoring = false
enable_disk_monitoring   = false
enable_sns_notifications = false
notification_email       = ""

root_volume_snapshot_id  = ""
data_volume_snapshot_id  = "snap-0777feef308067690"
data_volume_snapshot_fsr = false
