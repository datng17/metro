# ---------------------------------------------------------------------------
# Alerts: one SNS topic (email subscription) that receives
#   - CloudWatch alarms on the ALB, the gateway target group and RDS
#     (ALARM and OK transitions), and
#   - AWS Budgets notifications for the monthly account cost.
# ---------------------------------------------------------------------------
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  account = data.aws_caller_identity.current.account_id
  region  = data.aws_region.current.region
}

# Not KMS-encrypted on purpose: CloudWatch and Budgets cannot publish to a
# topic encrypted with the AWS-managed key alias/aws/sns, and a customer
# managed key costs $1/month. Alert messages contain no secrets.
resource "aws_sns_topic" "alerts" {
  name = "${var.name}-alerts"

  tags = {
    Name = "${var.name}-alerts"
  }
}

data "aws_iam_policy_document" "alerts" {
  # Same rights the default topic policy gives the owning account.
  statement {
    sid = "AccountOwner"
    actions = [
      "SNS:AddPermission",
      "SNS:DeleteTopic",
      "SNS:GetTopicAttributes",
      "SNS:ListSubscriptionsByTopic",
      "SNS:Publish",
      "SNS:RemovePermission",
      "SNS:SetTopicAttributes",
      "SNS:Subscribe",
    ]
    resources = [aws_sns_topic.alerts.arn]

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${local.account}:root"]
    }
  }

  statement {
    sid       = "CloudWatchAlarms"
    actions   = ["SNS:Publish"]
    resources = [aws_sns_topic.alerts.arn]

    principals {
      type        = "Service"
      identifiers = ["cloudwatch.amazonaws.com"]
    }

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:aws:cloudwatch:${local.region}:${local.account}:alarm:*"]
    }
  }

  statement {
    sid       = "Budgets"
    actions   = ["SNS:Publish"]
    resources = [aws_sns_topic.alerts.arn]

    principals {
      type        = "Service"
      identifiers = ["budgets.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account]
    }

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:aws:budgets::${local.account}:*"]
    }
  }
}

resource "aws_sns_topic_policy" "alerts" {
  arn    = aws_sns_topic.alerts.arn
  policy = data.aws_iam_policy_document.alerts.json
}

# AWS sends a confirmation email; nothing is delivered until it is confirmed.
resource "aws_sns_topic_subscription" "email" {
  count = var.alert_email == null ? 0 : 1

  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# ---------------------------------------------------------------------------
# CloudWatch alarms
#
# treat_missing_data:
#   notBreaching: the metric is only emitted when something happens (5xx
#                 counts, unhealthy hosts) or the source is stopped (RDS).
#   breaching:    gateway-healthy-hosts. No data means no healthy gateway.
# ---------------------------------------------------------------------------
locals {
  alb_dimensions = { LoadBalancer = var.alb_arn_suffix }
  tg_dimensions = {
    LoadBalancer = var.alb_arn_suffix
    TargetGroup  = var.target_group_arn_suffix
  }
  rds_dimensions = { DBInstanceIdentifier = var.rds_identifier }

  alarms = {
    alb-5xx = {
      description         = "The ALB returned >= ${var.alb_5xx_threshold} 5xx in 5 minutes (502/503/504: no healthy gateway, or gateway timeouts)."
      namespace           = "AWS/ApplicationELB"
      metric_name         = "HTTPCode_ELB_5XX_Count"
      statistic           = "Sum"
      period              = 300
      evaluation_periods  = 1
      datapoints_to_alarm = 1
      comparison_operator = "GreaterThanOrEqualToThreshold"
      threshold           = var.alb_5xx_threshold
      treat_missing_data  = "notBreaching"
      dimensions          = local.alb_dimensions
    }

    gateway-5xx = {
      description         = "The gateway returned >= ${var.target_5xx_threshold} 5xx in 5 minutes (errors in the gateway or a downstream service)."
      namespace           = "AWS/ApplicationELB"
      metric_name         = "HTTPCode_Target_5XX_Count"
      statistic           = "Sum"
      period              = 300
      evaluation_periods  = 1
      datapoints_to_alarm = 1
      comparison_operator = "GreaterThanOrEqualToThreshold"
      threshold           = var.target_5xx_threshold
      treat_missing_data  = "notBreaching"
      dimensions          = local.tg_dimensions
    }

    gateway-unhealthy-hosts = {
      description         = "At least one gateway target failed the ALB health check for 3 minutes."
      namespace           = "AWS/ApplicationELB"
      metric_name         = "UnHealthyHostCount"
      statistic           = "Maximum"
      period              = 60
      evaluation_periods  = 3
      datapoints_to_alarm = 3
      comparison_operator = "GreaterThanOrEqualToThreshold"
      threshold           = 1
      treat_missing_data  = "notBreaching"
      dimensions          = local.tg_dimensions
    }

    # Fires when the gateway is stopped: no registered target is not
    # "unhealthy", so UnHealthyHostCount alone would stay at 0.
    gateway-healthy-hosts = {
      description         = "No healthy gateway target for 2 minutes: the site is down."
      namespace           = "AWS/ApplicationELB"
      metric_name         = "HealthyHostCount"
      statistic           = "Minimum"
      period              = 60
      evaluation_periods  = 2
      datapoints_to_alarm = 2
      comparison_operator = "LessThanThreshold"
      threshold           = 1
      treat_missing_data  = "breaching"
      dimensions          = local.tg_dimensions
    }

    rds-cpu = {
      description         = "RDS average CPU above ${var.rds_cpu_threshold_percent}% for 15 minutes (db.t4g.micro may be out of CPU credits)."
      namespace           = "AWS/RDS"
      metric_name         = "CPUUtilization"
      statistic           = "Average"
      period              = 300
      evaluation_periods  = 3
      datapoints_to_alarm = 3
      comparison_operator = "GreaterThanThreshold"
      threshold           = var.rds_cpu_threshold_percent
      treat_missing_data  = "notBreaching"
      dimensions          = local.rds_dimensions
    }

    rds-free-storage = {
      description         = "RDS free storage below ${floor(var.rds_free_storage_threshold_bytes / 1073741824)} GiB."
      namespace           = "AWS/RDS"
      metric_name         = "FreeStorageSpace"
      statistic           = "Minimum"
      period              = 300
      evaluation_periods  = 1
      datapoints_to_alarm = 1
      comparison_operator = "LessThanThreshold"
      threshold           = var.rds_free_storage_threshold_bytes
      treat_missing_data  = "notBreaching"
      dimensions          = local.rds_dimensions
    }
  }
}

resource "aws_cloudwatch_metric_alarm" "this" {
  for_each = local.alarms

  alarm_name        = "${var.name}-${each.key}"
  alarm_description = each.value.description

  namespace   = each.value.namespace
  metric_name = each.value.metric_name
  dimensions  = each.value.dimensions
  statistic   = each.value.statistic
  period      = each.value.period

  evaluation_periods  = each.value.evaluation_periods
  datapoints_to_alarm = each.value.datapoints_to_alarm
  comparison_operator = each.value.comparison_operator
  threshold           = each.value.threshold
  treat_missing_data  = each.value.treat_missing_data

  actions_enabled = true
  alarm_actions   = [aws_sns_topic.alerts.arn]
  ok_actions      = [aws_sns_topic.alerts.arn]

  tags = {
    Name = "${var.name}-${each.key}"
  }

  depends_on = [aws_sns_topic_policy.alerts]
}

# ---------------------------------------------------------------------------
# Monthly cost budget (whole account, unblended cost). Notifies the alerts
# topic when actual spend passes each threshold, and when the forecast for
# the month passes the limit.
# ---------------------------------------------------------------------------
resource "aws_budgets_budget" "monthly" {
  name         = "${var.name}-monthly"
  budget_type  = "COST"
  limit_amount = format("%.2f", var.budget_limit_usd)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  dynamic "notification" {
    for_each = toset(var.budget_alert_thresholds_usd)

    content {
      comparison_operator       = "GREATER_THAN"
      notification_type         = "ACTUAL"
      threshold                 = notification.value
      threshold_type            = "ABSOLUTE_VALUE"
      subscriber_sns_topic_arns = [aws_sns_topic.alerts.arn]
    }
  }

  notification {
    comparison_operator       = "GREATER_THAN"
    notification_type         = "FORECASTED"
    threshold                 = 100
    threshold_type            = "PERCENTAGE"
    subscriber_sns_topic_arns = [aws_sns_topic.alerts.arn]
  }

  depends_on = [aws_sns_topic_policy.alerts]
}
