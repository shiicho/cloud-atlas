#!/bin/bash
# 05-fetch-module.sh - Fetch module (copy from remote to local)

echo "=== Create a test file on remote hosts ==="
ansible all -m file -a "path=/tmp/remote_info.txt state=touch mode=0600"ansible all -m shell -a "hostname > /tmp/remote_info.txt"
echo ""
echo "=== Fetch files to local ==="
ansible all -m fetch -a "src=/tmp/remote_info.txt dest=./fetched/ flat=no"
echo ""
echo "=== Check fetched files ==="
ls -la ./fetched/

echo ""
echo "=== Cleanup ==="
rm -rf ./fetched
ansible all -m file -a "path=/tmp/remote_info.txt state=absent"