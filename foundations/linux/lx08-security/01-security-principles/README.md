# 01 - 安全原则与威胁建模（Security Principles & Threat Modeling）

> **目标**：建立安全思维，理解 Linux 安全模型的核心原则  
> **前置**：基础 Linux 命令行操作（ls, cat, grep, find）、用户/权限管理基础  
> **时间**：⚡ 30 分钟（速读）/ 🔬 120 分钟（完整实操）  
> **实战场景**：系统安全状态检查、权限审计  

---

## 将学到的内容

1. 理解纵深防御（Defense in Depth）原则
2. 掌握最小权限原则（Least Privilege）
3. 理解 DAC（自主访问控制）与 MAC（强制访问控制）的区别
4. 能够进行基础威胁建模
5. 了解 TLS/证书的基础概念（为什么 HTTPS 安全）
6. 熟悉日本企业安全合规要求（ISMS, PCI DSS）

---

## 先跑起来！（10 分钟）

> 在学习理论之前，先体验系统安全状态检查。  
> 运行这些命令，观察输出——这就是安全运维的第一步。  

```bash
# 1. 检查 SELinux 模式（RHEL/CentOS/Rocky）
getenforce

# 2. 查看 SELinux 详细状态
sestatus

# 3. 检查开放端口（哪些服务在监听？）
ss -tulpn | head -10

# 4. 查看最近的失败登录尝试
sudo grep -i fail /var/log/secure 2>/dev/null | tail -5 || \
sudo grep -i fail /var/log/auth.log 2>/dev/null | tail -5

# 5. 找出 SUID 文件（潜在提权风险）
find /usr -perm /6000 -type f 2>/dev/null | head -10
```

**你刚刚检查了系统安全状态！**

| 你检查的内容 | 为什么重要 |
|-------------|-----------|
| SELinux 模式 | 是否启用强制访问控制？ |
| 开放端口 | 攻击面有多大？ |
| 失败登录 | 有人在尝试暴力破解吗？ |
| SUID 文件 | 有潜在提权漏洞吗？ |

> **问自己**：  
> - SELinux 是 `Enforcing` 吗？如果是 `Disabled` 或 `Permissive`，为什么？  
> - 有多少端口对外开放？每个都是必需的吗？  
> - 最近有失败的登录尝试吗？来自哪个 IP？  
> - 系统有多少 SUID 文件？你认识这些程序吗？  

现在让我们理解这些命令背后的原理。

---

## Step 1 — 安全思维导入（15 分钟）

### 1.1 为什么安全不是"可选"

在日本 IT 企业，安全不是"加分项"，而是**基本要求**。

| 场景 | 后果 |
|------|------|
| SSH 暴力破解成功 | 服务器被入侵，数据泄露 |
| 配置错误导致数据库暴露 | 客户信息泄露，法律责任 |
| 未修补已知漏洞 | 勒索软件攻击，业务中断 |
| 内部人员权限过大 | 离职员工删除数据 |

> **日本企业背景**：根据 IPA（情報処理推進機構）统计，配置错误（設定ミス）是安全事故的主要原因之一。  

### 1.2 运维视角的威胁：配置错误 vs 外部攻击

作为运维工程师，你面对的威胁主要分两类：

<!-- DIAGRAM: threat-sources -->
```
┌─────────────────────────────────────────────────────────────────┐
│                     威胁来源                                      │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│   外部威胁（External）              内部威胁（Internal）           │
│   ┌─────────────────┐              ┌─────────────────┐          │
│   │ 🌐 网络攻击      │              │ ⚙️ 配置错误      │          │
│   │   - SSH 暴力破解 │              │   - chmod 777   │          │
│   │   - Web 漏洞利用 │              │   - 弱密码      │          │
│   │   - 端口扫描    │              │   - 未打补丁    │          │
│   └────────┬────────┘              └────────┬────────┘          │
│            │                                 │                   │
│            │      ┌─────────────────┐       │                   │
│            └─────▶│  你的系统       │◀──────┘                   │
│                   │  (需要保护)     │                           │
│                   └─────────────────┘                           │
│                                                                 │
│   统计：70%+ 安全事故源于配置错误，而非高级攻击                    │
└─────────────────────────────────────────────────────────────────┘
```
<!-- /DIAGRAM -->

**关键认知**：大多数安全事故不是因为高级黑客攻击，而是因为**简单的配置错误**。

### 1.3 日本企业安全合规要求

| 标准 | 适用场景 | 关键要求 |
|------|----------|----------|
| **ISMS (ISO 27001)** | 大多数日本企业 | 信息安全管理体系，审计日志，访问控制 |
| **PCI DSS** | 金融/支付 | SSH 加固，防火墙规则，审计追踪 |
| **SOX** | 上市公司 | 访问控制，变更管理，审计日志 |
| **個人情報保護法** | 所有企业 | 个人数据保护，访问记录 |

> **职场提示**：在日本企业面试时，提到"ISMS 対応経験あり"会是加分项。  

---

## Step 2 — 核心安全原则（20 分钟）

### 2.1 纵深防御（Defense in Depth）

**一句话**：不要把所有鸡蛋放在一个篮子里。

<!-- DIAGRAM: defense-in-depth -->
```
┌─────────────────────────────────────────────────────────────────┐
│                     纵深防御模型                                  │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│   ┌───────────────────────────────────────────────────────────┐ │
│   │  Layer 1: 网络边界（Network Perimeter）                    │ │
│   │  防火墙、nftables、安全组                                   │ │
│   │ ┌───────────────────────────────────────────────────────┐ │ │
│   │ │  Layer 2: 主机防护（Host Security）                    │ │ │
│   │ │  SSH 加固、Fail2Ban、系统更新                          │ │ │
│   │ │ ┌───────────────────────────────────────────────────┐ │ │ │
│   │ │ │  Layer 3: 访问控制（Access Control）               │ │ │ │
│   │ │ │  用户权限、sudo、SELinux                           │ │ │ │
│   │ │ │ ┌───────────────────────────────────────────────┐ │ │ │ │
│   │ │ │ │  Layer 4: 应用安全（Application Security）    │ │ │ │ │
│   │ │ │ │  输入验证、加密、认证                          │ │ │ │ │
│   │ │ │ │ ┌───────────────────────────────────────────┐ │ │ │ │ │
│   │ │ │ │ │  核心资产（Data）                         │ │ │ │ │ │
│   │ │ │ │ │  数据库、配置、日志                       │ │ │ │ │ │
│   │ │ │ │ └───────────────────────────────────────────┘ │ │ │ │ │
│   │ │ │ └───────────────────────────────────────────────┘ │ │ │ │
│   │ │ └───────────────────────────────────────────────────┘ │ │ │
│   │ └───────────────────────────────────────────────────────┘ │ │
│   └───────────────────────────────────────────────────────────┘ │
│                                                                 │
│   即使外层被突破，内层仍提供保护                                  │
└─────────────────────────────────────────────────────────────────┘
```
<!-- /DIAGRAM -->

**Linux 中的纵深防御示例**：

| 层级 | 技术 | 作用 |
|------|------|------|
| 网络 | nftables/firewalld | 限制可访问端口 |
| 主机 | SSH 密钥认证 | 防止暴力破解 |
| 主机 | Fail2Ban | 封禁恶意 IP |
| 系统 | SELinux | 限制进程能力（MAC） |
| 系统 | sudo | 限制 root 访问 |
| 应用 | 专用服务用户 | 隔离服务权限 |

### 2.2 最小权限原则（Least Privilege）

**一句话**：只给必要的权限，不多也不少。

```bash
# 反面教材：chmod 777
chmod 777 /var/www/html/  # 所有人可读写执行 ← 危险！

# 正确做法：精确权限
chown -R www-data:www-data /var/www/html/
chmod 755 /var/www/html/           # 目录
chmod 644 /var/www/html/*.html     # 文件
```

**最小权限的应用场景**：

| 场景 | 错误做法 | 正确做法 |
|------|----------|----------|
| 服务运行 | 以 root 运行 nginx | 以 nginx 用户运行 |
| 文件权限 | chmod 777 | 精确设置 owner/group |
| sudo 配置 | `ALL=(ALL) ALL` | 只允许特定命令 |
| 数据库用户 | 使用 root 账户 | 应用专用账户，只有必要权限 |

### 2.3 默认拒绝（Default Deny）

**一句话**：默认禁止一切，明确允许需要的。

```bash
# 防火墙示例：默认拒绝
nft add chain inet filter input { type filter hook input priority 0 \; policy drop \; }

# 然后明确允许需要的
nft add rule inet filter input tcp dport 22 accept    # SSH
nft add rule inet filter input tcp dport 80 accept    # HTTP
nft add rule inet filter input tcp dport 443 accept   # HTTPS
```

### 2.4 分离职责（Separation of Duties）

**一句话**：不同角色有不同权限，没有"超级用户"。

| 角色 | 权限范围 |
|------|----------|
| 开发者 | 部署代码，查看应用日志 |
| 运维 | 系统配置，服务管理 |
| DBA | 数据库管理，备份 |
| 安全 | 审计日志，安全扫描 |

> **日本企业背景**：权限分离（権限分離）是合规审计的重点。审计员会问："谁有权限修改生产环境？有记录吗？"  

---

## Step 3 — Linux 安全模型：DAC vs MAC（20 分钟）

### 3.1 传统权限模型：DAC（自主访问控制）

DAC（Discretionary Access Control）是传统 Unix/Linux 权限模型：

```bash
# 查看文件权限
ls -l /etc/passwd
# -rw-r--r-- 1 root root 2847 Jan  4 10:00 /etc/passwd

# 权限解读
# -rw-r--r--
#  │├─┤├─┤├─┤
#  │ │  │  └─ Other（其他用户）：只读
#  │ │  └──── Group（组）：只读
#  │ └─────── Owner（所有者）：读写
#  └───────── 文件类型（- = 普通文件）
```

**DAC 的特点**：

| 特点 | 说明 |
|------|------|
| 所有者控制 | 文件所有者可以修改权限 |
| 简单直观 | rwx 模型易于理解 |
| 局限性 | root 可以绕过所有限制 |

**DAC 的局限性**：

```bash
# 问题：root 不受 DAC 限制
chmod 000 /etc/shadow       # 任何人都没权限
cat /etc/shadow            # 普通用户失败
sudo cat /etc/shadow       # root 成功！

# 问题：进程继承用户权限
# 如果 nginx 以 root 运行，nginx 被攻破 = root 被攻破
```

### 3.2 强制访问控制：MAC（SELinux）

MAC（Mandatory Access Control）是额外的安全层：

<!-- DIAGRAM: dac-vs-mac -->
```
┌─────────────────────────────────────────────────────────────────┐
│                     DAC vs MAC 对比                              │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│   DAC（传统权限）                  MAC（SELinux）                 │
│   ┌─────────────────────┐        ┌─────────────────────┐        │
│   │    用户 alice       │        │    进程 httpd_t     │        │
│   │         │           │        │         │           │        │
│   │    检查 rwx 权限    │        │    检查 SELinux 策略│        │
│   │         │           │        │         │           │        │
│   │         ▼           │        │         ▼           │        │
│   │  ┌───────────┐      │        │  ┌───────────┐      │        │
│   │  │   文件    │      │        │  │   文件    │      │        │
│   │  │ owner:alice│     │        │  │ type:     │      │        │
│   │  │ mode:rw-  │      │        │  │ httpd_sys │      │        │
│   │  └───────────┘      │        │  │ _content_t│      │        │
│   │                     │        │  └───────────┘      │        │
│   │  ✓ alice 可以写入   │        │  ✓ httpd_t 可以读取 │        │
│   │  ✓ root 可以写入    │        │  ✗ httpd_t 不能写入 │        │
│   │  ✗ bob 不能写入     │        │  ✗ httpd_t 不能      │        │
│   │                     │        │    访问 user_home_t │        │
│   └─────────────────────┘        └─────────────────────┘        │
│                                                                 │
│   DAC: 基于用户身份                MAC: 基于进程和资源类型        │
│   DAC: root 可绕过                 MAC: 即使 root 也受限制       │
└─────────────────────────────────────────────────────────────────┘
```
<!-- /DIAGRAM -->

**检查 SELinux 状态**：

```bash
# 查看 SELinux 模式
getenforce
# Enforcing = 强制执行策略
# Permissive = 只记录不强制
# Disabled = 完全禁用

# 查看详细状态
sestatus

# 查看文件的 SELinux 上下文
ls -Z /var/www/html/
# -rw-r--r--. root root unconfined_u:object_r:httpd_sys_content_t:s0 index.html
#                                              └── 类型：httpd 可读取的内容

# 查看进程的 SELinux 上下文
ps auxZ | grep httpd
# system_u:system_r:httpd_t:s0   root ... /usr/sbin/httpd
#                   └── 类型：httpd 进程
```

### 3.3 DAC + MAC = 双重保护

```bash
# 场景：nginx 配置错误，尝试访问 /home/alice/secret.txt

# DAC 检查：
# - nginx 以 nginx 用户运行
# - /home/alice/secret.txt 权限是 600（只有 alice 可读）
# - DAC 拒绝：nginx 用户没有权限 ✗

# 如果 DAC 被绕过（比如 nginx 以 root 运行）...

# MAC 检查：
# - nginx 进程类型是 httpd_t
# - /home/alice/secret.txt 类型是 user_home_t
# - SELinux 策略不允许 httpd_t 访问 user_home_t
# - MAC 拒绝 ✗

# 结论：即使配置错误，SELinux 仍然保护了用户数据
```

> **重要**：SELinux 是你的安全网，不是障碍。后续课程会深入学习 SELinux 配置和排错。  

---

## Step 4 — 基础威胁建模（15 分钟）

### 4.1 威胁建模三问

进行威胁建模时，问自己三个问题：

| 问题 | 示例答案 |
|------|----------|
| **什么需要保护？（资产）** | 数据库、配置文件、用户数据 |
| **谁会攻击？如何攻击？（威胁）** | 外部黑客（SSH 暴力破解）、内部人员（权限滥用） |
| **如何防护？（控制）** | 密钥认证、最小权限、审计日志 |

### 4.2 简单威胁建模练习

**场景**：你负责一台运行 Web 应用的 Linux 服务器。

**Step 1: 资产识别**

```bash
# 列出关键资产
- Web 应用代码 (/var/www/app)
- 数据库 (MySQL/PostgreSQL)
- 配置文件 (/etc/nginx, /etc/app)
- 日志文件 (/var/log)
- SSH 私钥 (管理员访问)
```

**Step 2: 威胁识别**

| 威胁 | 攻击方式 | 可能性 | 影响 |
|------|----------|--------|------|
| SSH 暴力破解 | 字典攻击猜密码 | 高 | 高 |
| Web 漏洞利用 | SQL 注入、XSS | 中 | 高 |
| 配置错误 | 文件权限过大 | 高 | 中 |
| 内部威胁 | 离职员工账户未删除 | 中 | 高 |

**Step 3: 控制措施**

| 威胁 | 控制措施 | 课程章节 |
|------|----------|----------|
| SSH 暴力破解 | 密钥认证 + Fail2Ban | Lesson 02 |
| Web 漏洞 | SELinux + WAF | Lesson 03-05 |
| 配置错误 | 权限审计 + CIS 基线 | Lesson 10 |
| 内部威胁 | 审计日志 + 定期账户审查 | Lesson 07 |

---

## Step 5 — TLS/证书基础（15 分钟）

> **为什么在安全原则课程讲 TLS？** 因为在现代运维中，几乎所有服务都使用 TLS 加密通信。  
> 理解 TLS 基础能帮助你诊断连接问题、配置安全服务。  

### 5.1 TLS 握手概述

<!-- DIAGRAM: tls-handshake -->
```
┌─────────────────────────────────────────────────────────────────┐
│                     TLS 握手简化流程                              │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│   Client (浏览器)                        Server (Web 服务器)     │
│        │                                        │               │
│        │  1. ClientHello (支持的加密套件)       │               │
│        │───────────────────────────────────────▶│               │
│        │                                        │               │
│        │  2. ServerHello + 证书                 │               │
│        │◀───────────────────────────────────────│               │
│        │                                        │               │
│        │  3. 验证证书 ✓                         │               │
│        │     - 证书是否过期？                    │               │
│        │     - 颁发机构可信？                    │               │
│        │     - 域名匹配？                        │               │
│        │                                        │               │
│        │  4. 密钥交换（生成会话密钥）            │               │
│        │◀──────────────────────────────────────▶│               │
│        │                                        │               │
│        │  5. 加密通信开始 🔐                    │               │
│        │◀═══════════════════════════════════════▶               │
│        │                                        │               │
└─────────────────────────────────────────────────────────────────┘
```
<!-- /DIAGRAM -->

### 5.2 证书链：信任的传递

```bash
# 查看网站证书链
openssl s_client -connect example.com:443 -showcerts </dev/null 2>/dev/null | \
  grep -E "subject=|issuer="
```

```
# 输出示例（证书链）：
#
# Leaf 证书（网站证书）
#   subject=CN = example.com
#   issuer=CN = Let's Encrypt Authority X3
#
# Intermediate 证书（中间 CA）
#   subject=CN = Let's Encrypt Authority X3
#   issuer=CN = DST Root CA X3
#
# Root 证书（根 CA）
#   subject=CN = DST Root CA X3
#   issuer=CN = DST Root CA X3  ← 自签名
```

<!-- DIAGRAM: certificate-chain -->
```
┌─────────────────────────────────────────────────────────────────┐
│                     证书链（Certificate Chain）                  │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│   ┌─────────────────────┐                                       │
│   │  Root CA (根证书)    │  ← 预装在操作系统/浏览器中            │
│   │  自签名，最高信任    │                                       │
│   └──────────┬──────────┘                                       │
│              │ 签发                                              │
│              ▼                                                   │
│   ┌─────────────────────┐                                       │
│   │  Intermediate CA     │  ← 中间证书，传递信任                 │
│   │  (中间证书颁发机构)  │                                       │
│   └──────────┬──────────┘                                       │
│              │ 签发                                              │
│              ▼                                                   │
│   ┌─────────────────────┐                                       │
│   │  Leaf Certificate    │  ← 网站/服务使用的证书                │
│   │  (你的域名证书)      │                                       │
│   │  example.com         │                                       │
│   └─────────────────────┘                                       │
│                                                                 │
│   验证过程：从 Leaf → Intermediate → Root                        │
│   如果能追溯到受信任的 Root CA，证书有效 ✓                       │
└─────────────────────────────────────────────────────────────────┘
```
<!-- /DIAGRAM -->

### 5.3 系统信任库

```bash
# RHEL/CentOS: 信任库位置
ls /etc/pki/tls/certs/
ls /etc/pki/ca-trust/source/anchors/

# 添加自定义 CA（企业内部 CA）
sudo cp company-ca.crt /etc/pki/ca-trust/source/anchors/
sudo update-ca-trust

# Debian/Ubuntu
ls /etc/ssl/certs/
sudo cp company-ca.crt /usr/local/share/ca-certificates/
sudo update-ca-certificates
```

### 5.4 调试 TLS 连接问题

```bash
# 检查证书有效期
openssl s_client -connect example.com:443 </dev/null 2>/dev/null | \
  openssl x509 -noout -dates

# 输出：
# notBefore=Jan  1 00:00:00 2024 GMT
# notAfter=Dec 31 23:59:59 2024 GMT  ← 检查是否过期！

# 完整连接测试
openssl s_client -connect example.com:443 -servername example.com

# 检查支持的协议和加密套件
nmap --script ssl-enum-ciphers -p 443 example.com
```

### 5.5 反模式：curl -k 的危险

> **关键警告**：这是生产环境中绝对禁止的做法。  

```bash
# 错误做法：绕过证书验证
curl -k https://internal-api.company.com/data
# 或
curl --insecure https://internal-api.company.com/data
# 或
wget --no-check-certificate https://internal-api.company.com/data

# 为什么危险？
# - 无法验证服务器身份
# - 中间人攻击（MITM）可以拦截所有数据
# - 攻击者可以伪装成目标服务器
```

**正确做法**：

```bash
# 1. 检查证书问题
openssl s_client -connect internal-api.company.com:443

# 2. 常见问题和解决方案
#    - 证书过期 → 更新证书
#    - 自签名证书 → 添加 CA 到信任库
#    - 域名不匹配 → 使用正确域名或修复证书

# 3. 如果是内部 CA，添加到系统信任库
sudo cp company-ca.crt /etc/pki/ca-trust/source/anchors/
sudo update-ca-trust

# 4. 现在可以正常访问（无需 -k）
curl https://internal-api.company.com/data
```

> **日本企业背景**：安全审计（セキュリティ監査）时，`curl -k` 出现在脚本中会被标记为高风险问题。  

---

## Step 6 — 动手实验：权限审计（20 分钟）

### 6.1 实验目标

使用脚本检查系统敏感文件权限，识别潜在安全风险。

### 6.2 运行审计脚本

```bash
# 下载审计脚本（或使用本课 code/ 目录的脚本）
cd /tmp

# 创建审计脚本
cat > permission-audit.sh << 'EOF'
#!/bin/bash
# permission-audit.sh - 权限审计脚本
# 用于检查常见的权限问题

echo "=========================================="
echo " Linux 权限审计报告"
echo " 生成时间: $(date)"
echo " 主机名: $(hostname)"
echo "=========================================="
echo

# 1. 检查 SUID 文件
echo "[1] SUID/SGID 文件检查"
echo "-------------------------------------------"
echo "SUID 文件允许以文件所有者权限执行，可能被利用提权。"
echo
find /usr /bin /sbin -perm /6000 -type f 2>/dev/null | while read file; do
    echo "  $file"
done | head -20
echo "  (显示前 20 个)"
echo

# 2. 检查世界可写文件
echo "[2] 世界可写文件检查（排除 /tmp, /var/tmp）"
echo "-------------------------------------------"
echo "世界可写文件可能被任何用户修改。"
echo
find /etc /var/www /home -xdev -type f -perm -0002 2>/dev/null | head -10
if [ $? -eq 0 ]; then
    echo "  (如果有输出，需要检查是否必要)"
else
    echo "  未发现世界可写文件 ✓"
fi
echo

# 3. 检查关键文件权限
echo "[3] 关键文件权限检查"
echo "-------------------------------------------"
check_permission() {
    local file=$1
    local expected=$2
    if [ -f "$file" ]; then
        actual=$(stat -c %a "$file" 2>/dev/null)
        if [ "$actual" = "$expected" ]; then
            echo "  ✓ $file: $actual (期望: $expected)"
        else
            echo "  ✗ $file: $actual (期望: $expected) <- 需检查"
        fi
    else
        echo "  - $file: 文件不存在"
    fi
}

check_permission "/etc/passwd" "644"
check_permission "/etc/shadow" "000"
check_permission "/etc/group" "644"
check_permission "/etc/gshadow" "000"
check_permission "/etc/ssh/sshd_config" "600"
echo

# 4. 检查无密码用户
echo "[4] 无密码用户检查"
echo "-------------------------------------------"
awk -F: '($2 == "" || $2 == "!") && $7 !~ /nologin|false/ {print "  警告: " $1 " 可能没有密码或被锁定"}' /etc/shadow 2>/dev/null
echo

# 5. 检查 SELinux 状态
echo "[5] SELinux 状态"
echo "-------------------------------------------"
if command -v getenforce &>/dev/null; then
    status=$(getenforce)
    if [ "$status" = "Enforcing" ]; then
        echo "  ✓ SELinux: $status"
    else
        echo "  ✗ SELinux: $status <- 建议启用 Enforcing 模式"
    fi
else
    echo "  - SELinux 未安装（可能是 Ubuntu/Debian，使用 AppArmor）"
fi
echo

# 6. 检查开放端口
echo "[6] 监听端口检查"
echo "-------------------------------------------"
ss -tulpn 2>/dev/null | grep LISTEN | awk '{print "  " $1 " " $5}' | head -10
echo "  (显示前 10 个监听端口)"
echo

# 7. 检查失败登录
echo "[7] 最近失败登录（最近 5 条）"
echo "-------------------------------------------"
if [ -f /var/log/secure ]; then
    grep -i "failed" /var/log/secure 2>/dev/null | tail -5 | while read line; do
        echo "  $line"
    done
elif [ -f /var/log/auth.log ]; then
    grep -i "failed" /var/log/auth.log 2>/dev/null | tail -5 | while read line; do
        echo "  $line"
    done
else
    echo "  无法读取认证日志"
fi
echo

echo "=========================================="
echo " 审计完成"
echo "=========================================="
EOF

chmod +x permission-audit.sh
```

### 6.3 运行审计

```bash
# 运行审计脚本
sudo ./permission-audit.sh
```

### 6.4 分析结果

运行脚本后，关注以下问题：

| 检查项 | 问题 | 应对措施 |
|--------|------|----------|
| SUID 文件 | 不熟悉的程序有 SUID | 确认是否必要，不需要则 `chmod -s` |
| 世界可写 | /etc 下有世界可写文件 | 立即修复权限 |
| 关键文件 | /etc/shadow 权限不是 000 | 修复为 `chmod 000 /etc/shadow` |
| SELinux | 不是 Enforcing | 评估启用 |
| 失败登录 | 大量失败尝试 | 检查来源 IP，考虑 Fail2Ban |

---

## 反模式：常见错误

### 错误 1：chmod 777 解决问题

```bash
# 错误：权限问题？777 搞定！
chmod 777 /var/www/html/
chmod 777 /etc/app/config.yml

# 后果：
# - 任何用户可以修改配置文件
# - Web 应用可能被篡改
# - 安全审计必定失败

# 正确：分析具体需要什么权限
ls -la /var/www/html/
# 确定正确的 owner 和 group
chown -R www-data:www-data /var/www/html/
chmod 755 /var/www/html/
chmod 644 /var/www/html/*
```

### 错误 2：setenforce 0 作为永久解决方案

```bash
# 错误："SELinux 阻止了？关掉！"
setenforce 0
# 或更糟：
sed -i 's/SELINUX=enforcing/SELINUX=disabled/' /etc/selinux/config

# 后果：
# - 失去 MAC 保护层
# - 安全审计失败
# - 重新启用需要完整 relabel（耗时）

# 正确：排查并解决 SELinux 拒绝
ausearch -m avc -ts recent
audit2why < /var/log/audit/audit.log
# 根据建议使用 setsebool 或 semanage fcontext
```

### 错误 3：curl -k 绕过证书验证

```bash
# 错误："证书错误？加 -k！"
curl -k https://api.internal.com/sensitive-data

# 后果：
# - 无法验证服务器身份
# - 中间人攻击可以拦截数据
# - 生产环境绝对禁止

# 正确：修复证书问题
openssl s_client -connect api.internal.com:443
# 根据错误信息：添加 CA、更新证书、修复域名
```

### 错误 4：以 root 运行所有服务

```bash
# 错误：方便起见，nginx 以 root 运行
# nginx.conf: user root;

# 后果：
# - nginx 漏洞 = root 权限泄露
# - 违反最小权限原则

# 正确：专用服务用户
# nginx.conf: user nginx;
# 或使用 systemd 的 User= 指令
```

---

## 职场小贴士（Japan IT Context）

### 安全合规术语

| 日语术语 | 含义 | 相关内容 |
|----------|------|----------|
| セキュリティ対策 | 安全措施 | 本课所有内容 |
| 権限分離（けんげんぶんり） | 权限分离 | 最小权限原则 |
| 監査ログ（かんさログ） | 审计日志 | auditd（Lesson 07） |
| アクセス制御 | 访问控制 | DAC, MAC |
| 脆弱性対策（ぜいじゃくせいたいさく） | 漏洞应对 | 补丁管理 |
| インシデント対応 | 事故响应 | 威胁建模 |

### ISMS 对日常运维的影响

在通过 ISMS (ISO 27001) 认证的日本企业：

1. **变更管理**：任何配置变更需要审批和记录
2. **访问控制**：定期审查账户权限（棚卸し）
3. **审计日志**：必须保留并定期审查
4. **事故响应**：有明确的上报和处理流程

```bash
# 日常工作中的合规意识

# 1. 配置变更前记录
echo "$(date): 准备修改 sshd_config" >> /var/log/change.log

# 2. 备份原配置
cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak.$(date +%Y%m%d)

# 3. 进行变更并验证
sshd -t  # 语法检查

# 4. 记录变更完成
echo "$(date): sshd_config 修改完成，已重启服务" >> /var/log/change.log
```

---

## 检查清单

完成本课后，你应该能够：

- [ ] 解释纵深防御（Defense in Depth）原则
- [ ] 解释最小权限原则（Least Privilege）
- [ ] 区分 DAC（自主访问控制）和 MAC（强制访问控制）
- [ ] 说明 SELinux 的作用和三种模式
- [ ] 使用 `getenforce` 和 `sestatus` 检查 SELinux 状态
- [ ] 使用 `ss -tulpn` 检查开放端口
- [ ] 使用 `find -perm /6000` 查找 SUID 文件
- [ ] 解释 TLS 证书链的基本概念
- [ ] 使用 `openssl s_client` 检查证书
- [ ] 解释为什么 `curl -k` 是危险的
- [ ] 进行基础威胁建模（资产、威胁、控制）
- [ ] 说明日本企业常见的安全合规要求（ISMS, PCI DSS）

---

## 本课小结

| 概念 | 要点 |
|------|------|
| 纵深防御 | 多层保护，不依赖单一措施 |
| 最小权限 | 只给必要的权限 |
| 默认拒绝 | 先禁止一切，再明确允许 |
| DAC | 传统权限（rwx），所有者控制 |
| MAC | SELinux，即使 root 也受限 |
| 威胁建模 | 资产 → 威胁 → 控制 |
| TLS | 证书链验证，不要用 -k 绕过 |
| 合规 | ISMS, PCI DSS 在日本企业很重要 |

**核心理念**：安全不是一次性工作，而是持续的过程。70%+ 的安全事故源于配置错误——养成良好的习惯比学习高级技术更重要。

---

## 延伸阅读

- [CIS Benchmarks](https://www.cisecurity.org/cis-benchmarks) - 行业标准安全基线
- [Red Hat SELinux Guide](https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/9/html/using_selinux/index) - 官方 SELinux 文档
- [OWASP Threat Modeling](https://owasp.org/www-community/Threat_Modeling) - 威胁建模方法论
- 下一课：[02 - SSH 现代化加固](../02-ssh-hardening/) - 学习密钥认证、Fail2Ban、回滚演练
- 相关课程：[LX02 - 用户与权限](../../lx02-sysadmin/) - 复习 DAC 基础

---

## 系列导航

[系列首页](../) | [02 - SSH 现代化加固 -->](../02-ssh-hardening/)
