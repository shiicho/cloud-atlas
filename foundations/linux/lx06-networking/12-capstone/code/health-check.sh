#!/bin/bash
# =============================================================================
# Multi-Zone Network Health Check Script
# =============================================================================
#
# Purpose: Daily operational health monitoring
# Japanese IT Term: Daily operational monitoring script
#
# This script is designed for:
#   - Daily health checks
#   - Incident response verification
#   - Cron-based automated monitoring
#
# Usage:
#   sudo ./health-check.sh           # Interactive mode
#   sudo ./health-check.sh --quiet   # Machine-readable output (for cron)
#   sudo ./health-check.sh --json    # JSON output (for monitoring systems)
#
# Exit codes:
#   0 - All checks passed
#   1 - Some checks failed
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

# Colors (disabled in quiet mode)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Counters
TOTAL=0
PASSED=0
FAILED=0

# Options
QUIET=false
JSON=false

# Results array for JSON output
declare -a RESULTS

# -----------------------------------------------------------------------------
# Argument Parsing
# -----------------------------------------------------------------------------

while [[ $# -gt 0 ]]; do
    case $1 in
        --quiet|-q)
            QUIET=true
            RED=''
            GREEN=''
            YELLOW=''
            NC=''
            shift
            ;;
        --json|-j)
            JSON=true
            QUIET=true
            RED=''
            GREEN=''
            YELLOW=''
            NC=''
            shift
            ;;
        *)
            echo "Usage: $0 [--quiet|-q] [--json|-j]"
            exit 1
            ;;
    esac
done

# -----------------------------------------------------------------------------
# Helper Functions
# -----------------------------------------------------------------------------

check_root() {
    if [[ $EUID -ne 0 ]]; then
        if [[ "$JSON" == true ]]; then
            echo '{"error": "Must run as root"}'
        else
            echo "ERROR: This script must be run as root"
        fi
        exit 1
    fi
}

log() {
    if [[ "$QUIET" == false ]]; then
        echo "$@"
    fi
}

# Health check function
check() {
    local name=$1
    local cmd=$2
    local expected=$3  # "success" or "fail"

    ((TOTAL++))

    if eval "$cmd" &>/dev/null; then
        result="success"
    else
        result="fail"
    fi

    if [[ "$result" == "$expected" ]]; then
        status="PASS"
        ((PASSED++))
    else
        status="FAIL"
        ((FAILED++))
    fi

    # Store result for JSON
    if [[ "$JSON" == true ]]; then
        RESULTS+=("{\"name\": \"$name\", \"status\": \"$status\", \"expected\": \"$expected\", \"actual\": \"$result\"}")
    elif [[ "$QUIET" == true ]]; then
        echo "$status: $name"
    else
        if [[ "$status" == "PASS" ]]; then
            echo -e "${GREEN}[PASS]${NC} $name"
        else
            echo -e "${RED}[FAIL]${NC} $name"
        fi
    fi
}

# -----------------------------------------------------------------------------
# Health Checks
# -----------------------------------------------------------------------------

run_checks() {
    # Namespace checks
    log ""
    log "--- Namespace Status ---"
    check "Namespace zone-web exists" "ip netns list | grep -q zone-web" "success"
    check "Namespace zone-app exists" "ip netns list | grep -q zone-app" "success"
    check "Namespace zone-db exists" "ip netns list | grep -q zone-db" "success"

    # Service checks
    log ""
    log "--- Service Status ---"
    check "Web service port 80" "ip netns exec zone-web ss -tuln | grep -q ':80 '" "success"
    check "App service port 8080" "ip netns exec zone-app ss -tuln | grep -q ':8080 '" "success"
    check "DB service port 3306" "ip netns exec zone-db ss -tuln | grep -q ':3306 '" "success"

    # Connectivity checks (should succeed)
    log ""
    log "--- Allowed Connections ---"
    check "Host -> Web HTTP" "curl -s --connect-timeout $TIMEOUT http://${WEB_IP}:80" "success"
    check "Web -> App HTTP" "ip netns exec zone-web curl -s --connect-timeout $TIMEOUT http://${APP_IP}:8080" "success"
    check "App -> DB TCP" "ip netns exec zone-app nc -z -w $TIMEOUT $DB_IP 3306" "success"

    # Security checks (should fail)
    log ""
    log "--- Blocked Connections (Security) ---"
    check "Host -> App blocked" "curl -s --connect-timeout $TIMEOUT http://${APP_IP}:8080" "fail"
    check "Host -> DB blocked" "nc -z -w $TIMEOUT $DB_IP 3306" "fail"
    check "Web -> DB blocked" "ip netns exec zone-web nc -z -w $TIMEOUT $DB_IP 3306" "fail"
}

# -----------------------------------------------------------------------------
# Output
# -----------------------------------------------------------------------------

output_results() {
    local timestamp
    timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

    if [[ "$JSON" == true ]]; then
        # Build JSON array
        local results_json=""
        for r in "${RESULTS[@]}"; do
            if [[ -n "$results_json" ]]; then
                results_json+=","
            fi
            results_json+="$r"
        done

        cat << EOF
{
  "timestamp": "$timestamp",
  "total": $TOTAL,
  "passed": $PASSED,
  "failed": $FAILED,
  "status": "$([ $FAILED -eq 0 ] && echo 'healthy' || echo 'unhealthy')",
  "results": [$results_json]
}
EOF
    else
        log ""
        log "======================================================================"
        log "Health Check Summary"
        log "Time: $timestamp"
        log "======================================================================"
        log ""
        log "Total: $TOTAL | Passed: $PASSED | Failed: $FAILED"
        log ""

        if [[ $FAILED -eq 0 ]]; then
            log -e "${GREEN}Status: HEALTHY${NC}"
        else
            log -e "${RED}Status: UNHEALTHY - Requires investigation${NC}"
        fi
        log "======================================================================"
    fi
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------

main() {
    if [[ "$QUIET" == false ]]; then
        echo "======================================================================"
        echo "Multi-Zone Network Health Check"
        echo "Time: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "======================================================================"
    fi

    check_root
    run_checks
    output_results

    exit $FAILED
}

main
