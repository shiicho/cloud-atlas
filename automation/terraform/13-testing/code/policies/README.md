# OPA Policies for Terraform

This directory contains Open Policy Agent (OPA) policies for validating Terraform configurations.

## Usage

### 1. Generate Terraform Plan JSON

```bash
cd ../sample-module
terraform init
terraform plan -out=tfplan.binary
terraform show -json tfplan.binary > tfplan.json
```

### 2. Run Policy Checks

```bash
# Check required tags
opa eval -i tfplan.json -d required_tags.rego "data.terraform.deny"

# Check S3 security
opa eval -i tfplan.json -d s3_security.rego "data.terraform.s3.deny"

# Get summary
opa eval -i tfplan.json -d required_tags.rego "data.terraform.summary"
```

### 3. CI/CD Integration

```bash
# Fail if any violations
opa eval -i tfplan.json -d policies/ "data.terraform.deny" --fail-defined

# Pretty output
opa eval -i tfplan.json -d policies/ "data.terraform.deny" --format pretty
```

## Policies

### required_tags.rego

Enforces required tags on all taggable AWS resources:

- **Required**: `Environment`, `Owner`
- **Recommended**: `Project`, `CostCenter`, `Team`

### s3_security.rego

Enforces S3 security best practices:

- Block all public access
- Enable server-side encryption
- Warn if production buckets lack versioning
- Warn if production buckets lack access logging

## Customization

Edit the policy files to match your organization's requirements:

```rego
# In required_tags.rego
required_tags := {"Environment", "Owner", "CostCenter", "Team"}

# Valid environment values
valid_environments := {"dev", "staging", "prod", "dr"}
```

## References

- [OPA Documentation](https://www.openpolicyagent.org/docs/latest/)
- [OPA Terraform Integration](https://www.openpolicyagent.org/docs/latest/terraform/)
- [Rego Language Reference](https://www.openpolicyagent.org/docs/latest/policy-language/)
