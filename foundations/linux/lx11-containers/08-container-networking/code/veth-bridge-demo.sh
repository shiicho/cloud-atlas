#!/bin/bash
# =============================================================================
# veth-bridge-demo.sh - veth pair + bridge network demo
# =============================================================================
#
# Purpose: Demonstrate container network architecture with veth pairs and bridge
# Usage:   sudo ./veth-bridge-demo.sh
#
# This script creates:
# - A bridge (br-demo) acting as a virtual switch
# - Two network namespaces (container1, container2) simulating containers
# - veth pairs connecting each namespace to the bridge
#
# Network topology:
#
#   container1 (172.20.0.2)  container2 (172.20.0.3)
#        │                         │
#      veth1-ct                  veth2-ct
#        │                         │
#      veth1-br                  veth2-br
#        │                         │
#        └────────┬────────────────┘
#                 │
#             br-demo (172.20.0.1)
#
# =============================================================================

set -e

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Network configuration
BRIDGE="br-demo"
BRIDGE_IP="172.20.0.1/24"
SUBNET="172.20.0.0/24"

# Container 1
NS1="container1"
VETH1_BR="veth1-br"
VETH1_CT="veth1-ct"
IP1="172.20.0.2/24"

# Container 2
NS2="container2"
VETH2_BR="veth2-br"
VETH2_CT="veth2-ct"
IP2="172.20.0.3/24"

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

run_cmd() {
    print_cmd "$1"
    eval "$1"
    echo ""
}

cleanup() {
    print_header "Cleanup"

    print_step "Deleting network namespaces..."
    ip netns del $NS1 2>/dev/null || true
    ip netns del $NS2 2>/dev/null || true

    print_step "Deleting bridge..."
    ip link del $BRIDGE 2>/dev/null || true

    print_info "Cleanup complete."
}

# =============================================================================
# Main script
# =============================================================================

# Check root
if [ "$EUID" -ne 0 ]; then
    echo "Error: This script must be run as root"
    exit 1
fi

# Trap for cleanup
trap cleanup EXIT

print_header "veth + Bridge Network Demo"

echo "This demo creates:"
echo "  - Bridge: $BRIDGE ($BRIDGE_IP)"
echo "  - Container 1: $NS1 ($IP1)"
echo "  - Container 2: $NS2 ($IP2)"
echo ""

# =============================================================================
# Step 1: Create bridge
# =============================================================================

print_header "Step 1: Create Bridge (Virtual Switch)"

print_step "Creating bridge $BRIDGE..."
run_cmd "ip link add $BRIDGE type bridge"

print_step "Assigning IP address to bridge..."
run_cmd "ip addr add $BRIDGE_IP dev $BRIDGE"

print_step "Bringing bridge up..."
run_cmd "ip link set $BRIDGE up"

print_info "Bridge created. This acts as a virtual switch for containers."

# =============================================================================
# Step 2: Create network namespaces
# =============================================================================

print_header "Step 2: Create Network Namespaces (Containers)"

print_step "Creating namespace $NS1..."
run_cmd "ip netns add $NS1"

print_step "Creating namespace $NS2..."
run_cmd "ip netns add $NS2"

print_step "Listing namespaces..."
run_cmd "ip netns list"

# =============================================================================
# Step 3: Create veth pairs
# =============================================================================

print_header "Step 3: Create veth Pairs (Virtual Cables)"

print_step "Creating veth pair for $NS1..."
run_cmd "ip link add $VETH1_BR type veth peer name $VETH1_CT"

print_step "Creating veth pair for $NS2..."
run_cmd "ip link add $VETH2_BR type veth peer name $VETH2_CT"

print_info "veth pairs created. Each pair is like a virtual network cable."

# =============================================================================
# Step 4: Move veth ends into namespaces
# =============================================================================

print_header "Step 4: Move veth Ends into Namespaces"

print_step "Moving $VETH1_CT into $NS1..."
run_cmd "ip link set $VETH1_CT netns $NS1"

print_step "Moving $VETH2_CT into $NS2..."
run_cmd "ip link set $VETH2_CT netns $NS2"

print_info "One end of each veth is now inside the namespace (container)."

# =============================================================================
# Step 5: Attach bridge-side veth to bridge
# =============================================================================

print_header "Step 5: Connect veth to Bridge"

print_step "Connecting $VETH1_BR to $BRIDGE..."
run_cmd "ip link set $VETH1_BR master $BRIDGE"

print_step "Connecting $VETH2_BR to $BRIDGE..."
run_cmd "ip link set $VETH2_BR master $BRIDGE"

print_step "Bringing bridge-side veth up..."
run_cmd "ip link set $VETH1_BR up"
run_cmd "ip link set $VETH2_BR up"

# =============================================================================
# Step 6: Configure namespaces
# =============================================================================

print_header "Step 6: Configure Container Network"

print_step "Configuring $NS1..."
run_cmd "ip netns exec $NS1 ip addr add $IP1 dev $VETH1_CT"
run_cmd "ip netns exec $NS1 ip link set $VETH1_CT up"
run_cmd "ip netns exec $NS1 ip link set lo up"
run_cmd "ip netns exec $NS1 ip route add default via 172.20.0.1"

print_step "Configuring $NS2..."
run_cmd "ip netns exec $NS2 ip addr add $IP2 dev $VETH2_CT"
run_cmd "ip netns exec $NS2 ip link set $VETH2_CT up"
run_cmd "ip netns exec $NS2 ip link set lo up"
run_cmd "ip netns exec $NS2 ip route add default via 172.20.0.1"

# =============================================================================
# Step 7: Verify configuration
# =============================================================================

print_header "Step 7: Verify Configuration"

print_step "Bridge status..."
run_cmd "ip link show $BRIDGE"

print_step "Bridge members..."
run_cmd "bridge link show"

print_step "Container 1 network..."
run_cmd "ip netns exec $NS1 ip addr show $VETH1_CT"

print_step "Container 2 network..."
run_cmd "ip netns exec $NS2 ip addr show $VETH2_CT"

# =============================================================================
# Step 8: Test connectivity
# =============================================================================

print_header "Step 8: Test Connectivity"

print_step "Container 1 -> Bridge (gateway)..."
run_cmd "ip netns exec $NS1 ping -c 2 172.20.0.1"

print_step "Container 2 -> Bridge (gateway)..."
run_cmd "ip netns exec $NS2 ping -c 2 172.20.0.1"

print_step "Container 1 -> Container 2..."
run_cmd "ip netns exec $NS1 ping -c 2 172.20.0.3"

print_step "Container 2 -> Container 1..."
run_cmd "ip netns exec $NS2 ping -c 2 172.20.0.2"

# =============================================================================
# Summary
# =============================================================================

print_header "Demo Complete!"

echo "Network topology:"
echo ""
echo "   container1 (172.20.0.2)  container2 (172.20.0.3)"
echo "        |                         |"
echo "      veth1-ct                  veth2-ct"
echo "        |                         |"
echo "      veth1-br                  veth2-br"
echo "        |                         |"
echo "        +----------+----------+"
echo "                   |"
echo "               br-demo (172.20.0.1)"
echo ""
echo "Key takeaways:"
echo "  1. Each container has its own network namespace"
echo "  2. veth pairs connect containers to the bridge"
echo "  3. Bridge acts as a virtual switch for container-to-container traffic"
echo "  4. This is the foundation of Docker bridge networking"
echo ""
echo "Try these commands before cleanup:"
echo "  ip netns exec container1 ip addr"
echo "  ip netns exec container1 ping 172.20.0.3"
echo "  bridge link show"
echo ""

read -p "Press Enter to cleanup and exit..."

# Cleanup happens via trap
