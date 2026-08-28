terraform {
  # Provider and Terraform versions are pinned so CI and laptops agree.
  required_version = ">= 1.6.0, < 2.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "aws" {
  region = var.aws_region

  # Every single resource created by this stack carries these three tags.
  default_tags {
    tags = {
      Project     = var.project
      Owner       = var.owner
      ManagedBy   = "terraform"
      Environment = var.environment
    }
  }
}
