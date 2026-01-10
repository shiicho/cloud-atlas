# 06 - strace 系统调用追踪

> **目标**：掌握 strace 系统调用追踪技能，识别常见性能问题模式（syscall storms），学会从系统调用层面定位应用性能瓶颈  
> **前置**：Lesson 01 USE Method、Lesson 05 Network Performance  
> **时间**：⚡ 20 分钟（速读）/ 🔬 75 分钟（完整实操）  
> **实战场景**：アプリが遅い原因調査、syscall storm 定位、应用级性能分析  

---

## 将学到的内容

1. 使用 strace 追踪进程系统调用（新进程、运行中进程、子进程）
2. 解读 strace 输出（系统调用名、参数、返回值、错误码）
3. 使用性能分析模式（-c 统计、-T 计时、-t/-tt 时间戳）
4. 筛选特定系统调用（-e trace=open,read,write; -e trace=network）
5. 识别常见性能问题模式（stat() storm、open/close loop、DNS blocking）
6. 了解 ltrace 库调用追踪

---

## 先跑起来！（5 分钟）

> 在深入 strace 理论之前，先体验系统调用追踪的魔力。  
> 运行这些命令，观察输出 - 这就是你将要系统化掌握的技能。  

```bash
# 追踪 ls 命令的系统调用（看看 ls 背后做了什么）
strace ls /tmp 2>&1 | head -30

# 统计 ls 命令的系统调用分布
strace -c ls /tmp

# 追踪特定进程的文件操作（用你系统上的任意进程）
# 先找一个进程
ps aux | grep -E "bash|sshd" | head -1
# 假设 PID 是 1234
# strace -e trace=file -p 1234 -t

# 查看正在运行进程的实时系统调用
# strace -p $(pgrep -n bash) -f -tt -T 2>&1 | head -20
```

**你刚刚看到了系统调用的世界！**

- 一个简单的 `ls` 命令背后有几十个系统调用
- `strace -c` 给你统计视图：哪些调用最多、最耗时
- 每个系统调用都有名称、参数、返回值

**但这些输出意味着什么？为什么 `stat()` 调用这么多？`ENOENT` 是什么？**

让我们从系统调用基础开始理解。

---

## Step 1 - 什么是系统调用？（10 分钟）

### 1.1 用户态 vs 内核态

<!-- DIAGRAM: userspace-kernel -->
```
┌─────────────────────────────────────────────────────────────────────┐
│                      用户态 vs 内核态                                │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│   ┌─────────────────────────────────────────────────────────────┐  │
│   │                     用户态 (User Space)                      │  │
│   │                                                             │  │
│   │   ┌──────────┐   ┌──────────┐   ┌──────────┐              │  │
│   │   │  Python  │   │   Java   │   │    C     │   应用程序    │  │
│   │   │  程序    │   │  程序    │   │  程序    │              │  │
│   │   └────┬─────┘   └────┬─────┘   └────┬─────┘              │  │
│   │        │              │              │                     │  │
│   │        └──────────────┼──────────────┘                     │  │
│   │                       │                                     │  │
│   │                       ▼                                     │  │
│   │              ┌────────────────┐                            │  │
│   │              │  系统调用接口  │  syscall interface         │  │
│   │              │  (glibc etc.)  │                            │  │
│   │              └────────┬───────┘                            │  │
│   └───────────────────────┼─────────────────────────────────────┘  │
│                           │                                        │
│   ════════════════════════╪════════════════════════════════════   │
│                     SYSCALL BOUNDARY                               │
│   ════════════════════════╪════════════════════════════════════   │
│                           │                                        │
│   ┌───────────────────────┼─────────────────────────────────────┐  │
│   │                       ▼                      内核态          │  │
│   │              ┌────────────────┐             (Kernel Space)   │  │
│   │              │    内核       │                              │  │
│   │              │               │                              │  │
│   │   ┌─────────────────────────────────────────────────────┐  │  │
│   │   │  文件系统  │  网络协议栈  │  进程调度  │  内存管理   │  │  │
│   │   └─────────────────────────────────────────────────────┘  │  │
│   │                       │                                     │  │
│   │                       ▼                                     │  │
│   │              ┌────────────────┐                            │  │
│   │              │   硬件设备    │                              │  │
│   │              └────────────────┘                            │  │
│   └─────────────────────────────────────────────────────────────┘  │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```
<!-- /DIAGRAM -->

**关键理解**：

- 应用程序运行在**用户态**，无法直接访问硬件
- 需要硬件操作时，必须通过**系统调用**请求内核
- 系统调用是用户态和内核态的**唯一合法通道**
- **strace** 就是追踪这些系统调用的工具

### 1.2 常见系统调用分类

| 分类 | 系统调用示例 | 用途 |
|------|-------------|------|
| **文件操作** | open, read, write, close, stat, lstat | 文件读写、属性查询 |
| **进程控制** | fork, exec, exit, wait, kill | 进程创建、终止 |
| **内存管理** | mmap, munmap, brk, mprotect | 内存分配、映射 |
| **网络操作** | socket, connect, send, recv, accept | 网络通信 |
| **信号处理** | signal, sigaction, kill | 进程间信号 |

### 1.3 strace 的工作原理

```bash
# strace 使用 ptrace 系统调用来追踪目标进程
# 每次目标进程执行 syscall，strace 都会被通知

# 这就是为什么 strace 有开销：
# 1. 每个 syscall 都会中断目标进程
# 2. strace 记录信息
# 3. 再恢复目标进程

# 开销通常是 10x-100x 减速！
# 生产环境要谨慎使用
```

---

## Step 2 - strace 基础用法（15 分钟）

### 2.1 三种追踪模式

<!-- DIAGRAM: strace-modes -->
```
┌─────────────────────────────────────────────────────────────────────┐
│                       strace 三种追踪模式                            │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│   模式 1：启动新进程追踪                                             │
│   ┌─────────────────────────────────────────────────────────────┐  │
│   │                                                             │  │
│   │   $ strace ./program                                        │  │
│   │                                                             │  │
│   │   strace 启动 program，从头追踪所有 syscall                  │  │
│   │   适用：调试启动问题、分析程序行为                           │  │
│   │                                                             │  │
│   └─────────────────────────────────────────────────────────────┘  │
│                                                                     │
│   模式 2：附加到运行中进程                                           │
│   ┌─────────────────────────────────────────────────────────────┐  │
│   │                                                             │  │
│   │   $ strace -p PID                                           │  │
│   │                                                             │  │
│   │   附加到已运行的进程，实时追踪                               │  │
│   │   适用：生产环境诊断、运行中问题排查                         │  │
│   │   ⚠️  进程会被减速，谨慎使用                                 │  │
│   │                                                             │  │
│   └─────────────────────────────────────────────────────────────┘  │
│                                                                     │
│   模式 3：追踪子进程                                                 │
│   ┌─────────────────────────────────────────────────────────────┐  │
│   │                                                             │  │
│   │   $ strace -f ./program                                     │  │
│   │   $ strace -f -p PID                                        │  │
│   │                                                             │  │
│   │   -f = follow forks                                         │  │
│   │   追踪目标进程及其所有子进程                                 │  │
│   │   适用：多进程程序、shell 脚本、服务进程                     │  │
│   │                                                             │  │
│   └─────────────────────────────────────────────────────────────┘  │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```
<!-- /DIAGRAM -->

### 2.2 基本命令示例

```bash
# 模式 1：追踪新进程
strace ls /tmp
strace ./my_program arg1 arg2

# 模式 2：附加到运行中进程
strace -p 1234                  # 追踪 PID 1234
strace -p $(pgrep nginx | head -1)  # 追踪第一个 nginx 进程

# 模式 3：追踪子进程
strace -f ./script.sh           # 追踪 shell 脚本及其子命令
strace -f -p 1234               # 追踪进程及其子进程

# 输出到文件（推荐用于分析）
strace -o output.txt ls /tmp
strace -o output.txt -f -p 1234
```

### 2.3 strace 输出解读

```bash
$ strace cat /etc/hostname
# 输出格式：
# syscall_name(arg1, arg2, ...) = return_value <time>

openat(AT_FDCWD, "/etc/hostname", O_RDONLY) = 3
#  │        │           │            │        └─ 返回值：文件描述符 3
#  │        │           │            └─ flags：只读
#  │        │           └─ 文件路径
#  │        └─ 特殊值：当前工作目录
#  └─ 系统调用名

read(3, "my-server\n", 131072)    = 10
#  │   │       │         │          └─ 返回值：读取了 10 字节
#  │   │       │         └─ 缓冲区大小
#  │   │       └─ 读取的内容（部分显示）
#  │   └─ 文件描述符
#  └─ 系统调用名

close(3)                          = 0
#     │                             └─ 返回值：0 表示成功
#     └─ 关闭文件描述符 3
```

### 2.4 常见错误码

当系统调用失败时，返回值是 -1，并显示错误码：

```bash
openat(AT_FDCWD, "/nonexistent", O_RDONLY) = -1 ENOENT (No such file or directory)
#                                              │  │
#                                              │  └─ 错误描述
#                                              └─ 错误码
```

| 错误码 | 含义 | 常见原因 |
|--------|------|----------|
| `ENOENT` | No such file or directory | 文件/目录不存在 |
| `EACCES` | Permission denied | 权限不足 |
| `EEXIST` | File exists | 文件已存在 |
| `EINTR` | Interrupted system call | 被信号中断 |
| `EAGAIN` | Resource temporarily unavailable | 非阻塞操作暂时无法完成 |
| `ECONNREFUSED` | Connection refused | 连接被拒绝 |
| `ETIMEDOUT` | Connection timed out | 连接超时 |

---

## Step 3 - 性能分析模式（15 分钟）

### 3.1 -c：统计汇总模式

**最常用的性能分析起点**。快速了解程序的 syscall 分布。

```bash
$ strace -c ls /tmp
% time     seconds  usecs/call     calls    errors syscall
------ ----------- ----------- --------- --------- ----------------
 28.57    0.000040           4        10           mmap
 21.43    0.000030           3        10           mprotect
 14.29    0.000020           2        10           close
 14.29    0.000020           4         5           openat
 14.29    0.000020          10         2           write
  7.14    0.000010           5         2           read
  0.00    0.000000           0        15        12 stat
------ ----------- ----------- --------- --------- ----------------
100.00    0.000140                    54        12 total
```

**解读要点**：

| 列 | 含义 | 性能分析意义 |
|------|------|-------------|
| `% time` | 该类 syscall 占总时间百分比 | **最重要**：找出耗时最多的 |
| `seconds` | 该类 syscall 总耗时 | 绝对时间 |
| `usecs/call` | 每次调用平均耗时（微秒）| 识别慢调用 |
| `calls` | 调用次数 | 识别高频调用 |
| `errors` | 错误次数 | **关键**：大量错误 = 潜在问题 |

**性能问题信号**：

```bash
# 信号 1：某类 syscall 错误数很高
   0.00    0.000000           0      1500     1500 stat
#                                              ^^^^
# 1500 次 stat 调用全部失败！典型的"找不到文件"问题

# 信号 2：某类 syscall 占用大量时间
 85.00    5.000000        5000      1000           poll
#
# poll 占 85% 时间，可能是网络等待或文件 I/O 等待

# 信号 3：某类 syscall 调用次数异常多
  0.50    0.000500           0    100000           open
#                                 ^^^^^^
# 10 万次 open！可能是未缓存文件句柄
```

### 3.2 -T：显示每次调用耗时

```bash
$ strace -T ls /tmp
openat(AT_FDCWD, "/tmp", O_RDONLY|O_NONBLOCK|O_CLOEXEC|O_DIRECTORY) = 3 <0.000015>
#                                                                        ^^^^^^^^^
#                                                                        耗时 15 微秒

getdents64(3, /* 5 entries */, 32768) = 160 <0.000008>
close(3)                               = 0 <0.000005>
```

**实用技巧：找出慢调用**

```bash
# 找出耗时超过 100ms (0.1秒) 的调用
strace -T -p 1234 2>&1 | awk -F'[<>]' '$2 > 0.1 {print}'

# 找出耗时超过 1秒 的调用
strace -T -p 1234 2>&1 | awk -F'[<>]' '$2 > 1.0 {print}'
```

### 3.3 -t/-tt/-ttt：时间戳模式

```bash
# -t：精确到秒
$ strace -t ls /tmp
14:30:25 execve("/bin/ls", ["ls", "/tmp"], ...) = 0
14:30:25 brk(NULL)                       = 0x55a8b1234000

# -tt：精确到微秒（推荐）
$ strace -tt ls /tmp
14:30:25.123456 execve("/bin/ls", ["ls", "/tmp"], ...) = 0
14:30:25.124789 brk(NULL)                = 0x55a8b1234000

# -ttt：Unix 时间戳（便于脚本处理）
$ strace -ttt ls /tmp
1704873025.123456 execve("/bin/ls", ["ls", "/tmp"], ...) = 0
```

**组合使用**（最完整的性能分析输出）：

```bash
# 推荐组合：时间戳 + 每次耗时
strace -tt -T -p 1234

# 输出：
14:30:25.123456 read(3, "data...", 4096) = 100 <0.000015>
14:30:25.123500 write(4, "data...", 100) = 100 <0.000008>
#  │              │                           │    │
#  │              │                           │    └─ 耗时
#  │              │                           └─ 返回值
#  │              └─ 系统调用及参数
#  └─ 时间戳
```

### 3.4 性能分析工作流

```bash
# Step 1: 先用 -c 获取全局视图
strace -c ./slow_program
# 发现：stat() 调用 5000 次，错误 4800 次

# Step 2: 用 -e 过滤，-T 查看详细
strace -e trace=stat -T ./slow_program 2>&1 | head -50
# 发现：反复 stat() 同一个不存在的配置文件

# Step 3: 用 -tt 查看时间线
strace -e trace=stat -tt ./slow_program 2>&1 | head -50
# 发现：每毫秒调用多次，形成 "stat storm"
```

---

## Step 4 - 筛选系统调用（10 分钟）

### 4.1 -e trace 选项

strace 默认输出所有系统调用，信息量大。使用 `-e trace` 过滤特定类别。

```bash
# 只追踪特定系统调用
strace -e trace=open,read,write ./program
strace -e trace=stat,lstat,fstat ./program
strace -e trace=connect,accept,send,recv ./program

# 使用预定义分类（更方便）
strace -e trace=file ./program       # 所有文件相关
strace -e trace=network ./program    # 所有网络相关
strace -e trace=process ./program    # 所有进程相关
strace -e trace=memory ./program     # 所有内存相关
strace -e trace=signal ./program     # 所有信号相关
strace -e trace=ipc ./program        # 所有 IPC 相关
```

### 4.2 预定义分类详解

| 分类 | 包含的系统调用 | 适用场景 |
|------|---------------|----------|
| `file` | open, read, write, close, stat, access, chmod... | 文件访问问题、权限问题 |
| `network` | socket, connect, accept, send, recv, bind... | 网络连接问题、延迟分析 |
| `process` | fork, exec, exit, wait, clone... | 进程创建问题、启动慢 |
| `memory` | mmap, munmap, brk, mprotect... | 内存分配问题 |
| `signal` | signal, sigaction, kill, sigprocmask... | 信号处理问题 |
| `desc` | read, write, close, dup, fcntl... (基于文件描述符) | I/O 操作分析 |

### 4.3 实战示例

```bash
# 场景 1：调试程序找不到配置文件
strace -e trace=file ./app 2>&1 | grep -E "open|ENOENT"
# 找出所有尝试打开但失败的文件

# 场景 2：分析网络连接慢
strace -e trace=network -T ./app 2>&1 | grep -E "connect|<"
# 找出哪个连接耗时长

# 场景 3：分析进程启动慢
strace -e trace=process -tt ./app 2>&1 | head -30
# 查看 fork/exec 时间线

# 场景 4：组合过滤
strace -e trace=open,stat,access ./app 2>&1 | grep -v "= 0"
# 只看失败的文件访问
```

### 4.4 排除特定系统调用

```bash
# 有时候输出太多，想排除某些调用
# 方法：使用 grep -v

strace ./program 2>&1 | grep -v -E "^(mmap|mprotect|brk)"
# 排除内存相关调用，专注其他

# 或使用 strace 的否定语法（较新版本）
strace -e trace=!mmap,!mprotect ./program
```

---

## Step 5 - 常见性能问题模式（15 分钟）

### 5.1 模式 1：stat() storm（统计风暴）

**症状**：程序 CPU 使用高，但看起来没做什么有意义的事。

```bash
$ strace -c ./slow_app
% time     seconds  usecs/call     calls    errors syscall
------ ----------- ----------- --------- --------- ----------------
 95.00    2.500000           2      1200000   1200000 stat
#                                  ^^^^^^^   ^^^^^^^
#                                  120 万次调用，全部失败！
```

**根因**：程序反复检查不存在的文件。

```bash
$ strace -e stat -T ./slow_app 2>&1 | head -20
stat("/etc/myapp/config.yaml", ...) = -1 ENOENT (No such file or directory) <0.000005>
stat("/etc/myapp/config.yaml", ...) = -1 ENOENT (No such file or directory) <0.000004>
stat("/etc/myapp/config.yaml", ...) = -1 ENOENT (No such file or directory) <0.000005>
stat("/etc/myapp/config.yaml", ...) = -1 ENOENT (No such file or directory) <0.000004>
# ... 反复循环
```

**典型场景**（来自 Gemini - The Syscall Storm）：

```
Python API 即使在低流量下也消耗 100% CPU
根因：代码在循环中检查配置文件，但文件不存在
每次循环都调用 stat()，形成"统计风暴"

日本语境：スケーリングコストの無駄（Mottainai - 浪费）
```

**解决方案**：

```python
# 错误：在循环中检查文件
while True:
    if os.path.exists("/etc/myapp/config.yaml"):  # 每次循环都调用 stat()
        config = load_config()
    process_request()

# 正确：只检查一次，或使用缓存
config = load_config_or_default()  # 启动时加载
while True:
    process_request(config)
```

### 5.2 模式 2：open/close loop（未缓存文件句柄）

**症状**：大量 open/close 调用，文件 I/O 慢。

```bash
$ strace -c ./app
% time     seconds  usecs/call     calls    errors syscall
------ ----------- ----------- --------- --------- ----------------
 40.00    1.000000          10    100000           openat
 35.00    0.875000           8    100000           close
 20.00    0.500000           5    100000           read
```

**根因**：每次操作都重新打开文件，而不是复用文件句柄。

```bash
$ strace -e trace=open,close -T ./app 2>&1 | head -20
openat(AT_FDCWD, "/data/records.db", O_RDONLY) = 3 <0.000050>
read(3, "...", 100) = 100 <0.000010>
close(3) = 0 <0.000005>
openat(AT_FDCWD, "/data/records.db", O_RDONLY) = 3 <0.000050>  # 又打开！
read(3, "...", 100) = 100 <0.000010>
close(3) = 0 <0.000005>
# ... 反复循环
```

**解决方案**：

```python
# 错误：每次都打开关闭
def get_record(id):
    with open("/data/records.db") as f:  # 每次调用都 open/close
        return find_record(f, id)

# 正确：复用文件句柄或使用连接池
class RecordStore:
    def __init__(self):
        self.fd = open("/data/records.db")  # 打开一次

    def get_record(self, id):
        return find_record(self.fd, id)  # 复用句柄
```

### 5.3 模式 3：DNS blocking（DNS 阻塞）

**症状**：网络请求偶发性延迟，约 5 秒倍数。

```bash
$ strace -e trace=network -T ./app 2>&1 | grep -E "connect|poll"
connect(3, {sa_family=AF_INET6, ...}, 28) = -1 EINPROGRESS <0.000050>
poll([{fd=3, events=POLLOUT}], 1, 5000) = 0 (Timeout) <5.001234>
#                                                       ^^^^^^^^^
#                                                       5 秒超时！
connect(3, {sa_family=AF_INET, ...}, 16) = 0 <0.050000>
# 然后 IPv4 成功
```

**根因**：DNS 解析先尝试 IPv6，超时后才 fallback 到 IPv4。

**相关场景**（来自 Gemini - The Invisible Delay）：

```
症状：随机页面加载正好多 5.0 秒
      只影响部分请求

根因：DNS 查询 IPv6 (AAAA) 超时，5 秒后才尝试 IPv4

日本语境：AWS RDS 接続時のランダム遅延
```

**诊断方法**：

```bash
# 用 strace 追踪 DNS 相关调用
strace -e trace=network -tt -T ./app 2>&1 | grep -E "socket|connect|poll"

# 或直接用 tcpdump 看 DNS
sudo tcpdump -nn port 53

# 检查 DNS 配置
cat /etc/resolv.conf
cat /etc/gai.conf  # IPv6 优先级配置
```

**解决方案**：

```bash
# 方案 1：禁用 IPv6 DNS 查询
echo 'precedence ::ffff:0:0/96  100' >> /etc/gai.conf

# 方案 2：在应用中强制 IPv4
# Python
socket.setdefaulttimeout(1)
socket.getaddrinfo(host, port, socket.AF_INET)

# 方案 3：检查 DNS 服务器是否支持 IPv6
```

### 5.4 模式识别速查表

| 模式 | strace -c 特征 | 根因 | 解决方向 |
|------|---------------|------|----------|
| **stat() storm** | stat 调用极多，errors 也多 | 反复检查不存在的文件 | 缓存检查结果 |
| **open/close loop** | open/close 成对且数量大 | 未复用文件句柄 | 使用句柄池 |
| **DNS blocking** | poll/select 超时 ~5s | IPv6 DNS 超时 | 调整 DNS 配置 |
| **read() 频繁小块** | read 调用多，每次字节少 | 无缓冲读取 | 使用 BufferedReader |
| **write() sync storm** | write 后紧跟 fsync/fdatasync | 过度刷盘 | 批量写入 |

---

## Step 6 - ltrace：库调用追踪（5 分钟）

### 6.1 strace vs ltrace

| 工具 | 追踪内容 | 适用场景 |
|------|----------|----------|
| **strace** | 系统调用（内核接口）| 文件、网络、进程等底层操作 |
| **ltrace** | 库函数调用（如 libc）| 程序逻辑、字符串操作、数学计算 |

### 6.2 ltrace 基本使用

```bash
# 安装
sudo apt install ltrace  # Debian/Ubuntu
sudo yum install ltrace  # RHEL/CentOS

# 基本追踪
ltrace ./program

# 追踪特定库
ltrace -l libc.so.6 ./program

# 统计模式
ltrace -c ./program

# 追踪运行中进程
ltrace -p 1234
```

### 6.3 ltrace 输出示例

```bash
$ ltrace ls /tmp
__libc_start_main(0x555555558100, 2, ...) = ...
setlocale(LC_ALL, "")                   = "en_US.UTF-8"
bindtextdomain("coreutils", "/usr/share/locale") = "/usr/share/locale"
textdomain("coreutils")                 = "coreutils"
getopt_long(2, 0x7fffffffde08, ..., 0, 0) = -1
strlen(".")                              = 1
malloc(32)                              = 0x5555555592a0
strncpy(0x5555555592a0, "/tmp", 31)     = 0x5555555592a0
opendir("/tmp")                         = 0x5555555595f0
readdir(0x5555555595f0)                 = 0x555555559610
strlen(".")                              = 1
```

### 6.4 ltrace 与 strace 配合使用

```bash
# 场景：程序运行慢，但 strace 看不出问题
# 可能是库函数内部问题

# Step 1: strace 看系统调用
strace -c ./program
# 输出正常，syscall 不是瓶颈

# Step 2: ltrace 看库调用
ltrace -c ./program
# 发现：strcmp 调用 100 万次！
# 根因：低效的字符串比较算法

# Step 3: 优化应用代码
# 使用 hash table 替代线性字符串比较
```

---

## strace Cheatsheet

```bash
# ============================================================
# strace Cheatsheet
# ============================================================

# === 基本追踪 ===
strace ./program              # 追踪新进程
strace -p PID                 # 附加到运行中进程
strace -f ./program           # 包含子进程
strace -f -p PID              # 运行进程 + 子进程

# === 性能分析 ===
strace -c ./program           # ⭐ 统计汇总（首选！）
strace -c -p PID              # 运行进程统计（Ctrl+C 结束）
strace -T ./program           # 显示每次调用耗时
strace -tt -T ./program       # 时间戳 + 耗时（完整分析）

# === 过滤系统调用 ===
strace -e trace=file ./program       # 文件相关
strace -e trace=network ./program    # 网络相关
strace -e trace=process ./program    # 进程相关
strace -e trace=open,read,write ./program  # 指定调用

# === 实用技巧 ===
# 找慢调用（耗时 > 0.1 秒）
strace -T -p PID 2>&1 | awk -F'[<>]' '$2 > 0.1 {print}'

# 找失败的文件访问
strace -e trace=file ./program 2>&1 | grep ENOENT

# 找网络超时
strace -e trace=network -T ./program 2>&1 | grep -E "poll.*Timeout|<[0-9]+\."

# 输出到文件
strace -o output.txt -tt -T -f ./program

# === 统计分析快速定位 ===
# errors 列高 → 大量失败调用 → 检查 ENOENT/EACCES
# calls 列高 → 调用频繁 → 检查是否可以缓存/批量
# % time 高 → 时间占用大 → 检查是否阻塞/超时

# === ltrace（库调用）===
ltrace ./program              # 追踪库函数
ltrace -c ./program           # 统计库函数调用

# === 生产环境注意 ===
# ⚠️  strace 开销大（10x-100x 减速）
# ⚠️  短时间追踪，或用 -e 过滤
# ⚠️  高负载场景考虑 eBPF (bpftrace, BCC)
```

---

## 实战场景：The Syscall Storm（Lab）

### 场景背景（来自 Gemini）

```
症状：Python API 即使在低流量下也消耗 100% 单核 CPU
      服务器扩容后成本翻倍，但性能没提升

日本语境：スケーリングコストの無駄（Mottainai - 浪费）
         - 扩容不解决问题，反而增加成本
```

### 模拟问题程序

```bash
# 创建实验目录
mkdir -p ~/strace-lab
cd ~/strace-lab

# 创建模拟程序（stat storm）
cat > stat_storm.py << 'EOF'
#!/usr/bin/env python3
"""
模拟 Syscall Storm 问题
每次循环都检查配置文件是否存在
"""
import os
import time

CONFIG_PATH = "/etc/myapp/config.yaml"  # 不存在的文件

def check_config():
    """错误模式：每次都检查文件"""
    return os.path.exists(CONFIG_PATH)

def process_request():
    """模拟请求处理"""
    time.sleep(0.001)  # 1ms 处理时间

def main():
    print(f"Starting server (checking {CONFIG_PATH})...")
    request_count = 0
    while request_count < 10000:  # 处理 10000 个请求
        if check_config():  # 每次请求都检查配置！
            print("Config found!")
        process_request()
        request_count += 1
        if request_count % 1000 == 0:
            print(f"Processed {request_count} requests")
    print("Done!")

if __name__ == "__main__":
    main()
EOF

chmod +x stat_storm.py
```

### 诊断步骤

```bash
# Step 1: 先用 -c 获取全局视图
strace -c python3 stat_storm.py
```

**预期输出**：

```
% time     seconds  usecs/call     calls    errors syscall
------ ----------- ----------- --------- --------- ----------------
 45.00    0.500000           0     10000     10000 stat
#                                            ^^^^^
#                                            全部失败！

 30.00    0.333000          33     10000           nanosleep
 10.00    0.111000          11     10000           write
  ...
```

```bash
# Step 2: 查看 stat 调用详情
strace -e trace=stat -T python3 stat_storm.py 2>&1 | head -20
```

**预期输出**：

```
stat("/etc/myapp/config.yaml", ...) = -1 ENOENT <0.000010>
stat("/etc/myapp/config.yaml", ...) = -1 ENOENT <0.000008>
stat("/etc/myapp/config.yaml", ...) = -1 ENOENT <0.000009>
# ... 反复调用同一个不存在的文件
```

```bash
# Step 3: 用时间戳查看频率
strace -e trace=stat -tt python3 stat_storm.py 2>&1 | head -10
```

**预期输出**：

```
14:30:25.001234 stat("/etc/myapp/config.yaml", ...) = -1 ENOENT
14:30:25.002345 stat("/etc/myapp/config.yaml", ...) = -1 ENOENT
14:30:25.003456 stat("/etc/myapp/config.yaml", ...) = -1 ENOENT
# 每毫秒一次！这是 stat storm
```

### 修复后对比

```bash
# 创建修复版本
cat > stat_storm_fixed.py << 'EOF'
#!/usr/bin/env python3
"""
修复版：只在启动时检查一次配置
"""
import os
import time

CONFIG_PATH = "/etc/myapp/config.yaml"

def load_config():
    """正确模式：启动时检查一次"""
    if os.path.exists(CONFIG_PATH):
        return {"loaded": True}
    return {"loaded": False, "default": True}

def process_request(config):
    time.sleep(0.001)

def main():
    print(f"Starting server...")
    config = load_config()  # 只检查一次！
    print(f"Config loaded: {config}")

    request_count = 0
    while request_count < 10000:
        process_request(config)  # 直接使用缓存的配置
        request_count += 1
        if request_count % 1000 == 0:
            print(f"Processed {request_count} requests")
    print("Done!")

if __name__ == "__main__":
    main()
EOF

# 对比修复前后
echo "=== 修复前 ==="
strace -c python3 stat_storm.py 2>&1 | grep stat

echo ""
echo "=== 修复后 ==="
strace -c python3 stat_storm_fixed.py 2>&1 | grep stat
```

**预期对比**：

```
=== 修复前 ===
 45.00    0.500000           0     10000     10000 stat

=== 修复后 ===
  0.01    0.000010          10         1         1 stat
#                                       ^         ^
#                                       只调用 1 次！
```

### 清理

```bash
rm -rf ~/strace-lab
```

---

## 反模式：常见错误

### 错误 1：在高频进程上长时间运行 strace

```bash
# 错误：对生产数据库运行 strace
strace -p $(pgrep mysqld) 2>&1 | head -1000000
# 这会导致数据库严重减速！

# 正确：短时间追踪 + 过滤
strace -p $(pgrep mysqld) -e trace=file -T 2>&1 | head -100
# 只追踪文件操作，只取 100 行
```

### 错误 2：不先用 -c 获取全局视图

```bash
# 错误：直接看详细输出
strace ./slow_program 2>&1 | less
# 几万行输出，不知道从哪看起

# 正确：先统计
strace -c ./slow_program
# 发现 stat() 占 90%，然后针对性分析
strace -e trace=stat -T ./slow_program 2>&1 | head -50
```

### 错误 3：忽略 errors 列

```bash
# 错误：只看 % time，忽略 errors
% time     seconds  usecs/call     calls    errors syscall
 45.00    0.001000           0      1000           stat
# "stat 只占 45% 时间，问题不大"

# 正确：注意 errors 列
 45.00    0.001000           0      1000      990 stat
#                                           ^^^
# 99% 失败！这是问题信号
```

### 错误 4：混淆 strace 和 ltrace

```bash
# 错误：用 strace 找库函数问题
strace ./program
# 看不到 strcmp、strlen 等库调用

# 正确：用 ltrace 看库调用
ltrace -c ./program
# 发现 strcmp 调用 100 万次
```

---

## 职场小贴士（Japan IT Context）

### アプリが遅い原因調査

在日本 IT 企业，"应用变慢"是常见的运维任务。strace 是排查利器。

| 日语术语 | 读音 | 含义 | strace 相关 |
|----------|------|------|-------------|
| システムコール | システムコール | System call | strace 追踪对象 |
| アプリ遅延 | アプリちえん | Application delay | strace -T 定位 |
| ボトルネック | ボトルネック | Bottleneck | strace -c 找热点 |
| 処理時間 | しょりじかん | Processing time | -T 参数显示 |
| 原因調査 | げんいんちょうさ | Root cause analysis | 系统化分析流程 |

### strace 使用报告模板

**障害調査報告（故障调查报告）**：

```markdown
## アプリケーション遅延調査報告

### 発生日時
2026-01-10 14:30 JST

### 症状
Python API のレスポンスが遅い（平均 500ms → 5000ms）
CPU 使用率が 100% に張り付く

### strace 分析結果

#### 統計サマリ（strace -c）
% time     seconds  usecs/call     calls    errors syscall
------ ----------- ----------- --------- --------- ----------------
 95.00    4.750000           4   1000000   1000000 stat

#### 問題パターン
- stat() システムコールが 100 万回、全て失敗（ENOENT）
- 対象ファイル: /etc/myapp/config.yaml（存在しない）
- 毎リクエストでファイル存在チェック → stat storm

### 根本原因
コードが毎リクエストで存在しない設定ファイルをチェック
os.path.exists() がループ内で呼ばれている

### 対策
1. 設定ファイルチェックを起動時のみに変更
2. 存在チェック結果をキャッシュ
3. デフォルト設定を実装

### エビデンス
[strace 出力ログ添付]
```

---

## 面试准备（Interview Prep）

### Q1: strace で何がわかりますか？

**回答要点**：

```
strace はプロセスが発行するシステムコールを追跡します。

わかること：
- ファイルアクセス（どのファイルを開いて読み書きしているか）
- ネットワーク操作（どのアドレスに接続しているか）
- プロセス操作（fork、exec など）
- エラー発生（ファイルが見つからない、権限エラーなど）

パフォーマンス分析では：
- -c オプションで統計を取得
- -T オプションで各呼び出しの時間を計測
- 大量のエラーや異常な呼び出し回数を検出
```

### Q2: strace のオーバーヘッドは？

**回答要点**：

```
strace は ptrace を使用するため、オーバーヘッドが大きいです。

影響：
- 10〜100 倍の遅延が発生する可能性
- 各システムコールでプロセスが停止・再開

本番環境での対策：
1. 短時間で実行（5-10 秒程度）
2. -e trace= でフィルタリング
3. 高負荷プロセスは避ける
4. eBPF ツール（bpftrace, BCC）を検討
   - オーバーヘッドが小さい
   - 本番環境でも安全
```

### Q3: stat storm とは何ですか？どう対処しますか？

**回答要点**：

```
stat storm は、同じファイルの存在確認を大量に繰り返す問題です。

典型的なパターン：
- ループ内で os.path.exists() を呼ぶ
- 存在しないファイルを毎回チェック
- CPU を消費するが有益な処理をしていない

検出方法：
strace -c ./program
→ stat のエラー数が異常に多い

対処法：
1. ファイル存在チェックを起動時に移動
2. 結果をキャッシュする
3. ファイル監視（inotify）に変更
```

---

## 检查清单

完成本课后，你应该能够：

- [ ] 解释系统调用的概念及 strace 的工作原理
- [ ] 使用三种追踪模式（新进程、附加、子进程）
- [ ] 解读 strace 输出（系统调用名、参数、返回值、错误码）
- [ ] 使用 -c 获取系统调用统计（性能分析首选）
- [ ] 使用 -T 追踪每次调用耗时
- [ ] 使用 -e trace= 筛选特定系统调用类别
- [ ] 识别 stat() storm 模式并提出解决方案
- [ ] 识别 open/close loop 模式并提出解决方案
- [ ] 识别 DNS blocking 模式并提出解决方案
- [ ] 了解 ltrace 的用途和基本使用
- [ ] 理解 strace 在生产环境的开销和使用注意事项

---

## 本课小结

| 概念 | 要点 |
|------|------|
| 系统调用 | 用户态程序与内核通信的唯一合法通道 |
| strace | 追踪进程的系统调用，性能分析利器 |
| -c 统计 | **首选**！快速获取全局视图 |
| -T 计时 | 显示每次调用耗时，找慢调用 |
| -e trace= | 过滤特定类别，减少噪音 |
| stat() storm | 反复检查不存在的文件，解决：缓存 |
| open/close loop | 未复用文件句柄，解决：句柄池 |
| DNS blocking | IPv6 超时后 fallback，解决：配置调整 |
| ltrace | 追踪库函数调用（非系统调用）|
| 生产注意 | 开销大（10-100x），短时间 + 过滤 |

---

## 延伸阅读

- [Brendan Gregg: strace Isn't Free](https://www.brendangregg.com/blog/2014-05-11/strace-wow-much-syscall.html)
- [Linux man-pages: strace(1)](https://man7.org/linux/man-pages/man1/strace.1.html)
- [Linux man-pages: syscalls(2)](https://man7.org/linux/man-pages/man2/syscalls.2.html)
- 上一课：[05 - 网络性能](../05-network-performance/)
- 下一课：[07 - perf 性能分析器](../07-perf/) - 从系统调用到 CPU 采样
- 相关课程：[LX10 - eBPF 入门](../10-ebpf-introduction/) - 生产环境低开销追踪

---

## 系列导航

[<-- 05 - 网络性能](../05-network-performance/) | [系列首页](../) | [07 - perf 性能分析器 -->](../07-perf/)
