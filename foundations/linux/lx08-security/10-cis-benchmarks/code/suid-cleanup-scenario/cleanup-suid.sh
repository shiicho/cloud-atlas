#!/bin/bash
# =============================================================================
# SUID Cleanup Script
# =============================================================================
#
# Description:
#   Removes SUID permissions from commonly flagged binaries per CIS Benchmark.
#   Creates backup and logs all changes.
#
# Usage:
#   sudo bash cleanup-suid.sh [--dry-run]
#
# Options:
#   --dry-run    Show what would be changed without making changes
#
# Prerequisites:
#   Run discover-suid.sh and analyze-suid.sh first
#
# Output:
#   /tmp/suid-audit/cleanup-log.txt
#
# Author: cloud-atlas
#
# WARNING:
#   This script modifies system file permissions!
#   - Review the changes carefully
#   - Test in non-production environment first
#   - Keep the backup/log for potential rollback
# =============================================================================

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

OUTPUT_DIR="/tmp/suid-audit"
LOG_FILE="${OUTPUT_DIR}/cleanup-log.txt"
BACKUP_FILE="${OUTPUT_DIR}/suid-backup.txt"

DRY_RUN=false

# Parse arguments
if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=true
fi

# Check root
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}[ERROR]${NC} This script must be run as root"
    exit 1
fi

# Files to remove SUID from (CIS recommendations)
# These are generally not needed on servers
CLEANUP_TARGETS=(
    "/usr/bin/newgrp"      # Group switching - rarely needed
    "/usr/bin/chfn"        # Finger info - rarely needed
    "/usr/bin/chsh"        # Shell change - admin should control
    "/usr/bin/write"       # Terminal write - rarely needed
    "/usr/bin/wall"        # Broadcast - rarely needed on servers
)

# Optional targets (uncomment if not needed)
# CLEANUP_TARGETS+=(
#     "/usr/bin/mount"     # User mount - uncomment if no user mounts
#     "/usr/bin/umount"    # User unmount - uncomment if no user mounts
#     "/usr/bin/pkexec"    # Polkit - uncomment if no GUI
# )

mkdir -p "${OUTPUT_DIR}"

echo ""
echo "=========================================="
echo "   SUID Permission Cleanup"
echo "=========================================="
echo ""

if [[ "${DRY_RUN}" == true ]]; then
    echo -e "${YELLOW}[DRY-RUN MODE]${NC} No changes will be made"
    echo ""
fi

# Initialize log
{
    echo "# SUID Cleanup Log"
    echo "# Date: $(date)"
    echo "# Host: $(hostname)"
    echo "# Dry Run: ${DRY_RUN}"
    echo ""
    echo "## Changes"
} > "${LOG_FILE}"

# Initialize backup
{
    echo "# SUID Permission Backup"
    echo "# Date: $(date)"
    echo "# Use this to restore permissions if needed"
    echo ""
    echo "# Restore commands:"
} > "${BACKUP_FILE}"

changed_count=0
skipped_count=0

for file in "${CLEANUP_TARGETS[@]}"; do
    echo -e "${BLUE}[CHECK]${NC} ${file}"

    if [[ ! -f "${file}" ]]; then
        echo -e "        ${YELLOW}Skipped: File not found${NC}"
        echo "- ${file}: FILE NOT FOUND (skipped)" >> "${LOG_FILE}"
        ((skipped_count++))
        continue
    fi

    # Get current permissions
    current_perm=$(stat -c "%a" "${file}")
    current_mode=$(stat -c "%A" "${file}")

    # Check if SUID is set
    if [[ ! "${current_mode}" =~ "s" ]]; then
        echo -e "        ${GREEN}Already clean: No SUID bit set${NC}"
        echo "- ${file}: Already clean (${current_mode})" >> "${LOG_FILE}"
        ((skipped_count++))
        continue
    fi

    echo -e "        Current: ${current_mode} (${current_perm})"

    # Calculate new permissions (remove SUID: subtract 4000)
    new_perm=$((current_perm - 4000))
    if [[ ${new_perm} -lt 0 ]]; then
        new_perm=$((current_perm - 2000))  # Try SGID if not SUID
    fi

    if [[ "${DRY_RUN}" == true ]]; then
        echo -e "        ${YELLOW}Would change:${NC} ${current_perm} -> ${new_perm}"
        echo "- ${file}: WOULD CHANGE ${current_perm} -> ${new_perm}" >> "${LOG_FILE}"
    else
        # Record backup command
        echo "chmod ${current_perm} ${file}  # Restore to ${current_mode}" >> "${BACKUP_FILE}"

        # Remove SUID
        chmod u-s "${file}"

        # Verify
        new_mode=$(stat -c "%A" "${file}")
        echo -e "        ${GREEN}Changed:${NC} ${current_mode} -> ${new_mode}"
        echo "- ${file}: CHANGED ${current_mode} -> ${new_mode}" >> "${LOG_FILE}"
    fi

    ((changed_count++))
done

echo ""
echo "=========================================="
echo "         CLEANUP SUMMARY"
echo "=========================================="
echo ""
if [[ "${DRY_RUN}" == true ]]; then
    echo -e "Would change:  ${YELLOW}${changed_count}${NC} files"
else
    echo -e "Changed:       ${GREEN}${changed_count}${NC} files"
fi
echo -e "Skipped:       ${skipped_count} files"
echo ""
echo "Log file:      ${LOG_FILE}"
echo "Backup file:   ${BACKUP_FILE}"
echo ""

if [[ "${DRY_RUN}" == true ]]; then
    echo "To apply changes, run:"
    echo "  sudo bash cleanup-suid.sh"
    echo ""
else
    echo "To verify changes:"
    echo "  ls -la ${CLEANUP_TARGETS[*]}"
    echo ""
    echo "To restore (if needed):"
    echo "  source ${BACKUP_FILE}"
    echo ""
    echo "To re-scan for compliance:"
    echo "  sudo bash ../openscap-scan.sh"
    echo ""
fi

# Append summary to log
{
    echo ""
    echo "## Summary"
    echo "- Changed: ${changed_count}"
    echo "- Skipped: ${skipped_count}"
    echo "- Dry Run: ${DRY_RUN}"
} >> "${LOG_FILE}"
