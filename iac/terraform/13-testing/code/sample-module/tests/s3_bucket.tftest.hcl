# =============================================================================
# S3 Bucket Module Tests
# =============================================================================
#
# Test file for sample-module using terraform test (TF 1.6+).
#
# Run tests: terraform test
# Run specific test: terraform test -filter=tests/s3_bucket.tftest.hcl
#
# Test types:
# - command = plan  : Dry-run, no resources created (fast)
# - command = apply : Creates real resources, auto-cleanup (slower)
#
# =============================================================================

# -----------------------------------------------------------------------------
# Test: Default values work correctly
# -----------------------------------------------------------------------------
# Verifies that the module works with all default values.
# Uses plan mode - no resources are actually created.

run "default_values" {
  command = plan

  # Assertions check expected behavior
  assert {
    condition     = startswith(aws_s3_bucket.main.bucket, "test-bucket-")
    error_message = "Bucket name should start with 'test-bucket-' by default"
  }

  assert {
    condition     = aws_s3_bucket.main.tags["Environment"] == "dev"
    error_message = "Default environment should be 'dev'"
  }

  assert {
    condition     = aws_s3_bucket.main.force_destroy == false
    error_message = "force_destroy should be false by default"
  }
}

# -----------------------------------------------------------------------------
# Test: Versioning is enabled by default
# -----------------------------------------------------------------------------
run "versioning_enabled_by_default" {
  command = plan

  assert {
    condition     = aws_s3_bucket_versioning.main.versioning_configuration[0].status == "Enabled"
    error_message = "Versioning should be enabled by default"
  }
}

# -----------------------------------------------------------------------------
# Test: Public access is blocked
# -----------------------------------------------------------------------------
run "public_access_blocked" {
  command = plan

  assert {
    condition     = aws_s3_bucket_public_access_block.main.block_public_acls == true
    error_message = "block_public_acls should be true"
  }

  assert {
    condition     = aws_s3_bucket_public_access_block.main.block_public_policy == true
    error_message = "block_public_policy should be true"
  }

  assert {
    condition     = aws_s3_bucket_public_access_block.main.ignore_public_acls == true
    error_message = "ignore_public_acls should be true"
  }

  assert {
    condition     = aws_s3_bucket_public_access_block.main.restrict_public_buckets == true
    error_message = "restrict_public_buckets should be true"
  }
}

# -----------------------------------------------------------------------------
# Test: Encryption is configured
# -----------------------------------------------------------------------------
run "encryption_configured" {
  command = plan

  assert {
    condition     = aws_s3_bucket_server_side_encryption_configuration.main.rule[0].apply_server_side_encryption_by_default[0].sse_algorithm == "AES256"
    error_message = "SSE algorithm should be AES256"
  }
}

# -----------------------------------------------------------------------------
# Test: Production environment configuration
# -----------------------------------------------------------------------------
# Tests production-specific settings with logging enabled.

run "production_config" {
  command = plan

  variables {
    environment    = "prod"
    enable_logging = true
  }

  assert {
    condition     = aws_s3_bucket.main.tags["Environment"] == "prod"
    error_message = "Environment tag should be 'prod'"
  }

  # Logging bucket should be created in production
  assert {
    condition     = length(aws_s3_bucket.logs) == 1
    error_message = "Logs bucket should be created when enable_logging is true"
  }

  # Logging configuration should exist
  assert {
    condition     = length(aws_s3_bucket_logging.main) == 1
    error_message = "Logging configuration should exist when enable_logging is true"
  }
}

# -----------------------------------------------------------------------------
# Test: Logging disabled by default
# -----------------------------------------------------------------------------
run "logging_disabled_by_default" {
  command = plan

  assert {
    condition     = length(aws_s3_bucket.logs) == 0
    error_message = "Logs bucket should not be created when enable_logging is false"
  }

  assert {
    condition     = length(aws_s3_bucket_logging.main) == 0
    error_message = "Logging configuration should not exist when enable_logging is false"
  }
}

# -----------------------------------------------------------------------------
# Test: Custom tags are merged
# -----------------------------------------------------------------------------
run "custom_tags_merged" {
  command = plan

  variables {
    tags = {
      Owner   = "team-platform"
      Project = "infrastructure"
    }
  }

  assert {
    condition     = aws_s3_bucket.main.tags["Owner"] == "team-platform"
    error_message = "Custom Owner tag should be applied"
  }

  assert {
    condition     = aws_s3_bucket.main.tags["Project"] == "infrastructure"
    error_message = "Custom Project tag should be applied"
  }

  # Default tags should still exist
  assert {
    condition     = aws_s3_bucket.main.tags["Environment"] == "dev"
    error_message = "Environment tag should still exist after merging custom tags"
  }
}

# -----------------------------------------------------------------------------
# Test: Versioning can be disabled
# -----------------------------------------------------------------------------
run "versioning_disabled" {
  command = plan

  variables {
    enable_versioning = false
  }

  assert {
    condition     = aws_s3_bucket_versioning.main.versioning_configuration[0].status == "Disabled"
    error_message = "Versioning should be disabled when enable_versioning is false"
  }
}

# -----------------------------------------------------------------------------
# Test: Invalid environment is rejected
# -----------------------------------------------------------------------------
# This test verifies that the validation rule works correctly.
# We expect the validation to fail, not pass.

run "invalid_environment_rejected" {
  command = plan

  variables {
    environment = "invalid"
  }

  # We expect the environment variable validation to fail
  expect_failures = [
    var.environment
  ]
}

# -----------------------------------------------------------------------------
# Test: Invalid bucket prefix is rejected
# -----------------------------------------------------------------------------
run "invalid_bucket_prefix_rejected" {
  command = plan

  variables {
    bucket_prefix = "Invalid-Prefix-"  # Uppercase not allowed
  }

  expect_failures = [
    var.bucket_prefix
  ]
}

# -----------------------------------------------------------------------------
# Test: Bucket prefix starting with hyphen is rejected
# -----------------------------------------------------------------------------
run "bucket_prefix_starting_with_hyphen_rejected" {
  command = plan

  variables {
    bucket_prefix = "-invalid-prefix-"  # Cannot start with hyphen
  }

  expect_failures = [
    var.bucket_prefix
  ]
}
