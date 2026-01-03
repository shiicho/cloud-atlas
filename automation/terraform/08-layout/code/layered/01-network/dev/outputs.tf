# =============================================================================
# Network Layer Outputs
# =============================================================================
# 这些输出将被 02-foundations 和 03-application 层引用
# 使用 terraform_remote_state 数据源
# =============================================================================

output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

output "vpc_cidr" {
  description = "VPC CIDR block"
  value       = aws_vpc.main.cidr_block
}

output "public_subnet_ids" {
  description = "Public subnet IDs"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "Private subnet IDs"
  value       = aws_subnet.private[*].id
}

output "default_security_group_id" {
  description = "Default security group ID"
  value       = aws_security_group.default.id
}

output "availability_zones" {
  description = "使用的可用区"
  value       = local.azs
}
