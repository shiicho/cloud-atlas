# 07 - perf 性能分析器

> **目标**：掌握 Linux 内核自带的 perf 性能分析器，学会 CPU profiling 和调用图生成  
> **前置**：LX09-06 strace（理解系统调用追踪）  
> **时间**：⚡ 20 分钟（速读）/ 🔬 75 分钟（完整实操）  
> **实战场景**：CPU 使用率が高い原因の特定、perf プロファイリング  

---

## 将学到的内容

1. 理解 perf 工具集概览
2. 使用 perf top 实时 CPU 分析
3. 使用 perf record 录制性能数据（-F 采样频率、-a/-p 范围、-g 调用图）
4. 使用 perf report 分析热点函数和调用栈
5. 使用 perf script 导出原始数据（为 Flamegraph 做准备）
6. 使用 perf stat 获取硬件计数器
7. 生产环境注意事项：开销评估、采样时间控制

---

## 先跑起来！（10 分钟）

> 在学习 perf 原理之前，先体验它的强大能力。  
> 运行这些命令，你将立即看到系统中哪些函数消耗最多 CPU。  

```bash
# 安装 perf（如果尚未安装）
# Ubuntu/Debian:
sudo apt install linux-tools-common linux-tools-$(uname -r) -y 2>/dev/null || true
# RHEL/CentOS:
sudo yum install perf -y 2>/dev/null || true

# 实时查看 CPU 热点函数（按 q 退出）
sudo perf top

# 录制 10 秒的 CPU 数据
sudo perf record -F 99 -a -g -- sleep 10

# 查看分析报告
sudo perf report
```

**你刚刚完成了 CPU profiling！**

- `perf top` 实时显示哪些函数正在消耗 CPU
- `perf record` 录制了 10 秒的采样数据
- `perf report` 让你交互式地分析热点

**接下来，让我们深入理解每个命令的原理和最佳实践。**

---

## Step 1 - perf 工具集概览（10 分钟）

### 1.1 什么是 perf？

**perf** 是 Linux 内核自带的性能分析工具，由 Ingo Molnar 开发，是内核的一部分。

**核心优势**：
- **内核级集成**：直接访问 CPU 性能计数器和内核追踪点
- **低开销**：采样式分析，适合生产环境
- **全面覆盖**：CPU、缓存、分支预测、系统调用等
- **Flamegraph 基础**：下一课将用 perf 数据生成火焰图

### 1.2 perf 子命令一览

<!-- DIAGRAM: perf-tools-overview -->
```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           perf 工具集概览                                    │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌───────────────────────────────────────────────────────────────────────┐ │
│  │  实时分析                                                              │ │
│  │                                                                       │ │
│  │  perf top         实时 CPU 热点函数（类似 top 但函数级别）              │ │
│  │                   交互式，按 q 退出                                    │ │
│  └───────────────────────────────────────────────────────────────────────┘ │
│                                                                             │
│  ┌───────────────────────────────────────────────────────────────────────┐ │
│  │  采样分析                                                              │ │
│  │                                                                       │ │
│  │  perf record      录制性能数据到 perf.data 文件                        │ │
│  │  perf report      交互式分析 perf.data                                 │ │
│  │  perf script      导出原始事件（给 Flamegraph 用）                     │ │
│  └───────────────────────────────────────────────────────────────────────┘ │
│                                                                             │
│  ┌───────────────────────────────────────────────────────────────────────┐ │
│  │  计数统计                                                              │ │
│  │                                                                       │ │
│  │  perf stat        运行命令并统计硬件计数器（cycles, instructions等）   │ │
│  │                   不采样，精确计数                                     │ │
│  └───────────────────────────────────────────────────────────────────────┘ │
│                                                                             │
│  ┌───────────────────────────────────────────────────────────────────────┐ │
│  │  高级功能                                                              │ │
│  │                                                                       │ │
│  │  perf trace       类似 strace 但开销更低                               │ │
│  │  perf sched       调度器分析                                           │ │
│  │  perf mem         内存访问分析                                         │ │
│  │  perf list        列出所有可用事件                                     │ │
│  └───────────────────────────────────────────────────────────────────────┘ │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```
<!-- /DIAGRAM -->

### 1.3 perf vs strace

| 对比项 | perf | strace |
|--------|------|--------|
| 分析对象 | CPU 时间、硬件计数器 | 系统调用 |
| 分析方式 | 采样（Sampling） | 追踪（Tracing） |
| 开销 | 低（1-5%） | 高（10-100x） |
| 生产环境 | 适合（短时间采样） | 慎用（开销大） |
| 输出 | 函数热点、调用栈 | 系统调用详情 |
| 典型场景 | "哪个函数占用 CPU？" | "程序在调用什么？" |

**使用场景选择**：
- **CPU 高**：先用 perf 定位热点函数
- **程序卡住**：先用 strace 看系统调用
- **需要 Flamegraph**：用 perf record

---

## Step 2 - perf top：实时 CPU 分析（10 分钟）

### 2.1 基本用法

```bash
# 系统范围实时分析（需要 root）
sudo perf top

# 分析特定进程
sudo perf top -p $(pgrep -f "your_process")

# 显示调用图
sudo perf top -g

# 按 q 退出，按 h 查看帮助
```

### 2.2 界面解读

```
Samples: 42K of event 'cycles', Event count (approx.): 28571428571
Overhead  Shared Object       Symbol
  12.50%  [kernel]            [k] _raw_spin_unlock_irqrestore
   8.30%  libc.so.6           [.] __memcpy_avx_unaligned
   5.20%  python3.9           [.] PyEval_EvalFrameDefault
   4.10%  [kernel]            [k] copy_user_enhanced_fast_string
   3.80%  libpthread.so.0     [.] pthread_mutex_lock
```

**字段含义**：

| 字段 | 含义 |
|------|------|
| Overhead | 该函数占用的 CPU 时间比例 |
| Shared Object | 来源（kernel 或 具体库/程序） |
| Symbol | 函数名（[k] = kernel, [.] = user space） |

### 2.3 交互操作

在 `perf top` 界面中：

| 按键 | 功能 |
|------|------|
| `q` | 退出 |
| `h` 或 `?` | 帮助菜单 |
| `E` | 展开/折叠调用栈 |
| `Enter` | 进入函数详情 |
| `s` | 按符号搜索 |
| `P` | 按 PID 过滤 |

### 2.4 实战：定位 CPU 消耗进程

```bash
# 创建一个 CPU 消耗测试程序
cat > /tmp/cpu_burner.py << 'EOF'
import hashlib
import time

def burn_cpu():
    while True:
        # 无意义的 hash 计算消耗 CPU
        hashlib.sha256(b"burn" * 10000).hexdigest()

if __name__ == "__main__":
    print("Starting CPU burner...")
    burn_cpu()
EOF

# 后台运行
python3 /tmp/cpu_burner.py &
BURNER_PID=$!
echo "CPU burner PID: $BURNER_PID"

# 用 perf top 观察
sudo perf top -p $BURNER_PID

# 清理
kill $BURNER_PID 2>/dev/null
```

---

## Step 3 - perf record：录制性能数据（15 分钟）

### 3.1 核心参数详解

```bash
perf record [选项] -- [命令]
```

**关键参数**：

<!-- DIAGRAM: perf-record-options -->
```
┌─────────────────────────────────────────────────────────────────────────────┐
│                       perf record 关键参数                                   │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │  -F 99    采样频率（Sampling Frequency）                             │   │
│  │                                                                      │   │
│  │  • 99 Hz = 每秒采样 99 次                                            │   │
│  │  • 为什么是 99 而不是 100？                                          │   │
│  │    → 避免与系统定时器 (100Hz) 产生 aliasing（叠加效应）              │   │
│  │  • 生产环境推荐：99 Hz（低开销）                                     │   │
│  │  • 调试环境可用：999 Hz（更精确，但开销更大）                        │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │  -a / -p PID    采样范围                                             │   │
│  │                                                                      │   │
│  │  -a           系统范围（所有 CPU、所有进程）                          │   │
│  │  -p PID       仅采样指定进程                                         │   │
│  │  -p PID1,PID2 采样多个进程                                           │   │
│  │                                                                      │   │
│  │  建议：生产环境用 -p 缩小范围，减少数据量和开销                       │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │  -g    调用图（Call Graph）                                          │   │
│  │                                                                      │   │
│  │  • 记录函数调用栈，不仅是热点函数                                    │   │
│  │  • 为 Flamegraph 生成必须的参数！                                    │   │
│  │  • 开销略大，但信息量丰富                                            │   │
│  │                                                                      │   │
│  │  调用图类型（--call-graph）：                                        │   │
│  │  • fp    基于栈帧指针（Frame Pointer）- 默认                         │   │
│  │  • dwarf 基于 DWARF 调试信息 - 更准确但更慢                          │   │
│  │  • lbr   基于 Last Branch Record（Intel CPU）- 最低开销              │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │  -o FILE    输出文件                                                 │   │
│  │                                                                      │   │
│  │  默认输出到 perf.data                                                │   │
│  │  可以指定：-o my_profile.data                                        │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```
<!-- /DIAGRAM -->

### 3.2 常用命令模式

```bash
# 模式 1：系统范围采样 30 秒
sudo perf record -F 99 -a -g -- sleep 30

# 模式 2：采样特定进程 30 秒
sudo perf record -F 99 -p $(pgrep -f "nginx") -g -- sleep 30

# 模式 3：采样命令执行全程
sudo perf record -F 99 -g -- ./my_program arg1 arg2

# 模式 4：采样指定事件
sudo perf record -e cycles,cache-misses -a -g -- sleep 10
```

### 3.3 采样频率选择指南

| 场景 | 推荐频率 | 说明 |
|------|----------|------|
| 生产环境快速诊断 | `-F 99` | 低开销，足够识别热点 |
| 详细分析 | `-F 999` | 更精确，开销约 1-3% |
| 极短时间采样 | `-F 4999` | 5秒内快速获取足够样本 |
| 长时间监控 | `-F 49` | 最小开销 |

**关键原则**：采样频率越高，数据越精确，但开销越大。

### 3.4 实战：录制 CPU 热点

```bash
# 创建工作目录
mkdir -p ~/perf-lab && cd ~/perf-lab

# 启动 CPU 消耗程序
python3 /tmp/cpu_burner.py &
BURNER_PID=$!
echo "CPU burner PID: $BURNER_PID"

# 录制 10 秒性能数据
sudo perf record -F 99 -p $BURNER_PID -g -o cpu_profile.data -- sleep 10

# 查看录制结果
ls -lh cpu_profile.data

# 清理
kill $BURNER_PID 2>/dev/null
```

---

## Step 4 - perf report：分析结果（15 分钟）

### 4.1 基本用法

```bash
# 交互式分析（默认）
sudo perf report

# 指定数据文件
sudo perf report -i cpu_profile.data

# 文本输出（非交互式）
sudo perf report --stdio

# 只显示前 20 个热点
sudo perf report --stdio | head -50
```

### 4.2 交互式界面解读

```
Samples: 9K of event 'cycles', Event count (approx.): 6571428571
  Children      Self  Command  Shared Object       Symbol
+   95.50%     0.00%  python3  [unknown]           [.] 0x00005555555548c0
+   75.30%    15.20%  python3  libcrypto.so.1.1    [.] SHA256_Update
+   60.10%    60.10%  python3  libcrypto.so.1.1    [.] sha256_block_data_order_avx2
+   12.50%     0.00%  python3  libc.so.6           [.] __libc_start_main
+    8.30%     8.30%  python3  python3.9           [.] PyEval_EvalFrameDefault
```

**字段含义**：

| 字段 | 含义 |
|------|------|
| Children | 该函数及其调用的所有子函数的 CPU 占比 |
| Self | 该函数自身（不含子函数）的 CPU 占比 |
| Command | 进程/命令名 |
| Shared Object | 函数所在的库或可执行文件 |
| Symbol | 函数名 |

**关键解读**：
- **Self 高**：该函数本身消耗 CPU（需要优化这个函数）
- **Children 高但 Self 低**：CPU 消耗在其调用的子函数中

### 4.3 交互操作

在 `perf report` 界面中：

| 按键 | 功能 |
|------|------|
| `Enter` | 展开/折叠调用栈 |
| `+` | 展开所有调用栈 |
| `-` | 折叠所有调用栈 |
| `a` | 显示函数汇编代码（Annotate） |
| `/` | 搜索函数名 |
| `q` | 退出 |
| `h` | 帮助 |

### 4.4 调用栈分析

```bash
# 展开调用栈查看
sudo perf report -g 'graph,0.5,caller'

# 输出调用栈（文本模式）
sudo perf report --stdio -g 'graph,0.5'
```

**输出示例**（调用栈展开）：

```
-   75.30%    15.20%  python3  libcrypto.so.1.1    [.] SHA256_Update
   - 60.10% sha256_block_data_order_avx2
        sha256_block_data_order
        SHA256_Update
        EVP_DigestUpdate
        _hashlib_HASH_update
        method_vectorcall_VARARGS
        _PyEval_EvalFrameDefault
        ...
```

**解读**：
- `SHA256_Update` 占用 75.30% CPU
- 其中 60.10% 是在 `sha256_block_data_order_avx2` 中消耗的
- 调用链从下到上：Python 调用 hashlib，hashlib 调用 OpenSSL

### 4.5 实战：分析 CPU 热点

```bash
cd ~/perf-lab

# 分析之前录制的数据
sudo perf report -i cpu_profile.data --stdio | head -30

# 交互式分析（按 Enter 展开调用栈）
sudo perf report -i cpu_profile.data
```

---

## Step 5 - perf script：导出原始数据（10 分钟）

### 5.1 为什么需要 perf script？

`perf script` 将二进制的 `perf.data` 导出为文本格式，主要用于：

1. **生成 Flamegraph**（下一课重点）
2. 自定义脚本处理
3. 长期存档分析数据

### 5.2 基本用法

```bash
# 导出全部数据
sudo perf script > profile.txt

# 指定输入文件
sudo perf script -i cpu_profile.data > profile.txt

# 只导出特定字段
sudo perf script -F comm,pid,tid,cpu,time,event,ip,sym,dso
```

### 5.3 输出格式

```
python3 12345/12345  2145.123456:   cycles:
        5555555554ab sha256_block_data_order_avx2+0x1b (/usr/lib/libcrypto.so.1.1)
        5555555548c0 SHA256_Update+0x80 (/usr/lib/libcrypto.so.1.1)
        5555555544a0 EVP_DigestUpdate+0x20 (/usr/lib/libcrypto.so.1.1)
        7ffff7b12340 _hashlib_HASH_update+0x40 (/usr/lib/python3.9)
        7ffff7a45670 method_vectorcall+0x30 (/usr/lib/libpython3.9.so.1.0)
```

### 5.4 为 Flamegraph 准备数据

```bash
# 标准 Flamegraph 工作流预览
# （详见下一课 08-flamegraphs）

# 1. 录制数据
sudo perf record -F 99 -a -g -- sleep 30

# 2. 导出为文本
sudo perf script > out.perf

# 3. 转换为 Flamegraph 格式（下一课详解）
# ./stackcollapse-perf.pl out.perf | ./flamegraph.pl > cpu.svg
```

---

## Step 6 - perf stat：硬件计数器（10 分钟）

### 6.1 什么是硬件计数器？

现代 CPU 内置了 **PMU（Performance Monitoring Unit）**，可以精确计数：

- CPU 周期数（cycles）
- 指令数（instructions）
- 缓存命中/未命中
- 分支预测成功/失败
- 等等

`perf stat` 直接读取这些计数器，**不是采样**，而是**精确计数**。

### 6.2 基本用法

```bash
# 统计命令执行的硬件计数器
perf stat ls -la /tmp

# 输出示例
 Performance counter stats for 'ls -la /tmp':

              2.15 msec task-clock                #    0.825 CPUs utilized
                 0      context-switches          #    0.000 K/sec
                 0      cpu-migrations            #    0.000 K/sec
               124      page-faults               #    0.058 M/sec
         5,234,567      cycles                    #    2.434 GHz
         3,876,543      instructions              #    0.74  insn per cycle
           654,321      branches                  #  304.335 M/sec
            12,345      branch-misses             #    1.89% of all branches

       0.002607025 seconds time elapsed
```

### 6.3 关键指标解读

| 指标 | 含义 | 健康值 |
|------|------|--------|
| cycles | CPU 周期数 | - |
| instructions | 执行的指令数 | - |
| insn per cycle (IPC) | 每周期指令数 | > 1.0 好，< 0.5 可能有问题 |
| branch-misses | 分支预测失败率 | < 5% 好 |
| cache-misses | 缓存未命中率 | < 10% 好 |

### 6.4 指定事件统计

```bash
# 统计特定事件
perf stat -e cycles,instructions,cache-misses,branch-misses ./my_program

# 统计 L1 缓存
perf stat -e L1-dcache-loads,L1-dcache-load-misses ./my_program

# 列出所有可用事件
perf list
```

### 6.5 实战：比较算法效率

```bash
# 创建测试程序
cat > /tmp/test_efficiency.py << 'EOF'
import sys

def linear_search(arr, target):
    for i, x in enumerate(arr):
        if x == target:
            return i
    return -1

def binary_search(arr, target):
    left, right = 0, len(arr) - 1
    while left <= right:
        mid = (left + right) // 2
        if arr[mid] == target:
            return mid
        elif arr[mid] < target:
            left = mid + 1
        else:
            right = mid - 1
    return -1

data = list(range(100000))
target = 99999

if sys.argv[1] == "linear":
    for _ in range(100):
        linear_search(data, target)
else:
    for _ in range(100):
        binary_search(data, target)
EOF

# 比较两种搜索算法
echo "=== Linear Search ==="
perf stat python3 /tmp/test_efficiency.py linear

echo ""
echo "=== Binary Search ==="
perf stat python3 /tmp/test_efficiency.py binary
```

---

## Step 7 - 生产环境注意事项（10 分钟）

### 7.1 开销评估

<!-- DIAGRAM: perf-overhead -->
```
┌─────────────────────────────────────────────────────────────────────────────┐
│                       perf 开销评估指南                                      │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  采样频率 vs 开销                                                            │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                                                                      │   │
│  │  -F 49    极低开销（< 0.5%）   适合：长时间监控、7x24 采集            │   │
│  │                                                                      │   │
│  │  -F 99    低开销（0.5-1%）    适合：生产环境诊断（推荐）               │   │
│  │                                                                      │   │
│  │  -F 999   中等开销（1-3%）    适合：详细分析、非高峰时段               │   │
│  │                                                                      │   │
│  │  -F 4999  较高开销（3-10%）   适合：开发/测试环境、短时间采样          │   │
│  │                                                                      │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
│  其他开销因素                                                                │
│                                                                             │
│  • -g（调用图）：增加约 30-50% 开销，但信息量丰富                           │
│  • -a（全系统）：数据量大，磁盘 I/O 增加                                    │
│  • 采样时间：越长，perf.data 越大                                           │
│                                                                             │
│  生产环境黄金法则                                                            │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                                                                      │   │
│  │  1. 使用 -F 99（不是 999 或更高）                                     │   │
│  │  2. 限制采样时间（30 秒通常足够）                                     │   │
│  │  3. 用 -p PID 而非 -a（缩小范围）                                     │   │
│  │  4. 在低峰时段执行                                                    │   │
│  │  5. 监控 perf.data 文件大小                                           │   │
│  │                                                                      │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```
<!-- /DIAGRAM -->

### 7.2 云环境警告：AWS Steal Time

> **云实验室警告（Cloud Lab Warning）**  
>
> 在 AWS t2/t3 等突发型实例上运行 perf 时，可能遇到 **CPU steal time** 问题。  
>
> **问题现象**：  
> - `top` 或 `mpstat` 显示高 `%st`（steal time）  
> - perf 采样结果中出现大量 `[unknown]` 或异常数据  
> - 性能分析结果不稳定  
>
> **原因**：  
> - t2/t3 是突发型实例，依赖 CPU 积分（Credit）  
> - 积分耗尽后，hypervisor 会"偷取"你请求的 CPU 时间  
> - 这不是你的程序问题，是云平台限制  
>
> **检测方法**：  
> ```bash  
> # 查看 steal time  
> mpstat -P ALL 1 3  
> # 如果 %steal > 5%，你的分析结果可能不准确  
> ```  
>
> **解决方案**：  
> 1. 使用 m 系列实例（如 m5.large）— 无 CPU 积分限制  
> 2. 短时间采样，让积分恢复后再采样  
> 3. 使用 cgroup 限制模拟 CPU 约束，而非 stress 工具  
>
> **日本 IT 语境**：  
> 日本のクラウド運用では、t2/t3 インスタンスのクレジット枯渇は本番でも発生する。  
> "CPU が高いのに処理が遅い" という障害は、steal time を見落としがち。  

### 7.3 安全的生产采样模板

```bash
#!/bin/bash
# safe-perf-record.sh - 生产环境安全的 perf 采样脚本
# 使用方法: ./safe-perf-record.sh [PID] [秒数]

PID=${1:-""}
DURATION=${2:-30}
OUTPUT="perf_$(date +%Y%m%d_%H%M%S).data"

# 检查 steal time
STEAL=$(vmstat 1 2 | tail -1 | awk '{print $16}')
if [ "$STEAL" -gt 5 ]; then
    echo "警告：检测到 steal time = $STEAL%"
    echo "你可能在突发型云实例上，分析结果可能不准确"
    echo "继续？(y/n)"
    read -r confirm
    [ "$confirm" != "y" ] && exit 1
fi

# 构建命令
if [ -n "$PID" ]; then
    echo "采样进程 PID=$PID，持续 $DURATION 秒..."
    sudo perf record -F 99 -p "$PID" -g -o "$OUTPUT" -- sleep "$DURATION"
else
    echo "系统范围采样，持续 $DURATION 秒..."
    sudo perf record -F 99 -a -g -o "$OUTPUT" -- sleep "$DURATION"
fi

# 报告结果
echo ""
echo "采样完成！"
ls -lh "$OUTPUT"
echo ""
echo "分析命令："
echo "  sudo perf report -i $OUTPUT"
echo ""
echo "导出 Flamegraph 数据："
echo "  sudo perf script -i $OUTPUT > profile.txt"
```

### 7.4 符号解析问题

```bash
# 问题：perf report 显示 [unknown] 或十六进制地址
# 原因：缺少调试符号

# 解决方案 1：安装调试符号包
# Ubuntu/Debian
sudo apt install linux-image-$(uname -r)-dbgsym
sudo apt install libc6-dbg

# RHEL/CentOS
sudo debuginfo-install $(rpm -qf $(which python3))

# 解决方案 2：为自己的程序保留符号
# 编译时不要 strip
gcc -g -o my_program my_program.c  # 保留调试信息
```

---

## perf 命令速查表

```bash
# =============================================================================
# perf 命令速查表
# =============================================================================

# -----------------------------------------------------------------------------
# 实时分析
# -----------------------------------------------------------------------------
perf top                      # 系统范围实时热点
perf top -p PID               # 特定进程实时热点
perf top -g                   # 带调用图的实时热点

# -----------------------------------------------------------------------------
# 录制数据
# -----------------------------------------------------------------------------
# 基本录制
perf record -F 99 -a -g -- sleep 30     # 系统范围，30 秒
perf record -F 99 -p PID -g -- sleep 30  # 特定进程，30 秒
perf record -F 99 -g -- ./program        # 录制程序全程

# 参数说明
# -F 99    采样频率 99 Hz（推荐，低开销）
# -a       系统范围（所有 CPU）
# -p PID   特定进程
# -g       记录调用图（必须，为 Flamegraph 准备）
# -o FILE  输出文件（默认 perf.data）

# -----------------------------------------------------------------------------
# 分析结果
# -----------------------------------------------------------------------------
perf report                   # 交互式分析
perf report -i FILE           # 分析指定文件
perf report --stdio           # 文本输出
perf report --stdio | head -30 # 只看前 30 行

# 调用图选项
perf report -g 'graph,0.5,caller'  # 展开调用图

# -----------------------------------------------------------------------------
# 导出数据
# -----------------------------------------------------------------------------
perf script                   # 导出为文本（给 Flamegraph）
perf script -i FILE > out.txt # 导出指定文件

# -----------------------------------------------------------------------------
# 硬件计数器
# -----------------------------------------------------------------------------
perf stat ./program           # 统计程序的硬件计数器
perf stat -e cycles,instructions,cache-misses ./program  # 指定事件
perf list                     # 列出所有可用事件

# -----------------------------------------------------------------------------
# 高级功能
# -----------------------------------------------------------------------------
perf trace -p PID             # 类似 strace 但低开销
perf sched record             # 调度器分析
perf mem record               # 内存访问分析

# =============================================================================
# 生产环境黄金法则
# =============================================================================
# 1. 使用 -F 99（低频采样）
# 2. 限制时间（30 秒通常足够）
# 3. 用 -p PID 而非 -a（缩小范围）
# 4. 检查 steal time（云环境）
# 5. 保存原始数据（perf.data）供后续分析
```

---

## Mini-Project：CPU 热点定位（15 分钟）

### 任务目标

使用 perf 工具链完成一次完整的 CPU 热点分析。

### 步骤

```bash
# 1. 创建工作目录
mkdir -p ~/perf-lab && cd ~/perf-lab

# 2. 创建一个有性能问题的程序
cat > cpu_problem.py << 'EOF'
import hashlib
import time
import random

def slow_hash():
    """CPU 密集型操作"""
    for _ in range(1000):
        data = str(random.random()).encode()
        hashlib.sha256(data).hexdigest()

def fast_operation():
    """快速操作"""
    return sum(range(100))

def main():
    start = time.time()
    for i in range(100):
        slow_hash()     # 热点函数
        fast_operation()
    print(f"完成，耗时: {time.time() - start:.2f}s")

if __name__ == "__main__":
    main()
EOF

# 3. 先运行一次看耗时
python3 cpu_problem.py

# 4. 使用 perf 录制
sudo perf record -F 99 -g -- python3 cpu_problem.py

# 5. 分析热点
sudo perf report --stdio | head -40

# 6. 导出数据（为 Flamegraph 准备）
sudo perf script > cpu_profile.txt
echo "导出了 $(wc -l < cpu_profile.txt) 行数据"

# 7. 查看调用栈
sudo perf report -g 'graph,0.5,caller' --stdio | head -60
```

### 验证清单

- [ ] 成功录制了 perf.data 文件
- [ ] 在 perf report 中看到了 `SHA256` 相关函数
- [ ] 理解 Children vs Self 的区别
- [ ] 成功导出了 perf script 文本数据
- [ ] 能解释为什么 `slow_hash` 是热点函数

---

## Lab 场景 1：CPU Hotspots with perf + Flamegraph (Codex)

### 场景描述

> **症状**：CPU 持续 90%，需要证明哪个函数是热点  
> **工具**：perf record, perf report, Flamegraph（下一课）  
> **目标**：定位消耗 CPU 的具体函数  

### 模拟环境

```bash
# 创建模拟程序
cat > /tmp/hotspot_demo.py << 'EOF'
import time

def hot_function_a():
    """故意做大量计算"""
    total = 0
    for i in range(100000):
        total += i * i
    return total

def hot_function_b():
    """字符串操作"""
    s = ""
    for i in range(1000):
        s += str(i)
    return len(s)

def cool_function():
    """快速函数"""
    return 42

def main():
    while True:
        for _ in range(10):
            hot_function_a()  # 预期热点
        for _ in range(5):
            hot_function_b()  # 次热点
        cool_function()       # 冷函数
        time.sleep(0.01)

if __name__ == "__main__":
    print("Running hotspot demo... (Ctrl+C to stop)")
    main()
EOF

# 后台运行
python3 /tmp/hotspot_demo.py &
PID=$!
echo "Demo PID: $PID"

# 录制 15 秒
sudo perf record -F 99 -p $PID -g -- sleep 15

# 分析
sudo perf report --stdio | head -30

# 清理
kill $PID 2>/dev/null
```

### 分析要点

1. **识别热点函数**：`hot_function_a` 应该占用最多 CPU
2. **理解 Children vs Self**：
   - `main` 的 Children 高（调用了所有函数）
   - `hot_function_a` 的 Self 高（实际执行代码）
3. **为 Flamegraph 准备**：
   ```bash
   sudo perf script > hotspot.perf
   # 下一课将转换为火焰图
   ```

---

## Lab 场景 2：The Morning Rush - Lock Contention (Gemini)

### 场景描述

> **背景**：朝ラッシュの遅延（早高峰延迟）  
> **症状**：服务器从 8 核迁移到 32 核后，批处理时间反而增加了 40%  
> **日本 IT 语境**：夜間バッチ (08:00 締め切り) が間に合わない  
> **根因**：锁竞争 / 线程惊群效应  

### 分析步骤

```bash
# 模拟锁竞争程序
cat > /tmp/lock_contention.py << 'EOF'
import threading
import time

# 全局锁 - 所有线程竞争
lock = threading.Lock()
counter = 0

def worker(thread_id, iterations):
    global counter
    for _ in range(iterations):
        with lock:  # 锁竞争点
            counter += 1
            # 模拟临界区内的工作
            _ = sum(range(100))

def main(num_threads, iterations):
    threads = []
    start = time.time()

    for i in range(num_threads):
        t = threading.Thread(target=worker, args=(i, iterations))
        threads.append(t)
        t.start()

    for t in threads:
        t.join()

    elapsed = time.time() - start
    print(f"Threads: {num_threads}, Time: {elapsed:.2f}s, Counter: {counter}")

if __name__ == "__main__":
    import sys
    threads = int(sys.argv[1]) if len(sys.argv) > 1 else 4
    main(threads, 10000)
EOF

# 测试不同线程数的性能
echo "=== 4 threads ==="
time python3 /tmp/lock_contention.py 4

echo ""
echo "=== 16 threads ==="
time python3 /tmp/lock_contention.py 16

echo ""
echo "=== 32 threads ==="
time python3 /tmp/lock_contention.py 32
```

### 使用 perf 分析

```bash
# 录制 32 线程版本
python3 /tmp/lock_contention.py 32 &
PID=$!
sudo perf record -F 99 -p $PID -g -- sleep 5
kill $PID 2>/dev/null

# 分析
sudo perf report --stdio | grep -E "pthread|lock|futex" | head -20

# 预期看到：
# - pthread_mutex_lock 占用大量 CPU
# - futex 系统调用（内核锁等待）
```

### 关键发现

```
# perf report 可能显示：
  25.30%  python3  libpthread.so.0  [.] pthread_mutex_lock
  18.50%  python3  [kernel]         [k] futex_wait_queue_me
  12.30%  python3  [kernel]         [k] native_queued_spin_lock_slowpath
```

**结论**：增加线程数并没有线性提升性能，因为锁竞争成为瓶颈。

---

## 反模式：常见错误

### 错误 1：过度采样（Over-Sampling in Production）

```bash
# 错误：高频长时间采样
sudo perf record -F 999 -a -- sleep 600  # 10 分钟，999 Hz！
# 问题：
# - perf.data 可能达到几 GB
# - CPU 开销 3-10%
# - 可能影响生产性能

# 正确：低频短时间
sudo perf record -F 99 -a -g -- sleep 30  # 30 秒，99 Hz
```

### 错误 2：忘记 -g 参数

```bash
# 错误：没有 -g，无法生成 Flamegraph
sudo perf record -F 99 -a -- sleep 30
# 只能看到热点函数，看不到调用栈

# 正确：加上 -g
sudo perf record -F 99 -a -g -- sleep 30
# 可以看完整调用链，可以生成 Flamegraph
```

### 错误 3：符号丢失不处理

```bash
# 问题：perf report 显示大量 [unknown]
# 原因：缺少调试符号

# 解决：安装调试符号包
sudo apt install linux-image-$(uname -r)-dbgsym
sudo debuginfo-install python3

# 或者：对自己的程序保留符号
gcc -g -o program program.c  # 不要 strip
```

---

## 职场小贴士（Japan IT Context）

### CPU 使用率が高い原因の特定 - perf プロファイリング

在日本 IT 企业，当遇到 CPU 高的问题时，需要提供 **エビデンス（证据）**。

**报告模板**：

```markdown
## 障害報告：CPU 使用率高騰

### 発生日時
2026-01-10 14:30 JST

### 症状
Webサーバーの CPU 使用率が 90% 以上で推移

### 調査方法
perf によるプロファイリング（本番への影響を最小限に）

```bash
perf record -F 99 -p $(pgrep nginx) -g -- sleep 30
perf report --stdio
```

### 調査結果

| 関数名 | CPU 占有率 | 説明 |
|--------|-----------|------|
| SSL_read | 35.2% | TLS 暗号化処理 |
| ngx_http_gzip_body_filter | 22.1% | Gzip 圧縮 |
| malloc | 12.5% | メモリ割り当て |

### 結論
TLS 処理と Gzip 圧縮が CPU の主要消費元。

### 対策案
1. TLS オフロード（ロードバランサーで処理）
2. Gzip レベルを 6→4 に下げる（圧縮率と速度のトレードオフ）
3. CPU 追加を検討
```

### 本番環境での低オーバーヘッド分析

| 日语术语 | 读音 | 含义 |
|----------|------|------|
| 低オーバーヘッド | ていオーバーヘッド | Low overhead |
| 本番環境 | ほんばんかんきょう | Production environment |
| プロファイリング | プロファイリング | Profiling |
| ホットスポット | ホットスポット | Hotspot |
| ボトルネック | ボトルネック | Bottleneck |

---

## 面试准备（Interview Prep）

### Q1: perf record の -F 99 の意味は？

**回答要点**：

```
-F 99 はサンプリング周波数を 99Hz に設定します。
つまり、1秒間に 99 回 CPU の状態をサンプリングします。

なぜ 100 ではなく 99 か？
→ 100Hz はシステムタイマー (100Hz HZ) と同期し、
  aliasing（畳み込み効果）を起こす可能性がある。
  素数 (99) を使うことでこれを避けます。

本番環境では -F 99 が推奨されます：
- 低オーバーヘッド（約 1%）
- 十分なサンプル数でホットスポット特定可能
```

### Q2: perf のオーバーヘッドを抑えるには？

**回答要点**：

```
1. サンプリング周波数を下げる
   -F 99（推奨）、-F 49（長時間監視用）

2. 採取時間を短くする
   30 秒で十分な場合が多い

3. 範囲を絞る
   -a（全システム）ではなく -p PID（特定プロセス）

4. イベントを絞る
   デフォルトの cycles だけで十分な場合が多い

5. 低負荷時間帯に実行
   ピーク時を避ける

例：
sudo perf record -F 99 -p $PID -g -- sleep 30
```

### Q3: perf と strace の使い分けは？

**回答要点**：

```
perf:
- CPU 時間の分析（どの関数が CPU を消費しているか）
- サンプリング方式、低オーバーヘッド（1-5%）
- 本番環境で使用可能
- Flamegraph 生成に使用
- 使用場面：「CPU が高い原因は？」

strace:
- システムコールの追跡（何を呼んでいるか）
- トレース方式、高オーバーヘッド（10-100x）
- 本番では慎重に使用
- 使用場面：「プログラムが何をしているか？」「なぜブロックしているか？」

組み合わせ例：
1. まず perf で CPU ホットスポットを特定
2. 必要なら strace でシステムコールの詳細を確認
```

---

## 检查清单

完成本课后，你应该能够：

- [ ] 解释 perf 工具集的主要组件（top, record, report, script, stat）
- [ ] 使用 `perf top` 实时查看 CPU 热点
- [ ] 使用 `perf record -F 99 -g` 录制性能数据
- [ ] 解释 `-F 99` 参数的含义（采样频率，避免 aliasing）
- [ ] 区分 `-a`（系统范围）和 `-p PID`（特定进程）
- [ ] 使用 `perf report` 分析热点函数
- [ ] 理解 Children vs Self 的区别
- [ ] 使用 `perf script` 导出数据（为 Flamegraph 准备）
- [ ] 使用 `perf stat` 获取硬件计数器
- [ ] 解释生产环境中 perf 的开销控制策略
- [ ] 识别云环境中的 steal time 问题

---

## 本课小结

| 概念 | 要点 |
|------|------|
| perf top | 实时 CPU 热点分析，类似 top 但函数级别 |
| perf record | 录制性能数据，`-F 99 -g` 是关键参数 |
| perf report | 交互式分析，Children vs Self 理解热点 |
| perf script | 导出原始数据，为 Flamegraph 准备 |
| perf stat | 硬件计数器精确统计，IPC 是关键指标 |
| 生产考量 | 低频采样、短时间、缩小范围、注意 steal time |
| -F 99 | 99Hz 采样，避免与系统定时器 aliasing |
| -g | 记录调用图，Flamegraph 必需 |

---

## 延伸阅读

- [Brendan Gregg 的 perf 教程](https://www.brendangregg.com/perf.html)
- [Linux perf Wiki](https://perf.wiki.kernel.org/)
- 下一课：[08 - Flamegraph 火焰图](../08-flamegraphs/) - 将 perf 数据可视化
- 前一课：[06 - strace 系统调用追踪](../06-strace/)

---

## 系列导航

[<-- 06 - strace](../06-strace/) | [系列首页](../) | [08 - Flamegraph -->](../08-flamegraphs/)
