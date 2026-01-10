# 11 - 安全加固自动化 / Hardening Automation

> **目标**：使用 Ansible 实现自动化安全加固，构建可审计、可重复的加固流程  
> **前置**：完成 Lesson 01-10（安全原则、SSH、SELinux、auditd、nftables、PAM、CIS Benchmarks）  
> **时间**：⚡ 30 分钟（速读）/ 🔬 120 分钟（完整实操）  
> **实战项目**：创建 SSH 加固 playbook + 合规报告生成  

---

## 将学到的内容

1. 使用 Ansible 实现自动化加固
2. 理解幂等性（Idempotency）在安全配置中的重要性
3. 构建可审计的加固流程
4. 集成 CI/CD 安全检查
5. 供应链安全入门（SBOM 概念）

---

## 先跑起来！（10 分钟）

> 在学习理论之前，先看看自动化加固是什么样子。  

```bash
# 确保你有 Ansible（如果没有，先安装）
ansible --version || sudo dnf install ansible-core -y

# 进入课程目录
cd ~/cloud-atlas/foundations/linux/lx08-security/11-hardening-automation/code

# 查看加固 playbook 的内容（先不要执行）
cat hardening-playbook.yaml

# 语法检查
ansible-playbook hardening-playbook.yaml --syntax-check

# 干运行（--check 模式，不实际执行）
# 注意：需要有可连接的主机，这里用 localhost 演示
ansible-playbook hardening-playbook.yaml --check --diff -c local -i "localhost," -l localhost
```

**你刚刚：**

- 查看了一个完整的 SSH 加固 playbook
- 进行了语法检查（确保 YAML 格式正确）
- 使用 `--check --diff` 预览了会发生什么变化

**手动 vs 自动化的对比：**

| 手动加固 | 自动化加固 |
|----------|------------|
| 每台服务器重复操作 | 一次定义，多次执行 |
| 容易遗漏步骤 | 保证一致性 |
| 无法追踪历史 | Git 版本控制 |
| 难以审计 | 代码即文档 |
| 回滚困难 | 可重复执行 |

**现在让我们理解背后的原理。**

---

## Step 1 - 自动化加固原则（15 分钟）

### 1.1 Infrastructure as Code (IaC) 安全

安全配置也是代码，应该：

```
┌─────────────────────────────────────────────────────────────────┐
│              Infrastructure as Code Security Principles          │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│   1. 版本控制 (Version Control)                                 │
│   ┌─────────────────────────────────────────────────────────┐   │
│   │  hardening-playbook.yaml                                │   │
│   │       │                                                 │   │
│   │       ├── commit: "feat: add SSH hardening"            │   │
│   │       ├── commit: "fix: correct MaxAuthTries"          │   │
│   │       └── commit: "chore: update to ed25519"           │   │
│   │                                                         │   │
│   │  每次变更都有记录，可追溯，可回滚                        │   │
│   └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│   2. 代码审查 (Code Review)                                     │
│   ┌─────────────────────────────────────────────────────────┐   │
│   │  Pull Request → Security Review → Merge                 │   │
│   │                                                         │   │
│   │  安全配置变更需要多人审核                                │   │
│   └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│   3. 测试优先 (Test First)                                      │
│   ┌─────────────────────────────────────────────────────────┐   │
│   │  Test Environment → Staging → Production                │   │
│   │                                                         │   │
│   │  先在测试环境验证，再推广到生产                          │   │
│   └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│   4. 幂等性 (Idempotency)                                       │
│   ┌─────────────────────────────────────────────────────────┐   │
│   │  运行 1 次 == 运行 100 次                                │   │
│   │                                                         │   │
│   │  结果始终一致，不会因重复执行产生副作用                   │   │
│   └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

<details>
<summary>View ASCII source</summary>

```
┌─────────────────────────────────────────────────────────────────┐
│              Infrastructure as Code Security Principles          │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│   1. 版本控制 (Version Control)                                 │
│   ┌─────────────────────────────────────────────────────────┐   │
│   │  hardening-playbook.yaml                                │   │
│   │       │                                                 │   │
│   │       ├── commit: "feat: add SSH hardening"            │   │
│   │       ├── commit: "fix: correct MaxAuthTries"          │   │
│   │       └── commit: "chore: update to ed25519"           │   │
│   │                                                         │   │
│   │  每次变更都有记录，可追溯，可回滚                        │   │
│   └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│   2. 代码审查 (Code Review)                                     │
│   ┌─────────────────────────────────────────────────────────┐   │
│   │  Pull Request → Security Review → Merge                 │   │
│   │                                                         │   │
│   │  安全配置变更需要多人审核                                │   │
│   └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│   3. 测试优先 (Test First)                                      │
│   ┌─────────────────────────────────────────────────────────┐   │
│   │  Test Environment → Staging → Production                │   │
│   │                                                         │   │
│   │  先在测试环境验证，再推广到生产                          │   │
│   └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│   4. 幂等性 (Idempotency)                                       │
│   ┌─────────────────────────────────────────────────────────┐   │
│   │  运行 1 次 == 运行 100 次                                │   │
│   │                                                         │   │
│   │  结果始终一致，不会因重复执行产生副作用                   │   │
│   └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

</details>

### 1.2 幂等性（Idempotency）详解

**幂等性**是自动化加固的核心概念：

```yaml
# 幂等操作：无论执行多少次，结果相同
- name: Set PermitRootLogin to no
  ansible.builtin.lineinfile:
    path: /etc/ssh/sshd_config
    regexp: '^PermitRootLogin'
    line: 'PermitRootLogin no'

# 执行 1 次：PermitRootLogin no
# 执行 100 次：仍然是 PermitRootLogin no
# 不会变成 PermitRootLogin no no no...
```

**非幂等操作的危险：**

```bash
# 危险！非幂等操作
echo "PermitRootLogin no" >> /etc/ssh/sshd_config

# 执行 1 次：添加一行
# 执行 3 次：添加三行（配置重复，可能导致问题）
```

**Ansible 模块的幂等性保证：**

| 模块 | 幂等性 | 说明 |
|------|--------|------|
| `lineinfile` | 幂等 | 确保某行存在/不存在 |
| `copy` | 幂等 | 文件内容一致则不变更 |
| `template` | 幂等 | 模板渲染结果一致则不变更 |
| `service` | 幂等 | 服务状态达到目标即可 |
| `shell` | **非幂等** | 每次都会执行（需谨慎使用） |
| `command` | **非幂等** | 每次都会执行（需谨慎使用） |

### 1.3 可审计变更

```bash
# 自动化加固的审计轨迹
git log --oneline hardening-playbook.yaml

# 典型输出：
# a1b2c3d feat: enable SSH key-only authentication
# d4e5f6g fix: correct nftables chain priority
# g7h8i9j chore: update CIS benchmark references
# j0k1l2m initial: create hardening playbook

# 每次变更都有：
# - 谁改的（git author）
# - 什么时候（commit date）
# - 改了什么（commit message + diff）
# - 为什么改（PR description）
```

---

## Step 2 - Ansible 加固 Playbook 详解（30 分钟）

### 2.1 SSH 加固 Playbook 结构

```bash
# 查看完整的加固 playbook
cat code/hardening-playbook.yaml
```

**Playbook 核心结构：**

```yaml
---
# =============================================================================
# SSH Hardening Playbook
# =============================================================================
# Purpose: Automated SSH security hardening following CIS Benchmark
# Version: 1.0
# Author: Security Team
# Last Updated: 2026-01-04
# =============================================================================

- name: SSH Security Hardening
  hosts: servers
  become: yes

  vars:
    # 可配置变量（便于不同环境调整）
    ssh_permit_root_login: "no"
    ssh_password_auth: "no"
    ssh_max_auth_tries: 3
    ssh_client_alive_interval: 300
    ssh_client_alive_count_max: 2

  handlers:
    - name: Validate SSH config
      ansible.builtin.command: sshd -t
      changed_when: false
      listen: "validate and restart sshd"

    - name: Restart SSH
      ansible.builtin.service:
        name: sshd
        state: restarted
      listen: "validate and restart sshd"

  tasks:
    # 任务列表...
```

### 2.2 关键任务解析

**任务 1：禁止 root 登录**

```yaml
- name: Disable root login
  ansible.builtin.lineinfile:
    path: /etc/ssh/sshd_config
    regexp: '^#?PermitRootLogin'
    line: 'PermitRootLogin {{ ssh_permit_root_login }}'
    validate: 'sshd -t -f %s'
  notify: validate and restart sshd
```

**解析：**

| 参数 | 含义 | 为什么重要 |
|------|------|-----------|
| `regexp` | 匹配现有行 | 确保替换而不是追加 |
| `line` | 目标配置 | 使用变量便于定制 |
| `validate` | 部署前验证 | **防止语法错误锁死** |
| `notify` | 触发 handler | 只在变更时重启服务 |

**任务 2：禁用密码认证**

```yaml
- name: Disable password authentication
  ansible.builtin.lineinfile:
    path: /etc/ssh/sshd_config
    regexp: '^#?PasswordAuthentication'
    line: 'PasswordAuthentication {{ ssh_password_auth }}'
    validate: 'sshd -t -f %s'
  notify: validate and restart sshd
```

**任务 3：配置安全算法**

```yaml
- name: Configure secure key algorithms
  ansible.builtin.blockinfile:
    path: /etc/ssh/sshd_config
    marker: "# {mark} ANSIBLE MANAGED - Key Algorithms"
    block: |
      # Secure key algorithms (2025+ recommendations)
      PubkeyAcceptedAlgorithms ssh-ed25519,sk-ssh-ed25519@openssh.com,rsa-sha2-512,rsa-sha2-256
      HostKeyAlgorithms ssh-ed25519,rsa-sha2-512,rsa-sha2-256
      KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org,diffie-hellman-group16-sha512
      Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com
      MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com
    validate: 'sshd -t -f %s'
  notify: validate and restart sshd
```

**blockinfile 特点：**

- 管理多行配置块
- 自动添加标记（marker）标识 Ansible 管理的部分
- 幂等：相同内容不会重复添加

### 2.3 Handler 链式执行

```yaml
handlers:
  # Handler 1: 验证配置
  - name: Validate SSH config
    ansible.builtin.command: sshd -t
    changed_when: false
    listen: "validate and restart sshd"

  # Handler 2: 重启服务（在验证成功后执行）
  - name: Restart SSH
    ansible.builtin.service:
      name: sshd
      state: restarted
    listen: "validate and restart sshd"
```

**为什么使用 handler 链？**

```
配置变更 → notify → Handler 1 (sshd -t 验证) → Handler 2 (restart)
                           │
                           └── 如果验证失败，playbook 停止
                               配置不会应用，服务不会重启
                               避免锁死风险！
```

---

## Step 3 - 社区 Hardening Roles（20 分钟）

### 3.1 常用 Hardening Roles

不需要从零开始，社区有成熟的加固 roles：

| Role | 用途 | 维护者 |
|------|------|--------|
| `geerlingguy.security` | 通用 Linux 安全加固 | Jeff Geerling |
| `devsec.hardening` | CIS/STIG 合规加固 | dev-sec.io |
| `RedHatOfficial.rhel*_stig` | RHEL STIG 合规 | Red Hat |

### 3.2 使用 geerlingguy.security

```bash
# 安装 role
ansible-galaxy install geerlingguy.security

# 查看 role 变量
cat ~/.ansible/roles/geerlingguy.security/defaults/main.yml
```

**使用示例：**

```yaml
---
- name: Apply security hardening
  hosts: servers
  become: yes

  roles:
    - role: geerlingguy.security
      vars:
        security_sudoers_passwordless: []
        security_sudoers_passworded:
          - "admin"
        security_autoupdate_enabled: true
        security_fail2ban_enabled: true
```

### 3.3 使用 devsec.hardening

```bash
# 安装 collection
ansible-galaxy collection install devsec.hardening

# 使用 SSH hardening role
```

**使用示例：**

```yaml
---
- name: Apply DevSec hardening
  hosts: servers
  become: yes

  collections:
    - devsec.hardening

  roles:
    - ssh_hardening

  vars:
    # 自定义变量覆盖默认值
    ssh_permit_root_login: "no"
    ssh_allow_tcp_forwarding: "no"
    ssh_max_auth_retries: 3
```

### 3.4 RHEL STIG Roles

针对美国政府安全标准（Security Technical Implementation Guide）：

```bash
# 安装 Red Hat STIG roles
ansible-galaxy collection install redhatofficial.rhel9_stig

# 使用
```

```yaml
---
- name: Apply RHEL 9 STIG
  hosts: servers
  become: yes

  collections:
    - redhatofficial.rhel9_stig

  roles:
    - rhel9_stig
```

> **注意**：STIG roles 非常严格，可能影响业务功能。务必在测试环境充分验证。  

---

## Step 4 - 变更管理流程（20 分钟）

### 4.1 测试环境验证

```
┌─────────────────────────────────────────────────────────────────┐
│                    Hardening Change Management Flow              │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│   开发                                                          │
│   ┌─────────────────────────────────────────────────────────┐   │
│   │  1. 编写/修改 playbook                                   │   │
│   │  2. 本地语法检查 (ansible-playbook --syntax-check)      │   │
│   │  3. 提交 Pull Request                                    │   │
│   └──────────────────────┬──────────────────────────────────┘   │
│                          │                                       │
│                          ▼                                       │
│   测试环境                                                       │
│   ┌─────────────────────────────────────────────────────────┐   │
│   │  4. CI/CD 自动测试                                       │   │
│   │     - 语法检查                                           │   │
│   │     - Lint (ansible-lint)                               │   │
│   │     - Molecule 测试                                      │   │
│   │  5. 部署到测试服务器                                     │   │
│   │  6. OpenSCAP 合规扫描                                    │   │
│   │  7. 功能验证（SSH 仍可连接？）                           │   │
│   └──────────────────────┬──────────────────────────────────┘   │
│                          │                                       │
│                          ▼                                       │
│   Staging                                                        │
│   ┌─────────────────────────────────────────────────────────┐   │
│   │  8. 灰度发布（10% 服务器）                               │   │
│   │  9. 监控 24 小时                                         │   │
│   │  10. 无异常则继续                                        │   │
│   └──────────────────────┬──────────────────────────────────┘   │
│                          │                                       │
│                          ▼                                       │
│   生产环境                                                       │
│   ┌─────────────────────────────────────────────────────────┐   │
│   │  11. 分批部署（25% → 50% → 100%）                       │   │
│   │  12. 每批后监控                                          │   │
│   │  13. 异常时回滚                                          │   │
│   └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

<details>
<summary>View ASCII source</summary>

```
┌─────────────────────────────────────────────────────────────────┐
│                    Hardening Change Management Flow              │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│   开发                                                          │
│   ┌─────────────────────────────────────────────────────────┐   │
│   │  1. 编写/修改 playbook                                   │   │
│   │  2. 本地语法检查 (ansible-playbook --syntax-check)      │   │
│   │  3. 提交 Pull Request                                    │   │
│   └──────────────────────┬──────────────────────────────────┘   │
│                          │                                       │
│                          ▼                                       │
│   测试环境                                                       │
│   ┌─────────────────────────────────────────────────────────┐   │
│   │  4. CI/CD 自动测试                                       │   │
│   │     - 语法检查                                           │   │
│   │     - Lint (ansible-lint)                               │   │
│   │     - Molecule 测试                                      │   │
│   │  5. 部署到测试服务器                                     │   │
│   │  6. OpenSCAP 合规扫描                                    │   │
│   │  7. 功能验证（SSH 仍可连接？）                           │   │
│   └──────────────────────┬──────────────────────────────────┘   │
│                          │                                       │
│                          ▼                                       │
│   Staging                                                        │
│   ┌─────────────────────────────────────────────────────────┐   │
│   │  8. 灰度发布（10% 服务器）                               │   │
│   │  9. 监控 24 小时                                         │   │
│   │  10. 无异常则继续                                        │   │
│   └──────────────────────┬──────────────────────────────────┘   │
│                          │                                       │
│                          ▼                                       │
│   生产环境                                                       │
│   ┌─────────────────────────────────────────────────────────┐   │
│   │  11. 分批部署（25% → 50% → 100%）                       │   │
│   │  12. 每批后监控                                          │   │
│   │  13. 异常时回滚                                          │   │
│   └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

</details>

### 4.2 灰度发布策略

```yaml
# inventory 分组实现灰度
[production:children]
production_canary
production_main

[production_canary]
# 10% 服务器，先部署
server-01
server-02

[production_main]
# 90% 服务器，验证后部署
server-03
server-04
server-05
# ... 更多服务器
```

```bash
# Step 1: 部署到 canary 组
ansible-playbook hardening-playbook.yaml -l production_canary

# Step 2: 验证 24 小时后，部署到全部
ansible-playbook hardening-playbook.yaml -l production
```

### 4.3 回滚策略

**方法 1：Git 回滚**

```bash
# 查看历史版本
git log --oneline hardening-playbook.yaml

# 回滚到上一个版本
git checkout HEAD~1 -- hardening-playbook.yaml

# 重新执行 playbook
ansible-playbook hardening-playbook.yaml
```

**方法 2：配置备份回滚**

```yaml
# 在 playbook 中启用备份
- name: Modify SSH config with backup
  ansible.builtin.lineinfile:
    path: /etc/ssh/sshd_config
    regexp: '^PermitRootLogin'
    line: 'PermitRootLogin no'
    backup: yes   # 自动创建 .bak 备份
```

```bash
# 回滚时恢复备份
ansible servers -m shell -a "cp /etc/ssh/sshd_config.*.bak /etc/ssh/sshd_config" --become
ansible servers -m service -a "name=sshd state=restarted" --become
```

---

## Step 5 - CI/CD 安全集成（20 分钟）

### 5.1 CI/CD Pipeline 示例

```yaml
# .github/workflows/security-hardening.yml
name: Security Hardening CI

on:
  push:
    paths:
      - 'ansible/**'
  pull_request:
    paths:
      - 'ansible/**'

jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Install Ansible and Lint
        run: |
          pip install ansible ansible-lint

      - name: Ansible Lint
        run: |
          ansible-lint ansible/hardening-playbook.yaml

  syntax-check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Syntax Check
        run: |
          pip install ansible
          ansible-playbook ansible/hardening-playbook.yaml --syntax-check

  security-scan:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Install Trivy
        run: |
          sudo apt-get install wget apt-transport-https gnupg lsb-release
          wget -qO - https://aquasecurity.github.io/trivy-repo/deb/public.key | sudo apt-key add -
          echo deb https://aquasecurity.github.io/trivy-repo/deb $(lsb_release -sc) main | sudo tee /etc/apt/sources.list.d/trivy.list
          sudo apt-get update
          sudo apt-get install trivy

      - name: Scan for vulnerabilities
        run: |
          trivy config ansible/
```

### 5.2 镜像扫描（Trivy/Grype）

如果你的加固流程包含容器镜像：

```bash
# Trivy 扫描镜像漏洞
trivy image nginx:latest

# Grype 扫描
grype nginx:latest

# 扫描 Ansible playbook 中的安全问题
trivy config ansible/
```

### 5.3 合规门禁

```yaml
# 在 CI 中添加 OpenSCAP 扫描
- name: Run OpenSCAP compliance check
  run: |
    oscap xccdf eval \
      --profile cis_server_l1 \
      --results results.xml \
      --report report.html \
      /usr/share/xml/scap/ssg/content/ssg-rhel9-ds.xml

    # 检查通过率，低于 80% 则失败
    PASS_RATE=$(grep -o 'pass="[0-9]*"' results.xml | head -1 | grep -o '[0-9]*')
    TOTAL=$(grep -o 'total="[0-9]*"' results.xml | head -1 | grep -o '[0-9]*')
    RATE=$((PASS_RATE * 100 / TOTAL))

    if [ "$RATE" -lt 80 ]; then
      echo "Compliance rate $RATE% is below threshold 80%"
      exit 1
    fi
```

---

## Step 6 - 合规报告生成（15 分钟）

### 6.1 Jinja2 报告模板

```bash
# 查看报告模板
cat code/compliance-report.j2
```

**模板核心内容：**

```jinja2
# Security Hardening Compliance Report
# Generated: {{ ansible_date_time.iso8601 }}
# Target: {{ inventory_hostname }}

## System Information

| Item | Value |
|------|-------|
| Hostname | {{ ansible_hostname }} |
| OS | {{ ansible_distribution }} {{ ansible_distribution_version }} |
| Kernel | {{ ansible_kernel }} |
| IP Address | {{ ansible_default_ipv4.address | default('N/A') }} |

## SSH Hardening Status

| Setting | Expected | Actual | Status |
|---------|----------|--------|--------|
| PermitRootLogin | no | {{ ssh_config.PermitRootLogin | default('unknown') }} | {{ 'PASS' if ssh_config.PermitRootLogin == 'no' else 'FAIL' }} |
| PasswordAuthentication | no | {{ ssh_config.PasswordAuth | default('unknown') }} | {{ 'PASS' if ssh_config.PasswordAuth == 'no' else 'FAIL' }} |
| PubkeyAuthentication | yes | {{ ssh_config.PubkeyAuth | default('unknown') }} | {{ 'PASS' if ssh_config.PubkeyAuth == 'yes' else 'FAIL' }} |

## SELinux Status

- Mode: {{ ansible_selinux.mode | default('disabled') }}
- Policy: {{ ansible_selinux.type | default('N/A') }}
- Status: {{ 'PASS' if ansible_selinux.mode == 'enforcing' else 'REVIEW REQUIRED' }}

## Audit Status

- auditd: {{ 'Running' if auditd_status == 'running' else 'NOT RUNNING' }}
- Rules loaded: {{ audit_rules_count | default(0) }}
```

### 6.2 生成报告的 Playbook

```yaml
---
- name: Generate compliance report
  hosts: servers
  become: yes

  tasks:
    - name: Gather SSH config
      ansible.builtin.shell: |
        sshd -T | grep -E 'permitrootlogin|passwordauthentication|pubkeyauthentication'
      register: sshd_config_raw
      changed_when: false

    - name: Parse SSH config
      ansible.builtin.set_fact:
        ssh_config:
          PermitRootLogin: "{{ sshd_config_raw.stdout | regex_search('permitrootlogin (\\w+)', '\\1') | first }}"
          PasswordAuth: "{{ sshd_config_raw.stdout | regex_search('passwordauthentication (\\w+)', '\\1') | first }}"
          PubkeyAuth: "{{ sshd_config_raw.stdout | regex_search('pubkeyauthentication (\\w+)', '\\1') | first }}"

    - name: Check auditd status
      ansible.builtin.systemd:
        name: auditd
      register: auditd_service

    - name: Set auditd status
      ansible.builtin.set_fact:
        auditd_status: "{{ 'running' if auditd_service.status.ActiveState == 'active' else 'stopped' }}"

    - name: Count audit rules
      ansible.builtin.shell: auditctl -l | wc -l
      register: audit_rules
      changed_when: false

    - name: Set audit rules count
      ansible.builtin.set_fact:
        audit_rules_count: "{{ audit_rules.stdout }}"

    - name: Generate report
      ansible.builtin.template:
        src: compliance-report.j2
        dest: "/var/log/compliance-report-{{ ansible_date_time.date }}.md"
      delegate_to: localhost
```

---

## Step 7 - 供应链安全入门（10 分钟）

> **注意**：供应链安全的深入内容在 [LX11-CONTAINERS](../../lx11-containers/) 课程。这里只做简要介绍。  

### 7.1 什么是供应链安全？

```
┌─────────────────────────────────────────────────────────────────┐
│                    Software Supply Chain                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│   上游                                                          │
│   ┌─────────────┐    ┌─────────────┐    ┌─────────────┐        │
│   │  开源软件   │ ─▶ │  包管理器   │ ─▶ │  你的系统   │        │
│   │ (nginx,    │    │ (dnf, apt,  │    │            │        │
│   │  python)   │    │  pip, npm)  │    │            │        │
│   └─────────────┘    └─────────────┘    └─────────────┘        │
│         │                   │                   │               │
│         │                   │                   │               │
│         ▼                   ▼                   ▼               │
│   ┌─────────────────────────────────────────────────────────┐   │
│   │                    攻击向量                              │   │
│   │                                                         │   │
│   │  - 源代码篡改 (SolarWinds)                              │   │
│   │  - 依赖混淆 (Dependency Confusion)                      │   │
│   │  - 恶意包 (npm, PyPI 投毒)                              │   │
│   │  - 构建环境入侵                                         │   │
│   │  - 中间人攻击                                           │   │
│   └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│   历史事件：                                                     │
│   - 2020 SolarWinds: 影响 18,000+ 组织                         │
│   - 2021 Log4Shell: 影响数百万 Java 应用                       │
│   - 2022 npm event-stream: 加密货币钱包被盗                    │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

<details>
<summary>View ASCII source</summary>

```
┌─────────────────────────────────────────────────────────────────┐
│                    Software Supply Chain                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│   上游                                                          │
│   ┌─────────────┐    ┌─────────────┐    ┌─────────────┐        │
│   │  开源软件   │ ─▶ │  包管理器   │ ─▶ │  你的系统   │        │
│   │ (nginx,    │    │ (dnf, apt,  │    │            │        │
│   │  python)   │    │  pip, npm)  │    │            │        │
│   └─────────────┘    └─────────────┘    └─────────────┘        │
│         │                   │                   │               │
│         │                   │                   │               │
│         ▼                   ▼                   ▼               │
│   ┌─────────────────────────────────────────────────────────┐   │
│   │                    攻击向量                              │   │
│   │                                                         │   │
│   │  - 源代码篡改 (SolarWinds)                              │   │
│   │  - 依赖混淆 (Dependency Confusion)                      │   │
│   │  - 恶意包 (npm, PyPI 投毒)                              │   │
│   │  - 构建环境入侵                                         │   │
│   │  - 中间人攻击                                           │   │
│   └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│   历史事件：                                                     │
│   - 2020 SolarWinds: 影响 18,000+ 组织                         │
│   - 2021 Log4Shell: 影响数百万 Java 应用                       │
│   - 2022 npm event-stream: 加密货币钱包被盗                    │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

</details>

### 7.2 SBOM (Software Bill of Materials)

**SBOM** = 软件成分清单，列出软件包含的所有依赖：

```bash
# 生成 Linux 系统的包清单
rpm -qa > system-packages.txt

# 使用 Trivy 生成 SBOM
trivy image --format spdx-json -o sbom.json nginx:latest

# 使用 Syft 生成 SBOM
syft nginx:latest -o spdx-json > sbom.json
```

### 7.3 基础安全检查

```bash
# 1. 验证 RPM 包完整性
rpm -Va | grep -v "^\.\.\.\.\.\.\.\.T"  # 过滤时间戳变更

# 2. 检查安全更新
dnf check-update --security

# 3. 扫描已安装包的漏洞
trivy rootfs /

# 4. 验证 GPG 签名
rpm -K /path/to/package.rpm
```

### 7.4 深入学习路径

供应链安全的完整内容在 **LX11-CONTAINERS** 课程，包括：

- 容器镜像安全扫描
- 镜像签名与验证（Sigstore/cosign）
- 运行时安全（Falco, Tetragon）
- 准入控制（OPA Gatekeeper）
- SLSA 框架

---

## 反模式：常见错误

### 错误 1：直接在生产执行未测试的 playbook

```bash
# 危险！
ansible-playbook hardening.yaml -l production

# 后果：
# - 可能锁死 SSH 访问
# - 可能破坏业务功能
# - 无法回滚

# 正确做法：
# 1. 先在测试环境验证
ansible-playbook hardening.yaml -l test --check --diff

# 2. 测试环境执行
ansible-playbook hardening.yaml -l test

# 3. 灰度发布
ansible-playbook hardening.yaml -l production_canary

# 4. 验证后全量发布
ansible-playbook hardening.yaml -l production
```

### 错误 2：使用 shell 模块替代专用模块

```yaml
# 不推荐：非幂等，无验证
- name: Disable root login
  ansible.builtin.shell: |
    sed -i 's/PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config

# 推荐：幂等，有验证
- name: Disable root login
  ansible.builtin.lineinfile:
    path: /etc/ssh/sshd_config
    regexp: '^#?PermitRootLogin'
    line: 'PermitRootLogin no'
    validate: 'sshd -t -f %s'
```

### 错误 3：忽略 validate 参数

```yaml
# 危险！无验证
- name: Update SSH config
  ansible.builtin.lineinfile:
    path: /etc/ssh/sshd_config
    line: 'PermitRootLogin nope'  # 拼写错误！
  notify: restart sshd
# sshd 重启会失败，可能锁死访问

# 安全：有验证
- name: Update SSH config
  ansible.builtin.lineinfile:
    path: /etc/ssh/sshd_config
    line: 'PermitRootLogin no'
    validate: 'sshd -t -f %s'  # 部署前验证语法
  notify: restart sshd
# 语法错误会被捕获，任务失败但不会应用错误配置
```

### 错误 4：一键修复所有 CIS 项目

```bash
# 危险！盲目自动修复
oscap xccdf eval --remediate --profile cis ...

# 后果：
# - 可能禁用业务需要的服务
# - 可能修改关键配置
# - 无法预测影响

# 正确做法：
# 1. 先扫描，不修复
oscap xccdf eval --profile cis --report scan.html ...

# 2. 审查每个失败项
# 3. 评估业务影响
# 4. 逐项修复或记录例外
```

---

## 职场小贴士（Japan IT Context）

### 自动化加固相关术语

| 日语术语 | 含义 | 应用场景 |
|----------|------|----------|
| 自動化（じどうか） | 自动化 | Ansible 等工具 |
| 構成管理（こうせいかんり） | 配置管理 | Configuration as Code |
| 変更管理（へんこうかんり） | 变更管理 | Change Management |
| 承認フロー | 审批流程 | PR Review |
| テスト環境 | 测试环境 | Test Environment |
| 本番環境（ほんばんかんきょう） | 生产环境 | Production |
| 灰度リリース | 灰度发布 | Canary Deployment |
| ロールバック | 回滚 | Rollback |
| コンプライアンス | 合规 | Compliance |

### 日本企业自动化实践

**变更管理流程（典型）：**

```
1. 変更申請書 提出
   ↓
2. セキュリティチーム レビュー
   ↓
3. テスト環境 検証
   ↓
4. 承認者 承認
   ↓
5. 本番反映（計画メンテナンス窓内）
   ↓
6. 確認テスト
   ↓
7. 完了報告
```

**常见要求：**

| 要求 | 说明 |
|------|------|
| **双重确认** | 重要变更需要两人确认 |
| **事前通知** | 提前通知相关方 |
| **记录保持** | 保留变更记录供审计 |
| **回滚计划** | 必须有回滚方案 |
| **业务影响评估** | 评估对业务的影响 |

---

## 检查清单

完成本课后，你应该能够：

- [ ] 解释 IaC 安全原则（版本控制、代码审查、测试优先）
- [ ] 解释幂等性（Idempotency）的重要性
- [ ] 使用 `lineinfile` 模块配置 SSH 设置
- [ ] 使用 `blockinfile` 模块管理配置块
- [ ] 使用 `validate` 参数防止配置错误
- [ ] 配置 handler 链实现验证后重启
- [ ] 安装和使用社区 hardening roles（geerlingguy, devsec）
- [ ] 实施变更管理流程（测试 → 灰度 → 生产）
- [ ] 在 CI/CD 中集成安全检查（lint, scan）
- [ ] 使用 Jinja2 模板生成合规报告
- [ ] 解释 SBOM 和供应链安全基础概念

---

## 本课小结

| 概念 | 要点 | 记忆点 |
|------|------|--------|
| 幂等性 | 执行多次结果相同 | 自动化的核心要求 |
| lineinfile | 确保配置行存在 | 幂等的配置管理 |
| blockinfile | 管理配置块 | 用 marker 标记 |
| validate | 部署前验证 | **防止锁死！** |
| handler | 条件触发 | 只在变更时执行 |
| 变更管理 | 测试 → 灰度 → 生产 | 逐步推进 |
| SBOM | 软件成分清单 | 供应链安全基础 |

**核心原则：**

```
自动化 = 一致性 + 可追溯 + 可重复

手动加固：100 台服务器 × 人工操作 = 100 种配置
自动化加固：1 个 playbook × 100 台服务器 = 1 种配置
```

**安全自动化黄金法则：**

```
1. 版本控制一切
2. 测试环境先行
3. 验证后再应用
4. 保持回滚能力
5. 记录每次变更
```

---

## 延伸阅读

- [Ansible Security Automation](https://docs.ansible.com/ansible/latest/security/) - 官方安全自动化文档
- [geerlingguy.security](https://github.com/geerlingguy/ansible-role-security) - 流行的安全 role
- [DevSec Hardening](https://dev-sec.io/) - 社区安全基线
- [NIST Cybersecurity Framework](https://www.nist.gov/cyberframework) - 安全框架
- [SLSA Supply Chain Security](https://slsa.dev/) - 供应链安全框架
- 上一课：[10 - CIS Benchmarks 合规实战](../10-cis-benchmarks/) - 合规扫描与例外管理
- 下一课：[12 - Capstone: CIS 合规加固服务器](../12-capstone/) - 综合实战项目

---

## 系列导航

[上一课：10 - CIS Benchmarks](../10-cis-benchmarks/) | [系列首页](../) | [下一课：12 - Capstone ->](../12-capstone/)
