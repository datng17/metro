output "task_definition_arn" {
  description = "ARN (with revision) of the db-init task definition."
  value       = aws_ecs_task_definition.this.arn
}

output "task_family" {
  description = "Task definition family."
  value       = aws_ecs_task_definition.this.family
}

output "log_group_name" {
  description = "CloudWatch log group of db-init."
  value       = aws_cloudwatch_log_group.this.name
}

output "log_stream_prefix" {
  description = "Log stream prefix; a task's stream is <prefix>/<task-id>."
  value       = "db-init/${local.container}"
}

output "run_task_command" {
  description = "Command that starts db-init (works in bash and PowerShell)."
  value = join(" ", [
    "aws ecs run-task",
    "--cluster ${var.cluster_name}",
    "--task-definition ${aws_ecs_task_definition.this.family}",
    "--launch-type FARGATE",
    "--network-configuration \"awsvpcConfiguration={subnets=[${join(",", var.subnet_ids)}],securityGroups=[${join(",", var.security_group_ids)}],assignPublicIp=DISABLED}\"",
    "--query \"tasks[0].taskArn\" --output text",
  ])
}
