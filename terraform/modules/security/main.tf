###############################################################################
# Security groups, chained by reference:
#
#   internet ──80/443──▶ [alb sg] ──app_port──▶ [app sg] ──443──▶ [endpoints sg]
#
# The application security group has NO CIDR-based ingress at all - it only
# accepts traffic from the ALB security group ID. Port 22 is never opened:
# administrative access is through SSM Session Manager (see the compute module).
###############################################################################

resource "aws_security_group" "alb" {
  name_prefix = "${var.name}-alb-"
  description = "Public entry point: allows HTTP/HTTPS from the internet to the ALB."
  vpc_id      = var.vpc_id

  tags = merge(var.tags, { Name = "${var.name}-alb-sg" })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  for_each = toset(var.alb_ingress_cidrs)

  security_group_id = aws_security_group.alb.id
  description       = "HTTP from the internet"
  cidr_ipv4         = each.value
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"

  tags = var.tags
}

resource "aws_vpc_security_group_ingress_rule" "alb_https" {
  for_each = toset(var.alb_ingress_cidrs)

  security_group_id = aws_security_group.alb.id
  description       = "HTTPS from the internet (used once a certificate is attached)"
  cidr_ipv4         = each.value
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"

  tags = var.tags
}

# The ALB may only talk to the application tier, on the application port.
resource "aws_vpc_security_group_egress_rule" "alb_to_app" {
  security_group_id            = aws_security_group.alb.id
  description                  = "Forward requests to the application instances"
  referenced_security_group_id = aws_security_group.app.id
  from_port                    = var.app_port
  to_port                      = var.app_port
  ip_protocol                  = "tcp"

  tags = var.tags
}

###############################################################################
# Application tier
###############################################################################

resource "aws_security_group" "app" {
  name_prefix = "${var.name}-app-"
  description = "Application instances. Ingress only from the ALB security group."
  vpc_id      = var.vpc_id

  tags = merge(var.tags, { Name = "${var.name}-app-sg" })

  lifecycle {
    create_before_destroy = true
  }
}

# Chained by reference, not by CIDR: only the ALB SG can reach the app port.
resource "aws_vpc_security_group_ingress_rule" "app_from_alb" {
  security_group_id            = aws_security_group.app.id
  description                  = "Application traffic and health checks from the ALB only"
  referenced_security_group_id = aws_security_group.alb.id
  from_port                    = var.app_port
  to_port                      = var.app_port
  ip_protocol                  = "tcp"

  tags = var.tags
}

# NOTE: there is deliberately no ingress rule on port 22 anywhere in this file.
# Shell access is obtained with `aws ssm start-session`, which is outbound-only.

# Egress is required for: pulling the image from ECR, SSM Session Manager,
# CloudWatch Logs, and OS package updates. All of it leaves via the NAT Gateway.
resource "aws_vpc_security_group_egress_rule" "app_https" {
  security_group_id = aws_security_group.app.id
  description       = "HTTPS to AWS APIs (ECR, SSM, CloudWatch) and package mirrors"
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"

  tags = var.tags
}

resource "aws_vpc_security_group_egress_rule" "app_http" {
  security_group_id = aws_security_group.app.id
  description       = "HTTP for the Amazon Linux package repositories"
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"

  tags = var.tags
}

###############################################################################
# Interface VPC endpoints (optional) - keeps SSM/ECR/Logs traffic off the NAT.
###############################################################################

resource "aws_security_group" "vpc_endpoints" {
  name_prefix = "${var.name}-vpce-"
  description = "Interface VPC endpoints; HTTPS from inside the VPC only."
  vpc_id      = var.vpc_id

  tags = merge(var.tags, { Name = "${var.name}-vpce-sg" })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "vpce_from_app" {
  security_group_id            = aws_security_group.vpc_endpoints.id
  description                  = "HTTPS from the application tier"
  referenced_security_group_id = aws_security_group.app.id
  from_port                    = 443
  to_port                      = 443
  ip_protocol                  = "tcp"

  tags = var.tags
}
