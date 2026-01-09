#!/bin/bash
# =============================================================================
# Stuck Container Process Scenario
# =============================================================================
# Demonstrates how to debug a container when docker exec hangs.
# Uses nsenter and /proc filesystem to investigate.
#
# Usage: sudo ./stuck-process-scenario.sh
# =============================================================================

set -e

CONTAINER_NAME="stuck-process-demo"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== Stuck Container Process Debugging ===${NC}"
echo ""
echo "Scenario: Java container is stuck, docker exec hangs."
echo "Docker daemon seems fine but can't interact with container."
echo "Need to debug without relying on docker exec."
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Please run as root (sudo)${NC}"
    exit 1
fi

# Check for Docker
if ! command -v docker &> /dev/null; then
    echo -e "${RED}Docker is not installed${NC}"
    exit 1
fi

# Cleanup function
cleanup() {
    echo ""
    echo -e "${YELLOW}Cleaning up...${NC}"
    docker rm -f "$CONTAINER_NAME" 2>/dev/null || true
}
trap cleanup EXIT

echo -e "${GREEN}Step 1: Starting a test container${NC}"
docker rm -f "$CONTAINER_NAME" 2>/dev/null || true
docker run -d --name "$CONTAINER_NAME" alpine sleep infinity
echo "  Container started: $CONTAINER_NAME"
echo ""

echo -e "${GREEN}Step 2: Getting container PID${NC}"
PID=$(docker inspect --format '{{.State.Pid}}' "$CONTAINER_NAME")
echo "  Container PID on host: $PID"
echo "  Command: docker inspect --format '{{.State.Pid}}' $CONTAINER_NAME"
echo ""

echo -e "${GREEN}Step 3: Checking process status${NC}"
echo "  Command: ps -p $PID -o pid,stat,wchan,comm"
ps -p "$PID" -o pid,stat,wchan,comm
echo ""
echo "  STAT codes:"
echo "    S = sleeping (interruptible)"
echo "    D = sleeping (uninterruptible - waiting for I/O)"
echo "    R = running"
echo "    Z = zombie"
echo "    T = stopped"
echo ""

echo -e "${GREEN}Step 4: Checking what the process is waiting for${NC}"
echo "  Command: cat /proc/$PID/wchan"
echo "  Waiting on: $(cat /proc/$PID/wchan 2>/dev/null || echo 'N/A')"
echo ""

echo -e "${GREEN}Step 5: Checking process status details${NC}"
echo "  Command: cat /proc/$PID/status | head -20"
cat "/proc/$PID/status" | head -20
echo ""

echo -e "${GREEN}Step 6: Checking open file descriptors${NC}"
echo "  Command: ls -la /proc/$PID/fd | head -10"
ls -la "/proc/$PID/fd" | head -10
echo ""

echo -e "${GREEN}Step 7: Checking kernel stack (if stuck)${NC}"
echo "  Command: cat /proc/$PID/stack"
cat "/proc/$PID/stack" 2>/dev/null || echo "  (stack not available - may need root or kernel config)"
echo ""

echo -e "${GREEN}Step 8: Using nsenter to bypass docker exec${NC}"
echo "  Command: nsenter -t $PID -m -p ls -la /"
echo ""
nsenter -t "$PID" -m -p ls -la / 2>/dev/null || echo "  (nsenter failed)"
echo ""

echo -e "${GREEN}Step 9: Direct file access via MergedDir${NC}"
MERGED=$(docker inspect --format '{{.GraphDriver.Data.MergedDir}}' "$CONTAINER_NAME")
echo "  MergedDir: $MERGED"
echo "  Command: ls -la $MERGED/"
ls -la "$MERGED/" | head -10
echo ""
echo "  You can directly read logs:"
echo "  cat $MERGED/var/log/app.log"
echo ""

echo -e "${BLUE}=== Debugging Toolkit Summary ===${NC}"
echo ""
echo "When docker exec hangs, use these commands:"
echo ""
echo "1. Get PID:"
echo "   docker inspect --format '{{.State.Pid}}' <container>"
echo ""
echo "2. Check process state:"
echo "   ps -p <PID> -o pid,stat,wchan,comm"
echo ""
echo "3. Check what it's waiting for:"
echo "   cat /proc/<PID>/wchan"
echo "   cat /proc/<PID>/stack"
echo ""
echo "4. Check open files:"
echo "   ls -la /proc/<PID>/fd"
echo "   lsof -p <PID>"
echo ""
echo "5. Enter namespace directly:"
echo "   nsenter -t <PID> -m -p /bin/sh"
echo ""
echo "6. Read files directly:"
echo "   cat <MergedDir>/var/log/app.log"
echo ""
echo "7. For Java: generate thread dump"
echo "   kill -3 <PID>  # Sends SIGQUIT, generates thread dump to stdout"
echo ""
