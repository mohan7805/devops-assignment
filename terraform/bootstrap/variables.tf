variable "aws_region" {
  description = "AWS region that will hold the Terraform state bucket and lock table."
  type        = string
  default     = "ap-south-1"
}

variable "project" {
  description = "Project tag applied to every resource."
  type        = string
  default     = "devops-assignment"
}

variable "owner" {
  description = "Owner tag applied to every resource."
  type        = string
}

variable "state_bucket_name" {
  description = "Globally unique name for the S3 bucket holding Terraform state."
  type        = string
}

variable "lock_table_name" {
  description = "DynamoDB table used for Terraform state locking."
  type        = string
  default     = "devops-assignment-tf-locks"
}
