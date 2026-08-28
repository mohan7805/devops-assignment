###############################################################################
# Runtime configuration and secrets in SSM Parameter Store.
#
# Nothing secret is stored in this repository. Terraform creates the parameters
# with placeholder values and then ignores subsequent changes to those values,
# so the real secret is written once, out of band:
#
#   aws ssm put-parameter --name /devops-assignment/prod/greeting \
#     --type SecureString --value "..." --overwrite
###############################################################################

# Image tag currently deployed. The CI pipeline overwrites this with the short
# git SHA and then starts an instance refresh, so the launch template itself
# never has to change on a code-only deployment (no Terraform drift).
resource "aws_ssm_parameter" "image_tag" {
  name        = "/${var.project}/${var.environment}/image_tag"
  description = "Container image tag the Auto Scaling Group should run."
  type        = "String"
  value       = var.initial_image_tag
  tier        = "Standard"

  lifecycle {
    # Owned by the deployment pipeline after the first apply.
    ignore_changes = [value]
  }

  tags = local.tags
}

# Application secret, encrypted with the AWS-managed SSM key and read at boot.
resource "aws_ssm_parameter" "greeting" {
  name        = "/${var.project}/${var.environment}/greeting"
  description = "Greeting text returned by the API. Managed out of band, never committed."
  type        = "SecureString"
  value       = "CHANGE_ME - set with aws ssm put-parameter --overwrite"
  tier        = "Standard"

  lifecycle {
    # The real value is never in git and must not be reverted by an apply.
    ignore_changes = [value]
  }

  tags = local.tags
}

###############################################################################
# Deployment discovery parameters.
#
# The pipeline needs to know which Auto Scaling Group to refresh and which
# target group to poll. Publishing them here means the deploy job never has to
# guess resource names or hardcode ARNs - it just reads three parameters.
###############################################################################

resource "aws_ssm_parameter" "asg_name" {
  name        = "/${var.project}/${var.environment}/asg_name"
  description = "Auto Scaling Group the deployment pipeline refreshes."
  type        = "String"
  value       = module.compute.autoscaling_group_name

  tags = local.tags
}

resource "aws_ssm_parameter" "target_group_arn" {
  name        = "/${var.project}/${var.environment}/target_group_arn"
  description = "ALB target group the deployment pipeline polls for health."
  type        = "String"
  value       = module.alb.target_group_arn

  tags = local.tags
}

resource "aws_ssm_parameter" "alb_dns_name" {
  name        = "/${var.project}/${var.environment}/alb_dns_name"
  description = "Public DNS name of the load balancer."
  type        = "String"
  value       = module.alb.alb_dns_name

  tags = local.tags
}
