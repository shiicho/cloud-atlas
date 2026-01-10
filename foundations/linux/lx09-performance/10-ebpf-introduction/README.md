# 10 - eBPF 入门（BCC 工具）

> **目标**：理解 eBPF 的革命性优势，掌握 BCC 预编译工具进行生产环境低开销追踪  
> **前置**：08-Flamegraphs（必须能自信解读火焰图）  
> **时间**：⚡ 25 分钟（速读）/ 🔬 90 分钟（完整实操）  
> **实战场景**：本番環境での低オーバーヘッド調査 - BCC ツール活用  

---

## 将学到的内容

1. 理解 eBPF 是什么及其革命性优势
2. 理解 eBPF 安全模型（Verifier、沙盒）
3. 安装 BCC 工具（Ubuntu/RHEL）
4. 掌握 Tier 1 核心 BCC 工具（7 个必备）
5. 了解 Tier 2 推荐 BCC 工具（3 个障害対応利器）
6. 使用 bpftrace 快速一行脚本
7. 理解 BCC vs bpftrace vs libbpf 选择策略
8. 知道何时使用 eBPF vs 传统工具

---

## 先跑起来！（10 分钟）

> **前置检查**：你能自信解读 Flamegraph 吗？  
>
> 如果对 Flamegraph 还不熟悉，请先完成 [08 - Flamegraphs](../08-flamegraphs/)。  
> Codex GPT-5 建议："只有在学员能自信解读 Flamegraph 后才教 eBPF"。  

在学习 eBPF 理论之前，先体验它的威力。

```bash
# 检查内核版本（需要 4.4+，推荐 5.x+）
uname -r

# 安装 BCC 工具（Ubuntu 22.04+）
sudo apt update && sudo apt install -y bpfcc-tools linux-headers-$(uname -r)

# 或者 RHEL/CentOS 8+
# sudo dnf install -y bcc-tools

# 立即体验：追踪所有新进程执行
sudo execsnoop-bpfcc

# 在另一个终端运行一些命令
# ls, ps, cat /etc/passwd ...
# 观察 execsnoop 输出
```

**你刚刚看到了什么？**

```
PCOMM            PID    PPID   RET ARGS
ls               12345  12300    0 /bin/ls --color=auto
cat              12346  12300    0 /bin/cat /etc/passwd
ps               12347  12300    0 /bin/ps aux
```

每一个新进程的执行都被捕获了！包括那些"一闪而过"的短命进程。

**传统工具（top、ps）根本看不到这些短命进程。**

这就是 eBPF 的威力 —— 内核级可见性，低开销，生产安全。

---

## Step 1 - 什么是 eBPF？（15 分钟）

### 1.1 eBPF 简介

**eBPF（extended Berkeley Packet Filter）** 是 Linux 内核的革命性技术，允许在内核中安全地运行自定义程序。

<!-- DIAGRAM: ebpf-architecture -->
```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           eBPF 架构概览                                       │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│    用户空间 (User Space)                                                     │
│    ┌─────────────────────────────────────────────────────────────────────┐ │
│    │  BCC Tools        bpftrace        libbpf/CO-RE                     │ │
│    │  (execsnoop,      (one-liners)    (production tools)               │ │
│    │   biolatency...)                                                    │ │
│    └───────────────────────────────┬─────────────────────────────────────┘ │
│                                    │ 加载 eBPF 程序                        │
│    ────────────────────────────────┼─────────────────────────────────────── │
│                                    ▼                                       │
│    内核空间 (Kernel Space)                                                   │
│    ┌─────────────────────────────────────────────────────────────────────┐ │
│    │                        eBPF Verifier                                │ │
│    │                   ┌────────────────────┐                            │ │
│    │                   │ 安全检查：          │                            │ │
│    │                   │ • 无无限循环        │                            │ │
│    │                   │ • 无越界内存访问    │                            │ │
│    │                   │ • 有限指令数        │                            │ │
│    │                   │ • 只能访问允许的    │                            │ │
│    │                   │   内核数据结构      │                            │ │
│    │                   └─────────┬──────────┘                            │ │
│    │                             │ 验证通过                               │ │
│    │                             ▼                                       │ │
│    │    ┌─────────────────────────────────────────────────────────────┐ │ │
│    │    │                  eBPF 沙盒执行环境                            │ │ │
│    │    │  ┌─────────┐   ┌─────────┐   ┌─────────┐   ┌─────────┐    │ │ │
│    │    │  │ kprobes │   │ uprobes │   │ tracepoints│ │ XDP     │    │ │ │
│    │    │  └─────────┘   └─────────┘   └─────────┘   └─────────┘    │ │ │
│    │    └─────────────────────────────────────────────────────────────┘ │ │
│    │                             │                                       │ │
│    │                             ▼                                       │ │
│    │    ┌─────────────────────────────────────────────────────────────┐ │ │
│    │    │  内核内聚合 (In-Kernel Aggregation)                          │ │ │
│    │    │  • 直方图、计数、求和在内核完成                               │ │ │
│    │    │  • 只传输最终结果，不拷贝原始数据                             │ │ │
│    │    └─────────────────────────────────────────────────────────────┘ │ │
│    └─────────────────────────────────────────────────────────────────────┘ │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```
<!-- /DIAGRAM -->

### 1.2 为什么 eBPF 是革命性的？

**传统追踪的问题**：

| 工具 | 问题 |
|------|------|
| strace | 用户空间 ptrace，开销 10-100x，生产环境不可用 |
| perf | 采样有开销，持续追踪会产生大量数据 |
| kernel module | 不安全，可能导致内核崩溃 |

**eBPF 的优势**：

| 特性 | 说明 |
|------|------|
| **安全** | Verifier 验证程序安全性，不会崩溃内核 |
| **低开销** | 内核内聚合，不拷贝大量数据到用户空间 |
| **生产可用** | Netflix、Facebook、Google 在生产环境使用 |
| **动态** | 无需重启内核，动态加载/卸载 |

### 1.3 eBPF 安全模型

**为什么 eBPF 是安全的？**

```
┌─────────────────────────────────────────────────────────────────┐
│                    eBPF Verifier 安全保障                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1. 无无限循环                                                   │
│     • 程序必须有确定的终止点                                     │
│     • 循环次数有上限                                             │
│                                                                 │
│  2. 无越界内存访问                                               │
│     • 所有内存访问都经过边界检查                                 │
│     • 只能访问 eBPF 允许的内存区域                               │
│                                                                 │
│  3. 有限指令数                                                   │
│     • 程序复杂度有上限（默认 1M 指令）                           │
│     • 防止资源耗尽                                               │
│                                                                 │
│  4. 沙盒执行                                                     │
│     • 程序在受限环境中运行                                       │
│     • 不能直接调用任意内核函数                                   │
│                                                                 │
│  5. 权限控制                                                     │
│     • 需要 CAP_BPF 或 root 权限                                  │
│     • 不同类型的程序有不同权限                                   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 1.4 eBPF vs strace vs perf

```bash
# strace 的问题：高开销
strace -c -p $(pgrep nginx) &
# CPU 可能增加 50-100%！生产环境禁用！

# perf 的问题：数据量大
perf record -F 999 -a -- sleep 60
# 会产生大量数据，需要后处理

# eBPF 的优势：内核内聚合
sudo biolatency-bpfcc
# 直方图在内核计算，只传输结果
# 开销 < 1%，生产安全
```

**开销对比**：

| 工具 | 典型开销 | 生产可用 |
|------|----------|----------|
| strace | 10-100x | 否 |
| perf record | 1-5% | 短期可用 |
| eBPF (BCC) | < 1% | 是 |

---

## Step 2 - 安装 BCC 工具（10 分钟）

### 2.1 Ubuntu/Debian 安装

```bash
# Ubuntu 22.04+ / Debian 11+
sudo apt update
sudo apt install -y bpfcc-tools linux-headers-$(uname -r)

# 可选：安装 bpftrace
sudo apt install -y bpftrace

# 验证安装
which execsnoop-bpfcc
# /usr/sbin/execsnoop-bpfcc

# 测试运行
sudo execsnoop-bpfcc --help
```

### 2.2 RHEL/CentOS/Rocky 安装

```bash
# RHEL 8+ / CentOS 8+ / Rocky 8+
sudo dnf install -y bcc-tools kernel-devel-$(uname -r)

# 可选：安装 bpftrace
sudo dnf install -y bpftrace

# RHEL 上的工具名称没有 -bpfcc 后缀
which execsnoop
# /usr/share/bcc/tools/execsnoop

# 添加到 PATH
echo 'export PATH=$PATH:/usr/share/bcc/tools' >> ~/.bashrc
source ~/.bashrc
```

### 2.3 验证内核支持

```bash
# 检查内核版本（需要 4.4+，推荐 5.x+）
uname -r

# 检查 BPF 支持
cat /boot/config-$(uname -r) | grep -E "CONFIG_BPF=|CONFIG_BPF_SYSCALL="
# 应该看到：
# CONFIG_BPF=y
# CONFIG_BPF_SYSCALL=y

# 检查 BTF 支持（CO-RE 需要，5.2+）
ls /sys/kernel/btf/vmlinux
# 如果存在，支持 CO-RE
```

### 2.4 常见问题排查

```bash
# 问题：找不到内核头文件
# 解决：
sudo apt install linux-headers-$(uname -r)  # Ubuntu
sudo dnf install kernel-devel-$(uname -r)   # RHEL

# 问题：BPF 程序加载失败
# 检查：
cat /proc/sys/kernel/unprivileged_bpf_disabled
# 如果是 1，需要 root 权限

# 问题：在容器中运行
# 需要特权容器或挂载 /sys/kernel/debug
docker run --privileged -v /sys/kernel/debug:/sys/kernel/debug ...
```

---

## Step 3 - BCC 工具决策矩阵（10 分钟）

### 3.1 BCC vs bpftrace vs libbpf

在选择 eBPF 工具时，理解三种主要方式的定位非常重要：

<!-- DIAGRAM: ebpf-tool-decision -->
```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    eBPF 工具选择决策矩阵                                      │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌────────────────────────────────────────────────────────────────────────┐│
│  │  BCC Tools（预编译工具）                                                 ││
│  │  ────────────────────────────────────────────────────────────────────  ││
│  │  适用场景：需要经过验证的、可靠的工具进行特定分析                         ││
│  │                                                                        ││
│  │  优势：                                                                 ││
│  │  • 久经生产验证（Battle-tested）                                        ││
│  │  • 无需编码，即开即用                                                   ││
│  │  • 输出格式友好，易于理解                                               ││
│  │                                                                        ││
│  │  示例工具：execsnoop, biolatency, tcpconnect, ext4slower               ││
│  │                                                                        ││
│  │  ★ Tier 3 运维首选（覆盖 90% 场景）                                     ││
│  └────────────────────────────────────────────────────────────────────────┘│
│                                                                             │
│  ┌────────────────────────────────────────────────────────────────────────┐│
│  │  bpftrace（一行脚本）                                                    ││
│  │  ────────────────────────────────────────────────────────────────────  ││
│  │  适用场景：快速 ad-hoc 调查，BCC 没有现成工具时                          ││
│  │                                                                        ││
│  │  优势：                                                                 ││
│  │  • 灵活，可快速定制                                                     ││
│  │  • 适合自定义聚合                                                       ││
│  │  • 快速原型验证                                                         ││
│  │                                                                        ││
│  │  示例：                                                                 ││
│  │  bpftrace -e 'kprobe:vfs_read { @[comm] = count(); }'                  ││
│  │                                                                        ││
│  │  ★ Tier 3 备选（BCC 没有的功能）                                        ││
│  └────────────────────────────────────────────────────────────────────────┘│
│                                                                             │
│  ┌────────────────────────────────────────────────────────────────────────┐│
│  │  libbpf / CO-RE（生产工具开发）                                          ││
│  │  ────────────────────────────────────────────────────────────────────  ││
│  │  适用场景：构建可移植的生产级监控工具                                     ││
│  │                                                                        ││
│  │  优势：                                                                 ││
│  │  • CO-RE 跨内核版本可移植                                               ││
│  │  • 最低运行时开销                                                       ││
│  │  • 生产级可靠性                                                         ││
│  │                                                                        ││
│  │  ★ Tier 4+ 专家领域（超出本课程范围）                                    ││
│  └────────────────────────────────────────────────────────────────────────┘│
│                                                                             │
│  ┌────────────────────────────────────────────────────────────────────────┐│
│  │  Tier 3 运维工程师的选择顺序：                                           ││
│  │                                                                        ││
│  │  1. 先用 BCC 预编译工具 → 90% 场景覆盖                                   ││
│  │  2. BCC 没有的 → bpftrace 一行脚本                                       ││
│  │  3. 需要自定义生产工具 → 学习 libbpf（超出本课范围）                      ││
│  └────────────────────────────────────────────────────────────────────────┘│
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```
<!-- /DIAGRAM -->

### 3.2 决策流程

```
需要追踪某个行为？
│
├─→ BCC 有现成工具吗？
│   ├─→ 有 → 使用 BCC 工具（execsnoop, biolatency 等）
│   │
│   └─→ 没有 → 需要自定义追踪？
│       ├─→ 临时调查 → bpftrace 一行脚本
│       │
│       └─→ 持续监控 → 考虑 libbpf（或找现成工具）
```

---

## Step 4 - Tier 1 核心 BCC 工具（25 分钟）

这 7 个工具是每个运维工程师必须掌握的：

### 4.1 execsnoop - 进程执行追踪

**用途**：追踪所有新进程执行，检测短命进程。

```bash
# 基本用法
sudo execsnoop-bpfcc

# 带时间戳
sudo execsnoop-bpfcc -t

# 只看特定命令
sudo execsnoop-bpfcc -n curl

# 输出示例
# TIME     PCOMM            PID    PPID   RET ARGS
# 14:30:01 curl             12345  12300    0 /usr/bin/curl http://example.com
# 14:30:01 sh               12346  12345    0 /bin/sh -c "date"
```

**场景：The Ghost Load（幽灵负载）**

```bash
# 症状：load average 很高，但 top 看不到什么进程
# 原因：可能是短命进程频繁 fork/exec

# 使用 execsnoop 检测
sudo execsnoop-bpfcc -t | tee ghost_processes.log

# 观察 1 分钟，统计哪个命令最多
awk '{print $2}' ghost_processes.log | sort | uniq -c | sort -rn | head -10
```

### 4.2 opensnoop - 文件打开追踪

**用途**：追踪所有文件打开操作，定位配置文件访问问题。

```bash
# 基本用法
sudo opensnoop-bpfcc

# 只看特定进程
sudo opensnoop-bpfcc -p $(pgrep nginx)

# 只看特定文件路径
sudo opensnoop-bpfcc -n /etc

# 输出示例
# PID    COMM               FD ERR PATH
# 12345  nginx               3   0 /etc/nginx/nginx.conf
# 12345  nginx               4   0 /var/log/nginx/access.log
# 12346  python             -1   2 /etc/missing.conf  # ERR=2 表示 ENOENT
```

**场景：配置文件问题定位**

```bash
# 应用启动失败，怀疑配置文件问题
sudo opensnoop-bpfcc -p $(pgrep myapp)

# 看到 ERR=2 (ENOENT) 的文件就是找不到的配置
```

### 4.3 biolatency - I/O 延迟直方图

**用途**：显示块设备 I/O 延迟分布，比 iostat 更直观。

```bash
# 基本用法（按 Ctrl+C 结束并显示结果）
sudo biolatency-bpfcc

# 以毫秒显示
sudo biolatency-bpfcc -m

# 按磁盘分组
sudo biolatency-bpfcc -D

# 每 5 秒输出一次
sudo biolatency-bpfcc 5

# 输出示例
#      usecs               : count     distribution
#          0 -> 1          : 0        |                                    |
#          2 -> 3          : 5        |*                                   |
#          4 -> 7          : 123      |*****                               |
#          8 -> 15         : 456      |********************                |
#         16 -> 31         : 1024     |****************************************|
#         32 -> 63         : 512      |********************                |
#         64 -> 127        : 128      |*****                               |
#        128 -> 255        : 32       |*                                   |
#        256 -> 511        : 8        |                                    |
#        512 -> 1023       : 2        |                                    |
```

**解读**：

- 大多数 I/O 在 16-31 微秒完成（健康的 SSD）
- 如果出现 1ms+ 的长尾，说明有延迟问题

### 4.4 tcpconnect - TCP 连接追踪

**用途**：追踪出站 TCP 连接，调试网络问题。

```bash
# 基本用法
sudo tcpconnect-bpfcc

# 带时间戳
sudo tcpconnect-bpfcc -t

# 只看特定端口
sudo tcpconnect-bpfcc -P 443

# 输出示例
# TIME     PID    COMM         IP SADDR            DADDR            DPORT
# 14:30:01 12345  curl         4  192.168.1.10     93.184.216.34    443
# 14:30:02 12346  python       4  192.168.1.10     10.0.0.5         5432
```

**配套工具**：

```bash
# tcpaccept - 追踪入站连接
sudo tcpaccept-bpfcc

# tcplife - 显示连接生命周期
sudo tcplife-bpfcc
```

### 4.5 profile - CPU 采样分析

**用途**：低开销 CPU 采样，可生成火焰图。

```bash
# 基本用法（采样 30 秒）
sudo profile-bpfcc -F 99 30

# 按进程分组
sudo profile-bpfcc -F 99 -p $(pgrep java) 30

# 输出折叠格式（用于火焰图）
sudo profile-bpfcc -F 99 -f 30 > profile.out

# 生成火焰图
cat profile.out | FlameGraph/flamegraph.pl > cpu.svg
```

**对比 perf**：

| 特性 | perf record | profile (BCC) |
|------|-------------|---------------|
| 开销 | 较高 | 很低 |
| 数据量 | 大（需后处理） | 小（内核聚合） |
| 生产可用 | 短期 | 持续运行 |

### 4.6 runqlat - 调度延迟直方图

**用途**：显示进程在运行队列中等待的时间，检测 CPU 饱和。

```bash
# 基本用法
sudo runqlat-bpfcc

# 以毫秒显示
sudo runqlat-bpfcc -m

# 每 5 秒输出一次
sudo runqlat-bpfcc 5

# 输出示例
#      usecs               : count     distribution
#          0 -> 1          : 10000    |****************************************|
#          2 -> 3          : 5000     |********************                    |
#          4 -> 7          : 2000     |********                                |
#          8 -> 15         : 500      |**                                      |
#         16 -> 31         : 100      |                                        |
#         32 -> 63         : 20       |                                        |
#         64 -> 127        : 5        |                                        |
```

**解读**：

- 大多数在 0-1 微秒：CPU 健康
- 出现 1ms+ 等待：CPU 可能饱和

### 4.7 offcputime - Off-CPU 分析

**用途**：追踪进程阻塞（Off-CPU）时间，定位等待/锁问题。

```bash
# 追踪特定进程 30 秒
sudo offcputime-bpfcc -p $(pgrep java) 30

# 输出折叠格式（用于 Off-CPU 火焰图）
sudo offcputime-bpfcc -f -p $(pgrep java) 30 > offcpu.out

# 生成 Off-CPU 火焰图
cat offcpu.out | FlameGraph/flamegraph.pl --color=io > offcpu.svg
```

**场景：eBPF Off-CPU Wait Analysis（Codex 实验）**

```bash
# 症状：CPU 不高但延迟大，怀疑锁竞争

# 1. 用 offcputime 收集阻塞时间
sudo offcputime-bpfcc -f -p $(pgrep myapp) 60 > offcpu.out

# 2. 生成 Off-CPU 火焰图
cat offcpu.out | FlameGraph/flamegraph.pl --color=io > offcpu.svg

# 3. 在火焰图中查找：
#    - futex_wait：锁等待
#    - read/write：I/O 等待
#    - nanosleep：sleep 等待
```

---

## Step 5 - Tier 2 推荐 BCC 工具（15 分钟）

这 3 个工具在 障害対応 场景特别有用（Gemini 强烈推荐）：

### 5.1 ext4slower / xfs_slower - 文件系统延迟

**用途**：追踪慢文件系统操作（iostat 看不到的层面）。

```bash
# ext4 文件系统，显示 > 10ms 的操作
sudo ext4slower-bpfcc 10

# xfs 文件系统
sudo xfs_slower-bpfcc 10

# 输出示例
# TIME     COMM           PID    T BYTES   OFF_KB   LAT(ms) FILENAME
# 14:30:01 mysqld         12345  W 16384   102400   125.3   ibdata1
# 14:30:02 logrotate      12346  S 0       0        89.7    access.log
```

**为什么需要这个工具？**

```
iostat 显示：%util = 20%，await = 5ms
但应用报告：写入延迟 100ms+

原因：文件系统层面的问题（journaling、fsync、锁）
iostat 只能看到块设备层面

ext4slower 可以看到：
- T=S（fsync）导致的延迟
- 特定文件的高延迟
```

### 5.2 cachestat - 页缓存命中率

**用途**：显示页缓存效率，验证内存使用是否有效。

```bash
# 每秒输出一次
sudo cachestat-bpfcc 1

# 输出示例
#    HITS   MISSES  DIRTIES HITRATIO   BUFFERS_MB  CACHED_MB
#   12345      100       50    99.19%        100       4096
#   11000      500       30    95.65%        100       4096
#    5000     5000       20    50.00%        100       4096  # 命中率下降！
```

**解读**：

- HITRATIO > 95%：页缓存工作良好
- HITRATIO < 80%：工作集超出内存，性能下降

### 5.3 tcpretrans - TCP 重传追踪

**用途**：追踪 TCP 重传，检测网络质量问题。

```bash
# 基本用法
sudo tcpretrans-bpfcc

# 输出示例
# TIME     PID    IP LADDR:LPORT          T> RADDR:RPORT          STATE
# 14:30:01 12345  4  192.168.1.10:45678   R> 10.0.0.5:443         ESTABLISHED
# 14:30:02 12346  4  192.168.1.10:45679   R> 10.0.0.5:443         ESTABLISHED
```

**解读**：

- 偶尔的重传是正常的
- 持续的重传表示网络问题（丢包、拥塞）
- T 列：R = 重传，L = TLP（尾部丢失探测）

---

## Step 6 - bpftrace 一行脚本入门（10 分钟）

### 6.1 bpftrace 简介

bpftrace 是 eBPF 的"AWK"—— 适合快速编写一行追踪脚本。

```bash
# 安装
sudo apt install -y bpftrace  # Ubuntu
sudo dnf install -y bpftrace  # RHEL

# 验证
bpftrace --version
```

### 6.2 常用一行脚本

```bash
# 统计系统调用
sudo bpftrace -e 'tracepoint:raw_syscalls:sys_enter { @[comm] = count(); }'

# 追踪文件打开
sudo bpftrace -e 'tracepoint:syscalls:sys_enter_openat { printf("%s %s\n", comm, str(args->filename)); }'

# 统计 VFS 读取
sudo bpftrace -e 'kprobe:vfs_read { @[comm] = count(); }'

# I/O 大小直方图
sudo bpftrace -e 'tracepoint:block:block_rq_issue { @bytes = hist(args->bytes); }'

# 追踪进程退出
sudo bpftrace -e 'tracepoint:sched:sched_process_exit { printf("%s (%d) exited\n", comm, pid); }'
```

### 6.3 bpftrace vs BCC 选择

| 场景 | 选择 |
|------|------|
| 需要 biolatency 直方图 | BCC（现成工具） |
| 需要追踪自定义函数 | bpftrace（灵活） |
| 生产环境持续监控 | BCC（更稳定） |
| 临时调查特定问题 | bpftrace（快速） |

---

## Step 7 - 何时使用 eBPF vs 传统工具（10 分钟）

### 7.1 工具选择决策树

<!-- DIAGRAM: tool-decision-tree -->
```
┌─────────────────────────────────────────────────────────────────────────────┐
│                     eBPF vs 传统工具决策树                                    │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  需要追踪什么？                                                               │
│  │                                                                          │
│  ├─→ CPU 使用率                                                              │
│  │   ├─→ 概览 → top / htop                                                   │
│  │   ├─→ 采样分析 → perf record（短期）                                       │
│  │   └─→ 持续低开销采样 → profile (BCC) ✓                                    │
│  │                                                                          │
│  ├─→ I/O 延迟                                                                │
│  │   ├─→ 设备级延迟 → iostat                                                 │
│  │   └─→ 延迟分布 / 文件系统级 → biolatency, ext4slower (BCC) ✓              │
│  │                                                                          │
│  ├─→ 系统调用                                                                │
│  │   ├─→ 单进程调试（非生产） → strace                                        │
│  │   └─→ 生产环境追踪 → opensnoop, execsnoop (BCC) ✓                         │
│  │                                                                          │
│  ├─→ 网络连接                                                                │
│  │   ├─→ 当前连接状态 → ss                                                   │
│  │   └─→ 连接追踪 → tcpconnect, tcplife (BCC) ✓                              │
│  │                                                                          │
│  ├─→ 进程等待/阻塞                                                           │
│  │   ├─→ 无法用传统工具                                                      │
│  │   └─→ 必须用 eBPF → offcputime, runqlat (BCC) ✓                          │
│  │                                                                          │
│  └─→ 短命进程                                                                │
│      ├─→ 无法用传统工具（进程太快消失）                                       │
│      └─→ 必须用 eBPF → execsnoop (BCC) ✓                                     │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```
<!-- /DIAGRAM -->

### 7.2 场景对照表

| 场景 | 传统工具 | eBPF 工具 | 何时用 eBPF |
|------|----------|-----------|-------------|
| CPU 概览 | top, htop | - | 不需要 |
| CPU 采样 | perf record | profile | 生产环境持续采样 |
| 内存概览 | free, vmstat | - | 不需要 |
| 内存压力 | PSI | - | 不需要 |
| I/O 概览 | iostat | - | 不需要 |
| I/O 延迟分布 | - | biolatency | 需要直方图 |
| 文件系统延迟 | - | ext4slower | iostat 正常但应用慢 |
| 系统调用追踪 | strace | opensnoop | 生产环境 |
| 新进程追踪 | - | execsnoop | 短命进程问题 |
| TCP 连接追踪 | - | tcpconnect | 需要连接追踪 |
| Off-CPU 分析 | - | offcputime | 阻塞/锁问题 |
| 调度延迟 | - | runqlat | CPU 饱和分析 |

### 7.3 eBPF 不适用的场景

```
❌ 不需要 eBPF：
- 简单的资源概览（top, free, iostat 足够）
- 快速进程调试（strace 更方便，非生产）
- 网络连接状态（ss 足够）
- 内存压力检测（PSI 足够）

✓ 必须用 eBPF：
- 生产环境持续追踪（strace 开销太大）
- 短命进程问题（传统工具看不到）
- 延迟分布分析（需要直方图）
- Off-CPU 分析（没有传统替代品）
- 文件系统级问题（iostat 看不到）
```

---

## Step 8 - BCC 工具速查表

### 8.1 Tier 1 必备工具（7 个）

```bash
# =============================================================================
# BCC 工具速查表 - Tier 1 必备
# =============================================================================

# 1. execsnoop - 追踪新进程执行
sudo execsnoop-bpfcc              # 基本用法
sudo execsnoop-bpfcc -t           # 带时间戳
sudo execsnoop-bpfcc -n curl      # 只看特定命令

# 2. opensnoop - 追踪文件打开
sudo opensnoop-bpfcc              # 基本用法
sudo opensnoop-bpfcc -p PID       # 特定进程
sudo opensnoop-bpfcc -x           # 只显示失败的打开

# 3. biolatency - I/O 延迟直方图
sudo biolatency-bpfcc             # 基本用法，Ctrl+C 结束
sudo biolatency-bpfcc -m          # 以毫秒显示
sudo biolatency-bpfcc -D          # 按磁盘分组
sudo biolatency-bpfcc 5           # 每 5 秒输出

# 4. tcpconnect - TCP 连接追踪
sudo tcpconnect-bpfcc             # 出站连接
sudo tcpconnect-bpfcc -t          # 带时间戳
sudo tcpconnect-bpfcc -P 443      # 只看特定端口

# 5. profile - CPU 采样
sudo profile-bpfcc -F 99 30       # 99 Hz 采样 30 秒
sudo profile-bpfcc -p PID 30      # 特定进程
sudo profile-bpfcc -f 30 > p.out  # 折叠格式（火焰图）

# 6. runqlat - 调度延迟直方图
sudo runqlat-bpfcc                # 基本用法
sudo runqlat-bpfcc -m             # 毫秒
sudo runqlat-bpfcc 5              # 每 5 秒输出

# 7. offcputime - Off-CPU 分析
sudo offcputime-bpfcc -p PID 30   # 特定进程 30 秒
sudo offcputime-bpfcc -f 30       # 折叠格式（火焰图）
```

### 8.2 Tier 2 推荐工具（3 个）

```bash
# =============================================================================
# BCC 工具速查表 - Tier 2 推荐（障害対応利器）
# =============================================================================

# 1. ext4slower / xfs_slower - 文件系统延迟
sudo ext4slower-bpfcc 10          # ext4，显示 > 10ms 操作
sudo xfs_slower-bpfcc 10          # xfs
sudo btrfs_slower-bpfcc 10        # btrfs

# 2. cachestat - 页缓存命中率
sudo cachestat-bpfcc              # 基本用法
sudo cachestat-bpfcc 1            # 每秒输出
sudo cachestat-bpfcc 1 10         # 每秒，共 10 次

# 3. tcpretrans - TCP 重传
sudo tcpretrans-bpfcc             # 基本用法
sudo tcpretrans-bpfcc -l          # 包含 TLP
```

### 8.3 其他常用工具

```bash
# =============================================================================
# BCC 工具速查表 - 其他常用
# =============================================================================

# 网络
sudo tcpaccept-bpfcc              # 入站连接
sudo tcplife-bpfcc                # 连接生命周期
sudo tcptop-bpfcc                 # TCP 流量 top

# 磁盘
sudo biotop-bpfcc                 # I/O top
sudo bitesize-bpfcc               # I/O 大小直方图

# 内存
sudo memleak-bpfcc -p PID         # 内存泄漏检测
sudo oomkill-bpfcc                # OOM kill 追踪

# 文件系统
sudo filetop-bpfcc                # 文件 I/O top
sudo fileslower-bpfcc 10          # 慢文件操作

# 调度
sudo cpudist-bpfcc                # CPU 使用时间分布
sudo wakeuptime-bpfcc             # 唤醒延迟
```

---

## Step 9 - 实战练习（20 分钟）

### 练习 1：The Ghost Load（幽灵负载）

**场景**：load average 很高（> 4.0），但 top 显示 CPU 90% idle。

```bash
# 1. 确认症状
uptime
# load average: 5.50, 4.20, 3.80

top -bn1 | head -5
# %Cpu(s):  5.0 us,  2.0 sy,  0.0 ni, 90.0 id, 3.0 wa, ...
# 奇怪：负载高但 CPU 空闲？

# 2. 使用 execsnoop 追踪短命进程
sudo execsnoop-bpfcc -t | tee ghost.log &

# 等待 60 秒
sleep 60
kill %1

# 3. 分析哪个命令最频繁
awk '{print $2}' ghost.log | sort | uniq -c | sort -rn | head -10

# 可能发现：
#  1500 curl
#   800 sh
#   500 date
# 结论：监控脚本在循环执行 curl

# 4. 找到罪魁祸首
grep curl ghost.log | head -5
# 看 PPID 列，追踪到父进程
ps -p <PPID> -o pid,ppid,cmd
```

### 练习 2：eBPF Off-CPU Wait Analysis

**场景**：CPU 使用率不高，但应用响应延迟大。

```bash
# 1. 确认 CPU 不是瓶颈
top -bn1 | head -5
# CPU 使用率 30%，不是 CPU 问题

# 2. 怀疑阻塞/锁问题，使用 offcputime
sudo offcputime-bpfcc -f -p $(pgrep myapp) 60 > offcpu.out

# 3. 生成 Off-CPU 火焰图
git clone https://github.com/brendangregg/FlameGraph
cat offcpu.out | ./FlameGraph/flamegraph.pl --color=io > offcpu.svg

# 4. 在浏览器中打开 offcpu.svg 分析
# 寻找：
# - futex_wait：锁等待
# - do_poll / select：I/O 等待
# - nanosleep：sleep

# 5. 同时检查调度延迟
sudo runqlat-bpfcc 5
# 如果出现 ms 级延迟，CPU 可能饱和
```

### 练习 3：I/O 延迟深入分析

**场景**：iostat %util 很低，但应用报告 I/O 慢。

```bash
# 1. iostat 显示正常
iostat -x 1 3
# %util = 15%, await = 3ms，看起来正常

# 2. 但应用日志显示写入延迟 > 100ms
grep "slow write" /var/log/myapp/app.log

# 3. 使用 ext4slower 看文件系统层延迟
sudo ext4slower-bpfcc 10  # 显示 > 10ms 的操作

# 可能看到：
# TIME     COMM           PID    T BYTES   LAT(ms) FILENAME
# 14:30:01 myapp          12345  S 0       156.3   data.db
# T=S 表示 fsync！

# 4. 结论：不是块设备慢，是 fsync 导致的延迟

# 5. 进一步分析
sudo biolatency-bpfcc 5
# 看 I/O 延迟分布，确认是否有长尾
```

---

## 职场小贴士（Japan IT Context）

### 本番環境での低オーバーヘッド調査

在日本 IT 企业的生产环境中，最重要的原则是 **本番への影響を最小限に抑える**（最小化对生产的影响）。

| 日语术语 | 读音 | 含义 | eBPF 相关 |
|----------|------|------|-----------|
| 本番環境 | ほんばんかんきょう | Production environment | BCC 工具可安全使用 |
| 低オーバーヘッド | ていオーバーヘッド | Low overhead | eBPF 开销 < 1% |
| 障害調査 | しょうがいちょうさ | Incident investigation | execsnoop, biolatency |
| 再現テスト | さいげんテスト | Reproduction test | 可以在生产复现问题 |
| エビデンス | エビデンス | Evidence | BCC 工具输出作为证据 |

### 工具使用报告示例

```markdown
## 障害調査報告書

### 調査日時
2026-01-10 14:30 JST

### 使用ツール
- execsnoop-bpfcc（プロセス追跡）
- biolatency-bpfcc（I/O レイテンシ）

### オーバーヘッド
- CPU 影響: < 1%
- 本番適用: 可能

### 調査結果
execsnoop により、短命プロセス（curl）が毎秒 50 回実行されていることを確認。
監視スクリプトの設定誤りが原因と特定。

### 対策
監視間隔を 1 秒から 60 秒に変更。
```

### eBPF vs strace の選択

```
運用チーム向けガイドライン：

✓ BCC ツール（本番 OK）
  - execsnoop: プロセス追跡
  - biolatency: I/O レイテンシ
  - tcpconnect: 接続追跡
  - オーバーヘッド < 1%

✗ strace（本番 NG）
  - 高オーバーヘッド（10-100x）
  - プロセスが大幅に遅くなる
  - 開発環境でのみ使用
```

---

## 面试准备（Interview Prep）

### Q1: eBPF と strace の違いは？

**回答要点**：

```
eBPF と strace は目的は似ていますが、実装が大きく異なります。

strace:
- ユーザー空間で ptrace を使用
- 高オーバーヘッド（10-100x 遅くなる可能性）
- 本番環境では使用不可

eBPF:
- カーネル内で実行
- 低オーバーヘッド（< 1%）
- 本番環境で安全に使用可能
- Netflix, Facebook, Google で使用されている

本番で syscall 追跡が必要な場合は、
strace ではなく BCC の opensnoop や execsnoop を使います。
```

### Q2: eBPF が安全な理由は？

**回答要点**：

```
eBPF は Verifier によって安全性が保証されます。

1. 無限ループ禁止
   - プログラムは必ず終了する
   - ループ回数に上限がある

2. メモリアクセス制限
   - 境界チェックを通過しないとアクセス不可
   - カーネルクラッシュを防止

3. 命令数制限
   - プログラムの複雑度に上限
   - リソース枯渇を防止

4. サンドボックス実行
   - 任意のカーネル関数を呼べない
   - 許可された操作のみ

これにより、カーネルモジュールと違い、
eBPF プログラムがカーネルをクラッシュさせることはありません。
```

### Q3: BCC と bpftrace の使い分けは？

**回答要点**：

```
Tier 3 運用エンジニアの選択基準：

BCC ツールを優先（90% のケース）:
- 検証済みの信頼性
- 即座に使用可能
- 例: execsnoop, biolatency, tcpconnect

bpftrace を使用（BCC にない場合）:
- カスタム追跡が必要
- アドホック調査
- 例: 特定のカーネル関数を追跡

libbpf（Tier 4+ 専門家向け）:
- 本番ツール開発
- CO-RE による移植性
- 本コースの範囲外
```

---

## 检查清单

完成本课后，你应该能够：

- [ ] 解释 eBPF 是什么以及为什么它比 strace 更适合生产环境
- [ ] 解释 eBPF Verifier 如何保证安全性
- [ ] 在 Ubuntu 和 RHEL 上安装 BCC 工具
- [ ] 使用 execsnoop 追踪新进程执行
- [ ] 使用 opensnoop 追踪文件打开
- [ ] 使用 biolatency 查看 I/O 延迟分布
- [ ] 使用 tcpconnect 追踪 TCP 连接
- [ ] 使用 profile 进行 CPU 采样
- [ ] 使用 runqlat 检测调度延迟
- [ ] 使用 offcputime 进行 Off-CPU 分析
- [ ] 区分 BCC、bpftrace、libbpf 的使用场景
- [ ] 判断何时应该使用 eBPF vs 传统工具
- [ ] 使用 ext4slower 检测文件系统延迟
- [ ] 使用 cachestat 检测页缓存效率
- [ ] 使用 tcpretrans 检测 TCP 重传
- [ ] 编写简单的 bpftrace 一行脚本

---

## 本课小结

| 概念 | 要点 |
|------|------|
| eBPF | 内核内安全的可编程追踪，低开销，生产可用 |
| Verifier | 保证 eBPF 程序安全性：无无限循环、无越界访问 |
| BCC Tools | 预编译工具集，Tier 3 首选 |
| bpftrace | 一行脚本，BCC 没有时的备选 |
| Tier 1 工具 | execsnoop, opensnoop, biolatency, tcpconnect, profile, runqlat, offcputime |
| Tier 2 工具 | ext4slower, cachestat, tcpretrans |
| 使用时机 | 生产环境追踪、短命进程、延迟分布、Off-CPU 分析 |

---

## 延伸阅读

- [Brendan Gregg 的 BPF Performance Tools](https://www.brendangregg.com/bpf-performance-tools-book.html)
- [BCC GitHub 仓库](https://github.com/iovisor/bcc)
- [bpftrace GitHub 仓库](https://github.com/iovisor/bpftrace)
- [Linux eBPF 文档](https://docs.kernel.org/bpf/)
- 前置课程：[08 - Flamegraphs](../08-flamegraphs/) - 必须先掌握火焰图解读
- 综合项目：[Capstone - 完整性能审计](../capstone/) - 综合应用所有技能

---

## 系列导航

[<-- 09 - 内核调优](../09-kernel-tuning/) | [系列首页](../) | [Capstone 综合项目 -->](../capstone/)
