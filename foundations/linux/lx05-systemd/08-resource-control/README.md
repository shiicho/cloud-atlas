# 08 - 资源控制（cgroup v2）

> **目标**：掌握 cgroup v2 资源限制，防止服务成为"吵闹邻居"影响系统稳定  
> **前置**：已完成 [03 - Unit 文件解剖](../03-unit-files/)  
> **时间**：⚡ 15 分钟（速读）/ 🔬 50 分钟（完整实操）  
> **实战场景**：月次バッチ（Monthly Batch）消耗 32GB RAM 导致 OOM Killer 停止 SSH  

---

## 将学到的内容

1. 理解 cgroup v2 与 systemd 的集成
2. 配置 CPU 限制（CPUQuota, CPUWeight）
3. 配置内存限制（MemoryMax, MemoryHigh）
4. 配置 I/O 限制（IOWeight, IOBandwidthMax）
5. 使用 systemd-cgtop 监控资源
6. 了解 systemd-oomd 的 OOM 处理

---

## 先跑起来！（5 分钟）

> 在深入理论之前，先用 `systemd-cgtop` 看看系统资源使用情况。  

### 实时监控系统资源

```bash
# 启动 cgroup 资源监控（类似 top，但按 cgroup 分组）
sudo systemd-cgtop
```

**你应该看到**：

```
Control Group                            Tasks   %CPU   Memory  Input/s Output/s
/                                          245   12.3     3.2G        -        -
/system.slice                               89    8.1     1.5G        -        -
/system.slice/sshd.service                   3    0.1    12.5M        -        -
/system.slice/nginx.service                  5    0.3    45.2M        -        -
/user.slice                                 45    3.2   512.4M        -        -
```

**关键观察**：
- 每个服务都在独立的 cgroup 中
- 可以看到每个服务的 CPU、内存使用
- 系统按 `system.slice`、`user.slice` 分层组织

### 查看服务的资源限制

```bash
# 查看 nginx 的内存限制（如果没有 nginx，用 sshd）
systemctl show nginx -p MemoryMax,MemoryCurrent,CPUQuotaPerSecUSec

# 查看所有资源相关属性
systemctl show nginx --property=Memory*,CPU*,IO*,Tasks*
```

**恭喜！** 你刚刚看到了 systemd 的资源监控能力。接下来，让我们学习如何设置限制。

---

## Step 1 -- cgroup v2 基础（10 分钟）

### 1.1 什么是 cgroup？

cgroup（Control Groups）是 Linux 内核的资源限制机制。systemd 使用 cgroup 来：

- **隔离**：每个服务在独立的 cgroup 中
- **限制**：设置 CPU、内存、I/O 上限
- **追踪**：即使进程 fork 子进程，也能追踪到服务
- **监控**：统计每个服务的资源使用

### 1.2 cgroup v1 vs v2

![cgroup v1 vs v2](images/cgroup-v1-v2.png)

<details>
<summary>View ASCII source</summary>

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    cgroup v1 vs v2 架构对比                               │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  cgroup v1（旧架构）                                                      │
│  ─────────────────                                                       │
│                                                                          │
│    ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐              │
│    │ cpu      │  │ memory   │  │ blkio    │  │ cpuset   │              │
│    └────┬─────┘  └────┬─────┘  └────┬─────┘  └────┬─────┘              │
│         │             │             │             │                      │
│    ┌────▼─────┐  ┌────▼─────┐  ┌────▼─────┐  ┌────▼─────┐              │
│    │ nginx    │  │ nginx    │  │ nginx    │  │ nginx    │              │
│    └──────────┘  └──────────┘  └──────────┘  └──────────┘              │
│         ▲                                                               │
│         └── 问题：同一服务在多个层次结构中                               │
│                                                                          │
│  ─────────────────────────────────────────────────────────────────────  │
│                                                                          │
│  cgroup v2（统一层次结构）                                                │
│  ────────────────────────                                                │
│                                                                          │
│                    ┌──────────────────────┐                             │
│                    │   Unified Hierarchy   │                             │
│                    │  (CPU+Memory+IO+...)  │                             │
│                    └──────────┬───────────┘                             │
│                               │                                          │
│         ┌─────────────────────┼─────────────────────┐                   │
│         │                     │                     │                    │
│    ┌────▼─────┐         ┌────▼─────┐         ┌────▼─────┐              │
│    │ nginx    │         │ postgres │         │ redis    │              │
│    │ CPU: 50% │         │ Mem: 4G  │         │ IO: 100  │              │
│    │ Mem: 1G  │         │ CPU: 200%│         │ Mem: 512M│              │
│    └──────────┘         └──────────┘         └──────────┘              │
│         ▲                                                               │
│         └── 优势：所有资源在同一层次结构中管理                           │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

</details>

### 1.3 2025 年起：cgroup v2 是默认配置

| 发行版 | cgroup 版本 | 说明 |
|--------|-------------|------|
| RHEL 9 / Rocky 9 | v2（默认） | 2022 年起 |
| Ubuntu 22.04+ | v2（默认） | 2022 年起 |
| Fedora 40+ | v2（默认） | 2024 年起 |
| Debian 12+ | v2（默认） | 2023 年起 |

**验证你的系统**：

```bash
# 检查 cgroup 版本
cat /sys/fs/cgroup/cgroup.controllers

# 如果输出包含 "cpu memory io"，说明是 cgroup v2
# 如果文件不存在，可能是 v1

# 另一种检查方式
mount | grep cgroup
# cgroup v2: "cgroup2 on /sys/fs/cgroup type cgroup2"
# cgroup v1: 多个 "cgroup on /sys/fs/cgroup/xxx type cgroup"
```

### 1.4 systemd 的资源切片（Slice）

![Slice Hierarchy](images/slice-hierarchy.png)

<details>
<summary>View ASCII source</summary>

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    systemd Slice 层次结构                                 │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│                         ┌────────────────┐                              │
│                         │   -.slice      │  ← 根切片                    │
│                         │  (root slice)  │                              │
│                         └───────┬────────┘                              │
│                                 │                                        │
│         ┌───────────────────────┼───────────────────────┐               │
│         │                       │                       │                │
│    ┌────▼─────┐           ┌────▼─────┐           ┌────▼─────┐          │
│    │ system   │           │  user    │           │ machine  │          │
│    │ .slice   │           │ .slice   │           │ .slice   │          │
│    └────┬─────┘           └────┬─────┘           └────┬─────┘          │
│         │                      │                      │                  │
│    系统服务               用户会话               虚拟机/容器             │
│    ├── nginx.service      ├── user@1000.slice    ├── docker.service    │
│    ├── sshd.service       │   ├── session-1      └── vm@centos.scope   │
│    ├── postgresql.service │   └── dbus.service                          │
│    └── batch-job.service  └── user@1001.slice                           │
│                                                                          │
│  ─────────────────────────────────────────────────────────────────────  │
│                                                                          │
│  自定义 Slice 示例：                                                     │
│                                                                          │
│    ┌─────────────────┐                                                  │
│    │ batch.slice     │  ← 所有批处理任务的父切片                        │
│    └────────┬────────┘                                                  │
│             │                                                            │
│    ┌────────┼────────┐                                                  │
│    │        │        │                                                   │
│  daily    weekly   monthly                                               │
│  backup   cleanup  report                                                │
│  .service .service .service                                              │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

</details>

**三大默认切片**：

| Slice | 用途 | 典型成员 |
|-------|------|----------|
| `system.slice` | 系统服务 | nginx, sshd, postgresql |
| `user.slice` | 用户会话 | 用户登录后的进程 |
| `machine.slice` | 虚拟机/容器 | Docker 容器, libvirt VM |

---

## Step 2 -- CPU 限制（10 分钟）

### 2.1 CPUWeight vs CPUQuota

![CPU Control](images/cpu-control.png)

<details>
<summary>View ASCII source</summary>

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    CPU 控制：Weight vs Quota                              │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  CPUWeight（相对权重）                                                    │
│  ─────────────────────                                                   │
│                                                                          │
│    系统负载高时，按权重分配 CPU：                                         │
│                                                                          │
│    ┌──────────────────────────────────────────────────────────┐         │
│    │                    总 CPU 时间                           │         │
│    ├────────────────────────────┬─────────────────────────────┤         │
│    │      nginx (weight=100)    │    batch (weight=50)        │         │
│    │          66.7%             │         33.3%               │         │
│    └────────────────────────────┴─────────────────────────────┘         │
│                                                                          │
│    如果 batch 空闲，nginx 可以使用 100% CPU                              │
│                                                                          │
│  ─────────────────────────────────────────────────────────────────────  │
│                                                                          │
│  CPUQuota（硬限制）                                                       │
│  ─────────────────                                                       │
│                                                                          │
│    无论系统负载如何，都不能超过限制：                                     │
│                                                                          │
│    ┌──────────────────────────────────────────────────────────┐         │
│    │                    总 CPU 时间                           │         │
│    ├──────────────┬───────────────────────────────────────────┤         │
│    │ batch (50%)  │              空闲                         │         │
│    │    固定上限  │         即使空闲也不能使用                 │         │
│    └──────────────┴───────────────────────────────────────────┘         │
│                                                                          │
│    CPUQuota=50%  → 最多使用 0.5 个 CPU 核心                              │
│    CPUQuota=200% → 最多使用 2 个 CPU 核心（多核系统）                    │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

</details>

### 2.2 CPUWeight 配置

```ini
[Service]
# 默认值是 100
CPUWeight=100    # 默认权重
CPUWeight=50     # 一半权重（竞争时得到更少 CPU）
CPUWeight=200    # 双倍权重（竞争时得到更多 CPU）

# 取值范围：1-10000
# 只有在 CPU 竞争时才有意义
```

**适用场景**：
- 批处理任务设置低权重，让生产服务优先
- 关键服务设置高权重，确保响应速度

### 2.3 CPUQuota 配置

```ini
[Service]
# 硬限制：最多使用多少 CPU
CPUQuota=50%     # 最多 0.5 个 CPU 核心
CPUQuota=100%    # 最多 1 个 CPU 核心
CPUQuota=200%    # 最多 2 个 CPU 核心

# 实际含义：每 100ms 内可以使用多少 ms
# CPUQuota=50% → 每 100ms 内最多使用 50ms
```

**适用场景**：
- 限制批处理任务不影响生产服务
- 限制测试环境资源使用
- 多租户环境资源隔离

### 2.4 CPU 限制示例

```bash
# 创建一个 CPU 密集型服务来测试
sudo tee /etc/systemd/system/cpu-stress.service << 'EOF'
[Unit]
Description=CPU Stress Test Service

[Service]
Type=simple
ExecStart=/bin/bash -c 'while true; do echo; done > /dev/null'

# CPU 限制：最多 25% CPU
CPUQuota=25%

# CPU 权重：低于默认值
CPUWeight=50
EOF

sudo systemctl daemon-reload
```

```bash
# 启动并监控
sudo systemctl start cpu-stress

# 在另一个终端监控
sudo systemd-cgtop

# 观察 cpu-stress.service 的 CPU 使用（应该约 25%）

# 停止服务
sudo systemctl stop cpu-stress
```

---

## Step 3 -- 内存限制（15 分钟）

### 3.1 MemoryMax vs MemoryHigh

![Memory Control](images/memory-control.png)

<details>
<summary>View ASCII source</summary>

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    内存控制：MemoryMax vs MemoryHigh                      │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  MemoryMax（硬限制）                                                      │
│  ─────────────────                                                       │
│                                                                          │
│    MemoryMax=1G                                                          │
│                                                                          │
│    ┌──────────────────────────────────────────────────────────┐         │
│    │ ████████████████████████████████████████████████████████ │ 1G      │
│    └──────────────────────────────────────────────────────────┘         │
│                                            ▲                             │
│                                            │                             │
│                                       超过此限制                          │
│                                            │                             │
│                                            ▼                             │
│                                    ┌──────────────┐                      │
│                                    │  OOM Killer  │                      │
│                                    │  杀死进程！  │                      │
│                                    └──────────────┘                      │
│                                                                          │
│  ─────────────────────────────────────────────────────────────────────  │
│                                                                          │
│  MemoryHigh（软限制）                                                     │
│  ─────────────────                                                       │
│                                                                          │
│    MemoryHigh=750M                                                       │
│                                                                          │
│    ┌───────────────────────────────────────────────┬──────────┐         │
│    │ ██████████████████████████████████████████████│░░░░░░░░░░│ 1G      │
│    └───────────────────────────────────────────────┴──────────┘         │
│                                            ▲            ▲                │
│                                            │            │                │
│                                       超过此限制    仍可使用              │
│                                            │       但受到压力             │
│                                            ▼                             │
│                               ┌───────────────────────┐                  │
│                               │   内存回收压力增加     │                 │
│                               │   systemd-oomd 干预   │                 │
│                               └───────────────────────┘                  │
│                                                                          │
│  ─────────────────────────────────────────────────────────────────────  │
│                                                                          │
│  最佳实践：两者配合使用                                                   │
│                                                                          │
│    MemoryHigh=750M    ← 软限制，施加压力                                 │
│    MemoryMax=1G       ← 硬限制，绝对上限                                 │
│                                                                          │
│    正常: 0-750M（无压力）                                                │
│    警告: 750M-1G（有压力，系统尝试回收）                                 │
│    触发: >1G（OOM Killer 介入）                                          │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

</details>

### 3.2 内存相关指令

| 指令 | 作用 | 典型值 |
|------|------|--------|
| `MemoryMax=` | 硬限制，超过触发 OOM | 1G, 2G, 50% |
| `MemoryHigh=` | 软限制，超过施加压力 | MemoryMax 的 75% |
| `MemoryLow=` | 保证最小内存（低于此值不回收） | 128M, 256M |
| `MemoryMin=` | 绝对最小（更强保证） | 64M, 128M |
| `MemorySwapMax=` | 最大 swap 使用 | 0（禁用 swap） |

### 3.3 内存限制示例

```bash
# 创建内存限制测试服务
sudo tee /etc/systemd/system/mem-test.service << 'EOF'
[Unit]
Description=Memory Limit Test Service

[Service]
Type=simple
ExecStart=/bin/bash -c 'sleep infinity'

# 内存限制
MemoryMax=512M        # 硬限制：最多 512MB
MemoryHigh=400M       # 软限制：超过 400MB 施加压力
MemorySwapMax=0       # 禁用 swap
EOF

sudo systemctl daemon-reload
sudo systemctl start mem-test
```

```bash
# 查看内存配置
systemctl show mem-test -p MemoryMax,MemoryHigh,MemoryCurrent

# 查看 cgroup 详情
cat /sys/fs/cgroup/system.slice/mem-test.service/memory.max
cat /sys/fs/cgroup/system.slice/mem-test.service/memory.high
cat /sys/fs/cgroup/system.slice/mem-test.service/memory.current

# 清理
sudo systemctl stop mem-test
```

### 3.4 systemd-oomd：智能 OOM 处理

传统 OOM Killer 有个问题：它可能杀死重要服务（比如 sshd），导致无法远程登录排查问题。

**systemd-oomd** 是更智能的解决方案：

```bash
# 检查 systemd-oomd 状态
systemctl status systemd-oomd

# 查看 oomd 配置
cat /etc/systemd/oomd.conf
```

**systemd-oomd 工作原理**：

1. 监控服务的 `MemoryHigh` 超限情况
2. 计算内存压力（PSI - Pressure Stall Information）
3. 在系统陷入困境**之前**主动终止问题服务
4. 优先保护关键服务（sshd, init 等）

```ini
[Service]
# 启用 oomd 监控（需要 MemoryHigh）
MemoryHigh=750M
ManagedOOMSwap=auto
ManagedOOMMemoryPressure=auto
```

> **2023 更新**：systemd 253+（2023年2月发布）的 oomd 改进了基于 PSI 的决策，更加智能。  

---

## Step 4 -- I/O 和进程限制（10 分钟）

### 4.1 I/O 限制

```ini
[Service]
# I/O 权重（默认 100，范围 1-10000）
IOWeight=50              # 低 I/O 优先级

# I/O 带宽限制
IOReadBandwidthMax=/dev/sda 10M      # 读取最多 10MB/s
IOWriteBandwidthMax=/dev/sda 5M      # 写入最多 5MB/s

# I/O 操作限制（IOPS）
IOReadIOPSMax=/dev/sda 1000          # 最多 1000 次读/秒
IOWriteIOPSMax=/dev/sda 500          # 最多 500 次写/秒
```

**注意**：I/O 限制需要知道具体设备路径（如 `/dev/sda`）。在云环境中，设备名可能不固定。

### 4.2 进程限制（TasksMax）

```ini
[Service]
# 最大任务数（进程 + 线程）
TasksMax=100             # 最多 100 个任务

# 防止 fork 炸弹
# 默认值是系统限制的 15%
```

**fork 炸弹防护**：

```bash
# 系统默认限制
cat /proc/sys/kernel/threads-max

# 服务默认 TasksMax
systemctl show nginx -p TasksMax
```

### 4.3 传统 ulimit 限制

除了 cgroup 限制，还可以设置传统的 ulimit：

```ini
[Service]
# 最大打开文件数
LimitNOFILE=65535

# 最大进程数（注意：这是 ulimit，不是 cgroup TasksMax）
LimitNPROC=4096

# 核心转储大小
LimitCORE=infinity       # 允许完整 core dump
LimitCORE=0              # 禁用 core dump
```

---

## Step 5 -- 完整资源控制模板（5 分钟）

### 5.1 生产级资源限制模板

```ini
[Service]
# ===== CPU 限制 =====
CPUQuota=50%          # 最多 50% CPU（0.5 核心）
CPUWeight=50          # 竞争时低优先级（默认 100）

# ===== 内存限制 =====
MemoryMax=1G          # 硬限制：最多 1GB
MemoryHigh=750M       # 软限制：超过 750MB 施加压力
MemorySwapMax=0       # 禁用 swap

# ===== I/O 限制 =====
IOWeight=50           # 低 I/O 优先级
# IOReadBandwidthMax=/dev/sda 10M   # 可选：读取带宽限制

# ===== 进程限制 =====
TasksMax=100          # 最多 100 个任务（防 fork 炸弹）

# ===== 传统 ulimit =====
LimitNOFILE=65535     # 最大打开文件数
```

### 5.2 动态调整资源限制

```bash
# 不重启服务，直接修改资源限制
sudo systemctl set-property nginx MemoryMax=2G

# 查看修改后的值
systemctl show nginx -p MemoryMax

# 这个修改是持久化的，会创建 drop-in 文件
ls /etc/systemd/system/nginx.service.d/

# 如果只想临时修改（重启后恢复）
sudo systemctl set-property --runtime nginx MemoryMax=2G
```

---

## Step 6 -- 动手实验：资源限制防护（15 分钟）

> **场景**：为月度批处理任务设置资源限制，防止影响生产服务。  

### 6.1 创建模拟批处理服务

```bash
# 创建批处理脚本
sudo mkdir -p /opt/scripts
sudo tee /opt/scripts/monthly-batch.sh << 'EOF'
#!/bin/bash
# Monthly batch job simulation
# This script simulates a resource-intensive task

echo "Starting monthly batch job at $(date)"
echo "PID: $$"

# 模拟内存使用（创建临时数据）
echo "Allocating memory..."
for i in {1..10}; do
    data[$i]=$(head -c 10M /dev/urandom | base64)
    echo "Allocated ${i}0MB"
    sleep 1
done

# 模拟 CPU 使用
echo "Processing data..."
for i in {1..30}; do
    echo $i | md5sum > /dev/null
done

echo "Monthly batch job completed at $(date)"
EOF

sudo chmod +x /opt/scripts/monthly-batch.sh
```

### 6.2 创建带资源限制的服务

```bash
# 创建 Service 文件
sudo tee /etc/systemd/system/monthly-batch.service << 'EOF'
[Unit]
Description=Monthly Batch Job with Resource Limits
# 依赖网络（如果需要访问数据库）
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
User=root
ExecStart=/opt/scripts/monthly-batch.sh

# ===== 资源限制 =====
# CPU: 最多 25%，低优先级
CPUQuota=25%
CPUWeight=50

# 内存: 最多 256MB（演示用）
MemoryMax=256M
MemoryHigh=200M
MemorySwapMax=0

# 进程: 最多 50 个任务
TasksMax=50

# ===== 日志 =====
StandardOutput=journal
StandardError=journal

# ===== 超时 =====
TimeoutStartSec=300
EOF

sudo systemctl daemon-reload
```

### 6.3 测试资源限制

```bash
# 启动批处理（在后台监控）
sudo systemctl start monthly-batch &

# 在另一个终端监控资源使用
sudo systemd-cgtop -d 1 | grep monthly-batch

# 或者查看实时日志
sudo journalctl -u monthly-batch -f
```

### 6.4 验证限制生效

```bash
# 查看资源配置
systemctl show monthly-batch -p CPUQuota,MemoryMax,MemoryHigh,TasksMax

# 查看 cgroup 文件
cat /sys/fs/cgroup/system.slice/monthly-batch.service/memory.max
cat /sys/fs/cgroup/system.slice/monthly-batch.service/cpu.max
```

### 6.5 查看执行结果

```bash
# 查看服务状态
systemctl status monthly-batch

# 查看完整日志
sudo journalctl -u monthly-batch --no-pager

# 如果因为内存限制被 OOM kill，会看到：
# "monthly-batch.service: Main process exited, code=killed, status=9/KILL"
```

### 6.6 清理测试环境

```bash
# 删除服务和脚本
sudo rm /etc/systemd/system/monthly-batch.service
sudo rm /opt/scripts/monthly-batch.sh
sudo systemctl daemon-reload
```

---

## 反模式：常见错误

### 错误 1：只设置 MemoryMax 不设置 MemoryHigh

```ini
# 错误：没有预警，直接 OOM
[Service]
MemoryMax=1G

# 正确：设置软限制作为预警
[Service]
MemoryHigh=750M    # 软限制，施加压力
MemoryMax=1G       # 硬限制，绝对上限
```

**后果**：服务突然被 OOM Killer 终止，没有任何预警。

### 错误 2：CPUQuota 设置过低导致服务无响应

```ini
# 错误：Web 服务 CPU 限制太低
[Service]
CPUQuota=5%

# 正确：根据实际需求设置
[Service]
CPUQuota=50%       # 或更高
CPUWeight=50       # 使用权重而非硬限制
```

**后果**：用户请求超时，服务看起来像是挂了。

### 错误 3：忘记 MemorySwapMax 导致服务使用 swap

```ini
# 错误：限制了内存但没限制 swap
[Service]
MemoryMax=1G
# 服务可以使用无限 swap，性能急剧下降

# 正确：同时限制 swap
[Service]
MemoryMax=1G
MemorySwapMax=0    # 或设置一个合理的值
```

**后果**：服务疯狂使用 swap，整个系统变慢。

### 错误 4：TasksMax 设置太低导致服务启动失败

```ini
# 错误：Web 服务器需要更多线程
[Service]
TasksMax=10

# 正确：根据服务特性设置
[Service]
TasksMax=100       # 或 infinity 如果信任该服务
```

**后果**：服务启动时 fork 子进程失败。

---

## 资源监控命令速查

```bash
# === systemd-cgtop（推荐）===
sudo systemd-cgtop                    # 实时监控所有 cgroup
sudo systemd-cgtop -d 1               # 每秒刷新
sudo systemd-cgtop -p                 # 按路径排序
sudo systemd-cgtop -c                 # 按 CPU 排序
sudo systemd-cgtop -m                 # 按内存排序

# === systemctl show ===
systemctl show nginx -p MemoryMax     # 查看单个属性
systemctl show nginx -p Memory*       # 查看所有内存属性
systemctl show nginx --property=CPU*,Memory*,IO*,Tasks*

# === systemctl set-property ===
sudo systemctl set-property nginx MemoryMax=2G    # 持久化修改
sudo systemctl set-property --runtime nginx MemoryMax=2G  # 临时修改

# === cgroup 文件系统 ===
cat /sys/fs/cgroup/system.slice/nginx.service/memory.max
cat /sys/fs/cgroup/system.slice/nginx.service/memory.current
cat /sys/fs/cgroup/system.slice/nginx.service/cpu.max

# === 其他工具 ===
systemctl status nginx               # 包含资源使用信息
journalctl -u nginx | grep -i oom    # 检查 OOM 事件
dmesg | grep -i oom                  # 内核 OOM 日志
```

---

## 职场小贴士（Japan IT Context）

### 月次バッチ（Monthly Batch）事故案例

这是一个真实的日本 IT 运维场景：

> **事故报告**：月次バッチ処理が 32GB RAM を使用し、OOM Killer が SSH を停止。  
> リモートアクセス不能となり、データセンター出動が必要となった。  

**问题分析**：
1. 月度批处理任务没有内存限制
2. 数据量增长导致内存使用超出预期
3. OOM Killer 选择了 sshd 进程（因为它很久没活动）
4. 无法远程登录排查问题

**解决方案**：

```ini
[Service]
# 批处理任务资源限制
MemoryMax=8G          # 根据服务器内存设置（如 32GB 服务器设 25%）
MemoryHigh=6G         # 软限制预警
CPUQuota=50%          # 限制 CPU 使用
TasksMax=100          # 防止 fork 炸弹

# 启用 systemd-oomd 保护
ManagedOOMMemoryPressure=auto
```

### リソース制限（Resource Limits）相关术语

| 日语术语 | 含义 | systemd 对应 |
|----------|------|--------------|
| リソース制限 | 资源限制 | MemoryMax, CPUQuota |
| メモリ制限 | 内存限制 | MemoryMax, MemoryHigh |
| CPU 制限 | CPU 限制 | CPUQuota, CPUWeight |
| プロセス制限 | 进程限制 | TasksMax |
| OOM Killer | 内存不足杀手 | systemd-oomd |

### 品質保証（Quality Assurance）

日本企业对服务质量有严格要求：

```markdown
# リソース管理チェックリスト

## 必須設定
- [ ] MemoryMax が設定されている
- [ ] MemoryHigh が MemoryMax の 75% に設定されている
- [ ] CPUQuota または CPUWeight が設定されている
- [ ] TasksMax が適切に設定されている

## 監視項目
- [ ] systemd-cgtop で定期的にリソース使用を確認
- [ ] MemoryHigh 超過時のアラートが設定されている
- [ ] OOM Killer 発動時の通知が設定されている

## 障害対応
- [ ] リソース不足時の手動調整手順が文書化されている
- [ ] systemctl set-property の使用方法を理解している
```

---

## 检查清单

完成本课后，你应该能够：

- [ ] 解释 cgroup v2 与 v1 的区别
- [ ] 区分 CPUWeight（相对权重）和 CPUQuota（硬限制）
- [ ] 区分 MemoryMax（硬限制）和 MemoryHigh（软限制）
- [ ] 配置 TasksMax 防止 fork 炸弹
- [ ] 使用 `systemd-cgtop` 监控服务资源使用
- [ ] 使用 `systemctl show -p` 查看资源配置
- [ ] 使用 `systemctl set-property` 动态调整限制
- [ ] 理解 systemd-oomd 的作用
- [ ] 为批处理任务创建资源限制配置
- [ ] 解释为什么需要同时设置 MemoryMax 和 MemoryHigh

---

## 本课小结

| 概念 | 要点 | 记忆点 |
|------|------|--------|
| cgroup v2 | 统一层次结构 | 2025 年起是默认 |
| CPUQuota | 硬限制，绝对上限 | 50% = 0.5 核心 |
| CPUWeight | 相对权重，竞争时生效 | 默认 100 |
| MemoryMax | 硬限制，超过触发 OOM | 必须设置 |
| MemoryHigh | 软限制，超过施加压力 | MemoryMax 的 75% |
| TasksMax | 最大任务数 | 防 fork 炸弹 |
| systemd-cgtop | 资源监控 | 类似 top |
| systemd-oomd | 智能 OOM 处理 | 保护关键服务 |

---

## 面试准备

### Q: MemoryMax と MemoryHigh の違いは？

**A**:

- **MemoryMax** はハードリミット：超過すると OOM Killer がプロセスを終了します。絶対に超えられない制限です。

- **MemoryHigh** はソフトリミット：超過するとメモリ回収の圧力がかかりますが、即座に終了されません。systemd-oomd がこの値を監視して、システムが困窮する前に対処します。

**ベストプラクティス**：両方を設定し、MemoryHigh を MemoryMax の 75% 程度に設定します。

```ini
[Service]
MemoryHigh=750M    # 早期警告
MemoryMax=1G       # 絶対上限
```

### Q: fork 爆弾を防ぐ systemd の設定は？

**A**: `TasksMax=` でプロセス数（タスク数）を制限します。

```ini
[Service]
TasksMax=100    # 最大 100 タスク（プロセス + スレッド）
```

デフォルトでは、systemd は各サービスに対してシステム全体のスレッド制限の 15% を設定しています。

fork 爆弾とは、無限にプロセスを生成してシステムリソースを枯渇させる攻撃です。TasksMax を設定することで、特定のサービスが暴走してもシステム全体に影響を与えません。

### Q: cgroup v2 の確認方法は？

**A**: 以下のコマンドで確認できます：

```bash
# cgroup v2 の場合、コントローラが表示される
cat /sys/fs/cgroup/cgroup.controllers
# 出力: cpu memory io pids など

# または mount で確認
mount | grep cgroup
# v2: "cgroup2 on /sys/fs/cgroup type cgroup2"
# v1: 複数の "cgroup on /sys/fs/cgroup/xxx type cgroup"
```

2025 年以降、主要なディストリビューション（RHEL 9, Ubuntu 22.04+, Fedora 40+）はすべて cgroup v2 がデフォルトです。

---

## 延伸阅读

- [systemd.resource-control(5) man page](https://www.freedesktop.org/software/systemd/man/systemd.resource-control.html)
- [cgroup v2 Documentation](https://docs.kernel.org/admin-guide/cgroup-v2.html)
- 下一课：[09 - Drop-in 与安全加固](../09-customization-security/) -- 学习如何安全地定制和加固服务
- 相关课程：[06 - Timer](../06-timers/) -- 为定时任务设置资源限制

---

## 系列导航

[07 - journalctl 日志掌控 <--](../07-journalctl/) | [系列首页](../) | [--> 09 - Drop-in 与安全加固](../09-customization-security/)
