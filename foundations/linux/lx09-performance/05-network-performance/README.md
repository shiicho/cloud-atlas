# 05 - 网络性能（Network Performance）

> **目标**：使用 ss、iperf3、tcpdump 分析网络性能瓶颈，建立网络基线  
> **前置**：LX09-01 USE Method、LX06 网络基础（ss、TCP/IP）  
> **时间**：90-120 分钟  
> **实战场景**：タイムセール時のスループット問題調査、ECサイト運用  

---

## 将学到的内容

1. 理解网络性能四大指标：Bandwidth、Latency、Packet Loss、Jitter
2. 使用 ss 命令深入分析 socket 状态和队列深度
3. 使用 iperf3 建立网络基线（TCP/UDP 吞吐量）
4. 使用 ip -s link 和 ethtool -S 检查接口统计
5. 理解 TCP 缓冲区调优基础（net.ipv4.tcp_rmem/wmem）
6. 使用 tcpdump 从性能角度分析延迟和重传

---

## 先跑起来！（10 分钟）

> 在深入理论之前，先体验网络性能数据采集。  
> 运行这些命令，观察输出 — 这就是你将要系统化掌握的技能。  

```bash
# Socket 统计摘要 — 整体连接状态
ss -s

# 详细 TCP 连接状态 — 谁在通信？
ss -ntp state established | head -20

# 查看 socket 队列深度 — 有数据堆积吗？
ss -ntp | awk '$2 > 0 || $3 > 0 {print}' | head -10

# 网络接口统计 — 有丢包/错误吗？
ip -s link show | head -30

# TCP 内部信息 — 重传、RTT、cwnd
ss -ti state established | head -20
```

**你刚刚捕获了系统的网络性能快照！**

- `ss -s` 告诉你连接总数和各状态分布
- `ss -ntp` 显示每个连接的详细信息
- `Recv-Q/Send-Q` 显示 socket 队列深度（数据堆积情况）
- `ip -s link` 显示接口级别的包计数、错误、丢弃
- `ss -ti` 显示 TCP 内部状态（重传、RTT、拥塞窗口）

**这些数字意味着什么？正常还是异常？**

让我们用 USE Method 系统性地分析网络性能。

---

## Step 1 - 网络性能的 USE Method 视角（10 分钟）

### 1.1 回顾 USE Method

在 [Lesson 01](../01-use-methodology/) 中，我们学习了 USE Method。对于网络资源：

| 维度 | 网络含义 | 检查命令 |
|------|----------|----------|
| **U**tilization | 带宽使用率 | `ip -s link`, `sar -n DEV`, `ethtool -S` |
| **S**aturation | Socket 队列深度、连接排队 | `ss -nmp`, `netstat -s (overflows)` |
| **E**rrors | 丢包、重传、CRC 错误 | `ip -s link (errors, dropped)`, `ss -ti (retrans)` |

### 1.2 网络性能四大指标

<!-- DIAGRAM: network-metrics-overview -->
```
网络性能四大指标
════════════════════════════════════════════════════════════════════════════

  ┌─────────────────────────────────────────────────────────────────────────┐
  │                                                                         │
  │   ┌────────────────────┐           ┌────────────────────┐              │
  │   │ Bandwidth（带宽）   │           │ Latency（延迟）     │              │
  │   │ 单位：Mbps, Gbps   │           │ 单位：ms, us        │              │
  │   │                    │           │                    │              │
  │   │ 数据传输速率       │           │ 数据往返时间        │              │
  │   │ "管道有多粗"       │           │ "管道有多长"        │              │
  │   └────────────────────┘           └────────────────────┘              │
  │                                                                         │
  │   ┌────────────────────┐           ┌────────────────────┐              │
  │   │ Packet Loss（丢包）│           │ Jitter（抖动）      │              │
  │   │ 单位：%            │           │ 单位：ms            │              │
  │   │                    │           │                    │              │
  │   │ 数据包丢失比例     │           │ 延迟的波动程度      │              │
  │   │ "管道漏了多少"     │           │ "延迟稳定吗"        │              │
  │   └────────────────────┘           └────────────────────┘              │
  │                                                                         │
  └─────────────────────────────────────────────────────────────────────────┘

  ┌─────────────────────────────────────────────────────────────────────────┐
  │                                                                         │
  │   带宽决定吞吐量上限                                                     │
  │   延迟决定响应时间                                                       │
  │   丢包导致重传和延迟抖动                                                 │
  │   抖动影响实时应用（VoIP、视频、游戏）                                    │
  │                                                                         │
  └─────────────────────────────────────────────────────────────────────────┘
```
<!-- /DIAGRAM -->

### 1.3 指标之间的关系

**带宽-延迟乘积（BDP）** 是理解 TCP 性能的关键：

```
BDP = Bandwidth × RTT

例如：
- 1 Gbps 链路，10ms RTT
- BDP = 1,000,000,000 bits/s × 0.010 s = 10,000,000 bits = 1.25 MB

这意味着：要充分利用这条链路，TCP 窗口至少需要 1.25 MB
```

如果 TCP 缓冲区小于 BDP，带宽无法被充分利用！

---

## Step 2 - ss 命令深入：Socket 队列与 TCP 内部状态（20 分钟）

> **前置知识**：如果你还不熟悉 ss 基础用法，请先阅读 [LX06-05 套接字检查](../../networking/05-sockets/)  

### 2.1 ss -s：统计摘要

```bash
ss -s
```

```
Total: 342
TCP:   128 (estab 89, closed 12, orphaned 0, timewait 27)

Transport    Total     IP        IPv6
RAW          0         0         0
UDP          8         6         2
TCP          116       98        18
INET         124       104       20
FRAG         0         0         0
```

**关键指标**：

| 指标 | 含义 | 警告阈值 |
|------|------|----------|
| `estab` | 已建立连接数 | 取决于业务，但持续增长需关注 |
| `timewait` | 等待关闭的连接 | 高并发正常，但过多（>10000）可能耗尽端口 |
| `orphaned` | 孤儿连接（无进程关联） | > 0 需要调查 |

### 2.2 ss -nmp：详细连接状态与内存

```bash
# 查看所有 TCP 连接的详细信息
ss -nmp

# 只看 ESTABLISHED 状态
ss -nmp state established
```

```
Netid  State   Recv-Q  Send-Q   Local Address:Port   Peer Address:Port   Process
tcp    ESTAB   0       0        10.0.1.52:22         203.0.113.50:54321   users:(("sshd",pid=1234,fd=4))
                        skmem:(r0,rb131072,t0,tb87040,f0,w0,o0,bl0,d0)
tcp    ESTAB   45678   0        10.0.1.52:80         198.51.100.10:45678  users:(("nginx",pid=5678,fd=8))
                        skmem:(r45678,rb262144,t0,tb87040,f2304,w0,o0,bl0,d12)
```

**Recv-Q 和 Send-Q 解读**：

<!-- DIAGRAM: socket-queue-explanation -->
```
Socket 队列深度解读（性能关键指标！）
════════════════════════════════════════════════════════════════════════════

对于 LISTEN 状态的 socket：
─────────────────────────────────────────────────────────────────────────────
  Recv-Q = 等待 accept() 的连接数（SYN backlog）
  Send-Q = backlog 最大值

  例如：tcp  LISTEN  128  128  0.0.0.0:80  0.0.0.0:*
        Recv-Q=128 → ⚠️ backlog 已满！新连接可能被拒绝


对于 ESTABLISHED 状态的 socket：
─────────────────────────────────────────────────────────────────────────────
  Recv-Q = 收到但应用还没读取的数据（字节）
  Send-Q = 已发送但还没被对端确认的数据（字节）

        ┌───────────────────────────────────────────────────────────────┐
        │                                                               │
        │   网络                 ┌────────────┐                应用程序  │
        │   ────▶  Recv-Q 队列  │            │  read() ────▶          │
        │          ════════     │   Socket   │                         │
        │                       │            │                         │
        │   ◀────  Send-Q 队列  │            │  write() ◀────         │
        │          ════════     └────────────┘                         │
        │                                                               │
        └───────────────────────────────────────────────────────────────┘

  Recv-Q 持续 > 0：应用读取太慢（Consumer 瓶颈）
  Send-Q 持续 > 0：网络发送慢或对端处理慢

  正常情况：Recv-Q 和 Send-Q 应该接近 0 或快速变化
  异常情况：队列持续增长，说明处理跟不上
```
<!-- /DIAGRAM -->

### 2.3 ss -ti：TCP 内部信息

```bash
# 查看 TCP 内部状态（重传、RTT、拥塞窗口）
ss -ti state established | head -30

# 查看特定端口
ss -ti '( sport = :80 or sport = :443 )'
```

```
ESTAB  0  0  10.0.1.52:80  198.51.100.10:45678
     cubic wscale:7,7 rto:204 rtt:3.5/0.5 ato:40 mss:1460 pmtu:1500 rcvmss:1460
     advmss:1460 cwnd:10 bytes_sent:12345 bytes_acked:12345 bytes_received:5678
     segs_out:100 segs_in:80 data_segs_out:50 data_segs_in:40 send 33.4Mbps
     lastsnd:1000 lastrcv:500 lastack:500 pacing_rate 66.8Mbps delivery_rate 25Mbps
     delivered:51 app_limited busy:2000ms retrans:0/2 rcv_space:29200 rcv_ssthresh:29200
```

**关键字段解读**：

| 字段 | 含义 | 正常值 |
|------|------|--------|
| `rtt:3.5/0.5` | 往返时间/标准差（ms） | LAN < 1ms, WAN < 100ms |
| `cwnd:10` | 拥塞窗口（MSS 倍数） | 应该稳定或增长 |
| `retrans:0/2` | 当前重传/总重传次数 | 0 最好，偶尔 1-2 可接受 |
| `send 33.4Mbps` | 当前发送速率 | 与带宽对比 |
| `delivery_rate` | 实际数据传输速率 | 越接近带宽越好 |

### 2.4 实战：找出有问题的连接

```bash
# 找出 Recv-Q 不为 0 的连接（应用读取慢）
ss -ntp | awk '$2 > 0 {print "Recv-Q堆积:", $0}'

# 找出 Send-Q 不为 0 的连接（发送缓慢）
ss -ntp | awk '$3 > 0 {print "Send-Q堆积:", $0}'

# 找出有重传的连接
ss -ti state established | grep -E "retrans:[1-9]" -B1

# 找出 RTT 异常高的连接（> 100ms）
ss -ti state established | grep -E "rtt:[0-9]{3,}" -B1
```

---

## Step 3 - iperf3：网络基线测试（15 分钟）

### 3.1 为什么需要 iperf3？

**没有基线，你无法判断网络是否正常。**

```
场景：用户报告"网络慢"
  - 没有基线："慢到什么程度？"
  - 有基线："正常 800 Mbps，现在只有 50 Mbps，确认异常！"
```

iperf3 是网络性能基线测试的标准工具。

### 3.2 基本用法

```bash
# 安装 iperf3
# Ubuntu/Debian
sudo apt install iperf3

# RHEL/AlmaLinux
sudo dnf install iperf3
```

**服务端**（被测试的目标机器）：

```bash
# 启动 iperf3 服务（默认端口 5201）
iperf3 -s

# 后台运行
iperf3 -s -D
```

**客户端**（发起测试的机器）：

```bash
# 基本 TCP 测试（10 秒）
iperf3 -c <server_ip>

# 指定测试时长
iperf3 -c <server_ip> -t 30

# 双向测试
iperf3 -c <server_ip> --bidir

# UDP 测试（指定目标带宽）
iperf3 -c <server_ip> -u -b 100M
```

### 3.3 输出解读

```
[ ID] Interval           Transfer     Bitrate         Retr  Cwnd
[  5]   0.00-1.00   sec   112 MBytes   940 Mbits/sec    0   3.12 MBytes
[  5]   1.00-2.00   sec   112 MBytes   938 Mbits/sec    0   3.12 MBytes
[  5]   2.00-3.00   sec   111 MBytes   932 Mbits/sec    2   2.25 MBytes
...
- - - - - - - - - - - - - - - - - - - - - - - - -
[ ID] Interval           Transfer     Bitrate         Retr
[  5]   0.00-10.00  sec  1.09 GBytes   936 Mbits/sec    2    sender
[  5]   0.00-10.01  sec  1.09 GBytes   935 Mbits/sec         receiver
```

| 列 | 含义 |
|----|------|
| `Transfer` | 传输数据量 |
| `Bitrate` | 吞吐量（带宽利用率） |
| `Retr` | 重传次数（越少越好） |
| `Cwnd` | 拥塞窗口大小 |

### 3.4 UDP 测试

```bash
# UDP 测试（带宽设为 100 Mbps）
iperf3 -c <server_ip> -u -b 100M -t 10
```

```
[ ID] Interval           Transfer     Bitrate         Jitter    Lost/Total Datagrams
[  5]   0.00-10.00  sec   119 MBytes  99.8 Mbits/sec  0.045 ms  12/85714 (0.014%)  sender
[  5]   0.00-10.01  sec   119 MBytes  99.8 Mbits/sec  0.045 ms  12/85702 (0.014%)  receiver
```

UDP 测试额外显示：
- `Jitter`：抖动（越小越好，实时应用要求 < 30ms）
- `Lost/Total`：丢包率（0% 最好，< 1% 可接受）

### 3.5 并行流测试

```bash
# 使用 4 个并行流（测试聚合带宽）
iperf3 -c <server_ip> -P 4
```

**为什么需要并行流？**

单个 TCP 流可能无法充分利用高带宽-高延迟链路（BDP 限制）。

---

## Step 4 - 接口统计：ip -s link 与 ethtool -S（10 分钟）

### 4.1 ip -s link：包级别统计

```bash
ip -s link show eth0
```

```
2: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc fq_codel state UP
    link/ether 0a:1b:2c:3d:4e:5f brd ff:ff:ff:ff:ff:ff
    RX:  bytes  packets  errors  dropped  overrun  mcast
    12345678901  9876543  0       12       0        54321
    TX:  bytes  packets  errors  dropped  carrier  collsns
    98765432109  8765432  0       5        0        0
```

**USE Method 视角**：

| 字段 | USE 维度 | 说明 |
|------|----------|------|
| `bytes/packets` | Utilization | 流量统计 |
| `dropped` | Saturation | 因队列满而丢弃 |
| `errors` | Errors | 硬件/驱动错误 |
| `overrun` | Saturation | 接收缓冲区溢出 |

### 4.2 ethtool -S：驱动级详细统计

```bash
# 查看网卡驱动级统计（更详细）
sudo ethtool -S eth0 | head -50
```

```
NIC statistics:
     rx_packets: 9876543
     tx_packets: 8765432
     rx_bytes: 12345678901
     tx_bytes: 98765432109
     rx_errors: 0
     tx_errors: 0
     rx_dropped: 0
     tx_dropped: 0
     ...
     rx_queue_0_packets: 3456789
     rx_queue_0_bytes: 4567890123
     rx_queue_0_drops: 12
     ...
```

**关键指标**：

| 指标 | 含义 | 警告条件 |
|------|------|----------|
| `rx_dropped` | 接收丢包 | > 0 需调查 |
| `tx_dropped` | 发送丢包 | > 0 需调查 |
| `rx_queue_N_drops` | 特定队列丢包 | > 0 可能需要调整队列 |
| `rx_crc_errors` | CRC 校验错误 | > 0 可能是线缆问题 |
| `rx_fifo_errors` | FIFO 溢出 | > 0 表示处理不过来 |

### 4.3 查看网卡能力

```bash
# 查看网卡速度和协商状态
sudo ethtool eth0 | grep -E "Speed|Duplex|Link"
```

```
	Speed: 10000Mb/s
	Duplex: Full
	Link detected: yes
```

```bash
# 查看网卡支持的功能
sudo ethtool -k eth0 | grep -E "tcp-segmentation|generic-receive"
```

---

## Step 5 - TCP 缓冲区调优入门（15 分钟）

### 5.1 为什么需要调优 TCP 缓冲区？

回顾 BDP（带宽-延迟乘积）：

```
高带宽 + 高延迟 = 需要更大的 TCP 缓冲区

例如：跨国链路
- 带宽：1 Gbps
- RTT：200 ms（日本到美国）
- BDP = 1 Gbps × 0.2 s = 200 Mbits = 25 MB

如果 TCP 缓冲区只有 256 KB（默认），只能利用约 1% 的带宽！
```

### 5.2 相关内核参数

```bash
# 查看当前 TCP 缓冲区设置
sysctl net.ipv4.tcp_rmem
sysctl net.ipv4.tcp_wmem
sysctl net.core.rmem_max
sysctl net.core.wmem_max
```

```
net.ipv4.tcp_rmem = 4096    131072    6291456
                   最小     默认      最大
net.ipv4.tcp_wmem = 4096    16384     4194304
net.core.rmem_max = 212992
net.core.wmem_max = 212992
```

**参数解释**：

| 参数 | 含义 |
|------|------|
| `tcp_rmem` | TCP 接收缓冲区（min, default, max） |
| `tcp_wmem` | TCP 发送缓冲区（min, default, max） |
| `rmem_max` | 单个 socket 接收缓冲区的硬上限 |
| `wmem_max` | 单个 socket 发送缓冲区的硬上限 |

### 5.3 安全的调优示例

> **警告**：永远先测量基线，再做调优！  

```bash
# 查看当前基线
iperf3 -c <server_ip> -t 30

# 临时调整（重启后恢复）
sudo sysctl -w net.core.rmem_max=16777216
sudo sysctl -w net.core.wmem_max=16777216
sudo sysctl -w net.ipv4.tcp_rmem="4096 131072 16777216"
sudo sysctl -w net.ipv4.tcp_wmem="4096 65536 16777216"

# 再次测试
iperf3 -c <server_ip> -t 30

# 对比结果
```

### 5.4 持久化配置

如果测试证明有效，持久化到配置文件：

```bash
# /etc/sysctl.d/99-network-tuning.conf
# 高吞吐量网络调优
# 警告：仅在测量证明有效后启用

# 增大 socket 缓冲区上限
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216

# 增大 TCP 缓冲区
net.ipv4.tcp_rmem = 4096 131072 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216

# 增大连接队列
net.core.somaxconn = 65535
net.ipv4.tcp_max_syn_backlog = 65535
```

```bash
# 应用配置
sudo sysctl -p /etc/sysctl.d/99-network-tuning.conf
```

---

## Step 6 - tcpdump 性能分析：延迟与重传（15 分钟）

> **前置知识**：如果你还不熟悉 tcpdump 基础用法，请先阅读 [LX06-08 tcpdump 与抓包分析](../../networking/08-tcpdump/)  

### 6.1 从性能角度使用 tcpdump

tcpdump 不仅用于排查连接问题，也是性能分析的利器。

```bash
# 抓取特定端口的 TCP 流量，显示时间戳
sudo tcpdump -i eth0 -nn -tttt port 80 -c 100

# 只抓重传包（性能问题关键信号）
sudo tcpdump -i eth0 -nn 'tcp[tcpflags] & (tcp-syn|tcp-fin) == 0 and tcp[4:4] = tcp[8:4]'
```

### 6.2 识别重传

```bash
# 使用更现代的方式（需要较新内核）
sudo tcpdump -i eth0 -nn -v 'tcp' | grep -i retransmit

# 或者抓包后分析
sudo tcpdump -i eth0 -nn -w /tmp/capture.pcap port 80
tcpdump -nn -r /tmp/capture.pcap | grep -E '\[R\]|\[S\].*\[S\]'
```

### 6.3 计算延迟

抓取 SYN/SYN-ACK 来计算 RTT：

```bash
# 抓取握手包
sudo tcpdump -i eth0 -nn -tttt 'tcp[tcpflags] & (tcp-syn) != 0' -c 20
```

```
2026-01-10 14:30:01.123456 IP 10.0.1.52.45678 > 203.0.113.50.80: Flags [S], ...
2026-01-10 14:30:01.126789 IP 203.0.113.50.80 > 10.0.1.52.45678: Flags [S.], ...
```

**RTT = 126789 - 123456 = 3.333 ms**

### 6.4 性能相关的 tcpdump 过滤器

```bash
# 只看数据包（排除 ACK-only）
sudo tcpdump -i eth0 -nn 'tcp[tcpflags] & tcp-push != 0'

# 看窗口为 0 的包（流控信号）
sudo tcpdump -i eth0 -nn 'tcp[14:2] = 0'

# 看 RST 包（连接异常重置）
sudo tcpdump -i eth0 -nn 'tcp[tcpflags] & tcp-rst != 0'
```

---

## Step 7 - 网络性能 Cheatsheet（5 分钟）

```bash
# ==============================================================================
# 网络性能分析 Cheatsheet
# ==============================================================================

# --- Socket 统计 ---
ss -s                              # 总体统计
ss -nmp state established          # 详细连接信息（含内存）
ss -ti state established           # TCP 内部状态（RTT, 重传）

# --- 找问题连接 ---
ss -ntp | awk '$2 > 0'             # Recv-Q 堆积（应用读慢）
ss -ntp | awk '$3 > 0'             # Send-Q 堆积（发送慢）
ss -ti | grep -E "retrans:[1-9]"   # 有重传的连接

# --- 接口统计 ---
ip -s link show eth0               # 包级别统计
sudo ethtool -S eth0               # 驱动级详细统计
sudo ethtool eth0                  # 速度/双工状态

# --- iperf3 基线测试 ---
iperf3 -s                          # 服务端
iperf3 -c <ip> -t 30               # TCP 测试 30 秒
iperf3 -c <ip> --bidir             # 双向测试
iperf3 -c <ip> -u -b 100M          # UDP 测试
iperf3 -c <ip> -P 4                # 4 并行流

# --- TCP 缓冲区 ---
sysctl net.ipv4.tcp_rmem           # TCP 接收缓冲
sysctl net.ipv4.tcp_wmem           # TCP 发送缓冲
sysctl net.core.rmem_max           # 接收缓冲硬上限
sysctl net.core.wmem_max           # 发送缓冲硬上限

# --- tcpdump 性能分析 ---
sudo tcpdump -i eth0 -nn -tttt port 80 -c 100    # 带时间戳
sudo tcpdump -i eth0 -nn 'tcp[tcpflags] & tcp-rst != 0'  # 只看 RST

# --- 快速检查 ---
ping -c 10 <ip>                    # 基本延迟和丢包
mtr <ip>                           # 路径延迟分析
traceroute <ip>                    # 路由跟踪
```

---

## Step 8 - Lab 场景：网络黑洞（TCP Buffer Issue）（15 分钟）

> **场景来源**：Gemini 生成的 Japan IT 场景 - "The Network Black Hole"  
>
> **背景**：ECサイト（电商网站）在 タイムセール（限时特卖）期间，吞吐量在 10 Gbps 网卡上只能达到 1 Gbps。网络团队说"网络正常"，但应用团队说"数据传输慢"。  

### 8.1 问题现象

```bash
# 检查网卡速度
sudo ethtool eth0 | grep Speed
# Speed: 10000Mb/s

# 但 iperf3 测试只有 ~1 Gbps
iperf3 -c backend-server -t 10
# [ ID] Interval           Transfer     Bitrate
# [  5]   0.00-10.00  sec  1.12 GBytes   962 Mbits/sec    sender
```

### 8.2 诊断步骤

**Step A：检查 socket 队列**

```bash
ss -nmp state established | grep backend-server
```

```
tcp  ESTAB  262144  0  10.0.1.52:45678  10.0.1.100:8080
                      skmem:(r262144,rb262144,t0,tb87040,f0,w0,o0,bl0,d0)
```

**发现**：`Recv-Q = 262144`，接收缓冲区满了！

**Step B：检查 TCP 内部状态**

```bash
ss -ti state established | grep -A1 backend-server
```

```
ESTAB  262144  0  10.0.1.52:45678  10.0.1.100:8080
     cubic wscale:7,7 rto:204 rtt:0.5/0.1 cwnd:10 rcv_space:262144
     rcv_ssthresh:262144 ...
```

**发现**：`rcv_space = 262144`（256 KB），对于高带宽链路太小了！

**Step C：检查系统限制**

```bash
sysctl net.core.rmem_max
# net.core.rmem_max = 262144
```

**根因**：`rmem_max` 限制了 TCP 接收缓冲区，无法扩展到 BDP 需要的大小。

### 8.3 修复

```bash
# 临时调整
sudo sysctl -w net.core.rmem_max=16777216
sudo sysctl -w net.ipv4.tcp_rmem="4096 131072 16777216"

# 验证
iperf3 -c backend-server -t 10
# [ ID] Interval           Transfer     Bitrate
# [  5]   0.00-10.00  sec  9.31 GBytes   8.00 Gbits/sec    sender
```

吞吐量从 1 Gbps 提升到 8 Gbps！

---

## Step 9 - Lab 场景：隐形延迟（DNS Timeout）（15 分钟）

> **场景来源**：Gemini 生成的 Japan IT 场景 - "The Invisible Delay"  
>
> **背景**：AWS RDS 连接随机出现恰好 5 秒的延迟。不是每次都慢，但发生时必定是 5 秒。  

### 9.1 问题现象

```bash
# 大多数时候正常
time mysql -h db.example.com -e "SELECT 1"
# real    0m0.050s

# 偶尔慢 5 秒
time mysql -h db.example.com -e "SELECT 1"
# real    0m5.051s  ← 恰好多 5 秒！
```

### 9.2 诊断步骤

**Step A：抓包分析 DNS**

```bash
sudo tcpdump -i eth0 -nn port 53
```

```
14:30:01.001 IP 10.0.1.52.45678 > 10.0.0.2.53: 12345+ AAAA? db.example.com. (32)
14:30:06.001 IP 10.0.1.52.45679 > 10.0.0.2.53: 12346+ A? db.example.com. (32)
14:30:06.010 IP 10.0.0.2.53 > 10.0.1.52.45679: 12346 1/0/0 A 10.0.2.100 (48)
```

**发现**：
1. 先发送 AAAA 查询（IPv6）
2. 等待 5 秒超时
3. 再发送 A 查询（IPv4）
4. IPv4 立即返回

### 9.3 根因

系统配置了 IPv6，但 DNS 服务器或网络不支持 IPv6。

```bash
# 检查
cat /etc/resolv.conf
# nameserver 10.0.0.2
# options timeout:5  ← 5 秒超时！

# 检查 IPv6
ip -6 addr show
# inet6 fe80::1/64 scope link
```

### 9.4 修复选项

**选项 1：禁用 IPv6 DNS 查询**

```bash
# /etc/gai.conf
precedence ::ffff:0:0/96  100
```

**选项 2：在 resolv.conf 中添加选项**

```bash
# /etc/resolv.conf
options single-request-reopen
```

**选项 3：确保 DNS 服务器支持 IPv6**

```bash
# 检查 DNS 服务器是否响应 AAAA
dig AAAA db.example.com @10.0.0.2
```

---

## Mini-Project：网络基线报告（20 分钟）

### 项目目标

使用 iperf3 建立内网网络基线，记录带宽、延迟、丢包率。

### 10.1 创建基线脚本

```bash
#!/bin/bash
# network-baseline.sh - 网络性能基线采集脚本
# 用于 タイムセール 前的网络性能确认

# 配置
IPERF_SERVER="${1:-}"
DURATION=30
OUTPUT_DIR="network_baseline_$(date +%Y%m%d_%H%M%S)"

if [ -z "$IPERF_SERVER" ]; then
    echo "用法: $0 <iperf3服务器IP>"
    exit 1
fi

mkdir -p "$OUTPUT_DIR"
cd "$OUTPUT_DIR"

echo "============================================"
echo "  网络性能基线采集"
echo "  目标服务器: $IPERF_SERVER"
echo "  采集时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo "============================================"

# 系统信息
{
    echo "=== 系统信息 ==="
    uname -a
    echo ""
    echo "=== 网络接口 ==="
    ip -br link
    echo ""
    echo "=== 默认网关 ==="
    ip route | grep default
} > system_info.txt

# Step 1: 基础连通性
echo ""
echo "[Step 1] 基础连通性测试..."
{
    echo "=== Ping 测试 ==="
    ping -c 20 "$IPERF_SERVER"
} > ping_test.txt 2>&1

# 提取 ping 统计
PING_STATS=$(tail -2 ping_test.txt | head -1)
echo "  Ping 统计: $PING_STATS"

# Step 2: TCP 吞吐量
echo ""
echo "[Step 2] TCP 吞吐量测试 (${DURATION}秒)..."
iperf3 -c "$IPERF_SERVER" -t "$DURATION" -J > tcp_test.json 2>&1

if [ $? -eq 0 ]; then
    TCP_BW=$(jq -r '.end.sum_sent.bits_per_second' tcp_test.json 2>/dev/null | awk '{printf "%.2f Mbps", $1/1000000}')
    TCP_RETRANS=$(jq -r '.end.sum_sent.retransmits' tcp_test.json 2>/dev/null)
    echo "  TCP 吞吐量: $TCP_BW"
    echo "  重传次数: $TCP_RETRANS"
else
    echo "  TCP 测试失败，请确认 iperf3 服务端运行中"
fi

# Step 3: UDP 测试（丢包率和抖动）
echo ""
echo "[Step 3] UDP 测试 (100 Mbps, ${DURATION}秒)..."
iperf3 -c "$IPERF_SERVER" -u -b 100M -t "$DURATION" -J > udp_test.json 2>&1

if [ $? -eq 0 ]; then
    UDP_LOSS=$(jq -r '.end.sum.lost_percent' udp_test.json 2>/dev/null)
    UDP_JITTER=$(jq -r '.end.sum.jitter_ms' udp_test.json 2>/dev/null)
    echo "  UDP 丢包率: ${UDP_LOSS}%"
    echo "  UDP 抖动: ${UDP_JITTER} ms"
else
    echo "  UDP 测试失败"
fi

# Step 4: 双向测试
echo ""
echo "[Step 4] 双向吞吐量测试..."
iperf3 -c "$IPERF_SERVER" --bidir -t 10 -J > bidir_test.json 2>&1

# Step 5: Socket 状态快照
echo ""
echo "[Step 5] Socket 状态快照..."
{
    echo "=== ss -s ==="
    ss -s
    echo ""
    echo "=== 当前连接统计 ==="
    ss -tan | awk '{print $1}' | sort | uniq -c | sort -rn
} > socket_stats.txt

# Step 6: 接口统计
echo ""
echo "[Step 6] 接口统计..."
{
    echo "=== ip -s link ==="
    ip -s link show
} > interface_stats.txt

# 生成摘要报告
echo ""
echo "[生成摘要报告...]"

{
    echo "============================================"
    echo "  网络性能基线报告"
    echo "  采集时间: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "  目标服务器: $IPERF_SERVER"
    echo "============================================"
    echo ""
    echo "## 连通性"
    echo "$PING_STATS"
    echo ""
    echo "## TCP 吞吐量"
    if [ -f tcp_test.json ]; then
        echo "- 带宽: $TCP_BW"
        echo "- 重传: $TCP_RETRANS"
    fi
    echo ""
    echo "## UDP 性能"
    if [ -f udp_test.json ]; then
        echo "- 丢包率: ${UDP_LOSS}%"
        echo "- 抖动: ${UDP_JITTER} ms"
    fi
    echo ""
    echo "## 建议"
    if [ -n "$TCP_RETRANS" ] && [ "$TCP_RETRANS" -gt 0 ]; then
        echo "- ⚠️  检测到重传，建议检查网络质量"
    fi
    if [ -n "$UDP_LOSS" ] && [ "$(echo "$UDP_LOSS > 1" | bc -l 2>/dev/null)" = "1" ]; then
        echo "- ⚠️  UDP 丢包率超过 1%，可能影响实时应用"
    fi
    echo ""
    echo "============================================"
} > summary.txt

cat summary.txt

echo ""
echo "============================================"
echo "  基线采集完成！"
echo "  输出目录: $(pwd)"
echo "============================================"
```

### 10.2 运行基线采集

```bash
chmod +x network-baseline.sh

# 在目标服务器上启动 iperf3
ssh target-server 'iperf3 -s -D'

# 运行基线采集
./network-baseline.sh <target-server-ip>
```

### 10.3 检查清单

完成 Mini-Project 后，确认你有：

- [ ] 记录了 ping 延迟和丢包率
- [ ] 记录了 TCP 吞吐量和重传次数
- [ ] 记录了 UDP 丢包率和抖动
- [ ] 记录了 socket 状态分布
- [ ] 记录了接口统计
- [ ] 保存了基线报告供未来对比

---

## 反模式：常见错误

### 错误 1：忽略 Socket 队列深度

```bash
# 错误：只看连接数
ss -tan | wc -l
# "10000 个连接，看起来正常..."

# 正确：检查队列深度
ss -ntp | awk '$2 > 0 || $3 > 0'
# Recv-Q=65535 的连接说明应用处理不过来！
```

### 错误 2：调优前不测量

```bash
# 错误：直接抄网上配置
echo 'net.core.rmem_max = 16777216' >> /etc/sysctl.conf
sysctl -p
# "网上说这样好..."

# 正确：先测量基线
iperf3 -c server -t 30 > before.txt
sysctl -w net.core.rmem_max=16777216
iperf3 -c server -t 30 > after.txt
diff before.txt after.txt
# 证明有效再持久化
```

### 错误 3：只测单向

```bash
# 错误：只测客户端到服务器
iperf3 -c server

# 正确：双向测试
iperf3 -c server --bidir
# 上行和下行可能有不同瓶颈
```

---

## 职场小贴士（Japan IT Context）

### タイムセール対応（限时特卖对应）

在日本 EC 网站运营中，タイムセール（限时特卖）是网络压力最大的时刻。

| 日语术语 | 读音 | 含义 | 本课对应 |
|----------|------|------|----------|
| スループット | スループット | Throughput | iperf3 测试 |
| レイテンシ | レイテンシ | Latency | ss -ti, ping |
| パケットロス | パケットロス | Packet Loss | UDP 测试 |
| バッファ | バッファ | Buffer | TCP 缓冲区 |
| ボトルネック | ボトルネック | Bottleneck | 队列深度分析 |
| 輻輳 | ふくそう | Congestion | cwnd, 重传 |

### 性能問題報告書

```markdown
## 性能問題報告書

### 発生日時
2026-01-10 14:00 JST（タイムセール開始時）

### 症状
- スループットが 1 Gbps で頭打ち
- 10 Gbps NIC に対して 10% しか利用できていない

### 調査結果（USE Method）

#### Network
- Utilization: 1 Gbps / 10 Gbps = 10%
- Saturation: Recv-Q = 262144（バッファ満杯）⚠️
- Errors: 重传なし

### 根本原因
net.core.rmem_max = 262144 KB がボトルネック。
BDP = 10 Gbps × 0.5 ms = 625 KB 必要だが、256 KB で制限されていた。

### 対策
1. net.core.rmem_max を 16 MB に拡張
2. net.ipv4.tcp_rmem の max を 16 MB に設定
3. 設定変更後、スループットが 8 Gbps に改善

### エビデンス
- iperf3 before: 962 Mbps
- iperf3 after: 8.00 Gbps
- 添付: tcp_test_before.json, tcp_test_after.json
```

---

## 面试准备（Interview Prep）

### Q1: ss の Recv-Q が増加している意味は？

**回答要点**：

```
Recv-Q はソケットの受信キュー深度です。

ESTABLISHED 状態の場合：
- Recv-Q > 0 は、ネットワークからデータを受信したが、
  アプリケーションがまだ read() していないバイト数
- 持続的に高い場合、アプリケーションの処理が追いついていない
  （Consumer がボトルネック）

LISTEN 状態の場合：
- accept() を待っている接続数
- backlog 上限に達すると新規接続が拒否される

対処：アプリケーションの処理能力向上、または負荷分散
```

### Q2: iperf3 でベースラインを取る理由は？

**回答要点**：

```
ベースラインがないと、「遅い」の基準がわかりません。

理由：
1. 正常時の性能を数値で記録
2. 問題発生時に比較可能
3. 変更の効果を証明できる（エビデンス）
4. SLA 達成の確認

採取タイミング：
- 本番リリース前
- 大規模イベント前（タイムセールなど）
- 定期的（月次など）
- ネットワーク変更後
```

### Q3: TCP バッファを大きくすれば必ず速くなりますか？

**回答要点**：

```
いいえ、必ずしもそうではありません。

効果がある場合：
- 高帯域 × 高遅延のリンク（BDP が大きい）
- 現在のバッファが BDP より小さい場合

効果がない/悪化する場合：
- ボトルネックが帯域やCPUの場合
- メモリリソースが限られている場合
- 多数のコネクションがある場合（各接続にバッファ割当）

原則：必ず計測してから変更。盲目的なチューニングは禁物。
```

---

## 检查清单

完成本课后，你应该能够：

- [ ] 解释网络性能四大指标（Bandwidth, Latency, Packet Loss, Jitter）
- [ ] 使用 ss -nmp 分析 socket 队列深度
- [ ] 使用 ss -ti 查看 TCP 内部状态（RTT, cwnd, retrans）
- [ ] 使用 iperf3 建立 TCP/UDP 网络基线
- [ ] 使用 ip -s link 和 ethtool -S 检查接口统计
- [ ] 解释 TCP 缓冲区参数（tcp_rmem, tcp_wmem, rmem_max）
- [ ] 识别"TCP Buffer Issue"导致的吞吐量瓶颈
- [ ] 识别"DNS Timeout"导致的隐形延迟
- [ ] 避免"调优前不测量"的反模式

---

## 本课小结

| 概念 | 要点 |
|------|------|
| 四大指标 | Bandwidth, Latency, Packet Loss, Jitter |
| USE for Network | U=带宽利用率, S=队列深度, E=丢包/错误 |
| ss 核心用法 | `-s` 统计, `-nmp` 详情, `-ti` TCP 内部 |
| Recv-Q/Send-Q | 持续 > 0 表示处理跟不上 |
| iperf3 | 基线测试标准工具 |
| BDP | 带宽 × 延迟，决定所需缓冲区大小 |
| TCP 缓冲区 | rmem_max, wmem_max 是硬上限 |
| 核心原则 | 先测量基线，再做调优 |

---

## 延伸阅读

- [Brendan Gregg - Network Performance](https://www.brendangregg.com/blog/2017-09-18/linux-perf-analysis-60s.html)
- [Linux TCP Tuning](https://www.kernel.org/doc/html/latest/networking/ip-sysctl.html)
- [iperf3 Documentation](https://iperf.fr/iperf-doc.php)
- 上一课：[04 - I/O 分析](../04-io-analysis/)
- 下一课：[06 - strace 系统调用追踪](../06-strace/)
- 相关课程：[LX06-05 套接字检查](../../networking/05-sockets/)、[LX06-08 tcpdump](../../networking/08-tcpdump/)

---

## 系列导航

[<-- 04 - I/O 分析](../04-io-analysis/) | [系列首页](../) | [06 - strace -->](../06-strace/)
