#!/bin/bash
# 04-command-idempotent.sh - Making command module idempotent

echo "=== Command with 'creates' - only runs if file doesn't exist ==="
ansible all -m command -a "touch /tmp/marker creates=/tmp/marker"

echo ""
echo "=== Run again - should be SKIPPED (file exists) ==="
ansible all -m command -a "touch /tmp/marker creates=/tmp/marker"

echo ""
echo "=== Command with 'removes' - only runs if file exists ==="
ansible all -m command -a "rm /tmp/marker removes=/tmp/marker"

echo ""
echo "=== Run again - should be SKIPPED (file doesn't exist) ==="
ansible all -m command -a "rm /tmp/marker removes=/tmp/marker"
