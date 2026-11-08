output "repository_urls" {
  description = "Map of service name to repository URL (<account>.dkr.ecr.<region>.amazonaws.com/<prefix>/<service>)."
  value       = { for svc, repo in aws_ecr_repository.this : svc => repo.repository_url }
}

output "repository_arns" {
  description = "Map of service name to repository ARN (used later for IAM push/pull policies)."
  value       = { for svc, repo in aws_ecr_repository.this : svc => repo.arn }
}

output "repository_names" {
  description = "Map of service name to repository name (<prefix>/<service>)."
  value       = { for svc, repo in aws_ecr_repository.this : svc => repo.name }
}

output "registry_id" {
  description = "AWS account ID that owns the registry."
  value       = one(distinct([for repo in aws_ecr_repository.this : repo.registry_id]))
}

output "registry_url" {
  description = "Registry host used for docker login (<account>.dkr.ecr.<region>.amazonaws.com)."
  value       = one(distinct([for repo in aws_ecr_repository.this : split("/", repo.repository_url)[0]]))
}
