#!/bin/bash
# =============================================================================
# Distroless Black Box Debugging Scenario
# =============================================================================
# Demonstrates how to debug a container that has no shell, curl, or ping
# using nsenter from the host.
#
# Usage: sudo ./distroless-debug-scenario.sh
# =============================================================================

set -e

CONTAINER_NAME="distroless-debug-demo"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== Distroless Black Box Debugging ===${NC}"
echo ""
echo "Scenario: Your Go app runs in a distroless container."
echo "Problem: It can't connect to the database. But there's no shell!"
echo "Solution: Use nsenter from the host."
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

echo -e "${GREEN}Step 1: Starting a 'distroless-like' container${NC}"
echo "  (Using alpine with sleep to simulate a running app)"
docker rm -f "$CONTAINER_NAME" 2>/dev/null || true
docker run -d --name "$CONTAINER_NAME" alpine sleep infinity
echo "  Container started: $CONTAINER_NAME"
echo ""

echo -e "${GREEN}Step 2: Getting container PID on host${NC}"
PID=$(docker inspect --format '{{.State.Pid}}' "$CONTAINER_NAME")
echo "  Container PID: $PID"
echo "  Command: docker inspect --format '{{.State.Pid}}' $CONTAINER_NAME"
echo ""

echo -e "${GREEN}Step 3: Checking network config using nsenter${NC}"
echo "  Command: nsenter -t $PID -n ip addr"
echo ""
nsenter -t "$PID" -n ip addr
echo ""

echo -e "${GREEN}Step 4: Testing connectivity from container's network namespace${NC}"
echo "  Command: nsenter -t $PID -n ping -c 2 8.8.8.8"
echo ""
nsenter -t "$PID" -n ping -c 2 8.8.8.8 || echo "  (ping failed - check connectivity)"
echo ""

echo -e "${GREEN}Step 5: Checking routing table${NC}"
echo "  Command: nsenter -t $PID -n ip route"
echo ""
nsenter -t "$PID" -n ip route
echo ""

echo -e "${GREEN}Step 6: Testing port connectivity (like checking RDS 3306)${NC}"
echo "  Command: nsenter -t $PID -n nc -zv 8.8.8.8 443 -w 3"
echo ""
nsenter -t "$PID" -n nc -zv 8.8.8.8 443 -w 3 2>&1 || true
echo ""

echo -e "${GREEN}Step 7: Checking DNS configuration${NC}"
echo "  Command: nsenter -t $PID -m cat /etc/resolv.conf"
echo ""
nsenter -t "$PID" -m cat /etc/resolv.conf
echo ""

echo -e "${BLUE}=== nsenter Namespace Selection ===${NC}"
echo ""
echo "Key commands for debugging:"
echo ""
echo "  nsenter -t <PID> -n              # Network only (ip, ping, tcpdump)"
echo "  nsenter -t <PID> -m              # Mount only (cat files)"
echo "  nsenter -t <PID> -p              # PID only (see container processes)"
echo "  nsenter -t <PID> -n -m           # Network + Mount"
echo "  nsenter -t <PID> -a              # All namespaces"
echo ""
echo "For network debugging (most common):"
echo "  nsenter -t <PID> -n ping <host>"
echo "  nsenter -t <PID> -n nc -zv <host> <port>"
echo "  nsenter -t <PID> -n tcpdump -i eth0 -c 10"
echo ""

echo -e "${BLUE}=== Summary ===${NC}"
echo ""
echo "What you learned:"
echo "1. docker exec won't work on distroless containers (no shell)"
echo "2. Use nsenter -t <PID> -n to enter just the network namespace"
echo "3. Use HOST tools (ping, tcpdump, nc) to debug container network"
echo "4. This is a critical skill for production troubleshooting!"
echo ""
