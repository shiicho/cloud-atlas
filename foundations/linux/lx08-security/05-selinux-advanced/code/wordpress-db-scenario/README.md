# WordPress Remote Database Connection Scenario

## Scenario Description

This scenario simulates the common issue where WordPress on RHEL 9 cannot connect to an external database (like Amazon RDS) due to SELinux restrictions.

**Symptoms:**
- WordPress shows "Error establishing a database connection"
- `telnet rds-host 3306` works fine from the server
- File permissions are correct
- SELinux is in Enforcing mode

**Root Cause:**
The `httpd_can_network_connect_db` Boolean is `off` by default, preventing Apache/httpd processes from initiating outbound connections to database ports.

## Files

| File | Description |
|------|-------------|
| `diagnose-connection.sh` | Diagnose the connection issue |
| `fix-boolean.sh` | Apply the Boolean fix |
| `verify-fix.sh` | Verify the fix is working |
| `simulate-avc.sh` | Simulate AVC denial for learning |

## Usage

```bash
# Step 1: Run diagnosis
sudo bash diagnose-connection.sh

# Step 2: Apply fix
sudo bash fix-boolean.sh

# Step 3: Verify
sudo bash verify-fix.sh
```

## Learning Objectives

1. Identify SELinux as the cause when network tests pass but application fails
2. Use `ausearch` and `audit2why` to diagnose
3. Find and apply the correct Boolean
4. Document the change properly
