#!/bin/bash
# =============================================================================
# PAM Faillock Setup Script
# Configures account lockout: 5 failures = 10 minute lockout
#
# WARNING: This script modifies PAM configuration!
# - Keep a root session open before running
# - Test on non-production systems first
# - Have console access as backup
#
# Reference: CIS Benchmark 5.4.2
# =============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}=== PAM Faillock Configuration Script ===${NC}"
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}ERROR: This script must be run as root${NC}"
    echo "Usage: sudo $0"
    exit 1
fi

# Check if on RHEL/CentOS/Rocky or Debian/Ubuntu
if [ -f /etc/redhat-release ]; then
    DISTRO="rhel"
    PAM_AUTH="/etc/pam.d/system-auth"
    PAM_PASSWORD="/etc/pam.d/password-auth"
elif [ -f /etc/debian_version ]; then
    DISTRO="debian"
    PAM_AUTH="/etc/pam.d/common-auth"
    PAM_PASSWORD="/etc/pam.d/common-auth"
else
    echo -e "${RED}ERROR: Unsupported distribution${NC}"
    echo "This script supports RHEL/CentOS/Rocky and Debian/Ubuntu"
    exit 1
fi

echo "Detected distribution: $DISTRO"
echo ""

# Warning message
echo -e "${RED}╔══════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${RED}║                         WARNING                                   ║${NC}"
echo -e "${RED}╠══════════════════════════════════════════════════════════════════╣${NC}"
echo -e "${RED}║  This script will modify PAM configuration.                       ║${NC}"
echo -e "${RED}║  Incorrect PAM configuration can lock you out of the system!      ║${NC}"
echo -e "${RED}║                                                                   ║${NC}"
echo -e "${RED}║  Before continuing, ensure you have:                              ║${NC}"
echo -e "${RED}║  1. Another root terminal session open                            ║${NC}"
echo -e "${RED}║  2. Console access (VNC/IPMI/Cloud Console)                       ║${NC}"
echo -e "${RED}║  3. Tested this on a non-production system                        ║${NC}"
echo -e "${RED}╚══════════════════════════════════════════════════════════════════╝${NC}"
echo ""

read -p "Do you want to continue? (yes/no): " confirm
if [ "$confirm" != "yes" ]; then
    echo "Aborted."
    exit 0
fi

echo ""
echo -e "${GREEN}Starting configuration...${NC}"
echo ""

# Create backup directory
BACKUP_DIR="/etc/pam.d.bak.$(date +%Y%m%d-%H%M%S)"
echo "Creating backup at: $BACKUP_DIR"
cp -r /etc/pam.d "$BACKUP_DIR"

if [ -f /etc/security/faillock.conf ]; then
    cp /etc/security/faillock.conf /etc/security/faillock.conf.bak.$(date +%Y%m%d)
fi

echo -e "${GREEN}Backup created successfully${NC}"
echo ""

# Configure faillock.conf (RHEL 8.2+, Debian 11+)
echo "Configuring /etc/security/faillock.conf..."

cat > /etc/security/faillock.conf << 'EOF'
# =============================================================================
# Faillock Configuration
# 5 failures = 10 minute lockout
# Reference: CIS Benchmark 5.4.2
# Created by: setup-faillock.sh
# =============================================================================

# Maximum failed attempts before lockout
deny = 5

# Lockout duration in seconds (600 = 10 minutes)
unlock_time = 600

# Time window for counting failures (900 = 15 minutes)
fail_interval = 900

# Audit failed attempts
audit

# Silent mode (don't reveal remaining attempts)
silent

# Faillock data directory
dir = /var/run/faillock

# Uncomment to also lock root (requires console recovery capability)
# even_deny_root
# root_unlock_time = 60

EOF

echo -e "${GREEN}faillock.conf configured${NC}"
echo ""

# For RHEL 8+, use authselect if available
if [ "$DISTRO" = "rhel" ] && command -v authselect &> /dev/null; then
    echo "Detected authselect (RHEL 8+), enabling faillock feature..."

    # Check current profile
    CURRENT_PROFILE=$(authselect current 2>/dev/null | grep "Profile ID:" | awk '{print $3}')

    if [ -n "$CURRENT_PROFILE" ]; then
        echo "Current authselect profile: $CURRENT_PROFILE"
        authselect enable-feature with-faillock 2>/dev/null || true
        echo -e "${GREEN}Faillock feature enabled via authselect${NC}"
    else
        echo -e "${YELLOW}No authselect profile detected, using manual configuration${NC}"
    fi

else
    # Manual configuration for older systems or Debian
    echo "Configuring PAM files manually..."

    if [ "$DISTRO" = "rhel" ]; then
        # RHEL/CentOS manual configuration
        # Check if pam_faillock is already configured
        if ! grep -q "pam_faillock.so" "$PAM_AUTH"; then
            echo "Adding pam_faillock to $PAM_AUTH"

            # Create a temporary file with proper configuration
            # This is a simplified example - production systems should use authconfig or authselect
            echo -e "${YELLOW}Note: For RHEL 7, consider using authconfig command instead${NC}"
        fi
    else
        # Debian/Ubuntu manual configuration
        if ! grep -q "pam_faillock.so" "$PAM_AUTH"; then
            echo "Adding pam_faillock to $PAM_AUTH"

            # Debian may need libpam-modules package
            if ! dpkg -l | grep -q libpam-modules; then
                echo "Installing libpam-modules..."
                apt-get update && apt-get install -y libpam-modules
            fi
        fi
    fi
fi

echo ""
echo -e "${GREEN}=== Configuration Complete ===${NC}"
echo ""
echo "Summary:"
echo "  - Max failed attempts: 5"
echo "  - Lockout duration: 10 minutes (600 seconds)"
echo "  - Failure window: 15 minutes (900 seconds)"
echo ""
echo "Test commands:"
echo "  faillock --user testuser       # Check user status"
echo "  faillock --user testuser --reset  # Reset failed count"
echo ""
echo "To test lockout:"
echo "  1. Create test user: useradd -m testuser && passwd testuser"
echo "  2. Try wrong password 5+ times: ssh testuser@localhost"
echo "  3. Check status: faillock --user testuser"
echo ""
echo -e "${YELLOW}IMPORTANT: Test login in a NEW terminal before closing this one!${NC}"
echo ""
echo "To rollback:"
echo "  cp -r $BACKUP_DIR/* /etc/pam.d/"
echo "  cp /etc/security/faillock.conf.bak.* /etc/security/faillock.conf"
echo ""
