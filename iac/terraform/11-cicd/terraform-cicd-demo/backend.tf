# backend.tf
# S3 Remote Backend for CI/CD Demo
#
# IMPORTANT: Before using, replace PLACEHOLDER with your actual bucket name!
#
# Get bucket name from terraform-lab stack:
#   aws cloudformation describe-stacks --stack-name terraform-lab \
#     --query 'Stacks[0].Outputs[?OutputKey==`TfStateBucketName`].OutputValue' \
#     --output text
#
# Benefits of S3 Backend in CI/CD:
# - State persists across GitHub Actions runs (not lost when runner terminates)
# - State locking prevents concurrent apply conflicts
# - Versioning enables rollback if needed
# - Cleanup via terraform destroy actually works!

terraform {
  backend "s3" {
    bucket       = "PLACEHOLDER"  # Replace with your bucket name!
    key          = "iac/terraform/11-cicd/cicd-demo/terraform.tfstate"
    region       = "ap-northeast-1"
    encrypt      = true
    use_lockfile = true  # Terraform 1.10+ S3 native locking
  }
}
