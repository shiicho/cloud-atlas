# 08 - nftables 深入：现代防火墙 / nftables Deep Dive: Modern Firewall

> **目标**：掌握 nftables 现代防火墙配置，理解连接跟踪的重要性  
> **前置**：完成 Lesson 01-07（安全原则、SSH、SELinux、auditd）  
> **时间**：2.5 小时  
> **实战场景**：生产服务器防火墙配置 + iptables 迁移  

---

## 将学到的内容

1. 理解 nftables 取代 iptables 的原因
2. 掌握 nftables 语法和结构（tables, chains, rules）
3. 配置常见防火墙规则（状态跟踪、端口过滤、IP 白名单）
4. 从 iptables 迁移到 nftables
5. **掌握 `nft -c -f` 配置验证（关键安全技能！）**

---

## 先跑起来！（5 分钟）

> 在学习理论之前，先看看你的服务器当前的防火墙状态。  

```bash
# 查看当前 nftables 规则集
sudo nft list ruleset

# 如果输出为空或报错，检查 iptables（旧系统）
sudo iptables -L -n -v 2>/dev/null | head -20

# 检查防火墙服务状态
systemctl status nftables 2>/dev/null || systemctl status firewalld 2>/dev/null

# 查看开放的端口
sudo ss -tulpn | grep LISTEN

# 检查系统使用的是 nftables 还是 iptables 后端
# RHEL 9 / Debian 11+ / Ubuntu 22.04+ 默认使用 nftables
cat /etc/os-release | grep -E 'NAME|VERSION'
```

**你刚刚检查了：**

- 系统有防火墙规则吗？（很多系统默认无规则！）
- 使用的是现代 nftables 还是旧的 iptables？
- 当前开放了哪些端口？
- 是否有状态跟踪规则？（`ct state` 相关）

**如果你的服务器 `nft list ruleset` 输出为空，那它对网络攻击几乎没有防护。**

现在让我们理解并配置现代防火墙。

---

## Step 1 - nftables vs iptables：为什么要迁移？（15 分钟）

### 1.1 iptables 的问题

iptables 诞生于 2001 年，在 Linux 防火墙领域服务了 20+ 年。但它有几个致命问题：

```
iptables 的设计缺陷：

1. 碎片化框架
   ├── iptables   → IPv4
   ├── ip6tables  → IPv6
   ├── arptables  → ARP
   └── ebtables   → 以太网桥

2. 非原子更新
   - 添加规则时可能有短暂的规则空窗期
   - 大量规则更新可能导致连接中断

3. 语法复杂
   - 每个协议需要单独的命令
   - 规则难以阅读和维护
```

### 1.2 nftables 的优势

nftables 从 Linux 3.13（2014年）开始引入，2019 年后逐渐成为主流：

| 特性 | iptables | nftables |
|------|----------|----------|
| 框架统一 | 4 个独立工具 | 1 个统一框架 |
| 规则更新 | 非原子 | **原子更新** |
| 语法 | 复杂、多命令 | 简洁、类似编程语言 |
| 性能 | 线性规则匹配 | 可优化的规则集 |
| 默认状态（2025） | **维护模式** | RHEL 9, Debian 11+, Ubuntu 22.04+ 默认 |

### 1.3 2025 年现状

```
主流发行版防火墙后端：

RHEL/Rocky/AlmaLinux 9+   → nftables（默认）
Debian 11+ (Bullseye)     → nftables（默认）
Ubuntu 22.04+ (Jammy)     → nftables（默认）
Fedora 32+                → nftables（默认）

RHEL/CentOS 7             → iptables（EOL: 2024-06-30）
Ubuntu 18.04/20.04        → iptables（向 nftables 过渡）
```

> **关键信息**：如果你在 2025 年还在用 iptables 配置新服务器，你需要立即升级技能。  

---

## Step 2 - nftables 结构（20 分钟）

### 2.1 核心概念：Tables, Chains, Rules

```
nftables 层级结构：

┌─────────────────────────────────────────────────────────────┐
│                        Ruleset                              │
│  ┌───────────────────────────────────────────────────────┐  │
│  │                    Table: inet filter                 │  │
│  │  ┌─────────────────────────────────────────────────┐  │  │
│  │  │              Chain: input                       │  │  │
│  │  │  ┌─────────────────────────────────────────┐    │  │  │
│  │  │  │ Rule: ct state established accept       │    │  │  │
│  │  │  ├─────────────────────────────────────────┤    │  │  │
│  │  │  │ Rule: tcp dport 22 accept               │    │  │  │
│  │  │  ├─────────────────────────────────────────┤    │  │  │
│  │  │  │ Rule: tcp dport {80, 443} accept        │    │  │  │
│  │  │  ├─────────────────────────────────────────┤    │  │  │
│  │  │  │ Rule: drop                              │    │  │  │
│  │  │  └─────────────────────────────────────────┘    │  │  │
│  │  └─────────────────────────────────────────────────┘  │  │
│  │  ┌─────────────────────────────────────────────────┐  │  │
│  │  │              Chain: output                      │  │  │
│  │  │  ...                                            │  │  │
│  │  └─────────────────────────────────────────────────┘  │  │
│  └───────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

<details>
<summary>View ASCII source</summary>

```
┌─────────────────────────────────────────────────────────────┐
│                        Ruleset                              │
│  ┌───────────────────────────────────────────────────────┐  │
│  │                    Table: inet filter                 │  │
│  │  ┌─────────────────────────────────────────────────┐  │  │
│  │  │              Chain: input                       │  │  │
│  │  │  ┌─────────────────────────────────────────────┐    │  │
│  │  │  │ Rule: ct state established accept       │    │  │
│  │  │  ├─────────────────────────────────────────┤    │  │
│  │  │  │ Rule: tcp dport 22 accept               │    │  │
│  │  │  ├─────────────────────────────────────────┤    │  │
│  │  │  │ Rule: tcp dport {80, 443} accept        │    │  │
│  │  │  ├─────────────────────────────────────────┤    │  │
│  │  │  │ Rule: drop                              │    │  │
│  │  │  └─────────────────────────────────────────┘    │  │
│  │  └─────────────────────────────────────────────────┘  │  │
│  │  ┌─────────────────────────────────────────────────┐  │  │
│  │  │              Chain: output                      │  │  │
│  │  │  ...                                            │  │  │
│  │  └─────────────────────────────────────────────────┘  │  │
│  └───────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

</details>

### 2.2 Table 地址族（Address Family）

| 族 | 描述 | 等价的 iptables |
|---|------|-----------------|
| `inet` | IPv4 + IPv6 | iptables + ip6tables |
| `ip` | 仅 IPv4 | iptables |
| `ip6` | 仅 IPv6 | ip6tables |
| `arp` | ARP 包 | arptables |
| `bridge` | 桥接包 | ebtables |
| `netdev` | 入口（ingress） | 无 |

> **推荐**：2025 年新配置应优先使用 `inet` 族，同时处理 IPv4 和 IPv6。  

### 2.3 Chain 类型和 Hooks

```bash
# Chain 定义语法
chain <name> {
    type <type> hook <hook> priority <priority>; policy <policy>;
}

# type 类型
# - filter: 过滤包（最常用）
# - route:  改变路由决策
# - nat:    NAT 转换

# hook 钩子点
# - prerouting:  包到达后，路由决策前
# - input:       发送到本机的包
# - forward:     转发的包
# - output:      本机产生的包
# - postrouting: 包离开前

# priority 优先级（数字越小越先执行）
# - filter 默认使用 0

# policy 默认策略
# - accept: 默认放行（不推荐）
# - drop:   默认丢弃（推荐）
```

### 2.4 完整数据包流程

```
                                    本地进程
                                       ▲
                                       │
         ┌─────────────────────────────┼─────────────────────────────┐
         │                             │                             │
         │                      ┌──────┴──────┐                      │
         │                      │   INPUT     │                      │
         │                      │   chain     │                      │
         │                      └──────┬──────┘                      │
         │                             │                             │
         │                      ┌──────┴──────┐                      │
         │                      │   Routing   │                      │
         │                      │   Decision  │                      │
         │                      └──────┬──────┘                      │
         │                             │                             │
         │     ┌───────────────────────┼───────────────────────┐     │
         │     │                       │                       │     │
         │     ▼                       │                       ▼     │
  ┌──────┴───────┐              ┌──────┴──────┐         ┌───────┴────────┐
  │  PREROUTING  │              │   FORWARD   │         │    OUTPUT      │
  │    chain     │              │    chain    │         │    chain       │
  └──────┬───────┘              └──────┬──────┘         └───────┬────────┘
         │                             │                        │
         │                             │                        │
         │                      ┌──────┴──────┐                 │
         │                      │ POSTROUTING │◀────────────────┘
         │                      │   chain     │
         │                      └──────┬──────┘
         │                             │
         │                             ▼
  ───────┴─────────────────────────────────────────────────────────────
                             网络接口
```

<details>
<summary>View ASCII source</summary>

```
                                    本地进程
                                       ▲
                                       │
         ┌─────────────────────────────┼─────────────────────────────┐
         │                             │                             │
         │                      ┌──────┴──────┐                      │
         │                      │   INPUT     │                      │
         │                      │   chain     │                      │
         │                      └──────┬──────┘                      │
         │                             │                             │
         │                      ┌──────┴──────┐                      │
         │                      │   Routing   │                      │
         │                      │   Decision  │                      │
         │                      └──────┬──────┘                      │
         │                             │                             │
         │     ┌───────────────────────┼───────────────────────┐     │
         │     │                       │                       │     │
         │     ▼                       │                       ▼     │
  ┌──────┴───────┐              ┌──────┴──────┐         ┌───────┴────────┐
  │  PREROUTING  │              │   FORWARD   │         │    OUTPUT      │
  │    chain     │              │    chain    │         │    chain       │
  └──────┬───────┘              └──────┬──────┘         └───────┬────────┘
         │                             │                        │
         │                             │                        │
         │                      ┌──────┴──────┐                 │
         │                      │ POSTROUTING │◀────────────────┘
         │                      │   chain     │
         │                      └──────┬──────┘
         │                             │
         │                             ▼
  ───────┴─────────────────────────────────────────────────────────────
                             网络接口
```

</details>

---

## Step 3 - 基础命令（20 分钟）

### 3.1 查看规则

```bash
# 查看完整规则集
sudo nft list ruleset

# 查看特定表
sudo nft list table inet filter

# 查看特定链
sudo nft list chain inet filter input

# 带句柄（handle）显示（用于删除规则）
sudo nft -a list ruleset
```

### 3.2 添加表和链

```bash
# 添加表（inet 支持 IPv4 + IPv6）
sudo nft add table inet filter

# 添加链（带 hook 和策略）
sudo nft add chain inet filter input \
    '{ type filter hook input priority 0; policy drop; }'

sudo nft add chain inet filter output \
    '{ type filter hook output priority 0; policy accept; }'
```

### 3.3 添加规则

```bash
# 放行已建立的连接（关键规则！）
sudo nft add rule inet filter input ct state established,related accept

# 放行本地回环
sudo nft add rule inet filter input iif "lo" accept

# 放行 SSH（端口 22）
sudo nft add rule inet filter input tcp dport 22 accept

# 放行 HTTP/HTTPS
sudo nft add rule inet filter input tcp dport { 80, 443 } accept

# 放行 ICMP（ping）
sudo nft add rule inet filter input ip protocol icmp accept
sudo nft add rule inet filter input ip6 nexthdr icmpv6 accept

# 记录并丢弃其他流量
sudo nft add rule inet filter input log prefix \"[nftables DROP] \" counter drop
```

### 3.4 删除规则

```bash
# 首先查看规则句柄
sudo nft -a list chain inet filter input
# 输出示例：
# chain input {
#     type filter hook input priority 0; policy drop;
#     ct state established,related accept # handle 4
#     tcp dport 22 accept # handle 5
#     tcp dport 8080 accept # handle 6   ← 要删除这条
# }

# 使用句柄删除规则
sudo nft delete rule inet filter input handle 6

# 清空整个链
sudo nft flush chain inet filter input

# 删除链（必须先清空）
sudo nft delete chain inet filter input

# 删除表
sudo nft delete table inet filter
```

### 3.5 持久化规则

```bash
# 导出当前规则到文件
sudo nft list ruleset > /etc/nftables.conf

# 从文件加载规则
sudo nft -f /etc/nftables.conf

# 启用 nftables 服务（开机自动加载）
sudo systemctl enable nftables

# 重新加载配置
sudo systemctl reload nftables
```

---

## Step 4 - 核心概念：连接跟踪 ct state（15 分钟）

### 4.1 为什么 ct state 如此重要？

```
没有连接跟踪的规则：

客户端 ──── SYN ────> 服务器:22 (允许)
客户端 <─── SYN+ACK ─ 服务器:22 (需要额外规则!)
客户端 ──── ACK ────> 服务器:22 (需要额外规则!)

问题：需要为每种包类型写规则，复杂且容易出错

有连接跟踪的规则：

客户端 ──── SYN ────> 服务器:22 (允许，创建连接跟踪)
客户端 <─── SYN+ACK ─ 服务器:22 (established，自动允许)
客户端 ──── ACK ────> 服务器:22 (established，自动允许)

优势：一条规则处理所有相关流量
```

### 4.2 连接状态说明

| 状态 | 描述 | 示例 |
|------|------|------|
| `new` | 新连接的第一个包 | TCP SYN 包 |
| `established` | 已建立连接的后续包 | 数据传输 |
| `related` | 与已有连接相关的新连接 | FTP 数据连接 |
| `invalid` | 不属于任何已知连接 | 应该丢弃 |
| `untracked` | 不被跟踪的包 | 特殊场景 |

### 4.3 正确的规则顺序

```bash
# 标准安全规则顺序（很重要！）

# 1. 首先处理已建立的连接（高频流量，快速放行）
ct state established,related accept

# 2. 丢弃无效包
ct state invalid drop

# 3. 放行本地回环
iif "lo" accept

# 4. 放行特定端口的新连接
tcp dport 22 ct state new accept
tcp dport { 80, 443 } ct state new accept

# 5. 可选：ICMP
ip protocol icmp accept

# 6. 最后：默认拒绝（通过 policy drop 实现）
```

### 4.4 反模式：无状态规则

```bash
# 错误：无状态规则（不推荐！）
sudo nft add rule inet filter input tcp dport 22 accept

# 问题：
# 1. 无法区分新连接和已有连接
# 2. 可能允许恶意构造的包
# 3. 无法正确处理 FTP、SIP 等复杂协议

# 正确：使用连接跟踪
sudo nft add rule inet filter input ct state established,related accept
sudo nft add rule inet filter input tcp dport 22 ct state new accept
```

---

## Step 5 - 生产级防火墙配置（30 分钟）

### 5.1 创建配置文件

```bash
# 备份现有配置
sudo cp /etc/nftables.conf /etc/nftables.conf.bak.$(date +%Y%m%d)

# 创建生产级配置
sudo tee /etc/nftables.conf << 'EOF'
#!/usr/sbin/nft -f
# =============================================================================
# nftables Production Configuration
# Created: 2025-01-04
# Reference: CIS Benchmark, RHEL Best Practices
# =============================================================================

# 清空现有规则
flush ruleset

# =============================================================================
# Table: inet filter (IPv4 + IPv6)
# =============================================================================
table inet filter {

    # -------------------------------------------------------------------------
    # Chain: input - 入站流量控制
    # -------------------------------------------------------------------------
    chain input {
        type filter hook input priority 0; policy drop;

        # 状态跟踪（核心规则！）
        ct state established,related accept comment "Allow established/related"
        ct state invalid drop comment "Drop invalid packets"

        # 本地回环
        iif "lo" accept comment "Allow loopback"

        # SSH（限制 IP 白名单）
        # 生产环境应修改为实际的管理 IP
        ip saddr { 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16 } tcp dport 22 accept comment "SSH from private networks"

        # Web 服务
        tcp dport { 80, 443 } accept comment "HTTP/HTTPS"

        # ICMP（限制类型和速率）
        ip protocol icmp icmp type { echo-request, echo-reply, destination-unreachable } limit rate 10/second accept comment "ICMP rate limited"
        ip6 nexthdr icmpv6 icmpv6 type { echo-request, echo-reply, nd-neighbor-solicit, nd-neighbor-advert } accept comment "ICMPv6 essential"

        # 日志并丢弃其他流量
        log prefix "[nftables DROP] " counter drop comment "Log and drop other traffic"
    }

    # -------------------------------------------------------------------------
    # Chain: forward - 转发流量控制（默认禁用）
    # -------------------------------------------------------------------------
    chain forward {
        type filter hook forward priority 0; policy drop;

        # 如果是路由器/网关，在此添加规则
        # ct state established,related accept
        # ...
    }

    # -------------------------------------------------------------------------
    # Chain: output - 出站流量控制
    # -------------------------------------------------------------------------
    chain output {
        type filter hook output priority 0; policy accept;

        # 大多数场景不限制出站流量
        # 高安全环境可以限制：
        # ct state established,related accept
        # tcp dport { 53, 80, 443 } accept
        # udp dport 53 accept
        # drop
    }
}

# =============================================================================
# 可选：自定义 sets（IP 白名单）
# =============================================================================
# table inet filter {
#     set trusted_ips {
#         type ipv4_addr
#         flags interval
#         elements = { 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16 }
#     }
#
#     chain input {
#         ...
#         ip saddr @trusted_ips tcp dport 22 accept
#     }
# }
EOF
```

### 5.2 配置验证（关键步骤！）

> **这是本课最重要的技能：在应用配置之前验证语法。**  

```bash
# 验证配置语法（-c = check，-f = file）
sudo nft -c -f /etc/nftables.conf

# 如果有错误会显示：
# /etc/nftables.conf:25:9-15: Error: syntax error, unexpected string
#         invalid rule here
#         ^^^^^^^

# 如果没有输出 = 配置正确
echo "Configuration syntax is valid!"

# 验证后应用配置
sudo nft -f /etc/nftables.conf

# 验证应用结果
sudo nft list ruleset | head -30
```

### 5.3 安全应用流程

> **黄金法则**：修改防火墙配置时，**永远保持当前 SSH 会话打开**！  

```bash
# 1. 在当前终端执行，但不要关闭这个终端！
sudo nft -c -f /etc/nftables.conf
sudo nft -f /etc/nftables.conf

# 2. 打开新终端测试连接
# ssh user@server
# 如果新连接成功，才关闭旧终端

# 3. 如果出问题，在旧终端恢复：
sudo nft flush ruleset
# 或
sudo nft -f /etc/nftables.conf.bak.*

# 4. 启用服务持久化
sudo systemctl enable nftables
sudo systemctl reload nftables
```

### 5.4 设置自动恢复（可选，激进做法）

```bash
# 测试环境：每 5 分钟自动恢复防火墙规则
(crontab -l 2>/dev/null; echo "*/5 * * * * /usr/sbin/nft -f /etc/nftables.conf.safe") | crontab -

# 测试完成后移除
crontab -l | grep -v nftables.conf.safe | crontab -
```

---

## Step 6 - 常见规则示例（20 分钟）

### 6.1 IP 白名单

```bash
# 方法 1：直接在规则中
sudo nft add rule inet filter input ip saddr { 10.0.0.1, 10.0.0.2, 10.0.0.3 } accept

# 方法 2：使用 set（推荐，易于管理）
sudo nft add table inet filter
sudo nft add set inet filter trusted_ips '{ type ipv4_addr; flags interval; }'
sudo nft add element inet filter trusted_ips '{ 10.0.0.0/8, 192.168.1.0/24 }'
sudo nft add rule inet filter input ip saddr @trusted_ips accept

# 动态管理 set
sudo nft add element inet filter trusted_ips '{ 203.0.113.50 }'
sudo nft delete element inet filter trusted_ips '{ 203.0.113.50 }'
```

### 6.2 端口范围

```bash
# 单个端口
tcp dport 22 accept

# 多个端口
tcp dport { 22, 80, 443, 8080 } accept

# 端口范围
tcp dport 3000-3100 accept

# UDP 端口
udp dport 53 accept
```

### 6.3 速率限制

```bash
# 限制 SSH 连接速率（防暴力破解）
tcp dport 22 ct state new limit rate 3/minute accept

# 限制 ICMP（防 ping flood）
ip protocol icmp limit rate 10/second accept

# 更复杂的速率限制
tcp dport 22 meter ssh-meter { ip saddr limit rate 3/minute burst 5 packets } accept
```

### 6.4 日志记录

```bash
# 基本日志
log prefix "[nftables] " drop

# 带速率限制的日志（防止日志洪水）
log prefix "[nftables DROP] " limit rate 3/minute drop

# 日志组（供其他工具处理）
log prefix "[nftables] " group 0 drop

# 查看日志
sudo journalctl -k | grep nftables
# 或
sudo dmesg | grep nftables
```

### 6.5 高级匹配

```bash
# 匹配网络接口
iif "eth0" tcp dport 80 accept
oif "eth1" accept

# 匹配源/目标地址
ip saddr 192.168.1.0/24 ip daddr 10.0.0.1 accept

# 匹配 TCP 标志
tcp flags syn tcp dport 80 accept

# 匹配时间（需要 nftables 0.9.4+）
# meta hour >= 09:00 meta hour < 18:00 accept
```

---

## Step 7 - iptables 迁移（20 分钟）

### 7.1 使用 iptables-translate

```bash
# 安装翻译工具（如果没有）
# RHEL/CentOS: dnf install iptables-nft
# Debian/Ubuntu: apt install iptables-nft

# 翻译单条规则
iptables-translate -A INPUT -p tcp --dport 22 -j ACCEPT
# 输出: nft add rule ip filter INPUT tcp dport 22 counter accept

# 翻译整个规则集
iptables-save > iptables-rules.txt
iptables-restore-translate < iptables-rules.txt > nftables-rules.nft

# 验证翻译结果
cat nftables-rules.nft
```

### 7.2 翻译示例

原 iptables 规则：

```bash
# iptables-rules.txt
*filter
:INPUT DROP [0:0]
:FORWARD DROP [0:0]
:OUTPUT ACCEPT [0:0]
-A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
-A INPUT -i lo -j ACCEPT
-A INPUT -p tcp --dport 22 -j ACCEPT
-A INPUT -p tcp -m multiport --dports 80,443 -j ACCEPT
-A INPUT -p icmp -j ACCEPT
-A INPUT -j LOG --log-prefix "[iptables DROP] "
COMMIT
```

翻译后的 nftables 规则：

```bash
# nftables-rules.nft
table ip filter {
    chain INPUT {
        type filter hook input priority 0; policy drop;
        ct state established,related counter accept
        iif "lo" counter accept
        tcp dport 22 counter accept
        tcp dport { 80, 443 } counter accept
        ip protocol icmp counter accept
        counter log prefix "[iptables DROP] "
    }

    chain FORWARD {
        type filter hook forward priority 0; policy drop;
    }

    chain OUTPUT {
        type filter hook output priority 0; policy accept;
    }
}
```

### 7.3 迁移检查清单

```bash
# 1. 导出现有 iptables 规则
iptables-save > /tmp/iptables-backup.txt
ip6tables-save > /tmp/ip6tables-backup.txt

# 2. 翻译规则
iptables-restore-translate < /tmp/iptables-backup.txt > /tmp/nft-rules.nft

# 3. 验证翻译结果
sudo nft -c -f /tmp/nft-rules.nft

# 4. 应用新规则（保持旧会话！）
sudo nft -f /tmp/nft-rules.nft

# 5. 测试连接

# 6. 禁用 iptables 服务
sudo systemctl disable iptables
sudo systemctl disable ip6tables

# 7. 启用 nftables 服务
sudo systemctl enable nftables
```

### 7.4 双栈共存问题

```bash
# 检查当前后端
# RHEL 9 默认使用 nftables 后端
iptables -V
# 输出: iptables v1.8.x (nf_tables)  ← 说明使用 nftables 后端

# 如果显示 "legacy"，建议切换
# update-alternatives --set iptables /usr/sbin/iptables-nft
```

---

## Step 8 - firewalld 对比（10 分钟）

### 8.1 firewalld 与 nftables 的关系

```
           ┌─────────────┐
           │  firewalld  │  ← 高层 API
           └──────┬──────┘
                  │
                  ▼
           ┌─────────────┐
           │  nftables   │  ← 底层后端（RHEL 9+）
           └──────┬──────┘
                  │
                  ▼
           ┌─────────────┐
           │   Netfilter │  ← 内核
           └─────────────┘
```

### 8.2 何时使用哪个？

| 场景 | 推荐 | 原因 |
|------|------|------|
| 桌面/简单服务器 | firewalld | Zone 概念易懂 |
| 复杂规则/高性能 | nftables | 更精细控制 |
| 容器/Kubernetes | nftables | 直接控制 |
| 旧系统维护 | iptables | 兼容性 |
| 新系统部署 | nftables | 现代标准 |

### 8.3 firewalld 基础命令

```bash
# 查看状态
sudo firewall-cmd --state
sudo firewall-cmd --list-all

# 开放端口
sudo firewall-cmd --add-port=80/tcp --permanent
sudo firewall-cmd --add-service=https --permanent
sudo firewall-cmd --reload

# 查看底层 nftables 规则
sudo nft list ruleset | grep -A10 "firewalld"
```

### 8.4 注意：不要混用！

```bash
# 警告：firewalld 和直接 nftables 规则可能冲突

# 如果使用 firewalld，让它管理所有规则
# 不要同时手动添加 nftables 规则

# 如果使用纯 nftables，禁用 firewalld
sudo systemctl disable --now firewalld
sudo systemctl enable --now nftables
```

---

## 反模式：常见错误

### 错误 1：0.0.0.0/0 开放管理端口

```bash
# 危险！允许任何 IP 访问 SSH
tcp dport 22 accept

# 正确：限制来源 IP
ip saddr { 10.0.0.0/8, 192.168.0.0/16 } tcp dport 22 accept

# 或使用 IP 白名单 set
ip saddr @trusted_ips tcp dport 22 accept
```

### 错误 2：无状态规则

```bash
# 错误：没有连接跟踪
tcp dport 80 accept

# 正确：使用 ct state
ct state established,related accept
tcp dport 80 ct state new accept
```

### 错误 3：修改配置不验证就应用

```bash
# 危险！可能锁死 SSH
sudo vim /etc/nftables.conf
sudo nft -f /etc/nftables.conf    # ← 没有验证

# 正确做法
sudo vim /etc/nftables.conf
sudo nft -c -f /etc/nftables.conf  # ← 先验证语法
sudo nft -f /etc/nftables.conf     # ← 再应用
```

### 错误 4：忘记持久化

```bash
# 规则只在内存中，重启后丢失
sudo nft add rule inet filter input tcp dport 80 accept

# 正确：保存到文件
sudo nft list ruleset > /etc/nftables.conf
sudo systemctl enable nftables
```

### 错误 5：日志洪水

```bash
# 危险：每个丢弃的包都记录，可能填满磁盘
log prefix "[DROP] " drop

# 正确：限制日志速率
log prefix "[DROP] " limit rate 3/minute drop
```

---

## 职场小贴士（Japan IT Context）

### 防火墙管理在日本企业

| 日语术语 | 含义 | 技术实现 |
|----------|------|----------|
| ファイアウォール | 防火墙 | nftables/firewalld |
| 接続許可 | 连接许可 | accept 规则 |
| 接続拒否 | 连接拒绝 | drop/reject 规则 |
| アクセス制御 | 访问控制 | IP 白名单 |
| ポート開放 | 端口开放 | dport 规则 |
| 変更管理 | 变更管理 | 配置备份、审批流程 |

### 日本企业防火墙管理常见问题

1. **変更管理不足**：规则变更没有记录
   - 解决：使用 Git 管理配置文件 + 变更审批

2. **テスト環境がない**：直接在生产环境测试
   - 解决：先在测试环境验证规则

3. **全開放状態**：安全意识不足，规则过于宽松
   - 解决：最小权限原则，定期审计规则

### 防火墙变更申请模板

```markdown
## ファイアウォール変更申請書

### 申請日: 20XX年XX月XX日
### 申請者: 田中太郎
### 対象サーバー: production-web-01

### 変更内容
| 項目 | 現在 | 変更後 |
|------|------|--------|
| ポート 8080 | 拒否 | 許可（内部 IP のみ） |

### 変更理由
新規 API サービスの導入に伴い、内部ネットワークからのアクセスを許可する必要がある。

### セキュリティ影響評価
- 外部アクセス: 影響なし（内部 IP のみ許可）
- 既存サービス: 影響なし

### テスト計画
1. ステージング環境でルール確認
2. 本番環境適用後、接続テスト

### 承認
- [ ] セキュリティ担当: _________
- [ ] インフラ担当: _________
- [ ] 上長: _________
```

---

## 检查清单

完成本课后，你应该能够：

- [ ] 解释 nftables 取代 iptables 的原因（统一框架、原子更新、更清晰语法）
- [ ] 使用 `nft list ruleset` 查看当前规则
- [ ] 创建表、链、规则
- [ ] 理解 ct state 连接跟踪的重要性
- [ ] 配置 SSH IP 白名单规则
- [ ] **使用 `nft -c -f` 验证配置语法**
- [ ] 使用 `iptables-translate` 迁移旧规则
- [ ] 理解 firewalld 和 nftables 的关系
- [ ] 安全地应用防火墙变更（保持旧会话、验证后应用）

---

## 本课小结

| 概念 | 命令/配置 | 记忆点 |
|------|-----------|--------|
| 查看规则 | `nft list ruleset` | 包含所有表、链、规则 |
| 验证配置 | `nft -c -f file.conf` | **必须在应用前执行！** |
| 应用配置 | `nft -f file.conf` | 保持旧会话打开 |
| 连接跟踪 | `ct state established,related` | 核心安全规则 |
| IP 白名单 | `ip saddr @set_name accept` | 使用 set 便于管理 |
| 持久化 | `/etc/nftables.conf` + `systemctl enable` | 重启不丢失 |
| 迁移 | `iptables-translate` | 自动翻译规则 |

**黄金法则**：

```
验证前不应用 → ct state 是核心 → IP 白名单限制管理端口 → 保持后门会话
```

---

## 延伸阅读

- [nftables Wiki](https://wiki.nftables.org/) - 官方文档和示例
- [Red Hat nftables Guide](https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/9/html/configuring_firewalls_and_packet_filters/) - RHEL 9 官方指南
- [Netfilter Project](https://netfilter.org/) - 内核防火墙项目
- [CIS Benchmark for Linux](https://www.cisecurity.org/benchmark/red_hat_linux) - 合规基线
- 相关课程：[Lesson 02 - SSH 加固](../02-ssh-hardening/) - 防火墙配合 SSH 安全
- 相关课程：[Lesson 07 - auditd 审计](../07-auditd/) - 记录防火墙变更

---

## 系列导航

[上一课：07 - auditd 审计系统](../07-auditd/) | [系列首页](../) | [下一课：09 - PAM 高级配置 ->](../09-pam-advanced/)
