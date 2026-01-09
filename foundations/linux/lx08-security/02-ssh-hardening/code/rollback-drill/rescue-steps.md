# SSH Misconfiguration Recovery Guide

## Quick Reference

```bash
# If you still have a root terminal open:
sudo cp /etc/ssh/sshd_config.backup_* /etc/ssh/sshd_config
sudo sshd -t && sudo systemctl reload sshd
```

---

## Recovery Scenarios

### Scenario 1: You Have an Open Terminal Session

**Best case**: You kept a root session open before making changes.

```bash
# 1. Find the backup file
ls -la /etc/ssh/sshd_config.backup_*

# 2. Restore the backup
sudo cp /etc/ssh/sshd_config.backup_20250101_120000 /etc/ssh/sshd_config

# 3. Verify configuration is valid
sudo sshd -t
# No output = success

# 4. Reload sshd
sudo systemctl reload sshd

# 5. Test in a NEW terminal (keep this one open!)
# ssh user@localhost
```

---

### Scenario 2: Using Cloud Console (AWS, GCP, Azure)

**AWS EC2:**
```bash
# Option A: EC2 Instance Connect (if configured)
aws ec2-instance-connect send-ssh-public-key \
  --instance-id i-xxxxxxxxx \
  --availability-zone ap-northeast-1a \
  --instance-os-user ec2-user \
  --ssh-public-key file://~/.ssh/id_ed25519.pub

# Option B: SSM Session Manager (recommended)
aws ssm start-session --target i-xxxxxxxxx

# Option C: EC2 Serial Console (must be enabled first)
# AWS Console -> EC2 -> Instance -> Connect -> EC2 Serial Console
```

**GCP:**
```bash
# Use Serial Console
gcloud compute connect-to-serial-port INSTANCE_NAME --zone=ZONE

# Or use Cloud Shell with OS Login
gcloud compute ssh INSTANCE_NAME --zone=ZONE --tunnel-through-iap
```

**Azure:**
```bash
# Use Serial Console from Azure Portal
# VM -> Support + troubleshooting -> Serial console
```

Once connected, follow Scenario 1 steps.

---

### Scenario 3: Physical Console / IPMI / VNC

1. Connect to console (IPMI, iDRAC, iLO, or physical keyboard/monitor)
2. Login as root
3. Follow Scenario 1 steps

---

### Scenario 4: Live CD / Rescue Mode

When you cannot login at all (e.g., PAM or SELinux blocking console login):

**Boot into Rescue Mode:**

1. Reboot the server
2. During GRUB menu, select "Rescue" or press `e` to edit
3. Add `init=/bin/bash` to the kernel line
4. Press `Ctrl+X` or `F10` to boot

**Mount and Fix:**

```bash
# If root filesystem is read-only
mount -o remount,rw /

# Or if using separate partitions
mount /dev/sda2 /mnt  # Adjust device name

# Restore SSH config
cp /mnt/etc/ssh/sshd_config.backup_* /mnt/etc/ssh/sshd_config

# Or remove broken drop-in config
rm /mnt/etc/ssh/sshd_config.d/99-hardening.conf

# Exit and reboot
sync
exec /sbin/init
# or
reboot -f
```

**Using a Live CD:**

```bash
# Boot from Live CD/USB
# Find and mount root partition
lsblk
mount /dev/sda2 /mnt  # Adjust device name

# Restore configuration
cp /mnt/etc/ssh/sshd_config.backup_* /mnt/etc/ssh/sshd_config

# Unmount and reboot
umount /mnt
reboot
```

---

### Scenario 5: Using systemd Rescue Target

If sshd is completely broken but console login works:

```bash
# Switch to rescue mode (minimal services)
sudo systemctl isolate rescue.target

# Fix SSH configuration
cp /etc/ssh/sshd_config.backup_* /etc/ssh/sshd_config

# Return to normal mode
sudo systemctl isolate multi-user.target
```

---

## Common Misconfigurations and Fixes

### AllowUsers with Wrong Username

```bash
# Problem: AllowUsers nonexistent_user
# Solution: Remove or fix the AllowUsers line

# Find the problem
grep -n "AllowUsers" /etc/ssh/sshd_config

# Edit and fix
sudo vim /etc/ssh/sshd_config
# Delete or correct the AllowUsers line

# Test and reload
sudo sshd -t && sudo systemctl reload sshd
```

### PasswordAuthentication no (Without Keys)

```bash
# Problem: Password auth disabled but no authorized_keys

# Option 1: Re-enable password auth temporarily
echo "PasswordAuthentication yes" >> /etc/ssh/sshd_config
sudo sshd -t && sudo systemctl reload sshd

# Option 2: Add your public key
mkdir -p /home/user/.ssh
echo "ssh-ed25519 AAAAC3..." >> /home/user/.ssh/authorized_keys
chmod 700 /home/user/.ssh
chmod 600 /home/user/.ssh/authorized_keys
chown -R user:user /home/user/.ssh
```

### Syntax Error in Config

```bash
# Problem: InvalidOptionName in sshd_config
# sshd -t will show the exact line

sudo sshd -t
# Output: /etc/ssh/sshd_config: line 42: Bad configuration option: InvalidOption

# Fix: Remove or correct line 42
sudo sed -i '42d' /etc/ssh/sshd_config

# Or use vim
sudo vim /etc/ssh/sshd_config +42
```

### Wrong ListenAddress

```bash
# Problem: ListenAddress bound to wrong IP
# SSH cannot connect because it's listening on wrong interface

# Fix: Change or remove ListenAddress
grep -n "ListenAddress" /etc/ssh/sshd_config
sudo vim /etc/ssh/sshd_config
# Change to: ListenAddress 0.0.0.0
# Or delete the line to listen on all interfaces

sudo sshd -t && sudo systemctl reload sshd
```

---

## Prevention Best Practices

### Before Making Changes

```bash
# 1. Always backup first
sudo cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak.$(date +%Y%m%d)

# 2. Use drop-in files (easier to remove)
sudo vim /etc/ssh/sshd_config.d/99-mychanges.conf

# 3. Always validate before reload
sudo sshd -t

# 4. Use reload (not restart) - keeps existing connections
sudo systemctl reload sshd

# 5. Keep current terminal open until new connection works
```

### Automatic Recovery (Test Environment Only)

```bash
# Add a cron job to auto-restore every 5 minutes (for testing)
echo "*/5 * * * * root cp /etc/ssh/sshd_config.known-good /etc/ssh/sshd_config && systemctl reload sshd" \
  | sudo tee /etc/cron.d/ssh-recovery

# Remove after testing!
sudo rm /etc/cron.d/ssh-recovery
```

### Use Configuration Management

For production environments, use Ansible/Puppet/Chef to manage SSH config:

```yaml
# Ansible example
- name: Configure SSH
  template:
    src: sshd_config.j2
    dest: /etc/ssh/sshd_config
    validate: /usr/sbin/sshd -t -f %s
  notify: reload sshd
```

---

## Emergency Contacts

For production systems, ensure you have:

- [ ] Console access credentials documented
- [ ] Backup SSH keys stored securely
- [ ] Known-good sshd_config backed up off-server
- [ ] Team members who can help with console access
- [ ] Cloud provider support contact for console access

---

## Verification After Recovery

After fixing SSH, verify everything works:

```bash
# 1. Check sshd is running
sudo systemctl status sshd

# 2. Check configuration is valid
sudo sshd -t

# 3. Check sshd is listening
sudo ss -tlnp | grep sshd

# 4. Test local connection
ssh localhost

# 5. Test from another machine
# ssh user@server-ip
```
