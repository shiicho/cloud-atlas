# 03 - 服务故障：systemd 深度诊断（Service Failures: systemd Deep Diagnosis）

> **目标**：掌握 systemd 服务故障的系统性诊断方法，从状态检查到依赖分析  
> **前置**：LX05 systemd 基础、Lesson 01 故障排查方法论  
> **时间**：2 小时  
> **核心理念**：Active 不等于可用，依赖分析是关键  

---

## 将学到的内容

1. 使用 systemctl 和 journalctl 诊断服务故障
2. 理解和分析 systemd 依赖关系
3. 识别常见服务失败模式（配置错误、权限、依赖）
4. 使用 systemd-analyze 分析启动链
5. 诊断 Socket Activation 问题

---

## 先跑起来！（10 分钟）

> 服务出问题了？先运行这 4 条命令，立即看到问题所在。  

假设 nginx 服务不工作，这样快速诊断：

```bash
# 1. 查看服务状态（最重要的第一步）
systemctl status nginx

# 2. 查看最近错误日志
journalctl -u nginx -p err --since '1 hour ago'

# 3. 检查所有失败的服务
systemctl --failed

# 4. 检查端口是否真的在监听
ss -lntup | grep ':80\|:443'
```

**典型输出解读**：

```
# systemctl status nginx 可能显示：
● nginx.service - A high performance web server
     Loaded: loaded (/usr/lib/systemd/system/nginx.service; enabled)
     Active: failed (Result: exit-code) since Fri 2026-01-10 14:30:00 JST; 5min ago
    Process: 12345 ExecStart=/usr/sbin/nginx (code=exited, status=1/FAILURE)

# 关键信息：
# - Active: failed    → 服务启动失败
# - exit-code         → 程序返回了非零退出码
# - status=1/FAILURE  → 退出码是 1
```

**你刚刚用 4 条命令定位了服务问题的方向！**

现在让我们深入学习 systemd 服务诊断的完整方法。

---

## Step 1 -- 服务诊断命令详解（25 分钟）

### 1.1 systemctl status：服务状态全景

`systemctl status` 是诊断服务问题的第一步，它提供服务的完整状态快照。

```bash
# 基本用法
systemctl status nginx

# 显示更多日志行（默认 10 行）
systemctl status nginx -l -n 50
```

**输出解读**：

<!-- DIAGRAM: systemctl-status-anatomy -->
```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    systemctl status 输出解剖                                 │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ● nginx.service - A high performance web server                            │
│  │                 └──────── 服务描述（来自 unit file）                      │
│  │                                                                          │
│  │  Loaded: loaded (/usr/lib/systemd/system/nginx.service; enabled)        │
│  │          │       └─────────────── unit file 路径 ───────┘ │             │
│  │          │                                               │              │
│  │          └── 加载状态                          开机启动状态              │
│  │                                                                          │
│  │  Active: active (running) since Fri 2026-01-10 10:00:00 JST; 4h ago    │
│  │          │      └──────┘                                                 │
│  │          │      子状态                                                   │
│  │          └── 主状态                                                      │
│  │                                                                          │
│  │  Main PID: 1234 (nginx)                                                  │
│  │            └──── 主进程 PID                                              │
│  │                                                                          │
│  │  Tasks: 5 (limit: 4096)                                                  │
│  │  Memory: 12.0M                                                           │
│  │  CGroup: /system.slice/nginx.service                                     │
│  │          ├─1234 nginx: master process                                    │
│  │          └─1235 nginx: worker process                                    │
│  │                                                                          │
│  └── 最近日志（journalctl 摘录）                                             │
│                                                                             │
│  主状态可能值：                                                              │
│  • active     - 服务正在运行                                                │
│  • inactive   - 服务已停止                                                  │
│  • failed     - 服务启动失败                                                │
│  • activating - 正在启动中                                                  │
│  • deactivating - 正在停止中                                                │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```
<!-- /DIAGRAM -->

### 1.2 常见状态和退出码

| 状态 | 含义 | 下一步 |
|------|------|--------|
| `active (running)` | 服务正常运行 | 但要验证端口！ |
| `active (exited)` | 一次性服务，已执行完成 | 正常（如 oneshot 类型） |
| `inactive (dead)` | 服务未运行 | 检查是否应该运行 |
| `failed` | 启动失败 | 查看 journalctl 日志 |
| `activating (auto-restart)` | 正在重启 | 可能在循环崩溃 |

**常见退出码**：

| 退出码 | 含义 | 常见原因 |
|--------|------|----------|
| 0 | 成功 | 正常退出 |
| 1 | 通用错误 | 配置错误、权限问题 |
| 2 | 命令行参数错误 | ExecStart 参数有误 |
| 126 | 权限不足 | 无执行权限 |
| 127 | 命令未找到 | 路径错误或程序不存在 |
| 137 | SIGKILL (128+9) | OOM Killer 或手动 kill -9 |
| 143 | SIGTERM (128+15) | 正常终止信号 |

### 1.3 journalctl：深入日志分析

`journalctl` 是查看 systemd 服务日志的核心工具。

```bash
# 查看特定服务日志
journalctl -u nginx

# 只看错误及以上级别
journalctl -u nginx -p err

# 时间范围过滤
journalctl -u nginx --since '1 hour ago'
journalctl -u nginx --since '2026-01-10 14:00' --until '2026-01-10 15:00'

# 实时跟踪日志
journalctl -u nginx -f

# 本次启动以来的日志
journalctl -u nginx -b

# 输出为 JSON（脚本处理）
journalctl -u nginx -o json-pretty
```

**优先级级别**（-p 参数）：

| 级别 | 值 | 含义 |
|------|-----|------|
| emerg | 0 | 系统不可用 |
| alert | 1 | 必须立即处理 |
| crit | 2 | 严重错误 |
| err | 3 | 错误 |
| warning | 4 | 警告 |
| notice | 5 | 正常但重要 |
| info | 6 | 信息 |
| debug | 7 | 调试 |

```bash
# 只看 error 及以上（err, crit, alert, emerg）
journalctl -u nginx -p err

# 只看 warning 及以上
journalctl -u nginx -p warning
```

### 1.4 systemctl show：服务详细属性

`systemctl show` 显示服务的所有内部属性，用于深度诊断。

```bash
# 显示所有属性
systemctl show nginx

# 查看特定属性
systemctl show nginx -p MainPID,ExecMainStatus,ActiveState

# 常用属性
systemctl show nginx -p \
  MainPID,\
  ExecMainStatus,\
  ExecMainStartTimestamp,\
  ActiveState,\
  SubState,\
  Result,\
  NRestarts,\
  EnvironmentFiles
```

**关键属性说明**：

| 属性 | 含义 | 用途 |
|------|------|------|
| `MainPID` | 主进程 PID | 追踪进程状态 |
| `ExecMainStatus` | 主进程退出码 | 判断失败原因 |
| `Result` | 最近一次启动结果 | success/exit-code/signal 等 |
| `NRestarts` | 重启次数 | 判断是否在循环崩溃 |
| `EnvironmentFiles` | 环境变量文件 | 检查配置文件是否加载 |

---

## Step 2 -- 依赖分析：理解启动链（25 分钟）

### 2.1 为什么需要依赖分析？

服务不是孤立运行的。一个服务可能依赖：
- 网络（network.target）
- 其他服务（如数据库）
- 特定路径（如 /var/lib/mysql）
- 时间同步（time-sync.target）

如果依赖没有满足，服务可能：
- 启动失败
- 启动了但功能异常
- 启动顺序错误

### 2.2 systemctl list-dependencies

```bash
# 查看服务的依赖树
systemctl list-dependencies nginx

# 查看完整树（包括 target）
systemctl list-dependencies nginx --all

# 查看谁依赖这个服务（反向依赖）
systemctl list-dependencies nginx --reverse

# 查看启动前需要什么
systemctl list-dependencies nginx --before

# 查看启动后需要什么
systemctl list-dependencies nginx --after
```

**输出示例**：

```
nginx.service
● ├─system.slice
● ├─sysinit.target
● │ ├─dev-hugepages.mount
● │ ├─dev-mqueue.mount
● │ └─...
● └─network-online.target
●   └─NetworkManager-wait-online.service
```

### 2.3 依赖关系类型

systemd 有多种依赖关系，理解它们对诊断至关重要：

<!-- DIAGRAM: dependency-types -->
```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    systemd 依赖关系类型                                      │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │  Requires= (强依赖)                                                  │   │
│  │  ┌───────────────┐         ┌───────────────┐                        │   │
│  │  │   ServiceA    │ ──────▶ │   ServiceB    │                        │   │
│  │  │  (Requires)   │         │               │                        │   │
│  │  └───────────────┘         └───────────────┘                        │   │
│  │  如果 B 启动失败或停止，A 也会停止                                   │   │
│  │  最严格的依赖关系                                                    │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │  Wants= (弱依赖)                                                     │   │
│  │  ┌───────────────┐         ┌───────────────┐                        │   │
│  │  │   ServiceA    │ ─ ─ ─ ▶ │   ServiceB    │                        │   │
│  │  │   (Wants)     │         │               │                        │   │
│  │  └───────────────┘         └───────────────┘                        │   │
│  │  A 想要 B 一起启动，但 B 失败不影响 A                                │   │
│  │  推荐的默认依赖方式                                                  │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │  After= (顺序依赖)                                                   │   │
│  │  ┌───────────────┐         ┌───────────────┐                        │   │
│  │  │   ServiceA    │         │   ServiceB    │                        │   │
│  │  │   (After=B)   │  ◀────  │               │                        │   │
│  │  └───────────────┘         └───────────────┘                        │   │
│  │  只定义启动顺序（A 在 B 之后启动）                                   │   │
│  │  不会启动 B，只是"如果 B 要启动，先启动 B"                           │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
│  常见组合：                                                                 │
│  • Requires=B + After=B  →  必须等 B 启动成功后才启动 A                    │
│  • Wants=B + After=B     →  希望 B 先启动，但 B 失败不影响 A               │
│  • After=B (无 Requires/Wants) → 只是顺序，不会触发 B 启动                │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```
<!-- /DIAGRAM -->

### 2.4 systemd-analyze：启动链分析

```bash
# 查看系统启动时间
systemd-analyze

# 查看启动责备链（哪个服务最慢）
systemd-analyze blame

# 查看特定服务的启动链
systemd-analyze critical-chain nginx.service

# 绘制启动时序图（生成 SVG）
systemd-analyze plot > boot.svg
```

**critical-chain 输出解读**：

```bash
$ systemd-analyze critical-chain nginx.service
The time when unit became active or started is printed after the "@" character.
The time the unit took to start is printed after the "+" character.

nginx.service @12.456s +0.123s
└─network-online.target @12.345s
  └─NetworkManager-wait-online.service @2.123s +10.222s
    └─NetworkManager.service @1.890s +0.233s
      └─dbus.service @1.567s +0.323s
        └─basic.target @1.456s
          └─sockets.target @1.456s
```

**解读**：
- `@12.456s` = 服务在系统启动 12.456 秒后变为 active
- `+0.123s` = 服务本身启动耗时 0.123 秒
- 从下往上读：dbus → NetworkManager → wait-online → network-online → nginx

### 2.5 依赖问题诊断实例

**场景**：自定义应用服务启动失败

```bash
# 1. 查看服务状态
systemctl status myapp.service
# 显示 "Job for myapp.service failed because a dependency failed"

# 2. 查看依赖
systemctl list-dependencies myapp.service
# 发现依赖 postgresql.service

# 3. 检查 postgresql 状态
systemctl status postgresql.service
# 发现 postgresql 也是 failed

# 4. 查看 postgresql 日志
journalctl -u postgresql -p err
# 发现 "could not access directory: Permission denied"

# 5. 根因：postgresql 数据目录权限错误
# 修复后两个服务都能正常启动
```

---

## Step 3 -- 常见失败模式（25 分钟）

### 3.1 配置语法错误

最常见的失败原因。服务程序在启动时检测到配置文件有语法错误。

**诊断方法**：

```bash
# 查看日志中的配置错误
journalctl -u nginx -p err | grep -i 'config\|syntax\|parse'

# 使用服务自带的配置检查
nginx -t
httpd -t
named-checkconf
postfix check

# 如果没有检查工具，查看日志
journalctl -u myapp --since '5 min ago' | head -50
```

**常见错误消息**：
- `syntax error in /etc/nginx/nginx.conf`
- `configuration file test failed`
- `parse error near line XX`

### 3.2 EnvironmentFile 缺失

服务依赖的环境变量文件不存在或权限错误。

**诊断方法**：

```bash
# 查看服务的 EnvironmentFile 设置
systemctl cat myapp.service | grep -i environment

# 输出可能显示：
# EnvironmentFile=/etc/myapp/config
# EnvironmentFile=-/etc/myapp/optional.conf  # 前缀 - 表示可选

# 检查文件是否存在
ls -la /etc/myapp/config

# 检查文件权限
stat /etc/myapp/config
```

**错误消息示例**：
- `Failed to load environment files: No such file or directory`
- `myapp.service: Failed to read environment file`

**修复方法**：

```bash
# 创建缺失的配置文件
sudo touch /etc/myapp/config

# 或者修改 unit file 使其可选（添加 - 前缀）
sudo systemctl edit myapp.service
# 添加：
# [Service]
# EnvironmentFile=-/etc/myapp/config
```

### 3.3 权限问题（EACCES）

服务进程无法访问所需的文件或目录。

**诊断方法**：

```bash
# 日志中查找权限错误
journalctl -u nginx -p err | grep -i 'permission\|denied\|eacces'

# 检查关键目录权限
ls -la /var/log/nginx/
ls -la /var/lib/nginx/
ls -la /run/nginx/

# 检查服务运行的用户
systemctl show nginx -p User,Group
```

**常见场景**：
- 日志目录权限不正确
- PID 文件目录不存在
- 配置文件权限过严
- Socket 文件权限问题

**修复方法**：

```bash
# 修复目录权限
sudo chown -R nginx:nginx /var/log/nginx
sudo chmod 755 /var/log/nginx

# 创建缺失的运行时目录
sudo mkdir -p /run/nginx
sudo chown nginx:nginx /run/nginx
```

### 3.4 SELinux 阻止

在 RHEL/CentOS 系统上，SELinux 可能阻止服务访问资源，即使 DAC（传统权限）允许。

**诊断方法**：

```bash
# 检查 SELinux 状态
getenforce

# 查看最近的 SELinux 拒绝
ausearch -m AVC -ts recent

# 或使用 audit2why 分析
ausearch -m AVC -ts recent | audit2why

# 查看文件的 SELinux 上下文
ls -Z /var/www/html/
```

**常见场景**：
- 文件从其他位置移动（保留了原上下文）
- 非标准端口
- 自定义目录路径

**修复方法**：

```bash
# 恢复默认上下文
sudo restorecon -Rv /var/www/html/

# 如果是自定义路径，设置正确上下文
sudo semanage fcontext -a -t httpd_sys_content_t "/custom/path(/.*)?"
sudo restorecon -Rv /custom/path/

# 允许非标准端口
sudo semanage port -a -t http_port_t -p tcp 8080

# 临时关闭 SELinux（仅用于确认问题，不推荐生产使用）
sudo setenforce 0
# 测试服务
sudo setenforce 1
```

### 3.5 资源限制（OOM、Timeout）

服务因系统资源限制而失败。

**OOM Killer 诊断**：

```bash
# 检查内核日志
dmesg | grep -i 'oom\|killed'

# 或通过 journalctl
journalctl -k | grep -i 'oom\|killed'

# 查看服务的内存限制
systemctl show nginx -p MemoryLimit,MemoryHigh,MemoryMax
```

**Timeout 诊断**：

```bash
# 查看服务的超时设置
systemctl show nginx -p TimeoutStartSec,TimeoutStopSec

# 日志中查找超时
journalctl -u nginx | grep -i 'timeout'

# 常见消息：
# "nginx.service: Start operation timed out. Terminating."
```

**修复方法**：

```bash
# 增加启动超时（通过 drop-in 文件）
sudo systemctl edit nginx.service

# 添加：
[Service]
TimeoutStartSec=120

# 调整内存限制
[Service]
MemoryMax=2G
```

### 3.6 失败模式速查表

<!-- DIAGRAM: failure-modes-table -->
```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    服务失败模式速查表                                        │
├────────────────┬─────────────────────────┬──────────────────────────────────┤
│ 失败模式       │ 诊断命令                │ 常见修复                         │
├────────────────┼─────────────────────────┼──────────────────────────────────┤
│ 配置语法错误   │ journalctl -u <svc>     │ 检查配置文件语法                 │
│                │ <service> -t (configtest)│ nginx -t, httpd -t 等           │
├────────────────┼─────────────────────────┼──────────────────────────────────┤
│ EnvironmentFile│ systemctl cat <svc>     │ 创建文件或添加 - 前缀           │
│ 缺失           │ ls -la <envfile>        │                                  │
├────────────────┼─────────────────────────┼──────────────────────────────────┤
│ 权限问题       │ journalctl | grep deny  │ chown/chmod 修复权限            │
│ (EACCES)       │ ls -la <path>           │ 检查 User=/Group= 设置          │
├────────────────┼─────────────────────────┼──────────────────────────────────┤
│ SELinux 阻止   │ ausearch -m AVC         │ restorecon -Rv <path>           │
│                │ audit2why               │ semanage fcontext               │
├────────────────┼─────────────────────────┼──────────────────────────────────┤
│ OOM Killer     │ dmesg | grep oom        │ 增加内存或设置 MemoryMax=       │
│                │ journalctl -k | grep oom│                                  │
├────────────────┼─────────────────────────┼──────────────────────────────────┤
│ 启动超时       │ journalctl | grep time  │ 增加 TimeoutStartSec=           │
│                │ systemctl show -p Time  │                                  │
├────────────────┼─────────────────────────┼──────────────────────────────────┤
│ 依赖失败       │ systemctl list-dependen │ 检查依赖服务状态                │
│                │ systemctl status <dep>  │                                  │
├────────────────┼─────────────────────────┼──────────────────────────────────┤
│ 端口占用       │ ss -lntup | grep <port> │ 停止占用进程或更换端口          │
│                │                         │                                  │
└────────────────┴─────────────────────────┴──────────────────────────────────┘
```
<!-- /DIAGRAM -->

---

## Step 4 -- Socket Activation 问题（15 分钟）

### 4.1 什么是 Socket Activation？

Socket Activation 是 systemd 的一个特性：由 systemd 先监听端口，当有连接请求时再启动实际服务。

**优点**：
- 减少启动时的资源消耗
- 服务按需启动
- 支持服务热重启

**常见使用场景**：
- sshd.socket (SSH 服务)
- cups.socket (打印服务)
- cockpit.socket (Web 管理界面)

### 4.2 Socket Activation 结构

<!-- DIAGRAM: socket-activation -->
```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    Socket Activation 工作原理                                │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│   传统模式：                                                                │
│   ┌─────────────┐      ┌─────────────┐                                     │
│   │   systemd   │ ───▶ │   sshd      │ ───▶ 监听 22 端口                   │
│   │             │      │   (服务)    │                                     │
│   └─────────────┘      └─────────────┘                                     │
│                                                                             │
│   Socket Activation：                                                       │
│   ┌─────────────┐      ┌─────────────┐                                     │
│   │   systemd   │ ───▶ │ sshd.socket │ ───▶ 监听 22 端口                   │
│   │             │      └─────────────┘                                     │
│   │             │             │                                             │
│   │             │             │ 连接请求到达                                │
│   │             │             ▼                                             │
│   │             │      ┌─────────────┐                                     │
│   │             │ ───▶ │ sshd.service│ ───▶ 处理连接                       │
│   │             │      │ (按需启动)  │                                     │
│   └─────────────┘      └─────────────┘                                     │
│                                                                             │
│   文件对应：                                                                │
│   • sshd.socket    - 定义监听的端口/socket                                 │
│   • sshd.service   - 定义实际服务                                          │
│   • sshd@.service  - 模板服务（用于多实例）                                │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```
<!-- /DIAGRAM -->

### 4.3 诊断 Socket Activation 问题

**问题场景**：服务显示 active，但端口不监听

```bash
# 1. 检查服务状态
systemctl status sshd.service
# 显示 inactive (dead) - 正常！因为是 socket activation

# 2. 检查 socket 状态
systemctl status sshd.socket
# 应该显示 active (listening)

# 3. 验证端口监听
ss -lntup | grep ':22'
# 应该看到 systemd 在监听

# 4. 如果端口没有监听
systemctl is-enabled sshd.socket
systemctl start sshd.socket
```

**常见问题**：

| 症状 | 原因 | 修复 |
|------|------|------|
| 端口不监听 | socket 未启动 | `systemctl start <name>.socket` |
| 服务启动后立即停止 | socket 和 service 冲突 | 停止 service，只启用 socket |
| 连接被拒绝 | socket 配置错误 | 检查 .socket 文件中的 ListenStream= |

### 4.4 检查 Socket 配置

```bash
# 查看 socket unit 内容
systemctl cat sshd.socket

# 输出示例：
# [Socket]
# ListenStream=22
# Accept=no
#
# [Install]
# WantedBy=sockets.target

# 查看所有 socket
systemctl list-sockets

# 查看 socket 和对应服务的关系
systemctl list-sockets --show-types
```

---

## Step 5 -- 服务诊断决策树（10 分钟）

### 5.1 完整决策树

<!-- DIAGRAM: service-decision-tree -->
```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    服务故障诊断决策树                                        │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│                         服务不可用                                          │
│                            │                                                │
│                            ▼                                                │
│               ┌────────────────────────┐                                   │
│               │   systemctl status     │                                   │
│               │   查看主状态           │                                   │
│               └───────────┬────────────┘                                   │
│                           │                                                 │
│        ┌──────────────────┼──────────────────┐                             │
│        │                  │                  │                              │
│        ▼                  ▼                  ▼                              │
│   ┌─────────┐       ┌─────────┐        ┌─────────┐                         │
│   │ failed  │       │inactive │        │ active  │                         │
│   └────┬────┘       └────┬────┘        └────┬────┘                         │
│        │                 │                  │                               │
│        ▼                 ▼                  ▼                               │
│   ┌──────────────┐ ┌──────────────┐  ┌──────────────┐                      │
│   │journalctl -u │ │是 socket     │  │ss -lntup     │                      │
│   │<svc> -p err  │ │activation?   │  │检查端口监听  │                      │
│   └──────┬───────┘ └──────┬───────┘  └──────┬───────┘                      │
│          │                │                  │                              │
│          ▼                ▼                  ▼                              │
│   ┌─────────────────────────────────────────────────────────────────────┐  │
│   │ 根据错误类型分支：                                                    │  │
│   │                                                                      │  │
│   │ "config error"     →  检查配置语法 (nginx -t 等)                    │  │
│   │ "permission denied" →  检查文件权限 + SELinux (ls -Z, ausearch)     │  │
│   │ "No such file"      →  检查 EnvironmentFile 和路径                  │  │
│   │ "dependency failed" →  systemctl list-dependencies                  │  │
│   │ "timeout"           →  增加 TimeoutStartSec                         │  │
│   │ "oom"              →  检查内存，调整 MemoryMax                       │  │
│   │ "端口已占用"        →  ss -lntup | grep <port>                      │  │
│   │                                                                      │  │
│   │ 端口不监听但 active →  检查 socket activation                       │  │
│   │                       systemctl status <name>.socket                │  │
│   └─────────────────────────────────────────────────────────────────────┘  │
│                                                                             │
│   关键提醒：                                                                │
│   • Active 不等于可用 - 一定要验证端口！                                   │
│   • 检查依赖服务状态 - 问题可能在上游                                      │
│   • 查看完整日志 - journalctl -u <svc> -n 100                             │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```
<!-- /DIAGRAM -->

### 5.2 快速诊断命令组合

```bash
# 完整诊断脚本（保存为 diagnose-service.sh）
#!/bin/bash
SERVICE=${1:-nginx}

echo "=== Diagnosing $SERVICE ==="
echo ""

echo "[1] Service Status:"
systemctl status "$SERVICE" --no-pager -l

echo ""
echo "[2] Recent Errors:"
journalctl -u "$SERVICE" -p err --since '1 hour ago' --no-pager | tail -20

echo ""
echo "[3] Dependencies:"
systemctl list-dependencies "$SERVICE" --no-pager | head -15

echo ""
echo "[4] Properties:"
systemctl show "$SERVICE" -p MainPID,ExecMainStatus,ActiveState,SubState,Result,NRestarts

echo ""
echo "[5] Listening Ports (if applicable):"
ss -lntup 2>/dev/null | grep -E "$(systemctl show -p MainPID "$SERVICE" --value)" || echo "No ports found for this service"

echo ""
echo "[6] Related Socket (if any):"
SOCKET="${SERVICE%.service}.socket"
systemctl status "$SOCKET" --no-pager 2>/dev/null || echo "No associated socket unit"
```

---

## 动手实验（30 分钟）

### 实验 1：依赖地狱场景（The Dependency Nightmare）

**场景描述**：
你有一个 Web 应用服务 `webapp.service`，它依赖 `redis.service`。
用户报告 Web 应用无法访问，但 `systemctl status webapp` 显示 `active (running)`。

**模拟步骤**：

```bash
# 1. 创建一个模拟的依赖服务（故意让它失败）
sudo tee /etc/systemd/system/fake-redis.service << 'EOF'
[Unit]
Description=Fake Redis Service (for testing)

[Service]
Type=oneshot
ExecStart=/bin/false
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

# 2. 创建依赖 fake-redis 的应用服务
sudo tee /etc/systemd/system/test-webapp.service << 'EOF'
[Unit]
Description=Test Web Application
Requires=fake-redis.service
After=fake-redis.service

[Service]
Type=simple
ExecStart=/usr/bin/python3 -m http.server 8080
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

# 3. 重载 systemd
sudo systemctl daemon-reload

# 4. 尝试启动 webapp
sudo systemctl start test-webapp.service

# 5. 诊断问题
```

**诊断练习**：

```bash
# 检查服务状态
systemctl status test-webapp.service

# 查看依赖
systemctl list-dependencies test-webapp.service

# 检查依赖服务
systemctl status fake-redis.service

# 查看日志
journalctl -u test-webapp.service -p err --since '5 min ago'
journalctl -u fake-redis.service -p err --since '5 min ago'
```

**问题**：
1. 为什么 webapp 启动失败？
2. 如何修复 fake-redis 服务？
3. 如果 webapp 必须运行，即使 redis 不可用，应该如何修改配置？

<details>
<summary>点击查看答案</summary>

1. **原因**：webapp 使用 `Requires=fake-redis.service`，而 fake-redis 启动失败（ExecStart=/bin/false 返回非零）。强依赖失败导致 webapp 也无法启动。

2. **修复 fake-redis**：
```bash
# 修改为成功的命令
sudo sed -i 's|ExecStart=/bin/false|ExecStart=/bin/true|' /etc/systemd/system/fake-redis.service
sudo systemctl daemon-reload
sudo systemctl start fake-redis.service
sudo systemctl start test-webapp.service
```

3. **允许 webapp 独立运行**：
```bash
# 将 Requires 改为 Wants
sudo sed -i 's|Requires=fake-redis|Wants=fake-redis|' /etc/systemd/system/test-webapp.service
sudo systemctl daemon-reload
# 现在即使 fake-redis 失败，webapp 也能启动
```

</details>

**清理**：

```bash
sudo systemctl stop test-webapp.service fake-redis.service
sudo systemctl disable test-webapp.service fake-redis.service
sudo rm /etc/systemd/system/test-webapp.service /etc/systemd/system/fake-redis.service
sudo systemctl daemon-reload
```

### 实验 2：EnvironmentFile 缺失场景

**场景描述**：
一个服务 `myapp.service` 依赖环境变量文件 `/etc/myapp/config`，但文件不存在。

**模拟步骤**：

```bash
# 1. 创建测试服务
sudo tee /etc/systemd/system/envtest.service << 'EOF'
[Unit]
Description=Environment File Test Service

[Service]
Type=simple
EnvironmentFile=/etc/envtest/config
ExecStart=/bin/bash -c 'echo "APP_NAME=$APP_NAME, APP_PORT=$APP_PORT"; sleep infinity'

[Install]
WantedBy=multi-user.target
EOF

# 2. 重载并尝试启动
sudo systemctl daemon-reload
sudo systemctl start envtest.service

# 3. 检查状态
systemctl status envtest.service
```

**诊断练习**：

```bash
# 查看错误
journalctl -u envtest.service -p err

# 查看服务配置
systemctl cat envtest.service

# 检查文件是否存在
ls -la /etc/envtest/config
```

**修复步骤**：

```bash
# 创建配置目录和文件
sudo mkdir -p /etc/envtest
sudo tee /etc/envtest/config << 'EOF'
APP_NAME=MyTestApp
APP_PORT=8080
EOF

# 重新启动
sudo systemctl start envtest.service
systemctl status envtest.service

# 验证环境变量被读取
journalctl -u envtest.service | tail -5
```

**清理**：

```bash
sudo systemctl stop envtest.service
sudo systemctl disable envtest.service
sudo rm /etc/systemd/system/envtest.service
sudo rm -rf /etc/envtest
sudo systemctl daemon-reload
```

---

## 日本 IT 职场：サービス障害対応（15 分钟）

### 职场场景

在日本 IT 企业，服务故障通常通过监控系统（運用監視）首先发现。

**典型流程**：

```
監視アラート発報 → 一次対応 → 原因調査 → 恒久対策 → 報告書作成
   (Alert)       (First Response) (Investigation) (Permanent Fix) (Report)
```

### 核心日语术语

| 日语 | 读音 | 含义 | 例句 |
|------|------|------|------|
| **サービス起動失敗** | saabisu kidou shippai | 服务启动失败 | 「サービス起動失敗のアラートです」 |
| **依存関係** | izon kankei | 依赖关系 | 「依存関係を確認してください」 |
| **設定ファイル** | settei fairu | 配置文件 | 「設定ファイルの構文エラーです」 |
| **権限エラー** | kengen eraa | 权限错误 | 「権限エラーで起動できません」 |
| **再起動** | saikidou | 重启 | 「サービスを再起動します」 |
| **切り戻し** | kirimodoshi | 回滚 | 「変更を切り戻しました」 |

### 报告模板：サービス障害

```markdown
## サービス障害報告

### 概要
- 発生日時: 2026-01-10 14:30 (JST)
- 対象サービス: nginx.service
- 影響: Web サイトアクセス不可

### 障害内容
nginx サービスが起動失敗。
ステータス: failed (Result: exit-code)

### 原因
設定ファイル /etc/nginx/nginx.conf の構文エラー。
Line 45: 閉じブラケット不足。

### 対応内容
1. nginx -t で構文チェック実施
2. 構文エラーを修正
3. systemctl restart nginx で再起動
4. ss -lntup で Port 80/443 の Listen 確認

### 再発防止
- 設定変更時は必ず nginx -t を実行
- 変更手順書にチェック項目を追加
```

---

## 检查清单

完成本课后，你应该能够：

- [ ] 使用 `systemctl status` 解读服务状态的所有字段
- [ ] 使用 `journalctl -u <service> -p err` 过滤服务错误日志
- [ ] 解释 `Requires` vs `Wants` vs `After` 的区别
- [ ] 使用 `systemctl list-dependencies` 分析服务依赖
- [ ] 使用 `systemd-analyze critical-chain` 分析启动链
- [ ] 诊断常见失败模式：配置错误、权限问题、SELinux、EnvironmentFile
- [ ] 理解 Socket Activation 并诊断相关问题
- [ ] 验证服务真正可用（端口监听检查）
- [ ] 使用决策树系统性诊断服务问题

---

## 本课小结

| 概念 | 要点 |
|------|------|
| 服务状态检查 | `systemctl status` + `journalctl -u` 是第一步 |
| Active != 可用 | 一定要用 `ss -lntup` 验证端口监听 |
| 依赖分析 | `list-dependencies` + `critical-chain` |
| 依赖类型 | Requires(强) > Wants(弱) > After(仅顺序) |
| 常见失败 | 配置语法、权限、SELinux、EnvironmentFile、依赖 |
| Socket Activation | 服务 inactive 可能是正常的，检查 .socket |
| 退出码 | 0=成功, 1=通用错误, 137=OOM, 143=正常终止 |

**核心理念**：

> Active 不等于可用，依赖分析是关键。  
> 先看日志，再查依赖，最后验证端口。  

---

## 面试准备

### よくある質問（常见问题）

**Q: サービスが起動しない場合、どのように診断しますか？**

A: 以下のステップで診断します：
1. `systemctl status <service>` でステータス確認
2. `journalctl -u <service> -p err` でエラーログ確認
3. エラー内容に応じて対応：
   - 設定エラー → 設定ファイルの構文チェック
   - 権限エラー → ファイル権限と SELinux 確認
   - 依存エラー → `systemctl list-dependencies` で依存確認
4. `ss -lntup` でポート Listen 確認

**Q: systemd の依存関係について説明してください。**

A: 主な依存関係は 3 種類あります：
- **Requires**: 強い依存。依存先が失敗すると自分も停止
- **Wants**: 弱い依存。依存先が失敗しても自分は起動
- **After**: 順序のみ。依存先の起動を待つが、起動はトリガーしない

一般的には `Wants=B After=B` の組み合わせを推奨します。

**Q: サービスが active なのにアクセスできない場合は？**

A: 以下を確認します：
1. `ss -lntup` でポートが Listen しているか
2. Socket Activation の場合、`.socket` ユニットの状態
3. ファイアウォール（`firewall-cmd --list-all`）
4. SELinux（`ausearch -m AVC -ts recent`）

Active でも実際にポートを開いていない場合があります。必ず `ss` で確認します。

---

## トラブルシューティング（本課自体の問題解決）

### systemctl cat が動かない

```bash
# 古い systemd バージョンでは cat がない場合
cat /usr/lib/systemd/system/<service>.service
# または
cat /etc/systemd/system/<service>.service
```

### audit2why コマンドが見つからない

```bash
# RHEL/CentOS
sudo yum install policycoreutils-python-utils

# Fedora
sudo dnf install policycoreutils-python-utils
```

### systemd-analyze が使えない

```bash
# インストール確認
rpm -q systemd
# または
dpkg -l systemd

# バージョン確認（古いバージョンでは機能が限られる）
systemd --version
```

---

## 延伸阅读

- [systemd Service Unit Documentation](https://www.freedesktop.org/software/systemd/man/systemd.service.html)
- [systemd Directives Index](https://www.freedesktop.org/software/systemd/man/systemd.directives.html)
- [Red Hat - Working with systemd Unit Files](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/9/html/configuring_basic_system_settings/working-with-systemd-unit-files_configuring-basic-system-settings)
- 上一课：[02 - 启动故障](../02-boot-issues/) -- GRUB、initramfs、紧急模式
- 下一课：[04 - 网络问题](../04-network-problems/) -- 分层诊断

---

## 系列导航

[<-- 02 - 启动故障](../02-boot-issues/) | [系列首页](../) | [04 - 网络问题 -->](../04-network-problems/)
