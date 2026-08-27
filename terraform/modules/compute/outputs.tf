output "autoscaling_group_name" {
  description = "Name of the Auto Scaling Group (used by the deploy job)."
  value       = aws_autoscaling_group.this.name
}

output "autoscaling_group_arn" {
  description = "ARN of the Auto Scaling Group."
  value       = aws_autoscaling_group.this.arn
}

output "launch_template_id" {
  description = "ID of the launch template."
  value       = aws_launch_template.this.id
}

output "instance_role_arn" {
  description = "ARN of the least-privilege instance role."
  value       = aws_iam_role.instance.arn
}

output "instance_role_name" {
  description = "Name of the least-privilege instance role."
  value       = aws_iam_role.instance.name
}

output "ami_id" {
  description = "AMI resolved from the AWS-published SSM parameter."
  value       = data.aws_ssm_parameter.al2023_ami.value
}
