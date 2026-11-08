output "oidc_provider_arn" {
  description = "ARN of the GitHub Actions OIDC provider."
  value       = local.oidc_arn
}

output "deploy_role_arn" {
  description = "Role assumed by the CD workflows (GitHub variable AWS_ROLE_ARN)."
  value       = aws_iam_role.deploy.arn
}

output "deploy_role_subject" {
  description = "The only OIDC subject the deploy role trusts."
  value       = local.deploy_sub
}

output "plan_role_arn" {
  description = "Read-only role assumed by infra-ci.yml on pull requests (GitHub variable AWS_PLAN_ROLE_ARN), or null."
  value       = one(aws_iam_role.plan[*].arn)
}
