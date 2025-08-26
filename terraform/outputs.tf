# Outputs for Unreal Engine 5 Compilation Infrastructure

output "instance_id" {
  description = "ID of the EC2 instance"
  value       = aws_instance.ue5_compilation.id
}

output "instance_public_ip" {
  description = "Public IP address of the EC2 instance"
  value       = aws_instance.ue5_compilation.public_ip
}

output "instance_private_ip" {
  description = "Private IP address of the EC2 instance"
  value       = aws_instance.ue5_compilation.private_ip
}

output "instance_public_dns" {
  description = "Public DNS name of the EC2 instance"
  value       = aws_instance.ue5_compilation.public_dns
}

output "instance_availability_zone" {
  description = "Availability zone of the EC2 instance"
  value       = aws_instance.ue5_compilation.availability_zone
}

output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.main.id
}

output "vpc_cidr_block" {
  description = "CIDR block of the VPC"
  value       = aws_vpc.main.cidr_block
}

output "public_subnet_ids" {
  description = "IDs of the public subnets"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "IDs of the private subnets"
  value       = aws_subnet.private[*].id
}

output "security_group_id" {
  description = "ID of the security group"
  value       = aws_security_group.ue5_compilation.id
}

output "iam_role_arn" {
  description = "ARN of the IAM role for the EC2 instance"
  value       = aws_iam_role.ue5_compilation.arn
}

output "data_volume_id" {
  description = "ID of the additional EBS volume for UE5 data"
  value       = aws_ebs_volume.ue5_data.id
}

output "connection_instructions" {
  description = "Instructions for connecting to the instance"
  value = <<-EOT
    ========================================
    Unreal Engine 5 Compilation Instance
    ========================================
    
    Instance Details:
    - Instance ID: ${aws_instance.ue5_compilation.id}
    - Public IP: ${aws_instance.ue5_compilation.public_ip}
    - Public DNS: ${aws_instance.ue5_compilation.public_dns}
    - Instance Type: ${var.instance_type}
    - Availability Zone: ${aws_instance.ue5_compilation.availability_zone}
    
    Connection Instructions:
    1. Connect via RDP using the public IP: ${aws_instance.ue5_compilation.public_ip}
    2. Use your Windows credentials or the key pair if specified
    3. The instance is running Windows Server 2022
    
    Unreal Engine 5 Setup:
    - Installation Path: C:\UnrealEngine\UnrealEngine
    - Log Directory: C:\logs
    - Build Configuration: ${var.unreal_engine_version} (${var.unreal_engine_branch})
    
    Build Components:
    - Editor: ${var.enable_ue5_editor}
    - Server: ${var.enable_ue5_server}
    - Linux: ${var.enable_ue5_linux}
    
    Next Steps:
    1. Wait for the user data script to complete (check C:\logs\ue5-setup.log)
    2. Navigate to C:\UnrealEngine\UnrealEngine
    3. Launch UnrealEditor.exe from Engine\Binaries\Win64\
    4. Or open UE5.sln in Visual Studio
    
    Security Notes:
    - RDP port (3389) is open from: ${join(", ", var.allowed_cidr_blocks)}
    - Consider restricting access to your IP address only
    - Instance has encrypted volumes and secure metadata options
    
    Cost Optimization:
    - Spot Instance: ${var.enable_spot_instance}
    - Remember to terminate the instance when not in use
    
    ========================================
  EOT
}

output "terraform_workspace_info" {
  description = "Information about the Terraform workspace and configuration"
  value = {
    project_name     = var.project_name
    environment      = var.environment
    aws_region       = var.aws_region
    instance_type    = var.instance_type
    root_volume_size = var.root_volume_size
    root_volume_type = var.root_volume_type
    vpc_cidr         = var.vpc_cidr
    unreal_engine_version = var.unreal_engine_version
    unreal_engine_branch  = var.unreal_engine_branch
  }
} 