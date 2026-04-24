output "dashboard_name" {
  description = "Name of the CloudWatch dashboard"
  value       = aws_cloudwatch_dashboard.main.dashboard_name
}

output "dashboard_arn" {
  description = "ARN of the CloudWatch dashboard"
  value       = aws_cloudwatch_dashboard.main.dashboard_arn
}

output "cpu_alarm_arn" {
  description = "ARN of the CPU high usage alarm"
  value       = aws_cloudwatch_metric_alarm.cpu_high.arn
}

output "memory_alarm_arn" {
  description = "ARN of the memory high usage alarm (if enabled)"
  value       = var.enable_memory_monitoring ? aws_cloudwatch_metric_alarm.memory_high[0].arn : null
}

output "disk_alarm_arn" {
  description = "ARN of the disk high usage alarm (if enabled)"
  value       = var.enable_disk_monitoring ? aws_cloudwatch_metric_alarm.disk_high[0].arn : null
}

output "application_log_group_name" {
  description = "Name of the application CloudWatch log group"
  value       = aws_cloudwatch_log_group.application_logs.name
}

output "sns_topic_arn" {
  description = "ARN of the SNS topic for alarms (if enabled)"
  value       = var.enable_sns_notifications ? aws_sns_topic.alarms[0].arn : null
} 