#!/bin/bash
# =============================================================================
# cleanup.sh - Clean up after the Ghost Configuration Change scenario
# =============================================================================
# Part of: Ghost Configuration Change Scenario
# Course: LX08-SECURITY Lesson 07 - auditd
# =============================================================================

set -e

echo "=========================================="
echo "Cleaning up scenario"
echo "=========================================="
echo ""

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo "Error: This script must be run as root"
   echo "Usage: sudo bash cleanup.sh"
   exit 1
fi

echo "[1/3] Restoring sshd_config..."
if [[ -f /etc/ssh/sshd_config.scenario-backup ]]; then
    cp /etc/ssh/sshd_config.scenario-backup /etc/ssh/sshd_config
    echo "      Restored from backup"

    # Validate the config
    if sshd -t; then
        echo "      Configuration validated successfully"
    else
        echo "      WARNING: Configuration validation failed!"
        echo "      Please check /etc/ssh/sshd_config manually"
    fi

    # Optionally remove backup
    read -p "      Remove backup file? [y/N] " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        rm /etc/ssh/sshd_config.scenario-backup
        echo "      Backup removed"
    else
        echo "      Backup kept at /etc/ssh/sshd_config.scenario-backup"
    fi
else
    echo "      No backup found. Cannot restore."
    echo "      Please check /etc/ssh/sshd_config manually"
fi
echo ""

echo "[2/3] Removing audit rule..."
if auditctl -l | grep -q "key=ssh_config_scenario"; then
    auditctl -W /etc/ssh/sshd_config -p wa -k ssh_config_scenario
    echo "      Rule removed"
else
    echo "      Rule not found (already removed or never added)"
fi
echo ""

echo "[3/3] Verifying cleanup..."
echo ""
echo "Current PermitRootLogin setting:"
grep "^PermitRootLogin" /etc/ssh/sshd_config || echo "  (not explicitly set or commented out)"
echo ""
echo "Current audit rules for ssh_config_scenario:"
auditctl -l | grep ssh_config_scenario || echo "  None found (good)"
echo ""

echo "=========================================="
echo "Cleanup complete!"
echo "=========================================="
echo ""
echo "The scenario environment has been cleaned up."
echo ""
echo "What you learned:"
echo "  1. How to set up audit rules for file monitoring"
echo "  2. How to use ausearch to find events by key"
echo "  3. How auid tracks the original user even after sudo"
echo "  4. How to interpret audit log fields"
echo ""
echo "Key takeaway:"
echo "  auid (Audit User ID) is your best friend for accountability."
echo "  It never changes, even when users sudo to root."
echo ""
