# 01 · 网络拓扑与安全基础（端口/防火墙/服务账户）

> **目标**：掌握 HULFT 网络配置和企业级安全设计
> **前置**：[00 · HULFT 概念与架构](../00-concepts/)
> **适用**：日本 SIer/银行 IT 岗位面试准备
> **时长**：约 45 分钟

## 将完成的内容

1. 理解 HULFT 端口号（8594/8500/25421）及用途
2. 配置符合银行安全标准的服务账户
3. 设计单向/双向防火墙规则
4. 避免 NAT Hairpin 问题

---

## Step 1 — HULFT 端口配置

### 核心端口

HULFT 使用以下端口进行通信：

| 端口 | 用途 | 协议 | 说明 |
|------|------|------|------|
| **8594** | Control Channel | TCP | 控制通道（默认，可配置） |
| **8500** | Data Channel | TCP | 数据传输通道 |
| **25421** | HULFT Manager | TCP | Web GUI 管理界面（可选） |

### 端口通信流程

```
┌─────────────────┐                           ┌─────────────────┐
│   Node A        │                           │   Node B        │
│                 │                           │                 │
│  ┌───────────┐  │    8594 (Control)         │  ┌───────────┐  │
│  │  Engine   │──┼──────────────────────────→│  │  Engine   │  │
│  │           │  │                           │  │           │  │
│  │           │──┼──────────────────────────→│  │           │  │
│  └───────────┘  │    8500 (Data)            │  └───────────┘  │
│                 │                           │                 │
│  ┌───────────┐  │                           │                 │
│  │  Manager  │  │    25421 (Web GUI)        │                 │
│  │  (可选)   │←─┼─── 管理员浏览器访问 ───────┼─────────────────│
│  └───────────┘  │                           │                 │
└─────────────────┘                           └─────────────────┘
```

### 重要注意事项

```
⚠️ Control 和 Data 通道都需要双向 TCP 连接！

   原因：
   - 发送方需要接收 ACK 确认
   - 重试机制需要双向通信
   - 序列号/去重检查依赖双向握手

   常见错误：只开单向防火墙，导致：
   - 发送方永远等待确认
   - 传输卡住或超时
```

> 💡 **面试要点 #1**
>
> **问题**：「HULFTで開放すべきポートは何ですか？また、DMZからCoreへの一方向フローに対して、ファイアウォールルールをどのように設定しますか？」
>
> （中文参考：HULFT 需要开放哪些端口？如何为 DMZ→Core 单向流配置防火墙规则？）
>
> **期望回答**：
> - 端口：8594（Control）、8500（Data）
> - DMZ→Core 单向流：只在 Core 开放从 DMZ 的入站
> - 使用**集信（Pull）**模式，Core 发起连接，无需向 DMZ 开放入站
> - 指定源 IP，用变更工单记录所有规则

---

## Step 2 — 服务账户配置

### 日本银行标准命名规范

日本银行环境通常要求非登录系统账户：

```bash
# 推荐配置
用户名: hulftsvc / hulftusr / hulft
Shell:  /sbin/nologin          # 禁止交互登录
Group:  hulft
Home:   /opt/hulft
```

### 创建服务账户

```bash
# 创建 hulft 组
groupadd hulft

# 创建服务账户（非登录）
useradd -r \
  -s /sbin/nologin \
  -d /opt/hulft \
  -g hulft \
  -c "HULFT Service Account" \
  hulftsvc
```

### Sudo 权限范围（最小权限原则）

**只授予必要的权限：**

```bash
# /etc/sudoers.d/hulft
# HULFT 服务账户 sudo 配置

# 只允许启停操作
hulftsvc ALL=(root) NOPASSWD: /opt/hulft8/bin/hulstart
hulftsvc ALL=(root) NOPASSWD: /opt/hulft8/bin/hulstop

# 只允许读取日志
hulftsvc ALL=(root) NOPASSWD: /bin/cat /opt/hulft8/log/*
hulftsvc ALL=(root) NOPASSWD: /bin/tail /opt/hulft8/log/*

# 禁止：写入配置文件（需要审批流程）
# 禁止：安装/升级（需要变更管理）
```

### 为什么不用 root？

| 用 root 运行 | 用专用账户运行 |
|--------------|----------------|
| 安全审计失败 | 符合审计要求 |
| 权限过大 | 最小权限原则 |
| 无法追踪操作 | 可审计操作日志 |
| 银行不接受 | 银行标准配置 |

> 💡 **面试要点 #2**
>
> **问题**：「銀行環境でHULFT用のサービスアカウントをどのように設定することを推奨しますか？」
>
> （中文参考：在银行环境中，你会如何推荐配置 HULFT 的服务账户？）
>
> **期望回答**：
> - 非登录系统账户（shell: `/sbin/nologin`）
> - 专用组（hulft）
> - **只授权启停操作的 sudo**
> - 启用审计日志
> - 配置变更需要走审批流程

---

## Step 3 — 防火墙规则设计

### 场景 1：单向集信（Pull）模式

**最安全的设计** — DMZ→Core，Core 发起连接：

```
┌─────────────────────────────────────────────────────────────────┐
│                    单向集信（Pull）模式                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│   DMZ HULFT                              Core HULFT             │
│   ┌─────────┐                            ┌─────────┐           │
│   │         │ ←───────────────────────── │         │           │
│   │  等待   │      Core 发起连接          │  主动   │           │
│   │  被拉取 │      (集信)                 │  拉取   │           │
│   └─────────┘                            └─────────┘           │
│       ↑                                      │                  │
│       │                                      │                  │
│   无需入站规则                          出站到 DMZ              │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

**AWS Security Group 配置：**

```
# Core Security Group (核心系统)
Outbound: TCP 8594, 8500 → DMZ Security Group

# DMZ Security Group
Inbound:  TCP 8594, 8500 ← Core Security Group ONLY
```

**传统防火墙规则：**

```
# Core → DMZ (出站)
iptables -A OUTPUT -p tcp -d <DMZ_IP> --dport 8594 -j ACCEPT
iptables -A OUTPUT -p tcp -d <DMZ_IP> --dport 8500 -j ACCEPT

# 响应流量（已建立连接）
iptables -A INPUT -p tcp --sport 8594 -m state --state ESTABLISHED -j ACCEPT
iptables -A INPUT -p tcp --sport 8500 -m state --state ESTABLISHED -j ACCEPT
```

### 场景 2：双向通信

**当需要双向 Push/Pull 时：**

```
# 双方都需要开放
Node A ←→ Node B

# Security Group 配置
Node A Inbound:  TCP 8594, 8500 ← Node B
Node A Outbound: TCP 8594, 8500 → Node B

Node B Inbound:  TCP 8594, 8500 ← Node A
Node B Outbound: TCP 8594, 8500 → Node A
```

### 最佳实践

```
✅ 推荐做法：
   • 使用集信（Pull）从安全区域拉取，避免入站开放
   • 指定具体源 IP，不要用 ANY
   • 所有规则用变更工单号记录
   • 定期审计防火墙规则

❌ 避免：
   • 开放 0.0.0.0/0 到 HULFT 端口
   • 公网暴露 8594/8500
   • 没有文档的防火墙规则
```

---

## Step 4 — NAT Hairpin 问题与解决

### 什么是 NAT Hairpin？

当两个 HULFT 节点位于同一防火墙后，使用公网 IP 互访时：

```
┌─────────────────────────────────────────────────────────────────┐
│                      NAT Hairpin 问题                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│   ┌─────────┐                          ┌─────────┐             │
│   │ Node A  │                          │ Node B  │             │
│   │ 内网 IP │                          │ 内网 IP │             │
│   │ 10.0.1.5│                          │10.0.1.6 │             │
│   └────┬────┘                          └────┬────┘             │
│        │                                    │                   │
│        │      ┌──────────────┐              │                   │
│        └──────│   防火墙/NAT  │──────────────┘                   │
│               │              │                                  │
│               │  公网 IP     │                                  │
│               │  1.2.3.4     │                                  │
│               └──────────────┘                                  │
│                                                                 │
│   问题：Node A 访问 1.2.3.4 → 绕回同一防火墙                     │
│   结果：                                                        │
│   • Control 通道建立                                            │
│   • Data 通道被阻断或 PAT 破坏会话                               │
│   • 序列号/ACK 路径错乱                                         │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 解决方案

**方案 1：Split DNS（分离 DNS）**

```
# 外部 DNS
hulft-node-b.example.com → 1.2.3.4 (公网 IP)

# 内部 DNS
hulft-node-b.example.com → 10.0.1.6 (内网 IP)
```

**方案 2：/etc/hosts 覆盖**

```bash
# Node A 的 /etc/hosts
10.0.1.6    hulft-node-b    hulft-node-b.example.com

# Node B 的 /etc/hosts
10.0.1.5    hulft-node-a    hulft-node-a.example.com
```

**方案 3：HULFT 配置使用内网 IP**

```
# HULFT 节点定义（hlmtable.tbl）
# 直接使用内网 IP，不要用公网 IP 或可能解析到公网的主机名
NODE_B    10.0.1.6    8594
```

### 排查步骤

在安装 HULFT 之前，用 netcat 测试连通性：

```bash
# 在 Node B 上监听
nc -l 8594

# 在 Node A 上连接（使用你计划配置的地址）
nc -v 10.0.1.6 8594

# 如果失败，检查：
# 1. 是否经过 NAT hairpin？
# 2. 防火墙是否允许？
# 3. 路由是否正确？
```

> 💡 **面试要点 #3**
>
> **问题**：「両方のノードが同じファイアウォールの背後にある場合、NAT Hairpin問題をどのように回避しますか？」
>
> （中文参考：当两个节点位于同一防火墙后时，如何避免 NAT Hairpin 问题？）
>
> **期望回答**：
> - 使用 Split DNS 或 `/etc/hosts` 解析到**内网 IP**
> - HULFT 节点定义中**不要使用公网 IP**
> - 安装前用 netcat 测试验证路径
> - 多租户数据中心常见此问题

---

## Step 5 — NTP 时间同步

### 为什么重要？

```
⚠️ HULFT 依赖时间戳进行：
   • 日志关联分析
   • 重试超时计算
   • RC 代码时序判断
   • 审计追踪

   节点间时间偏差 > 几秒 → 可能导致：
   • 超时判断错误
   • 日志时序混乱
   • 排障困难
```

### 配置检查

```bash
# 检查 NTP 同步状态
timedatectl status

# 查看时间偏差
chronyc tracking

# 手动同步（如需要）
sudo chronyc makestep
```

### 验证两节点时间

```bash
# 在两个节点上同时执行
date +"%Y-%m-%d %H:%M:%S.%N"

# 偏差应小于 1 秒
```

---

## 实践练习

### 练习 1：设计防火墙规则

**场景**：设计 DMZ→Core 的防火墙规则

```
要求：
• DMZ 节点 IP: 10.0.2.100
• Core 节点 IP: 10.0.1.50
• 使用集信（Pull）模式
• 写出 AWS Security Group 规则
```

<details>
<summary>点击查看参考答案</summary>

```
# Core Security Group
Inbound Rules:
  - Type: Custom TCP
    Port: 8594
    Source: 10.0.2.100/32 (DMZ)
    Description: HULFT control from DMZ

  - Type: Custom TCP
    Port: 8500
    Source: 10.0.2.100/32 (DMZ)
    Description: HULFT data from DMZ

# DMZ Security Group
Outbound Rules:
  - Type: Custom TCP
    Port: 8594
    Destination: 10.0.1.50/32 (Core)
    Description: HULFT control to Core

  - Type: Custom TCP
    Port: 8500
    Destination: 10.0.1.50/32 (Core)
    Description: HULFT data to Core
```

注意：使用集信模式，DMZ 不需要入站规则！

</details>

### 练习 2：服务账户配置

**场景**：编写服务账户创建脚本

```bash
# 要求：
# 1. 创建 hulft 组
# 2. 创建 hulftsvc 用户（非登录）
# 3. 配置 sudo 只允许启停
```

<details>
<summary>点击查看参考答案</summary>

```bash
#!/bin/bash
# setup-hulft-account.sh

# 创建组
groupadd -f hulft

# 创建用户
useradd -r \
  -s /sbin/nologin \
  -d /opt/hulft \
  -g hulft \
  -c "HULFT Service Account" \
  hulftsvc 2>/dev/null || echo "User exists"

# 配置 sudo
cat > /etc/sudoers.d/hulft << 'EOF'
# HULFT Service Account Permissions
hulftsvc ALL=(root) NOPASSWD: /opt/hulft8/bin/hulstart
hulftsvc ALL=(root) NOPASSWD: /opt/hulft8/bin/hulstop
EOF

chmod 440 /etc/sudoers.d/hulft

echo "HULFT service account configured"
```

</details>

---

## 常见错误

| 错误 | 后果 | 预防 |
|------|------|------|
| 单向防火墙以为双向 | 发送方永远等待，传输卡住 | 明确双向规则或用集信 |
| NAT/PAT 重写不一致 | 序列错误，连接卡死 | 使用内网 IP 配置 |
| 用 root 运行 HULFT | 安全审计失败 | 使用专用服务账户 |
| 忘记 NTP 同步 | 超时计算错误，日志混乱 | 配置 chrony/ntpd |
| 公网暴露端口 | 安全风险 | 私有子网 + VPN/DX |

---

## 小结

| 主题 | 要点 |
|------|------|
| 端口 | 8594 (Control) + 8500 (Data)，双向 TCP |
| 服务账户 | 非登录、专用组、最小 sudo 权限 |
| 防火墙 | 集信模式最安全，指定源 IP |
| NAT Hairpin | 使用内网 IP，Split DNS |
| NTP | 节点间时间同步 < 1 秒 |

---

## 下一步

完成本课后，请继续：

- **[02 · HULFT 安装与基本配置](../02-installation/)** — 搭建双节点 Lab 环境

---

## 系列导航 / Series Nav

| 课程 | 主题 |
|------|------|
| 00 · 概念与架构 | Store-and-Forward, 术语 |
| **01 · 网络与安全** | ← 当前课程 |
| 02 · 安装配置 | HULFT8 双节点 Lab |
| 03 · 字符编码 | SJIS↔UTF-8, EBCDIC |
| 04 · 集信/配信实战 | 传输组、重试机制 |
| 05 · 作业联动 | JP1 集成、日志分析 |
| 06 · 云迁移 | HULFT Square, AWS VPC |
