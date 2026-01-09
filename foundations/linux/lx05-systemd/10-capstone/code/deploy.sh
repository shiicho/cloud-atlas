#!/bin/bash
# =============================================================================
# deploy.sh - Deploy MyApp Service Stack
# =============================================================================
# This script deploys all MyApp components to a Linux system
#
# Usage: sudo ./deploy.sh
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=============================================="
echo "  MyApp Deployment Script"
echo "=============================================="

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "ERROR: Please run as root (sudo ./deploy.sh)"
    exit 1
fi

# Step 1: Create user and directories
echo ""
echo "=== Step 1: Creating user and directories ==="

if ! id -u myapp &>/dev/null; then
    useradd -r -s /sbin/nologin -d /opt/myapp myapp
    echo "Created user: myapp"
else
    echo "User myapp already exists"
fi

mkdir -p /opt/myapp/{bin,config,logs,data}
mkdir -p /var/lib/myapp
mkdir -p /var/log/myapp

chown -R myapp:myapp /opt/myapp /var/lib/myapp /var/log/myapp
chmod 755 /opt/myapp
chmod 750 /opt/myapp/config

echo "Directories created"

# Step 2: Install scripts
echo ""
echo "=== Step 2: Installing scripts ==="

cp "$SCRIPT_DIR/scripts/myapp" /opt/myapp/bin/myapp
cp "$SCRIPT_DIR/scripts/health-check" /opt/myapp/bin/health-check
cp "$SCRIPT_DIR/scripts/logrotate" /opt/myapp/bin/logrotate

chmod +x /opt/myapp/bin/myapp
chmod +x /opt/myapp/bin/health-check
chmod +x /opt/myapp/bin/logrotate

chown myapp:myapp /opt/myapp/bin/*

echo "Scripts installed"

# Step 3: Install systemd units
echo ""
echo "=== Step 3: Installing systemd units ==="

cp "$SCRIPT_DIR/myapp.service" /etc/systemd/system/
cp "$SCRIPT_DIR/myapp-health.service" /etc/systemd/system/
cp "$SCRIPT_DIR/myapp-health.timer" /etc/systemd/system/
cp "$SCRIPT_DIR/myapp-logrotate.service" /etc/systemd/system/
cp "$SCRIPT_DIR/myapp-logrotate.timer" /etc/systemd/system/

mkdir -p /etc/systemd/system/myapp.service.d
cp "$SCRIPT_DIR/myapp.service.d/10-resources.conf" /etc/systemd/system/myapp.service.d/
cp "$SCRIPT_DIR/myapp.service.d/20-security.conf" /etc/systemd/system/myapp.service.d/

echo "Unit files installed"

# Step 4: Reload and verify
echo ""
echo "=== Step 4: Reload and verify ==="

systemctl daemon-reload

echo "Verifying unit files..."
for unit in myapp.service myapp-health.service myapp-health.timer myapp-logrotate.service myapp-logrotate.timer; do
    if systemd-analyze verify "/etc/systemd/system/$unit" 2>&1 | grep -q "error\|Error"; then
        echo "  $unit: FAILED"
        systemd-analyze verify "/etc/systemd/system/$unit"
    else
        echo "  $unit: OK"
    fi
done

# Step 5: Security audit
echo ""
echo "=== Step 5: Security audit ==="
echo "Running: systemd-analyze security myapp.service"
SCORE=$(systemd-analyze security myapp.service 2>/dev/null | tail -1 | awk '{print $NF}')
echo "Security score: $SCORE"

# Step 6: Enable and start services
echo ""
echo "=== Step 6: Enable and start services ==="

read -p "Do you want to start the services now? (y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    systemctl enable myapp.service
    systemctl enable myapp-health.timer
    systemctl enable myapp-logrotate.timer

    systemctl start myapp.service
    sleep 3
    systemctl start myapp-health.timer
    systemctl start myapp-logrotate.timer

    echo ""
    echo "Services started!"
    echo ""
    systemctl status myapp.service --no-pager
    echo ""
    systemctl list-timers --all | grep myapp
fi

echo ""
echo "=============================================="
echo "  Deployment Complete!"
echo "=============================================="
echo ""
echo "Commands to manage MyApp:"
echo "  systemctl status myapp.service"
echo "  systemctl list-timers | grep myapp"
echo "  journalctl -u myapp.service -f"
echo "  systemd-analyze security myapp.service"
