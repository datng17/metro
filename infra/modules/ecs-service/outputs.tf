output "service_name" {
  description = "ECS service name."
  value       = aws_ecs_service.this.name
}

output "service_arn" {
  description = "ECS service ARN."
  value       = aws_ecs_service.this.id
}

output "task_definition_arn" {
  description = "Task definition ARN (with revision)."
  value       = aws_ecs_task_definition.this.arn
}

output "task_definition_family" {
  description = "Task definition family."
  value       = aws_ecs_task_definition.this.family
}

output "container_name" {
  description = "Container name (for ECS Exec --container and load balancer attachment)."
  value       = var.service_name
}

output "security_group_id" {
  description = "Service security group (the one that receives ingress rules)."
  value       = aws_security_group.this.id
}

output "execution_role_arn" {
  description = "Task execution role ARN."
  value       = aws_iam_role.execution.arn
}

output "task_role_arn" {
  description = "Task role ARN."
  value       = aws_iam_role.task.arn
}

output "log_group_name" {
  description = "CloudWatch log group."
  value       = aws_cloudwatch_log_group.this.name
}

output "discovery_arn" {
  description = "Cloud Map service ARN, or null when service discovery is off."
  value       = one(aws_service_discovery_service.this[*].arn)
}
