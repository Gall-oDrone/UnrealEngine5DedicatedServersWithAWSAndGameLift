# gamelift-observability: one CloudWatch dashboard + a handful of alarms for the whole
# FrontendUI stack (GameLift fleets via the "default" metric group, the client proxy, and a
# "something is still running" guard on EC2 usage). SNS e-mail for the alarms.
#
# Cost: dashboard free (first 3), ~10 alarms free tier then $0.10/alarm/month, SNS e-mail free.

terraform {
  required_version = ">= 1.10"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

data "aws_region" "current" {}

locals {
  name   = "${var.project_name}-gamelift"
  region = data.aws_region.current.name
  gl     = { MetricGroups = var.metric_group, Location = "aggregate" }
}

# ---- Notifications --------------------------------------------------------------------------

resource "aws_sns_topic" "alerts" {
  name = "${local.name}-alerts"
}

resource "aws_sns_topic_subscription" "email" {
  count     = var.alert_email == "" ? 0 : 1
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email # AWS sends a confirmation mail; the subscription is inert until confirmed
}

# ---- Alarms ---------------------------------------------------------------------------------

resource "aws_cloudwatch_metric_alarm" "proxy_errors" {
  alarm_name          = "${local.name}-proxy-lambda-errors"
  alarm_description   = "The GameLift client proxy Lambda raised an unhandled error."
  namespace           = "AWS/Lambda"
  metric_name         = "Errors"
  dimensions          = { FunctionName = var.proxy_function_name }
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "proxy_5xx" {
  alarm_name          = "${local.name}-proxy-api-5xx"
  alarm_description   = "API Gateway returned 5xx for the GameLift client proxy."
  namespace           = "AWS/ApiGateway"
  metric_name         = "5xx"
  dimensions          = { ApiId = var.proxy_api_id }
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "server_crashes" {
  alarm_name          = "${local.name}-server-abnormal-terminations"
  alarm_description   = "A dedicated server process on a GameLift fleet exited without TerminateServerProcess (crash / kill)."
  namespace           = "AWS/GameLift"
  metric_name         = "ServerProcessAbnormalTerminations"
  dimensions          = local.gl
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
}

# "Forgotten build box / fleet" guard: any On-Demand EC2 vCPU in use for N hours straight.
# GameLift-managed instances count here too (container fleets are EC2 under the hood).
resource "aws_cloudwatch_metric_alarm" "ec2_running_too_long" {
  alarm_name          = "${local.name}-ec2-running-${var.ec2_hours_before_alarm}h"
  alarm_description   = "EC2 On-Demand vCPUs have been in use for ${var.ec2_hours_before_alarm} h straight. Build box or container fleet still up?"
  namespace           = "AWS/Usage"
  metric_name         = "ResourceCount"
  dimensions          = { Service = "EC2", Type = "Resource", Resource = "vCPU", Class = "Standard/OnDemand" }
  statistic           = "Maximum"
  period              = 3600
  evaluation_periods  = var.ec2_hours_before_alarm
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
}

# ---- Dashboard ------------------------------------------------------------------------------

locals {
  gl_dims = ["MetricGroups", var.metric_group, "Location", "aggregate"]
  widgets = [
    {
      type       = "text", x = 0, y = 0, width = 24, height = 2,
      properties = { markdown = "## FrontendUI - Amazon GameLift\nFleets in metric group **${var.metric_group}** (Anywhere + container fleets), the client proxy, and the EC2 usage guard. Budget: `FrontendUI-Monthly`." }
    },
    {
      type = "metric", x = 0, y = 2, width = 8, height = 6,
      properties = {
        title = "Game & player sessions", region = local.region, stat = "Maximum", period = 60, view = "timeSeries",
        metrics = [
          concat(["AWS/GameLift", "ActiveGameSessions"], local.gl_dims),
          concat(["AWS/GameLift", "CurrentPlayerSessions"], local.gl_dims),
          concat(["AWS/GameLift", "ActivatingGameSessions"], local.gl_dims),
        ]
      }
    },
    {
      type = "metric", x = 8, y = 2, width = 8, height = 6,
      properties = {
        title = "Server processes & capacity", region = local.region, stat = "Maximum", period = 60, view = "timeSeries",
        metrics = [
          concat(["AWS/GameLift", "ActiveServerProcesses"], local.gl_dims),
          concat(["AWS/GameLift", "HealthyServerProcesses"], local.gl_dims),
          concat(["AWS/GameLift", "AvailableGameSessions"], local.gl_dims),
          concat(["AWS/GameLift", "ActiveInstances"], local.gl_dims),
        ]
      }
    },
    {
      type = "metric", x = 16, y = 2, width = 8, height = 6,
      properties = {
        title = "Scaling signal & crashes", region = local.region, stat = "Average", period = 60, view = "timeSeries",
        metrics = [
          concat(["AWS/GameLift", "PercentAvailableGameSessions"], local.gl_dims, [{ yAxis = "left" }]),
          concat(["AWS/GameLift", "ServerProcessAbnormalTerminations"], local.gl_dims, [{ stat = "Sum", yAxis = "right", color = "#d62728" }]),
          concat(["AWS/GameLift", "ServerProcessTerminations"], local.gl_dims, [{ stat = "Sum", yAxis = "right" }]),
        ]
      }
    },
    {
      type = "metric", x = 0, y = 8, width = 8, height = 6,
      properties = {
        title = "Proxy - requests by status", region = local.region, stat = "Sum", period = 60, view = "timeSeries",
        metrics = [
          ["AWS/ApiGateway", "Count", "ApiId", var.proxy_api_id],
          ["AWS/ApiGateway", "4xx", "ApiId", var.proxy_api_id, { color = "#ff7f0e" }],
          ["AWS/ApiGateway", "5xx", "ApiId", var.proxy_api_id, { color = "#d62728" }],
        ]
      }
    },
    {
      type = "metric", x = 8, y = 8, width = 8, height = 6,
      properties = {
        title = "Proxy - latency (ms)", region = local.region, period = 60, view = "timeSeries",
        metrics = [
          ["AWS/ApiGateway", "Latency", "ApiId", var.proxy_api_id, { stat = "p95" }],
          ["AWS/Lambda", "Duration", "FunctionName", var.proxy_function_name, { stat = "p95" }],
        ]
      }
    },
    {
      type = "metric", x = 16, y = 8, width = 8, height = 6,
      properties = {
        title = "Proxy - Lambda health", region = local.region, stat = "Sum", period = 60, view = "timeSeries",
        metrics = [
          ["AWS/Lambda", "Invocations", "FunctionName", var.proxy_function_name],
          ["AWS/Lambda", "Errors", "FunctionName", var.proxy_function_name, { color = "#d62728" }],
          ["AWS/Lambda", "Throttles", "FunctionName", var.proxy_function_name],
        ]
      }
    },
    {
      type = "metric", x = 0, y = 14, width = 12, height = 5,
      properties = {
        title   = "EC2 On-Demand vCPUs in use (build box / container fleets)", region = local.region, stat = "Maximum", period = 300, view = "timeSeries",
        metrics = [["AWS/Usage", "ResourceCount", "Service", "EC2", "Type", "Resource", "Resource", "vCPU", "Class", "Standard/OnDemand"]]
      }
    },
    {
      type = "log", x = 12, y = 14, width = 12, height = 5,
      properties = {
        title  = "Proxy - last 401/400/5xx",
        region = local.region,
        query  = "SOURCE '/aws/apigateway/${var.proxy_function_name}' | fields time, status, ip | filter status >= 400 | sort @timestamp desc | limit 20"
      }
    },
  ]
}

resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = local.name
  dashboard_body = jsonencode({ widgets = local.widgets })
}
