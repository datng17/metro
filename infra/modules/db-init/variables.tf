variable "name" {
  description = "Name prefix (e.g. metro-prod). The task family is <name>-db-init."
  type        = string
}

variable "image" {
  description = "Image providing bash, pg_isready and psql."
  type        = string
  default     = "public.ecr.aws/docker/library/postgres:17"
}

variable "db_host" {
  description = "RDS endpoint address."
  type        = string
}

variable "db_port" {
  description = "RDS port."
  type        = number
  default     = 5432
}

variable "master_user_secret_arn" {
  description = "Secrets Manager ARN of the RDS-managed master credentials (JSON keys username, password)."
  type        = string
}

variable "app_db_username" {
  description = "Login role created for the services; owner of every service database."
  type        = string

  validation {
    condition     = can(regex("^[a-z_][a-z0-9_]{0,62}$", var.app_db_username))
    error_message = "app_db_username must be a lowercase PostgreSQL identifier."
  }
}

variable "app_password_parameter_arn" {
  description = "SSM SecureString ARN holding the app role password (DB_PASSWORD)."
  type        = string
}

variable "databases" {
  description = "Databases to create."
  type        = list(string)

  validation {
    condition     = length(var.databases) > 0 && alltrue([for d in var.databases : can(regex("^[a-z_][a-z0-9_]{0,62}$", d))])
    error_message = "databases must be lowercase PostgreSQL identifiers."
  }
}

variable "cluster_name" {
  description = "ECS cluster used in the generated run-task command."
  type        = string
}

variable "subnet_ids" {
  description = "Private app subnets for the task (they route out through fck-nat)."
  type        = list(string)
}

variable "security_group_ids" {
  description = "Security groups for the task; must include the one RDS allows."
  type        = list(string)
}

variable "log_retention_days" {
  description = "CloudWatch log retention."
  type        = number
  default     = 7
}
