output "parameter_arns" {
  description = "Map of env var name to SSM parameter ARN (generated, placeholder and external). Used as valueFrom in task definition secrets."
  value = merge(
    { for k, p in aws_ssm_parameter.generated : k => p.arn },
    { for k, p in aws_ssm_parameter.placeholder : k => p.arn },
    local.external_arns,
  )
}

output "parameter_names" {
  description = "Map of env var name to SSM parameter name."
  value = merge(
    { for k, p in aws_ssm_parameter.generated : k => p.name },
    { for k, p in aws_ssm_parameter.placeholder : k => p.name },
    { for k in var.external_secrets : k => "${var.path_prefix}/${k}" },
  )
}

output "parameter_arn_pattern" {
  description = "ARN pattern covering every parameter under the prefix (for the ECS execution role in Task 6)."
  value       = "${local.arn_prefix}${var.path_prefix}/*"
}
