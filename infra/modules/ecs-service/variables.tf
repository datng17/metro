variable "name_prefix" {
  description = "Name prefix (e.g. metro-prod). Resources are named <name_prefix>-<service_name>."
  type        = string
}

variable "service_name" {
  description = "Service and container name (e.g. eureka). Also the Cloud Map name: <service_name>.<namespace>."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,62}$", var.service_name))
    error_message = "service_name must be lowercase letters, digits and dashes (a valid DNS label)."
  }
}

# ---------------------------------------------------------------------------
# Placement
# ---------------------------------------------------------------------------
variable "cluster_arn" {
  description = "ECS cluster ARN."
  type        = string
}

variable "vpc_id" {
  description = "VPC of the service security group."
  type        = string
}

variable "subnet_ids" {
  description = "Private subnets for the tasks (no public IP; egress through fck-nat)."
  type        = list(string)
}

variable "shared_security_group_ids" {
  description = "Extra security groups attached to every task, e.g. the cluster-wide tasks SG that RDS trusts."
  type        = list(string)
  default     = []
}

variable "ingress_security_group_ids" {
  description = "Map of label => security group ID allowed to reach container_port."
  type        = map(string)
  default     = {}
}

variable "enable_service_discovery" {
  description = "Register the tasks in Cloud Map as <service_name>.<namespace>. Requires namespace_id."
  type        = bool
  default     = true
}

variable "namespace_id" {
  description = "Cloud Map private DNS namespace ID (used when enable_service_discovery is true)."
  type        = string
  default     = null
}

# ---------------------------------------------------------------------------
# Task definition
# ---------------------------------------------------------------------------
variable "image" {
  description = "Full image reference (repository:tag or repository@digest)."
  type        = string
}

variable "container_port" {
  description = "Port the container listens on (TCP)."
  type        = number
}

variable "cpu" {
  description = "Task CPU units (256 = 0.25 vCPU)."
  type        = number
  default     = 256
}

variable "memory" {
  description = "Task memory in MiB. Must be a valid Fargate combination with cpu."
  type        = number
  default     = 512
}

variable "cpu_architecture" {
  description = "X86_64 or ARM64. Must match the image."
  type        = string
  default     = "X86_64"

  validation {
    condition     = contains(["X86_64", "ARM64"], var.cpu_architecture)
    error_message = "cpu_architecture must be X86_64 or ARM64."
  }
}

variable "environment" {
  description = "Plain environment variables (non-secret)."
  type        = map(string)
  default     = {}
}

variable "secrets" {
  description = "Map of env var name => SSM parameter or Secrets Manager ARN, resolved by ECS at task start."
  type        = map(string)
  default     = {}
}

variable "secret_arn_patterns" {
  description = "SSM parameter ARNs/patterns the execution role may read (e.g. arn:...:parameter/metro/*). Every ARN in `secrets` must match one of them."
  type        = list(string)
  default     = []
}

variable "ecr_repository_arns" {
  description = "ECR repositories the execution role may pull from. Empty for public images (ECR Public is anonymous)."
  type        = list(string)
  default     = []
}

variable "command" {
  description = "Optional container command override."
  type        = list(string)
  default     = null
}

variable "health_check" {
  description = "Optional container health check. command is the ECS form, e.g. [\"CMD-SHELL\", \"curl -fs http://localhost:8761/actuator/health || exit 1\"]."
  type = object({
    command      = list(string)
    interval     = optional(number, 15)
    timeout      = optional(number, 5)
    retries      = optional(number, 3)
    start_period = optional(number, 60)
  })
  default = null
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days."
  type        = number
  default     = 7
}

# ---------------------------------------------------------------------------
# Service
# ---------------------------------------------------------------------------
variable "desired_count" {
  description = "Number of tasks."
  type        = number
  default     = 1
}

variable "capacity_provider" {
  description = "FARGATE (on-demand) or FARGATE_SPOT."
  type        = string
  default     = "FARGATE_SPOT"

  validation {
    condition     = contains(["FARGATE", "FARGATE_SPOT"], var.capacity_provider)
    error_message = "capacity_provider must be FARGATE or FARGATE_SPOT."
  }
}

variable "deployment_minimum_healthy_percent" {
  description = "Lower bound of running tasks during a deployment. 0 for single-instance stateful services (stop old, then start new)."
  type        = number
  default     = 100
}

variable "deployment_maximum_percent" {
  description = "Upper bound of running tasks during a deployment."
  type        = number
  default     = 200
}

variable "load_balancer_target_group_arn" {
  description = "Optional ALB target group (type ip) that ECS registers the tasks in, on container_port."
  type        = string
  default     = null
}

variable "health_check_grace_period_seconds" {
  description = "Seconds ECS ignores failing load balancer and container health checks after a task starts. Null leaves it unset (0)."
  type        = number
  default     = null
}

variable "wait_for_steady_state" {
  description = "Make terraform apply wait until the service is stable."
  type        = bool
  default     = false
}
