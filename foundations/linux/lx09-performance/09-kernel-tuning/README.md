# 09 - 内核调优（sysctl）

> **目标**：掌握 sysctl 调优方法论，学会安全地优化内核参数  
> **前置**：LX09-08 Flamegraph（理解性能分析流程）  
> **时间**：⚡ 20 分钟（速读）/ 🔬 75 分钟（完整实操）  
> **实战场景**：パラメータチューニング、変更管理、エビデンス記録  

---

## 将学到的内容

1. 理解 sysctl 工作机制和配置文件
2. 掌握调优方法论：测量 -> 改变 -> 验证
3. 识别安全调优参数 vs 危险调优参数
4. 应用常见工作负载配置（Web 服务器、数据库、批处理）
5. 持久化 sysctl 设置
6. 了解 Tuned 服务自动化调优

---

## 核心原则（所有 AI 共识）

在开始之前，请牢记这四条核心原则：

<!-- DIAGRAM: tuning-principles -->
```
┌─────────────────────────────────────────────────────────────────────────┐
│                     内核调优四大核心原则                                  │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│   ┌─────────────────────────────────────────────────────────────────┐  │
│   │  1. 永远先测量（Measure First）                                   │  │
│   │     没有基线数据，你不知道调优是否有效                              │  │
│   │     "改完感觉快了" 不是证据                                       │  │
│   └─────────────────────────────────────────────────────────────────┘  │
│                                                                         │
│   ┌─────────────────────────────────────────────────────────────────┐  │
│   │  2. 一次只改一个参数（One Change at a Time）                       │  │
│   │     同时改多个参数，无法判断哪个有效                                │  │
│   │     出问题也无法定位原因                                          │  │
│   └─────────────────────────────────────────────────────────────────┘  │
│                                                                         │
│   ┌─────────────────────────────────────────────────────────────────┐  │
│   │  3. 现代内核自动调优很好（Modern Kernels Auto-Tune Well）          │  │
│   │     Linux 5.x/6.x 的默认值经过大量优化                            │  │
│   │     大多数情况下，默认值就是最佳值                                  │  │
│   └─────────────────────────────────────────────────────────────────┘  │
│                                                                         │
│   ┌─────────────────────────────────────────────────────────────────┐  │
│   │  4. 2015 年的调优建议大多已过时（Old Advice is Outdated）          │  │
│   │     不要复制老博客的参数                                          │  │
│   │     内核版本不同，最佳参数也不同                                    │  │
│   └─────────────────────────────────────────────────────────────────┘  │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```
<!-- /DIAGRAM -->

---

## 先跑起来！（10 分钟）

> 在学习调优理论之前，先看看当前系统的内核参数。  

```bash
# 查看当前系统有多少个可调参数
sysctl -a 2>/dev/null | wc -l

# 查看几个关键参数
echo "=== 内存相关 ==="
sysctl vm.swappiness
sysctl vm.dirty_ratio
sysctl vm.dirty_background_ratio

echo ""
echo "=== 网络相关 ==="
sysctl net.core.rmem_max
sysctl net.core.wmem_max
sysctl net.ipv4.tcp_rmem
sysctl net.ipv4.tcp_wmem

echo ""
echo "=== 文件系统 ==="
sysctl fs.file-max
sysctl fs.nr_open

echo ""
echo "=== 内核信息 ==="
uname -r
```

**你刚刚看到了系统的关键调优参数！**

- `vm.swappiness`：控制 swap 使用倾向（0-100）
- `vm.dirty_ratio`：脏页占内存比例达到多少时强制写回
- `net.core.rmem_max`：TCP 接收缓冲区最大值

**问题来了**：这些默认值好不好？需要改吗？

**答案**：**先测量**！没有基线数据，你无法判断是否需要调优。

---

## Step 1 - sysctl 基础（10 分钟）

### 1.1 什么是 sysctl？

**sysctl** 是 Linux 内核参数的运行时配置接口。

```bash
# sysctl 读写的是 /proc/sys/ 目录下的文件
ls /proc/sys/
# 输出：abi  crypto  debug  dev  fs  kernel  net  user  vm

# 例如 vm.swappiness 对应
cat /proc/sys/vm/swappiness
# 等同于
sysctl vm.swappiness
```

### 1.2 常用 sysctl 命令

```bash
# 列出所有参数
sysctl -a

# 查看单个参数
sysctl vm.swappiness

# 临时修改（重启后失效）
sudo sysctl -w vm.swappiness=10

# 或直接写文件（效果相同）
echo 10 | sudo tee /proc/sys/vm/swappiness

# 从配置文件重新加载
sudo sysctl --system

# 查看特定类别
sysctl -a | grep ^net.core
sysctl -a | grep ^vm.
```

### 1.3 配置文件层次

sysctl 配置文件按优先级从低到高：

```bash
# 配置文件加载顺序（后加载的覆盖先加载的）
/usr/lib/sysctl.d/*.conf      # 系统默认
/run/sysctl.d/*.conf          # 运行时
/etc/sysctl.d/*.conf          # 管理员自定义（推荐）
/etc/sysctl.conf              # 传统位置（仍支持）
```

**最佳实践**：在 `/etc/sysctl.d/` 创建自定义配置文件

```bash
# 推荐的命名方式
/etc/sysctl.d/99-custom.conf      # 99 保证最后加载
/etc/sysctl.d/99-performance.conf # 按用途命名
```

---

## Step 2 - 调优方法论（15 分钟）

### 2.1 三步调优流程

<!-- DIAGRAM: tuning-methodology -->
```
┌─────────────────────────────────────────────────────────────────────────┐
│                       调优方法论：三步流程                                │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│   ┌─────────────┐      ┌─────────────┐      ┌─────────────┐           │
│   │   BASELINE  │ ───► │   CHANGE    │ ───► │   VERIFY    │           │
│   │   建立基线    │      │   修改参数    │      │   验证效果    │           │
│   └─────────────┘      └─────────────┘      └─────────────┘           │
│                                                                         │
│   Step 1: 基线              Step 2: 变更              Step 3: 验证      │
│   ─────────────              ─────────────              ─────────────    │
│   • 采集当前性能              • 记录当前值               • 采集新性能     │
│   • 记录当前参数值            • 修改一个参数              • 与基线对比     │
│   • 生成基线报告              • 记录修改原因              • 判断是否有效   │
│                                                                         │
│   输出：                     输出：                     输出：           │
│   baseline_before.txt       change_log.txt            baseline_after.txt│
│                                                                         │
│   ┌─────────────────────────────────────────────────────────────────┐  │
│   │  如果效果不佳或出现问题 → 回滚到原值 → 尝试其他参数               │  │
│   └─────────────────────────────────────────────────────────────────┘  │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```
<!-- /DIAGRAM -->

### 2.2 实战：调优 vm.swappiness

**场景**：数据库服务器希望减少 swap 使用

**Step 1：建立基线**

```bash
#!/bin/bash
# tuning-baseline.sh - 调优前基线采集

BASELINE_DIR="tuning_baseline_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BASELINE_DIR"
cd "$BASELINE_DIR"

echo "=== 采集调优基线 ===" | tee baseline.txt

# 1. 记录当前参数值
echo "" >> baseline.txt
echo "【当前 sysctl 参数】" >> baseline.txt
echo "vm.swappiness = $(sysctl -n vm.swappiness)" >> baseline.txt
echo "vm.dirty_ratio = $(sysctl -n vm.dirty_ratio)" >> baseline.txt
echo "vm.dirty_background_ratio = $(sysctl -n vm.dirty_background_ratio)" >> baseline.txt

# 2. 采集内存状态
echo "" >> baseline.txt
echo "【内存状态】" >> baseline.txt
free -h >> baseline.txt

# 3. 采集 swap 使用
echo "" >> baseline.txt
echo "【Swap 活动】" >> baseline.txt
vmstat 1 10 | tee vmstat.txt >> baseline.txt

# 4. PSI 内存压力
echo "" >> baseline.txt
echo "【PSI 内存压力】" >> baseline.txt
cat /proc/pressure/memory >> baseline.txt

echo ""
echo "基线采集完成: $BASELINE_DIR/baseline.txt"
```

**Step 2：修改参数**

```bash
# 1. 记录当前值
CURRENT_SWAPPINESS=$(sysctl -n vm.swappiness)
echo "当前 vm.swappiness = $CURRENT_SWAPPINESS"

# 2. 记录修改原因
cat > change_log.txt << EOF
日期: $(date)
参数: vm.swappiness
原值: $CURRENT_SWAPPINESS
新值: 10
原因: 数据库服务器，减少 swap 使用，优先保留数据库缓存
参考: 内部调优指南 v2.1
EOF

# 3. 临时修改（测试用）
sudo sysctl -w vm.swappiness=10

# 4. 确认修改
sysctl vm.swappiness
```

**Step 3：验证效果**

```bash
# 运行相同的基线脚本，对比结果
./tuning-baseline.sh

# 对比前后 vmstat 输出
echo "=== Swap 活动对比 ==="
echo "修改前 si/so 平均值:"
awk 'NR>2 {si+=$7; so+=$8; n++} END {print "si:", si/n, "so:", so/n}' tuning_baseline_*/vmstat.txt

echo "修改后 si/so 平均值:"
awk 'NR>2 {si+=$7; so+=$8; n++} END {print "si:", si/n, "so:", so/n}' tuning_baseline_*/vmstat.txt
```

### 2.3 完整调优脚本

```bash
#!/bin/bash
# safe-sysctl-tune.sh - 安全的 sysctl 调优脚本
# 用法: ./safe-sysctl-tune.sh <参数名> <新值>
#
# 特点：
# 1. 自动备份当前值
# 2. 记录变更日志
# 3. 支持回滚

set -e

PARAM=$1
NEW_VALUE=$2
LOG_DIR="${HOME}/sysctl-changes"
LOG_FILE="${LOG_DIR}/changes.log"

if [ -z "$PARAM" ] || [ -z "$NEW_VALUE" ]; then
    echo "用法: $0 <参数名> <新值>"
    echo "示例: $0 vm.swappiness 10"
    exit 1
fi

# 确保日志目录存在
mkdir -p "$LOG_DIR"

# 获取当前值
CURRENT_VALUE=$(sysctl -n "$PARAM" 2>/dev/null)
if [ -z "$CURRENT_VALUE" ]; then
    echo "错误: 参数 $PARAM 不存在"
    exit 1
fi

# 记录变更
echo "$(date '+%Y-%m-%d %H:%M:%S') | $PARAM | $CURRENT_VALUE -> $NEW_VALUE" >> "$LOG_FILE"

# 应用变更
echo "变更: $PARAM"
echo "  原值: $CURRENT_VALUE"
echo "  新值: $NEW_VALUE"
echo ""

read -p "确认修改? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    sudo sysctl -w "$PARAM=$NEW_VALUE"
    echo "修改成功！"
    echo ""
    echo "回滚命令: sudo sysctl -w $PARAM=$CURRENT_VALUE"
else
    echo "已取消"
fi
```

---

## Step 3 - 安全调优参数（15 分钟）

### 3.1 参数分类

<!-- DIAGRAM: parameter-safety -->
```
┌─────────────────────────────────────────────────────────────────────────┐
│                       sysctl 参数安全分类                                │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│   ┌─────────────────────────────────────────────────────────────────┐  │
│   │  安全区域（可由运维调整）                                          │  │
│   │  ────────────────────────                                        │  │
│   │  vm.swappiness           (10-60)                                 │  │
│   │  vm.dirty_ratio          (5-40)                                  │  │
│   │  vm.dirty_background_ratio (1-10)                                │  │
│   │  net.core.rmem_max       (增大)                                  │  │
│   │  net.core.wmem_max       (增大)                                  │  │
│   │  net.core.somaxconn      (增大)                                  │  │
│   │  net.ipv4.tcp_max_syn_backlog (增大)                             │  │
│   └─────────────────────────────────────────────────────────────────┘  │
│                                                                         │
│   ┌─────────────────────────────────────────────────────────────────┐  │
│   │  谨慎区域（需要专家评审）                                          │  │
│   │  ────────────────────────                                        │  │
│   │  kernel.sched_*          调度器参数                               │  │
│   │  vm.overcommit_*         内存过量分配                              │  │
│   │  vm.min_free_kbytes      最小空闲内存                              │  │
│   │  net.ipv4.ip_local_port_range  本地端口范围                        │  │
│   └─────────────────────────────────────────────────────────────────┘  │
│                                                                         │
│   ┌─────────────────────────────────────────────────────────────────┐  │
│   │  危险区域（永远不改！）                                            │  │
│   │  ────────────────────────                                        │  │
│   │  kernel.randomize_va_space    ASLR 安全机制                       │  │
│   │  kernel.dmesg_restrict        dmesg 访问限制                      │  │
│   │  kernel.kptr_restrict         内核指针限制                         │  │
│   │  kernel.exec-shield-*         执行保护                            │  │
│   │  net.ipv4.ip_forward          除非明确需要路由功能                  │  │
│   └─────────────────────────────────────────────────────────────────┘  │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```
<!-- /DIAGRAM -->

### 3.2 内存参数详解

#### vm.swappiness

控制内核使用 swap 的倾向（0-200，默认 60）

```bash
# 查看当前值
sysctl vm.swappiness

# 典型配置
# 60  - 默认值，平衡策略
# 10  - 数据库服务器，减少 swap 使用
# 1   - 尽量不用 swap，但不完全禁用
# 0   - 只在内存极度紧张时使用 swap
```

**什么时候调低？**
- 数据库服务器（PostgreSQL, MySQL）需要大量内存缓存
- 内存充足但希望避免 swap 延迟

**什么时候保持默认？**
- 通用服务器
- 内存不充裕的系统

#### vm.dirty_ratio / vm.dirty_background_ratio

控制脏页（dirty pages）写回磁盘的时机

```bash
# 查看当前值
sysctl vm.dirty_ratio           # 默认 20（%）
sysctl vm.dirty_background_ratio # 默认 10（%）

# dirty_background_ratio: 后台写回开始的阈值
# dirty_ratio: 强制同步写回的阈值
```

**配置建议**：

| 场景 | dirty_ratio | dirty_background_ratio | 说明 |
|------|-------------|------------------------|------|
| 默认 | 20 | 10 | 平衡策略 |
| 写入密集 | 40 | 10 | 允许更多脏页缓存 |
| 低延迟 | 10 | 5 | 更频繁写回 |
| SSD | 15 | 5 | SSD 写入快，可以更积极写回 |

### 3.3 网络参数详解

#### TCP 缓冲区

```bash
# 接收缓冲区最大值
sysctl net.core.rmem_max        # 默认约 200KB
sysctl net.core.wmem_max        # 默认约 200KB

# TCP 自动调优范围 (min, default, max)
sysctl net.ipv4.tcp_rmem        # 4096 131072 6291456
sysctl net.ipv4.tcp_wmem        # 4096 16384 4194304
```

**高带宽场景配置**：

```bash
# 增大缓冲区最大值（16MB）
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216

# TCP 缓冲区范围
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216
```

#### 连接队列

```bash
# 最大连接队列
sysctl net.core.somaxconn           # 默认 4096
sysctl net.ipv4.tcp_max_syn_backlog # 默认 1024

# 高并发场景
net.core.somaxconn = 65535
net.ipv4.tcp_max_syn_backlog = 65535
```

---

## Step 4 - 工作负载配置示例（15 分钟）

### 4.1 Web 服务器配置

```bash
# /etc/sysctl.d/99-web-server.conf
# Web 服务器优化配置
# 适用于：Nginx, Apache, Node.js 等高并发 Web 服务

# ========================================
# 网络优化
# ========================================

# 增大连接队列（高并发必须）
net.core.somaxconn = 65535
net.ipv4.tcp_max_syn_backlog = 65535

# 增大 TCP 缓冲区
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216

# TIME_WAIT 优化
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 30

# 本地端口范围（大量出站连接时需要）
net.ipv4.ip_local_port_range = 10240 65535

# ========================================
# 内存优化
# ========================================

# 保守的 swap 使用
vm.swappiness = 10

# ========================================
# 文件描述符
# ========================================

# 最大打开文件数
fs.file-max = 2097152
fs.nr_open = 2097152
```

### 4.2 数据库服务器配置

```bash
# /etc/sysctl.d/99-database.conf
# 数据库服务器优化配置
# 适用于：PostgreSQL, MySQL, MariaDB

# ========================================
# 内存优化（数据库核心）
# ========================================

# 最小化 swap 使用（保护数据库缓存）
vm.swappiness = 10

# 增加脏页缓存（数据库写入优化）
vm.dirty_ratio = 40
vm.dirty_background_ratio = 10

# 防止 OOM 杀死数据库进程
vm.overcommit_memory = 2
vm.overcommit_ratio = 80

# ========================================
# 网络优化
# ========================================

# 增大 TCP 缓冲区（大数据传输）
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216

# ========================================
# 磁盘 I/O
# ========================================

# 增加预读（顺序读取优化）
# 注意：这个通过 blockdev 设置，不是 sysctl
# blockdev --setra 4096 /dev/sda
```

### 4.3 批处理/计算服务器配置

```bash
# /etc/sysctl.d/99-batch-job.conf
# 批处理/计算服务器优化配置
# 适用于：数据处理、科学计算、日志分析

# ========================================
# 内存优化
# ========================================

# 允许适度使用 swap（批处理可以容忍）
vm.swappiness = 30

# 增大脏页缓存（大文件处理）
vm.dirty_ratio = 60
vm.dirty_background_ratio = 20

# ========================================
# 进程限制
# ========================================

# 增大进程数限制
kernel.pid_max = 4194304

# ========================================
# 虚拟内存
# ========================================

# 允许 overcommit（大数据处理常见）
# 注意：需要配合应用程序的内存管理
vm.overcommit_memory = 1
```

### 4.4 配置应用与验证

```bash
# 应用配置
sudo cp 99-web-server.conf /etc/sysctl.d/
sudo sysctl --system

# 验证配置
echo "=== 验证网络配置 ==="
sysctl net.core.somaxconn
sysctl net.ipv4.tcp_max_syn_backlog

echo "=== 验证内存配置 ==="
sysctl vm.swappiness
sysctl vm.dirty_ratio

# 检查是否有错误
journalctl -b | grep sysctl
```

---

## Step 5 - 调优模板（10 分钟）

### 5.1 通用调优模板

```bash
# /etc/sysctl.d/99-performance.conf
# ========================================
# 通用性能调优模板
# ========================================
#
# 重要：在应用前请先建立基线！
#   ./use-baseline.sh > before.txt
#
# 应用后验证：
#   ./use-baseline.sh > after.txt
#   diff before.txt after.txt
#
# ========================================

# ----------------------------------------
# 内存调优（安全范围）
# ----------------------------------------

# Swap 使用倾向（10-60）
# 10: 数据库/缓存服务器
# 30: 批处理服务器
# 60: 默认（通用服务器）
vm.swappiness = 10

# 脏页写回阈值
# dirty_background_ratio: 后台写回开始
# dirty_ratio: 强制同步写回
vm.dirty_ratio = 15
vm.dirty_background_ratio = 5

# ----------------------------------------
# 网络调优（安全范围）
# ----------------------------------------

# TCP 缓冲区最大值（高带宽场景）
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216

# TCP 缓冲区范围
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216

# 连接队列（高并发场景）
net.core.somaxconn = 65535
net.ipv4.tcp_max_syn_backlog = 65535

# ----------------------------------------
# 以下参数默认不启用，按需取消注释
# ----------------------------------------

# TIME_WAIT 优化（仅出站连接密集场景）
# net.ipv4.tcp_tw_reuse = 1
# net.ipv4.tcp_fin_timeout = 30

# 本地端口范围（大量出站连接）
# net.ipv4.ip_local_port_range = 10240 65535
```

### 5.2 调优检查脚本

```bash
#!/bin/bash
# sysctl-audit.sh - sysctl 配置审计脚本

echo "============================================"
echo "  sysctl 配置审计报告"
echo "  时间: $(date)"
echo "  内核: $(uname -r)"
echo "============================================"
echo ""

# 内存参数
echo "【内存参数】"
echo "  vm.swappiness = $(sysctl -n vm.swappiness)"
SWAP=$(sysctl -n vm.swappiness)
if [ "$SWAP" -gt 60 ]; then
    echo "    建议: 数据库服务器考虑降低到 10-30"
fi

echo "  vm.dirty_ratio = $(sysctl -n vm.dirty_ratio)"
echo "  vm.dirty_background_ratio = $(sysctl -n vm.dirty_background_ratio)"
echo ""

# 网络参数
echo "【网络参数】"
echo "  net.core.somaxconn = $(sysctl -n net.core.somaxconn)"
SOMAXCONN=$(sysctl -n net.core.somaxconn)
if [ "$SOMAXCONN" -lt 1024 ]; then
    echo "    建议: 高并发场景考虑增大到 65535"
fi

echo "  net.core.rmem_max = $(sysctl -n net.core.rmem_max)"
RMEM=$(sysctl -n net.core.rmem_max)
if [ "$RMEM" -lt 1048576 ]; then
    echo "    建议: 高带宽场景考虑增大到 16777216"
fi

echo "  net.ipv4.tcp_max_syn_backlog = $(sysctl -n net.ipv4.tcp_max_syn_backlog)"
echo ""

# 安全参数检查
echo "【安全参数】"
ASLR=$(sysctl -n kernel.randomize_va_space 2>/dev/null)
if [ "$ASLR" != "2" ]; then
    echo "  WARNING: ASLR 未完全启用 (当前=$ASLR, 应为=2)"
else
    echo "  kernel.randomize_va_space = 2 (OK)"
fi

echo ""

# 配置文件检查
echo "【配置文件】"
echo "  /etc/sysctl.d/ 目录内容:"
ls -la /etc/sysctl.d/ 2>/dev/null || echo "    目录不存在"
echo ""

echo "审计完成。"
```

---

## Step 6 - Tuned 服务简介（5 分钟）

### 6.1 什么是 Tuned？

**Tuned** 是 Red Hat 提供的动态系统调优服务，预置了多种工作负载配置。

```bash
# 安装（RHEL/CentOS/Rocky）
sudo dnf install tuned

# 安装（Debian/Ubuntu）
sudo apt install tuned

# 启动服务
sudo systemctl enable --now tuned
```

### 6.2 使用 Tuned

```bash
# 查看可用配置
tuned-adm list

# 输出示例：
# - balanced               # 平衡（默认）
# - throughput-performance # 高吞吐量
# - latency-performance    # 低延迟
# - network-latency        # 网络低延迟
# - network-throughput     # 网络高吞吐
# - virtual-guest          # 虚拟机
# - virtual-host           # 虚拟化宿主机

# 查看当前配置
tuned-adm active

# 应用配置
sudo tuned-adm profile throughput-performance

# 推荐配置
tuned-adm recommend
```

### 6.3 Tuned vs 手动调优

| 比较项 | Tuned | 手动 sysctl |
|--------|-------|-------------|
| 易用性 | 一键切换 | 需要编写配置 |
| 灵活性 | 预设配置 | 完全自定义 |
| 动态调整 | 支持 | 不支持 |
| 适用场景 | 通用服务器 | 精细调优 |
| 学习曲线 | 低 | 高 |

**建议**：
- 新手/通用场景：使用 Tuned
- 高级场景/精细调优：手动 sysctl + Tuned 配合

---

## 反模式：常见错误

### 错误 1：先调优后测量（Tuning Before Measuring）

```bash
# 错误：直接从网上复制参数
echo "vm.swappiness = 10" >> /etc/sysctl.conf
echo "改完了！应该更快了吧..."

# 正确：先建立基线
./use-baseline.sh > before.txt
# 修改参数
echo 10 | sudo tee /proc/sys/vm/swappiness
# 重新测量
./use-baseline.sh > after.txt
# 对比
diff before.txt after.txt
```

### 错误 2：复制 2015 年博客的参数

```bash
# 错误：过时的参数（可能在旧内核有效）
net.ipv4.tcp_tw_recycle = 1    # 已在 Linux 4.12 移除！
net.core.netdev_max_backlog = 300000  # 极端值
vm.min_free_kbytes = 1048576   # 可能导致 OOM

# 正确：验证参数是否适用于当前内核
sysctl net.ipv4.tcp_tw_recycle
# sysctl: cannot stat /proc/sys/net/ipv4/tcp_tw_recycle: No such file or directory
# 参数不存在！说明已过时
```

### 错误 3：同时修改多个参数

```bash
# 错误：一次改很多
vm.swappiness = 10
vm.dirty_ratio = 5
net.core.rmem_max = 67108864
net.core.somaxconn = 65535
# "感觉变快了..."
# 问题：无法知道哪个参数有效，哪个可能有害

# 正确：一次改一个
# Round 1: 只改 vm.swappiness，测量
# Round 2: 只改 net.core.somaxconn，测量
# ...
```

### 错误 4：忽略现代内核的自动调优

```bash
# 错误：强制设置固定值
net.ipv4.tcp_rmem = 4096 87380 16777216  # 固定最大值

# 更好：让内核自动调优
# 现代内核（5.x+）的 TCP 自动调优非常智能
# 只需设置 rmem_max 天花板，让内核自行决定
net.core.rmem_max = 16777216
# tcp_rmem 保持默认，内核会动态调整
```

---

## 职场小贴士（Japan IT Context）

### パラメータチューニング（参数调优）

在日本 IT 企业，参数调优需要严格的变更管理流程。

| 日语术语 | 读音 | 含义 | 关联 |
|----------|------|------|------|
| パラメータチューニング | パラメータチューニング | Parameter tuning | sysctl 调优 |
| 変更管理 | へんこうかんり | Change management | 变更流程 |
| エビデンス | エビデンス | Evidence | 调优前后数据 |
| 切り戻し | きりもどし | Rollback | 回滚到原值 |
| 影響調査 | えいきょうちょうさ | Impact analysis | 评估调优影响 |

### 変更管理（变更管理）

日本企业的参数变更流程通常包括：

1. **事前申請**（事前申请）：提交变更请求
2. **影響調査**（影响调查）：评估变更影响
3. **エビデンス取得**（证据获取）：采集基线数据
4. **変更実施**（变更实施）：应用变更
5. **事後確認**（事后确认）：验证变更效果
6. **切り戻し手順**（回滚步骤）：准备回滚方案

### 変更申請書 示例

```markdown
## 変更申請書

### 申請日
2026-01-10

### 変更対象
本番 Web サーバー (web-prod-01)

### 変更内容
sysctl パラメータ調整

| パラメータ | 変更前 | 変更後 | 根拠 |
|-----------|--------|--------|------|
| vm.swappiness | 60 | 10 | DB キャッシュ効率改善 |
| net.core.somaxconn | 4096 | 65535 | 高負荷時の接続拒否防止 |

### エビデンス
- 変更前ベースライン: baseline_20260110_before.txt
- 変更後データ: baseline_20260110_after.txt

### 影響
- 想定影響: DB 応答速度改善、接続エラー減少
- リスク: swap 使用時のメモリ逼迫

### 切り戻し手順
```bash
sudo sysctl -w vm.swappiness=60
sudo sysctl -w net.core.somaxconn=4096
```

### 承認
- 申請者: 田中
- 承認者: 鈴木（インフラリーダー）
```

---

## Mini-Project：工作负载调优实验（15 分钟）

### 任务目标

对 Web 服务器负载建立基线，应用调优，验证效果。

### 实验步骤

```bash
# 1. 创建工作目录
mkdir -p ~/tuning-lab
cd ~/tuning-lab

# 2. 保存当前参数（备份）
sysctl -a > sysctl_backup_$(date +%Y%m%d).txt

# 3. 创建基线脚本
cat > web-baseline.sh << 'EOF'
#!/bin/bash
# Web 服务器调优基线脚本

OUTPUT="web_baseline_$(date +%Y%m%d_%H%M%S).txt"

echo "=== Web 服务器调优基线 ===" > $OUTPUT
echo "时间: $(date)" >> $OUTPUT
echo "" >> $OUTPUT

# 当前参数
echo "【当前 sysctl 参数】" >> $OUTPUT
echo "vm.swappiness = $(sysctl -n vm.swappiness)" >> $OUTPUT
echo "net.core.somaxconn = $(sysctl -n net.core.somaxconn)" >> $OUTPUT
echo "net.core.rmem_max = $(sysctl -n net.core.rmem_max)" >> $OUTPUT
echo "" >> $OUTPUT

# 网络连接统计
echo "【网络连接统计】" >> $OUTPUT
ss -s >> $OUTPUT
echo "" >> $OUTPUT

# 内存状态
echo "【内存状态】" >> $OUTPUT
free -h >> $OUTPUT
echo "" >> $OUTPUT

# PSI 压力
echo "【PSI 压力】" >> $OUTPUT
cat /proc/pressure/cpu >> $OUTPUT
cat /proc/pressure/memory >> $OUTPUT
cat /proc/pressure/io >> $OUTPUT
echo "" >> $OUTPUT

echo "基线保存到: $OUTPUT"
cat $OUTPUT
EOF

chmod +x web-baseline.sh

# 4. 采集变更前基线
./web-baseline.sh

# 5. 创建调优配置
cat > 99-web-tuning-test.conf << 'EOF'
# Web 服务器调优测试配置
vm.swappiness = 10
net.core.somaxconn = 65535
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
EOF

# 6. 应用配置（临时测试）
echo "应用调优参数..."
sudo sysctl -w vm.swappiness=10
sudo sysctl -w net.core.somaxconn=65535
sudo sysctl -w net.core.rmem_max=16777216
sudo sysctl -w net.core.wmem_max=16777216

# 7. 采集变更后基线
./web-baseline.sh

# 8. 对比结果
echo ""
echo "=== 调优对比 ==="
echo "变更前:"
grep "vm.swappiness\|somaxconn\|rmem_max" web_baseline_*.txt | head -4
echo ""
echo "变更后:"
grep "vm.swappiness\|somaxconn\|rmem_max" web_baseline_*.txt | tail -4
```

### 验证检查清单

完成以下任务：

- [ ] 备份当前 sysctl 参数
- [ ] 采集变更前基线数据
- [ ] 记录变更原因和预期效果
- [ ] 应用调优参数
- [ ] 采集变更后基线数据
- [ ] 对比前后数据，评估效果
- [ ] 准备回滚命令

---

## 面试准备（Interview Prep）

### Q1: sysctl パラメータを変更する前に何をすべきですか？

**回答要点**：

```
sysctl パラメータを変更する前に、以下の手順を実施します：

1. ベースライン取得
   - 現在のパラメータ値を記録
   - 現在の性能データを採取（vmstat, iostat 等）

2. 変更計画の作成
   - 変更するパラメータと新しい値
   - 変更の根拠（なぜこの値なのか）
   - 想定される影響

3. 切り戻し手順の準備
   - 元の値に戻すコマンドを用意

4. 一度に変更するのは一つのパラメータのみ
   - 複数同時に変更すると、効果の判断が困難
```

### Q2: vm.swappiness を下げると何が起きますか？

**回答要点**：

```
vm.swappiness はカーネルが swap を使用する傾向を制御します。

値を下げると（例：60 → 10）：
- メリット：
  - アプリケーションのメモリがスワップアウトされにくい
  - データベースのキャッシュが保持されやすい
  - swap I/O による遅延が減少

- デメリット：
  - メモリ逼迫時に OOM Killer が発生しやすい
  - ファイルキャッシュが減少する可能性

適用場面：
- データベースサーバー（10-30 が一般的）
- キャッシュサーバー（Memcached, Redis）

注意点：
- メモリが十分にある環境で効果的
- 必ずベースラインを取得してから変更
```

### Q3: 古いブログの sysctl 設定をコピーしてはいけない理由は？

**回答要点**：

```
2015年頃のブログ設定をコピーすべきでない理由：

1. パラメータが削除されている可能性
   - 例：net.ipv4.tcp_tw_recycle は Linux 4.12 で削除
   - 存在しないパラメータを設定するとエラー

2. デフォルト値が改善されている
   - 現代のカーネル（5.x, 6.x）は自動チューニングが優秀
   - 古い「最適値」が今のデフォルトより悪い場合も

3. ハードウェア環境が違う
   - SSD の普及、メモリ容量の増加
   - 10年前の最適値は現在の環境に合わない

正しいアプローチ：
- 公式ドキュメントを参照
- ベースラインを取得してから変更
- 一つずつ変更して効果を検証
```

---

## 检查清单

完成本课后，你应该能够：

- [ ] 使用 sysctl 查看和修改内核参数
- [ ] 遵循调优方法论：基线 -> 变更 -> 验证
- [ ] 区分安全调优参数和危险参数
- [ ] 创建持久化的 sysctl 配置文件（/etc/sysctl.d/）
- [ ] 应用常见工作负载配置（Web、数据库、批处理）
- [ ] 使用 Tuned 服务进行自动化调优
- [ ] 避免常见反模式（先调优后测量、复制旧参数等）
- [ ] 准备完整的变更文档（日本 IT 标准）

---

## 本课小结

| 概念 | 要点 |
|------|------|
| sysctl | 内核参数运行时配置接口 |
| 调优方法论 | 基线 -> 变更 -> 验证，一次一个参数 |
| 安全参数 | vm.swappiness, vm.dirty_ratio, net.core.rmem_max |
| 危险参数 | 安全相关参数永远不改 |
| 配置持久化 | /etc/sysctl.d/99-*.conf |
| Tuned | Red Hat 自动化调优服务 |
| 核心原则 | 永远先测量，现代内核自动调优很好 |

---

## 延伸阅读

- [Linux Kernel sysctl 文档](https://www.kernel.org/doc/html/latest/admin-guide/sysctl/)
- [Red Hat Tuned 官方文档](https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/9/html/monitoring_and_managing_system_status_and_performance/getting-started-with-tuned_monitoring-and-managing-system-status-and-performance)
- [Brendan Gregg 的 Linux 性能调优](https://www.brendangregg.com/linuxperf.html)
- 上一课：[08 - Flamegraph 火焰图](../08-flamegraphs/)
- 下一课：[10 - eBPF 入门](../10-ebpf-introduction/)

---

## 系列导航

[<-- 08 - Flamegraph](../08-flamegraphs/) | [系列首页](../) | [10 - eBPF 入门 -->](../10-ebpf-introduction/)
