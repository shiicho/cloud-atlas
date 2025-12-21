# =============================================================================
# OPA Policy: Required Tags
# =============================================================================
#
# This policy enforces that all AWS resources have required tags.
# Tags are essential for:
# - Cost allocation (chargeback)
# - Resource ownership tracking
# - Environment identification
# - Compliance and auditing
#
# Usage:
#   1. Generate plan JSON: terraform plan -out=tfplan.binary
#   2. Convert to JSON: terraform show -json tfplan.binary > tfplan.json
#   3. Run OPA: opa eval -i tfplan.json -d required_tags.rego "data.terraform.deny"
#
# =============================================================================

package terraform

import input as tfplan

# -----------------------------------------------------------------------------
# Configuration: Required Tags
# -----------------------------------------------------------------------------
# Modify this set to match your organization's tagging requirements

required_tags := {"Environment", "Owner"}

# Additional tags that are recommended but not required
recommended_tags := {"Project", "CostCenter", "Team"}

# -----------------------------------------------------------------------------
# Helper Functions
# -----------------------------------------------------------------------------

# Get all resources that will be created or updated
resources_with_changes[resource] {
    resource := tfplan.resource_changes[_]
    resource.change.actions[_] == "create"
}

resources_with_changes[resource] {
    resource := tfplan.resource_changes[_]
    resource.change.actions[_] == "update"
}

# Check if a resource type supports tags
taggable_resource_types := {
    "aws_s3_bucket",
    "aws_instance",
    "aws_vpc",
    "aws_subnet",
    "aws_security_group",
    "aws_db_instance",
    "aws_lambda_function",
    "aws_dynamodb_table",
    "aws_sqs_queue",
    "aws_sns_topic",
    "aws_iam_role",
    "aws_ecs_cluster",
    "aws_ecs_service",
    "aws_eks_cluster",
    "aws_elasticache_cluster",
    "aws_elasticsearch_domain",
    "aws_kinesis_stream",
    "aws_kms_key"
}

# -----------------------------------------------------------------------------
# Deny Rules: Required Tags
# -----------------------------------------------------------------------------

# Deny if required tags are missing
deny[msg] {
    resource := resources_with_changes[_]
    taggable_resource_types[resource.type]

    # Get tags from the planned resource
    tags := object.get(resource.change.after, "tags", {})

    # Find missing required tags
    missing := required_tags - {tag | tags[tag]}
    count(missing) > 0

    msg := sprintf(
        "[REQUIRED] Resource '%s' (%s) is missing required tags: %v",
        [resource.address, resource.type, missing]
    )
}

# Deny if Environment tag has invalid value
deny[msg] {
    resource := resources_with_changes[_]
    taggable_resource_types[resource.type]

    tags := object.get(resource.change.after, "tags", {})
    env_value := tags["Environment"]

    valid_environments := {"dev", "staging", "prod", "test"}
    not valid_environments[env_value]

    msg := sprintf(
        "[INVALID] Resource '%s' has invalid Environment tag value '%s'. Must be one of: %v",
        [resource.address, env_value, valid_environments]
    )
}

# -----------------------------------------------------------------------------
# Warn Rules: Recommended Tags
# -----------------------------------------------------------------------------

warn[msg] {
    resource := resources_with_changes[_]
    taggable_resource_types[resource.type]

    tags := object.get(resource.change.after, "tags", {})

    missing := recommended_tags - {tag | tags[tag]}
    count(missing) > 0

    msg := sprintf(
        "[RECOMMENDED] Resource '%s' is missing recommended tags: %v",
        [resource.address, missing]
    )
}

# -----------------------------------------------------------------------------
# Summary Helpers
# -----------------------------------------------------------------------------

# Count of violations
violation_count := count(deny)

# Count of warnings
warning_count := count(warn)

# Summary output
summary := {
    "violations": violation_count,
    "warnings": warning_count,
    "compliant": violation_count == 0
}
