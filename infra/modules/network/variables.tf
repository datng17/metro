variable "name" {
  description = "Name prefix for all network resources (e.g. metro-prod)."
  type        = string
}

variable "vpc_cidr" {
  description = "IPv4 CIDR block of the VPC."
  type        = string
  default     = "10.20.0.0/16"

  validation {
    condition     = can(cidrnetmask(var.vpc_cidr)) && endswith(var.vpc_cidr, "/16")
    error_message = "vpc_cidr must be a valid /16 IPv4 CIDR (the subnet layout assumes a /16)."
  }
}

variable "azs" {
  description = "Exactly two availability zones to spread the subnets across."
  type        = list(string)

  validation {
    condition     = length(var.azs) == 2
    error_message = "azs must contain exactly 2 availability zones."
  }
}

variable "nat_instance_type" {
  description = "EC2 instance type for the fck-nat instance."
  type        = string
  default     = "t4g.nano"
}
