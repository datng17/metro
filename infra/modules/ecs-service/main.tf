# ---------------------------------------------------------------------------
# One ECS Fargate service: log group, IAM roles, security group, Cloud Map
# registration, task definition and service (rolling deploy with the
# deployment circuit breaker, ECS Exec enabled).
# ---------------------------------------------------------------------------
data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

locals {
  full_name = "${var.name_prefix}-${var.service_name}"
  region    = data.aws_region.current.region
  account   = data.aws_caller_identity.current.account_id
}

# ---------------------------------------------------------------------------
# Logs
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "this" {
  name              = "/ecs/${var.name_prefix}/${var.service_name}"
  retention_in_days = var.log_retention_days
}

# ---------------------------------------------------------------------------
# IAM
#   execution role: used by the ECS agent to pull the image, write logs and
#                   resolve `secrets` (only the given /metro/* parameters).
#   task role:      used by the application; only the ssmmessages actions that
#                   ECS Exec needs.
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account]
    }

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:aws:ecs:${local.region}:${local.account}:*"]
    }
  }
}

resource "aws_iam_role" "execution" {
  name               = "${local.full_name}-execution"
  assume_role_policy = data.aws_iam_policy_document.assume.json
}

data "aws_iam_policy_document" "execution" {
  statement {
    sid       = "Logs"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.this.arn}:*"]
  }

  dynamic "statement" {
    for_each = length(var.ecr_repository_arns) > 0 ? [1] : []

    content {
      sid       = "EcrAuth"
      actions   = ["ecr:GetAuthorizationToken"]
      resources = ["*"] # this action does not support resource-level permissions
    }
  }

  dynamic "statement" {
    for_each = length(var.ecr_repository_arns) > 0 ? [1] : []

    content {
      sid = "EcrPull"
      actions = [
        "ecr:BatchCheckLayerAvailability",
        "ecr:BatchGetImage",
        "ecr:GetDownloadUrlForLayer",
      ]
      resources = var.ecr_repository_arns
    }
  }

  # SecureStrings use the AWS-managed key alias/aws/ssm, so no kms:Decrypt grant is needed.
  dynamic "statement" {
    for_each = length(var.secret_arn_patterns) > 0 ? [1] : []

    content {
      sid       = "ReadSecrets"
      actions   = ["ssm:GetParameters"]
      resources = var.secret_arn_patterns
    }
  }
}

resource "aws_iam_role_policy" "execution" {
  name   = "execution"
  role   = aws_iam_role.execution.id
  policy = data.aws_iam_policy_document.execution.json
}

resource "aws_iam_role" "task" {
  name               = "${local.full_name}-task"
  assume_role_policy = data.aws_iam_policy_document.assume.json
}

data "aws_iam_policy_document" "task" {
  statement {
    sid = "EcsExec"
    actions = [
      "ssmmessages:CreateControlChannel",
      "ssmmessages:CreateDataChannel",
      "ssmmessages:OpenControlChannel",
      "ssmmessages:OpenDataChannel",
    ]
    resources = ["*"] # ssmmessages does not support resource-level permissions
  }
}

resource "aws_iam_role_policy" "task" {
  name   = "ecs-exec"
  role   = aws_iam_role.task.id
  policy = data.aws_iam_policy_document.task.json
}

# ---------------------------------------------------------------------------
# Security group: container_port from the listed SGs only. No egress rules;
# outbound traffic is allowed by the shared tasks SG (rules are unioned).
# ---------------------------------------------------------------------------
resource "aws_security_group" "this" {
  name        = local.full_name
  description = "${local.full_name}: tcp ${var.container_port} from allowed SGs"
  vpc_id      = var.vpc_id

  tags = {
    Name = local.full_name
  }
}

resource "aws_vpc_security_group_ingress_rule" "this" {
  for_each = var.ingress_security_group_ids

  security_group_id            = aws_security_group.this.id
  description                  = "${var.service_name} ${var.container_port} from ${each.key}"
  ip_protocol                  = "tcp"
  from_port                    = var.container_port
  to_port                      = var.container_port
  referenced_security_group_id = each.value
}

# ---------------------------------------------------------------------------
# Cloud Map: <service_name>.<namespace> -> A records of the running task IPs.
# ECS registers and deregisters the tasks; unhealthy tasks are removed.
# ---------------------------------------------------------------------------
resource "aws_service_discovery_service" "this" {
  # A plain bool, so count is known at plan time even when the namespace is new.
  count = var.enable_service_discovery ? 1 : 0

  name          = var.service_name
  force_destroy = true

  lifecycle {
    precondition {
      condition     = var.namespace_id != null
      error_message = "namespace_id is required when enable_service_discovery is true."
    }
  }

  dns_config {
    namespace_id   = var.namespace_id
    routing_policy = "MULTIVALUE"

    dns_records {
      type = "A"
      ttl  = 10
    }
  }
}

# ---------------------------------------------------------------------------
# Task definition
# ---------------------------------------------------------------------------
resource "aws_ecs_task_definition" "this" {
  family                   = local.full_name
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.cpu
  memory                   = var.memory
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.task.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = var.cpu_architecture
  }

  container_definitions = jsonencode([
    merge(
      {
        name      = var.service_name
        image     = var.image
        essential = true

        portMappings = [
          { containerPort = var.container_port, protocol = "tcp" }
        ]

        environment = [for k in sort(keys(var.environment)) : { name = k, value = var.environment[k] }]
        secrets     = [for k in sort(keys(var.secrets)) : { name = k, valueFrom = var.secrets[k] }]

        # Recommended for ECS Exec: reaps the processes that exec sessions leave behind.
        linuxParameters = { initProcessEnabled = true }

        logConfiguration = {
          logDriver = "awslogs"
          options = {
            awslogs-group         = aws_cloudwatch_log_group.this.name
            awslogs-region        = local.region
            awslogs-stream-prefix = var.service_name
          }
        }
      },
      var.command == null ? {} : { command = var.command },
      var.health_check == null ? {} : {
        healthCheck = {
          command     = var.health_check.command
          interval    = var.health_check.interval
          timeout     = var.health_check.timeout
          retries     = var.health_check.retries
          startPeriod = var.health_check.start_period
        }
      },
    )
  ])
}

# ---------------------------------------------------------------------------
# Service
# ---------------------------------------------------------------------------
resource "aws_ecs_service" "this" {
  name            = var.service_name
  cluster         = var.cluster_arn
  task_definition = aws_ecs_task_definition.this.arn
  desired_count   = var.desired_count

  capacity_provider_strategy {
    capacity_provider = var.capacity_provider
    weight            = 1
  }

  platform_version        = "LATEST"
  enable_execute_command  = true
  propagate_tags          = "SERVICE"
  enable_ecs_managed_tags = true

  network_configuration {
    subnets          = var.subnet_ids
    security_groups  = concat([aws_security_group.this.id], var.shared_security_group_ids)
    assign_public_ip = false
  }

  dynamic "service_registries" {
    for_each = aws_service_discovery_service.this

    content {
      registry_arn = service_registries.value.arn
    }
  }

  # ALB target group: ECS registers each task IP on container_port and
  # deregisters (with draining) on stop.
  dynamic "load_balancer" {
    for_each = var.load_balancer_target_group_arn == null ? [] : [var.load_balancer_target_group_arn]

    content {
      target_group_arn = load_balancer.value
      container_name   = var.service_name
      container_port   = var.container_port
    }
  }

  # Spring Boot needs time to start: ECS ignores failing ALB and container
  # health checks for this many seconds after a task starts.
  health_check_grace_period_seconds = var.health_check_grace_period_seconds

  deployment_minimum_healthy_percent = var.deployment_minimum_healthy_percent
  deployment_maximum_percent         = var.deployment_maximum_percent

  # A deployment whose tasks keep failing is stopped and rolled back to the
  # last steady-state task definition.
  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  wait_for_steady_state = var.wait_for_steady_state

  # The task roles must keep their policies until the tasks are gone.
  depends_on = [
    aws_iam_role_policy.execution,
    aws_iam_role_policy.task,
  ]
}
