# Pre-Audit SUID Cleanup Scenario

> **Scenario**: A financial client requires servers to pass CIS Benchmark scans before go-live.  
> The scan flags several unnecessary SUID binaries as privilege escalation risks.  
> Your task: Find all SUID files, assess necessity, remove SUID from unnecessary files, document exceptions.  

## Learning Objectives

1. Understand SUID/SGID security risks
2. Use `find` to discover SUID/SGID files
3. Assess which SUID files are necessary
4. Safely remove SUID permissions
5. Document exceptions for required SUID files

## Scenario Background

### What is SUID?

SUID (Set User ID) is a special permission bit that allows a program to run with the privileges of the file owner (usually root), regardless of who executes it.

```
Normal file:     -rwxr-xr-x (755)
SUID file:       -rwsr-xr-x (4755)  <- Note the 's'
```

### Why is SUID a Security Risk?

If a SUID-root program has a vulnerability, an attacker can exploit it to gain root access:

```
Attacker -> Exploits bug in SUID program -> Gains root shell
            (running as normal user)        (full system access)
```

Real-world examples:
- **CVE-2021-4034 (PwnKit)**: pkexec vulnerability, root access via SUID
- **CVE-2019-14287**: sudo configuration bypass

## Workflow

```
Step 1: Discover       Step 2: Analyze        Step 3: Cleanup
┌───────────────┐     ┌───────────────┐     ┌───────────────┐
│ discover-     │────▶│ analyze-      │────▶│ cleanup-      │
│ suid.sh       │     │ suid.sh       │     │ suid.sh       │
│               │     │               │     │               │
│ Find all SUID │     │ Categorize    │     │ Remove SUID   │
│ files         │     │ and assess    │     │ from flagged  │
└───────────────┘     └───────────────┘     └───────────────┘
        │                     │                     │
        ▼                     ▼                     ▼
/tmp/suid-audit/        Report with          Log + backup
suid-files.txt          recommendations      for rollback
```

## Usage

### Step 1: Discover SUID Files

```bash
# Find all SUID and SGID files on the system
sudo bash discover-suid.sh

# Output:
# - /tmp/suid-audit/suid-files.txt
# - /tmp/suid-audit/sgid-files.txt
# - Summary on console
```

### Step 2: Analyze Files

```bash
# Generate detailed assessment report
sudo bash analyze-suid.sh

# Output:
# - /tmp/suid-audit/suid-analysis-report.md
# - Categories: Essential, Review, Removable, Unknown
```

### Step 3: Review and Cleanup

```bash
# First, dry run to see what would change
sudo bash cleanup-suid.sh --dry-run

# If satisfied, apply changes
sudo bash cleanup-suid.sh

# Output:
# - /tmp/suid-audit/cleanup-log.txt
# - /tmp/suid-audit/suid-backup.txt (for rollback)
```

### Step 4: Verify

```bash
# Re-run discovery to confirm changes
sudo bash discover-suid.sh

# Run OpenSCAP scan
sudo bash ../openscap-scan.sh
```

## Common SUID Files Assessment

### Essential (DO NOT REMOVE SUID)

| File | Reason |
|------|--------|
| `/usr/bin/passwd` | Users need to change passwords |
| `/usr/bin/sudo` | Privilege elevation framework |
| `/usr/bin/su` | User switching |
| `/usr/sbin/unix_chkpwd` | PAM password checking |

### Recommended for SUID Removal

| File | Reason |
|------|--------|
| `/usr/bin/newgrp` | Rarely used, users don't typically switch groups |
| `/usr/bin/chfn` | Finger info change - admin should control |
| `/usr/bin/chsh` | Shell change - admin should control |
| `/usr/bin/write` | Terminal messaging - not needed on servers |

### Case-by-Case Review

| File | Consider Removal If... |
|------|------------------------|
| `/usr/bin/mount` | No user-mountable filesystems |
| `/usr/bin/umount` | No user-mountable filesystems |
| `/usr/bin/pkexec` | No GUI or polkit-based auth |
| `/usr/bin/crontab` | Cron access restricted to admin |

## Exception Documentation

If you cannot remove SUID from a file, document the exception:

```bash
# Copy the exception template
cp ../exception-template.md ./my-suid-exception.md

# Fill in the required information
# - Control ID: CIS X.X.X (SUID related)
# - Business justification
# - Risk assessment
# - Compensating controls
```

Example compensating controls for retained SUID:
- Restrict file execution with ACLs
- Monitor execution with auditd
- Apply SELinux policies

## Rollback

If cleanup causes issues:

```bash
# View the backup
cat /tmp/suid-audit/suid-backup.txt

# Restore individual file
sudo chmod u+s /usr/bin/newgrp

# Or source the backup script
sudo bash /tmp/suid-audit/suid-backup.txt
```

## CIS Benchmark References

- **CIS RHEL 9 Benchmark**: Section 6.1.x (File Permissions)
- **OpenSCAP Rule**: `file_permissions_unauthorized_suid`
- **STIG ID**: RHEL-09-XXX (SUID restrictions)

## Troubleshooting

### "Permission denied" after removing SUID

Some programs require SUID to function. If a user reports issues:

1. Check which file they need: `which <command>`
2. Verify SUID status: `ls -la /usr/bin/<command>`
3. Assess if SUID is truly needed
4. If needed, restore: `sudo chmod u+s /usr/bin/<command>`
5. Document as exception

### How to check if a binary needs SUID

```bash
# Check file capabilities (alternative to SUID)
getcap /path/to/binary

# Check what the binary does
file /path/to/binary
strings /path/to/binary | grep -i "privilege\|suid\|root" | head

# Check package documentation
rpm -qi $(rpm -qf /path/to/binary) | grep -i description -A 5
```
