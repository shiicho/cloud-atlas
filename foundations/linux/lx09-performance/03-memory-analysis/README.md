# 03 - 内存分析（Memory Analysis）

> **目标**：掌握 Linux 内存分析技能，正确解读 free 输出，使用 USE Method 定位内存瓶颈  
> **前置**：完成 Lesson 01 USE 方法论、Lesson 02 CPU 分析  
> **时间**：90-120 分钟  
> **实战场景**：OOM Killer でサービス停止 - 原因調査、内存泄漏诊断  

---

## 将学到的内容

1. 理解 Linux 内存模型（物理内存 vs 虚拟内存）
2. 正确解读 free 输出（buff/cache 不是"浪费"！）
3. 区分 Page Cache 和 Anonymous Memory
4. 掌握进程内存指标：VSZ, RSS, PSS, USS
5. 使用 smem 分析 PSS/USS
6. 使用 pmap -x 分析进程内存映射
7. 理解 Slab 缓存和 slabtop
8. 使用 PSI memory 检测内存压力
9. 理解 OOM Killer 机制和 oom_score_adj

---

## 先跑起来！（5 分钟）

> 在学习理论之前，先捕获系统的内存状态快照。  
> 运行这些命令，观察输出 -- 这就是你将要分析的数据。  

```bash
# 查看内存概览（最常用）
free -h

# 查看详细内存信息
cat /proc/meminfo | head -30

# 查看内存压力（PSI）
cat /proc/pressure/memory

# 查看进程内存使用排行
ps aux --sort=-%mem | head -10

# 查看 Slab 缓存（内核内存）
cat /proc/meminfo | grep -E "^Slab|^SReclaimable|^SUnreclaim"
```

**你刚刚捕获了系统的内存性能快照！**

- `free` 告诉你内存分布
- `/proc/meminfo` 提供详细内存指标
- PSI 告诉你内存是否"感到压力"
- `ps --sort=-%mem` 展示哪些进程在用内存
- Slab 是内核自己用的内存

**但这些数字意味着什么？free 显示"used"很高是问题吗？**

让我们深入理解 Linux 内存管理机制。

---

## Step 1 -- Linux 内存模型（15 分钟）

### 1.1 物理内存 vs 虚拟内存

每个进程都有自己的 **虚拟地址空间**，Linux 内核负责将虚拟地址映射到 **物理内存**。

<!-- DIAGRAM: virtual-vs-physical-memory -->
```
┌─────────────────────────────────────────────────────────────────────┐
│                    Linux 内存模型                                    │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│   ┌──────────────────┐    ┌──────────────────┐                      │
│   │    进程 A        │    │    进程 B        │                      │
│   │  虚拟地址空间     │    │  虚拟地址空间     │                      │
│   │                  │    │                  │                      │
│   │  0x0000..FFFF    │    │  0x0000..FFFF    │                      │
│   │  (看起来独享     │    │  (看起来独享     │                      │
│   │   整个地址空间)   │    │   整个地址空间)   │                      │
│   └────────┬─────────┘    └────────┬─────────┘                      │
│            │                       │                                 │
│            ▼                       ▼                                 │
│   ┌─────────────────────────────────────────────────────────────┐   │
│   │                    MMU（内存管理单元）                        │   │
│   │                    页表映射 (Page Table)                     │   │
│   └─────────────────────────────────────────────────────────────┘   │
│            │                       │                                 │
│            ▼                       ▼                                 │
│   ┌─────────────────────────────────────────────────────────────┐   │
│   │                      物理内存 (RAM)                          │   │
│   │  ┌──────┐  ┌──────┐  ┌──────┐  ┌──────┐  ┌──────┐         │   │
│   │  │ Page │  │ Page │  │ Page │  │ Page │  │ Page │  ...    │   │
│   │  │  0   │  │  1   │  │  2   │  │  3   │  │  4   │         │   │
│   │  └──────┘  └──────┘  └──────┘  └──────┘  └──────┘         │   │
│   │     ↑          ↑                   ↑                        │   │
│   │    进程A      共享库               进程B                      │   │
│   └─────────────────────────────────────────────────────────────┘   │
│                                                                      │
│   关键概念：                                                         │
│   • 虚拟内存让每个进程"以为"自己独占整个地址空间                       │
│   • 物理内存是实际的 RAM                                             │
│   • 内核负责映射，对进程透明                                         │
│   • 多个进程可以共享同一物理页（shared libraries）                    │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```
<!-- /DIAGRAM -->

### 1.2 Page Cache：Linux 的"智慧"

Linux 会把空闲内存用作 **Page Cache**（页缓存），缓存磁盘数据。

```bash
# 查看 Page Cache 大小
cat /proc/meminfo | grep -E "^Cached|^Buffers"
```

<!-- DIAGRAM: page-cache-concept -->
```
┌─────────────────────────────────────────────────────────────────────┐
│                       Page Cache 工作原理                            │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│   第一次读取文件：                                                   │
│   ┌──────┐     ┌──────────┐     ┌──────────┐                       │
│   │ 应用  │ ──▶ │ Page     │ ──▶ │ 磁盘     │                       │
│   │      │     │ Cache    │     │          │                       │
│   └──────┘     │ (未命中)  │     └──────────┘                       │
│                └──────────┘          │                              │
│                     ↑                │                              │
│                     └────────────────┘                              │
│                       数据加载到缓存                                 │
│                                                                      │
│   第二次读取同一文件：                                               │
│   ┌──────┐     ┌──────────┐                                        │
│   │ 应用  │ ──▶ │ Page     │  ✓ 缓存命中！                          │
│   │      │ ◀── │ Cache    │    无需访问磁盘                         │
│   └──────┘     └──────────┘                                        │
│                                                                      │
│   ⚠️ 关键洞察：                                                     │
│   • Page Cache 使用"空闲"内存，不是"浪费"                           │
│   • 当应用需要内存时，内核会自动回收 Cache                           │
│   • free 命令的 "available" 才是真正可用的内存                      │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```
<!-- /DIAGRAM -->

### 1.3 Anonymous Memory vs File-backed Memory

Linux 内存分为两大类：

| 类型 | 英文 | 来源 | 可回收？ |
|------|------|------|----------|
| 文件页 | File-backed | Page Cache（磁盘文件缓存） | 可直接丢弃或写回 |
| 匿名页 | Anonymous | malloc、堆、栈 | 只能写入 Swap |

```bash
# 查看匿名页 vs 文件页
cat /proc/meminfo | grep -E "^AnonPages|^Mapped|^Cached"
```

**为什么这很重要？**

- **内存压力时**：内核优先回收 File-backed 页（只需丢弃或写回磁盘）
- **匿名页**：进程的数据（堆、栈），只能写入 Swap
- **没有 Swap + 匿名页增长** = OOM 风险！

---

## Step 2 -- free 命令深度解读（15 分钟）

### 2.1 free 输出解析

```bash
free -h
#               total        used        free      shared  buff/cache   available
# Mem:           15Gi        4.5Gi       2.0Gi       500Mi        9.0Gi       10Gi
# Swap:          2.0Gi          0B        2.0Gi
```

| 列 | 含义 | 说明 |
|----|------|------|
| total | 总物理内存 | RAM 大小 |
| used | 已使用内存 | **包含了部分 cache** |
| free | 完全空闲 | **不是真正的"可用"** |
| shared | 共享内存 | tmpfs、shared memory |
| buff/cache | 缓冲/缓存 | Page Cache + Buffers |
| **available** | **真正可用** | **看这个！** |

### 2.2 buff/cache 不是"浪费"！

<!-- DIAGRAM: free-memory-interpretation -->
```
┌─────────────────────────────────────────────────────────────────────┐
│                    free 输出正确解读                                 │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│   ❌ 错误理解：                                                      │
│   "free 只有 2GB，内存快满了！"                                      │
│   "buff/cache 占了 9GB，浪费了！"                                    │
│                                                                      │
│   ✅ 正确理解：                                                      │
│   ┌───────────────────────────────────────────────────────────┐     │
│   │                    total = 15GB                            │     │
│   ├─────────────┬────────────────────────────┬────────────────┤     │
│   │   used      │       buff/cache           │     free       │     │
│   │   4.5GB     │         9GB                │     2GB        │     │
│   │             │   ┌─────────────────┐      │                │     │
│   │  真正被     │   │ 可回收的缓存！  │      │   完全空闲     │     │
│   │  进程使用   │   │ 应用需要时会    │      │                │     │
│   │             │   │ 自动释放        │      │                │     │
│   │             │   └─────────────────┘      │                │     │
│   └─────────────┴────────────────────────────┴────────────────┘     │
│                              │                                       │
│                              ▼                                       │
│   ┌───────────────────────────────────────────────────────────┐     │
│   │              available = 10GB (真正可用！)                  │     │
│   │              = free + 可回收的 buff/cache                   │     │
│   └───────────────────────────────────────────────────────────┘     │
│                                                                      │
│   📊 判断内存是否紧张，看 available，不是 free！                     │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```
<!-- /DIAGRAM -->

### 2.3 free -w 分离 buffers 和 cache

```bash
free -wh
#               total        used        free      shared     buffers       cache   available
# Mem:           15Gi        4.5Gi       2.0Gi       500Mi       500Mi        8.5Gi       10Gi
```

| 指标 | 含义 |
|------|------|
| buffers | 块设备 I/O 缓冲（元数据缓存） |
| cache | Page Cache（文件内容缓存） |

**大多数情况下，cache 远大于 buffers。**

### 2.4 内存健康判断标准

```bash
# 快速判断内存健康度
free -h | awk '/^Mem:/ {
    total = $2
    available = $7
    gsub(/[^0-9.]/, "", total)
    gsub(/[^0-9.]/, "", available)
    pct = (available / total) * 100
    printf "Available: %.1f%% of total\n", pct
    if (pct < 10) print "⚠️  警告：可用内存不足 10%"
    else if (pct < 20) print "⚠️  注意：可用内存不足 20%"
    else print "✅ 内存状态正常"
}'
```

---

## Step 3 -- /proc/meminfo 关键指标（15 分钟）

### 3.1 核心指标速查

```bash
cat /proc/meminfo | grep -E "^MemTotal|^MemFree|^MemAvailable|^Buffers|^Cached|^SwapTotal|^SwapFree|^Slab|^AnonPages"
```

| 指标 | 含义 | 关注点 |
|------|------|--------|
| MemTotal | 总物理内存 | 基准值 |
| MemFree | 完全空闲内存 | **不是真正可用** |
| MemAvailable | 真正可用内存 | **看这个** |
| Buffers | 块设备缓冲 | 通常很小 |
| Cached | Page Cache | 可回收 |
| SwapTotal | Swap 总量 | 配置的 Swap |
| SwapFree | Swap 空闲 | 使用了多少 Swap |
| Slab | 内核 Slab 缓存 | 内核数据结构 |
| AnonPages | 匿名页 | 进程实际使用 |

### 3.2 Active vs Inactive

```bash
cat /proc/meminfo | grep -E "^Active|^Inactive"
# Active:          5000000 kB
# Inactive:        3000000 kB
# Active(anon):    2000000 kB
# Inactive(anon):   500000 kB
# Active(file):    3000000 kB
# Inactive(file):  2500000 kB
```

| 指标 | 含义 |
|------|------|
| Active | 最近被访问的页 |
| Inactive | 长时间未被访问的页 |
| Active(anon) | 活跃的匿名页 |
| Inactive(anon) | 不活跃的匿名页（Swap 候选） |
| Active(file) | 活跃的文件页 |
| Inactive(file) | 不活跃的文件页（回收候选） |

**内存回收顺序**：优先回收 Inactive(file) -> Inactive(anon) -> Active...

### 3.3 内存分析脚本

```bash
#!/bin/bash
# memory-analysis.sh - 内存状态分析

echo "=== Memory Analysis Report ==="
echo "Time: $(date)"
echo ""

# 基础指标
echo "【基础指标】"
awk '
/^MemTotal:/ { total = $2 }
/^MemAvailable:/ { avail = $2 }
/^Cached:/ { cached = $2 }
/^Buffers:/ { buffers = $2 }
/^AnonPages:/ { anon = $2 }
/^Slab:/ { slab = $2 }
END {
    printf "  总内存: %.2f GB\n", total/1024/1024
    printf "  可用: %.2f GB (%.1f%%)\n", avail/1024/1024, avail/total*100
    printf "  Page Cache: %.2f GB\n", cached/1024/1024
    printf "  Buffers: %.2f MB\n", buffers/1024
    printf "  匿名页: %.2f GB\n", anon/1024/1024
    printf "  Slab: %.2f GB\n", slab/1024/1024
}
' /proc/meminfo

echo ""
echo "【Swap 状态】"
awk '
/^SwapTotal:/ { stotal = $2 }
/^SwapFree:/ { sfree = $2 }
END {
    sused = stotal - sfree
    if (stotal > 0) {
        printf "  Swap 总量: %.2f GB\n", stotal/1024/1024
        printf "  Swap 使用: %.2f GB (%.1f%%)\n", sused/1024/1024, sused/stotal*100
        if (sused/stotal*100 > 50) print "  ⚠️  Swap 使用超过 50%"
    } else {
        print "  Swap 未配置"
    }
}
' /proc/meminfo

echo ""
echo "【PSI Memory Pressure】"
if [ -f /proc/pressure/memory ]; then
    cat /proc/pressure/memory
else
    echo "  PSI 不可用"
fi
```

---

## Step 4 -- 进程内存指标：VSZ, RSS, PSS, USS（20 分钟）

### 4.1 四种内存指标

在分析进程内存时，你会遇到多种指标。它们有什么区别？

<!-- DIAGRAM: memory-metrics-comparison -->
```
┌─────────────────────────────────────────────────────────────────────┐
│                    进程内存指标对比                                  │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│   ┌─────────────────────────────────────────────────────────────┐   │
│   │  VSZ (Virtual Size) - 虚拟内存大小                          │   │
│   │  • 进程申请的全部虚拟内存                                    │   │
│   │  • 包含未实际分配的内存（malloc 但未使用）                    │   │
│   │  • 通常很大，但不代表实际使用                                │   │
│   │  • ⚠️ 几乎没有参考价值！                                    │   │
│   └─────────────────────────────────────────────────────────────┘   │
│                                                                      │
│   ┌─────────────────────────────────────────────────────────────┐   │
│   │  RSS (Resident Set Size) - 驻留内存大小                      │   │
│   │  • 进程实际在物理内存中的页                                  │   │
│   │  • 包含共享库（被多个进程共享）                              │   │
│   │  • ⚠️ 多进程时会重复计算共享库！                            │   │
│   └─────────────────────────────────────────────────────────────┘   │
│                                                                      │
│   ┌─────────────────────────────────────────────────────────────┐   │
│   │  PSS (Proportional Set Size) - 比例分摊大小                  │   │
│   │  • 共享内存按使用进程数平分                                  │   │
│   │  • 例：100MB 共享库被 10 个进程使用，每个计 10MB             │   │
│   │  • ✅ 更准确！所有进程 PSS 之和 ≈ 总内存使用                │   │
│   └─────────────────────────────────────────────────────────────┘   │
│                                                                      │
│   ┌─────────────────────────────────────────────────────────────┐   │
│   │  USS (Unique Set Size) - 独占内存大小                        │   │
│   │  • 只有该进程使用的内存                                      │   │
│   │  • 杀死进程后会释放的内存                                    │   │
│   │  • ✅ 判断"杀进程能释放多少内存"最准确                      │   │
│   └─────────────────────────────────────────────────────────────┘   │
│                                                                      │
│   大小关系：VSZ >> RSS >= PSS >= USS                                │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```
<!-- /DIAGRAM -->

### 4.2 用 ps 查看 VSZ 和 RSS

```bash
# VSZ 和 RSS
ps aux --sort=-%mem | head -10
#  USER       PID %CPU %MEM    VSZ   RSS TTY      STAT START   TIME COMMAND
#  mysql     1234  0.5  8.0  2000000 1300000 ?   Ssl  Jan01 100:00 mysqld
#                            ↑       ↑
#                           VSZ     RSS (KB)

# 更详细的格式
ps -eo pid,user,vsz,rss,comm --sort=-rss | head -10
```

### 4.3 用 smem 查看 PSS 和 USS

**smem** 是分析进程内存的神器，可以显示 PSS 和 USS。

```bash
# 安装 smem
# RHEL/CentOS
sudo dnf install smem -y
# Debian/Ubuntu
sudo apt install smem -y

# 基本用法：按 PSS 排序
smem -rs pss | head -15

# 显示人类可读格式和总计
smem -tk

# 按用户汇总
smem -u

# 按映射（库文件）汇总
smem -m | head -10
```

### 4.4 smem 输出解读

```bash
smem -rs pss | head -10
#   PID User     Command                         Swap      USS      PSS      RSS
# 12345 mysql    /usr/sbin/mysqld                   0  1200000  1250000  1300000
# 12346 www-data /usr/sbin/nginx: worker            0    50000    80000   150000
```

| 列 | 含义 | 用途 |
|----|------|------|
| Swap | 在 Swap 中的内存 | 被换出的内存 |
| USS | 独占内存 | 杀进程能释放多少 |
| PSS | 比例分摊 | 更准确的内存使用 |
| RSS | 驻留内存 | 传统指标 |

### 4.5 实战：找出真正的内存大户

```bash
# 错误方法：按 RSS 排序（共享库重复计算）
ps aux --sort=-%mem | head -10

# 正确方法：按 PSS 排序（准确分摊）
smem -rs pss | head -10

# 最佳方法：看 USS（杀进程能释放多少）
smem -rs uss | head -10

# 汇总所有进程
smem -tk
# 最后一行显示总计
```

---

## Step 5 -- pmap 分析进程内存映射（10 分钟）

### 5.1 pmap 基本用法

```bash
# 查看进程内存映射
pmap PID

# 扩展格式（更详细）
pmap -x PID

# 设备格式（显示设备和 inode）
pmap -d PID
```

### 5.2 pmap -x 输出解读

```bash
pmap -x 12345 | head -20
# Address           Kbytes     RSS   Dirty Mode  Mapping
# 00005555555000      8000    4000       0 r-x-- mysqld
# 00007fff12340000    1000     500     500 rw--- [heap]
# 00007fff56780000      64      64      64 rw--- [stack]
# ----------------  ------  ------  ------
# total kB          200000  150000   10000
```

| 列 | 含义 |
|----|------|
| Address | 虚拟地址 |
| Kbytes | 虚拟大小 |
| RSS | 实际物理内存 |
| Dirty | 被修改的页（需要写回） |
| Mode | 权限（r=读, w=写, x=执行） |
| Mapping | 映射来源（文件名、[heap]、[stack]、[anon]） |

### 5.3 识别内存问题

```bash
# 找出占用最多内存的映射
pmap -x PID | sort -k2 -rn | head -10

# 关注的区域：
# [heap]  - 堆内存，动态分配
# [stack] - 栈内存，函数调用
# [anon]  - 匿名映射，mmap 分配
# 库文件  - 共享库

# 如果 [heap] 持续增长，可能是内存泄漏
```

### 5.4 追踪进程内存增长

```bash
#!/bin/bash
# track-memory.sh - 追踪进程内存变化
PID=$1
INTERVAL=${2:-5}

if [ -z "$PID" ]; then
    echo "Usage: $0 <PID> [interval_seconds]"
    exit 1
fi

echo "Tracking memory for PID $PID every $INTERVAL seconds"
echo "Time,VSZ(KB),RSS(KB),Heap(KB)"

while true; do
    if ! kill -0 $PID 2>/dev/null; then
        echo "Process $PID no longer exists"
        exit 1
    fi

    VSZ=$(ps -o vsz= -p $PID)
    RSS=$(ps -o rss= -p $PID)
    HEAP=$(pmap -x $PID 2>/dev/null | grep '\[heap\]' | awk '{print $2}')

    echo "$(date +%H:%M:%S),$VSZ,$RSS,${HEAP:-0}"
    sleep $INTERVAL
done
```

---

## Step 6 -- Slab 缓存和 slabtop（10 分钟）

### 6.1 什么是 Slab？

**Slab** 是内核用来高效分配小内存块的机制。内核数据结构（如 dentry、inode）都存在 Slab 中。

```bash
# 查看 Slab 总量
cat /proc/meminfo | grep -E "^Slab|^SReclaimable|^SUnreclaim"
# Slab:            500000 kB    # Slab 总量
# SReclaimable:    400000 kB    # 可回收的 Slab
# SUnreclaim:      100000 kB    # 不可回收的 Slab
```

| 指标 | 含义 |
|------|------|
| Slab | 内核 Slab 缓存总量 |
| SReclaimable | 可回收部分（如 dentry、inode 缓存） |
| SUnreclaim | 不可回收部分（内核正在使用） |

### 6.2 slabtop 实时监控

```bash
# 实时查看 Slab 使用
sudo slabtop

# 按使用量排序
sudo slabtop -s c

# 一次性输出（用于脚本）
sudo slabtop -o | head -20
```

**slabtop 输出示例**：

```
 Active / Total Objects (% used)    : 1234567 / 2000000 (61.7%)
 Active / Total Slabs (% used)      : 50000 / 80000 (62.5%)
 Active / Total Caches (% used)     : 100 / 150 (66.7%)
 Active / Total Size (% used)       : 400000.00K / 600000.00K (66.7%)

  OBJS ACTIVE  USE OBJ SIZE  SLABS OBJ/SLAB CACHE SIZE NAME
 500000 450000  90%    0.19K  25000       20    100000K dentry
 300000 280000  93%    0.57K  10714       28    170624K inode_cache
 200000 180000  90%    0.06K   3125       64     12500K buffer_head
```

### 6.3 dentry/inode 缓存膨胀

**常见问题**：文件服务器上 dentry/inode 缓存膨胀，占用大量内存。

```bash
# 查看 dentry 和 inode 缓存大小
sudo slabtop -o | grep -E "dentry|inode" | head -5

# 这是正常行为！访问过的目录项和文件元数据被缓存
# 除非造成内存压力，否则不需要干预
```

### 6.4 手动触发缓存回收（谨慎使用！）

```bash
# ⚠️ 仅用于测试/实验，生产环境慎用！
# 释放 pagecache, dentries, inodes
sync; echo 3 > /proc/sys/vm/drop_caches

# 选项：
# 1 = 释放 pagecache
# 2 = 释放 dentries + inodes
# 3 = 释放全部
```

> **警告**：在生产环境执行 `drop_caches` 会导致性能下降！  
> 缓存是有价值的，强制清除后需要重新从磁盘读取。  

---

## Step 7 -- PSI Memory 压力检测（10 分钟）

### 7.1 PSI Memory 指标

```bash
cat /proc/pressure/memory
# some avg10=0.50 avg60=0.20 avg300=0.10 total=12345678
# full avg10=0.00 avg60=0.00 avg300=0.00 total=123456
```

| 指标 | 含义 | 警戒线 |
|------|------|--------|
| some | 有进程因内存不足而等待 | > 10% 需关注 |
| full | 所有进程都在等待内存 | > 0 是严重问题 |

### 7.2 Memory Pressure 与性能关系

```
Memory Pressure = 系统在做内存回收/换页

影响：
• 内存回收占用 CPU 时间
• 换页导致 I/O 增加
• 应用响应变慢
```

### 7.3 PSI 监控脚本

```bash
#!/bin/bash
# psi-memory-monitor.sh - 内存压力监控

WARN_THRESHOLD=10
CRIT_THRESHOLD=25

while true; do
    some=$(awk '/^some/ {print $2}' /proc/pressure/memory | cut -d= -f2)
    full=$(awk '/^full/ {print $2}' /proc/pressure/memory | cut -d= -f2)

    some_int=${some%.*}
    full_int=${full%.*}

    timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    if [ "$full_int" -gt 0 ]; then
        echo "[$timestamp] CRITICAL: Memory full pressure = ${full}%"
    elif [ "$some_int" -gt "$CRIT_THRESHOLD" ]; then
        echo "[$timestamp] CRITICAL: Memory some pressure = ${some}%"
    elif [ "$some_int" -gt "$WARN_THRESHOLD" ]; then
        echo "[$timestamp] WARNING: Memory some pressure = ${some}%"
    else
        echo "[$timestamp] OK: Memory pressure some=${some}%, full=${full}%"
    fi

    sleep 5
done
```

---

## Step 8 -- OOM Killer 机制（15 分钟）

### 8.1 什么是 OOM Killer？

当系统内存完全耗尽，无法继续分配时，内核会启动 **OOM Killer**（Out of Memory Killer），
选择并杀死进程来释放内存。

<!-- DIAGRAM: oom-killer-flow -->
```
┌─────────────────────────────────────────────────────────────────────┐
│                       OOM Killer 触发流程                            │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│   内存分配请求                                                       │
│        │                                                             │
│        ▼                                                             │
│   ┌─────────────┐                                                   │
│   │ 有足够内存？ │──── Yes ────▶ 分配成功                            │
│   └──────┬──────┘                                                   │
│          │ No                                                        │
│          ▼                                                           │
│   ┌─────────────┐                                                   │
│   │ 尝试回收内存 │                                                   │
│   │ (Page Cache,│                                                   │
│   │  Slab, Swap)│                                                   │
│   └──────┬──────┘                                                   │
│          │                                                           │
│          ▼                                                           │
│   ┌─────────────┐                                                   │
│   │ 回收成功？   │──── Yes ────▶ 分配成功                            │
│   └──────┬──────┘                                                   │
│          │ No                                                        │
│          ▼                                                           │
│   ┌─────────────────────────────────────────────────────────────┐   │
│   │                    OOM Killer 启动                           │   │
│   │  1. 计算每个进程的 oom_score                                 │   │
│   │  2. 选择 oom_score 最高的进程                                │   │
│   │  3. 发送 SIGKILL 杀死该进程                                  │   │
│   │  4. 释放内存                                                 │   │
│   └─────────────────────────────────────────────────────────────┘   │
│                                                                      │
│   oom_score 计算因素：                                              │
│   • 进程使用的内存量（越大分数越高）                                 │
│   • 进程运行时间（越短分数越高）                                     │
│   • root 用户进程有一定保护                                         │
│   • oom_score_adj 手动调整值                                        │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```
<!-- /DIAGRAM -->

### 8.2 查看进程的 OOM 分数

```bash
# 查看进程的 OOM 分数（0-1000，越高越容易被杀）
cat /proc/PID/oom_score

# 查看所有进程的 OOM 分数
for pid in $(ls /proc | grep -E '^[0-9]+$'); do
    if [ -f /proc/$pid/oom_score ]; then
        name=$(cat /proc/$pid/comm 2>/dev/null || echo "unknown")
        score=$(cat /proc/$pid/oom_score 2>/dev/null || echo "0")
        echo "$score $pid $name"
    fi
done | sort -rn | head -10
```

### 8.3 oom_score_adj 调整

```bash
# 查看调整值（-1000 到 1000）
cat /proc/PID/oom_score_adj

# 设置调整值
# -1000 = 永不被 OOM Killer 杀死
# 1000 = 最优先被杀
echo -500 > /proc/PID/oom_score_adj

# 保护关键服务（systemd 方式）
sudo systemctl edit myservice.service
# 添加：
# [Service]
# OOMScoreAdjust=-500
```

### 8.4 查看 OOM 事件日志

```bash
# dmesg 中查找 OOM 事件
dmesg | grep -i "out of memory" -A 30

# journalctl 查找
journalctl -k | grep -i "oom"

# 典型 OOM 日志：
# Out of memory: Killed process 12345 (java) total-vm:2000000kB, anon-rss:1500000kB
# oom-kill:constraint=CONSTRAINT_NONE,nodemask=(null),cpuset=/...
```

### 8.5 OOM 保护策略

```bash
# 方法 1：调整 oom_score_adj
# 保护重要服务
echo -500 | sudo tee /proc/$(pgrep mysqld)/oom_score_adj

# 方法 2：使用 systemd 资源限制
sudo systemctl edit myservice.service
# [Service]
# MemoryMax=2G
# MemoryHigh=1.8G

# 方法 3：配置 systemd-oomd（主动式 OOM 管理）
# systemd-oomd 在 PSI 压力达到阈值时主动杀进程
# 比内核 OOM Killer 更可控
```

---

## Step 9 -- 动手实验（30 分钟）

### 实验 1：Memory Pressure + Reclaim Storm（Codex 场景）

> **场景**：新应用部署后，RSS 持续增长，swap 虽然是 0，但响应延迟明显上升。  
> 你需要诊断是 Page Cache 回收风暴还是真正的内存泄漏。  

```bash
# 1. 模拟内存压力（创建内存消耗进程）
# 注意：这会消耗内存，确保系统有足够 RAM！
python3 -c "
import time
data = []
print('Allocating memory...')
for i in range(50):  # 分配约 500MB
    data.append('x' * 10_000_000)
    print(f'Allocated {(i+1)*10}MB, total: {len(data)*10}MB')
    time.sleep(0.5)
print('Holding memory for 60 seconds...')
time.sleep(60)
" &
MEM_PID=$!
echo "Started memory consumer (PID: $MEM_PID)"

# 2. 观察内存变化
watch -n 1 'free -h; echo ""; cat /proc/pressure/memory'

# 3. 使用 vmstat 观察内存回收活动
vmstat 1 10
# 关注 si/so 列（swap in/out）
# 关注 free/buff/cache 变化

# 4. 使用 smem 定位内存消耗者
smem -rs pss | head -10

# 5. 区分 Page Cache 和 Anonymous Memory
cat /proc/meminfo | grep -E "^Cached|^AnonPages"
# 如果 AnonPages 增长 = 进程真的在用内存
# 如果 Cached 减少 = Page Cache 被回收

# 6. 清理
kill $MEM_PID 2>/dev/null
wait $MEM_PID 2>/dev/null
echo "Cleanup done"
```

**检查清单**：
- [ ] free 的 available 减少了吗？
- [ ] PSI memory 的 some 值增加了吗？
- [ ] vmstat 的 si/so 有活动吗？
- [ ] smem 能定位到消耗内存的进程吗？
- [ ] AnonPages 增长了吗？

### 实验 2：The Leak That Wasn't（Gemini 场景 - Slab Fragmentation）

> **场景**：ファイルサーバー（文件服务器）上 antivirus 进程突然被 OOM Killer 杀死。  
> free 显示可用内存很少，但 ps 统计的 RSS 只占总内存的 40%。  
> "内存去哪了？"  

```bash
# 1. 模拟大量小文件访问（会膨胀 dentry/inode 缓存）
# 创建测试目录结构
mkdir -p /tmp/slab-test
cd /tmp/slab-test

echo "Creating 10000 small files..."
for i in {1..10000}; do
    echo "test content $i" > file_$i.txt
done

# 触发文件系统遍历（膨胀 dentry/inode 缓存）
echo "Traversing files to populate cache..."
find /tmp/slab-test -type f | wc -l
ls -la /tmp/slab-test > /dev/null
stat /tmp/slab-test/* > /dev/null 2>&1

# 2. 检查 Slab 使用
echo ""
echo "=== Slab Memory Usage ==="
cat /proc/meminfo | grep -E "^Slab|^SReclaimable|^SUnreclaim"

echo ""
echo "=== Top Slab Caches ==="
sudo slabtop -o | head -15

# 3. 对比 free 和 ps
echo ""
echo "=== Free Memory ==="
free -h

echo ""
echo "=== Total Process RSS ==="
ps aux | awk 'NR>1 {sum += $6} END {printf "Total RSS: %.2f GB\n", sum/1024/1024}'

# 4. 计算"内存去哪了"
echo ""
echo "=== Memory Breakdown ==="
awk '
/^MemTotal:/ { total = $2 }
/^MemFree:/ { free = $2 }
/^Cached:/ { cached = $2 }
/^Buffers:/ { buffers = $2 }
/^Slab:/ { slab = $2 }
/^AnonPages:/ { anon = $2 }
END {
    printf "Total: %.2f GB\n", total/1024/1024
    printf "Anonymous (process): %.2f GB\n", anon/1024/1024
    printf "Page Cache: %.2f GB\n", cached/1024/1024
    printf "Slab: %.2f GB\n", slab/1024/1024
    printf "Free: %.2f GB\n", free/1024/1024
    accounted = anon + cached + slab + free
    printf "Accounted: %.2f GB\n", accounted/1024/1024
    printf "Unaccounted: %.2f GB\n", (total - accounted)/1024/1024
}
' /proc/meminfo

# 5. 清理
rm -rf /tmp/slab-test
echo ""
echo "Cleanup done"
```

**检查清单**：
- [ ] Slab 使用量是否明显？
- [ ] dentry/inode_cache 在 slabtop 中排名靠前吗？
- [ ] free 的"lost"内存是否能用 Slab 解释？
- [ ] 这是 Slab fragmentation，不是内存泄漏！

---

## 内存分析 Cheatsheet（速查表）

```bash
# =============================================================================
# Memory Analysis Cheatsheet
# =============================================================================

# --- 快速概览 ---
free -h                              # 内存概览（看 available！）
free -wh                             # 分离 buffers 和 cache
cat /proc/pressure/memory            # PSI 内存压力

# --- 详细分析 ---
cat /proc/meminfo | head -30         # 完整内存信息
cat /proc/meminfo | grep -E "^Mem|^Swap|^Cached|^Slab|^Anon"

# --- 进程内存 ---
ps aux --sort=-%mem | head -10       # RSS 排行（不准确）
smem -rs pss | head -10              # PSS 排行（推荐！）
smem -rs uss | head -10              # USS 排行（杀进程能释放多少）
smem -tk                             # 显示总计

# --- 进程内存详情 ---
pmap -x PID                          # 内存映射详情
pmap -x PID | grep '\[heap\]'        # 堆内存

# --- Slab 缓存 ---
cat /proc/meminfo | grep Slab        # Slab 总量
sudo slabtop -o | head -15           # Slab 详情

# --- 内存压力 ---
vmstat 1 5                           # si/so = swap in/out
cat /proc/pressure/memory            # PSI 压力

# --- OOM 相关 ---
dmesg | grep -i "out of memory"      # OOM 事件
cat /proc/PID/oom_score              # 进程 OOM 分数
cat /proc/PID/oom_score_adj          # OOM 调整值

# --- 内存回收（谨慎！）---
sync; echo 3 > /proc/sys/vm/drop_caches  # 清除缓存（生产环境慎用！）
```

---

## 反模式：常见错误

### 错误 1：强制 drop_caches 释放内存

```bash
# 错误做法
# "内存不够了，清一下缓存！"
sync; echo 3 > /proc/sys/vm/drop_caches

# 正确理解
# Page Cache 是有价值的！
# 清除后应用需要重新从磁盘读取，性能会下降
# 只有在测试/调试时才用 drop_caches
```

**正确做法**：
1. 检查 `available` 是否真的不足
2. 如果 `available` 低，用 `smem` 找出真正的内存大户
3. 优化应用或增加内存

### 错误 2："Swap 是坏的，应该禁用"

```bash
# 错误做法
sudo swapoff -a
# "Swap 会让系统变慢，禁用它！"

# 正确理解
# Swap 允许内核将不活跃的匿名页换出
# 即使有足够内存，少量 Swap 使用也是正常的
# 完全禁用 Swap + 内存耗尽 = 直接 OOM！
```

**正确做法**：
1. 监控 `vmstat si/so`，只有频繁 swap in/out 才是问题
2. 调整 `vm.swappiness`（默认 60，可调低到 10-30）
3. 保留 Swap 作为安全缓冲

### 错误 3：把 RSS 当作真实内存使用

```bash
# 错误做法
ps aux --sort=-%mem | head -10
# "这些进程 RSS 加起来超过物理内存了！系统有问题！"

# 正确理解
# RSS 包含共享库，多个进程会重复计算
# 10 个进程都加载 libc.so，RSS 会计算 10 次！
```

**正确做法**：
```bash
# 使用 PSS（按比例分摊共享内存）
smem -rs pss | head -10

# 或使用 USS（独占内存）
smem -rs uss | head -10
```

---

## 职场小贴士（Japan IT Context）

### OOM Killer でサービス停止 - 原因調査

在日本 IT 企业，OOM 导致的服务停止是严重的 障害（故障）。

| 日语术语 | 读音 | 含义 |
|----------|------|------|
| メモリ不足 | メモリぶそく | Memory shortage |
| メモリリーク | メモリリーク | Memory leak |
| OOMキラー | OOMキラー | OOM Killer |
| 障害対応 | しょうがいたいおう | Incident response |
| 原因調査 | げんいんちょうさ | Root cause analysis |

### OOM 調査報告書テンプレート

```
========================================
障害報告書 / OOM Killer によるサービス停止
========================================

【発生日時】2026-01-10 14:30 JST

【影響範囲】
- アプリケーションサーバー 1 台
- サービス停止時間：約 5 分

【症状】
- OOM Killer により Java プロセスが強制終了
- dmesg: "Out of memory: Killed process 12345 (java)"

【調査結果】

1. メモリ状況
   MemTotal:      16GB
   MemAvailable:  100MB (0.6%)  ← 枯渇状態
   SwapUsed:      2GB (100%)     ← Swap も枯渇

2. メモリ消費内訳
   AnonPages:     14GB           ← プロセスが使用
   Slab:          500MB          ← 正常範囲
   Cached:        200MB          ← ほぼ回収済み

3. 原因特定
   - smem で確認：Java プロセスの PSS が 13GB
   - ヒープダンプ分析：HashMap のメモリリーク検出
   - 原因コード：UserSessionCache の unbounded growth

【対策】
1. 即時対応：Java ヒープサイズを 8GB に制限
2. 恒久対策：UserSessionCache に TTL と最大サイズを設定
3. 監視強化：PSI memory > 20% でアラート設定

【エビデンス】
- dmesg ログ：添付
- smem 出力：添付
- ヒープダンプ分析：添付
```

### メモリ分析は障害対応の重要スキル

日本の IT 運用現場では：

1. **エビデンス重視** - 推測ではなくデータで説明
2. **根本原因の特定** - 「メモリ不足」で終わらず、なぜ不足したかまで追求
3. **再発防止策** - 監視・制限・コード修正の 3 点セット

---

## 面试准备（Interview Prep）

### Q1: free の buff/cache が大きいのは問題ですか？

**回答要点**：

```
問題ではありません。

Linux は未使用メモリを Page Cache として活用し、
ディスク I/O を高速化しています。

free コマンドで見るべきは：
- used や free ではなく
- available（真の空き容量）

buff/cache はアプリケーションが必要な時に
自動的に解放されます。
「available」が十分あれば、メモリは健全です。
```

### Q2: OOM Killer を防ぐ方法は？

**回答要点**：

```
複数の方法があります：

1. アプリケーションレベル
   - メモリリークの修正
   - ヒープサイズの適切な制限

2. システムレベル
   - systemd の MemoryMax/MemoryHigh 設定
   - 重要サービスの oom_score_adj を下げる

3. 監視レベル
   - PSI memory 監視でアラート
   - systemd-oomd で事前介入

4. インフラレベル
   - 十分な物理メモリ
   - 適切な Swap サイズ
```

### Q3: RSS と PSS の違いは？

**回答要点**：

```
RSS (Resident Set Size):
- プロセスが使用している物理メモリ
- 共享ライブラリを重複カウント
- 複数プロセスの RSS 合計 > 物理メモリ可能

PSS (Proportional Set Size):
- 共有メモリを使用プロセス数で按分
- より正確なメモリ使用量
- 全プロセスの PSS 合計 ≈ 実際のメモリ使用

推奨：
- smem コマンドで PSS を確認
- メモリ分析には PSS を使用
```

---

## 检查清单

完成本课后，你应该能够：

- [ ] 解释 Linux 内存模型（虚拟 vs 物理、Page Cache vs Anonymous）
- [ ] 正确解读 free 输出（知道 available 才是真正可用内存）
- [ ] 区分 VSZ, RSS, PSS, USS 四种进程内存指标
- [ ] 使用 smem 分析进程内存（PSS/USS）
- [ ] 使用 pmap -x 查看进程内存映射
- [ ] 使用 slabtop 分析内核 Slab 缓存
- [ ] 使用 PSI memory 检测内存压力
- [ ] 理解 OOM Killer 机制和 oom_score_adj
- [ ] 区分内存泄漏和 Slab/Cache 膨胀
- [ ] 避免常见反模式（强制 drop_caches、禁用 Swap）

---

## 本课小结

| 概念 | 命令/路径 | 记忆点 |
|------|-----------|--------|
| 内存概览 | `free -h` | 看 available，不是 free |
| 详细信息 | `/proc/meminfo` | AnonPages = 进程真正使用 |
| 进程内存 | `smem -rs pss` | PSS 比 RSS 准确 |
| 内存映射 | `pmap -x PID` | 看 [heap] 是否增长 |
| Slab 缓存 | `slabtop` | dentry/inode 可能膨胀 |
| 内存压力 | `/proc/pressure/memory` | some > 10% 需关注 |
| OOM 保护 | `oom_score_adj` | -1000 永不被杀 |

**关键洞察**：
- buff/cache 不是浪费，是 Linux 智慧
- 用 PSS/USS 分析进程内存，RSS 不准确
- Slab 膨胀不是泄漏，是缓存
- 保留 Swap 作为安全缓冲
- PSI memory 比传统指标更准确

---

## 延伸阅读

- [Linux Memory Management Documentation](https://www.kernel.org/doc/html/latest/admin-guide/mm/index.html)
- [Understanding Linux Memory Usage](https://www.brendangregg.com/blog/2017-08-06/linuxmemory.html)
- [smem Memory Reporting Tool](https://www.selenic.com/smem/)
- 上一课：[02 - CPU 分析](../02-cpu-analysis/) -- CPU 性能分析
- 下一课：[04 - I/O 分析](../04-io-analysis/) -- 磁盘 I/O 性能分析
- 相关课程：[LX07 - 存储管理](../../storage/) -- 理解块设备和文件系统

---

## 系列导航

[<-- 02 - CPU 分析](../02-cpu-analysis/) | [系列首页](../) | [04 - I/O 分析 -->](../04-io-analysis/)
