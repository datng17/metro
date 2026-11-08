module "network" {
  source = "../../modules/network"

  name              = var.name
  vpc_cidr          = var.vpc_cidr
  azs               = var.azs
  nat_instance_type = var.nat_instance_type
}

module "ecr" {
  source = "../../modules/ecr"

  repository_prefix    = "metro"
  services             = toset(var.services)
  image_tag_mutability = "IMMUTABLE"
  max_image_count      = 10
  force_delete         = var.ecr_force_delete
}

# ---------------------------------------------------------------------------
# Task 5: ECS cluster (needed by db-init), RDS, SSM secrets, db-init
# ---------------------------------------------------------------------------
module "ecs_cluster" {
  source = "../../modules/ecs-cluster"

  name           = var.name
  vpc_id         = module.network.vpc_id
  namespace_name = var.cloudmap_namespace
}

module "rds" {
  source = "../../modules/rds"

  name       = var.name
  vpc_id     = module.network.vpc_id
  subnet_ids = module.network.private_data_subnet_ids
  allowed_security_group_ids = {
    ecs_tasks = module.ecs_cluster.tasks_security_group_id
  }

  engine_version        = "17"
  instance_class        = "db.t4g.micro"
  allocated_storage     = 20
  backup_retention_days = 1
  deletion_protection   = var.rds_deletion_protection
  skip_final_snapshot   = var.rds_skip_final_snapshot
}

module "secrets" {
  source = "../../modules/ssm-secrets"

  path_prefix = "/metro"

  generated_secrets = {
    DB_PASSWORD          = { length = 32 }
    RABBITMQ_PASSWORD    = { length = 32 }
    API_KEY              = { length = 40 }
    TICKET_QR_SECRET_KEY = { length = 48 }
    # The services decode it with Decoders.BASE64 -> 64 random bytes (HS512-capable).
    JWT_SECRET_KEY = { length = 64, base64 = true }
  }

  placeholder_secrets = var.optional_secret_names

  # Created by hand so the Atlas password never enters Terraform state:
  #   aws ssm put-parameter --name /metro/MONGODB_URI --type SecureString --value "<uri>"
  external_secrets = ["MONGODB_URI"]
}

module "db_init" {
  source = "../../modules/db-init"

  name                       = var.name
  db_host                    = module.rds.address
  db_port                    = module.rds.port
  master_user_secret_arn     = module.rds.master_user_secret_arn
  app_db_username            = var.db_app_username
  app_password_parameter_arn = module.secrets.parameter_arns["DB_PASSWORD"]
  databases                  = var.databases

  cluster_name       = module.ecs_cluster.cluster_name
  subnet_ids         = module.network.private_app_subnet_ids
  security_group_ids = [module.ecs_cluster.tasks_security_group_id]
}

# ---------------------------------------------------------------------------
# Task 6: platform layer (redis, rabbitmq, eureka) on ECS + Cloud Map
#   redis.metro.local:6379, rabbitmq.metro.local:5672, eureka.metro.local:8761
# ---------------------------------------------------------------------------

# Image of each of our services: the tag from var.image_tags, otherwise the
# most recently pushed image in metro/<svc>. Tags are immutable (Task 4).
data "aws_ecr_image" "app" {
  for_each = toset(var.services)

  repository_name = module.ecr.repository_names[each.key]
  image_tag       = lookup(var.image_tags, each.key, null)
  most_recent     = contains(keys(var.image_tags), each.key) ? null : true
}

locals {
  app_images = {
    for svc, img in data.aws_ecr_image.app :
    svc => "${module.ecr.repository_urls[svc]}:${lookup(var.image_tags, svc, try(img.image_tags[0], ""))}"
  }

  # Arguments shared by every ECS service.
  ecs_common = {
    cluster_arn               = module.ecs_cluster.cluster_arn
    vpc_id                    = module.network.vpc_id
    subnet_ids                = module.network.private_app_subnet_ids
    shared_security_group_ids = [module.ecs_cluster.tasks_security_group_id]
    namespace_id              = module.ecs_cluster.namespace_id
    # Any ECS task (they all carry the shared tasks SG) may call the service.
    ingress_security_group_ids = { ecs_tasks = module.ecs_cluster.tasks_security_group_id }
  }

  eureka_url = "http://eureka.${module.ecs_cluster.namespace_name}:8761/eureka/"
}

# Redis 7.2 (no persistence, no password: reachable only from ECS tasks).
# Pulled from the ECR Public mirror of Docker Hub's official image, which has
# no anonymous pull rate limit per NAT IP.
module "redis" {
  source = "../../modules/ecs-service"

  name_prefix  = var.name
  service_name = "redis"
  image        = "public.ecr.aws/docker/library/redis:7.2"

  container_port = 6379
  cpu            = 256
  memory         = 512

  capacity_provider = "FARGATE_SPOT"
  # Single instance: stop the old task before starting the new one.
  deployment_minimum_healthy_percent = 0
  deployment_maximum_percent         = 100

  health_check = {
    command      = ["CMD-SHELL", "redis-cli ping | grep -q PONG"]
    start_period = 10
  }

  cluster_arn                = local.ecs_common.cluster_arn
  vpc_id                     = local.ecs_common.vpc_id
  subnet_ids                 = local.ecs_common.subnet_ids
  shared_security_group_ids  = local.ecs_common.shared_security_group_ids
  namespace_id               = local.ecs_common.namespace_id
  ingress_security_group_ids = local.ecs_common.ingress_security_group_ids
}

# RabbitMQ 3 with the management plugin (UI on 15672: reach it with ECS Exec
# port forwarding, it is not opened in the security group).
module "rabbitmq" {
  source = "../../modules/ecs-service"

  name_prefix  = var.name
  service_name = "rabbitmq"
  image        = "public.ecr.aws/docker/library/rabbitmq:3-management"

  container_port = 5672
  cpu            = 256
  memory         = 1024

  capacity_provider                  = "FARGATE_SPOT"
  deployment_minimum_healthy_percent = 0
  deployment_maximum_percent         = 100

  environment = {
    RABBITMQ_DEFAULT_USER = var.rabbitmq_username
  }
  secrets = {
    RABBITMQ_DEFAULT_PASS = module.secrets.parameter_arns["RABBITMQ_PASSWORD"]
  }
  secret_arn_patterns = [module.secrets.parameter_arn_pattern]

  # ECS runs health checks as root (the image has no USER). Run the CLI as the
  # rabbitmq user: as root it can create /var/lib/rabbitmq/.erlang.cookie owned
  # by root during boot, and the broker (uid 999) then fails with eacces.
  health_check = {
    command      = ["CMD-SHELL", "gosu rabbitmq rabbitmq-diagnostics -q ping"]
    interval     = 30
    timeout      = 10
    start_period = 60
  }

  cluster_arn                = local.ecs_common.cluster_arn
  vpc_id                     = local.ecs_common.vpc_id
  subnet_ids                 = local.ecs_common.subnet_ids
  shared_security_group_ids  = local.ecs_common.shared_security_group_ids
  namespace_id               = local.ecs_common.namespace_id
  ingress_security_group_ids = local.ecs_common.ingress_security_group_ids
}

# Eureka server (on-demand: every service depends on it).
module "eureka" {
  source = "../../modules/ecs-service"

  name_prefix         = var.name
  service_name        = "eureka"
  image               = local.app_images["eureka-service"]
  ecr_repository_arns = [module.ecr.repository_arns["eureka-service"]]

  container_port = 8761
  cpu            = 512
  memory         = 1024

  capacity_provider                  = "FARGATE"
  deployment_minimum_healthy_percent = 0
  deployment_maximum_percent         = 100

  environment = {
    SPRING_PROFILES_ACTIVE = "aws"
    EUREKA_HOSTNAME        = "eureka.${module.ecs_cluster.namespace_name}"
  }

  health_check = {
    command      = ["CMD-SHELL", "curl -fs http://localhost:8761/actuator/health || exit 1"]
    start_period = 120
  }

  cluster_arn                = local.ecs_common.cluster_arn
  vpc_id                     = local.ecs_common.vpc_id
  subnet_ids                 = local.ecs_common.subnet_ids
  shared_security_group_ids  = local.ecs_common.shared_security_group_ids
  namespace_id               = local.ecs_common.namespace_id
  ingress_security_group_ids = local.ecs_common.ingress_security_group_ids
}

# ---------------------------------------------------------------------------
# Task 7: ALB (HTTPS with the ACM certificate) -> gateway on on-demand Fargate
#   https://metro.test.name.vn -> Cloudflare DNS-only CNAME -> ALB :443
#   -> target group (ip, 4003, /actuator/health) -> gateway tasks
# ---------------------------------------------------------------------------
data "aws_caller_identity" "current" {}

locals {
  acm_certificate_arn = coalesce(
    var.acm_certificate_arn,
    "arn:aws:acm:${var.region}:${data.aws_caller_identity.current.account_id}:certificate/${var.acm_certificate_id}",
  )
}

module "alb" {
  source = "../../modules/alb"

  name            = var.name
  vpc_id          = module.network.vpc_id
  subnet_ids      = module.network.public_subnet_ids
  certificate_arn = local.acm_certificate_arn
  ssl_policy      = "ELBSecurityPolicy-TLS13-1-2-2021-06"

  target_name       = "gateway"
  target_port       = 4003
  health_check_path = "/actuator/health"
}

# The ALB may only send traffic to the gateway tasks, on 4003.
resource "aws_vpc_security_group_egress_rule" "alb_to_gateway" {
  security_group_id            = module.alb.security_group_id
  description                  = "ALB to gateway 4003"
  ip_protocol                  = "tcp"
  from_port                    = 4003
  to_port                      = 4003
  referenced_security_group_id = module.gateway.security_group_id
}

# Spring Cloud Gateway (on-demand: it is the only public entry point).
# Routes lb://<service> through Eureka; each task registers its own IP.
module "gateway" {
  source = "../../modules/ecs-service"

  name_prefix         = var.name
  service_name        = "gateway"
  image               = local.app_images["gateway-service"]
  ecr_repository_arns = [module.ecr.repository_arns["gateway-service"]]

  container_port = 4003
  cpu            = 512
  memory         = 1024
  desired_count  = var.gateway_desired_count

  capacity_provider = "FARGATE"
  # Rolling deploy behind the ALB: start the new task, wait until the target
  # group reports it healthy, then drain and stop the old one.
  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200

  load_balancer_target_group_arn    = module.alb.target_group_arn
  health_check_grace_period_seconds = 180

  environment = {
    SPRING_PROFILES_ACTIVE = "aws"
    EUREKA_URL             = local.eureka_url
    REDIS_HOST             = "redis.${module.ecs_cluster.namespace_name}"
    REDIS_PORT             = "6379"
    CORS_ALLOWED_ORIGINS   = var.cors_allowed_origins
    # cronjob-service has no Eureka client; module.business["cronjob"] registers
    # it in Cloud Map as cronjob.<namespace>.
    CRONJOB_SERVICE_URI = "http://cronjob.${module.ecs_cluster.namespace_name}:4010"
  }
  secrets = {
    JWT_SECRET_KEY = module.secrets.parameter_arns["JWT_SECRET_KEY"]
    API_KEY        = module.secrets.parameter_arns["API_KEY"]
  }
  secret_arn_patterns = [module.secrets.parameter_arn_pattern]

  health_check = {
    command      = ["CMD-SHELL", "curl -fs http://localhost:4003/actuator/health || exit 1"]
    start_period = 120
  }

  # Nothing inside the VPC calls the gateway by DNS, so no Cloud Map entry.
  enable_service_discovery = false

  cluster_arn               = local.ecs_common.cluster_arn
  vpc_id                    = local.ecs_common.vpc_id
  subnet_ids                = local.ecs_common.subnet_ids
  shared_security_group_ids = local.ecs_common.shared_security_group_ids
  # Only the ALB may reach 4003 (not the other ECS tasks).
  ingress_security_group_ids = { alb = module.alb.security_group_id }
}
