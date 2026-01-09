# 07 - 日志分析：journalctl 与时间线重建（Log Analysis: journalctl and Timeline Reconstruction）

> **目标**：精通 journalctl 过滤查询，掌握多源日志关联分析，学会重建事件时间线  
> **前置**：LX03 文本处理、LX05 systemd、Lesson 01 方法论  
> **时间**：2 小时  
> **核心理念**：日志是证据，时间线是真相  

---

## 前置技能提醒

> **重要**：本课大量使用 LX03 学到的文本处理技能。  
> 如果不熟悉以下内容，建议先复习 LX03-TEXT：  
>
> - **grep 正则表达式过滤**：`grep -E 'error|fail|timeout' /var/log/messages`  
> - **awk 字段提取**：`awk '{print $1, $3, $NF}' access.log`  
> - **多文件日志关联**：`grep -h 'request-id' *.log | sort -k2`  
> - **时间范围过滤**：`awk '$2 >= "14:00" && $2 <= "15:00"' log.txt`  
>
> 如果不熟悉以上技能，建议先完成 LX03-TEXT 课程。  

---

## 将学到的内容

1. 精通 journalctl 过滤和查询（-u, -p, --since, -g, -o json）
2. 理解传统日志文件位置和格式
3. 进行多源日志关联分析（3-Source Rule）
4. 重建事件时间线（时区规范化）
5. 识别日志分析反模式

---

## 先跑起来！（10 分钟）

> 在学习日志分析理论之前，先体验"精准定位"的威力。  
> 一条命令立即给你结构化的错误信息。  

```bash
# 获取最近 1 小时的错误日志，输出为 JSON 格式，提取消息
journalctl -p err --since '1 hour ago' -o json | jq -r '.MESSAGE' | head -20
```

**输出示例**：

```
Failed to start nginx.service: Unit nginx.service not found.
error: PAM: Authentication failure for root from 192.168.1.100
kernel: ata1.00: exception Emask 0x0 SAct 0x0 SErr 0x0 action 0x6
sshd[12345]: Connection closed by authenticating user admin 192.168.1.50 port 22
```

**你刚刚做到的**：
- 按优先级过滤（只看 err 及以上）
- 按时间范围过滤（最近 1 小时）
- 获取结构化输出（JSON 格式）
- 用 jq 提取关键字段（MESSAGE）

**这就是现代日志分析的威力** -- 不需要 grep 在文本里大海捞针。现在让我们系统学习日志分析的方法论。

---

## Step 1 -- journalctl 精通（30 分钟）

### 1.1 systemd journal vs 传统日志

<!-- DIAGRAM: journal-vs-traditional -->
```
┌──────────────────────────────────────────────────────────────────┐
│              systemd journal vs 传统日志                          │
├──────────────────────────────────────────────────────────────────┤
│                                                                  │
│  传统日志 (syslog)                  systemd journal              │
│  ┌─────────────────────┐           ┌─────────────────────────┐  │
│  │ • 纯文本文件         │           │ • 二进制结构化存储       │  │
│  │ • 按文件分类         │           │ • 统一入口               │  │
│  │ • grep/awk 搜索     │           │ • 字段查询               │  │
│  │ • 手动轮转          │           │ • 自动空间管理           │  │
│  │ • 无元数据          │           │ • 丰富元数据             │  │
│  └─────────────────────┘           └─────────────────────────┘  │
│                                                                  │
│  文件位置：                         存储位置：                    │
│  • /var/log/messages               • /var/log/journal/           │
│  • /var/log/syslog                 • 或 /run/log/journal/ (内存) │
│  • /var/log/secure                                               │
│  • /var/log/auth.log                                             │
│                                                                  │
│  两者共存：                                                       │
│  • RHEL/CentOS: journal + rsyslog 并存                           │
│  • Ubuntu: journal + rsyslog 并存                                │
│  • 纯 systemd 系统: 可禁用 rsyslog                               │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘
```
<!-- /DIAGRAM -->

### 1.2 journalctl 基础过滤

**按服务过滤 (-u)**：

```bash
# 查看特定服务的日志
journalctl -u sshd
journalctl -u nginx
journalctl -u mysql

# 多个服务
journalctl -u sshd -u nginx

# 查看服务的最新日志（等同于 tail）
journalctl -u sshd -n 50

# 实时跟踪（等同于 tail -f）
journalctl -u nginx -f
```

**按优先级过滤 (-p)**：

```bash
# 只看错误及以上 (err, crit, alert, emerg)
journalctl -p err

# 只看警告及以上
journalctl -p warning

# 指定优先级范围
journalctl -p warning..err
```

**优先级级别参考**：

| 数字 | 名称 | 含义 |
|------|------|------|
| 0 | emerg | 系统不可用 |
| 1 | alert | 必须立即处理 |
| 2 | crit | 严重错误 |
| 3 | err | 错误 |
| 4 | warning | 警告 |
| 5 | notice | 正常但重要 |
| 6 | info | 信息 |
| 7 | debug | 调试 |

### 1.3 时间范围过滤

**--since 和 --until**：

```bash
# 相对时间
journalctl --since '1 hour ago'
journalctl --since '30 minutes ago'
journalctl --since 'yesterday'
journalctl --since 'today'

# 绝对时间
journalctl --since '2026-01-10 14:00' --until '2026-01-10 15:00'
journalctl --since '2026-01-10 14:00:00' --until '2026-01-10 14:30:00'

# 组合使用
journalctl -u nginx --since '1 hour ago' -p err

# 查看本次启动以来的日志
journalctl -b

# 查看上次启动的日志
journalctl -b -1
```

**时间格式支持**：

```
# 绝对格式
YYYY-MM-DD HH:MM:SS
YYYY-MM-DD HH:MM
YYYY-MM-DD

# 相对格式
"X minutes ago"
"X hours ago"
"X days ago"
"yesterday"
"today"
"now"
```

### 1.4 正则搜索 (-g)

```bash
# 搜索包含特定模式的日志
journalctl -g 'error|fail|timeout'
journalctl -g 'sshd.*Failed'
journalctl -g 'OOM\|killed'

# 组合过滤
journalctl -u sshd --since '1 hour ago' -g 'Failed password'

# 区分大小写（默认不区分）
journalctl --case-sensitive=true -g 'Error'
```

### 1.5 输出格式 (-o)

```bash
# 默认格式（人类可读）
journalctl -u nginx

# JSON 格式（脚本处理）
journalctl -u nginx -o json

# 单行 JSON（每条日志一行）
journalctl -u nginx -o json --no-pager

# 简短格式
journalctl -u nginx -o short

# 带微秒时间戳
journalctl -u nginx -o short-precise

# 导出格式（用于传输）
journalctl -u nginx -o export
```

**JSON 输出结合 jq**：

```bash
# 提取消息字段
journalctl -u nginx -o json | jq -r '.MESSAGE'

# 提取时间和消息
journalctl -u nginx -o json | jq -r '[.__REALTIME_TIMESTAMP, .MESSAGE] | @tsv'

# 统计错误类型
journalctl -p err -o json --since '1 hour ago' | \
  jq -r '.MESSAGE' | \
  sort | uniq -c | sort -rn | head -10
```

### 1.6 其他常用选项

```bash
# 内核日志
journalctl -k
journalctl --dmesg

# 按进程 ID
journalctl _PID=1234

# 按用户
journalctl _UID=1000

# 按可执行文件路径
journalctl _EXE=/usr/sbin/sshd

# 反向显示（最新在前）
journalctl -r

# 不分页
journalctl --no-pager

# 显示日志占用空间
journalctl --disk-usage

# 清理旧日志
sudo journalctl --vacuum-time=7d  # 保留 7 天
sudo journalctl --vacuum-size=500M  # 保留 500MB
```

---

## Step 2 -- 传统日志位置与格式（20 分钟）

### 2.1 主要日志文件

虽然 systemd journal 是现代标准，但传统日志文件仍然广泛使用：

<!-- DIAGRAM: traditional-log-locations -->
```
┌──────────────────────────────────────────────────────────────────┐
│                    传统日志文件位置                               │
├──────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │ 系统日志                                                     ││
│  ├─────────────────────────────────────────────────────────────┤│
│  │ RHEL/CentOS              Debian/Ubuntu                      ││
│  │ /var/log/messages        /var/log/syslog      (系统消息)    ││
│  │ /var/log/secure          /var/log/auth.log    (认证日志)    ││
│  │ /var/log/maillog         /var/log/mail.log    (邮件日志)    ││
│  │ /var/log/cron            /var/log/cron.log    (定时任务)    ││
│  └─────────────────────────────────────────────────────────────┘│
│                                                                  │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │ 通用日志                                                     ││
│  ├─────────────────────────────────────────────────────────────┤│
│  │ /var/log/dmesg           - 启动时内核消息                    ││
│  │ /var/log/boot.log        - 启动服务日志                      ││
│  │ /var/log/lastlog         - 最后登录记录（二进制）            ││
│  │ /var/log/wtmp            - 登录历史（二进制）                ││
│  │ /var/log/btmp            - 失败登录（二进制）                ││
│  └─────────────────────────────────────────────────────────────┘│
│                                                                  │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │ 应用日志                                                     ││
│  ├─────────────────────────────────────────────────────────────┤│
│  │ /var/log/nginx/          - Nginx 日志                        ││
│  │ /var/log/httpd/          - Apache 日志                       ││
│  │ /var/log/mysql/          - MySQL 日志                        ││
│  │ /var/log/postgresql/     - PostgreSQL 日志                   ││
│  │ /var/log/audit/          - 审计日志                          ││
│  └─────────────────────────────────────────────────────────────┘│
│                                                                  │
└──────────────────────────────────────────────────────────────────┘
```
<!-- /DIAGRAM -->

### 2.2 syslog vs messages 格式

**传统 syslog 格式**：

```
# /var/log/messages 或 /var/log/syslog
Jan 10 14:30:45 hostname sshd[12345]: Failed password for root from 192.168.1.100 port 22 ssh2
 ↑           ↑        ↑     ↑           ↑
 时间戳      主机名   程序  PID         消息内容
```

**字段提取**：

```bash
# 提取时间、程序、消息
awk '{print $1, $2, $3, $5, $6}' /var/log/messages

# 统计程序出现次数
awk '{print $5}' /var/log/messages | cut -d'[' -f1 | sort | uniq -c | sort -rn | head -10

# 按时间范围过滤（syslog 格式没有年份！）
grep 'Jan 10' /var/log/messages | awk '$3 >= "14:00" && $3 <= "15:00"'
```

### 2.3 认证日志

**RHEL/CentOS: /var/log/secure**
**Debian/Ubuntu: /var/log/auth.log**

```bash
# 查看 SSH 登录失败
grep 'Failed password' /var/log/secure

# 统计登录失败的 IP
grep 'Failed password' /var/log/secure | \
  awk '{print $(NF-3)}' | sort | uniq -c | sort -rn | head -10

# 查看成功登录
grep 'Accepted' /var/log/secure | tail -20

# 查看 sudo 使用
grep 'sudo:' /var/log/secure
```

### 2.4 内核日志 (dmesg)

```bash
# 查看内核日志
dmesg

# 带时间戳
dmesg -T

# 只看错误和警告
dmesg -l err,warn

# 搜索特定内容
dmesg | grep -i 'error\|fail\|oom'

# 磁盘相关
dmesg | grep -i 'ata\|scsi\|sda'

# OOM Killer
dmesg | grep -i 'oom\|killed'
```

### 2.5 二进制日志文件

**wtmp/btmp/lastlog 是二进制格式**，需要专用命令：

```bash
# 登录历史 (wtmp)
last
last -n 20
last reboot  # 重启历史

# 失败登录 (btmp) - 需要 root
sudo lastb
sudo lastb -n 20

# 最后登录时间 (lastlog)
lastlog
lastlog -u username
```

---

## Step 3 -- 多源日志关联：3-Source Rule（25 分钟）

### 3.1 什么是 3-Source Rule？

**核心原则**：诊断问题时，至少关联 3 个来源的日志。

<!-- DIAGRAM: three-source-rule -->
```
┌──────────────────────────────────────────────────────────────────┐
│                    3-Source Rule 日志关联                        │
├──────────────────────────────────────────────────────────────────┤
│                                                                  │
│                        问题发生                                  │
│                           │                                      │
│           ┌───────────────┼───────────────┐                      │
│           ▼               ▼               ▼                      │
│    ┌─────────────┐ ┌─────────────┐ ┌─────────────┐              │
│    │ 1. 应用日志 │ │ 2. 系统日志 │ │ 3. 外部数据 │              │
│    │             │ │             │ │             │              │
│    │ • 业务日志  │ │ • journal   │ │ • 监控指标  │              │
│    │ • 错误堆栈  │ │ • dmesg     │ │ • 网络流量  │              │
│    │ • 请求日志  │ │ • secure    │ │ • 变更记录  │              │
│    │ • 审计日志  │ │ • messages  │ │ • 部署日志  │              │
│    └──────┬──────┘ └──────┬──────┘ └──────┬──────┘              │
│           │               │               │                      │
│           └───────────────┼───────────────┘                      │
│                           ▼                                      │
│                    ┌─────────────┐                               │
│                    │  时间线重建  │                               │
│                    │  因果推断    │                               │
│                    └─────────────┘                               │
│                                                                  │
│  为什么需要多源？                                                 │
│  • 单源可能缺失关键信息                                          │
│  • 应用日志可能没有记录系统级问题                                │
│  • 系统日志可能没有业务上下文                                    │
│  • 外部数据提供触发因素线索                                      │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘
```
<!-- /DIAGRAM -->

### 3.2 日志关联实战

**场景**：API 服务在 14:30 开始返回 500 错误。

**Step 1: 应用日志**

```bash
# 查看应用日志中的错误
grep -E '14:3[0-5].*ERROR' /var/log/myapp/app.log

# 输出：
# 2026-01-10 14:30:15 ERROR Database connection timeout
# 2026-01-10 14:30:16 ERROR Failed to execute query
# 2026-01-10 14:30:17 ERROR Database connection timeout
```

**Step 2: 系统日志**

```bash
# 同时间段的系统事件
journalctl --since '2026-01-10 14:25' --until '2026-01-10 14:35' -p warning

# 输出：
# Jan 10 14:28:30 server kernel: ata1: exception Emask 0x10 SAct 0x0
# Jan 10 14:29:00 server kernel: ata1.00: failed command: READ DMA
# Jan 10 14:30:00 server mysqld[5678]: Disk I/O error
```

**Step 3: 外部数据**

```bash
# 检查同时间的磁盘指标（假设保存了监控数据）
cat /var/log/sar/sa10 | sar -d -s 14:25:00 -e 14:35:00

# 或检查变更记录
grep '14:2[0-9]' /var/log/deploy.log

# 输出：
# 2026-01-10 14:20:00 Started backup job on /dev/sda
```

**因果链推断**：

```
14:20 备份任务启动 → 14:28 磁盘 I/O 压力 → 14:29 磁盘错误 →
14:30 MySQL I/O 失败 → 14:30 应用数据库超时 → 500 错误
```

### 3.3 关联技巧

**按时间戳对齐**：

```bash
# 合并多个日志，按时间排序
(
  awk '{print "APP:", $0}' /var/log/myapp/app.log
  awk '{print "SYS:", $0}' /var/log/messages
  awk '{print "SEC:", $0}' /var/log/secure
) | sort -k2,3 | grep '14:3[0-5]'
```

**按 Request ID 追踪**（如果应用支持）：

```bash
# 找到问题请求的 ID
grep '500' /var/log/nginx/access.log | head -1
# 输出: ... request_id=abc123 ...

# 在所有日志中搜索这个 ID
grep -rh 'abc123' /var/log/myapp/ /var/log/nginx/
```

**按 PID 关联**：

```bash
# 找到崩溃进程的 PID
journalctl -p err --since '14:30' | grep -oP 'PID \K\d+'

# 查看这个进程之前的活动
journalctl _PID=12345 --since '14:00'
```

---

## Step 4 -- 时间线重建（20 分钟）

### 4.1 时区规范化（关键！）

**日本 IT 环境的时区问题**：

- 服务器可能是 UTC 或 JST
- 日志文件可能混合不同时区
- 时间线必须统一到一个时区

<!-- DIAGRAM: timezone-normalization -->
```
┌──────────────────────────────────────────────────────────────────┐
│                    时区规范化                                     │
├──────────────────────────────────────────────────────────────────┤
│                                                                  │
│  问题场景：                                                       │
│  ┌──────────────────────────────────────────────────────────────┐│
│  │ 服务器 A (UTC):    2026-01-10 05:30:00 ERROR              ││
│  │ 服务器 B (JST):    2026-01-10 14:30:00 ERROR              ││
│  │                    ↑                                        ││
│  │                    这是同一时刻！                            ││
│  └──────────────────────────────────────────────────────────────┘│
│                                                                  │
│  时区转换：                                                       │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │  UTC → JST: +9 小时                                         ││
│  │  JST → UTC: -9 小时                                         ││
│  │                                                              ││
│  │  UTC 05:30 = JST 14:30                                      ││
│  │  UTC 00:00 = JST 09:00                                      ││
│  └─────────────────────────────────────────────────────────────┘│
│                                                                  │
│  日本企业标准：                                                   │
│  • 障害報告書 时间线使用 JST                                     │
│  • 所有时间标注 (JST) 或 (UTC)                                   │
│                                                                  │
│  检查系统时区：                                                   │
│  $ timedatectl                                                  │
│  $ date +%Z  # 显示时区简写 (JST/UTC)                           │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘
```
<!-- /DIAGRAM -->

**检查和转换时区**：

```bash
# 检查系统时区
timedatectl
date +%Z

# journalctl 输出时间格式
journalctl -o short           # 本地时区
journalctl -o short-iso       # ISO 格式带时区
journalctl -o short-precise   # 精确到微秒

# 在查询中指定时区（journalctl 使用本地时区）
TZ=UTC journalctl --since '05:30' --until '05:35'  # UTC 时间
TZ=Asia/Tokyo journalctl --since '14:30' --until '14:35'  # JST 时间

# 转换 UTC 到 JST
date -d '2026-01-10 05:30 UTC' '+%Y-%m-%d %H:%M:%S JST'
```

### 4.2 登录历史追踪 (wtmp/btmp)

```bash
# 查看登录历史
last
last -t 20260110143000  # 某时间点之前的登录
last -F  # 完整时间格式

# 查看特定用户
last username
last root

# 查看失败登录
sudo lastb
sudo lastb -F

# 谁在什么时候登录的？
who /var/log/wtmp
```

### 4.3 命令历史追踪 (bash_history)

**注意**：bash_history 默认不记录时间戳，需要配置。

```bash
# 查看用户命令历史
cat /home/username/.bash_history
cat /root/.bash_history

# 启用时间戳（在 .bashrc 中添加）
export HISTTIMEFORMAT="%Y-%m-%d %H:%M:%S "
export HISTSIZE=10000
export HISTFILESIZE=20000

# 查看带时间戳的历史（如果已启用）
history
```

### 4.4 文件时间戳追踪 (stat)

```bash
# 查看文件时间戳
stat /etc/nginx/nginx.conf

# 输出解读：
# Access: 最后访问时间
# Modify: 最后修改内容时间（重要！）
# Change: 最后修改元数据时间（权限、属主等）

# 找最近修改的配置文件
find /etc -name '*.conf' -mtime -1  # 最近 1 天修改

# 找特定时间范围内修改的文件
find /etc -newermt '2026-01-10 14:00' ! -newermt '2026-01-10 15:00'
```

### 4.5 时间线重建模板

**障害報告書时间线格式**：

```markdown
## 時系列 (Timeline)

| 時刻 (JST) | 事象 | 来源 |
|------------|------|------|
| 14:20:00 | バックアップジョブ開始 | /var/log/cron |
| 14:28:30 | ディスク I/O エラー発生 | dmesg |
| 14:29:00 | MySQL ディスク I/O 失敗 | journalctl -u mysql |
| 14:30:15 | API 500 エラー開始 | /var/log/myapp/app.log |
| 14:32:00 | 監視アラート発報 | Zabbix |
| 14:35:00 | 担当者ログイン | last |
| 14:40:00 | バックアップジョブ停止 | 手動操作 |
| 14:45:00 | 正常復旧確認 | 動作確認 |
```

---

## Step 5 -- 日志分析反模式（15 分钟）

### 5.1 反模式识别

| 反模式 | 错误做法 | 后果 | 正确做法 |
|--------|----------|------|----------|
| **只用 grep** | 不使用 journalctl 字段过滤 | 效率低，错过结构化信息 | 用 journalctl -u, -p, -g |
| **忽略时区** | 混合 UTC/JST 时间 | 时间线混乱，因果错误 | 统一到 JST，标注时区 |
| **只看最近日志** | 只 tail 最后几行 | 错过问题开始的线索 | 用 --since 回溯到问题前 |
| **单源分析** | 只看应用日志 | 错过系统级原因 | 3-Source Rule 多源关联 |
| **忽略正常日志** | 只搜索 error | 错过异常但非错误的模式 | 对比正常时的日志模式 |

### 5.2 反模式案例

**案例：只用 grep 的低效分析**

```bash
# 反模式：在大文件中 grep
grep 'error' /var/log/messages | tail -100
# 问题：
# - 没有时间范围，扫描整个文件
# - 大小写敏感，可能漏掉 Error, ERROR
# - 没有优先级过滤

# 正确做法：使用 journalctl
journalctl -p err --since '1 hour ago'
# 优点：
# - 有索引，查询快
# - 自动处理大小写
# - 结构化输出
```

**案例：忽略时区的错误时间线**

```bash
# 反模式：混合不同时区日志
14:30:00 [应用日志-JST] ERROR: Database timeout
05:32:00 [系统日志-UTC] MySQL connection failed
# 问题：看起来应用错误在系统错误之前，实际相反！

# 正确做法：统一时区
14:30:00 JST [应用日志] ERROR: Database timeout
14:32:00 JST [系统日志] MySQL connection failed  # UTC 05:32 = JST 14:32
# 现在因果关系清楚了
```

**案例：只看最近日志错过根因**

```bash
# 反模式：只看最近错误
journalctl -p err -n 10
# 问题：可能只看到症状（500 错误），看不到根因（磁盘错误）

# 正确做法：回溯到问题开始前
journalctl -p warning --since '30 minutes ago'
# 可以看到问题发展的完整过程
```

---

## Step 6 -- journalctl 速查表（Cheatsheet）

### 6.1 常用查询

```bash
# === 按服务 ===
journalctl -u sshd                 # SSH 服务
journalctl -u nginx                # Nginx
journalctl -u sshd -u nginx        # 多个服务

# === 按优先级 ===
journalctl -p err                  # 错误及以上
journalctl -p warning              # 警告及以上
journalctl -p err..crit            # err 到 crit 范围

# === 按时间 ===
journalctl --since '1 hour ago'
journalctl --since '2026-01-10 14:00' --until '2026-01-10 15:00'
journalctl --since yesterday
journalctl --since today

# === 按启动 ===
journalctl -b                      # 本次启动
journalctl -b -1                   # 上次启动
journalctl --list-boots            # 列出所有启动

# === 正则搜索 ===
journalctl -g 'error|fail|timeout'
journalctl -g 'sshd.*Failed'

# === 内核日志 ===
journalctl -k                      # 等同于 dmesg
journalctl -k --since '1 hour ago'

# === 输出格式 ===
journalctl -o json                 # JSON 格式
journalctl -o json | jq '.MESSAGE' # 提取字段
journalctl -o short-precise        # 精确时间戳

# === 实时跟踪 ===
journalctl -f                      # 跟踪所有
journalctl -u nginx -f             # 跟踪特定服务

# === 空间管理 ===
journalctl --disk-usage            # 查看占用
sudo journalctl --vacuum-time=7d   # 清理 7 天前
sudo journalctl --vacuum-size=500M # 限制大小
```

### 6.2 高级组合

```bash
# 组合多个条件
journalctl -u nginx -p err --since '1 hour ago' -o json | jq '.MESSAGE'

# 导出特定时间段日志
journalctl --since '2026-01-10 14:00' --until '2026-01-10 15:00' > /tmp/incident.log

# 统计错误类型
journalctl -p err --since '1 hour ago' -o json | \
  jq -r '._SYSTEMD_UNIT // "kernel"' | \
  sort | uniq -c | sort -rn

# 实时监控错误
journalctl -p err -f -o json | jq -r '[.SYSLOG_IDENTIFIER, .MESSAGE] | @tsv'
```

---

## Step 7 -- 动手实验（30 分钟）

### 实验 1：时间线重建练习

**场景**：用户报告 Web 应用在 14:30 左右无法访问。请重建时间线。

```bash
# Step 1: 收集系统日志
journalctl --since '14:25' --until '14:40' > /tmp/timeline/journal.log

# Step 2: 收集内核日志
dmesg -T > /tmp/timeline/dmesg.log

# Step 3: 收集应用日志（假设 nginx）
journalctl -u nginx --since '14:25' --until '14:40' > /tmp/timeline/nginx.log

# Step 4: 检查登录历史
last -t 20260110144000 > /tmp/timeline/logins.log

# Step 5: 检查配置变更
find /etc -newermt '14:00' ! -newermt '14:40' -type f 2>/dev/null > /tmp/timeline/changes.log

# Step 6: 整合分析
# 按时间排序所有日志条目
cat /tmp/timeline/*.log | sort | less
```

**练习任务**：
1. 创建一个统一的时间线
2. 识别问题的第一个异常信号
3. 确定根因和触发因素
4. 用障害報告書格式记录

### 实验 2：journalctl 高级查询

完成以下查询任务：

```bash
# 任务 1: 找出最近 24 小时内所有失败的 SSH 登录尝试
# 你的命令：
journalctl -u sshd --since '24 hours ago' -g 'Failed'

# 任务 2: 统计最近 1 小时内各服务的错误数量
# 你的命令：
journalctl -p err --since '1 hour ago' -o json | \
  jq -r '._SYSTEMD_UNIT // "other"' | sort | uniq -c | sort -rn

# 任务 3: 找出上次重启前后的内核错误
# 你的命令：
journalctl -k -b -1 -p err  # 上次启动
journalctl -k -b 0 -p err   # 本次启动

# 任务 4: 导出 JSON 格式日志用于脚本处理
# 你的命令：
journalctl -u nginx --since '1 hour ago' -o json --no-pager > nginx.json

# 任务 5: 实时监控所有错误并高亮显示
# 你的命令：
journalctl -p err -f | grep --color -E 'error|fail|timeout|$'
```

### 实验 3：日志分析脚本

创建一个日志分析脚本：

```bash
#!/bin/bash
# log-analyzer.sh - 日志快速分析脚本

SINCE="${1:-1 hour ago}"

echo "=== Log Analysis Report ==="
echo "Time Range: $SINCE to now"
echo "Generated: $(date)"
echo ""

echo "=== Error Summary by Service ==="
journalctl -p err --since "$SINCE" -o json 2>/dev/null | \
  jq -r '._SYSTEMD_UNIT // "kernel"' | \
  sort | uniq -c | sort -rn | head -10

echo ""
echo "=== Recent Critical/Emergency Messages ==="
journalctl -p crit --since "$SINCE" 2>/dev/null | head -20

echo ""
echo "=== OOM Killer Events ==="
journalctl -k --since "$SINCE" 2>/dev/null | grep -i 'oom\|killed' | head -10

echo ""
echo "=== Failed SSH Logins ==="
journalctl -u sshd --since "$SINCE" 2>/dev/null | grep -i 'failed' | head -10

echo ""
echo "=== Disk Errors ==="
dmesg -T 2>/dev/null | grep -i 'error\|fail\|ata\|scsi' | tail -10
```

使用方法：

```bash
chmod +x log-analyzer.sh
./log-analyzer.sh '2 hours ago'
```

---

## 检查清单

完成本课后，你应该能够：

- [ ] 使用 journalctl -u 按服务过滤日志
- [ ] 使用 journalctl -p 按优先级过滤日志
- [ ] 使用 --since/--until 按时间范围过滤
- [ ] 使用 -g 进行正则表达式搜索
- [ ] 使用 -o json 输出结构化数据
- [ ] 解释传统日志文件的位置和用途
- [ ] 应用 3-Source Rule 进行多源日志关联
- [ ] 规范化时区并重建事件时间线
- [ ] 使用 wtmp/lastb/stat 追踪登录和文件变更历史
- [ ] 识别并避免日志分析的常见反模式

---

## 本课小结

| 概念 | 要点 |
|------|------|
| journalctl | systemd 的统一日志查询工具，支持字段过滤 |
| -u service | 按服务过滤 |
| -p priority | 按优先级过滤（err, warning, info...）|
| --since/--until | 时间范围过滤，支持相对和绝对时间 |
| -g pattern | 正则表达式搜索 |
| -o json | 结构化输出，便于脚本处理 |
| 3-Source Rule | 关联应用日志 + 系统日志 + 外部数据 |
| 时区规范化 | 统一到 JST，标注时区，避免混乱 |
| wtmp/btmp | 登录历史，用 last/lastb 查看 |
| stat | 文件时间戳，追踪配置变更 |

**核心理念**：

> journalctl 字段过滤比 grep 高效得多。  
> 多源关联才能看清问题全貌。  
> 时区规范化是时间线重建的前提。  
> 日志是证据，时间线是真相。  

---

## 日本 IT 职场贴士

### ログ分析は障害報告書の証拠（日志分析是故障报告的证据）

在日本企业的故障报告中，日志是最重要的证据：

| 日语术语 | 含义 | 场景 |
|----------|------|------|
| **ログ分析** | 日志分析 | "ログ分析の結果、..." |
| **時系列** | 时间线 | 障害報告書必须项 |
| **証跡** | 证据/痕迹 | "証跡として保存" |
| **タイムゾーン** | 时区 | "JST で統一" |

### タイムゾーンは JST で統一（时区统一为 JST）

日本企业的故障报告时间线**必须**使用 JST：

```markdown
## 時系列 (Timeline)

| 時刻 (JST) | 事象 |
|------------|------|
| 14:30:00 | 監視アラート発報 |
| 14:32:00 | 担当者対応開始 |
| 14:45:00 | 原因特定 |
| 15:00:00 | 復旧完了 |

※ 全時刻は JST (日本標準時) で記載
```

### 报告时的表达

```
# 日志分析结果报告模板
【ログ分析結果】
・エラー発生時刻: 14:30:00 JST
・初回エラー: "Database connection timeout"
・原因: ディスク I/O 障害により MySQL 接続失敗
・証跡: journalctl -u mysql --since "14:25" の出力を添付

【根本原因】
dmesg ログより、14:28 にディスク I/O エラーが発生。
バックアップジョブとの I/O 競合が原因と推定。
```

---

## 面试准备

### よくある質問（常见问题）

**Q: journalctl で特定のサービスのエラーログを見る方法は？**

A: 以下のコマンドを使います：
```bash
journalctl -u <サービス名> -p err
```
例えば nginx のエラーを見る場合：
```bash
journalctl -u nginx -p err --since '1 hour ago'
```
-u でサービス指定、-p でプライオリティ指定、--since で時間範囲を指定できます。

**Q: 複数のログソースを関連付けて分析する方法は？**

A: 3-Source Rule を使います：
1. アプリケーションログ（業務エラー）
2. システムログ（OS レベルのイベント）
3. 外部データ（監視メトリクス、デプロイログ）

これらをタイムスタンプで関連付けて、因果関係を推論します。
重要なのはタイムゾーンの統一です。UTC と JST が混在すると時系列が狂います。

**Q: 障害発生時、最初にどのログを確認しますか？**

A: まず journalctl で概要を把握します：
```bash
journalctl -p err --since '30 minutes ago'
```
次に関連サービスのログを確認し、最後に dmesg でカーネルレベルの問題を確認します。
複数ソースを関連付けることで、症状だけでなく根本原因を特定できます。

**Q: ログの時系列を作成する際の注意点は？**

A: 主な注意点は：
1. **タイムゾーン統一**: 必ず JST で統一し、(JST) と明記
2. **複数ソース**: アプリ、システム、監視の3つ以上を参照
3. **時系列順**: 事象の発生順に並べ、因果関係を明確に
4. **証跡記録**: 各エントリにログの出典を記載

---

## トラブルシューティング（本課自体の問題解決）

### journalctl の出力が少ない・空

```bash
# ジャーナルの保持設定を確認
journalctl --disk-usage

# 保持設定
cat /etc/systemd/journald.conf
# Storage=auto/persistent/volatile/none
# SystemMaxUse=500M

# 永続化を有効にする
sudo mkdir -p /var/log/journal
sudo systemd-tmpfiles --create --prefix /var/log/journal
sudo systemctl restart systemd-journald
```

### jq がインストールされていない

```bash
# RHEL/CentOS
sudo yum install jq

# Debian/Ubuntu
sudo apt install jq

# jq なしで JSON を処理
journalctl -o json | python3 -c "import json,sys; [print(json.loads(l).get('MESSAGE','')) for l in sys.stdin]"
```

### 時間指定が効かない

```bash
# タイムゾーンを確認
timedatectl

# 明示的にタイムゾーンを指定
TZ=Asia/Tokyo journalctl --since '14:30'

# ISO 形式で指定
journalctl --since '2026-01-10T14:30:00+09:00'
```

### 古いログが見れない

```bash
# ブート一覧を確認
journalctl --list-boots

# 永続化されていない場合、再起動でログが消える
# /var/log/journal/ が存在するか確認
ls -la /var/log/journal/

# 存在しない場合は作成
sudo mkdir -p /var/log/journal
sudo systemctl restart systemd-journald
```

---

## 延伸阅读

- [systemd Journal Documentation](https://www.freedesktop.org/software/systemd/man/journalctl.html)
- [Linux Logging Best Practices](https://www.loggly.com/ultimate-guide/linux-logging-basics/)
- [jq Manual](https://stedolan.github.io/jq/manual/)
- 上一课：[06 - 性能问题](../06-performance/) -- USE 方法论实战
- 下一课：[08 - strace 调试](../08-strace/) -- 系统调用追踪

---

## 系列导航

[<-- 06 - 性能问题](../06-performance/) | [系列首页](../) | [08 - strace 调试 -->](../08-strace/)
