#!/bin/bash
# =============================================================================
# Disk Space Mystery Scenario
# =============================================================================
# Demonstrates common causes of "invisible" disk space consumption
# in containerized environments.
#
# Usage: sudo ./disk-mystery-scenario.sh
# =============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== Disk Space Mystery Scenario ===${NC}"
echo ""
echo "Scenario: Zabbix alerts 'disk 100% full'"
echo "But when you check inside containers: du -sh / shows only 500MB"
echo "Where is the 'hidden' disk space?"
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Please run as root (sudo)${NC}"
    exit 1
fi

echo -e "${GREEN}=== Investigation Step 1: Host-level disk usage ===${NC}"
echo "  Command: df -h /var/lib/docker"
df -h /var/lib/docker 2>/dev/null || df -h /
echo ""

echo -e "${GREEN}=== Investigation Step 2: Docker space usage ===${NC}"
echo "  Command: docker system df"
if command -v docker &> /dev/null; then
    docker system df
else
    echo "  Docker not available"
fi
echo ""

echo -e "${GREEN}=== Investigation Step 3: Deleted but still-open files ===${NC}"
echo "  These files are deleted but processes still hold file handles"
echo "  The space is NOT freed until the process closes the file!"
echo ""
echo "  Command: lsof +L1 | head -15"
lsof +L1 2>/dev/null | head -15 || echo "  (no deleted open files found)"
echo ""

echo -e "${YELLOW}Common culprits:${NC}"
echo "  - Log files that were deleted while the app was still writing"
echo "  - Temp files created then 'deleted' but process still using"
echo ""
echo "  Fix options:"
echo "  1. Restart the process: docker restart <container>"
echo "  2. Truncate the file: : > /proc/<PID>/fd/<FD>"
echo ""

echo -e "${GREEN}=== Investigation Step 4: OverlayFS upper layer size ===${NC}"
echo ""
echo "  Container writes go to the 'upper' layer, not volumes!"
echo "  Large upper layers indicate data written inside the container."
echo ""

if command -v docker &> /dev/null; then
    CONTAINER_ID=$(docker ps -q | head -1)
    if [ -n "$CONTAINER_ID" ]; then
        echo "  Checking container: $CONTAINER_ID"
        UPPER_DIR=$(docker inspect --format '{{.GraphDriver.Data.UpperDir}}' "$CONTAINER_ID" 2>/dev/null)
        if [ -n "$UPPER_DIR" ] && [ -d "$UPPER_DIR" ]; then
            echo "  Upper dir: $UPPER_DIR"
            echo "  Size: $(du -sh "$UPPER_DIR" 2>/dev/null | cut -f1)"
        fi
    else
        echo "  (no running containers to check)"
    fi
fi
echo ""
echo "  If upper layer is large, the container is writing data"
echo "  that should go to a volume instead!"
echo ""

echo -e "${GREEN}=== Investigation Step 5: Dangling images and volumes ===${NC}"
echo ""
echo "  Command: docker system df -v"
echo ""
if command -v docker &> /dev/null; then
    docker system df -v 2>/dev/null | head -30 || true
fi
echo ""

echo -e "${GREEN}=== Investigation Step 6: Check from inside container ===${NC}"
echo ""
if command -v docker &> /dev/null; then
    CONTAINER_ID=$(docker ps -q | head -1)
    if [ -n "$CONTAINER_ID" ]; then
        PID=$(docker inspect --format '{{.State.Pid}}' "$CONTAINER_ID")
        echo "  Using nsenter to check from container's perspective:"
        echo "  Command: nsenter -t $PID -m df -h"
        nsenter -t "$PID" -m df -h 2>/dev/null || true
    fi
fi
echo ""

echo -e "${BLUE}=== Cleanup Commands ===${NC}"
echo ""
echo "  # Remove unused containers, networks, images"
echo "  docker system prune"
echo ""
echo "  # Also remove unused volumes (CAREFUL!)"
echo "  docker system prune --volumes"
echo ""
echo "  # Remove dangling images only"
echo "  docker image prune"
echo ""

echo -e "${BLUE}=== Summary ===${NC}"
echo ""
echo "Hidden disk space is usually caused by:"
echo ""
echo "1. Deleted but open files (lsof +L1)"
echo "   - Fix: restart process or truncate via /proc/PID/fd/FD"
echo ""
echo "2. OverlayFS upper layer growth"
echo "   - Container writing to filesystem instead of volume"
echo "   - Fix: use volumes for data, not overlay"
echo ""
echo "3. Docker logs (JSON files)"
echo "   - /var/lib/docker/containers/<id>/<id>-json.log"
echo "   - Fix: configure log rotation"
echo ""
echo "4. Dangling images/volumes"
echo "   - Fix: docker system prune --volumes"
echo ""
