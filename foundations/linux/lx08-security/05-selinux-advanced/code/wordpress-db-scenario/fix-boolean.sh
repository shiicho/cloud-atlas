#!/bin/bash
# =============================================================================
# fix-boolean.sh - Fix WordPress Database Connection via SELinux Boolean
# =============================================================================
#
# This script enables the httpd_can_network_connect_db Boolean to allow
# Apache/httpd to connect to remote database servers.
#
# Usage: sudo bash fix-boolean.sh
#
# =============================================================================

set -e

echo "============================================================"
echo "Fix: Enable httpd_can_network_connect_db"
echo "============================================================"
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "Error: This script requires root privileges"
    echo "Usage: sudo bash $0"
    exit 1
fi

# Record the change for audit trail
LOGFILE="/var/log/selinux-changes.log"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
USER=$(logname 2>/dev/null || echo "$SUDO_USER")

# Step 1: Check current status
echo "[Step 1] Current Status"
echo "------------------------------------------------------------"
BEFORE=$(getsebool httpd_can_network_connect_db | awk '{print $NF}')
echo "httpd_can_network_connect_db: $BEFORE"

if [ "$BEFORE" = "on" ]; then
    echo ""
    echo "Boolean is already enabled. No changes needed."
    exit 0
fi

echo ""

# Step 2: Confirm before making changes
echo "[Step 2] Confirmation"
echo "------------------------------------------------------------"
echo ""
echo "This will enable the following SELinux Boolean:"
echo "  httpd_can_network_connect_db"
echo ""
echo "Effect:"
echo "  - httpd processes can connect to database ports"
echo "  - Affects MySQL (3306), PostgreSQL (5432), etc."
echo ""
echo "This change is PERMANENT (persists across reboots)"
echo ""

read -p "Proceed? [y/N] " -n 1 -r
echo ""

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 0
fi

echo ""

# Step 3: Apply the change
echo "[Step 3] Applying Change"
echo "------------------------------------------------------------"
echo "Running: setsebool -P httpd_can_network_connect_db on"
echo ""

setsebool -P httpd_can_network_connect_db on

echo "Done."
echo ""

# Step 4: Verify
echo "[Step 4] Verification"
echo "------------------------------------------------------------"
AFTER=$(getsebool httpd_can_network_connect_db | awk '{print $NF}')
echo "httpd_can_network_connect_db: $AFTER"

if [ "$AFTER" = "on" ]; then
    echo ""
    echo "SUCCESS: Boolean is now enabled"
else
    echo ""
    echo "WARNING: Boolean change may not have taken effect"
    exit 1
fi

echo ""

# Step 5: Log the change
echo "[Step 5] Logging Change"
echo "------------------------------------------------------------"

LOG_ENTRY="${TIMESTAMP} - setsebool -P httpd_can_network_connect_db on - WordPress RDS connection - User: ${USER}"
echo "$LOG_ENTRY" >> "$LOGFILE"
echo "Logged to: $LOGFILE"
echo "Entry: $LOG_ENTRY"

echo ""

# Step 6: Next steps
echo "[Step 6] Next Steps"
echo "------------------------------------------------------------"
echo ""
echo "1. Test the WordPress database connection:"
echo "   curl -I http://localhost/"
echo ""
echo "2. Check WordPress dashboard for database errors"
echo ""
echo "3. If still failing, check:"
echo "   - Database credentials in wp-config.php"
echo "   - Network connectivity to database server"
echo "   - Database server firewall/security groups"
echo ""
echo "4. Rollback command (if needed):"
echo "   sudo setsebool -P httpd_can_network_connect_db off"
echo ""

echo "============================================================"
echo "Fix applied successfully"
echo "============================================================"
