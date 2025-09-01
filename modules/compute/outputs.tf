output "instance_id" {
  description = "ID of the EC2 instance"
  value       = var.enable_spot_instance ? aws_spot_instance_request.ue5_server_spot[0].spot_instance_id : aws_instance.ue5_server[0].id
}

output "instance_public_ip" {
  description = "Public IP address of the EC2 instance"
  value       = var.enable_spot_instance ? aws_spot_instance_request.ue5_server_spot[0].public_ip : aws_instance.ue5_server[0].public_ip
}

output "instance_private_ip" {
  description = "Private IP address of the EC2 instance"
  value       = var.enable_spot_instance ? aws_spot_instance_request.ue5_server_spot[0].private_ip : aws_instance.ue5_server[0].private_ip
}

output "instance_arn" {
  description = "ARN of the EC2 instance"
  value       = var.enable_spot_instance ? aws_spot_instance_request.ue5_server_spot[0].arn : aws_instance.ue5_server[0].arn
}

output "security_group_id" {
  description = "ID of the security group"
  value       = aws_security_group.ec2.id
}

output "iam_role_arn" {
  description = "ARN of the IAM role"
  value       = aws_iam_role.ec2_role.arn
}

output "data_volume_id" {
  description = "ID of the data EBS volume"
  value       = aws_ebs_volume.data_volume.id
}

output "instance_state" {
  description = "Current state of the EC2 instance"
  value       = var.enable_spot_instance ? aws_spot_instance_request.ue5_server_spot[0].instance_state : aws_instance.ue5_server[0].instance_state
}

output "dcv_port" {
  description = "Port for NICE DCV service"
  value       = var.dcv_port
}

output "windows_admin_password" {
  description = "Windows Administrator password"
  value       = var.admin_password != "" ? var.admin_password : random_password.windows_admin[0].result
  sensitive   = true
} 