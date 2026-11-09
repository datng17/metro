variable "name" {
  description = "Name prefix for the topic, alarms and budget."
  type        = string
}

variable "alert_email" {
  description = "Email subscribed to the alerts topic (confirm the AWS email). Null creates the topic without a subscription."
  type        = string
  default     = null

  validation {
    condition     = var.alert_email == null || can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", var.alert_email))
    error_message = "alert_email must be a valid email address or null."
  }
}

# ---------------------------------------------------------------------------
# ALB / gateway target group
# ---------------------------------------------------------------------------
variable "alb_arn_suffix" {
  description = "ALB ARN suffix (CloudWatch LoadBalancer dimension)."
  type        = string
}

variable "target_group_arn_suffix" {
  description = "Gateway target group ARN suffix (CloudWatch TargetGroup dimension)."
  type        = string
}

variable "alb_5xx_threshold" {
  description = "Alarm when the ALB itself returns at least this many 5xx (502/503/504) in 5 minutes."
  type        = number
  default     = 5
}

variable "target_5xx_threshold" {
  description = "Alarm when the gateway returns at least this many 5xx in 5 minutes."
  type        = number
  default     = 10
}

# ---------------------------------------------------------------------------
# RDS
# ---------------------------------------------------------------------------
variable "rds_identifier" {
  description = "RDS instance identifier (CloudWatch DBInstanceIdentifier dimension)."
  type        = string
}

variable "rds_cpu_threshold_percent" {
  description = "Alarm when RDS average CPU stays above this for 15 minutes."
  type        = number
  default     = 80
}

variable "rds_free_storage_threshold_bytes" {
  description = "Alarm when RDS free storage drops below this many bytes (default 2 GiB of 20 GB)."
  type        = number
  default     = 2147483648
}

# ---------------------------------------------------------------------------
# Budget
# ---------------------------------------------------------------------------
variable "budget_limit_usd" {
  description = "Monthly cost budget for the whole account, in USD."
  type        = number
  default     = 100
}

variable "budget_alert_thresholds_usd" {
  description = "Actual-spend amounts (USD) that notify the alerts topic."
  type        = list(number)
  default     = [50, 100]
}
