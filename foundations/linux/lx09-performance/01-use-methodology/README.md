# 01 - 性能方法论（USE Method）

> **目标**：掌握 USE Method 性能分析框架，建立"问题导向"而非"工具导向"的分析思维  
> **前置**：LX05-SYSTEMD（理解 cgroup v2、journalctl）、LX07-STORAGE（I/O 基础）  
> **时间**：⚡ 20 分钟（速读）/ 🔬 75 分钟（完整实操）  
> **实战场景**：性能監視、障害対応、基线建立  

---

## 将学到的内容

1. 理解 USE Method：Utilization, Saturation, Errors
2. 识别四大资源类型：CPU, Memory, Disk, Network
3. 理解基线（Baseline）的重要性
4. 区分症状（Symptom）与根因（Root Cause）
5. 了解 RED Method 作为补充（应用层）
6. 建立问题导向的分析思维

---

## 先跑起来！（10 分钟）

> 在学习方法论之前，先体验真实的性能数据采集。  
> 运行这些命令，观察输出 — 这就是你将要系统化理解的技能。  

```bash
# 进程列表 —— 谁在用 CPU？
top -bn1 | head -20

# 虚拟内存统计 —— CPU、内存、I/O 全景图
vmstat 1 5

# 磁盘 I/O 统计 —— 存储是瓶颈吗？
iostat -x 1 3

# PSI（Pressure Stall Information）—— 现代资源压力检测
cat /proc/pressure/cpu
cat /proc/pressure/memory
cat /proc/pressure/io

# 内存概览 —— 但 "used" 真的被用了吗？
free -h
```

**你刚刚捕获了系统的性能快照！**

- `top` 告诉你谁在用 CPU
- `vmstat` 给你 CPU、内存、I/O 的全景
- `iostat` 深入磁盘性能
- `PSI` 告诉你系统是否"感到压力"
- `free` 显示内存分布

**但这些数字意味着什么？正常还是异常？**

这就是为什么我们需要 **方法论** —— 一个系统化的分析框架。

---

## Step 1 - 为什么需要方法论？（10 分钟）

### 1.1 工具导向 vs 问题导向

**反模式：Tool Shopping（工具购物）**

```
遇到性能问题 →
    "我知道 top！" → 运行 top →
    "CPU 正常..." →
    "我知道 iostat！" → 运行 iostat →
    "I/O 也正常..." →
    "我知道 netstat！" → ...无尽循环
```

这种"撞大运"式的排查效率极低。

**正确姿势：问题导向（Question-First）**

```
遇到性能问题 →
    "什么资源是瓶颈？" →
    系统性检查 CPU / Memory / Disk / Network →
    定位到具体资源 →
    选择对应工具深入分析
```

### 1.2 USE Method 简介

**USE Method** 由性能工程大师 **Brendan Gregg** 提出，是一套系统性的性能分析框架。

**核心思想**：对每种资源，检查三个维度。

<!-- DIAGRAM: use-method-overview -->
```
┌─────────────────────────────────────────────────────────────────────┐
│                        USE Method 框架                               │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│   对于每种资源（CPU, Memory, Disk, Network），检查：                 │
│                                                                     │
│   ┌─────────────────────────────────────────────────────────────┐  │
│   │  U = Utilization（利用率）                                    │  │
│   │      资源使用率：CPU 繁忙时间、内存使用率、磁盘 %util          │  │
│   │      问题："资源用了多少？"                                   │  │
│   └─────────────────────────────────────────────────────────────┘  │
│                                                                     │
│   ┌─────────────────────────────────────────────────────────────┐  │
│   │  S = Saturation（饱和度）                                     │  │
│   │      等待队列深度：run queue、swap in/out、I/O 队列          │  │
│   │      问题："有请求在排队等待吗？"                             │  │
│   └─────────────────────────────────────────────────────────────┘  │
│                                                                     │
│   ┌─────────────────────────────────────────────────────────────┐  │
│   │  E = Errors（错误）                                           │  │
│   │      错误计数：硬件错误、丢包、重试                           │  │
│   │      问题："有错误发生吗？"                                   │  │
│   └─────────────────────────────────────────────────────────────┘  │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```
<!-- /DIAGRAM -->

### 1.3 USE vs 传统思路

| 传统思路 | USE Method |
|----------|------------|
| 看 CPU 高不高 | Utilization：CPU 用了多少？ |
| CPU 高就是问题 | Saturation：有进程在等待吗？ |
| 忽略错误检查 | Errors：有硬件/驱动错误吗？ |
| 只看一种资源 | 系统性检查 4 种资源 |

---

## Step 2 - USE Method 详解（15 分钟）

### 2.1 Utilization（利用率）

**定义**：资源被使用的时间比例或容量比例。

```bash
# CPU Utilization
vmstat 1 3 | tail -3
# 看 us + sy 列（用户态 + 内核态 CPU 使用）

# Memory Utilization
free -h
# 看 used / total，但更准确的是 available

# Disk Utilization
iostat -x 1 3
# 看 %util 列（设备繁忙程度）

# Network Utilization
ip -s link show eth0
# 看 TX/RX bytes，与网卡带宽比较
```

**关键点**：

- **100% 利用率不一定是问题** —— 如果没有排队等待
- **低利用率不一定没问题** —— 可能有错误导致无法使用

### 2.2 Saturation（饱和度）

**定义**：资源供不应求的程度，通常表现为队列深度或等待时间。

```bash
# CPU Saturation - 运行队列
vmstat 1 3
# r 列 > CPU 核心数 = CPU 饱和
# 例如：4 核机器，r = 8 表示有 4 个进程在等待

# Memory Saturation - 换页活动
vmstat 1 3
# si/so 列 > 0 表示正在使用 swap（内存饱和的信号）

# Disk Saturation - I/O 队列深度
iostat -x 1 3
# avgqu-sz 列 > 1 表示 I/O 请求在排队

# Network Saturation - Socket 队列
ss -s
# 查看 "in queue" 数量
```

**关键点**：

- **饱和度是性能问题的直接信号**
- 即使利用率不高，饱和度高也意味着问题
- **PSI（Pressure Stall Information）** 是现代 Linux 检测饱和度的最佳方式

### 2.3 Errors（错误）

**定义**：错误计数，包括硬件错误、软件错误、重试等。

```bash
# 系统日志中的错误
dmesg | grep -i error | tail -10

# 磁盘错误
cat /sys/block/sda/stat
# 或 dmesg | grep -i "I/O error"

# 网络错误
ip -s link show eth0
# 看 errors、dropped、overruns 行

# 内存错误（OOM）
dmesg | grep -i "out of memory"
journalctl -k | grep -i oom
```

**关键点**：

- **错误往往被忽视**，但可能是根本原因
- 硬件错误可能导致性能下降而非完全失败
- **先查错误，再看利用率和饱和度**

---

## Step 3 - 四大资源的 USE 检查清单（15 分钟）

### 3.1 USE Checklist 全景图

<!-- DIAGRAM: use-checklist -->
```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         USE Method Checklist                                 │
├──────────────┬──────────────────────┬─────────────────────┬─────────────────┤
│   Resource   │    Utilization       │    Saturation       │     Errors      │
├──────────────┼──────────────────────┼─────────────────────┼─────────────────┤
│              │ vmstat (us, sy)      │ vmstat (r > CPUs)   │ dmesg           │
│     CPU      │ top (%CPU)           │ /proc/schedstat     │ perf stat       │
│              │ mpstat -P ALL        │ PSI cpu             │ (CPU errors     │
│              │ sar -u               │                     │  are rare)      │
├──────────────┼──────────────────────┼─────────────────────┼─────────────────┤
│              │ free -m              │ vmstat (si, so)     │ dmesg | grep    │
│   Memory     │ /proc/meminfo        │ PSI memory          │   "out of mem"  │
│              │ smem -tk             │ sar -B (pgscank)    │ OOM killer logs │
│              │                      │                     │                 │
├──────────────┼──────────────────────┼─────────────────────┼─────────────────┤
│              │ iostat -x (%util)    │ iostat (avgqu-sz)   │ /sys/block/*/   │
│   Disk I/O   │ sar -d               │ iostat (await)      │   stat          │
│              │                      │ PSI io              │ dmesg | grep    │
│              │                      │                     │   "I/O error"   │
├──────────────┼──────────────────────┼─────────────────────┼─────────────────┤
│              │ ip -s link           │ ss -s               │ ip -s link      │
│   Network    │ sar -n DEV           │ netstat -s          │   (errors,      │
│              │ ethtool -S           │   (overflows)       │    dropped)     │
│              │                      │                     │ /proc/net/dev   │
└──────────────┴──────────────────────┴─────────────────────┴─────────────────┘
```
<!-- /DIAGRAM -->

### 3.2 CPU 检查实战

```bash
# Step 1: Utilization
echo "=== CPU Utilization ==="
vmstat 1 3 | tail -3

# Step 2: Saturation
echo "=== CPU Saturation (run queue) ==="
vmstat 1 3 | awk 'NR>2 {print "r (runqueue):", $1, "  CPUs:", '$(nproc)'}'

echo "=== PSI CPU Pressure ==="
cat /proc/pressure/cpu

# Step 3: Errors
echo "=== CPU Errors (rare) ==="
dmesg | grep -i "mce\|cpu.*error" | tail -5 || echo "No CPU errors found"
```

**解读示例**：

```
procs -----------memory---------- ---swap-- -----io---- -system-- ------cpu-----
 r  b   swpd   free   buff  cache   si   so    bi    bo   in   cs us sy id wa st
 8  0      0 512000  50000 200000    0    0    10    20  500 1000 75 10 15  0  0
```

- `r = 8`：8 个进程在运行/等待 CPU
- 如果系统只有 4 核，说明 **CPU 饱和**
- `us = 75, sy = 10`：CPU 利用率 85%

### 3.3 Memory 检查实战

```bash
# Step 1: Utilization
echo "=== Memory Utilization ==="
free -h

# Step 2: Saturation
echo "=== Memory Saturation (swapping) ==="
vmstat 1 3 | awk 'NR>2 {print "si:", $7, "so:", $8}'

echo "=== PSI Memory Pressure ==="
cat /proc/pressure/memory

# Step 3: Errors
echo "=== Memory Errors (OOM) ==="
dmesg | grep -i "out of memory" | tail -3 || echo "No OOM events"
```

**关键指标**：

- `free` 的 `available` 才是真正可用内存（包括可回收的 cache）
- `vmstat` 的 `si/so > 0` 表示正在使用 swap（内存压力信号）
- PSI memory 的 `some` 和 `full` 指标更准确

### 3.4 Disk I/O 检查实战

```bash
# Step 1: Utilization
echo "=== Disk Utilization ==="
iostat -x 1 3 | grep -E "Device|sd|nvme|vd"

# Step 2: Saturation
echo "=== Disk Saturation (queue depth, latency) ==="
iostat -x 1 3 | awk '/sd|nvme|vd/ {print $1, "avgqu-sz:", $9, "await:", $10}'

echo "=== PSI I/O Pressure ==="
cat /proc/pressure/io

# Step 3: Errors
echo "=== Disk Errors ==="
dmesg | grep -i "I/O error\|disk error" | tail -5 || echo "No disk errors"
```

**关键指标**：

- `%util > 80%`：设备繁忙
- `await > 20ms (HDD)` 或 `> 5ms (SSD)`：延迟高
- `avgqu-sz > 1`：有请求在排队

### 3.5 Network 检查实战

```bash
# Step 1: Utilization
echo "=== Network Utilization ==="
ip -s link show | grep -A3 "^[0-9]:" | head -20

# Step 2: Saturation
echo "=== Network Saturation (socket queues) ==="
ss -s

# Step 3: Errors
echo "=== Network Errors ==="
ip -s link show | grep -E "errors|dropped|overruns"
```

**关键指标**：

- `TX/RX bytes` 与网卡带宽比较
- `errors, dropped, overruns > 0`：网络问题信号
- Socket queue 深度持续增长：应用处理不过来

---

## Step 4 - PSI：现代资源压力检测（10 分钟）

### 4.1 什么是 PSI？

**PSI（Pressure Stall Information）** 是 Linux 4.20+ 引入的资源压力检测机制，比传统的 load average 更准确。

```bash
# 查看 PSI（需要 Linux 4.20+）
cat /proc/pressure/cpu
cat /proc/pressure/memory
cat /proc/pressure/io
```

**输出示例**：

```
some avg10=2.50 avg60=1.20 avg300=0.80 total=12345678
full avg10=0.10 avg60=0.05 avg300=0.02 total=1234567
```

### 4.2 PSI 指标解读

| 指标 | 含义 |
|------|------|
| `some` | 至少有一个任务因该资源阻塞的时间比例 |
| `full` | 所有任务都因该资源阻塞的时间比例 |
| `avg10/60/300` | 10秒/60秒/300秒 滑动窗口平均值 |
| `total` | 累计阻塞微秒数 |

**阈值建议**：

- `some avg10 > 5%`：资源有压力，需要关注
- `some avg10 > 20%`：资源压力大，可能影响性能
- `full avg10 > 0`：严重资源短缺

### 4.3 PSI vs Load Average

```bash
# 传统方式：Load Average
uptime
# 输出：load average: 4.50, 3.20, 2.80

# 现代方式：PSI
cat /proc/pressure/cpu
cat /proc/pressure/memory
cat /proc/pressure/io
```

**为什么 PSI 更好？**

| Load Average | PSI |
|--------------|-----|
| 包含 CPU + I/O wait | 分别显示 CPU/Memory/I/O |
| 难以判断瓶颈在哪 | 明确指出哪个资源有压力 |
| 绝对数值，难以比较 | 百分比，易于理解 |
| 无法区分"忙"和"等待" | `some` vs `full` 区分 |

### 4.4 Kernel 6.x 更新提示

> **内核 6.x 对运维的影响**  
>
> 大多数生产环境运行 RHEL 9 (kernel 5.14) 或 Ubuntu 22.04 (5.15)。  
> 本课程的实验在 5.x+ 都能正常运行。  
>
> Kernel 6.x 的改进：  
> - **PSI 成熟度**：更可靠的压力指标，更好的 systemd-oomd 集成  
> - **cgroup v2 改进**：更精确的 memory.high 节流，per-cgroup PSI  
> - **io_uring 增强**：更高效的异步 I/O（对应用透明）  
> - **MGLRU**：多代 LRU 内存回收算法，改善页面回收效率  

---

## Step 5 - 基线：性能分析的锚点（10 分钟）

### 5.1 为什么需要基线？

**没有基线，你无法判断"正常"还是"异常"。**

```
场景：CPU 利用率 70%
  - 没有基线："70% 高吗？好像有点高..."
  - 有基线："正常时是 30-40%，现在 70% 是异常！"
```

### 5.2 什么时候采集基线？

| 时机 | 说明 |
|------|------|
| 系统上线后 | 正常运行状态，无特殊负载 |
| 每周/每月定期 | 捕捉正常波动范围 |
| 变更前后 | 对比变更影响 |
| 发布新版本后 | 建立新的性能基准 |

### 5.3 基线采集脚本

```bash
#!/bin/bash
# baseline.sh - 系统性能基线采集脚本
# 用法: ./baseline.sh [采集时长秒数]

DURATION=${1:-60}
OUTPUT_DIR="baseline_$(date +%Y%m%d_%H%M%S)"

mkdir -p "$OUTPUT_DIR"
cd "$OUTPUT_DIR"

echo "开始采集基线数据，持续 $DURATION 秒..."
echo "输出目录: $OUTPUT_DIR"

# 系统信息
{
    echo "=== 系统信息 ==="
    uname -a
    echo ""
    echo "=== CPU 信息 ==="
    lscpu | grep -E "^CPU\(s\)|^Model name|^Architecture"
    echo ""
    echo "=== 内存信息 ==="
    free -h
    echo ""
    echo "=== 磁盘信息 ==="
    df -h
} > system_info.txt

# CPU + Memory + I/O 全景
vmstat 1 $DURATION > vmstat.txt &
VMSTAT_PID=$!

# 磁盘 I/O 详情
iostat -x 1 $DURATION > iostat.txt &
IOSTAT_PID=$!

# PSI 压力采样
{
    for i in $(seq 1 $DURATION); do
        echo "=== $(date) ==="
        cat /proc/pressure/cpu
        cat /proc/pressure/memory
        cat /proc/pressure/io
        sleep 1
    done
} > psi.txt &
PSI_PID=$!

# 等待采集完成
wait $VMSTAT_PID $IOSTAT_PID $PSI_PID

# 生成摘要
{
    echo "=== 基线采集摘要 ==="
    echo "采集时间: $(date)"
    echo "采集时长: $DURATION 秒"
    echo ""

    echo "=== vmstat 平均值 ==="
    awk 'NR>2 {
        us+=$13; sy+=$14; id+=$15; wa+=$16; r+=$1; n++
    } END {
        print "平均 CPU: us=" us/n "% sy=" sy/n "% id=" id/n "% wa=" wa/n "%"
        print "平均运行队列: r=" r/n
    }' vmstat.txt
    echo ""

    echo "=== PSI 最终值 ==="
    tail -4 psi.txt
} > summary.txt

echo ""
echo "采集完成！"
echo "摘要: $OUTPUT_DIR/summary.txt"
cat summary.txt
```

### 5.4 基线对比

```bash
# 假设已有基线目录 baseline_20260101 和当前数据
# 对比 vmstat 平均值

echo "=== 基线对比 ==="
echo "基线 (2026-01-01):"
awk 'NR>2 {us+=$13; sy+=$14; n++} END {print "CPU us:", us/n, "sy:", sy/n}' baseline_20260101/vmstat.txt

echo "当前:"
vmstat 1 5 | awk 'NR>2 {us+=$13; sy+=$14; n++} END {print "CPU us:", us/n, "sy:", sy/n}'
```

---

## Step 6 - RED Method 简介（5 分钟）

### 6.1 USE vs RED

**USE Method** 是 **资源导向**（Resource-Oriented）：

- 适合基础设施监控（CPU, Memory, Disk, Network）

**RED Method** 是 **服务导向**（Service-Oriented）：

- 适合应用/微服务监控

<!-- DIAGRAM: use-vs-red -->
```
┌──────────────────────────────────────────────────────────────────────┐
│                    USE Method vs RED Method                          │
├────────────────────────────────┬─────────────────────────────────────┤
│         USE Method             │          RED Method                  │
│       (资源导向)                │        (服务导向)                    │
├────────────────────────────────┼─────────────────────────────────────┤
│                                │                                      │
│  U = Utilization               │  R = Rate                            │
│      资源使用率                 │      请求速率（req/sec）             │
│                                │                                      │
│  S = Saturation                │  E = Errors                          │
│      等待队列深度               │      错误率（error/sec）             │
│                                │                                      │
│  E = Errors                    │  D = Duration                        │
│      错误计数                   │      请求延迟（ms）                  │
│                                │                                      │
├────────────────────────────────┼─────────────────────────────────────┤
│  适用场景：                     │  适用场景：                          │
│  • 服务器性能分析               │  • API/微服务监控                    │
│  • 基础设施监控                 │  • 用户体验监控                      │
│  • 底层资源问题定位             │  • SLA 监控                          │
│                                │                                      │
└────────────────────────────────┴─────────────────────────────────────┘
```
<!-- /DIAGRAM -->

### 6.2 实际应用

**Tier 3 运维工程师** 主要使用 USE Method 分析基础设施。

**当需要分析应用层问题时**，结合 RED Method：

```bash
# 如果有 nginx 日志
# Rate: 请求速率
tail -10000 /var/log/nginx/access.log | wc -l
# 10秒内的请求数

# Errors: 错误率
grep " 5[0-9][0-9] " /var/log/nginx/access.log | wc -l

# Duration: 延迟（需要日志格式包含请求时间）
awk '{print $NF}' /var/log/nginx/access.log | sort -n | tail -10
# 最慢的 10 个请求
```

---

## Step 7 - Mini-Project：建立系统基线（15 分钟）

### 任务目标

使用 USE Method 对你的系统建立基线报告。

### 7.1 创建完整基线脚本

```bash
# 创建工作目录
mkdir -p ~/performance-lab
cd ~/performance-lab

# 创建完整的 USE Method 基线脚本
cat > use-baseline.sh << 'EOF'
#!/bin/bash
# USE Method 基线采集脚本
# 使用方法: ./use-baseline.sh [采集秒数]

DURATION=${1:-30}
REPORT="use_report_$(date +%Y%m%d_%H%M%S).txt"

echo "============================================" | tee $REPORT
echo "  USE Method 系统基线报告" | tee -a $REPORT
echo "  采集时间: $(date)" | tee -a $REPORT
echo "  采集时长: $DURATION 秒" | tee -a $REPORT
echo "  主机名: $(hostname)" | tee -a $REPORT
echo "============================================" | tee -a $REPORT
echo "" | tee -a $REPORT

# 系统概览
echo "【系统概览】" | tee -a $REPORT
echo "CPU 核心数: $(nproc)" | tee -a $REPORT
echo "总内存: $(free -h | awk '/^Mem:/ {print $2}')" | tee -a $REPORT
echo "内核版本: $(uname -r)" | tee -a $REPORT
echo "" | tee -a $REPORT

# ============================================
# CPU 分析
# ============================================
echo "============================================" | tee -a $REPORT
echo "  CPU 分析 (USE)" | tee -a $REPORT
echo "============================================" | tee -a $REPORT

echo "" | tee -a $REPORT
echo "【U - Utilization】" | tee -a $REPORT
echo "vmstat 采样 ($DURATION 秒):" | tee -a $REPORT
vmstat 1 $DURATION | tail -$DURATION | awk '
    {us+=$13; sy+=$14; id+=$15; wa+=$16; n++}
    END {
        printf "  平均 CPU: us=%.1f%% sy=%.1f%% id=%.1f%% wa=%.1f%%\n",
               us/n, sy/n, id/n, wa/n
    }
' | tee -a $REPORT

echo "" | tee -a $REPORT
echo "【S - Saturation】" | tee -a $REPORT
echo "运行队列 (r 列):" | tee -a $REPORT
vmstat 1 3 | tail -1 | awk -v cpus=$(nproc) '
    {
        printf "  当前 r=%d, CPU 核心=%d\n", $1, cpus
        if ($1 > cpus) print "  ⚠️  CPU 饱和！运行队列 > 核心数"
        else print "  ✅ CPU 未饱和"
    }
' | tee -a $REPORT

echo "" | tee -a $REPORT
echo "PSI CPU:" | tee -a $REPORT
if [ -f /proc/pressure/cpu ]; then
    cat /proc/pressure/cpu | tee -a $REPORT
else
    echo "  PSI 不可用（需要 Linux 4.20+）" | tee -a $REPORT
fi

echo "" | tee -a $REPORT
echo "【E - Errors】" | tee -a $REPORT
CPU_ERRORS=$(dmesg 2>/dev/null | grep -ci "mce\|cpu.*error")
echo "  CPU/MCE 错误数: $CPU_ERRORS" | tee -a $REPORT

# ============================================
# Memory 分析
# ============================================
echo "" | tee -a $REPORT
echo "============================================" | tee -a $REPORT
echo "  Memory 分析 (USE)" | tee -a $REPORT
echo "============================================" | tee -a $REPORT

echo "" | tee -a $REPORT
echo "【U - Utilization】" | tee -a $REPORT
free -h | tee -a $REPORT

echo "" | tee -a $REPORT
echo "【S - Saturation】" | tee -a $REPORT
echo "Swap 活动 (si/so):" | tee -a $REPORT
vmstat 1 3 | tail -1 | awk '
    {
        printf "  si=%d so=%d (页/秒)\n", $7, $8
        if ($7 > 0 || $8 > 0) print "  ⚠️  正在使用 Swap！内存可能饱和"
        else print "  ✅ 无 Swap 活动"
    }
' | tee -a $REPORT

echo "" | tee -a $REPORT
echo "PSI Memory:" | tee -a $REPORT
if [ -f /proc/pressure/memory ]; then
    cat /proc/pressure/memory | tee -a $REPORT
else
    echo "  PSI 不可用" | tee -a $REPORT
fi

echo "" | tee -a $REPORT
echo "【E - Errors】" | tee -a $REPORT
OOM_COUNT=$(dmesg 2>/dev/null | grep -ci "out of memory")
echo "  OOM 事件数: $OOM_COUNT" | tee -a $REPORT

# ============================================
# Disk I/O 分析
# ============================================
echo "" | tee -a $REPORT
echo "============================================" | tee -a $REPORT
echo "  Disk I/O 分析 (USE)" | tee -a $REPORT
echo "============================================" | tee -a $REPORT

echo "" | tee -a $REPORT
echo "【U - Utilization】" | tee -a $REPORT
echo "iostat 采样:" | tee -a $REPORT
iostat -x 1 3 2>/dev/null | grep -E "Device|sd|nvme|vd|xvd" | tail -5 | tee -a $REPORT

echo "" | tee -a $REPORT
echo "【S - Saturation】" | tee -a $REPORT
echo "I/O 队列深度 (avgqu-sz) 和延迟 (await):" | tee -a $REPORT
iostat -x 1 3 2>/dev/null | awk '/sd|nvme|vd|xvd/ {print "  " $1 ": avgqu-sz=" $9 " await=" $10 "ms"}' | tail -5 | tee -a $REPORT

echo "" | tee -a $REPORT
echo "PSI I/O:" | tee -a $REPORT
if [ -f /proc/pressure/io ]; then
    cat /proc/pressure/io | tee -a $REPORT
else
    echo "  PSI 不可用" | tee -a $REPORT
fi

echo "" | tee -a $REPORT
echo "【E - Errors】" | tee -a $REPORT
IO_ERRORS=$(dmesg 2>/dev/null | grep -ci "I/O error")
echo "  I/O 错误数: $IO_ERRORS" | tee -a $REPORT

# ============================================
# Network 分析
# ============================================
echo "" | tee -a $REPORT
echo "============================================" | tee -a $REPORT
echo "  Network 分析 (USE)" | tee -a $REPORT
echo "============================================" | tee -a $REPORT

echo "" | tee -a $REPORT
echo "【U - Utilization】" | tee -a $REPORT
ip -s link show 2>/dev/null | grep -A2 "^[0-9]:" | head -12 | tee -a $REPORT

echo "" | tee -a $REPORT
echo "【S - Saturation】" | tee -a $REPORT
echo "Socket 统计:" | tee -a $REPORT
ss -s 2>/dev/null | head -5 | tee -a $REPORT

echo "" | tee -a $REPORT
echo "【E - Errors】" | tee -a $REPORT
echo "网络接口错误:" | tee -a $REPORT
ip -s link show 2>/dev/null | grep -E "errors|dropped" | head -5 | tee -a $REPORT

# ============================================
# 总结
# ============================================
echo "" | tee -a $REPORT
echo "============================================" | tee -a $REPORT
echo "  基线采集完成" | tee -a $REPORT
echo "  报告保存: $REPORT" | tee -a $REPORT
echo "============================================" | tee -a $REPORT

EOF

chmod +x use-baseline.sh
```

### 7.2 运行基线采集

```bash
# 运行基线采集（默认 30 秒）
./use-baseline.sh

# 或指定采集时长
./use-baseline.sh 60
```

### 7.3 检查清单

完成以下任务：

- [ ] 运行 USE Method 基线脚本
- [ ] 记录 CPU 利用率和运行队列
- [ ] 记录内存使用和 Swap 活动
- [ ] 记录磁盘 I/O 利用率和队列深度
- [ ] 记录网络错误计数
- [ ] 检查 PSI 压力指标
- [ ] 保存基线报告供未来对比

---

## 反模式：常见错误

### 错误 1：工具导向思维（Tool-First Thinking）

```bash
# 错误：随机尝试工具
top          # CPU 看起来正常...
free -m      # 内存也正常...
iostat       # I/O 也正常...
netstat      # 网络也正常...
# "那问题在哪？？？"

# 正确：USE Method 系统检查
# 1. 先检查所有资源的 Errors（错误优先）
# 2. 再检查 Saturation（是否有排队）
# 3. 最后看 Utilization（使用率）
```

### 错误 2：单一指标迷恋（Single-Metric Fixation）

```bash
# 错误：只看 CPU
top  # "CPU 80%！问题就是 CPU！"

# 正确：同时检查 I/O wait
vmstat 1 3
# 如果 wa > 0，可能是 I/O 问题导致的 CPU 等待
# 不要被表象迷惑
```

### 错误 3：先调优后测量（Tuning Before Measuring）

```bash
# 错误：直接修改参数
echo 10 > /proc/sys/vm/swappiness  # "网上说设成 10 好..."

# 正确：先建立基线
./use-baseline.sh > before.txt
# 修改参数
echo 10 > /proc/sys/vm/swappiness
# 再采集数据对比
./use-baseline.sh > after.txt
# 比较差异
diff before.txt after.txt
```

---

## 职场小贴士（Japan IT Context）

### 性能監視（性能监控）

在日本 IT 企业，性能监控是基础设施运维的核心职责。

| 日语术语 | 读音 | 含义 | USE Method 对应 |
|----------|------|------|-----------------|
| 性能監視 | せいのうかんし | Performance monitoring | 定期基线采集 |
| 性能劣化 | せいのうれっか | Performance degradation | USE 变化检测 |
| ボトルネック | ボトルネック | Bottleneck | USE 定位瓶颈 |
| エビデンス | エビデンス | Evidence | 数据支撑结论 |
| リソース枯渇 | リソースこかつ | Resource exhaustion | Saturation 检测 |

### エビデンス重視（证据重视）

日本 IT 企业非常重视 **エビデンス**（证据）。

**不可接受**：
- "我觉得是 CPU 问题"
- "应该是内存不够"

**可接受**：
- "vmstat 显示 r=12，CPU 核心数为 4，运行队列饱和"
- "PSI memory some=25%，超过阈值 5%，确认内存压力"

### 障害報告書（故障报告）示例

```markdown
## 障害報告書

### 発生日時
2026-01-10 14:30 JST

### 症状
Web 応答が遅い（5秒以上）

### 調査結果（USE Method）

#### CPU
- Utilization: us=30% sy=5% （正常）
- Saturation: r=2, CPUs=4 （正常）
- Errors: なし

#### Memory
- Utilization: 使用率 85%
- Saturation: PSI memory some=32% ⚠️
- Errors: OOM なし

#### Disk I/O
- Utilization: %util=95% ⚠️
- Saturation: avgqu-sz=8.5, await=120ms ⚠️
- Errors: なし

### 結論
ディスク I/O がボトルネック。%util=95%、await=120ms。

### 対策
1. I/O 負荷の高いプロセスを特定（iotop）
2. ログローテーション時間を変更
3. SSD へのアップグレードを検討
```

---

## 面试准备（Interview Prep）

### Q1: USE Method とは何ですか？（什么是 USE Method？）

**回答要点**：

```
USE Method は Brendan Gregg が提唱した性能分析手法です。

各リソース（CPU, Memory, Disk, Network）に対して、
3つの観点から体系的にチェックします：

- U = Utilization（利用率）
- S = Saturation（飽和度 = キュー待ち）
- E = Errors（エラー数）

Tool-first（ツール先行）ではなく、
Question-first（問題先行）のアプローチです。
```

### Q2: ベースラインの重要性は？（基线的重要性？）

**回答要点**：

```
ベースラインがないと、
現在の値が「正常」か「異常」か判断できません。

例：CPU 使用率 70%
- ベースラインなし：「70%は高い？よくわからない...」
- ベースラインあり：「通常は 30-40%、今は 70% = 異常！」

定期的にベースラインを取得し、
変更前後で比較することが重要です。
```

### Q3: PSI と Load Average の違いは？（PSI 和 Load Average 的区别？）

**回答要点**：

```
Load Average:
- CPU と I/O wait が混在
- どのリソースが問題か判別しにくい
- 絶対値で比較が難しい

PSI (Pressure Stall Information):
- CPU / Memory / I/O を個別に表示
- パーセンテージで理解しやすい
- some（部分的）と full（完全）を区別

Modern Linux では PSI を優先的に使用すべきです。
```

---

## 检查清单

完成本课后，你应该能够：

- [ ] 解释 USE Method 的三个维度（Utilization, Saturation, Errors）
- [ ] 识别四大资源类型及其对应的 USE 检查命令
- [ ] 使用 vmstat、iostat、free、ip 等工具采集性能数据
- [ ] 解读 PSI（Pressure Stall Information）指标
- [ ] 建立系统性能基线并保存报告
- [ ] 避免工具导向思维，采用问题导向分析
- [ ] 区分 USE Method（资源导向）和 RED Method（服务导向）

---

## 本课小结

| 概念 | 要点 |
|------|------|
| USE Method | Utilization + Saturation + Errors |
| 四大资源 | CPU, Memory, Disk, Network |
| 基线 | 性能分析的锚点，没有基线无法判断异常 |
| PSI | 现代资源压力检测，比 load average 更准确 |
| RED Method | 应用层补充：Rate, Errors, Duration |
| 核心原则 | 问题导向，非工具导向；先测量，再调优 |

---

## 延伸阅读

- [Brendan Gregg 的 USE Method 原文](https://www.brendangregg.com/usemethod.html)
- [Linux PSI 文档](https://docs.kernel.org/accounting/psi.html)
- 下一课：[02 - CPU 分析](../02-cpu-analysis/) - 深入 top、mpstat、pidstat、PSI
- 相关课程：[LX07 - 存储管理](../../lx07-storage/) - 理解块设备和文件系统

---

## 系列导航

[系列首页](../) | [02 - CPU 分析 -->](../02-cpu-analysis/)
