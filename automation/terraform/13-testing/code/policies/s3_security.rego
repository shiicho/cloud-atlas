# =============================================================================
# OPA Policy: S3 Security
# =============================================================================
#
# This policy enforces S3 security best practices:
# - No public buckets
# - Encryption enabled
# - Versioning enabled for production
# - Logging enabled for production
#
# Usage:
#   opa eval -i tfplan.json -d s3_security.rego "data.terraform.s3.deny"
#
# =============================================================================

package terraform.s3

import input as tfplan

# -----------------------------------------------------------------------------
# Helper: Get S3 bucket resources being created
# -----------------------------------------------------------------------------

s3_buckets[resource] {
    resource := tfplan.resource_changes[_]
    resource.type == "aws_s3_bucket"
    resource.change.actions[_] == "create"
}

s3_public_access_blocks[resource] {
    resource := tfplan.resource_changes[_]
    resource.type == "aws_s3_bucket_public_access_block"
    resource.change.actions[_] == "create"
}

s3_encryption_configs[resource] {
    resource := tfplan.resource_changes[_]
    resource.type == "aws_s3_bucket_server_side_encryption_configuration"
    resource.change.actions[_] == "create"
}

# -----------------------------------------------------------------------------
# Deny: Public Access Must Be Blocked
# -----------------------------------------------------------------------------

deny[msg] {
    resource := s3_public_access_blocks[_]
    config := resource.change.after

    config.block_public_acls != true

    msg := sprintf(
        "[S3-001] Bucket '%s' must have block_public_acls = true",
        [resource.address]
    )
}

deny[msg] {
    resource := s3_public_access_blocks[_]
    config := resource.change.after

    config.block_public_policy != true

    msg := sprintf(
        "[S3-002] Bucket '%s' must have block_public_policy = true",
        [resource.address]
    )
}

deny[msg] {
    resource := s3_public_access_blocks[_]
    config := resource.change.after

    config.ignore_public_acls != true

    msg := sprintf(
        "[S3-003] Bucket '%s' must have ignore_public_acls = true",
        [resource.address]
    )
}

deny[msg] {
    resource := s3_public_access_blocks[_]
    config := resource.change.after

    config.restrict_public_buckets != true

    msg := sprintf(
        "[S3-004] Bucket '%s' must have restrict_public_buckets = true",
        [resource.address]
    )
}

# -----------------------------------------------------------------------------
# Deny: Encryption Must Be Enabled
# -----------------------------------------------------------------------------

# Check that encryption configuration exists for each bucket
deny[msg] {
    bucket := s3_buckets[_]
    bucket_name := bucket.change.after.bucket

    # Check if there's a matching encryption configuration
    not encryption_exists(bucket_name)

    msg := sprintf(
        "[S3-005] Bucket '%s' must have server-side encryption configuration",
        [bucket.address]
    )
}

encryption_exists(bucket_name) {
    enc := s3_encryption_configs[_]
    enc.change.after.bucket == bucket_name
}

# -----------------------------------------------------------------------------
# Warn: Production Buckets Should Have Versioning
# -----------------------------------------------------------------------------

warn[msg] {
    bucket := s3_buckets[_]
    tags := object.get(bucket.change.after, "tags", {})

    tags["Environment"] == "prod"

    # Check versioning status
    versioning := tfplan.resource_changes[_]
    versioning.type == "aws_s3_bucket_versioning"
    versioning.change.after.bucket == bucket.change.after.bucket
    versioning.change.after.versioning_configuration[0].status != "Enabled"

    msg := sprintf(
        "[S3-WARN-001] Production bucket '%s' should have versioning enabled",
        [bucket.address]
    )
}

# -----------------------------------------------------------------------------
# Warn: Production Buckets Should Have Logging
# -----------------------------------------------------------------------------

warn[msg] {
    bucket := s3_buckets[_]
    tags := object.get(bucket.change.after, "tags", {})

    tags["Environment"] == "prod"

    # Check if logging exists
    not logging_exists(bucket.change.after.bucket)

    msg := sprintf(
        "[S3-WARN-002] Production bucket '%s' should have access logging enabled",
        [bucket.address]
    )
}

logging_exists(bucket_id) {
    logging := tfplan.resource_changes[_]
    logging.type == "aws_s3_bucket_logging"
    logging.change.after.bucket == bucket_id
}

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------

violation_count := count(deny)
warning_count := count(warn)

summary := {
    "violations": violation_count,
    "warnings": warning_count,
    "compliant": violation_count == 0
}
