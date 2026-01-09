#!/bin/bash
# =============================================================================
# PAM Faillock Test Script
# Tests account lockout functionality
#
# Usage: sudo ./test-lockout.sh [username]
# =============================================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

TEST_USER="${1:-testlockuser}"

echo -e "${YELLOW}=== PAM Faillock Test Script ===${NC}"
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}ERROR: This script must be run as root${NC}"
    echo "Usage: sudo $0 [username]"
    exit 1
fi

# Check if faillock command exists
if ! command -v faillock &> /dev/null; then
    echo -e "${RED}ERROR: faillock command not found${NC}"
    echo "Please ensure pam_faillock is installed and configured"
    exit 1
fi

echo "Test user: $TEST_USER"
echo ""

# Create test user if doesn't exist
if ! id "$TEST_USER" &>/dev/null; then
    echo "Creating test user: $TEST_USER"
    useradd -m "$TEST_USER"
    echo "${TEST_USER}:TestPass123!" | chpasswd
    echo -e "${GREEN}Test user created with password: TestPass123!${NC}"
else
    echo "Test user already exists"
fi

echo ""

# Show initial status
echo "=== Initial faillock status ==="
faillock --user "$TEST_USER"
echo ""

# Simulate failed login attempts
echo "=== Simulating failed login attempts ==="
echo "Attempting 6 failed SSH logins..."
echo ""

for i in {1..6}; do
    echo "Attempt $i: Trying wrong password..."
    # Use sshpass or expect for automated testing
    # For safety, just show what would happen
    sshpass -p "wrongpassword" ssh -o StrictHostKeyChecking=no -o BatchMode=no "$TEST_USER@localhost" exit 2>/dev/null || true
    sleep 1
done

echo ""
echo "=== Faillock status after failed attempts ==="
faillock --user "$TEST_USER"
echo ""

# Check if account is locked
FAIL_COUNT=$(faillock --user "$TEST_USER" | grep -c "V" || echo "0")
echo "Failed attempts recorded: $FAIL_COUNT"

if [ "$FAIL_COUNT" -ge 5 ]; then
    echo -e "${GREEN}SUCCESS: Account is now locked (5+ failures)${NC}"
else
    echo -e "${YELLOW}WARNING: Account may not be locked (check faillock configuration)${NC}"
fi

echo ""
echo "=== Reset options ==="
echo ""
echo "To unlock the account:"
echo "  faillock --user $TEST_USER --reset"
echo ""
echo "To delete test user:"
echo "  userdel -r $TEST_USER"
echo ""

# Ask if user wants to reset
read -p "Reset faillock count for $TEST_USER? (y/n): " reset_confirm
if [ "$reset_confirm" = "y" ]; then
    faillock --user "$TEST_USER" --reset
    echo -e "${GREEN}Faillock count reset${NC}"
    faillock --user "$TEST_USER"
fi
