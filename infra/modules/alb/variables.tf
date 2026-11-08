variable "name" {
  description = "Name prefix (e.g. metro-prod). The ALB is <name>-alb, the target group <name>-<target_name>."
  type        = string
}

variable "vpc_id" {
  description = "VPC of the ALB and target group."
  type        = string
}

variable "subnet_ids" {
  description = "Public subnets for the internet-facing ALB (at least two AZs)."
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) >= 2
    error_message = "An ALB needs subnets in at least two availability zones."
  }
}

variable "certificate_arn" {
  description = "ACM certificate ARN for the HTTPS listener (same region as the ALB)."
  type        = string

  validation {
    condition     = can(regex("^arn:aws:acm:[a-z0-9-]+:[0-9]{12}:certificate/[0-9a-f-]+$", var.certificate_arn))
    error_message = "certificate_arn must be an ACM certificate ARN."
  }
}

variable "ssl_policy" {
  description = "TLS security policy of the HTTPS listener."
  type        = string
  default     = "ELBSecurityPolicy-TLS13-1-2-2021-06"
}

variable "ingress_cidr_ipv4" {
  description = "IPv4 ranges allowed to reach ports 80 and 443."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

# ---------------------------------------------------------------------------
# Target group (one backend: the gateway)
# ---------------------------------------------------------------------------
variable "target_name" {
  description = "Short name of the backend (used in the target group name)."
  type        = string
  default     = "gateway"
}

variable "target_port" {
  description = "Container port of the targets."
  type        = number
  default     = 4003
}

variable "health_check_path" {
  description = "HTTP path the ALB probes on each target."
  type        = string
  default     = "/actuator/health"
}

variable "health_check_matcher" {
  description = "HTTP codes that count as healthy."
  type        = string
  default     = "200"
}

variable "deregistration_delay" {
  description = "Seconds to drain in-flight requests from a target before it is removed."
  type        = number
  default     = 30
}

variable "idle_timeout" {
  description = "ALB idle connection timeout in seconds."
  type        = number
  default     = 60
}

variable "deletion_protection" {
  description = "Deletion protection on the ALB. Leave false so terraform destroy works."
  type        = bool
  default     = false
}
