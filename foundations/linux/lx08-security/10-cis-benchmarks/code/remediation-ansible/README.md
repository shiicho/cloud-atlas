# Ansible Remediation (Placeholder)

> **Note**: This directory is a placeholder for Ansible-based CIS remediation.  
> Detailed Ansible hardening is covered in **Lesson 11 - Hardening Automation**.  

## Why Separate Lesson?

Ansible-based remediation requires understanding of:

1. Ansible basics (inventory, playbooks, modules)
2. Idempotency principles
3. Testing strategies
4. Rollback procedures
5. Variable management for different environments

These topics deserve dedicated coverage rather than a quick reference.

## Quick Reference

For those already familiar with Ansible, here are common approaches:

### OpenSCAP Generated Playbook

```bash
# Generate Ansible playbook from SCAP content
sudo oscap xccdf generate fix \
  --profile xccdf_org.ssgproject.content_profile_cis_server_l1 \
  --fix-type ansible \
  /usr/share/xml/scap/ssg/content/ssg-rhel9-ds.xml > cis-remediation.yml

# WARNING: Review the generated playbook before running!
# Do NOT blindly execute on production systems.
```

### Community Roles

| Role | Source | Description |
|------|--------|-------------|
| `devsec.os_hardening` | Ansible Galaxy | CIS-aligned hardening |
| `geerlingguy.security` | Ansible Galaxy | General security hardening |
| `RedHatOfficial.rhel9_stig` | Automation Hub | STIG compliance |

### Installation

```bash
# Install from Ansible Galaxy
ansible-galaxy install devsec.os_hardening
ansible-galaxy install geerlingguy.security

# Install from Automation Hub (RHEL subscription required)
ansible-galaxy collection install redhat.rhel_system_roles
```

### Basic Usage

```yaml
# playbook.yml
---
- name: CIS Hardening
  hosts: servers
  become: yes
  roles:
    - devsec.os_hardening

# Run with:
# ansible-playbook -i inventory playbook.yml --check  # Dry run
# ansible-playbook -i inventory playbook.yml          # Apply
```

## Important Warnings

### 1. Never Apply Blindly

```bash
# BAD - no review, no dry run
ansible-playbook remediation.yml

# GOOD - review, dry run, verify
cat remediation.yml | less
ansible-playbook remediation.yml --check --diff
# Review output carefully
ansible-playbook remediation.yml --limit test-server
# Verify test-server works
ansible-playbook remediation.yml
```

### 2. Use Limit for Staged Rollout

```bash
# First: Single test server
ansible-playbook playbook.yml --limit test-01

# Second: Small group
ansible-playbook playbook.yml --limit staging

# Third: Production (with change window)
ansible-playbook playbook.yml --limit production
```

### 3. Always Have Rollback Plan

```yaml
# Include backup tasks in your playbook
- name: Backup sshd_config before changes
  copy:
    src: /etc/ssh/sshd_config
    dest: /etc/ssh/sshd_config.bak.{{ ansible_date_time.date }}
    remote_src: yes
```

## Next Steps

Continue to **[Lesson 11 - Hardening Automation](../../11-hardening-automation/)** for:

- Complete Ansible hardening playbook structure
- Testing strategies (molecule, test kitchen)
- CI/CD integration for security
- Compliance report generation
- Multi-environment configuration
- Rollback automation

## References

- [SCAP Security Guide](https://www.open-scap.org/security-policies/scap-security-guide/)
- [dev-sec.io](https://dev-sec.io/) - DevSec Hardening Framework
- [Ansible Security Automation](https://www.ansible.com/use-cases/security-automation)
- [CIS Ansible Benchmarks](https://www.cisecurity.org/benchmark/ansible)
