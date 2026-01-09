# 07 - auditd 审计系统 / Linux Audit System

> **目标**：掌握 Linux 审计系统，实现关键文件监控、用户行为追踪、事故调查证据收集  
> **前置**：完成 Lesson 01-06（安全原则、SSH、SELinux、Capabilities）  
> **时间**：3 小时  
> **实战场景**：幽灵配置变更追踪、黄金周异常调查、隐藏挖矿程序检测  

---

## 将学到的内容

1. 理解 Linux 审计系统架构（kernel audit, auditd, /var/log/audit）
2. 配置审计规则监控关键文件和操作
3. 使用 ausearch 和 aureport 分析审计日志
4. **核心技能**：通过 auid 追踪原始用户，即使 sudo 后
5. 检测 Living off the Land (LOTL) 攻击
6. 为安全事故生成调查报告（報告書）

---

## 先跑起来！（10 分钟）

> 在学习理论之前，先看看你的系统正在记录什么。  

```bash
# 检查 auditd 是否运行
systemctl status auditd

# 查看当前审计规则
sudo auditctl -l

# 查看最近的审计日志（最后 10 条）
sudo ausearch -m USER_LOGIN,USER_AUTH -ts recent --format text 2>/dev/null | tail -20

# 快速体验：监控一个文件的访问
sudo auditctl -w /etc/passwd -p war -k passwd_access
cat /etc/passwd > /dev/null
sudo ausearch -k passwd_access -ts recent --format text

# 清理测试规则
sudo auditctl -d -w /etc/passwd -p war -k passwd_access
```

**你刚刚：**

- 检查了审计系统是否运行
- 查看了当前有哪些审计规则
- 临时添加了一个文件监控规则
- 触发并查看了审计事件
- 删除了临时规则

**为什么这很重要？**

想象这个场景：周一早晨，你发现生产服务器的 `/etc/ssh/sshd_config` 被修改了，`PermitRootLogin` 从 `no` 变成了 `yes`。团队里没人承认改过。**谁改的？什么时候？用什么命令？**

没有 auditd，你只能猜测。有了 auditd，你可以精确追踪。

---

## Step 1 - 审计系统架构（15 分钟）

### 1.1 Linux 审计子系统概览

```
┌─────────────────────────────────────────────────────────────────┐
│                    Linux Audit Architecture                      │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│   用户空间                                                       │
│   ┌─────────────────────────────────────────────────────────┐   │
│   │                                                         │   │
│   │    auditctl          ausearch         aureport          │   │
│   │   (规则管理)        (日志搜索)       (报告生成)           │   │
│   │        │                ↑                ↑               │   │
│   │        │                │                │               │   │
│   │        ↓                │                │               │   │
│   │   ┌─────────────────────┴────────────────┴───────────┐  │   │
│   │   │                    auditd                         │  │   │
│   │   │              (审计守护进程)                        │  │   │
│   │   └─────────────────────┬────────────────────────────┘  │   │
│   │                         │                                │   │
│   │                         ↓                                │   │
│   │               /var/log/audit/audit.log                   │   │
│   │                   (审计日志文件)                          │   │
│   └─────────────────────────────────────────────────────────┘   │
│                              ↑                                   │
│   ───────────────────────────┼───────────────────────────────   │
│                              │                                   │
│   内核空间                    │ netlink socket                   │
│   ┌──────────────────────────┴──────────────────────────────┐   │
│   │              Kernel Audit Subsystem                      │   │
│   │                                                          │   │
│   │   系统调用 ─→ 规则匹配 ─→ 生成审计事件 ─→ 发送到用户空间   │   │
│   │                                                          │   │
│   │   监控点：                                                │   │
│   │   - 系统调用 (execve, open, chmod, ...)                  │   │
│   │   - 文件访问                                              │   │
│   │   - 用户认证                                              │   │
│   │   - 网络连接                                              │   │
│   └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

<details>
<summary>View ASCII source</summary>

```
┌─────────────────────────────────────────────────────────────────┐
│                    Linux Audit Architecture                      │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│   用户空间                                                       │
│   ┌─────────────────────────────────────────────────────────┐   │
│   │                                                         │   │
│   │    auditctl          ausearch         aureport          │   │
│   │   (规则管理)        (日志搜索)       (报告生成)           │   │
│   │        │                ↑                ↑               │   │
│   │        │                │                │               │   │
│   │        ↓                │                │               │   │
│   │   ┌─────────────────────┴────────────────┴───────────┐  │   │
│   │   │                    auditd                         │  │   │
│   │   │              (审计守护进程)                        │  │   │
│   │   └─────────────────────┬────────────────────────────┘  │   │
│   │                         │                                │   │
│   │                         ↓                                │   │
│   │               /var/log/audit/audit.log                   │   │
│   │                   (审计日志文件)                          │   │
│   └─────────────────────────────────────────────────────────┘   │
│                              ↑                                   │
│   ───────────────────────────┼───────────────────────────────   │
│                              │                                   │
│   内核空间                    │ netlink socket                   │
│   ┌──────────────────────────┴──────────────────────────────┐   │
│   │              Kernel Audit Subsystem                      │   │
│   │                                                          │   │
│   │   系统调用 ─→ 规则匹配 ─→ 生成审计事件 ─→ 发送到用户空间   │   │
│   │                                                          │   │
│   │   监控点：                                                │   │
│   │   - 系统调用 (execve, open, chmod, ...)                  │   │
│   │   - 文件访问                                              │   │
│   │   - 用户认证                                              │   │
│   │   - 网络连接                                              │   │
│   └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

</details>

### 1.2 核心组件

| 组件 | 作用 | 文件/命令 |
|------|------|-----------|
| Kernel Audit | 内核级事件捕获 | 内置于 Linux 内核 |
| auditd | 审计守护进程 | `/usr/sbin/auditd` |
| auditctl | 规则管理 | `auditctl -l`, `auditctl -w` |
| ausearch | 日志搜索 | `ausearch -k`, `ausearch -ts` |
| aureport | 报告生成 | `aureport --login`, `aureport --file` |
| audit.log | 审计日志 | `/var/log/audit/audit.log` |

### 1.3 审计日志位置

```bash
# 主日志文件
ls -la /var/log/audit/

# 典型输出：
# -rw------- 1 root root 8388608 Jan 04 10:00 audit.log
# -rw------- 1 root root 8388608 Jan 03 00:00 audit.log.1
# -rw------- 1 root root 8388608 Jan 02 00:00 audit.log.2

# 查看日志轮转配置
cat /etc/audit/auditd.conf | grep -E "log_file|max_log_file|num_logs"
```

### 1.4 auditd 配置文件

```bash
# 主配置文件
sudo cat /etc/audit/auditd.conf

# 关键配置项：
# log_file = /var/log/audit/audit.log    # 日志位置
# max_log_file = 8                        # 单个日志最大 MB
# num_logs = 5                            # 保留日志数量
# max_log_file_action = ROTATE            # 达到上限时轮转
# space_left_action = SYSLOG              # 磁盘空间不足时动作
```

---

## Step 2 - 审计规则基础（30 分钟）

### 2.1 规则类型

Linux 审计规则分为三类：

| 类型 | 说明 | 示例 |
|------|------|------|
| **文件系统规则 (-w)** | 监控文件/目录访问 | `-w /etc/passwd -p wa -k passwd_change` |
| **系统调用规则 (-a)** | 监控系统调用 | `-a always,exit -F arch=b64 -S execve -k commands` |
| **控制规则 (-D, -b)** | 审计系统配置 | `-D` (删除所有规则), `-b 8192` (缓冲区) |

### 2.2 文件系统规则 (-w)

**语法**：`-w <路径> -p <权限> -k <关键字>`

**权限标志**：

| 标志 | 含义 | 触发条件 |
|------|------|----------|
| `r` | read | 读取文件 |
| `w` | write | 写入文件 |
| `x` | execute | 执行文件 |
| `a` | attribute | 修改文件属性（权限、所有者等） |

**示例**：

```bash
# 监控 SSH 配置文件的写入和属性修改
sudo auditctl -w /etc/ssh/sshd_config -p wa -k ssh_config_change

# 监控整个 /etc/sudoers.d/ 目录
sudo auditctl -w /etc/sudoers.d/ -p wa -k sudo_config_change

# 监控敏感文件读取
sudo auditctl -w /etc/shadow -p r -k shadow_read
```

### 2.3 系统调用规则 (-a)

**语法**：`-a <list,action> -F <field=value> -S <syscall> -k <关键字>`

```bash
# 监控所有命令执行（64位系统）
sudo auditctl -a always,exit -F arch=b64 -S execve -k command_exec

# 监控特定用户的命令执行
sudo auditctl -a always,exit -F arch=b64 -S execve -F uid=1000 -k user1000_commands

# 监控文件删除操作
sudo auditctl -a always,exit -F arch=b64 -S unlink,unlinkat,rename,renameat -k file_delete
```

### 2.4 规则关键字 (-k)

**关键字（key）** 是搜索审计日志的标签，非常重要：

```bash
# 添加规则时指定 key
sudo auditctl -w /etc/ssh/sshd_config -p wa -k ssh_config

# 使用 key 搜索相关事件
sudo ausearch -k ssh_config

# 好的 key 命名规范：
# - 描述性：ssh_config_change, sudo_usage, file_delete
# - 一致性：同类规则使用相同前缀
# - 可搜索：避免过于通用的名称
```

### 2.5 查看和管理规则

```bash
# 查看当前规则
sudo auditctl -l

# 查看规则状态
sudo auditctl -s

# 删除单条规则
sudo auditctl -d -w /etc/passwd -p wa -k passwd_change

# 删除所有规则
sudo auditctl -D

# 从文件加载规则
sudo auditctl -R /etc/audit/rules.d/my-rules.rules
```

---

## Step 3 - 永久规则配置（30 分钟）

### 3.1 规则文件结构

```bash
# 规则目录
ls /etc/audit/rules.d/

# 规则加载顺序：按文件名字母序
# 10-base.rules      ← 基础配置（先加载）
# 20-ssh-config.rules
# 30-sudo.rules
# 40-lotl.rules
# 99-finalize.rules  ← 最后加载
```

### 3.2 10-base.rules - 基础规则

```bash
# 查看本课提供的基础规则
cat code/audit.rules.d/10-base.rules
```

```bash
# =============================================================================
# 10-base.rules - Audit Base Configuration
# =============================================================================
# Purpose: Basic audit system setup and critical system file monitoring
# Reference: CIS Benchmark, NIST SP 800-53
# =============================================================================

# -----------------------------------------------------------------------------
# Audit System Configuration
# -----------------------------------------------------------------------------

# Delete all existing rules (start fresh)
-D

# Set buffer size (increase for busy systems)
-b 8192

# Set failure mode (1=printk, 2=panic)
# Use 1 for production, 2 for high-security environments
-f 1

# -----------------------------------------------------------------------------
# Identity and Authentication Files
# -----------------------------------------------------------------------------

# User account files
-w /etc/passwd -p wa -k identity
-w /etc/shadow -p wa -k identity
-w /etc/group -p wa -k identity
-w /etc/gshadow -p wa -k identity

# PAM configuration
-w /etc/pam.d/ -p wa -k pam_config

# NSS configuration
-w /etc/nsswitch.conf -p wa -k identity

# -----------------------------------------------------------------------------
# Login and Session Tracking
# -----------------------------------------------------------------------------

# Login records
-w /var/log/lastlog -p wa -k logins
-w /var/run/faillock/ -p wa -k logins

# Session files
-w /var/log/wtmp -p wa -k session
-w /var/log/btmp -p wa -k session

# -----------------------------------------------------------------------------
# Privilege Escalation Monitoring
# -----------------------------------------------------------------------------

# sudo and su usage
-w /usr/bin/sudo -p x -k privilege_escalation
-w /usr/bin/su -p x -k privilege_escalation

# Privilege escalation attempts (setuid/setgid)
-a always,exit -F arch=b64 -S setuid,setgid,setreuid,setregid -k privilege_change
-a always,exit -F arch=b32 -S setuid,setgid,setreuid,setregid -k privilege_change
```

### 3.3 20-ssh-config.rules - SSH 监控

```bash
cat code/audit.rules.d/20-ssh-config.rules
```

```bash
# =============================================================================
# 20-ssh-config.rules - SSH Configuration Monitoring
# =============================================================================
# Purpose: Track all changes to SSH configuration
# Scenario: "Ghost Configuration Change" - unauthorized sshd_config modification
# =============================================================================

# SSH daemon configuration
-w /etc/ssh/sshd_config -p wa -k ssh_config
-w /etc/ssh/sshd_config.d/ -p wa -k ssh_config

# SSH client configuration (optional, can generate many events)
# -w /etc/ssh/ssh_config -p wa -k ssh_config

# SSH host keys
-w /etc/ssh/ssh_host_ed25519_key -p wa -k ssh_hostkeys
-w /etc/ssh/ssh_host_rsa_key -p wa -k ssh_hostkeys

# Authorized keys (per-user) - use with caution on systems with many users
-w /root/.ssh/authorized_keys -p wa -k ssh_authorized_keys
```

### 3.4 30-sudo.rules - sudo 监控

```bash
cat code/audit.rules.d/30-sudo.rules
```

```bash
# =============================================================================
# 30-sudo.rules - sudo and Administrative Actions Monitoring
# =============================================================================
# Purpose: Track all sudo configuration changes and usage
# =============================================================================

# sudo configuration files
-w /etc/sudoers -p wa -k sudo_config
-w /etc/sudoers.d/ -p wa -k sudo_config

# sudo command execution
-w /usr/bin/sudo -p x -k sudo_usage

# su command execution
-w /usr/bin/su -p x -k su_usage

# Administrative commands
-w /usr/sbin/useradd -p x -k user_admin
-w /usr/sbin/userdel -p x -k user_admin
-w /usr/sbin/usermod -p x -k user_admin
-w /usr/sbin/groupadd -p x -k user_admin
-w /usr/sbin/groupdel -p x -k user_admin
-w /usr/sbin/groupmod -p x -k user_admin
```

### 3.5 40-lotl.rules - Living off the Land 检测

```bash
cat code/audit.rules.d/40-lotl.rules
```

```bash
# =============================================================================
# 40-lotl.rules - Living off the Land (LOTL) Attack Detection
# =============================================================================
# Purpose: Detect abuse of legitimate system tools for malicious purposes
# Reference: MITRE ATT&CK, LOLBins
# =============================================================================

# -----------------------------------------------------------------------------
# Network Reconnaissance Tools
# -----------------------------------------------------------------------------

# Download tools (can be used to fetch malicious payloads)
-w /usr/bin/curl -p x -k lotl_download
-w /usr/bin/wget -p x -k lotl_download

# Network tools (can be used for data exfiltration or lateral movement)
-w /usr/bin/nc -p x -k lotl_network
-w /usr/bin/ncat -p x -k lotl_network
-w /usr/bin/netcat -p x -k lotl_network
-w /usr/bin/nmap -p x -k lotl_recon
-w /usr/bin/tcpdump -p x -k lotl_capture

# SSH/SCP (lateral movement)
-w /usr/bin/ssh -p x -k lotl_ssh
-w /usr/bin/scp -p x -k lotl_ssh
-w /usr/bin/sftp -p x -k lotl_ssh

# -----------------------------------------------------------------------------
# Scripting and Execution Tools
# -----------------------------------------------------------------------------

# Compilers (can compile malicious code)
-w /usr/bin/gcc -p x -k lotl_compile
-w /usr/bin/g++ -p x -k lotl_compile
-w /usr/bin/make -p x -k lotl_compile

# -----------------------------------------------------------------------------
# System Modification Tools
# -----------------------------------------------------------------------------

# Cron manipulation (persistence)
-w /usr/bin/crontab -p x -k lotl_cron
-w /var/spool/cron/ -p wa -k cron_modification
-w /etc/cron.d/ -p wa -k cron_modification
-w /etc/cron.daily/ -p wa -k cron_modification
-w /etc/cron.hourly/ -p wa -k cron_modification

# Systemd manipulation (persistence)
-w /etc/systemd/system/ -p wa -k systemd_modification
-w /usr/lib/systemd/system/ -p wa -k systemd_modification

# -----------------------------------------------------------------------------
# Encoding and Obfuscation Tools
# -----------------------------------------------------------------------------

# Base64 (often used to obfuscate malicious commands)
-w /usr/bin/base64 -p x -k lotl_obfuscation
```

### 3.6 应用规则

```bash
# 复制规则文件到系统目录
sudo cp code/audit.rules.d/*.rules /etc/audit/rules.d/

# 重新生成并加载规则
sudo augenrules --load

# 验证规则已加载
sudo auditctl -l | head -20

# 检查是否有错误
sudo auditctl -s
```

---

## Step 4 - 审计日志分析（40 分钟）

### 4.1 ausearch 基础用法

`ausearch` 是搜索审计日志的主要工具：

```bash
# 基础语法
ausearch [选项]

# 常用选项：
# -k <key>     按关键字搜索
# -ts <time>   起始时间
# -te <time>   结束时间
# -ua <uid>    按用户 ID
# -ui <uid>    按登录用户 ID
# -m <type>    按消息类型
# --format text/raw/interpret  输出格式
```

### 4.2 按关键字搜索

```bash
# 搜索 SSH 配置相关事件
sudo ausearch -k ssh_config

# 搜索 sudo 使用
sudo ausearch -k sudo_usage

# 搜索多个关键字
sudo ausearch -k ssh_config -k sudo_config
```

### 4.3 按时间范围搜索

```bash
# 最近的事件
sudo ausearch -ts recent

# 今天的事件
sudo ausearch -ts today

# 过去 1 小时
sudo ausearch -ts "1 hour ago"

# 指定时间范围
sudo ausearch -ts "01/04/2026 09:00:00" -te "01/04/2026 18:00:00"

# 特定日期
sudo ausearch -ts "yesterday" -te "today"
```

### 4.4 auid - 审计用户 ID（核心概念）

> **这是本课最重要的概念之一。**  

`auid`（Audit User ID）是用户**登录时**的原始 UID，即使 `sudo` 或 `su` 切换用户后也不会改变。

```
┌─────────────────────────────────────────────────────────────────┐
│                   auid vs uid/euid 对比                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│   用户 tanaka (uid=1000) 登录                                   │
│   ┌─────────────────────────────────────────────────────────┐   │
│   │ auid=1000                                               │   │
│   │ uid=1000                                                │   │
│   │ euid=1000                                               │   │
│   └─────────────────────────────────────────────────────────┘   │
│                         │                                       │
│                         │ sudo su - root                        │
│                         ▼                                       │
│   ┌─────────────────────────────────────────────────────────┐   │
│   │ auid=1000  ← 不变！仍然是 tanaka                         │   │
│   │ uid=0      ← 变成 root                                  │   │
│   │ euid=0     ← 变成 root                                  │   │
│   └─────────────────────────────────────────────────────────┘   │
│                         │                                       │
│                         │ 修改 /etc/ssh/sshd_config            │
│                         ▼                                       │
│   ┌─────────────────────────────────────────────────────────┐   │
│   │ 审计日志记录：                                           │   │
│   │ auid=1000 (tanaka) 修改了 sshd_config                   │   │
│   │                                                         │   │
│   │ 即使使用 root 权限操作，我们仍然知道是 tanaka 做的！     │   │
│   └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│   关键价值：追踪责任人，不被 sudo/su 欺骗                       │
└─────────────────────────────────────────────────────────────────┘
```

<details>
<summary>View ASCII source</summary>

```
┌─────────────────────────────────────────────────────────────────┐
│                   auid vs uid/euid 对比                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│   用户 tanaka (uid=1000) 登录                                   │
│   ┌─────────────────────────────────────────────────────────┐   │
│   │ auid=1000                                               │   │
│   │ uid=1000                                                │   │
│   │ euid=1000                                               │   │
│   └─────────────────────────────────────────────────────────┘   │
│                         │                                       │
│                         │ sudo su - root                        │
│                         ▼                                       │
│   ┌─────────────────────────────────────────────────────────┐   │
│   │ auid=1000  ← 不变！仍然是 tanaka                         │   │
│   │ uid=0      ← 变成 root                                  │   │
│   │ euid=0     ← 变成 root                                  │   │
│   └─────────────────────────────────────────────────────────┘   │
│                         │                                       │
│                         │ 修改 /etc/ssh/sshd_config            │
│                         ▼                                       │
│   ┌─────────────────────────────────────────────────────────┐   │
│   │ 审计日志记录：                                           │   │
│   │ auid=1000 (tanaka) 修改了 sshd_config                   │   │
│   │                                                         │   │
│   │ 即使使用 root 权限操作，我们仍然知道是 tanaka 做的！     │   │
│   └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│   关键价值：追踪责任人，不被 sudo/su 欺骗                       │
└─────────────────────────────────────────────────────────────────┘
```

</details>

**实际搜索**：

```bash
# 按 auid 搜索（谁登录）
sudo ausearch -ua 1000

# 按 uid 搜索（当前是谁）
sudo ausearch -ui 0   # root 权限执行的操作

# 查找特定用户的所有操作（即使 sudo 后）
sudo ausearch -ua 1000 --format text | grep -E "auid=|comm="
```

### 4.5 理解审计日志格式

```bash
# 查看原始日志
sudo ausearch -k ssh_config --raw

# 典型输出：
# type=SYSCALL msg=audit(1704369600.123:456): arch=c000003e syscall=257 success=yes exit=3 a0=ffffff9c a1=7ffdc8d5a020 a2=241 a3=1b6 items=2 ppid=12345 pid=12346 auid=1000 uid=0 gid=0 euid=0 suid=0 fsuid=0 egid=0 sgid=0 fsgid=0 tty=pts0 ses=1 comm="vim" exe="/usr/bin/vim" key="ssh_config"
```

**字段解释**：

| 字段 | 含义 | 示例值 |
|------|------|--------|
| `type=SYSCALL` | 事件类型 | SYSCALL, PATH, CWD |
| `msg=audit(timestamp:serial)` | 时间戳和序列号 | 1704369600.123:456 |
| `arch=c000003e` | 系统架构 | c000003e = x86_64 |
| `syscall=257` | 系统调用号 | 257 = openat |
| `auid=1000` | 审计用户 ID | **原始登录用户** |
| `uid=0` | 当前用户 ID | root (sudo 后) |
| `comm="vim"` | 命令名 | vim |
| `exe="/usr/bin/vim"` | 可执行文件路径 | /usr/bin/vim |
| `key="ssh_config"` | 审计规则关键字 | ssh_config |

### 4.6 使用 --format 输出

```bash
# 文本格式（人类可读）
sudo ausearch -k ssh_config --format text

# 解释格式（更详细）
sudo ausearch -k ssh_config --interpret

# 原始格式
sudo ausearch -k ssh_config --raw

# CSV 格式（适合导入 Excel）
sudo ausearch -k ssh_config --format csv
```

---

## Step 5 - 使用 aureport 生成报告（20 分钟）

### 5.1 aureport 概览

`aureport` 生成审计数据的汇总报告：

```bash
# 总体汇总
sudo aureport --summary

# 登录报告
sudo aureport --login

# 用户报告
sudo aureport --user

# 文件报告
sudo aureport --file

# 可执行文件报告
sudo aureport --executable

# 认证报告
sudo aureport --auth

# 失败事件
sudo aureport --failed
```

### 5.2 时间范围报告

```bash
# 今天的登录
sudo aureport --login --start today

# 特定时间范围
sudo aureport --login --start "01/01/2026 00:00:00" --end "01/04/2026 23:59:59"

# 过去一周的失败登录
sudo aureport --failed --start "1 week ago"
```

### 5.3 生成调查报告

```bash
# 综合报告示例
echo "=== 审计报告 ===" > /tmp/audit-report.txt
echo "生成时间: $(date)" >> /tmp/audit-report.txt
echo "" >> /tmp/audit-report.txt

echo "=== 登录汇总 ===" >> /tmp/audit-report.txt
sudo aureport --login --start today >> /tmp/audit-report.txt
echo "" >> /tmp/audit-report.txt

echo "=== 失败事件 ===" >> /tmp/audit-report.txt
sudo aureport --failed --start today >> /tmp/audit-report.txt
echo "" >> /tmp/audit-report.txt

echo "=== 权限提升 ===" >> /tmp/audit-report.txt
sudo ausearch -k privilege_escalation -ts today --format text >> /tmp/audit-report.txt

cat /tmp/audit-report.txt
```

---

## Step 6 - 实战场景演练（45 分钟）

### 6.1 场景 1：幽灵配置变更（Ghost Configuration Change）

> **场景描述**：周一早晨，你发现生产服务器的 SSH 配置被修改了，`PermitRootLogin` 从 `no` 变成了 `yes`。团队里没人承认改过。谁做的？  

**演练步骤**：

```bash
# 使用提供的演练脚本
cd /path/to/cloud-atlas/foundations/linux/security/07-auditd/code/ghost-change-scenario

# 1. 设置审计规则
sudo bash setup-audit.sh

# 2. 模拟配置变更（在另一个终端，用不同用户执行）
sudo bash simulate-change.sh

# 3. 调查变更
sudo bash investigate.sh
```

**手动调查步骤**：

```bash
# 1. 确认文件被修改
sudo stat /etc/ssh/sshd_config

# 2. 搜索 SSH 配置相关的审计事件
sudo ausearch -k ssh_config -ts "1 hour ago" --format text

# 3. 找到修改操作，识别 auid
# 即使操作者使用了 sudo，auid 仍然显示原始用户

# 4. 查看具体是谁
getent passwd <auid>

# 5. 查看该用户的所有操作（时间线重建）
sudo ausearch -ua <auid> -ts "1 hour ago" --format text
```

### 6.2 场景 2：黄金周异常（Golden Week Anomaly）

> **场景描述**：季度审计发现，某用户账户在国定假日（黄金周）凌晨 3 点访问了生产文件服务器。该用户声称当时在休假。是账户被盗还是遗忘的定时任务？  

**调查步骤**：

```bash
# 1. 确定时间范围（假设是 5 月 3 日凌晨 3 点）
sudo ausearch -ua 1000 -ts "05/03/2026 02:00:00" -te "05/03/2026 04:00:00" --format text

# 2. 查看登录来源
sudo ausearch -m USER_LOGIN -ts "05/03/2026 02:00:00" -te "05/03/2026 04:00:00" --interpret

# 3. 检查是否是 cron 任务
sudo ausearch -k cron_modification -ts "05/01/2026" --format text

# 4. 查看 wtmp 记录（登录历史）
last | grep "May  3"

# 5. 检查 SSH 登录来源 IP
sudo journalctl -u sshd --since "2026-05-03 02:00" --until "2026-05-03 04:00" | grep "Accepted"
```

**分析关键点**：

| 情况 | 特征 | 判断 |
|------|------|------|
| 正常 cron | 无 USER_LOGIN 事件 | 是定时任务 |
| SSH 登录（本人） | 登录 IP 是用户常用 IP | 可能遗忘 |
| SSH 登录（异常） | 登录 IP 是陌生地址 | 账户可能被盗 |
| 横向移动 | 从其他服务器 SSH 过来 | 需要调查源头 |

### 6.3 场景 3：隐藏挖矿程序（Hidden Cryptominer）

> **场景描述**：Zabbix 告警数据库备机 CPU 占用 99%。`top` 显示一个叫 `kworker` 的进程，但真正的 `kworker` 是内核线程，不应该占用这么多 CPU。怀疑是恶意挖矿程序。  

**调查步骤**：

```bash
# 1. 识别可疑进程
ps aux | grep kworker
# 注意：真正的 kworker 应该在 [] 中，如 [kworker/0:0]
# 如果没有 []，很可能是伪装的用户态程序

# 2. 检查进程的真实路径
ls -l /proc/<PID>/exe
# 真正的内核线程会显示 /proc/<PID>/exe -> (kernel)
# 伪装的程序会显示实际路径

# 3. 查找可执行文件的来源
sudo ausearch -f /path/to/suspicious/binary --format text

# 4. 检查持久化机制 - cron
sudo ausearch -k cron_modification -ts "1 week ago" --format text
crontab -l
ls -la /etc/cron.d/

# 5. 检查持久化机制 - systemd
sudo ausearch -k systemd_modification -ts "1 week ago" --format text
ls -la /etc/systemd/system/ | grep -v "^l"

# 6. 检查最近修改的文件
sudo find /etc -mtime -7 -type f | head -20

# 7. 重建时间线：谁下载的？
sudo ausearch -k lotl_download -ts "1 week ago" --format text | grep -E "curl|wget"
```

---

## Step 7 - 事故报告模板（15 分钟）

### 7.1 日本企业事故报告格式

在日本 IT 企业，安全事故需要正式的書面報告：

```bash
cat code/incident-report-template.md
```

### 7.2 报告模板

```markdown
# セキュリティインシデント報告書

## 基本情報

| 項目 | 内容 |
|------|------|
| 報告日 | 2026年01月04日 |
| 報告者 | __________ |
| インシデント発生日時 | 2026年01月03日 15:30 JST |
| 影響システム | production-bastion-01 |
| 深刻度 | 中 (設定変更、データ漏洩なし) |

## インシデント概要

### 何が起きたか
堡垒机 SSH 配置文件 `/etc/ssh/sshd_config` 被未经授权修改，
`PermitRootLogin` 设置从 `no` 变更为 `yes`。

### 発見経緯
週明け月曜日の定期セキュリティ監査で設定ファイルの差分チェック時に発覚。

## 調査結果

### 証拠収集 (auditd)

```bash
# 使用的搜索命令
sudo ausearch -k ssh_config -ts "01/01/2026 00:00:00" -te "01/03/2026 23:59:59" --format text
```

### 時系列

| 時刻 | 事象 | 証拠 |
|------|------|------|
| 01/03 15:28 | tanaka (uid=1000) SSH ログイン | ausearch -m USER_LOGIN |
| 01/03 15:30 | sudo su - root 実行 | ausearch -k sudo_usage |
| 01/03 15:31 | vim /etc/ssh/sshd_config 実行 | ausearch -k ssh_config |
| 01/03 15:32 | systemctl restart sshd 実行 | journalctl -u sshd |

### 責任者特定

- **auid**: 1000
- **ユーザー名**: tanaka
- **所属**: 開発チーム
- **備考**: 本人は「テスト環境と間違えた」と証言

## 影響範囲

- [x] 設定変更あり
- [ ] データ漏洩なし
- [ ] 不正アクセスの兆候なし
- [ ] サービス停止なし

## 対応状況

| 対応項目 | 状態 | 担当 | 完了日 |
|----------|------|------|--------|
| 設定復旧 | 完了 | ops-team | 01/04 09:00 |
| 証拠保全 | 完了 | sec-team | 01/04 09:30 |
| 本人ヒアリング | 完了 | manager | 01/04 10:00 |
| 再発防止策検討 | 進行中 | sec-team | - |

## 再発防止策

### 技術的対策
1. sshd_config の変更に対するアラート設定
2. 本番環境変更の承認フロー導入
3. 環境別プロンプト色分け（本番=赤）

### 運用的対策
1. 変更管理プロセスの再教育
2. 本番アクセス権限の見直し

## 承認

| 役職 | 氏名 | 日付 | 署名 |
|------|------|------|------|
| セキュリティ担当 | | | |
| 部門長 | | | |
| CISO | | | |
```

---

## 反模式：常见错误

### 错误 1：禁用 auditd

```bash
# 危险！禁用审计
sudo systemctl stop auditd
sudo systemctl disable auditd

# 后果：
# - 无法追踪任何操作
# - 安全事故无法调查
# - 违反合规要求

# 如果觉得日志太多，正确做法是优化规则，不是禁用
```

### 错误 2：规则过于宽泛

```bash
# 危险！监控所有 execve（会产生海量日志）
-a always,exit -F arch=b64 -S execve -k everything

# 后果：
# - 日志暴涨
# - 性能下降
# - 重要事件被淹没

# 正确做法：针对性监控
-w /etc/ssh/sshd_config -p wa -k ssh_config  # 只监控关键文件
```

### 错误 3：日志保留时间太短

```bash
# 危险的配置
# /etc/audit/auditd.conf
max_log_file = 5      # 只有 5MB
num_logs = 3          # 只保留 3 个文件
# 总共只有 15MB 日志

# 后果：
# - 调查时发现日志已被轮转覆盖
# - 证据丢失

# 合规要求通常需要保留 90+ 天日志
```

### 错误 4：忽略 auid

```bash
# 只按 uid 搜索
sudo ausearch -ui 0   # 只找 root 操作

# 问题：无法知道是谁 sudo 成 root 的

# 正确做法：使用 auid 追踪原始用户
sudo ausearch -ua 1000   # 找 tanaka 的所有操作，包括 sudo 后的
```

---

## 职场小贴士（Japan IT Context）

### 审计相关术语

| 日语术语 | 含义 | 应用场景 |
|----------|------|----------|
| 監査ログ（かんさログ） | 审计日志 | auditd 日志 |
| 証跡（しょうせき） | 证据/审计轨迹 | 安全调查证据 |
| 報告書（ほうこくしょ） | 报告书 | 事故报告文档 |
| 不正アクセス | 非法访问 | 安全事故类型 |
| 変更管理 | 变更管理 | 配置变更流程 |
| コンプライアンス | 合规 | ISMS, PCI DSS |
| セキュリティ監査 | 安全审计 | 定期检查 |

### 日本企业审计要求

1. **ISMS/ISO 27001**
   - 需要保留访问日志
   - 需要定期审查日志
   - 需要事故响应流程

2. **PCI DSS（金融）**
   - 日志保留 1 年以上
   - 实时日志监控
   - 审计系统完整性

3. **上场企业 SOX 合规**
   - 访问控制审计
   - 变更管理证据
   - 权限分离

### 日本企业常见做法

```bash
# 1. 集中日志管理
# auditd → rsyslog → 中央日志服务器（Splunk, Elasticsearch）

# 2. 日志保留期间
# 通常 1 年以上，金融行业可能要求 5-7 年

# 3. 定期审计报告
# 每月生成 aureport 汇总，由安全团队审查

# 4. 告警设置
# 关键事件（sudo 到 root，配置变更）实时告警
```

---

## 检查清单

完成本课后，你应该能够：

- [ ] 解释 Linux 审计系统架构（内核审计 → auditd → audit.log）
- [ ] 使用 `auditctl -w` 添加文件监控规则
- [ ] 使用 `auditctl -a` 添加系统调用监控规则
- [ ] 将规则写入 `/etc/audit/rules.d/` 实现持久化
- [ ] 使用 `ausearch -k` 按关键字搜索日志
- [ ] 使用 `ausearch -ts` 按时间范围搜索
- [ ] **解释 auid 与 uid 的区别，追踪 sudo 后的原始用户**
- [ ] 使用 `aureport` 生成登录、文件、失败事件报告
- [ ] 配置 LOTL 攻击检测规则
- [ ] 根据审计日志生成日本企业格式的事故报告

---

## 本课小结

| 概念 | 命令/配置 | 记忆点 |
|------|-----------|--------|
| 查看规则 | `auditctl -l` | 当前审计规则列表 |
| 添加文件监控 | `auditctl -w /path -p wa -k key` | -p: r/w/x/a |
| 删除规则 | `auditctl -d` 或 `-D` | -D 删除全部 |
| 永久规则 | `/etc/audit/rules.d/*.rules` | 按文件名排序加载 |
| 加载规则 | `augenrules --load` | 重新加载所有规则 |
| 按 key 搜索 | `ausearch -k key` | 规则关键字很重要 |
| 按时间搜索 | `ausearch -ts "1 hour ago"` | 支持自然语言 |
| 按原始用户搜索 | `ausearch -ua <auid>` | **auid 不变** |
| 生成报告 | `aureport --login` | 汇总统计 |

**核心概念**：

```
auid（审计用户 ID）= 登录时的原始 UID
即使 sudo/su 后，auid 仍然不变
这是追踪"谁做了什么"的关键
```

**LOTL 检测关键点**：

```
Living off the Land = 滥用合法工具
监控 curl, wget, nc, base64 等工具的执行
这些工具本身合法，但被恶意使用时是攻击信号
```

---

## 延伸阅读

- [Linux Audit Documentation](https://github.com/linux-audit/audit-documentation/wiki) - 官方文档
- [CIS Benchmark - Audit Configuration](https://www.cisecurity.org/benchmark) - 合规基线
- [MITRE ATT&CK - Defense Evasion](https://attack.mitre.org/tactics/TA0005/) - LOTL 攻击技术
- [NIST SP 800-53 - Audit and Accountability](https://csrc.nist.gov/publications/detail/sp/800-53/rev-5/final) - 审计合规标准
- 上一课：[06 - Linux Capabilities](../06-capabilities/) - 精细权限控制
- 下一课：[08 - nftables 深入](../08-nftables/) - 现代防火墙

---

## 系列导航

[上一课：06 - Linux Capabilities](../06-capabilities/) | [系列首页](../) | [下一课：08 - nftables 深入 ->](../08-nftables/)
