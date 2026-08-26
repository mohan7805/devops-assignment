output "alb_security_group_id" {
  description = "Security group attached to the Application Load Balancer."
  value       = aws_security_group.alb.id
}

output "app_security_group_id" {
  description = "Security group attached to the Auto Scaling Group instances."
  value       = aws_security_group.app.id
}

output "vpc_endpoints_security_group_id" {
  description = "Security group for interface VPC endpoints."
  value       = aws_security_group.vpc_endpoints.id
}
