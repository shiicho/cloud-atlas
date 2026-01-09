# 02 - CPU 分析（CPU Analysis）

> **目标**：掌握 CPU 性能分析的核心技能，正确解读 Load Average，使用 USE Method 定位 CPU 瓶颈  
> **前置**：完成 Lesson 01 USE 方法论  
> **时间**：90-120 分钟  
> **实战场景**：夜間バッチ遅延調査、CPU 高负载问题诊断  

---

## 将学到的内容

1. 正确解读 Load Average（包含 I/O wait！）
2. 使用 top/htop 定位 CPU 消耗进程
3. 使用 mpstat -P ALL 分析多核 CPU 分布
4. 使用 pidstat -u 追踪进程级 CPU
5. 理解 PSI（Pressure Stall Information）替代 Load Average
6. 区分 %user、%system、%iowait、%steal
7. 理解上下文切换（voluntary vs involuntary）

---

## 先跑起来！（5 分钟）

> 在学习理论之前，先捕获系统的 CPU 状态快照。  
> 运行这些命令，观察输出 -- 这就是你将要分析的数据。  

```bash
# 查看当前 CPU 负载
uptime
cat /proc/loadavg

# 查看 CPU 压力（PSI - 现代方法）
cat /proc/pressure/cpu

# 查看每个 CPU 核心的使用情况
mpstat -P ALL 1 3

# 找到最消耗 CPU 的进程
ps aux --sort=-%cpu | head -10

# 进程级 CPU 使用追踪
pidstat -u 1 3
```

**你刚刚捕获了系统的 CPU 性能快照！**

- `uptime` 告诉你系统负载
- PSI 告诉你 CPU 是否"感到压力"
- `mpstat` 展示每个核心的状态
- `pidstat` 追踪是哪个进程在消耗 CPU

现在让我们深入理解这些数字的含义。

---

## Step 1 -- Load Average 正确解读（20 分钟）

### 1.1 Load Average 到底是什么？

很多人误以为 Load Average 就是 CPU 使用率。**这是错误的！**

<!-- DIAGRAM: load-average-components -->
```
┌─────────────────────────────────────────────────────────────────┐
│                   Load Average 的真正含义                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│   Load Average = 正在运行的进程 + 等待运行的进程 + 不可中断 I/O   │
│                                                                  │
│   ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐ │
│   │   R 状态进程     │  │ Run Queue 等待  │  │   D 状态进程     │ │
│   │  正在使用 CPU   │ + │  等待 CPU 调度  │ + │  等待磁盘/网络   │ │
│   │                 │  │                 │  │  (I/O wait)     │ │
│   └─────────────────┘  └─────────────────┘  └─────────────────┘ │
│          ▲                    ▲                    ▲            │
│          │                    │                    │            │
│       CPU 问题            CPU 饱和             I/O 问题          │
│                                                                  │
│   ⚠️ 关键洞察：高 Load 不一定是 CPU 问题！                       │
│   如果 Load 高但 CPU 使用率低，问题在 I/O！                      │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```
<!-- /DIAGRAM -->

### 1.2 查看 Load Average

```bash
# 三种方式查看 Load Average
uptime
# 输出：10:30:45 up 7 days, load average: 2.45, 1.23, 0.89
#                                          ↑      ↑      ↑
#                                        1分钟  5分钟  15分钟

cat /proc/loadavg
# 输出：2.45 1.23 0.89 3/256 12345
#       ↑    ↑    ↑    ↑     ↑
#      1m   5m  15m  运行/总进程  最近PID

# top 第一行也显示 Load Average
top -bn1 | head -1
```

### 1.3 Load Average vs CPU 核心数

```bash
# 查看 CPU 核心数
nproc
# 或
lscpu | grep "^CPU(s):"

# 解读规则：
# - Load = CPU 核心数：CPU 刚好满负荷
# - Load > CPU 核心数：可能有等待（不一定是 CPU 瓶颈！）
# - Load < CPU 核心数：有空闲能力
```

### 1.4 常见误区：高 Load 不等于 CPU 问题

```bash
# 场景：Load 40，但 CPU 只有 20%
# 这是典型的 I/O 瓶颈！

# 验证步骤 1：检查 vmstat
vmstat 1 5
#  r  b   swpd   free   buff  cache   si   so    bi    bo   in   cs us sy id wa st
#  2 38      0 123456  78901 234567    0    0  8000  2000 1234 5678  5  5 10 80  0
#  ↑  ↑                                                            ↑  ↑  ↑  ↑
#  运行 阻塞                                                       us sy id wa
#  队列 (D状态)                                                          (I/O wait!)

# 如果 wa（I/O wait）很高，说明进程在等 I/O，不是 CPU 问题！

# 验证步骤 2：检查 D 状态进程
ps aux | awk '$8 ~ /^D/ {print}'

# 验证步骤 3：使用 PSI 确认
cat /proc/pressure/cpu
cat /proc/pressure/io
# 如果 io 的 some/full 很高，而 cpu 的很低，确认是 I/O 问题
```

### 1.5 Load Average 的局限性

| 问题 | 说明 |
|------|------|
| 混合信号 | CPU 等待和 I/O 等待混在一起 |
| 滞后性 | 1/5/15 分钟平均，无法反映瞬时状态 |
| 无比例 | 不告诉你"多严重" |
| 难解读 | "Load 10 算高吗？" 取决于核心数 |

**现代替代方案**：使用 PSI（下文详述）

---

## Step 2 -- PSI：现代压力检测（15 分钟）

### 2.1 什么是 PSI？

PSI（Pressure Stall Information）是 Linux 4.20+ 引入的资源压力检测机制。
它直接回答："系统是否因为缺乏某资源而在等待？"

```bash
# 检查系统是否支持 PSI
ls /proc/pressure/
# cpu  io  memory

# 如果没有这个目录，内核版本太旧（< 4.20）
uname -r
```

### 2.2 解读 PSI 输出

```bash
cat /proc/pressure/cpu
# some avg10=0.00 avg60=0.00 avg300=0.00 total=12345678
# full avg10=0.00 avg60=0.00 avg300=0.00 total=0

# 解读：
# some = 有进程因等待该资源而停滞的时间比例
# full = 所有进程都在等待该资源的时间比例（CPU 通常为 0）
# avg10/60/300 = 10秒/60秒/300秒 滑动窗口平均值（百分比）
# total = 累计停滞时间（微秒）
```

<!-- DIAGRAM: psi-interpretation -->
```
┌─────────────────────────────────────────────────────────────────┐
│                     PSI 指标解读                                 │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│   some（部分压力）                                               │
│   ├── 至少有一个任务因等待资源而停滞                              │
│   ├── 对于 CPU：表示有任务在 run queue 等待                       │
│   └── 值越高 → 资源竞争越激烈                                    │
│                                                                  │
│   full（完全压力）                                               │
│   ├── 所有任务都在等待资源                                       │
│   ├── 对于 CPU：通常为 0（总有人在运行）                          │
│   ├── 对于 IO/Memory：表示系统完全阻塞                           │
│   └── full > 0 是严重问题！                                      │
│                                                                  │
│   ┌─────────────────────────────────────────────────────────┐   │
│   │  健康系统           │  警告状态           │ 危险状态      │   │
│   │  some < 5%          │  some 5-20%        │ some > 20%    │   │
│   │  full = 0           │  full 0-5%         │ full > 5%     │   │
│   └─────────────────────────────────────────────────────────┘   │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```
<!-- /DIAGRAM -->

### 2.3 PSI vs Load Average

| 维度 | Load Average | PSI |
|------|--------------|-----|
| 精确性 | 模糊（包含 D 状态） | 精确（分离 CPU/IO/Memory） |
| 时效性 | 1/5/15 分钟平均 | 10/60/300 秒实时 |
| 严重程度 | 数字，难比较 | 百分比，直观 |
| 可用性 | 所有 Linux | Kernel 4.20+ |

```bash
# 推荐做法：两者结合
echo "=== Load Average ==="
uptime

echo ""
echo "=== PSI (精确压力) ==="
echo "CPU:"
cat /proc/pressure/cpu
echo ""
echo "IO:"
cat /proc/pressure/io
echo ""
echo "Memory:"
cat /proc/pressure/memory
```

### 2.4 PSI 监控脚本

```bash
#!/bin/bash
# psi-monitor.sh - PSI 压力监控

THRESHOLD_WARN=10   # 警告阈值 (%)
THRESHOLD_CRIT=25   # 危险阈值 (%)

for resource in cpu io memory; do
    some=$(awk '/^some/ {print $2}' /proc/pressure/$resource | cut -d= -f2)

    # 转换为整数比较
    some_int=${some%.*}

    if [ "$some_int" -gt "$THRESHOLD_CRIT" ]; then
        echo "[CRITICAL] $resource pressure: ${some}%"
    elif [ "$some_int" -gt "$THRESHOLD_WARN" ]; then
        echo "[WARNING] $resource pressure: ${some}%"
    else
        echo "[OK] $resource pressure: ${some}%"
    fi
done
```

---

## Step 3 -- top/htop 核心指标（20 分钟）

### 3.1 top CPU 行解读

```bash
top
# 按 1 键显示每个 CPU 核心

# CPU 行解读：
# %Cpu(s):  5.2 us,  2.1 sy,  0.0 ni, 92.0 id,  0.5 wa,  0.0 hi,  0.2 si,  0.0 st
#           ↑        ↑        ↑        ↑        ↑        ↑        ↑        ↑
#          user    system   nice     idle    iowait  hardirq softirq  steal
```

| 指标 | 全称 | 含义 |
|------|------|------|
| us | user | 用户空间程序（应用代码） |
| sy | system | 内核空间（系统调用） |
| ni | nice | 低优先级用户进程 |
| id | idle | 空闲 |
| wa | iowait | 等待 I/O 完成 |
| hi | hardirq | 硬件中断处理 |
| si | softirq | 软件中断处理 |
| st | steal | 被虚拟化层"偷走"的 CPU |

### 3.2 CPU 指标分析决策树

<!-- DIAGRAM: cpu-metrics-decision-tree -->
```
┌─────────────────────────────────────────────────────────────────┐
│                   CPU 指标分析决策树                              │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│   观察 top 的 CPU 行                                             │
│          │                                                       │
│          ▼                                                       │
│   ┌────────────────┐                                            │
│   │  us (user) 高？ │                                            │
│   └───────┬────────┘                                            │
│           │ YES                                                  │
│           ▼                                                       │
│   应用程序消耗 CPU（正常或优化代码）                               │
│   → 使用 perf/strace 分析应用                                    │
│                                                                  │
│   ┌────────────────┐                                            │
│   │  sy (system) 高？│                                           │
│   └───────┬────────┘                                            │
│           │ YES                                                  │
│           ▼                                                       │
│   大量系统调用/内核操作                                           │
│   → 可能是 I/O 密集、大量 syscall、锁争用                         │
│   → 使用 strace -c 分析                                          │
│                                                                  │
│   ┌────────────────┐                                            │
│   │  wa (iowait) 高？│                                           │
│   └───────┬────────┘                                            │
│           │ YES                                                  │
│           ▼                                                       │
│   CPU 在等待 I/O！这不是 CPU 问题！                               │
│   → 使用 iostat, iotop 分析磁盘                                  │
│                                                                  │
│   ┌────────────────┐                                            │
│   │  st (steal) 高？ │                                           │
│   └───────┬────────┘                                            │
│           │ YES                                                  │
│           ▼                                                       │
│   虚拟化层在"偷" CPU！                                           │
│   → 检查 hypervisor、其他 VM 负载                                │
│   → 云环境可能是 CPU credits 耗尽                                │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```
<!-- /DIAGRAM -->

### 3.3 进程状态速查

在 top/htop 中，`S`（State）列显示进程状态：

| 状态 | 含义 | 说明 |
|------|------|------|
| R | Running | 正在运行或等待 CPU |
| S | Sleeping | 可中断睡眠（等待事件） |
| D | Disk sleep | 不可中断睡眠（等待 I/O） |
| T | Stopped | 已停止（SIGSTOP） |
| Z | Zombie | 僵尸（已退出，等待回收） |

### 3.4 top 关键操作

```bash
# 在 top 中的常用按键
P       # 按 CPU 使用率排序（默认）
M       # 按内存使用排序
1       # 显示每个 CPU 核心
c       # 显示完整命令行
H       # 显示线程
o       # 添加过滤器（如 COMMAND=java）
k       # 杀死进程（输入 PID）
q       # 退出

# 批处理模式（用于脚本/日志）
top -b -n 1 | head -20
top -b -n 5 -d 2 > cpu-monitor.log   # 每 2 秒采样，共 5 次
```

### 3.5 htop 的优势

```bash
# 安装 htop
# RHEL/CentOS
sudo dnf install htop -y
# Debian/Ubuntu
sudo apt install htop -y

# htop 提供更好的体验：
# - 彩色界面，更易读
# - 鼠标支持
# - 进程树视图（F5）
# - 更直观的 CPU/内存条
# - 批量选择和操作进程
```

---

## Step 4 -- mpstat 多核分析（15 分钟）

### 4.1 为什么需要 mpstat？

top 只显示所有 CPU 的汇总。但在多核系统中：
- 某个核心可能过载，其他空闲（不均衡）
- 单线程程序只能使用一个核心
- 某些 IRQ（中断）可能绑定到特定核心

```bash
# mpstat 属于 sysstat 包
# RHEL/CentOS
sudo dnf install sysstat -y
# Debian/Ubuntu
sudo apt install sysstat -y
```

### 4.2 mpstat 基本用法

```bash
# 显示所有 CPU 核心，每秒采样一次，共 5 次
mpstat -P ALL 1 5

# 输出示例：
# 10:30:01 CPU  %usr  %nice %sys %iowait %irq %soft %steal %guest %gnice %idle
# 10:30:02 all  5.00   0.00 2.00    0.50 0.00  0.25   0.00   0.00   0.00 92.25
# 10:30:02   0 50.00   0.00 5.00    0.00 0.00  1.00   0.00   0.00   0.00 44.00  ← 核心 0 很忙！
# 10:30:02   1  2.00   0.00 1.00    0.00 0.00  0.00   0.00   0.00   0.00 97.00
# 10:30:02   2  1.00   0.00 1.00    0.00 0.00  0.00   0.00   0.00   0.00 98.00
# 10:30:02   3  1.00   0.00 1.00    2.00 0.00  0.00   0.00   0.00   0.00 96.00
```

### 4.3 识别 CPU 不均衡

```bash
# 场景：单线程应用（只能用一个核心）
mpstat -P ALL 1 3 | grep -E "CPU|all|^[0-9]"

# 如果看到：
# - 某个核心 %idle 很低，其他很高
# - 这个核心的 %usr 或 %sys 很高
# → 可能是单线程程序绑定到了这个核心

# 解决方案：
# 1. 优化应用使其多线程
# 2. 使用 taskset 绑定到其他核心
# 3. 多实例运行
```

### 4.4 识别中断不均衡

```bash
# 网卡中断通常绑定到特定核心
cat /proc/interrupts | head -20

# 如果某个核心的 %irq/%soft 很高
# 可能是网络中断没有均匀分布

# 现代网卡支持 RSS（Receive Side Scaling）
# 可以将中断分散到多个核心
ethtool -l eth0   # 查看队列数
```

---

## Step 5 -- pidstat 进程级 CPU（15 分钟）

### 5.1 基本用法

```bash
# pidstat 也是 sysstat 包的一部分

# 每秒显示所有进程的 CPU 使用
pidstat -u 1

# 输出示例：
# 10:30:01 UID  PID   %usr  %system  %guest  %wait  %CPU  CPU  Command
# 10:30:02   0  1234  45.00    5.00    0.00   0.00 50.00    0  java
# 10:30:02  33  5678   2.00    1.00    0.00   0.50  3.00    1  nginx
```

### 5.2 指标解读

| 指标 | 含义 |
|------|------|
| %usr | 用户空间 CPU 使用 |
| %system | 内核空间 CPU 使用 |
| %guest | 运行虚拟机的 CPU 时间 |
| %wait | 等待 CPU 的时间（run queue 等待） |
| %CPU | 总 CPU 使用（%usr + %system） |
| CPU | 运行在哪个核心 |

### 5.3 追踪特定进程

```bash
# 追踪特定 PID
pidstat -u -p 1234 1 10

# 追踪特定命令（使用 pgrep 获取 PID）
pidstat -u -p $(pgrep -d, java) 1 5

# 追踪特定用户的进程
pidstat -u -U www-data 1 5
```

### 5.4 显示线程级 CPU

```bash
# -t 选项显示线程
pidstat -u -t -p 1234 1 5

# 输出会显示每个线程的 CPU 使用
# 对于 Java 等多线程应用特别有用
```

---

## Step 6 -- 上下文切换分析（10 分钟）

### 6.1 什么是上下文切换？

<!-- DIAGRAM: context-switching -->
```
┌─────────────────────────────────────────────────────────────────┐
│                       上下文切换                                 │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│   CPU 从一个进程/线程切换到另一个时，需要保存和恢复状态            │
│                                                                  │
│   ┌─────────┐  保存状态  ┌─────────┐  恢复状态  ┌─────────┐     │
│   │ 进程 A  │ ─────────▶ │ 内核    │ ─────────▶ │ 进程 B  │     │
│   │ (运行)  │            │ (切换)  │            │ (运行)  │     │
│   └─────────┘            └─────────┘            └─────────┘     │
│                                                                  │
│   上下文切换类型：                                               │
│   ┌────────────────────────────────────────────────────────┐    │
│   │  自愿切换 (Voluntary)                                   │    │
│   │  ├── 进程主动让出 CPU（等待 I/O、睡眠、锁）              │    │
│   │  └── 正常行为，不一定是问题                             │    │
│   ├────────────────────────────────────────────────────────┤    │
│   │  非自愿切换 (Involuntary)                               │    │
│   │  ├── 内核强制切换（时间片用完、更高优先级抢占）           │    │
│   │  └── 过多 = CPU 竞争激烈！                              │    │
│   └────────────────────────────────────────────────────────┘    │
│                                                                  │
│   ⚠️ 上下文切换开销：                                           │
│   - 每次切换需要几微秒                                          │
│   - 会导致 CPU 缓存失效                                         │
│   - 过多切换 = CPU 浪费在切换上而非计算                         │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```
<!-- /DIAGRAM -->

### 6.2 查看系统级上下文切换

```bash
# vmstat 的 cs 列
vmstat 1 5
#  r  b   swpd   free   buff  cache   si   so    bi    bo   in   cs us sy id wa st
#  2  0      0 123456  78901 234567    0    0     0     0 1000 5000  5  2 93  0  0
#                                                             ↑    ↑
#                                                            in   cs
#                                                         中断数  上下文切换数

# 正常范围取决于工作负载
# - 高并发 Web 服务器：几万/秒是正常的
# - 批处理任务：应该较低
# - 突然增加是问题信号
```

### 6.3 进程级上下文切换

```bash
# pidstat -w 显示上下文切换
pidstat -w 1 5

# 输出示例：
# 10:30:01 UID   PID   cswch/s nvcswch/s  Command
# 10:30:02   0  1234    500.00     50.00  java
# 10:30:02  33  5678     10.00      2.00  nginx

# cswch/s  = 自愿切换/秒（voluntary context switches）
# nvcswch/s = 非自愿切换/秒（non-voluntary context switches）
```

### 6.4 诊断上下文切换问题

```bash
# 高非自愿切换意味着：
# - 进程在争抢 CPU
# - 线程太多，CPU 不够用
# - 可能有锁争用

# 结合 mpstat 分析
mpstat -P ALL 1 3
# 如果 %usr + %sys 接近 100%，且 cs 很高
# → CPU 饱和，进程在排队

# 结合 pidstat 定位问题进程
pidstat -w -p ALL 1 5 | sort -k5 -rn | head -10
```

---

## Step 7 -- Cloud Lab 警告：Steal Time（10 分钟）

### 7.1 什么是 Steal Time？

在云环境（AWS、GCP、Azure 等）中，你可能看到 `%st`（steal time）不为 0。

```bash
# 查看 steal time
top
# 或
mpstat -P ALL 1 3 | grep -E "CPU|all"
```

### 7.2 AWS t2/t3 实例的 CPU Credits

> **重要**：如果你在 AWS t2/t3 实例上做性能测试，这是必读内容！  

<!-- DIAGRAM: aws-cpu-credits -->
```
┌─────────────────────────────────────────────────────────────────┐
│               AWS t2/t3 CPU Credits 机制                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│   t2/t3 是"突发性能"实例（Burstable Performance）                │
│                                                                  │
│   ┌─────────────────────────────────────────────────────────┐   │
│   │  正常状态                                                │   │
│   │  ├── 基线性能：如 t3.micro 基线 10% CPU                  │   │
│   │  ├── 积累 CPU Credits（每小时按比例积累）                 │   │
│   │  └── 可以突发到 100% CPU（消耗 credits）                  │   │
│   ├─────────────────────────────────────────────────────────┤   │
│   │  Credits 耗尽后                                          │   │
│   │  ├── 被限制回基线（10%）                                 │   │
│   │  ├── 你看到高 %st（steal time）                          │   │
│   │  └── 这不是"问题"，是设计如此！                          │   │
│   └─────────────────────────────────────────────────────────┘   │
│                                                                  │
│   ⚠️ 性能测试陷阱：                                             │
│   - 开始测试时 credits 满，性能很好                             │
│   - Credits 耗尽后，突然变慢                                    │
│   - 看起来像 CPU 问题，实际是 credits 问题！                     │
│                                                                  │
│   📊 如何检测：                                                  │
│   $ mpstat -P ALL 1 | grep -E "CPU|all"                         │
│   如果 %steal > 5%，你正在被限制                                 │
│                                                                  │
│   💡 解决方案：                                                  │
│   1. 使用 m/c 系列实例（无 credits 限制）                        │
│   2. 启用 Unlimited mode（按使用付费）                          │
│   3. 使用 cgroup 限制而非 stress 测试                           │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```
<!-- /DIAGRAM -->

### 7.3 检测 CPU Credits 耗尽

```bash
# 方法 1：检查 steal time
mpstat -P ALL 1 | grep -E "CPU|all"
# 如果 %steal > 5%，可能是 credits 耗尽

# 方法 2：AWS CLI 检查（需要权限）
aws cloudwatch get-metric-statistics \
  --namespace AWS/EC2 \
  --metric-name CPUCreditBalance \
  --dimensions Name=InstanceId,Value=i-your-instance-id \
  --period 300 --statistics Average \
  --start-time $(date -d '1 hour ago' --utc +%Y-%m-%dT%H:%M:%SZ) \
  --end-time $(date --utc +%Y-%m-%dT%H:%M:%SZ)
```

### 7.4 性能测试替代方案

```bash
# 不要用 stress 工具在 t2/t3 上做长时间压测
# 而是使用 cgroup 限制来模拟 CPU 约束

# 创建一个有 CPU 限制的 cgroup（需要 cgroup v2）
sudo systemctl set-property --runtime mytest.slice CPUQuota=50%

# 或使用 docker 限制
docker run --cpus=0.5 your-image

# 这样可以稳定地测试 CPU 受限场景
# 而不会因为 credits 耗尽导致结果不稳定
```

---

## Step 8 -- CPU 分析 Cheatsheet（速查表）

```bash
# =============================================================================
# CPU Analysis Cheatsheet
# =============================================================================

# --- 负载和压力 ---
uptime                              # Load average（1/5/15 分钟）
cat /proc/loadavg                   # Load + 运行进程数
cat /proc/pressure/cpu              # PSI CPU 压力（推荐！）

# --- 系统级 CPU ---
vmstat 1 5                          # CPU、内存、I/O 综合
mpstat -P ALL 1 5                   # 每个核心详情
sar -u 1 5                          # CPU 使用率历史

# --- 进程级 CPU ---
top                                 # 交互式监控
htop                                # 增强版 top
ps aux --sort=-%cpu | head -10      # CPU 消耗排行
pidstat -u 1 5                      # 进程 CPU 使用

# --- 上下文切换 ---
vmstat 1 5                          # cs 列 = 系统级切换
pidstat -w 1 5                      # 进程级切换
pidstat -wt -p PID 1 5              # 线程级切换

# --- 问题定位 ---
ps aux | awk '$8 ~ /^D/'            # D 状态进程（I/O 阻塞）
ps aux | awk '$8 ~ /^R/'            # R 状态进程（正在运行）

# --- 云环境 ---
mpstat -P ALL 1 | grep "%steal"     # Steal time 检查
```

---

## Step 9 -- 动手实验（30 分钟）

### 实验 1：CPU Saturation + Run-Queue Explosion（Codex 场景）

> **场景**：夜間バッチ（夜间批处理）运行时，Web 服务响应变慢。  
> 你需要诊断是否是 CPU 饱和问题。  

```bash
# 1. 模拟批处理负载（在后台运行）
# 注意：这会消耗 CPU，生产环境不要运行！
for i in {1..4}; do
    (while true; do echo "scale=10000; 4*a(1)" | bc -l > /dev/null; done) &
done
echo "Started 4 CPU-intensive processes"

# 2. 观察 Load Average 变化
watch -n 1 'uptime; echo ""; cat /proc/pressure/cpu'

# 3. 分析 CPU 状态
mpstat -P ALL 1 5

# 4. 找到 Run Queue 长度
vmstat 1 5
# r 列 = run queue 中等待的进程数
# 如果 r > CPU 核心数，说明 CPU 饱和

# 5. 定位消耗 CPU 的进程
pidstat -u 1 5 | sort -k8 -rn | head -10

# 6. 清理
pkill -f "bc -l"
echo "Cleanup done"
```

**检查清单**：
- [ ] Load Average 增加了吗？
- [ ] PSI cpu 的 some 值增加了吗？
- [ ] vmstat 的 r 列大于 CPU 核心数吗？
- [ ] 能定位到是哪些进程消耗 CPU 吗？

### 实验 2：The Ghost Load（Gemini 场景 - 短命进程）

> **场景**：运用監視センター（监控中心）告警 Load Average 持续高于 4.0，  
> 但 top 显示 CPU 90% idle。  
> 这是"幽灵负载"问题。  

```bash
# 1. 模拟短命进程（每秒大量 fork/exec）
# 这个脚本会快速创建和销毁进程
(while true; do for i in {1..100}; do /bin/true; done; sleep 0.1; done) &
SHORT_PROC=$!
echo "Started short-lived process spawner (PID: $SHORT_PROC)"

# 2. 观察 Load Average 上升
sleep 10
uptime
# Load 会上升，但 top 可能看不到具体进程！

# 3. 使用 top 观察
echo "Open another terminal and run: top"
echo "Press Enter when ready..."
read

# 你可能看到 %idle 很高，但 Load 不低
# 因为 top 刷新间隔捕获不到短命进程

# 4. 使用 execsnoop（需要 BCC tools）捕获
echo "If you have BCC tools installed, run:"
echo "sudo execsnoop-bpfcc"
echo "This will show the rapid process creation"

# 5. 使用 vmstat 观察
vmstat 1 10
# 注意 r 列和 cs 列
# 短命进程导致大量上下文切换

# 6. 清理
kill $SHORT_PROC 2>/dev/null
wait $SHORT_PROC 2>/dev/null
echo "Cleanup done"
```

**检查清单**：
- [ ] Load Average 高但 top 显示 idle？
- [ ] 这是 Ghost Load 的典型表现
- [ ] 需要用 execsnoop（eBPF）或 perf 才能捕获

### 实验 3：I/O Wait vs CPU Problem

> **场景**：区分 CPU 问题和 I/O 问题  

```bash
# 1. 创建 I/O 密集任务
(dd if=/dev/zero of=/tmp/testfile bs=1M count=1000 conv=fdatasync 2>/dev/null; rm -f /tmp/testfile) &
IO_PROC=$!
echo "Started I/O intensive task (PID: $IO_PROC)"

# 2. 观察 vmstat
vmstat 1 10
# 注意 wa（iowait）列

# 3. 观察 mpstat
mpstat -P ALL 1 5
# %iowait 会很高

# 4. 检查 PSI
echo "=== CPU Pressure ==="
cat /proc/pressure/cpu
echo ""
echo "=== IO Pressure ==="
cat /proc/pressure/io

# 如果 io 的 some 很高，而 cpu 的很低
# 说明问题在 I/O，不是 CPU

# 5. 清理
wait $IO_PROC 2>/dev/null
echo "Cleanup done"
```

**检查清单**：
- [ ] vmstat 的 wa 列是否明显增加？
- [ ] mpstat 的 %iowait 是否很高？
- [ ] PSI io 的压力是否高于 PSI cpu？
- [ ] 这证明问题是 I/O，不是 CPU

---

## 反模式：常见错误

### 错误 1：把 Load Average 当 CPU 使用率

```bash
# 错误思维
uptime
# "Load 8 on 4-core system = 200% CPU overload!"

# 正确思维
# Load 包含 I/O wait，需要进一步分析
vmstat 1 3
# 看 wa 列是否高

cat /proc/pressure/cpu
cat /proc/pressure/io
# 比较 cpu 和 io 的压力
```

**原因**：Load Average 是一个复合指标，包含 CPU 等待和 I/O 等待。高 Load 不一定是 CPU 问题。

### 错误 2：看到高 CPU 进程就 kill

```bash
# 错误做法
top
# "Java 占 90% CPU，杀了它！"
kill -9 $(pgrep java)

# 正确做法
# 1. 先理解这个进程是什么
ps -p $(pgrep java) -o pid,user,args

# 2. 检查这个进程是否应该消耗 CPU
# 批处理任务消耗 CPU 是正常的！

# 3. 如果是异常，先用 strace/perf 分析原因
strace -c -p $(pgrep java) -f
# 或
perf top -p $(pgrep java)

# 4. 根据分析结果决定下一步
```

**原因**：高 CPU 使用率可能是正常行为（批处理、计算任务）。盲目杀进程会造成服务中断。

### 错误 3：忽略 %iowait

```bash
# 错误思维
mpstat -P ALL 1 3
# "CPU 0 显示 50% busy，其他空闲，CPU 不均衡！"

# 正确做法：检查这 50% 是什么
# 如果大部分是 %iowait，那不是 CPU 问题
mpstat -P ALL 1 3
#          %usr  %sys  %iowait  %idle
# CPU 0:    5%    5%    40%      50%   ← 这是 I/O 问题，不是 CPU！
```

**原因**：%iowait 表示 CPU 在等待 I/O，CPU 本身是空闲的。这是磁盘/网络问题，不是 CPU 问题。

### 错误 4：忽略 Cloud Steal Time

```bash
# 错误思维
# "性能测试开始很好，后来突然变慢，肯定是内存泄漏！"

# 正确做法：检查 steal time
mpstat -P ALL 1 | grep "%steal"

# 如果 steal > 5%，你在被虚拟化层限制
# 这在 AWS t2/t3 等突发实例上很常见
```

**原因**：云环境的突发实例有 CPU credits 限制，耗尽后会被 throttle。

---

## 职场小贴士（Japan IT Context）

### 夜間バッチ遅延調査（夜间批处理延迟调查）

在日本 IT 企业，夜间批处理是关键业务流程：

| 日语术语 | 含义 | 场景 |
|----------|------|------|
| 夜間バッチ | 夜间批处理 | 凌晨运行的定时任务 |
| バッチ遅延 | 批处理延迟 | 处理时间超过预期 |
| 負荷原因の切り分け | 负载原因排查 | CPU/IO/Memory 分离 |
| 性能監視 | 性能监控 | 持续监控和告警 |

### 批处理延迟调查流程

```bash
#!/bin/bash
# batch-delay-investigation.sh
# バッチ遅延調査スクリプト

echo "=== 1. 系统概览 ==="
uptime
free -h
df -h | grep -v tmpfs

echo ""
echo "=== 2. CPU 分析 ==="
echo "--- Load Average ---"
cat /proc/loadavg

echo ""
echo "--- PSI Pressure ---"
cat /proc/pressure/cpu
cat /proc/pressure/io
cat /proc/pressure/memory

echo ""
echo "--- vmstat (5 samples) ---"
vmstat 1 5

echo ""
echo "=== 3. Top CPU Processes ==="
ps aux --sort=-%cpu | head -10

echo ""
echo "=== 4. D-state Processes (I/O blocked) ==="
ps aux | awk '$8 ~ /^D/ {print $2, $8, $11}'

echo ""
echo "=== 5. Diagnosis ==="
# 自动诊断逻辑
PSI_CPU=$(awk '/^some/ {print $2}' /proc/pressure/cpu | cut -d= -f2)
PSI_IO=$(awk '/^some/ {print $2}' /proc/pressure/io | cut -d= -f2)

if (( $(echo "$PSI_IO > $PSI_CPU" | bc -l) )); then
    echo ">>> 结论：IO 压力高于 CPU 压力，可能是磁盘瓶颈"
    echo ">>> 建议：使用 iostat -x 1 5 进一步分析"
else
    echo ">>> 结论：CPU 压力可能是主因"
    echo ">>> 建议：使用 pidstat -u 1 5 定位消耗 CPU 的进程"
fi
```

### 报告模板

```
========================================
障害報告書 / バッチ遅延調査
========================================

【発生日時】2026-01-10 03:00 ～ 05:30

【症状】
- 夜間バッチ処理が 2.5 時間遅延
- load average が通常 2.0 から 12.0 に上昇

【調査結果】
1. PSI 分析
   - CPU pressure: some=5.2%（正常範囲）
   - IO pressure: some=45.3%（高負荷！）

2. 原因特定
   - D 状態プロセスが 8 個検出
   - iotop で logrotate が大量 I/O 発生を確認
   - 原因：logrotate と バッチ処理のタイミング重複

【対策】
- logrotate の実行時刻を 02:00 → 06:00 に変更
- バッチ処理のタイムアウト設定を追加

【エビデンス】
- vmstat ログ：添付
- iostat ログ：添付
- PSI ログ：添付
```

---

## 检查清单

完成本课后，你应该能够：

- [ ] 正确解读 Load Average（知道它包含 I/O wait）
- [ ] 使用 PSI 检测 CPU 压力
- [ ] 区分 %user、%system、%iowait、%steal 的含义
- [ ] 使用 top/htop 快速定位高 CPU 进程
- [ ] 使用 mpstat -P ALL 分析多核 CPU 分布
- [ ] 使用 pidstat -u 追踪进程级 CPU 使用
- [ ] 使用 vmstat/pidstat -w 分析上下文切换
- [ ] 识别 Cloud 环境的 Steal Time 问题
- [ ] 区分 CPU 问题和 I/O 问题
- [ ] 应用 USE Method 系统性分析 CPU 资源

---

## 本课小结

| 概念 | 命令/路径 | 记忆点 |
|------|-----------|--------|
| Load Average | `uptime`, `/proc/loadavg` | 包含 I/O wait，不只是 CPU |
| PSI 压力 | `/proc/pressure/cpu` | 现代方法，比 Load 更准确 |
| 系统 CPU | `vmstat 1`, `mpstat -P ALL 1` | 区分 us/sy/wa/st |
| 进程 CPU | `pidstat -u 1`, `top` | 定位消耗 CPU 的进程 |
| 上下文切换 | `vmstat cs`, `pidstat -w` | cswch 自愿，nvcswch 非自愿 |
| Steal Time | `mpstat` 的 %st | 云环境 CPU credits 限制 |

**关键洞察**：
- 高 Load 不一定是 CPU 问题（可能是 I/O）
- 用 PSI 替代 Load Average 判断资源压力
- 分析 CPU 时，先确认 %iowait 是否高
- 云环境注意 %steal，可能是 credits 耗尽

---

## 延伸阅读

- [Brendan Gregg: CPU Utilization is Wrong](http://www.brendangregg.com/blog/2017-05-09/cpu-utilization-is-wrong.html)
- [PSI - Pressure Stall Information](https://facebookmicrosites.github.io/psi/docs/overview)
- [Linux Load Averages: Solving the Mystery](http://www.brendangregg.com/blog/2017-08-08/linux-load-averages.html)
- 上一课：[01 - 性能方法论（USE Method）](../01-use-methodology/) -- 建立分析框架
- 下一课：[03 - 内存分析](../03-memory-analysis/) -- 内存性能分析
- 相关课程：[LX07 - 存储管理](../../storage/) -- 理解 I/O 子系统

---

## 系列导航

[<-- 01 - USE 方法论](../01-use-methodology/) | [系列首页](../) | [03 - 内存分析 -->](../03-memory-analysis/)
