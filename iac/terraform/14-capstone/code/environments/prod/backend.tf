# =============================================================================
# environments/prod/backend.tf
# 远程后端配置 - Production 环境
# =============================================================================
#
# 使用课程实验环境提供的 S3 Bucket（避免重复创建）
#
# 获取 Bucket 名称：
#   aws cloudformation describe-stacks --stack-name terraform-lab \
#     --query 'Stacks[0].Outputs[?OutputKey==`TfStateBucketName`].OutputValue' \
#     --output text --region ap-northeast-1
#
# 或者在 EC2 上直接使用环境变量：
#   echo $TF_STATE_BUCKET
#
# =============================================================================

terraform {
  backend "s3" {
    # 替换为实际的 Bucket 名称（从 CloudFormation 输出获取）
    # 格式: tfstate-terraform-lab-{AccountId}
    bucket = "tfstate-terraform-lab-REPLACE_WITH_YOUR_BUCKET"

    # 每个 lesson + 环境使用独立的 state key
    key = "14-capstone/prod/terraform.tfstate"

    region       = "ap-northeast-1"
    encrypt      = true
    use_lockfile = true # Terraform 1.10+ 原生 S3 锁定
  }
}
