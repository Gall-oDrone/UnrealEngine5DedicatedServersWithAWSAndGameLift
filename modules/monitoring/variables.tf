variable "project_name" {
  description = "Name of the project"
  type        = string
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "instance_id" {
  description = "ID of the EC2 instance to monitor"
  type        = string
}

variable "ebs_volume_id" {
  description = "ID of the EBS volume to monitor"
  type        = string
}

variable "enable_memory_monitoring" {
  description = "Whether to enable memory monitoring"
  type        = bool
  default     = false
}

variable "enable_disk_monitoring" {
  description = "Whether to enable disk space monitoring"
  type        = bool
  default     = false
}

variable "enable_sns_notifications" {
  description = "Whether to enable SNS notifications for alarms"
  type        = bool
  default     = false
}

variable "notification_email" {
  description = "Email address for SNS notifications"
  type        = string
  default     = ""
}

variable "log_retention_days" {
  description = "Number of days to retain CloudWatch logs"
  type        = number
  default     = 30
}

variable "alarm_actions" {
  description = "List of ARNs to notify when alarms are triggered"
  type        = list(string)
  default     = []
}

variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default     = {}
} 