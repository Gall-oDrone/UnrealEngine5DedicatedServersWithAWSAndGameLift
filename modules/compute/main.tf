# Compute Module for Unreal Engine 5 Infrastructure
# This module creates EC2 instances and related compute resources

# Data sources - THESE WERE MISSING
data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

# Random password for Windows Administrator
resource "random_password" "windows_admin" {
  count   = var.admin_password == "" ? 1 : 0
  length  = 16
  special = true
  upper   = true
  lower   = true
  numeric = true
}

# Data source for Windows AMI (only used if custom_ami_id is not provided)
data "aws_ami" "windows_server" {
  count       = var.custom_ami_id == "" ? 1 : 0
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["Windows_Server-2022-English-Full-Base-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Snapshot metadata for the restore sources. Verified BEFORE any billable
# resource is created: an archived snapshot cannot be used to create a volume
# until restored with `aws ec2 restore-snapshot-tier`
# (see scripts/snapshot/manage_snapshot.sh).
data "aws_ebs_snapshot" "data_volume" {
  count        = var.data_volume_snapshot_id != "" ? 1 : 0
  snapshot_ids = [var.data_volume_snapshot_id]
  owners       = ["self"]
}

data "aws_ebs_snapshot" "root_volume" {
  count        = var.root_volume_snapshot_id != "" ? 1 : 0
  snapshot_ids = [var.root_volume_snapshot_id]
  owners       = ["self"]
}

# Local value to determine which AMI to use
locals {
  ami_id = var.custom_ami_id != "" ? var.custom_ami_id : data.aws_ami.windows_server[0].id

  data_snapshot_ready = (
    var.data_volume_snapshot_id == "" ||
    (data.aws_ebs_snapshot.data_volume[0].storage_tier == "standard" && data.aws_ebs_snapshot.data_volume[0].state == "completed")
  )
  root_snapshot_ready = (
    var.root_volume_snapshot_id == "" ||
    (data.aws_ebs_snapshot.root_volume[0].storage_tier == "standard" && data.aws_ebs_snapshot.root_volume[0].state == "completed")
  )
  data_snapshot_tier = var.data_volume_snapshot_id != "" ? data.aws_ebs_snapshot.data_volume[0].storage_tier : "n/a"
  data_snapshot_size = var.data_volume_snapshot_id != "" ? data.aws_ebs_snapshot.data_volume[0].volume_size : 0

  # Cost guard: multi-GPU / very large types are refused unless
  # allow_expensive_instance_types = true (a forgotten g5.24xlarge cost ~$1,160).
  expensive_instance_type = can(regex(
    "^(g[456](d|dn|e)?\\.(8|12|16|24|48)xlarge|g[456](d|dn|e)?\\.metal.*|p[2-5](d|e|en)?\\..*|inf2\\.(24|48)xlarge|trn1n?\\..*|[a-z0-9]+\\.(32|48|56|96|112|176|192)xlarge|[a-z0-9]+\\.metal.*)$",
    var.instance_type
  ))
  instance_type_allowed = !local.expensive_instance_type || var.allow_expensive_instance_types

  snapshot_restore_hint = <<-EOT
    Data volume snapshot '${var.data_volume_snapshot_id}' is not usable yet (tier='${local.data_snapshot_tier}').
    Archived snapshots must be restored to the standard tier first (24-72 h):
      ./scripts/snapshot/manage_snapshot.sh restore --days 7 --wait
  EOT

  instance_type_hint = <<-EOT
    Instance type '${var.instance_type}' is classified as EXPENSIVE (multi-GPU / very large).
    Set `allow_expensive_instance_types = true` in terraform.tfvars if you really need it,
    and run scripts/cleanup/cleanup.sh when you are done.
  EOT
}

# Security Group for EC2 instances
resource "aws_security_group" "ec2" {
  name_prefix = "${var.project_name}-ec2-sg"
  vpc_id      = var.vpc_id

  # RDP access
  ingress {
    from_port   = 3389
    to_port     = 3389
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
    description = "RDP access"
  }

  # WinRM access
  ingress {
    from_port   = 5985
    to_port     = 5986
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
    description = "WinRM access"
  }

  # HTTP/HTTPS for Unreal Engine services
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
    description = "HTTP access"
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
    description = "HTTPS access"
  }

  # DCV access
  ingress {
    from_port   = var.dcv_port
    to_port     = var.dcv_port
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
    description = "NICE DCV access"
  }

  # All outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-ec2-sg"
  })
}

# IAM Role for EC2 instances
resource "aws_iam_role" "ec2_role" {
  name = "${var.project_name}-ec2-role-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = var.common_tags

  # Ensure proper cleanup order
  lifecycle {
    create_before_destroy = false
  }
}

# IAM Instance Profile
resource "aws_iam_instance_profile" "ec2_profile" {
  name = "${var.project_name}-ec2-profile-${var.environment}"
  role = aws_iam_role.ec2_role.name

  depends_on = [
    aws_iam_role_policy.cloudwatch_policy,
    aws_iam_role_policy.ssm_policy,
    aws_iam_role_policy_attachment.ssm_managed_instance_core
  ]

  # Ensure proper cleanup order
  lifecycle {
    create_before_destroy = false
  }
}

# IAM Policy for CloudWatch Logs
resource "aws_iam_role_policy" "cloudwatch_policy" {
  name = "${var.project_name}-cloudwatch-policy"
  role = aws_iam_role.ec2_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams"
        ]
        Resource = [
          "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/ec2/${var.project_name}-${var.environment}*"
        ]
      }
    ]
  })
}

# IAM Policy for S3 access (optional)
resource "aws_iam_role_policy" "s3_policy" {
  count = var.enable_s3_access ? 1 : 0
  name  = "${var.project_name}-s3-policy"
  role  = aws_iam_role.ec2_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::${var.s3_bucket_name}",
          "arn:aws:s3:::${var.s3_bucket_name}/*"
        ]
      }
    ]
  })
}

# Add after line 124 (the CloudWatch policy)
resource "aws_iam_role_policy" "ssm_policy" {
  name = "${var.project_name}-ssm-policy"
  role = aws_iam_role.ec2_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          # Core SSM permissions
          "ssm:UpdateInstanceInformation",
          "ssm:ListAssociations",
          "ssm:ListInstanceAssociations",
          "ssm:DescribeInstanceInformation",
          "ssm:DescribeDocumentParameters",
          "ssm:DescribeDocument",
          "ssm:GetDocument",
          "ssm:ListDocuments",

          # SSM Messages for Session Manager
          "ssmmessages:CreateControlChannel",
          "ssmmessages:CreateDataChannel",
          "ssmmessages:OpenControlChannel",
          "ssmmessages:OpenDataChannel",
          "ec2messages:*"
        ]
        Resource = "*"
      }
    ]
  })
}

# Also attach the AWS managed policy
resource "aws_iam_role_policy_attachment" "ssm_managed_instance_core" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Spot Instance Request (if spot is enabled)
resource "aws_spot_instance_request" "ue5_server_spot" {
  count = var.enable_spot_instance ? 1 : 0

  ami                    = local.ami_id
  instance_type          = var.instance_type
  subnet_id              = var.subnet_id
  vpc_security_group_ids = [aws_security_group.ec2.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2_profile.name
  key_name               = var.key_pair_name

  spot_price = var.spot_max_price
  spot_type  = "one-time"

  root_block_device {
    volume_type = "gp3"
    volume_size = var.root_volume_size
    encrypted   = true
  }

  user_data = templatefile("${path.module}/templates/minimal-setup.ps1", {
    admin_password = var.admin_password != "" ? var.admin_password : random_password.windows_admin[0].result
  })

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-ue5-server-spot"
  })

  lifecycle {
    precondition {
      condition     = local.instance_type_allowed
      error_message = local.instance_type_hint
    }
    precondition {
      condition     = local.data_snapshot_ready
      error_message = local.snapshot_restore_hint
    }
  }
}

# Regular On-Demand Instance (if spot is not enabled)
resource "aws_instance" "ue5_server" {
  count = var.enable_spot_instance ? 0 : 1

  ami                    = local.ami_id
  instance_type          = var.instance_type
  subnet_id              = var.subnet_id
  vpc_security_group_ids = [aws_security_group.ec2.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2_profile.name
  key_name               = var.key_pair_name

  root_block_device {
    volume_type = "gp3"
    volume_size = var.root_volume_size
    encrypted   = true
  }

  user_data = templatefile("${path.module}/templates/minimal-setup.ps1", {
    admin_password = var.admin_password != "" ? var.admin_password : random_password.windows_admin[0].result
  })

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-ue5-server"
  })

  depends_on = [aws_iam_role_policy.cloudwatch_policy]

  lifecycle {
    precondition {
      condition     = local.instance_type_allowed
      error_message = local.instance_type_hint
    }
    precondition {
      condition     = local.data_snapshot_ready
      error_message = local.snapshot_restore_hint
    }
  }
}

# EBS Volume for root (if using snapshot)
resource "aws_ebs_volume" "root_volume" {
  count = var.root_volume_snapshot_id != "" ? 1 : 0

  availability_zone = var.availability_zone
  type              = "gp3"
  size              = var.root_volume_size
  encrypted         = true
  snapshot_id       = var.root_volume_snapshot_id

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-root-volume"
  })

  lifecycle {
    precondition {
      condition     = local.root_snapshot_ready
      error_message = "Root volume snapshot '${var.root_volume_snapshot_id}' is not in the standard tier / completed state. Restore it before applying."
    }
  }
}

# EBS Volume for data (a restore of the archived UE 5.6 snapshot when
# data_volume_snapshot_id is set).
resource "aws_ebs_volume" "data_volume" {
  availability_zone = var.availability_zone
  type              = "gp3"
  size              = var.data_volume_size
  encrypted         = true
  snapshot_id       = var.data_volume_snapshot_id != "" ? var.data_volume_snapshot_id : null

  tags = merge(var.common_tags, {
    Name                   = "${var.project_name}-data-volume"
    SourceSnapshot         = var.data_volume_snapshot_id != "" ? var.data_volume_snapshot_id : "none"
    RestorableFromSnapshot = var.data_volume_snapshot_id != "" ? "true" : "false"
  })

  lifecycle {
    precondition {
      condition     = local.data_snapshot_ready
      error_message = local.snapshot_restore_hint
    }
    precondition {
      condition     = var.data_volume_size >= local.data_snapshot_size
      error_message = "data_volume_size (${var.data_volume_size} GB) must be >= the snapshot size (${local.data_snapshot_size} GB)."
    }
  }
}

# Fast Snapshot Restore for data volume (if enabled)
# WARNING: ~$0.75 per AZ-hour (~$540/month) while enabled.
resource "aws_ebs_fast_snapshot_restore" "data_volume_fsr" {
  count = var.data_volume_snapshot_fsr && var.data_volume_snapshot_id != "" ? 1 : 0

  availability_zone = var.availability_zone
  snapshot_id       = var.data_volume_snapshot_id

  lifecycle {
    precondition {
      condition     = local.data_snapshot_ready
      error_message = local.snapshot_restore_hint
    }
  }
}

# EBS Volume Attachment for on-demand instance
resource "aws_volume_attachment" "data_volume_attachment" {
  count       = var.enable_spot_instance ? 0 : 1
  device_name = "/dev/sdf"
  volume_id   = aws_ebs_volume.data_volume.id
  instance_id = aws_instance.ue5_server[0].id
}

# EBS Volume Attachment for spot instance
resource "aws_volume_attachment" "data_volume_attachment_spot" {
  count       = var.enable_spot_instance ? 1 : 0
  device_name = "/dev/sdf"
  volume_id   = aws_ebs_volume.data_volume.id
  instance_id = aws_spot_instance_request.ue5_server_spot[0].spot_instance_id
}

# Additional Root Volume Attachment for on-demand instance (if using snapshot)
resource "aws_volume_attachment" "additional_root_volume_attachment" {
  count       = var.enable_spot_instance ? 0 : (var.root_volume_snapshot_id != "" ? 1 : 0)
  device_name = "/dev/sdg"
  volume_id   = aws_ebs_volume.root_volume[0].id
  instance_id = aws_instance.ue5_server[0].id
}

# Additional Root Volume Attachment for spot instance (if using snapshot)
resource "aws_volume_attachment" "additional_root_volume_attachment_spot" {
  count       = var.enable_spot_instance ? (var.root_volume_snapshot_id != "" ? 1 : 0) : 0
  device_name = "/dev/sdg"
  volume_id   = aws_ebs_volume.root_volume[0].id
  instance_id = aws_spot_instance_request.ue5_server_spot[0].spot_instance_id
}