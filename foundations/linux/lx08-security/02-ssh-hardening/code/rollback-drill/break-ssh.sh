#!/bin/bash
# =============================================================================
# SSH Misconfiguration Drill - break-ssh.sh
# =============================================================================
#
# PURPOSE: Create a controlled SSH misconfiguration for recovery practice
#
# WARNING:
#   - ONLY run in a TEST environment
#   - ONLY run if you have console/IPMI/VNC access as backup
#   - This WILL break SSH access temporarily
#
# WHAT IT DOES:
#   1. Backs up current sshd_config
#   2. Creates a broken configuration
#   3. Reloads sshd (breaking SSH access)
#
# RECOVERY:
#   See rescue-steps.md in this directory
#
# =============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}ERROR: This script must be run as root${NC}"
   echo "Usage: sudo $0"
   exit 1
fi

# Safety check
echo -e "${YELLOW}"
echo "========================================"
echo "     SSH MISCONFIGURATION DRILL"
echo "========================================"
echo -e "${NC}"
echo "This script will:"
echo "  1. Backup current SSH configuration"
echo "  2. Create a BROKEN configuration"
echo "  3. Reload sshd (breaking SSH access)"
echo ""
echo -e "${RED}WARNING: You will NOT be able to SSH after this!${NC}"
echo ""
echo "Make sure you have:"
echo "  [ ] Console access (VNC/IPMI/Cloud Console)"
echo "  [ ] Another root terminal still open"
echo "  [ ] Read rescue-steps.md"
echo ""
read -p "Type 'BREAK IT' to continue (or anything else to cancel): " confirm

if [[ "$confirm" != "BREAK IT" ]]; then
    echo "Cancelled. No changes made."
    exit 0
fi

# Create backup timestamp
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="/etc/ssh/sshd_config.backup_${TIMESTAMP}"

echo ""
echo -e "${GREEN}Step 1: Backing up current configuration${NC}"
cp /etc/ssh/sshd_config "$BACKUP_FILE"
echo "Backup saved to: $BACKUP_FILE"

# Create broken configuration
echo ""
echo -e "${YELLOW}Step 2: Creating broken configuration${NC}"

# Choose a random misconfiguration type
BREAK_TYPE=$((RANDOM % 3))

case $BREAK_TYPE in
    0)
        echo "Misconfiguration type: Invalid AllowUsers directive"
        # Add an AllowUsers line with a non-existent user
        echo "" >> /etc/ssh/sshd_config
        echo "# DRILL: Broken config - invalid AllowUsers" >> /etc/ssh/sshd_config
        echo "AllowUsers nonexistent_user_drill_12345" >> /etc/ssh/sshd_config
        ;;
    1)
        echo "Misconfiguration type: Syntax error"
        # Add a syntax error
        echo "" >> /etc/ssh/sshd_config
        echo "# DRILL: Broken config - syntax error" >> /etc/ssh/sshd_config
        echo "InvalidOptionName yes" >> /etc/ssh/sshd_config
        ;;
    2)
        echo "Misconfiguration type: Disabled all authentication"
        # Disable all authentication methods
        echo "" >> /etc/ssh/sshd_config
        echo "# DRILL: Broken config - all auth disabled" >> /etc/ssh/sshd_config
        echo "PasswordAuthentication no" >> /etc/ssh/sshd_config
        echo "PubkeyAuthentication no" >> /etc/ssh/sshd_config
        echo "KbdInteractiveAuthentication no" >> /etc/ssh/sshd_config
        ;;
esac

echo ""
echo -e "${YELLOW}Step 3: Testing configuration (this will show the error)${NC}"
echo ""

# Show the error but continue
if ! sshd -t; then
    echo ""
    echo -e "${RED}Configuration has errors (this is expected for drill)${NC}"
else
    echo ""
    echo -e "${YELLOW}Configuration is valid syntax but will cause login issues${NC}"
fi

echo ""
echo -e "${RED}Step 4: Reloading sshd with broken config${NC}"
echo ""
read -p "Last chance to cancel. Press Enter to break SSH or Ctrl+C to cancel..."

# Try reload first (safer, existing connections survive)
if systemctl reload sshd 2>/dev/null || service sshd reload 2>/dev/null; then
    echo "sshd reloaded"
else
    # If reload fails (syntax error), restart will also fail but that's the point
    echo "Reload failed (expected for syntax errors)"
    echo "Attempting restart..."
    systemctl restart sshd 2>/dev/null || service sshd restart 2>/dev/null || true
fi

echo ""
echo "========================================"
echo -e "${RED}SSH IS NOW BROKEN!${NC}"
echo "========================================"
echo ""
echo "Your current session should still work."
echo "New SSH connections will FAIL."
echo ""
echo "To recover:"
echo "  1. Use this terminal or console access"
echo "  2. Run: cp $BACKUP_FILE /etc/ssh/sshd_config"
echo "  3. Run: sshd -t"
echo "  4. Run: systemctl reload sshd"
echo ""
echo "See rescue-steps.md for detailed recovery instructions."
echo ""
echo "Backup file: $BACKUP_FILE"
echo ""
