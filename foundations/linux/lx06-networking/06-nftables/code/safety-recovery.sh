#!/bin/bash
# =============================================================================
# nftables Safety Recovery Script
# =============================================================================
#
# Description: Schedule automatic firewall recovery before testing new rules
# Usage:       ./safety-recovery.sh [seconds] [config_file]
# Default:     300 seconds (5 minutes), /etc/nftables.conf
#
# Example:
#   ./safety-recovery.sh 300 /etc/nftables.conf
#   # Now safely test your new rules
#   # If you get locked out, rules will restore in 5 minutes
#
# =============================================================================

set -e

# Configuration
DELAY="${1:-300}"                          # Default: 5 minutes
CONFIG="${2:-/etc/nftables.conf}"          # Default: system config
BACKUP="/tmp/nftables-backup-$(date +%Y%m%d-%H%M%S).nft"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}=== nftables Safety Recovery Script ===${NC}"
echo ""

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}Error: This script must be run as root${NC}"
    echo "Usage: sudo $0 [seconds] [config_file]"
    exit 1
fi

# Check if config file exists
if [[ ! -f "$CONFIG" ]]; then
    echo -e "${RED}Error: Config file not found: $CONFIG${NC}"
    exit 1
fi

# Backup current ruleset
echo -e "${GREEN}[1/4] Backing up current ruleset...${NC}"
nft list ruleset > "$BACKUP"
echo "      Backup saved to: $BACKUP"

# Schedule recovery
echo -e "${GREEN}[2/4] Scheduling recovery in $DELAY seconds...${NC}"
(
    sleep "$DELAY"
    echo "[$(date)] Restoring nftables rules from $CONFIG"
    nft flush ruleset
    nft -f "$CONFIG"
    echo "[$(date)] Rules restored successfully"
) &

RECOVERY_PID=$!
echo "      Recovery PID: $RECOVERY_PID"

# Show instructions
echo ""
echo -e "${GREEN}[3/4] Safety net is active!${NC}"
echo ""
echo -e "${YELLOW}You now have $DELAY seconds to test your new rules.${NC}"
echo ""
echo "If you get locked out:"
echo "  - Rules will automatically restore to $CONFIG"
echo "  - Recovery scheduled at: $(date -d "+$DELAY seconds" 2>/dev/null || date -v+${DELAY}S)"
echo ""
echo "If your new rules work correctly:"
echo "  - Kill the recovery process: kill $RECOVERY_PID"
echo "  - Or just let it run (it will reload the same config)"
echo ""

# Show recovery process status
echo -e "${GREEN}[4/4] Recovery process started${NC}"
echo "      To cancel: kill $RECOVERY_PID"
echo "      To verify: ps aux | grep $RECOVERY_PID"
echo ""

# Wait for user input or timeout
echo -e "${YELLOW}Press Enter to continue (or Ctrl+C to cancel)...${NC}"
read -r

echo ""
echo -e "${GREEN}Done! You can now apply your new rules.${NC}"
echo "Remember: Recovery will trigger in $DELAY seconds unless you cancel it."
echo ""
echo "Commands:"
echo "  Apply new rules:    nft -f /path/to/new-rules.nft"
echo "  Cancel recovery:    kill $RECOVERY_PID"
echo "  Check recovery:     ps aux | grep $RECOVERY_PID"
