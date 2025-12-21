# outputs.tf
# moved blocks 演练 - 输出值
# =============================================================================

output "instance_id" {
  description = "EC2 实例 ID"
  value       = aws_instance.app.id
}

output "security_group_id" {
  description = "安全组 ID"
  value       = aws_security_group.app.id
}

output "private_ip" {
  description = "私有 IP 地址"
  value       = aws_instance.app.private_ip
}

# -----------------------------------------------------------------------------
# 演练说明
# -----------------------------------------------------------------------------

output "refactoring_guide" {
  description = "重构演练指南"
  value       = <<-EOT

    moved blocks 重构演练指南:

    Step 1: 确认当前状态
      terraform state list
      # 输出: aws_instance.app, aws_security_group.app

    Step 2: 编辑 main.tf
      1. 取消注释 moved blocks
      2. 将 resource "aws_instance" "app" 改为 "application"
      3. 将 resource "aws_security_group" "app" 改为 "application"
      4. 更新所有引用

    Step 3: 查看 Plan
      terraform plan
      # 应该显示:
      # aws_instance.app will be moved to aws_instance.application
      # aws_security_group.app will be moved to aws_security_group.application

    Step 4: 应用移动
      terraform apply
      # State 自动更新，资源不会重建

    Step 5: 验证
      terraform state list
      # 输出: aws_instance.application, aws_security_group.application

    对比传统方式 (state mv):
      terraform state mv aws_instance.app aws_instance.application
      # 需要在每个环境手动执行
      # 没有版本控制

  EOT
}
