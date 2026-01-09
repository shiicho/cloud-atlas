# 09 - PAM 高级配置 / PAM Advanced Configuration

> **目标**：掌握 PAM 模块堆栈、账户锁定和密码策略配置  
> **前置**：完成 Lesson 02（SSH 加固）、Lesson 08（nftables）  
> **时间**：2 小时  
> **警告**：PAM 配置错误可能导致无法登录！始终保留备用 root 会话  

---

## 将学到的内容

1. 理解 PAM 模块堆栈工作原理
2. 配置账户锁定策略（pam_faillock，替代已废弃的 pam_tally2）
3. 配置密码复杂度要求（pam_pwquality）
4. 安全测试 PAM 变更
5. 常见 PAM 故障排查

---

## 先跑起来！（5 分钟）

> 在学习 PAM 理论之前，先看看系统当前的 PAM 配置状态。  

```bash
# 1. 查看系统登录相关的 PAM 配置
cat /etc/pam.d/system-auth 2>/dev/null || cat /etc/pam.d/common-auth 2>/dev/null | head -20

# 2. 检查是否配置了账户锁定（pam_faillock 或旧版 pam_tally2）
grep -r "pam_faillock\|pam_tally2" /etc/pam.d/ 2>/dev/null

# 3. 查看当前密码策略
cat /etc/security/pwquality.conf 2>/dev/null | grep -v "^#" | grep -v "^$"

# 4. 检查账户锁定状态
faillock --user root 2>/dev/null || echo "faillock 未配置或未安装"

# 5. 列出 /etc/pam.d/ 下的配置文件
ls -la /etc/pam.d/ | head -15
```

**你刚刚检查了：**

- 系统当前使用哪些 PAM 模块？
- 是否配置了登录失败锁定？（防暴力破解）
- 密码复杂度要求是什么？
- 哪些服务使用 PAM？

**如果 `faillock` 返回 "未配置"，你的服务器可能容易受到暴力破解攻击。**

现在让我们理解 PAM 的工作原理，然后正确配置它。

---

## Step 1 - PAM 架构详解（20 分钟）

### 1.1 什么是 PAM？

PAM（Pluggable Authentication Modules）是 Linux 认证框架，允许应用程序使用可插拔的认证机制。

```
传统方式（无 PAM）：
┌───────────┐     直接验证      ┌───────────┐
│   sshd    │ ─────────────────▶│ /etc/shadow│
└───────────┘                   └───────────┘
     问题：每个应用都要自己实现认证逻辑

PAM 方式：
┌───────────┐     ┌─────────────┐     ┌───────────────┐
│   sshd    │────▶│     PAM     │────▶│ pam_unix.so   │──▶ /etc/shadow
└───────────┘     │  Framework  │     │ pam_faillock  │──▶ 锁定计数
     │            └─────────────┘     │ pam_pwquality │──▶ 密码检查
     │                  ▲             │ pam_ldap.so   │──▶ LDAP 服务器
┌───────────┐           │             └───────────────┘
│   login   │───────────┘
└───────────┘
     好处：集中管理认证策略
```

<details>
<summary>View ASCII source</summary>

```
传统方式（无 PAM）：
┌───────────┐     直接验证      ┌───────────┐
│   sshd    │ ─────────────────▶│ /etc/shadow│
└───────────┘                   └───────────┘
     问题：每个应用都要自己实现认证逻辑

PAM 方式：
┌───────────┐     ┌─────────────┐     ┌───────────────┐
│   sshd    │────▶│     PAM     │────▶│ pam_unix.so   │──▶ /etc/shadow
└───────────┘     │  Framework  │     │ pam_faillock  │──▶ 锁定计数
     │            └─────────────┘     │ pam_pwquality │──▶ 密码检查
     │                  ▲             │ pam_ldap.so   │──▶ LDAP 服务器
┌───────────┐           │             └───────────────┘
│   login   │───────────┘
└───────────┘
     好处：集中管理认证策略
```

</details>

### 1.2 PAM 四种模块类型

PAM 将认证流程分为四个独立的阶段：

| 类型 | 英文 | 作用 | 示例 |
|------|------|------|------|
| **auth** | Authentication | 验证用户身份 | 检查密码、密钥、指纹 |
| **account** | Account Management | 检查账户状态 | 账户是否过期、锁定 |
| **password** | Password Management | 修改密码时调用 | 检查密码强度、更新密码 |
| **session** | Session Management | 会话开始/结束时调用 | 设置环境变量、记录日志 |

```
用户登录流程：

   用户输入密码
         │
         ▼
   ┌─────────────┐
   │    auth     │ ─── "密码正确吗？"
   └──────┬──────┘
         │ 通过
         ▼
   ┌─────────────┐
   │   account   │ ─── "账户可以登录吗？（未过期、未锁定）"
   └──────┬──────┘
         │ 通过
         ▼
   ┌─────────────┐
   │   session   │ ─── "设置用户环境、记录登录日志"
   └──────┬──────┘
         │
         ▼
      登录成功！
```

<details>
<summary>View ASCII source</summary>

```
用户登录流程：

   用户输入密码
         │
         ▼
   ┌─────────────┐
   │    auth     │ ─── "密码正确吗？"
   └──────┬──────┘
         │ 通过
         ▼
   ┌─────────────┐
   │   account   │ ─── "账户可以登录吗？（未过期、未锁定）"
   └──────┬──────┘
         │ 通过
         ▼
   ┌─────────────┐
   │   session   │ ─── "设置用户环境、记录登录日志"
   └──────┬──────┘
         │
         ▼
      登录成功！
```

</details>

### 1.3 控制标志（Control Flags）

控制标志决定模块失败时如何处理：

| 标志 | 失败时行为 | 记忆法 |
|------|------------|--------|
| **required** | 标记失败，继续执行后续模块 | "必须成功，但不急着告诉你" |
| **requisite** | 立即返回失败，不执行后续 | "立即失败" |
| **sufficient** | 成功则立即返回，跳过后续 | "足够了，通过！" |
| **optional** | 结果被忽略（除非是唯一模块） | "可选的" |

```
控制流程示例：

auth required     pam_env.so          # 必须成功，继续
auth required     pam_faillock.so     # 必须成功，继续（检查锁定）
auth sufficient   pam_unix.so         # 密码正确？→ 成功，跳过后续
auth sufficient   pam_sss.so          # LDAP 认证？→ 成功，跳过后续
auth required     pam_deny.so         # 最后保险：拒绝一切

执行顺序：env → faillock → unix（成功则结束）→ sss → deny
```

### 1.4 配置文件位置

```bash
# 主配置目录
/etc/pam.d/
├── system-auth      # RHEL: 系统认证（被其他文件 include）
├── password-auth    # RHEL: 密码认证
├── common-auth      # Debian: 通用认证
├── common-password  # Debian: 密码相关
├── sshd             # SSH 服务专用
├── login            # 本地登录
├── sudo             # sudo 命令
└── su               # su 命令

# 策略文件目录
/etc/security/
├── pwquality.conf   # 密码复杂度策略
├── faillock.conf    # 账户锁定策略（新版）
├── limits.conf      # 资源限制
├── access.conf      # 访问控制
└── time.conf        # 时间限制
```

---

## Step 2 - 账户锁定配置：pam_faillock（30 分钟）

### 2.1 pam_faillock vs pam_tally2

> **重要**：pam_tally2 在 RHEL 8 / Fedora 28 后已废弃，请使用 pam_faillock。  

| 特性 | pam_tally2（旧） | pam_faillock（新） |
|------|------------------|-------------------|
| 状态 | **已废弃** | 推荐 |
| 命令 | `pam_tally2` | `faillock` |
| 配置 | PAM 文件中 | /etc/security/faillock.conf |
| 日志 | /var/log/tallylog | /var/run/faillock/* |

### 2.2 查看当前状态

```bash
# 检查 faillock 是否已配置
grep pam_faillock /etc/pam.d/system-auth 2>/dev/null || \
grep pam_faillock /etc/pam.d/common-auth 2>/dev/null

# 查看用户锁定状态
sudo faillock --user testuser

# 查看所有用户的锁定状态
sudo faillock

# 输出示例：
# testuser:
# When                Type  Source                              Valid
# 2025-01-04 10:23:15 RHOST 192.168.1.100                           V
# 2025-01-04 10:23:18 RHOST 192.168.1.100                           V
# 2025-01-04 10:23:21 RHOST 192.168.1.100                           V
```

### 2.3 配置 pam_faillock

#### 方法 1：使用 faillock.conf（推荐，RHEL 8.2+）

```bash
# 查看默认配置
cat /etc/security/faillock.conf

# 创建自定义配置
sudo tee /etc/security/faillock.conf << 'EOF'
# =============================================================================
# Faillock Configuration
# 5 次失败后锁定账户 10 分钟
# Reference: CIS Benchmark 5.4.2
# =============================================================================

# 最大失败次数（超过此数锁定）
deny = 5

# 锁定时间（秒）- 10 分钟
unlock_time = 600

# 失败计数窗口（秒）- 15 分钟内的失败才计数
fail_interval = 900

# 是否锁定 root（生产环境建议 yes，但需要有其他恢复方式）
# even_deny_root
# root_unlock_time = 60

# 审计失败尝试
audit

# 静默模式（不提示剩余尝试次数，防止信息泄露）
silent

# 记录目录
dir = /var/run/faillock

EOF
```

#### 方法 2：直接在 PAM 文件配置（旧版本）

如果系统不支持 faillock.conf，需要直接修改 PAM 文件：

```bash
# RHEL/CentOS: 备份并编辑 system-auth
sudo cp /etc/pam.d/system-auth /etc/pam.d/system-auth.bak.$(date +%Y%m%d)

# 在 auth 部分添加（pam_unix 之前）:
auth        required      pam_faillock.so preauth silent audit deny=5 unlock_time=600
auth        sufficient    pam_unix.so ...
auth        [default=die] pam_faillock.so authfail audit deny=5 unlock_time=600

# 在 account 部分添加:
account     required      pam_faillock.so
```

### 2.4 测试账户锁定

> **警告**：在测试环境进行，并确保有备用 root 会话！  

```bash
# 创建测试用户
sudo useradd -m testlockuser
sudo passwd testlockuser  # 设置密码

# 故意输错密码 5 次
ssh testlockuser@localhost  # 输入错误密码 5 次

# 检查锁定状态
sudo faillock --user testlockuser

# 输出示例：
# testlockuser:
# When                Type  Source                              Valid
# 2025-01-04 10:30:01 RHOST 127.0.0.1                               V
# 2025-01-04 10:30:03 RHOST 127.0.0.1                               V
# 2025-01-04 10:30:05 RHOST 127.0.0.1                               V
# 2025-01-04 10:30:07 RHOST 127.0.0.1                               V
# 2025-01-04 10:30:09 RHOST 127.0.0.1                               V

# 再次尝试登录（即使密码正确也会被拒绝）
ssh testlockuser@localhost
# 输出：Permission denied (publickey,gssapi-keyex,gssapi-with-mic,password).
```

### 2.5 解锁账户

```bash
# 解锁特定用户
sudo faillock --user testlockuser --reset

# 验证解锁
sudo faillock --user testlockuser
# 输出应为空

# 现在可以正常登录了
ssh testlockuser@localhost
```

### 2.6 实战：配置脚本

使用我们提供的脚本快速配置：

```bash
# 查看脚本内容
cat code/pam-faillock-demo/setup-faillock.sh

# 执行配置（需要 root）
sudo bash code/pam-faillock-demo/setup-faillock.sh
```

---

## Step 3 - 密码策略配置：pam_pwquality（20 分钟）

### 3.1 pam_pwquality 简介

pam_pwquality 用于在用户更改密码时检查密码强度。

```
密码更改流程：

   用户执行 passwd
         │
         ▼
   ┌─────────────────┐
   │  pam_pwquality  │ ─── "密码够复杂吗？"
   └────────┬────────┘
            │ 检查
            ▼
   ┌───────────────────────────────────────────────────┐
   │ - 长度足够？（minlen）                            │
   │ - 包含数字？（dcredit）                           │
   │ - 包含大写？（ucredit）                           │
   │ - 包含特殊字符？（ocredit）                       │
   │ - 不是字典词？（dictcheck）                       │
   │ - 不包含用户名？（usercheck）                     │
   └───────────────────────────────────────────────────┘
            │
            ▼
      通过 → 允许更改密码
      失败 → 拒绝，要求重新输入
```

<details>
<summary>View ASCII source</summary>

```
密码更改流程：

   用户执行 passwd
         │
         ▼
   ┌─────────────────┐
   │  pam_pwquality  │ ─── "密码够复杂吗？"
   └────────┬────────┘
            │ 检查
            ▼
   ┌───────────────────────────────────────────────────┐
   │ - 长度足够？（minlen）                            │
   │ - 包含数字？（dcredit）                           │
   │ - 包含大写？（ucredit）                           │
   │ - 包含特殊字符？（ocredit）                       │
   │ - 不是字典词？（dictcheck）                       │
   │ - 不包含用户名？（usercheck）                     │
   └───────────────────────────────────────────────────┘
            │
            ▼
      通过 → 允许更改密码
      失败 → 拒绝，要求重新输入
```

</details>

### 3.2 配置参数详解

| 参数 | 含义 | CIS 推荐 | 示例 |
|------|------|----------|------|
| minlen | 最小长度 | 14 | minlen = 14 |
| dcredit | 数字要求（负数=必须包含N个） | -1 | dcredit = -1 |
| ucredit | 大写字母要求 | -1 | ucredit = -1 |
| lcredit | 小写字母要求 | -1 | lcredit = -1 |
| ocredit | 特殊字符要求 | -1 | ocredit = -1 |
| minclass | 最少字符类别数 | 4 | minclass = 4 |
| dictcheck | 字典检查 | 1 | dictcheck = 1 |
| usercheck | 用户名检查 | 1 | usercheck = 1 |
| maxrepeat | 最大连续重复字符 | 3 | maxrepeat = 3 |
| maxclassrepeat | 同类字符最大连续 | 4 | maxclassrepeat = 4 |
| retry | 重试次数 | 3 | retry = 3 |

> **注意**：credit 参数使用负数表示"必须包含"，正数表示"加分项"。  

### 3.3 配置密码策略

```bash
# 备份原配置
sudo cp /etc/security/pwquality.conf /etc/security/pwquality.conf.bak.$(date +%Y%m%d)

# 创建 CIS 合规配置
sudo tee /etc/security/pwquality.conf << 'EOF'
# =============================================================================
# Password Quality Configuration
# Reference: CIS Benchmark 5.4.1, NIST SP 800-63B
# =============================================================================

# 最小密码长度（CIS 推荐 14）
minlen = 14

# 字符类别要求（负数 = 必须包含的数量）
# 必须包含至少 1 个数字
dcredit = -1

# 必须包含至少 1 个大写字母
ucredit = -1

# 必须包含至少 1 个小写字母
lcredit = -1

# 必须包含至少 1 个特殊字符
ocredit = -1

# 最少需要的字符类别数（数字、大写、小写、特殊）
minclass = 4

# 字典检查：禁止使用常见密码
dictcheck = 1

# 用户名检查：禁止密码包含用户名
usercheck = 1

# 几何序列检查：禁止 "1234" 等
gecoscheck = 1

# 最大连续相同字符数
maxrepeat = 3

# 同类字符（如全数字）最大连续数
maxclassrepeat = 4

# 新密码与旧密码必须不同的字符数
difok = 8

# 允许的重试次数
retry = 3

# 是否强制 root 也遵守规则
enforce_for_root

# 拒绝空密码
# (由 pam_unix 的 nullok 选项控制)

EOF
```

### 3.4 验证密码策略

```bash
# 测试密码强度检查
pwscore "Weak123"
# 输出：Password quality check failed: ...

pwscore "MyStr0ng!Pass#2025"
# 输出：84

# 尝试更改密码（会被策略拦截弱密码）
# 创建测试用户
sudo useradd -m pwtest
sudo passwd pwtest  # 尝试设置弱密码如 "password123"

# 输出示例：
# BAD PASSWORD: The password fails the dictionary check - it is based on a dictionary word
# BAD PASSWORD: The password is shorter than 14 characters
```

### 3.5 示例配置文件

使用我们提供的配置：

```bash
# 查看示例配置
cat code/pwquality.conf

# 应用配置
sudo cp code/pwquality.conf /etc/security/pwquality.conf
```

---

## Step 4 - 常用 PAM 模块概览（15 分钟）

### 4.1 核心模块

| 模块 | 用途 | 配置文件 |
|------|------|----------|
| pam_unix | 标准 Linux 认证（/etc/passwd, /etc/shadow） | - |
| pam_faillock | 登录失败锁定 | /etc/security/faillock.conf |
| pam_pwquality | 密码强度检查 | /etc/security/pwquality.conf |
| pam_limits | 资源限制（ulimit） | /etc/security/limits.conf |

### 4.2 访问控制模块

| 模块 | 用途 | 配置文件 |
|------|------|----------|
| pam_access | 基于用户/主机的访问控制 | /etc/security/access.conf |
| pam_time | 基于时间的访问控制 | /etc/security/time.conf |
| pam_listfile | 基于文件列表的访问控制 | 自定义 |

#### pam_access 示例

```bash
# /etc/security/access.conf 示例
# 拒绝非管理员组从外部 IP 登录
-:ALL EXCEPT wheel:ALL EXCEPT LOCAL 192.168.0.0/16

# 允许 sysadmin 组从任何地方登录
+:sysadmin:ALL

# 拒绝其他所有用户
-:ALL:ALL
```

#### pam_time 示例

```bash
# /etc/security/time.conf 示例
# 只允许 developers 组在工作时间登录
sshd;*;developers;Wk0900-1800
```

### 4.3 企业认证模块

> **注意**：企业 LDAP/AD 集成是高级话题，这里仅做概览。  

| 模块 | 用途 | 常见场景 |
|------|------|----------|
| pam_ldap | 直接 LDAP 认证 | 传统 LDAP 环境 |
| pam_sss | SSSD 认证（推荐） | AD/LDAP/FreeIPA 集成 |
| pam_krb5 | Kerberos 认证 | AD 环境 |

```
企业环境典型 PAM 栈：

auth  required     pam_env.so
auth  required     pam_faillock.so preauth
auth  sufficient   pam_sss.so           ← SSSD 处理 AD/LDAP
auth  sufficient   pam_unix.so          ← 本地用户回退
auth  required     pam_faillock.so authfail
auth  required     pam_deny.so
```

<details>
<summary>View ASCII source</summary>

```
企业环境典型 PAM 栈：

auth  required     pam_env.so
auth  required     pam_faillock.so preauth
auth  sufficient   pam_sss.so           ← SSSD 处理 AD/LDAP
auth  sufficient   pam_unix.so          ← 本地用户回退
auth  required     pam_faillock.so authfail
auth  required     pam_deny.so
```

</details>

### 4.4 pam_limits 快速示例

```bash
# /etc/security/limits.conf
# 限制 webserver 用户的资源
webserver        soft    nofile          4096
webserver        hard    nofile          65536
webserver        soft    nproc           256
webserver        hard    nproc           512

# 限制所有用户
*                soft    core            0        # 禁用 core dump
*                hard    maxlogins       10       # 最大登录数
```

---

## Step 5 - PAM 调试与故障排查（20 分钟）

### 5.1 常见错误及解决

| 症状 | 可能原因 | 诊断命令 | 解决方案 |
|------|----------|----------|----------|
| 无法登录（密码正确） | PAM 配置语法错误 | `journalctl -u sshd` | 恢复备份 |
| 密码正确但被拒绝 | 账户被 faillock 锁定 | `faillock --user xxx` | `faillock --reset` |
| sudo 不工作 | /etc/pam.d/sudo 错误 | `sudo -l` 输出 | 使用 root 修复 |
| 密码修改被拒绝 | pwquality 策略过严 | 查看错误提示 | 调整 pwquality.conf |

### 5.2 查看认证日志

```bash
# RHEL/CentOS: 认证日志
sudo tail -f /var/log/secure

# Debian/Ubuntu: 认证日志
sudo tail -f /var/log/auth.log

# 使用 journalctl 查看 SSH 认证
sudo journalctl -u sshd -f

# 查看 PAM 相关日志
sudo journalctl | grep -i pam

# 查看登录失败
sudo journalctl -t sshd --since "1 hour ago" | grep -i "failed\|denied"
```

### 5.3 启用 PAM 调试

> **警告**：调试模式会记录敏感信息，只在排错时临时启用！  

```bash
# 在 PAM 配置中添加 debug 参数
# /etc/pam.d/sshd
auth    required    pam_faillock.so preauth silent audit deny=5 debug

# 或在 /etc/security/faillock.conf 添加
# debug

# 查看调试输出
sudo journalctl -u sshd -f
```

### 5.4 PAM 配置语法验证

不幸的是，PAM 没有像 `sshd -t` 那样的验证工具。但可以：

```bash
# 1. 检查文件语法（基本检查）
for f in /etc/pam.d/*; do
    echo "=== Checking $f ==="
    # 检查是否引用不存在的模块
    grep -E "^(auth|account|password|session)" "$f" | while read line; do
        module=$(echo "$line" | awk '{print $3}' | sed 's/\.so.*/\.so/')
        if ! find /lib64/security /lib/security -name "$module" 2>/dev/null | grep -q .; then
            echo "WARNING: Module $module not found"
        fi
    done
done

# 2. 测试模块是否存在
ls /lib64/security/ 2>/dev/null || ls /lib/x86_64-linux-gnu/security/

# 3. 使用 pamtester（如果可用）
# sudo dnf install pamtester
pamtester sshd testuser authenticate
```

### 5.5 常见 PAM 错误消息

| 错误消息 | 含义 | 解决方案 |
|----------|------|----------|
| `Module is unknown` | 模块文件不存在 | 安装对应包 |
| `Authentication failure` | 认证失败 | 检查密码/密钥/锁定状态 |
| `Permission denied` | 访问被拒绝 | 检查 pam_access, faillock |
| `account expired` | 账户过期 | `chage -l user` 检查 |
| `password has expired` | 密码过期 | `chage -d 0 user` 或更新密码 |

---

## Step 6 - 安全测试 PAM 变更（15 分钟）

> **这是本课最重要的技能：安全地测试 PAM 配置变更。**  

### 6.1 黄金法则

```
┌─────────────────────────────────────────────────────────────────┐
│                     PAM 变更安全法则                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1. 永远保持一个 root 会话打开                                  │
│     - 新开终端测试，不要关闭旧终端                              │
│     - 确保有控制台访问权限                                      │
│                                                                 │
│  2. 修改前备份                                                  │
│     cp /etc/pam.d/system-auth /etc/pam.d/system-auth.bak       │
│                                                                 │
│  3. 在测试环境先验证                                            │
│     - 使用 VM 或容器测试                                        │
│     - 不要直接在生产环境测试                                    │
│                                                                 │
│  4. 准备回滚计划                                                │
│     - 知道如何恢复备份                                          │
│     - 知道如何进入救援模式                                      │
│                                                                 │
│  5. 小步修改，逐一测试                                          │
│     - 不要一次改很多东西                                        │
│     - 每改一项就测试                                            │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

<details>
<summary>View ASCII source</summary>

```
┌─────────────────────────────────────────────────────────────────┐
│                     PAM 变更安全法则                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1. 永远保持一个 root 会话打开                                  │
│     - 新开终端测试，不要关闭旧终端                              │
│     - 确保有控制台访问权限                                      │
│                                                                 │
│  2. 修改前备份                                                  │
│     cp /etc/pam.d/system-auth /etc/pam.d/system-auth.bak       │
│                                                                 │
│  3. 在测试环境先验证                                            │
│     - 使用 VM 或容器测试                                        │
│     - 不要直接在生产环境测试                                    │
│                                                                 │
│  4. 准备回滚计划                                                │
│     - 知道如何恢复备份                                          │
│     - 知道如何进入救援模式                                      │
│                                                                 │
│  5. 小步修改，逐一测试                                          │
│     - 不要一次改很多东西                                        │
│     - 每改一项就测试                                            │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

</details>

### 6.2 测试流程

```bash
# 1. 保持当前 root 终端打开！

# 2. 备份所有相关配置
sudo cp -r /etc/pam.d /etc/pam.d.bak.$(date +%Y%m%d)
sudo cp /etc/security/faillock.conf /etc/security/faillock.conf.bak

# 3. 进行修改
sudo vim /etc/security/faillock.conf

# 4. 打开新终端测试（不要关闭旧终端！）
# 在新终端：
ssh testuser@localhost

# 5. 如果成功，再测试几个场景：
#    - 正确密码登录
#    - 错误密码登录（验证锁定）
#    - sudo 命令
#    - su 命令

# 6. 如果失败，在旧终端恢复：
sudo cp -r /etc/pam.d.bak.* /etc/pam.d

# 7. 确认一切正常后，才关闭旧终端
```

### 6.3 救援模式恢复

如果完全锁死，使用救援模式：

```bash
# 1. 重启进入 GRUB
# 在启动时按 e 编辑启动项

# 2. 在 linux 行末尾添加：
init=/bin/bash
# 或
rd.break

# 3. 按 Ctrl+X 启动

# 4. 挂载根文件系统可写
mount -o remount,rw /sysroot
chroot /sysroot

# 5. 恢复备份
cp /etc/pam.d.bak/* /etc/pam.d/
# 或恢复默认
authselect select sssd --force  # RHEL 8+

# 6. 如果改了 SELinux 文件，需要 relabel
touch /.autorelabel

# 7. 重启
exit
reboot
```

---

## 反模式：常见错误

### 错误 1：直接修改生产环境 PAM

```bash
# 危险！没有备份就修改
sudo vim /etc/pam.d/system-auth

# 正确做法
sudo cp /etc/pam.d/system-auth /etc/pam.d/system-auth.bak.$(date +%Y%m%d)
sudo vim /etc/pam.d/system-auth
# 在另一个终端测试！
```

### 错误 2：同时修改多个配置

```bash
# 危险！同时改很多，出问题不知道是哪个
sudo vim /etc/pam.d/system-auth
sudo vim /etc/pam.d/sshd
sudo vim /etc/security/faillock.conf
sudo vim /etc/security/pwquality.conf

# 正确做法：一次只改一个，测试后再改下一个
```

### 错误 3：使用 even_deny_root 但没有其他恢复方式

```bash
# /etc/security/faillock.conf
even_deny_root          # ← root 也会被锁定！
root_unlock_time = 60   # ← 必须设置恢复时间

# 如果没有设置 root_unlock_time，且锁定了 root，你可能需要救援模式恢复
```

### 错误 4：忘记 pam_faillock 需要两行

```bash
# 错误：只加了一行
auth required pam_faillock.so preauth

# 正确：需要两行（preauth 和 authfail）
auth required pam_faillock.so preauth silent audit deny=5
auth [default=die] pam_faillock.so authfail audit deny=5
```

---

## 职场小贴士（Japan IT Context）

### PAM 安全在日本企业

| 日语术语 | 含义 | 技术实现 |
|----------|------|----------|
| パスワードポリシー | 密码策略 | pam_pwquality |
| アカウントロック | 账户锁定 | pam_faillock |
| ログイン認証 | 登录认证 | PAM 认证流程 |
| 多要素認証 | 多因素认证 | pam_google_authenticator 等 |
| LDAP 連携 | LDAP 集成 | pam_sss / pam_ldap |

### 日本企业合规要求

很多日本企业需要满足以下合规要求：

1. **ISMS (ISO 27001)**
   - 密码复杂度要求
   - 账户锁定策略
   - 访问控制

2. **PCI DSS**（金融/支付行业）
   - 8.1.6: 6 次失败后锁定
   - 8.1.7: 锁定至少 30 分钟
   - 8.2.3: 密码至少 7 字符

3. **J-SOX**（上市公司）
   - 访问控制审计
   - 密码变更记录

### 安全检查报告模板

```markdown
## PAM セキュリティ監査結果

### 確認日: 20XX年XX月XX日
### 対象サーバー: production-app-01

| 項目 | 推奨設定 | 現在設定 | 判定 |
|------|----------|----------|------|
| アカウントロック（失敗回数） | 5 回 | 未設定 | NG |
| ロック時間 | 10 分以上 | - | NG |
| パスワード最小長 | 14 文字 | 8 文字 | 要改善 |
| パスワード複雑性 | 有効 | 無効 | NG |

### 改善提案
1. pam_faillock を導入し、5 回失敗で 10 分ロック設定
2. pwquality で 14 文字以上、複雑性要件を有効化
3. 変更後のテスト手順を文書化
```

---

## 检查清单

完成本课后，你应该能够：

- [ ] 解释 PAM 四种模块类型（auth, account, password, session）
- [ ] 解释控制标志的区别（required, requisite, sufficient, optional）
- [ ] 配置 pam_faillock 实现账户锁定
- [ ] 使用 `faillock` 命令查看和重置锁定状态
- [ ] 配置 pam_pwquality 密码策略
- [ ] 使用 `pwscore` 测试密码强度
- [ ] 安全地测试 PAM 配置变更（保持备用会话）
- [ ] 从 PAM 配置错误中恢复

---

## 本课小结

| 概念 | 命令/配置 | 记忆点 |
|------|-----------|--------|
| 账户锁定 | pam_faillock | 替代 pam_tally2 |
| 查看锁定 | `faillock --user xxx` | 查看失败记录 |
| 解锁账户 | `faillock --user xxx --reset` | 清除失败记录 |
| 密码策略 | /etc/security/pwquality.conf | minlen, dcredit 等 |
| 测试密码 | `pwscore "password"` | 返回分数 |
| 认证日志 | /var/log/secure 或 auth.log | 查看失败原因 |
| 安全法则 | **保持备用 root 会话！** | 最重要的规则 |

**黄金法则**：

```
PAM 配置 = 高风险操作

备份 → 保持备用会话 → 小步修改 → 逐一测试 → 准备回滚
```

---

## 延伸阅读

- [Linux PAM Documentation](http://www.linux-pam.org/Linux-PAM-html/) - 官方文档
- [CIS Benchmark - Password Settings](https://www.cisecurity.org/benchmark) - 合规基线
- [RHEL 9 PAM Configuration](https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/9/html/security_hardening/configuring-and-managing-security_security-hardening) - Red Hat 官方指南
- [pam_faillock man page](https://man7.org/linux/man-pages/man8/pam_faillock.8.html) - 详细参数
- 相关课程：[Lesson 02 - SSH 加固](../02-ssh-hardening/) - SSH 认证与 PAM 的关系
- 相关课程：[Lesson 10 - CIS Benchmarks](../10-cis-benchmarks/) - 合规扫描会检查 PAM 配置

---

## 系列导航

[上一课：08 - nftables 深入](../08-nftables/) | [系列首页](../) | [下一课：10 - CIS Benchmarks 合规实战 ->](../10-cis-benchmarks/)
