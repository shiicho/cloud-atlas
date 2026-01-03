#!/bin/bash
set -e
# 01-setup-facts.sh - Gathering system facts

echo "=== Get all facts from a host ==="
ansible web-1.ans.local -m setup | head -50

echo ""
echo "=== Filter specific facts (ansible_distribution) ==="
ansible web-1.ans.local -m setup -a "filter=ansible_distribution*"

echo ""
echo "=== Get memory facts ==="
ansible web-1.ans.local -m setup -a "filter=ansible_mem*"

echo ""
echo "=== Get network facts ==="
ansible web-1.ans.local -m setup -a "filter=ansible_default_ipv4"
