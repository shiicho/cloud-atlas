# 04 - DNS 配置（DNS Configuration）

> **目标**：掌握现代 Linux DNS 配置方法，理解 systemd-resolved 架构，学会 DNS 问题排查  
> **前置**：已完成 [03 - IP 路由](../03-routing/)，理解网络层连通性概念  
> **时间**：⚡ 12 分钟（速读）/ 🔬 50 分钟（完整实操）  
> **实战场景**：DNS 故障排查、VPN split-DNS 配置、企业网络 DNS 管理  

---

## 将学到的内容

1. 理解 systemd-resolved 架构和 stub resolver（127.0.0.53）
2. 使用 `resolvectl` 管理和调试 DNS
3. 配置静态 DNS 服务器（正确的方式）
4. 理解 split-DNS 在 VPN 和企业网络中的应用
5. 使用 `dig` / `nslookup` 进行 DNS 调试
6. 知道何时以及如何使用传统 `/etc/resolv.conf`

---

## 先跑起来！（5 分钟）

> 在学习理论之前，先看看你的系统现在的 DNS 配置。  
> 运行这些命令，观察输出 -- 你会发现一些"神秘"的东西。  

```bash
# 查看 /etc/resolv.conf 的"真面目"
ls -la /etc/resolv.conf

# 查看 DNS 配置详情
resolvectl status

# 测试 DNS 解析
resolvectl query www.google.com

# 对比：使用外部 DNS 直接查询
dig @8.8.8.8 www.google.com +short
```

**你刚刚揭开了现代 Linux DNS 的神秘面纱！**

你可能注意到 `/etc/resolv.conf` 是一个符号链接，指向 systemd 的某个文件。这就是为什么直接编辑它会失效的原因 -- 接下来我们详细解释。

---

## Step 1 -- systemd-resolved 架构（15 分钟）

### 1.1 为什么传统方式会失效？

在很多教程中，你会看到这样的"经典"配置方法：

```bash
# 错误做法 -- 在现代系统上会失效
echo "nameserver 8.8.8.8" | sudo tee /etc/resolv.conf
```

几分钟后，或者网络重连后，你会发现配置被覆盖了。这不是 bug，而是 systemd-resolved 在"工作"。

### 1.2 systemd-resolved 架构图

<!-- DIAGRAM: systemd-resolved-architecture -->
```
┌────────────────────────────────────────────────────────────────────────────┐
│                      systemd-resolved 架构                                  │
├────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  应用程序                                                                   │
│  (curl, ping, 浏览器)                                                       │
│        │                                                                    │
│        ▼                                                                    │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │              /etc/resolv.conf                                        │   │
│  │              nameserver 127.0.0.53  ◄── Stub Resolver 地址           │   │
│  │              (符号链接)                                               │   │
│  └──────────────────────────────┬──────────────────────────────────────┘   │
│                                 │                                           │
│                                 ▼                                           │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                    systemd-resolved                                  │   │
│  │  ┌────────────┐  ┌────────────┐  ┌────────────┐                     │   │
│  │  │  DNS 缓存   │  │ 查询路由   │  │  DNSSEC    │                     │   │
│  │  │  (Cache)   │  │ (Routing)  │  │  验证      │                     │   │
│  │  └────────────┘  └────────────┘  └────────────┘                     │   │
│  │                                                                      │   │
│  │  Per-Link DNS 配置：                                                 │   │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────┐                           │   │
│  │  │  eth0    │  │  wlan0   │  │  tun0    │  ◄── 每个接口可有不同 DNS  │   │
│  │  │ 10.0.1.2 │  │ 8.8.8.8  │  │内网 DNS   │                           │   │
│  │  └──────────┘  └──────────┘  └──────────┘                           │   │
│  └──────────────────────────────┬──────────────────────────────────────┘   │
│                                 │                                           │
│                                 ▼                                           │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                    上游 DNS 服务器                                    │   │
│  │  企业 DNS / 云 VPC DNS / 公共 DNS (8.8.8.8, 1.1.1.1)                 │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
└────────────────────────────────────────────────────────────────────────────┘
```
<!-- /DIAGRAM -->

### 1.3 Stub Resolver：127.0.0.53

```bash
# 查看 resolv.conf 指向哪里
ls -la /etc/resolv.conf
```

典型输出：
```
lrwxrwxrwx 1 root root 39 Jan  1 00:00 /etc/resolv.conf -> ../run/systemd/resolve/stub-resolv.conf
```

```bash
# 查看实际内容
cat /etc/resolv.conf
```

```
# This is /run/systemd/resolve/stub-resolv.conf managed by man:systemd-resolved(8).
# ...
nameserver 127.0.0.53
options edns0 trust-ad
search localdomain
```

**127.0.0.53** 就是 systemd-resolved 的 stub resolver：

| 特性 | 说明 |
|------|------|
| 本地代理 | 所有 DNS 查询先发到这里 |
| 缓存 | 减少重复查询 |
| 路由 | 根据域名选择合适的上游 DNS |
| DNSSEC | 可选的安全验证 |

### 1.4 /etc/resolv.conf 符号链接的几种模式

```bash
# 查看可能的链接目标
ls -la /run/systemd/resolve/
```

| 链接目标 | 特点 | 适用场景 |
|----------|------|----------|
| `stub-resolv.conf` | 指向 127.0.0.53（推荐） | 大多数场景 |
| `resolv.conf` | 直接上游 DNS | 需要绕过本地缓存 |
| 实际文件 | 不是符号链接 | 手动管理或旧系统 |

---

## Step 2 -- resolvectl：现代 DNS 管理工具（10 分钟）

### Lab 1：查看 DNS 状态

```bash
# 查看整体 DNS 状态
resolvectl status
```

**输出解读：**

```
Global
         Protocols: +LLMNR +mDNS -DNSOverTLS DNSSEC=no/unsupported
  resolv.conf mode: stub
Current DNS Server: 10.0.1.2
       DNS Servers: 10.0.1.2

Link 2 (eth0)
    Current Scopes: DNS LLMNR/IPv4 LLMNR/IPv6
         Protocols: +DefaultRoute +LLMNR -mDNS -DNSOverTLS DNSSEC=no/unsupported
Current DNS Server: 10.0.1.2
       DNS Servers: 10.0.1.2
        DNS Domain: ap-northeast-1.compute.internal
```

| 字段 | 含义 |
|------|------|
| `Global` | 全局 DNS 配置 |
| `Link X (eth0)` | 每个网络接口的 DNS 配置 |
| `Current DNS Server` | 当前使用的 DNS 服务器 |
| `DNS Domain` | 搜索域（自动补全短域名） |
| `+DefaultRoute` | 该接口是默认 DNS 路由 |

### Lab 2：测试 DNS 解析

```bash
# 使用 systemd-resolved 解析（经过缓存）
resolvectl query www.google.com

# 查看详细信息
resolvectl query --legend=no www.google.com

# 反向解析（IP 到域名）
resolvectl query 8.8.8.8
```

**输出示例：**

```
www.google.com: 142.250.196.132                  -- link: eth0
                2404:6800:4004:820::2004         -- link: eth0

-- Information acquired via protocol DNS in 23.4ms.
-- Data is authenticated: no; Data was acquired via local or encrypted transport: no
-- Data from: network
```

### Lab 3：DNS 缓存管理

```bash
# 查看缓存统计
resolvectl statistics

# 清除 DNS 缓存（排障时常用）
sudo resolvectl flush-caches

# 再次查看统计（缓存计数归零）
resolvectl statistics
```

**常见场景**：当你修改了 DNS 记录但本地还解析到旧 IP 时，清除缓存。

---

## Step 3 -- 配置静态 DNS（10 分钟）

### 3.1 正确的配置方法

**方法 1：通过 NetworkManager（推荐）**

```bash
# 查看当前连接
nmcli con show

# 设置 DNS 服务器
sudo nmcli con mod "Wired connection 1" ipv4.dns "8.8.8.8 8.8.4.4"

# 设置忽略 DHCP 的 DNS（使用自定义 DNS）
sudo nmcli con mod "Wired connection 1" ipv4.ignore-auto-dns yes

# 重新激活连接
sudo nmcli con up "Wired connection 1"

# 验证
resolvectl status eth0
```

**方法 2：配置 systemd-resolved**

```bash
# 编辑全局配置
sudo vim /etc/systemd/resolved.conf
```

```ini
[Resolve]
# 全局 DNS 服务器（备用）
DNS=8.8.8.8 8.8.4.4
# 备选 DNS
FallbackDNS=1.1.1.1 9.9.9.9
# 搜索域
Domains=~.
# DNSSEC 模式：no, allow-downgrade, yes
DNSSEC=allow-downgrade
# DNS over TLS
DNSOverTLS=opportunistic
```

```bash
# 重启服务使配置生效
sudo systemctl restart systemd-resolved

# 验证配置
resolvectl status
```

### 3.2 Per-Link DNS 配置

每个网络接口可以有不同的 DNS 服务器：

```bash
# 为特定接口设置 DNS
sudo resolvectl dns eth0 10.0.1.2 10.0.1.3

# 为特定接口设置搜索域
sudo resolvectl domain eth0 internal.company.com

# 验证
resolvectl status eth0
```

> **注意**：`resolvectl dns/domain` 设置是临时的，重启后丢失。永久配置需要通过 NetworkManager 或 netplan。  

---

## Step 4 -- Split-DNS：VPN 与企业网络（5 分钟）

### 4.1 什么是 Split-DNS？

<!-- DIAGRAM: split-dns-concept -->
```
┌────────────────────────────────────────────────────────────────────────────┐
│                           Split-DNS 概念                                    │
├────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  你的电脑                                                                   │
│  ┌───────────────────────────────────────────────────────────────────────┐ │
│  │                     systemd-resolved                                  │ │
│  │                                                                        │ │
│  │   查询: internal.company.com                                          │ │
│  │         │                                                             │ │
│  │         ▼                                                             │ │
│  │   ┌─────────────────────────────────────────────────────────────┐     │ │
│  │   │  域名匹配规则（DNS Routing）                                  │     │ │
│  │   │                                                              │     │ │
│  │   │  *.company.com  ────► 企业 DNS (10.1.1.53)  via tun0 (VPN)  │     │ │
│  │   │  *.internal     ────► 企业 DNS (10.1.1.53)  via tun0 (VPN)  │     │ │
│  │   │  其他所有域名   ────► 公共 DNS (8.8.8.8)    via eth0        │     │ │
│  │   │                                                              │     │ │
│  │   └─────────────────────────────────────────────────────────────┘     │ │
│  │                                                                        │ │
│  └───────────────────────────────────────────────────────────────────────┘ │
│                                                                             │
│  好处：                                                                     │
│  - 内网域名通过 VPN 解析（安全、正确）                                      │
│  - 公网域名直接解析（快速、不走 VPN）                                       │
│  - 两者互不干扰                                                            │
│                                                                             │
└────────────────────────────────────────────────────────────────────────────┘
```
<!-- /DIAGRAM -->

### 4.2 配置 Split-DNS

```bash
# 为 VPN 接口设置特定域的 DNS
# tun0 是 VPN 接口，company.com 域名走企业 DNS
sudo resolvectl domain tun0 company.com internal

# 设置该接口的 DNS 服务器
sudo resolvectl dns tun0 10.1.1.53

# 验证配置
resolvectl status
```

**输出示例：**

```
Link 5 (tun0)
    Current Scopes: DNS
         Protocols: -DefaultRoute -LLMNR -mDNS -DNSOverTLS DNSSEC=no/unsupported
Current DNS Server: 10.1.1.53
       DNS Servers: 10.1.1.53
        DNS Domain: company.com internal
```

注意 `-DefaultRoute`：表示该接口不是默认 DNS 路由，只处理匹配的域名。

---

## Step 5 -- DNS 调试工具（5 分钟）

### Lab 4：使用 dig 调试

```bash
# 安装 dig（如果没有）
sudo dnf install bind-utils -y   # RHEL/CentOS
sudo apt install dnsutils -y      # Debian/Ubuntu

# 基本查询
dig www.google.com

# 简短输出
dig www.google.com +short

# 指定 DNS 服务器查询（绕过本地缓存）
dig @8.8.8.8 www.google.com

# 查询特定记录类型
dig www.google.com A       # IPv4 地址
dig www.google.com AAAA    # IPv6 地址
dig google.com MX          # 邮件服务器
dig google.com NS          # 域名服务器
dig google.com TXT         # TXT 记录

# 追踪完整解析过程
dig www.google.com +trace
```

**dig 输出解读：**

```
; <<>> DiG 9.18.12 <<>> www.google.com
;; global options: +cmd
;; Got answer:
;; ->>HEADER<<- opcode: QUERY, status: NOERROR, id: 12345
;; flags: qr rd ra; QUERY: 1, ANSWER: 1, AUTHORITY: 0, ADDITIONAL: 1

;; QUESTION SECTION:
;www.google.com.                IN      A

;; ANSWER SECTION:
www.google.com.         300     IN      A       142.250.196.132

;; Query time: 23 msec
;; SERVER: 127.0.0.53#53(127.0.0.53) (UDP)
;; WHEN: Sat Jan 04 2025 15:30:00 JST
;; MSG SIZE  rcvd: 59
```

| 字段 | 含义 |
|------|------|
| `status: NOERROR` | 查询成功 |
| `ANSWER: 1` | 有 1 条回答 |
| `300` | TTL（缓存时间，秒） |
| `Query time: 23 msec` | 查询耗时 |
| `SERVER: 127.0.0.53` | 使用的 DNS 服务器 |

### Lab 5：对比不同 DNS 服务器

```bash
# 创建 DNS 对比脚本
cat << 'EOF' > /tmp/dns-compare.sh
#!/bin/bash
DOMAIN="${1:-www.google.com}"
echo "=== DNS Resolution Comparison for: $DOMAIN ==="
echo ""
echo "--- Local (systemd-resolved) ---"
dig @127.0.0.53 "$DOMAIN" +short +time=2
echo ""
echo "--- Google DNS (8.8.8.8) ---"
dig @8.8.8.8 "$DOMAIN" +short +time=2
echo ""
echo "--- Cloudflare DNS (1.1.1.1) ---"
dig @1.1.1.1 "$DOMAIN" +short +time=2
echo ""
echo "--- Quad9 DNS (9.9.9.9) ---"
dig @9.9.9.9 "$DOMAIN" +short +time=2
EOF

chmod +x /tmp/dns-compare.sh
/tmp/dns-compare.sh www.google.com
```

---

## Step 6 -- 传统配置：何时直接用 /etc/resolv.conf

### 6.1 需要直接配置的场景

| 场景 | 原因 |
|------|------|
| 容器/Docker | 很多容器不运行 systemd |
| 最小化安装 | 可能没有 systemd-resolved |
| 特殊嵌入式系统 | 资源受限 |
| 兼容性要求 | 某些旧应用需要 |

### 6.2 禁用 systemd-resolved（谨慎！）

```bash
# 只有在确实需要时才这样做

# 1. 停止并禁用 systemd-resolved
sudo systemctl stop systemd-resolved
sudo systemctl disable systemd-resolved

# 2. 删除符号链接，创建真实文件
sudo rm /etc/resolv.conf
sudo tee /etc/resolv.conf << EOF
nameserver 8.8.8.8
nameserver 8.8.4.4
search localdomain
EOF

# 3. 防止被覆盖（可选）
sudo chattr +i /etc/resolv.conf

# 恢复方法
sudo chattr -i /etc/resolv.conf
sudo systemctl enable systemd-resolved
sudo systemctl start systemd-resolved
sudo ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
```

> **警告**：禁用 systemd-resolved 后，你将失去 DNS 缓存、per-link DNS、split-DNS 等功能。  

---

## Failure Lab：Split Brain DNS 演示

### 场景

你在云服务器上运行应用，发现某个域名解析失败。Ping IP 成功，但 ping 域名失败。

### 复现问题

```bash
# 模拟 resolv.conf 被意外覆盖
sudo cp /etc/resolv.conf /tmp/resolv.conf.bak

# 错误操作：直接覆盖（模拟某些脚本的行为）
echo "nameserver 192.168.255.255" | sudo tee /etc/resolv.conf

# 测试：DNS 解析失败
ping -c 1 www.google.com
# ping: www.google.com: Temporary failure in name resolution

# 但 IP 连接正常
ping -c 1 8.8.8.8
# 成功
```

### 诊断过程

```bash
# Step 1: 检查 resolv.conf
cat /etc/resolv.conf
# 发现 nameserver 指向无效地址

# Step 2: 检查 systemd-resolved 状态
resolvectl status
# 可能显示服务还在运行但配置被覆盖

# Step 3: 检查符号链接
ls -la /etc/resolv.conf
# 发现不再是符号链接，而是普通文件

# Step 4: 对比测试
dig @8.8.8.8 www.google.com +short
# 使用外部 DNS 可以解析 -- 证明不是网络问题
```

### 正确修复

```bash
# 方法 1：恢复符号链接（推荐）
sudo rm /etc/resolv.conf
sudo ln -s /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
sudo systemctl restart systemd-resolved

# 方法 2：如果需要自定义 DNS，用正确方式
sudo nmcli con mod "Wired connection 1" ipv4.dns "8.8.8.8"
sudo nmcli con up "Wired connection 1"

# 验证修复
resolvectl status
ping -c 1 www.google.com
```

### 经验教训

| 错误做法 | 正确做法 |
|----------|----------|
| 直接编辑 /etc/resolv.conf | 使用 nmcli 或 resolved.conf |
| 禁用 systemd-resolved 不配置替代 | 理解后果，提供替代方案 |
| 不检查符号链接状态 | 排障时先 `ls -la /etc/resolv.conf` |

---

## Mini Project：DNS 调试工作流脚本

创建一个 DNS 问题诊断脚本：

```bash
#!/bin/bash
# dns-debug.sh - DNS 问题诊断脚本
# 用法: ./dns-debug.sh [domain]

DOMAIN="${1:-www.google.com}"
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "=========================================="
echo "DNS Diagnostic Report"
echo "Domain: $DOMAIN"
echo "Date: $(date)"
echo "=========================================="

echo ""
echo "=== 1. resolv.conf Status ==="
if [ -L /etc/resolv.conf ]; then
    echo -e "${GREEN}[OK]${NC} /etc/resolv.conf is a symlink"
    ls -la /etc/resolv.conf
else
    echo -e "${YELLOW}[WARN]${NC} /etc/resolv.conf is NOT a symlink"
    echo "This may cause DNS configuration issues"
fi

echo ""
echo "=== 2. systemd-resolved Status ==="
if systemctl is-active --quiet systemd-resolved; then
    echo -e "${GREEN}[OK]${NC} systemd-resolved is running"
else
    echo -e "${RED}[FAIL]${NC} systemd-resolved is NOT running"
fi

echo ""
echo "=== 3. Current DNS Configuration ==="
resolvectl status 2>/dev/null || echo "resolvectl not available"

echo ""
echo "=== 4. DNS Resolution Test ==="
echo "--- Local resolver (127.0.0.53) ---"
RESULT=$(dig @127.0.0.53 "$DOMAIN" +short +time=3 2>/dev/null)
if [ -n "$RESULT" ]; then
    echo -e "${GREEN}[OK]${NC} $RESULT"
else
    echo -e "${RED}[FAIL]${NC} Local resolution failed"
fi

echo ""
echo "--- Google DNS (8.8.8.8) ---"
RESULT=$(dig @8.8.8.8 "$DOMAIN" +short +time=3 2>/dev/null)
if [ -n "$RESULT" ]; then
    echo -e "${GREEN}[OK]${NC} $RESULT"
else
    echo -e "${RED}[FAIL]${NC} Google DNS resolution failed"
fi

echo ""
echo "--- Cloudflare DNS (1.1.1.1) ---"
RESULT=$(dig @1.1.1.1 "$DOMAIN" +short +time=3 2>/dev/null)
if [ -n "$RESULT" ]; then
    echo -e "${GREEN}[OK]${NC} $RESULT"
else
    echo -e "${RED}[FAIL]${NC} Cloudflare DNS resolution failed"
fi

echo ""
echo "=== 5. DNS Cache Statistics ==="
resolvectl statistics 2>/dev/null || echo "Statistics not available"

echo ""
echo "=== 6. Recommendations ==="
# Check for common issues
if ! systemctl is-active --quiet systemd-resolved; then
    echo "- Start systemd-resolved: sudo systemctl start systemd-resolved"
fi

if [ ! -L /etc/resolv.conf ]; then
    echo "- Restore symlink: sudo ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf"
fi

LOCAL_FAIL=$(dig @127.0.0.53 "$DOMAIN" +short +time=3 2>/dev/null)
EXTERNAL_OK=$(dig @8.8.8.8 "$DOMAIN" +short +time=3 2>/dev/null)
if [ -z "$LOCAL_FAIL" ] && [ -n "$EXTERNAL_OK" ]; then
    echo "- Local DNS issue detected. Try: sudo resolvectl flush-caches"
    echo "- Or check: resolvectl status"
fi

echo ""
echo "=========================================="
echo "Diagnostic complete"
echo "=========================================="
```

**使用方法：**

```bash
# 保存脚本
chmod +x dns-debug.sh

# 运行诊断
./dns-debug.sh www.google.com

# 诊断特定域名
./dns-debug.sh internal.company.com
```

---

## 职场小贴士（Japan IT Context）

### DNS 障害対応（DNS トラブルシューティング）

在日本 IT 企业，DNS 问题排查是常见的运维任务：

| 日语术语 | 含义 | 场景 |
|----------|------|------|
| 名前解決 | 域名解析 | DNS の基本機能 |
| DNS 障害 | DNS 故障 | 障害報告で使用 |
| キャッシュクリア | 清除缓存 | resolvectl flush-caches |
| 切り分け | 问题切分 | 内部 DNS vs 外部 DNS |
| フォワーダー | DNS 转发器 | 企业 DNS 架构 |

### 常用排障对话

**场景**：用户报告"ページが開けない"（打不开网页）

```
1. まず ping で IP 疎通確認します
   (First, verify IP connectivity with ping)

2. DNS 解決ができるか確認します
   (Check if DNS resolution works)
   $ dig www.example.com +short

3. 外部 DNS で解決できれば、内部 DNS の問題です
   (If external DNS works, it's an internal DNS issue)
   $ dig @8.8.8.8 www.example.com +short

4. キャッシュをクリアして再試行します
   (Clear cache and retry)
   $ sudo resolvectl flush-caches
```

---

## 面试问题

### Q1: systemd-resolved とは何ですか？

**A:** systemd-resolved は、モダンな DNS リゾルバデーモンです。127.0.0.53 でローカルスタブリゾルバを提供し、DNS キャッシュ、per-link DNS 設定、split-DNS（VPN シナリオ）、DNSSEC 検証をサポートします。/etc/resolv.conf は通常、このサービスが管理するファイルへのシンボリックリンクです。

### Q2: DNS 障害の切り分け手順を教えてください

**A:**
1. `resolvectl status` で現在の DNS 設定を確認
2. `dig @127.0.0.53 domain` でローカルリゾルバをテスト
3. `dig @8.8.8.8 domain` で外部 DNS をテスト
4. ローカルが失敗、外部が成功なら、systemd-resolved の設定問題
5. 両方失敗なら、ネットワーク接続問題
6. 両方成功なら、アプリケーション固有の問題

### Q3: /etc/resolv.conf を直接編集してはいけない理由は？

**A:** systemd-resolved を使用している場合、/etc/resolv.conf は `/run/systemd/resolve/stub-resolv.conf` へのシンボリックリンクです。直接編集しても、NetworkManager や systemd-resolved が設定を上書きします。永続的な変更には `nmcli con mod` または `/etc/systemd/resolved.conf` を使用します。

### Q4: Split-DNS とは？いつ使いますか？

**A:** Split-DNS は、ドメインによって異なる DNS サーバーを使用する設定です。VPN 接続時によく使います：内部ドメイン（*.company.com）は VPN 経由の企業 DNS へ、その他は通常の DNS へルーティングします。これにより、セキュリティと効率を両立できます。

---

## 检查清单

完成本课后，你应该能够：

- [ ] 解释 systemd-resolved 的架构和 127.0.0.53 stub resolver 的作用
- [ ] 查看和解读 `resolvectl status` 输出
- [ ] 使用 `resolvectl query` 测试 DNS 解析
- [ ] 使用 `resolvectl flush-caches` 清除 DNS 缓存
- [ ] 通过 nmcli 或 resolved.conf 正确配置静态 DNS
- [ ] 理解 split-DNS 的概念和 VPN 场景应用
- [ ] 使用 `dig` 进行 DNS 调试和对比测试
- [ ] 诊断并修复常见 DNS 问题（resolv.conf 被覆盖等）
- [ ] 说明为什么不应直接编辑 /etc/resolv.conf

---

## 本课小结

| 概念 | 命令/文件 | 记忆点 |
|------|-----------|--------|
| 查看 DNS 状态 | `resolvectl status` | 第一个排障命令 |
| 测试解析 | `resolvectl query` | 使用本地缓存 |
| 清除缓存 | `resolvectl flush-caches` | 排障常用 |
| 配置 DNS | `nmcli con mod` | 正确的持久化方式 |
| 全局配置 | `/etc/systemd/resolved.conf` | FallbackDNS, DNSSEC |
| DNS 调试 | `dig @server domain` | 绕过本地缓存 |
| Stub Resolver | 127.0.0.53 | systemd-resolved 入口 |
| Split-DNS | per-link domain | VPN 场景 |

**核心理念**：

```
DNS 问题排查流程：

  1. resolvectl status     → 当前配置正确吗？
  2. dig @127.0.0.53       → 本地解析工作吗？
  3. dig @8.8.8.8          → 外部 DNS 工作吗？
  4. 对比结果              → 问题在哪一层？
```

---

## 延伸阅读

- [systemd-resolved man page](https://www.freedesktop.org/software/systemd/man/systemd-resolved.html)
- [resolvectl man page](https://www.freedesktop.org/software/systemd/man/resolvectl.html)
- [Arch Wiki - systemd-resolved](https://wiki.archlinux.org/title/Systemd-resolved)
- [DNS over TLS with systemd-resolved](https://wiki.archlinux.org/title/Systemd-resolved#DNS_over_TLS)
- 上一课：[03 - IP 路由](../03-routing/) -- 路由表配置和排障
- 下一课：[05 - 套接字检查](../05-sockets/) -- 使用 ss 检查网络连接

---

## 系列导航

[<- 03 - IP 路由](../03-routing/) | [系列首页](../) | [05 - 套接字检查 ->](../05-sockets/)
