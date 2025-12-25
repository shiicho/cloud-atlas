#!/bin/bash
# fill-disk.sh - Fill disk to target percentage for Zabbix alert testing
#
# Usage:
#   ./fill-disk.sh          # Show current usage + help
#   ./fill-disk.sh 85       # Fill to 85% (triggers Warning)
#   ./fill-disk.sh 95       # Fill to 95% (triggers High)
#   ./fill-disk.sh clean    # Remove test file
#
# Note: File is created in user's home directory (no sudo required)

set -e

TESTFILE="$HOME/disk-test-file"
MOUNT_POINT="/"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Show current disk usage with explanation
show_usage() {
    echo -e "${BLUE}=== Current Disk Usage ===${NC}"
    echo ""

    # Get raw values in bytes
    local info=$(df -B1 "$MOUNT_POINT" | tail -1)
    local filesystem=$(echo "$info" | awk '{print $1}')
    local total_bytes=$(echo "$info" | awk '{print $2}')
    local used_bytes=$(echo "$info" | awk '{print $3}')
    local avail_bytes=$(echo "$info" | awk '{print $4}')
    local current_pct=$(echo "$info" | awk '{print $5}' | tr -d '%')

    # Convert to human readable
    local total_h=$(numfmt --to=iec --suffix=B $total_bytes 2>/dev/null || echo "$((total_bytes/1024/1024/1024))GB")
    local used_h=$(numfmt --to=iec --suffix=B $used_bytes 2>/dev/null || echo "$((used_bytes/1024/1024/1024))GB")
    local avail_h=$(numfmt --to=iec --suffix=B $avail_bytes 2>/dev/null || echo "$((avail_bytes/1024/1024/1024))GB")

    # Show df output
    df -h "$MOUNT_POINT"
    echo ""

    # Explain the values
    echo -e "${YELLOW}Understanding the output:${NC}"
    echo "  Filesystem: $filesystem"
    echo "  Total:      $total_h (100%)"
    echo "  Used:       $used_h ($current_pct%)"
    echo "  Available:  $avail_h ($((100 - current_pct))%)"
    echo ""

    # Show test file status
    if [[ -f "$TESTFILE" ]]; then
        local testfile_size=$(stat -c%s "$TESTFILE" 2>/dev/null || stat -f%z "$TESTFILE" 2>/dev/null || echo 0)
        local testfile_h=$(numfmt --to=iec --suffix=B $testfile_size 2>/dev/null || echo "$((testfile_size/1024/1024))MB")
        echo -e "${GREEN}Test file exists:${NC} $TESTFILE ($testfile_h)"
    else
        echo -e "Test file: ${YELLOW}not created${NC}"
    fi

    return $current_pct
}

# Clean up test file
clean() {
    echo -e "${BLUE}=== Cleaning Up ===${NC}"
    echo ""

    if [[ -f "$TESTFILE" ]]; then
        local testfile_size=$(stat -c%s "$TESTFILE" 2>/dev/null || stat -f%z "$TESTFILE" 2>/dev/null || echo 0)
        local testfile_h=$(numfmt --to=iec --suffix=B $testfile_size 2>/dev/null || echo "$((testfile_size/1024/1024))MB")
        echo "Removing test file: $TESTFILE ($testfile_h)"
        rm -f "$TESTFILE"
        echo -e "${GREEN}Done.${NC}"
    else
        echo "No test file found at $TESTFILE"
    fi

    echo ""
    show_usage
}

# Fill to target percentage
fill_to() {
    local target=$1

    # Handle both 85 and 0.85 format
    if echo "$target" | grep -q '\.'; then
        # Has decimal point, convert 0.85 -> 85
        target=$(echo "$target * 100" | bc | cut -d. -f1)
    fi

    # Validate target
    if [[ $target -lt 1 ]] || [[ $target -gt 99 ]]; then
        echo -e "${RED}Error: Target must be between 1 and 99 (got: $target)${NC}"
        exit 1
    fi

    echo -e "${BLUE}=== Filling Disk to ${target}% ===${NC}"
    echo ""

    # Get current values in bytes
    local info=$(df -B1 "$MOUNT_POINT" | tail -1)
    local total_bytes=$(echo "$info" | awk '{print $2}')
    local used_bytes=$(echo "$info" | awk '{print $3}')
    local current_pct=$(echo "$info" | awk '{print $5}' | tr -d '%')

    # If test file exists, subtract its size from "used" for calculation
    local testfile_size=0
    if [[ -f "$TESTFILE" ]]; then
        testfile_size=$(stat -c%s "$TESTFILE" 2>/dev/null || stat -f%z "$TESTFILE" 2>/dev/null || echo 0)
        used_bytes=$((used_bytes - testfile_size))
        echo "Existing test file found, will be replaced."
        rm -f "$TESTFILE"
    fi

    # Calculate required file size
    # target_used = total * target / 100
    # need_bytes = target_used - current_used (without test file)
    local target_used=$((total_bytes * target / 100))
    local need_bytes=$((target_used - used_bytes))

    if [[ $need_bytes -le 0 ]]; then
        echo -e "${YELLOW}Current usage already >= target (${target}%)${NC}"
        echo "Run '$0 clean' first if you want to reset."
        show_usage
        exit 0
    fi

    # Convert to MB for dd (round up)
    local need_mb=$(( (need_bytes + 1048575) / 1048576 ))
    local need_h=$(numfmt --to=iec --suffix=B $need_bytes 2>/dev/null || echo "${need_mb}MB")

    echo -e "${YELLOW}Calculation:${NC}"
    echo "  Target usage:    ${target}%"
    echo "  Current usage:   ${current_pct}% (excluding test file)"
    echo "  Need to create:  $need_h file"
    echo "  File location:   $TESTFILE"
    echo ""

    # Create file
    echo "Creating file..."
    dd if=/dev/zero of="$TESTFILE" bs=1M count=$need_mb status=progress 2>&1

    echo ""
    echo -e "${GREEN}=== After Fill ===${NC}"
    show_usage

    # Show next steps
    echo ""
    echo -e "${BLUE}=== Next Steps ===${NC}"
    echo "1. Wait 1-2 minutes for Zabbix Agent to collect data"
    echo "2. Check Zabbix Web UI: Monitoring -> Problems"
    echo "3. Check Mailpit for email notification (if High severity)"
    echo ""
    echo "To clean up: $0 clean"
}

# Show help
show_help() {
    echo "fill-disk.sh - Fill disk to target percentage for Zabbix alert testing"
    echo ""
    echo -e "${YELLOW}Usage:${NC}"
    echo "  $0              Show current disk usage"
    echo "  $0 85           Fill to 85% (triggers Warning at 80%)"
    echo "  $0 95           Fill to 95% (triggers High at 90%)"
    echo "  $0 0.85         Same as 85 (decimal format supported)"
    echo "  $0 clean        Remove test file"
    echo ""
    echo -e "${YELLOW}Zabbix Trigger Thresholds:${NC}"
    echo "  Warning: >= 80%  (no email - Action filters High+)"
    echo "  High:    >= 90%  (sends email notification)"
    echo ""
}

# Main
case "${1:-}" in
    -h|--help|help)
        show_help
        ;;
    clean|none)
        clean
        ;;
    "")
        show_help
        echo ""
        show_usage
        ;;
    *)
        fill_to "$1"
        ;;
esac
