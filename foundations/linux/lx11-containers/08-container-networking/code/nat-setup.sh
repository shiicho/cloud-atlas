#!/bin/bash
# =============================================================================
# nat-setup.sh - Container NAT configuration with nftables
# =============================================================================
#
# Purpose: Demonstrate NAT configuration for container networking using nftables
# Usage:   sudo ./nat-setup.sh
#
# This script creates:
# - A network namespace simulating a container
# - veth pair for connectivity
# - nftables NAT rules for outbound internet access
# - Optional port forwarding (DNAT) configuration
#
# IMPORTANT: Uses nftables (modern) instead of iptables (legacy)
#
# =============================================================================

set -e

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Network configuration
NS="nat-container"
VETH_HOST="veth-nat-h"
VETH_CT="veth-nat-c"
SUBNET="172.21.0.0/24"
HOST_IP="172.21.0.1"
CONTAINER_IP="172.21.0.2"
NFT_TABLE="container_nat"

# =============================================================================
# Helper functions
# =============================================================================

print_header() {
    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
}

print_step() {
    echo -e "${GREEN}[STEP]${NC} $1"
}

print_info() {
    echo -e "${YELLOW}[INFO]${NC} $1"
}

print_cmd() {
    echo -e "${BLUE}[CMD]${NC} $1"
}

print_warn() {
    echo -e "${RED}[WARN]${NC} $1"
}

run_cmd() {
    print_cmd "$1"
    eval "$1"
    echo ""
}

cleanup() {
    print_header "Cleanup"

    print_step "Deleting network namespace..."
    ip netns del $NS 2>/dev/null || true

    print_step "Deleting nftables table..."
    nft delete table ip $NFT_TABLE 2>/dev/null || true

    print_info "Cleanup complete."
}

check_nftables() {
    if ! command -v nft &> /dev/null; then
        print_warn "nftables (nft) not found. Installing..."
        if command -v apt-get &> /dev/null; then
            apt-get update && apt-get install -y nftables
        elif command -v dnf &> /dev/null; then
            dnf install -y nftables
        else
            echo "Error: Please install nftables manually"
            exit 1
        fi
    fi
}

# =============================================================================
# Main script
# =============================================================================

# Check root
if [ "$EUID" -ne 0 ]; then
    echo "Error: This script must be run as root"
    exit 1
fi

# Check nftables
check_nftables

# Trap for cleanup
trap cleanup EXIT

print_header "Container NAT Demo with nftables"

echo "This demo creates:"
echo "  - Container namespace: $NS ($CONTAINER_IP)"
echo "  - Host-side veth: $VETH_HOST ($HOST_IP)"
echo "  - NAT table: $NFT_TABLE"
echo ""
print_info "Using nftables (modern) instead of iptables (legacy)"
echo ""

# =============================================================================
# Step 1: Create namespace and veth pair
# =============================================================================

print_header "Step 1: Create Network Environment"

print_step "Creating network namespace..."
run_cmd "ip netns add $NS"

print_step "Creating veth pair..."
run_cmd "ip link add $VETH_HOST type veth peer name $VETH_CT"

print_step "Moving container-side veth into namespace..."
run_cmd "ip link set $VETH_CT netns $NS"

print_step "Configuring host-side interface..."
run_cmd "ip addr add ${HOST_IP}/24 dev $VETH_HOST"
run_cmd "ip link set $VETH_HOST up"

print_step "Configuring container-side interface..."
run_cmd "ip netns exec $NS ip addr add ${CONTAINER_IP}/24 dev $VETH_CT"
run_cmd "ip netns exec $NS ip link set $VETH_CT up"
run_cmd "ip netns exec $NS ip link set lo up"
run_cmd "ip netns exec $NS ip route add default via $HOST_IP"

# =============================================================================
# Step 2: Enable IP forwarding
# =============================================================================

print_header "Step 2: Enable IP Forwarding"

print_step "Checking current IP forwarding status..."
current_forward=$(cat /proc/sys/net/ipv4/ip_forward)
print_info "Current ip_forward: $current_forward"

if [ "$current_forward" -eq 0 ]; then
    print_step "Enabling IP forwarding..."
    run_cmd "echo 1 > /proc/sys/net/ipv4/ip_forward"
    print_info "IP forwarding enabled (temporary, will reset on reboot)"
else
    print_info "IP forwarding already enabled"
fi

# =============================================================================
# Step 3: Configure nftables NAT
# =============================================================================

print_header "Step 3: Configure nftables NAT"

print_step "Creating NAT table..."
run_cmd "nft add table ip $NFT_TABLE"

print_step "Creating postrouting chain for SNAT/MASQUERADE..."
run_cmd "nft add chain ip $NFT_TABLE postrouting { type nat hook postrouting priority 100 \\; }"

print_step "Adding masquerade rule for container subnet..."
run_cmd "nft add rule ip $NFT_TABLE postrouting ip saddr $SUBNET masquerade"

print_step "Creating prerouting chain for DNAT (port forwarding)..."
run_cmd "nft add chain ip $NFT_TABLE prerouting { type nat hook prerouting priority -100 \\; }"

print_info "NAT configuration complete."

# =============================================================================
# Step 4: Show nftables configuration
# =============================================================================

print_header "Step 4: Show nftables Configuration"

print_step "Listing NAT table rules..."
run_cmd "nft list table ip $NFT_TABLE"

print_info "Rule explanation:"
echo "  - postrouting: MASQUERADE changes source IP to host IP for outbound traffic"
echo "  - prerouting: DNAT would redirect incoming traffic to container"
echo ""

# =============================================================================
# Step 5: Test connectivity
# =============================================================================

print_header "Step 5: Test Connectivity"

print_step "Testing container -> host..."
run_cmd "ip netns exec $NS ping -c 2 $HOST_IP"

print_step "Testing container -> external (8.8.8.8)..."
if ip netns exec $NS ping -c 3 8.8.8.8; then
    print_info "External connectivity: SUCCESS"
else
    print_warn "External connectivity: FAILED"
    echo ""
    echo "Possible causes:"
    echo "  1. No internet connection on host"
    echo "  2. Firewall blocking forwarded traffic"
    echo "  3. Missing routes on host"
fi

# =============================================================================
# Step 6: Demonstrate port forwarding (DNAT)
# =============================================================================

print_header "Step 6: Port Forwarding Example"

print_info "To forward host port 8080 to container port 80, you would run:"
echo ""
echo "  nft add rule ip $NFT_TABLE prerouting tcp dport 8080 dnat to ${CONTAINER_IP}:80"
echo ""
print_info "This would redirect incoming connections on host:8080 to container:80"
echo ""

# Let's actually add it as a demonstration
print_step "Adding port forwarding rule (8080 -> container:80)..."
run_cmd "nft add rule ip $NFT_TABLE prerouting tcp dport 8080 dnat to ${CONTAINER_IP}:80"

print_step "Updated NAT rules..."
run_cmd "nft list table ip $NFT_TABLE"

# =============================================================================
# Step 7: Compare with iptables syntax
# =============================================================================

print_header "Comparison: nftables vs iptables"

echo "nftables (modern - what we used):"
echo "  nft add table ip nat"
echo "  nft add chain ip nat postrouting { type nat hook postrouting priority 100 \\; }"
echo "  nft add rule ip nat postrouting ip saddr $SUBNET masquerade"
echo ""
echo "iptables (legacy - NOT recommended):"
echo "  iptables -t nat -A POSTROUTING -s $SUBNET -j MASQUERADE"
echo ""
print_info "nftables advantages:"
echo "  - Unified syntax for all table types"
echo "  - Better performance with large rule sets"
echo "  - Atomic rule updates"
echo "  - Native set/map support"
echo ""

# =============================================================================
# Summary
# =============================================================================

print_header "Demo Complete!"

echo "What we configured:"
echo ""
echo "   Container ($CONTAINER_IP)"
echo "        |"
echo "      veth pair"
echo "        |"
echo "   Host ($HOST_IP)"
echo "        |"
echo "   nftables NAT (MASQUERADE)"
echo "        |"
echo "   External Network"
echo ""
echo "NAT flow for outbound traffic:"
echo "  1. Container sends packet: src=$CONTAINER_IP dst=8.8.8.8"
echo "  2. NAT changes source: src=<host-public-ip> dst=8.8.8.8"
echo "  3. Response comes back: src=8.8.8.8 dst=<host-public-ip>"
echo "  4. NAT restores destination: src=8.8.8.8 dst=$CONTAINER_IP"
echo ""
echo "Key nftables commands:"
echo "  nft list ruleset          # Show all rules"
echo "  nft list table ip nat     # Show specific table"
echo "  nft flush table ip nat    # Clear table"
echo "  nft delete table ip nat   # Delete table"
echo ""

read -p "Press Enter to cleanup and exit..."

# Cleanup happens via trap
