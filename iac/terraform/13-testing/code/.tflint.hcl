# =============================================================================
# tflint Configuration
# =============================================================================
#
# tflint is a linter for Terraform that checks for:
# - Deprecated syntax
# - Provider-specific best practices
# - Naming conventions
# - Missing documentation
#
# Initialize: tflint --init
# Run: tflint
#
# =============================================================================

# -----------------------------------------------------------------------------
# Terraform Plugin (Built-in rules)
# -----------------------------------------------------------------------------
plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

# -----------------------------------------------------------------------------
# AWS Plugin (AWS-specific rules)
# -----------------------------------------------------------------------------
plugin "aws" {
  enabled = true
  version = "0.32.0"
  source  = "github.com/terraform-linters/tflint-ruleset-aws"
}

# -----------------------------------------------------------------------------
# Custom Rules
# -----------------------------------------------------------------------------

# Naming convention: snake_case for all identifiers
# Example: my_bucket (OK), myBucket (NG), my-bucket (NG)
rule "terraform_naming_convention" {
  enabled = true
  format  = "snake_case"
}

# All variables must have descriptions
# Makes modules self-documenting
rule "terraform_documented_variables" {
  enabled = true
}

# All outputs must have descriptions
rule "terraform_documented_outputs" {
  enabled = true
}

# Warn about unused declarations
rule "terraform_unused_declarations" {
  enabled = true
}

# Standard module structure
rule "terraform_standard_module_structure" {
  enabled = true
}

# Require terraform block with required_version
rule "terraform_required_version" {
  enabled = true
}

# Require provider version constraints
rule "terraform_required_providers" {
  enabled = true
}

# -----------------------------------------------------------------------------
# AWS-Specific Rules (examples)
# -----------------------------------------------------------------------------

# Detect previous generation instance types (t1, m1, m2, etc.)
# These are outdated and usually more expensive per performance
rule "aws_instance_previous_type" {
  enabled = true
}

# Detect invalid instance types
rule "aws_instance_invalid_type" {
  enabled = true
}

# Detect invalid AMI IDs
rule "aws_instance_invalid_ami" {
  enabled = true
}

# -----------------------------------------------------------------------------
# Ignored Rules (customize as needed)
# -----------------------------------------------------------------------------
# Uncomment to disable specific rules

# rule "terraform_module_pinned_source" {
#   enabled = false
# }
