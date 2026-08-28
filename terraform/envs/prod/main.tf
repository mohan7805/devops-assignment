###############################################################################
# Production stack.
#
#   internet ─▶ ALB (public subnets) ─▶ ASG t3.micro x2 (private subnets)
#                                        │
#                                        ├─▶ ECR (image pull)
#                                        ├─▶ SSM Parameter Store (config/secrets)
#                                        └─▶ CloudWatch Logs
###############################################################################

locals {
  name = "${var.project}-${var.environment}"

  tags = {
    Project     = var.project
    Owner       = var.owner
    ManagedBy   = "terraform"
    Environment = var.environment
  }
}

module "vpc" {
  source = "../../modules/vpc"

  name               = local.name
  cidr_block         = var.vpc_cidr
  az_count           = var.az_count
  single_nat_gateway = var.single_nat_gateway
  tags               = local.tags
}

module "security" {
  source = "../../modules/security"

  name              = local.name
  vpc_id            = module.vpc.vpc_id
  vpc_cidr_block    = module.vpc.vpc_cidr_block
  app_port          = var.app_port
  alb_ingress_cidrs = var.alb_ingress_cidrs
  tags              = local.tags
}

module "ecr" {
  source = "../../modules/ecr"

  name = var.project
  tags = local.tags
}

module "alb" {
  source = "../../modules/alb"

  name              = local.name
  vpc_id            = module.vpc.vpc_id
  public_subnet_ids = module.vpc.public_subnet_ids
  security_group_id = module.security.alb_security_group_id
  app_port          = var.app_port
  health_check_path = "/health"
  tags              = local.tags
}

module "observability" {
  source = "../../modules/observability"

  name                    = local.name
  log_retention_days      = var.log_retention_days
  alarm_email             = var.alarm_email
  alb_arn_suffix          = module.alb.alb_arn_suffix
  target_group_arn_suffix = module.alb.target_group_arn_suffix
  tags                    = local.tags
}

module "compute" {
  source = "../../modules/compute"

  name       = local.name
  aws_region = var.aws_region

  private_subnet_ids = module.vpc.private_subnet_ids
  security_group_id  = module.security.app_security_group_id
  target_group_arn   = module.alb.target_group_arn

  instance_type    = var.instance_type
  min_size         = var.min_size
  max_size         = var.max_size
  desired_capacity = var.desired_capacity

  app_port    = var.app_port
  app_version = var.app_version

  ecr_repository_url = module.ecr.repository_url
  ecr_repository_arn = module.ecr.repository_arn

  image_tag_parameter_name = aws_ssm_parameter.image_tag.name
  greeting_parameter_name  = aws_ssm_parameter.greeting.name

  # The instance role may read only these two parameters.
  secret_parameter_arns = [
    aws_ssm_parameter.image_tag.arn,
    aws_ssm_parameter.greeting.arn,
  ]

  log_group_name = module.observability.log_group_name
  log_group_arn  = module.observability.log_group_arn

  tags = local.tags
}
