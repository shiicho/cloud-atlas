#!/bin/bash
# =============================================================================
# cleanup.sh - Remove MyApp Service Stack
# =============================================================================
# This script removes all MyApp components from the system
#
# Usage: sudo ./cleanup.sh
# =============================================================================

set -e

echo "=============================================="
echo "  MyApp Cleanup Script"
echo "=============================================="

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "ERROR: Please run as root (sudo ./cleanup.sh)"
    exit 1
fi

echo ""
read -p "This will remove all MyApp components. Continue? (y/n): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 0
fi

# Step 1: Stop services
echo ""
echo "=== Step 1: Stopping services ==="

systemctl stop myapp-health.timer 2>/dev/null || true
systemctl stop myapp-logrotate.timer 2>/dev/null || true
systemctl stop myapp.service 2>/dev/null || true

systemctl disable myapp.service 2>/dev/null || true
systemctl disable myapp-health.timer 2>/dev/null || true
systemctl disable myapp-logrotate.timer 2>/dev/null || true

echo "Services stopped"

# Step 2: Remove unit files
echo ""
echo "=== Step 2: Removing unit files ==="

rm -f /etc/systemd/system/myapp.service
rm -rf /etc/systemd/system/myapp.service.d
rm -f /etc/systemd/system/myapp-health.service
rm -f /etc/systemd/system/myapp-health.timer
rm -f /etc/systemd/system/myapp-logrotate.service
rm -f /etc/systemd/system/myapp-logrotate.timer

systemctl daemon-reload

echo "Unit files removed"

# Step 3: Remove application
echo ""
echo "=== Step 3: Removing application files ==="

rm -rf /opt/myapp
rm -rf /var/lib/myapp
rm -rf /var/log/myapp

echo "Application files removed"

# Step 4: Remove user
echo ""
echo "=== Step 4: Removing user ==="

if id -u myapp &>/dev/null; then
    userdel myapp 2>/dev/null || true
    echo "User myapp removed"
else
    echo "User myapp not found"
fi

echo ""
echo "=============================================="
echo "  Cleanup Complete!"
echo "=============================================="
