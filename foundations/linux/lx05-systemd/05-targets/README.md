# 05 - Target 与启动流程（Targets and Boot Process）

> **目标**：掌握 Target 作为同步点的角色，理解 Linux 完整启动流程，学会分析和排查启动问题  
> **前置**：Lesson 04 依赖与排序（dependency-management）  
> **时间**：60-75 分钟  
> **实战场景**：ブート問題のトラブルシューティング - 起動が遅い原因調査  

---

## 将学到的内容

1. 理解 Target 作为同步点的角色
2. 对应 SysV runlevel 到 systemd target
3. 查看和更改默认 target
4. 掌握完整的 5 阶段启动流程
5. 使用 systemd-analyze 分析启动性能
6. 配置时间同步（chrony/timedatectl）
7. 使用紧急和救援模式排查问题

---

## 先跑起来！（5 分钟）

> 在学习理论之前，先体验 Target 和启动分析。  
> 运行这些命令，观察系统的启动状态。  

```bash
# 查看当前运行的 target
systemctl get-default

# 系统启动用了多长时间？
systemd-analyze

# 哪些服务启动最慢？
systemd-analyze blame | head -10

# 查看启动关键路径
systemd-analyze critical-chain

# 查看所有 target
systemctl list-units --type=target
```

**你刚刚完成了启动分析的核心操作！**

- `get-default` 显示系统默认启动到哪个 target
- `systemd-analyze` 显示总启动时间
- `blame` 找出最慢的服务
- `critical-chain` 显示启动的关键路径

现在让我们深入理解 Target 和启动流程。

---

## Step 1 - 理解 Target（15 分钟）

### 1.1 什么是 Target？

Target 是 systemd 的同步点（Synchronization Point），它：

- **不运行任何进程**
- **只是一组 Unit 的集合**
- **定义系统状态的里程碑**

```
Target = 同步点（Synchronization Point）

┌─────────────────────────────────────────────────────────────┐
│                      multi-user.target                       │
│  ┌─────────────────────────────────────────────────────────┐ │
│  │                                                         │ │
│  │   ┌──────────┐  ┌──────────┐  ┌──────────┐            │ │
│  │   │ sshd     │  │ nginx    │  │ cron     │  ...       │ │
│  │   └──────────┘  └──────────┘  └──────────┘            │ │
│  │                                                         │ │
│  │   所有 WantedBy=multi-user.target 的服务                │ │
│  │                                                         │ │
│  └─────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘

Target 本身不运行进程，只是把相关服务组织在一起的"标签"
```

### 1.2 SysV Runlevel 到 systemd Target 映射

如果你熟悉旧的 runlevel 概念，这是对应关系：

| SysV Runlevel | systemd Target | 用途 |
|---------------|----------------|------|
| 0 | poweroff.target | 关机 |
| 1, S | rescue.target | 单用户模式（救援） |
| 2, 3, 4 | multi-user.target | 多用户命令行 |
| 5 | graphical.target | 图形界面 |
| 6 | reboot.target | 重启 |

```bash
# 验证映射关系
ls -la /usr/lib/systemd/system/runlevel*.target
```

### 1.3 标准 Target 层次

```
系统启动的 Target 层次：

       sysinit.target
             │
             ▼
       basic.target
             │
     ┌───────┼───────┐
     │       │       │
     ▼       ▼       ▼
 sockets  timers   paths
 .target  .target  .target
     │       │       │
     └───────┼───────┘
             ▼
      multi-user.target ← 服务器默认停在这里
             │
             ▼
      graphical.target  ← 桌面系统停在这里
```

### 1.4 特殊 Target

| Target | 用途 |
|--------|------|
| `sysinit.target` | 系统初始化（文件系统、swap） |
| `basic.target` | 基本系统功能就绪 |
| `local-fs.target` | 本地文件系统挂载完成 |
| `network.target` | 网络栈初始化 |
| `network-online.target` | 网络实际可用 |
| `timers.target` | Timer 管理就绪 |
| `sockets.target` | Socket 管理就绪 |

**重要区分**：`network.target` vs `network-online.target`

```bash
# network.target - 网络栈初始化（但可能还没拿到 IP）
# network-online.target - 网络实际可用（有 IP，能连外网）

# 对于需要网络连接的服务，应该用：
After=network-online.target
Wants=network-online.target
```

---

## Step 2 - Target 管理（10 分钟）

### 2.1 查看和设置默认 Target

```bash
# 查看当前默认 target
systemctl get-default

# 设置默认 target（需要 root）
sudo systemctl set-default multi-user.target    # 服务器推荐
sudo systemctl set-default graphical.target     # 桌面系统

# 查看设置后的符号链接
ls -la /etc/systemd/system/default.target
```

### 2.2 切换 Target（isolate）

`isolate` 命令可以立即切换到指定 target，**停止不属于该 target 的服务**：

```bash
# 切换到救援模式（小心！会停止大多数服务）
sudo systemctl isolate rescue.target

# 切换回多用户模式
sudo systemctl isolate multi-user.target

# 切换到图形界面
sudo systemctl isolate graphical.target
```

**注意**：不是所有 target 都能 isolate。只有设置了 `AllowIsolate=yes` 的 target 才行。

### 2.3 查看 Target 依赖

```bash
# 查看 multi-user.target 包含哪些服务
systemctl list-dependencies multi-user.target

# 反向查询：哪些服务属于这个 target
systemctl list-dependencies --reverse multi-user.target | head -20

# 递归显示完整依赖树
systemctl list-dependencies multi-user.target --all | head -30
```

---

## Step 3 - 完整启动流程（20 分钟）

### 3.1 五阶段启动流程

Linux 系统从按下电源键到登录提示，经历 5 个阶段：

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        Linux 完整启动流程                                 │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  Stage 1: Firmware (UEFI/BIOS)                                         │
│  ┌───────────────────────────────────────────────────────────────────┐ │
│  │ - POST (Power-On Self-Test)                                       │ │
│  │ - 硬件初始化                                                       │ │
│  │ - 查找启动设备                                                     │ │
│  │ - 加载 Bootloader                                                  │ │
│  └───────────────────────────────────────────────────────────────────┘ │
│                              │                                         │
│                              ▼                                         │
│  Stage 2: Bootloader (GRUB2)                                          │
│  ┌───────────────────────────────────────────────────────────────────┐ │
│  │ - 显示内核选择菜单                                                 │ │
│  │ - 加载选定的内核和 initramfs                                       │ │
│  │ - 传递内核参数                                                     │ │
│  └───────────────────────────────────────────────────────────────────┘ │
│                              │                                         │
│                              ▼                                         │
│  Stage 3: Kernel Initialization                                        │
│  ┌───────────────────────────────────────────────────────────────────┐ │
│  │ - 硬件检测和驱动加载                                               │ │
│  │ - 挂载 initramfs 作为临时根文件系统                                │ │
│  │ - 内核参数：systemd.unit=, rd.break, init=                        │ │
│  └───────────────────────────────────────────────────────────────────┘ │
│                              │                                         │
│                              ▼                                         │
│  Stage 4: initramfs Stage                                              │
│  ┌───────────────────────────────────────────────────────────────────┐ │
│  │ - 运行 initramfs 中的脚本                                         │ │
│  │ - 设置 LVM/LUKS/RAID                                              │ │
│  │ - 挂载真正的根文件系统                                             │ │
│  │ - 切换到真实根（pivot_root）                                       │ │
│  └───────────────────────────────────────────────────────────────────┘ │
│                              │                                         │
│                              ▼                                         │
│  Stage 5: systemd (PID 1)                                              │
│  ┌───────────────────────────────────────────────────────────────────┐ │
│  │ - 内核执行 /sbin/init -> systemd                                  │ │
│  │ - 解析 Unit 文件                                                   │ │
│  │ - sysinit.target -> basic.target -> multi-user.target             │ │
│  │ - 到达默认 target，显示登录提示                                    │ │
│  └───────────────────────────────────────────────────────────────────┘ │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

### 3.2 Stage 2: Bootloader (GRUB2)

```bash
# 查看 GRUB 配置
cat /etc/default/grub

# 常用内核参数
# systemd.unit=emergency.target  - 启动到紧急模式
# rd.break                       - 在挂载根之前进入 initramfs shell
# init=/bin/bash                 - 绕过 systemd（最后手段）

# 重新生成 GRUB 配置（修改后）
# RHEL/CentOS/Rocky:
sudo grub2-mkconfig -o /boot/grub2/grub.cfg
# Ubuntu/Debian:
sudo update-grub
```

### 3.3 Stage 4: initramfs 和 dracut

initramfs（Initial RAM Filesystem）是一个临时的根文件系统，在内核加载后、挂载真正根之前使用。

```bash
# 查看 initramfs 内容
lsinitrd | head -50

# 查看 initramfs 中包含的模块
lsinitrd | grep -E "\.ko$" | head -20

# 重建 initramfs（添加 LVM/LUKS 模块后）
sudo dracut -f

# 查看可用的 dracut 模块
dracut --list-modules
```

**何时需要重建 initramfs：**

- 添加 LVM/LUKS/multipath 支持
- 内核更新失败后修复
- 启动卡在 initramfs 阶段

### 3.4 Stage 5: systemd Target 流程

```bash
# 查看完整的启动依赖链
systemctl list-dependencies default.target --all | head -50

# 启动流程可视化
systemd-analyze plot > /tmp/boot.svg
# 用浏览器打开 /tmp/boot.svg 查看时间线图
```

---

## Step 4 - 启动性能分析（10 分钟）

### 4.1 systemd-analyze 命令集

```bash
# 基本启动时间
systemd-analyze

# 输出示例：
# Startup finished in 2.5s (firmware) + 3.1s (loader) + 1.2s (kernel)
#                    + 4.3s (initrd) + 15.2s (userspace) = 26.3s

# 各服务启动时间排序
systemd-analyze blame | head -15

# 启动关键路径（Critical Chain）
systemd-analyze critical-chain
```

### 4.2 理解 Critical Chain

```bash
# 关键路径分析
systemd-analyze critical-chain

# 输出示例：
# graphical.target @20.130s
# └─multi-user.target @20.130s
#   └─postgresql.service @15.523s +4.607s
#     └─network-online.target @15.521s
#       └─NetworkManager-wait-online.service @5.123s +10.398s
#         └─NetworkManager.service @4.865s +256ms
#           └─basic.target @4.863s
```

**关键路径解读：**

- `@` 后面是该 Unit 启动的时间点
- `+` 后面是该 Unit 启动耗时
- 最下面的是先启动的，最上面的是最后启动的
- 优化关键路径上的服务可以减少总启动时间

### 4.3 生成启动时间线图

```bash
# 生成 SVG 时间线图
systemd-analyze plot > /tmp/boot-timeline.svg

# 如果是服务器（无图形界面），可以 scp 下载到本地查看
# 或者用 systemd-analyze blame 的文本输出

# 查看特定 target 的依赖
systemd-analyze critical-chain multi-user.target
```

### 4.4 常见启动慢的原因

| 服务 | 常见原因 | 优化方法 |
|------|----------|----------|
| NetworkManager-wait-online | 等待 DHCP | 静态 IP 或调整超时 |
| plymouth-quit-wait | 等待启动画面 | 服务器可禁用 plymouth |
| systemd-udev-settle | 等待设备稳定 | 检查慢设备或禁用 |
| lvm2-monitor | LVM 监控 | 无 LVM 可禁用 |

```bash
# 检查是否有超时等待的服务
journalctl -b | grep -i timeout

# 禁用不需要的服务
sudo systemctl disable plymouth-quit-wait.service  # 服务器无需
```

---

## Step 5 - 时间同步（10 分钟）

### 5.1 为什么时间同步至关重要？

时间同步对运维至关重要：

| 场景 | 时间不准的后果 |
|------|----------------|
| TLS/SSL 握手 | 证书验证失败（Not Yet Valid / Expired） |
| 日志关联 | 多服务器故障排查时无法关联日志 |
| 分布式系统 | Kubernetes、etcd 共识失败 |
| 定时任务 | cron/timer 执行时间错误 |
| 审计合规 | ISMS、PCI DSS 要求时间准确 |

### 5.2 chrony vs ntpd

| 特性 | chrony | ntpd |
|------|--------|------|
| 状态 | 现代默认（RHEL 9, Ubuntu 22.04+） | 传统方案 |
| 同步速度 | 快速，适合 VM 和移动设备 | 较慢 |
| 资源占用 | 低 | 较高 |
| 推荐场景 | 生产环境首选 | 特殊兼容需求 |

### 5.3 timedatectl 命令

```bash
# 查看当前时间状态
timedatectl

# 输出示例：
#                Local time: Sun 2026-01-04 15:30:45 JST
#            Universal time: Sun 2026-01-04 06:30:45 UTC
#                  RTC time: Sun 2026-01-04 06:30:45
#                 Time zone: Asia/Tokyo (JST, +0900)
# System clock synchronized: yes
#               NTP service: active
#           RTC in local TZ: no

# 设置时区（日本）
sudo timedatectl set-timezone Asia/Tokyo

# 启用 NTP 同步
sudo timedatectl set-ntp true

# 查看同步状态（使用 systemd-timesyncd 时）
timedatectl timesync-status
```

### 5.4 chrony 操作

```bash
# 检查 chrony 服务状态
systemctl status chronyd

# 查看 NTP 源
chronyc sources

# 输出示例：
# MS Name/IP address         Stratum Poll Reach LastRx Last sample
# ===============================================================================
# ^* ntp.nict.jp                   1   6   377    34   -234us[ -312us] +/-   11ms
# ^+ ntp.jst.mfeed.ad.jp           2   6   377    35   +892us[ +814us] +/-   21ms

# 查看同步状态
chronyc tracking

# 强制立即同步（谨慎使用）
sudo chronyc makestep
```

### 5.5 反模式：忽略时间漂移

**错误做法**：在障害対応时忽略时间检查。

**正确做法**：故障排查第一步检查时间同步。

```bash
# 故障排查时的时间检查清单
timedatectl                    # 时间和时区是否正确？
chronyc sources                # NTP 源是否可达？
chronyc tracking               # 时间偏差有多大？
```

---

## Step 6 - 紧急和救援模式（10 分钟）

### 6.1 三种恢复模式

| 模式 | 访问方式 | 提供的环境 | 使用场景 |
|------|----------|------------|----------|
| `rescue.target` | `systemctl isolate` 或内核参数 | 单用户，基本文件系统挂载 | 修复配置、密码重置 |
| `emergency.target` | 内核参数 `systemd.unit=emergency.target` | 最小环境，仅根文件系统 | 严重问题修复 |
| `rd.break` | 内核参数 | initramfs shell | 密码重置、文件系统修复 |

### 6.2 进入救援模式

**方法 1：从运行中的系统**

```bash
# 切换到救援模式
sudo systemctl isolate rescue.target

# 返回正常模式
sudo systemctl isolate multi-user.target
```

**方法 2：从 GRUB 启动菜单**

1. 重启系统，在 GRUB 菜单按 `e` 编辑
2. 找到 `linux` 行，在行末添加：
   - `systemd.unit=rescue.target` - 救援模式
   - `systemd.unit=emergency.target` - 紧急模式
3. 按 `Ctrl+X` 启动

### 6.3 使用 rd.break 重置 root 密码

**这是 RHCSA 考试重点！**

1. 在 GRUB 菜单按 `e` 编辑
2. 在 `linux` 行末添加 `rd.break`
3. 按 `Ctrl+X` 启动

```bash
# 进入 initramfs shell 后
# 真实根文件系统挂载在 /sysroot

# 重新挂载为可写
mount -o remount,rw /sysroot

# 进入真实根环境
chroot /sysroot

# 重置密码
passwd root

# 触发 SELinux 重新标记（RHEL/CentOS 必需）
touch /.autorelabel

# 退出并重启
exit
exit
# 或者 reboot -f
```

### 6.4 救援模式实用技巧

```bash
# 在救援模式下检查日志
journalctl -xb

# 检查启动失败的服务
systemctl --failed

# 检查文件系统
fsck /dev/sda1

# 重新加载 systemd（修改 unit 文件后）
systemctl daemon-reload
```

---

## Step 7 - Mini-Project：创建自定义 Target（15 分钟）

### 任务目标

为应用栈创建 `myapp.target`，统一管理相关服务（Web、API、Worker）。

### 7.1 场景说明

```
自定义 Target 架构：

              myapp.target
                   │
         ┌─────────┼─────────┐
         │         │         │
         ▼         ▼         ▼
   myapp-web    myapp-api   myapp-worker
    .service     .service    .service

一个命令启动/停止整个应用栈：
  systemctl start myapp.target
  systemctl stop myapp.target
```

### 7.2 创建 Target 文件

```bash
# 创建工作目录
mkdir -p ~/systemd-lab/myapp-target
cd ~/systemd-lab/myapp-target

# 创建自定义 Target
sudo tee /etc/systemd/system/myapp.target << 'EOF'
[Unit]
Description=My Application Stack Target
Documentation=https://example.com/myapp
Requires=basic.target
After=basic.target network-online.target
Wants=network-online.target
# 允许 isolate 到这个 target
AllowIsolate=yes

[Install]
WantedBy=multi-user.target
EOF
```

### 7.3 创建应用服务

```bash
# Web 服务（模拟）
sudo tee /etc/systemd/system/myapp-web.service << 'EOF'
[Unit]
Description=MyApp Web Server
Documentation=https://example.com/myapp/web
After=network-online.target myapp-api.service
Wants=network-online.target
# 属于 myapp.target
PartOf=myapp.target

[Service]
Type=simple
ExecStart=/bin/sleep infinity
Restart=on-failure
RestartSec=5

[Install]
WantedBy=myapp.target
EOF

# API 服务（模拟）
sudo tee /etc/systemd/system/myapp-api.service << 'EOF'
[Unit]
Description=MyApp API Server
Documentation=https://example.com/myapp/api
After=network-online.target
Wants=network-online.target
PartOf=myapp.target

[Service]
Type=simple
ExecStart=/bin/sleep infinity
Restart=on-failure
RestartSec=5

[Install]
WantedBy=myapp.target
EOF

# Worker 服务（模拟）
sudo tee /etc/systemd/system/myapp-worker.service << 'EOF'
[Unit]
Description=MyApp Background Worker
Documentation=https://example.com/myapp/worker
After=myapp-api.service
PartOf=myapp.target

[Service]
Type=simple
ExecStart=/bin/sleep infinity
Restart=on-failure
RestartSec=5

[Install]
WantedBy=myapp.target
EOF
```

### 7.4 启用和测试

```bash
# 重新加载 systemd
sudo systemctl daemon-reload

# 启用所有服务（创建符号链接到 target）
sudo systemctl enable myapp-web.service myapp-api.service myapp-worker.service

# 启动整个应用栈
sudo systemctl start myapp.target

# 查看状态
systemctl status myapp.target
systemctl status myapp-*.service

# 查看 target 包含的服务
systemctl list-dependencies myapp.target

# 停止整个应用栈（PartOf= 会传播停止信号）
sudo systemctl stop myapp.target

# 验证所有服务都已停止
systemctl status myapp-*.service
```

### 7.5 验证清单

- [ ] 创建了 myapp.target 文件
- [ ] 创建了 3 个 myapp-*.service 文件
- [ ] 使用 `WantedBy=myapp.target` 关联服务
- [ ] 使用 `PartOf=myapp.target` 传播停止信号
- [ ] `systemctl start myapp.target` 启动所有服务
- [ ] `systemctl stop myapp.target` 停止所有服务

---

## 反模式：常见错误

### 错误 1：混淆 network.target 和 network-online.target

**错误做法**：

```ini
[Unit]
After=network.target
```

**问题**：`network.target` 只表示网络栈初始化，不保证网络可用。

**正确做法**：

```ini
[Unit]
After=network-online.target
Wants=network-online.target
```

### 错误 2：不检查时间同步就开始故障排查

**错误做法**：直接查看日志，忽略时间。

**问题**：如果时间不同步，日志时间戳无法与其他服务器关联。

**正确做法**：

```bash
# 故障排查第一步
timedatectl
chronyc tracking
```

### 错误 3：在救援模式忘记重新挂载文件系统

**错误做法**：

```bash
# 进入救援模式后直接编辑文件
vi /etc/fstab  # 失败！文件系统是只读的
```

**正确做法**：

```bash
# 先重新挂载为可写
mount -o remount,rw /
# 然后编辑
vi /etc/fstab
```

---

## 职场小贴士（Japan IT Context）

### ブート問題のトラブルシューティング

在日本 IT 企业，系统启动问题的排查流程：

```
障害対応フロー（启动问题）：

┌─────────────────────────────────────────────────┐
│ 1. 情報収集（信息收集）                           │
│    - どの段階で止まっているか？                   │
│    - エラーメッセージは何か？                     │
└────────────────────┬────────────────────────────┘
                     ▼
┌─────────────────────────────────────────────────┐
│ 2. 起動時間分析                                  │
│    systemd-analyze                              │
│    systemd-analyze blame                        │
│    systemd-analyze critical-chain               │
└────────────────────┬────────────────────────────┘
                     ▼
┌─────────────────────────────────────────────────┐
│ 3. 時刻同期確認                                  │
│    timedatectl                                  │
│    chronyc sources                              │
└────────────────────┬────────────────────────────┘
                     ▼
┌─────────────────────────────────────────────────┐
│ 4. ログ確認                                      │
│    journalctl -xb                               │
│    journalctl -u [failed-service]               │
└────────────────────┬────────────────────────────┘
                     ▼
┌─────────────────────────────────────────────────┐
│ 5. 修正と検証                                    │
│    - 設定修正                                    │
│    - daemon-reload                              │
│    - サービス再起動                              │
└─────────────────────────────────────────────────┘
```

### 日本 IT 术语对照

| 日语术语 | 读音 | 含义 | 相关命令 |
|----------|------|------|----------|
| ブート | ブート | Boot | systemd-analyze |
| 起動順序 | きどうじゅんじょ | 启动顺序 | critical-chain |
| レスキューモード | レスキューモード | Rescue mode | rescue.target |
| 時刻同期 | じこくどうき | 时间同步 | timedatectl, chronyc |
| デフォルト | デフォルト | Default | get-default |

### 审计要求

在日本 IT 企业，时间同步对审计至关重要：

```
ISMS/PCI DSS 要求：
- 所有服务器时间必须同步
- NTP 源必须可追溯
- 时间偏差必须在容许范围内

检查项目：
□ timedatectl 显示 NTP service: active
□ chronyc tracking 显示 Leap status: Normal
□ 时间偏差 < 100ms
```

---

## 面试准备（Interview Prep）

### Q1: multi-user.target と graphical.target の違いは？

**回答要点**：

```
multi-user.target:
- CLI 環境（コマンドライン）
- サーバー向けの標準設定
- リソース消費が少ない
- SSH でアクセス

graphical.target:
- GUI 環境（デスクトップ）
- デスクトップ PC、ワークステーション向け
- Display Manager が起動
- より多くのリソースを使用

サーバーは multi-user.target が推奨。
```

### Q2: ブートが遅い時の調査方法は？

**回答要点**：

```
1. 全体時間の確認
   systemd-analyze
   → firmware, loader, kernel, initrd, userspace の各段階

2. 遅いサービスの特定
   systemd-analyze blame | head -10
   → 時間がかかるサービスをリストアップ

3. クリティカルパスの確認
   systemd-analyze critical-chain
   → ボトルネックになっているサービスを特定

4. 対策
   - 不要なサービスを無効化
   - 依存関係の最適化
   - タイムアウト設定の見直し
```

### Q3: 時刻同期が重要な理由は？

**回答要点**：

```
1. TLS/SSL
   - 証明書の有効期限チェックで時刻が必要
   - 時刻がずれると「証明書が無効」エラー

2. ログ分析
   - 複数サーバーのログを時系列で関連付け
   - インシデント調査で時刻一致が必須

3. 分散システム
   - Kubernetes, etcd などのコンセンサス
   - 時刻ずれで split-brain の可能性

4. 監査・コンプライアンス
   - ISMS, PCI DSS で正確な時刻記録が要求
```

---

## 检查清单

完成本课后，你应该能够：

- [ ] 解释 Target 是同步点，不运行进程
- [ ] 对应 SysV runlevel 到 systemd target（0=poweroff, 1=rescue, 3=multi-user, 5=graphical, 6=reboot）
- [ ] 使用 `get-default`/`set-default` 管理默认 target
- [ ] 使用 `isolate` 切换 target
- [ ] 描述 5 阶段启动流程（Firmware > Bootloader > Kernel > initramfs > systemd）
- [ ] 使用 `systemd-analyze` 分析启动性能
- [ ] 使用 `timedatectl` 和 `chronyc` 管理时间同步
- [ ] 使用 `lsinitrd` 和 `dracut` 管理 initramfs
- [ ] 使用救援模式和紧急模式排查问题
- [ ] 使用 `rd.break` 重置 root 密码
- [ ] 创建自定义 Target 管理应用栈

---

## 本课小结

| 概念 | 要点 |
|------|------|
| Target | 同步点，不运行进程，只是服务分组 |
| Runlevel 映射 | 0=poweroff, 1=rescue, 3=multi-user, 5=graphical, 6=reboot |
| 5 阶段启动 | Firmware > Bootloader > Kernel > initramfs > systemd |
| 启动分析 | systemd-analyze, blame, critical-chain |
| 时间同步 | timedatectl + chrony（现代首选） |
| 救援模式 | rescue.target（基本环境）, emergency.target（最小环境）, rd.break（initramfs shell） |

---

## 延伸阅读

- [systemd Targets 官方文档](https://www.freedesktop.org/software/systemd/man/systemd.target.html)
- [systemd-analyze 手册](https://www.freedesktop.org/software/systemd/man/systemd-analyze.html)
- [chrony 官方文档](https://chrony.tuxfamily.org/documentation.html)
- [dracut 手册](https://man7.org/linux/man-pages/man8/dracut.8.html)
- 上一课：[04 - 依赖与排序](../04-dependencies/) - 理解 systemd 依赖关系
- 下一课：[06 - Timer（现代 cron 替代）](../06-timers/) - 学习 systemd 定时任务

---

## 系列导航

[<-- 04 - 依赖与排序](../04-dependencies/) | [系列首页](../) | [06 - Timer -->](../06-timers/)
