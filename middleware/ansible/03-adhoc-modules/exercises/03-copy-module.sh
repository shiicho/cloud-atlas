#!/bin/bash
# 03-copy-module.sh - Copy module usage

echo "=== Copy content directly to file ==="
ansible all -m copy -a "content='Hello from Ansible\n' dest=/tmp/hello.txt"
echo ""
echo "=== Verify file content ==="
ansible all -m command -a "cat /tmp/hello.txt"
echo ""
echo "=== Copy with mode and backup ==="
ansible all -m copy -a "content='Updated content\n' dest=/tmp/hello.txt mode=0644 backup=yes"
echo ""
echo "=== Cleanup ==="
ansible all -m file -a "path=/tmp/hello.txt state=absent"