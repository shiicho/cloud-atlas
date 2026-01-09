# 12 - 综合项目：多区域网络

> **目标**：综合运用所有知识，构建生产级三区域网络架构（Web-App-DB）  
> **前置**：完成 01-11 课全部内容  
> **时间**：90-120 分钟  
> **环境**：Linux（需要 root 权限，用于网络命名空间操作）  

---

## 将学到的内容

1. 设计三区域网络架构（Web/App/DB 三層構造）
2. 使用网络命名空间模拟独立区域
3. 配置 nftables 实现区域间访问控制
4. 实现跨区域路由和 DNS 解析
5. 创建健康检查脚本
6. 编写故障排查手册（運用手順書）

---

## 项目概述

### 业务场景

你是一家日本 IT 企业的基础设施工程师。公司要求按照「三層構造」安全架构搭建新的应用环境：

- **Web 区域**：面向互联网，运行 Nginx 反向代理
- **App 区域**：内部应用服务器，仅允许 Web 区访问
- **DB 区域**：数据库服务器，仅允许 App 区访问

### 安全要求

| 区域 | 允许的入站流量 | 禁止的入站流量 |
|------|---------------|---------------|
| Web Zone | 80/443 from internet, SSH from mgmt | - |
| App Zone | 8080 from Web Zone only | Internet direct access |
| DB Zone | 3306 from App Zone only | Internet, Web Zone |

---

## Step 1 - 先跑起来：一键部署三区域网络（15 分钟）

> **目标**：先运行脚本看到完整架构，再理解每个组件。  

### 1.1 克隆代码

```bash
# GitHub（海外用户）
git clone --filter=blob:none --sparse https://github.com/shiicho/cloud-atlas ~/cloud-atlas
cd ~/cloud-atlas && git sparse-checkout set foundations/linux/networking/12-capstone

# Gitee（中国大陆用户）
git clone --filter=blob:none --sparse https://gitee.com/shiicho/cloud-atlas ~/cloud-atlas
cd ~/cloud-atlas && git sparse-checkout set foundations/linux/networking/12-capstone
```

### 1.2 一键部署

```bash
cd ~/cloud-atlas/foundations/linux/networking/12-capstone/code

# 运行部署脚本（需要 root 权限）
sudo ./setup.sh
```

预期输出：

```
====================================================================
Multi-Zone Network Setup - Three-Tier Architecture
====================================================================

[1/6] Creating network namespaces...
      Created: zone-web
      Created: zone-app
      Created: zone-db

[2/6] Creating virtual bridge...
      Bridge zone-br0 created and activated

[3/6] Creating veth pairs and connecting zones...
      Connected zone-web to bridge (10.100.1.10/24)
      Connected zone-app to bridge (10.100.1.20/24)
      Connected zone-db to bridge (10.100.1.30/24)

[4/6] Configuring routing...
      Default routes configured for all zones

[5/6] Applying nftables firewall rules...
      zone-web: Allow 80/443/22, deny others
      zone-app: Allow 8080 from web only
      zone-db: Allow 3306 from app only

[6/6] Starting test services...
      zone-web: nginx listening on :80
      zone-app: python http.server on :8080
      zone-db: nc listening on :3306

====================================================================
Setup Complete! Run ./verify.sh to test the architecture.
====================================================================
```

### 1.3 验证架构

```bash
sudo ./verify.sh
```

预期输出：

```
====================================================================
Multi-Zone Network Verification
====================================================================

[Test 1] Web Zone accessible from outside (HTTP)
         curl 10.100.1.10:80 ... OK (200)

[Test 2] App Zone NOT accessible from outside
         curl 10.100.1.20:8080 ... OK (Connection refused/timeout)

[Test 3] Web -> App connection (port 8080)
         From zone-web: curl 10.100.1.20:8080 ... OK (200)

[Test 4] App -> DB connection (port 3306)
         From zone-app: nc -z 10.100.1.30 3306 ... OK (Open)

[Test 5] Web -> DB connection (should be blocked)
         From zone-web: nc -z 10.100.1.30 3306 ... OK (Blocked)

[Test 6] Outside -> DB connection (should be blocked)
         nc -z 10.100.1.30 3306 ... OK (Blocked)

====================================================================
All Tests Passed! Architecture is correctly configured.
====================================================================
```

**恭喜！你刚刚部署了一个生产级的三区域网络架构。** 接下来让我们理解每个组件是如何工作的。

---

## Step 2 - 发生了什么？架构详解（20 分钟）

### 2.1 整体架构图

<!-- DIAGRAM: three-zone-architecture -->
```
三区域网络架构（三層構造）
============================================================================

                            Internet
                               │
                               │ HTTP 80/443
                               ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                        Host Network (Default NS)                         │
│                                                                          │
│    ┌──────────────────────────────────────────────────────────────┐     │
│    │                     zone-br0 (Bridge)                         │     │
│    │                      10.100.1.0/24                            │     │
│    └───────┬─────────────────┬─────────────────┬──────────────────┘     │
│            │                 │                 │                         │
│     veth-web-br        veth-app-br       veth-db-br                     │
│            │                 │                 │                         │
│  ══════════╪═════════════════╪═════════════════╪══════════════════════  │
│            │                 │                 │                         │
│     veth-web-ns        veth-app-ns       veth-db-ns                     │
│            │                 │                 │                         │
│  ┌─────────┴───────┐ ┌──────┴────────┐ ┌──────┴────────┐               │
│  │   zone-web      │ │   zone-app    │ │   zone-db     │               │
│  │   (Namespace)   │ │   (Namespace) │ │   (Namespace) │               │
│  │                 │ │               │ │               │               │
│  │  10.100.1.10    │ │ 10.100.1.20   │ │ 10.100.1.30   │               │
│  │                 │ │               │ │               │               │
│  │  ┌───────────┐  │ │ ┌───────────┐ │ │ ┌───────────┐ │               │
│  │  │  Nginx    │  │ │ │  App Svc  │ │ │ │  DB Svc   │ │               │
│  │  │  :80/443  │  │ │ │  :8080    │ │ │ │  :3306    │ │               │
│  │  └───────────┘  │ │ └───────────┘ │ │ └───────────┘ │               │
│  │                 │ │               │ │               │               │
│  │  nftables:      │ │ nftables:     │ │ nftables:     │               │
│  │  - Allow 80/443 │ │ - Allow 8080  │ │ - Allow 3306  │               │
│  │    from any     │ │   from .10    │ │   from .20    │               │
│  │  - Allow 22     │ │   only        │ │   only        │               │
│  │    from mgmt    │ │ - Drop others │ │ - Drop others │               │
│  └─────────────────┘ └───────────────┘ └───────────────┘               │
│                                                                          │
│  Flow: Internet → Web (:80) → App (:8080) → DB (:3306)                  │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘

图例：
  ───────  物理/虚拟连接
  ═══════  命名空间边界
  ▶        允许的数据流向
```
<!-- /DIAGRAM -->

### 2.2 网络命名空间（Network Namespace）

每个区域使用独立的网络命名空间，实现网络栈隔离：

```bash
# 查看所有命名空间
sudo ip netns list
```

```
zone-db (id: 2)
zone-app (id: 1)
zone-web (id: 0)
```

每个命名空间拥有：
- 独立的网络接口
- 独立的路由表
- 独立的防火墙规则
- 独立的 /proc/net

```bash
# 在特定命名空间中执行命令
sudo ip netns exec zone-web ip addr show
sudo ip netns exec zone-app ss -tuln
```

### 2.3 虚拟网络设备

<!-- DIAGRAM: veth-bridge-connection -->
```
Veth Pair 和 Bridge 连接详解
============================================================================

Veth Pair（虚拟以太网对）：

    可以想象成一根虚拟网线，两端各有一个接口

    ┌─────────────┐                ┌─────────────┐
    │ veth-web-ns │◄═══════════════►│ veth-web-br │
    │ (在 zone-web│    虚拟网线     │ (在 bridge  │
    │  命名空间)  │                │  上)        │
    └─────────────┘                └─────────────┘

Bridge（虚拟交换机）：

    连接多个 veth 端点，实现二层转发

              zone-br0 (Bridge)
    ┌─────────────────────────────────────┐
    │                                     │
    │  ┌──────────┐ ┌──────────┐ ┌──────────┐
    │  │veth-web  │ │veth-app  │ │veth-db   │
    │  │  -br     │ │  -br     │ │  -br     │
    │  └────┬─────┘ └────┬─────┘ └────┬─────┘
    │       │            │            │       │
    └───────┼────────────┼────────────┼───────┘
            │            │            │
            ▼            ▼            ▼
        zone-web     zone-app     zone-db
       10.100.1.10   10.100.1.20  10.100.1.30

工作原理：
1. zone-web 发送到 10.100.1.20 的包
2. 包从 veth-web-ns 出去
3. 通过 veth pair 到达 veth-web-br
4. Bridge 查看 MAC 表，转发到 veth-app-br
5. 通过 veth pair 到达 zone-app 的 veth-app-ns
6. zone-app 收到包
```
<!-- /DIAGRAM -->

### 2.4 防火墙规则（nftables）

每个区域有独立的防火墙规则：

**Web Zone - 对外开放 HTTP/HTTPS**

```bash
sudo ip netns exec zone-web nft list ruleset
```

```nft
table inet filter {
    chain input {
        type filter hook input priority 0; policy drop;

        ct state established,related accept
        iif "lo" accept

        # Allow HTTP/HTTPS from anywhere
        tcp dport { 80, 443 } accept

        # Allow SSH from management network
        ip saddr 10.100.0.0/16 tcp dport 22 accept

        # ICMP for diagnostics
        icmp type echo-request accept
    }
}
```

**App Zone - 仅允许 Web Zone 访问**

```bash
sudo ip netns exec zone-app nft list ruleset
```

```nft
table inet filter {
    chain input {
        type filter hook input priority 0; policy drop;

        ct state established,related accept
        iif "lo" accept

        # Allow 8080 ONLY from Web Zone
        ip saddr 10.100.1.10 tcp dport 8080 accept

        # SSH from management
        ip saddr 10.100.0.0/16 tcp dport 22 accept
    }
}
```

**DB Zone - 仅允许 App Zone 访问**

```bash
sudo ip netns exec zone-db nft list ruleset
```

```nft
table inet filter {
    chain input {
        type filter hook input priority 0; policy drop;

        ct state established,related accept
        iif "lo" accept

        # Allow 3306 ONLY from App Zone
        ip saddr 10.100.1.20 tcp dport 3306 accept

        # SSH from management
        ip saddr 10.100.0.0/16 tcp dport 22 accept
    }
}
```

---

## Step 3 - 核心概念：三層構造安全模型（15 分钟）

### 3.1 为什么需要三层架构？

<!-- DIAGRAM: three-tier-security -->
```
三層構造セキュリティモデル（三层安全模型）
============================================================================

攻击场景分析：

场景 A：没有区域隔离
─────────────────────────────────────────────────────────────────────────
    攻击者                     服务器（全部在一个网络）
       │
       │  1. 攻击 Web 漏洞
       ├──────────────────────────────▶ Web Server ──┐
       │                                              │ 同一网络
       │  2. 利用 Web 权限直接访问 DB                 │ 无隔离
       └──────────────────────────────────────────────▶ DB Server
                                                        │
                                                   数据泄露！


场景 B：三层隔离架构
─────────────────────────────────────────────────────────────────────────
    攻击者
       │
       │  1. 攻击 Web 漏洞
       ├────────────────────────▶ Web Zone ─────┐
       │                         (可控损失)      │
       │                                        │ 防火墙
       │  2. 尝试直接访问 DB                    │ 阻断
       └─────────────── ✗ ──────────────────────┤
                                                │
                                App Zone ◀──────┘
                                   │
                                   │ 仅允许 App → DB
                                   ▼
                                DB Zone
                              (数据安全)


纵深防御（Defense in Depth）：
============================================================================

    Layer 1: 网络边界防火墙（Security Group / WAF）
         │
         ▼
    Layer 2: Web Zone 防火墙（nftables）
         │
         │  仅 80/443
         ▼
    Layer 3: App Zone 防火墙
         │
         │  仅 8080 from Web
         ▼
    Layer 4: DB Zone 防火墙
         │
         │  仅 3306 from App
         ▼
    Layer 5: 数据库认证
         │
         ▼
    数据

每一层都是一道防线，即使一层被突破，后面还有保护。
```
<!-- /DIAGRAM -->

### 3.2 日本 IT 企业的实践

在日本 IT 企業（特に金融・医療分野），三層構造是基本的安全要求：

| 日本語 | 中文 | 说明 |
|--------|------|------|
| 三層構造 | 三层架构 | Web-App-DB 分离 |
| DMZ | 非军事区 | Web Zone 所在区域 |
| 内部ネットワーク | 内部网络 | App/DB Zone |
| アクセス制御 | 访问控制 | nftables/Security Group |
| セグメンテーション | 网络分段 | VLAN 或 Namespace 隔离 |

### 3.3 最小权限原则

```
最小権限の原則（Principle of Least Privilege）

每个区域只开放必要的端口，只允许必要的来源访问：

┌─────────────────────────────────────────────────────────────────────┐
│                          Web Zone                                    │
│  允许：80/443 from ANY, 22 from mgmt                                 │
│  禁止：其他所有端口                                                  │
└─────────────────────────────────────────────────────────────────────┘
                              │
                              │ 仅 8080
                              ▼
┌─────────────────────────────────────────────────────────────────────┐
│                          App Zone                                    │
│  允许：8080 from 10.100.1.10 (Web), 22 from mgmt                    │
│  禁止：8080 from Internet, from DB Zone                              │
└─────────────────────────────────────────────────────────────────────┘
                              │
                              │ 仅 3306
                              ▼
┌─────────────────────────────────────────────────────────────────────┐
│                          DB Zone                                     │
│  允许：3306 from 10.100.1.20 (App), 22 from mgmt                    │
│  禁止：3306 from Internet, from Web Zone                             │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Step 4 - 动手实验：手动构建网络（30 分钟）

> **目标**：不使用脚本，手动构建整个架构，深入理解每个步骤。  

先清理自动部署的环境：

```bash
sudo ./cleanup.sh
```

### 4.1 创建网络命名空间

```bash
# 创建三个区域的命名空间
sudo ip netns add zone-web
sudo ip netns add zone-app
sudo ip netns add zone-db

# 验证
sudo ip netns list
```

### 4.2 创建虚拟网桥

```bash
# 创建 bridge
sudo ip link add zone-br0 type bridge

# 启用 bridge
sudo ip link set zone-br0 up

# 给 bridge 分配 IP（用于主机访问各区域）
sudo ip addr add 10.100.1.1/24 dev zone-br0

# 验证
ip addr show zone-br0
```

### 4.3 创建 Veth Pair 并连接区域

```bash
# Web Zone
sudo ip link add veth-web-ns type veth peer name veth-web-br
sudo ip link set veth-web-br master zone-br0
sudo ip link set veth-web-br up
sudo ip link set veth-web-ns netns zone-web
sudo ip netns exec zone-web ip link set veth-web-ns name eth0
sudo ip netns exec zone-web ip addr add 10.100.1.10/24 dev eth0
sudo ip netns exec zone-web ip link set eth0 up
sudo ip netns exec zone-web ip link set lo up

# App Zone
sudo ip link add veth-app-ns type veth peer name veth-app-br
sudo ip link set veth-app-br master zone-br0
sudo ip link set veth-app-br up
sudo ip link set veth-app-ns netns zone-app
sudo ip netns exec zone-app ip link set veth-app-ns name eth0
sudo ip netns exec zone-app ip addr add 10.100.1.20/24 dev eth0
sudo ip netns exec zone-app ip link set eth0 up
sudo ip netns exec zone-app ip link set lo up

# DB Zone
sudo ip link add veth-db-ns type veth peer name veth-db-br
sudo ip link set veth-db-br master zone-br0
sudo ip link set veth-db-br up
sudo ip link set veth-db-ns netns zone-db
sudo ip netns exec zone-db ip link set veth-db-ns name eth0
sudo ip netns exec zone-db ip addr add 10.100.1.30/24 dev eth0
sudo ip netns exec zone-db ip link set eth0 up
sudo ip netns exec zone-db ip link set lo up
```

### 4.4 配置路由

```bash
# 各区域添加默认路由
sudo ip netns exec zone-web ip route add default via 10.100.1.1
sudo ip netns exec zone-app ip route add default via 10.100.1.1
sudo ip netns exec zone-db ip route add default via 10.100.1.1

# 验证连通性（此时无防火墙，全部可通）
sudo ip netns exec zone-web ping -c 1 10.100.1.20
sudo ip netns exec zone-app ping -c 1 10.100.1.30
```

### 4.5 应用防火墙规则

```bash
# Web Zone 防火墙
sudo ip netns exec zone-web nft -f - << 'EOF'
flush ruleset

table inet filter {
    chain input {
        type filter hook input priority 0; policy drop;

        ct state established,related accept
        ct state invalid drop
        iif "lo" accept

        # HTTP/HTTPS from anywhere
        tcp dport { 80, 443 } accept comment "HTTP/HTTPS"

        # SSH from management network
        ip saddr 10.100.0.0/16 tcp dport 22 accept comment "SSH mgmt"

        # ICMP
        icmp type echo-request accept

        log prefix "[zone-web DROP] " limit rate 3/minute
    }

    chain output {
        type filter hook output priority 0; policy accept;
    }
}
EOF

# App Zone 防火墙
sudo ip netns exec zone-app nft -f - << 'EOF'
flush ruleset

table inet filter {
    chain input {
        type filter hook input priority 0; policy drop;

        ct state established,related accept
        ct state invalid drop
        iif "lo" accept

        # Port 8080 ONLY from Web Zone
        ip saddr 10.100.1.10 tcp dport 8080 accept comment "App from Web"

        # SSH from management
        ip saddr 10.100.0.0/16 tcp dport 22 accept comment "SSH mgmt"

        # ICMP for diagnostics
        icmp type echo-request accept

        log prefix "[zone-app DROP] " limit rate 3/minute
    }

    chain output {
        type filter hook output priority 0; policy accept;
    }
}
EOF

# DB Zone 防火墙
sudo ip netns exec zone-db nft -f - << 'EOF'
flush ruleset

table inet filter {
    chain input {
        type filter hook input priority 0; policy drop;

        ct state established,related accept
        ct state invalid drop
        iif "lo" accept

        # Port 3306 ONLY from App Zone
        ip saddr 10.100.1.20 tcp dport 3306 accept comment "DB from App"

        # SSH from management
        ip saddr 10.100.0.0/16 tcp dport 22 accept comment "SSH mgmt"

        # ICMP for diagnostics
        icmp type echo-request accept

        log prefix "[zone-db DROP] " limit rate 3/minute
    }

    chain output {
        type filter hook output priority 0; policy accept;
    }
}
EOF
```

### 4.6 启动测试服务

```bash
# Web Zone - 简单 HTTP 服务
sudo ip netns exec zone-web python3 -m http.server 80 --bind 0.0.0.0 &

# App Zone - 应用服务
sudo ip netns exec zone-app python3 -m http.server 8080 --bind 0.0.0.0 &

# DB Zone - 模拟数据库端口
sudo ip netns exec zone-db nc -l -k 3306 &
```

### 4.7 验证防火墙效果

```bash
# 测试 1：外部访问 Web Zone（应该成功）
curl -s -o /dev/null -w "%{http_code}" http://10.100.1.10:80
# 预期：200

# 测试 2：外部访问 App Zone（应该失败）
curl -s --connect-timeout 2 http://10.100.1.20:8080 2>&1 || echo "Blocked!"
# 预期：Blocked!

# 测试 3：Web -> App（应该成功）
sudo ip netns exec zone-web curl -s -o /dev/null -w "%{http_code}" http://10.100.1.20:8080
# 预期：200

# 测试 4：Web -> DB（应该失败）
sudo ip netns exec zone-web nc -z -w 2 10.100.1.30 3306 || echo "Blocked!"
# 预期：Blocked!

# 测试 5：App -> DB（应该成功）
sudo ip netns exec zone-app nc -z -w 2 10.100.1.30 3306 && echo "Connected!"
# 预期：Connected!
```

---

## Step 5 - 健康检查脚本（15 分钟）

### 5.1 创建检查脚本

健康检查是运维的关键环节。创建一个全面的检查脚本：

```bash
#!/bin/bash
# health-check.sh - Multi-Zone Network Health Check
# 用于日常运维巡检（運用監視）

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Zone IPs
WEB_IP="10.100.1.10"
APP_IP="10.100.1.20"
DB_IP="10.100.1.30"

TOTAL=0
PASSED=0
FAILED=0

check() {
    local name=$1
    local cmd=$2
    local expected=$3

    ((TOTAL++))

    if eval "$cmd" &>/dev/null; then
        result="success"
    else
        result="failed"
    fi

    if [[ "$result" == "$expected" ]]; then
        echo -e "${GREEN}[PASS]${NC} $name"
        ((PASSED++))
    else
        echo -e "${RED}[FAIL]${NC} $name (expected: $expected, got: $result)"
        ((FAILED++))
    fi
}

echo "======================================================================"
echo "Multi-Zone Network Health Check"
echo "Time: $(date '+%Y-%m-%d %H:%M:%S')"
echo "======================================================================"
echo ""

# Check namespaces exist
echo "--- Namespace Status ---"
for ns in zone-web zone-app zone-db; do
    check "Namespace $ns exists" "ip netns list | grep -q $ns" "success"
done
echo ""

# Check services running
echo "--- Service Status ---"
check "Web service (port 80)" "sudo ip netns exec zone-web ss -tuln | grep -q ':80 '" "success"
check "App service (port 8080)" "sudo ip netns exec zone-app ss -tuln | grep -q ':8080 '" "success"
check "DB service (port 3306)" "sudo ip netns exec zone-db ss -tuln | grep -q ':3306 '" "success"
echo ""

# Check connectivity (should work)
echo "--- Allowed Connections ---"
check "Host -> Web (HTTP 80)" "curl -s --connect-timeout 2 http://${WEB_IP}:80" "success"
check "Web -> App (HTTP 8080)" "sudo ip netns exec zone-web curl -s --connect-timeout 2 http://${APP_IP}:8080" "success"
check "App -> DB (TCP 3306)" "sudo ip netns exec zone-app nc -z -w 2 ${DB_IP} 3306" "success"
echo ""

# Check connectivity (should be blocked)
echo "--- Blocked Connections (Security Verification) ---"
check "Host -> App direct (blocked)" "curl -s --connect-timeout 2 http://${APP_IP}:8080" "failed"
check "Host -> DB direct (blocked)" "nc -z -w 2 ${DB_IP} 3306" "failed"
check "Web -> DB direct (blocked)" "sudo ip netns exec zone-web nc -z -w 2 ${DB_IP} 3306" "failed"
check "DB -> App (blocked)" "sudo ip netns exec zone-db nc -z -w 2 ${APP_IP} 8080" "failed"
echo ""

# Summary
echo "======================================================================"
echo -e "Total: $TOTAL | ${GREEN}Passed: $PASSED${NC} | ${RED}Failed: $FAILED${NC}"
if [[ $FAILED -eq 0 ]]; then
    echo -e "${GREEN}All checks passed! System is healthy.${NC}"
    exit 0
else
    echo -e "${RED}Some checks failed! Please investigate.${NC}"
    exit 1
fi
```

### 5.2 运行健康检查

```bash
chmod +x health-check.sh
sudo ./health-check.sh
```

预期输出：

```
======================================================================
Multi-Zone Network Health Check
Time: 2025-01-05 15:30:00
======================================================================

--- Namespace Status ---
[PASS] Namespace zone-web exists
[PASS] Namespace zone-app exists
[PASS] Namespace zone-db exists

--- Service Status ---
[PASS] Web service (port 80)
[PASS] App service (port 8080)
[PASS] DB service (port 3306)

--- Allowed Connections ---
[PASS] Host -> Web (HTTP 80)
[PASS] Web -> App (HTTP 8080)
[PASS] App -> DB (TCP 3306)

--- Blocked Connections (Security Verification) ---
[PASS] Host -> App direct (blocked)
[PASS] Host -> DB direct (blocked)
[PASS] Web -> DB direct (blocked)
[PASS] DB -> App (blocked)

======================================================================
Total: 13 | Passed: 13 | Failed: 0
All checks passed! System is healthy.
======================================================================
```

---

## Step 6 - 故障排查手册（10 分钟）

### 6.1 L3 -> L4 -> L7 排障流程

<!-- DIAGRAM: troubleshooting-workflow -->
```
故障排查工作流（障害対応フロー）
============================================================================

报告：「App Zone 访问 DB Zone 失败」

Step 1: L3 - 网络层检查
─────────────────────────────────────────────────────────────────────────
    ┌─────────────────────────────────────────────────────────────────┐
    │  # 从 App Zone ping DB Zone                                     │
    │  sudo ip netns exec zone-app ping -c 3 10.100.1.30              │
    │                                                                  │
    │  成功 → 网络可达，进入 L4 检查                                   │
    │  失败 → 检查：                                                   │
    │         - ip netns exec zone-app ip route  (路由表)              │
    │         - ip link show zone-br0            (Bridge 状态)         │
    │         - ip netns exec zone-db ip addr    (IP 配置)             │
    └─────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
Step 2: L4 - 传输层检查
─────────────────────────────────────────────────────────────────────────
    ┌─────────────────────────────────────────────────────────────────┐
    │  # 检查 DB Zone 端口是否监听                                     │
    │  sudo ip netns exec zone-db ss -tuln | grep 3306                │
    │                                                                  │
    │  有输出 → 服务在监听，检查防火墙                                 │
    │  无输出 → 服务未启动！启动服务                                   │
    │                                                                  │
    │  # 检查防火墙规则                                                │
    │  sudo ip netns exec zone-db nft list ruleset | grep 3306        │
    │                                                                  │
    │  # 检查来源 IP 是否被允许                                        │
    │  sudo ip netns exec zone-db nft list ruleset | grep 10.100.1.20 │
    └─────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
Step 3: L4 - 抓包分析
─────────────────────────────────────────────────────────────────────────
    ┌─────────────────────────────────────────────────────────────────┐
    │  # 在 DB Zone 抓包                                               │
    │  sudo ip netns exec zone-db tcpdump -i eth0 port 3306 -nn       │
    │                                                                  │
    │  # 同时从 App Zone 发起连接                                      │
    │  sudo ip netns exec zone-app nc -z 10.100.1.30 3306             │
    │                                                                  │
    │  看到 SYN 无 SYN-ACK → 防火墙丢弃或服务未响应                    │
    │  看到 RST           → 端口未监听或被 reject                      │
    │  看到完整握手       → L4 正常，问题在 L7                         │
    └─────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
Step 4: L7 - 应用层检查
─────────────────────────────────────────────────────────────────────────
    ┌─────────────────────────────────────────────────────────────────┐
    │  # 检查应用日志                                                  │
    │  journalctl -u mysql  # 或具体的应用日志                         │
    │                                                                  │
    │  # 检查应用配置                                                  │
    │  - 应用是否绑定到正确的 IP？                                     │
    │  - 应用是否配置了访问控制？                                      │
    │  - 认证是否正确？                                                │
    └─────────────────────────────────────────────────────────────────┘
```
<!-- /DIAGRAM -->

### 6.2 常见问题速查表

| 症状 | 可能原因 | 排查命令 |
|------|----------|----------|
| ping 不通 | 路由问题 | `ip netns exec zone-X ip route` |
| 连接超时 | 防火墙 DROP | `nft list ruleset \| grep dport` |
| 连接被拒绝 | 服务未启动 | `ss -tuln \| grep :PORT` |
| 只能本地访问 | 绑定 127.0.0.1 | `ss -tuln` 看 Local Address |
| 间歇性失败 | 资源耗尽 | `ss -s`, `cat /proc/net/sockstat` |

### 6.3 紧急恢复命令

```bash
# 紧急：清空所有防火墙规则（恢复连通性）
sudo ip netns exec zone-web nft flush ruleset
sudo ip netns exec zone-app nft flush ruleset
sudo ip netns exec zone-db nft flush ruleset

# 警告：这会移除所有安全规则！仅用于紧急情况。
# 恢复后立即重新应用规则：
sudo ./setup.sh
```

---

## Step 7 - 交付物清单

完成本项目后，你应该产出以下文件：

### 7.1 代码文件

```
12-capstone/
├── README.md           # 本文档
└── code/
    ├── setup.sh        # 一键部署脚本
    ├── cleanup.sh      # 清理脚本
    ├── verify.sh       # 验证脚本
    ├── nftables.nft    # 防火墙规则模板
    └── health-check.sh # 健康检查脚本
```

### 7.2 规则集文件（nftables.nft）

```nft
# =============================================================================
# Multi-Zone Network Firewall Rules
# Three-Tier Architecture: Web -> App -> DB
# =============================================================================

# Web Zone Rules
# Allow: HTTP/HTTPS from any, SSH from mgmt
# Deny: All other inbound

# App Zone Rules
# Allow: 8080 from Web Zone (10.100.1.10) only
# Deny: Direct internet access, access from DB Zone

# DB Zone Rules
# Allow: 3306 from App Zone (10.100.1.20) only
# Deny: Direct internet access, access from Web Zone
```

### 7.3 架构图

包含在本文档中的 ASCII 图表可导出为 PNG（使用 diagram-generator）。

### 7.4 运维手册

本文档的 Step 6 部分即为运维排障手册，可独立提取使用。

---

## 职场小贴士

### 日本 IT 常用术语

| 日本語 | 中文 | 本项目对应 |
|--------|------|-----------|
| 三層構造 | 三层架构 | Web-App-DB 分离 |
| セグメンテーション | 网络分段 | Network Namespace |
| アクセス制御リスト | 访问控制列表 | nftables rules |
| 手順書 | 操作手册 | 排障手册 |
| 障害対応 | 故障处理 | L3-L4-L7 workflow |
| エビデンス | 证据 | tcpdump 抓包 |
| 切り分け | 问题隔离 | 分层排查 |

### 面试常见问题

**Q: 本番ネットワーク設計で重要なポイントは？**

A: 4 点が重要です：
1. セキュリティゾーン分離（三層構造）- Web/App/DB を分離
2. 最小権限の通信許可 - 必要なポートのみ開放
3. 監視とログ - 健康チェックとアクセスログ
4. 障害時の切り分け手順書 - L3→L4→L7 の体系的な診断

**Q: このネットワーク構成の障害対応手順は？**

A: L3→L4→L7 の順で確認します：
1. L3: ping で経路確認、ip route でルーティング確認
2. L4: ss -tuln でポート確認、nft list でファイアウォール確認
3. L4: tcpdump でパケット到達を確認
4. L7: アプリケーションログを確認

**Q: nftables と iptables どちらを使うべき？**

A: 2025 年では nftables を推奨します。理由：
- RHEL 9、Ubuntu 22.04+ のデフォルト
- IPv4/IPv6 統合、アトミック更新
- iptables は maintenance mode

---

## 检查清单

完成本课后，确认你能够：

- [ ] 使用 `ip netns` 创建和管理网络命名空间
- [ ] 使用 veth pair 和 bridge 连接命名空间
- [ ] 编写 nftables 规则实现区域间访问控制
- [ ] 解释三层架构的安全意义
- [ ] 使用 L3→L4→L7 方法排查网络问题
- [ ] 编写健康检查脚本
- [ ] 编写故障排查手册
- [ ] 在面试中解释三層構造设计

---

## 评估标准

| 评估项 | 要求 | 验证方法 |
|--------|------|----------|
| Web Zone 可访问 | 80/443 对外开放 | `curl http://10.100.1.10` |
| App Zone 隔离 | 不能从外部直接访问 | `curl http://10.100.1.20` 失败 |
| DB Zone 隔离 | 仅 App Zone 可访问 | Web Zone 访问 3306 失败 |
| 规则集有注释 | 每条规则有 comment | `nft list ruleset` 检查 |
| 健康检查覆盖 | 检查所有关键连接 | 运行 `verify.sh` |
| 文档可用 | 排障手册可操作 | 按手册排查问题 |

---

## 延伸阅读

- [Linux Network Namespaces - man page](https://man7.org/linux/man-pages/man7/network_namespaces.7.html)
- [nftables Wiki](https://wiki.nftables.org/)
- [Docker Networking Internals](https://docs.docker.com/network/) - 基于相同原理
- [Kubernetes CNI](https://kubernetes.io/docs/concepts/extend-kubernetes/compute-storage-net/network-plugins/) - 进阶容器网络

---

## 清理环境

完成实验后，清理所有资源：

```bash
sudo ./cleanup.sh
```

---

## 课程完结

恭喜！你已完成 **Linux Networking** 全部 12 课的学习。

通过本课程，你掌握了：

| 模块 | 技能 |
|------|------|
| 基础 (01-03) | TCP/IP 模型、接口配置、IP 路由 |
| 服务 (04-05) | DNS 配置、套接字检查 |
| 防火墙 (06-07) | nftables、firewalld |
| 高级 (08-10) | tcpdump、SSH、网络命名空间 |
| 实战 (11-12) | 故障排查、生产架构 |

这些技能将直接应用于：
- **日常运维**：网络排障、防火墙配置
- **容器技术**：Docker/K8s 网络理解
- **云架构**：VPC、Security Group 设计
- **面试准备**：LPIC-2、RHCSA 考点覆盖

---

## 系列导航

[<- 11 - 故障排查工作流](../11-troubleshooting/) | [系列首页](../) | 课程完结
