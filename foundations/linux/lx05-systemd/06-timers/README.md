# 06 - Timer（现代 cron 替代）

> **目标**：掌握 systemd Timer，学会从 cron 迁移到更强大的定时任务管理  
> **前置**：已完成 [03 - Unit 文件解剖](../03-unit-files/) 和 [04 - 依赖与排序](../04-dependencies/)  
> **时间**：45-60 分钟  
> **实战场景**：夜間バッチ（Overnight Batch）-- 确保 03:00 的备份任务可靠执行  

---

## 将学到的内容

1. 理解 Timer 相比 cron 的优势
2. 掌握 OnCalendar 日历表达式语法
3. 使用 Monotonic timers（OnBootSec, OnUnitActiveSec）
4. 配置 Persistent=true 捕获错过的运行
5. 从 cron 迁移到 Timer

---

## 先跑起来！（5 分钟）

> 在深入理论之前，先创建一个每分钟运行的 Timer，看看它是如何工作的。  

### 创建一个简单的 Timer

```bash
# 创建一个简单的服务（Timer 触发的任务）
sudo tee /etc/systemd/system/hello-timer.service << 'EOF'
[Unit]
Description=Hello Timer Demo Service

[Service]
Type=oneshot
ExecStart=/bin/echo "Hello from timer at $(date)"
EOF

# 创建配套的 Timer
sudo tee /etc/systemd/system/hello-timer.timer << 'EOF'
[Unit]
Description=Hello Timer Demo

[Timer]
OnCalendar=*:*:00
AccuracySec=1s

[Install]
WantedBy=timers.target
EOF

# 重新加载并启动 Timer
sudo systemctl daemon-reload
sudo systemctl enable --now hello-timer.timer
```

### 观察 Timer 运行

```bash
# 查看所有活动的 Timer
systemctl list-timers --all

# 查看我们的 Timer 状态
systemctl status hello-timer.timer

# 实时查看日志（每分钟会有新输出）
sudo journalctl -u hello-timer.service -f
```

**你应该看到**：
- `list-timers` 显示下次触发时间
- 每分钟的 00 秒，服务会执行一次
- 日志中记录了每次执行的时间

**恭喜！** 你刚刚创建了第一个 systemd Timer。接下来，让我们了解它为什么比 cron 更强大。

---

## Step 1 -- Timer vs Cron：为什么要迁移（10 分钟）

### 1.1 Cron 的痛点

在使用 cron 多年后，运维工程师们发现了这些问题：

| 问题 | Cron 的表现 | 带来的麻烦 |
|------|-------------|------------|
| 日志分散 | 输出到 mail 或需要手动重定向 | 排查问题困难 |
| 错过的任务 | 系统宕机期间的任务直接丢失 | 关键备份可能未执行 |
| 没有依赖管理 | 无法指定"数据库启动后再运行" | 任务可能因依赖未就绪而失败 |
| 无资源控制 | 批处理可能耗尽系统资源 | 影响生产服务 |
| 调试困难 | 手动测试需要修改时间或等待 | 开发效率低 |

### 1.2 Timer 的优势

![Timer Advantages](images/timer-advantages.png)

<details>
<summary>View ASCII source</summary>

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    systemd Timer 优势                                    │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  1. 集成日志                                                             │
│     ┌─────────────┐        ┌──────────────┐                             │
│     │ Timer 触发   │───────►│  journalctl  │ ◄── 统一查看日志            │
│     │ 服务执行     │        │  -u backup   │                             │
│     └─────────────┘        └──────────────┘                             │
│                                                                          │
│  2. Persistent=true 捕获错过的运行                                       │
│     ┌─────────────────────────────────────────────────────────────┐     │
│     │  计划: 03:00 执行备份                                        │     │
│     │  实际: 02:00-04:00 系统宕机                                  │     │
│     │  结果: 04:00 系统启动后立即补执行！                          │     │
│     └─────────────────────────────────────────────────────────────┘     │
│                                                                          │
│  3. 依赖管理                                                             │
│     After=postgresql.service  ── 数据库启动后再执行                      │
│     Wants=network-online.target ── 确保网络就绪                          │
│                                                                          │
│  4. 资源控制                                                             │
│     MemoryMax=2G  ── 防止批处理耗尽内存                                  │
│     CPUQuota=50%  ── 限制 CPU 使用                                       │
│                                                                          │
│  5. 即时测试                                                             │
│     systemctl start backup.service  ── 立即手动触发                      │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

</details>

### 1.3 功能对比表

| 功能 | cron | systemd Timer |
|------|------|---------------|
| 日志 | 需手动配置 | journalctl -u 直接查看 |
| 错过的任务 | 丢失 | Persistent=true 补运行 |
| 依赖管理 | 无 | After=, Wants= |
| 资源限制 | 无 | MemoryMax, CPUQuota |
| 随机延迟 | 无（自己写 sleep） | RandomizedDelaySec |
| 手动触发 | 复制命令执行 | systemctl start |
| 状态查看 | 无 | systemctl list-timers |
| 下次运行时间 | 需要计算 | NEXT 列直接显示 |

> **关键点**：Timer 不是"替代" cron，而是**更强大**的定时任务解决方案。  

---

## Step 2 -- Timer 的两种类型（10 分钟）

### 2.1 两种计时方式

![Timer Types](images/timer-types.png)

<details>
<summary>View ASCII source</summary>

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    systemd Timer 两种类型                                │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  类型 1: Realtime Timer（日历时间）                                      │
│  ─────────────────────────────────                                       │
│                                                                          │
│    OnCalendar=*-*-* 03:00:00    ← 每天凌晨 3 点                         │
│    OnCalendar=Mon..Fri *-*-* 09:00:00  ← 工作日 9 点                    │
│    OnCalendar=*-*-1 00:00:00    ← 每月 1 号                              │
│                                                                          │
│    适用：必须在特定时间执行（备份、报告、日志轮转）                      │
│                                                                          │
│  ─────────────────────────────────────────────────────────────────────  │
│                                                                          │
│  类型 2: Monotonic Timer（单调时间/间隔）                                │
│  ────────────────────────────────────────                                │
│                                                                          │
│    OnBootSec=5min        ← 启动后 5 分钟                                 │
│    OnUnitActiveSec=1h    ← 上次运行后 1 小时                             │
│    OnStartupSec=10min    ← systemd 启动后 10 分钟                        │
│                                                                          │
│    适用：周期性任务（健康检查、缓存清理、状态同步）                      │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

</details>

### 2.2 Realtime Timer（OnCalendar）

基于日历时间，在特定时刻触发：

```ini
[Timer]
# 每天凌晨 3 点
OnCalendar=*-*-* 03:00:00

# 等价的简写形式
OnCalendar=daily               # 每天 00:00
OnCalendar=weekly              # 每周一 00:00
OnCalendar=monthly             # 每月 1 号 00:00
```

**适用场景**：
- 数据库备份（夜間バッチ）
- 日志轮转
- 报告生成
- 定时同步

### 2.3 Monotonic Timer（OnBootSec, OnUnitActiveSec）

基于时间间隔，相对于某个事件触发：

```ini
[Timer]
# 系统启动后 5 分钟执行
OnBootSec=5min

# 上次执行后 1 小时再执行
OnUnitActiveSec=1h

# 组合使用：启动后 5 分钟，之后每小时
OnBootSec=5min
OnUnitActiveSec=1h
```

**Monotonic Timer 参考点**：

| 指令 | 参考点 | 典型用途 |
|------|--------|----------|
| `OnBootSec=` | 系统启动时间 | 启动后初始化任务 |
| `OnStartupSec=` | systemd 启动时间 | 用户会话任务 |
| `OnUnitActiveSec=` | Timer 激活时间 | 首次执行 |
| `OnUnitInactiveSec=` | Timer 停止后时间 | 服务停止后清理 |

### 2.4 如何选择

| 需求 | 选择 | 示例 |
|------|------|------|
| 每天固定时间执行 | OnCalendar | 备份、报告 |
| 每隔 N 时间执行 | OnUnitActiveSec | 健康检查、监控 |
| 启动后延迟执行 | OnBootSec | 初始化、预热 |
| 固定时间 + 周期 | OnCalendar + OnUnitActiveSec | 少见，但支持 |

---

## Step 3 -- OnCalendar 语法详解（15 分钟）

### 3.1 完整语法格式

```
DayOfWeek Year-Month-Day Hour:Minute:Second
```

### 3.2 常用表达式速查表

```bash
# 时间简写
OnCalendar=minutely           # 每分钟
OnCalendar=hourly             # 每小时整点
OnCalendar=daily              # 每天 00:00
OnCalendar=weekly             # 每周一 00:00
OnCalendar=monthly            # 每月 1 号 00:00
OnCalendar=yearly             # 每年 1 月 1 号 00:00
OnCalendar=quarterly          # 每季度第一天

# 指定时间
OnCalendar=*-*-* 03:00:00     # 每天 03:00
OnCalendar=*-*-* 09:30:00     # 每天 09:30
OnCalendar=*-*-* *:00:00      # 每小时整点
OnCalendar=*-*-* *:*:00       # 每分钟

# 指定星期
OnCalendar=Mon *-*-* 09:00:00         # 每周一 09:00
OnCalendar=Mon..Fri *-*-* 09:00:00    # 周一到周五 09:00
OnCalendar=Sat,Sun *-*-* 10:00:00     # 周末 10:00

# 指定日期
OnCalendar=*-*-1 00:00:00     # 每月 1 号
OnCalendar=*-*-15 12:00:00    # 每月 15 号中午
OnCalendar=*-1-1 00:00:00     # 每年 1 月 1 号
OnCalendar=*-*-1,15 00:00:00  # 每月 1 号和 15 号

# 间隔表达式
OnCalendar=*:0/15             # 每 15 分钟（00, 15, 30, 45）
OnCalendar=*:0/30             # 每 30 分钟（00, 30）
OnCalendar=0/2:00             # 每 2 小时整点（00:00, 02:00, ...）
```

### 3.3 验证表达式：systemd-analyze calendar

**这是最重要的工具！** 在生产环境部署前，务必验证你的表达式。

```bash
# 验证表达式并显示下次运行时间
systemd-analyze calendar "Mon..Fri *-*-* 09:00:00"

# 显示接下来 5 次运行时间
systemd-analyze calendar --iterations=5 "daily"

# 验证复杂表达式
systemd-analyze calendar --iterations=10 "*-*-1,15 03:00:00"
```

**示例输出**：

```
$ systemd-analyze calendar --iterations=5 "Mon..Fri *-*-* 09:00:00"
  Original form: Mon..Fri *-*-* 09:00:00
Normalized form: Mon..Fri *-*-* 09:00:00
    Next elapse: Mon 2026-01-06 09:00:00 JST
       (in UTC): Mon 2026-01-06 00:00:00 UTC
       From now: 1 day 14h left
       Iter. #1: Mon 2026-01-06 09:00:00 JST
       Iter. #2: Tue 2026-01-07 09:00:00 JST
       Iter. #3: Wed 2026-01-08 09:00:00 JST
       Iter. #4: Thu 2026-01-09 09:00:00 JST
       Iter. #5: Fri 2026-01-10 09:00:00 JST
```

### 3.4 常见错误

```bash
# 错误：秒数缺失（会报错）
OnCalendar=*-*-* 03:00
# 正确
OnCalendar=*-*-* 03:00:00

# 错误：星期格式（全称不行）
OnCalendar=Monday *-*-* 09:00:00
# 正确（使用三字母缩写）
OnCalendar=Mon *-*-* 09:00:00

# 错误：空格位置
OnCalendar=Mon..Fri*-*-*09:00:00
# 正确（星期和日期之间有空格）
OnCalendar=Mon..Fri *-*-* 09:00:00
```

---

## Step 4 -- Timer 关键配置选项（10 分钟）

### 4.1 Persistent=true（必须掌握！）

**场景**：备份任务设定在每天 03:00 执行。服务器在 02:00-05:00 因维护重启。

| 配置 | 结果 |
|------|------|
| `Persistent=false`（默认） | 03:00 的任务丢失，当天没有备份 |
| `Persistent=true` | 05:00 服务器启动后立即补执行 |

```ini
[Timer]
OnCalendar=*-*-* 03:00:00
Persistent=true    # 系统恢复后补执行错过的任务
```

> **重要**：对于关键任务（备份、报告、合规检查），**必须设置 Persistent=true**。  

### 4.2 RandomizedDelaySec（防止雷群效应）

**场景**：100 台服务器都在 03:00:00 同时执行备份，NFS 存储瞬间过载。

```ini
[Timer]
OnCalendar=*-*-* 03:00:00
RandomizedDelaySec=30min    # 在 03:00 - 03:30 之间随机延迟
```

![Thundering Herd Prevention](images/randomized-delay.png)

<details>
<summary>View ASCII source</summary>

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    RandomizedDelaySec 雷群效应防护                       │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  没有 RandomizedDelaySec:                                                │
│                                                                          │
│    03:00:00  ████████████████████████████████  100 台服务器同时执行      │
│              ▲                                                           │
│              └── NFS 存储瞬间过载！                                      │
│                                                                          │
│  ─────────────────────────────────────────────────────────────────────  │
│                                                                          │
│  有 RandomizedDelaySec=30min:                                            │
│                                                                          │
│    03:00  ████                                                           │
│    03:05  ██████                                                         │
│    03:10  ████                                                           │
│    03:15  ████████                                                       │
│    03:20  ██████                                                         │
│    03:25  ████                                                           │
│    03:30  ██████                                                         │
│              ▲                                                           │
│              └── 负载均匀分布，存储正常                                  │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

</details>

### 4.3 AccuracySec（计时器合并）

systemd 默认会合并相近的 Timer 以节省 CPU 唤醒。

```ini
[Timer]
OnCalendar=*-*-* 03:00:00
AccuracySec=1min     # 精度：1 分钟内触发
# AccuracySec=1s     # 需要精确到秒时使用
```

| AccuracySec 值 | 适用场景 |
|----------------|----------|
| 默认（1分钟） | 大多数批处理任务 |
| 1s | 需要精确时间的任务 |
| 1h | 非关键任务，节省资源 |

### 4.4 完整 Timer 模板

```ini
# /etc/systemd/system/backup.timer
[Unit]
Description=Daily Database Backup Timer

[Timer]
OnCalendar=*-*-* 03:00:00
Persistent=true           # 补执行错过的任务
RandomizedDelaySec=30min  # 防止雷群效应
AccuracySec=1min          # 1 分钟精度

[Install]
WantedBy=timers.target
```

```ini
# /etc/systemd/system/backup.service
[Unit]
Description=Database Backup Service
After=postgresql.service
Wants=postgresql.service

[Service]
Type=oneshot
User=backup
Group=backup
ExecStart=/opt/scripts/backup-db.sh

# 资源限制（防止影响其他服务）
MemoryMax=2G
CPUQuota=50%

# 日志
StandardOutput=journal
StandardError=journal
```

---

## Step 5 -- 动手实验：Cron 到 Timer 迁移（15 分钟）

> **场景**：将现有的 crontab 备份任务迁移为 systemd Timer。  

### 5.1 原始 crontab

```bash
# 当前 crontab 内容
# 0 3 * * * /opt/scripts/daily-backup.sh >> /var/log/backup.log 2>&1
# 0 * * * * /opt/scripts/cleanup-tmp.sh >> /var/log/cleanup.log 2>&1
# 0 9 * * 1-5 /opt/scripts/send-report.sh >> /var/log/report.log 2>&1
```

### 5.2 创建备份脚本

```bash
# 创建脚本目录
sudo mkdir -p /opt/scripts

# 创建模拟备份脚本
sudo tee /opt/scripts/daily-backup.sh << 'EOF'
#!/bin/bash
# Daily backup script for systemd timer demo
set -e

BACKUP_DIR="/var/backup"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

echo "Starting backup at $TIMESTAMP"
mkdir -p "$BACKUP_DIR"

# 模拟备份操作
echo "Backup content: $TIMESTAMP" > "$BACKUP_DIR/backup_$TIMESTAMP.txt"

echo "Backup completed successfully"
EOF

sudo chmod +x /opt/scripts/daily-backup.sh
sudo mkdir -p /var/backup
```

### 5.3 创建 Timer 和 Service

```bash
# 创建 Service 文件
sudo tee /etc/systemd/system/daily-backup.service << 'EOF'
[Unit]
Description=Daily Backup Service
# 如果依赖数据库，取消下面的注释
# After=postgresql.service
# Wants=postgresql.service

[Service]
Type=oneshot
User=root
ExecStart=/opt/scripts/daily-backup.sh

# 资源限制
MemoryMax=1G
CPUQuota=25%

# 超时设置（备份可能很长）
TimeoutStartSec=3600

# 日志输出到 journal
StandardOutput=journal
StandardError=journal
EOF

# 创建 Timer 文件
sudo tee /etc/systemd/system/daily-backup.timer << 'EOF'
[Unit]
Description=Daily Backup Timer

[Timer]
# 每天凌晨 3 点
OnCalendar=*-*-* 03:00:00
# 补执行错过的任务（关键！）
Persistent=true
# 防止多服务器同时执行
RandomizedDelaySec=30min
# 精度
AccuracySec=1min

[Install]
WantedBy=timers.target
EOF

# 重新加载并启用
sudo systemctl daemon-reload
sudo systemctl enable --now daily-backup.timer
```

### 5.4 验证 Timer

```bash
# 查看 Timer 状态
systemctl status daily-backup.timer

# 查看所有 Timer
systemctl list-timers --all | grep backup

# 验证下次运行时间
systemd-analyze calendar --iterations=3 "*-*-* 03:00:00"
```

### 5.5 手动测试

```bash
# 立即执行一次（不用等到 03:00！）
sudo systemctl start daily-backup.service

# 查看执行结果
systemctl status daily-backup.service

# 查看日志
sudo journalctl -u daily-backup.service --since "5 minutes ago"

# 验证备份文件
ls -la /var/backup/
```

### 5.6 迁移对照表

| Cron 表达式 | OnCalendar 表达式 | 说明 |
|-------------|-------------------|------|
| `0 3 * * *` | `*-*-* 03:00:00` | 每天 3 点 |
| `0 * * * *` | `hourly` | 每小时 |
| `0 9 * * 1-5` | `Mon..Fri *-*-* 09:00:00` | 工作日 9 点 |
| `*/15 * * * *` | `*:0/15` | 每 15 分钟 |
| `0 0 1 * *` | `monthly` 或 `*-*-1 00:00:00` | 每月 1 号 |
| `0 0 * * 0` | `Sun *-*-* 00:00:00` | 每周日 |

### 5.7 清理测试环境

```bash
# 停止并禁用 Timer
sudo systemctl stop daily-backup.timer
sudo systemctl disable daily-backup.timer

# 删除 Unit 文件
sudo rm /etc/systemd/system/daily-backup.{service,timer}
sudo systemctl daemon-reload

# 删除脚本和备份
sudo rm -rf /opt/scripts/daily-backup.sh /var/backup

# 清理第一个实验的 Timer
sudo systemctl stop hello-timer.timer
sudo systemctl disable hello-timer.timer
sudo rm /etc/systemd/system/hello-timer.{service,timer}
sudo systemctl daemon-reload
```

---

## 反模式：常见错误

### 错误 1：关键任务没有 Persistent=true

```ini
# 错误：服务器重启后丢失任务
[Timer]
OnCalendar=*-*-* 03:00:00
# 没有 Persistent=true

# 正确：确保补执行
[Timer]
OnCalendar=*-*-* 03:00:00
Persistent=true
```

**后果**：服务器维护重启后，当天的备份任务丢失，可能违反合规要求。

### 错误 2：没有 RandomizedDelaySec

```ini
# 错误：100 台服务器同时执行
[Timer]
OnCalendar=*-*-* 03:00:00
Persistent=true

# 正确：分散负载
[Timer]
OnCalendar=*-*-* 03:00:00
Persistent=true
RandomizedDelaySec=30min
```

**后果**：所有服务器同时向 NFS/数据库发起请求，造成雷群效应（Thundering Herd）。

### 错误 3：OnBootSec 用于必须在特定时间运行的任务

```ini
# 错误：备份应该在 03:00 执行，而不是启动后
[Timer]
OnBootSec=3h

# 正确：使用 OnCalendar
[Timer]
OnCalendar=*-*-* 03:00:00
Persistent=true
```

**后果**：如果服务器在 14:00 重启，备份会在 17:00 执行，完全偏离计划。

### 错误 4：忘记 daemon-reload

```bash
# 错误：修改 Timer 后直接重启
sudo vim /etc/systemd/system/backup.timer
sudo systemctl restart backup.timer

# 正确：先重新加载配置
sudo vim /etc/systemd/system/backup.timer
sudo systemctl daemon-reload
sudo systemctl restart backup.timer
```

**后果**：Timer 仍然使用旧配置运行。

### 错误 5：Timer 启用但服务未创建

```bash
# Timer 文件存在，但对应的 .service 文件不存在
systemctl enable backup.timer
# Error: Unit file backup.service does not exist
```

**后果**：Timer 无法触发任何任务。

---

## Timer 管理命令速查

```bash
# 查看所有 Timer
systemctl list-timers
systemctl list-timers --all    # 包括非活动的

# Timer 状态
systemctl status backup.timer
systemctl is-active backup.timer
systemctl is-enabled backup.timer

# 启用和禁用
systemctl enable backup.timer   # 开机自启
systemctl enable --now backup.timer  # 启用并立即激活
systemctl disable backup.timer  # 禁用

# 手动触发任务（测试用）
systemctl start backup.service  # 立即执行一次

# 查看日志
journalctl -u backup.service              # 所有日志
journalctl -u backup.service --since "1 day ago"  # 最近一天
journalctl -u backup.service -f           # 实时跟踪

# 验证表达式
systemd-analyze calendar "Mon..Fri *-*-* 09:00:00"
systemd-analyze calendar --iterations=5 "daily"
```

---

## 职场小贴士（Japan IT Context）

### 夜間バッチ（Overnight Batch）

在日本 IT 企业，夜间批处理是运维的重要组成部分。

| 日语术语 | 含义 | systemd 对应 |
|----------|------|--------------|
| 夜間バッチ（やかんバッチ） | 夜间批处理 | OnCalendar=*-*-* 03:00:00 |
| 定期バッチ（ていきバッチ） | 定期批处理 | Timer unit |
| 実行漏れ（じっこうもれ） | 执行遗漏 | Persistent=true 防止 |
| 同時実行回避 | 避免同时执行 | RandomizedDelaySec |

### 合规要求

日本企业（特别是金融、医疗行业）有严格的合规要求：

```markdown
# バックアップ運用手順書

## Timer 設定確認事項
1. Persistent=true が設定されていること（実行漏れ防止）
2. RandomizedDelaySec が適切に設定されていること
3. journalctl で実行ログが確認できること
4. 障害時の手動実行手順が文書化されていること

## 監視項目
- Timer の NEXT 実行時刻が正しいこと
- 前回実行の EXIT STATUS が 0 であること
- バックアップファイルが正しく生成されていること
```

### 障害対応

Timer が実行されなかった場合の対応：

```bash
# 1. Timer 状態確認
systemctl status backup.timer

# 2. 前回実行確認
journalctl -u backup.service --since "2 days ago"

# 3. 手動実行
sudo systemctl start backup.service

# 4. 実行確認
systemctl status backup.service
journalctl -u backup.service -n 50
```

---

## 检查清单

完成本课后，你应该能够：

- [ ] 解释 Timer 相比 cron 的 5 个优势
- [ ] 区分 Realtime Timer（OnCalendar）和 Monotonic Timer（OnBootSec）
- [ ] 使用 `systemd-analyze calendar` 验证 OnCalendar 表达式
- [ ] 为 Timer 配置 Persistent=true 防止执行遗漏
- [ ] 使用 RandomizedDelaySec 防止雷群效应
- [ ] 将 crontab 任务迁移为 systemd Timer
- [ ] 使用 `systemctl list-timers` 查看 Timer 状态
- [ ] 使用 `systemctl start` 手动触发任务测试
- [ ] 使用 `journalctl -u` 查看定时任务日志
- [ ] 解释 Persistent=true 对合规的重要性

---

## 本课小结

| 概念 | 要点 | 记忆点 |
|------|------|--------|
| Timer vs Cron | 日志、持久化、依赖、资源控制 | Timer 更强大 |
| Realtime Timer | OnCalendar | 固定时间执行 |
| Monotonic Timer | OnBootSec, OnUnitActiveSec | 间隔执行 |
| Persistent | 系统恢复后补执行 | 关键任务必须！ |
| RandomizedDelaySec | 随机延迟 | 防雷群效应 |
| AccuracySec | 计时精度 | 默认 1 分钟 |
| 验证工具 | systemd-analyze calendar | 部署前必用 |
| 手动测试 | systemctl start xxx.service | 不用等触发时间 |

---

## 面试准备

### Q: systemd timer と cron の違いは？

**A**: systemd timer には cron にない以下のメリットがあります：

1. **journalctl でログ確認可能** - 出力を手動でリダイレクトする必要がない
2. **Persistent=true で実行漏れ防止** - システム停止中に実行時刻が過ぎた場合、起動後に即座に実行
3. **依存関係とリソース制御が可能** - After=postgresql.service や MemoryMax=2G など
4. **RandomizedDelaySec で雷群効果を防止** - 複数サーバーの同時実行を回避
5. **systemctl start で即座にテスト可能** - cron のように実行時刻を待つ必要がない

### Q: Persistent=true の効果は？

**A**: システム停止中に実行時刻が過ぎた場合、起動後に即座に実行します。例えば、毎日 03:00 のバックアップで、02:00-05:00 にサーバーがダウンしていた場合：

- `Persistent=false`（デフォルト）: バックアップは実行されない
- `Persistent=true`: 05:00 の起動後、即座にバックアップを実行

これはコンプライアンス要件で特に重要です。金融・医療系では、バックアップの実行漏れは監査で問題になります。

### Q: OnCalendar の構文を確認する方法は？

**A**: `systemd-analyze calendar` コマンドを使用します：

```bash
# 構文確認
systemd-analyze calendar "Mon..Fri *-*-* 09:00:00"

# 次の5回の実行時刻を確認
systemd-analyze calendar --iterations=5 "daily"
```

本番環境にデプロイする前に、必ずこのコマンドで確認することが重要です。

---

## 延伸阅读

- [systemd.timer(5) man page](https://www.freedesktop.org/software/systemd/man/systemd.timer.html)
- [systemd.time(7) man page](https://www.freedesktop.org/software/systemd/man/systemd.time.html) - OnCalendar 语法详解
- 下一课：[07 - journalctl 日志掌控](../07-journalctl/) -- 学习如何分析定时任务日志
- 相关课程：[08 - 资源控制](../08-resource-control/) -- 为批处理任务设置资源限制

---

## 系列导航

[05 - Target 与启动流程 <--](../05-targets/) | [系列首页](../) | [--> 07 - journalctl 日志掌控](../07-journalctl/)
