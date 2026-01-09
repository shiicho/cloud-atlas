# 02 - SSH 现代化加固 / Modern SSH Hardening

> **目标**：掌握 2025-2026 年 SSH 安全加固最佳实践  
> **前置**：完成 Lesson 01（安全原则与威胁建模）  
> **时间**：2.5 小时  
> **实战场景**：生产服务器 SSH 加固 + 误配置恢复演练  

---

## 将学到的内容

1. 配置仅密钥认证（Key-only authentication）
2. 选择安全的密钥算法（ed25519 推荐）
3. 实施基础 SSH 加固设置
4. 配置 Fail2Ban 防暴力破解
5. **练习误配置恢复（回滚演练）**

---

## 先跑起来！（5 分钟）

> 在学习理论之前，先看看你的服务器有多"不安全"。  

```bash
# 查看当前 SSH 配置的关键安全设置
sudo sshd -T | grep -E 'permitrootlogin|passwordauthentication|pubkeyauthentication|permitemptypasswords'

# 查看服务器支持的密钥算法
sudo sshd -T | grep -E 'pubkeyacceptedalgorithms|hostkeyalgorithms' | head -2

# 查看最近的 SSH 登录失败记录
sudo grep -i "failed" /var/log/secure 2>/dev/null | tail -5 || \
sudo grep -i "failed" /var/log/auth.log 2>/dev/null | tail -5 || \
sudo journalctl -u sshd --since "1 hour ago" | grep -i "failed" | tail -5

# 检查是否还在用古老的 ssh-rsa 密钥
ls -la ~/.ssh/*.pub 2>/dev/null && \
for key in ~/.ssh/*.pub; do echo "=== $key ===" && head -1 "$key" | cut -d' ' -f1; done
```

**你刚刚检查了：**

- 是否允许 root 直接登录？（应该 `no`）
- 是否允许密码登录？（应该 `no`）
- 是否启用了公钥认证？（应该 `yes`）
- 密钥算法是否是现代的？（ed25519 > RSA > ssh-rsa）
- 最近有没有人尝试暴力破解？

**如果你的服务器允许密码登录 + root 登录，那它正在互联网上裸奔。**

现在让我们修复它。

---

## Step 1 - SSH 安全现状 2025-2026（10 分钟）

### 1.1 ssh-rsa 已经死了

OpenSSH 8.8+（2021年9月）开始，ssh-rsa 签名算法**默认禁用**。

```bash
# 检查你的 OpenSSH 版本
ssh -V

# OpenSSH_9.x 是现代版本
# OpenSSH_7.x 或更早需要升级
```

**为什么 ssh-rsa 被弃用？**

| 算法 | 哈希 | 状态 | 安全性 |
|------|------|------|--------|
| ssh-rsa | SHA-1 | **已弃用** | 可被碰撞攻击 |
| rsa-sha2-256 | SHA-256 | 可用 | 安全 |
| rsa-sha2-512 | SHA-512 | 可用 | 安全 |
| ssh-ed25519 | EdDSA | **推荐** | 最安全、最快 |

### 1.2 现代密钥算法推荐

```
2025 年推荐优先级：

1. ed25519        ← 首选（快速、安全、短密钥）
2. ecdsa-sha2-*   ← 可接受（曲线安全性有争议）
3. rsa-sha2-512   ← 兼容性需要时（密钥需 3072+ 位）
4. sk-ssh-ed25519 ← 硬件密钥（FIDO2/U2F）
```

### 1.3 OpenSSH 9.x 新特性概览

| 版本 | 新特性 | 安全影响 |
|------|--------|----------|
| 9.0 | 默认 SFTP 使用更安全的传输 | 文件传输更安全 |
| 9.2 | FIDO2 resident keys | 硬件密钥无需私钥文件 |
| 9.5 | 更严格的算法默认 | 自动拒绝弱算法 |
| 9.8 | 实验性后量子密钥交换 | 未来量子计算防护 |

---

## Step 2 - 生成现代 SSH 密钥（15 分钟）

### 2.1 生成 ed25519 密钥

```bash
# 生成 ed25519 密钥（推荐）
ssh-keygen -t ed25519 -C "your_email@example.com"

# 输出：
# Generating public/private ed25519 key pair.
# Enter file in which to save the key (/home/user/.ssh/id_ed25519):
# Enter passphrase (empty for no passphrase):   ← 强烈建议设置！
# Enter same passphrase again:
```

**Passphrase 建议**：
- 12+ 字符
- 包含空格（容易记忆的短句）
- 示例：`my first server in tokyo 2025`

### 2.2 查看密钥信息

```bash
# 查看公钥（这个要复制到服务器）
cat ~/.ssh/id_ed25519.pub

# 输出示例：
# ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI... your_email@example.com

# 对比 RSA 密钥长度（ed25519 更短但更安全）
wc -c ~/.ssh/id_ed25519.pub ~/.ssh/id_rsa.pub 2>/dev/null
```

### 2.3 如果必须使用 RSA

有些老旧系统只支持 RSA。如果必须使用：

```bash
# 生成 4096 位 RSA 密钥（最小 3072，推荐 4096）
ssh-keygen -t rsa -b 4096 -C "your_email@example.com"

# 警告：2048 位 RSA 在 2025 年已不推荐！
```

### 2.4 配置 authorized_keys

```bash
# 在目标服务器上
mkdir -p ~/.ssh
chmod 700 ~/.ssh

# 添加公钥
echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5... your_email@example.com" >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys

# 验证权限（这很重要！权限错误会导致密钥认证失败）
ls -la ~/.ssh/
# drwx------ . ~/.ssh
# -rw------- . ~/.ssh/authorized_keys
```

### 2.5 使用 ssh-agent 管理密钥

```bash
# 启动 ssh-agent
eval "$(ssh-agent -s)"

# 添加密钥（会要求输入 passphrase）
ssh-add ~/.ssh/id_ed25519

# 查看已加载的密钥
ssh-add -l

# 在 ~/.bashrc 或 ~/.zshrc 中自动启动
# if [ -z "$SSH_AUTH_SOCK" ]; then
#   eval "$(ssh-agent -s)"
# fi
```

---

## Step 3 - sshd_config 安全加固（30 分钟）

### 3.1 查看当前配置

```bash
# 查看生效的配置（包括默认值）
sudo sshd -T

# 查看主配置文件
sudo cat /etc/ssh/sshd_config

# 查看 drop-in 配置目录（如果存在）
ls /etc/ssh/sshd_config.d/ 2>/dev/null
```

### 3.2 安全加固配置

创建一个 drop-in 配置文件（推荐方式，便于管理和回滚）：

```bash
# 备份原始配置
sudo cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak.$(date +%Y%m%d)

# 创建加固配置（使用 drop-in 目录）
sudo tee /etc/ssh/sshd_config.d/99-hardening.conf << 'EOF'
# =============================================================================
# SSH Hardening Configuration
# Created: $(date +%Y-%m-%d)
# Reference: CIS Benchmark, OpenSSH Best Practices 2025
# =============================================================================

# -----------------------------------------------------------------------------
# 1. Authentication Settings
# -----------------------------------------------------------------------------

# 禁止 root 直接登录（使用 sudo 替代）
PermitRootLogin no

# 禁止密码认证（仅允许密钥）
PasswordAuthentication no

# 禁止空密码
PermitEmptyPasswords no

# 启用公钥认证
PubkeyAuthentication yes

# 禁止基于主机的认证
HostbasedAuthentication no

# 禁止 rhosts 认证
IgnoreRhosts yes

# -----------------------------------------------------------------------------
# 2. Connection Settings
# -----------------------------------------------------------------------------

# 最大认证尝试次数
MaxAuthTries 3

# 登录超时时间（秒）
LoginGraceTime 60

# 最大并发未认证连接
MaxStartups 10:30:60

# 客户端存活检测
ClientAliveInterval 300
ClientAliveCountMax 2

# -----------------------------------------------------------------------------
# 3. Algorithm Settings (2025 Recommendations)
# -----------------------------------------------------------------------------

# 只允许安全的密钥算法
PubkeyAcceptedAlgorithms ssh-ed25519,sk-ssh-ed25519@openssh.com,rsa-sha2-512,rsa-sha2-256

# 主机密钥算法
HostKeyAlgorithms ssh-ed25519,rsa-sha2-512,rsa-sha2-256

# 密钥交换算法
KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org,diffie-hellman-group16-sha512,diffie-hellman-group18-sha512

# 加密算法
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com

# MAC 算法
MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com

# -----------------------------------------------------------------------------
# 4. Logging and Auditing
# -----------------------------------------------------------------------------

# 详细日志记录
LogLevel VERBOSE

# Syslog facility
SyslogFacility AUTH

# -----------------------------------------------------------------------------
# 5. Misc Security Settings
# -----------------------------------------------------------------------------

# 禁用 X11 转发（除非需要）
X11Forwarding no

# 禁用 TCP 转发（根据需求调整）
# AllowTcpForwarding no

# 显示上次登录信息
PrintLastLog yes

# 禁用 motd
PrintMotd no

# 限制可登录用户（可选，取消注释并修改）
# AllowUsers admin deploy
# AllowGroups sshusers wheel

EOF
```

### 3.3 配置验证（关键步骤！）

> **这是本课最重要的技能：在重启服务之前验证配置。**  

```bash
# 验证配置语法（-t = test mode）
sudo sshd -t

# 如果有错误会显示：
# /etc/ssh/sshd_config.d/99-hardening.conf: line 42: Bad configuration option: InvalidOption
# 如果没有输出 = 配置正确

# 验证配置内容（-T = extended test mode）
sudo sshd -T | grep -E 'permitrootlogin|passwordauthentication'
# 应该显示：
# permitrootlogin no
# passwordauthentication no
```

### 3.4 安全重启 sshd

> **黄金法则**：修改 SSH 配置时，**永远保持当前会话打开**！  

```bash
# 在当前终端执行，但不要关闭这个终端！
sudo systemctl reload sshd

# 打开新终端测试连接
# ssh user@server
# 如果新连接成功，才关闭旧终端

# 如果出问题，在旧终端恢复：
# sudo mv /etc/ssh/sshd_config.d/99-hardening.conf /etc/ssh/sshd_config.d/99-hardening.conf.broken
# sudo systemctl reload sshd
```

---

## Step 4 - Fail2Ban 配置（20 分钟）

### 4.1 什么是 Fail2Ban？

Fail2Ban 监控日志文件，检测暴力破解尝试，自动封禁攻击 IP。

```
攻击流程：

黑客 → SSH 暴力破解 → 失败日志 → Fail2Ban 检测 → iptables/nftables 封禁
  |                                                        |
  └──────────── 被封禁 15 分钟 ←─────────────────────────────┘
```

### 4.2 安装 Fail2Ban

```bash
# RHEL/CentOS/Rocky
sudo dnf install epel-release -y
sudo dnf install fail2ban -y

# Debian/Ubuntu
sudo apt update
sudo apt install fail2ban -y

# 启动并设置开机自启
sudo systemctl enable --now fail2ban
```

### 4.3 配置 SSH 保护

```bash
# 创建本地配置（不要直接修改 jail.conf）
sudo tee /etc/fail2ban/jail.local << 'EOF'
# =============================================================================
# Fail2Ban SSH Protection
# =============================================================================

[DEFAULT]
# 封禁时间（秒）- 15 分钟
bantime = 900

# 检测时间窗口（秒）- 10 分钟内
findtime = 600

# 最大失败次数
maxretry = 5

# 封禁动作（根据系统选择）
# banaction = iptables-multiport     # 旧系统
banaction = nftables-multiport       # 现代系统（RHEL 9+, Debian 11+）

# 忽略的 IP（不会被封禁）
ignoreip = 127.0.0.1/8 ::1

[sshd]
enabled = true
port = ssh
logpath = %(sshd_log)s
backend = %(sshd_backend)s

# 更严格的设置（可选）
# maxretry = 3
# bantime = 3600
# findtime = 1800

EOF
```

### 4.4 验证 Fail2Ban 状态

```bash
# 重启 fail2ban
sudo systemctl restart fail2ban

# 查看状态
sudo fail2ban-client status

# 查看 SSH jail 详情
sudo fail2ban-client status sshd

# 输出示例：
# Status for the jail: sshd
# |- Filter
# |  |- Currently failed: 2
# |  |- Total failed:     15
# |  `- File list:        /var/log/secure
# `- Actions
#    |- Currently banned: 1
#    |- Total banned:     3
#    `- Banned IP list:   203.0.113.50
```

### 4.5 常用 Fail2Ban 命令

```bash
# 手动封禁 IP
sudo fail2ban-client set sshd banip 192.168.1.100

# 手动解封 IP
sudo fail2ban-client set sshd unbanip 192.168.1.100

# 查看封禁的 IP
sudo fail2ban-client get sshd banned

# 查看 fail2ban 日志
sudo tail -f /var/log/fail2ban.log
```

---

## Step 5 - 误配置恢复演练（30 分钟）

> **这是本课最重要的实战技能。**  
> 在生产环境中，SSH 配置错误可能导致你被永久锁在服务器外面。  

### 5.1 常见的致命错误

| 错误 | 后果 | 恢复难度 |
|------|------|----------|
| `PasswordAuthentication no` + 没有密钥 | 无法登录 | 需要控制台 |
| `AllowUsers` 写错用户名 | 无法登录 | 需要控制台 |
| `sshd_config` 语法错误 | sshd 无法启动 | 需要控制台 |
| `ListenAddress` 绑定错误地址 | 无法连接 | 需要控制台 |

### 5.2 回滚演练：故意制造误配置

> **只在测试环境进行！** 确保你有控制台访问权限。  

使用我们提供的演练脚本：

```bash
# 查看脚本内容（先了解它做什么）
cat code/rollback-drill/break-ssh.sh

# 在测试环境执行（需要 root）
sudo bash code/rollback-drill/break-ssh.sh
```

脚本会：
1. 备份当前配置
2. 创建一个故意错误的配置
3. 重启 sshd

### 5.3 恢复步骤

当你被锁在外面时：

**方法 1：使用另一个已登录的终端**

```bash
# 如果你还有一个 root 会话打开
sudo mv /etc/ssh/sshd_config /etc/ssh/sshd_config.broken
sudo mv /etc/ssh/sshd_config.bak.* /etc/ssh/sshd_config
sudo sshd -t && sudo systemctl restart sshd
```

**方法 2：使用控制台（VNC/IPMI/Cloud Console）**

```bash
# 通过控制台登录后
sudo mv /etc/ssh/sshd_config /etc/ssh/sshd_config.broken
sudo mv /etc/ssh/sshd_config.bak.* /etc/ssh/sshd_config
sudo sshd -t && sudo systemctl restart sshd
```

**方法 3：使用 Live CD/救援模式**

```bash
# 挂载系统分区
mount /dev/sda1 /mnt

# 恢复配置
mv /mnt/etc/ssh/sshd_config /mnt/etc/ssh/sshd_config.broken
cp /mnt/etc/ssh/sshd_config.bak.* /mnt/etc/ssh/sshd_config

# 重启
reboot
```

**方法 4：AWS EC2 救援（Instance Connect / SSM）**

```bash
# 如果 SSH 失败，使用 EC2 Instance Connect（需要事先配置）
aws ec2-instance-connect send-ssh-public-key \
  --instance-id i-xxxxxxxxx \
  --availability-zone ap-northeast-1a \
  --instance-os-user ec2-user \
  --ssh-public-key file://~/.ssh/id_ed25519.pub

# 或使用 SSM Session Manager
aws ssm start-session --target i-xxxxxxxxx
```

### 5.4 防止误配置的最佳实践

```bash
# 1. 永远先验证
sudo sshd -t

# 2. 使用 reload 而不是 restart（更平滑）
sudo systemctl reload sshd

# 3. 保持旧终端打开直到新连接成功

# 4. 使用 drop-in 配置文件（便于回滚）
# /etc/ssh/sshd_config.d/99-hardening.conf
# 删除这个文件就能恢复默认

# 5. 设置自动恢复 cron（可选，激进做法）
# 每 5 分钟自动恢复 SSH 配置（测试环境）
# */5 * * * * /usr/bin/cp /etc/ssh/sshd_config.backup /etc/ssh/sshd_config && /usr/bin/systemctl reload sshd
```

---

## 高级话题：SSH 证书认证（可选）

> **适用场景**：大规模部署（100+ 服务器），需要集中管理访问权限。  

传统密钥认证的问题：

- 每个服务器需要配置每个用户的公钥
- 无法设置密钥过期时间
- 撤销访问需要逐台服务器删除公钥

SSH 证书认证解决这些问题：

```
┌─────────────────────────────────────────────────────────────────┐
│                    SSH Certificate Architecture                  │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────┐    签发证书     ┌─────────────────────────┐   │
│  │     CA      │ ───────────────▶│  用户证书（有效期 24h） │   │
│  │（证书颁发机构）│                 └─────────────────────────┘   │
│  └──────┬──────┘                              │                  │
│         │                                     │                  │
│         │ 信任 CA 公钥                        │ 使用证书登录     │
│         ▼                                     ▼                  │
│  ┌─────────────┐                    ┌─────────────────────────┐ │
│  │   服务器     │ ◀──────────────── │        用户            │ │
│  │ TrustedUserCA│                   │  (无需 authorized_keys) │ │
│  └─────────────┘                    └─────────────────────────┘ │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

<details>
<summary>View ASCII source</summary>

```
┌─────────────────────────────────────────────────────────────────┐
│                    SSH Certificate Architecture                  │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────┐    签发证书     ┌─────────────────────────┐   │
│  │     CA      │ ───────────────▶│  用户证书（有效期 24h） │   │
│  │（证书颁发机构）│                 └─────────────────────────┘   │
│  └──────┬──────┘                              │                  │
│         │                                     │                  │
│         │ 信任 CA 公钥                        │ 使用证书登录     │
│         ▼                                     ▼                  │
│  ┌─────────────┐                    ┌─────────────────────────┐ │
│  │   服务器     │ ◀──────────────── │        用户            │ │
│  │ TrustedUserCA│                   │  (无需 authorized_keys) │ │
│  └─────────────┘                    └─────────────────────────┘ │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

</details>

**基本配置步骤**（仅供了解）：

```bash
# 1. 创建 CA 密钥对
ssh-keygen -t ed25519 -f /etc/ssh/ca_key -C "SSH CA"

# 2. 为用户签发证书（有效期 24 小时）
ssh-keygen -s /etc/ssh/ca_key -I user@example.com -n username -V +24h ~/.ssh/id_ed25519.pub

# 3. 服务器配置信任 CA
echo "TrustedUserCAKeys /etc/ssh/ca_key.pub" >> /etc/ssh/sshd_config
```

> **推荐工具**：[Netflix BLESS](https://github.com/Netflix/bless)、[Teleport](https://goteleport.com/)、[Vault SSH](https://www.vaultproject.io/docs/secrets/ssh)  

---

## 反模式：常见错误

### 错误 1：修改配置后不验证就重启

```bash
# 危险！可能锁死自己
sudo vim /etc/ssh/sshd_config
sudo systemctl restart sshd    # ← 没有验证就重启

# 正确做法
sudo vim /etc/ssh/sshd_config
sudo sshd -t                   # ← 先验证
sudo systemctl reload sshd     # ← reload 比 restart 更安全
```

### 错误 2：禁用密码但没有配置密钥

```bash
# 致命错误！
PasswordAuthentication no
# 但 ~/.ssh/authorized_keys 是空的或不存在

# 正确做法：先确保密钥可用，再禁用密码
ssh -i ~/.ssh/id_ed25519 user@server
# 成功后再修改配置
```

### 错误 3：使用共享 SSH 密钥

```bash
# 危险！整个团队用同一个私钥
# - 无法追踪谁做了什么
# - 一人离职需要更换所有服务器密钥
# - 密钥泄露影响所有人

# 正确做法：每人一个密钥
ssh-keygen -t ed25519 -C "tanaka@company.com"
# 在 authorized_keys 中添加每个人的公钥，带注释
```

### 错误 4：使用过时的算法

```bash
# 不安全的配置
ssh-keygen -t rsa -b 1024     # ← 太短，可被破解
ssh-keygen -t dsa             # ← 已完全弃用

# 2025 年安全配置
ssh-keygen -t ed25519         # ← 首选
ssh-keygen -t rsa -b 4096     # ← 需要兼容时
```

---

## 职场小贴士（Japan IT Context）

### SSH 安全在日本企业

| 日语术语 | 含义 | 技术实现 |
|----------|------|----------|
| パスワード認証 | 密码认证 | `PasswordAuthentication yes/no` |
| 公開鍵認証 | 公钥认证 | `PubkeyAuthentication yes` |
| 個人鍵 | 个人密钥 | 每人一对密钥 |
| 共有鍵 | 共享密钥 | **反模式**，应避免 |
| 不正アクセス | 非法访问 | Fail2Ban 检测 |

### 日本企业常见的 SSH 管理问题

1. **共有鍵の問題**：很多日本企业仍在使用共享密钥
   - 解决：引入个人密钥 + 堡垒机

2. **パスワード認証がまだ有効**：密码认证仍然启用
   - 解决：渐进式迁移到密钥认证

3. **ログ管理不足**：SSH 日志保留不足
   - 解决：配置 rsyslog + 中央日志服务器

### 安全检查报告模板

```markdown
## SSH セキュリティ監査結果

### 確認日: 20XX年XX月XX日
### 対象サーバー: production-web-01

| 項目 | 推奨設定 | 現在設定 | 判定 |
|------|----------|----------|------|
| PermitRootLogin | no | no | OK |
| PasswordAuthentication | no | yes | NG |
| PubkeyAuthentication | yes | yes | OK |
| 鍵アルゴリズム | ed25519 | rsa | 要改善 |
| Fail2Ban | 有効 | 無効 | NG |

### 改善提案
1. パスワード認証を無効化
2. 全ユーザーの ed25519 鍵への移行
3. Fail2Ban の導入
```

---

## 检查清单

完成本课后，你应该能够：

- [ ] 解释为什么 ssh-rsa 被弃用
- [ ] 生成 ed25519 密钥对
- [ ] 配置 `authorized_keys` 并设置正确权限
- [ ] 使用 `sshd -t` 验证配置语法
- [ ] 配置关键安全选项：`PermitRootLogin no`、`PasswordAuthentication no`
- [ ] 安装和配置 Fail2Ban
- [ ] 从 SSH 误配置中恢复
- [ ] 解释密码锁定 vs 账户锁定的区别

---

## 本课小结

| 概念 | 命令/配置 | 记忆点 |
|------|-----------|--------|
| 密钥生成 | `ssh-keygen -t ed25519` | 2025 首选算法 |
| 配置验证 | `sshd -t` | **必须在重启前执行！** |
| 禁止 root | `PermitRootLogin no` | 使用 sudo 替代 |
| 禁止密码 | `PasswordAuthentication no` | 密钥才安全 |
| 暴力破解防护 | Fail2Ban | 自动封禁攻击 IP |
| 配置备份 | `cp sshd_config sshd_config.bak.$(date)` | 回滚保障 |
| 安全重启 | `systemctl reload sshd` | 保持旧会话 |

**黄金法则**：

```
修改前备份 → 验证后重启 → 保留后门（旧会话/控制台）
```

---

## 延伸阅读

- [OpenSSH Release Notes](https://www.openssh.com/releasenotes.html) - 版本更新说明
- [Mozilla SSH Guidelines](https://infosec.mozilla.org/guidelines/openssh) - 企业级配置指南
- [CIS Benchmark for SSH](https://www.cisecurity.org/benchmark) - 合规基线
- [Fail2Ban Documentation](https://www.fail2ban.org/wiki/index.php/Main_Page) - 官方文档
- 相关课程：[Lesson 07 - auditd 审计](../07-auditd/) - 学习 SSH 配置变更审计

---

## 系列导航

[上一课：01 - 安全原则与威胁建模](../01-security-principles/) | [系列首页](../) | [下一课：03 - SELinux 核心概念 ->](../03-selinux-concepts/)
