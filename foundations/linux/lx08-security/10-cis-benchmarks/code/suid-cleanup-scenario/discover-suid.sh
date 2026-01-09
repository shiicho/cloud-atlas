#!/bin/bash
# =============================================================================
# SUID/SGID Discovery Script
# =============================================================================
#
# Description:
#   Discovers all SUID and SGID files on the system for CIS compliance review.
#   Part of the "Pre-Audit SUID Cleanup" scenario.
#
# Usage:
#   sudo bash discover-suid.sh
#
# Output:
#   - Console summary
#   - /tmp/suid-audit/suid-files.txt
#   - /tmp/suid-audit/sgid-files.txt
#   - /tmp/suid-audit/suid-sgid-all.txt
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

OUTPUT_DIR="/tmp/suid-audit"
SUID_FILE="${OUTPUT_DIR}/suid-files.txt"
SGID_FILE="${OUTPUT_DIR}/sgid-files.txt"
ALL_FILE="${OUTPUT_DIR}/suid-sgid-all.txt"

# Check root
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}[ERROR]${NC} This script must be run as root"
    exit 1
fi

# Create output directory
mkdir -p "${OUTPUT_DIR}"

echo ""
echo "=========================================="
echo "   SUID/SGID File Discovery"
echo "=========================================="
echo ""
echo -e "${BLUE}[INFO]${NC} Scanning filesystem for SUID/SGID files..."
echo -e "${BLUE}[INFO]${NC} This may take a few minutes..."
echo ""

# Find SUID files (permission 4000)
echo -e "${YELLOW}[STEP 1]${NC} Finding SUID files (u+s)..."
find / -perm /4000 -type f 2>/dev/null | sort > "${SUID_FILE}"
suid_count=$(wc -l < "${SUID_FILE}")
echo -e "         Found: ${suid_count} SUID files"

# Find SGID files (permission 2000)
echo -e "${YELLOW}[STEP 2]${NC} Finding SGID files (g+s)..."
find / -perm /2000 -type f 2>/dev/null | sort > "${SGID_FILE}"
sgid_count=$(wc -l < "${SGID_FILE}")
echo -e "         Found: ${sgid_count} SGID files"

# Combine and deduplicate
echo -e "${YELLOW}[STEP 3]${NC} Creating combined list..."
find / -perm /6000 -type f 2>/dev/null | sort > "${ALL_FILE}"
all_count=$(wc -l < "${ALL_FILE}")

echo ""
echo "=========================================="
echo "         DISCOVERY SUMMARY"
echo "=========================================="
echo ""
echo -e "SUID files (u+s):     ${YELLOW}${suid_count}${NC}"
echo -e "SGID files (g+s):     ${YELLOW}${sgid_count}${NC}"
echo -e "Total unique:         ${YELLOW}${all_count}${NC}"
echo ""
echo "Output files:"
echo "  ${SUID_FILE}"
echo "  ${SGID_FILE}"
echo "  ${ALL_FILE}"
echo ""

# Show categorized summary
echo "=========================================="
echo "      CATEGORIZED BREAKDOWN"
echo "=========================================="
echo ""

# System utilities (expected SUID)
echo -e "${GREEN}[EXPECTED]${NC} System utilities with SUID (normal):"
for cmd in passwd sudo su mount umount; do
    if grep -q "/${cmd}$" "${SUID_FILE}"; then
        file=$(grep "/${cmd}$" "${SUID_FILE}" | head -1)
        echo "  - ${file}"
    fi
done
echo ""

# Polkit (potential removal candidate)
echo -e "${YELLOW}[REVIEW]${NC} Polkit binaries (may not be needed on servers):"
grep -E "pkexec|polkit" "${SUID_FILE}" 2>/dev/null || echo "  (none found)"
echo ""

# User management utilities
echo -e "${YELLOW}[REVIEW]${NC} User management utilities:"
for cmd in chage chfn chsh gpasswd newgrp; do
    if grep -q "/${cmd}$" "${SUID_FILE}"; then
        file=$(grep "/${cmd}$" "${SUID_FILE}" | head -1)
        echo "  - ${file}"
    fi
done
echo ""

# Network utilities
echo -e "${YELLOW}[REVIEW]${NC} Network utilities:"
for cmd in ping ping6 traceroute; do
    if grep -q "/${cmd}" "${SUID_FILE}"; then
        file=$(grep "/${cmd}" "${SUID_FILE}" | head -1)
        echo "  - ${file}"
    fi
done
echo ""

# SSH utilities
echo -e "${YELLOW}[REVIEW]${NC} SSH utilities:"
grep -E "ssh-keysign|ssh-agent" "${SUID_FILE}" 2>/dev/null || echo "  (none found)"
echo ""

# Cron utilities
echo -e "${YELLOW}[REVIEW]${NC} Cron utilities:"
grep -E "crontab|at" "${SUID_FILE}" 2>/dev/null || echo "  (none found)"
echo ""

# Unknown/custom (need investigation)
echo -e "${RED}[INVESTIGATE]${NC} Other SUID files (may need review):"
# Exclude known system paths
grep -v -E "(passwd|sudo|su|mount|umount|pkexec|polkit|chage|chfn|chsh|gpasswd|newgrp|ping|ssh|cron|at|unix_chkpwd|pam_timestamp)" "${SUID_FILE}" | head -10 || echo "  (none found)"
echo ""

echo "=========================================="
echo "          NEXT STEPS"
echo "=========================================="
echo ""
echo "1. Review each file in ${ALL_FILE}"
echo "2. Run: sudo bash analyze-suid.sh"
echo "3. Document decisions for each file"
echo "4. Remove SUID from unnecessary files: chmod u-s <file>"
echo ""
echo "CIS Benchmark recommendations:"
echo "- Remove SUID from: newgrp, chfn, chsh (if not needed)"
echo "- Review: mount, umount (if no user mounts needed)"
echo "- Review: pkexec (if no GUI/polkit needed)"
echo ""
