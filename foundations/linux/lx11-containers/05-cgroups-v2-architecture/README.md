# 05 - cgroups v2：统一资源控制架构

> **目标**：理解 cgroups v2 的统一层级架构，掌握版本检测和层级探索  
> **前置**：完成 [01 - 容器 vs 虚拟机](../01-containers-vs-vms/)；了解 [LX05-SYSTEMD](../../lx05-systemd/) 中的 cgroups 基础  
> **时间**：⚡ 30 分钟（速读）/ 🔬 120 分钟（完整实操）  
> **场景**：本番環境でのリソース制御確認（生产环境资源控制确认）  

---

## 将学到的内容

1. 回顾 cgroups 核心概念：「能用多少」的资源约束
2. 区分 cgroups v1 和 v2 的关键差异
3. 理解 v2 统一层级（Unified Hierarchy）架构
4. 掌握 systemd 与 cgroups v2 的深度集成
5. 学会检测系统 cgroups 版本并探索层级结构

---

## 先跑起来：检测你的 cgroups 版本（5 分钟）

> **不讲原理，先动手！** 一条命令判断你的系统用的是 v1 还是 v2。  

```bash
# 检测 cgroups 版本
mount | grep cgroup
```

**如果你看到这样的输出（v2）：**

```
cgroup2 on /sys/fs/cgroup type cgroup2 (rw,nosuid,nodev,noexec,relatime,nsdelegate,memory_recursiveprot)
```

**恭喜！** 你的系统使用 cgroups v2（统一层级）。这是 2025 年的主流配置。

**如果你看到这样的输出（v1）：**

```
cgroup on /sys/fs/cgroup/cpu type cgroup (rw,nosuid,nodev,noexec,relatime,cpu)
cgroup on /sys/fs/cgroup/memory type cgroup (rw,nosuid,nodev,noexec,relatime,memory)
cgroup on /sys/fs/cgroup/blkio type cgroup (rw,nosuid,nodev,noexec,relatime,blkio)
...
```

你的系统使用 cgroups v1（分离层级）。每个控制器有独立的挂载点。

**再看一条命令：**

```bash
# 探索 cgroup 层级
ls /sys/fs/cgroup/
```

v2 的输出（简洁）：

```
cgroup.controllers  cgroup.procs  cpu.stat  memory.current  ...
system.slice/  user.slice/  init.scope/
```

v1 的输出（复杂）：

```
cpu/  memory/  blkio/  devices/  freezer/  ...
```

---

**你刚刚做了什么？**

你判断了系统的 cgroups 版本。这是容器故障排查的第一步 —— 知道你在哪个架构下工作。

---

## 发生了什么？

### cgroups 的作用回顾

在 [01 - 容器 vs 虚拟机](../01-containers-vs-vms/) 中，我们学到：

```
Container = Process + Constraints（约束）
```

| 约束类型 | 作用 | 对应技术 |
|----------|------|----------|
| **可见性约束** | 进程能「看到」什么 | Namespace |
| **资源约束** | 进程能「用」多少 | **cgroups** |

**Namespace 控制「看到什么」，cgroups 控制「用多少」。**

在 LX05-SYSTEMD 中，你已经接触过 cgroups：

```bash
# 查看服务的 cgroup
systemctl status sshd | grep -i cgroup

# 查看 cgroup 层级
systemd-cgls
```

本课深入 cgroups v2 的架构原理，为下一课的资源限制实战打基础。

---

## 核心概念：cgroups v1 vs v2

### v1：分离层级（Legacy）

cgroups v1（2008 年引入）使用**分离层级**：每个控制器（cpu, memory, blkio 等）有独立的层级结构。

<!-- DIAGRAM: cgroups-v1-architecture -->
```
cgroups v1 架构（分离层级）：

┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐
│ /sys/fs/cgroup/ │  │ /sys/fs/cgroup/ │  │ /sys/fs/cgroup/ │
│ cpu/            │  │ memory/         │  │ blkio/          │
│                 │  │                 │  │                 │
│ ├── group-a/    │  │ ├── group-a/    │  │ ├── group-a/    │
│ │   └── tasks   │  │ │   └── tasks   │  │ │   └── tasks   │
│ │               │  │ │               │  │ │               │
│ └── group-b/    │  │ └── group-b/    │  │ └── group-x/    │
│     └── tasks   │  │     └── tasks   │  │     └── tasks   │
└─────────────────┘  └─────────────────┘  └─────────────────┘
     独立管理             独立管理             独立管理

问题 1：同一个进程可以在不同控制器中属于不同组！
        cpu/group-a + memory/group-b = 管理混乱

问题 2：每个控制器独立挂载，配置复杂
问题 3：无法原子性地移动进程到多个控制器
```
<!-- /DIAGRAM -->

**v1 的痛点：**

1. **层级不一致**：进程 A 可以在 cpu/group-a 但在 memory/group-b
2. **管理复杂**：需要分别配置每个控制器
3. **委托困难**：无法将一组资源整体委托给非 root 用户

### v2：统一层级（Modern）

cgroups v2（2016 年稳定，2025 年成为默认）使用**统一层级**：所有控制器在同一层级结构中。

<!-- DIAGRAM: cgroups-v2-architecture -->
```
cgroups v2 架构（统一层级）：

┌───────────────────────────────────────────────────────────┐
│ /sys/fs/cgroup/                                           │
│                                                           │
│   cgroup.controllers: cpu memory io pids                  │
│   cgroup.subtree_control: cpu memory io pids              │
│                                                           │
│   ├── system.slice/                    ← systemd 系统服务 │
│   │   ├── docker.service/                                 │
│   │   │   ├── cgroup.procs             ← 进程列表        │
│   │   │   ├── cpu.max                  ← CPU 限制        │
│   │   │   ├── memory.max               ← 内存限制        │
│   │   │   └── io.max                   ← IO 限制         │
│   │   │                                                   │
│   │   └── sshd.service/                                   │
│   │       ├── cgroup.procs                                │
│   │       ├── cpu.max                                     │
│   │       └── memory.max                                  │
│   │                                                       │
│   ├── user.slice/                      ← 用户会话        │
│   │   └── user-1000.slice/                                │
│   │       └── session-1.scope/                            │
│   │                                                       │
│   └── init.scope/                      ← PID 1 (systemd) │
│                                                           │
└───────────────────────────────────────────────────────────┘
                     统一管理

优势 1：所有控制器在同一层级，进程位置唯一确定
优势 2：配置集中，一个目录管理所有资源
优势 3：支持子树委托（subtree delegation）
```
<!-- /DIAGRAM -->

### 关键差异对比

| 特性 | cgroups v1 | cgroups v2 |
|------|------------|------------|
| **层级结构** | 每个控制器独立层级 | 统一单一层级 |
| **挂载点** | 多个（/sys/fs/cgroup/{cpu,memory,...}） | 一个（/sys/fs/cgroup） |
| **进程归属** | 可以在不同控制器中属于不同组 | 位置唯一，所有控制器统一 |
| **配置文件** | 控制器特定（cpu.shares, memory.limit_in_bytes） | 统一命名（cpu.max, memory.max） |
| **委托** | 复杂，需要分别委托 | 简单，子树整体委托 |
| **systemd 集成** | 部分 | 完全 |
| **2025 状态** | Legacy | **默认** |

### 2025 年发行版状态

| 发行版 | 默认版本 | 说明 |
|--------|----------|------|
| **RHEL 9 / Rocky 9 / AlmaLinux 9** | v2 | 2022 年起默认 |
| **Ubuntu 22.04+** | v2 | 2022 年起默认 |
| **Debian 12+** | v2 | 2023 年起默认 |
| **Fedora 31+** | v2 | 2019 年起默认（先驱） |
| **RHEL 8** | v1 | 可切换到 v2 |
| **Ubuntu 20.04** | v1 | 可切换到 v2 |

**日本企业现状**：多くの企業システムはまだ v1 の可能性がある（RHEL 8 / CentOS 7 系統）。了解两个版本对于故障排查至关重要。

---

## 动手练习

### Lab 1：版本检测完整流程

**目标**：准确判断系统的 cgroups 版本。

**方法 1：检查挂载类型**

```bash
# 最可靠的方法
mount | grep cgroup

# v2 特征：只有一行，类型是 cgroup2
# cgroup2 on /sys/fs/cgroup type cgroup2 ...

# v1 特征：多行，类型是 cgroup，按控制器分
# cgroup on /sys/fs/cgroup/cpu type cgroup ...
# cgroup on /sys/fs/cgroup/memory type cgroup ...
```

**方法 2：检查文件系统结构**

```bash
# v2 检测：cgroup.controllers 文件存在
ls /sys/fs/cgroup/cgroup.controllers 2>/dev/null && echo "cgroups v2" || echo "NOT v2"

# v1 检测：存在控制器子目录
ls -d /sys/fs/cgroup/cpu 2>/dev/null && echo "cgroups v1 present" || echo "NO v1 cpu controller"
```

**方法 3：使用 stat 命令**

```bash
stat -fc %T /sys/fs/cgroup
# v2: cgroup2fs
# v1: tmpfs（因为 v1 下 /sys/fs/cgroup 是 tmpfs，控制器各自挂载）
```

**创建检测脚本**：

```bash
#!/bin/bash
# cgroup-version-detect.sh

echo "=== cgroups 版本检测 ==="

# 方法 1
if mount | grep -q "cgroup2 on /sys/fs/cgroup"; then
    VERSION="v2"
elif mount | grep -q "cgroup on /sys/fs/cgroup/"; then
    VERSION="v1"
else
    VERSION="unknown"
fi

echo "检测结果: cgroups $VERSION"
echo ""

# 详细信息
echo "=== 挂载信息 ==="
mount | grep cgroup
echo ""

# 可用控制器
if [ "$VERSION" = "v2" ]; then
    echo "=== 可用控制器 (v2) ==="
    cat /sys/fs/cgroup/cgroup.controllers
else
    echo "=== 可用控制器 (v1) ==="
    ls /sys/fs/cgroup/
fi
```

运行脚本：

```bash
chmod +x cgroup-version-detect.sh
./cgroup-version-detect.sh
```

---

### Lab 2：探索 cgroups v2 层级结构

**目标**：理解 v2 的统一层级和 systemd 集成。

**前提**：确认系统是 cgroups v2。

```bash
# 确认 v2
mount | grep cgroup2
```

**步骤 1：查看根 cgroup**

```bash
# 进入 cgroup 根目录
cd /sys/fs/cgroup

# 查看目录结构
ls -la
```

输出说明：

```
drwxr-xr-x  - root  cgroup.controllers    # 可用的控制器列表
drwxr-xr-x  - root  cgroup.procs          # 属于此 cgroup 的进程
drwxr-xr-x  - root  cgroup.subtree_control # 子树启用的控制器
drwxr-xr-x  - root  cpu.stat              # CPU 统计
drwxr-xr-x  - root  memory.current        # 当前内存使用
drwxr-xr-x  - root  system.slice/         # systemd 系统服务 cgroup
drwxr-xr-x  - root  user.slice/           # 用户会话 cgroup
drwxr-xr-x  - root  init.scope/           # PID 1 (systemd) 自己的 cgroup
```

**步骤 2：查看可用控制器**

```bash
# 系统支持的控制器
cat /sys/fs/cgroup/cgroup.controllers
```

典型输出：

```
cpuset cpu io memory hugetlb pids rdma misc
```

| 控制器 | 作用 |
|--------|------|
| **cpu** | CPU 时间限制和权重 |
| **cpuset** | CPU 亲和性和 NUMA 节点 |
| **io** | 块 I/O 带宽限制 |
| **memory** | 内存使用限制 |
| **pids** | 进程数量限制 |
| **hugetlb** | 大页内存限制 |

**步骤 3：查看子树控制**

```bash
# 根 cgroup 启用了哪些控制器传递给子 cgroup
cat /sys/fs/cgroup/cgroup.subtree_control
```

输出：

```
cpu io memory pids
```

这意味着 system.slice、user.slice 等子 cgroup 可以使用这些控制器。

**步骤 4：探索 systemd 切片结构**

```bash
# 查看 system.slice 结构
ls /sys/fs/cgroup/system.slice/

# 查看某个服务的 cgroup（例如 sshd）
ls /sys/fs/cgroup/system.slice/sshd.service/ 2>/dev/null || echo "sshd.service 目录不存在"

# 查看 user.slice 结构
ls /sys/fs/cgroup/user.slice/
```

**步骤 5：查看当前 shell 所属的 cgroup**

```bash
# 查看当前进程的 cgroup
cat /proc/self/cgroup
```

v2 输出（简洁）：

```
0::/user.slice/user-1000.slice/session-1.scope
```

v1 输出（多行）：

```
12:memory:/user.slice/user-1000.slice
11:cpu,cpuacct:/user.slice/user-1000.slice
...
```

---

### Lab 3：使用 systemd 工具探索

**目标**：使用 systemd 提供的工具查看 cgroup 状态。

**工具 1：systemd-cgls（cgroup 树状视图）**

```bash
# 查看完整 cgroup 层级树
systemd-cgls --no-pager

# 只看系统服务
systemd-cgls --no-pager /system.slice

# 只看用户会话
systemd-cgls --no-pager /user.slice
```

输出示例：

```
Control group /:
-.slice
├─user.slice
│ └─user-1000.slice
│   └─session-1.scope
│     ├─ 1234 bash
│     └─ 5678 vim
├─init.scope
│ └─   1 /usr/lib/systemd/systemd
└─system.slice
  ├─sshd.service
  │ └─ 789 sshd: /usr/sbin/sshd -D
  └─docker.service
    └─ 456 /usr/bin/dockerd
```

**工具 2：systemd-cgtop（实时资源监控）**

```bash
# 实时查看 cgroup 资源使用
sudo systemd-cgtop

# 按内存排序
sudo systemd-cgtop --order=memory

# 只显示一次，不交互
sudo systemd-cgtop -n 1
```

输出示例：

```
Control Group                          Tasks   %CPU   Memory  Input/s Output/s
/                                        156    2.3     1.2G        -        -
/system.slice                             45    1.5   512.0M        -        -
/system.slice/docker.service              12    0.8   256.0M        -        -
/user.slice                               23    0.5   128.0M        -        -
```

**工具 3：systemctl 查看服务资源状态**

```bash
# 查看服务的 cgroup 路径
systemctl status sshd | grep -i cgroup

# 查看服务的资源配置
systemctl show sshd --property=MemoryAccounting,CPUAccounting,MemoryCurrent

# 列出所有启用资源监控的服务
systemctl show '*' --property=MemoryAccounting | grep "yes"
```

---

## systemd 与 cgroups v2 集成

### slice 层级结构

systemd 使用 slice 组织 cgroup 层级：

```
┌─────────────────────────────────────────────────────────┐
│                    -.slice (root)                       │
├─────────────────────────────────────────────────────────┤
│                                                         │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────┐  │
│  │  system.slice   │  │   user.slice    │  │ machine │  │
│  │                 │  │                 │  │ .slice  │  │
│  │  系统服务       │  │  用户会话       │  │  虚拟机  │  │
│  │  sshd.service   │  │  user-1000      │  │  容器   │  │
│  │  docker.service │  │   .slice        │  │         │  │
│  │  nginx.service  │  │    └─session    │  │         │  │
│  └─────────────────┘  └─────────────────┘  └─────────┘  │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

| Slice | 用途 | 示例 |
|-------|------|------|
| **system.slice** | 系统服务 | sshd.service, docker.service |
| **user.slice** | 用户会话 | user-1000.slice/session-1.scope |
| **machine.slice** | 虚拟机和容器 | libvirt 虚拟机 |

### Unit 类型与 cgroup 关系

| Unit 类型 | cgroup 行为 |
|-----------|-------------|
| **.service** | 创建独立 cgroup，所有子进程归入 |
| **.scope** | 外部创建的进程组（如用户登录会话） |
| **.slice** | cgroup 分组，用于资源划分 |

### 资源控制示例

systemd 通过 Unit 文件配置资源限制（下一课详解）：

```ini
# /etc/systemd/system/myapp.service
[Service]
MemoryMax=512M
CPUQuota=50%
```

这些配置最终写入 cgroup 文件：

```bash
# 对应的 cgroup 文件
cat /sys/fs/cgroup/system.slice/myapp.service/memory.max
# 536870912 (512M in bytes)

cat /sys/fs/cgroup/system.slice/myapp.service/cpu.max
# 50000 100000 (50% of one core)
```

---

## 职场小贴士

### 日本 IT 现场常见场景

**场景 1：cgroup 版本确认（本番環境調査）**

```
問題：コンテナが異常終了、原因調査

最初の確認ステップ：
1. cgroup バージョンは？
   mount | grep cgroup

2. v1 の場合：
   - 各コントローラーを個別に確認
   - /sys/fs/cgroup/memory/docker/<container-id>/

3. v2 の場合：
   - 統一パスで確認
   - /sys/fs/cgroup/system.slice/docker-<id>.scope/
```

**场景 2：リソース監視報告（资源监控报告）**

```
上司：「各サービスのリソース使用状況を報告して」

対応：
# systemd-cgtop で一覧取得
sudo systemd-cgtop -n 1 --order=memory > /tmp/cgroup-report.txt

# 特定サービスの詳細
systemctl status docker --no-pager >> /tmp/cgroup-report.txt

# 報告書にコマンド出力を添付
```

**场景 3：RHEL 8 から RHEL 9 移行**

```
移行時の注意点：

RHEL 8 (cgroups v1):
  - /sys/fs/cgroup/memory/limit_in_bytes
  - memory.limit_in_bytes ファイル

RHEL 9 (cgroups v2):
  - /sys/fs/cgroup/memory.max
  - memory.max ファイル

スクリプトや監視設定の更新が必要！
```

### 常见日语术语

| 日语 | 读音 | 含义 |
|------|------|------|
| リソース制限 | リソースせいげん | Resource limits |
| 統一階層 | とういつかいそう | Unified hierarchy |
| コントローラ | コントローラ | Controller |
| スライス | スライス | Slice |
| 名前空間 | なまえくうかん | Namespace |

---

## 检查清单

完成本课后，你应该能够：

- [ ] 使用 `mount | grep cgroup` 判断系统 cgroups 版本
- [ ] 解释 v1 分离层级 vs v2 统一层级的区别
- [ ] 说出 v2 的三大优势（统一层级、简化配置、子树委托）
- [ ] 使用 `cat /sys/fs/cgroup/cgroup.controllers` 查看可用控制器
- [ ] 使用 `systemd-cgls` 查看 cgroup 层级树
- [ ] 使用 `systemd-cgtop` 实时监控资源使用
- [ ] 理解 system.slice 和 user.slice 的用途
- [ ] 找到特定服务的 cgroup 路径

---

## 本课小结

| 概念 | 要点 |
|------|------|
| cgroups | 控制进程「能用多少」资源 |
| v1 vs v2 | 分离层级 vs 统一层级 |
| 2025 状态 | v2 是 RHEL 9 / Ubuntu 22.04+ 默认 |
| v2 结构 | /sys/fs/cgroup（单一挂载点） |
| systemd 集成 | slice（system/user/machine）+ service/scope |
| 检测命令 | `mount \| grep cgroup` |
| 监控命令 | `systemd-cgtop`, `systemd-cgls` |

---

## v1 vs v2 架构对比图（完整）

<!-- DIAGRAM: v1-vs-v2-complete -->
```
cgroups v1 (分离层级):
┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐
│ /sys/fs/cgroup/ │  │ /sys/fs/cgroup/ │  │ /sys/fs/cgroup/ │
│ cpu/            │  │ memory/         │  │ blkio/          │
│   └── group1/   │  │   └── group1/   │  │   └── group1/   │
│       └── ...   │  │       └── ...   │  │       └── ...   │
└─────────────────┘  └─────────────────┘  └─────────────────┘
     独立管理             独立管理             独立管理

cgroups v2 (统一层级):
┌───────────────────────────────────────────────────────────┐
│ /sys/fs/cgroup/                                           │
│   ├── cgroup.controllers  (cpu memory io pids)            │
│   ├── cgroup.subtree_control                              │
│   ├── system.slice/                                       │
│   │   └── docker-xxx.scope/                               │
│   │       ├── cpu.max                                     │
│   │       ├── memory.max                                  │
│   │       └── io.max                                      │
│   └── user.slice/                                         │
│       └── ...                                             │
└───────────────────────────────────────────────────────────┘
                      统一管理
```
<!-- /DIAGRAM -->

---

## 反模式：常见错误

### 错误 1：假设所有系统都是 v2

```bash
# 错误：直接访问 v2 路径
cat /sys/fs/cgroup/memory.max  # 在 v1 系统上会失败

# 正确：先检测版本
if mount | grep -q "cgroup2"; then
    cat /sys/fs/cgroup/memory.max
else
    cat /sys/fs/cgroup/memory/memory.limit_in_bytes
fi
```

### 错误 2：混淆 v1 和 v2 的配置文件名

```bash
# v1 配置文件
memory.limit_in_bytes    # v1
cpu.shares               # v1

# v2 配置文件
memory.max               # v2
cpu.weight               # v2

# 错误：在 v2 系统上使用 v1 文件名
echo 512M > /sys/fs/cgroup/.../memory.limit_in_bytes  # 不存在！

# 正确：使用 v2 文件名
echo 536870912 > /sys/fs/cgroup/.../memory.max
```

### 错误 3：忽略 systemd 集成

```bash
# 错误：手动创建 cgroup 目录
mkdir /sys/fs/cgroup/mygroup  # 可能与 systemd 冲突

# 正确：使用 systemd 管理
# 通过 Unit 文件配置资源限制，让 systemd 创建 cgroup
```

---

## 延伸阅读

### 官方文档

- [cgroups v2 - Kernel Documentation](https://www.kernel.org/doc/Documentation/cgroup-v2.txt)
- [systemd Resource Control](https://www.freedesktop.org/software/systemd/man/systemd.resource-control.html)
- [Red Hat - Understanding cgroups](https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/9/html/managing_monitoring_and_updating_the_kernel/assembly_using-cgroups-v2-to-control-distribution-of-cpu-time-for-applications_managing-monitoring-and-updating-the-kernel)

### 相关课程

- [LX05-SYSTEMD](../../lx05-systemd/) - systemd 资源控制基础
- 下一课：[06 - cgroups v2 资源限制实战](../06-cgroups-v2-resource-control/) - CPU/内存/IO 限制与 OOM 调查

### 推荐阅读

- *Container Security* by Liz Rice - Chapter 5: cgroups
- Brendan Gregg's cgroup diagrams and analysis

---

## 面试准备（Interview Prep）

### Q1: cgroups v1 と v2 の違いは？（v1 和 v2 的区别？）

**回答要点**：

```
v1（レガシー）：
- 各コントローラーが独立した階層を持つ
- 同じプロセスが異なるコントローラーで別々のグループに属せる
- 管理が複雑

v2（現在のデフォルト）：
- 統一階層（Unified Hierarchy）
- 1つのマウントポイント（/sys/fs/cgroup）
- プロセスの位置が一意に決まる
- systemd との統合が完全
```

### Q2: システムの cgroups バージョンをどうやって確認しますか？（如何确认系统的 cgroups 版本？）

**回答要点**：

```bash
# 最も確実な方法
mount | grep cgroup

# v2 の場合：cgroup2 on /sys/fs/cgroup type cgroup2
# v1 の場合：複数行、cgroup on /sys/fs/cgroup/cpu type cgroup など

# 追加確認
stat -fc %T /sys/fs/cgroup
# v2: cgroup2fs
# v1: tmpfs
```

### Q3: systemd と cgroups の関係は？（systemd 和 cgroups 的关系？）

**回答要点**：

```
systemd は cgroups を活用：
1. 各サービスに独立した cgroup を自動作成
2. slice 構造で階層化（system.slice, user.slice）
3. Unit ファイルでリソース制限を宣言的に設定
4. systemd-cgtop, systemd-cgls で監視

重要：cgroups v2 と systemd の統合が最も完全。
RHEL 9 / Ubuntu 22.04 以降は両方とも v2 がデフォルト。
```

---

## 系列导航

[<- 04 - User Namespace](../04-user-namespace-rootless/) | [系列首页](../) | [06 - cgroups 资源限制实战 -->](../06-cgroups-v2-resource-control/)
