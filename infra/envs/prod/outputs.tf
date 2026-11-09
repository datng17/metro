output "nat_eip" {
  description = "Fixed egress IP of the VPC. Add it as <ip>/32 in MongoDB Atlas Network Access."
  value       = module.network.nat_eip
}

output "vpc_id" {
  description = "ID of the prod VPC."
  value       = module.network.vpc_id
}

output "public_subnet_ids" {
  description = "Public subnet IDs."
  value       = module.network.public_subnet_ids
}

output "private_app_subnet_ids" {
  description = "Private application subnet IDs."
  value       = module.network.private_app_subnet_ids
}

output "private_data_subnet_ids" {
  description = "Private data subnet IDs."
  value       = module.network.private_data_subnet_ids
}

output "ecr_registry_url" {
  description = "ECR registry host for docker login."
  value       = module.ecr.registry_url
}

output "ecr_repository_urls" {
  description = "Map of service name to ECR repository URL."
  value       = module.ecr.repository_urls
}

output "ecs_cluster_name" {
  description = "ECS cluster name."
  value       = module.ecs_cluster.cluster_name
}

output "ecs_tasks_security_group_id" {
  description = "Shared security group of all ECS tasks (the only source RDS accepts)."
  value       = module.ecs_cluster.tasks_security_group_id
}

output "rds_address" {
  description = "RDS endpoint (DB_HOST)."
  value       = module.rds.address
}

output "rds_port" {
  description = "RDS port (DB_PORT)."
  value       = module.rds.port
}

output "rds_master_user_secret_arn" {
  description = "Secrets Manager ARN of the RDS-managed master credentials."
  value       = module.rds.master_user_secret_arn
}

output "db_app_username" {
  description = "Login role used by the services (DB_USER)."
  value       = var.db_app_username
}

output "ssm_parameter_arns" {
  description = "Map of env var name to SSM parameter ARN."
  value       = module.secrets.parameter_arns
}

output "db_init_task_definition_arn" {
  description = "db-init task definition ARN."
  value       = module.db_init.task_definition_arn
}

output "db_init_log_group" {
  description = "db-init CloudWatch log group."
  value       = module.db_init.log_group_name
}

output "db_init_run_task_command" {
  description = "Command that starts the db-init task."
  value       = module.db_init.run_task_command
}

output "cloudmap_namespace" {
  description = "Cloud Map private DNS namespace."
  value       = module.ecs_cluster.namespace_name
}

output "eureka_url" {
  description = "EUREKA_URL for the Eureka clients."
  value       = local.eureka_url
}

output "platform_endpoints" {
  description = "Private endpoints of the platform services (REDIS_HOST, RABBITMQ_HOST, Eureka)."
  value = {
    redis    = "redis.${module.ecs_cluster.namespace_name}:6379"
    rabbitmq = "rabbitmq.${module.ecs_cluster.namespace_name}:5672"
    eureka   = "eureka.${module.ecs_cluster.namespace_name}:8761"
  }
}

output "platform_images" {
  description = "Images deployed for the platform services."
  value = {
    redis    = "public.ecr.aws/docker/library/redis:7.2"
    rabbitmq = "public.ecr.aws/docker/library/rabbitmq:3-management"
    eureka   = local.app_images["eureka-service"]
  }
}

output "ecs_services" {
  description = "ECS service names in the cluster."
  value = concat(
    [module.redis.service_name, module.rabbitmq.service_name, module.eureka.service_name, module.gateway.service_name],
    [for k in sort(keys(module.business)) : module.business[k].service_name],
  )
}

output "business_services" {
  description = "Business services: Cloud Map endpoint, log group and image."
  value = {
    for k, m in module.business : k => {
      endpoint  = "${k}.${module.ecs_cluster.namespace_name}:${local.business_services[k].port}"
      log_group = m.log_group_name
      image     = local.app_images[local.business_services[k].repository]
    }
  }
}

output "alb_dns_name" {
  description = "ALB DNS name. Create the Cloudflare DNS-only (grey cloud) CNAME metro -> this value."
  value       = module.alb.dns_name
}

output "alb_security_group_id" {
  description = "ALB security group (the only source the gateway accepts on 4003)."
  value       = module.alb.security_group_id
}

output "gateway_target_group_arn" {
  description = "Target group of the gateway tasks (for aws elbv2 describe-target-health)."
  value       = module.alb.target_group_arn
}

output "acm_certificate_arn" {
  description = "ACM certificate on the HTTPS listener."
  value       = local.acm_certificate_arn
}

output "public_url" {
  description = "Public HTTPS endpoint once the Cloudflare CNAME exists."
  value       = "https://${var.domain_name}"
}

output "cloudflare_dns_record" {
  description = "Record to create in Cloudflare (Proxy status: DNS only)."
  value = {
    type    = "CNAME"
    name    = split(".", var.domain_name)[0]
    target  = module.alb.dns_name
    proxied = false
  }
}

output "gateway_image" {
  description = "Image deployed for the gateway."
  value       = local.app_images["gateway-service"]
}

output "eureka_exec_command" {
  description = "ECS Exec into eureka (needs the Session Manager plugin). Replace <task-id>, or use the helper in the Task 6 notes."
  value       = "aws ecs execute-command --cluster ${module.ecs_cluster.cluster_name} --task <task-id> --container ${module.eureka.container_name} --interactive --command \"curl -s localhost:8761/actuator/health\""
}

output "github_deploy_role_arn" {
  description = "Set as the GitHub repository variable AWS_ROLE_ARN (used by the CD workflows)."
  value       = module.github_oidc.deploy_role_arn
}

output "github_deploy_role_subject" {
  description = "The only OIDC subject the deploy role trusts."
  value       = module.github_oidc.deploy_role_subject
}

output "github_plan_role_arn" {
  description = "Set as the GitHub repository variable AWS_PLAN_ROLE_ARN (used by infra-ci.yml), or null."
  value       = module.github_oidc.plan_role_arn
}

output "rds_identifier" {
  description = "RDS instance identifier (aws rds stop-db-instance / start-db-instance)."
  value       = module.rds.identifier
}

output "alerts_sns_topic_arn" {
  description = "SNS topic of the alarms and the budget. Confirm the subscription email."
  value       = module.monitoring.sns_topic_arn
}

output "alarm_names" {
  description = "CloudWatch alarms that notify the alerts topic."
  value       = module.monitoring.alarm_names
}

output "budget_name" {
  description = "AWS Budgets monthly cost budget."
  value       = module.monitoring.budget_name
}

output "scale_config" {
  description = "Read by scripts/scale.ps1 and scripts/scale.sh: cluster, start order, Terraform desired counts, RDS and alarms."
  value = {
    cluster        = module.ecs_cluster.cluster_name
    groups         = local.scale_groups
    desired_counts = local.service_desired_counts
    rds_identifier = module.rds.identifier
    alarm_names    = module.monitoring.alarm_names
    health_url     = "https://${var.domain_name}/actuator/health"
  }
}
