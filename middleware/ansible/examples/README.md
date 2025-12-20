# Ansible Course Examples

> **Ready-to-run playbooks** organized by topic with progressive difficulty.

---

## Quick Start

```bash
# Clone this repo (if not already done)
git clone https://github.com/shiicho/cloud-atlas
cd cloud-atlas/content/middleware/ansible/examples

# Run any example
ansible-playbook 02-playbook-basics/solution/01-minimal-play.yaml
```

---

## How to Use These Examples

### Learning Flow

1. **Read the template** - Understand what you need to build
2. **Try it yourself** - Complete the template
3. **Compare with solution** - See the working version
4. **Diff between versions** - Understand incremental changes

```bash
# See what changed between step 1 and step 2
diff solution/01-minimal-play.yaml solution/02-with-vars.yaml
```

### Folder Structure

```
examples/
├── 01-inventory/           # Inventory formats and patterns
│   ├── template/           # Empty skeleton to complete
│   └── solution/           # Working examples (01, 02, 03...)
├── 02-playbook-basics/     # Playbook fundamentals
├── 03-variables-logic/     # Variables, facts, conditions
├── 04-loops/               # All loop types (12 examples)
├── 05-async-serial/        # Performance patterns
├── 06-roles-galaxy/        # Role structure
├── 07-aws-ssm/             # AWS SSM integration
├── 08-error-handling/      # Blocks, rescue, error handling
└── 09-vault/               # Secrets management
```

---

## Example Inventory

### 01-inventory/ (5 examples)
| File | Description |
|------|-------------|
| `01-basic-ini.ini` | Simple host list (INI format) |
| `02-with-groups.ini` | Host groups and children |
| `03-yaml-format.yaml` | YAML inventory equivalent |
| `04-group-vars/` | group_vars and host_vars |
| `05-aws-ec2-dynamic.yaml` | AWS EC2 dynamic inventory |

### 02-playbook-basics/ (5 examples)
| File | Description |
|------|-------------|
| `01-minimal-play.yaml` | Simplest possible playbook |
| `02-with-vars.yaml` | Add variables section |
| `03-with-handler.yaml` | Add handler + notify |
| `04-with-tags.yaml` | Add tags for selective run |
| `05-full-webserver.yaml` | Complete nginx deployment |

### 03-variables-logic/ (7 examples)
| File | Description |
|------|-------------|
| `01-inline-vars.yaml` | vars: section basics |
| `02-vars-in-tasks.yaml` | Using {{ variable }} |
| `03-facts-access.yaml` | ansible_distribution, etc. |
| `04-when-basic.yaml` | Simple condition |
| `05-when-multiple.yaml` | AND/OR conditions |
| `06-register-basic.yaml` | Register command output |
| `07-register-when.yaml` | Combine register + when |

### 04-loops/ (12 examples)
| File | Description |
|------|-------------|
| `01-loop-basic.yaml` | Basic loop: keyword |
| `02-with-items.yaml` | with_items (legacy) |
| `03-loop-dict.yaml` | Dictionary iteration |
| `04-loop-subelements.yaml` | Nested structures |
| `05-loop-nested.yaml` | Cartesian product |
| `06-loop-together.yaml` | Paired iteration |
| `07-loop-sequence.yaml` | Numbered sequences |
| `08-loop-fileglob.yaml` | File pattern matching |
| `09-loop-until.yaml` | Retry until condition |
| `10-loop-control.yaml` | label, pause, index_var |
| `11-loop-flatten.yaml` | Flatten nested lists |
| `12-loop-complex.yaml` | Combined techniques |

### 05-async-serial/ (6 examples)
| File | Description |
|------|-------------|
| `01-baseline.yaml` | Normal serial execution |
| `02-gather-facts-off.yaml` | Performance: skip facts |
| `03-async-poll.yaml` | Async with polling |
| `04-async-fire-forget.yaml` | Async poll: 0 |
| `05-serial-batch.yaml` | Rolling updates |
| `06-strategy-free.yaml` | Free strategy |

### 06-roles-galaxy/ (4 examples)
| File | Description |
|------|-------------|
| `01-role-init/` | After ansible-galaxy init |
| `02-role-with-vars/` | Add defaults/vars |
| `03-role-with-handlers/` | Add handlers |
| `04-role-with-molecule/` | Add molecule tests |

### 07-aws-ssm/ (3 examples)
| File | Description |
|------|-------------|
| `01-ssm-inventory.yaml` | SSM dynamic inventory |
| `02-patch-automation.yaml` | OS patching via SSM |
| `03-ssm-document.yaml` | Run SSM document |

### 08-error-handling/ (4 examples)
| File | Description |
|------|-------------|
| `01-ignore-errors.yaml` | ignore_errors: true |
| `02-failed-when.yaml` | Custom failure condition |
| `03-block-rescue.yaml` | block/rescue/always |
| `04-any-errors-fatal.yaml` | Stop on first failure |

### 09-vault/ (4 examples)
| File | Description |
|------|-------------|
| `01-encrypt-file.yaml` | ansible-vault encrypt |
| `02-encrypt-string.yaml` | Inline encrypted var |
| `03-multiple-vaults.yaml` | Multiple vault IDs |
| `04-vault-in-playbook.yaml` | Using encrypted vars |

---

## Diff Examples

See exactly what changes between versions:

```bash
# Variables: What does adding vars look like?
diff 02-playbook-basics/solution/01-minimal-play.yaml \
     02-playbook-basics/solution/02-with-vars.yaml

# Handlers: How do you add notification?
diff 02-playbook-basics/solution/02-with-vars.yaml \
     02-playbook-basics/solution/03-with-handler.yaml

# Loops: What's the difference between loop types?
diff 04-loops/solution/01-loop-basic.yaml \
     04-loops/solution/03-loop-dict.yaml
```

---

## Related Lessons

| Examples Folder | Lesson |
|-----------------|--------|
| 01-inventory/ | [02 · インベントリ管理](../02-inventory/) |
| 02-playbook-basics/ | [04 · Playbook 基礎](../04-playbook-basics/) |
| 03-variables-logic/ | [05 · 変数とロジック](../05-variables-logic/) |
| 04-loops/ | [05 · 変数とロジック](../05-variables-logic/) |
| 05-async-serial/ | [04 · Playbook 基礎](../04-playbook-basics/) |
| 06-roles-galaxy/ | [06 · Roles と Galaxy](../06-roles-galaxy/) |
| 07-aws-ssm/ | [02a · SSM 接続](../02a-ssm-connection/) |
| 08-error-handling/ | [08 · エラーハンドリング](../08-error-handling/) |
| 09-vault/ | [09 · Vault シークレット](../09-vault-secrets/) |

---

## Contributing

To add a new example:
1. Follow the numbered naming convention (`01-`, `02-`, etc.)
2. Add inline comments explaining each section
3. Keep examples focused on ONE concept
4. Update this README with the new example

---

*Based on teaching patterns from [Spurin's Dive Into Ansible](https://github.com/spurin/diveintoansible)*
