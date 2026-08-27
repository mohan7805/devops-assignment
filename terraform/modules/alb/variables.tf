variable "name" {
  description = "Name prefix for every resource in this module."
  type        = string
}

variable "vpc_id" {
  description = "VPC the target group lives in."
  type        = string
}

variable "public_subnet_ids" {
  description = "Public subnets (one per AZ) the ALB is placed in."
  type        = list(string)
}

variable "security_group_id" {
  description = "Security group attached to the ALB."
  type        = string
}

variable "app_port" {
  description = "Port the targets listen on."
  type        = number
  default     = 8080
}

variable "health_check_path" {
  description = "Path used for the target-group health check."
  type        = string
  default     = "/health"
}

variable "deregistration_delay" {
  description = "Seconds the ALB drains a target before deregistering it. Must be shorter than the app's graceful shutdown."
  type        = number
  default     = 30
}

variable "enable_deletion_protection" {
  description = "Protect the ALB from accidental deletion."
  type        = bool
  default     = false
}

variable "access_logs_bucket" {
  description = "Optional S3 bucket for ALB access logs. Empty string disables them."
  type        = string
  default     = ""
}

variable "tags" {
  description = "Additional tags merged into every resource."
  type        = map(string)
  default     = {}
}
