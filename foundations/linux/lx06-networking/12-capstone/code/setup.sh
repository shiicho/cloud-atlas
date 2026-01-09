#!/bin/bash
# =============================================================================
# Multi-Zone Network Setup Script
# Three-Tier Architecture: Web -> App -> DB
# =============================================================================
#
# This script creates a production-like three-zone network using:
# - Network namespaces (isolated network stacks)
# - Veth pairs (virtual ethernet cables)
# - Bridge (virtual switch)
# - nftables (modern firewall)
#
# Architecture:
#   Internet -> Web Zone (:80/443) -> App Zone (:8080) -> DB Zone (:3306)
#
# Usage: sudo ./setup.sh
#
# =============================================================================

set -euo pipefail

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------

BRIDGE_NAME="zone-br0"
BRIDGE_IP="10.100.1.1/24"

# Zone definitions: name:ip:port
declare -A ZONES=(
    ["web"]="10.100.1.10:80"
    ["app"]="10.100.1.20:8080"
    ["db"]="10.100.1.30:3306"
)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root (use sudo)"
        exit 1
    fi
}

check_dependencies() {
    local deps=("ip" "nft" "python3" "nc")
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            log_error "Required command '$dep' not found. Please install it."
            exit 1
        fi
    done
}

cleanup_existing() {
    log_info "Cleaning up any existing configuration..."

    # Kill any existing test services
    pkill -f "python3 -m http.server" 2>/dev/null || true
    pkill -f "nc -l -k" 2>/dev/null || true

    # Delete namespaces (this also removes veth pairs inside them)
    for zone in "${!ZONES[@]}"; do
        ip netns del "zone-${zone}" 2>/dev/null || true
    done

    # Delete bridge
    ip link del "$BRIDGE_NAME" 2>/dev/null || true

    sleep 1
}

# -----------------------------------------------------------------------------
# Main Setup Functions
# -----------------------------------------------------------------------------

create_namespaces() {
    echo ""
    log_info "[1/6] Creating network namespaces..."

    for zone in "${!ZONES[@]}"; do
        ip netns add "zone-${zone}"
        log_success "Created: zone-${zone}"
    done
}

create_bridge() {
    echo ""
    log_info "[2/6] Creating virtual bridge..."

    # Create bridge
    ip link add "$BRIDGE_NAME" type bridge
    ip link set "$BRIDGE_NAME" up

    # Assign IP to bridge (for host access to zones)
    ip addr add "$BRIDGE_IP" dev "$BRIDGE_NAME"

    log_success "Bridge $BRIDGE_NAME created and activated"
}

connect_zones() {
    echo ""
    log_info "[3/6] Creating veth pairs and connecting zones..."

    for zone in "${!ZONES[@]}"; do
        local zone_ip="${ZONES[$zone]%%:*}"

        # Create veth pair
        ip link add "veth-${zone}-ns" type veth peer name "veth-${zone}-br"

        # Connect one end to bridge
        ip link set "veth-${zone}-br" master "$BRIDGE_NAME"
        ip link set "veth-${zone}-br" up

        # Move other end to namespace
        ip link set "veth-${zone}-ns" netns "zone-${zone}"

        # Configure namespace interface
        ip netns exec "zone-${zone}" ip link set "veth-${zone}-ns" name eth0
        ip netns exec "zone-${zone}" ip addr add "${zone_ip}/24" dev eth0
        ip netns exec "zone-${zone}" ip link set eth0 up
        ip netns exec "zone-${zone}" ip link set lo up

        log_success "Connected zone-${zone} to bridge (${zone_ip}/24)"
    done
}

configure_routing() {
    echo ""
    log_info "[4/6] Configuring routing..."

    local gateway="${BRIDGE_IP%%/*}"

    for zone in "${!ZONES[@]}"; do
        ip netns exec "zone-${zone}" ip route add default via "$gateway"
    done

    log_success "Default routes configured for all zones"
}

apply_firewall_rules() {
    echo ""
    log_info "[5/6] Applying nftables firewall rules..."

    # Web Zone - Allow HTTP/HTTPS from anywhere, SSH from mgmt
    ip netns exec zone-web nft -f - << 'EOF'
flush ruleset

table inet filter {
    chain input {
        type filter hook input priority 0; policy drop;

        # Connection tracking - MUST be first
        ct state established,related accept comment "Allow established/related"
        ct state invalid drop comment "Drop invalid packets"

        # Loopback
        iif "lo" accept comment "Allow loopback"

        # HTTP/HTTPS from anywhere
        tcp dport 80 accept comment "HTTP"
        tcp dport 443 accept comment "HTTPS"

        # SSH from management network
        ip saddr 10.100.0.0/16 tcp dport 22 accept comment "SSH from mgmt"

        # ICMP for diagnostics
        icmp type echo-request accept comment "ICMP ping"

        # Log dropped packets
        log prefix "[zone-web DROP] " limit rate 3/minute
    }

    chain output {
        type filter hook output priority 0; policy accept;
    }
}
EOF
    log_success "zone-web: Allow 80/443/22, deny others"

    # App Zone - Allow 8080 ONLY from Web Zone
    ip netns exec zone-app nft -f - << 'EOF'
flush ruleset

table inet filter {
    chain input {
        type filter hook input priority 0; policy drop;

        ct state established,related accept comment "Allow established/related"
        ct state invalid drop comment "Drop invalid packets"

        iif "lo" accept comment "Allow loopback"

        # Port 8080 ONLY from Web Zone (10.100.1.10)
        ip saddr 10.100.1.10 tcp dport 8080 accept comment "App from Web only"

        # SSH from management
        ip saddr 10.100.0.0/16 tcp dport 22 accept comment "SSH from mgmt"

        # ICMP for diagnostics
        icmp type echo-request accept comment "ICMP ping"

        log prefix "[zone-app DROP] " limit rate 3/minute
    }

    chain output {
        type filter hook output priority 0; policy accept;
    }
}
EOF
    log_success "zone-app: Allow 8080 from web only"

    # DB Zone - Allow 3306 ONLY from App Zone
    ip netns exec zone-db nft -f - << 'EOF'
flush ruleset

table inet filter {
    chain input {
        type filter hook input priority 0; policy drop;

        ct state established,related accept comment "Allow established/related"
        ct state invalid drop comment "Drop invalid packets"

        iif "lo" accept comment "Allow loopback"

        # Port 3306 ONLY from App Zone (10.100.1.20)
        ip saddr 10.100.1.20 tcp dport 3306 accept comment "DB from App only"

        # SSH from management
        ip saddr 10.100.0.0/16 tcp dport 22 accept comment "SSH from mgmt"

        # ICMP for diagnostics
        icmp type echo-request accept comment "ICMP ping"

        log prefix "[zone-db DROP] " limit rate 3/minute
    }

    chain output {
        type filter hook output priority 0; policy accept;
    }
}
EOF
    log_success "zone-db: Allow 3306 from app only"
}

start_test_services() {
    echo ""
    log_info "[6/6] Starting test services..."

    # Web Zone - Simple HTTP server on port 80
    ip netns exec zone-web python3 -m http.server 80 --bind 0.0.0.0 &>/dev/null &
    log_success "zone-web: python http.server on :80"

    # App Zone - Simple HTTP server on port 8080
    ip netns exec zone-app python3 -m http.server 8080 --bind 0.0.0.0 &>/dev/null &
    log_success "zone-app: python http.server on :8080"

    # DB Zone - Simple TCP listener on port 3306 (simulating MySQL)
    ip netns exec zone-db bash -c 'while true; do nc -l -p 3306 -c "echo MySQL-Simulator"; done' &>/dev/null &
    log_success "zone-db: nc listening on :3306"

    # Wait for services to start
    sleep 2
}

print_summary() {
    echo ""
    echo "======================================================================"
    echo -e "${GREEN}Setup Complete!${NC}"
    echo "======================================================================"
    echo ""
    echo "Network Architecture:"
    echo "  Bridge: $BRIDGE_NAME (${BRIDGE_IP})"
    echo ""
    echo "  Zone        IP              Service     Allowed From"
    echo "  ────────    ──────────────  ──────────  ────────────────────"
    echo "  zone-web    10.100.1.10     :80/443     anywhere"
    echo "  zone-app    10.100.1.20     :8080       zone-web only"
    echo "  zone-db     10.100.1.30     :3306       zone-app only"
    echo ""
    echo "Quick Test Commands:"
    echo "  # Test Web Zone (should work)"
    echo "  curl http://10.100.1.10:80"
    echo ""
    echo "  # Test App Zone from outside (should fail)"
    echo "  curl --connect-timeout 2 http://10.100.1.20:8080"
    echo ""
    echo "  # Test Web -> App (should work)"
    echo "  sudo ip netns exec zone-web curl http://10.100.1.20:8080"
    echo ""
    echo "  # Run full verification"
    echo "  sudo ./verify.sh"
    echo ""
    echo "======================================================================"
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------

main() {
    echo "======================================================================"
    echo "Multi-Zone Network Setup - Three-Tier Architecture"
    echo "======================================================================"

    check_root
    check_dependencies
    cleanup_existing

    create_namespaces
    create_bridge
    connect_zones
    configure_routing
    apply_firewall_rules
    start_test_services

    print_summary
}

main "$@"
