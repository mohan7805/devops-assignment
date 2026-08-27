output "alb_arn" {
  description = "ARN of the Application Load Balancer."
  value       = aws_lb.this.arn
}

output "alb_arn_suffix" {
  description = "ARN suffix, used as a CloudWatch metric dimension."
  value       = aws_lb.this.arn_suffix
}

output "alb_dns_name" {
  description = "Public DNS name of the load balancer."
  value       = aws_lb.this.dns_name
}

output "alb_zone_id" {
  description = "Hosted zone ID of the ALB, for Route 53 alias records."
  value       = aws_lb.this.zone_id
}

output "target_group_arn" {
  description = "ARN of the target group the ASG attaches to."
  value       = aws_lb_target_group.this.arn
}

output "target_group_arn_suffix" {
  description = "Target group ARN suffix, used as a CloudWatch metric dimension."
  value       = aws_lb_target_group.this.arn_suffix
}

output "target_group_name" {
  description = "Name of the target group (used by the deployment health gate)."
  value       = aws_lb_target_group.this.name
}
