output "instance_id" {
  description = "ID of the EC2 instance"
  value       = var.enable_spot_instance ? (
    length(aws_spot_instance_request.ue5_server_spot) > 0 ? aws_spot_instance_request.ue5_server_spot[0].spot_instance_id : null
  ) : (
    length(aws_instance.ue5_server) > 0 ? aws_instance.ue5_server[0].id : null
  )
}

output "instance_public_ip" {
  description = "Public IP address of the EC2 instance"
  value       = var.enable_spot_instance ? (
    length(aws_spot_instance_request.ue5_server_spot) > 0 ? aws_spot_instance_request.ue5_server_spot[0].public_ip : null
  ) : (
    length(aws_instance.ue5_server) > 0 ? aws_instance.ue5_server[0].public_ip : null
  )
}

output "instance_private_ip" {
  description = "Private IP address of the EC2 instance"
  value       = var.enable_spot_instance ? (
    length(aws_spot_instance_request.ue5_server_spot) > 0 ? aws_spot_instance_request.ue5_server_spot[0].private_ip : null
  ) : (
    length(aws_instance.ue5_server) > 0 ? aws_instance.ue5_server[0].private_ip : null
  )
}

output "instance_arn" {
  description = "ARN of the EC2 instance"
  value       = var.enable_spot_instance ? (
    length(aws_spot_instance_request.ue5_server_spot) > 0 ? aws_spot_instance_request.ue5_server_spot[0].arn : null
  ) : (
    length(aws_instance.ue5_server) > 0 ? aws_instance.ue5_server[0].arn : null
  )
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
  value       = var.enable_spot_instance ? (
    length(aws_spot_instance_request.ue5_server_spot) > 0 ? aws_spot_instance_request.ue5_server_spot[0].instance_state : null
  ) : (
    length(aws_instance.ue5_server) > 0 ? aws_instance.ue5_server[0].instance_state : null
  )
}

output "spot_request_id" {
  description = "ID of the spot instance request (if using spot)"
  value       = var.enable_spot_instance && length(aws_spot_instance_request.ue5_server_spot) > 0 ? aws_spot_instance_request.ue5_server_spot[0].id : null
}

output "instance_type_used" {
  description = "Instance type being used"
  value       = var.instance_type
}