output "sns_topic_arn" {
  description = "Alerts SNS topic ARN."
  value       = aws_sns_topic.alerts.arn
}

output "alarm_names" {
  description = "Names of the CloudWatch alarms (sorted)."
  value       = sort([for a in aws_cloudwatch_metric_alarm.this : a.alarm_name])
}

output "budget_name" {
  description = "AWS Budgets budget name."
  value       = aws_budgets_budget.monthly.name
}
