variable "name" {
  description = "Name prefix. The instance is named <name>-postgres."
  type        = string
}

variable "vpc_id" {
  description = "VPC of the database security group."
  type        = string
}

variable "subnet_ids" {
  description = "Private data subnet IDs (at least 2 AZs) for the DB subnet group."
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) >= 2
    error_message = "subnet_ids must contain at least 2 subnets in different AZs."
  }
}

variable "allowed_security_group_ids" {
  description = "Security groups allowed to connect on 5432, keyed by a static label (e.g. { ecs_tasks = sg-... })."
  type        = map(string)
}

variable "engine_version" {
  description = "PostgreSQL major (or major.minor) version."
  type        = string
  default     = "17"
}

variable "instance_class" {
  description = "RDS instance class."
  type        = string
  default     = "db.t4g.micro"
}

variable "allocated_storage" {
  description = "Allocated gp3 storage in GiB."
  type        = number
  default     = 20
}

variable "master_username" {
  description = "Master user name. Its password is managed by RDS in Secrets Manager."
  type        = string
  default     = "metro_admin"
}

variable "backup_retention_days" {
  description = "Automated backup retention in days."
  type        = number
  default     = 1
}

variable "deletion_protection" {
  description = "Block deletion of the instance. Set to false before terraform destroy."
  type        = bool
}

variable "skip_final_snapshot" {
  description = "Skip the final snapshot on deletion. When false, the snapshot <name>-postgres-final is created."
  type        = bool
}
