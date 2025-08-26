# IAM Role for EC2 instance
resource "aws_iam_role" "ue5_compilation" {
  name = "${var.project_name}-ue5-compilation-role-${var.environment}"

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

  tags = merge(var.additional_tags, {
    Name = "${var.project_name}-ue5-compilation-role-${var.environment}"
  })
}

# IAM Instance Profile
resource "aws_iam_instance_profile" "ue5_compilation" {
  name = "${var.project_name}-ue5-compilation-profile-${var.environment}"
  role = aws_iam_role.ue5_compilation.name
}

# CloudWatch Logs policy for the IAM role
resource "aws_iam_role_policy" "cloudwatch_logs" {
  name = "${var.project_name}-cloudwatch-logs-policy-${var.environment}"
  role = aws_iam_role.ue5_compilation.id

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

# S3 access policy for storing build artifacts (optional)
resource "aws_iam_role_policy" "s3_access" {
  name = "${var.project_name}-s3-access-policy-${var.environment}"
  role = aws_iam_role.ue5_compilation.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::${var.project_name}-build-artifacts-${var.environment}",
          "arn:aws:s3:::${var.project_name}-build-artifacts-${var.environment}/*"
        ]
      }
    ]
  })
}

# EC2 Instance for Unreal Engine 5 Compilation
resource "aws_instance" "ue5_compilation" {
  ami           = data.aws_ami.windows_server.id
  instance_type = var.instance_type
  subnet_id     = aws_subnet.public[0].id

  vpc_security_group_ids = [aws_security_group.ue5_compilation.id]
  key_name               = var.key_pair_name != "" ? var.key_pair_name : null
  iam_instance_profile   = aws_iam_instance_profile.ue5_compilation.name

  root_block_device {
    volume_size = var.root_volume_size
    volume_type = var.root_volume_type
    encrypted   = true

    tags = merge(var.additional_tags, {
      Name = "${var.project_name}-root-volume-${var.environment}"
    })
  }

  # Spot instance configuration (if enabled)
  dynamic "spot_config" {
    for_each = var.enable_spot_instance ? [1] : []
    content {
      spot_price = "0.50" # Adjust based on current spot prices
      type       = "one-time"
    }
  }

  # Instance metadata options for security
  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
    http_put_response_hop_limit = 1
  }

  # User data script for Unreal Engine 5 setup
  user_data = base64encode(templatefile("${path.module}/templates/user_data.ps1", {
    unreal_engine_version = var.unreal_engine_version
    unreal_engine_branch  = var.unreal_engine_branch
    enable_ue5_editor     = var.enable_ue5_editor
    enable_ue5_server     = var.enable_ue5_server
    enable_ue5_linux      = var.enable_ue5_linux
    parallel_build_jobs   = var.parallel_build_jobs
    build_timeout_hours   = var.build_timeout_hours
    project_name          = var.project_name
    environment           = var.environment
  }))

  tags = merge(var.additional_tags, {
    Name = "${var.instance_name}-${var.environment}"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# Additional EBS volume for Unreal Engine source and build files
resource "aws_ebs_volume" "ue5_data" {
  availability_zone = aws_instance.ue5_compilation.availability_zone
  size              = 500 # 500 GB for UE5 source and build files
  type              = "gp3"
  encrypted         = true

  tags = merge(var.additional_tags, {
    Name = "${var.project_name}-ue5-data-volume-${var.environment}"
  })
}

# Attach the data volume to the instance
resource "aws_volume_attachment" "ue5_data" {
  device_name = "/dev/sdf"
  volume_id   = aws_ebs_volume.ue5_data.id
  instance_id = aws_instance.ue5_compilation.id
} 