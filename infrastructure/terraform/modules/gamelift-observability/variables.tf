variable "project_name" {
  type    = string
  default = "frontendui"
}

variable "metric_group" {
  description = "GameLift fleet metric group aggregated on the dashboard/alarms (fleets default to \"default\")."
  type        = string
  default     = "default"
}

variable "proxy_function_name" {
  description = "Lambda function name of the GameLift client proxy."
  type        = string
}

variable "proxy_api_id" {
  description = "API Gateway HTTP API id of the GameLift client proxy."
  type        = string
}

variable "alert_email" {
  description = "E-mail subscribed to the alerts SNS topic (empty = topic only)."
  type        = string
  default     = ""
}

variable "ec2_hours_before_alarm" {
  description = "Alarm when any On-Demand EC2 vCPU has been in use for this many consecutive hours."
  type        = number
  default     = 6
}
