# outputs.tf
# 输出值定义
# =============================================================================
#
# 输出值用于：
# 1. apply 后显示重要信息
# 2. 供脚本读取（如 drift-inject.sh）
# 3. 供其他模块引用

# -----------------------------------------------------------------------------
# 实例信息
# -----------------------------------------------------------------------------

output "instance_id" {
  description = "EC2 实例 ID（drift-inject.sh 需要）"
  value       = aws_instance.demo.id
}

output "instance_arn" {
  description = "EC2 实例 ARN"
  value       = aws_instance.demo.arn
}

output "instance_state" {
  description = "EC2 实例状态"
  value       = aws_instance.demo.instance_state
}

# -----------------------------------------------------------------------------
# 标签信息（Drift 检测重点）
# -----------------------------------------------------------------------------

output "instance_tags" {
  description = "EC2 实例标签（用于对比 Drift）"
  value       = aws_instance.demo.tags
}

# -----------------------------------------------------------------------------
# 网络信息
# -----------------------------------------------------------------------------

output "private_ip" {
  description = "私有 IP 地址"
  value       = aws_instance.demo.private_ip
}

output "security_group_id" {
  description = "安全组 ID"
  value       = aws_security_group.demo.id
}

# -----------------------------------------------------------------------------
# 访问信息
# -----------------------------------------------------------------------------

output "ssm_connect_command" {
  description = "SSM 连接命令"
  value       = "aws ssm start-session --target ${aws_instance.demo.id}"
}

output "console_url" {
  description = "AWS Console 中查看此实例的 URL"
  value       = "https://ap-northeast-1.console.aws.amazon.com/ec2/home?region=ap-northeast-1#InstanceDetails:instanceId=${aws_instance.demo.id}"
}

# -----------------------------------------------------------------------------
# AMI 信息
# -----------------------------------------------------------------------------

output "ami_id" {
  description = "使用的 AMI ID"
  value       = data.aws_ami.amazon_linux.id
}

output "ami_name" {
  description = "使用的 AMI 名称"
  value       = data.aws_ami.amazon_linux.name
}
