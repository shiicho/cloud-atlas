# =============================================================================
# 变量定义 - 反模式示例
# Variables - Anti-Pattern Example
# =============================================================================

variable "region" {
  type        = string
  description = "AWS region"
  default     = "ap-northeast-1"
}

variable "environment" {
  type        = string
  description = "Environment name (dev/staging/prod)"
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be dev, staging, or prod."
  }
}

# =============================================================================
# ❌ 即使标记为 sensitive，默认值仍是硬编码的
# =============================================================================

# 注意：即使设置 sensitive = true
# 1. 代码中的默认值仍然可见
# 2. State 文件中仍是明文
# 3. 只是 terraform plan/apply 输出时显示 (sensitive value)
