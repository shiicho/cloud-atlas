# 06 - cgroups v2：资源限制实战

> **目标**：掌握 cgroups v2 资源控制实战 —— 配置 CPU/内存/IO 限制，理解 OOM Kill 调查  
> **前置**：[Lesson 05 - cgroups v2 架构](../05-cgroups-v2-architecture/)  
> **时间**：2.5 小时  
> **环境**：Linux 系统（cgroup v2 enabled，建议 Ubuntu 22.04+ / RHEL 9+)  

---

## 将学到的内容

1. 手动创建 cgroup 并配置资源限制
2. 理解 `memory.high` vs `memory.max` 的关键区别
3. 观察 CPU 限制和内存 OOM Kill 效果
4. 调查「静默 OOM Kill」—— 日本 IT 运维现场常见的夜间批处理问题

---

## 先跑起来：5 分钟触发 OOM Kill

> **不讲原理，先动手！** 你马上就会看到 Linux 内核杀死进程的「证据」。  

### 准备工作

安装 stress 工具（如果没有）：

```bash
# Ubuntu/Debian
sudo apt-get install -y stress

# RHEL/CentOS
sudo dnf install -y stress
```

### 创建一个内存受限的 cgroup

```bash
# 创建 cgroup（需要 root 权限）
sudo mkdir /sys/fs/cgroup/demo-oom

# 设置内存硬限制为 50MB
echo "50M" | sudo tee /sys/fs/cgroup/demo-oom/memory.max

# 把当前 shell 加入这个 cgroup
echo $$ | sudo tee /sys/fs/cgroup/demo-oom/cgroup.procs
```

### 触发 OOM Kill

```bash
# 尝试分配 100MB 内存（超过 50MB 限制）
stress --vm 1 --vm-bytes 100M --timeout 10s
```

输出：

```
stress: info: [12345] dispatching hogs: 0 cpu, 0 io, 1 vm, 0 hdd
stress: FAIL: [12345] (415) <-- worker 12346 got signal 9
stress: WARN: [12345] (417) now reaping child worker processes
stress: FAIL: [12345] (451) failed run completed in 0s
```

**Signal 9 就是 SIGKILL！** 内核杀死了 stress 进程。

### 查看 OOM 证据

```bash
# 查看内核日志
dmesg | tail -20 | grep -i oom
```

输出类似：

```
[12345.678901] oom-kill:constraint=CONSTRAINT_MEMCG,nodemask=...
[12345.678902] Memory cgroup out of memory: Killed process 12346 (stress)
```

```bash
# 查看 cgroup 的 OOM 事件统计
cat /sys/fs/cgroup/demo-oom/memory.events
```

输出：

```
low 0
high 0
max 1
oom 1
oom_kill 1
oom_group_kill 0
```

**oom_kill 1** —— 记录了一次 OOM Kill 事件！

### 清理

```bash
# 退出 cgroup（新开一个 shell）
# 或者删除 cgroup
sudo rmdir /sys/fs/cgroup/demo-oom
```

---

**你刚刚做了什么？**

```
┌─────────────────────────────────────────────────────────────────┐
│                      cgroup: demo-oom                           │
│                      memory.max = 50MB                          │
│                                                                 │
│   ┌─────────────────────────────────────────────────────────┐   │
│   │  stress --vm-bytes 100M                                 │   │
│   │                                                         │   │
│   │  尝试分配 100MB                                         │   │
│   │       │                                                 │   │
│   │       ▼                                                 │   │
│   │  超过 memory.max 限制                                   │   │
│   │       │                                                 │   │
│   │       ▼                                                 │   │
│   │  内核触发 OOM Kill                                      │   │
│   │       │                                                 │   │
│   │       ▼                                                 │   │
│   │  进程收到 SIGKILL (Signal 9)                            │   │
│   └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│   证据记录：                                                    │
│   - dmesg: "Memory cgroup out of memory"                       │
│   - memory.events: oom_kill 1                                  │
└─────────────────────────────────────────────────────────────────┘
```

这就是容器资源限制的核心机制。Docker/Kubernetes 的 `--memory` 参数背后就是这个 cgroup 配置。

---

## 发生了什么？

### cgroup 资源控制文件

当你创建 `/sys/fs/cgroup/demo-oom` 目录时，内核自动生成了一系列控制文件：

```bash
ls /sys/fs/cgroup/demo-oom/
```

```
cgroup.controllers  cpu.max      memory.current  memory.max   pids.max
cgroup.procs        cpu.stat     memory.events   memory.stat  ...
```

关键文件：

| 文件 | 作用 | 示例值 |
|------|------|--------|
| `memory.max` | 内存硬限制 | `50M`, `1G`, `max`(无限制) |
| `memory.high` | 内存软限制 | `40M` |
| `memory.current` | 当前内存使用 | `12345678`(字节) |
| `memory.events` | OOM 事件统计 | `oom_kill 1` |
| `cpu.max` | CPU 时间限制 | `50000 100000`(50%) |
| `pids.max` | 最大进程数 | `100` |

### 进程如何被限制

```bash
echo $$ | sudo tee /sys/fs/cgroup/demo-oom/cgroup.procs
```

这一行做了什么？

1. `$$` 是当前 shell 的 PID
2. 写入 `cgroup.procs` 将进程移入该 cgroup
3. 该进程及其**所有子进程**都受该 cgroup 限制

---

## 核心概念：memory.high vs memory.max

**这是 cgroups v2 最重要的概念之一，也是运维面试常考题。**

### 两种内存限制

```
                    内存使用量
                        │
    0 ─────────────────┴─────────────────────────────────▶
                        │
                        │  正常运行
                        │
    ────────────────────┼──────── memory.high (软限制)
                        │
                        │  系统积极回收内存
                        │  进程变慢但继续运行
                        │
    ────────────────────┼──────── memory.max (硬限制)
                        │
                        │  触发 OOM Kill
                        │  进程被杀死
                        │
```

### 详细对比

| 特性 | memory.high (软限制) | memory.max (硬限制) |
|------|----------------------|---------------------|
| **触发条件** | 使用量超过 high | 使用量达到 max |
| **系统行为** | 积极回收内存（memory reclaim） | 触发 OOM Kill |
| **进程状态** | 变慢但继续运行 | 被杀死 |
| **用途** | 避免突然 OOM | 绝对上限 |
| **推荐值** | 目标的 80% | 目标值 |

### 推荐配置模式

```bash
# 目标：限制进程最多使用 1GB 内存
# 配置 high 为 800M，max 为 1G

echo "800M" | sudo tee /sys/fs/cgroup/myapp/memory.high   # 软限制
echo "1G"   | sudo tee /sys/fs/cgroup/myapp/memory.max    # 硬限制
```

这样配置的效果：

- 使用量 < 800M：正常运行
- 800M < 使用量 < 1G：系统积极回收内存，进程变慢但不会死
- 使用量 = 1G：OOM Kill

**为什么需要 memory.high？**

如果只设置 memory.max，进程会「突然死亡」，没有预警。设置 memory.high 给系统一个「缓冲区」，让进程有机会释放内存或被监控发现。

---

## 动手练习

### Lab 1：手动创建 cgroup 并配置资源限制

**目标**：理解 cgroup 创建和资源限制配置

**步骤 1**：创建 cgroup

```bash
# 创建 cgroup 目录
sudo mkdir /sys/fs/cgroup/lab-resource

# 查看可用控制器
cat /sys/fs/cgroup/cgroup.controllers

# 查看当前 cgroup 已启用的控制器
cat /sys/fs/cgroup/cgroup.subtree_control
```

**步骤 2**：配置内存限制

```bash
# 设置软限制和硬限制
echo "80M" | sudo tee /sys/fs/cgroup/lab-resource/memory.high
echo "100M" | sudo tee /sys/fs/cgroup/lab-resource/memory.max

# 验证配置
cat /sys/fs/cgroup/lab-resource/memory.high
cat /sys/fs/cgroup/lab-resource/memory.max
```

**步骤 3**：配置 CPU 限制（50%）

```bash
# cpu.max 格式：'quota period'
# '50000 100000' 表示每 100ms 只能使用 50ms CPU
echo "50000 100000" | sudo tee /sys/fs/cgroup/lab-resource/cpu.max

# 验证
cat /sys/fs/cgroup/lab-resource/cpu.max
```

**步骤 4**：配置 PID 限制

```bash
# 限制最多 10 个进程
echo "10" | sudo tee /sys/fs/cgroup/lab-resource/pids.max

# 验证
cat /sys/fs/cgroup/lab-resource/pids.max
```

**清理**：

```bash
sudo rmdir /sys/fs/cgroup/lab-resource
```

---

### Lab 2：内存限制 + OOM 演示

**目标**：观察 memory.high 和 memory.max 的不同行为

运行演示脚本：

```bash
cd ~/cloud-atlas/foundations/linux/containers/06-cgroups-v2-resource-control/code
sudo ./memory-limit-demo.sh
```

或手动执行：

**演示 memory.high（软限制）**：

```bash
# 创建 cgroup
sudo mkdir /sys/fs/cgroup/demo-high

# 只设置 memory.high（软限制），不设置 memory.max
echo "50M" | sudo tee /sys/fs/cgroup/demo-high/memory.high

# 启动新 shell 在这个 cgroup 中
sudo bash -c 'echo $$ > /sys/fs/cgroup/demo-high/cgroup.procs && exec bash'

# 在新 shell 中，尝试分配 80M 内存
stress --vm 1 --vm-bytes 80M --timeout 5s

# 观察进程变慢但没有被杀死
# 查看事件
cat /sys/fs/cgroup/demo-high/memory.events
```

**演示 memory.max（硬限制）**：

```bash
# 创建 cgroup
sudo mkdir /sys/fs/cgroup/demo-max

# 设置 memory.max（硬限制）
echo "50M" | sudo tee /sys/fs/cgroup/demo-max/memory.max

# 启动新 shell
sudo bash -c 'echo $$ > /sys/fs/cgroup/demo-max/cgroup.procs && exec bash'

# 尝试分配 80M 内存
stress --vm 1 --vm-bytes 80M --timeout 5s

# 观察进程被杀死
cat /sys/fs/cgroup/demo-max/memory.events
```

**清理**：

```bash
sudo rmdir /sys/fs/cgroup/demo-high 2>/dev/null
sudo rmdir /sys/fs/cgroup/demo-max 2>/dev/null
```

---

### Lab 3：CPU 限制演示

**目标**：观察 CPU 时间被限制在 50%

运行演示脚本：

```bash
cd ~/cloud-atlas/foundations/linux/containers/06-cgroups-v2-resource-control/code
sudo ./cpu-throttle-demo.sh
```

或手动执行：

**步骤 1**：创建 CPU 限制 cgroup

```bash
sudo mkdir /sys/fs/cgroup/demo-cpu

# 限制为 50% CPU
# '50000 100000' = 每 100000 微秒只能用 50000 微秒
echo "50000 100000" | sudo tee /sys/fs/cgroup/demo-cpu/cpu.max
```

**步骤 2**：运行 CPU 密集任务

```bash
# 在一个终端启动 stress（不在 cgroup 中）
stress --cpu 1 --timeout 30s &
STRESS_PID=$!

# 查看 CPU 使用率（应该接近 100%）
top -p $STRESS_PID -b -n 1 | tail -2

# 杀掉
kill $STRESS_PID
```

**步骤 3**：在 cgroup 中运行同样任务

```bash
# 将进程加入 cgroup 运行
sudo bash -c "echo \$\$ > /sys/fs/cgroup/demo-cpu/cgroup.procs && stress --cpu 1 --timeout 30s" &
STRESS_PID=$!

# 查看 CPU 使用率（应该限制在 50% 左右）
sleep 2
top -p $STRESS_PID -b -n 1 | tail -2

# 等待完成或杀掉
kill $STRESS_PID 2>/dev/null
```

**步骤 4**：查看 CPU 统计

```bash
cat /sys/fs/cgroup/demo-cpu/cpu.stat
```

输出：

```
usage_usec 12345678       # 总 CPU 使用时间
user_usec 12000000        # 用户态时间
system_usec 345678        # 内核态时间
nr_periods 1234           # 调度周期数
nr_throttled 567          # 被限制的周期数
throttled_usec 8901234    # 被限制的总时间
```

**nr_throttled** > 0 表示 CPU 限制生效了！

**清理**：

```bash
sudo rmdir /sys/fs/cgroup/demo-cpu
```

---

### Lab 4：Silent OOM 场景调查

**场景**：夜间批处理凌晨 3 点突然消失，没有任何应用日志

这是日本 IT 运维现场的经典问题。批处理程序（バッチ処理）在凌晨运行，早上发现它「消失」了，但没有错误日志。

**目标**：学会从宿主机视角调查容器/进程问题

**模拟场景**：

```bash
# 步骤 1：创建受限 cgroup 模拟容器
sudo mkdir /sys/fs/cgroup/batch-job

# 步骤 2：设置内存限制（模拟 Kubernetes pod 限制）
echo "100M" | sudo tee /sys/fs/cgroup/batch-job/memory.max

# 步骤 3：运行「批处理」任务（会被 OOM Kill）
sudo bash -c 'echo $$ > /sys/fs/cgroup/batch-job/cgroup.procs && stress --vm 1 --vm-bytes 200M --timeout 60s'
```

进程会立即被杀死。

**调查步骤**：

```bash
# 证据 1：检查 dmesg（内核日志）
dmesg | grep -i oom | tail -10
```

输出：

```
[xxxxx.xxxxxx] oom-kill:constraint=CONSTRAINT_MEMCG...
[xxxxx.xxxxxx] Memory cgroup out of memory: Killed process XXXX (stress)
[xxxxx.xxxxxx] oom_reaper: reaped process XXXX (stress)
```

```bash
# 证据 2：检查 memory.events
cat /sys/fs/cgroup/batch-job/memory.events
```

输出：

```
low 0
high 0
max 1
oom 1
oom_kill 1
```

```bash
# 证据 3：使用 journalctl 查看内核消息
journalctl -k | grep -i oom | tail -10
```

**生成障害報告書（事故报告）**：

```markdown
## 障害報告書

### 事象
夜間バッチ処理が 03:00 に異常終了。アプリケーションログに記録なし。

### 原因
cgroup メモリ制限による OOM Kill

### 証拠
1. dmesg 出力：
   `Memory cgroup out of memory: Killed process XXXX (stress)`

2. memory.events：
   `oom_kill 1`

### 対策
- メモリ制限を 200M に引き上げ
- または memory.high を設定して事前警告を有効化
```

**清理**：

```bash
sudo rmdir /sys/fs/cgroup/batch-job
```

---

## IO 控制（简介）

cgroups v2 也支持 IO 限制，但配置稍复杂。

### 查看设备号

```bash
# 查看磁盘设备的 major:minor 号
lsblk -d -o NAME,MAJ:MIN
```

输出：

```
NAME MAJ:MIN
sda    8:0
nvme0n1 259:0
```

### 配置 IO 限制

```bash
# 创建 cgroup
sudo mkdir /sys/fs/cgroup/demo-io

# 限制对 sda (8:0) 的读写带宽为 10MB/s
echo "8:0 rbps=10485760 wbps=10485760" | sudo tee /sys/fs/cgroup/demo-io/io.max

# 验证
cat /sys/fs/cgroup/demo-io/io.max
```

格式说明：

```
MAJ:MIN rbps=读带宽(bytes/s) wbps=写带宽(bytes/s) riops=读IOPS wiops=写IOPS
```

**注意**：IO 控制效果取决于底层存储类型，SSD/NVMe 的效果可能不如 HDD 明显。

---

## PID 控制（防止 Fork 炸弹）

### 问题场景

```bash
# 不要运行这个！这是 fork bomb
# :(){ :|:& };:
```

Fork 炸弹会无限创建进程，耗尽系统资源。

### 解决方案：pids.max

```bash
# 创建 cgroup
sudo mkdir /sys/fs/cgroup/demo-pids

# 限制最多 5 个进程
echo "5" | sudo tee /sys/fs/cgroup/demo-pids/pids.max

# 测试
sudo bash -c 'echo $$ > /sys/fs/cgroup/demo-pids/cgroup.procs && for i in {1..10}; do sleep 100 & done'
```

输出：

```
-bash: fork: retry: Resource temporarily unavailable
-bash: fork: retry: Resource temporarily unavailable
```

只有前 5 个进程能创建成功！

**清理**：

```bash
# 先杀死 sleep 进程
sudo pkill -9 -f "sleep 100"
sudo rmdir /sys/fs/cgroup/demo-pids
```

---

## 职场小贴士

### 日本 IT 现场常见场景

**场景 1：OOM Kill は夜間バッチ問題の主原因**

```
状況：
朝出社すると、夜間バッチが失敗していた。
アプリログには何も記録されていない。

確認手順：
1. dmesg | grep -i oom
2. cat /sys/fs/cgroup/<container>/memory.events
3. journalctl -k | grep -i oom

報告書に添付：
- dmesg の出力
- memory.events の内容
- 推奨対策（メモリ増加 or memory.high 設定）
```

**场景 2：Kubernetes Pod OOM 調査**

```bash
# Pod が CrashLoopBackOff になっている
kubectl describe pod <pod-name>

# Events に OOMKilled が表示されている場合
# ノードで確認：
ssh <node>
dmesg | grep -i oom | grep <container-id>
```

**场景 3：リソース制限の設定確認**

```bash
# Docker コンテナのリソース制限を確認
docker inspect <container> | jq '.[0].HostConfig.Memory'
docker inspect <container> | jq '.[0].HostConfig.CpuQuota'

# cgroup で直接確認
cat /sys/fs/cgroup/system.slice/docker-<id>.scope/memory.max
cat /sys/fs/cgroup/system.slice/docker-<id>.scope/cpu.max
```

### 運用監視のポイント

1. **memory.events を定期監視**
   - oom_kill > 0 の場合はアラート
   - high イベントが多い場合は memory.high に近づいている

2. **cpu.stat の nr_throttled を監視**
   - 値が増え続ける場合は CPU 制限に引っかかっている

3. **pids.current を監視**
   - pids.max に近づいている場合は fork 制限に注意

---

## 检查清单

完成本课后，你应该能够：

- [ ] 手动创建 cgroup 目录 (`mkdir /sys/fs/cgroup/xxx`)
- [ ] 配置内存限制 (`memory.high`, `memory.max`)
- [ ] 配置 CPU 限制 (`cpu.max = 'quota period'`)
- [ ] 配置 PID 限制 (`pids.max`)
- [ ] 解释 `memory.high` 和 `memory.max` 的区别
- [ ] 使用 `stress` 触发 OOM Kill 并观察现象
- [ ] 从 `dmesg` 和 `memory.events` 找到 OOM Kill 证据
- [ ] 理解日本 IT 现场的夜间批处理 OOM 问题

---

## 延伸阅读

### 官方文档

- [cgroups v2 - Kernel Documentation](https://www.kernel.org/doc/Documentation/cgroup-v2.txt)
- [Memory Controller - cgroups v2](https://docs.kernel.org/admin-guide/cgroup-v2.html#memory)
- [CPU Controller - cgroups v2](https://docs.kernel.org/admin-guide/cgroup-v2.html#cpu)

### 相关课程

- [Lesson 05 - cgroups v2 架构](../05-cgroups-v2-architecture/) - cgroups v2 统一层级原理
- [Lesson 11 - 容器故障排查](../11-debugging-troubleshooting/) - 完整排查方法论
- [LX05 - systemd 资源控制](../../systemd/) - systemd 与 cgroups 集成

### 推荐阅读

- *Container Security* by Liz Rice - Chapter on cgroups
- Red Hat Documentation: Resource Management Guide

---

## 系列导航

[<-- 05 - cgroups v2 架构](../05-cgroups-v2-architecture/) | [Home](../) | [07 - OverlayFS -->](../07-overlay-filesystems/)
