#!/bin/bash
# 02-file-module.sh - File module and idempotence

echo "=== Create a file (first run = CHANGED) ==="
ansible all -m file -a "path=/tmp/ansible_test state=touch"

echo ""
echo "=== Set file mode (first run = CHANGED) ==="
ansible all -m file -a "path=/tmp/ansible_test state=file mode=0600"

echo ""
echo "=== Re-run same command (should be SUCCESS/green - no change) ==="
ansible all -m file -a "path=/tmp/ansible_test state=file mode=0600"

echo ""
echo "=== Create directory ==="
ansible all -m file -a "path=/tmp/ansible_dir state=directory mode=0755"

echo ""
echo "=== Cleanup ==="
ansible all -m file -a "path=/tmp/ansible_test state=absent"
ansible all -m file -a "path=/tmp/ansible_dir state=absent"
