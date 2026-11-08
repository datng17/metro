output "state_bucket_name" {
  description = "Name of the Terraform state bucket. Put it in infra/envs/prod/backend.hcl."
  value       = aws_s3_bucket.state.bucket
}

output "state_bucket_arn" {
  description = "ARN of the Terraform state bucket."
  value       = aws_s3_bucket.state.arn
}

output "region" {
  description = "Region of the Terraform state bucket."
  value       = var.region
}
