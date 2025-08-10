# Simple Monitoring and Alerting Configuration

# SNS Topic for alerts
resource "aws_sns_topic" "webtrees_alerts" {
  name = "webtrees-alerts"
  
  tags = merge(var.tags, {
    Name = "webtrees-alerts"
  })
}

# SNS Topic subscription for email alerts
resource "aws_sns_topic_subscription" "webtrees_alerts_email" {
  count     = var.alert_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.webtrees_alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# CloudWatch Dashboard
resource "aws_cloudwatch_dashboard" "webtrees_dashboard" {
  dashboard_name = "webtrees-monitoring"

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
            ["AWS/EC2", "CPUUtilization", "InstanceId", aws_instance.webtrees_instance.id],
            ["CWAgent", "MEM_USED", "InstanceId", aws_instance.webtrees_instance.id],
            ["CWAgent", "DISK_USED", "InstanceId", aws_instance.webtrees_instance.id, "path", "/"]
          ]
          view    = "timeSeries"
          stacked = false
          region  = var.aws_region
          title   = "System Metrics"
          period  = 60
          stat    = "Average"
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
            ["Webtrees/Docker", "WebtreesRunning"],
            [".", "MariaDBRunning"],
            ["Webtrees/Application", "WebsiteUp"]
          ]
          view    = "singleValue"
          region  = var.aws_region
          title   = "Application Health"
          period  = 60
          stat    = "Average"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 24
        height = 6
        properties = {
          metrics = [
            ["Webtrees/Docker", "WebtreesMemoryPercent"],
            [".", "MariaDBMemoryPercent"]
          ]
          view    = "timeSeries"
          stacked = false
          region  = var.aws_region
          title   = "Docker Container Memory"
          period  = 60
          stat    = "Average"
        }
      }
    ]
  })
}

# Alarm for EC2 instance status check
resource "aws_cloudwatch_metric_alarm" "ec2_status_check" {
  alarm_name          = "webtrees-ec2-status-check"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "StatusCheckFailed"
  namespace           = "AWS/EC2"
  period              = "300"
  statistic           = "Maximum"
  threshold           = "0"
  alarm_description   = "EC2 instance status check failed"
  alarm_actions       = [aws_sns_topic.webtrees_alerts.arn]
  ok_actions          = [aws_sns_topic.webtrees_alerts.arn]
  treat_missing_data  = "breaching"

  dimensions = {
    InstanceId = aws_instance.webtrees_instance.id
  }

  tags = var.tags
}

# Alarm for high CPU utilization
resource "aws_cloudwatch_metric_alarm" "high_cpu" {
  alarm_name          = "webtrees-high-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "3"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "300"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "CPU utilization above 80%"
  alarm_actions       = [aws_sns_topic.webtrees_alerts.arn]
  ok_actions          = [aws_sns_topic.webtrees_alerts.arn]

  dimensions = {
    InstanceId = aws_instance.webtrees_instance.id
  }

  tags = var.tags
}

# Alarm for Webtrees container not running
resource "aws_cloudwatch_metric_alarm" "webtrees_container_down" {
  alarm_name          = "webtrees-container-down"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "WebtreesRunning"
  namespace           = "Webtrees/Docker"
  period              = "60"
  statistic           = "Minimum"
  threshold           = "1"
  alarm_description   = "Webtrees Docker container is not running"
  alarm_actions       = [aws_sns_topic.webtrees_alerts.arn]
  ok_actions          = [aws_sns_topic.webtrees_alerts.arn]
  treat_missing_data  = "breaching"

  tags = var.tags
}

# Alarm for MariaDB container not running
resource "aws_cloudwatch_metric_alarm" "mariadb_container_down" {
  alarm_name          = "webtrees-mariadb-down"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "MariaDBRunning"
  namespace           = "Webtrees/Docker"
  period              = "60"
  statistic           = "Minimum"
  threshold           = "1"
  alarm_description   = "MariaDB Docker container is not running"
  alarm_actions       = [aws_sns_topic.webtrees_alerts.arn]
  ok_actions          = [aws_sns_topic.webtrees_alerts.arn]
  treat_missing_data  = "breaching"

  tags = var.tags
}

# Alarm for website not responding
resource "aws_cloudwatch_metric_alarm" "website_down" {
  alarm_name          = "webtrees-website-down"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "3"
  metric_name         = "WebsiteUp"
  namespace           = "Webtrees/Application"
  period              = "60"
  statistic           = "Minimum"
  threshold           = "1"
  alarm_description   = "Website is not responding"
  alarm_actions       = [aws_sns_topic.webtrees_alerts.arn]
  ok_actions          = [aws_sns_topic.webtrees_alerts.arn]
  treat_missing_data  = "breaching"

  tags = var.tags
}

# CloudWatch Log Group for application logs
resource "aws_cloudwatch_log_group" "webtrees_logs" {
  name              = "/aws/ec2/webtrees"
  retention_in_days = 7

  tags = var.tags
}

# IAM policy for CloudWatch agent
resource "aws_iam_role_policy_attachment" "cloudwatch_agent_policy" {
  role       = aws_iam_role.webtrees_ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

# IAM policy for custom metrics
resource "aws_iam_role_policy" "cloudwatch_metrics_policy" {
  name = "webtrees-cloudwatch-metrics"
  role = aws_iam_role.webtrees_ec2_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricData",
          "ec2:DescribeVolumes",
          "ec2:DescribeTags",
          "logs:PutLogEvents",
          "logs:CreateLogGroup",
          "logs:CreateLogStream"
        ]
        Resource = "*"
      }
    ]
  })
}

# Outputs
output "sns_topic_arn" {
  description = "SNS topic ARN for alerts"
  value       = aws_sns_topic.webtrees_alerts.arn
}

output "monitoring_dashboard_url" {
  description = "CloudWatch Dashboard URL"
  value       = "https://console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=webtrees-monitoring"
}

output "alert_configuration" {
  description = "Alert configuration status"
  value = var.alert_email != "" ? "Email alerts configured for: ${var.alert_email}" : "No email alerts configured. Set 'alert_email' variable to enable."
}