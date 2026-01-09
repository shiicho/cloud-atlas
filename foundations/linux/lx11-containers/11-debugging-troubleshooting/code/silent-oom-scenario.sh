#!/bin/bash
# =============================================================================
# Silent OOM Kill Scenario
# =============================================================================
# Simulates a "silent" OOM kill - the process disappears without any
# application logs. Demonstrates how to find evidence on the host.
#
# Usage: sudo ./silent-oom-scenario.sh
# =============================================================================

set -e

CGROUP_NAME="silent-oom-demo"
CGROUP_PATH="/sys/fs/cgroup/${CGROUP_NAME}"
MEMORY_LIMIT="50M"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== Silent OOM Kill Scenario ===${NC}"
echo ""
echo "This demo simulates a batch job that 'silently' disappears."
echo "You'll learn how to find the evidence on the host."
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Please run as root (sudo)${NC}"
    exit 1
fi

# Check cgroup v2
if ! mount | grep -q "cgroup2"; then
    echo -e "${RED}This system does not appear to use cgroup v2${NC}"
    exit 1
fi

# Cleanup function
cleanup() {
    echo ""
    echo -e "${YELLOW}Cleaning up...${NC}"
    rmdir "$CGROUP_PATH" 2>/dev/null || true
}
trap cleanup EXIT

# Check for stress command
if ! command -v stress &> /dev/null; then
    echo -e "${YELLOW}Installing stress tool...${NC}"
    apt-get install -y stress 2>/dev/null || dnf install -y stress 2>/dev/null || {
        echo -e "${RED}Please install 'stress' package manually${NC}"
        exit 1
    }
fi

echo -e "${GREEN}Step 1: Creating cgroup with ${MEMORY_LIMIT} memory limit${NC}"
mkdir -p "$CGROUP_PATH"
echo "$MEMORY_LIMIT" > "${CGROUP_PATH}/memory.max"
echo "  Created: $CGROUP_PATH"
echo "  Memory limit: $(cat ${CGROUP_PATH}/memory.max)"
echo ""

echo -e "${GREEN}Step 2: Recording initial memory.events${NC}"
echo "  Before:"
cat "${CGROUP_PATH}/memory.events"
echo ""

echo -e "${GREEN}Step 3: Running 'batch job' (stress --vm 1 --vm-bytes 100M)${NC}"
echo "  This will try to allocate 100M in a 50M cgroup..."
echo ""

# Run stress in the cgroup
bash -c "echo \$\$ > ${CGROUP_PATH}/cgroup.procs && stress --vm 1 --vm-bytes 100M --timeout 10s" 2>&1 || true

echo ""
echo -e "${RED}The process 'silently' disappeared!${NC}"
echo "Notice: No application error message - just 'got signal 9' (SIGKILL)"
echo ""

echo -e "${GREEN}Step 4: Finding evidence${NC}"
echo ""

echo -e "${YELLOW}Evidence 1: Kernel log (dmesg)${NC}"
echo "  Command: dmesg | grep -i oom | tail -5"
dmesg | grep -i oom | tail -5 || echo "  (no OOM messages - try running again)"
echo ""

echo -e "${YELLOW}Evidence 2: cgroup memory events${NC}"
echo "  Command: cat ${CGROUP_PATH}/memory.events"
cat "${CGROUP_PATH}/memory.events"
echo ""
echo -e "  ${GREEN}oom_kill > 0 means OOM killed a process!${NC}"
echo ""

echo -e "${YELLOW}Evidence 3: journalctl kernel messages${NC}"
echo "  Command: journalctl -k --since '2 minutes ago' | grep -i oom | tail -3"
journalctl -k --since "2 minutes ago" | grep -i oom | tail -3 || echo "  (no recent OOM messages)"
echo ""

echo -e "${BLUE}=== Summary ===${NC}"
echo ""
echo "What you learned:"
echo "1. Application logs are EMPTY during OOM kill"
echo "2. The evidence is on the HOST, not in the container"
echo "3. Key commands:"
echo "   - dmesg | grep -i oom"
echo "   - cat /sys/fs/cgroup/<path>/memory.events"
echo "   - journalctl -k | grep -i oom"
echo ""
echo "Anti-pattern to avoid:"
echo "  'Only checking container logs, not host dmesg'"
echo "  OOM kills are only visible from the host!"
echo ""
