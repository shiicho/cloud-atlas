#!/bin/bash
# =============================================================================
# Linux Capabilities Demo Script - cap-demo.sh
# =============================================================================
#
# PURPOSE: Demonstrate Linux Capabilities usage and inspection
#
# REQUIREMENTS:
#   - libcap (provides getcap, setcap, capsh)
#   - Run with sudo for certain operations
#
# WHAT IT DOES:
#   1. Shows all files with capabilities in the system
#   2. Displays current process capabilities
#   3. Demonstrates capability setting and usage
#   4. Provides interactive examples
#
# =============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Header function
print_header() {
    echo ""
    echo -e "${BLUE}============================================${NC}"
    echo -e "${BLUE} $1${NC}"
    echo -e "${BLUE}============================================${NC}"
    echo ""
}

# Check if libcap tools are installed
check_requirements() {
    print_header "Checking Requirements"

    local missing=0

    for cmd in getcap setcap capsh; do
        if command -v $cmd &>/dev/null; then
            echo -e "  ${GREEN}[OK]${NC} $cmd found: $(which $cmd)"
        else
            echo -e "  ${RED}[MISSING]${NC} $cmd not found"
            missing=1
        fi
    done

    if [[ $missing -eq 1 ]]; then
        echo ""
        echo -e "${YELLOW}Install libcap:${NC}"
        echo "  RHEL/CentOS: sudo dnf install libcap"
        echo "  Debian/Ubuntu: sudo apt install libcap2-bin"
        exit 1
    fi

    echo ""
    echo -e "${GREEN}All requirements met!${NC}"
}

# Section 1: System-wide capabilities scan
scan_system_capabilities() {
    print_header "1. System-Wide Capabilities Scan"

    echo "Files with capabilities set (limited to common paths):"
    echo ""

    local count=0
    for path in /usr/bin /usr/sbin /bin /sbin; do
        if [[ -d "$path" ]]; then
            while IFS= read -r line; do
                if [[ -n "$line" ]]; then
                    echo "  $line"
                    ((count++))
                fi
            done < <(getcap -r "$path" 2>/dev/null)
        fi
    done

    echo ""
    echo -e "Total files with capabilities: ${GREEN}$count${NC}"
    echo ""
    echo "Common capabilities you might see:"
    echo "  - cap_net_raw=ep         : Raw socket access (ping)"
    echo "  - cap_net_bind_service=ep: Bind to ports < 1024"
    echo "  - cap_net_admin=ep       : Network administration"
}

# Section 2: Current process capabilities
show_process_capabilities() {
    print_header "2. Current Process Capabilities"

    echo "Current shell (PID: $$) capabilities:"
    echo ""

    # Get capability values
    cat /proc/$$/status | grep -E "^Cap" | while read line; do
        cap_name=$(echo "$line" | awk '{print $1}' | tr -d ':')
        cap_value=$(echo "$line" | awk '{print $2}')
        echo -e "  ${cap_name}: $cap_value"
    done

    echo ""
    echo "Decoded capabilities using capsh:"
    echo ""

    # Decode each capability set
    for cap_type in CapInh CapPrm CapEff CapBnd CapAmb; do
        cap_value=$(grep "^$cap_type" /proc/$$/status | awk '{print $2}')
        if [[ -n "$cap_value" ]]; then
            decoded=$(capsh --decode=$cap_value 2>/dev/null || echo "decode failed")
            printf "  %-8s: %s\n" "$cap_type" "$decoded"
        fi
    done

    echo ""
    echo "Capability set meanings:"
    echo "  CapInh (Inheritable): Capabilities preserved across execve"
    echo "  CapPrm (Permitted):   Maximum capabilities available"
    echo "  CapEff (Effective):   Currently active capabilities"
    echo "  CapBnd (Bounding):    Upper limit on acquirable capabilities"
    echo "  CapAmb (Ambient):     Capabilities passed to non-SUID programs"
}

# Section 3: Demonstrate capability setting
demo_capability_setting() {
    print_header "3. Capability Setting Demo (requires sudo)"

    # Check if we have sudo access
    if [[ $EUID -eq 0 ]]; then
        echo "Running as root, proceeding with demo..."
    else
        echo -e "${YELLOW}This section requires sudo access.${NC}"
        echo "Showing commands only (not executing):"
        echo ""
        echo "# Create a test binary (copy of cat)"
        echo "sudo cp /usr/bin/cat /tmp/cat-cap-demo"
        echo ""
        echo "# Set capability"
        echo "sudo setcap 'cap_dac_read_search=+ep' /tmp/cat-cap-demo"
        echo ""
        echo "# Verify capability"
        echo "getcap /tmp/cat-cap-demo"
        echo "# Expected: /tmp/cat-cap-demo cap_dac_read_search=ep"
        echo ""
        echo "# Remove capability"
        echo "sudo setcap -r /tmp/cat-cap-demo"
        echo ""
        echo "# Cleanup"
        echo "sudo rm /tmp/cat-cap-demo"
        return
    fi

    # Actual demo (only runs as root)
    local test_binary="/tmp/cat-cap-demo-$$"

    echo "Creating test binary..."
    cp /usr/bin/cat "$test_binary"

    echo ""
    echo "Before setting capability:"
    getcap "$test_binary" || echo "  (no capabilities)"

    echo ""
    echo "Setting cap_dac_read_search=+ep..."
    setcap 'cap_dac_read_search=+ep' "$test_binary"

    echo ""
    echo "After setting capability:"
    getcap "$test_binary"

    echo ""
    echo "Removing capability..."
    setcap -r "$test_binary"

    echo ""
    echo "After removing capability:"
    getcap "$test_binary" || echo "  (no capabilities)"

    echo ""
    echo "Cleaning up..."
    rm -f "$test_binary"

    echo -e "${GREEN}Demo completed successfully!${NC}"
}

# Section 4: Port binding demo
demo_port_binding() {
    print_header "4. Port Binding Capability Demo"

    echo "This demonstrates CAP_NET_BIND_SERVICE for binding ports < 1024"
    echo ""

    if ! command -v python3 &>/dev/null; then
        echo -e "${YELLOW}Python3 not found, skipping demo${NC}"
        return
    fi

    echo "Test script (simple-server.py):"
    echo ""
    cat << 'PYTHON'
#!/usr/bin/env python3
import socket
import os

print(f"Running as UID: {os.getuid()}")
print(f"Attempting to bind to port 80...")

try:
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sock.bind(('0.0.0.0', 80))
    sock.listen(1)
    print("SUCCESS! Listening on port 80")
    sock.close()
except PermissionError as e:
    print(f"FAILED: {e}")
    print("Solution: setcap 'cap_net_bind_service=+ep' /path/to/binary")
PYTHON

    echo ""
    echo "Expected result when running as non-root without capability:"
    echo "  FAILED: [Errno 13] Permission denied"
    echo ""
    echo "Expected result after: setcap 'cap_net_bind_service=+ep' /usr/bin/python3"
    echo "  SUCCESS! Listening on port 80"
    echo ""
    echo -e "${YELLOW}WARNING: Never set capabilities on interpreters in production!${NC}"
    echo "Use systemd AmbientCapabilities instead."
}

# Section 5: systemd integration info
show_systemd_integration() {
    print_header "5. systemd Capability Integration"

    echo "Key systemd directives for capabilities:"
    echo ""
    echo -e "${GREEN}AmbientCapabilities=${NC}"
    echo "  Capabilities granted to the service process"
    echo "  Example: AmbientCapabilities=CAP_NET_BIND_SERVICE"
    echo ""
    echo -e "${GREEN}CapabilityBoundingSet=${NC}"
    echo "  Upper limit on what capabilities can be acquired"
    echo "  Example: CapabilityBoundingSet=CAP_NET_BIND_SERVICE CAP_NET_RAW"
    echo ""
    echo -e "${GREEN}NoNewPrivileges=true${NC}"
    echo "  Prevents gaining new privileges via SUID, etc."
    echo "  Always use with AmbientCapabilities!"
    echo ""
    echo "Example service file:"
    echo ""
    cat << 'UNIT'
[Service]
User=myuser
Group=mygroup

# Grant only needed capability
AmbientCapabilities=CAP_NET_BIND_SERVICE
CapabilityBoundingSet=CAP_NET_BIND_SERVICE

# Prevent privilege escalation
NoNewPrivileges=true

# Additional hardening
ProtectSystem=strict
ProtectHome=true
PrivateTmp=true
UNIT
}

# Section 6: Container capabilities info
show_container_info() {
    print_header "6. Container Capabilities Best Practices"

    echo -e "${GREEN}Best Practice: Start with minimal capabilities${NC}"
    echo ""
    echo "# Docker/Podman: Drop all, add what you need"
    echo "docker run --cap-drop=ALL --cap-add=NET_BIND_SERVICE myapp"
    echo ""
    echo -e "${RED}Anti-Pattern: --privileged mode${NC}"
    echo ""
    echo "# NEVER use in production (disables all security)"
    echo "docker run --privileged myapp  # DANGEROUS!"
    echo ""
    echo -e "${RED}Anti-Pattern: CAP_SYS_ADMIN${NC}"
    echo ""
    echo "# CAP_SYS_ADMIN is essentially root"
    echo "docker run --cap-add=SYS_ADMIN myapp  # DANGEROUS!"
    echo ""
    echo "Kubernetes Pod Security Context:"
    echo ""
    cat << 'YAML'
securityContext:
  allowPrivilegeEscalation: false
  capabilities:
    drop:
      - ALL
    add:
      - NET_BIND_SERVICE
YAML
}

# Section 7: Common capabilities reference
show_capabilities_reference() {
    print_header "7. Common Capabilities Reference"

    printf "%-25s %-10s %s\n" "CAPABILITY" "RISK" "USE CASE"
    printf "%-25s %-10s %s\n" "-------------------------" "----------" "--------------------"
    printf "%-25s ${GREEN}%-10s${NC} %s\n" "CAP_NET_BIND_SERVICE" "Low" "Bind ports < 1024"
    printf "%-25s ${GREEN}%-10s${NC} %s\n" "CAP_NET_RAW" "Medium" "Raw sockets (ping)"
    printf "%-25s ${YELLOW}%-10s${NC} %s\n" "CAP_NET_ADMIN" "Medium" "Network config"
    printf "%-25s ${YELLOW}%-10s${NC} %s\n" "CAP_DAC_OVERRIDE" "High" "Bypass file perms"
    printf "%-25s ${YELLOW}%-10s${NC} %s\n" "CAP_SYS_PTRACE" "High" "Process debugging"
    printf "%-25s ${RED}%-10s${NC} %s\n" "CAP_SYS_ADMIN" "Critical" "ALMOST ROOT!"
    echo ""
    echo -e "${RED}WARNING: CAP_SYS_ADMIN is a catch-all capability that grants"
    echo -e "almost all root privileges. Avoid unless absolutely necessary!${NC}"
}

# Main function
main() {
    echo -e "${BLUE}"
    echo "============================================"
    echo "     Linux Capabilities Demo Script"
    echo "============================================"
    echo -e "${NC}"

    check_requirements

    echo ""
    echo "Select a section to explore:"
    echo "  1) System-wide capabilities scan"
    echo "  2) Current process capabilities"
    echo "  3) Capability setting demo"
    echo "  4) Port binding demo"
    echo "  5) systemd integration"
    echo "  6) Container capabilities"
    echo "  7) Capabilities reference"
    echo "  a) Run all sections"
    echo "  q) Quit"
    echo ""

    if [[ -n "$1" ]]; then
        choice="$1"
    else
        read -p "Enter choice [1-7, a, q]: " choice
    fi

    case $choice in
        1) scan_system_capabilities ;;
        2) show_process_capabilities ;;
        3) demo_capability_setting ;;
        4) demo_port_binding ;;
        5) show_systemd_integration ;;
        6) show_container_info ;;
        7) show_capabilities_reference ;;
        a|A)
            scan_system_capabilities
            show_process_capabilities
            demo_capability_setting
            demo_port_binding
            show_systemd_integration
            show_container_info
            show_capabilities_reference
            ;;
        q|Q) exit 0 ;;
        *) echo "Invalid choice" ;;
    esac

    echo ""
    echo -e "${GREEN}Demo completed!${NC}"
}

# Run main function
main "$@"
