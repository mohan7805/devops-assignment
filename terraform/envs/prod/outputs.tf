output "app_url" {
  description = "Public URL of the application."
  value       = "http://${module.alb.alb_dns_name}"
}

output "alb_dns_name" {
  description = "Bare DNS name of the load balancer (no scheme)."
  value       = module.alb.alb_dns_name
}

output "alb_arn_suffix" {
  description = "ALB ARN suffix (CloudWatch dimension)."
  value       = module.alb.alb_arn_suffix
}

output "target_group_arn" {
  description = "Target group ARN, used by the pipeline's health gate."
  value       = module.alb.target_group_arn
}

output "autoscaling_group_name" {
  description = "ASG name, used by the pipeline to start an instance refresh."
  value       = module.compute.autoscaling_group_name
}

output "ecr_repository_url" {
  description = "ECR repository the pipeline pushes to."
  value       = module.ecr.repository_url
}

output "ecr_repository_name" {
  description = "ECR repository name."
  value       = module.ecr.repository_name
}

output "image_tag_parameter_name" {
  description = "SSM parameter the pipeline updates with the new image tag."
  value       = aws_ssm_parameter.image_tag.name
}

output "log_group_name" {
  description = "CloudWatch log group holding application and system logs."
  value       = module.observability.log_group_name
}

output "sns_topic_arn" {
  description = "SNS topic the CloudWatch alarms publish to."
  value       = module.observability.sns_topic_arn
}

output "alarm_names" {
  description = "CloudWatch alarms guarding the service."
  value       = module.observability.alarm_names
}

output "vpc_id" {
  description = "ID of the VPC."
  value       = module.vpc.vpc_id
}

output "availability_zones" {
  description = "AZs the stack spans (resolved from a data source, never hardcoded)."
  value       = module.vpc.availability_zones
}

output "private_subnet_ids" {
  description = "Private subnets hosting the application instances."
  value       = module.vpc.private_subnet_ids
}

output "instance_role_name" {
  description = "Least-privilege IAM role attached to the instances."
  value       = module.compute.instance_role_name
}
