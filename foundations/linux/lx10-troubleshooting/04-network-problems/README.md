# 04 - 网络问题：分层诊断

> **目标**：掌握分层网络诊断方法，系统性排查连通性和性能问题  
> **前置**：LX06-NETWORK 网络基础（ss、nftables、DNS）  
> **时间**：2.5 小时  
> **实战场景**：curl 超时但服务器在运行，间歇性 502 Bad Gateway  

---

## 将学到的内容

1. 使用分层方法诊断网络问题（L2 -> L3 -> L4 -> L7）
2. 掌握网络诊断工具组合（ip, ss, dig, curl, nc）
3. 识别 DNS 问题的常见症状和排查方法
4. 诊断防火墙导致的连通性问题
5. 理解高级网络问题（MTU、端口耗尽、conntrack）
6. 完成 TCP 黑洞场景的完整排查

---

## 先跑起来！（10 分钟）

> 场景：你收到告警 "API 服务不可用"，curl 请求超时。  
> 服务器还在运行，但就是连不上。先别慌，用这个快速诊断流程：  

```bash
# 1. 服务在监听吗？（L4 检查）
ss -lntup | grep ':80\|:443\|:8080'

# 2. 能 ping 通吗？（L3 检查）
ping -c 3 <目标IP>

# 3. 端口能连上吗？（L4 检查）
nc -zv <目标IP> 80
# 或
curl -v --connect-timeout 5 http://<目标IP>/

# 4. DNS 正常吗？（L7 检查）
dig <域名> +short

# 5. 防火墙放行了吗？
# RHEL/CentOS:
firewall-cmd --list-all
# 或 nftables:
nft list ruleset | head -50
```

**你刚刚完成了一次快速分层诊断！**

这就是网络排查的核心思路：从上到下或从下到上，逐层排查。
现在让我们系统学习分层诊断方法。

---

## Step 1 -- 分层诊断方法论（15 分钟）

### 1.1 网络七层模型简化版

对于运维排查，我们关注四个关键层次：

<!-- DIAGRAM: network-layers -->
```
┌───────────────────────────────────────────────────────────────────────────┐
│                     网络分层诊断模型                                        │
├───────────────────────────────────────────────────────────────────────────┤
│                                                                           │
│  OSI 模型          运维视角              诊断工具                          │
│  ────────          ────────              ────────                          │
│                                                                           │
│  ┌─────────────┐   ┌─────────────┐      ┌─────────────────────────────┐  │
│  │ Layer 7     │   │ 应用层      │      │ curl, wget, dig             │  │
│  │ Application │   │ HTTP/DNS    │      │ openssl s_client            │  │
│  └─────────────┘   └─────────────┘      └─────────────────────────────┘  │
│        ↓                 ↓                                                │
│  ┌─────────────┐   ┌─────────────┐      ┌─────────────────────────────┐  │
│  │ Layer 4     │   │ 传输层      │      │ ss, netstat, nc -zv         │  │
│  │ Transport   │   │ TCP/UDP     │      │ tcpdump (TCP flags)         │  │
│  └─────────────┘   └─────────────┘      └─────────────────────────────┘  │
│        ↓                 ↓                                                │
│  ┌─────────────┐   ┌─────────────┐      ┌─────────────────────────────┐  │
│  │ Layer 3     │   │ 网络层      │      │ ping, traceroute, ip route  │  │
│  │ Network     │   │ IP 路由     │      │ ip addr, mtr                │  │
│  └─────────────┘   └─────────────┘      └─────────────────────────────┘  │
│        ↓                 ↓                                                │
│  ┌─────────────┐   ┌─────────────┐      ┌─────────────────────────────┐  │
│  │ Layer 1-2   │   │ 物理/链路层 │      │ ip link, ethtool            │  │
│  │ Physical/   │   │ 网卡/线缆   │      │ dmesg (网卡错误)            │  │
│  │ Data Link   │   │             │      │                             │  │
│  └─────────────┘   └─────────────┘      └─────────────────────────────┘  │
│                                                                           │
│  诊断方向：                                                               │
│  ─────────                                                                │
│  • 自上而下：从 L7 开始（应用报错） → 逐层向下排查                         │
│  • 自下而上：从 L2 开始（物理检查） → 逐层向上验证                         │
│                                                                           │
│  经验法则：                                                               │
│  ─────────                                                                │
│  • 应用报 "Connection refused" → L4 问题（服务没监听）                    │
│  • 应用报 "Network unreachable" → L3 问题（路由问题）                     │
│  • 应用报 "Connection timed out" → 可能 L3/L4/防火墙                      │
│  • 应用报 "Name resolution failed" → L7 DNS 问题                          │
│                                                                           │
└───────────────────────────────────────────────────────────────────────────┘
```
<!-- /DIAGRAM -->

### 1.2 常见错误信息与层次映射

| 错误信息 | 可能的层次 | 首先检查 |
|----------|-----------|----------|
| `Connection refused` | L4 | 服务是否监听端口 |
| `Connection timed out` | L3/L4/防火墙 | ping → nc → 防火墙 |
| `Network is unreachable` | L3 | 路由表、网关配置 |
| `No route to host` | L3 | 路由表、目标主机防火墙 |
| `Name or service not known` | L7 DNS | /etc/resolv.conf, dig |
| `SSL/TLS handshake failed` | L7 | 证书、时间同步 |

### 1.3 诊断顺序：自上而下 vs 自下而上

**自上而下**（推荐，更高效）：
```
应用报错 → 分析错误信息 → 定位可能层次 → 验证
```

**自下而上**（彻底，但耗时）：
```
L2 网卡 → L3 IP/路由 → L4 端口 → L7 应用
```

**经验法则**：
- 有明确错误信息 → 自上而下
- 完全不通、无错误信息 → 自下而上
- 间歇性问题 → 需要抓包分析

---

## Step 2 -- Layer 1-2 诊断：物理和链路层（10 分钟）

### 2.1 网卡状态检查

```bash
# 查看网卡状态
ip link show

# 输出解读：
# 2: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 ...
#          state UP                        ← 状态正常
#          state DOWN                      ← 网卡未启用或线缆问题

# 启用网卡
ip link set eth0 up

# 查看网卡详细信息（物理层）
ethtool eth0
# 关注：
#   Link detected: yes    ← 线缆连接正常
#   Speed: 1000Mb/s       ← 速率
#   Duplex: Full          ← 双工模式
```

### 2.2 网卡错误统计

```bash
# 查看网卡统计（包括错误）
ip -s link show eth0

# 输出示例：
#     RX:  bytes packets errors dropped missed  mcast
#          1234  5678    0      0       0       0      ← 正常
#          1234  5678    123    456     0       0      ← 有问题！

# 更详细的统计（需要 ethtool）
ethtool -S eth0 | grep -E 'error|drop|collision'
```

### 2.3 内核网络错误

```bash
# 检查内核日志中的网络错误
dmesg | grep -iE 'eth|network|link|carrier' | tail -20

# 常见错误：
# "eth0: link down"          ← 链路断开
# "eth0: NIC Link is Down"   ← 网卡连接丢失
# "carrier lost"             ← 载波信号丢失
```

---

## Step 3 -- Layer 3 诊断：网络层（20 分钟）

### 3.1 IP 地址检查

```bash
# 查看 IP 地址
ip addr show

# 输出解读：
# 2: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500
#     inet 192.168.1.100/24 brd 192.168.1.255 scope global eth0
#          ↑ IP 地址         ↑ 子网掩码       ↑ 作用域

# 检查特定接口
ip addr show eth0

# 常见问题：
# - 没有 IP 地址 → DHCP 问题或静态配置错误
# - IP 冲突 → 同网段其他主机使用相同 IP
```

### 3.2 路由表检查

```bash
# 查看路由表
ip route

# 输出示例：
# default via 192.168.1.1 dev eth0        ← 默认网关
# 192.168.1.0/24 dev eth0 proto kernel    ← 直连网段

# 查看到特定目标的路由
ip route get 8.8.8.8
# 输出：8.8.8.8 via 192.168.1.1 dev eth0 src 192.168.1.100

# 常见问题：
# - 没有默认路由 → 无法访问外网
# - 网关不可达 → 网关配置错误或网关宕机
```

### 3.3 ping 测试

```bash
# 基本 ping
ping -c 3 192.168.1.1

# 指定源 IP（多网卡环境）
ping -c 3 -I eth0 192.168.1.1

# ping 结果解读：
# 64 bytes from 192.168.1.1: icmp_seq=1 ttl=64 time=0.5 ms  ← 正常
# Request timeout                                            ← 超时
# Destination Host Unreachable                               ← 主机不可达
# Network is unreachable                                     ← 网络不可达
```

### 3.4 traceroute 定位断点

```bash
# 跟踪路由（默认 UDP）
traceroute 8.8.8.8

# 使用 ICMP（需要 root）
traceroute -I 8.8.8.8

# 使用 TCP（穿越防火墙）
traceroute -T -p 80 google.com

# 输出解读：
# 1  192.168.1.1    0.5 ms    ← 第一跳（网关）
# 2  10.0.0.1       2.1 ms    ← 第二跳
# 3  * * *                    ← 超时（可能丢包或防火墙）
# 4  8.8.8.8        15.2 ms   ← 目标
```

### 3.5 mtr：更强大的路径分析

```bash
# mtr = ping + traceroute，持续监控
mtr -c 100 8.8.8.8

# 报告模式（非交互）
mtr -r -c 100 8.8.8.8

# 输出关注点：
#                          Loss%  Snt  Last  Avg  Best  Wrst
# 1. 192.168.1.1            0.0%  100   0.5  0.6   0.3   1.2
# 2. 10.0.0.1               5.0%  100   2.1  3.2   1.8  15.3  ← 5% 丢包
# 3. ???                   100.0%  100   0.0  0.0   0.0   0.0  ← 完全丢包
```

---

## Step 4 -- Layer 4 诊断：传输层（25 分钟）

### 4.1 ss 命令：现代 netstat 替代

```bash
# 查看所有监听端口
ss -lntup

# 参数解释：
# -l: 只显示监听状态
# -n: 不解析端口名（显示数字）
# -t: TCP
# -u: UDP
# -p: 显示进程信息（需要 root）

# 输出示例：
# Netid  State   Recv-Q  Send-Q  Local Address:Port  Peer Address:Port  Process
# tcp    LISTEN  0       128     0.0.0.0:22          0.0.0.0:*          users:(("sshd",pid=1234))
# tcp    LISTEN  0       128     0.0.0.0:80          0.0.0.0:*          users:(("nginx",pid=5678))
```

### 4.2 检查服务是否监听

```bash
# 检查特定端口
ss -lntp | grep ':80'

# 如果没有输出 → 服务没有在监听！
# 可能原因：
# - 服务未启动
# - 服务配置监听在其他端口
# - 服务绑定在 127.0.0.1（只接受本地连接）

# 检查服务是否只绑定本地
ss -lntp | grep nginx
# 0.0.0.0:80    ← 接受所有 IP 连接
# 127.0.0.1:80  ← 只接受本地连接！
```

### 4.3 nc (netcat) 端口测试

```bash
# 测试 TCP 端口连通性
nc -zv 192.168.1.100 80

# 输出：
# Connection to 192.168.1.100 80 port [tcp/http] succeeded!  ← 成功
# nc: connect to 192.168.1.100 port 80 (tcp) failed: Connection refused  ← 拒绝
# nc: connect to 192.168.1.100 port 80 (tcp) failed: Connection timed out  ← 超时

# 测试端口范围
nc -zv 192.168.1.100 80-90

# 测试 UDP 端口
nc -zuv 192.168.1.100 53
```

### 4.4 查看连接状态统计

```bash
# 查看 TCP 连接统计
ss -s

# 输出示例：
# Total: 1234
# TCP:   567 (estab 234, closed 123, orphaned 12, timewait 89)
#                       ↑ 活跃连接                  ↑ TIME_WAIT

# 查看特定状态的连接
ss -tn state established          # 已建立的连接
ss -tn state time-wait            # TIME_WAIT 状态
ss -tn state close-wait           # CLOSE_WAIT 状态（可能资源泄漏）

# 统计各状态数量
ss -tan | awk '{print $1}' | sort | uniq -c | sort -rn
```

### 4.5 TCP 连接状态解读

<!-- DIAGRAM: tcp-states -->
```
┌───────────────────────────────────────────────────────────────────────────┐
│                       TCP 连接状态与排查                                    │
├───────────────────────────────────────────────────────────────────────────┤
│                                                                           │
│  关键状态：                                                               │
│  ─────────                                                                │
│                                                                           │
│  ESTABLISHED  ─────────── 正常的活跃连接                                  │
│                                                                           │
│  TIME_WAIT   ─────────── 连接关闭后等待状态                               │
│                          持续 2*MSL (通常 60秒)                           │
│                          大量 TIME_WAIT → 可能端口耗尽                    │
│                                                                           │
│  CLOSE_WAIT  ─────────── 对端关闭，本端未关闭                             │
│                          大量 CLOSE_WAIT → 应用代码问题（未关闭连接）      │
│                                                                           │
│  SYN_SENT    ─────────── 发送 SYN，等待响应                               │
│                          长时间停留 → 对端无响应或防火墙丢包               │
│                                                                           │
│  FIN_WAIT1/2 ─────────── 正在关闭连接                                     │
│                          大量堆积 → 对端应用异常                          │
│                                                                           │
│                                                                           │
│  排查命令：                                                               │
│  ─────────                                                                │
│                                                                           │
│  # 统计各状态数量                                                         │
│  ss -tan | awk 'NR>1 {print $1}' | sort | uniq -c | sort -rn              │
│                                                                           │
│  # 查看 TIME_WAIT 数量                                                    │
│  ss -tan state time-wait | wc -l                                          │
│                                                                           │
│  # 查看哪些 IP 有大量连接                                                 │
│  ss -tan | awk '{print $5}' | cut -d: -f1 | sort | uniq -c | sort -rn     │
│                                                                           │
└───────────────────────────────────────────────────────────────────────────┘
```
<!-- /DIAGRAM -->

---

## Step 5 -- Layer 7 诊断：应用层（20 分钟）

### 5.1 curl 详细诊断

```bash
# 详细模式
curl -v http://example.com/

# 输出关键信息：
# * Trying 93.184.216.34:80...           ← 连接 IP
# * Connected to example.com              ← 连接成功
# > GET / HTTP/1.1                        ← 请求发送
# < HTTP/1.1 200 OK                       ← 响应状态

# 只显示 HTTP 头
curl -I http://example.com/

# 设置超时
curl --connect-timeout 5 --max-time 10 http://example.com/

# 指定 DNS 解析（绕过本地 DNS）
curl --resolve example.com:80:93.184.216.34 http://example.com/

# 使用特定源 IP（多网卡）
curl --interface eth0 http://example.com/
```

### 5.2 curl 时间分析

```bash
# 显示详细时间信息
curl -w @- -o /dev/null -s http://example.com/ <<'EOF'
    time_namelookup:  %{time_namelookup}s
       time_connect:  %{time_connect}s
    time_appconnect:  %{time_appconnect}s
   time_pretransfer:  %{time_pretransfer}s
      time_redirect:  %{time_redirect}s
 time_starttransfer:  %{time_starttransfer}s
                    ----------
         time_total:  %{time_total}s
EOF

# 输出解读：
#     time_namelookup:  0.012s  ← DNS 解析时间
#        time_connect:  0.025s  ← TCP 连接时间
#     time_appconnect:  0.100s  ← TLS 握手时间（HTTPS）
#    time_pretransfer:  0.100s  ← 准备传输时间
#       time_redirect:  0.000s  ← 重定向时间
#  time_starttransfer:  0.150s  ← 首字节时间 (TTFB)
#          time_total:  0.200s  ← 总时间

# 问题诊断：
# - time_namelookup 很大 → DNS 问题
# - time_connect - time_namelookup 很大 → 网络延迟或连接问题
# - time_starttransfer - time_connect 很大 → 服务器响应慢
```

### 5.3 DNS 诊断

```bash
# 基本查询
dig example.com

# 只显示结果
dig +short example.com

# 指定 DNS 服务器
dig @8.8.8.8 example.com

# 追踪完整解析过程
dig +trace example.com

# 反向 DNS 查询
dig -x 93.184.216.34

# 查看本地 DNS 配置
cat /etc/resolv.conf

# systemd-resolved 状态
resolvectl status
# 或
systemd-resolve --status
```

### 5.4 DNS 问题诊断流程

<!-- DIAGRAM: dns-troubleshooting -->
```
┌───────────────────────────────────────────────────────────────────────────┐
│                       DNS 问题诊断流程                                      │
├───────────────────────────────────────────────────────────────────────────┤
│                                                                           │
│  DNS 解析失败                                                             │
│       │                                                                   │
│       ▼                                                                   │
│  ┌─────────────────────────────────┐                                      │
│  │ 检查 /etc/resolv.conf          │                                      │
│  │ nameserver 配置正确吗？         │                                      │
│  └──────────────┬──────────────────┘                                      │
│                 │                                                         │
│        ┌────────┴────────┐                                                │
│        │ 配置错误        │ 配置正确                                       │
│        ▼                 ▼                                                │
│  ┌──────────────┐  ┌─────────────────────────────────┐                   │
│  │ 修复配置    │  │ dig @<nameserver> <域名>        │                   │
│  │             │  │ DNS 服务器能响应吗？            │                   │
│  └──────────────┘  └──────────────┬──────────────────┘                   │
│                                   │                                       │
│                          ┌────────┴────────┐                              │
│                          │ 不响应          │ 响应正常                     │
│                          ▼                 ▼                              │
│                   ┌──────────────┐  ┌──────────────────────────┐         │
│                   │ DNS 服务器   │  │ dig @8.8.8.8 <域名>      │         │
│                   │ 不可达       │  │ 公共 DNS 能解析吗？      │         │
│                   │              │  └──────────────┬───────────┘         │
│                   │ 检查：       │                 │                      │
│                   │ - ping DNS   │        ┌────────┴────────┐             │
│                   │ - 防火墙     │        │ 不能            │ 能          │
│                   │ - 网络路由   │        ▼                 ▼             │
│                   └──────────────┘  ┌──────────────┐  ┌──────────────┐   │
│                                     │ 域名本身问题 │  │ 本地 DNS     │   │
│                                     │ 或上游 DNS   │  │ 配置/缓存    │   │
│                                     │ 故障         │  │ 问题         │   │
│                                     └──────────────┘  └──────────────┘   │
│                                                                           │
│  常见 DNS 问题：                                                          │
│  ───────────────                                                          │
│  • /etc/resolv.conf 被覆盖（NetworkManager, systemd-resolved）            │
│  • 首个 nameserver 不可达（导致 5 秒超时）                                 │
│  • DNS 缓存过期或污染                                                      │
│  • systemd-resolved 配置问题                                              │
│                                                                           │
└───────────────────────────────────────────────────────────────────────────┘
```
<!-- /DIAGRAM -->

### 5.5 DNS 超时问题

DNS 超时是常见的"神秘延迟"来源：

```bash
# 场景：命令启动慢 5 秒
# 原因：/etc/resolv.conf 中首个 nameserver 不可达

# 检查 resolv.conf
cat /etc/resolv.conf
# nameserver 10.0.0.1    ← 如果这个不可达，等待 5 秒超时
# nameserver 8.8.8.8

# 测试 DNS 服务器连通性
nc -zvu 10.0.0.1 53
# 或
dig @10.0.0.1 google.com +time=2

# 解决方案：
# 1. 调整 nameserver 顺序
# 2. 设置超时时间
echo "options timeout:1 attempts:2" >> /etc/resolv.conf
```

---

## Step 6 -- 防火墙诊断（15 分钟）

### 6.1 nftables 检查

```bash
# 查看所有规则
nft list ruleset

# 查看特定表
nft list table inet filter

# 查看规则计数器
nft list ruleset -a

# 常见问题：
# - INPUT chain 默认 DROP，但没有放行规则
# - 规则顺序错误（REJECT 在 ACCEPT 之前）
```

### 6.2 firewalld 检查（RHEL/CentOS）

```bash
# 查看状态
systemctl status firewalld

# 查看当前区域
firewall-cmd --get-active-zones

# 查看区域规则
firewall-cmd --zone=public --list-all

# 查看所有开放端口
firewall-cmd --list-ports

# 临时放行端口（测试用）
firewall-cmd --zone=public --add-port=8080/tcp

# 永久放行
firewall-cmd --zone=public --add-port=8080/tcp --permanent
firewall-cmd --reload
```

### 6.3 查找防火墙丢包

```bash
# 方法 1：查看 dmesg
dmesg | grep -iE 'drop|reject|block' | tail -20

# 方法 2：nftables 添加日志规则
nft add rule inet filter input log prefix "NFT-DROP: " drop

# 方法 3：查看 /var/log/messages 或 /var/log/kern.log
grep -i 'drop\|reject\|block' /var/log/messages | tail -20

# 方法 4：tcpdump 抓包分析
tcpdump -i eth0 host 192.168.1.100 and port 80 -nn
```

### 6.4 临时禁用防火墙（排查用）

```bash
# 警告：仅用于排查，排查后立即恢复！

# 禁用 firewalld
systemctl stop firewalld

# 禁用 nftables
nft flush ruleset

# 禁用 iptables
iptables -F
iptables -P INPUT ACCEPT
iptables -P FORWARD ACCEPT
iptables -P OUTPUT ACCEPT

# 如果禁用防火墙后问题消失 → 确认是防火墙规则问题
# 立即恢复防火墙！
systemctl start firewalld
```

---

## Step 7 -- 高级网络问题（20 分钟）

### 7.1 MTU 不匹配

MTU（Maximum Transmission Unit）不匹配会导致大包丢失，表现为：
- 小数据量正常，大文件传输失败
- HTTPS 握手失败（证书太大）
- 间歇性连接问题

```bash
# 查看 MTU
ip link show eth0 | grep mtu

# 测试路径 MTU
ping -M do -s 1472 192.168.1.1
# -M do: 不分片
# -s 1472: 数据大小 (1472 + 28 = 1500 = 标准 MTU)

# 如果返回 "Message too long" → 路径上有更小的 MTU

# 逐步减小找到最大可用
ping -M do -s 1400 192.168.1.1

# 临时修改 MTU
ip link set eth0 mtu 1400
```

### 7.2 临时端口耗尽（Ephemeral Port Exhaustion）

这是"TCP 黑洞"场景的常见原因：

```bash
# 检查可用端口范围
cat /proc/sys/net/ipv4/ip_local_port_range
# 32768   60999  ← 默认范围约 28000 个端口

# 查看 TIME_WAIT 连接数
ss -tan state time-wait | wc -l

# 查看到特定目标的连接数
ss -tan | grep <后端IP> | wc -l

# 问题诊断：
# 如果 TIME_WAIT 数量接近端口范围 → 端口耗尽！

# 解决方案 1：启用 tcp_tw_reuse
echo 1 > /proc/sys/net/ipv4/tcp_tw_reuse
# 或永久生效
echo "net.ipv4.tcp_tw_reuse = 1" >> /etc/sysctl.conf
sysctl -p

# 解决方案 2：扩大端口范围
echo "10240 65535" > /proc/sys/net/ipv4/ip_local_port_range

# 解决方案 3：应用层使用连接池
# 这才是根本解决方案！
```

### 7.3 连接跟踪表满（conntrack full）

```bash
# 检查 conntrack 表使用
cat /proc/sys/net/netfilter/nf_conntrack_count
cat /proc/sys/net/netfilter/nf_conntrack_max

# 如果 count 接近 max → 表满了！

# 查看 conntrack 条目
conntrack -L | head -20

# 解决方案：增大表大小
echo 262144 > /proc/sys/net/netfilter/nf_conntrack_max
# 或永久
echo "net.netfilter.nf_conntrack_max = 262144" >> /etc/sysctl.conf

# 减少超时时间
echo 60 > /proc/sys/net/netfilter/nf_conntrack_tcp_timeout_time_wait
```

### 7.4 内核网络参数检查

```bash
# 查看关键网络参数
sysctl -a | grep -E 'somaxconn|backlog|tw_reuse|port_range|conntrack'

# 关键参数说明：
# net.core.somaxconn              ← 监听队列最大长度
# net.core.netdev_max_backlog     ← 网卡接收队列长度
# net.ipv4.tcp_tw_reuse           ← 重用 TIME_WAIT 连接
# net.ipv4.ip_local_port_range    ← 临时端口范围
# net.netfilter.nf_conntrack_max  ← 连接跟踪表大小
```

---

## Step 8 -- 网络诊断决策树（10 分钟）

### 8.1 完整决策树

<!-- DIAGRAM: network-decision-tree -->
```
┌───────────────────────────────────────────────────────────────────────────┐
│                       网络问题诊断决策树                                    │
├───────────────────────────────────────────────────────────────────────────┤
│                                                                           │
│  连通性问题                                                               │
│       │                                                                   │
│       ▼                                                                   │
│  ┌─────────────────────────────────┐                                      │
│  │ ip link show                    │                                      │
│  │ 网卡状态 UP 吗？                │                                      │
│  └──────────────┬──────────────────┘                                      │
│                 │                                                         │
│        ┌────────┴────────┐                                                │
│        │ DOWN            │ UP                                             │
│        ▼                 ▼                                                │
│  ┌──────────────┐  ┌─────────────────────────────────┐                   │
│  │ L1/L2 问题   │  │ ping <目标IP>                   │                   │
│  │ 检查网线/   │  │ L3 连通吗？                     │                   │
│  │ 网卡配置    │  └──────────────┬──────────────────┘                   │
│  └──────────────┘                │                                        │
│                         ┌────────┴────────┐                               │
│                         │ 不通            │ 通                            │
│                         ▼                 ▼                               │
│                   ┌──────────────┐  ┌─────────────────────────────────┐  │
│                   │ L3 问题      │  │ nc -zv <IP> <PORT>              │  │
│                   │              │  │ L4 端口开放吗？                 │  │
│                   │ 检查：       │  └──────────────┬──────────────────┘  │
│                   │ - ip route   │                 │                      │
│                   │ - 网关       │        ┌────────┴────────┐             │
│                   │ - 防火墙L3   │        │ 拒绝/超时       │ 成功        │
│                   └──────────────┘        ▼                 ▼             │
│                                     ┌──────────────┐  ┌──────────────┐   │
│                                     │ L4 问题      │  │ L7 问题      │   │
│                                     │              │  │              │   │
│                                     │ 拒绝：       │  │ curl/dig     │   │
│                                     │ ss -lntup    │  │ 应用层诊断   │   │
│                                     │ 服务监听?    │  │              │   │
│                                     │              │  │ 检查：       │   │
│                                     │ 超时：       │  │ - HTTP 响应  │   │
│                                     │ 防火墙L4     │  │ - DNS 解析   │   │
│                                     │ nft/firewall │  │ - 应用日志   │   │
│                                     └──────────────┘  └──────────────┘   │
│                                                                           │
└───────────────────────────────────────────────────────────────────────────┘
```
<!-- /DIAGRAM -->

### 8.2 快速诊断脚本

```bash
#!/bin/bash
# network-diag.sh - 快速网络诊断脚本

TARGET=${1:-"8.8.8.8"}
PORT=${2:-"80"}

echo "=========================================="
echo "Network Diagnosis for $TARGET:$PORT"
echo "=========================================="

echo ""
echo "[1] Local Network Interface"
ip link show | grep -E '^[0-9]+:|state'

echo ""
echo "[2] IP Address"
ip addr show | grep 'inet '

echo ""
echo "[3] Default Route"
ip route | grep default

echo ""
echo "[4] L3 - Ping Test"
ping -c 3 -W 2 $TARGET 2>&1 | tail -3

echo ""
echo "[5] L4 - Port Test"
nc -zv -w 3 $TARGET $PORT 2>&1

echo ""
echo "[6] Local Listening Ports"
ss -lntup | head -10

echo ""
echo "[7] DNS Resolution"
dig +short $TARGET 2>/dev/null || echo "Not a hostname or dig not available"

echo ""
echo "[8] Connection Statistics"
ss -s | head -5

echo ""
echo "=========================================="
echo "Done"
echo "=========================================="
```

---

## Step 9 -- 实战场景：TCP 黑洞（25 分钟）

### 9.1 场景描述

> **场景**：Nginx 反向代理间歇性返回 502 Bad Gateway。  
>
> 表现：  
> - 大部分请求正常  
> - 偶尔返回 502，几秒后恢复  
> - 后端服务健康检查正常  
> - 问题在高峰期更频繁  

### 9.2 排查步骤

**Step 1：查看 Nginx 错误日志**

```bash
tail -f /var/log/nginx/error.log

# 输出：
# connect() failed (99: Cannot assign requested address) while connecting to upstream
#                     ↑ 关键！无法分配地址 = 端口耗尽
```

**Step 2：检查 TCP 连接状态**

```bash
# 查看连接统计
ss -s

# 输出：
# TCP:   28567 (estab 234, closed 123, orphaned 12, timewait 27890)
#                                                      ↑ 大量 TIME_WAIT

# 查看 TIME_WAIT 数量
ss -tan state time-wait | wc -l
# 27890

# 查看端口范围
cat /proc/sys/net/ipv4/ip_local_port_range
# 32768   60999  ← 约 28000 个端口
# TIME_WAIT 已占用 27890 个！几乎耗尽！
```

**Step 3：确认连接目标**

```bash
# 查看 TIME_WAIT 连接到哪里
ss -tan state time-wait | awk '{print $4}' | cut -d: -f1 | sort | uniq -c | sort -rn | head -5

# 输出：
# 25000 10.0.0.100    ← 大量连接到后端服务器
# 2000  10.0.0.101
```

**Step 4：分析根因**

```
问题链：
1. Nginx 到后端使用短连接（每个请求新建 TCP 连接）
2. 连接关闭后进入 TIME_WAIT 状态（等待 2*MSL = 60秒）
3. 高峰期每秒 500 请求，60 秒内累积 30000 个 TIME_WAIT
4. 临时端口范围只有 28000 个
5. 端口耗尽 → 无法建立新连接 → 502
```

**Step 5：临时解决**

```bash
# 启用 TIME_WAIT 重用
echo 1 > /proc/sys/net/ipv4/tcp_tw_reuse

# 扩大端口范围
echo "10240 65535" > /proc/sys/net/ipv4/ip_local_port_range

# 永久生效
cat >> /etc/sysctl.conf << EOF
net.ipv4.tcp_tw_reuse = 1
net.ipv4.ip_local_port_range = 10240 65535
EOF
sysctl -p
```

**Step 6：根本解决（应用层）**

```nginx
# nginx.conf - 启用连接池（keepalive）
upstream backend {
    server 10.0.0.100:8080;
    server 10.0.0.101:8080;

    keepalive 100;  # 保持 100 个长连接
}

server {
    location / {
        proxy_pass http://backend;
        proxy_http_version 1.1;
        proxy_set_header Connection "";  # 使用长连接
    }
}
```

### 9.3 验证修复

```bash
# 重启 Nginx
nginx -t && systemctl reload nginx

# 监控 TIME_WAIT 数量
watch -n 1 'ss -tan state time-wait | wc -l'

# 应该看到 TIME_WAIT 数量显著下降
```

---

## Step 10 -- 实战场景：DNS 超时（15 分钟）

### 10.1 场景描述

> **场景**：CLI 工具（如 curl 或自定义脚本）启动需要 5 秒，然后运行正常。  
>
> 表现：  
> - 任何网络命令都延迟 5 秒  
> - 延迟后工作正常  
> - 重启后问题依旧  

### 10.2 排查步骤

**Step 1：使用 strace 定位阻塞**

```bash
strace -tt -T -o /tmp/trace.log curl -s http://example.com/

# 查看耗时最长的系统调用
grep -E '\<[0-9]+\.[0-9]{3,}\>' /tmp/trace.log | sort -t= -k2 -n | tail -10

# 输出可能显示：
# 14:30:01.123 poll([{fd=3, events=POLLIN}], 1, 5000) = 0 (Timeout) <5.001234>
#                                                        ↑ poll 超时 5 秒！
```

**Step 2：识别 DNS 超时**

```bash
# 查看超时前后的系统调用
grep -B 5 -A 5 'Timeout' /tmp/trace.log

# 通常会看到：
# socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP) = 3
# connect(3, {sa_family=AF_INET, sin_port=53, sin_addr=inet_addr("10.0.0.1")}, 16) = 0
# sendto(3, "...", 28, 0, NULL, 0) = 28
# poll([{fd=3, events=POLLIN}], 1, 5000) = 0 (Timeout)
#      ↑ 向 10.0.0.1:53 (DNS) 发送请求后超时
```

**Step 3：检查 DNS 配置**

```bash
cat /etc/resolv.conf
# nameserver 10.0.0.1    ← 首个 DNS 不可达
# nameserver 8.8.8.8

# 测试首个 DNS
nc -zvu -w 1 10.0.0.1 53
# nc: connect to 10.0.0.1 port 53 (udp) failed: Connection timed out

# 测试第二个 DNS
nc -zvu -w 1 8.8.8.8 53
# Connection to 8.8.8.8 53 port [udp/domain] succeeded!
```

**Step 4：解决方案**

```bash
# 方案 1：移除不可达的 DNS
# 编辑 /etc/resolv.conf，删除或注释 10.0.0.1

# 方案 2：调整超时设置
cat > /etc/resolv.conf << EOF
nameserver 8.8.8.8
nameserver 10.0.0.1
options timeout:1 attempts:2
EOF

# 方案 3：如果使用 NetworkManager
nmcli con mod "System eth0" ipv4.dns "8.8.8.8"
nmcli con up "System eth0"

# 方案 4：如果使用 systemd-resolved
# 编辑 /etc/systemd/resolved.conf
# [Resolve]
# DNS=8.8.8.8
# FallbackDNS=1.1.1.1
systemctl restart systemd-resolved
```

---

## 动手实验（30 分钟）

### 实验 1：分层诊断练习

在你的测试环境中完成以下诊断：

```bash
# 1. L2 检查
ip link show
# 记录：网卡状态，是否有 errors

# 2. L3 检查
ip addr show
ip route
ping -c 3 <默认网关>
# 记录：IP 配置，路由，网关连通性

# 3. L4 检查
ss -lntup
nc -zv <某个服务器> 22
# 记录：监听端口，远程端口连通性

# 4. L7 检查
curl -v http://example.com/
dig example.com
# 记录：HTTP 响应，DNS 解析
```

### 实验 2：模拟端口耗尽

```bash
# 警告：仅在测试环境执行！

# 1. 设置一个小的端口范围
echo "60000 60100" > /proc/sys/net/ipv4/ip_local_port_range

# 2. 创建大量连接
for i in $(seq 1 100); do
    nc -z example.com 80 &
done
wait

# 3. 观察 TIME_WAIT
ss -tan state time-wait | wc -l

# 4. 尝试新连接
curl http://example.com/
# 可能会看到 "Cannot assign requested address"

# 5. 恢复端口范围
echo "32768 60999" > /proc/sys/net/ipv4/ip_local_port_range
```

### 实验 3：DNS 诊断练习

```bash
# 1. 查看当前 DNS 配置
cat /etc/resolv.conf

# 2. 测试 DNS 解析时间
time dig google.com

# 3. 追踪完整解析过程
dig +trace google.com

# 4. 使用不同 DNS 服务器
dig @8.8.8.8 google.com +short
dig @1.1.1.1 google.com +short

# 5. 测试 DNS 服务器连通性
for dns in 8.8.8.8 1.1.1.1 9.9.9.9; do
    echo -n "$dns: "
    nc -zvu -w 1 $dns 53 2>&1 | grep -o 'succeeded\|failed'
done
```

---

## 反模式：常见错误

### 错误 1：只盯网络

```bash
# 错误：直接假设是网络问题
ping <服务器>  # 通了
# "网络没问题啊，肯定是应用的问题"

# 正确：分层验证
ss -lntup | grep ':80'  # 先检查服务是否监听
nc -zv <服务器> 80       # 再检查端口连通性
curl -v http://<服务器>/ # 最后检查应用层
```

### 错误 2：忽略 DNS

```bash
# 错误：不考虑 DNS 问题
curl http://api.example.com/  # 超时
# "服务器挂了！"

# 正确：先检查 DNS
dig api.example.com +short
# 如果返回空或超时 → DNS 问题，不是服务器问题
```

### 错误 3：只看 ping

```bash
# 错误：ping 通就认为没问题
ping <服务器>  # 成功
# "网络正常"

# 正确：ping 只测试 L3
# ping 通不代表：
# - 服务端口开放（L4）
# - 应用正常响应（L7）
# - 防火墙允许业务流量

nc -zv <服务器> 80  # 检查 L4
curl -I http://<服务器>/  # 检查 L7
```

### 错误 4：临时端口问题忽略

```bash
# 错误：只看是否有连接
ss -tan | wc -l
# "连接数不多啊"

# 正确：检查 TIME_WAIT
ss -tan state time-wait | wc -l
# TIME_WAIT 也占用端口！
```

---

## 职场小贴士（Japan IT Context）

### 网络排查基本功（ネットワーク障害の切り分け）

在日本 IT 现场，网络排查能力是基本技能：

| 日语术语 | 含义 | 场景 |
|----------|------|------|
| 疎通確認 | 连通性确认 | ping/nc 测试 |
| 切り分け | 问题隔离 | 分层诊断 |
| 証跡 | 证据/记录 | 截图命令输出 |
| 一次切り分け | 初步隔离 | 确定问题在哪一层 |
| 詳細調査 | 详细调查 | tcpdump 等深入分析 |

### 网络排查报告要点

日本企业的网络故障报告需要：

```markdown
# ネットワーク障害 切り分け結果

## 確認日時
2026-01-10 14:30 (JST)

## 事象
API サーバーへの接続がタイムアウト

## 切り分け結果
| 確認項目 | コマンド | 結果 |
|----------|----------|------|
| L3 疎通 | ping 192.168.1.100 | OK |
| L4 ポート | nc -zv 192.168.1.100 80 | NG (Connection refused) |
| サービス状態 | systemctl status nginx | inactive (dead) |

## 原因
nginx サービスが停止していた

## 対応
systemctl start nginx でサービス起動
```

### 保留证据的重要性

```bash
# 在日本企业，"证据"非常重要
# 排查过程中务必保存输出

# 保存网络诊断结果
{
    echo "=== $(date) ==="
    echo ""
    echo "--- ip link ---"
    ip link show
    echo ""
    echo "--- ip addr ---"
    ip addr show
    echo ""
    echo "--- ip route ---"
    ip route
    echo ""
    echo "--- ss -lntup ---"
    ss -lntup
    echo ""
    echo "--- ping test ---"
    ping -c 3 <目标>
} > /tmp/network-diag-$(date +%Y%m%d-%H%M%S).txt
```

### 面试常见问题

**Q1: ネットワーク障害が発生した場合、どのように切り分けますか？**
（网络故障发生时，如何进行问题隔离？）

参考答案：
1. 分層アプローチで切り分けます
2. まず L3（ping）で IP レベルの疎通を確認
3. 次に L4（nc -zv）でポートの疎通を確認
4. 最後に L7（curl）でアプリケーション層を確認
5. 各層で問題が見つかれば、その層を詳細調査します

**Q2: DNS の問題をどのように診断しますか？**
（DNS 问题如何诊断？）

参考答案：
1. /etc/resolv.conf の nameserver 設定を確認
2. dig コマンドで名前解決をテスト
3. dig @8.8.8.8 で公開 DNS との比較
4. DNS サーバーへの疎通（nc -zvu <DNS> 53）を確認
5. 必要に応じて dig +trace で解決経路を追跡

**Q3: 「Cannot assign requested address」エラーの原因は？**

参考答案：
- 一時ポートの枯渇が原因です
- ss -s で TIME_WAIT 数を確認します
- 解決策：
  - tcp_tw_reuse を有効化
  - ip_local_port_range を拡大
  - アプリケーション側でコネクションプールを使用

---

## 检查清单

完成本课后，你应该能够：

- [ ] 解释网络四层诊断模型（L2/L3/L4/L7）
- [ ] 使用 ip link/addr/route 诊断 L2/L3 问题
- [ ] 使用 ss -lntup 检查服务监听状态
- [ ] 使用 nc -zv 测试端口连通性
- [ ] 使用 dig 诊断 DNS 问题
- [ ] 检查 /etc/resolv.conf 配置
- [ ] 使用 firewall-cmd 或 nft 检查防火墙规则
- [ ] 解释 TIME_WAIT 状态及其影响
- [ ] 诊断临时端口耗尽问题
- [ ] 使用 curl 时间分析定位延迟来源
- [ ] 使用网络诊断决策树系统性排查问题

---

## 本课小结

| 概念 | 关键命令 | 记忆点 |
|------|----------|--------|
| L2 诊断 | ip link, ethtool | 网卡状态，物理连接 |
| L3 诊断 | ping, traceroute, ip route | IP 层连通性，路由 |
| L4 诊断 | ss -lntup, nc -zv | 端口监听，TCP 连接 |
| L7 诊断 | curl -v, dig | HTTP 响应，DNS 解析 |
| DNS 问题 | dig, /etc/resolv.conf | 首个 nameserver 不可达 = 5秒超时 |
| 防火墙 | nft list, firewall-cmd | 先检查规则再责怪网络 |
| 端口耗尽 | ss -tan state time-wait | TIME_WAIT 累积导致 502 |
| MTU 问题 | ping -M do -s 1472 | 大包不通、小包正常 |

**核心理念**：

> 分层诊断，逐层验证。  
> ping 通不代表服务可用。  
> DNS 问题常被误诊。  
> TIME_WAIT 也占端口。  

---

## 延伸阅读

- [Brendan Gregg - Linux Network Performance](https://www.brendangregg.com/networking.html)
- [Red Hat - Network Troubleshooting](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/9/html/configuring_and_managing_networking/index)
- [TCP/IP Guide](http://www.tcpipguide.com/)
- 下一课：[05 - 存储故障](../05-storage-issues/) -- 容量、inode、I/O 错误
- 相关课程：[LX06-NETWORK](../../network/) -- 网络基础知识

---

## 系列导航

[<-- 03 - 服务故障](../03-service-failures/) | [系列首页](../) | [05 - 存储故障 -->](../05-storage-issues/)
