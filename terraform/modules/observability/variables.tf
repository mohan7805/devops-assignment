variable "name" {
  description = "Name prefix for every resource in this module."
  type        = string
}

variable "log_retention_days" {
  description = "CloudWatch Logs retention period, in days."
  type        = number
  default     = 30

  validation {
    condition = contains(
      [1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653],
      var.log_retention_days
    )
    error_message = "log_retention_days must be one of the retention values accepted by CloudWatch Logs."
  }
}

variable "alarm_email" {
  description = "Email address subscribed to the SNS alarm topic. Confirm the subscription from your inbox."
  type        = string
}

variable "alb_arn_suffix" {
  description = "ALB ARN suffix, used as a CloudWatch metric dimension."
  type        = string
}

variable "target_group_arn_suffix" {
  description = "Target group ARN suffix, used as a CloudWatch metric dimension."
  type        = string
}

variable "autoscaling_group_name" {
  description = "ASG name, used for the CPU alarm dimension."
  type        = string
  default     = ""
}

variable "alb_5xx_threshold" {
  description = "Number of 5XX responses in one evaluation period that triggers the alarm."
  type        = number
  default     = 5
}

variable "tags" {
  description = "Additional tags merged into every resource."
  type        = map(string)
  default     = {}
}

variable "enable_sns_encryption" {
  description = "Encrypt the SNS alarm topic with a customer-managed KMS key. Adds ~$1/month."
  type        = bool
  default     = true
}
