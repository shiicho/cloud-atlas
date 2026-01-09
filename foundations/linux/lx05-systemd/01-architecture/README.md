# 01 - 架构与设计哲学（Architecture and Philosophy）

> **目标**：理解 systemd 的架构设计，认识 PID 1 的职责和 11 种 Unit 类型  
> **前置**：基础 Linux 命令行操作（LX02-SYSADMIN 推荐）  
> **时间**：45-60 分钟  
> **实战场景**：障害対応时快速定位问题层级  

---

## 将学到的内容

1. 理解 systemd 为什么取代 SysV init
2. 理解 PID 1 的角色与职责
3. 了解 systemd 模块化架构（69+ 二进制文件）
4. 认识 11 种 Unit 类型
5. 理解 systemd 与 cgroups 的关系

---

## 先跑起来！（5 分钟）

> 在学习理论之前，先看看 systemd 管理着什么。  
> 运行这些命令，观察你系统的真实状态。  

```bash
# 查看 systemd 版本
systemctl --version

# PID 1 是谁？
ps -p 1 -o comm=

# 系统当前状态概览
systemctl status

# 查看所有运行中的服务
systemctl list-units --type=service --state=running | head -15

# 查看所有 Unit 类型的数量统计
systemctl list-units --all --no-pager | awk '{print $1}' | grep -oE '\.[a-z]+$' | sort | uniq -c | sort -rn
```

**你刚刚看到了 systemd 管理的整个系统！**

- PID 1 就是 systemd
- 系统中运行着几十个 service
- 还有 socket、timer、mount 等各种 Unit 类型

现在让我们理解这背后的架构。

---

## Step 1 - 从 SysV init 到 systemd（10 分钟）

### 1.1 SysV init 的问题

在 systemd 之前，Linux 使用 SysV init 启动系统：

```
SysV init 启动流程（顺序执行）：
┌─────────┐   ┌─────────┐   ┌─────────┐   ┌─────────┐   ┌─────────┐
│ S01xxx  │──▶│ S02xxx  │──▶│ S03xxx  │──▶│ S04xxx  │──▶│ S99xxx  │
│ (网络)   │   │ (日志)   │   │ (数据库) │   │ (Web)   │   │ (完成)   │
└─────────┘   └─────────┘   └─────────┘   └─────────┘   └─────────┘
    10s    +      5s     +      8s     +     3s     =    26s 总时间
```

**SysV init 的痛点**：

| 问题 | 影响 |
|------|------|
| 顺序启动 | 启动慢，不能并行 |
| Shell 脚本 | 难以维护，容易出错 |
| 进程追踪困难 | 服务 fork 后丢失关联 |
| 无统一管理工具 | 每个发行版命令不同 |

### 1.2 systemd 的解决方案

```
systemd 启动流程（并行依赖）：
              ┌─────────┐
              │ 日志    │
              │ (5s)   │
              └────┬────┘
┌─────────┐        │        ┌─────────┐
│ 网络    │────────┼────────│ 数据库   │
│ (10s)   │        │        │ (8s)    │
└────┬────┘        │        └────┬────┘
     │             │             │
     └─────────────┼─────────────┘
                   ▼
              ┌─────────┐
              │ Web     │
              │ (3s)    │
              └─────────┘

总时间：~13s（最长路径：网络 10s + Web 3s）
```

**systemd 的优势**：

| 特性 | 好处 |
|------|------|
| 并行启动 | 依赖关系决定顺序，无关服务并行 |
| 声明式配置 | Unit 文件替代 Shell 脚本 |
| cgroup 追踪 | 精确追踪服务的所有进程 |
| 统一工具 | `systemctl` 一个命令管理一切 |

### 1.3 动手验证：启动时间对比

```bash
# 查看系统启动耗时
systemd-analyze

# 查看各服务启动耗时（按时间排序）
systemd-analyze blame | head -10

# 查看启动关键路径
systemd-analyze critical-chain
```

---

## Step 2 - PID 1：系统的守护者（10 分钟）

### 2.1 为什么 PID 1 特殊？

PID 1 是 Linux 内核启动后运行的第一个用户空间进程。它有特殊职责：

```bash
# 验证 PID 1
ps -p 1 -o pid,comm,args

# 查看进程树（PID 1 是所有进程的祖先）
pstree -p | head -20
```

### 2.2 PID 1 的三大职责

```
┌─────────────────────────────────────────────────────────────┐
│                    PID 1 (systemd) 职责                      │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  1. 进程收割（Reaping Orphans）                              │
│     ┌────────┐                                              │
│     │ 父进程  │──x──▶ 退出                                   │
│     └───┬────┘                                              │
│         │                                                   │
│     ┌───▼────┐        ┌─────────┐                          │
│     │ 子进程  │──────▶ │ PID 1   │  ← 自动收养孤儿进程        │
│     │ (孤儿)  │        │ 收割    │                          │
│     └────────┘        └─────────┘                          │
│                                                             │
│  2. 服务监控（Service Supervision）                          │
│     - 检测服务崩溃                                           │
│     - 根据策略自动重启（Restart=on-failure）                  │
│     - 记录状态到 journal                                     │
│                                                             │
│  3. cgroup 管理（Resource Control）                          │
│     - 每个服务独立 cgroup                                    │
│     - CPU、内存、I/O 限制                                    │
│     - 精确追踪服务的所有子进程                                │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### 2.3 动手验证：cgroup 追踪

```bash
# 查看 sshd 服务的 cgroup
systemctl status sshd | grep -i cgroup

# 或者直接查看 cgroup 层次
cat /proc/$(pgrep -o sshd)/cgroup

# 查看系统的 cgroup 层次结构
systemd-cgls --no-pager | head -30
```

**cgroup 的威力**：即使服务 fork 了多个子进程，systemd 也能通过 cgroup 追踪它们全部。

---

## Step 3 - systemd 六层架构（10 分钟）

### 3.1 架构全景图

```
┌─────────────────────────────────────────────────────────┐
│                     L6: Utilities                       │
│     systemctl  journalctl  systemd-analyze  timedatectl │
├─────────────────────────────────────────────────────────┤
│  L5a: Daemons     │  L5b: Targets    │  L5c: External   │
│  journald         │  multi-user      │  nginx.service   │
│  networkd         │  graphical       │  postgresql      │
│  resolved         │  timers          │  custom apps     │
├─────────────────────────────────────────────────────────┤
│                     L4: PID 1 (systemd)                 │
│              Unit management, cgroup control            │
├─────────────────────────────────────────────────────────┤
│                     L3: Libraries                       │
│                   libsystemd, libudev                   │
├─────────────────────────────────────────────────────────┤
│                     L2: Linux Kernel                    │
│               cgroups, namespaces, seccomp              │
├─────────────────────────────────────────────────────────┤
│                     L1: Hardware                        │
└─────────────────────────────────────────────────────────┘
```

### 3.2 各层职责

| 层级 | 组件 | 职责 |
|------|------|------|
| L6 | Utilities | 用户交互工具（systemctl, journalctl） |
| L5 | Daemons/Targets | 系统服务和同步点 |
| L4 | PID 1 | Unit 管理、cgroup 控制 |
| L3 | Libraries | libsystemd（SD-Bus, sd_notify） |
| L2 | Kernel | cgroups v2, namespaces, seccomp |
| L1 | Hardware | 物理或虚拟硬件 |

### 3.3 常见误解：systemd 不是单体程序

```bash
# 查看 systemd 相关的二进制文件数量
ls /usr/lib/systemd/ | wc -l

# 查看具体有哪些组件
ls /usr/lib/systemd/
```

**systemd 是一套工具集**，包含 69+ 个独立二进制文件：

| 组件 | 用途 |
|------|------|
| `systemd` | PID 1，核心管理器 |
| `systemd-journald` | 日志守护进程 |
| `systemd-networkd` | 网络配置 |
| `systemd-resolved` | DNS 解析 |
| `systemd-logind` | 登录管理 |
| `systemd-udevd` | 设备管理 |
| `systemd-timesyncd` | 时间同步 |

---

## Step 4 - 11 种 Unit 类型（10 分钟）

### 4.1 Unit 类型概览

systemd 管理的对象叫做 Unit（单元），共有 11 种类型：

| 类型 | 后缀 | 用途 | 示例 |
|------|------|------|------|
| **service** | `.service` | 系统服务 | nginx.service |
| **socket** | `.socket` | 套接字激活 | sshd.socket |
| **timer** | `.timer` | 定时任务（替代 cron） | backup.timer |
| **mount** | `.mount` | 文件系统挂载 | home.mount |
| **automount** | `.automount` | 自动挂载 | nfs-share.automount |
| **target** | `.target` | 同步点/分组 | multi-user.target |
| **device** | `.device` | 设备 | dev-sda.device |
| **swap** | `.swap` | 交换分区 | dev-sda2.swap |
| **path** | `.path` | 路径监控 | myapp.path |
| **slice** | `.slice` | cgroup 切片 | user.slice |
| **scope** | `.scope` | 外部进程组 | session-1.scope |

### 4.2 动手探索：你系统的 Unit

```bash
# 按类型统计 Unit 数量
systemctl list-units --all --no-pager | \
    awk '{print $1}' | \
    grep -oE '\.[a-z]+$' | \
    sort | uniq -c | sort -rn

# 查看所有 service 类型
systemctl list-units --type=service --all | head -20

# 查看所有 timer 类型
systemctl list-units --type=timer --all

# 查看所有 target 类型
systemctl list-units --type=target --all
```

### 4.3 最常用的 Unit 类型

日常运维中最常接触的是这 4 种：

```
         service                    timer
     ┌─────────────┐           ┌─────────────┐
     │ 长期运行的   │           │ 定时触发的   │
     │ 后台服务     │           │ 计划任务     │
     │             │           │             │
     │ nginx       │           │ backup      │
     │ postgresql  │           │ logrotate   │
     └─────────────┘           └─────────────┘

         target                    socket
     ┌─────────────┐           ┌─────────────┐
     │ 服务分组/    │           │ 按需激活     │
     │ 同步点       │           │ 节省资源     │
     │             │           │             │
     │ multi-user  │           │ sshd.socket │
     │ graphical   │           │ cups.socket │
     └─────────────┘           └─────────────┘
```

---

## Step 5 - Mini-Project：探索系统 Unit（10 分钟）

### 任务目标

使用 systemctl 列出、分类统计当前系统的所有 Unit 类型。

### 5.1 创建探索脚本

```bash
# 创建工作目录
mkdir -p ~/systemd-lab
cd ~/systemd-lab

# 创建探索脚本
cat > explore-units.sh << 'EOF'
#!/bin/bash
# systemd Unit Explorer - 系统 Unit 探索工具

echo "============================================"
echo "  systemd Unit 探索报告"
echo "  生成时间: $(date)"
echo "============================================"
echo ""

# systemd 版本
echo "【systemd 版本】"
systemctl --version | head -1
echo ""

# 系统启动时间
echo "【系统启动耗时】"
systemd-analyze
echo ""

# Unit 类型统计
echo "【Unit 类型统计】"
echo "--------------------------------"
printf "%-15s %s\n" "类型" "数量"
echo "--------------------------------"

systemctl list-units --all --no-pager 2>/dev/null | \
    awk '{print $1}' | \
    grep -oE '\.[a-z]+$' | \
    sort | uniq -c | sort -rn | \
    while read count type; do
        printf "%-15s %s\n" "$type" "$count"
    done

echo "--------------------------------"
echo ""

# 失败的 Unit
echo "【失败的 Unit】"
failed_count=$(systemctl list-units --failed --no-pager 2>/dev/null | grep -c "loaded units listed")
if [ "$failed_count" = "0" ]; then
    systemctl list-units --failed --no-pager 2>/dev/null | grep -v "^$" | head -10
else
    echo "没有失败的 Unit"
fi
echo ""

# 活跃的 timer
echo "【活跃的 Timer】"
systemctl list-timers --no-pager 2>/dev/null | head -10
echo ""

# 资源使用最高的服务（如果有 systemd-cgtop）
echo "【资源使用情况（前 10）】"
if command -v systemd-cgtop &>/dev/null; then
    systemd-cgtop -n 1 --order=memory 2>/dev/null | head -12
else
    echo "systemd-cgtop 不可用"
fi

echo ""
echo "============================================"
echo "  报告完成"
echo "============================================"
EOF

chmod +x explore-units.sh
```

### 5.2 运行探索脚本

```bash
# 运行脚本
./explore-units.sh

# 保存报告
./explore-units.sh > unit-report-$(date +%Y%m%d).txt
cat unit-report-$(date +%Y%m%d).txt
```

### 5.3 检查清单

完成以下任务：

- [ ] 确认 PID 1 是 systemd
- [ ] 查看系统启动耗时
- [ ] 统计各类型 Unit 的数量
- [ ] 查看是否有失败的 Unit
- [ ] 查看活跃的 timer

---

## 反模式：常见误解

### 误解 1：systemd 是一个庞大的单体程序

**错误理解**：systemd 把所有功能塞进一个程序。

**实际情况**：systemd 是 69+ 个独立二进制文件的集合。你可以选择性启用/禁用各组件。

```bash
# 禁用不需要的组件
systemctl disable systemd-networkd  # 如果用 NetworkManager
systemctl disable systemd-resolved  # 如果用传统 DNS 配置
```

### 误解 2：cgroup 只用于容器

**错误理解**：cgroup 是 Docker/Kubernetes 的技术，与 systemd 无关。

**实际情况**：systemd 依赖 cgroup 追踪服务进程。每个 service 自动分配独立的 cgroup。

```bash
# 查看 cgroup 层次
systemd-cgls

# 查看特定服务的资源限制
systemctl show nginx --property=MemoryMax,CPUQuota
```

### 误解 3：systemd 只管服务

**错误理解**：systemd 就是服务管理器。

**实际情况**：systemd 管理 11 种 Unit 类型，包括挂载点、定时任务、设备等。

---

## 职场小贴士（Japan IT Context）

### 障害対応（故障处理）中的架构思维

在日本 IT 企业，处理故障时需要快速定位问题在哪一层：

```
问题定位流程：
┌─────────────────────────────────────────────────┐
│ 用户报告：Web 应用无法访问                        │
└────────────────────┬────────────────────────────┘
                     ▼
┌─────────────────────────────────────────────────┐
│ L6 检查：systemctl status nginx                  │
│     → 服务状态？运行中？失败？                    │
└────────────────────┬────────────────────────────┘
                     ▼
┌─────────────────────────────────────────────────┐
│ L5 检查：journalctl -u nginx                     │
│     → 日志中有什么错误？                         │
└────────────────────┬────────────────────────────┘
                     ▼
┌─────────────────────────────────────────────────┐
│ L4 检查：systemctl list-dependencies nginx       │
│     → 依赖的服务都正常吗？                       │
└────────────────────┬────────────────────────────┘
                     ▼
┌─────────────────────────────────────────────────┐
│ L2 检查：dmesg | tail                           │
│     → 内核有报错吗？磁盘/网络问题？              │
└─────────────────────────────────────────────────┘
```

### 日本 IT 术语对照

| 日语术语 | 读音 | 含义 | systemd 相关 |
|----------|------|------|--------------|
| 障害対応 | しょうがいたいおう | 故障处理 | systemctl status, journalctl |
| 起動順序 | きどうじゅんじょ | 启动顺序 | systemd-analyze critical-chain |
| プロセス管理 | プロセスかんり | 进程管理 | cgroup 追踪 |
| サービス監視 | サービスかんし | 服务监控 | systemctl is-active |

---

## 面试准备（Interview Prep）

### Q1: systemd と SysV init の違いは？（systemd 和 SysV init 的区别？）

**回答要点**：

```
SysV init:
- 順次起動（Sequential boot）
- シェルスクリプトベース
- プロセス追跡が困難

systemd:
- 依存関係ベースの並列起動（Parallel boot based on dependencies）
- 宣言的な Unit ファイル
- cgroup で確実にプロセス追跡
```

### Q2: systemd が PID 1 である理由は？（为什么 systemd 是 PID 1？）

**回答要点**：

```
PID 1 の特別な役割：
1. 孤児プロセスの回収（Orphan process reaping）
2. サービス監視と自動再起動
3. cgroup 管理の一元化

全プロセスの親として、システム全体を管理できる唯一のポジション。
```

---

## 检查清单

完成本课后，你应该能够：

- [ ] 解释 systemd 相比 SysV init 的优势（并行启动、依赖管理、cgroup 追踪）
- [ ] 说明 PID 1 的三大职责（进程收割、服务监控、cgroup 管理）
- [ ] 描述 systemd 六层架构的各层职责
- [ ] 列出并解释 4 种最常用的 Unit 类型（service, timer, target, socket）
- [ ] 使用 systemctl 和 systemd-analyze 探索系统状态
- [ ] 理解 systemd 是模块化工具集，不是单体程序

---

## 本课小结

| 概念 | 要点 |
|------|------|
| SysV vs systemd | 顺序启动 vs 并行依赖 |
| PID 1 职责 | 进程收割、服务监控、cgroup 管理 |
| 六层架构 | Hardware → Kernel → Libraries → PID1 → Daemons → Utilities |
| Unit 类型 | 11 种，最常用：service, timer, target, socket |
| cgroups | 资源隔离与进程追踪 |

---

## 延伸阅读

- [systemd 官方文档](https://www.freedesktop.org/wiki/Software/systemd/)
- [Lennart Poettering 的 systemd 设计文档](http://0pointer.de/blog/projects/systemd.html)
- 下一课：[02 - 服务管理（systemctl 实战）](../02-systemctl/) - 学习使用 systemctl 管理服务
- 相关课程：[LX02 - 系统管理基础](../../sysadmin/) - 用户、进程、权限管理

---

## 系列导航

[系列首页](../) | [02 - 服务管理 -->](../02-systemctl/)
