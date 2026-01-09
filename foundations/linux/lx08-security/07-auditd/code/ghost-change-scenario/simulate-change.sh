#!/bin/bash
# =============================================================================
# simulate-change.sh - Simulate the unauthorized configuration change
# =============================================================================
# Part of: Ghost Configuration Change Scenario
# Course: LX08-SECURITY Lesson 07 - auditd
# =============================================================================

set -e

echo "=========================================="
echo "Simulating unauthorized SSH config change"
echo "=========================================="
echo ""

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo "Error: This script must be run as root (via sudo)"
   echo "Usage: sudo bash simulate-change.sh"
   exit 1
fi

# Record the current user (for investigation)
CURRENT_USER=$(who am i | awk '{print $1}')
if [[ -z "$CURRENT_USER" ]]; then
    CURRENT_USER=$SUDO_USER
fi

echo "Simulation info (for instructor, not shown in logs):"
echo "  - Current user: $CURRENT_USER"
echo "  - Current time: $(date)"
echo "  - auid should be: $(cat /proc/self/loginuid)"
echo ""

echo "[1/3] Recording current PermitRootLogin setting..."
CURRENT_SETTING=$(grep -E "^#?PermitRootLogin" /etc/ssh/sshd_config | tail -1 || echo "not found")
echo "      Current setting: $CURRENT_SETTING"
echo ""

echo "[2/3] Making the 'unauthorized' change..."
echo "      Simulating: Someone changed PermitRootLogin to 'yes'"
echo ""

# Create a temporary file and make the change
# This simulates using vim/nano to edit the file
TEMP_FILE=$(mktemp)
cat /etc/ssh/sshd_config > "$TEMP_FILE"

# If PermitRootLogin exists (commented or not), replace it
# Otherwise, add it
if grep -qE "^#?PermitRootLogin" "$TEMP_FILE"; then
    sed -i 's/^#*PermitRootLogin.*/PermitRootLogin yes/' "$TEMP_FILE"
else
    echo "PermitRootLogin yes" >> "$TEMP_FILE"
fi

# Copy the changed file back (this triggers the audit event)
cp "$TEMP_FILE" /etc/ssh/sshd_config
rm "$TEMP_FILE"

echo "      Change applied!"
echo ""

echo "[3/3] Verifying the change..."
NEW_SETTING=$(grep "^PermitRootLogin" /etc/ssh/sshd_config | tail -1)
echo "      New setting: $NEW_SETTING"
echo ""

# Validate sshd config (important for safety)
echo "Validating sshd configuration syntax..."
if sshd -t; then
    echo "      Configuration is valid"
else
    echo "      WARNING: Configuration has errors!"
fi

echo ""
echo "=========================================="
echo "Simulation complete!"
echo "=========================================="
echo ""
echo "The 'unauthorized' change has been made."
echo ""
echo "In a real scenario, this would be discovered during:"
echo "  - Regular security audits"
echo "  - Configuration management drift detection"
echo "  - Compliance scanning"
echo ""
echo "Now run: sudo bash investigate.sh"
echo ""
echo "IMPORTANT: Run cleanup.sh after investigation to restore the config!"
echo ""
