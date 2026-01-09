#!/bin/bash
# =============================================================================
# Multi-Zone Network Cleanup Script
# =============================================================================
#
# This script removes all resources created by setup.sh:
#   - Network namespaces (zone-web, zone-app, zone-db)
#   - Virtual bridge (zone-br0)
#   - Veth pairs (automatically removed with namespaces)
#   - Test services (python http.server, nc)
#
# Usage: sudo ./cleanup.sh
#
# =============================================================================

set -uo pipefail

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------

BRIDGE_NAME="zone-br0"
ZONES=("web" "app" "db")

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# -----------------------------------------------------------------------------
# Helper Functions
# -----------------------------------------------------------------------------

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}[ERROR]${NC} This script must be run as root (use sudo)"
        exit 1
    fi
}

# -----------------------------------------------------------------------------
# Cleanup Functions
# -----------------------------------------------------------------------------

stop_test_services() {
    log_info "Stopping test services..."

    # Kill Python HTTP servers
    local pids
    pids=$(pgrep -f "python3 -m http.server" 2>/dev/null || true)
    if [[ -n "$pids" ]]; then
        echo "$pids" | xargs -r kill 2>/dev/null || true
        log_success "Stopped Python HTTP servers"
    else
        log_warn "No Python HTTP servers found"
    fi

    # Kill netcat listeners
    pids=$(pgrep -f "nc -l" 2>/dev/null || true)
    if [[ -n "$pids" ]]; then
        echo "$pids" | xargs -r kill 2>/dev/null || true
        log_success "Stopped netcat listeners"
    else
        log_warn "No netcat listeners found"
    fi
}

delete_namespaces() {
    log_info "Deleting network namespaces..."

    for zone in "${ZONES[@]}"; do
        local ns_name="zone-${zone}"
        if ip netns list | grep -q "$ns_name"; then
            ip netns del "$ns_name"
            log_success "Deleted namespace: $ns_name"
        else
            log_warn "Namespace $ns_name not found"
        fi
    done
}

delete_bridge() {
    log_info "Deleting virtual bridge..."

    if ip link show "$BRIDGE_NAME" &>/dev/null; then
        ip link set "$BRIDGE_NAME" down 2>/dev/null || true
        ip link del "$BRIDGE_NAME"
        log_success "Deleted bridge: $BRIDGE_NAME"
    else
        log_warn "Bridge $BRIDGE_NAME not found"
    fi
}

cleanup_veth_pairs() {
    log_info "Cleaning up orphaned veth interfaces..."

    # Veth pairs inside namespaces are automatically removed when namespace is deleted
    # But bridge-side interfaces might remain if namespace deletion fails

    for zone in "${ZONES[@]}"; do
        local veth_br="veth-${zone}-br"
        if ip link show "$veth_br" &>/dev/null; then
            ip link del "$veth_br" 2>/dev/null || true
            log_success "Cleaned up orphaned: $veth_br"
        fi
    done
}

verify_cleanup() {
    log_info "Verifying cleanup..."

    local issues=0

    # Check namespaces
    for zone in "${ZONES[@]}"; do
        if ip netns list | grep -q "zone-${zone}"; then
            log_warn "Namespace zone-${zone} still exists!"
            ((issues++))
        fi
    done

    # Check bridge
    if ip link show "$BRIDGE_NAME" &>/dev/null; then
        log_warn "Bridge $BRIDGE_NAME still exists!"
        ((issues++))
    fi

    # Check processes
    if pgrep -f "python3 -m http.server" &>/dev/null; then
        log_warn "Python HTTP server still running!"
        ((issues++))
    fi

    if pgrep -f "nc -l" &>/dev/null; then
        log_warn "Netcat listener still running!"
        ((issues++))
    fi

    return $issues
}

print_summary() {
    echo ""
    echo "======================================================================"
    if verify_cleanup; then
        echo -e "${GREEN}Cleanup completed successfully!${NC}"
        echo ""
        echo "All resources have been removed:"
        echo "  - Network namespaces (zone-web, zone-app, zone-db)"
        echo "  - Virtual bridge ($BRIDGE_NAME)"
        echo "  - Test services (HTTP servers, netcat)"
        echo ""
        echo "To recreate the environment, run:"
        echo "  sudo ./setup.sh"
    else
        echo -e "${YELLOW}Cleanup completed with warnings.${NC}"
        echo ""
        echo "Some resources may not have been fully removed."
        echo "You can try running cleanup again or manually remove them:"
        echo ""
        echo "  # Manual cleanup commands:"
        echo "  sudo ip netns del zone-web"
        echo "  sudo ip netns del zone-app"
        echo "  sudo ip netns del zone-db"
        echo "  sudo ip link del $BRIDGE_NAME"
        echo "  sudo pkill -f 'python3 -m http.server'"
        echo "  sudo pkill -f 'nc -l'"
    fi
    echo "======================================================================"
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------

main() {
    echo "======================================================================"
    echo "Multi-Zone Network Cleanup"
    echo "======================================================================"
    echo ""

    check_root

    stop_test_services
    echo ""

    delete_namespaces
    echo ""

    delete_bridge
    echo ""

    cleanup_veth_pairs
    echo ""

    print_summary
}

main "$@"
