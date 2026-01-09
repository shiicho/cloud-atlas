#!/bin/bash
# =============================================================================
# Multi-Zone Network Verification Script
# =============================================================================
#
# This script verifies the three-zone network architecture is correctly
# configured by testing:
#   1. Namespace existence
#   2. Service availability
#   3. Allowed connections (should succeed)
#   4. Blocked connections (should fail - security verification)
#
# Usage: sudo ./verify.sh
#
# Exit codes:
#   0 - All tests passed
#   1 - Some tests failed
#
# =============================================================================

set -uo pipefail

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------

WEB_IP="10.100.1.10"
APP_IP="10.100.1.20"
DB_IP="10.100.1.30"

TIMEOUT=2

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Counters
TOTAL=0
PASSED=0
FAILED=0

# -----------------------------------------------------------------------------
# Helper Functions
# -----------------------------------------------------------------------------

check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}[ERROR]${NC} This script must be run as root (use sudo)"
        exit 1
    fi
}

# Test function that expects success
test_should_succeed() {
    local name=$1
    local cmd=$2

    ((TOTAL++))

    if eval "$cmd" &>/dev/null; then
        echo -e "${GREEN}[PASS]${NC} $name"
        ((PASSED++))
        return 0
    else
        echo -e "${RED}[FAIL]${NC} $name"
        echo -e "       Command: $cmd"
        ((FAILED++))
        return 1
    fi
}

# Test function that expects failure (security test)
test_should_fail() {
    local name=$1
    local cmd=$2

    ((TOTAL++))

    if eval "$cmd" &>/dev/null; then
        echo -e "${RED}[FAIL]${NC} $name (connection succeeded when it should be blocked!)"
        echo -e "       ${YELLOW}SECURITY ISSUE: Firewall rule may be missing${NC}"
        ((FAILED++))
        return 1
    else
        echo -e "${GREEN}[PASS]${NC} $name (correctly blocked)"
        ((PASSED++))
        return 0
    fi
}

print_header() {
    echo ""
    echo -e "${BLUE}--- $1 ---${NC}"
}

# -----------------------------------------------------------------------------
# Tests
# -----------------------------------------------------------------------------

test_namespaces() {
    print_header "Namespace Status"

    test_should_succeed "Namespace zone-web exists" \
        "ip netns list | grep -q zone-web"

    test_should_succeed "Namespace zone-app exists" \
        "ip netns list | grep -q zone-app"

    test_should_succeed "Namespace zone-db exists" \
        "ip netns list | grep -q zone-db"
}

test_bridge() {
    print_header "Bridge Status"

    test_should_succeed "Bridge zone-br0 exists" \
        "ip link show zone-br0"

    test_should_succeed "Bridge has IP 10.100.1.1" \
        "ip addr show zone-br0 | grep -q '10.100.1.1'"
}

test_zone_interfaces() {
    print_header "Zone Interface Status"

    test_should_succeed "zone-web has eth0 with 10.100.1.10" \
        "ip netns exec zone-web ip addr show eth0 | grep -q '10.100.1.10'"

    test_should_succeed "zone-app has eth0 with 10.100.1.20" \
        "ip netns exec zone-app ip addr show eth0 | grep -q '10.100.1.20'"

    test_should_succeed "zone-db has eth0 with 10.100.1.30" \
        "ip netns exec zone-db ip addr show eth0 | grep -q '10.100.1.30'"
}

test_services() {
    print_header "Service Status"

    test_should_succeed "Web service listening on port 80" \
        "ip netns exec zone-web ss -tuln | grep -q ':80 '"

    test_should_succeed "App service listening on port 8080" \
        "ip netns exec zone-app ss -tuln | grep -q ':8080 '"

    test_should_succeed "DB service listening on port 3306" \
        "ip netns exec zone-db ss -tuln | grep -q ':3306 '"
}

test_l3_connectivity() {
    print_header "L3 Connectivity (ping)"

    test_should_succeed "Host -> Web Zone ping" \
        "ping -c 1 -W $TIMEOUT $WEB_IP"

    test_should_succeed "Host -> App Zone ping" \
        "ping -c 1 -W $TIMEOUT $APP_IP"

    test_should_succeed "Host -> DB Zone ping" \
        "ping -c 1 -W $TIMEOUT $DB_IP"

    test_should_succeed "Web -> App ping" \
        "ip netns exec zone-web ping -c 1 -W $TIMEOUT $APP_IP"

    test_should_succeed "App -> DB ping" \
        "ip netns exec zone-app ping -c 1 -W $TIMEOUT $DB_IP"
}

test_allowed_connections() {
    print_header "Allowed Connections (should succeed)"

    test_should_succeed "Host -> Web Zone HTTP (port 80)" \
        "curl -s --connect-timeout $TIMEOUT http://${WEB_IP}:80"

    test_should_succeed "Web -> App (port 8080)" \
        "ip netns exec zone-web curl -s --connect-timeout $TIMEOUT http://${APP_IP}:8080"

    test_should_succeed "App -> DB (port 3306)" \
        "ip netns exec zone-app nc -z -w $TIMEOUT $DB_IP 3306"
}

test_blocked_connections() {
    print_header "Blocked Connections (security verification)"

    echo -e "${YELLOW}These tests verify firewall rules are working correctly.${NC}"
    echo -e "${YELLOW}All connections below SHOULD FAIL (be blocked).${NC}"
    echo ""

    test_should_fail "Host -> App Zone direct (port 8080)" \
        "curl -s --connect-timeout $TIMEOUT http://${APP_IP}:8080"

    test_should_fail "Host -> DB Zone direct (port 3306)" \
        "nc -z -w $TIMEOUT $DB_IP 3306"

    test_should_fail "Web -> DB direct (port 3306)" \
        "ip netns exec zone-web nc -z -w $TIMEOUT $DB_IP 3306"

    test_should_fail "DB -> App (port 8080)" \
        "ip netns exec zone-db nc -z -w $TIMEOUT $APP_IP 8080"

    test_should_fail "DB -> Web (port 80)" \
        "ip netns exec zone-db nc -z -w $TIMEOUT $WEB_IP 80"
}

test_firewall_rules() {
    print_header "Firewall Rules Verification"

    test_should_succeed "zone-web has ct state tracking" \
        "ip netns exec zone-web nft list ruleset | grep -q 'ct state established'"

    test_should_succeed "zone-app allows only from 10.100.1.10" \
        "ip netns exec zone-app nft list ruleset | grep -q 'ip saddr 10.100.1.10'"

    test_should_succeed "zone-db allows only from 10.100.1.20" \
        "ip netns exec zone-db nft list ruleset | grep -q 'ip saddr 10.100.1.20'"

    test_should_succeed "zone-web has default drop policy" \
        "ip netns exec zone-web nft list chain inet filter input | grep -q 'policy drop'"

    test_should_succeed "zone-app has default drop policy" \
        "ip netns exec zone-app nft list chain inet filter input | grep -q 'policy drop'"

    test_should_succeed "zone-db has default drop policy" \
        "ip netns exec zone-db nft list chain inet filter input | grep -q 'policy drop'"
}

print_summary() {
    echo ""
    echo "======================================================================"
    echo "Verification Summary"
    echo "======================================================================"
    echo ""
    echo "Total tests: $TOTAL"
    echo -e "Passed:      ${GREEN}$PASSED${NC}"
    echo -e "Failed:      ${RED}$FAILED${NC}"
    echo ""

    if [[ $FAILED -eq 0 ]]; then
        echo -e "${GREEN}======================================================================"
        echo "All tests passed! Network architecture is correctly configured."
        echo "======================================================================${NC}"
        return 0
    else
        echo -e "${RED}======================================================================"
        echo "Some tests failed! Please review the output above."
        echo ""
        echo "Troubleshooting steps:"
        echo "  1. Run: sudo ./setup.sh  (to recreate the environment)"
        echo "  2. Check namespace existence: ip netns list"
        echo "  3. Check bridge: ip link show zone-br0"
        echo "  4. Check firewall: ip netns exec zone-X nft list ruleset"
        echo "======================================================================${NC}"
        return 1
    fi
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------

main() {
    echo "======================================================================"
    echo "Multi-Zone Network Verification"
    echo "Time: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "======================================================================"

    check_root

    test_namespaces
    test_bridge
    test_zone_interfaces
    test_services
    test_l3_connectivity
    test_allowed_connections
    test_blocked_connections
    test_firewall_rules

    print_summary

    exit $FAILED
}

main "$@"
