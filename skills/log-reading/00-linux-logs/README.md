# 00 · Linux 日志系统概览（journalctl, syslog, dmesg, auth.log）

> **目标**：理解 Linux 日志系统架构，掌握常用日志文件位置和用途  
> **前置**：基本 Linux 命令行操作  
> **区域**：任意（本课在本地/EC2 均可练习）  
> **费用**：无额外费用

## 将完成的内容

1. 理解 Linux 日志架构（journalctl vs syslog vs dmesg）
2. 掌握 `/var/log` 目录结构和常用日志文件
3. 使用 `journalctl` 查看 systemd 日志
4. 使用 `dmesg` 分析内核日志
5. 读懂 `auth.log` 认证日志
6. 实战：诊断 EBS 挂载导致的启动延迟

---

## Linux 日志系统架构

Linux 有多个日志来源，理解它们的区别是排查问题的第一步：

| 日志类型 | 命令/文件 | 用途 | 典型场景 |
|---------|----------|------|---------|
| **systemd journal** | `journalctl` | 服务日志、启动日志 | 服务崩溃、启动失败 |
| **syslog** | `/var/log/messages` | 传统系统日志 | 通用系统事件 |
| **内核日志** | `dmesg` | 内核 ring buffer | 硬件/驱动问题 |
| **认证日志** | `/var/log/auth.log` | SSH/sudo/PAM | 登录失败、权限问题 |

> **注意**：不同发行版日志位置略有差异：
> - Amazon Linux 2023 / RHEL / CentOS：`/var/log/messages`
> - Ubuntu / Debian：`/var/log/syslog`
> - 某些发行版只有 journalctl，无传统 syslog 文件

---

## Step 1 — 探索 /var/log 目录

首先看看系统有哪些日志文件：

```bash
ls -lh /var/log/
```

常见日志文件说明：

| 文件 | 内容 |
|------|------|
| `messages` / `syslog` | 系统通用日志 |
| `auth.log` / `secure` | 认证相关（SSH、sudo） |
| `dmesg` | 内核启动消息快照 |
| `boot.log` | 启动过程日志 |
| `cron` | 定时任务日志 |
| `nginx/` | Nginx access/error log |

---

## Step 2 — journalctl 基础 {#journalctl}

`journalctl` 是 systemd 的日志查看工具，功能强大：

### 查看所有日志

```bash
journalctl
```

### 查看特定服务日志

```bash
# 查看 sshd 服务日志
journalctl -u sshd

# 实时跟踪日志（类似 tail -f）
journalctl -u sshd -f
```

### 按时间过滤

```bash
# 当前启动的日志
journalctl -b

# 上次启动的日志（排查重启前问题）
journalctl -b -1

# 指定时间范围
journalctl --since "2024-06-20 09:00" --until "2024-06-20 10:00"

# 最近 10 分钟
journalctl --since "10 minutes ago"
```

### 按优先级过滤

```bash
# 只看 error 及以上
journalctl -p err

# 优先级：emerg, alert, crit, err, warning, notice, info, debug
```

### 输出格式

```bash
# JSON 格式（便于 jq 处理）
journalctl -u nginx -o json-pretty

# 简洁格式（无时间戳）
journalctl -u nginx -o cat
```

---

## Step 3 — dmesg 内核日志 {#dmesg}

`dmesg` 显示内核 ring buffer，主要用于：
- 硬件检测问题
- 驱动加载失败
- 磁盘/网络设备问题
- OOM（内存不足）事件

### 基本用法

```bash
# 查看最近的内核消息
dmesg | tail -20

# 带时间戳（更易读）
dmesg -T

# 只看 error/warning
dmesg --level=err,warn
```

### 常见需要关注的模式

```bash
# 磁盘错误
dmesg | grep -i 'error\|fail\|bad'

# OOM 事件
dmesg | grep -i 'out of memory\|oom'

# 网络设备问题
dmesg | grep -i 'eth\|eni\|link'
```

---

## Step 4 — auth.log 认证日志 {#auth}

认证日志记录所有登录尝试和权限操作：

### 文件位置

- Ubuntu/Debian: `/var/log/auth.log`
- RHEL/CentOS/Amazon Linux: `/var/log/secure`

### 常见日志模式

**SSH 登录成功：**
```
Jun 20 09:15:23 ip-10-0-1-5 sshd[1234]: Accepted publickey for ec2-user from 10.0.2.15 port 51234
```

**SSH 登录失败：**
```
Jun 20 09:15:25 ip-10-0-1-5 sshd[1235]: Failed password for invalid user admin from 203.0.113.24 port 55422
```

**sudo 命令记录：**
```
Jun 20 09:16:00 ip-10-0-1-5 sudo: ec2-user : TTY=pts/0 ; PWD=/home/ec2-user ; COMMAND=/bin/systemctl restart nginx
```

### 快速分析命令

```bash
# 查看登录失败
grep "Failed password" /var/log/auth.log

# 统计失败登录 IP（Amazon Linux 用 /var/log/secure）
grep "Failed password" /var/log/auth.log | awk '{print $(NF-3)}' | sort | uniq -c | sort -nr | head

# 查看 sudo 操作记录
grep "sudo:" /var/log/auth.log
```

---

## Step 5 — 日志时区注意事项

**关键概念**：日志时区处理是排查问题的常见坑！

| 日志来源 | 默认时区 | 注意事项 |
|---------|---------|---------|
| `journalctl` | 系统时区 | 可用 `--utc` 强制 UTC |
| AWS CloudTrail | UTC | 固定 UTC |
| Nginx access log | 可配置 | 检查 `log_format` |
| 应用日志 | 看框架 | Java 常用 UTC，需确认 |

**日本环境特别注意**：
- 系统时区通常是 JST (+0900)
- AWS 服务日志通常是 UTC
- 关联日志时**必须统一时区**

```bash
# 查看系统时区
timedatectl

# journalctl 用 UTC 显示
journalctl --utc

# 时区转换：UTC → JST
# UTC 2024-06-20 00:00:00 = JST 2024-06-20 09:00:00
```

---

## 实战练习：诊断 EBS 挂载导致的启动延迟

### 场景描述

运维同事反馈：「EC2 实例最近添加了一块 EBS 后，重启变慢了约 30 秒。」

### 日志样本

**dmesg 输出：**
```
[  12.3] EXT4-fs (xvdf): bad geometry: block count 0
```

**journalctl -b | grep fstab 输出：**
```
Jun 20 09:12:18 ip-10-0-1-5 systemd[1]: Failed to mount /data.
Jun 20 09:12:48 systemd[1]: dev-xvdf.device: Job timed out.
```

### 分析步骤

1. **看 dmesg**：`bad geometry: block count 0` 表示文件系统有问题
2. **看 journalctl**：mount 失败后，等待 30 秒超时（09:12:18 → 09:12:48）
3. **根因**：EBS 未正确格式化，fstab 配置了挂载但设备无有效文件系统

### 发现要点

| 层次 | 发现 |
|------|------|
| **显而易见** | `Failed to mount /data` 错误 |
| **需要细看** | 30 秒 timeout 延迟导致 boot 变慢（时间差 09:12:18 到 09:12:48） |

### 修复建议

```bash
# 1. 检查设备
lsblk

# 2. 格式化 EBS（注意：会清空数据！）
sudo mkfs.ext4 /dev/xvdf

# 3. 或者从 fstab 移除/注释该条目
sudo vi /etc/fstab
# 添加 nofail 选项避免启动阻塞
/dev/xvdf /data ext4 defaults,nofail 0 2
```

---

## 面试常见问题

### Q1: journalctl 与 dmesg 有什么区别？

**期望回答**：
> journalctl 是 systemd 日志，记录服务启动/停止、应用日志等用户空间事件。
> dmesg 是 kernel ring buffer，记录内核层面的消息，如硬件检测、驱动加载、OOM 等。

**红旗回答**：
- 回答「一样」
- 仅说「都看日志」

### Q2: auth.log 中登录失败与 PAM 日志如何关联？

**期望回答**：
> sshd 调用 PAM stack 进行认证，auth.log 同时记录 sshd 事件和 PAM 认证结果。
> 可以通过 PID 或时间戳关联同一次登录尝试。

**红旗回答**：
- 只说 grep 命令，不理解日志关联

---

## 常见错误

1. **混淆 journalctl 和 dmesg 的用途**
   - journalctl 看服务，dmesg 看内核

2. **不知道 /var/log/messages 在某些发行版不存在**
   - Ubuntu 用 `/var/log/syslog`
   - 现代系统可能只有 journalctl

3. **忽略 boot 日志中的 timeout 模式**
   - 超时等待往往隐藏在时间戳差值中

---

## 快速参考

| 需求 | 命令 |
|------|------|
| 看服务日志 | `journalctl -u <service>` |
| 看当前启动日志 | `journalctl -b` |
| 看上次启动日志 | `journalctl -b -1` |
| 看内核消息 | `dmesg -T` |
| 看认证日志 | `cat /var/log/auth.log` 或 `secure` |
| 实时跟踪 | `journalctl -f` |
| 只看错误 | `journalctl -p err` |

---

## 下一步

- [01 · 日志分析工具与模式识别](../01-tools-patterns/) - 学习 grep/rg/jq/less 工具链

## 系列导航 / Series Nav

| 课程 | 主题 |
|------|------|
| **00 · Linux 日志系统概览** | 当前 |
| [01 · 日志分析工具与模式识别](../01-tools-patterns/) | grep/rg/jq/less |
| [02 · systemd 服务日志分析](../02-systemd-logs/) | crash loop, timeout |
| [03 · Web 服务器日志](../03-web-server-logs/) | Nginx/Apache 5xx |
| [04 · AWS 日志实战](../04-aws-logs/) | CloudTrail, VPC Flow |
| [05 · 故障时间线重建](../05-timeline-report/) | 障害報告書 |
| [06 · RCA 根因分析实战](../06-rca-practice/) | Five Whys |
