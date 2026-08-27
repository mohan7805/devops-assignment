###############################################################################
# Application Load Balancer
#
# Internet-facing, placed in the two public subnets, forwarding to a target
# group of Auto Scaling Group instances in the private subnets.
###############################################################################

resource "aws_lb" "this" {
  name               = substr("${var.name}-alb", 0, 32)
  internal           = false
  load_balancer_type = "application"
  subnets            = var.public_subnet_ids
  security_groups    = [var.security_group_id]

  idle_timeout                     = 60
  enable_deletion_protection       = var.enable_deletion_protection
  enable_cross_zone_load_balancing = true
  drop_invalid_header_fields       = true

  dynamic "access_logs" {
    for_each = var.access_logs_bucket == "" ? [] : [1]
    content {
      bucket  = var.access_logs_bucket
      prefix  = var.name
      enabled = true
    }
  }

  tags = merge(var.tags, { Name = "${var.name}-alb" })
}

resource "aws_lb_target_group" "this" {
  name        = substr("${var.name}-tg", 0, 32)
  port        = var.app_port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "instance"

  # Shorter than the container's graceful shutdown window, so in-flight
  # requests always finish before the process exits (zero-downtime deploys).
  deregistration_delay = var.deregistration_delay

  health_check {
    enabled             = true
    path                = var.health_check_path
    port                = "traffic-port"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  stickiness {
    type    = "lb_cookie"
    enabled = false
  }

  # NOTE: no create_before_destroy here. The target group has a fixed,
  # predictable name that the deployment pipeline relies on, and two target
  # groups cannot share a name - so a replacement must be destroy-then-create.
  tags = merge(var.tags, { Name = "${var.name}-tg" })
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this.arn
  }

  tags = var.tags
}
