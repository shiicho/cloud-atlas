# 08 - tcpdump 与抓包分析

> **目标**：使用 tcpdump 抓包分析网络问题，从"包到了吗"到"包的内容对吗"  
> **前置**：了解套接字检查（05）和防火墙配置（06-07）  
> **时间**：60 分钟  
> **环境**：任意 Linux 发行版（Ubuntu, AlmaLinux, Amazon Linux 均可）  

---

## 将学到的内容

1. 使用 tcpdump 捕获网络流量
2. 掌握常用过滤器（host、port、tcp）
3. 读懂 tcpdump 输出（3 次握手、RST、重传）
4. 保存抓包文件供 Wireshark 分析
5. 安全和权限考虑

---

## Step 1 - 先跑起来：抓你的第一个包（5 分钟）

> **目标**：先"尝到" tcpdump 的威力，再理解原理。  

打开终端，抓取到 Google DNS 的 ping 包：

### 1.1 启动 tcpdump

```bash
# 终端 1：启动 tcpdump（需要 root）
sudo tcpdump -i any -nn icmp -c 5
```

### 1.2 在另一个终端发送 ping

```bash
# 终端 2：发送 ping
ping -c 2 8.8.8.8
```

### 1.3 观察 tcpdump 输出

```
tcpdump: data link type LINUX_SLL2
tcpdump: verbose output suppressed, use -v or -vv for full protocol decode
listening on any, link-type LINUX_SLL2 (Linux cooked v2), snapshot length 262144 bytes
14:30:01.123456 eth0  Out IP 10.0.1.52 > 8.8.8.8: ICMP echo request, id 1234, seq 1, length 64
14:30:01.145678 eth0  In  IP 8.8.8.8 > 10.0.1.52: ICMP echo reply, id 1234, seq 1, length 64
14:30:02.124567 eth0  Out IP 10.0.1.52 > 8.8.8.8: ICMP echo request, id 1234, seq 2, length 64
14:30:02.146789 eth0  In  IP 8.8.8.8 > 10.0.1.52: ICMP echo reply, id 1234, seq 2, length 64
4 packets captured
```

**你看到了**：
- `Out` = 出站包（你发的 ping request）
- `In` = 入站包（收到的 reply）
- 每个包的时间戳、源/目的 IP、协议类型

**参数解释**：

| 参数 | 含义 |
|------|------|
| `-i any` | 监听所有接口 |
| `-nn` | 不解析主机名和端口名（更快、更准确） |
| `icmp` | 只抓 ICMP 协议（ping） |
| `-c 5` | 抓 5 个包后停止 |

---

**一条命令，看到了网络的真实流量！**

接下来，让我们抓取更有意义的 TCP 连接。

---

## Step 2 - 发生了什么？TCP 三次握手详解（15 分钟）

### 2.1 抓取 TCP 连接过程

```bash
# 终端 1：抓取到 80 端口的 TCP 流量
sudo tcpdump -i any -nn port 80 -c 10
```

```bash
# 终端 2：发起 HTTP 请求
curl -I http://example.com
```

### 2.2 观察三次握手

```
14:30:01.001 IP 10.0.1.52.45678 > 93.184.216.34.80: Flags [S], seq 100, win 64240, length 0
14:30:01.050 IP 93.184.216.34.80 > 10.0.1.52.45678: Flags [S.], seq 200, ack 101, win 65535, length 0
14:30:01.051 IP 10.0.1.52.45678 > 93.184.216.34.80: Flags [.], ack 201, win 64240, length 0
```

### 2.3 理解 TCP Flags

<!-- DIAGRAM: tcp-three-way-handshake -->
```
TCP 三次握手
════════════════════════════════════════════════════════════════════

    客户端 (10.0.1.52)                      服务器 (93.184.216.34)
         │                                        │
         │  ────────── [S] SYN ──────────▶       │  第 1 步：客户端发起连接
         │             seq=100                    │  "你好，我想建立连接"
         │                                        │
         │  ◀──────── [S.] SYN+ACK ─────────     │  第 2 步：服务器同意
         │            seq=200, ack=101            │  "好的，我准备好了"
         │                                        │
         │  ────────── [.] ACK ──────────▶       │  第 3 步：客户端确认
         │            ack=201                     │  "收到，开始传数据"
         │                                        │
         ╔══════════════════════════════════════╗
         ║       连接建立 - ESTABLISHED          ║
         ╚══════════════════════════════════════╝

tcpdump Flags 对照表：
───────────────────────────────────────────────────────────────────
  [S]   = SYN        发起连接
  [S.]  = SYN+ACK    同意连接
  [.]   = ACK        确认（小数点表示 ACK）
  [P.]  = PSH+ACK    推送数据
  [F.]  = FIN+ACK    关闭连接
  [R]   = RST        重置/拒绝
  [R.]  = RST+ACK    重置+确认
```
<!-- /DIAGRAM -->

### 2.4 常见的 Flag 组合

| Flags | 含义 | 何时出现 |
|-------|------|----------|
| `[S]` | SYN | 客户端发起连接 |
| `[S.]` | SYN+ACK | 服务器同意连接 |
| `[.]` | ACK | 确认包（数据传输中常见） |
| `[P.]` | PSH+ACK | 有数据要发送 |
| `[F.]` | FIN+ACK | 关闭连接 |
| `[R]` | RST | 连接被拒绝/重置 |

---

## Step 3 - 核心概念：tcpdump 常用选项和过滤器（15 分钟）

### 3.1 必会的命令选项

```bash
# 最常用组合
sudo tcpdump -i eth0 -nn -tttt -vv

# 选项详解
-i eth0     # 指定网卡（重要！多网卡服务器必须指定）
-nn         # 不解析主机名和端口（8.8.8.8 而不是 dns.google）
-tttt       # 人类可读的时间戳（2026-01-05 14:30:01.123456）
-v/-vv/-vvv # 详细程度（越多越详细）
-c 100      # 只抓 100 个包
-s 0        # 抓完整包（不截断）
-w file.pcap # 保存到文件
-r file.pcap # 从文件读取
```

### 3.2 基础过滤器

```bash
# 按主机过滤
sudo tcpdump -i eth0 -nn host 192.168.1.100        # 源或目的是这个 IP
sudo tcpdump -i eth0 -nn src host 192.168.1.100    # 只看源 IP
sudo tcpdump -i eth0 -nn dst host 192.168.1.100    # 只看目的 IP

# 按端口过滤
sudo tcpdump -i eth0 -nn port 80                   # 源或目的端口是 80
sudo tcpdump -i eth0 -nn src port 80               # 源端口是 80
sudo tcpdump -i eth0 -nn dst port 443              # 目的端口是 443

# 按协议过滤
sudo tcpdump -i eth0 -nn tcp                       # 只看 TCP
sudo tcpdump -i eth0 -nn udp                       # 只看 UDP
sudo tcpdump -i eth0 -nn icmp                      # 只看 ICMP
```

### 3.3 组合过滤器

```bash
# and - 同时满足
sudo tcpdump -i eth0 -nn host 192.168.1.100 and port 443

# or - 满足其一
sudo tcpdump -i eth0 -nn 'port 80 or port 443'

# not - 排除
sudo tcpdump -i eth0 -nn not port 22               # 排除 SSH（避免干扰）

# 复杂组合（用括号，需要转义或引号）
sudo tcpdump -i eth0 -nn 'host 192.168.1.100 and (port 80 or port 443)'
```

### 3.4 高级过滤：只抓 SYN 包

```bash
# 只抓新连接的 SYN 包（不包括 SYN-ACK）
sudo tcpdump -i eth0 -nn 'tcp[tcpflags] == tcp-syn'

# 抓所有带 SYN 标志的包（包括 SYN-ACK）
sudo tcpdump -i eth0 -nn 'tcp[tcpflags] & tcp-syn != 0'

# 只抓 RST 包（排查连接拒绝）
sudo tcpdump -i eth0 -nn 'tcp[tcpflags] & tcp-rst != 0'
```

**TCP Flag 值参考**：

| Flag | 十进制值 | 符号名 |
|------|----------|--------|
| FIN | 1 | tcp-fin |
| SYN | 2 | tcp-syn |
| RST | 4 | tcp-rst |
| PSH | 8 | tcp-push |
| ACK | 16 | tcp-ack |
| URG | 32 | tcp-urg |

---

## Step 4 - 识别问题：三种常见故障模式（15 分钟）

### 4.1 正常连接 vs 故障连接

<!-- DIAGRAM: tcpdump-connection-patterns -->
```
tcpdump 输出模式：快速判断问题类型
════════════════════════════════════════════════════════════════════

场景 A：正常连接（三次握手成功）
─────────────────────────────────────────────────────────────────────
  客户端                                      服务器
     │  ─────── [S] ────────▶                  │
     │  ◀────── [S.] ───────                   │  ✓ 连接建立
     │  ─────── [.] ────────▶                  │
     │  ◀─────── 数据 ───────                  │


场景 B：Connection Refused（端口没监听 / 防火墙 REJECT）
─────────────────────────────────────────────────────────────────────
  客户端                                      服务器
     │  ─────── [S] ────────▶                  │
     │  ◀────── [R.] ───────                   │  ✗ 立即收到 RST
     │                                         │
  诊断：服务没启动，或防火墙 REJECT 规则


场景 C：Timeout / 超时（防火墙 DROP）
─────────────────────────────────────────────────────────────────────
  客户端                                      服务器
     │  ─────── [S] ────────▶                  │
     │       （等待...）                        │  ✗ 无响应
     │  ─────── [S] ────────▶  重传 1          │
     │       （等待...）                        │  ✗ 无响应
     │  ─────── [S] ────────▶  重传 2          │
     │                                         │
  诊断：防火墙 DROP，路由问题，或服务器宕机


场景 D：重传（网络质量差）
─────────────────────────────────────────────────────────────────────
  客户端                                      服务器
     │  ─────── [P.] seq=1000 ──▶              │
     │       （等待...）                        │  ✗ 没收到 ACK
     │  ─────── [P.] seq=1000 ──▶  重传        │
     │  ◀────── [.] ack=1460 ────               │  ✓ 终于收到
     │                                         │
  诊断：网络丢包、拥塞、或对端处理慢
```
<!-- /DIAGRAM -->

### 4.2 实验：观察 Connection Refused

```bash
# 终端 1：抓包
sudo tcpdump -i any -nn port 9999

# 终端 2：连接一个没开的端口
curl http://localhost:9999
```

**你会看到**：
```
14:30:01.001 IP 127.0.0.1.45678 > 127.0.0.1.9999: Flags [S], seq 100, win 65495, length 0
14:30:01.001 IP 127.0.0.1.9999 > 127.0.0.1.45678: Flags [R.], seq 0, ack 101, win 0, length 0
```

**解读**：客户端发 SYN，立即收到 RST（Reset）= 端口没监听。

### 4.3 实验：观察 Timeout（防火墙 DROP）

```bash
# 如果有防火墙规则 DROP 某个端口，会看到：
14:30:01.001 IP 10.0.1.52.45678 > 10.0.2.100.3306: Flags [S], seq 100, win 64240, length 0
14:30:02.003 IP 10.0.1.52.45678 > 10.0.2.100.3306: Flags [S], seq 100, win 64240, length 0
14:30:04.007 IP 10.0.1.52.45678 > 10.0.2.100.3306: Flags [S], seq 100, win 64240, length 0
14:30:08.015 IP 10.0.1.52.45678 > 10.0.2.100.3306: Flags [S], seq 100, win 64240, length 0
```

**解读**：
- **同一个 seq 号重复出现** = SYN 重传
- **时间间隔指数增长**（1s, 2s, 4s...）= TCP 重传退避
- **没有任何响应** = 防火墙 DROP 或路由黑洞

### 4.4 快速诊断表

| tcpdump 现象 | 可能原因 | 下一步检查 |
|--------------|----------|------------|
| SYN 后立即 RST | 端口没监听 | `ss -tuln` 检查服务 |
| SYN 后立即 RST | 防火墙 REJECT | `firewall-cmd --list-all` |
| SYN 无响应，不断重传 | 防火墙 DROP | 检查两端防火墙 |
| SYN 无响应 | 路由问题 | `traceroute` 检查路径 |
| 数据包重传 | 网络丢包/拥塞 | 检查网络设备 |

---

## Step 5 - 保存抓包文件与 Wireshark（5 分钟）

### 5.1 保存为 pcap 文件

```bash
# 保存抓包（-w = write）
sudo tcpdump -i eth0 -nn -s 0 -w capture.pcap

# 限制抓包数量或时间
sudo tcpdump -i eth0 -nn -s 0 -c 1000 -w capture.pcap    # 1000 个包
timeout 60 sudo tcpdump -i eth0 -nn -s 0 -w capture.pcap # 60 秒

# 只抓特定流量（减小文件）
sudo tcpdump -i eth0 -nn -s 0 host 192.168.1.100 and port 443 -w https.pcap
```

### 5.2 从文件读取

```bash
# 读取 pcap 文件
tcpdump -nn -r capture.pcap

# 读取时再过滤
tcpdump -nn -r capture.pcap port 443
tcpdump -nn -r capture.pcap 'tcp[tcpflags] & tcp-rst != 0'
```

### 5.3 tcpdump vs Wireshark 使用场景

| 场景 | 使用 tcpdump | 使用 Wireshark |
|------|--------------|----------------|
| 远程服务器（无 GUI） | Yes | No |
| 快速验证流量 | Yes | No |
| 脚本/自动化 | Yes | No |
| 深度协议分析 | 只负责抓包 | Yes |
| 跟踪 TCP 流 | No | Yes |
| 可视化分析 | No | Yes |

**最佳实践**：服务器上用 tcpdump 抓包，下载到本地用 Wireshark 分析。

```bash
# 从远程服务器下载 pcap 文件
scp server:/tmp/capture.pcap ./

# 或者边抓边传（实时分析）
ssh server 'sudo tcpdump -i eth0 -nn -s 0 -w -' | wireshark -k -i -
```

---

## Step 6 - 权限和安全考虑（5 分钟）

### 6.1 权限要求

tcpdump 需要读取网络接口的原始数据包，有两种方式：

```bash
# 方式 1：使用 sudo（推荐）
sudo tcpdump -i eth0 -nn

# 方式 2：使用 Linux Capabilities（无需完整 root）
sudo setcap cap_net_raw,cap_net_admin=eip $(which tcpdump)
# 之后普通用户可以运行
tcpdump -i eth0 -nn
```

### 6.2 生产环境注意事项

**DO（应该做）**：
- 使用 `-c` 限制包数量
- 使用过滤器缩小范围
- 抓完就停止，不要长时间运行
- 分析完后删除 pcap 文件

**DON'T（不要做）**：
- 在高流量接口无过滤地抓包（性能影响）
- 把包含敏感数据的 pcap 提交到 Git
- 未经授权在他人网络抓包（违法）
- 忘记 `-nn`（DNS 解析会拖慢速度）

### 6.3 日本 IT 职场提示

在日本企业环境中抓包需要注意：

```
抓包工作流程（日本企业标准）
════════════════════════════════════════════════════════════════════

1. 报告（報告）
   └── 创建障害票（incident ticket）
   └── 获取上级/チームリーダー批准

2. 抓包（キャプチャ）
   └── 只抓相关流量，不要大范围抓
   └── 记录开始/结束时间
   └── 保存抓包命令作为证据

3. 分析（分析）
   └── 本地分析，不要在生产服务器上长时间操作
   └── 截图关键发现

4. 报告结果（結果報告）
   └── 附上分析摘要（不是原始 pcap）
   └── 删除 pcap 文件

5. エビデンス保存
   └── 把命令和关键输出记录到 ticket
```

---

## Step 7 - 故障实验室：SYN 风暴诊断（10 分钟）

> **场景**：监控系统报警"大量 SYN 但服务无法连接"，你需要排查。  

### 7.1 问题现象

```bash
# 同事报告的问题
curl http://192.168.1.100:8080
# curl: (7) Failed to connect to 192.168.1.100 port 8080: Connection timed out
```

### 7.2 诊断步骤

**Step A：在客户端抓包确认 SYN 是否发出**

```bash
# 客户端
sudo tcpdump -i eth0 -nn host 192.168.1.100 and port 8080
```

```
14:30:01.001 IP 10.0.1.52.45678 > 192.168.1.100.8080: Flags [S], seq 100, win 64240, length 0
14:30:02.003 IP 10.0.1.52.45678 > 192.168.1.100.8080: Flags [S], seq 100, win 64240, length 0
14:30:04.007 IP 10.0.1.52.45678 > 192.168.1.100.8080: Flags [S], seq 100, win 64240, length 0
```

**结论**：SYN 发出了，但没有响应。

**Step B：在服务器端抓包确认是否收到**

```bash
# 服务器端
sudo tcpdump -i eth0 -nn port 8080
```

**情况 1**：服务器端看到 SYN
```
14:30:01.002 IP 10.0.1.52.45678 > 192.168.1.100.8080: Flags [S], ...
```
→ 包到了服务器，问题在服务器端（防火墙 DROP 或服务没监听）

**情况 2**：服务器端看不到任何包
→ 包没到服务器，问题在网络路径（路由、中间防火墙）

**Step C：检查服务和防火墙**

```bash
# 检查服务是否监听
ss -tuln | grep 8080

# 检查防火墙
sudo firewall-cmd --list-all
sudo nft list ruleset | grep 8080
```

### 7.3 根因分析示例

<!-- DIAGRAM: syn-flood-diagnosis -->
```
SYN 无响应问题诊断流程
════════════════════════════════════════════════════════════════════

                    ┌─────────────────────────────┐
                    │ 客户端发 SYN，无响应        │
                    │ tcpdump 只看到 SYN 重传     │
                    └─────────────┬───────────────┘
                                  │
                                  ▼
                    ┌─────────────────────────────┐
                    │ 服务器端抓包                │
                    │ sudo tcpdump -i eth0 ...    │
                    └─────────────┬───────────────┘
                                  │
                    ┌─────────────┴─────────────┐
                    │                           │
             看到 SYN ▼                   看不到 SYN ▼
        ┌───────────────────┐         ┌───────────────────┐
        │ 包到了服务器      │         │ 包没到服务器      │
        └─────────┬─────────┘         └─────────┬─────────┘
                  │                             │
                  ▼                             ▼
        ┌───────────────────┐         ┌───────────────────┐
        │ 检查 ss -tuln     │         │ 检查网络路径      │
        │ 服务在监听？      │         │ traceroute 目标   │
        └─────────┬─────────┘         │ 中间设备防火墙？  │
                  │                   └───────────────────┘
           ┌──────┴──────┐
           │             │
        没监听 ▼      在监听 ▼
   ┌─────────────┐  ┌─────────────────┐
   │ 启动服务！  │  │ 检查 OS 防火墙  │
   │             │  │ nft list ruleset│
   └─────────────┘  │ DROP 规则？     │
                    └─────────────────┘
```
<!-- /DIAGRAM -->

---

## Mini Project：连接问题诊断工具

### 项目说明

编写一个脚本，自动抓包诊断"无法连接服务"问题，生成证据报告。

### 代码实现

创建文件 `connection-diag.sh`：

```bash
#!/bin/bash
# 连接问题诊断工具
# 用于障害対応（incident response）时快速收集证据

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 参数检查
if [ $# -lt 2 ]; then
    echo "用法: $0 <目标IP> <端口>"
    echo "示例: $0 192.168.1.100 8080"
    exit 1
fi

TARGET_IP=$1
TARGET_PORT=$2
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
REPORT_FILE="conn_diag_${TARGET_IP}_${TARGET_PORT}_${TIMESTAMP}.txt"
PCAP_FILE="conn_diag_${TARGET_IP}_${TARGET_PORT}_${TIMESTAMP}.pcap"

echo -e "${BLUE}======================================${NC}"
echo -e "${BLUE}连接问题诊断工具${NC}"
echo -e "${BLUE}目标: ${TARGET_IP}:${TARGET_PORT}${NC}"
echo -e "${BLUE}======================================${NC}"
echo ""

# 初始化报告
{
    echo "# 连接诊断报告"
    echo "# 目标: ${TARGET_IP}:${TARGET_PORT}"
    echo "# 时间: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "# 诊断主机: $(hostname)"
    echo ""
} > "$REPORT_FILE"

# Step 1: 基础连通性
echo -e "${YELLOW}[Step 1] 基础连通性检查...${NC}"
{
    echo "## Step 1: 基础连通性"
    echo ""
    echo "### ping 测试"
    echo '```'
    ping -c 3 "$TARGET_IP" 2>&1 || true
    echo '```'
    echo ""
} >> "$REPORT_FILE"

# Step 2: 路由检查
echo -e "${YELLOW}[Step 2] 路由检查...${NC}"
{
    echo "## Step 2: 路由信息"
    echo ""
    echo "### ip route get"
    echo '```'
    ip route get "$TARGET_IP" 2>&1 || true
    echo '```'
    echo ""
} >> "$REPORT_FILE"

# Step 3: 本地防火墙检查
echo -e "${YELLOW}[Step 3] 本地防火墙检查...${NC}"
{
    echo "## Step 3: 本地防火墙"
    echo ""
    if command -v firewall-cmd &> /dev/null; then
        echo "### firewalld 状态"
        echo '```'
        sudo firewall-cmd --list-all 2>&1 || true
        echo '```'
    elif command -v nft &> /dev/null; then
        echo "### nftables 规则"
        echo '```'
        sudo nft list ruleset 2>&1 | head -50 || true
        echo '```'
    fi
    echo ""
} >> "$REPORT_FILE"

# Step 4: 抓包诊断（核心步骤）
echo -e "${YELLOW}[Step 4] 抓包诊断（5秒）...${NC}"
{
    echo "## Step 4: 抓包分析"
    echo ""
} >> "$REPORT_FILE"

# 后台启动 tcpdump
sudo tcpdump -i any -nn host "$TARGET_IP" and port "$TARGET_PORT" -c 20 -w "$PCAP_FILE" 2>/dev/null &
TCPDUMP_PID=$!
sleep 1

# 发起连接尝试
echo -e "  发起 TCP 连接尝试..."
timeout 5 bash -c "echo '' | nc -v -w 3 $TARGET_IP $TARGET_PORT" 2>&1 || true
sleep 2

# 停止 tcpdump
sudo kill $TCPDUMP_PID 2>/dev/null || true
wait $TCPDUMP_PID 2>/dev/null || true

# 分析抓包结果
{
    echo "### tcpdump 输出"
    echo '```'
    if [ -f "$PCAP_FILE" ]; then
        tcpdump -nn -r "$PCAP_FILE" 2>&1 || echo "无法读取 pcap 文件"
    else
        echo "未捕获到数据包"
    fi
    echo '```'
    echo ""
} >> "$REPORT_FILE"

# Step 5: 分析和结论
echo -e "${YELLOW}[Step 5] 生成分析结论...${NC}"
{
    echo "## Step 5: 诊断结论"
    echo ""

    if [ -f "$PCAP_FILE" ]; then
        # 检查是否有 RST
        RST_COUNT=$(tcpdump -nn -r "$PCAP_FILE" 'tcp[tcpflags] & tcp-rst != 0' 2>/dev/null | wc -l)
        # 检查是否有 SYN-ACK
        SYNACK_COUNT=$(tcpdump -nn -r "$PCAP_FILE" 'tcp[tcpflags] == (tcp-syn|tcp-ack)' 2>/dev/null | wc -l)
        # 检查 SYN 数量
        SYN_COUNT=$(tcpdump -nn -r "$PCAP_FILE" 'tcp[tcpflags] == tcp-syn' 2>/dev/null | wc -l)

        if [ "$SYNACK_COUNT" -gt 0 ]; then
            echo "**结论**: 连接成功建立"
            echo "- 观察到 SYN-ACK 响应"
            echo "- 服务端正常响应"
        elif [ "$RST_COUNT" -gt 0 ]; then
            echo "**结论**: Connection Refused"
            echo "- 观察到 RST 响应"
            echo "- 可能原因："
            echo "  - 服务未启动（检查 ss -tuln）"
            echo "  - 防火墙 REJECT 规则"
        elif [ "$SYN_COUNT" -gt 0 ]; then
            echo "**结论**: Connection Timeout"
            echo "- 发送了 $SYN_COUNT 个 SYN，无响应"
            echo "- 可能原因："
            echo "  - 防火墙 DROP 规则"
            echo "  - 网络路由问题"
            echo "  - 目标服务器宕机"
        else
            echo "**结论**: 无法建立连接"
            echo "- 未捕获到相关数据包"
            echo "- 检查本地网络配置"
        fi
    else
        echo "**结论**: 诊断失败"
        echo "- 未能捕获数据包"
    fi
    echo ""
} >> "$REPORT_FILE"

# 输出结果
echo ""
echo -e "${GREEN}======================================${NC}"
echo -e "${GREEN}诊断完成！${NC}"
echo -e "${GREEN}======================================${NC}"
echo ""
echo -e "报告文件: ${BLUE}$REPORT_FILE${NC}"
if [ -f "$PCAP_FILE" ]; then
    echo -e "抓包文件: ${BLUE}$PCAP_FILE${NC}"
fi
echo ""
echo -e "${YELLOW}报告内容预览:${NC}"
echo "--------------------------------------"
tail -20 "$REPORT_FILE"
```

### 使用方法

```bash
# 添加执行权限
chmod +x connection-diag.sh

# 运行诊断
sudo ./connection-diag.sh 192.168.1.100 8080
```

### 示例输出

```
======================================
连接问题诊断工具
目标: 192.168.1.100:8080
======================================

[Step 1] 基础连通性检查...
[Step 2] 路由检查...
[Step 3] 本地防火墙检查...
[Step 4] 抓包诊断（5秒）...
  发起 TCP 连接尝试...
[Step 5] 生成分析结论...

======================================
诊断完成！
======================================

报告文件: conn_diag_192.168.1.100_8080_20260105_143000.txt
抓包文件: conn_diag_192.168.1.100_8080_20260105_143000.pcap

报告内容预览:
--------------------------------------
## Step 5: 诊断结论

**结论**: Connection Timeout
- 发送了 3 个 SYN，无响应
- 可能原因：
  - 防火墙 DROP 规则
  - 网络路由问题
  - 目标服务器宕机
```

---

## 职场小贴士

### 日本 IT 常用术语

| 日本語 | 中文 | 场景 |
|--------|------|------|
| パケットキャプチャ | 抓包 | tcpdump 作业 |
| 三ウェイハンドシェイク | 三次握手 | TCP 连接 |
| 疎通確認 | 连通性确认 | ping/telnet 测试 |
| エビデンス | 证据 | 保存的 pcap 文件 |
| ドロップ | DROP/丢弃 | 防火墙规则 |
| リセット | Reset/RST | 连接拒绝 |
| 再送 | 重传 | TCP retransmission |

### 面试常见问题

**Q: tcpdump で TCP 接続問題を診断する手順は？**

A: まず `tcpdump -i eth0 -nn port <ポート>` でキャプチャを開始し、SYN/SYN-ACK/ACK の 3 ウェイハンドシェイクを確認します。SYN のみで応答がない場合はドロップ、SYN に対して RST が返る場合は接続拒否です。両端（クライアント側とサーバ側）でキャプチャすることで、どこで問題が発生しているか切り分けできます。

**Q: tcpdump と Wireshark の使い分けは？**

A: tcpdump は CLI ツールでサーバ上でのキャプチャに適しています。`-w` オプションで pcap 形式で保存し、それを Wireshark で GUI 分析するのがベストプラクティスです。複雑なプロトコル解析や TCP ストリーム追跡は Wireshark が得意です。

**Q: 本番環境でパケットキャプチャする際の注意点は？**

A: 事前に承認を得ること、フィルタを使って必要最小限のトラフィックのみキャプチャすること、パフォーマンスへの影響を考慮して `-c` で数量制限すること、機密情報を含む可能性があるため分析後は pcap ファイルを削除することが重要です。

---

## 本课小结

| 你学到的 | 命令/概念 |
|----------|-----------|
| 基本抓包 | `sudo tcpdump -i eth0 -nn` |
| 指定主机和端口 | `host 192.168.1.100 and port 80` |
| 组合过滤器 | `and`, `or`, `not`, 括号 |
| 只抓 SYN | `'tcp[tcpflags] == tcp-syn'` |
| 只抓 RST | `'tcp[tcpflags] & tcp-rst != 0'` |
| 保存文件 | `-w capture.pcap` |
| 读取文件 | `-r capture.pcap` |

**核心诊断模式**：

```
正常连接：  [S] → [S.] → [.]    三次握手完成
连接拒绝：  [S] → [R.]          立即收到 RST
超时/DROP： [S] → [S] → [S]     SYN 不断重传，无响应
网络丢包：  同一 seq 重复出现    数据包重传
```

---

## 反模式警示

| 错误做法 | 正确做法 |
|----------|----------|
| 多网卡服务器不指定 `-i` 接口 | 明确指定 `-i eth0` 或具体接口 |
| 只从服务器端抓包 | 客户端 + 服务器端双向抓包 |
| 不保存 pcap 就开始改配置 | 先 `-w` 保存证据，再改配置 |
| 忘记 `-nn` 导致 DNS 解析慢 | 始终使用 `-nn` |
| 无限制地抓高流量接口 | 使用 `-c` 限制数量，使用过滤器 |

---

## 检查清单

在继续下一课之前，确认你能：

- [ ] 使用 `tcpdump -i eth0 -nn` 抓取基本流量
- [ ] 使用 `host` 和 `port` 过滤器
- [ ] 组合使用 `and`、`or`、`not`
- [ ] 读懂三次握手输出（`[S]` → `[S.]` → `[.]`）
- [ ] 识别 Connection Refused（RST 响应）
- [ ] 识别 Timeout（SYN 重传无响应）
- [ ] 使用 `-w` 保存 pcap 文件
- [ ] 解释为什么需要双端抓包

---

## 延伸阅读

- [tcpdump man page](https://www.tcpdump.org/manpages/tcpdump.1.html)
- [Wireshark 官方文档](https://www.wireshark.org/docs/)
- [Daniel Miessler tcpdump Tutorial](https://danielmiessler.com/study/tcpdump/)
- [Red Hat - Troubleshooting Network Issues with tcpdump](https://www.redhat.com/sysadmin/troubleshoot-tcpdump)

---

## 下一步

你已经学会了使用 tcpdump 抓包分析网络问题。这是网络故障排查的核心技能。接下来，让我们深入学习 SSH 的高级用法——密钥管理、隧道和跳板机。

[09 - SSH 深入 ->](../09-ssh/)

---

## 系列导航

[<- 07 - firewalld 区域](../07-firewalld/) | [Home](/) | [09 - SSH 深入 ->](../09-ssh/)
