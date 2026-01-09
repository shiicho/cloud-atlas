#!/bin/bash
# =============================================================================
# Lab: Stuck Process Debugging
# =============================================================================
# Hands-on lab for debugging containers when docker exec doesn't work.
#
# Usage: sudo ./lab-stuck-process.sh
# =============================================================================

set -e

CONTAINER_NAME="lab-stuck-process"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== Lab: Stuck Process Debugging ===${NC}"
echo ""
echo "Objective: Debug a container when docker exec doesn't work"
echo ""

if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Please run as root (sudo)${NC}"
    exit 1
fi

if ! command -v docker &> /dev/null; then
    echo -e "${RED}Docker is not installed${NC}"
    exit 1
fi

# Cleanup
cleanup() {
    docker rm -f "$CONTAINER_NAME" 2>/dev/null || true
}
trap cleanup EXIT

echo -e "${GREEN}Task 1: Start a container${NC}"
echo ""
docker rm -f "$CONTAINER_NAME" 2>/dev/null || true
docker run -d --name "$CONTAINER_NAME" alpine sleep infinity
echo "  Container started: $CONTAINER_NAME"
echo ""

echo -e "${GREEN}Task 2: Get container PID${NC}"
echo ""
echo "  Command: docker inspect --format '{{.State.Pid}}' $CONTAINER_NAME"
read -p "Press Enter to execute..."

PID=$(docker inspect --format '{{.State.Pid}}' "$CONTAINER_NAME")
echo "  Container PID: $PID"
echo ""

echo -e "${GREEN}Task 3: Check process status${NC}"
echo ""
echo "  Command: ps -p $PID -o pid,stat,wchan,comm"
read -p "Press Enter to execute..."

ps -p "$PID" -o pid,stat,wchan,comm
echo ""
echo "  STAT codes:"
echo "    S = sleeping (interruptible)"
echo "    D = uninterruptible sleep (stuck!)"
echo "    R = running"
echo "    Z = zombie"
echo ""

echo -e "${GREEN}Task 4: Check what process is waiting for${NC}"
echo ""
echo "  Command: cat /proc/$PID/wchan"
read -p "Press Enter to execute..."

echo "  Waiting on: $(cat /proc/$PID/wchan 2>/dev/null || echo 'N/A')"
echo ""

echo -e "${GREEN}Task 5: Check process status file${NC}"
echo ""
echo "  Command: cat /proc/$PID/status | head -15"
read -p "Press Enter to execute..."

cat "/proc/$PID/status" | head -15
echo ""

echo -e "${GREEN}Task 6: Check open file descriptors${NC}"
echo ""
echo "  Command: ls -la /proc/$PID/fd | head -10"
read -p "Press Enter to execute..."

ls -la "/proc/$PID/fd" | head -10
echo ""

echo -e "${GREEN}Task 7: Check kernel stack${NC}"
echo ""
echo "  Command: cat /proc/$PID/stack"
read -p "Press Enter to execute..."

cat "/proc/$PID/stack" 2>/dev/null || echo "  (stack not available)"
echo ""

echo -e "${GREEN}Task 8: Use nsenter to bypass docker exec${NC}"
echo ""
echo "  Command: nsenter -t $PID -m -p ls -la /"
read -p "Press Enter to execute..."

nsenter -t "$PID" -m -p ls -la /
echo ""

echo -e "${GREEN}Task 9: Access container filesystem directly${NC}"
echo ""
MERGED=$(docker inspect --format '{{.GraphDriver.Data.MergedDir}}' "$CONTAINER_NAME")
echo "  MergedDir: $MERGED"
echo "  Command: ls -la $MERGED/"
read -p "Press Enter to execute..."

ls -la "$MERGED/" | head -10
echo ""

echo -e "${BLUE}=== Lab Assessment ===${NC}"
echo ""
echo "What you practiced:"
echo ""
echo "1. Getting container PID from Docker"
echo "2. Reading process status from /proc"
echo "3. Checking what process is blocked on"
echo "4. Using nsenter to bypass docker exec"
echo "5. Direct filesystem access via MergedDir"
echo ""

echo "Debugging toolkit:"
echo ""
echo "  ps -p <PID> -o pid,stat,wchan,comm"
echo "  cat /proc/<PID>/wchan"
echo "  cat /proc/<PID>/stack"
echo "  ls -la /proc/<PID>/fd"
echo "  nsenter -t <PID> -m -p /bin/sh"
echo ""

echo -e "${GREEN}Lab complete!${NC}"
echo ""
