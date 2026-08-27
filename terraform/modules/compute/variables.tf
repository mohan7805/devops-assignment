variable "name" {
  description = "Name prefix for every resource in this module."
  type        = string
}

variable "aws_region" {
  description = "Region the instances run in (passed to the AWS CLI in user-data)."
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnets the Auto Scaling Group launches instances into."
  type        = list(string)
}

variable "security_group_id" {
  description = "Security group attached to the instances."
  type        = string
}

variable "target_group_arn" {
  description = "ALB target group the ASG registers instances with."
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type."
  type        = string
  default     = "t3.micro"
}

variable "min_size" {
  description = "Minimum number of instances."
  type        = number
  default     = 2
}

variable "max_size" {
  description = "Maximum number of instances."
  type        = number
  default     = 4
}

variable "desired_capacity" {
  description = "Desired number of instances."
  type        = number
  default     = 2
}

variable "app_port" {
  description = "Port the container publishes on the host."
  type        = number
  default     = 8080
}

variable "app_version" {
  description = "Application version reported by /info."
  type        = string
  default     = "1.0.0"
}

variable "ecr_repository_url" {
  description = "ECR repository the image is pulled from."
  type        = string
}

variable "ecr_repository_arn" {
  description = "ECR repository ARN, used to scope the pull permission."
  type        = string
}

variable "image_tag_parameter_name" {
  description = "SSM parameter holding the image tag to run. CI updates it, then triggers an instance refresh."
  type        = string
}

variable "secret_parameter_arns" {
  description = "ARNs of the SSM parameters the instance is allowed to read at runtime."
  type        = list(string)
}

variable "greeting_parameter_name" {
  description = "SSM SecureString parameter holding the greeting text."
  type        = string
}

variable "log_group_name" {
  description = "CloudWatch log group the container and system logs are shipped to."
  type        = string
}

variable "log_group_arn" {
  description = "ARN of the CloudWatch log group, used to scope the logging permission."
  type        = string
}

variable "kms_key_arn" {
  description = "KMS key used for SSM SecureString decryption. Empty string = AWS-managed alias/aws/ssm."
  type        = string
  default     = ""
}

variable "instance_warmup_seconds" {
  description = "Seconds a new instance is given to warm up during an instance refresh."
  type        = number
  default     = 120
}

variable "tags" {
  description = "Additional tags merged into every resource."
  type        = map(string)
  default     = {}
}
