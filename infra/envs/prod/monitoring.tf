# ---------------------------------------------------------------------------
# Task 10: alarms and cost controls.
#   CloudWatch alarms (ALB 5xx, gateway 5xx, gateway unhealthy/healthy hosts,
#   RDS CPU, RDS free storage) and an AWS Budget ($50 / $100 actual, 100%
#   forecast) all notify the SNS topic metro-prod-alerts (email subscription).
#
# scripts/scale.ps1 / scale.sh disable the alarm actions on `down` (a stopped
# gateway would otherwise page you) and enable them again on `up`.
# ---------------------------------------------------------------------------
module "monitoring" {
  source = "../../modules/monitoring"

  name        = var.name
  alert_email = var.alert_email

  alb_arn_suffix          = module.alb.alb_arn_suffix
  target_group_arn_suffix = module.alb.target_group_arn_suffix
  rds_identifier          = module.rds.identifier

  budget_limit_usd            = var.budget_limit_usd
  budget_alert_thresholds_usd = var.budget_alert_thresholds_usd
}

locals {
  # Start order used by scale.ps1/scale.sh `up` (reversed for `down`):
  # platform first, then the services that register with Eureka.
  scale_groups = [
    [module.redis.service_name, module.rabbitmq.service_name, module.eureka.service_name],
    concat([for k in sort(keys(module.business)) : module.business[k].service_name], [module.gateway.service_name]),
  ]

  # desired_count Terraform sets on each ECS service; `up` restores exactly
  # these values. redis, rabbitmq and eureka use the ecs-service default (1).
  service_desired_counts = merge(
    {
      (module.redis.service_name)    = 1
      (module.rabbitmq.service_name) = 1
      (module.eureka.service_name)   = 1
      (module.gateway.service_name)  = var.gateway_desired_count
    },
    { for k, m in module.business : m.service_name => var.business_desired_count },
  )
}
