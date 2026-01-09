# systemd Capability Demo Service

This directory contains a complete example of a systemd service that:

1. Runs as a non-root user
2. Binds to port 80 (privileged port) using `CAP_NET_BIND_SERVICE`
3. Demonstrates security best practices

## Files

| File | Description |
|------|-------------|
| `cap-demo.service` | systemd unit file with capabilities configuration |
| `server.py` | Simple Python HTTP server for demonstration |

## Quick Setup

```bash
# 1. Create service user
sudo useradd -r -s /sbin/nologin capdemo

# 2. Create application directory
sudo mkdir -p /opt/capdemo

# 3. Copy server script
sudo cp server.py /opt/capdemo/
sudo chmod +x /opt/capdemo/server.py

# 4. Set ownership
sudo chown -R capdemo:capdemo /opt/capdemo

# 5. Install service
sudo cp cap-demo.service /etc/systemd/system/

# 6. Reload systemd
sudo systemctl daemon-reload

# 7. Start service
sudo systemctl start cap-demo

# 8. Check status
sudo systemctl status cap-demo
```

## Verification

```bash
# Check listening port
ss -tlnp | grep :80

# Check process capabilities
PID=$(systemctl show cap-demo -p MainPID --value)
sudo cat /proc/$PID/status | grep Cap

# Decode effective capabilities
sudo capsh --decode=$(sudo cat /proc/$PID/status | grep CapEff | awk '{print $2}')

# Access the web interface
curl http://localhost/status
```

## Key Configuration Explained

```ini
[Service]
# Run as non-root user
User=capdemo
Group=capdemo

# Grant CAP_NET_BIND_SERVICE to bind port 80
AmbientCapabilities=CAP_NET_BIND_SERVICE

# Limit capabilities to only what's needed
CapabilityBoundingSet=CAP_NET_BIND_SERVICE

# Prevent privilege escalation via SUID
NoNewPrivileges=true
```

## Cleanup

```bash
# Stop and remove service
sudo systemctl stop cap-demo
sudo systemctl disable cap-demo
sudo rm /etc/systemd/system/cap-demo.service
sudo systemctl daemon-reload

# Remove user and files
sudo userdel capdemo
sudo rm -rf /opt/capdemo
```

## Security Notes

1. **AmbientCapabilities** grants specific capabilities to non-root services
2. **CapabilityBoundingSet** limits what capabilities can ever be acquired
3. **NoNewPrivileges** prevents SUID/SGID exploitation
4. Additional hardening options like `ProtectSystem`, `PrivateTmp` are included

## Related Documentation

- [man capabilities(7)](https://man7.org/linux/man-pages/man7/capabilities.7.html)
- [systemd.exec(5) - Capabilities](https://www.freedesktop.org/software/systemd/man/systemd.exec.html#Capabilities)
