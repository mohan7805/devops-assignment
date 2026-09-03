variable "aws_region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "ap-south-1"
}

variable "project" {
  description = "Project name; used as a resource name prefix and as the Project tag."
  type        = string
  default     = "devops-assignment"
}

variable "owner" {
  description = "Owner tag value (team or individual responsible for the stack)."
  type        = string
  default     = "mohan"
}

variable "environment" {
  description = "Environment name, used in resource names and tags."
  type        = string
  default     = "prod"
}

variable "vpc_cidr" {
  description = "CIDR block of the VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "az_count" {
  description = "Number of Availability Zones to span."
  type        = number
  default     = 2
}

variable "single_nat_gateway" {
  description = "true = one NAT Gateway (cheaper); false = one per AZ (HA)."
  type        = bool
  default     = true
}

variable "instance_type" {
  description = "EC2 instance type for the application tier."
  type        = string
  default     = "t3.micro"
}

variable "min_size" {
  description = "Minimum ASG size."
  type        = number
  default     = 1
}

variable "max_size" {
  description = "Maximum ASG size."
  type        = number
  default     = 2
}

variable "desired_capacity" {
  description = "Desired ASG size."
  type        = number
  default     = 1
}

variable "app_port" {
  description = "Port the application container listens on."
  type        = number
  default     = 8080
}

variable "app_version" {
  description = "Application version reported by GET /info."
  type        = string
  default     = "1.0.0"
}

variable "initial_image_tag" {
  description = "Image tag used on the very first apply, before the pipeline has pushed anything."
  type        = string
  default     = "bootstrap"
}

variable "log_retention_days" {
  description = "CloudWatch Logs retention, in days."
  type        = number
  default     = 30
}

variable "alarm_email" {
  description = "Email address subscribed to the SNS alarm topic."
  type        = string
  default     = "mohanmadhavan7805@gmail.com"
}

variable "alb_ingress_cidrs" {
  description = "CIDRs allowed to reach the ALB."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}
