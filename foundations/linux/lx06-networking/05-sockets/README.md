# 05 - 套接字检查 (ss)

> **目标**：使用 ss 命令检查网络连接和监听端口，排查"服务运行但无法连接"问题  
> **前置**：了解 TCP/IP 基础和 DNS 配置（01-04 课）  
> **时间**：45 分钟  
> **环境**：任意 Linux 发行版（Ubuntu, AlmaLinux, Amazon Linux 均可）  

---

## 将学到的内容

1. 使用 ss 命令检查监听端口和连接
2. 理解常见套接字状态（LISTEN、ESTABLISHED、TIME_WAIT）
3. 区分 0.0.0.0 vs 127.0.0.1 监听地址
4. 使用 ss 过滤器快速定位问题
5. 知道 netstat 已弃用及区别

---

## Step 1 - 先跑起来：快速检查端口（5 分钟）

> **目标**：先"尝到" ss 命令的威力，再理解原理。  

打开终端，运行这条最常用的命令：

### 1.1 查看所有监听端口

```bash
ss -tuln
```

```
Netid  State   Recv-Q  Send-Q   Local Address:Port    Peer Address:Port  Process
tcp    LISTEN  0       128      0.0.0.0:22             0.0.0.0:*
tcp    LISTEN  0       511      127.0.0.1:80           0.0.0.0:*
tcp    LISTEN  0       128      0.0.0.0:443            0.0.0.0:*
udp    UNCONN  0       0        127.0.0.53%lo:53       0.0.0.0:*
```

**参数解释**：

| 参数 | 含义 |
|------|------|
| `-t` | TCP 套接字 |
| `-u` | UDP 套接字 |
| `-l` | 仅显示 LISTEN 状态（监听中） |
| `-n` | 数字格式（不解析域名） |

**你看到了**：哪些服务在等待连接，监听在什么地址和端口。

### 1.2 加上进程信息

```bash
sudo ss -tulpn
```

```
Netid  State   Recv-Q  Send-Q   Local Address:Port    Peer Address:Port  Process
tcp    LISTEN  0       128      0.0.0.0:22             0.0.0.0:*          users:(("sshd",pid=1234,fd=3))
tcp    LISTEN  0       511      127.0.0.1:80           0.0.0.0:*          users:(("nginx",pid=5678,fd=6))
```

`-p` 参数显示进程名和 PID，需要 root 权限。

### 1.3 查看所有连接（包括已建立的）

```bash
ss -tan
```

```
State      Recv-Q  Send-Q   Local Address:Port    Peer Address:Port
LISTEN     0       128      0.0.0.0:22             0.0.0.0:*
ESTAB      0       0        10.0.1.52:22           203.0.113.50:54321
TIME_WAIT  0       0        10.0.1.52:80           198.51.100.10:45678
```

**你看到了**：监听的端口 + 已建立的连接 + 等待关闭的连接。

---

**3 条命令，完整的套接字状态！**

| 命令 | 用途 |
|------|------|
| `ss -tuln` | 快速查看监听端口 |
| `ss -tulpn` | 查看监听端口 + 进程（需 sudo） |
| `ss -tan` | 查看所有 TCP 连接状态 |

接下来，让我们理解输出中的关键信息。

---

## Step 2 - 发生了什么？监听地址的秘密（10 分钟）

### 2.1 最常见的陷阱：0.0.0.0 vs 127.0.0.1

看这两行输出：

```
tcp    LISTEN  0  128  0.0.0.0:22       0.0.0.0:*
tcp    LISTEN  0  511  127.0.0.1:80     0.0.0.0:*
```

| 监听地址 | 含义 | 远程可访问？ |
|----------|------|--------------|
| `0.0.0.0:22` | 监听所有网络接口 | 是 |
| `127.0.0.1:80` | 仅监听本地回环 | 否 |
| `:::22` | IPv6 所有接口 | 是 |
| `::1:80` | IPv6 本地回环 | 否 |

**这是运维排障的头号陷阱！**

服务在运行（`systemctl status` 显示 active），但远程连不上。原因往往是服务绑定了 `127.0.0.1`。

<!-- DIAGRAM: listen-address-comparison -->
```
监听地址决定谁能连接
════════════════════════════════════════════════════════════════════

场景 A：服务监听 0.0.0.0:80
─────────────────────────────────────────────────────────────────────
                                    ┌─────────────────┐
    互联网用户 ─────────────────────▶│                 │
                                    │    服务器       │
    内网同事   ─────────────────────▶│  0.0.0.0:80    │ ✓ 全部可访问
                                    │                 │
    本机 curl  ─────────────────────▶│                 │
                                    └─────────────────┘

场景 B：服务监听 127.0.0.1:80
─────────────────────────────────────────────────────────────────────
                                    ┌─────────────────┐
    互联网用户 ────────── ✗ ─────────│                 │
                                    │    服务器       │
    内网同事   ────────── ✗ ─────────│ 127.0.0.1:80   │ 仅本机可访问
                                    │                 │
    本机 curl  ─────────────────────▶│                 │ ✓
                                    └─────────────────┘
```
<!-- /DIAGRAM -->

### 2.2 实际验证

假设你有一个 Nginx 服务：

```bash
# 检查监听地址
sudo ss -tulpn | grep nginx
```

如果输出是：
```
tcp  LISTEN  0  511  127.0.0.1:80  0.0.0.0:*  users:(("nginx",pid=5678))
```

那就解释了为什么 `curl localhost` 成功，但从其他机器访问失败：

```bash
# 本机测试 - 成功
curl http://localhost

# 远程测试 - 失败（Connection refused）
curl http://<服务器IP>
```

**修复方法**：修改服务配置，绑定到 `0.0.0.0` 或具体的外部 IP。

---

## Step 3 - 核心概念：套接字状态详解（10 分钟）

### 3.1 TCP 连接生命周期

<!-- DIAGRAM: tcp-socket-states -->
```
TCP 套接字状态转换图
════════════════════════════════════════════════════════════════════

服务端                                          客户端
────────                                        ────────

  CLOSED                                         CLOSED
     │                                              │
     │ bind() + listen()                            │
     ▼                                              │
  LISTEN ◀────────────────────────────────────┐     │
     │                                        │     │
     │         收到 SYN                       │     │ connect()
     ▼                                        │     ▼
  SYN_RCVD ─────────────────────────────────────── SYN_SENT
     │           发送 SYN+ACK                       │
     │                                              │
     │         收到 ACK                收到 SYN+ACK │
     ▼                                              ▼
  ╔═══════════════════════════════════════════════════════╗
  ║              ESTABLISHED (数据传输)                   ║
  ║                                                       ║
  ║  这是正常工作状态，ss -tan 会显示大量 ESTAB          ║
  ╚═══════════════════════════════════════════════════════╝
     │                                              │
     │ close()                            close()   │
     ▼                                              ▼
  FIN_WAIT_1 ─────────────────────────────── CLOSE_WAIT
     │           发送/收到 FIN                      │
     ▼                                              │
  FIN_WAIT_2                                        │ close()
     │                                              ▼
     │         收到 FIN                        LAST_ACK
     ▼                                              │
  ╔═══════════════════════════════════════════════════════╗
  ║              TIME_WAIT (等待 2MSL)                    ║
  ║                                                       ║
  ║  大量 TIME_WAIT 是正常现象（高并发场景）              ║
  ║  但过多可能耗尽端口                                   ║
  ╚═══════════════════════════════════════════════════════╝
     │
     │ 2MSL 超时
     ▼
  CLOSED
```
<!-- /DIAGRAM -->

### 3.2 常见状态及含义

| 状态 | 含义 | 正常？ | 排障提示 |
|------|------|--------|----------|
| **LISTEN** | 等待连接 | 是 | 服务正在监听 |
| **ESTABLISHED** | 连接已建立 | 是 | 正常通信中 |
| **SYN_SENT** | 发送 SYN，等待响应 | 短暂 | 大量堆积 = 目标不响应 |
| **SYN_RCVD** | 收到 SYN，等待 ACK | 短暂 | 大量堆积 = 可能 SYN 洪水攻击 |
| **TIME_WAIT** | 等待确保对方收到 FIN | 是 | 高并发正常，过多需调优 |
| **CLOSE_WAIT** | 等待应用关闭 | 警告 | 大量堆积 = 应用未正确关闭连接 |
| **FIN_WAIT_1/2** | 主动关闭，等待对方响应 | 短暂 | 长时间卡住 = 网络问题 |

### 3.3 快速状态统计

```bash
# 统计各状态的连接数
ss -tan | awk '{print $1}' | sort | uniq -c | sort -rn
```

```
    127 ESTAB
     45 TIME-WAIT
     12 LISTEN
      3 CLOSE-WAIT
      1 State
```

**解读**：
- `ESTAB` 最多 = 正常，有很多活跃连接
- `TIME_WAIT` 较多 = 高并发场景正常
- `CLOSE_WAIT` 堆积 = 应用程序 bug，需要排查

---

## Step 4 - 动手实验：ss 过滤器（10 分钟）

### Lab 1：按状态过滤

```bash
# 只看 ESTABLISHED 连接
ss -tan state established

# 只看 TIME_WAIT
ss -tan state time-wait

# 只看 LISTEN
ss -tln state listening
```

### Lab 2：按端口过滤

```bash
# 查看 22 端口的所有连接
ss -tan 'sport = :22'

# 查看目标端口是 443 的连接
ss -tan 'dport = :443'

# 组合：源端口 22，状态 ESTABLISHED
ss -tan 'sport = :22' state established
```

### Lab 3：按进程过滤

```bash
# 查看 nginx 的所有套接字
sudo ss -tulpn | grep nginx

# 查看特定 PID 的套接字
sudo ss -tulpn | grep 'pid=1234'
```

### Lab 4：Unix 域套接字

```bash
# 查看 Unix 域套接字（进程间通信）
ss -x

# 常见的 Unix 套接字
ss -x | grep -E 'docker|mysql|postgresql'
```

Unix 域套接字用于同一台机器上的进程通信，比 TCP 快。

---

## Step 5 - netstat vs ss：为什么 ss 更好（5 分钟）

### 5.1 性能对比

| 特性 | netstat | ss |
|------|---------|-----|
| 数据来源 | 读取 /proc/net/* 文件 | 直接使用 netlink API |
| 速度 | 慢（大量文件 I/O） | 快（内核直接返回） |
| 过滤能力 | 需要配合 grep | 内置强大过滤器 |
| 信息详细度 | 基础 | 更详细（内存、定时器等） |
| 维护状态 | 弃用（net-tools 包） | 活跃（iproute2 包） |

### 5.2 在高负载服务器上的差异

```bash
# 在有 10000+ 连接的服务器上
time netstat -tan | wc -l   # 可能需要几秒
time ss -tan | wc -l        # 几乎瞬间完成
```

### 5.3 命令对照表

| 任务 | netstat（弃用） | ss（推荐） |
|------|-----------------|------------|
| 监听端口 | `netstat -tuln` | `ss -tuln` |
| 所有连接 | `netstat -tan` | `ss -tan` |
| 带进程 | `netstat -tulpn` | `ss -tulpn` |
| 统计 | `netstat -s` | `ss -s` |
| Unix 套接字 | `netstat -x` | `ss -x` |

> **记住**：如果你还在用 netstat，是时候切换到 ss 了。在日本 IT 现场，面试官可能会问这个区别。  

---

## Step 6 - 故障实验室：Localhost 陷阱（10 分钟）

> **场景**：运维同事说"服务在运行但是远程连不上"，你需要排查。  

### 6.1 模拟问题

创建一个只监听 localhost 的服务：

```bash
# 使用 Python 创建简单 HTTP 服务
# 故意绑定到 127.0.0.1
python3 -m http.server 8080 --bind 127.0.0.1 &
```

### 6.2 验证问题

```bash
# 本机测试 - 成功
curl http://localhost:8080
# 输出：Directory listing...

# 检查监听地址
ss -tuln | grep 8080
# tcp  LISTEN  0  5  127.0.0.1:8080  0.0.0.0:*

# 从另一台机器测试（或用外部 IP）
curl http://<你的外部IP>:8080
# curl: (7) Failed to connect... Connection refused
```

### 6.3 定位根因

```bash
# 关键检查：监听地址是什么？
ss -tulpn | grep 8080
```

```
tcp  LISTEN  0  5  127.0.0.1:8080  0.0.0.0:*  users:(("python3",pid=12345))
```

**根因**：服务绑定了 `127.0.0.1`，只接受本地连接。

### 6.4 修复

```bash
# 停止旧服务
kill %1  # 或 kill 12345

# 正确方式：绑定到所有接口
python3 -m http.server 8080 --bind 0.0.0.0 &

# 验证
ss -tuln | grep 8080
# tcp  LISTEN  0  5  0.0.0.0:8080  0.0.0.0:*
```

### 6.5 诊断流程图

<!-- DIAGRAM: localhost-trap-diagnosis -->
```
"服务运行但远程连不上"排障流程
════════════════════════════════════════════════════════════════════

           ┌─────────────────────────┐
           │ 远程连接失败            │
           │ Connection refused      │
           └───────────┬─────────────┘
                       │
                       ▼
           ┌─────────────────────────┐
           │ 检查服务是否运行        │
           │ systemctl status xxx    │
           └───────────┬─────────────┘
                       │
              ┌────────┴────────┐
              │                 │
        没运行 ▼           运行中 ▼
    ┌─────────────┐     ┌─────────────────────────┐
    │ 启动服务    │     │ 检查监听地址            │
    │ systemctl   │     │ ss -tulpn | grep <port> │
    │ start xxx   │     └───────────┬─────────────┘
    └─────────────┘                 │
                          ┌─────────┴─────────┐
                          │                   │
                   127.0.0.1 ▼            0.0.0.0 ▼
              ┌─────────────────┐    ┌─────────────────┐
              │ 找到问题！      │    │ 检查防火墙      │
              │ 修改配置绑定到  │    │ firewall-cmd    │
              │ 0.0.0.0         │    │ --list-all      │
              └─────────────────┘    └─────────────────┘
```
<!-- /DIAGRAM -->

---

## Mini Project：服务端口检查脚本

### 项目说明

编写一个脚本，检查关键服务端口是否正常监听，报告异常情况。

### 代码实现

创建文件 `port-checker.sh`：

```bash
#!/bin/bash
# 服务端口检查脚本
# 用于运维巡检（運用監視）

# 定义要检查的服务和端口
declare -A SERVICES
SERVICES=(
    ["SSH"]="22"
    ["HTTP"]="80"
    ["HTTPS"]="443"
    ["MySQL"]="3306"
    ["Redis"]="6379"
)

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "======================================"
echo "服务端口检查报告"
echo "检查时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo "======================================"
echo ""

ISSUES_FOUND=0

for SERVICE in "${!SERVICES[@]}"; do
    PORT="${SERVICES[$SERVICE]}"

    # 检查端口是否监听
    LISTEN_INFO=$(ss -tuln 2>/dev/null | grep ":${PORT} " | head -1)

    if [ -z "$LISTEN_INFO" ]; then
        echo -e "${RED}[异常]${NC} $SERVICE (端口 $PORT): 未监听"
        ((ISSUES_FOUND++))
    else
        # 提取监听地址
        LISTEN_ADDR=$(echo "$LISTEN_INFO" | awk '{print $5}' | cut -d: -f1)

        if [ "$LISTEN_ADDR" = "127.0.0.1" ] || [ "$LISTEN_ADDR" = "::1" ]; then
            echo -e "${YELLOW}[警告]${NC} $SERVICE (端口 $PORT): 仅监听 localhost"
            ((ISSUES_FOUND++))
        else
            echo -e "${GREEN}[正常]${NC} $SERVICE (端口 $PORT): 监听 $LISTEN_ADDR"
        fi
    fi
done

echo ""
echo "======================================"
if [ $ISSUES_FOUND -eq 0 ]; then
    echo -e "${GREEN}检查完成: 全部正常${NC}"
else
    echo -e "${RED}检查完成: 发现 $ISSUES_FOUND 个问题${NC}"
fi
echo "======================================"

exit $ISSUES_FOUND
```

### 使用方法

```bash
# 添加执行权限
chmod +x port-checker.sh

# 运行检查
./port-checker.sh
```

### 示例输出

```
======================================
服务端口检查报告
检查时间: 2025-01-05 14:30:00
======================================

[正常] SSH (端口 22): 监听 0.0.0.0
[警告] HTTP (端口 80): 仅监听 localhost
[正常] HTTPS (端口 443): 监听 0.0.0.0
[异常] MySQL (端口 3306): 未监听
[异常] Redis (端口 6379): 未监听

======================================
检查完成: 发现 3 个问题
======================================
```

### 扩展：添加到 cron 定时检查

```bash
# 每 5 分钟检查一次
*/5 * * * * /path/to/port-checker.sh >> /var/log/port-check.log 2>&1
```

---

## 职场小贴士

### 日本 IT 常用术语

| 日本語 | 中文 | 场景 |
|--------|------|------|
| ポート監視 | 端口监控 | 运维巡检 |
| 待ち受け | 监听/等待连接 | ss -l 输出 |
| コネクション | 连接 | ESTABLISHED 状态 |
| タイムアウト | 超时 | 连接失败原因 |
| ソケット枯渇 | 套接字耗尽 | TIME_WAIT 过多 |

### 面试常见问题

**Q: ss と netstat の違いは？**

A: ss は netlink API を直接使用するため高速です。netstat は /proc 経由でファイル I/O が発生し遅い。また ss はフィルタリング機能が強力で、詳細情報（メモリ使用量、タイマーなど）も取得できます。現在 netstat は非推奨で、ss の使用が推奨されています。

**Q: サービスが LISTEN してるのに接続できない原因は？**

A: 最も多い原因は 127.0.0.1 のみで LISTEN している場合です。`ss -tuln` で Local Address を確認します。127.0.0.1 なら設定を変更して 0.0.0.0 にバインドする必要があります。それでも接続できない場合は、firewalld や Security Group（クラウド環境）を確認します。

**Q: CLOSE_WAIT が大量にある場合の対処は？**

A: CLOSE_WAIT は相手から FIN を受け取ったが、アプリケーションが close() していない状態です。大量にある場合はアプリケーションのバグで、コネクションを正しくクローズしていない可能性が高い。アプリケーションログを確認し、開発チームにエスカレーションします。

---

## 本课小结

| 你学到的 | 命令/概念 |
|----------|-----------|
| 查看监听端口 | `ss -tuln` |
| 查看端口和进程 | `ss -tulpn`（需 sudo） |
| 查看所有连接 | `ss -tan` |
| 按状态过滤 | `ss state established` |
| 按端口过滤 | `ss 'sport = :22'` |
| 监听地址区别 | 0.0.0.0（外部可访问）vs 127.0.0.1（仅本地） |
| 套接字状态 | LISTEN、ESTABLISHED、TIME_WAIT、CLOSE_WAIT |

**核心理念**：

```
"服务在运行" ≠ "服务可访问"

排障步骤：
1. ss -tulpn | grep <port>  ← 检查是否监听
2. 看 Local Address          ← 127.0.0.1 还是 0.0.0.0？
3. 确认后再查防火墙          ← 不要一上来就怀疑防火墙
```

---

## 反模式警示

| 错误做法 | 正确做法 |
|----------|----------|
| 使用 netstat 而不是 ss | 使用 ss（更快、信息更全） |
| 以为"服务在运行"就等于"服务可访问" | 用 ss 检查监听地址 |
| 不看监听地址就认为是防火墙问题 | 先确认 0.0.0.0 vs 127.0.0.1 |
| 只在服务端排查 | 客户端 + 服务端双向验证 |

---

## 检查清单

在继续下一课之前，确认你能：

- [ ] 使用 `ss -tuln` 查看监听端口
- [ ] 使用 `ss -tulpn` 查看端口对应的进程
- [ ] 解释 `0.0.0.0:22` 和 `127.0.0.1:80` 的区别
- [ ] 使用 `ss state` 过滤器按状态筛选
- [ ] 解释 LISTEN、ESTABLISHED、TIME_WAIT、CLOSE_WAIT 的含义
- [ ] 说明为什么 ss 比 netstat 更好
- [ ] 排查"服务运行但无法连接"问题

---

## 延伸阅读

- [ss 命令 - man page](https://man7.org/linux/man-pages/man8/ss.8.html)
- [TCP 连接状态 - 维基百科](https://en.wikipedia.org/wiki/Transmission_Control_Protocol#Protocol_operation)
- [iproute2 - Linux 网络工具集](https://wiki.linuxfoundation.org/networking/iproute2)

---

## 下一步

你已经学会了使用 ss 检查套接字和排查连接问题。接下来，让我们学习现代 Linux 防火墙——nftables 的基础配置。

[06 - nftables 基础 ->](../06-nftables/)

---

## 系列导航

[<- 04 - DNS 配置](../04-dns/) | [Home](/) | [06 - nftables 基础 ->](../06-nftables/)
