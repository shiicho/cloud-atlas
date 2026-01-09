#!/bin/bash
# =============================================================================
# setup-audit.sh - Set up audit rules for SSH config monitoring
# =============================================================================
# Part of: Ghost Configuration Change Scenario
# Course: LX08-SECURITY Lesson 07 - auditd
# =============================================================================

set -e

echo "=========================================="
echo "Setting up audit rules for SSH config"
echo "=========================================="
echo ""

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo "Error: This script must be run as root"
   echo "Usage: sudo bash setup-audit.sh"
   exit 1
fi

# Check if auditd is running
if ! systemctl is-active --quiet auditd; then
    echo "Warning: auditd is not running. Starting it..."
    systemctl start auditd
fi

echo "[1/3] Backing up sshd_config..."
if [[ ! -f /etc/ssh/sshd_config.scenario-backup ]]; then
    cp /etc/ssh/sshd_config /etc/ssh/sshd_config.scenario-backup
    echo "      Backup created: /etc/ssh/sshd_config.scenario-backup"
else
    echo "      Backup already exists, skipping"
fi

echo ""
echo "[2/3] Adding audit rule for sshd_config..."

# Check if rule already exists
if auditctl -l | grep -q "key=ssh_config_scenario"; then
    echo "      Rule already exists, removing old rule first..."
    auditctl -W /etc/ssh/sshd_config -p wa -k ssh_config_scenario 2>/dev/null || true
fi

# Add the audit rule
auditctl -w /etc/ssh/sshd_config -p wa -k ssh_config_scenario
echo "      Rule added: -w /etc/ssh/sshd_config -p wa -k ssh_config_scenario"

echo ""
echo "[3/3] Verifying rule..."
echo ""
echo "Current audit rules for ssh_config:"
auditctl -l | grep ssh_config || echo "      No rules found (unexpected)"

echo ""
echo "=========================================="
echo "Setup complete!"
echo "=========================================="
echo ""
echo "Next steps:"
echo "  1. Run simulate-change.sh to create the 'unauthorized' change"
echo "     (Preferably from a different terminal or as a different user)"
echo ""
echo "  2. Run investigate.sh to find who made the change"
echo ""
echo "  3. When done, run cleanup.sh to restore configuration"
echo ""
