variable "name" {
  description = "Name of the ECR repository."
  type        = string
}

variable "image_tag_mutability" {
  description = "MUTABLE or IMMUTABLE. Immutable tags guarantee a SHA tag is never overwritten."
  type        = string
  default     = "IMMUTABLE"
}

variable "untagged_image_expiry_days" {
  description = "Days after which untagged images are expired."
  type        = number
  default     = 7
}

variable "max_tagged_images" {
  description = "How many tagged images to retain."
  type        = number
  default     = 30
}

variable "tags" {
  description = "Additional tags merged into every resource."
  type        = map(string)
  default     = {}
}
