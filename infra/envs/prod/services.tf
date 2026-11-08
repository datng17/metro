# ---------------------------------------------------------------------------
# Task 8: business services on Fargate Spot, wired through Eureka (gateway
# routes lb://<service>), Cloud Map (<name>.metro.local for Feign URLs and
# cronjob) and the shared tasks SG (RDS, redis, rabbitmq, eureka and every
# service port accept it).
#
# Each entry of local.business_services becomes one module.business["<name>"].
# The key is the ECS service, container and Cloud Map name; values match the
# service's application-aws.yml.
# ---------------------------------------------------------------------------
locals {
  ns = module.ecs_cluster.namespace_name

  # Base URLs for the Feign clients (the aws profiles append the paths).
  internal_urls = {
    user    = "http://user.${local.ns}:4007"
    station = "http://station.${local.ns}:4004"
    ticket  = "http://ticket.${local.ns}:4005"
  }

  env_eureka = {
    SPRING_PROFILES_ACTIVE = "aws"
    EUREKA_URL             = local.eureka_url
  }

  env_db = {
    DB_HOST = module.rds.address
    DB_PORT = tostring(module.rds.port)
    DB_USER = var.db_app_username
  }

  env_redis = {
    REDIS_HOST = "redis.${local.ns}"
    REDIS_PORT = "6379"
  }

  env_rabbit = {
    RABBITMQ_HOST = "rabbitmq.${local.ns}"
    RABBITMQ_PORT = "5672"
    RABBITMQ_USER = var.rabbitmq_username
  }

  # Names of /metro/* SSM parameters; each becomes an env var of the same name.
  secrets_app    = ["JWT_SECRET_KEY", "API_KEY"]
  secrets_db     = ["DB_PASSWORD"]
  secrets_rabbit = ["RABBITMQ_PASSWORD"]

  business_services = {
    auth = {
      repository  = "auth-service"
      port        = 4006
      health_path = "/api/v1/actuator/health"
      environment = merge(local.env_eureka, local.env_redis, {
        USER_SERVICE_URL = local.internal_urls.user
      })
      secrets = concat(local.secrets_app, [
        "GOOGLE_CLIENT_ID", "GOOGLE_CLIENT_SECRET",
        "FACEBOOK_CLIENT_ID", "FACEBOOK_CLIENT_SECRET",
      ])
    }

    user = {
      repository  = "user-service"
      port        = 4007
      health_path = "/api/v1/actuator/health"
      environment = merge(local.env_eureka, local.env_db, local.env_redis, {
        DB_NAME = "userdb"
      })
      secrets = concat(local.secrets_app, local.secrets_db, [
        "OPENAI_API_KEY", "POCKETBASE_EMAIL", "POCKETBASE_PASSWORD",
      ])
    }

    station = {
      repository  = "station-service"
      port        = 4004
      health_path = "/actuator/health"
      environment = merge(local.env_eureka, local.env_db, local.env_rabbit, {
        DB_NAME          = "stationdb"
        MONGODB_DATABASE = "Bus"
      })
      # MONGODB_URI is created by hand (aws ssm put-parameter), never by Terraform.
      secrets = concat(local.secrets_app, local.secrets_db, local.secrets_rabbit, ["MONGODB_URI"])
    }

    ticket = {
      repository  = "ticket-service"
      port        = 4005
      health_path = "/actuator/health"
      environment = merge(local.env_eureka, local.env_db, local.env_rabbit, {
        DB_NAME             = "ticketdb"
        USER_SERVICE_URL    = local.internal_urls.user
        STATION_SERVICE_URL = local.internal_urls.station
      })
      secrets = concat(local.secrets_app, local.secrets_db, local.secrets_rabbit, ["TICKET_QR_SECRET_KEY"])
    }

    order = {
      repository  = "order-service"
      port        = 4009
      health_path = "/actuator/health"
      environment = merge(local.env_eureka, local.env_db, local.env_rabbit, {
        DB_NAME            = "orderdb"
        TICKET_SERVICE_URL = local.internal_urls.ticket
      })
      secrets = concat(local.secrets_app, local.secrets_db, local.secrets_rabbit, [
        "PAYPAL_CLIENT_ID", "PAYPAL_CLIENT_SECRET",
        "STRIPE_SECRET_KEY", "STRIPE_PUBLISHABLE_KEY",
        "VNPAY_TMN_CODE", "VNPAY_SECRET_KEY",
      ])
    }

    notification = {
      repository  = "notification-service"
      port        = 4008
      health_path = "/api/v1/actuator/health"
      environment = merge(local.env_eureka, local.env_db, local.env_redis, local.env_rabbit, {
        DB_NAME          = "notificationdb"
        USER_SERVICE_URL = local.internal_urls.user
        FIREBASE_ENABLED = "false"
      })
      secrets = concat(local.secrets_app, local.secrets_db, local.secrets_rabbit, [
        "SMTP_USERNAME", "SMTP_PASSWORD",
      ])
    }

    # No Eureka client: the gateway reaches it at cronjob.<namespace>:4010
    # (CRONJOB_SERVICE_URI). Context path /api.
    cronjob = {
      repository  = "cronjob-service"
      port        = 4010
      health_path = "/api/actuator/health"
      environment = merge(local.env_db, {
        SPRING_PROFILES_ACTIVE = "aws"
        DB_NAME                = "cronjobdb"
        TICKET_SERVICE_URL     = local.internal_urls.ticket
        STATION_SERVICE_URL    = local.internal_urls.station
      })
      secrets = concat(["API_KEY"], local.secrets_db)
    }
  }
}

module "business" {
  source   = "../../modules/ecs-service"
  for_each = local.business_services

  name_prefix         = var.name
  service_name        = each.key
  image               = local.app_images[each.value.repository]
  ecr_repository_arns = [module.ecr.repository_arns[each.value.repository]]

  container_port = each.value.port
  cpu            = 512
  memory         = 1024
  desired_count  = var.business_desired_count

  capacity_provider = "FARGATE_SPOT"
  # Rolling deploy: start the new task, wait until it is healthy, stop the old one.
  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200
  health_check_grace_period_seconds  = 180

  environment         = each.value.environment
  secrets             = { for name in each.value.secrets : name => module.secrets.parameter_arns[name] }
  secret_arn_patterns = [module.secrets.parameter_arn_pattern]

  health_check = {
    command      = ["CMD-SHELL", "curl -fs http://localhost:${each.value.port}${each.value.health_path} || exit 1"]
    interval     = 30
    start_period = 120
  }

  # <name>.metro.local for Feign clients and the gateway's cronjob route.
  enable_service_discovery = true

  cluster_arn               = local.ecs_common.cluster_arn
  vpc_id                    = local.ecs_common.vpc_id
  subnet_ids                = local.ecs_common.subnet_ids
  shared_security_group_ids = local.ecs_common.shared_security_group_ids
  namespace_id              = local.ecs_common.namespace_id
  # Gateway and service-to-service Feign calls: every task carries the shared tasks SG.
  ingress_security_group_ids = local.ecs_common.ingress_security_group_ids
}
