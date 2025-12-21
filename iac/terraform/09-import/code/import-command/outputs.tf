# =============================================================================
# outputs.tf - 输出值
# =============================================================================

output "instance_id" {
  description = "导入的 EC2 实例 ID"
  value       = aws_instance.legacy.id
}

output "instance_public_ip" {
  description = "EC2 实例的公网 IP（如果有）"
  value       = aws_instance.legacy.public_ip
}

output "instance_private_ip" {
  description = "EC2 实例的私网 IP"
  value       = aws_instance.legacy.private_ip
}

output "instance_state" {
  description = "EC2 实例的当前状态"
  value       = aws_instance.legacy.instance_state
}
