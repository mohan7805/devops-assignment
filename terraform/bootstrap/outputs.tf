output "state_bucket" {
  description = "Name of the S3 bucket holding Terraform state."
  value       = aws_s3_bucket.state.id
}

output "lock_table" {
  description = "Name of the DynamoDB table used for state locking."
  value       = aws_dynamodb_table.locks.name
}

output "backend_block" {
  description = "Copy this into terraform/envs/prod/backend.tf (or pass with -backend-config)."
  value       = <<-EOT
    terraform {
      backend "s3" {
        bucket         = "${aws_s3_bucket.state.id}"
        key            = "prod/terraform.tfstate"
        region         = "${var.aws_region}"
        dynamodb_table = "${aws_dynamodb_table.locks.name}"
        encrypt        = true
      }
    }
  EOT
}
