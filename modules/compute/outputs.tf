output "instance_id" {
  description = "ID of the EC2 instance"
  value       = aws_instance.ue5_server.id
}

output "instance_public_ip" {
  description = "Public IP address of the EC2 instance"
  value       = aws_instance.ue5_server.public_ip
}

output "instance_private_ip" {
  description = "Private IP address of the EC2 instance"
  value       = aws_instance.ue5_server.private_ip
}

output "instance_arn" {
  description = "ARN of the EC2 instance"
  value       = aws_instance.ue5_server.arn
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
  value       = aws_instance.ue5_server.instance_state
} 