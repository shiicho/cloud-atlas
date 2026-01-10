# 06 - nftables 基础（nftables Basics）

> **目标**：理解 nftables 防火墙架构，配置基本过滤规则  
> **前置**：完成 Lesson 05（套接字检查 ss）  
> **时间**：⚡ 15 分钟（速读）/ 🔬 60 分钟（完整实操）  
> **环境**：RHEL 9 / AlmaLinux 9 / Ubuntu 22.04+（nftables 默认启用）  

---

## 将学到的内容

1. 理解 nftables 架构（families、tables、chains、rules）
2. 使用 `nft` 命令查看和管理规则
3. 创建基本过滤规则（允许 SSH、HTTP）
4. 理解状态防火墙（`ct state`）的重要性
5. 从 iptables 迁移到 nftables

---

## Step 1 - 先跑起来：查看防火墙状态（10 分钟）

> 在学习理论之前，先看看你的服务器防火墙状态。  

```bash
# 查看当前 nftables 规则
sudo nft list ruleset

# 检查 nftables 服务状态
systemctl status nftables

# 如果规则为空，检查是否用了 firewalld
systemctl status firewalld 2>/dev/null

# 查看当前开放的端口
ss -tulpn | grep LISTEN
```

**你刚刚检查了**：

- 系统有防火墙规则吗？（很多系统默认无规则！）
- 使用的是 nftables 还是 firewalld？
- 当前开放了哪些端口？

**如果 `nft list ruleset` 输出为空，你的服务器对网络攻击几乎没有防护。**

现在让我们理解并配置现代防火墙。

---

## Step 1 - 发生了什么？nftables 架构（15 分钟）

### 1.1 为什么用 nftables 而不是 iptables？

iptables 诞生于 2001 年，服务了 Linux 20+ 年。但它有几个问题：

| 问题 | iptables | nftables |
|------|----------|----------|
| 框架碎片化 | 4 个工具（iptables/ip6tables/arptables/ebtables） | 1 个统一框架 |
| 规则更新 | 非原子（有短暂空窗期） | **原子更新** |
| 语法 | 复杂、每个协议不同 | 简洁、类似编程语言 |
| 默认状态（2026） | **维护模式** | RHEL 9, Debian 11+, Ubuntu 22.04+ 默认 |

**2026 年现状**：

```
主流发行版防火墙后端：

RHEL/Rocky/AlmaLinux 9+   → nftables（默认）
Debian 11+ (Bullseye)     → nftables（默认）
Ubuntu 22.04+ (Jammy)     → nftables（默认）
Fedora 32+                → nftables（默认）

RHEL/CentOS 7             → iptables（EOL: 2024-06-30）
```

> **如果你在 2026 年还用 iptables 配置新服务器，需要升级技能了。**  

### 1.2 nftables 层级结构

<!-- DIAGRAM: nftables-architecture -->
```
nftables 层级结构：

┌─────────────────────────────────────────────────────────────────┐
│                          Ruleset                                 │
│                        (整个规则集)                              │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │                   Table: inet filter                       │  │
│  │                  (表：inet 家族，名为 filter)              │  │
│  │  ┌─────────────────────────────────────────────────────┐  │  │
│  │  │                Chain: input                         │  │  │
│  │  │              (链：处理入站流量)                      │  │  │
│  │  │  ┌───────────────────────────────────────────────┐  │  │  │
│  │  │  │ Rule: ct state established,related accept     │  │  │  │
│  │  │  ├───────────────────────────────────────────────┤  │  │  │
│  │  │  │ Rule: tcp dport 22 accept                     │  │  │  │
│  │  │  ├───────────────────────────────────────────────┤  │  │  │
│  │  │  │ Rule: tcp dport { 80, 443 } accept            │  │  │  │
│  │  │  ├───────────────────────────────────────────────┤  │  │  │
│  │  │  │ Rule: drop                                    │  │  │  │
│  │  │  └───────────────────────────────────────────────┘  │  │  │
│  │  └─────────────────────────────────────────────────────┘  │  │
│  │  ┌─────────────────────────────────────────────────────┐  │  │
│  │  │                Chain: output                        │  │  │
│  │  │              (链：处理出站流量)                      │  │  │
│  │  └─────────────────────────────────────────────────────┘  │  │
│  └───────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```
<!-- /DIAGRAM -->

**层级关系**：

| 层级 | 说明 | 类比 |
|------|------|------|
| **Ruleset** | 整个防火墙配置 | 整栋大楼 |
| **Table** | 规则的容器，指定地址族 | 楼层 |
| **Chain** | 规则链，指定 hook 点 | 房间 |
| **Rule** | 具体的过滤规则 | 家具 |

### 1.3 地址族（Address Family）

| 族 | 描述 | 等价的 iptables |
|---|------|-----------------|
| `inet` | IPv4 + IPv6（推荐） | iptables + ip6tables |
| `ip` | 仅 IPv4 | iptables |
| `ip6` | 仅 IPv6 | ip6tables |
| `arp` | ARP 包 | arptables |
| `bridge` | 桥接包 | ebtables |

> **推荐**：2026 年新配置应优先使用 `inet` 族，同时处理 IPv4 和 IPv6。  

### 1.4 Chain 的 Hook 点

<!-- DIAGRAM: nftables-hooks -->
```
数据包流经的 Hook 点：

                                    本地进程
                                       ▲ │
                                       │ │
                          ┌────────────┘ └────────────┐
                          │                           │
                   ┌──────┴──────┐             ┌──────┴──────┐
                   │   INPUT     │             │   OUTPUT    │
                   │   (入站)    │             │   (出站)    │
                   └──────┬──────┘             └──────┬──────┘
                          ▲                           │
                          │                           ▼
                   ┌──────┴──────┐             ┌──────┴──────┐
                   │   Routing   │             │  POSTROUTING│
                   │   Decision  │             │   (出口)    │
                   └──────┬──────┘             └──────┬──────┘
                          ▲                           │
                          │                           ▼
  ───────────────────────────────────────────────────────────────
          网络接口入口                    网络接口出口
               ▲                              │
               │                              ▼
        ┌──────┴──────┐                ┌──────┴──────┐
        │ PREROUTING  │                │  FORWARD    │
        │   (入口)    │                │   (转发)    │
        └─────────────┘                └─────────────┘
```
<!-- /DIAGRAM -->

**常用 Hook**：

| Hook | 用途 | 示例 |
|------|------|------|
| `input` | 控制进入本机的流量 | 允许 SSH 连接 |
| `output` | 控制从本机发出的流量 | 限制出站访问 |
| `forward` | 控制转发流量（路由器） | NAT 网关 |

---

## Step 2 - nft 命令基础（15 分钟）

### 2.1 查看规则

```bash
# 查看完整规则集
sudo nft list ruleset

# 查看特定表
sudo nft list table inet filter

# 查看特定链
sudo nft list chain inet filter input

# 带句柄（handle）显示 - 用于删除规则
sudo nft -a list ruleset
```

### 2.2 添加表和链

```bash
# 添加表（inet 支持 IPv4 + IPv6）
sudo nft add table inet filter

# 添加链（带 hook 和策略）
sudo nft add chain inet filter input \
    '{ type filter hook input priority 0; policy drop; }'

sudo nft add chain inet filter output \
    '{ type filter hook output priority 0; policy accept; }'
```

### 2.3 添加规则

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
```

### 2.4 删除规则

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

> **反模式**：不使用 handles 就尝试删除规则。必须先用 `nft -a` 查看句柄。  

---

## Step 3 - 状态防火墙 ct state（10 分钟）

### 3.1 为什么 ct state 如此重要？

<!-- DIAGRAM: ct-state-importance -->
```
没有连接跟踪的规则：

客户端 ──── SYN ────> 服务器:22 (允许)
客户端 <─── SYN+ACK ─ 服务器:22 (需要额外规则!)
客户端 ──── ACK ────> 服务器:22 (需要额外规则!)

问题：需要为每种包类型写规则，复杂且容易出错

───────────────────────────────────────────────────

有连接跟踪的规则：

客户端 ──── SYN ────> 服务器:22 (新连接，检查 dport 22 规则)
客户端 <─── SYN+ACK ─ 服务器:22 (established，自动允许!)
客户端 ──── ACK ────> 服务器:22 (established，自动允许!)

优势：一条规则处理所有相关流量
```
<!-- /DIAGRAM -->

### 3.2 连接状态说明

| 状态 | 描述 | 示例 |
|------|------|------|
| `new` | 新连接的第一个包 | TCP SYN 包 |
| `established` | 已建立连接的后续包 | 数据传输 |
| `related` | 与已有连接相关的新连接 | FTP 数据连接 |
| `invalid` | 不属于任何已知连接 | 应该丢弃 |

### 3.3 正确的规则顺序

```bash
# 标准安全规则顺序（顺序很重要！）

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

# 6. 默认拒绝（通过 policy drop 实现）
```

> **反模式**：忘记 `ct state established,related`，会阻断响应包，导致连接建立后无法通信。  

---

## Step 4 - 安全操作协议（必读！）

> **这是本课最重要的内容。防火墙配置错误可能导致你被锁在服务器外面。**  

### 4.1 黄金法则

```
永远不要在没有恢复计划的情况下测试防火墙规则
```

### 4.2 安全操作步骤

**方法 1：保持第二个终端**

```bash
# 步骤 1：开两个终端连接到服务器
# 终端 A：用于修改规则
# 终端 B：保持连接不动，作为后备

# 步骤 2：在终端 A 修改规则
sudo nft add rule inet filter input tcp dport 22 accept

# 步骤 3：在终端 B 测试新连接
# 打开第三个终端尝试 SSH
# 如果成功 → 规则正确
# 如果失败 → 用终端 A 或 B 恢复
```

**方法 2：自动恢复（推荐）**

```bash
# 在修改规则前，调度自动恢复任务
# 如果被锁定，规则将在 5 分钟后自动恢复

# 保存当前规则
sudo nft list ruleset > /tmp/nftables-backup.nft

# 调度恢复任务（5 分钟后执行）
nohup bash -c 'sleep 300 && nft flush ruleset && nft -f /etc/nftables.conf' &

# 现在可以安全地测试新规则了
sudo nft -f /tmp/test-rules.nft

# 如果一切正常，取消恢复任务
# 查找后台任务
jobs -l
# 或者直接等 5 分钟让它执行也无妨
```

**方法 3：使用 at 命令**

```bash
# 5 分钟后恢复规则
echo 'nft -f /etc/nftables.conf' | sudo at now + 5 minutes

# 查看调度的任务
sudo atq

# 如果测试成功，取消恢复任务
sudo atrm <job_id>
```

### 4.3 验证配置语法

```bash
# 在应用配置前验证语法（关键步骤！）
sudo nft -c -f /etc/nftables.conf

# 如果有错误会显示：
# /etc/nftables.conf:25:9-15: Error: syntax error
#         invalid rule here
#         ^^^^^^^

# 没有输出 = 配置正确
```

> **反模式**：`flush` 所有规则来"修复"问题。这会破坏现有连接，创建安全漏洞。  

---

## Step 5 - 动手练习：Default-Deny 防火墙（15 分钟）

### 5.1 项目目标

构建一个 default-deny 防火墙：
- 默认拒绝所有入站流量
- 仅允许 SSH（端口 22）
- 仅允许 HTTP/HTTPS（端口 80、443）
- 允许已建立的连接响应

### 5.2 创建配置文件

```bash
# 创建配置文件
cat << 'EOF' | sudo tee /etc/nftables.conf
#!/usr/sbin/nft -f
# =============================================================================
# Default-Deny Firewall Configuration
# Description: Allow only SSH and HTTP/HTTPS
# =============================================================================

# Clear existing rules
flush ruleset

# =============================================================================
# Table: inet filter (IPv4 + IPv6)
# =============================================================================
table inet filter {

    # -------------------------------------------------------------------------
    # Chain: input - Inbound traffic control
    # Policy: DROP (default deny)
    # -------------------------------------------------------------------------
    chain input {
        type filter hook input priority 0; policy drop;

        # Connection tracking (CRITICAL - must be first!)
        ct state established,related accept comment "Allow established/related"
        ct state invalid drop comment "Drop invalid packets"

        # Loopback interface
        iif "lo" accept comment "Allow loopback"

        # SSH (port 22)
        tcp dport 22 accept comment "SSH"

        # Web services
        tcp dport 80 accept comment "HTTP"
        tcp dport 443 accept comment "HTTPS"

        # ICMP (ping)
        ip protocol icmp icmp type { echo-request, echo-reply } accept comment "ICMP"
        ip6 nexthdr icmpv6 icmpv6 type { echo-request, echo-reply } accept comment "ICMPv6"

        # Log dropped packets (rate limited)
        log prefix "[nftables DROP] " limit rate 3/minute comment "Log drops"
    }

    # -------------------------------------------------------------------------
    # Chain: forward - Transit traffic (disabled by default)
    # -------------------------------------------------------------------------
    chain forward {
        type filter hook forward priority 0; policy drop;
    }

    # -------------------------------------------------------------------------
    # Chain: output - Outbound traffic (allow all)
    # -------------------------------------------------------------------------
    chain output {
        type filter hook output priority 0; policy accept;
    }
}
EOF
```

### 5.3 验证并应用

```bash
# 步骤 1：验证语法
sudo nft -c -f /etc/nftables.conf
echo "Syntax OK!"

# 步骤 2：设置自动恢复（安全网）
nohup bash -c 'sleep 300 && nft flush ruleset' &
echo "Recovery scheduled in 5 minutes"

# 步骤 3：应用配置
sudo nft -f /etc/nftables.conf

# 步骤 4：验证规则
sudo nft list ruleset

# 步骤 5：测试连接（打开新终端）
# ssh user@server  # 应该成功
# curl http://server  # 应该成功（如果有 web 服务）

# 步骤 6：持久化
sudo systemctl enable nftables
sudo systemctl restart nftables
```

### 5.4 验证结果

```bash
# 查看规则
sudo nft list ruleset

# 测试端口
nc -zv localhost 22   # 应该成功
nc -zv localhost 80   # 应该成功（如果有服务监听）
nc -zv localhost 3306 # 应该失败（被阻断）

# 查看日志（被阻断的连接）
sudo journalctl -k | grep "nftables DROP" | tail -5
```

---

## Step 6 - nftables 高级特性（可选）

### 6.1 Sets：高效的批量匹配

```bash
# 创建 IP 白名单 set
sudo nft add set inet filter trusted_ips '{ type ipv4_addr; flags interval; }'

# 添加元素
sudo nft add element inet filter trusted_ips '{ 10.0.0.0/8, 192.168.1.0/24 }'

# 在规则中使用
sudo nft add rule inet filter input ip saddr @trusted_ips accept

# 动态更新（不中断服务）
sudo nft add element inet filter trusted_ips '{ 203.0.113.50 }'
sudo nft delete element inet filter trusted_ips '{ 203.0.113.50 }'
```

### 6.2 原子更新

nftables 的一个重要特性是**原子更新**：

```bash
# iptables 方式（危险）：
# 规则一条一条添加，中间可能有空窗期

# nftables 方式（安全）：
# 整个规则集作为事务一次性替换
sudo nft -f /etc/nftables.conf
# 要么全部成功，要么全部失败，没有中间状态
```

### 6.3 速率限制

```bash
# 限制 SSH 连接速率（防暴力破解）
sudo nft add rule inet filter input tcp dport 22 ct state new \
    limit rate 3/minute accept

# 限制 ICMP（防 ping flood）
sudo nft add rule inet filter input ip protocol icmp \
    limit rate 10/second accept
```

---

## Step 7 - 从 iptables 迁移

### 7.1 使用 iptables-translate

```bash
# 翻译单条规则
iptables-translate -A INPUT -p tcp --dport 22 -j ACCEPT
# 输出: nft add rule ip filter INPUT tcp dport 22 counter accept

# 翻译整个规则集
iptables-save > /tmp/iptables-rules.txt
iptables-restore-translate < /tmp/iptables-rules.txt > /tmp/nftables-rules.nft

# 验证翻译结果
sudo nft -c -f /tmp/nftables-rules.nft
```

### 7.2 iptables-nft 兼容层

```bash
# 检查当前后端
iptables -V
# 输出: iptables v1.8.x (nf_tables)  ← 使用 nftables 后端
# 输出: iptables v1.8.x (legacy)     ← 使用传统 iptables

# RHEL 9+ 默认使用 nftables 后端
# 旧的 iptables 命令实际上调用 nftables
```

### 7.3 何时使用 nftables vs firewalld？

| 场景 | 推荐 | 原因 |
|------|------|------|
| 简单服务器 | firewalld | Zone 概念易懂，命令简单 |
| 复杂规则 | nftables | 更精细控制 |
| 容器/K8s | nftables | 直接控制，性能更好 |
| 新手学习 | firewalld | 入门更容易 |
| 需要迁移 | nftables | 现代标准 |

> **反模式**：混用 `nft` 直接配置和 `firewalld`。两者会冲突，选择一个使用。  

---

## 职场小贴士

### 日本 IT 常用术语

| 日本語 | 中文 | 技术实现 |
|--------|------|----------|
| ファイアウォール | 防火墙 | nftables/firewalld |
| 接続許可 | 连接许可 | accept 规则 |
| 接続拒否 | 连接拒绝 | drop/reject 规则 |
| アクセス制御 | 访问控制 | IP 白名单 |
| ポート開放 | 端口开放 | dport 规则 |
| 設定変更 | 配置变更 | nft -f 应用 |

### 面试常见问题

**Q: nftables と iptables の違いは？**

A: nftables は統一シンタックス、IPv4/IPv6 統合、セット対応、アトミック更新が特徴です。2020 年以降のデフォルトで、iptables は maintenance mode です。

**Q: iptables から nftables への移行方法は？**

A: `iptables-translate` でルール変換、`iptables-nft` で互換レイヤー使用。新規システムは nftables 推奨です。

### 障害対応のポイント

```bash
# 网络不通时的快速检查
# 1. 确认防火墙规则
sudo nft list ruleset | grep -E "dport (22|80|443)"

# 2. 确认服务在监听
ss -tuln | grep -E ":(22|80|443)"

# 3. 检查日志
sudo journalctl -k | grep "nftables DROP" | tail -10
```

---

## 检查清单

完成本课后，你应该能够：

- [ ] 解释 nftables 的层级结构（ruleset → table → chain → rule）
- [ ] 使用 `nft list ruleset` 查看当前规则
- [ ] 使用 `nft add table/chain/rule` 添加规则
- [ ] 理解 `ct state established,related` 的重要性
- [ ] 使用 `nft -c -f` 验证配置语法
- [ ] 安全地应用防火墙变更（保持后备会话、设置自动恢复）
- [ ] 使用 `iptables-translate` 迁移旧规则
- [ ] 配置 default-deny 防火墙

---

## 本课小结

| 概念 | 命令 | 记忆点 |
|------|------|--------|
| 查看规则 | `nft list ruleset` | 完整规则集 |
| 验证配置 | `nft -c -f file` | **应用前必须验证** |
| 应用配置 | `nft -f file` | 原子更新 |
| 状态跟踪 | `ct state established,related` | **核心规则，必须有** |
| 删除规则 | `nft -a list` + `delete handle X` | 需要先获取句柄 |
| 持久化 | `/etc/nftables.conf` + `systemctl enable` | 重启不丢失 |
| 迁移工具 | `iptables-translate` | 自动翻译规则 |

**关键安全原则**：

```
永远不要在没有恢复计划的情况下测试防火墙规则

1. 保持第二个终端连接
2. 设置自动恢复任务
3. 先验证语法再应用
```

---

## 延伸阅读

- [nftables Wiki](https://wiki.nftables.org/) - 官方文档和示例
- [Red Hat nftables Guide](https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/9/html/configuring_firewalls_and_packet_filters/) - RHEL 9 官方指南
- [Netfilter Project](https://netfilter.org/) - 内核防火墙项目
- 相关课程：[07 - firewalld 区域](../07-firewalld/) - 更高级别的防火墙管理
- 相关课程：[LX08 - 安全加固](../../lx08-security/) - 生产级防火墙配置

---

## 下一步

你已经理解了 nftables 基础。接下来，让我们学习 firewalld——一个更高级别的防火墙管理工具，它在底层使用 nftables，但提供更友好的 zone 概念。

-> [07 - firewalld 区域](../07-firewalld/)

---

## 系列导航

[<- 05 - 套接字检查 (ss)](../05-sockets/) | [系列首页](../) | [07 - firewalld 区域 ->](../07-firewalld/)
