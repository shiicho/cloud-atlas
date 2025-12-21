# outputs.tf
# State 操作演练 - 输出值
# =============================================================================

# -----------------------------------------------------------------------------
# Bucket 名称
# -----------------------------------------------------------------------------

output "logs_bucket_name" {
  description = "Logs bucket 名称"
  value       = aws_s3_bucket.logs.bucket
}

output "data_bucket_name" {
  description = "Data bucket 名称"
  value       = aws_s3_bucket.data.bucket
}

output "backup_bucket_name" {
  description = "Backup bucket 名称"
  value       = aws_s3_bucket.backup.bucket
}

# -----------------------------------------------------------------------------
# Bucket ARN
# -----------------------------------------------------------------------------

output "logs_bucket_arn" {
  description = "Logs bucket ARN"
  value       = aws_s3_bucket.logs.arn
}

output "data_bucket_arn" {
  description = "Data bucket ARN"
  value       = aws_s3_bucket.data.arn
}

output "backup_bucket_arn" {
  description = "Backup bucket ARN"
  value       = aws_s3_bucket.backup.arn
}

# -----------------------------------------------------------------------------
# 演练提示
# -----------------------------------------------------------------------------

output "state_commands_hint" {
  description = "State 操作命令提示"
  value       = <<-EOT

    State 操作演练命令:

    1. 查看资源列表:
       terraform state list

    2. 查看资源详情:
       terraform state show aws_s3_bucket.logs

    3. 重命名资源 (state mv):
       terraform state mv aws_s3_bucket.logs aws_s3_bucket.log_bucket
       然后修改代码中的资源名称！

    4. 取消管理 (state rm):
       terraform state rm aws_s3_bucket.data
       terraform state rm aws_s3_bucket_versioning.data
       资源仍在 AWS 中，但 Terraform 不再管理

    5. 强制重建 (-replace):
       terraform apply -replace="aws_s3_bucket.backup"
       注意：bucket 必须为空才能删除重建

  EOT
}
