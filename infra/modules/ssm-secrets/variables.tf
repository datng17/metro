variable "path_prefix" {
  description = "Parameter path prefix, with a leading slash and no trailing slash."
  type        = string
  default     = "/metro"

  validation {
    condition     = can(regex("^(/[A-Za-z0-9_.-]+)+$", var.path_prefix))
    error_message = "path_prefix must look like /metro (leading slash, no trailing slash)."
  }
}

variable "generated_secrets" {
  description = "Secrets generated with random_password, keyed by env var name. base64 = true stores base64(random string). Bump version to rotate."
  type = map(object({
    length  = number
    base64  = optional(bool, false)
    version = optional(number, 1)
  }))
  default = {}
}

variable "placeholder_secrets" {
  description = "Optional third-party keys created with a placeholder value and set manually later."
  type        = set(string)
  default     = []
}

variable "placeholder_value" {
  description = "Value written to new placeholder parameters. Matches the aws profile defaults."
  type        = string
  default     = "dummy"
}

variable "external_secrets" {
  description = "Parameters created outside Terraform (aws ssm put-parameter). Terraform only builds their ARNs."
  type        = set(string)
  default     = []
}
