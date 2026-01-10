# 08 - strace：系统调用追踪（strace for Application Debugging）

> **目标**：掌握 strace 追踪系统调用，定位应用层"黑盒"问题  
> **前置**：LX05 systemd 基础、LX09 性能分析基础  
> **时间**：⚡ 30 分钟（速读）/ 🔬 120 分钟（完整实操）  
> **核心理念**：当应用日志沉默时，系统调用会说话  

---

## 将学到的内容

1. 使用 strace 追踪系统调用
2. 识别常见系统调用错误码
3. 使用时间分析定位阻塞点
4. 理解生产环境使用限制
5. 了解 eBPF 替代方案

---

## 先跑起来！（5 分钟）

> 不需要理解原理，先看 strace 能告诉我们什么。  

```bash
# 统计 ls 命令的系统调用
strace -c ls /tmp

# 输出类似：
# % time     seconds  usecs/call     calls    errors syscall
# ------ ----------- ----------- --------- --------- ----------------
#  25.00    0.000012           6         2           getdents64
#  18.75    0.000009           9         1           write
#  14.58    0.000007           7         1           openat
#   ...
# ------ ----------- ----------- --------- --------- ----------------
# 100.00    0.000048                    23           total
```

**你刚刚看到了一个简单命令背后的系统调用统计！**

`ls` 命令实际上调用了 `openat`（打开目录）、`getdents64`（读取目录条目）、`write`（输出结果）等系统调用。

现在让我们学习如何用 strace 诊断真实的"黑盒"问题。

---

## Step 1 -- 什么是系统调用？（10 分钟）

### 1.1 应用程序与内核的桥梁

每个应用程序想要做任何"真正的事情"——读文件、发网络包、分配内存——都必须请求内核帮忙。这个请求就是**系统调用（System Call / syscall）**。

<!-- DIAGRAM: syscall-bridge -->
```
┌──────────────────────────────────────────────────────────────────┐
│                    系统调用：应用与内核的桥梁                      │
├──────────────────────────────────────────────────────────────────┤
│                                                                  │
│   用户空间 (User Space)                                          │
│   ┌────────────────────────────────────────────────────────┐    │
│   │                                                        │    │
│   │    应用程序                                             │    │
│   │    ┌─────────┐  ┌─────────┐  ┌─────────┐              │    │
│   │    │ Python  │  │  Java   │  │  nginx  │  ...         │    │
│   │    └────┬────┘  └────┬────┘  └────┬────┘              │    │
│   │         │            │            │                    │    │
│   │         └────────────┼────────────┘                    │    │
│   │                      │                                 │    │
│   │                      ▼                                 │    │
│   │              ┌───────────────┐                         │    │
│   │              │  系统调用接口  │                         │    │
│   │              │  open, read,  │                         │    │
│   │              │  write, socket│                         │    │
│   │              └───────┬───────┘                         │    │
│   └──────────────────────┼─────────────────────────────────┘    │
│                          │                                       │
│   ════════════════════════════════════════════════════════════   │
│                          │ 系统调用边界                          │
│   ════════════════════════════════════════════════════════════   │
│                          │                                       │
│   内核空间 (Kernel Space)│                                       │
│   ┌──────────────────────┼─────────────────────────────────┐    │
│   │                      ▼                                 │    │
│   │   ┌──────────┐  ┌──────────┐  ┌──────────┐            │    │
│   │   │ 文件系统 │  │ 网络栈   │  │ 内存管理 │            │    │
│   │   └──────────┘  └──────────┘  └──────────┘            │    │
│   │                                                        │    │
│   └────────────────────────────────────────────────────────┘    │
│                                                                  │
│   strace 的作用：拦截并记录每一次系统调用                         │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘
```
<!-- /DIAGRAM -->

### 1.2 为什么 strace 这么有用？

当应用出现问题时，通常有三种信息来源：

| 信息来源 | 特点 | 局限 |
|----------|------|------|
| **应用日志** | 开发者选择记录的信息 | 可能不够详细，或根本没记录 |
| **系统日志** | 内核和系统服务的信息 | 不包含应用内部细节 |
| **系统调用** | 应用与内核的所有交互 | 信息量大，需要过滤 |

**strace 的价值**：当应用日志沉默时，系统调用会告诉你应用正在尝试做什么。

典型场景：
- 应用卡住，没有任何日志输出 → strace 显示阻塞在 `connect()` 或 `read()`
- 应用报错"文件不存在"，但没说哪个文件 → strace 显示 `open("/path/to/file") = -1 ENOENT`
- 应用启动慢 → strace 显示在 DNS 解析时等待 5 秒

---

## Step 2 -- strace 基础用法（20 分钟）

### 2.1 追踪新进程

```bash
# 基本用法：追踪命令执行
strace ls /tmp

# 输出示例：
# execve("/bin/ls", ["ls", "/tmp"], ...) = 0
# openat(AT_FDCWD, "/tmp", O_RDONLY|...) = 3
# getdents64(3, ...) = 96
# write(1, "file1\nfile2\n", 12) = 12
# close(3) = 0
# exit_group(0) = ?
```

### 2.2 附加到运行中的进程

```bash
# 找到进程 PID
pidof nginx
# 或
pgrep -f "python myapp.py"

# 附加到进程
sudo strace -p <PID>

# 按 Ctrl+C 停止追踪
```

### 2.3 常用选项速查

| 选项 | 作用 | 使用场景 |
|------|------|----------|
| `-p <PID>` | 附加到运行中的进程 | 调试卡住的服务 |
| `-f` | 追踪子进程 | 多进程应用（nginx、Apache） |
| `-e trace=<syscalls>` | 只追踪指定系统调用 | 减少噪音，聚焦问题 |
| `-o <file>` | 输出到文件 | 长时间追踪 |
| `-tt` | 显示微秒级时间戳 | 时间线分析 |
| `-T` | 显示每个系统调用耗时 | 定位慢调用 |
| `-c` | 统计汇总 | 性能分析 |
| `-s <size>` | 字符串截断长度（默认 32） | 看完整路径/数据 |

### 2.4 实用命令组合

```bash
# 追踪新进程，显示时间戳和耗时，输出到文件
strace -f -tt -T -o /tmp/trace.log <command>

# 附加到进程，追踪子进程，输出到文件
sudo strace -p <PID> -f -tt -T -o /tmp/trace.log

# 只追踪文件操作
strace -e trace=file <command>

# 只追踪网络操作
strace -e trace=network <command>

# 只追踪特定系统调用
strace -e trace=open,read,write,connect <command>

# 统计汇总（性能分析）
strace -c <command>

# 显示完整字符串（路径等）
strace -s 200 <command>
```

### 2.5 trace= 过滤类别

strace 支持按类别过滤系统调用：

| 类别 | 包含的系统调用 | 使用场景 |
|------|----------------|----------|
| `file` | open, stat, chmod, unlink... | 文件权限、路径问题 |
| `network` | socket, connect, send, recv... | 网络连接问题 |
| `process` | fork, exec, wait, kill... | 进程管理问题 |
| `signal` | signal, sigaction, kill... | 信号处理问题 |
| `ipc` | shmget, semop, msgget... | 进程间通信问题 |
| `desc` | read, write, close, dup... | 文件描述符操作 |
| `memory` | mmap, brk, mprotect... | 内存分配问题 |

---

## Step 3 -- 时间分析：定位阻塞点（20 分钟）

### 3.1 -tt 和 -T 的威力

```bash
# -tt: 时间戳（微秒精度）
# -T: 系统调用耗时

strace -tt -T curl http://example.com 2>&1 | head -20

# 输出示例：
# 14:30:01.123456 socket(AF_INET, SOCK_STREAM, ...) = 3 <0.000015>
# 14:30:01.123500 connect(3, {sa_family=AF_INET, sin_port=htons(80), ...}) = 0 <0.025123>
#                                                                             ↑
#                                                        这个 connect 花了 25ms
```

### 3.2 识别阻塞的系统调用

常见的阻塞系统调用：

| 系统调用 | 阻塞原因 | 排查方向 |
|----------|----------|----------|
| `connect()` | TCP 连接建立 | 网络延迟、防火墙、目标不可达 |
| `read()` | 等待数据 | 对端未发送、网络延迟 |
| `poll()`/`select()` | 等待事件 | I/O 多路复用超时 |
| `futex()` | 线程同步 | 死锁、竞争 |
| `nanosleep()` | 显式睡眠 | 代码中的 sleep |
| `recvfrom()` | 等待网络数据 | DNS 响应超时 |

### 3.3 统计分析：-c 选项

```bash
# 统计系统调用分布
strace -c ls -la /usr/bin

# 输出：
# % time     seconds  usecs/call     calls    errors syscall
# ------ ----------- ----------- --------- --------- ----------------
#  45.00    0.001234          12       100           getdents64
#  25.00    0.000687          34        20           write
#  15.00    0.000412           8        50           lstat
#   ...
```

**解读**：
- `% time`: 该系统调用占总时间的百分比
- `usecs/call`: 每次调用的平均耗时（微秒）
- `calls`: 调用次数
- `errors`: 返回错误的次数

---

## Step 4 -- 常见错误码解读（15 分钟）

### 4.1 文件相关错误

```bash
# ENOENT: 文件或目录不存在
open("/nonexistent/file", O_RDONLY) = -1 ENOENT (No such file or directory)
# 排查：检查路径是否正确，文件是否存在

# EACCES: 权限不足
open("/etc/shadow", O_RDONLY) = -1 EACCES (Permission denied)
# 排查：检查文件权限、用户身份、SELinux

# EEXIST: 文件已存在
mkdir("/tmp/existing_dir", 0755) = -1 EEXIST (File exists)
# 排查：通常是正常的（检查存在性）

# ENOTEMPTY: 目录非空
rmdir("/tmp/nonempty_dir") = -1 ENOTEMPTY (Directory not empty)
# 排查：需要先清空目录
```

### 4.2 网络相关错误

```bash
# ECONNREFUSED: 连接被拒绝
connect(3, {sa_family=AF_INET, sin_port=htons(3306), ...}) = -1 ECONNREFUSED
# 排查：目标端口未监听，服务未启动

# ETIMEDOUT: 连接超时
connect(3, {sa_family=AF_INET, sin_port=htons(80), ...}) = -1 ETIMEDOUT
# 排查：网络不可达，防火墙阻止，目标服务器无响应

# ENETUNREACH: 网络不可达
connect(3, {sa_family=AF_INET, sin_addr=...}) = -1 ENETUNREACH
# 排查：路由问题，网关配置

# ECONNRESET: 连接被重置
read(3, ...) = -1 ECONNRESET (Connection reset by peer)
# 排查：对端强制关闭连接
```

### 4.3 资源相关错误

```bash
# ENOMEM: 内存不足
mmap(NULL, 1073741824, ...) = -1 ENOMEM (Cannot allocate memory)
# 排查：检查内存使用，可能是内存泄漏

# EMFILE: 进程打开文件数达到上限
open("/tmp/file", O_RDONLY) = -1 EMFILE (Too many open files)
# 排查：ulimit -n, lsof -p <pid> | wc -l

# ENFILE: 系统打开文件数达到上限
open("/tmp/file", O_RDONLY) = -1 ENFILE (Too many open files in system)
# 排查：cat /proc/sys/fs/file-nr
```

### 4.4 错误码速查表

<!-- DIAGRAM: errno-quick-reference -->
```
┌──────────────────────────────────────────────────────────────────┐
│                    常见错误码速查表                               │
├───────────────┬──────────────────┬───────────────────────────────┤
│ 错误码        │ 含义             │ 常见原因                       │
├───────────────┼──────────────────┼───────────────────────────────┤
│ ENOENT        │ 文件不存在       │ 路径错误、文件被删除           │
│ EACCES        │ 权限拒绝         │ 文件权限、SELinux             │
│ EPERM         │ 操作不允许       │ 需要 root 权限                │
├───────────────┼──────────────────┼───────────────────────────────┤
│ ECONNREFUSED  │ 连接被拒绝       │ 服务未启动、端口未监听         │
│ ETIMEDOUT     │ 连接超时         │ 网络问题、防火墙               │
│ ECONNRESET    │ 连接重置         │ 对端关闭连接                   │
│ ENETUNREACH   │ 网络不可达       │ 路由问题                       │
├───────────────┼──────────────────┼───────────────────────────────┤
│ EMFILE        │ 进程文件数上限   │ 文件句柄泄漏                   │
│ ENFILE        │ 系统文件数上限   │ 系统级问题                     │
│ ENOMEM        │ 内存不足         │ OOM、内存泄漏                  │
├───────────────┼──────────────────┼───────────────────────────────┤
│ EAGAIN/       │ 资源暂时不可用   │ 非阻塞 I/O、需要重试           │
│ EWOULDBLOCK   │                  │                               │
│ EINTR         │ 系统调用被中断   │ 信号处理                       │
└───────────────┴──────────────────┴───────────────────────────────┘
```
<!-- /DIAGRAM -->

---

## Step 5 -- 生产环境考量（15 分钟）

### 5.1 strace 的性能开销

**重要警告**：strace 使用 `ptrace` 系统调用，会导致被追踪进程 **10-100 倍** 的性能下降！

```
正常执行：         ████████████████████  100 req/s
strace 追踪：      ██                      1-10 req/s
```

**为什么这么慢？**
- 每个系统调用都会被拦截
- 进程在用户态和内核态之间反复切换
- strace 需要读取和格式化每个调用的参数

### 5.2 何时可以使用 strace

| 场景 | 是否推荐 | 原因 |
|------|----------|------|
| 开发/测试环境 | **推荐** | 没有性能顾虑 |
| 生产环境调试 | **谨慎** | 可能影响服务 |
| 生产环境非关键进程 | 可以 | 影响有限 |
| 生产环境核心服务 | **不推荐** | 可能导致故障 |
| 问题复现时临时使用 | 可以 | 抓证据后立即停止 |

### 5.3 减少 strace 开销的技巧

```bash
# 1. 使用 -e trace= 只追踪需要的系统调用
strace -e trace=network -p <PID>        # 只追踪网络
strace -e trace=open,read -p <PID>      # 只追踪特定调用

# 2. 限制追踪时间
timeout 10 strace -p <PID> -o /tmp/trace.log

# 3. 追踪后立即脱离
# 按 Ctrl+C 或从另一个终端 kill strace

# 4. 对复制的进程追踪（如果可以）
# 启动一个新的调试实例，而不是追踪生产实例
```

### 5.4 eBPF：生产环境的替代方案

**eBPF（extended Berkeley Packet Filter）** 是现代 Linux 的"可编程内核"技术，开销极低。

<!-- DIAGRAM: strace-vs-ebpf -->
```
┌──────────────────────────────────────────────────────────────────┐
│                    strace vs eBPF 对比                           │
├──────────────────────────────────────────────────────────────────┤
│                                                                  │
│   strace (ptrace)                    eBPF                        │
│   ┌─────────────────┐               ┌─────────────────┐         │
│   │ 性能开销        │               │ 性能开销        │         │
│   │ 10-100x 下降    │               │ <5% 下降       │         │
│   │ ██████████      │               │ █               │         │
│   └─────────────────┘               └─────────────────┘         │
│                                                                  │
│   适用场景：                        适用场景：                   │
│   • 开发环境                        • 生产环境                   │
│   • 测试环境                        • 性能分析                   │
│   • 问题复现                        • 持续监控                   │
│                                                                  │
│   工具：                            工具：                       │
│   • strace                          • bpftrace                   │
│                                     • bcc (BPF Compiler Collection)│
│                                     • opensnoop, tcpconnect      │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘
```
<!-- /DIAGRAM -->

### 5.5 常用 eBPF 工具

```bash
# opensnoop: 追踪文件打开（类似 strace -e trace=open）
sudo opensnoop

# tcpconnect: 追踪 TCP 连接
sudo tcpconnect

# execsnoop: 追踪进程执行
sudo execsnoop

# bpftrace 一行脚本
sudo bpftrace -e 'tracepoint:syscalls:sys_enter_openat { printf("%s %s\n", comm, str(args->filename)); }'
```

**注意**：eBPF 需要 Linux 4.x+ 内核，在 LX09-PERFORMANCE 课程中有更详细介绍。

---

## Step 6 -- 实战案例：神秘的延迟（25 分钟）

### 6.1 场景描述

> **症状**：一个简单的 CLI 工具（比如一个内部脚本）启动时卡住约 5 秒，然后运行很快。应用日志没有任何错误。  

这是生产环境中非常常见的问题。让我们用 strace 来诊断。

### 6.2 复现问题

首先，我们创建一个模拟这个问题的脚本：

```bash
# 创建测试脚本（模拟需要 DNS 解析的应用）
cat > /tmp/slow-app.py << 'EOF'
#!/usr/bin/env python3
import socket
import sys

# 模拟应用启动时的 DNS 查询
# 如果 /etc/resolv.conf 中第一个 nameserver 不可达，会超时
try:
    socket.getaddrinfo("internal.example.com", 80)
except:
    pass

print("Application started!")
# 后续操作很快...
for i in range(5):
    print(f"Processing item {i}")
EOF

chmod +x /tmp/slow-app.py
```

### 6.3 使用 strace 诊断

```bash
# 使用 strace 追踪，关注时间
strace -tt -T -e trace=network,open /tmp/slow-app.py 2>&1 | head -50

# 或者输出到文件便于分析
strace -tt -T -f -o /tmp/trace.log /tmp/slow-app.py
```

### 6.4 分析 strace 输出

在真实的 DNS 超时场景中，你会看到类似这样的输出：

```
14:30:01.123456 socket(AF_INET, SOCK_DGRAM, ...) = 3 <0.000023>
14:30:01.123500 connect(3, {sa_family=AF_INET, sin_port=htons(53),
                           sin_addr=inet_addr("10.0.0.1")}, 16) = 0 <0.000015>
14:30:01.123550 sendto(3, "...", 32, ...) = 32 <0.000012>
14:30:01.123600 poll([{fd=3, events=POLLIN}], 1, 5000) = 0 (Timeout) <5.000234>
                                                          ↑
                                              这里！poll 超时等待了 5 秒
14:30:06.123900 close(3) = 0 <0.000008>
# 尝试第二个 nameserver
14:30:06.123950 socket(AF_INET, SOCK_DGRAM, ...) = 3 <0.000020>
14:30:06.124000 connect(3, {sa_family=AF_INET, sin_port=htons(53),
                           sin_addr=inet_addr("8.8.8.8")}, 16) = 0 <0.000010>
14:30:06.124050 sendto(3, "...", 32, ...) = 32 <0.000008>
14:30:06.124100 poll([{fd=3, events=POLLIN}], 1, 5000) = 1 <0.023456>
                                                           ↑
                                              第二个 nameserver 23ms 响应
```

### 6.5 关键发现

1. **端口 53** = DNS 查询
2. **第一个 IP（10.0.0.1）** 的 `poll()` 返回 `Timeout`，耗时 5 秒
3. **第二个 IP（8.8.8.8）** 的 `poll()` 立即返回

### 6.6 确认根因

```bash
# 检查 DNS 配置
cat /etc/resolv.conf
# nameserver 10.0.0.1    # 第一个 nameserver 不可达！
# nameserver 8.8.8.8

# 测试第一个 nameserver
dig @10.0.0.1 example.com +time=2
# ;; connection timed out; no servers could be reached

# 测试第二个 nameserver
dig @8.8.8.8 example.com +time=2
# ;; ANSWER SECTION:
# example.com.  ...
```

### 6.7 修复方案

```bash
# 方案 1: 修复第一个 nameserver（如果是内部 DNS）
# 联系网络团队修复 10.0.0.1

# 方案 2: 调整 resolv.conf 顺序
sudo vim /etc/resolv.conf
# nameserver 8.8.8.8    # 可用的放前面
# nameserver 10.0.0.1

# 方案 3: 设置更短的超时（临时缓解）
# 在 /etc/resolv.conf 添加:
# options timeout:1 attempts:1
```

### 6.8 经验总结

| 症状 | strace 关键输出 | 根因 |
|------|-----------------|------|
| 启动慢 5 秒 | `poll(..., 5000) = 0 (Timeout)` + 端口 53 | DNS 超时 |
| 连接慢 | `connect(...) <长时间>` | 网络延迟或不可达 |
| 文件操作失败 | `open(...) = -1 ENOENT` | 文件路径错误 |
| 权限错误 | `open(...) = -1 EACCES` | 文件权限或 SELinux |

---

## Step 7 -- strace 速查表（5 分钟）

### 7.1 最常用命令

```bash
# ============================================
# strace 速查表 - 保存到 /usr/local/bin/strace-cheatsheet.sh
# ============================================

# 追踪新进程（完整信息）
strace -f -tt -T -s 200 -o /tmp/trace.log <command>

# 附加到运行中进程
sudo strace -p <PID> -f -tt -T -o /tmp/trace.log

# 统计汇总（性能分析）
strace -c <command>

# 只追踪文件操作
strace -e trace=file <command>

# 只追踪网络操作
strace -e trace=network <command>

# 只追踪特定系统调用
strace -e trace=open,read,write,connect,socket <command>

# 追踪失败的系统调用
strace -Z <command>

# 追踪特定信号
strace -e signal=SIGKILL,SIGTERM <command>
```

### 7.2 输出过滤技巧

```bash
# 找到所有失败的系统调用
strace <command> 2>&1 | grep ' = -1'

# 找到所有文件打开
strace <command> 2>&1 | grep 'open'

# 找到耗时超过 100ms 的调用（需要 -T）
strace -T <command> 2>&1 | awk -F'<|>' '$2 > 0.1 {print}'

# 找到特定错误码
strace <command> 2>&1 | grep 'ENOENT\|EACCES'
```

---

## Step 8 -- 日本 IT 职场：开发环境活用（10 分钟）

### 8.1 strace 在日本企业的使用

在日本 IT 企业，strace 通常有明确的使用规范：

```
本番環境（生产环境）         開発環境（开发环境）
    │                           │
    ├── strace は基本禁止        ├── strace 自由に使用可
    │   (基本禁止使用 strace)    │   (可以自由使用)
    │                           │
    ├── 例外：障害調査時のみ      ├── パフォーマンス分析
    │   (例外：故障调查时)       │   (性能分析)
    │   承認プロセス必要         │
    │   (需要审批流程)           ├── デバッグ
    │                           │   (调试)
    └── eBPF 推奨               │
        (推荐使用 eBPF)          └── 問題再現
                                    (问题复现)
```

### 8.2 相关日语术语

| 日语 | 读音 | 含义 | 使用场景 |
|------|------|------|----------|
| **本番環境** | honban kankyou | 生产环境 | "本番環境での strace は禁止" |
| **開発環境** | kaihatsu kankyou | 开发环境 | strace 主要使用场所 |
| **システムコール** | shisutemu kooru | 系统调用 | strace 追踪的对象 |
| **デバッグ** | debaggu | 调试 | strace 的主要用途 |
| **性能劣化** | seinou rekka | 性能下降 | strace 的副作用 |
| **影響調査** | eikyou chousa | 影响调查 | 使用前的评估 |

### 8.3 生产环境使用的审批流程

在日本企业，生产环境使用 strace 通常需要：

1. **事前申请**（事前申請）
2. **影响评估**（影響調査）
3. **主管审批**（上長承認）
4. **执行时间限制**（実行時間制限）
5. **事后报告**（事後報告）

```
申請書例：
────────────────────────────────
件名：本番環境 strace 使用申請

対象サーバー：api-server-01
対象プロセス：nginx (PID: 1234)
使用理由：502 エラーの原因調査
予定時間：5 分以内
影響：一時的な性能低下（約 50%）

承認者：____________
日付：______________
────────────────────────────────
```

---

## 动手实验（20 分钟）

### 实验 1：神秘延迟场景

**目标**：使用 strace 定位应用启动慢的原因

```bash
# 步骤 1：创建模拟脚本
cat > /tmp/mystery-latency.sh << 'EOF'
#!/bin/bash
# 模拟启动时的网络操作
# 这个脚本会尝试连接一个不存在的主机

# 模拟 DNS 查询（会超时）
timeout 5 bash -c 'echo > /dev/tcp/192.0.2.1/80' 2>/dev/null || true

echo "Application started successfully!"
echo "Processing..."
sleep 1
echo "Done!"
EOF

chmod +x /tmp/mystery-latency.sh

# 步骤 2：直接运行，观察延迟
time /tmp/mystery-latency.sh

# 步骤 3：用 strace 追踪
strace -tt -T -e trace=network,connect /tmp/mystery-latency.sh 2>&1

# 步骤 4：分析输出，找到阻塞点
# 提示：寻找耗时最长的系统调用
```

**预期发现**：
- `connect()` 调用到 192.0.2.1 会超时
- 192.0.2.1 是 TEST-NET（不可路由的测试地址）

### 实验 2：权限问题追踪

**目标**：使用 strace 找到"隐藏"的权限错误

```bash
# 步骤 1：创建测试场景
sudo mkdir -p /tmp/protected
sudo touch /tmp/protected/secret.txt
sudo chmod 600 /tmp/protected/secret.txt
sudo chown root:root /tmp/protected/secret.txt

# 步骤 2：尝试读取（会失败）
cat /tmp/protected/secret.txt
# cat: /tmp/protected/secret.txt: Permission denied

# 步骤 3：用 strace 追踪
strace -e trace=open,openat cat /tmp/protected/secret.txt 2>&1

# 步骤 4：分析输出
# 你应该看到：
# openat(AT_FDCWD, "/tmp/protected/secret.txt", O_RDONLY) = -1 EACCES

# 步骤 5：清理
sudo rm -rf /tmp/protected
```

### 实验 3：统计分析练习

**目标**：使用 strace -c 进行性能分析

```bash
# 比较两个命令的系统调用分布

# 命令 1：ls
strace -c ls /usr 2>&1

# 命令 2：find（更多系统调用）
strace -c find /usr -maxdepth 1 -type f 2>&1

# 对比分析：
# - 哪个命令的系统调用更多？
# - 哪类系统调用占比最高？
# - 有什么性能优化建议？
```

---

## 检查清单

完成本课后，你应该能够：

- [ ] 解释什么是系统调用以及 strace 的作用
- [ ] 使用 strace 追踪新进程和运行中的进程
- [ ] 使用 `-e trace=` 过滤特定类型的系统调用
- [ ] 使用 `-tt` 和 `-T` 进行时间分析
- [ ] 使用 `-c` 进行统计汇总
- [ ] 解读常见错误码（ENOENT, EACCES, ETIMEDOUT, ECONNREFUSED）
- [ ] 解释 strace 在生产环境的性能影响
- [ ] 说明何时应该使用 eBPF 替代 strace
- [ ] 完成"神秘延迟"实验，定位 DNS/网络超时
- [ ] 理解日本企业对 strace 使用的规范

---

## 本课小结

| 概念 | 要点 |
|------|------|
| 系统调用 | 应用程序与内核交互的唯一方式 |
| strace 基础 | `-p` 附加进程，`-f` 追踪子进程，`-o` 输出文件 |
| 时间分析 | `-tt` 时间戳，`-T` 调用耗时，`-c` 统计汇总 |
| 过滤技巧 | `-e trace=file/network/process` 减少噪音 |
| 常见错误 | ENOENT 文件不存在，EACCES 权限拒绝，ETIMEDOUT 超时 |
| 生产考量 | strace 导致 10-100x 性能下降，生产环境谨慎使用 |
| eBPF 替代 | opensnoop, tcpconnect, bpftrace - 开销低 |

**核心理念**：

> 当应用日志沉默时，系统调用会说话。  
> 但在生产环境，请用更轻量的 eBPF 工具。  

---

## 面试准备

### よくある質問（常见问题）

**Q: strace とは何ですか？どのような場面で使いますか？**

A: strace はシステムコールをトレースするツールです。アプリケーションが何をしようとしているか（ファイルアクセス、ネットワーク接続など）を確認できます。

使用場面：
- アプリケーションログに情報がない場合のデバッグ
- 起動が遅い原因の特定（DNS タイムアウトなど）
- ファイルアクセスエラーの詳細確認
- パフォーマンス分析（-c オプション）

**Q: 本番環境で strace を使う際の注意点は？**

A: strace は ptrace を使うため、対象プロセスに **10〜100 倍** の性能劣化を引き起こします。

本番環境での対策：
- `-e trace=` で必要なシステムコールのみトレース
- 短時間で終了する
- 可能なら eBPF ツール（opensnoop、tcpconnect）を使用
- 事前に影響調査と承認プロセスを経る

**Q: ECONNREFUSED と ETIMEDOUT の違いは？**

A:
- **ECONNREFUSED**: 対象ホストに到達し、RST パケットを受信。サービスが起動していない。
- **ETIMEDOUT**: 対象ホストに到達できない、またはレスポンスがない。ネットワークの問題やファイアウォールの可能性。

**Q: アプリケーションの起動が遅い場合、strace でどう調査しますか？**

A: 以下のコマンドで時間情報付きでトレースします：

```bash
strace -tt -T -o /tmp/trace.log <command>
```

出力から以下を確認：
1. 長時間かかっている syscall を探す（`<5.000...>` など）
2. その syscall の種類を確認（connect、poll、read など）
3. 引数から対象を特定（IP アドレス、ファイルパスなど）

よくある原因：DNS タイムアウト、ネットワーク接続タイムアウト、ファイル I/O 待ち

---

## トラブルシューティング（本課自体の問題解決）

### strace: permission denied

```bash
# 他人のプロセスをトレースするには root 権限が必要
sudo strace -p <PID>

# または ptrace スコープの緩和（セキュリティリスクあり）
sudo sysctl kernel.yama.ptrace_scope=0
```

### 出力が多すぎて見づらい

```bash
# 特定のシステムコールのみトレース
strace -e trace=open,connect <command>

# ファイルに出力して grep
strace -o /tmp/trace.log <command>
grep 'ENOENT\|EACCES\|ETIMEDOUT' /tmp/trace.log
```

### strace が遅すぎる

```bash
# -c で統計のみ取得（出力が少ない分やや速い）
strace -c <command>

# または eBPF ツールを使用
sudo opensnoop
sudo tcpconnect
```

### bcc/bpftrace がインストールされていない

```bash
# RHEL/CentOS 8+
sudo dnf install bcc-tools bpftrace

# Ubuntu 20.04+
sudo apt install bpfcc-tools bpftrace

# ツールの場所
ls /usr/share/bcc/tools/
# opensnoop, tcpconnect, execsnoop などがある
```

---

## 延伸阅读

- [strace man page](https://man7.org/linux/man-pages/man1/strace.1.html)
- [Brendan Gregg - strace Wow Much Syscall](https://www.brendangregg.com/blog/2014-05-11/strace-wow-much-syscall.html)
- [BPF Performance Tools (Book)](https://www.brendangregg.com/bpf-performance-tools-book.html)
- 相关课程：[LX09-PERFORMANCE](../../lx09-performance/) - eBPF 详细介绍
- 下一课：[09 - Core Dump 与崩溃分析](../09-core-dumps/)

---

## 系列导航

[<-- 07 - 日志分析](../07-log-analysis/) | [系列首页](../) | [09 - Core Dump 与崩溃分析 -->](../09-core-dumps/)
