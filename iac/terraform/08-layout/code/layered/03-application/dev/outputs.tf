# =============================================================================
# Application Layer Outputs
# =============================================================================

output "app_instance_id" {
  description = "Application EC2 instance ID"
  value       = aws_instance.app.id
}

output "app_public_ip" {
  description = "Application server public IP"
  value       = aws_instance.app.public_ip
}

output "app_public_dns" {
  description = "Application server public DNS"
  value       = aws_instance.app.public_dns
}

output "app_security_group_id" {
  description = "Application security group ID"
  value       = aws_security_group.app.id
}

output "app_url" {
  description = "Application URL"
  value       = "http://${aws_instance.app.public_ip}"
}
