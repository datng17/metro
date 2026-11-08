variable "region" {
  description = "AWS region for the Terraform state bucket."
  type        = string
  default     = "us-east-1"
}

variable "state_bucket_name" {
  description = "Globally unique name of the S3 bucket that stores Terraform remote state (e.g. metro-tfstate-<account_id>)."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.state_bucket_name))
    error_message = "state_bucket_name must be a valid S3 bucket name: 3-63 chars, lowercase letters, digits, dots and hyphens."
  }
}

variable "noncurrent_version_retention_days" {
  description = "Days to keep old (noncurrent) versions of state objects before they expire."
  type        = number
  default     = 90
}
