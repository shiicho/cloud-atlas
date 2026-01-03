# =============================================================================
# modules/ec2/outputs.tf
# EC2/ASG 模块输出值
# =============================================================================

# -----------------------------------------------------------------------------
# Launch Template
# -----------------------------------------------------------------------------

output "launch_template_id" {
  description = "Launch Template ID"
  value       = aws_launch_template.main.id
}

output "launch_template_arn" {
  description = "Launch Template ARN"
  value       = aws_launch_template.main.arn
}

output "launch_template_latest_version" {
  description = "Launch Template 最新版本"
  value       = aws_launch_template.main.latest_version
}

# -----------------------------------------------------------------------------
# Auto Scaling Group
# -----------------------------------------------------------------------------

output "asg_name" {
  description = "Auto Scaling Group 名称"
  value       = aws_autoscaling_group.main.name
}

output "asg_arn" {
  description = "Auto Scaling Group ARN"
  value       = aws_autoscaling_group.main.arn
}

output "asg_id" {
  description = "Auto Scaling Group ID"
  value       = aws_autoscaling_group.main.id
}

# -----------------------------------------------------------------------------
# Security Group
# -----------------------------------------------------------------------------

output "security_group_id" {
  description = "EC2 安全组 ID"
  value       = aws_security_group.ec2.id
}

output "security_group_arn" {
  description = "EC2 安全组 ARN"
  value       = aws_security_group.ec2.arn
}

# -----------------------------------------------------------------------------
# IAM
# -----------------------------------------------------------------------------

output "iam_role_arn" {
  description = "EC2 IAM Role ARN"
  value       = var.create_iam_role ? aws_iam_role.ec2[0].arn : null
}

output "iam_role_name" {
  description = "EC2 IAM Role 名称"
  value       = var.create_iam_role ? aws_iam_role.ec2[0].name : null
}

output "iam_instance_profile_arn" {
  description = "EC2 IAM Instance Profile ARN"
  value       = var.create_iam_role ? aws_iam_instance_profile.ec2[0].arn : null
}

# -----------------------------------------------------------------------------
# AMI
# -----------------------------------------------------------------------------

output "ami_id" {
  description = "使用的 AMI ID"
  value       = local.ami_id
}

# -----------------------------------------------------------------------------
# Auto Scaling Policies
# -----------------------------------------------------------------------------

output "scale_up_policy_arn" {
  description = "扩容策略 ARN"
  value       = var.enable_autoscaling ? aws_autoscaling_policy.scale_up[0].arn : null
}

output "scale_down_policy_arn" {
  description = "缩容策略 ARN"
  value       = var.enable_autoscaling ? aws_autoscaling_policy.scale_down[0].arn : null
}
