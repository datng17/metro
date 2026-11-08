# ---------------------------------------------------------------------------
# Internet-facing Application Load Balancer in the public subnets.
#   :80  -> 301 redirect to https://<host>:443/<path>?<query>
#   :443 -> TLS terminated with the ACM certificate -> forward to the target
#           group (type ip: Fargate task ENIs, registered by ECS).
# The ALB security group allows 80/443 from the internet. Its egress rule to
# the targets is added by the caller (SG-to-SG, so it can only reach them).
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Security group
# ---------------------------------------------------------------------------
resource "aws_security_group" "this" {
  name        = "${var.name}-alb"
  description = "${var.name} ALB: http/https from the internet"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${var.name}-alb"
  }
}

locals {
  listener_ports = { http = 80, https = 443 }

  # One ingress rule per (port, CIDR).
  ingress_rules = {
    for pair in setproduct(keys(local.listener_ports), var.ingress_cidr_ipv4) :
    "${pair[0]}-${pair[1]}" => { port = local.listener_ports[pair[0]], cidr = pair[1] }
  }
}

resource "aws_vpc_security_group_ingress_rule" "listeners" {
  for_each = local.ingress_rules

  security_group_id = aws_security_group.this.id
  description       = "tcp ${each.value.port} from ${each.value.cidr}"
  ip_protocol       = "tcp"
  from_port         = each.value.port
  to_port           = each.value.port
  cidr_ipv4         = each.value.cidr
}

# ---------------------------------------------------------------------------
# Load balancer
# ---------------------------------------------------------------------------
resource "aws_lb" "this" {
  name               = "${var.name}-alb"
  internal           = false
  load_balancer_type = "application"
  ip_address_type    = "ipv4"
  security_groups    = [aws_security_group.this.id]
  subnets            = var.subnet_ids

  idle_timeout               = var.idle_timeout
  enable_deletion_protection = var.deletion_protection
  # Reject requests with malformed headers instead of passing them to the app.
  drop_invalid_header_fields = true
  enable_http2               = true

  tags = {
    Name = "${var.name}-alb"
  }
}

# ---------------------------------------------------------------------------
# Target group: ECS registers each gateway task IP on target_port.
# ---------------------------------------------------------------------------
resource "aws_lb_target_group" "this" {
  name        = "${var.name}-${var.target_name}"
  vpc_id      = var.vpc_id
  target_type = "ip"
  protocol    = "HTTP"
  port        = var.target_port

  deregistration_delay = var.deregistration_delay

  health_check {
    enabled             = true
    protocol            = "HTTP"
    port                = "traffic-port"
    path                = var.health_check_path
    matcher             = var.health_check_matcher
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  tags = {
    Name = "${var.name}-${var.target_name}"
  }

  # A changed name/port needs a new group; create it before removing the old
  # one so the listener always has a target.
  lifecycle {
    create_before_destroy = true
  }
}

# ---------------------------------------------------------------------------
# Listeners
# ---------------------------------------------------------------------------
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      protocol    = "HTTPS"
      port        = "443"
      status_code = "HTTP_301"
    }
  }
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.this.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = var.ssl_policy
  certificate_arn   = var.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this.arn
  }
}
