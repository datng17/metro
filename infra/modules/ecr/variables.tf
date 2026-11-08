variable "repository_prefix" {
  description = "Namespace prefix for the repositories. Each repository is named <prefix>/<service>."
  type        = string
  default     = "metro"

  validation {
    condition     = can(regex("^[a-z0-9]+(?:[._-][a-z0-9]+)*$", var.repository_prefix))
    error_message = "repository_prefix must be lowercase alphanumerics, optionally separated by '.', '_' or '-'."
  }
}

variable "services" {
  description = "Service names. One repository <prefix>/<service> is created per entry."
  type        = set(string)

  validation {
    condition     = length(var.services) > 0 && alltrue([for s in var.services : can(regex("^[a-z0-9]+(?:-[a-z0-9]+)*$", s))])
    error_message = "services must be a non-empty set of lowercase, dash-separated names (e.g. auth-service)."
  }
}

variable "image_tag_mutability" {
  description = "Tag mutability of every repository. IMMUTABLE prevents a pushed tag (git SHA) from being overwritten."
  type        = string
  default     = "IMMUTABLE"

  validation {
    condition     = contains(["MUTABLE", "IMMUTABLE"], var.image_tag_mutability)
    error_message = "image_tag_mutability must be MUTABLE or IMMUTABLE."
  }
}

variable "max_image_count" {
  description = "Number of most recent images kept per repository. Older images are expired by the lifecycle policy."
  type        = number
  default     = 10

  validation {
    condition     = var.max_image_count >= 1 && floor(var.max_image_count) == var.max_image_count
    error_message = "max_image_count must be a positive whole number."
  }
}

variable "force_delete" {
  description = "Allow terraform destroy to delete repositories that still contain images."
  type        = bool
  default     = false
}
