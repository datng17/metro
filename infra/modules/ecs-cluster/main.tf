# ---------------------------------------------------------------------------
# ECS cluster (Fargate only). Container Insights is off to save cost.
# Services are created with the ecs-service module.
# ---------------------------------------------------------------------------
resource "aws_ecs_cluster" "this" {
  name = var.name

  setting {
    name  = "containerInsights"
    value = "disabled"
  }

  tags = {
    Name = var.name
  }
}

resource "aws_ecs_cluster_capacity_providers" "this" {
  cluster_name       = aws_ecs_cluster.this.name
  capacity_providers = ["FARGATE", "FARGATE_SPOT"]

  # Tasks started without a strategy (e.g. the db-init one-off) run on-demand.
  default_capacity_provider_strategy {
    capacity_provider = "FARGATE"
    weight            = 1
    base              = 0
  }
}

# ---------------------------------------------------------------------------
# Shared security group attached to every ECS task. Data stores (RDS) allow
# ingress only from this group. It has no ingress rules of its own; each
# ecs-service has its own security group that allows its port from this one.
# ---------------------------------------------------------------------------
resource "aws_security_group" "tasks" {
  name        = "${var.name}-ecs-tasks"
  description = "Shared SG for all ECS tasks; source SG for RDS access"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${var.name}-ecs-tasks"
  }
}

# Outbound to anywhere: ECR/CloudWatch/SSM endpoints and Atlas go through fck-nat.
resource "aws_vpc_security_group_egress_rule" "tasks_all" {
  security_group_id = aws_security_group.tasks.id
  description       = "All outbound traffic"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

# ---------------------------------------------------------------------------
# Cloud Map private DNS namespace (a private Route 53 hosted zone in the VPC).
# Each ecs-service registers <service>.<namespace> as A records of its task IPs.
# ---------------------------------------------------------------------------
resource "aws_service_discovery_private_dns_namespace" "this" {
  name        = var.namespace_name
  description = "Service discovery for ${var.name} ECS services"
  vpc         = var.vpc_id

  tags = {
    Name = var.namespace_name
  }
}
