# Custom SELinux Policy Demo

## Overview

This directory contains example files for creating a custom SELinux policy module. This is provided for **learning purposes only** - in practice, always try Booleans, fcontext, and port management before resorting to custom policies.

## Files

| File | Description |
|------|-------------|
| `myapp.te` | Type Enforcement rules |
| `myapp.fc` | File Context definitions |
| `build-install.sh` | Build and install script |
| `dangerous-example.te` | Example of DANGEROUS policy (DO NOT USE) |

## When to Use Custom Policies

Custom policies are the **LAST RESORT**. Try these first:

1. **Boolean**: `setsebool -P httpd_can_network_connect on`
2. **Port**: `semanage port -a -t http_port_t -p tcp 8080`
3. **File Context**: `semanage fcontext -a -t httpd_sys_content_t '/data/www(/.*)?'`

Only create custom policies when ALL of the above fail.

## Safe Policy Creation Workflow

```bash
# 1. Switch to Permissive to collect all denials
sudo setenforce 0

# 2. Run your application, trigger all operations
./run-all-operations.sh

# 3. Collect denials
sudo ausearch -m avc -ts recent > denials.log

# 4. Generate policy (DO NOT apply blindly!)
audit2allow -i denials.log -m myapp > myapp.te

# 5. REVIEW THE POLICY CAREFULLY!
cat myapp.te
# Check each 'allow' rule

# 6. Only after review, compile and install
sudo bash build-install.sh

# 7. Switch back to Enforcing
sudo setenforce 1

# 8. Test
./test-application.sh
```

## Dangerous Patterns to Avoid

See `dangerous-example.te` for examples of policies you should NEVER accept, even if audit2allow generates them:

- Allowing access to shadow_t (password files)
- Wildcard permissions (*) on sensitive types
- Granting excessive capabilities
- Allowing execution of arbitrary binaries

## Learning Objectives

1. Understand the structure of .te and .fc files
2. Learn the policy compilation workflow
3. Recognize dangerous policy rules
4. Appreciate why Booleans are preferred
