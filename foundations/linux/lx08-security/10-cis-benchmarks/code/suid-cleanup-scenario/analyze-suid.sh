#!/bin/bash
# =============================================================================
# SUID/SGID Analysis Script
# =============================================================================
#
# Description:
#   Analyzes SUID/SGID files discovered by discover-suid.sh
#   Generates a detailed assessment report for CIS compliance.
#
# Usage:
#   sudo bash analyze-suid.sh
#
# Prerequisites:
#   Run discover-suid.sh first
#
# Output:
#   /tmp/suid-audit/suid-analysis-report.md
#
# Author: cloud-atlas
# =============================================================================

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

INPUT_DIR="/tmp/suid-audit"
SUID_FILE="${INPUT_DIR}/suid-files.txt"
REPORT_FILE="${INPUT_DIR}/suid-analysis-report.md"

# Check root
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}[ERROR]${NC} This script must be run as root"
    exit 1
fi

# Check input file
if [[ ! -f "${SUID_FILE}" ]]; then
    echo -e "${RED}[ERROR]${NC} Input file not found: ${SUID_FILE}"
    echo "Please run discover-suid.sh first"
    exit 1
fi

echo ""
echo "=========================================="
echo "   SUID/SGID File Analysis"
echo "=========================================="
echo ""
echo -e "${BLUE}[INFO]${NC} Analyzing SUID/SGID files..."
echo ""

# Known file classifications
declare -A ESSENTIAL=(
    ["/usr/bin/passwd"]="Password change - Required for users"
    ["/usr/bin/sudo"]="Privilege elevation - Required"
    ["/usr/bin/su"]="User switching - Required"
    ["/usr/sbin/unix_chkpwd"]="PAM password check - Required"
    ["/usr/sbin/pam_timestamp_check"]="PAM timestamp - Required"
)

declare -A REVIEW=(
    ["/usr/bin/mount"]="User mount - Review if needed"
    ["/usr/bin/umount"]="User unmount - Review if needed"
    ["/usr/bin/pkexec"]="Polkit execute - Review if GUI needed"
    ["/usr/bin/crontab"]="Cron editing - Review if needed"
    ["/usr/bin/at"]="Job scheduling - Review if needed"
    ["/usr/bin/chage"]="Password expiry - Usually root only"
    ["/usr/bin/chfn"]="Finger info - Usually not needed"
    ["/usr/bin/chsh"]="Shell change - Usually not needed"
    ["/usr/bin/gpasswd"]="Group password - Usually root only"
    ["/usr/bin/newgrp"]="Group switching - Usually not needed"
    ["/usr/bin/write"]="Write to terminal - Usually not needed"
    ["/usr/bin/wall"]="Broadcast message - Usually not needed"
    ["/usr/libexec/openssh/ssh-keysign"]="SSH host-based auth - Usually not needed"
)

declare -A REMOVABLE=(
    ["/usr/bin/chfn"]="Finger info change - Recommended to remove SUID"
    ["/usr/bin/chsh"]="Shell change - Recommended to remove SUID"
    ["/usr/bin/newgrp"]="Group switching - Recommended to remove SUID"
    ["/usr/bin/write"]="Terminal write - Recommended to remove SUID"
)

# Start report
cat > "${REPORT_FILE}" << 'EOF'
# SUID/SGID Analysis Report

**Generated:** $(date +"%Y-%m-%d %H:%M:%S")
**System:** $(hostname)

---

## Summary

| Category | Count | Action |
|----------|-------|--------|
EOF

essential_count=0
review_count=0
removable_count=0
unknown_count=0

# Count categories
while IFS= read -r file; do
    if [[ -n "${ESSENTIAL[$file]:-}" ]]; then
        ((essential_count++))
    elif [[ -n "${REMOVABLE[$file]:-}" ]]; then
        ((removable_count++))
    elif [[ -n "${REVIEW[$file]:-}" ]]; then
        ((review_count++))
    else
        ((unknown_count++))
    fi
done < "${SUID_FILE}"

# Add counts to report
echo "| Essential | ${essential_count} | Keep |" >> "${REPORT_FILE}"
echo "| Review Needed | ${review_count} | Assess |" >> "${REPORT_FILE}"
echo "| Recommended Remove | ${removable_count} | Remove SUID |" >> "${REPORT_FILE}"
echo "| Unknown/Custom | ${unknown_count} | Investigate |" >> "${REPORT_FILE}"

cat >> "${REPORT_FILE}" << 'EOF'

---

## Detailed Analysis

### Essential Files (DO NOT MODIFY)

These files are required for basic system operation:

| File | Permission | Package | Description |
|------|------------|---------|-------------|
EOF

while IFS= read -r file; do
    if [[ -n "${ESSENTIAL[$file]:-}" ]]; then
        perm=$(stat -c "%a" "$file" 2>/dev/null || echo "???")
        pkg=$(rpm -qf "$file" 2>/dev/null || dpkg -S "$file" 2>/dev/null | cut -d: -f1 || echo "unknown")
        echo "| \`${file}\` | ${perm} | ${pkg} | ${ESSENTIAL[$file]} |" >> "${REPORT_FILE}"
    fi
done < "${SUID_FILE}"

cat >> "${REPORT_FILE}" << 'EOF'

### Files to Review

Assess whether these are needed for your use case:

| File | Permission | Package | Risk | Description |
|------|------------|---------|------|-------------|
EOF

while IFS= read -r file; do
    if [[ -n "${REVIEW[$file]:-}" ]]; then
        perm=$(stat -c "%a" "$file" 2>/dev/null || echo "???")
        pkg=$(rpm -qf "$file" 2>/dev/null || dpkg -S "$file" 2>/dev/null | cut -d: -f1 || echo "unknown")
        echo "| \`${file}\` | ${perm} | ${pkg} | Medium | ${REVIEW[$file]} |" >> "${REPORT_FILE}"
    fi
done < "${SUID_FILE}"

cat >> "${REPORT_FILE}" << 'EOF'

### Recommended for SUID Removal

CIS Benchmark recommends removing SUID from these files:

| File | Permission | Package | Recommendation |
|------|------------|---------|----------------|
EOF

while IFS= read -r file; do
    if [[ -n "${REMOVABLE[$file]:-}" ]]; then
        perm=$(stat -c "%a" "$file" 2>/dev/null || echo "???")
        pkg=$(rpm -qf "$file" 2>/dev/null || dpkg -S "$file" 2>/dev/null | cut -d: -f1 || echo "unknown")
        echo "| \`${file}\` | ${perm} | ${pkg} | ${REMOVABLE[$file]} |" >> "${REPORT_FILE}"
    fi
done < "${SUID_FILE}"

cat >> "${REPORT_FILE}" << 'EOF'

### Unknown/Custom Files (INVESTIGATE)

These files need manual investigation:

| File | Permission | Package | Owner |
|------|------------|---------|-------|
EOF

while IFS= read -r file; do
    if [[ -z "${ESSENTIAL[$file]:-}" ]] && [[ -z "${REVIEW[$file]:-}" ]] && [[ -z "${REMOVABLE[$file]:-}" ]]; then
        perm=$(stat -c "%a" "$file" 2>/dev/null || echo "???")
        owner=$(stat -c "%U:%G" "$file" 2>/dev/null || echo "???")
        pkg=$(rpm -qf "$file" 2>/dev/null || dpkg -S "$file" 2>/dev/null | cut -d: -f1 || echo "unknown/custom")
        echo "| \`${file}\` | ${perm} | ${pkg} | ${owner} |" >> "${REPORT_FILE}"
    fi
done < "${SUID_FILE}"

cat >> "${REPORT_FILE}" << 'EOF'

---

## Remediation Commands

### Remove SUID from recommended files:

```bash
# Remove SUID from newgrp
sudo chmod u-s /usr/bin/newgrp

# Remove SUID from chfn
sudo chmod u-s /usr/bin/chfn

# Remove SUID from chsh
sudo chmod u-s /usr/bin/chsh

# Remove SUID from write (if exists)
sudo chmod u-s /usr/bin/write 2>/dev/null || true
```

### Verify changes:

```bash
ls -la /usr/bin/newgrp /usr/bin/chfn /usr/bin/chsh
```

---

## Exception Documentation

If you cannot remove SUID from certain files, document exceptions using:

```
code/exception-template.md
```

---

## Re-scan After Remediation

```bash
sudo bash discover-suid.sh
sudo oscap xccdf eval --profile cis_server_l1 ...
```

EOF

echo -e "${GREEN}[SUCCESS]${NC} Analysis complete!"
echo ""
echo "=========================================="
echo "         ANALYSIS SUMMARY"
echo "=========================================="
echo ""
echo -e "Essential files:      ${GREEN}${essential_count}${NC} (do not modify)"
echo -e "Review needed:        ${YELLOW}${review_count}${NC} (assess each)"
echo -e "Recommended remove:   ${RED}${removable_count}${NC} (remove SUID)"
echo -e "Unknown/investigate:  ${RED}${unknown_count}${NC} (investigate)"
echo ""
echo "Report generated: ${REPORT_FILE}"
echo ""
echo "Next steps:"
echo "  1. Review the report: cat ${REPORT_FILE}"
echo "  2. For removable files: sudo bash cleanup-suid.sh"
echo "  3. For exceptions: cp code/exception-template.md ./my-exception.md"
echo ""
