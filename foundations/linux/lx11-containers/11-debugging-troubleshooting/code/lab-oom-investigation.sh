#!/bin/bash
# =============================================================================
# Lab: OOM Kill Investigation
# =============================================================================
# Hands-on lab for investigating OOM kill events.
# Complete this lab to practice the 4-step troubleshooting methodology.
#
# Usage: sudo ./lab-oom-investigation.sh
# =============================================================================

set -e

CGROUP_NAME="lab-oom-investigation"
CGROUP_PATH="/sys/fs/cgroup/${CGROUP_NAME}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== Lab: OOM Kill Investigation ===${NC}"
echo ""
echo "Objective: Practice investigating an OOM kill event"
echo ""

if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Please run as root (sudo)${NC}"
    exit 1
fi

# Check for stress
if ! command -v stress &> /dev/null; then
    echo -e "${YELLOW}Installing stress...${NC}"
    apt-get install -y stress 2>/dev/null || dnf install -y stress 2>/dev/null
fi

# Cleanup
cleanup() {
    rmdir "$CGROUP_PATH" 2>/dev/null || true
}
trap cleanup EXIT

echo -e "${GREEN}Task 1: Create a cgroup with 64MB memory limit${NC}"
echo ""
echo "  Your commands:"
echo "  mkdir -p $CGROUP_PATH"
echo "  echo '64M' > ${CGROUP_PATH}/memory.max"
echo ""
read -p "Press Enter to execute..."

mkdir -p "$CGROUP_PATH"
echo "64M" > "${CGROUP_PATH}/memory.max"
echo -e "${GREEN}Done!${NC} Memory limit set to: $(cat ${CGROUP_PATH}/memory.max)"
echo ""

echo -e "${GREEN}Task 2: Record initial memory.events${NC}"
echo ""
echo "  Command: cat ${CGROUP_PATH}/memory.events"
echo ""
read -p "Press Enter to execute..."

echo "Initial memory.events:"
cat "${CGROUP_PATH}/memory.events"
echo ""
OOM_BEFORE=$(grep oom_kill "${CGROUP_PATH}/memory.events" | awk '{print $2}')

echo -e "${GREEN}Task 3: Trigger OOM kill (allocate 128M in 64M cgroup)${NC}"
echo ""
echo "  Command: stress --vm 1 --vm-bytes 128M --timeout 10s"
echo ""
read -p "Press Enter to execute (this will fail - that's expected!)..."

bash -c "echo \$\$ > ${CGROUP_PATH}/cgroup.procs && stress --vm 1 --vm-bytes 128M --timeout 10s" 2>&1 || true
echo ""

echo -e "${GREEN}Task 4: Collect evidence${NC}"
echo ""

echo -e "${YELLOW}Evidence 1: dmesg${NC}"
echo "  Command: dmesg | grep -i oom | tail -5"
read -p "Press Enter to execute..."
dmesg | grep -i oom | tail -5
echo ""

echo -e "${YELLOW}Evidence 2: memory.events${NC}"
echo "  Command: cat ${CGROUP_PATH}/memory.events"
read -p "Press Enter to execute..."
cat "${CGROUP_PATH}/memory.events"
OOM_AFTER=$(grep oom_kill "${CGROUP_PATH}/memory.events" | awk '{print $2}')
echo ""

echo -e "${YELLOW}Evidence 3: journalctl${NC}"
echo "  Command: journalctl -k --since '2 minutes ago' | grep -i oom | tail -3"
read -p "Press Enter to execute..."
journalctl -k --since "2 minutes ago" | grep -i oom | tail -3 || true
echo ""

echo -e "${BLUE}=== Lab Assessment ===${NC}"
echo ""
echo "Questions to answer:"
echo ""
echo "1. What was the oom_kill count before? $OOM_BEFORE"
echo "2. What is the oom_kill count after? $OOM_AFTER"
echo "3. Did the count increase? $([ "$OOM_AFTER" -gt "$OOM_BEFORE" ] && echo 'YES' || echo 'NO')"
echo ""

if [ "$OOM_AFTER" -gt "$OOM_BEFORE" ]; then
    echo -e "${GREEN}SUCCESS!${NC} You successfully investigated an OOM kill."
else
    echo -e "${YELLOW}WARNING:${NC} OOM count didn't increase. Check dmesg for details."
fi

echo ""
echo -e "${BLUE}=== Incident Report Template ===${NC}"
echo ""
echo "Fill out this template for practice:"
echo ""
echo "## Incident Report"
echo ""
echo "### Symptom"
echo "Process disappeared without application logs."
echo ""
echo "### Root Cause"
echo "cgroup memory limit (64MB) exceeded by process attempting to allocate 128MB."
echo ""
echo "### Evidence"
echo "1. dmesg: 'Memory cgroup out of memory: Killed process...'"
echo "2. memory.events: oom_kill increased from $OOM_BEFORE to $OOM_AFTER"
echo ""
echo "### Resolution"
echo "- Short term: Increase memory limit"
echo "- Long term: Optimize application memory usage"
echo ""
