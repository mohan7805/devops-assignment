output "repository_url" {
  description = "URL used to pull and push images (no tag)."
  value       = aws_ecr_repository.this.repository_url
}

output "repository_arn" {
  description = "ARN of the repository, used to scope the instance IAM policy."
  value       = aws_ecr_repository.this.arn
}

output "repository_name" {
  description = "Name of the repository."
  value       = aws_ecr_repository.this.name
}
