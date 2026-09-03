###############################################################################
# Remote state in S3 (versioned + encrypted) with DynamoDB state locking.
#
# The bucket and lock table are created by terraform/bootstrap. The concrete
# values are supplied at init time so the same code works for any account:
#
#   terraform init \
#     -backend-config="bucket=<state-bucket>" \
#     -backend-config="key=prod/terraform.tfstate" \
#     -backend-config="region=<region>" \
#     -backend-config="dynamodb_table=devops-assignment-tf-locks"
#
# CI passes these from GitHub Secrets - see .github/workflows/terraform.yml.
###############################################################################

terraform {
  backend "s3" {
    key     = "prod/terraform.tfstate"
    encrypt = true
  }
}
