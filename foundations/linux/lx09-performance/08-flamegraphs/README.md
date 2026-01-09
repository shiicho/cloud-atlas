# 08 - Flamegraph 火焰图

> **目标**：掌握 Flamegraph 解读与生成技能，学会用可视化定位 CPU 热点和性能瓶颈  
> **前置**：Lesson 07 perf 性能分析器（perf record、perf script）  
> **时间**：60-90 分钟  
> **实战场景**：性能レポートへの可視化、CPU 热点分析、性能优化前后对比  

---

## 将学到的内容

1. 解读 Flamegraph 可视化（宽度 = 时间占比，栈底到顶的调用关系）
2. 识别"热点"函数（宽的顶部帧）
3. 从 perf 数据生成 Flamegraph
4. 区分 On-CPU 和 Off-CPU Flamegraph
5. 使用差分 Flamegraph 对比优化前后
6. 了解现代持续分析工具（Pyroscope, Parca）

---

## 先跑起来！（10 分钟）

> 在学习 Flamegraph 理论之前，先看一个真实的火焰图。  
> **味道先行**：先体验，再理解。  

### 快速生成你的第一个 Flamegraph

```bash
# 1. 下载 FlameGraph 工具集
git clone https://github.com/brendangregg/FlameGraph ~/FlameGraph

# 2. 录制系统活动（需要 root 权限）
sudo perf record -F 99 -a -g -- sleep 10

# 3. 生成 Flamegraph
sudo perf script | ~/FlameGraph/stackcollapse-perf.pl | ~/FlameGraph/flamegraph.pl > ~/flamegraph.svg

# 4. 查看结果
echo "Flamegraph 已生成: ~/flamegraph.svg"
echo "用浏览器打开查看（可点击交互！）"

# 如果在 EC2/远程服务器，可以下载到本地查看
# scp user@server:~/flamegraph.svg .
```

**打开 SVG 文件后你会看到**：

<!-- DIAGRAM: flamegraph-anatomy -->
```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        Flamegraph 解剖图                                     │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│   ← 宽度 = 时间占比（不是调用次数！） →                                      │
│                                                                             │
│   ┌─────┐ ┌───────────────────────┐ ┌─────────┐ ┌───┐                      │
│   │func │ │      hot_func()       │ │  func_b │ │ c │   ← 顶部 = 叶子函数    │
│   │_a   │ │   (这是"热点"!)       │ │         │ │   │     时间花在这里       │
│   └─────┘ └───────────────────────┘ └─────────┘ └───┘                      │
│   ┌───────────────────────────────────────────────────────┐                │
│   │                    caller_func()                      │                │
│   │                   (调用了上面的函数)                   │                │
│   └───────────────────────────────────────────────────────┘                │
│   ┌─────────────────────────────────────────────────────────────────────┐  │
│   │                              main()                                 │  │
│   │                           (根函数)                                  │  │
│   └─────────────────────────────────────────────────────────────────────┘  │
│                                                                             │
│   ↑ 底部 = 根函数（调用链起点）                                             │
│                                                                             │
│   注意：                                                                    │
│   • 宽的帧 = 时间占比大                                                     │
│   • 顶部宽帧 = CPU 热点（需要优化）                                         │
│   • 左右顺序无意义（按字母排序，不是时间顺序）                              │
│   • 颜色通常随机（用于区分，无特殊含义）                                    │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```
<!-- /DIAGRAM -->

**交互操作**：

- **点击帧**：放大该调用子树
- **搜索**：按 Ctrl+F 搜索函数名
- **重置**：点击最底部的 "all" 或 "Reset Zoom"

**你刚刚生成了系统的 CPU 画像！**

现在让我们理解这张图的含义。

---

## Step 1 - Flamegraph 解读（15 分钟）

### 1.1 宽度的含义（最重要！）

**宽度 = 时间占比**（采样比例），**不是调用次数**。

这是最常见的误解，必须理解清楚：

| 常见误解 | 正确理解 |
|----------|----------|
| 宽 = 调用次数多 | 宽 = 时间占比大（采样中出现频率高）|
| 窄 = 调用次数少 | 窄 = 时间占比小 |
| 颜色有特殊含义 | 颜色通常随机（便于区分，无语义）|

**举例**：

```
如果函数 A 被调用 1000 次，每次 1ms，总共 1 秒
如果函数 B 被调用 10 次，每次 100ms，总共 1 秒

在 Flamegraph 中，A 和 B 的宽度相同！
因为它们占用的 CPU 时间相同。
```

### 1.2 纵向阅读：调用栈

<!-- DIAGRAM: flamegraph-stack-direction -->
```
┌─────────────────────────────────────────────────────────────────────────────┐
│                       Flamegraph 调用栈方向                                  │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│                         ┌────────────────┐                                  │
│   顶部 (Top)    ────►   │  leaf_func()   │   ← 叶子函数                     │
│   "热点在这里"          │ (实际执行代码) │     CPU 真正花时间的地方         │
│                         └────────────────┘                                  │
│                                 ↑                                           │
│                                 │ 调用                                       │
│                         ┌────────────────┐                                  │
│                         │ middle_func()  │   ← 中间函数                     │
│                         │                │                                  │
│                         └────────────────┘                                  │
│                                 ↑                                           │
│                                 │ 调用                                       │
│                         ┌────────────────┐                                  │
│   底部 (Bottom) ────►   │     main()     │   ← 根函数                       │
│   "调用链起点"          │   (入口点)     │     所有调用从这里开始           │
│                         └────────────────┘                                  │
│                                                                             │
│   阅读方向：                                                                │
│   • 从下到上：调用顺序（谁调用了谁）                                        │
│   • 从上到下：追溯路径（热点是怎么被调用的）                                │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```
<!-- /DIAGRAM -->

**关键理解**：

- **底部**：程序入口（main、start_thread 等）
- **顶部**：实际执行的代码（CPU 时间真正花在这里）
- **找热点**：看顶部有哪些宽帧

### 1.3 横向阅读：并列而非时序

**横向排列是按字母排序，不是执行时间顺序！**

```
错误理解：A B C 表示先执行 A，再执行 B，再执行 C
正确理解：A B C 只是三个并列的调用，按名称排序显示
```

这意味着：

- 不能从左右位置判断执行先后
- 只能从宽度判断时间占比
- 横向是为了节省垂直空间，让图更紧凑

### 1.4 识别热点函数

**热点函数**：顶部的宽帧。

<!-- DIAGRAM: finding-hotspots -->
```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         识别热点函数                                         │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│   场景 1：明显的单一热点                                                     │
│   ┌──┐ ┌─────────────────────────────────┐ ┌──┐                            │
│   │a │ │         regex_match()           │ │c │  ← 这就是热点！             │
│   └──┘ │       占用 60% CPU 时间         │ └──┘    优化这里效果最大         │
│   ┌────────────────────────────────────────────┐                           │
│   │             process_request()              │                           │
│   └────────────────────────────────────────────┘                           │
│                                                                             │
│   场景 2：平均分散（无明显热点）                                             │
│   ┌────────┐ ┌────────┐ ┌────────┐ ┌────────┐                              │
│   │ func_a │ │ func_b │ │ func_c │ │ func_d │  ← 没有明显热点               │
│   │  25%   │ │  25%   │ │  25%   │ │  25%   │    需要整体优化或架构调整     │
│   └────────┘ └────────┘ └────────┘ └────────┘                              │
│                                                                             │
│   场景 3：深度调用栈                                                         │
│   ┌───────────────────────────────────────────────────────┐                │
│   │                     hot_leaf()                        │  ← 顶部宽帧     │
│   └───────────────────────────────────────────────────────┘                │
│   ┌───────────────────────────────────────────────────────┐                │
│   │                    layer_4()                          │    但实际上     │
│   └───────────────────────────────────────────────────────┘    是整个调用   │
│   ┌───────────────────────────────────────────────────────┐    链都有问题   │
│   │                    layer_3()                          │                │
│   └───────────────────────────────────────────────────────┘                │
│   (深度塔状结构通常表示同一调用路径)                                         │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```
<!-- /DIAGRAM -->

**热点识别步骤**：

1. 找顶部最宽的帧
2. 确认它是业务代码还是系统/库代码
3. 如果是库代码，看是谁调用的（向下追溯）
4. 如果是业务代码，分析是否可以优化

### 1.5 颜色的含义

大多数 Flamegraph 工具的颜色是**随机**或**按类别**：

| 颜色方案 | 含义 |
|----------|------|
| **随机色** | 默认，便于视觉区分，无语义 |
| **红/橙暖色** | 有些工具用暖色表示"热"（但不绝对）|
| **蓝色** | 有些工具表示内核态函数 |
| **绿色** | 有些工具表示用户态函数 |

**不要过度解读颜色**，关注宽度才是关键。

---

## Step 2 - Flamegraph 生成流程（15 分钟）

### 2.1 完整生成流程

<!-- DIAGRAM: flamegraph-workflow -->
```
┌─────────────────────────────────────────────────────────────────────────────┐
│                      Flamegraph 生成流程                                     │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│   Step 1: 录制                                                              │
│   ┌─────────────────────────────────────────────────────────────────────┐  │
│   │  perf record -F 99 -a -g -- sleep 30                                │  │
│   │                                                                     │  │
│   │  -F 99   : 采样频率 99Hz (避免 aliasing)                            │  │
│   │  -a      : 系统范围 (所有 CPU)                                      │  │
│   │  -g      : 记录调用栈 (关键!)                                       │  │
│   │  sleep 30: 采样 30 秒                                               │  │
│   │                                                                     │  │
│   │  输出: perf.data (二进制文件)                                       │  │
│   └─────────────────────────────────────────────────────────────────────┘  │
│                              │                                              │
│                              ▼                                              │
│   Step 2: 导出文本                                                          │
│   ┌─────────────────────────────────────────────────────────────────────┐  │
│   │  perf script > out.perf                                             │  │
│   │                                                                     │  │
│   │  将二进制 perf.data 转为可读的文本格式                              │  │
│   │  包含时间戳、进程名、调用栈等信息                                   │  │
│   └─────────────────────────────────────────────────────────────────────┘  │
│                              │                                              │
│                              ▼                                              │
│   Step 3: 折叠调用栈                                                        │
│   ┌─────────────────────────────────────────────────────────────────────┐  │
│   │  stackcollapse-perf.pl out.perf > out.folded                        │  │
│   │                                                                     │  │
│   │  将多行调用栈压缩为单行格式：                                       │  │
│   │  main;caller;func 123  (调用路径 + 采样计数)                        │  │
│   └─────────────────────────────────────────────────────────────────────┘  │
│                              │                                              │
│                              ▼                                              │
│   Step 4: 生成 SVG                                                          │
│   ┌─────────────────────────────────────────────────────────────────────┐  │
│   │  flamegraph.pl out.folded > cpu.svg                                 │  │
│   │                                                                     │  │
│   │  生成交互式 SVG 文件                                                │  │
│   │  可以在浏览器中点击、搜索、放大                                     │  │
│   └─────────────────────────────────────────────────────────────────────┘  │
│                                                                             │
│   简化命令（管道一步完成）：                                                 │
│   perf script | stackcollapse-perf.pl | flamegraph.pl > cpu.svg            │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```
<!-- /DIAGRAM -->

### 2.2 采样参数选择

**采样频率 -F**：

```bash
# 推荐：99 Hz
perf record -F 99 -a -g -- sleep 30

# 为什么是 99 而不是 100？
# 避免与系统 timer (通常 100Hz) 产生 aliasing（采样偏差）
# 99 是素数，减少周期性干扰
```

**采样时长**：

| 场景 | 推荐时长 | 说明 |
|------|----------|------|
| 快速诊断 | 10-30 秒 | 捕获典型负载 |
| 详细分析 | 60 秒 | 更准确的统计 |
| 特定问题复现 | 与问题持续时间对齐 | 例如等 5 分钟后的批处理 |

**采样范围**：

```bash
# 系统范围（推荐用于服务器分析）
perf record -F 99 -a -g -- sleep 30

# 特定进程（减少噪音）
perf record -F 99 -p $(pgrep myapp) -g -- sleep 30

# 特定命令
perf record -F 99 -g -- ./my_program
```

### 2.3 一键生成脚本

```bash
#!/bin/bash
# flamegraph.sh - 一键生成 Flamegraph
# 用法: ./flamegraph.sh [采样秒数] [输出文件名]

DURATION=${1:-30}
OUTPUT=${2:-"flamegraph_$(date +%Y%m%d_%H%M%S)"}
FLAMEGRAPH_DIR="${FLAMEGRAPH_DIR:-$HOME/FlameGraph}"

# 检查 FlameGraph 工具
if [ ! -d "$FLAMEGRAPH_DIR" ]; then
    echo "正在下载 FlameGraph 工具..."
    git clone https://github.com/brendangregg/FlameGraph "$FLAMEGRAPH_DIR"
fi

echo "开始采样 ($DURATION 秒)..."
sudo perf record -F 99 -a -g -- sleep $DURATION

echo "生成 Flamegraph..."
sudo perf script | \
    "$FLAMEGRAPH_DIR/stackcollapse-perf.pl" | \
    "$FLAMEGRAPH_DIR/flamegraph.pl" > "${OUTPUT}.svg"

echo ""
echo "=========================================="
echo "  Flamegraph 生成完成！"
echo "  文件: ${OUTPUT}.svg"
echo "=========================================="
echo ""
echo "用浏览器打开 SVG 文件查看（支持点击交互）"

# 清理 perf.data
rm -f perf.data
```

### 2.4 常见问题排查

**问题 1：符号缺失（地址而非函数名）**

```bash
# 症状：Flamegraph 显示 [unknown] 或十六进制地址
# 原因：缺少调试符号

# 解决方案 1：安装 debuginfo 包
sudo apt install linux-tools-$(uname -r)  # Ubuntu
sudo yum install kernel-debuginfo         # RHEL/CentOS

# 解决方案 2：对于应用程序
# 编译时保留调试符号 (-g)
# 或安装 *-dbg / *-debuginfo 包
```

**问题 2：调用栈不完整**

```bash
# 症状：调用栈只有几层
# 原因：编译器优化去除了帧指针

# 解决方案：使用 DWARF 展开
perf record -F 99 -a -g --call-graph dwarf -- sleep 30

# 或者重新编译应用
# gcc -fno-omit-frame-pointer -g ...
```

**问题 3：权限不足**

```bash
# 症状：perf record 失败
# 解决方案：用 root 或设置权限

# 临时允许
echo 0 | sudo tee /proc/sys/kernel/perf_event_paranoid

# 或以 root 运行
sudo perf record ...
```

---

## Step 3 - On-CPU vs Off-CPU（10 分钟）

### 3.1 两种 Flamegraph 的区别

<!-- DIAGRAM: oncpu-vs-offcpu -->
```
┌─────────────────────────────────────────────────────────────────────────────┐
│                      On-CPU vs Off-CPU Flamegraph                            │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│   On-CPU Flamegraph                    Off-CPU Flamegraph                   │
│   ┌────────────────────────┐          ┌────────────────────────┐           │
│   │  代码在 CPU 上运行时    │          │  代码在等待时          │           │
│   │                        │          │  (不占用 CPU)           │           │
│   │  回答：                │          │  回答：                │           │
│   │  "CPU 忙在做什么？"    │          │  "代码在等什么？"      │           │
│   │                        │          │                        │           │
│   │  典型场景：            │          │  典型场景：            │           │
│   │  • 计算密集型代码      │          │  • I/O 等待            │           │
│   │  • CPU 热点函数        │          │  • 锁等待              │           │
│   │  • 算法效率问题        │          │  • 网络等待            │           │
│   │                        │          │  • sleep/条件变量等待  │           │
│   │  生成方式：            │          │  生成方式：            │           │
│   │  perf record -g        │          │  需要 eBPF 工具        │           │
│   │  (标准 perf 采样)      │          │  (offcputime-bpfcc)    │           │
│   └────────────────────────┘          └────────────────────────┘           │
│                                                                             │
│   选择指南：                                                                │
│   ┌─────────────────────────────────────────────────────────────────────┐  │
│   │  症状                        │ 应该用            │                  │  │
│   │  ─────────────────────────────────────────────────                  │  │
│   │  CPU 使用率高                │ On-CPU           │                  │  │
│   │  CPU 使用率低但延迟高        │ Off-CPU          │                  │  │
│   │  两者都有问题               │ 两个都做         │                  │  │
│   └─────────────────────────────────────────────────────────────────────┘  │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```
<!-- /DIAGRAM -->

### 3.2 何时使用哪种？

**使用 On-CPU Flamegraph**：

```bash
# 场景：CPU 使用率高（如 90%），想知道 CPU 在忙什么
# 工具：标准 perf

perf record -F 99 -a -g -- sleep 30
perf script | stackcollapse-perf.pl | flamegraph.pl > cpu.svg
```

**使用 Off-CPU Flamegraph**：

```bash
# 场景：CPU 使用率低（如 20%），但延迟高、响应慢
# 原因：代码大部分时间在等待（I/O、锁、网络）
# 工具：需要 eBPF (BCC offcputime)

# 安装 BCC 工具
sudo apt install bpfcc-tools  # Ubuntu
sudo yum install bcc-tools    # RHEL/CentOS

# 生成 Off-CPU Flamegraph
sudo offcputime-bpfcc -f 30 | \
    ~/FlameGraph/flamegraph.pl --color=io --title="Off-CPU Flamegraph" > offcpu.svg
```

### 3.3 典型案例对比

**案例 1：CPU 密集型问题**

```
症状：CPU 95%，服务慢
On-CPU Flamegraph 显示：
  regex_compile() 占 60%
  → 问题：每次请求都重新编译正则表达式
  → 解决：预编译正则表达式
```

**案例 2：I/O 等待问题**

```
症状：CPU 10%，服务慢
On-CPU Flamegraph 显示：正常，没有热点
Off-CPU Flamegraph 显示：
  pread64() 占 70%
  → 问题：大量同步磁盘读取
  → 解决：使用缓存或异步 I/O
```

**案例 3：锁竞争问题**

```
症状：CPU 50%，但多核服务器性能不增
Off-CPU Flamegraph 显示：
  futex_wait() 占 40%
  → 问题：锁竞争严重
  → 解决：减小锁粒度或使用无锁数据结构
```

---

## Step 4 - 差分 Flamegraph（10 分钟）

### 4.1 什么是差分 Flamegraph？

差分 Flamegraph（Differential Flamegraph）用于**对比两次采样**的差异。

典型场景：

- 优化前后对比
- 版本升级前后对比
- 负载变化前后对比

### 4.2 生成差分 Flamegraph

```bash
# Step 1: 采集基线（优化前/旧版本）
perf record -F 99 -a -g -o perf_before.data -- sleep 30
perf script -i perf_before.data | stackcollapse-perf.pl > before.folded

# Step 2: 采集对比（优化后/新版本）
# ... 部署新版本或应用优化 ...
perf record -F 99 -a -g -o perf_after.data -- sleep 30
perf script -i perf_after.data | stackcollapse-perf.pl > after.folded

# Step 3: 生成差分 Flamegraph
~/FlameGraph/difffolded.pl before.folded after.folded | \
    ~/FlameGraph/flamegraph.pl > diff.svg
```

### 4.3 解读差分 Flamegraph

<!-- DIAGRAM: differential-flamegraph -->
```
┌─────────────────────────────────────────────────────────────────────────────┐
│                       差分 Flamegraph 解读                                   │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│   颜色含义：                                                                │
│   ┌─────────────────────────────────────────────────────────────────────┐  │
│   │  红色/橙色 (Warm)                                                   │  │
│   │  • 时间占比 增加                                                    │  │
│   │  • "变慢了"                                                         │  │
│   │  • 需要关注                                                         │  │
│   └─────────────────────────────────────────────────────────────────────┘  │
│                                                                             │
│   ┌─────────────────────────────────────────────────────────────────────┐  │
│   │  蓝色 (Cool)                                                        │  │
│   │  • 时间占比 减少                                                    │  │
│   │  • "变快了"                                                         │  │
│   │  • 优化成功的信号                                                   │  │
│   └─────────────────────────────────────────────────────────────────────┘  │
│                                                                             │
│   ┌─────────────────────────────────────────────────────────────────────┐  │
│   │  白色/浅色                                                          │  │
│   │  • 基本没变化                                                       │  │
│   │  • 无需关注                                                         │  │
│   └─────────────────────────────────────────────────────────────────────┘  │
│                                                                             │
│   示例：                                                                    │
│   ┌──────────────────────────────────────────────────────────┐            │
│   │ ████████ regex_match() ████████  (蓝色 - 时间减少!)      │            │
│   │ ████████████████████ (原来占 40%)                        │            │
│   │ ████████ (现在占 15%)                                    │            │
│   │                                                          │            │
│   │ ██████ new_cache_lookup() ██████  (红色 - 新增函数)     │            │
│   │                                                          │            │
│   └──────────────────────────────────────────────────────────┘            │
│   解读：regex_match 优化成功（蓝色），但引入了 cache 开销（红色）         │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```
<!-- /DIAGRAM -->

### 4.4 差分 Flamegraph 实战

```bash
#!/bin/bash
# diff-flamegraph.sh - 生成差分 Flamegraph
# 用法: ./diff-flamegraph.sh <before.data> <after.data> [output.svg]

BEFORE=$1
AFTER=$2
OUTPUT=${3:-"diff_$(date +%Y%m%d_%H%M%S).svg"}
FLAMEGRAPH_DIR="${FLAMEGRAPH_DIR:-$HOME/FlameGraph}"

if [ -z "$BEFORE" ] || [ -z "$AFTER" ]; then
    echo "用法: $0 <before.data> <after.data> [output.svg]"
    exit 1
fi

# 折叠调用栈
perf script -i "$BEFORE" | "$FLAMEGRAPH_DIR/stackcollapse-perf.pl" > /tmp/before.folded
perf script -i "$AFTER" | "$FLAMEGRAPH_DIR/stackcollapse-perf.pl" > /tmp/after.folded

# 生成差分图
"$FLAMEGRAPH_DIR/difffolded.pl" /tmp/before.folded /tmp/after.folded | \
    "$FLAMEGRAPH_DIR/flamegraph.pl" \
    --title="Differential Flamegraph (Red=增加, Blue=减少)" > "$OUTPUT"

echo "差分 Flamegraph 已生成: $OUTPUT"
echo "红色 = 时间占比增加（变慢）"
echo "蓝色 = 时间占比减少（变快）"
```

---

## Step 5 - 现代持续分析工具（5 分钟）

### 5.1 传统 vs 持续分析

| 传统 Flamegraph | 持续分析（Continuous Profiling）|
|-----------------|--------------------------------|
| 手动采样（ad-hoc）| 7x24 自动采样 |
| 事后分析 | 实时监控 |
| 本地文件 | 集中存储 + Web UI |
| 单时间点快照 | 历史对比、趋势分析 |

### 5.2 现代工具介绍

**Pyroscope**（开源，自托管或 SaaS）：

```bash
# 安装 Agent
curl -fsSL https://pyroscope.io/install.sh | sudo sh

# 启动 Agent + 应用
pyroscope exec -- ./my_application

# 访问 Web UI
# http://localhost:4040
```

**Parca**（开源，云原生）：

```bash
# Kubernetes 部署
kubectl apply -f https://parca.dev/parca-server.yaml

# 自动发现 Pod 并采集
# 支持 eBPF，零代码侵入
```

**商业方案**：

- **Datadog Continuous Profiler**
- **AWS CodeGuru Profiler**
- **Google Cloud Profiler**

### 5.3 何时考虑持续分析？

| 场景 | 推荐方案 |
|------|----------|
| 临时排查问题 | 手动 perf + FlameGraph |
| 定期性能审计 | 手动 + 脚本自动化 |
| 生产环境持续监控 | Pyroscope/Parca |
| 已有监控体系 | Datadog/Grafana 集成方案 |

---

## Cloud Lab 警告

### AWS t2/t3 Steal Time 问题

> 在 AWS t2/t3 实例上进行性能采样时，可能会遇到 **steal time** 干扰。  

**什么是 Steal Time？**

```bash
# 查看 steal time
mpstat -P ALL 1 | grep -E "CPU|all"

# 输出中的 %st 列就是 steal time
```

**问题现象**：

- Flamegraph 显示大量时间花在等待
- 实际是 hypervisor 限流（CPU credit 耗尽）
- 不是你的应用问题！

**识别方法**：

```bash
# 检查 steal time
vmstat 1 5
# 如果 st 列 > 5%，你的采样数据可能不准确

# 检查 CPU Credit（需要 AWS CLI）
aws cloudwatch get-metric-statistics \
    --namespace AWS/EC2 \
    --metric-name CPUCreditBalance \
    --dimensions Name=InstanceId,Value=i-xxxxx \
    --period 300 --statistics Average \
    --start-time $(date -d '1 hour ago' --utc +%Y-%m-%dT%H:%M:%SZ) \
    --end-time $(date --utc +%Y-%m-%dT%H:%M:%SZ)
```

**解决方案**：

```bash
# 方案 1：使用非突发实例（m5/c5 系列）
# 无 CPU credit 限制，性能稳定

# 方案 2：短时间采样，避免触发限流
perf record -F 99 -a -g -- sleep 10  # 10 秒而非 60 秒

# 方案 3：使用 cgroup 模拟 CPU 限制（更可控）
systemctl set-property --runtime myapp.service CPUQuota=50%
```

---

## Flamegraph Cheatsheet

```bash
# ============================================================
# Flamegraph Cheatsheet
# ============================================================

# === 快速生成 ===
# 下载工具（只需一次）
git clone https://github.com/brendangregg/FlameGraph ~/FlameGraph

# 一行生成 Flamegraph
sudo perf record -F 99 -a -g -- sleep 30 && \
    sudo perf script | ~/FlameGraph/stackcollapse-perf.pl | \
    ~/FlameGraph/flamegraph.pl > cpu.svg

# === 采样参数 ===
# 系统范围
perf record -F 99 -a -g -- sleep 30

# 特定进程
perf record -F 99 -p PID -g -- sleep 30

# 特定命令
perf record -F 99 -g -- ./my_program

# 更完整的调用栈（DWARF 展开）
perf record -F 99 -a -g --call-graph dwarf -- sleep 30

# === 分步生成 ===
# Step 1: 录制
sudo perf record -F 99 -a -g -- sleep 30

# Step 2: 导出
sudo perf script > out.perf

# Step 3: 折叠
~/FlameGraph/stackcollapse-perf.pl out.perf > out.folded

# Step 4: 生成 SVG
~/FlameGraph/flamegraph.pl out.folded > cpu.svg

# === 差分 Flamegraph ===
# 生成两份数据
perf record -o before.data -F 99 -a -g -- sleep 30
# ... 优化/升级 ...
perf record -o after.data -F 99 -a -g -- sleep 30

# 生成差分
perf script -i before.data | stackcollapse-perf.pl > before.folded
perf script -i after.data | stackcollapse-perf.pl > after.folded
~/FlameGraph/difffolded.pl before.folded after.folded | \
    ~/FlameGraph/flamegraph.pl > diff.svg

# === Off-CPU Flamegraph (需要 eBPF) ===
# 安装 BCC 工具
sudo apt install bpfcc-tools  # Ubuntu

# 生成 Off-CPU Flamegraph
sudo offcputime-bpfcc -f 30 | \
    ~/FlameGraph/flamegraph.pl --color=io --title="Off-CPU" > offcpu.svg

# === 定制选项 ===
# 添加标题
flamegraph.pl --title="My Application CPU Profile" input.folded > output.svg

# 颜色方案
flamegraph.pl --color=java input.folded > output.svg    # Java 友好配色
flamegraph.pl --color=io input.folded > output.svg      # I/O 配色

# 反转顺序（icicle graph）
flamegraph.pl --inverted input.folded > output.svg

# === 解读要点 ===
# 宽度 = 时间占比（不是调用次数！）
# 顶部宽帧 = 热点函数（优先优化）
# 左右顺序 = 无意义（按字母排序）
# 颜色 = 通常随机（便于区分）

# === 交互操作 ===
# 点击帧 = 放大子树
# Ctrl+F = 搜索函数
# 点击底部 = 重置视图
```

---

## 实战场景：CPU 热点定位（Lab）

### 场景背景

```
症状：Web 服务 CPU 使用率 90%，响应变慢
需求：使用 Flamegraph 定位热点函数

日本语境：性能レポート作成 - エビデンスとしてのフレームグラフ
```

### 模拟问题程序

```bash
# 创建实验目录
mkdir -p ~/flamegraph-lab
cd ~/flamegraph-lab

# 创建模拟程序（CPU 密集型）
cat > cpu_hog.py << 'EOF'
#!/usr/bin/env python3
"""
模拟 CPU 密集型问题
- inefficient_sort() 是热点函数
- 每次请求都重新排序大数组
"""
import random
import time

def inefficient_sort(data):
    """故意低效的排序（冒泡排序）"""
    arr = list(data)
    n = len(arr)
    for i in range(n):
        for j in range(0, n-i-1):
            if arr[j] > arr[j+1]:
                arr[j], arr[j+1] = arr[j+1], arr[j]
    return arr

def process_request(request_id):
    """模拟请求处理"""
    # 每次请求都创建新数组并排序（低效！）
    data = [random.randint(1, 10000) for _ in range(1000)]
    sorted_data = inefficient_sort(data)  # 热点函数
    return sorted_data[:10]

def main():
    print("Starting server simulation...")
    print("Press Ctrl+C to stop")

    request_count = 0
    start_time = time.time()

    try:
        while True:
            result = process_request(request_count)
            request_count += 1

            if request_count % 100 == 0:
                elapsed = time.time() - start_time
                rps = request_count / elapsed
                print(f"Processed {request_count} requests ({rps:.1f} req/s)")
    except KeyboardInterrupt:
        print(f"\nTotal: {request_count} requests")

if __name__ == "__main__":
    main()
EOF

chmod +x cpu_hog.py
```

### 诊断步骤

```bash
# 确保有 FlameGraph 工具
if [ ! -d ~/FlameGraph ]; then
    git clone https://github.com/brendangregg/FlameGraph ~/FlameGraph
fi

# Step 1: 启动问题程序（后台运行）
python3 ~/flamegraph-lab/cpu_hog.py &
PID=$!
echo "程序 PID: $PID"

# 等待程序启动
sleep 2

# Step 2: 录制 CPU 使用（30 秒）
echo "开始录制 CPU 使用..."
sudo perf record -F 99 -p $PID -g -- sleep 30

# Step 3: 生成 Flamegraph
echo "生成 Flamegraph..."
sudo perf script | ~/FlameGraph/stackcollapse-perf.pl | \
    ~/FlameGraph/flamegraph.pl --title="CPU Hog Analysis" > ~/flamegraph-lab/result.svg

# Step 4: 停止程序
kill $PID 2>/dev/null

echo ""
echo "=========================================="
echo "  分析完成！"
echo "  Flamegraph: ~/flamegraph-lab/result.svg"
echo "=========================================="
```

### 预期结果分析

打开 `result.svg`，你应该看到：

```
预期 Flamegraph 结构：

┌───────────────────────────────────────────────────────────────┐
│                  inefficient_sort (热点!)                     │  ← 顶部最宽
│                   占用 70-80% CPU 时间                        │
└───────────────────────────────────────────────────────────────┘
┌───────────────────────────────────────────────────────────────┐
│                     process_request                           │
└───────────────────────────────────────────────────────────────┘
┌───────────────────────────────────────────────────────────────┐
│                          main                                 │
└───────────────────────────────────────────────────────────────┘

分析结论：
- inefficient_sort() 是明显的热点函数
- 冒泡排序 O(n^2) 复杂度导致 CPU 浪费
- 优化方案：使用 Python 内置 sorted() (Timsort, O(n log n))
```

### 优化验证

```bash
# 创建优化版本
cat > cpu_hog_fixed.py << 'EOF'
#!/usr/bin/env python3
"""
优化版：使用内置排序
"""
import random
import time

def efficient_sort(data):
    """使用 Python 内置排序（Timsort）"""
    return sorted(data)

def process_request(request_id):
    data = [random.randint(1, 10000) for _ in range(1000)]
    sorted_data = efficient_sort(data)  # 优化后
    return sorted_data[:10]

def main():
    print("Starting optimized server...")
    request_count = 0
    start_time = time.time()

    try:
        while True:
            result = process_request(request_count)
            request_count += 1

            if request_count % 1000 == 0:  # 更高频率输出
                elapsed = time.time() - start_time
                rps = request_count / elapsed
                print(f"Processed {request_count} requests ({rps:.1f} req/s)")
    except KeyboardInterrupt:
        print(f"\nTotal: {request_count} requests")

if __name__ == "__main__":
    main()
EOF

# 对比优化前后的请求处理速度
echo "=== 优化前 ==="
timeout 10 python3 ~/flamegraph-lab/cpu_hog.py 2>/dev/null || true

echo ""
echo "=== 优化后 ==="
timeout 10 python3 ~/flamegraph-lab/cpu_hog_fixed.py 2>/dev/null || true
```

### 清理

```bash
rm -rf ~/flamegraph-lab
```

---

## 反模式：常见错误

### 错误 1：误解宽度含义

```bash
# 错误理解
"这个函数很宽，说明它被调用很多次"

# 正确理解
"这个函数很宽，说明它占用了大量 CPU 时间"
"可能是调用次数多，也可能是每次调用很慢"

# 验证方法：结合 perf stat 看调用次数
perf stat -e cycles,instructions -- ./my_program
```

### 错误 2：忽略 Off-CPU 分析

```bash
# 错误：CPU 使用率低，但只看 On-CPU Flamegraph
"On-CPU Flamegraph 看起来正常，问题在哪？"

# 正确：CPU 低但延迟高时，应该看 Off-CPU
# 代码可能大部分时间在等待（I/O、锁、网络）
sudo offcputime-bpfcc -f 30 | flamegraph.pl > offcpu.svg
```

### 错误 3：采样时间不当

```bash
# 错误：采样时间太短，数据不稳定
perf record -F 99 -a -g -- sleep 5  # 只有 5 秒

# 错误：采样时间太长，在 t2/t3 上触发限流
perf record -F 99 -a -g -- sleep 600  # 10 分钟

# 正确：根据场景选择合适时长
# 快速诊断：10-30 秒
# 详细分析：60 秒
# 特定问题：与问题持续时间对齐
```

### 错误 4：忘记检查符号

```bash
# 错误：看到一堆 [unknown] 就放弃
"Flamegraph 都是 [unknown]，没法分析"

# 正确：安装调试符号
sudo apt install linux-tools-$(uname -r)
sudo apt install python3-dbg  # Python
sudo yum install kernel-debuginfo  # RHEL

# 或使用 DWARF 展开
perf record -F 99 -a -g --call-graph dwarf -- sleep 30
```

---

## 职场小贴士（Japan IT Context）

### 性能レポートへの可視化

在日本 IT 企业，性能报告需要**可视化证据**（エビデンス）。Flamegraph 是完美的性能分析可视化工具。

| 日语术语 | 读音 | 含义 | Flamegraph 相关 |
|----------|------|------|-----------------|
| フレームグラフ | フレームグラフ | Flamegraph | 性能可视化工具 |
| ホットスポット | ホットスポット | Hot spot | 热点函数 |
| プロファイリング | プロファイリング | Profiling | 性能分析 |
| 可視化 | かしか | Visualization | 报告必备 |
| エビデンス | エビデンス | Evidence | 数据证据 |
| チューニング | チューニング | Tuning | 性能调优 |

### 性能报告模板（Flamegraph 部分）

```markdown
## 性能分析報告 - フレームグラフ分析

### 分析環境
- サーバ: web-server-01 (m5.large)
- 分析日時: 2026-01-10 14:30 JST
- サンプリング: 99Hz, 30秒間

### On-CPU フレームグラフ

![On-CPU Flamegraph](./oncpu.svg)

#### 主要な発見

| ホットスポット | 時間占有率 | 問題点 | 対策 |
|--------------|----------|-------|------|
| regex_match() | 45% | 毎リクエストで正規表現コンパイル | プリコンパイル化 |
| json_parse() | 25% | 大きなJSON解析 | ストリーミング解析 |

### 結論
- regex_match() が最大のボトルネック
- 正規表現のプリコンパイルで 40% 以上の改善見込み

### 対策実施後の差分フレームグラフ

![Differential Flamegraph](./diff.svg)

- 青色 = 改善（時間減少）
- 赤色 = 悪化（時間増加）

regex_match() が大幅に改善（青色）を確認。
```

---

## 面试准备（Interview Prep）

### Q1: フレームグラフの幅は何を表しますか？

**回答要点**：

```
幅はサンプル数に対する時間の割合を表します。

重要なポイント：
- 幅が広い = その関数に時間がかかっている
- 呼び出し回数ではない！
- 1回だけ呼ばれても時間がかかれば幅が広い
- 1万回呼ばれても各呼び出しが短ければ幅は狭い

例：
- 関数 A: 1000 回呼び出し × 1ms = 1秒
- 関数 B: 10 回呼び出し × 100ms = 1秒
→ フレームグラフでは同じ幅になる
```

### Q2: On-CPU と Off-CPU フレームグラフの違いは？

**回答要点**：

```
On-CPU フレームグラフ:
- CPU を使用中の時間を可視化
- "CPU は何に忙しいか？" に答える
- CPU 使用率が高い時に有効
- 標準の perf で生成可能

Off-CPU フレームグラフ:
- 待機時間（I/O、ロック、sleep）を可視化
- "コードは何を待っているか？" に答える
- CPU 使用率が低いのに遅い時に有効
- eBPF (BCC offcputime) が必要

使い分け:
- CPU 高い → On-CPU を先に
- CPU 低いが遅い → Off-CPU を先に
- 両方問題ありそう → 両方取得
```

### Q3: フレームグラフでホットスポットを見つける方法は？

**回答要点**：

```
ホットスポットの見つけ方：

1. 頂部（Top）を見る
   - 頂部は実際にコードが実行されている場所
   - ここに時間がかかっている

2. 幅の広いフレームを探す
   - 幅が広い = 時間占有率が高い
   - 特に頂部で幅が広いものがホットスポット

3. 「台地」（plateau）を探す
   - 頂部が平らに広がっている部分
   - その関数自体に時間がかかっている

4. 深い塔は要注意
   - 同じ幅で深く続く場合
   - 一つの呼び出しパスが支配的

見つけた後の対応：
- 自分のコードなら → 最適化を検討
- ライブラリなら → 使い方を見直す、代替を検討
- システムコールなら → I/O パターンを見直す
```

---

## 检查清单

完成本课后，你应该能够：

- [ ] 解释 Flamegraph 的宽度含义（时间占比，非调用次数）
- [ ] 理解纵向阅读方向（底部 = 根，顶部 = 叶子/热点）
- [ ] 识别热点函数（顶部的宽帧）
- [ ] 使用 perf record + FlameGraph 脚本生成 Flamegraph
- [ ] 选择合适的采样参数（-F 99, -g, 时长）
- [ ] 区分 On-CPU 和 Off-CPU Flamegraph 的适用场景
- [ ] 生成差分 Flamegraph 对比优化前后
- [ ] 解读差分 Flamegraph 的颜色含义（红 = 增加，蓝 = 减少）
- [ ] 排查常见问题（符号缺失、调用栈不完整）
- [ ] 了解 AWS t2/t3 steal time 对采样的影响
- [ ] 了解现代持续分析工具（Pyroscope, Parca）

---

## 本课小结

| 概念 | 要点 |
|------|------|
| Flamegraph | CPU 时间的可视化堆栈图 |
| 宽度 | 时间占比（**不是**调用次数！）|
| 纵向 | 底部 = 根函数，顶部 = 叶子函数（热点）|
| 横向 | 按字母排序，无时间意义 |
| 热点 | 顶部的宽帧，优先优化目标 |
| On-CPU | CPU 忙碌时的分析，标准 perf |
| Off-CPU | CPU 等待时的分析，需要 eBPF |
| 差分图 | 红 = 变慢，蓝 = 变快 |
| 持续分析 | Pyroscope/Parca 用于生产监控 |

---

## 延伸阅读

- [Brendan Gregg: Flame Graphs](https://www.brendangregg.com/flamegraphs.html) - 作者原文
- [FlameGraph GitHub](https://github.com/brendangregg/FlameGraph) - 工具仓库
- [Pyroscope 文档](https://pyroscope.io/docs/) - 持续分析工具
- [Parca 文档](https://www.parca.dev/docs/) - 云原生持续分析
- 上一课：[07 - perf 性能分析器](../07-perf/)
- 下一课：[09 - 内核调优（sysctl）](../09-kernel-tuning/)
- 相关课程：[LX10 - eBPF 入门](../10-ebpf-introduction/) - Off-CPU 分析需要

---

## 系列导航

[<-- 07 - perf 性能分析器](../07-perf/) | [系列首页](../) | [09 - 内核调优 -->](../09-kernel-tuning/)
