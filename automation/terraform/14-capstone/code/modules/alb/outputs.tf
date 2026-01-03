# =============================================================================
# modules/alb/outputs.tf
# ALB 模块输出值
# =============================================================================

# -----------------------------------------------------------------------------
# ALB
# -----------------------------------------------------------------------------

output "alb_id" {
  description = "ALB ID"
  value       = aws_lb.main.id
}

output "alb_arn" {
  description = "ALB ARN"
  value       = aws_lb.main.arn
}

output "alb_arn_suffix" {
  description = "ALB ARN 后缀（用于 CloudWatch 指标）"
  value       = aws_lb.main.arn_suffix
}

output "alb_dns_name" {
  description = "ALB DNS 名称"
  value       = aws_lb.main.dns_name
}

output "alb_zone_id" {
  description = "ALB 托管区域 ID（用于 Route 53 别名记录）"
  value       = aws_lb.main.zone_id
}

# -----------------------------------------------------------------------------
# Target Group
# -----------------------------------------------------------------------------

output "target_group_arn" {
  description = "目标组 ARN"
  value       = aws_lb_target_group.main.arn
}

output "target_group_arn_suffix" {
  description = "目标组 ARN 后缀（用于 CloudWatch 指标）"
  value       = aws_lb_target_group.main.arn_suffix
}

output "target_group_name" {
  description = "目标组名称"
  value       = aws_lb_target_group.main.name
}

# -----------------------------------------------------------------------------
# Listeners
# -----------------------------------------------------------------------------

output "http_listener_arn" {
  description = "HTTP 监听器 ARN"
  value       = aws_lb_listener.http.arn
}

output "https_listener_arn" {
  description = "HTTPS 监听器 ARN（如果启用）"
  value       = length(aws_lb_listener.https) > 0 ? aws_lb_listener.https[0].arn : null
}

# -----------------------------------------------------------------------------
# Security Group
# -----------------------------------------------------------------------------

output "security_group_id" {
  description = "ALB 安全组 ID"
  value       = aws_security_group.alb.id
}

output "security_group_arn" {
  description = "ALB 安全组 ARN"
  value       = aws_security_group.alb.arn
}

# -----------------------------------------------------------------------------
# URL
# -----------------------------------------------------------------------------

output "alb_url" {
  description = "ALB 访问 URL"
  value       = "http://${aws_lb.main.dns_name}"
}

output "alb_https_url" {
  description = "ALB HTTPS 访问 URL（如果启用）"
  value       = var.certificate_arn != null ? "https://${aws_lb.main.dns_name}" : null
}
