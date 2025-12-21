# outputs.tf
# 输出值定义
#
# Output 用于：
# 1. apply 完成后显示重要信息
# 2. 供其他模块引用
# 3. 供外部脚本读取

# -----------------------------------------------------------------------------
# 网络资源 ID
# -----------------------------------------------------------------------------

output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

output "subnet_id" {
  description = "Public Subnet ID"
  value       = aws_subnet.public.id
}

output "security_group_id" {
  description = "Security Group ID"
  value       = aws_security_group.web.id
}

# -----------------------------------------------------------------------------
# Data Source 输出
# -----------------------------------------------------------------------------

output "az_used" {
  description = "使用的可用区"
  value       = data.aws_availability_zones.available.names[0]
}

output "all_azs" {
  description = "当前区域所有可用区"
  value       = data.aws_availability_zones.available.names
}

output "latest_ami_id" {
  description = "最新 Amazon Linux 2023 AMI ID"
  value       = data.aws_ami.al2023.id
}

output "latest_ami_name" {
  description = "最新 Amazon Linux 2023 AMI 名称"
  value       = data.aws_ami.al2023.name
}

# -----------------------------------------------------------------------------
# 账户和区域信息
# -----------------------------------------------------------------------------

output "account_id" {
  description = "AWS 账户 ID"
  value       = data.aws_caller_identity.current.account_id
}

output "region" {
  description = "当前区域"
  value       = data.aws_region.current.name
}

# -----------------------------------------------------------------------------
# 便捷链接
# -----------------------------------------------------------------------------

output "vpc_console_url" {
  description = "在 AWS Console 中查看此 VPC"
  value       = "https://${data.aws_region.current.name}.console.aws.amazon.com/vpc/home?region=${data.aws_region.current.name}#VpcDetails:VpcId=${aws_vpc.main.id}"
}
