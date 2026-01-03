# outputs.tf
# 输出值定义

# -----------------------------------------------------------------------------
# for_each 资源输出
# -----------------------------------------------------------------------------

output "bucket_names" {
  description = "所有 bucket 名称（map）"
  value       = { for key, bucket in aws_s3_bucket.apps : key => bucket.bucket }
}

output "bucket_arns" {
  description = "所有 bucket ARN（map）"
  value       = { for key, bucket in aws_s3_bucket.apps : key => bucket.arn }
}

# 使用 splat 风格
output "all_bucket_ids" {
  description = "所有 bucket ID（list）"
  value       = values(aws_s3_bucket.apps)[*].id
}

# -----------------------------------------------------------------------------
# IAM Users 输出
# -----------------------------------------------------------------------------

output "iam_users" {
  description = "IAM 用户列表"
  value       = { for key, user in aws_iam_user.team_foreach : key => user.arn }
}

# -----------------------------------------------------------------------------
# Security Groups 输出
# -----------------------------------------------------------------------------

output "security_group_id" {
  description = "Dynamic demo SG ID"
  value       = aws_security_group.dynamic_demo.id
}

output "ingress_rules_applied" {
  description = "已应用的入站规则"
  value = [
    for rule in var.ingress_rules : {
      port        = rule.port
      description = rule.description
    }
  ]
}

# -----------------------------------------------------------------------------
# 统计信息
# -----------------------------------------------------------------------------

output "summary" {
  description = "资源统计"
  value = {
    buckets_count    = length(aws_s3_bucket.apps)
    users_count      = length(aws_iam_user.team_foreach)
    ingress_rules    = length(var.ingress_rules)
  }
}
