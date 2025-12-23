#!/bin/bash
set -e
# 06-ansible-doc.sh - Using ansible-doc for module documentation

echo "=== List all modules ==="
ansible-doc -l | head -20

echo ""
echo "=== Get help for file module ==="
ansible-doc file | head -50

echo ""
echo "=== Get help for copy module ==="
ansible-doc copy | head -50

echo ""
echo "=== Get module examples only ==="
ansible-doc -s file
