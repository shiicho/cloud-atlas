# backend.tf
# Using local backend for this demo
#
# This keeps the demo simple - no remote state setup needed.
# In production, use S3 remote backend (see lesson 02).
#
# The state file (terraform.tfstate) stays on your local machine.
# GitHub Actions also uses local state for this demo.

# Default: local backend (no configuration needed)
