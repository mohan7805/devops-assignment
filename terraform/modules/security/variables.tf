variable "name" {
  description = "Name prefix for every resource in this module."
  type        = string
}

variable "vpc_id" {
  description = "VPC the security groups belong to."
  type        = string
}

variable "vpc_cidr_block" {
  description = "VPC CIDR, used for the VPC-endpoint security group ingress."
  type        = string
}

variable "app_port" {
  description = "TCP port the container listens on."
  type        = number
  default     = 8080
}

variable "alb_ingress_cidrs" {
  description = "CIDR blocks allowed to reach the ALB. Public app => 0.0.0.0/0."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "tags" {
  description = "Additional tags merged into every resource."
  type        = map(string)
  default     = {}
}
