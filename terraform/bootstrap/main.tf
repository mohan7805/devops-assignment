###############################################################################
# Remote state backend bootstrap.
#
# This configuration is applied ONCE, before the main stack, and keeps its own
# state locally (it is the chicken that lays the egg). It creates:
#   * a versioned, encrypted, private S3 bucket for terraform.tfstate
#   * a DynamoDB table used for state locking
#
#   terraform -chdir=terraform/bootstrap init
#   terraform -chdir=terraform/bootstrap apply -var owner=you -var state_bucket_name=...
###############################################################################

resource "aws_s3_bucket" "state" {
  bucket = var.state_bucket_name

  # Guard against `terraform destroy` wiping the state of every environment.
  lifecycle {
    prevent_destroy = true
  }
}

# Versioning: required so a corrupted or truncated state file can be rolled back.
resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Encryption at rest for the state file, which contains resource attributes.
resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket = aws_s3_bucket.state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Reject any plaintext (non-TLS) access to the state bucket.
resource "aws_s3_bucket_policy" "state_tls_only" {
  bucket = aws_s3_bucket.state.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.state.arn,
          "${aws_s3_bucket.state.arn}/*",
        ]
        Condition = {
          Bool = { "aws:SecureTransport" = "false" }
        }
      }
    ]
  })
}

# Expire non-current state versions after 90 days to keep the bucket tidy.
resource "aws_s3_bucket_lifecycle_configuration" "state" {
  bucket     = aws_s3_bucket.state.id
  depends_on = [aws_s3_bucket_versioning.state]

  rule {
    id     = "expire-noncurrent-state-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 90
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

# State locking: prevents two concurrent `terraform apply` runs (for example a
# developer and the GitHub Actions pipeline) from corrupting the state.
resource "aws_dynamodb_table" "locks" {
  name         = var.lock_table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  server_side_encryption {
    enabled = true
  }

  point_in_time_recovery {
    enabled = true
  }

  lifecycle {
    prevent_destroy = true
  }
}
