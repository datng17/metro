variable "name" {
  description = "Name prefix for the IAM roles (e.g. metro-prod)."
  type        = string
}

variable "github_repository" {
  description = "GitHub repository allowed to assume the roles, as <owner>/<repo>."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$", var.github_repository))
    error_message = "github_repository must look like <owner>/<repo>."
  }
}

variable "deploy_branch" {
  description = "Only workflow runs on this branch may assume the deploy role."
  type        = string
  default     = "main-deployment"
}

variable "create_oidc_provider" {
  description = "Create the token.actions.githubusercontent.com OIDC provider. Set to false if the account already has one (only one per URL is allowed)."
  type        = bool
  default     = true
}

variable "ecr_repository_arns" {
  description = "ECR repositories the deploy role may push to (metro/<svc>)."
  type        = list(string)
}

variable "ecs_service_arns" {
  description = "ECS services the deploy role may describe and update."
  type        = list(string)
}

variable "pass_role_arns" {
  description = "Task and execution roles the deploy role may pass to ECS in new task definitions."
  type        = list(string)
}

variable "enable_plan_role" {
  description = "Create a read-only role that pull_request runs can assume for terraform plan."
  type        = bool
  default     = true
}
