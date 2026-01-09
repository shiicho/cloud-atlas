#!/bin/bash
# =============================================================================
# iptables to nftables Migration Example
# =============================================================================
#
# Description: Demonstrates how to migrate from iptables to nftables
# Platform: RHEL 9 / AlmaLinux 9 / Debian 11+ / Ubuntu 22.04+
#
# This script shows the migration process, not meant to be run directly.
# Review and adapt to your environment.
#
# =============================================================================

set -e

echo "=== iptables to nftables Migration Guide ==="
echo ""

# -----------------------------------------------------------------------------
# Step 1: Check current state
# -----------------------------------------------------------------------------
echo "[Step 1] Check current firewall state"
echo ""

echo "# Check which backend iptables uses:"
echo "iptables -V"
echo "# Output: iptables v1.8.x (nf_tables)  <- nftables backend"
echo "# Output: iptables v1.8.x (legacy)     <- legacy backend"
echo ""

echo "# List current iptables rules:"
echo "iptables-save"
echo ""

# -----------------------------------------------------------------------------
# Step 2: Backup current rules
# -----------------------------------------------------------------------------
echo "[Step 2] Backup current iptables rules"
echo ""

echo "# Backup IPv4 rules:"
echo "iptables-save > /tmp/iptables-backup.txt"
echo ""

echo "# Backup IPv6 rules (if used):"
echo "ip6tables-save > /tmp/ip6tables-backup.txt"
echo ""

# -----------------------------------------------------------------------------
# Step 3: Translate rules
# -----------------------------------------------------------------------------
echo "[Step 3] Translate iptables rules to nftables"
echo ""

echo "# Translate single rule:"
echo "iptables-translate -A INPUT -p tcp --dport 22 -j ACCEPT"
echo "# Output: nft add rule ip filter INPUT tcp dport 22 counter accept"
echo ""

echo "# Translate entire ruleset:"
echo "iptables-restore-translate < /tmp/iptables-backup.txt > /tmp/nftables-rules.nft"
echo ""

# -----------------------------------------------------------------------------
# Step 4: Example translation
# -----------------------------------------------------------------------------
echo "[Step 4] Example: iptables -> nftables translation"
echo ""

echo "Original iptables rules (/tmp/iptables-backup.txt):"
cat << 'IPTABLES_EXAMPLE'
*filter
:INPUT DROP [0:0]
:FORWARD DROP [0:0]
:OUTPUT ACCEPT [0:0]
-A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
-A INPUT -i lo -j ACCEPT
-A INPUT -p tcp --dport 22 -j ACCEPT
-A INPUT -p tcp -m multiport --dports 80,443 -j ACCEPT
-A INPUT -p icmp -j ACCEPT
-A INPUT -j LOG --log-prefix "[iptables DROP] "
COMMIT
IPTABLES_EXAMPLE
echo ""

echo "Translated nftables rules (/tmp/nftables-rules.nft):"
cat << 'NFTABLES_EXAMPLE'
table ip filter {
    chain INPUT {
        type filter hook input priority 0; policy drop;
        ct state established,related counter accept
        iif "lo" counter accept
        tcp dport 22 counter accept
        tcp dport { 80, 443 } counter accept
        ip protocol icmp counter accept
        counter log prefix "[iptables DROP] "
    }

    chain FORWARD {
        type filter hook forward priority 0; policy drop;
    }

    chain OUTPUT {
        type filter hook output priority 0; policy accept;
    }
}
NFTABLES_EXAMPLE
echo ""

# -----------------------------------------------------------------------------
# Step 5: Validate and apply
# -----------------------------------------------------------------------------
echo "[Step 5] Validate and apply nftables rules"
echo ""

echo "# Validate syntax (CRITICAL - always do this first!):"
echo "nft -c -f /tmp/nftables-rules.nft"
echo ""

echo "# Set up safety recovery (recommended):"
echo "nohup bash -c 'sleep 300 && nft -f /etc/nftables.conf' &"
echo ""

echo "# Apply new rules:"
echo "nft -f /tmp/nftables-rules.nft"
echo ""

echo "# Verify rules:"
echo "nft list ruleset"
echo ""

# -----------------------------------------------------------------------------
# Step 6: Persist and cleanup
# -----------------------------------------------------------------------------
echo "[Step 6] Persist changes and cleanup"
echo ""

echo "# Save to system config:"
echo "cp /tmp/nftables-rules.nft /etc/nftables.conf"
echo ""

echo "# Disable iptables services:"
echo "systemctl disable iptables"
echo "systemctl disable ip6tables"
echo ""

echo "# Enable nftables service:"
echo "systemctl enable nftables"
echo "systemctl restart nftables"
echo ""

echo "# Verify service status:"
echo "systemctl status nftables"
echo ""

# -----------------------------------------------------------------------------
# Important notes
# -----------------------------------------------------------------------------
echo "=== Important Notes ==="
echo ""
echo "1. RHEL 9+ uses nftables backend by default"
echo "   Even 'iptables' commands actually use nftables"
echo ""
echo "2. Don't mix iptables and nftables direct commands"
echo "   Choose one approach and stick with it"
echo ""
echo "3. firewalld uses nftables backend on modern systems"
echo "   If using firewalld, let it manage the rules"
echo ""
echo "4. Always validate before applying!"
echo "   nft -c -f config.nft"
echo ""
echo "5. Keep a backup SSH session open during changes"
echo ""
