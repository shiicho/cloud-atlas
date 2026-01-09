#!/bin/bash
# =============================================================================
# Lab: Disk Space Mystery Investigation
# =============================================================================
# Hands-on lab for finding "hidden" disk space consumption.
#
# Usage: sudo ./lab-disk-mystery.sh
# =============================================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== Lab: Disk Space Mystery Investigation ===${NC}"
echo ""
echo "Objective: Find where 'hidden' disk space is being used"
echo ""

if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Please run as root (sudo)${NC}"
    exit 1
fi

echo -e "${GREEN}Task 1: Check host disk usage${NC}"
echo ""
echo "  Command: df -h /"
read -p "Press Enter to execute..."

df -h /
echo ""

echo -e "${GREEN}Task 2: Check Docker disk usage${NC}"
echo ""
echo "  Command: docker system df"
read -p "Press Enter to execute..."

docker system df 2>/dev/null || echo "Docker not available"
echo ""

echo -e "${GREEN}Task 3: Find deleted but open files${NC}"
echo ""
echo "  Command: lsof +L1 | head -20"
echo "  (These files are deleted but processes still hold handles)"
read -p "Press Enter to execute..."

lsof +L1 2>/dev/null | head -20 || echo "No deleted open files found"
echo ""

echo -e "${GREEN}Task 4: Check Docker images size${NC}"
echo ""
echo "  Command: docker image ls --format 'table {{.Repository}}\t{{.Size}}'"
read -p "Press Enter to execute..."

docker image ls --format 'table {{.Repository}}\t{{.Size}}' 2>/dev/null | head -15 || echo "Docker not available"
echo ""

echo -e "${GREEN}Task 5: Check container overlay layers${NC}"
echo ""

if command -v docker &> /dev/null; then
    CONTAINER_ID=$(docker ps -q | head -1)
    if [ -n "$CONTAINER_ID" ]; then
        echo "  Checking container: $CONTAINER_ID"
        read -p "Press Enter to execute..."

        UPPER_DIR=$(docker inspect --format '{{.GraphDriver.Data.UpperDir}}' "$CONTAINER_ID" 2>/dev/null)
        if [ -n "$UPPER_DIR" ] && [ -d "$UPPER_DIR" ]; then
            echo "  UpperDir: $UPPER_DIR"
            echo "  Size: $(du -sh "$UPPER_DIR" 2>/dev/null | cut -f1)"
        else
            echo "  (UpperDir not accessible)"
        fi
    else
        echo "  No running containers"
    fi
else
    echo "  Docker not available"
fi
echo ""

echo -e "${GREEN}Task 6: Check Docker volumes${NC}"
echo ""
echo "  Command: docker volume ls"
read -p "Press Enter to execute..."

docker volume ls 2>/dev/null || echo "Docker not available"
echo ""

echo -e "${GREEN}Task 7: Find large files on system${NC}"
echo ""
echo "  Command: find /var -type f -size +100M 2>/dev/null | head -10"
read -p "Press Enter to execute..."

find /var -type f -size +100M 2>/dev/null | head -10 || echo "No large files found in /var"
echo ""

echo -e "${BLUE}=== Lab Assessment ===${NC}"
echo ""
echo "Common causes of 'hidden' disk space:"
echo ""
echo "1. Deleted but open files"
echo "   - lsof +L1 finds them"
echo "   - Fix: restart process or truncate"
echo ""
echo "2. OverlayFS upper layers"
echo "   - Check docker inspect GraphDriver.Data.UpperDir"
echo "   - Fix: use volumes instead of overlay"
echo ""
echo "3. Docker build cache"
echo "   - docker system df shows it"
echo "   - Fix: docker builder prune"
echo ""
echo "4. Dangling images/volumes"
echo "   - docker system df shows it"
echo "   - Fix: docker system prune"
echo ""

echo -e "${GREEN}Lab complete!${NC}"
echo ""
