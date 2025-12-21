# =============================================================================
# Input Variables
# =============================================================================
#
# Variables for the S3 bucket module.
# All variables have descriptions for tflint compliance.
#
# =============================================================================

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "bucket_prefix" {
  description = "Prefix for the S3 bucket name"
  type        = string
  default     = "test-bucket-"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]*$", var.bucket_prefix))
    error_message = "Bucket prefix must start with lowercase letter or number, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "enable_versioning" {
  description = "Enable versioning for the S3 bucket"
  type        = bool
  default     = true
}

variable "enable_logging" {
  description = "Enable access logging for the S3 bucket (recommended for production)"
  type        = bool
  default     = false
}

variable "tags" {
  description = "Additional tags to apply to the bucket"
  type        = map(string)
  default     = {}
}

variable "force_destroy" {
  description = "Allow bucket to be destroyed even if not empty (use with caution!)"
  type        = bool
  default     = false
}
