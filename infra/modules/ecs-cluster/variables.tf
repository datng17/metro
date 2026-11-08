variable "name" {
  description = "Cluster name, also used as the prefix of the shared task security group."
  type        = string
}

variable "vpc_id" {
  description = "VPC that the shared task security group belongs to."
  type        = string
}

variable "namespace_name" {
  description = "Cloud Map private DNS namespace for service discovery."
  type        = string
  default     = "metro.local"
}
