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

# Data source for Windows AMI
data "aws_ami" "windows_server" {
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
}

# IAM Instance Profile
resource "aws_iam_instance_profile" "ec2_profile" {
  name = "${var.project_name}-ec2-profile-${var.environment}"
  role = aws_iam_role.ec2_role.name
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
          "ssm:UpdateInstanceInformation",
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
  
  ami                    = data.aws_ami.windows_server.id
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
}

# Regular On-Demand Instance (if spot is not enabled)
resource "aws_instance" "ue5_server" {
  count = var.enable_spot_instance ? 0 : 1
  
  ami                    = data.aws_ami.windows_server.id
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
}

# EBS Volume for data
resource "aws_ebs_volume" "data_volume" {
  availability_zone = var.availability_zone
  type              = "gp3"
  size              = var.data_volume_size
  encrypted         = true

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-data-volume"
  })
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