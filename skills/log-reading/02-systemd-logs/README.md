# 02 · systemd 服务日志分析（crash loop, timeout patterns）

> **目标**：识别 crash loop 模式和根本原因，理解 systemd StartLimitBurst 机制  
> **前置**：[01 · 日志分析工具与模式识别](../01-tools-patterns/)  
> **区域**：任意（本课在本地/EC2 均可练习）  
> **费用**：无额外费用

## 将完成的内容

1. 使用 journalctl 分析服务日志
2. 识别 crash loop 模式
3. 理解 StartLimitBurst/IntervalSec 机制
4. 识别 readiness/liveness probe 超时
5. 实战：分析服务崩溃循环的根因

---

## journalctl 服务日志分析

### 查看特定服务日志

```bash
# 查看 nginx 服务日志
journalctl -u nginx

# 实时跟踪服务日志
journalctl -u nginx -f

# 只看当前启动后的日志
journalctl -u nginx -b

# 只看上次启动的日志（排查重启前的问题）
journalctl -u nginx -b -1
```

### 常用过滤参数

```bash
# 最近 100 行
journalctl -u myapp -n 100

# 只看错误及以上
journalctl -u myapp -p err

# 指定时间范围
journalctl -u myapp --since "1 hour ago"
journalctl -u myapp --since "2024-06-22 10:00" --until "2024-06-22 11:00"

# 反向显示（最新在前）
journalctl -u myapp -r
```

### 输出格式

```bash
# JSON 格式（便于 jq 处理）
journalctl -u myapp -o json-pretty

# 简洁格式（无时间戳，只有消息）
journalctl -u myapp -o cat

# 详细格式（包含所有元数据）
journalctl -u myapp -o verbose
```

---

## Crash Loop 识别 {#crash-loop}

### 什么是 Crash Loop

服务启动后立即崩溃，systemd 反复尝试重启，形成"崩溃循环"。

### 典型日志模式

```
Jun 22 10:01:00 systemd[1]: app.service: Scheduled restart job, restart counter is at 5.
Jun 22 10:01:00 app[1234]: FATAL: Missing DB_URI
Jun 22 10:01:00 systemd[1]: app.service: Main process exited, code=exited, status=1/FAILURE
Jun 22 10:01:10 systemd[1]: app.service: Start request repeated too quickly.
Jun 22 10:01:10 systemd[1]: app.service: Failed with result 'start-limit-hit'.
```

### 识别关键词

| 关键词 | 含义 |
|--------|------|
| `restart counter is at N` | 已重启 N 次 |
| `Start request repeated too quickly` | 触发了重启限制 |
| `Failed with result 'start-limit-hit'` | 因重启次数过多被停止 |
| `FATAL` / `ERROR` | 应用层错误 |
| `code=exited, status=1` | 非正常退出 |

---

## StartLimitBurst/IntervalSec 机制

systemd 有内置的重启保护机制，防止服务无限重启消耗资源。

### 默认配置

```ini
# /lib/systemd/system/myapp.service 或 override
[Unit]
StartLimitIntervalSec=10s    # 时间窗口
StartLimitBurst=5            # 窗口内最大启动次数

[Service]
Restart=on-failure           # 失败时重启
RestartSec=100ms             # 重启间隔
```

### 机制说明

在 `StartLimitIntervalSec`（默认 10 秒）内，如果服务启动次数超过 `StartLimitBurst`（默认 5 次），systemd 会：
1. 停止尝试重启
2. 记录 `start-limit-hit`
3. 需要手动 `systemctl reset-failed` 才能再次启动

### 查看服务配置

```bash
# 查看服务完整配置
systemctl show myapp.service | grep -E 'StartLimit|Restart'

# 输出示例：
# StartLimitIntervalUSec=10s
# StartLimitBurst=5
# RestartUSec=100ms
```

### 重置失败计数

```bash
# 重置服务状态
sudo systemctl reset-failed myapp.service

# 然后重新启动
sudo systemctl start myapp.service
```

---

## Timeout 模式识别 {#timeout}

### readiness/liveness probe 超时

在 Kubernetes 环境中，探针超时是常见问题：

```
Jun 22 09:59:58 kubelet[222]: Liveness probe failed: Get http://127.0.0.1:8080/health: dial tcp 127.0.0.1:8080: connect: connection refused
Jun 22 10:00:28 kubelet[222]: Container app failed liveness probe, will be restarted
```

### systemd 服务超时

```bash
# 启动超时
Jun 22 10:01:30 systemd[1]: myapp.service: Start operation timed out. Terminating.

# 停止超时
Jun 22 10:02:00 systemd[1]: myapp.service: State 'stop-sigterm' timed out. Killing.
```

### 调整超时配置

```ini
[Service]
TimeoutStartSec=90       # 启动超时（默认 90s）
TimeoutStopSec=90        # 停止超时（默认 90s）
TimeoutSec=90            # 同时设置启动和停止超时
```

---

## 实战练习：分析 Crash Loop 根因

### 场景描述

应用服务 `app.service` 持续重启，需要找到根本原因。

### 日志样本

**journalctl -u app.service 输出：**
```
Jun 22 10:01:00 systemd[1]: app.service: Scheduled restart job, restart counter is at 5.
Jun 22 10:01:00 app[1234]: FATAL: Missing DB_URI
Jun 22 10:01:10 systemd[1]: app.service: Start request repeated too quickly.
```

**如果是 Kubernetes 环境（kubelet 日志）：**
```
Jun 22 09:59:58 kubelet[222]: Liveness probe failed: Get http://127.0.0.1:8080/health: dial tcp 127.0.0.1:8080: connect: connection refused
```

### 分析步骤

**Step 1: 查看服务当前状态**

```bash
systemctl status app.service
```

输出示例：
```
● app.service - My Application
     Loaded: loaded (/etc/systemd/system/app.service; enabled)
     Active: failed (Result: start-limit-hit) since ...
    Process: 1234 ExecStart=/usr/bin/app (code=exited, status=1/FAILURE)
   Main PID: 1234 (code=exited, status=1/FAILURE)
```

**Step 2: 查看历史日志，找第一个错误**

```bash
# 关键：看第一条 FATAL/ERROR，不是最后一条
journalctl -u app.service -b -1 | grep -E "FATAL|ERROR" | head -5
```

**Step 3: 检查环境变量配置**

```bash
# 如果是 env 缺失问题
cat /etc/systemd/system/app.service
# 或
systemctl cat app.service
```

**Step 4: 修复并重启**

```bash
# 添加缺失的环境变量
sudo systemctl edit app.service
# 添加：
# [Service]
# Environment="DB_URI=postgresql://..."

# 重载配置
sudo systemctl daemon-reload

# 重置失败状态
sudo systemctl reset-failed app.service

# 重新启动
sudo systemctl start app.service
```

### 发现要点

| 层次 | 发现 |
|------|------|
| **显而易见** | `FATAL: Missing DB_URI` 是直接原因 |
| **需要细看** | restart counter=5 触发 StartLimitBurst，10:01:10 后服务停止重试 |

---

## 常见 Crash Loop 原因

| 原因 | 日志特征 | 解决方案 |
|------|---------|---------|
| 缺少环境变量 | `Missing ENV_VAR` | 添加 Environment= 配置 |
| 配置文件错误 | `parse error`, `invalid config` | 检查配置文件语法 |
| 端口被占用 | `Address already in use` | 释放端口或更改配置 |
| 依赖服务未启动 | `connection refused` | 添加 After=/Requires= 依赖 |
| 权限问题 | `Permission denied` | 检查用户/文件权限 |
| 资源不足 | `OOM`, `out of memory` | 增加内存或调整限制 |

---

## 面试常见问题

### Q1: systemd restart counter 什么时候触发 StartLimitInterval?

**期望回答**：
> 在 `StartLimitIntervalSec`（默认 10 秒）时间窗口内，服务启动次数超过 `StartLimitBurst`（默认 5 次），就会触发限制。
> 触发后服务状态变为 `start-limit-hit`，需要 `systemctl reset-failed` 才能重新启动。

**红旗回答**：
- 误以为是 CPU 或内存限制
- 不知道这个机制的存在

### Q2: 如何确认 crash loop 原因在 env 缺失？

**期望回答**：
> 使用 `journalctl -u service -b -1` 查看上次启动的日志，找第一条 FATAL/ERROR 消息。
> 通常第一个错误才是根因，后续错误可能是级联影响。

**红旗回答**：
- 只看最后一条日志
- 不回溯历史

---

## 常见错误

1. **只看最后一条日志，不回溯第一个错误**
   - 第一个错误往往是根因

2. **不理解 StartLimitBurst 机制**
   - 误以为服务"死了"，实际是被 systemd 阻止重启

3. **混淆 ExecStart 失败和 readiness 超时**
   - ExecStart 失败：进程启动就崩溃
   - Readiness 超时：进程启动但未就绪

---

## 排查流程图

```
服务无法启动
    │
    ├── systemctl status 看状态
    │       │
    │       ├── active (running) → 服务正常
    │       ├── active (exited) → 一次性服务已完成
    │       ├── inactive (dead) → 已停止
    │       └── failed (start-limit-hit) → 触发重启限制
    │
    ├── journalctl -u xxx -b 看当前日志
    │       │
    │       └── 找 FATAL/ERROR
    │
    └── journalctl -u xxx -b -1 看上次日志
            │
            └── 找第一条错误（根因）
```

---

## 快速参考

| 需求 | 命令 |
|------|------|
| 查看服务状态 | `systemctl status <service>` |
| 查看服务日志 | `journalctl -u <service>` |
| 只看当前启动 | `journalctl -u <service> -b` |
| 只看上次启动 | `journalctl -u <service> -b -1` |
| 实时跟踪 | `journalctl -u <service> -f` |
| 只看错误 | `journalctl -u <service> -p err` |
| 重置失败状态 | `systemctl reset-failed <service>` |
| 查看服务配置 | `systemctl cat <service>` |

---

## 下一步

- [03 · Web 服务器日志](../03-web-server-logs/) - 分析 Nginx/Apache 5xx spike

## 系列导航 / Series Nav

| 课程 | 主题 |
|------|------|
| [00 · Linux 日志系统概览](../00-linux-logs/) | journalctl, dmesg, auth.log |
| [01 · 日志分析工具与模式识别](../01-tools-patterns/) | grep/rg/jq/less |
| **02 · systemd 服务日志分析** | 当前 |
| [03 · Web 服务器日志](../03-web-server-logs/) | Nginx/Apache 5xx |
| [04 · AWS 日志实战](../04-aws-logs/) | CloudTrail, VPC Flow |
| [05 · 故障时间线重建](../05-timeline-report/) | 障害報告書 |
| [06 · RCA 根因分析实战](../06-rca-practice/) | Five Whys |
