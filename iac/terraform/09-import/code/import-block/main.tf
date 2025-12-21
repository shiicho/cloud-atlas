# =============================================================================
# main.tf - 资源定义
# =============================================================================
#
# 初始为空 - 资源代码将通过以下方式生成:
#   terraform plan -generate-config-out=generated.tf
#
# 生成后，请:
#   1. 审查 generated.tf 中的代码
#   2. 删除不必要的默认值属性
#   3. 将硬编码值改为变量
#   4. 将代码移动到此文件
#   5. 删除 generated.tf
#
# =============================================================================

# -----------------------------------------------------------------------------
# 导入后的资源定义
# -----------------------------------------------------------------------------
# 运行 terraform plan -generate-config-out=generated.tf 后
# 将生成的代码复制到这里，并进行以下优化:
#
# 1. 删除计算属性（如 arn, id, public_ip 等）
# 2. 删除默认值属性（减少代码噪音）
# 3. 参数化硬编码值：
#    - ami           → var.ami_id 或 data source
#    - subnet_id     → var.subnet_id
#    - security_groups → var.security_group_ids
# 4. 添加必要的 lifecycle 规则
#
# 示例（审查后的代码）:
#
# resource "aws_instance" "imported_legacy" {
#   ami           = data.aws_ami.amazon_linux.id
#   instance_type = var.instance_type
#   subnet_id     = var.subnet_id
#
#   vpc_security_group_ids = var.security_group_ids
#
#   tags = {
#     Name        = "imported-legacy-instance"
#     Environment = var.environment
#     ManagedBy   = "Terraform"
#   }
#
#   lifecycle {
#     # 防止意外删除
#     prevent_destroy = false  # 练习时设为 false，生产环境可设为 true
#   }
# }
