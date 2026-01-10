# 04 - I/O 分析（I/O Analysis）

> **目标**：掌握磁盘 I/O 性能分析技能，使用 iostat、iotop、pidstat 等工具定位 I/O 瓶颈  
> **前置**：Lesson 01 USE Method、Lesson 03 Memory Analysis  
> **时间**：⚡ 20 分钟（速读）/ 🔬 75 分钟（完整实操）  
> **实战场景**：深夜のディスクスパイク調査、I/O bound 问题诊断  

---

## 将学到的内容

1. 理解磁盘 I/O 基础（Sequential vs Random、IOPS vs Throughput）
2. 使用 iostat -x 分析磁盘性能核心指标
3. 使用 iotop 定位 I/O 消耗进程
4. 使用 pidstat -d 追踪进程 I/O
5. 使用 PSI io 检测 I/O 压力
6. 了解 I/O 调度器（mq-deadline, bfq, none）
7. 了解 blktrace/blkparse 高级追踪（进阶）

---

## 先跑起来！（5 分钟）

> 在深入 I/O 理论之前，先捕获系统的 I/O 快照。  
> 运行这些命令，观察输出 - 这就是你将要系统化理解的技能。  

```bash
# 磁盘 I/O 扩展统计（最重要的工具）
iostat -x 1 3

# PSI I/O 压力（现代内核 4.20+）
cat /proc/pressure/io

# 查看哪些进程在做 I/O（需要 root）
sudo iotop -o -b -n 3

# 查看当前 I/O 调度器
cat /sys/block/sda/queue/scheduler 2>/dev/null || \
cat /sys/block/nvme0n1/queue/scheduler 2>/dev/null || \
cat /sys/block/vda/queue/scheduler
```

**你刚刚捕获了系统的 I/O 快照！**

- `iostat -x` 显示每个磁盘设备的详细 I/O 指标
- `PSI io` 告诉你系统是否因 I/O 而"感到压力"
- `iotop` 显示哪些进程在消耗 I/O
- `scheduler` 显示内核如何调度 I/O 请求

**但这些数字意味着什么？%util 95% 是好是坏？await 30ms 正常吗？**

让我们从 I/O 基础开始理解。

---

## Step 1 - 磁盘 I/O 基础（10 分钟）

### 1.1 存储层次结构

<!-- DIAGRAM: storage-hierarchy -->
```
┌─────────────────────────────────────────────────────────────────────┐
│                      存储层次结构                                    │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│    应用程序                                                          │
│        ↓                                                            │
│    ┌─────────────────────────────────────────────────────────────┐  │
│    │  Page Cache（页缓存）                                        │  │
│    │  内存中缓存磁盘数据，读写都经过这里                           │  │
│    └─────────────────────────────────────────────────────────────┘  │
│        ↓ cache miss 或 sync/flush                                  │
│    ┌─────────────────────────────────────────────────────────────┐  │
│    │  Block Layer（块层）                                          │  │
│    │  I/O 调度器在这里决定请求顺序                                 │  │
│    └─────────────────────────────────────────────────────────────┘  │
│        ↓                                                            │
│    ┌─────────────────────────────────────────────────────────────┐  │
│    │  Device Driver（设备驱动）                                    │  │
│    │  与硬件通信                                                   │  │
│    └─────────────────────────────────────────────────────────────┘  │
│        ↓                                                            │
│    ┌─────────────────────────────────────────────────────────────┐  │
│    │  Physical Device（物理设备）                                  │  │
│    │  HDD / SSD / NVMe                                             │  │
│    └─────────────────────────────────────────────────────────────┘  │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```
<!-- /DIAGRAM -->

**关键理解**：

- 大多数读操作被 Page Cache 拦截（cache hit），不会到达磁盘
- 写操作默认先写入 Page Cache，由内核异步刷盘
- `iostat` 显示的是 **到达块设备层** 的 I/O，不是应用层 I/O

### 1.2 顺序 I/O vs 随机 I/O

<!-- DIAGRAM: sequential-vs-random -->
```
┌─────────────────────────────────────────────────────────────────────┐
│              Sequential I/O vs Random I/O                           │
├────────────────────────────────┬────────────────────────────────────┤
│        Sequential I/O          │          Random I/O                │
│        （顺序 I/O）             │         （随机 I/O）               │
├────────────────────────────────┼────────────────────────────────────┤
│                                │                                    │
│  ┌──┬──┬──┬──┬──┬──┬──┬──┐    │  ┌──┬──┬──┬──┬──┬──┬──┬──┐        │
│  │1 │2 │3 │4 │5 │6 │7 │8 │    │  │1 │  │3 │  │  │6 │  │8 │        │
│  └──┴──┴──┴──┴──┴──┴──┴──┘    │  └──┴──┴──┴──┴──┴──┴──┴──┘        │
│        ─────────────►         │    ↑  ↑     ↑     ↑                │
│    连续读取/写入               │    跳跃访问不同位置                 │
│                                │                                    │
├────────────────────────────────┼────────────────────────────────────┤
│  典型场景：                     │  典型场景：                        │
│  • 日志写入                    │  • 数据库查询                      │
│  • 视频流媒体                  │  • 虚拟机磁盘                      │
│  • 备份/恢复                   │  • 邮件服务器                      │
│  • 大文件复制                  │  • Web 服务器（小文件）            │
│                                │                                    │
├────────────────────────────────┼────────────────────────────────────┤
│  HDD 性能：                    │  HDD 性能：                        │
│  ~150-200 MB/s                 │  ~0.5-2 MB/s（受寻道限制）         │
│  IOPS 不重要                   │  ~100-200 IOPS                     │
│                                │                                    │
│  SSD 性能：                    │  SSD 性能：                        │
│  ~500-3500 MB/s                │  ~50,000-500,000 IOPS              │
│  SSD 随机和顺序差异小          │  随机性能优势明显                   │
│                                │                                    │
└────────────────────────────────┴────────────────────────────────────┘
```
<!-- /DIAGRAM -->

### 1.3 IOPS vs Throughput

| 指标 | 含义 | 重要场景 |
|------|------|----------|
| **IOPS** | I/O Operations Per Second（每秒 I/O 操作数）| 数据库、随机小文件访问 |
| **Throughput** | MB/s（每秒传输字节数）| 大文件传输、流媒体、备份 |

**经验法则**：

```
IOPS × 平均 I/O 大小 ≈ Throughput

例：10,000 IOPS × 4KB = 40 MB/s
例：100 IOPS × 1MB = 100 MB/s
```

### 1.4 读 vs 写的差异

| 操作 | 特点 | 对性能的影响 |
|------|------|--------------|
| **Read** | 可以被 Page Cache 命中 | Cache hit 时几乎无延迟 |
| **Write** | 默认异步（写入 cache 后返回）| 对应用延迟影响小 |
| **Sync Write** | 必须等待数据落盘 | 延迟 = 物理磁盘延迟 |
| **fsync/O_SYNC** | 强制刷盘 | 数据库常用，影响性能 |

---

## Step 2 - iostat 核心指标详解（15 分钟）

### 2.1 iostat 基本使用

```bash
# 基本用法
iostat -x 1        # 扩展统计，每秒刷新

# 排除零活动设备（更清晰）
iostat -xz 1

# 指定设备
iostat -x sda 1

# 显示 MB/s 而非扇区
iostat -xm 1

# 实际推荐组合
iostat -xz 1 5     # 扩展统计，排除闲置设备，每秒刷新，共 5 次
```

### 2.2 iostat -x 输出详解

```bash
$ iostat -x 1
Device  r/s  w/s  rkB/s  wkB/s  rrqm/s  wrqm/s  %rrqm  %wrqm  r_await  w_await  aqu-sz  rareq-sz  wareq-sz  svctm  %util
sda    50   100    400    800     5       20      9.1   16.7      2.5      5.0    0.75       8.0       8.0    1.5   22.5
```

### 2.3 核心指标解读

<!-- DIAGRAM: iostat-metrics -->
```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        iostat -x 核心指标                                    │
├──────────────┬──────────────────────────────────────────────────────────────┤
│    指标       │              含义与阈值                                      │
├──────────────┼──────────────────────────────────────────────────────────────┤
│              │                                                              │
│   r/s        │  每秒读操作数（Read IOPS）                                   │
│   w/s        │  每秒写操作数（Write IOPS）                                  │
│              │  合计 = 总 IOPS，数据库场景重点关注                          │
│              │                                                              │
├──────────────┼──────────────────────────────────────────────────────────────┤
│              │                                                              │
│   rkB/s      │  每秒读取 KB 数（Read Throughput）                           │
│   wkB/s      │  每秒写入 KB 数（Write Throughput）                          │
│              │  大文件传输场景重点关注                                       │
│              │                                                              │
├──────────────┼──────────────────────────────────────────────────────────────┤
│              │                                                              │
│   %util      │  ⭐ 设备繁忙程度（Utilization）                              │
│              │                                                              │
│              │  解读：                                                      │
│              │  • < 70%：设备空闲，有余量                                   │
│              │  • 70-90%：较忙，需要关注                                    │
│              │  • > 90%：接近饱和                                           │
│              │  • 100%：设备满载                                            │
│              │                                                              │
│              │  ⚠️  注意：对于 SSD/NVMe，%util 可能不准确                   │
│              │  因为它们支持并行处理多个请求                                 │
│              │                                                              │
├──────────────┼──────────────────────────────────────────────────────────────┤
│              │                                                              │
│   await      │  ⭐ 平均 I/O 等待时间（ms）- 最重要的延迟指标                │
│              │                                                              │
│              │  阈值建议：                                                  │
│              │  • HDD：< 20ms 正常，> 50ms 需要关注                         │
│              │  • SSD：< 5ms 正常，> 10ms 需要关注                          │
│              │  • NVMe：< 1ms 正常，> 3ms 需要关注                          │
│              │                                                              │
│   r_await    │  读操作平均等待时间                                          │
│   w_await    │  写操作平均等待时间                                          │
│              │                                                              │
├──────────────┼──────────────────────────────────────────────────────────────┤
│              │                                                              │
│   aqu-sz     │  ⭐ 平均 I/O 队列深度（Saturation 指标）                     │
│   (avgqu-sz) │                                                              │
│              │  解读：                                                      │
│              │  • < 1：请求即时处理，无排队                                 │
│              │  • 1-4：有少量排队，正常范围                                 │
│              │  • > 4：明显排队，可能是瓶颈                                 │
│              │  • > 8：严重排队，I/O 饱和                                   │
│              │                                                              │
├──────────────┼──────────────────────────────────────────────────────────────┤
│              │                                                              │
│   rrqm/s     │  每秒合并的读请求数（Request Merge）                         │
│   wrqm/s     │  每秒合并的写请求数                                          │
│              │  高合并率 = 顺序 I/O 效率高                                  │
│              │                                                              │
└──────────────┴──────────────────────────────────────────────────────────────┘
```
<!-- /DIAGRAM -->

### 2.4 USE Method 应用于 Disk I/O

根据 Lesson 01 学习的 USE Method：

```bash
# U - Utilization（利用率）
iostat -xz 1 3 | awk '/sd|nvme|vd/ {print $1, "%util:", $NF}'

# S - Saturation（饱和度）
iostat -xz 1 3 | awk '/sd|nvme|vd/ {print $1, "aqu-sz:", $(NF-5), "await:", $(NF-3)}'

# E - Errors
dmesg | grep -i "I/O error\|medium error\|disk error" | tail -5

# PSI I/O Pressure（现代方式）
cat /proc/pressure/io
```

### 2.5 常见 iostat 输出模式分析

**模式 1：I/O 饱和**

```
Device   r/s   w/s   rkB/s   wkB/s   await   aqu-sz   %util
sda      500   200    4000    1600      85      12      99
```

解读：
- `%util = 99%`：设备满载
- `await = 85ms`：延迟非常高（HDD 正常 < 20ms）
- `aqu-sz = 12`：严重排队

**模式 2：随机 I/O 压力**

```
Device   r/s   w/s   rkB/s   wkB/s   await   aqu-sz   %util
sda     1500    50    6000     200      15       4      85
```

解读：
- 高 IOPS（1500 r/s）+ 低 throughput（6 MB/s）= 随机小 I/O
- 可能是数据库随机读取

**模式 3：顺序写入（日志/备份）**

```
Device   r/s   w/s   rkB/s   wkB/s   await   aqu-sz   %util
sda       5   100     40   102400       3       1      45
```

解读：
- 低 IOPS + 高 throughput = 顺序大块写入
- `await = 3ms` + `aqu-sz = 1`：I/O 正常

---

## Step 3 - iotop：定位 I/O 消耗进程（10 分钟）

### 3.1 iotop 基本使用

```bash
# 需要 root 权限
sudo iotop

# 仅显示有 I/O 活动的进程（推荐）
sudo iotop -o

# 批量模式（适合脚本/日志）
sudo iotop -o -b -n 5

# 仅显示进程（不显示线程）
sudo iotop -o -P

# 累积模式（显示自启动以来的总 I/O）
sudo iotop -a
```

### 3.2 iotop 输出解读

```
Total DISK READ:       5.00 M/s | Total DISK WRITE:      10.00 M/s
Current DISK READ:     3.00 M/s | Current DISK WRITE:     8.00 M/s
    TID  PRIO  USER     DISK READ  DISK WRITE  SWAPIN     IO>    COMMAND
   1234 be/4  mysql       3.00 M/s    5.00 M/s  0.00 %  75.00 % mysqld
   5678 be/4  root        2.00 M/s    3.00 M/s  0.00 %  60.00 % rsync
    999 be/4  www-data    0.00 B/s    2.00 M/s  0.00 %  20.00 % php-fpm
```

| 列 | 含义 |
|------|------|
| `TID` | 线程 ID（-P 时为 PID）|
| `PRIO` | I/O 优先级（be = best effort）|
| `DISK READ` | 实际读取速率 |
| `DISK WRITE` | 实际写入速率 |
| `SWAPIN` | 从 swap 读入的时间百分比 |
| `IO>` | 等待 I/O 的时间百分比（关键！）|

### 3.3 iotop 快捷键

| 按键 | 功能 |
|------|------|
| `o` | 仅显示活动进程（toggle） |
| `p` | 显示进程/线程切换 |
| `a` | 累积/当前模式切换 |
| `r` | 反向排序 |
| `左/右` | 切换排序列 |
| `q` | 退出 |

### 3.4 实战：定位 I/O 消耗者

```bash
# 场景：系统变慢，怀疑 I/O 问题

# Step 1: 确认是否 I/O 问题
cat /proc/pressure/io
# 如果 some avg10 > 10%，确认 I/O 压力

# Step 2: 用 iotop 找到消耗者
sudo iotop -o -P -b -n 3 | head -20

# Step 3: 追踪特定进程的详细 I/O
# 假设发现 PID 1234 是 top consumer
sudo pidstat -d -p 1234 1 5
```

---

## Step 4 - pidstat -d：进程级 I/O 追踪（5 分钟）

### 4.1 pidstat -d 基本使用

```bash
# 所有进程的 I/O 统计
pidstat -d 1

# 特定进程
pidstat -d -p 1234 1

# 包含子进程（-T ALL）
pidstat -d -T ALL -p 1234 1

# 输出 CPU 和 I/O 一起看
pidstat -u -d 1
```

### 4.2 pidstat -d 输出解读

```
$ pidstat -d 1

08:30:01 AM   UID       PID   kB_rd/s   kB_wr/s kB_ccwr/s iodelay  Command
08:30:02 AM  1000      1234    500.00   1000.00      0.00      50  mysqld
08:30:02 AM     0      5678   2000.00      0.00      0.00       5  rsync
```

| 列 | 含义 |
|------|------|
| `kB_rd/s` | 每秒读取 KB |
| `kB_wr/s` | 每秒写入 KB |
| `kB_ccwr/s` | 被取消的写入 KB（写入后被截断）|
| `iodelay` | **I/O 等待延迟（clock ticks）** - 非常有用！|

### 4.3 iodelay 指标的价值

`iodelay` 是 pidstat 特有的指标，表示进程因 I/O 等待而被阻塞的时间。

```bash
# 找出 I/O 等待最多的进程
pidstat -d 1 10 | awk '$NF!="Command" && $7>0 {print}' | sort -k7 -nr | head
```

**iodelay 解读**：

- `0-10`：几乎不等待 I/O
- `10-50`：有一定 I/O 等待
- `>100`：显著 I/O 瓶颈

---

## Step 5 - PSI I/O 压力检测（5 分钟）

### 5.1 PSI I/O 指标

```bash
$ cat /proc/pressure/io
some avg10=5.50 avg60=3.20 avg300=1.80 total=12345678
full avg10=2.10 avg60=1.05 avg300=0.50 total=6543210
```

| 指标 | 含义 |
|------|------|
| `some` | 至少有一个任务因 I/O 等待的时间比例 |
| `full` | 所有非空闲任务都因 I/O 等待的时间比例 |

### 5.2 PSI vs iostat 的区别

| 对比项 | iostat | PSI io |
|--------|--------|--------|
| 视角 | 设备层面 | 任务/进程层面 |
| 含义 | 设备有多忙 | 任务被 I/O 阻塞多少 |
| 使用场景 | 诊断具体设备 | 判断 I/O 是否影响整体性能 |

### 5.3 实战：快速判断 I/O 是否是瓶颈

```bash
# 一行命令判断 I/O 状态
awk -F= '/some/ {split($2, a, " "); print "I/O Pressure:", a[1] "% (avg10)";
         if (a[1] > 20) print "⚠️  High I/O pressure!"
         else if (a[1] > 5) print "⚡ Moderate I/O pressure"
         else print "✅ I/O OK"}' /proc/pressure/io
```

---

## Step 6 - I/O 调度器（5 分钟）

### 6.1 查看当前调度器

```bash
# 查看所有块设备的调度器
for dev in /sys/block/*/queue/scheduler; do
    echo "$dev: $(cat $dev)"
done

# 典型输出
# /sys/block/sda/queue/scheduler: mq-deadline [bfq] none
# /sys/block/nvme0n1/queue/scheduler: [none] mq-deadline
```

方括号 `[]` 表示当前使用的调度器。

### 6.2 调度器对比

| 调度器 | 适用场景 | 特点 |
|--------|----------|------|
| **mq-deadline** | 通用服务器（默认）| 保证请求延迟上限，适合 HDD |
| **bfq** | 桌面/交互式 | 公平带宽分配，低延迟交互 |
| **none** | NVMe SSD | 无调度，设备自己处理（最优） |
| **kyber**（少见）| 高性能 SSD | 延迟导向 |

### 6.3 为什么 NVMe 用 none？

<!-- DIAGRAM: nvme-scheduler -->
```
┌─────────────────────────────────────────────────────────────────────┐
│              HDD vs NVMe I/O 调度需求                                │
├─────────────────────────────────┬───────────────────────────────────┤
│            HDD                   │             NVMe                  │
├─────────────────────────────────┼───────────────────────────────────┤
│                                 │                                   │
│  • 机械臂寻道耗时               │  • 无机械部件，随机 = 顺序        │
│  • 顺序 I/O 远快于随机          │  • 原生支持数万并发请求           │
│  • 需要内核调度优化顺序         │  • 硬件队列比内核更高效           │
│                                 │                                   │
│  调度器价值：                   │  调度器价值：                     │
│  重排请求，减少寻道             │  增加 CPU 开销，无 I/O 收益       │
│                                 │                                   │
│  推荐：mq-deadline 或 bfq       │  推荐：none                       │
│                                 │                                   │
└─────────────────────────────────┴───────────────────────────────────┘
```
<!-- /DIAGRAM -->

### 6.4 临时修改调度器

```bash
# 切换到 mq-deadline（临时）
echo mq-deadline | sudo tee /sys/block/sda/queue/scheduler

# 切换到 none（NVMe 推荐）
echo none | sudo tee /sys/block/nvme0n1/queue/scheduler
```

---

## Step 7 - blktrace/blkparse（高级追踪）（5 分钟）

> **适用场景**：需要深入分析 I/O 路径、延迟分布、请求合并时使用。  
> 日常运维很少需要，但在深度性能调优时非常有价值。  

### 7.1 blktrace 基本使用

```bash
# 安装
sudo apt install blktrace  # Debian/Ubuntu
sudo yum install blktrace  # RHEL/CentOS

# 追踪 10 秒
sudo blktrace -d /dev/sda -o - | blkparse -i - | head -50

# 保存到文件
sudo blktrace -d /dev/sda -w 10
# 生成 sda.blktrace.* 文件

# 解析
blkparse -i sda.blktrace.0 | head -100
```

### 7.2 blkparse 输出解读

```
8,0  0  1  0.000000000  1234  Q  WS 12345678 + 8 [mysqld]
8,0  0  2  0.000001234  1234  G  WS 12345678 + 8 [mysqld]
8,0  0  3  0.000005678  1234  D  WS 12345678 + 8 [mysqld]
8,0  0  4  0.001234567  1234  C  WS 12345678 + 8 [0]
```

| 字母 | 含义 |
|------|------|
| `Q` | Queued - 请求进入队列 |
| `G` | Get request - 获取请求结构 |
| `D` | Dispatched - 发送到设备 |
| `C` | Completed - 完成 |
| `M` | Merged - 被合并 |

**延迟计算**：`C 时间 - Q 时间 = 总 I/O 延迟`

### 7.3 使用 btt 分析

```bash
# btt 是 blktrace 的统计分析工具
blkparse -i sda.blktrace.0 -d sda.bin
btt -i sda.bin

# 输出延迟分布、合并率等统计
```

---

## 现代 I/O: io_uring 简介

> **io_uring** 是 Linux 5.1+ 引入的高性能异步 I/O 接口。  
> 作为运维工程师，你需要**识别**应用是否使用它，以及它如何影响性能分析。  

### 什么是 io_uring？

<!-- DIAGRAM: io-uring-concept -->
```
┌─────────────────────────────────────────────────────────────────────┐
│                    传统 I/O vs io_uring                              │
├────────────────────────────────┬────────────────────────────────────┤
│        Traditional I/O         │            io_uring                 │
├────────────────────────────────┼────────────────────────────────────┤
│                                │                                    │
│  应用程序                      │  应用程序                          │
│      ↓ syscall (每次 I/O)      │      ↓ setup 一次                  │
│  ┌────────────┐               │  ┌─────────────────────────────┐   │
│  │   read()   │  ← 阻塞       │  │ Submission Queue (SQ)       │   │
│  │   write()  │               │  │ 提交队列：批量提交请求       │   │
│  └────────────┘               │  └─────────────────────────────┘   │
│      ↓ syscall (每次 I/O)      │      ↓ 异步处理                    │
│  ┌────────────┐               │  ┌─────────────────────────────┐   │
│  │   内核      │               │  │ Completion Queue (CQ)       │   │
│  └────────────┘               │  │ 完成队列：批量获取结果       │   │
│                                │  └─────────────────────────────┘   │
│                                │                                    │
│  问题：                        │  优势：                            │
│  • 每次 I/O 都是 syscall       │  • 批量提交，减少 syscall          │
│  • 高 IOPS 时 CPU 开销大       │  • 异步完成，CPU 效率高            │
│  • 阻塞等待                    │  • 零拷贝可能                      │
│                                │                                    │
└────────────────────────────────┴────────────────────────────────────┘
```
<!-- /DIAGRAM -->

### 哪些应用使用 io_uring？

| 应用 | 版本 | io_uring 支持 |
|------|------|---------------|
| PostgreSQL | 16+ | 可选启用 |
| RocksDB | Recent | 支持 |
| liburing 应用 | - | 原生 |
| 某些高性能存储引擎 | - | 支持 |

### 如何检测应用是否使用 io_uring？

```bash
# 方法 1: strace 检测 io_uring 相关 syscall
strace -e io_uring_enter,io_uring_setup -p PID 2>&1 | head -20
# 如果看到这些 syscall，说明在使用 io_uring

# 方法 2: perf trace
sudo perf trace -e 'io_uring:*' -p PID -- sleep 5

# 方法 3: 检查 fd 类型
ls -la /proc/PID/fd/ | grep io_uring
# 或
cat /proc/PID/fdinfo/* 2>/dev/null | grep -i io_uring
```

### 为什么运维需要关心 io_uring？

1. **strace 看不到完整 I/O**：传统 `strace` 追踪 `read/write` syscall，但 io_uring 的 I/O 通过队列提交，syscall 数量大幅减少。

2. **不同的性能特征**：
   - 更低的 `%sys` CPU（fewer syscalls）
   - iostat `%util` 可能偏低但 IOPS 很高
   - 需要用 `biolatency`（BCC）而非 `strace` 分析延迟

3. **调试方式不同**：
   ```bash
   # 传统应用：strace -e read,write
   # io_uring 应用：需要 bpftrace 或 BCC 工具
   sudo biolatency-bpfcc -D
   ```

### io_uring Awareness 总结

| 场景 | 行动 |
|------|------|
| 应用 I/O 性能高但 `strace` 看不到 syscall | 检查是否使用 io_uring |
| `%sys` CPU 很低但 IOPS 很高 | 可能是 io_uring 效果 |
| 需要追踪 io_uring I/O | 使用 `perf trace` 或 BCC `biolatency` |

---

## I/O 分析 Cheatsheet

```bash
# ============================================================
# I/O Analysis Cheatsheet
# ============================================================

# === 快速诊断 ===
# PSI I/O 压力（首选！）
cat /proc/pressure/io

# iostat 扩展统计
iostat -xz 1 5

# === USE Method 应用 ===
# U - Utilization
iostat -xz 1 | awk '/sd|nvme|vd/ {print $1, "%util:", $NF}'

# S - Saturation (queue depth, latency)
iostat -xz 1 | awk '/sd|nvme|vd/ {print $1, "aqu-sz:", $(NF-5), "await:", $(NF-3)}'

# E - Errors
dmesg | grep -i "I/O error\|medium error" | tail -5

# === 定位 I/O 消耗进程 ===
# iotop（需要 root）
sudo iotop -o -P

# pidstat
pidstat -d 1 5

# 找 I/O 等待最多的进程
pidstat -d 1 10 | awk '$7>10 {print}' | sort -k7 -nr

# === I/O 调度器 ===
# 查看
cat /sys/block/sda/queue/scheduler

# 切换（临时）
echo mq-deadline | sudo tee /sys/block/sda/queue/scheduler

# === 高级追踪 ===
# blktrace（深度分析）
sudo blktrace -d /dev/sda -o - | blkparse -i - | head -50

# === io_uring 检测 ===
strace -e io_uring_enter,io_uring_setup -p PID 2>&1 | head

# === 关键阈值 ===
# %util > 80%    → 设备繁忙
# await > 20ms (HDD) / > 5ms (SSD)  → 延迟高
# aqu-sz > 4     → 明显排队
# PSI io some > 10%  → I/O 压力显著
```

---

## 实战场景：Lab Scenarios

### Lab 1: High Load but Low CPU（I/O Bound 问题）

**场景**（来自 Codex GPT-5）：

```
症状：8 核服务器，Load Average = 40，但 CPU 使用率只有 20%
      文件访问非常慢
```

**诊断步骤**：

```bash
# Step 1: 确认 Load Average
uptime
# load average: 40.50, 38.20, 35.80

# Step 2: 检查 CPU（验证不是 CPU 问题）
vmstat 1 3
# 如果 us + sy < 30%，CPU 不是瓶颈
# 如果 wa (iowait) > 20%，怀疑 I/O

# Step 3: PSI 确认 I/O 压力
cat /proc/pressure/io
# some avg10=45.00  ← I/O 压力严重！

# Step 4: iostat 确认磁盘饱和
iostat -xz 1 3
# %util = 99%, await = 150ms, aqu-sz = 15
# 磁盘完全饱和

# Step 5: 找出 I/O 消耗者
sudo iotop -o -P -b -n 3
# 发现：rsync 进程消耗大量写 I/O

# Step 6: 验证是否误操作
ps aux | grep rsync
# rsync -av /backup /data  ← 备份任务在业务时间运行
```

**结论**：备份任务在业务时间运行导致 I/O 饱和，Load 高但 CPU 低。

**解决方案**：
1. 调整备份时间到低峰期
2. 使用 `ionice -c 3` 降低备份 I/O 优先级
3. 考虑增量备份减少 I/O 量

---

### Lab 2: The Disk Thrashing at Midnight（真夜中のディスク暴走）

**场景**（来自 Gemini - Japan IT Context）：

```
症状：每天 00:05，EC 网站返回 502 错误持续 2 分钟
      iowait 飙升到 90%

日本语境：ECサイトのダウン、SLA违反
```

**诊断步骤**：

```bash
# Step 1: 收集历史数据
# 确认问题时间点
grep "00:0[0-9]" /var/log/nginx/error.log | tail -20

# Step 2: 检查 cron 任务
crontab -l
cat /etc/crontab
ls /etc/cron.d/
# 发现：logrotate 在 00:05 运行

# Step 3: 分析 logrotate 影响
cat /etc/logrotate.d/nginx
# compress  ← gzip 压缩大日志文件！

# Step 4: 模拟问题（测试环境）
# 在 00:05 监控 I/O
watch -n 1 'iostat -xz 1 1 | tail -5'

# 观察到：
# %util = 98%, await = 200ms
# 原因：gzip 压缩 + ext4 journal barrier

# Step 5: 确认 logrotate 进程
ps aux | grep -E "logrotate|gzip"
sudo iotop -o
# gzip 消耗大量写 I/O
```

**根因分析**：

```
logrotate → gzip 压缩大日志 → 大量写 I/O
          → ext4 journal barrier → 阻塞其他 I/O
          → Web 应用无法写日志/读数据
          → 502 错误
```

**解决方案**：

```bash
# 方案 1: 使用 delaycompress（推迟压缩）
cat > /etc/logrotate.d/nginx << 'EOF'
/var/log/nginx/*.log {
    daily
    rotate 14
    compress
    delaycompress   # 下一次 rotate 时才压缩
    notifempty
    missingok
    sharedscripts
    postrotate
        [ -f /var/run/nginx.pid ] && kill -USR1 $(cat /var/run/nginx.pid)
    endscript
}
EOF

# 方案 2: 使用 pigz（并行 gzip）
apt install pigz
# 修改 logrotate 使用 pigz
compresscmd /usr/bin/pigz
compressoptions -p 2

# 方案 3: 调整 rotate 时间到低峰期
# 移动到 04:00
```

---

## 职场小贴士（Japan IT Context）

### 深夜のディスクスパイク調査

在日本 IT 企业，深夜的性能问题调查是常见的运维任务。

| 日语术语 | 读音 | 含义 | I/O 分析相关 |
|----------|------|------|--------------|
| ディスクI/O | ディスクアイオー | Disk I/O | iostat 分析对象 |
| ボトルネック | ボトルネック | Bottleneck | USE Method 定位 |
| 夜間バッチ | やかんバッチ | 夜间批处理 | 常见 I/O 问题源 |
| スパイク | スパイク | Spike | 突发 I/O 峰值 |
| ログローテーション | ログローテーション | Log rotation | 常见 I/O 问题源 |

### 障害対応のポイント

**I/O 问题报告模板**（日本企业风格）：

```markdown
## 障害報告書

### 発生日時
2026-01-10 00:05-00:07 JST

### 症状
ECサイトで 502 エラーが発生、約2分間

### 調査結果（USE Method - Disk I/O）

#### Utilization
- %util: 98%（通常 20%以下）

#### Saturation
- await: 200ms（通常 10ms以下）
- aqu-sz: 12（通常 1以下）
- PSI io some: 85%

#### Errors
- I/O error: なし

### 根本原因
00:05 の logrotate が大容量ログファイル（2GB）を
gzip 圧縮する際に発生するディスク I/O 負荷

### 対策
1. delaycompress オプションの追加
2. logrotate 実行時間を 04:00 に変更
3. 監視強化（PSI io > 50% でアラート）

### エビデンス
[iostat 出力、PSI データ、iotop スクリーンショット添付]
```

---

## 面试准备（Interview Prep）

### Q1: iostat の %util と await の関係は？

**回答要点**：

```
%util はデバイスの忙しさを表します（時間ベース）。
await は I/O リクエストの平均待ち時間です。

重要な関係：
- %util が低くても await が高い場合がある
  → デバイスは空いているが、個々の I/O が遅い（可能性：HDD 故障前兆）

- %util が高くても await が低い場合がある
  → デバイスは忙しいが、効率よく処理している（SSD の並列処理）

両方見ることが重要。%util だけ、await だけでは判断できない。
```

### Q2: I/O ボトルネックと CPU ボトルネックの見分け方は？

**回答要点**：

```
方法 1: vmstat で wa (iowait) を確認
- wa が高い（> 20%）→ I/O ボトルネック
- us + sy が高い → CPU ボトルネック

方法 2: PSI で確認（推奨）
- /proc/pressure/io some > 10% → I/O 問題
- /proc/pressure/cpu some > 10% → CPU 問題

方法 3: Load Average の解釈
- Load が高いが CPU 使用率が低い → I/O 待ちが原因
  （Load には uninterruptible sleep = I/O 待ちも含まれる）
```

### Q3: NVMe で I/O 調度器を none にする理由は？

**回答要点**：

```
HDD の場合：
- 機械式のヘッド移動（シーク）が遅い
- カーネルの調度器がリクエストを並べ替えて最適化
- mq-deadline や bfq が効果的

NVMe の場合：
- 電子的アクセス、シークなし
- ハードウェアが複数キューをネイティブサポート
- カーネル調度はオーバーヘッドになるだけ
- none（調度なし）が最適

確認方法：
cat /sys/block/nvme0n1/queue/scheduler
```

---

## 检查清单

完成本课后，你应该能够：

- [ ] 解释顺序 I/O vs 随机 I/O 的性能差异
- [ ] 解释 IOPS vs Throughput 的概念和关系
- [ ] 使用 iostat -x 并解读 %util、await、aqu-sz 指标
- [ ] 使用 iotop 定位 I/O 消耗最多的进程
- [ ] 使用 pidstat -d 追踪特定进程的 I/O
- [ ] 使用 PSI io 快速判断 I/O 压力
- [ ] 解释 mq-deadline、bfq、none 调度器的适用场景
- [ ] 识别应用是否使用 io_uring（Awareness level）
- [ ] 使用 USE Method 系统分析 Disk I/O（U/S/E）
- [ ] 诊断 "High Load but Low CPU" 的 I/O bound 问题

---

## 本课小结

| 概念 | 要点 |
|------|------|
| 顺序 vs 随机 | HDD 顺序快、随机慢；SSD 差异小 |
| IOPS vs Throughput | IOPS = 操作数/秒，Throughput = MB/秒 |
| iostat 核心指标 | %util（繁忙度）、await（延迟）、aqu-sz（队列） |
| PSI io | 现代 I/O 压力检测，比 load average 更准确 |
| 调度器选择 | HDD: mq-deadline，NVMe: none |
| io_uring | 现代异步 I/O，减少 syscall，需要不同追踪方法 |

---

## 延伸阅读

- [Brendan Gregg 的 iostat 解读](https://www.brendangregg.com/blog/2020-06-19/iostat.html)
- [Linux Block I/O 层文档](https://www.kernel.org/doc/html/latest/block/index.html)
- [io_uring 官方文档](https://kernel.dk/io_uring.pdf)
- 上一课：[03 - 内存分析](../03-memory-analysis/)
- 下一课：[05 - 网络性能](../05-network-performance/)
- 相关课程：[LX07 - 存储管理](../../lx07-storage/) - 文件系统和块设备基础

---

## 系列导航

[<-- 03 - 内存分析](../03-memory-analysis/) | [系列首页](../) | [05 - 网络性能 -->](../05-network-performance/)
