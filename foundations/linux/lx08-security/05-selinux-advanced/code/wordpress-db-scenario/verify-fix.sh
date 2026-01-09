#!/bin/bash
# =============================================================================
# verify-fix.sh - Verify SELinux Boolean Fix
# =============================================================================
#
# This script verifies that the httpd_can_network_connect_db Boolean is
# correctly enabled and the fix is working.
#
# Usage: sudo bash verify-fix.sh
#
# =============================================================================

set -e

echo "============================================================"
echo "Verify: httpd_can_network_connect_db Fix"
echo "============================================================"
echo ""

# Check 1: Boolean status
echo "[Check 1] Boolean Status"
echo "------------------------------------------------------------"
STATUS=$(getsebool httpd_can_network_connect_db | awk '{print $NF}')
echo "httpd_can_network_connect_db: $STATUS"

if [ "$STATUS" = "on" ]; then
    echo "PASS: Boolean is enabled"
    BOOL_OK=1
else
    echo "FAIL: Boolean is not enabled"
    echo ""
    echo "Run: sudo setsebool -P httpd_can_network_connect_db on"
    BOOL_OK=0
fi

echo ""

# Check 2: SELinux mode
echo "[Check 2] SELinux Mode"
echo "------------------------------------------------------------"
MODE=$(getenforce)
echo "Current mode: $MODE"

if [ "$MODE" = "Enforcing" ]; then
    echo "PASS: SELinux is Enforcing (production mode)"
    MODE_OK=1
elif [ "$MODE" = "Permissive" ]; then
    echo "WARNING: SELinux is Permissive (testing mode)"
    echo "Remember to switch to Enforcing: sudo setenforce 1"
    MODE_OK=1
else
    echo "FAIL: SELinux is Disabled"
    MODE_OK=0
fi

echo ""

# Check 3: No recent AVC denials for httpd + database
echo "[Check 3] AVC Denials"
echo "------------------------------------------------------------"

if [ "$EUID" -eq 0 ]; then
    RECENT_AVC=$(ausearch -m avc -ts recent 2>/dev/null | grep -c "httpd.*name_connect" || echo 0)

    if [ "$RECENT_AVC" -eq 0 ]; then
        echo "PASS: No recent database connection denials"
        AVC_OK=1
    else
        echo "WARNING: Found $RECENT_AVC recent AVC denials"
        echo ""
        echo "Details:"
        ausearch -m avc -ts recent 2>/dev/null | grep "httpd.*name_connect" | tail -3
        AVC_OK=0
    fi
else
    echo "SKIP: Need root to check audit log"
    AVC_OK=1
fi

echo ""

# Check 4: Web server process
echo "[Check 4] Web Server"
echo "------------------------------------------------------------"

if pgrep -x httpd > /dev/null 2>&1; then
    echo "PASS: Apache (httpd) is running"
    HTTP_OK=1
elif pgrep -x nginx > /dev/null 2>&1; then
    echo "PASS: Nginx is running"
    HTTP_OK=1
else
    echo "WARNING: No web server running"
    echo "Start with: sudo systemctl start httpd"
    HTTP_OK=0
fi

echo ""

# Check 5: Change log
echo "[Check 5] Change Log"
echo "------------------------------------------------------------"
LOGFILE="/var/log/selinux-changes.log"

if [ -f "$LOGFILE" ]; then
    echo "Recent SELinux changes:"
    tail -5 "$LOGFILE" 2>/dev/null || echo "(no entries)"
else
    echo "No change log found at $LOGFILE"
fi

echo ""

# Summary
echo "============================================================"
echo "Summary"
echo "============================================================"
echo ""

TOTAL=0
PASSED=0

for check in BOOL_OK MODE_OK AVC_OK HTTP_OK; do
    TOTAL=$((TOTAL + 1))
    if [ "${!check}" -eq 1 ]; then
        PASSED=$((PASSED + 1))
    fi
done

echo "Passed: $PASSED / $TOTAL"
echo ""

if [ "$PASSED" -eq "$TOTAL" ]; then
    echo "All checks passed!"
    echo ""
    echo "The SELinux Boolean fix is correctly applied."
    echo "WordPress should now be able to connect to the remote database."
else
    echo "Some checks did not pass."
    echo ""
    echo "Review the output above and address any FAIL or WARNING items."
fi

echo ""
echo "============================================================"
