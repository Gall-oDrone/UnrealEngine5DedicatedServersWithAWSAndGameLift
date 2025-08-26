# Monitoring Module for Unreal Engine 5 Infrastructure
# This module creates CloudWatch monitoring and alerting resources

# CloudWatch Dashboard
resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "${var.project_name}-dashboard"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/EC2", "CPUUtilization", "AutoScalingGroupName", "${var.project_name}-asg"],
            [".", "NetworkIn", ".", "."],
            [".", "NetworkOut", ".", "."]
          ]
          period = 300
          stat   = "Average"
          region = var.aws_region
          title  = "EC2 Instance Metrics"
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/EBS", "VolumeReadBytes", "VolumeId", var.ebs_volume_id],
            [".", "VolumeWriteBytes", ".", "."],
            [".", "VolumeReadOps", ".", "."],
            [".", "VolumeWriteOps", ".", "."]
          ]
          period = 300
          stat   = "Average"
          region = var.aws_region
          title  = "EBS Volume Metrics"
        }
      }
    ]
  })
}

# CloudWatch Alarm for High CPU Usage
resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  alarm_name          = "${var.project_name}-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "300"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "This metric monitors EC2 CPU utilization"
  alarm_actions       = var.alarm_actions

  dimensions = {
    InstanceId = var.instance_id
  }

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-cpu-high-alarm"
  })
}

# CloudWatch Alarm for High Memory Usage (if available)
resource "aws_cloudwatch_metric_alarm" "memory_high" {
  count               = var.enable_memory_monitoring ? 1 : 0
  alarm_name          = "${var.project_name}-memory-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "Memory % Committed Bytes In Use"
  namespace           = "CWAgent"
  period              = "300"
  statistic           = "Average"
  threshold           = "85"
  alarm_description   = "This metric monitors memory utilization"
  alarm_actions       = var.alarm_actions

  dimensions = {
    InstanceId = var.instance_id
  }

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-memory-high-alarm"
  })
}

# CloudWatch Alarm for Disk Space
resource "aws_cloudwatch_metric_alarm" "disk_high" {
  count               = var.enable_disk_monitoring ? 1 : 0
  alarm_name          = "${var.project_name}-disk-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "disk_used_percent"
  namespace           = "CWAgent"
  period              = "300"
  statistic           = "Average"
  threshold           = "85"
  alarm_description   = "This metric monitors disk space utilization"
  alarm_actions       = var.alarm_actions

  dimensions = {
    InstanceId = var.instance_id
    Filesystem = "C:"
    MountPath  = "C:"
  }

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-disk-high-alarm"
  })
}

# CloudWatch Log Group for application logs
resource "aws_cloudwatch_log_group" "application_logs" {
  name              = "/aws/application/${var.project_name}"
  retention_in_days = var.log_retention_days

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-application-logs"
  })
}

# SNS Topic for alarms (if enabled)
resource "aws_sns_topic" "alarms" {
  count = var.enable_sns_notifications ? 1 : 0
  name  = "${var.project_name}-alarms"

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-alarms-topic"
  })
}

# SNS Topic Subscription (if enabled)
resource "aws_sns_topic_subscription" "email" {
  count     = var.enable_sns_notifications && var.notification_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.alarms[0].arn
  protocol  = "email"
  endpoint  = var.notification_email
} 