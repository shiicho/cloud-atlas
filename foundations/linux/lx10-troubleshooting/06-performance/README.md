# 06 - 性能问题：USE 方法论实战（Performance Troubleshooting: USE in Practice）

> **目标**：应用 USE 方法论诊断性能问题，区分 CPU 负载和 I/O 压力，识别 OOM Killer 和僵尸进程  
> **前置**：LX09 性能分析基础、LX05 systemd、Lesson 01 方法论  
> **时间**：2.5 小时  
> **核心理念**：Load Average 高不等于 CPU 过载，要用数据说话  

---

## 将学到的内容

1. 应用 USE 方法论诊断 CPU、内存、I/O 性能问题
2. 区分 CPU 负载和 I/O 压力（高 Load + 低 CPU = I/O 问题）
3. 识别 OOM Killer 和内存压力信号
4. 定位性能瓶颈进程
5. 处理僵尸进程和 PID 耗尽问题

---

## 先跑起来！（10 分钟）

> 在学习性能诊断之前，先体验"快速定位"的威力。  
> 这几条命令立即告诉你系统性能瓶颈在哪里。  

```bash
# 一键性能诊断：vmstat 看整体 + 找 I/O 阻塞进程
vmstat 1 5 && ps aux | awk '$8 ~ /D/'
```

**输出解读**：

```
procs -----------memory---------- ---swap-- -----io---- -system-- ------cpu-----
 r  b   swpd   free   buff  cache   si   so    bi    bo   in   cs us sy id wa st
 2  8      0 123456  12345 234567    0    0  8192  1024  500  800  5  3 10 82  0
 1  9      0 123456  12345 234567    0    0  9000  1024  520  850  4  2  8 86  0

# r=2: 2个进程等待CPU
# b=8: 8个进程在I/O阻塞！
# wa=82%: 82% CPU时间在等I/O

# ps 输出 D 状态进程（不可中断睡眠）
USER  PID %CPU %MEM   VSZ   RSS TTY  STAT START   TIME COMMAND
root  1234 0.0  0.1 12345 1234 ?    D    10:00   0:05 dd if=/dev/sda ...
mysql 5678 0.0  5.0 98765 5432 ?    D    09:00   0:30 mysqld --datadir...
```

**你刚刚发现**：
- Load Average 可能很高，但 CPU 使用率（us+sy）只有 10%
- **真正的问题是 I/O wait（wa=82%）**
- 8 个进程在 D 状态（不可中断睡眠），被磁盘 I/O 阻塞

**这就是"高负载的谎言"** -- Load 高不等于 CPU 过载。现在让我们深入学习如何系统性诊断性能问题。

---

## Step 1 -- USE 方法论实战（25 分钟）

### 1.1 回顾 USE 方法论

在 Lesson 01 中，我们学习了 USE 方法论的理论。现在我们要实战应用。

| 维度 | 检查什么 | 关键指标 |
|------|----------|----------|
| **U** - Utilization | 资源忙碌的时间百分比 | 使用率 % |
| **S** - Saturation | 等待队列的长度 | 等待数、队列深度 |
| **E** - Errors | 错误事件的数量 | dmesg、日志错误 |

### 1.2 CPU 性能分析

**工具矩阵**：

| 维度 | 工具 | 关键指标 |
|------|------|----------|
| Utilization | `top`, `mpstat -P ALL` | us + sy（用户态+内核态）|
| Saturation | `vmstat` r 列, `/proc/pressure/cpu` | 等待 CPU 的进程数 |
| Errors | `dmesg`, MCE 日志 | 硬件错误 |

**CPU 分析命令序列**：

```bash
# 1. 总体 CPU 使用率
top -bn1 | head -5
# 看 %Cpu(s): us (用户), sy (系统), wa (I/O等待), id (空闲)

# 2. 每个 CPU 核心的使用率
mpstat -P ALL 1 3
# 看是否有单核满载（可能是单线程程序瓶颈）

# 3. CPU 饱和度 - 等待队列
vmstat 1 5
# r 列 > CPU 核数 = CPU 饱和

# 4. 按进程看 CPU 使用
pidstat -u 1 5
# 找出消耗 CPU 最多的进程

# 5. PSI (Pressure Stall Information) - 现代方法
cat /proc/pressure/cpu
# avg10 > 0 表示最近 10 秒有 CPU 压力
```

**关键判断**：

```
CPU 使用率高 (us+sy > 80%) + r 列高 → CPU 真正过载，需要优化程序或加 CPU
CPU 使用率低 (us+sy < 20%) + Load 高 → 不是 CPU 问题！看 I/O wait
```

### 1.3 内存性能分析

**工具矩阵**：

| 维度 | 工具 | 关键指标 |
|------|------|----------|
| Utilization | `free -m`, `/proc/meminfo` | available, used |
| Saturation | `vmstat` si/so 列, `/proc/pressure/memory` | swap in/out |
| Errors | `dmesg \| grep -i oom` | OOM Killer 事件 |

**内存分析命令序列**：

```bash
# 1. 内存使用概览
free -m
# 重点看 available，不是 free
# available = free + buffers + cache（可回收）

# 2. 内存压力 - swap 活动
vmstat 1 5
# si/so 列非零 = 内存压力，在使用 swap

# 3. OOM Killer 历史
dmesg | grep -i 'oom\|killed'
# 找被杀的进程

# 4. 按进程看内存使用
smem -t -k
# 或
ps aux --sort=-%mem | head -10

# 5. PSI 内存压力
cat /proc/pressure/memory
# some avg10 > 0 表示有内存压力
```

**关键判断**：

```
available < 10% + si/so 非零 → 内存不足，需要优化或加内存
available OK + 进程被杀 → 可能是 cgroup 限制或 OOM score 问题
```

### 1.4 I/O 性能分析

**工具矩阵**：

| 维度 | 工具 | 关键指标 |
|------|------|----------|
| Utilization | `iostat -xz` %util | 磁盘忙碌百分比 |
| Saturation | `iostat -xz` avgqu-sz, aqu-sz | 队列深度 |
| Errors | `dmesg`, `smartctl` | 磁盘错误 |

**I/O 分析命令序列**：

```bash
# 1. 磁盘 I/O 详细统计
iostat -xz 1 5
# 重点指标：
#   %util - 磁盘忙碌百分比（>70% 需关注）
#   await - 平均等待时间（ms）
#   avgqu-sz - 平均队列深度

# 2. 实时 I/O 进程排行
iotop -o
# -o 只显示有 I/O 活动的进程

# 3. 按进程看 I/O
pidstat -d 1 5
# kB_rd/s, kB_wr/s - 读写速率

# 4. D 状态进程（I/O 阻塞）
ps aux | awk '$8 ~ /D/'
# 或
ps -eo pid,stat,wchan:20,comm | grep ' D'

# 5. PSI I/O 压力
cat /proc/pressure/io
```

**关键判断**：

```
%util > 90% + await 高 → 磁盘是瓶颈
D 状态进程多 → I/O 阻塞，查 iostat 找是哪个磁盘
%util 低但 await 高 → 可能是远程存储（NFS/SAN）问题
```

### 1.5 网络性能分析

**工具矩阵**：

| 维度 | 工具 | 关键指标 |
|------|------|----------|
| Utilization | `sar -n DEV`, `ip -s link` | 带宽使用 |
| Saturation | `ss -s`, `netstat -s` | 重传、丢包 |
| Errors | `ip -s link`, `ethtool -S` | 网卡错误 |

**网络分析命令序列**：

```bash
# 1. 网络流量统计
sar -n DEV 1 5
# rxkB/s, txkB/s - 接收/发送速率

# 2. 连接统计
ss -s
# 重点看 TCP 连接数、TIME-WAIT 数量

# 3. 网卡错误统计
ip -s link show eth0
# 看 errors, dropped, overruns

# 4. TCP 重传
netstat -s | grep -i retrans
# 重传多 = 网络质量问题

# 5. 网络压力
cat /proc/net/softnet_stat
# 第二列非零 = 丢包
```

---

## Step 2 -- Load Average 深度解读（20 分钟）

### 2.1 什么是 Load Average？

```bash
# 查看 Load Average
uptime
# 输出: 10:30:00 up 5 days, load average: 4.50, 3.20, 2.80
#                                          ↑     ↑     ↑
#                                         1分  5分  15分
```

**Load Average 的含义**：
- **不只是 CPU 使用率**，而是"等待运行的任务数"
- 包括：等待 CPU 的进程 + 等待 I/O 的进程（D 状态）
- 相当于"系统有多少工作要做"

### 2.2 与 CPU 核数的关系

<!-- DIAGRAM: load-average-interpretation -->
```
┌──────────────────────────────────────────────────────────────────┐
│               Load Average 与 CPU 核数的关系                      │
├──────────────────────────────────────────────────────────────────┤
│                                                                  │
│  假设系统有 4 个 CPU 核心                                        │
│                                                                  │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │  Load = 1.0   →  1个任务运行/等待，CPU 25% 容量         │    │
│  │  Load = 4.0   →  4个任务，CPU 刚好满载（理想状态）      │    │
│  │  Load = 8.0   →  8个任务，4个运行 + 4个等待（过载）     │    │
│  │  Load = 40.0  →  严重过载！但要看是 CPU 还是 I/O       │    │
│  └─────────────────────────────────────────────────────────┘    │
│                                                                  │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │  经验法则：                                              │    │
│  │                                                          │    │
│  │  Load / CPU核数 < 0.7   →  健康                         │    │
│  │  Load / CPU核数 0.7-1.0 →  需要关注                     │    │
│  │  Load / CPU核数 > 1.0   →  过载，需要行动               │    │
│  │                                                          │    │
│  │  例：4核系统，Load 2.8 → 2.8/4 = 0.7 → 边界状态        │    │
│  └─────────────────────────────────────────────────────────┘    │
│                                                                  │
│  重要：Load 高但 CPU 空闲 = I/O 问题！                           │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘
```
<!-- /DIAGRAM -->

**快速检查**：

```bash
# 获取 CPU 核数
nproc
# 或
grep -c ^processor /proc/cpuinfo

# 计算 Load 比率
load=$(uptime | awk -F'load average:' '{print $2}' | cut -d',' -f1 | tr -d ' ')
cores=$(nproc)
echo "Load: $load, Cores: $cores, Ratio: $(echo "scale=2; $load / $cores" | bc)"
```

### 2.3 高 Load + 低 CPU = I/O 问题

**这是最常见的"高负载谎言"场景**：

```bash
# 场景：Load Average = 40，但 CPU 几乎空闲
$ uptime
 10:30:00 up 5 days, load average: 40.50, 38.20, 35.80

$ top -bn1 | head -5
%Cpu(s):  2.0 us,  1.5 sy,  0.0 ni,  5.0 id, 91.5 wa,  0.0 hi,  0.0 si
#                                            ↑
#                                         wa=91.5%！
```

**诊断流程**：

```bash
# 1. 确认是 I/O wait 问题
vmstat 1 5
# 看 b 列（blocked）和 wa 列

# 2. 找 D 状态进程
ps aux | awk '$8 ~ /D/'

# 3. 确认是哪个磁盘
iostat -xz 1 3
# 看 %util 最高的设备

# 4. 找是什么进程在读写
iotop -o
# 或
pidstat -d 1 5
```

### 2.4 1/5/15 分钟的含义

| 指标 | 含义 | 用途 |
|------|------|------|
| 1 分钟 | 最近压力 | 实时监控 |
| 5 分钟 | 短期趋势 | 判断是否持续 |
| 15 分钟 | 长期趋势 | 基线对比 |

**趋势判断**：

```
1min > 5min > 15min → 负载上升中（关注！）
1min < 5min < 15min → 负载下降中（恢复中）
1min ≈ 5min ≈ 15min → 负载稳定（正常或持续过载）
```

---

## Step 3 -- I/O Wait 深度分析（20 分钟）

### 3.1 vmstat 详解

```bash
$ vmstat 1 5
procs -----------memory---------- ---swap-- -----io---- -system-- ------cpu-----
 r  b   swpd   free   buff  cache   si   so    bi    bo   in   cs us sy id wa st
 2  8      0 123456  12345 234567    0    0  8192  1024  500  800  5  3 10 82  0
```

**关键列解读**：

| 列 | 含义 | 正常值 | 异常信号 |
|----|------|--------|----------|
| r | 等待 CPU 的进程数 | < CPU 核数 | > 核数表示 CPU 饱和 |
| b | 不可中断睡眠（D 状态） | 0-2 | > 5 表示 I/O 阻塞严重 |
| si | swap in (KB/s) | 0 | 非零表示内存压力 |
| so | swap out (KB/s) | 0 | 非零表示内存压力 |
| bi | 块设备读入 (KB/s) | 变化 | 持续高值需要关注 |
| bo | 块设备写出 (KB/s) | 变化 | 持续高值需要关注 |
| wa | I/O 等待 CPU 百分比 | < 10% | > 20% 表示 I/O 瓶颈 |

### 3.2 D 状态进程（不可中断睡眠）

**什么是 D 状态？**

进程状态中，D (Uninterruptible Sleep) 表示进程正在等待 I/O 完成，**无法被信号中断**（包括 SIGKILL）。

```bash
# 找所有 D 状态进程
ps aux | awk '$8 ~ /D/'

# 更详细的信息：等待什么
ps -eo pid,stat,wchan:20,comm | grep ' D'

# 示例输出：
#  PID STAT WCHAN                COMMAND
# 1234 D    blkdev_issue_discar  fstrim
# 5678 D    rpc_wait_bit_killable nfsd
```

**D 状态的特点**：
- **不能被 kill -9**：信号无法中断内核 I/O 操作
- **贡献 Load Average**：即使没有使用 CPU
- **通常原因**：磁盘 I/O、NFS 卡住、硬件问题

### 3.3 iostat 详细分析

```bash
$ iostat -xz 1 3
Device     r/s     w/s   rkB/s   wkB/s avgrq-sz avgqu-sz  await  %util
sda       50.00  100.00 2000.00 5000.00    93.33     5.20  34.67  95.00
sdb        0.50    2.00   10.00   50.00    48.00     0.02   6.67   0.50
```

**关键指标**：

| 指标 | 含义 | 关注阈值 |
|------|------|----------|
| r/s, w/s | 每秒读写次数 | 取决于磁盘类型 |
| rkB/s, wkB/s | 每秒读写 KB | 带宽利用率 |
| avgqu-sz | 平均队列深度 | > 1 表示排队 |
| await | 平均等待时间(ms) | HDD < 20ms, SSD < 5ms |
| %util | 磁盘忙碌百分比 | > 70% 需关注，> 90% 瓶颈 |

**判断方法**：

```
%util 高 + await 高 → 磁盘是瓶颈
%util 高 + await 正常 → 吞吐量大但响应 OK
%util 低 + await 高 → 可能是远程存储问题
```

### 3.4 NFS 卡住的特殊情况

NFS 挂载点卡住是 D 状态进程的常见原因：

```bash
# 检查 NFS 挂载状态
mount | grep nfs
nfsstat -c

# 检查是否有 NFS 相关的 D 状态进程
ps -eo pid,stat,wchan:30,comm | grep -E 'D.*(nfs|rpc)'

# 测试 NFS 服务器连通性
showmount -e nfs-server
rpcinfo -p nfs-server

# 如果 NFS 卡住，可能需要强制卸载
umount -l /mnt/nfs    # lazy unmount
umount -f /mnt/nfs    # force unmount (可能失败)
```

**NFS 卡住的诊断**：

```bash
# 查看 RPC 统计
nfsstat -c
# 看 retrans（重传）数量是否在增长

# 查看 sunrpc 状态
cat /proc/net/rpc/nfs
```

---

## Step 4 -- OOM Killer 深入理解（25 分钟）

### 4.1 什么是 OOM Killer？

当系统内存严重不足时，Linux 内核会调用 OOM (Out-Of-Memory) Killer 来杀死进程释放内存。

**关键特点**：
- **发生在内核层面**，不会写入应用日志
- **只在 dmesg/journalctl -k 中可见**
- 进程"神秘消失"的常见原因

### 4.2 检测 OOM Killer

```bash
# 方法 1: dmesg 搜索
dmesg | grep -i 'oom\|killed'

# 方法 2: journalctl 内核日志
journalctl -k | grep -i 'oom\|killed'

# 方法 3: 特定时间范围
journalctl -k --since '24 hours ago' | grep -i oom

# 典型 OOM 日志：
# [12345.678901] Out of memory: Killed process 1234 (java) total-vm:8192000kB,
#                anon-rss:4096000kB, file-rss:0kB, shmem-rss:0kB
```

### 4.3 OOM Score 机制

每个进程都有一个 OOM score，分数越高越容易被杀。

```bash
# 查看进程的 OOM score
cat /proc/<PID>/oom_score

# 查看 OOM score 调整值
cat /proc/<PID>/oom_score_adj
# 范围: -1000 到 1000
# -1000 = 永不被 OOM 杀死
# 1000 = 最优先被杀

# 一键查看所有进程的 OOM score
ps -eo pid,comm,oom_score,oom_score_adj --sort=-oom_score | head -20
```

**OOM Score 计算因素**：
- 进程使用的内存量（越大分数越高）
- oom_score_adj 调整值
- 是否是 root 进程（稍低分数）

### 4.4 保护关键进程

```bash
# 保护进程不被 OOM 杀死
echo -1000 > /proc/<PID>/oom_score_adj

# 或者在 systemd service 中配置
# /etc/systemd/system/myapp.service
[Service]
OOMScoreAdjust=-1000

# 查看当前设置
systemctl show myapp | grep OOM
```

**警告**：过度保护可能导致系统完全卡死而不是杀进程。

### 4.5 内存压力指标（PSI）

PSI (Pressure Stall Information) 是现代 Linux 的内存压力监控方法。

```bash
# 查看内存压力
cat /proc/pressure/memory

# 输出解读：
# some avg10=5.00 avg60=3.50 avg300=2.00 total=123456789
# full avg10=1.00 avg60=0.50 avg300=0.20 total=12345678

# some: 有进程因为内存等待
# full: 所有进程都在因为内存等待
# avg10/60/300: 10秒/60秒/300秒平均值
```

**阈值参考**：

| 指标 | 健康 | 警告 | 严重 |
|------|------|------|------|
| some avg10 | < 10 | 10-40 | > 40 |
| full avg10 | < 5 | 5-20 | > 20 |

### 4.6 OOM 预防策略

```bash
# 1. 监控内存使用趋势
free -m
vmstat 1 5

# 2. 设置 swap（提供缓冲）
swapon --show
# 如果没有 swap，考虑添加

# 3. 使用 cgroup 限制进程内存
# 现代方法: systemd cgroup
systemctl set-property myapp.service MemoryMax=2G

# 4. 监控 OOM 事件
# 可以用 systemd-oomd 主动管理（RHEL 9+/Fedora）
systemctl status systemd-oomd
```

---

## Step 5 -- 僵尸进程与 PID 耗尽（20 分钟）

### 5.1 什么是僵尸进程？

**僵尸进程 (Zombie Process)**：已经退出但父进程还没有回收其退出状态的进程。

```bash
# 找僵尸进程
ps aux | awk '$8 == "Z"'

# 更详细的信息
ps -eo pid,ppid,stat,comm | grep ' Z'
# 注意 PPID（父进程 ID）
```

**僵尸进程的特点**：
- 状态显示为 Z（Zombie）或 defunct
- **不占用 CPU、内存等资源**
- **只占用一个 PID**
- 无法被 kill（已经死了）

### 5.2 僵尸进程的危害

单个僵尸进程无害，但大量僵尸进程会导致 **PID 耗尽**：

```bash
# 查看 PID 限制
cat /proc/sys/kernel/pid_max
# 通常是 32768 或更高

# 查看当前进程数
ps aux | wc -l

# 查看僵尸进程数量
ps aux | awk '$8 == "Z"' | wc -l
```

### 5.3 PID 耗尽的症状

当 PID 耗尽时，你会看到：

```bash
$ any_command
bash: fork: retry: Resource temporarily unavailable
bash: fork: retry: No child processes

# 但内存可能是充足的
$ free -m
              total        used        free      shared  buff/cache   available
Mem:          16000        4000        8000         100        4000       11500
```

### 5.4 处理僵尸进程

**核心原则**：杀死产生僵尸的父进程。

```bash
# 1. 找到僵尸进程的父进程
ps -eo pid,ppid,stat,comm | grep ' Z'
# 例如输出: 1234 5678 Z    <defunct>
# 父进程是 5678

# 2. 查看父进程是什么
ps -p 5678 -o pid,ppid,comm,args
# 例如: 5678 1 my_script /usr/local/bin/my_script.sh

# 3. 分析父进程为什么不回收子进程
# 可能原因:
#   - 没有调用 wait()
#   - 信号处理器阻止了回收
#   - 程序 bug

# 4. 处理方案:
# 方案 A: 修复父进程代码（最佳）
# 方案 B: 重启父进程
kill 5678
# 或
systemctl restart my_service

# 方案 C: 如果父进程是 init (PID 1)，僵尸会自动被回收
# 所以有时候等一会儿就好了
```

### 5.5 批量处理僵尸

```bash
#!/bin/bash
# 找出所有僵尸进程的父进程并分析

echo "=== Zombie Processes ==="
ps -eo pid,ppid,stat,comm | grep ' Z'

echo ""
echo "=== Parent Processes ==="
for zombie_ppid in $(ps -eo ppid,stat | awk '$2 == "Z" {print $1}' | sort -u); do
    echo "--- Parent PID: $zombie_ppid ---"
    ps -p $zombie_ppid -o pid,ppid,comm,args 2>/dev/null || echo "Parent already dead"
    echo "Zombie children: $(ps -eo ppid,stat | awk -v ppid=$zombie_ppid '$1 == ppid && $2 == "Z"' | wc -l)"
done
```

---

## Step 6 -- 三大实战场景（30 分钟）

### 6.1 场景一：高负载的谎言（The High-Load Lie）

**症状**：
- Load Average 飙升到 40+
- 但 CPU 使用率（User + System）接近 0%
- 系统感觉卡顿

**诊断流程**：

```bash
# 1. 确认 Load 高但 CPU 低
uptime
# load average: 42.50, 40.20, 38.80

top -bn1 | head -5
# %Cpu(s): 2.0 us, 1.0 sy, 0.0 ni, 5.0 id, 92.0 wa
#                                          ↑ wa=92%！

# 2. 确认是 I/O 问题
vmstat 1 5
# b 列（blocked）很高，wa 列很高

# 3. 找 D 状态进程
ps aux | awk '$8 ~ /D/'
# 输出大量进程

# 4. 找是哪个磁盘
iostat -xz 1 3
# sda %util=99%, await=500ms

# 5. 确认磁盘问题
dmesg | tail -50
# [12345.678] ata1.00: exception Emask 0x0 SAct 0x0 SErr 0x0 action 0x6
# [12345.679] ata1.00: failed command: READ DMA
```

**根因**：磁盘硬件问题或 NFS 卡住导致 I/O 阻塞。

**处理**：
1. 检查磁盘健康：`smartctl -a /dev/sda`
2. 如果是 NFS：检查 NFS 服务器连通性
3. 可能需要更换磁盘或修复 NFS

### 6.2 场景二：无声的崩溃（The Clean Crash）

**症状**：
- 关键进程（如 Python/Java worker）每 24 小时"神秘"死亡
- 应用日志**无任何错误**
- 重启后又正常运行一段时间

**诊断流程**：

```bash
# 1. 检查是不是 OOM Killer
dmesg | grep -i 'oom\|killed'
# [86400.123] Out of memory: Killed process 1234 (python) total-vm:8192000kB

# 2. 确认时间戳
journalctl -k --since '24 hours ago' | grep -i oom
# Jan 10 10:30:00 server kernel: Out of memory: Killed process 1234

# 3. 关联应用日志时间
# 确认 OOM 时间和进程死亡时间匹配

# 4. 分析内存使用模式
ps aux --sort=-%mem | head -10
# 找内存使用最多的进程

# 5. 检查是否有内存泄漏
# 监控进程内存随时间增长
while true; do
    ps -p <PID> -o pid,rss,vsz,comm
    sleep 60
done
```

**根因**：进程内存泄漏或内存配置不当，触发 OOM Killer。

**处理**：
1. 调整进程内存限制
2. 修复内存泄漏（应用层面）
3. 增加系统内存或 swap
4. 调整 oom_score_adj 保护关键进程（谨慎使用）

### 6.3 场景三：僵尸末日（Zombie Apocalypse）

**症状**：
- 无法 fork 新进程：`bash: fork: Resource temporarily unavailable`
- 内存充足
- 磁盘空间充足

**诊断流程**：

```bash
# 1. 确认可以执行内置命令（不需要 fork）
echo "test"  # 正常
type ls      # 正常

# 2. 检查进程数
# 如果能执行，快速检查
cat /proc/sys/kernel/pid_max
# 32768

# 3. 统计当前进程
wc -l < /proc/[0-9]*/stat 2>/dev/null
# 或者在问题发生前准备好的脚本

# 4. 找僵尸进程
cat /proc/[0-9]*/status 2>/dev/null | grep -c "State:.*Z"
# 如果接近 pid_max，就是僵尸导致

# 5. 找僵尸的父进程
cat /proc/[0-9]*/status 2>/dev/null | grep -B3 "State:.*Z" | grep PPid
```

**根因**：某个进程（通常是脚本）疯狂 fork 子进程但不回收，产生大量僵尸。

**紧急处理**：

```bash
# 如果还能 SSH 进去
# 找到产生僵尸的父进程并杀死
ps -eo pid,ppid,stat,comm | grep Z | awk '{print $2}' | sort | uniq -c | sort -rn | head -5
# 输出: 10000 1234
# 说明 PID 1234 产生了 10000 个僵尸

# 杀死父进程
kill 1234

# 僵尸会被 init 回收
```

---

## Step 7 -- 性能分析速查表（Cheatsheet）

### 7.1 快速诊断命令

```bash
# === CPU 分析 ===
top                           # 交互式概览
mpstat -P ALL 1               # 每 CPU 核心使用率
pidstat -u 1                  # 按进程 CPU 使用
perf top                      # 实时热点函数

# === 内存分析 ===
free -m                       # 内存概览
vmstat 1                      # 内存压力（si/so）
smem -t -k                    # 按进程内存
dmesg | grep -i oom           # OOM 事件

# === I/O 分析 ===
iostat -xz 1                  # 磁盘详细统计
iotop -o                      # 实时 I/O 进程
pidstat -d 1                  # 按进程 I/O

# === 进程状态 ===
ps aux | awk '$8 == "D"'      # I/O 阻塞进程
ps aux | awk '$8 == "Z"'      # 僵尸进程

# === 压力指标 (PSI) ===
cat /proc/pressure/cpu        # CPU 压力
cat /proc/pressure/memory     # 内存压力
cat /proc/pressure/io         # I/O 压力
```

### 7.2 性能问题决策树

<!-- DIAGRAM: performance-decision-tree -->
```
┌──────────────────────────────────────────────────────────────────┐
│                    性能问题诊断决策树                             │
├──────────────────────────────────────────────────────────────────┤
│                                                                  │
│                      性能问题                                    │
│                         │                                        │
│                         ▼                                        │
│           ┌──────────────────────────┐                          │
│           │ Load Average 高？        │                          │
│           └───────────┬──────────────┘                          │
│                       │                                          │
│          ┌────────────┴────────────┐                            │
│          │ Yes                     │ No                         │
│          ▼                         ▼                            │
│  ┌───────────────────┐   ┌────────────────────┐                │
│  │ CPU us+sy 高？    │   │ 响应慢但系统空闲   │                │
│  └────────┬──────────┘   │ → 网络/应用层问题  │                │
│           │              └────────────────────┘                │
│  ┌────────┴────────┐                                            │
│  │ Yes             │ No                                         │
│  ▼                 ▼                                            │
│  ┌──────────────┐  ┌──────────────────────────────────┐        │
│  │ CPU 真正过载 │  │ wa (I/O wait) 高？               │        │
│  │              │  └─────────────┬────────────────────┘        │
│  │ 优化:       │                │                              │
│  │ • 找 CPU 大户│       ┌───────┴───────┐                      │
│  │ • 优化代码   │       │ Yes           │ No                   │
│  │ • 加 CPU    │       ▼               ▼                      │
│  └──────────────┘  ┌─────────────┐ ┌─────────────────┐        │
│                    │ I/O 瓶颈   │ │ si/so 非零？    │        │
│                    │            │ └────────┬────────┘        │
│                    │ 检查:      │          │                  │
│                    │ • D 状态   │    ┌─────┴─────┐            │
│                    │ • iostat   │    │ Yes       │ No        │
│                    │ • iotop    │    ▼           ▼            │
│                    │ • dmesg    │ ┌────────┐ ┌────────────┐  │
│                    └─────────────┘ │ 内存   │ │ 检查其他   │  │
│                                    │ 压力   │ │ 如 NFS     │  │
│                                    └────────┘ └────────────┘  │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘
```
<!-- /DIAGRAM -->

---

## Step 8 -- 动手实验（30 分钟）

### 实验 1：模拟高负载谎言

```bash
# 创建 I/O 压力（需要 stress-ng）
# 安装: sudo yum install stress-ng 或 sudo apt install stress-ng

# 在一个终端创建 I/O 压力
stress-ng --io 4 --timeout 60s

# 在另一个终端观察
watch -n 1 'uptime; echo "---"; vmstat 1 3 | tail -4'

# 分析
# 1. Load Average 会上升
# 2. CPU us+sy 应该较低
# 3. wa (I/O wait) 会很高
# 4. vmstat b 列会有值
```

### 实验 2：模拟 OOM Killer

**警告**：此实验会消耗大量内存，在测试环境进行！

```bash
# 创建一个会消耗内存的脚本
cat > /tmp/memory_hog.py << 'EOF'
import time
data = []
try:
    while True:
        # 每次分配 100MB
        data.append('X' * (100 * 1024 * 1024))
        print(f"Allocated {len(data) * 100}MB")
        time.sleep(1)
except MemoryError:
    print("MemoryError!")
EOF

# 运行（在测试环境！）
python3 /tmp/memory_hog.py &

# 在另一个终端监控
watch -n 1 'free -m; echo "---"; dmesg | tail -5'

# 观察 OOM Killer 触发
# 然后检查
dmesg | grep -i oom

# 清理
rm /tmp/memory_hog.py
```

### 实验 3：模拟僵尸进程

```bash
# 创建一个产生僵尸的脚本
cat > /tmp/zombie_creator.sh << 'EOF'
#!/bin/bash
# 创建子进程但不回收
for i in {1..10}; do
    (sleep 1; exit 0) &
done
# 父进程不 wait，故意不回收
echo "Created 10 child processes, sleeping..."
sleep 30
EOF

chmod +x /tmp/zombie_creator.sh

# 运行
/tmp/zombie_creator.sh &

# 等几秒后检查僵尸
sleep 5
ps aux | grep -E 'Z|defunct'

# 僵尸的 PPID
ps -eo pid,ppid,stat,comm | grep Z

# 清理
kill %1  # 杀死后台任务
rm /tmp/zombie_creator.sh
```

---

## 检查清单

完成本课后，你应该能够：

- [ ] 解释 USE 方法论在性能诊断中的应用
- [ ] 使用 top、vmstat、iostat 诊断 CPU/内存/I/O 问题
- [ ] 解释 Load Average 与 CPU 核数的关系
- [ ] 判断 "高 Load + 低 CPU = I/O 问题"
- [ ] 使用 `ps aux | awk '$8 ~ /D/'` 找 I/O 阻塞进程
- [ ] 检测和分析 OOM Killer 事件
- [ ] 理解 oom_score 机制并保护关键进程
- [ ] 识别僵尸进程并找到其父进程
- [ ] 诊断 PID 耗尽问题
- [ ] 使用 PSI 指标监控系统压力

---

## 本课小结

| 概念 | 要点 |
|------|------|
| USE 方法论 | CPU/内存/I/O/网络 各检查 Utilization/Saturation/Errors |
| Load Average | 不只是 CPU，包括 I/O 等待；和 CPU 核数对比 |
| 高 Load 低 CPU | I/O 问题！看 vmstat wa 列和 D 状态进程 |
| D 状态进程 | 不可中断睡眠，等待 I/O，无法被 kill |
| OOM Killer | 内核杀进程释放内存，只在 dmesg 可见 |
| oom_score | 分数越高越容易被杀；-1000 可保护进程 |
| 僵尸进程 | 已退出但未回收；杀父进程解决 |
| PID 耗尽 | 大量僵尸导致；fork 失败但内存 OK |
| PSI | /proc/pressure/* 现代压力监控 |

**核心理念**：

> Load Average 高不等于 CPU 过载，要用数据说话。  
> OOM Killer 发生在内核日志，不是应用日志。  
> D 状态进程无法被 kill，要解决根本 I/O 问题。  

---

## 日本 IT 职场贴士

### 性能障害是 SLA 违反に直结

在日本企业，性能问题直接关系到 SLA（Service Level Agreement）合规：

| 日语术语 | 含义 | 场景 |
|----------|------|------|
| **SLA 違反** | SLA 违约 | 响应时间超标 |
| **基線** | 基线 | 正常时的性能指标 |
| **性能劣化** | 性能下降 | 响应变慢 |
| **ボトルネック** | 瓶颈 | 性能瓶颈点 |

### 基線との比較が重要（基线对比很重要）

日本企业强调与基线对比：

```bash
# 建立基线
# 在正常时记录关键指标
vmstat 1 60 > /var/log/baseline/vmstat-$(date +%Y%m%d).log
iostat -xz 1 60 > /var/log/baseline/iostat-$(date +%Y%m%d).log

# 故障时对比
# "平常の Load は 2-3、今は 40 です"
# "平时 Load 是 2-3，现在是 40"
```

### 报告时的表达

```
# 性能问题报告模板
【事象】API 応答時間が 5 秒超（SLA: 2 秒以内）
【影響】全ユーザーに影響
【原因】ディスク I/O 飽和（%util 95%）
【対応】I/O 負荷の原因プロセスを特定中
```

---

## 面试准备

### よくある質問（常见问题）

**Q: Load Average が高いのに CPU 使用率が低い場合、何を疑いますか？**

A: I/O ボトルネックを疑います。具体的には：
1. vmstat で wa (I/O wait) を確認
2. D 状態のプロセスを確認（`ps aux | awk '$8 ~ /D/'`）
3. iostat で %util が高いデバイスを特定
4. iotop や pidstat -d で原因プロセスを特定

Load Average には CPU 待ちだけでなく、I/O 待ちプロセスも含まれるため、このような状況が発生します。

**Q: OOM Killer が発生した場合、どう調査しますか？**

A: まず dmesg や journalctl -k で OOM Killer のログを確認します：
```bash
dmesg | grep -i 'oom\|killed'
```
ログには、どのプロセスがどれだけのメモリを使用していたか記録されています。
次に、oom_score_adj を確認し、重要なプロセスが保護されているか確認します。
再発防止として、メモリ使用量の監視や、cgroup によるメモリ制限を検討します。

**Q: ゾンビプロセスの対処法は？**

A: ゾンビプロセス自体は kill できないため、親プロセスを処理します：
1. `ps -eo pid,ppid,stat,comm | grep Z` で親プロセス（PPID）を特定
2. 親プロセスが正常なら、プログラムの wait() 呼び出しを修正
3. 緊急時は親プロセスを再起動して、ゾンビを init が回収するようにする

大量のゾンビは PID 枯渇を引き起こすため、早めの対処が重要です。

---

## トラブルシューティング（本課自体の問題解決）

### stress-ng がインストールできない

```bash
# RHEL/CentOS (EPEL 必要)
sudo yum install epel-release
sudo yum install stress-ng

# Debian/Ubuntu
sudo apt update
sudo apt install stress-ng

# 代替: dd でディスク I/O 負荷
dd if=/dev/zero of=/tmp/testfile bs=1M count=1000 conv=fdatasync
```

### iotop で "Permission denied"

```bash
# root 権限が必要
sudo iotop

# または CONFIG_TASK_IO_ACCOUNTING が無効の場合
# カーネル再コンパイルが必要（通常は有効）
grep CONFIG_TASK_IO_ACCOUNTING /boot/config-$(uname -r)
```

### /proc/pressure が存在しない

```bash
# Linux 4.20+ で導入された PSI 機能
uname -r

# 4.20 未満の場合は PSI なし
# 代わりに vmstat の si/so 列や iostat を使用
```

---

## 延伸阅读

- [Brendan Gregg - Linux Performance](https://www.brendangregg.com/linuxperf.html)
- [USE Method](https://www.brendangregg.com/usemethod.html)
- [Linux Kernel - PSI Documentation](https://www.kernel.org/doc/Documentation/accounting/psi.txt)
- [OOM Killer Documentation](https://www.kernel.org/doc/gorman/html/understand/understand016.html)
- 上一课：[05 - 存储故障](../05-storage-issues/) -- 容量、inode、I/O 错误
- 下一课：[07 - 日志分析](../07-log-analysis/) -- journalctl 与时间线重建

---

## 系列导航

[<-- 05 - 存储故障](../05-storage-issues/) | [系列首页](../) | [07 - 日志分析 -->](../07-log-analysis/)
