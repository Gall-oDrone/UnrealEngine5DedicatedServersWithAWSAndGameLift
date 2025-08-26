output "kms_key_arn" {
  description = "ARN of the KMS key (if enabled)"
  value       = var.enable_kms ? aws_kms_key.main[0].arn : null
}

output "kms_key_id" {
  description = "ID of the KMS key (if enabled)"
  value       = var.enable_kms ? aws_kms_key.main[0].key_id : null
}

output "security_log_group_name" {
  description = "Name of the security CloudWatch log group"
  value       = aws_cloudwatch_log_group.security_logs.name
}

output "vpc_flow_log_id" {
  description = "ID of the VPC Flow Log (if enabled)"
  value       = var.enable_vpc_flow_logs ? aws_flow_log.vpc_flow_log[0].id : null
}

output "vpc_flow_log_role_arn" {
  description = "ARN of the VPC Flow Log IAM role (if enabled)"
  value       = var.enable_vpc_flow_logs ? aws_iam_role.vpc_flow_log_role[0].arn : null
} 