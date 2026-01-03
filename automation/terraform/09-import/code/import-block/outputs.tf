# =============================================================================
# outputs.tf - 输出值
# =============================================================================
#
# 导入完成后，这些输出将显示导入资源的信息
# 在 terraform apply 成功后可以通过 terraform output 查看
#
# =============================================================================

# -----------------------------------------------------------------------------
# 实例信息输出
# -----------------------------------------------------------------------------
# 注意：这些输出需要在资源导入成功后才能使用
# 首次运行时如果 main.tf 为空，这些输出会报错
# 请在生成代码并完成导入后取消注释

# output "instance_id" {
#   description = "导入的 EC2 实例 ID"
#   value       = aws_instance.imported_legacy.id
# }

# output "instance_public_ip" {
#   description = "EC2 实例的公网 IP（如果有）"
#   value       = aws_instance.imported_legacy.public_ip
# }

# output "instance_private_ip" {
#   description = "EC2 实例的私网 IP"
#   value       = aws_instance.imported_legacy.private_ip
# }

# output "instance_state" {
#   description = "EC2 实例的当前状态"
#   value       = aws_instance.imported_legacy.instance_state
# }

# output "instance_ami" {
#   description = "EC2 实例使用的 AMI"
#   value       = aws_instance.imported_legacy.ami
# }

# output "instance_type" {
#   description = "EC2 实例类型"
#   value       = aws_instance.imported_legacy.instance_type
# }

# output "instance_subnet" {
#   description = "EC2 实例所在子网"
#   value       = aws_instance.imported_legacy.subnet_id
# }

# output "instance_security_groups" {
#   description = "EC2 实例关联的安全组"
#   value       = aws_instance.imported_legacy.vpc_security_group_ids
# }

# -----------------------------------------------------------------------------
# 导入状态摘要
# -----------------------------------------------------------------------------
# 取消注释后，terraform output 将显示完整的导入摘要

# output "import_summary" {
#   description = "导入资源摘要"
#   value = {
#     resource_type = "aws_instance"
#     resource_name = "imported_legacy"
#     instance_id   = aws_instance.imported_legacy.id
#     instance_type = aws_instance.imported_legacy.instance_type
#     ami           = aws_instance.imported_legacy.ami
#     subnet_id     = aws_instance.imported_legacy.subnet_id
#     managed_by    = "Terraform"
#     import_method = "Import Block (TF 1.5+)"
#   }
# }
