# Development Environment Outputs

output "vpc_id" {
  description = "ID of the VPC"
  value       = module.networking.vpc_id
}

output "public_subnet_ids" {
  description = "IDs of the public subnets"
  value       = module.networking.public_subnet_ids
}

output "private_subnet_ids" {
  description = "IDs of the private subnets"
  value       = module.networking.private_subnet_ids
}

output "instance_id" {
  description = "ID of the EC2 instance"
  value       = module.compute.instance_id
}

output "instance_public_ip" {
  description = "Public IP address of the EC2 instance"
  value       = module.compute.instance_public_ip
}

output "instance_private_ip" {
  description = "Private IP address of the EC2 instance"
  value       = module.compute.instance_private_ip
}

output "security_group_id" {
  description = "ID of the security group"
  value       = module.compute.security_group_id
}

output "data_volume_id" {
  description = "ID of the data EBS volume"
  value       = module.compute.data_volume_id
}

output "dashboard_name" {
  description = "Name of the CloudWatch dashboard"
  value       = module.monitoring.dashboard_name
}

output "dashboard_url" {
  description = "URL of the CloudWatch dashboard"
  value       = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${module.monitoring.dashboard_name}"
}

output "kms_key_arn" {
  description = "ARN of the KMS key (if enabled)"
  value       = module.security.kms_key_arn
}

output "vpc_flow_log_id" {
  description = "ID of the VPC Flow Log (if enabled)"
  value       = module.security.vpc_flow_log_id
}

output "sns_topic_arn" {
  description = "ARN of the SNS topic for alarms (if enabled)"
  value       = module.monitoring.sns_topic_arn
}

# Connection information
output "connection_info" {
  description = "Information for connecting to the instance"
  value = {
    public_ip  = module.compute.instance_public_ip
    private_ip = module.compute.instance_private_ip
    rdp_port   = 3389
    winrm_port = 5985
  }
}

# Cost estimation
output "estimated_monthly_cost" {
  description = "Estimated monthly cost for the infrastructure"
  value = {
    ec2_instance = "~$300-500/month (varies by instance type and usage)"
    ebs_volumes  = "~$50-100/month (varies by volume size)"
    nat_gateway  = var.enable_nat_gateway ? "~$45/month" : "$0"
    vpc_flow_logs = var.enable_vpc_flow_logs ? "~$10-20/month" : "$0"
    cloudwatch   = "~$5-15/month"
    total        = "~$365-680/month"
  }
} 