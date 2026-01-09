#!/bin/bash
# =============================================================================
# diagnose-connection.sh - Diagnose WordPress Database Connection Issues
# =============================================================================
#
# This script helps diagnose why WordPress cannot connect to a remote database
# when SELinux is in Enforcing mode.
#
# Usage: sudo bash diagnose-connection.sh
#
# =============================================================================

set -e

echo "============================================================"
echo "WordPress Database Connection Diagnosis"
echo "============================================================"
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "Error: This script requires root privileges"
    echo "Usage: sudo bash $0"
    exit 1
fi

# Step 1: Check SELinux status
echo "[Step 1] SELinux Status"
echo "------------------------------------------------------------"
SELINUX_MODE=$(getenforce)
echo "Current mode: $SELINUX_MODE"

if [ "$SELINUX_MODE" = "Disabled" ]; then
    echo "SELinux is disabled - this is not the cause of the issue"
    echo "Check network connectivity and database credentials instead"
    exit 0
fi

if [ "$SELINUX_MODE" = "Permissive" ]; then
    echo "SELinux is Permissive - issues are logged but not blocked"
    echo "If the app works in Permissive but not Enforcing, SELinux is the cause"
fi

echo ""

# Step 2: Check httpd process
echo "[Step 2] Web Server Process"
echo "------------------------------------------------------------"
if pgrep -x httpd > /dev/null 2>&1; then
    echo "Apache (httpd) is running"
    ps auxZ | grep httpd | head -3
elif pgrep -x nginx > /dev/null 2>&1; then
    echo "Nginx is running"
    ps auxZ | grep nginx | head -3
else
    echo "No web server process found"
    echo "Start the web server first: systemctl start httpd"
fi

echo ""

# Step 3: Check database-related Booleans
echo "[Step 3] Database Connection Booleans"
echo "------------------------------------------------------------"
echo ""
echo "Current Boolean status:"
echo ""

BOOLEANS=("httpd_can_network_connect_db" "httpd_can_network_connect")

for bool in "${BOOLEANS[@]}"; do
    STATUS=$(getsebool "$bool" 2>/dev/null | awk '{print $NF}')
    if [ "$STATUS" = "off" ]; then
        echo "  $bool --> $STATUS  [POTENTIAL ISSUE]"
    else
        echo "  $bool --> $STATUS  [OK]"
    fi
done

echo ""
echo "Boolean descriptions:"
semanage boolean -l | grep -E "httpd_can_network_connect_db|httpd_can_network_connect" | head -5

echo ""

# Step 4: Check recent AVC denials
echo "[Step 4] Recent AVC Denials (last 10 minutes)"
echo "------------------------------------------------------------"
echo ""

AVC_OUTPUT=$(ausearch -m avc -ts recent 2>/dev/null | grep -E "httpd|mysql|3306" || true)

if [ -z "$AVC_OUTPUT" ]; then
    echo "No recent httpd/database-related AVC denials found"
    echo ""
    echo "Possible reasons:"
    echo "  1. SELinux is not blocking the connection"
    echo "  2. The connection attempt hasn't happened recently"
    echo "  3. The denial happened earlier (check full audit log)"
    echo ""
    echo "Try: sudo ausearch -m avc | grep -E 'httpd|mysql|3306'"
else
    echo "Found AVC denials:"
    echo ""
    echo "$AVC_OUTPUT"
fi

echo ""

# Step 5: Analyze with audit2why
echo "[Step 5] Denial Analysis (audit2why)"
echo "------------------------------------------------------------"
echo ""

if command -v audit2why &> /dev/null; then
    ANALYSIS=$(ausearch -m avc -ts recent 2>/dev/null | audit2why 2>/dev/null | head -20 || true)
    if [ -n "$ANALYSIS" ]; then
        echo "$ANALYSIS"
    else
        echo "No analysis available - no recent denials to analyze"
    fi
else
    echo "audit2why not installed"
    echo "Install with: dnf install policycoreutils-python-utils"
fi

echo ""

# Step 6: Recommendation
echo "[Step 6] Recommendation"
echo "------------------------------------------------------------"
echo ""

DB_BOOL=$(getsebool httpd_can_network_connect_db 2>/dev/null | awk '{print $NF}')

if [ "$DB_BOOL" = "off" ]; then
    echo "The Boolean 'httpd_can_network_connect_db' is OFF"
    echo ""
    echo "This prevents httpd from connecting to database ports (3306, 5432, etc.)"
    echo ""
    echo "To fix, run:"
    echo "  sudo setsebool -P httpd_can_network_connect_db on"
    echo ""
    echo "Or use the fix script:"
    echo "  sudo bash fix-boolean.sh"
else
    echo "The Boolean 'httpd_can_network_connect_db' is already ON"
    echo ""
    echo "SELinux should not be blocking database connections"
    echo "Check other causes:"
    echo "  - Database credentials in wp-config.php"
    echo "  - Network connectivity (telnet, nc)"
    echo "  - Database server firewall/security groups"
fi

echo ""
echo "============================================================"
echo "Diagnosis complete"
echo "============================================================"
