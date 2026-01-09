#!/bin/bash
# =============================================================================
# Lab: Distroless Container Network Debugging
# =============================================================================
# Hands-on lab for debugging containers without shell using nsenter.
#
# Usage: sudo ./lab-distroless-debug.sh
# =============================================================================

set -e

CONTAINER_NAME="lab-distroless"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== Lab: Distroless Network Debugging ===${NC}"
echo ""
echo "Objective: Debug network issues in a container with no shell"
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
echo "  Command: docker run -d --name $CONTAINER_NAME alpine sleep infinity"
read -p "Press Enter to execute..."

docker rm -f "$CONTAINER_NAME" 2>/dev/null || true
docker run -d --name "$CONTAINER_NAME" alpine sleep infinity
echo -e "${GREEN}Done!${NC}"
echo ""

echo -e "${GREEN}Task 2: Get container PID${NC}"
echo ""
echo "  Command: docker inspect --format '{{.State.Pid}}' $CONTAINER_NAME"
read -p "Press Enter to execute..."

PID=$(docker inspect --format '{{.State.Pid}}' "$CONTAINER_NAME")
echo "  Container PID: $PID"
echo ""

echo -e "${GREEN}Task 3: Enter network namespace and check IP${NC}"
echo ""
echo "  Command: nsenter -t $PID -n ip addr"
read -p "Press Enter to execute..."

nsenter -t "$PID" -n ip addr
echo ""

echo -e "${GREEN}Task 4: Check routing table${NC}"
echo ""
echo "  Command: nsenter -t $PID -n ip route"
read -p "Press Enter to execute..."

nsenter -t "$PID" -n ip route
echo ""

echo -e "${GREEN}Task 5: Test external connectivity${NC}"
echo ""
echo "  Command: nsenter -t $PID -n ping -c 2 8.8.8.8"
read -p "Press Enter to execute..."

nsenter -t "$PID" -n ping -c 2 8.8.8.8 || echo "(ping may fail in some environments)"
echo ""

echo -e "${GREEN}Task 6: Test port connectivity${NC}"
echo ""
echo "  Command: nsenter -t $PID -n nc -zv google.com 443 -w 3"
read -p "Press Enter to execute..."

nsenter -t "$PID" -n nc -zv google.com 443 -w 3 2>&1 || echo "(connection may fail)"
echo ""

echo -e "${GREEN}Task 7: Check DNS configuration${NC}"
echo ""
echo "  Command: nsenter -t $PID -m cat /etc/resolv.conf"
read -p "Press Enter to execute..."

nsenter -t "$PID" -m cat /etc/resolv.conf
echo ""

echo -e "${BLUE}=== Lab Assessment ===${NC}"
echo ""
echo "What you practiced:"
echo ""
echo "1. Getting container PID from Docker"
echo "2. Using nsenter -n for network namespace"
echo "3. Using nsenter -m for mount namespace"
echo "4. Testing connectivity from container's perspective"
echo "5. Debugging without docker exec"
echo ""

echo "Key takeaways:"
echo ""
echo "- nsenter -t <PID> -n: Use host tools in container's network"
echo "- nsenter -t <PID> -m: Access container's filesystem"
echo "- You can use ping, nc, tcpdump from the host!"
echo ""

echo -e "${GREEN}Lab complete!${NC}"
echo ""
