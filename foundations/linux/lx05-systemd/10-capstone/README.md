# 10 - 综合项目：生产级服务（Capstone: Production-Ready Service）

> **目标**：综合运用所有知识，创建一个生产级的 systemd 服务配置  
> **前置**：已完成本课程 01-09 所有课程  
> **时间**：90-120 分钟  
> **实战场景**：本番環境のアプリケーション管理 - 创建完整的 Web 应用服务栈  

---

## 将学到的内容

1. 创建完整的生产级服务配置
2. 实现定时任务（Timer）
3. 配置资源限制
4. 应用安全加固
5. 通过 systemd-analyze security 审计

---

## 综合项目要求

本次综合项目将创建一个**完整的 Web 应用服务栈**，包含以下组件：

| 组件 | 文件 | 用途 |
|------|------|------|
| 主服务 | `myapp.service` | Web 应用主进程 |
| 健康检查 | `myapp-health.timer` + `.service` | 定期检查应用健康状态 |
| 日志清理 | `myapp-logrotate.timer` + `.service` | 定期清理旧日志 |
| 资源限制 | `myapp.service.d/10-resources.conf` | Drop-in 资源配置 |
| 安全加固 | `myapp.service.d/20-security.conf` | Drop-in 安全配置 |

### 必须满足的要求

**服务要求**：
- [ ] Type=notify 或适当的类型
- [ ] 正确的依赖关系（After, Wants）
- [ ] Restart=on-failure with RestartSec
- [ ] StartLimitIntervalSec 防止重启风暴
- [ ] User/Group 非 root 运行

**Timer 要求**：
- [ ] 配套的 .timer 文件
- [ ] OnCalendar 或 Monotonic 计时
- [ ] Persistent=true
- [ ] RandomizedDelaySec 防雷群

**资源控制要求**：
- [ ] MemoryMax 硬限制
- [ ] CPUQuota 或 CPUWeight
- [ ] TasksMax fork 保护

**安全要求**：
- [ ] NoNewPrivileges=yes
- [ ] PrivateTmp=yes
- [ ] ProtectSystem=strict
- [ ] ProtectHome=yes
- [ ] systemd-analyze security 评分 < 5.0

**日志要求**：
- [ ] StandardOutput/StandardError=journal
- [ ] 可使用 journalctl -u 查看日志

---

## Step 1 -- 准备工作（10 分钟）

### 1.1 创建应用用户和目录

```bash
# 创建专用用户和组
sudo useradd -r -s /sbin/nologin -d /opt/myapp myapp

# 创建应用目录结构
sudo mkdir -p /opt/myapp/{bin,config,logs,data}
sudo mkdir -p /var/lib/myapp
sudo mkdir -p /var/log/myapp

# 设置权限
sudo chown -R myapp:myapp /opt/myapp /var/lib/myapp /var/log/myapp
sudo chmod 755 /opt/myapp
sudo chmod 750 /opt/myapp/config
```

### 1.2 创建模拟应用

```bash
# 创建模拟 Web 应用脚本
sudo tee /opt/myapp/bin/myapp << 'EOF'
#!/bin/bash
# =============================================================================
# MyApp - Simulated Web Application
# =============================================================================
# This script simulates a web application for systemd training
# It supports Type=notify by sending READY=1 after initialization

set -e

APP_NAME="myapp"
PID_FILE="/var/lib/myapp/myapp.pid"
LOG_FILE="/var/log/myapp/myapp.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Signal handlers
cleanup() {
    log "Received shutdown signal, stopping..."
    rm -f "$PID_FILE"
    log "MyApp stopped gracefully"
    exit 0
}

reload_config() {
    log "Received SIGHUP, reloading configuration..."
    # Simulate config reload
    sleep 1
    log "Configuration reloaded"
}

trap cleanup SIGTERM SIGINT
trap reload_config SIGHUP

# Initialization phase
log "MyApp starting..."
log "PID: $$"
echo $$ > "$PID_FILE"

# Simulate initialization (loading config, connecting to DB, etc.)
log "Loading configuration..."
sleep 1
log "Connecting to database..."
sleep 1
log "Initializing cache..."
sleep 1

# Notify systemd that we're ready (for Type=notify)
if [ -n "$NOTIFY_SOCKET" ]; then
    log "Sending READY notification to systemd"
    systemd-notify --ready --status="MyApp is running"
fi

log "MyApp is now ready and accepting connections"

# Main loop - simulate a running web server
counter=0
while true; do
    sleep 30
    counter=$((counter + 1))
    log "Heartbeat #$counter - MyApp is healthy"

    # Update systemd status periodically
    if [ -n "$NOTIFY_SOCKET" ]; then
        systemd-notify --status="Running: $counter heartbeats"
    fi
done
EOF

sudo chmod +x /opt/myapp/bin/myapp
sudo chown myapp:myapp /opt/myapp/bin/myapp
```

### 1.3 创建健康检查脚本

```bash
# 创建健康检查脚本
sudo tee /opt/myapp/bin/health-check << 'EOF'
#!/bin/bash
# =============================================================================
# MyApp Health Check Script
# =============================================================================
# Checks if MyApp is running and healthy

APP_NAME="myapp"
PID_FILE="/var/lib/myapp/myapp.pid"
LOG_FILE="/var/log/myapp/health-check.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log "Starting health check..."

# Check if PID file exists
if [ ! -f "$PID_FILE" ]; then
    log "ERROR: PID file not found"
    exit 1
fi

# Check if process is running
PID=$(cat "$PID_FILE")
if ! kill -0 "$PID" 2>/dev/null; then
    log "ERROR: Process $PID is not running"
    exit 1
fi

# Check if main log has recent entries
LAST_LOG_TIME=$(stat -c %Y /var/log/myapp/myapp.log 2>/dev/null || echo 0)
CURRENT_TIME=$(date +%s)
LOG_AGE=$((CURRENT_TIME - LAST_LOG_TIME))

if [ "$LOG_AGE" -gt 120 ]; then
    log "WARNING: No log activity for $LOG_AGE seconds"
    # Not failing, just warning
fi

log "Health check PASSED - PID: $PID"
exit 0
EOF

sudo chmod +x /opt/myapp/bin/health-check
sudo chown myapp:myapp /opt/myapp/bin/health-check
```

### 1.4 创建日志清理脚本

```bash
# 创建日志清理脚本
sudo tee /opt/myapp/bin/logrotate << 'EOF'
#!/bin/bash
# =============================================================================
# MyApp Log Rotation Script
# =============================================================================
# Rotates and cleans up old log files

LOG_DIR="/var/log/myapp"
MAX_LOG_FILES=7
MAX_LOG_SIZE_MB=100

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

log "Starting log rotation..."

# Rotate logs if they exceed size limit
for logfile in "$LOG_DIR"/*.log; do
    if [ -f "$logfile" ]; then
        SIZE_MB=$(du -m "$logfile" 2>/dev/null | cut -f1)
        if [ "${SIZE_MB:-0}" -gt "$MAX_LOG_SIZE_MB" ]; then
            TIMESTAMP=$(date +%Y%m%d_%H%M%S)
            mv "$logfile" "${logfile}.${TIMESTAMP}"
            gzip "${logfile}.${TIMESTAMP}"
            log "Rotated: $logfile (${SIZE_MB}MB)"
        fi
    fi
done

# Clean up old rotated logs
find "$LOG_DIR" -name "*.log.*.gz" -mtime +$MAX_LOG_FILES -delete
log "Cleaned up logs older than $MAX_LOG_FILES days"

log "Log rotation completed"
EOF

sudo chmod +x /opt/myapp/bin/logrotate
sudo chown myapp:myapp /opt/myapp/bin/logrotate
```

---

## Step 2 -- 创建主服务（myapp.service）（15 分钟）

### 2.1 主服务 Unit 文件

```bash
# 创建主服务文件
sudo tee /etc/systemd/system/myapp.service << 'EOF'
# =============================================================================
# myapp.service - MyApp Web Application Service
# =============================================================================
# Production-ready systemd unit file for a web application
#
# Features:
#   - Type=notify for proper startup detection
#   - Proper dependencies and ordering
#   - Restart policy with rate limiting
#   - Non-root user execution
#   - Journal logging
#
# Created for: systemd 深入课程 - 综合项目
# =============================================================================

[Unit]
Description=MyApp Web Application Service
Documentation=https://example.com/myapp/docs

# Dependencies: Start after network is ready
After=network-online.target
Wants=network-online.target

# If you have database dependency:
# After=network-online.target postgresql.service
# Wants=network-online.target postgresql.service

[Service]
# -----------------------------------------------------------------------------
# Service Type
# -----------------------------------------------------------------------------
# Type=notify: The service sends READY=1 when fully initialized
# This ensures systemd waits for actual readiness, not just process start
Type=notify
NotifyAccess=main

# -----------------------------------------------------------------------------
# User and Group
# -----------------------------------------------------------------------------
# NEVER run as root in production!
User=myapp
Group=myapp

# -----------------------------------------------------------------------------
# Working Directory and Environment
# -----------------------------------------------------------------------------
WorkingDirectory=/opt/myapp

# Environment variables (non-sensitive)
Environment=APP_ENV=production
Environment=LOG_LEVEL=info

# For sensitive data, use EnvironmentFile with proper permissions
# EnvironmentFile=/opt/myapp/config/secrets
# Make sure secrets file has 0600 permissions!

# -----------------------------------------------------------------------------
# Execution
# -----------------------------------------------------------------------------
ExecStart=/opt/myapp/bin/myapp
ExecReload=/bin/kill -HUP $MAINPID

# -----------------------------------------------------------------------------
# Restart Policy
# -----------------------------------------------------------------------------
# Restart on failure, but not on clean exit
Restart=on-failure
RestartSec=5

# Prevent restart loops (restart storm protection)
# Max 5 restarts in 300 seconds, then give up
StartLimitIntervalSec=300
StartLimitBurst=5

# -----------------------------------------------------------------------------
# Timeouts
# -----------------------------------------------------------------------------
# Time to wait for startup notification
TimeoutStartSec=60

# Time to wait for graceful shutdown
TimeoutStopSec=30

# -----------------------------------------------------------------------------
# Logging
# -----------------------------------------------------------------------------
StandardOutput=journal
StandardError=journal
SyslogIdentifier=myapp

[Install]
WantedBy=multi-user.target
EOF
```

### 2.2 创建资源限制 Drop-in

```bash
# 创建 Drop-in 目录
sudo mkdir -p /etc/systemd/system/myapp.service.d

# 创建资源限制配置
sudo tee /etc/systemd/system/myapp.service.d/10-resources.conf << 'EOF'
# =============================================================================
# 10-resources.conf - Resource Limits for MyApp
# =============================================================================
# Drop-in file for resource control
#
# Memory: Prevents OOM and protects other services
# CPU: Ensures fair sharing with production workloads
# Tasks: Fork bomb protection
# =============================================================================

[Service]
# -----------------------------------------------------------------------------
# CPU Limits
# -----------------------------------------------------------------------------
# Hard limit: Maximum 50% of one CPU core
CPUQuota=50%

# Soft limit: Lower priority when competing for CPU
CPUWeight=80

# -----------------------------------------------------------------------------
# Memory Limits
# -----------------------------------------------------------------------------
# Hard limit: Kill if exceeds 512MB
MemoryMax=512M

# Soft limit: Apply pressure at 400MB
MemoryHigh=400M

# Disable swap (prevent performance degradation)
MemorySwapMax=0

# -----------------------------------------------------------------------------
# Process Limits
# -----------------------------------------------------------------------------
# Maximum tasks (processes + threads) - fork bomb protection
TasksMax=64

# -----------------------------------------------------------------------------
# I/O Limits (optional)
# -----------------------------------------------------------------------------
# Lower I/O priority for batch-like workloads
IOWeight=80

# -----------------------------------------------------------------------------
# Traditional Limits
# -----------------------------------------------------------------------------
# Maximum open files
LimitNOFILE=65535
EOF
```

### 2.3 创建安全加固 Drop-in

```bash
# 创建安全加固配置
sudo tee /etc/systemd/system/myapp.service.d/20-security.conf << 'EOF'
# =============================================================================
# 20-security.conf - Security Hardening for MyApp
# =============================================================================
# Drop-in file for security hardening
#
# Goal: systemd-analyze security score < 5.0
#
# IMPORTANT: Test incrementally! Some directives may break your app.
# =============================================================================

[Service]
# -----------------------------------------------------------------------------
# Privilege Restrictions
# -----------------------------------------------------------------------------
# Prevent privilege escalation via setuid/setgid
NoNewPrivileges=yes

# Restrict SUID/SGID file creation
RestrictSUIDSGID=yes

# Drop all capabilities except what's needed
# Remove CAP_NET_BIND_SERVICE if not binding to ports < 1024
CapabilityBoundingSet=CAP_NET_BIND_SERVICE

# Ambient capabilities (if needed for binding to privileged ports)
# AmbientCapabilities=CAP_NET_BIND_SERVICE

# -----------------------------------------------------------------------------
# Filesystem Protection
# -----------------------------------------------------------------------------
# Make /usr, /boot, /etc read-only
ProtectSystem=strict

# Prevent access to /home, /root
ProtectHome=yes

# Private /tmp (isolated from other processes)
PrivateTmp=yes

# Private /dev (limited device access)
PrivateDevices=yes

# Directories this service can write to (exceptions)
ReadWritePaths=/var/lib/myapp /var/log/myapp

# -----------------------------------------------------------------------------
# Kernel Protection
# -----------------------------------------------------------------------------
# Prevent modifying kernel tunables (/proc/sys)
ProtectKernelTunables=yes

# Prevent loading kernel modules
ProtectKernelModules=yes

# Prevent accessing kernel logs
ProtectKernelLogs=yes

# Prevent modifying control groups
ProtectControlGroups=yes

# -----------------------------------------------------------------------------
# Network Restrictions
# -----------------------------------------------------------------------------
# Restrict to IPv4, IPv6, and Unix sockets only
RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX

# -----------------------------------------------------------------------------
# System Call Filtering
# -----------------------------------------------------------------------------
# Only allow system calls needed for typical services
SystemCallFilter=@system-service

# Only allow native architecture (prevent 32-bit exploits on 64-bit)
SystemCallArchitectures=native

# -----------------------------------------------------------------------------
# Additional Hardening
# -----------------------------------------------------------------------------
# Prevent personality changes
LockPersonality=yes

# Prevent real-time scheduling (not needed for web apps)
RestrictRealtime=yes

# Prevent namespace creation
RestrictNamespaces=yes

# Protect clock (prevent time manipulation)
ProtectClock=yes

# Protect hostname
ProtectHostname=yes

# Deny write+execute memory (prevents some exploits)
# WARNING: May break JIT compilers (Node.js, Java)
# MemoryDenyWriteExecute=yes
EOF
```

---

## Step 3 -- 创建健康检查 Timer（10 分钟）

### 3.1 健康检查服务

```bash
# 创建健康检查 Service
sudo tee /etc/systemd/system/myapp-health.service << 'EOF'
# =============================================================================
# myapp-health.service - Health Check Service for MyApp
# =============================================================================
# Triggered by myapp-health.timer to check application health
# Type=oneshot for short-lived tasks
# =============================================================================

[Unit]
Description=MyApp Health Check
# Only run if main service is active
After=myapp.service
Requires=myapp.service

[Service]
Type=oneshot
User=myapp
Group=myapp

ExecStart=/opt/myapp/bin/health-check

# Logging
StandardOutput=journal
StandardError=journal
SyslogIdentifier=myapp-health

# Quick timeout for health checks
TimeoutStartSec=30

# Security (inherit most from main service concept)
NoNewPrivileges=yes
ProtectSystem=strict
ProtectHome=yes
PrivateTmp=yes
ReadOnlyPaths=/opt/myapp
ReadWritePaths=/var/log/myapp /var/lib/myapp
EOF
```

### 3.2 健康检查 Timer

```bash
# 创建健康检查 Timer
sudo tee /etc/systemd/system/myapp-health.timer << 'EOF'
# =============================================================================
# myapp-health.timer - Health Check Timer for MyApp
# =============================================================================
# Runs health check every 5 minutes
# Uses Monotonic timer (OnUnitActiveSec) for interval-based execution
# =============================================================================

[Unit]
Description=MyApp Health Check Timer
# Only activate if main service is active
After=myapp.service
Requires=myapp.service

[Timer]
# First check 1 minute after timer starts
OnActiveSec=1min

# Then check every 5 minutes
OnUnitActiveSec=5min

# Accuracy: 30 seconds is fine for health checks
AccuracySec=30s

[Install]
WantedBy=timers.target
EOF
```

---

## Step 4 -- 创建日志清理 Timer（10 分钟）

### 4.1 日志清理服务

```bash
# 创建日志清理 Service
sudo tee /etc/systemd/system/myapp-logrotate.service << 'EOF'
# =============================================================================
# myapp-logrotate.service - Log Rotation Service for MyApp
# =============================================================================
# Triggered by myapp-logrotate.timer to clean up old logs
# Type=oneshot for short-lived tasks
# =============================================================================

[Unit]
Description=MyApp Log Rotation
After=myapp.service

[Service]
Type=oneshot
User=myapp
Group=myapp

ExecStart=/opt/myapp/bin/logrotate

# Logging
StandardOutput=journal
StandardError=journal
SyslogIdentifier=myapp-logrotate

# Timeout
TimeoutStartSec=120

# Resource limits for batch task
CPUQuota=25%
MemoryMax=128M

# Security
NoNewPrivileges=yes
ProtectSystem=strict
ProtectHome=yes
PrivateTmp=yes
ReadWritePaths=/var/log/myapp
EOF
```

### 4.2 日志清理 Timer

```bash
# 创建日志清理 Timer
sudo tee /etc/systemd/system/myapp-logrotate.timer << 'EOF'
# =============================================================================
# myapp-logrotate.timer - Log Rotation Timer for MyApp
# =============================================================================
# Runs log rotation daily at 04:00
# Uses Realtime timer (OnCalendar) for time-based execution
# =============================================================================

[Unit]
Description=MyApp Log Rotation Timer

[Timer]
# Run daily at 04:00
OnCalendar=*-*-* 04:00:00

# IMPORTANT: Catch up on missed runs (e.g., server was down)
Persistent=true

# Random delay to prevent thundering herd (if multiple servers)
RandomizedDelaySec=30min

# Accuracy: 1 minute is fine for daily tasks
AccuracySec=1min

[Install]
WantedBy=timers.target
EOF
```

---

## Step 5 -- 部署和验证（20 分钟）

### 5.1 验证 Unit 文件语法

```bash
# 重新加载 systemd 配置
sudo systemctl daemon-reload

# 验证所有 Unit 文件语法
echo "=== Verifying Unit Files ==="

for unit in myapp.service myapp-health.service myapp-health.timer myapp-logrotate.service myapp-logrotate.timer; do
    echo -n "Checking $unit... "
    if sudo systemd-analyze verify "/etc/systemd/system/$unit" 2>&1 | grep -q "error\|Error"; then
        echo "FAILED"
        sudo systemd-analyze verify "/etc/systemd/system/$unit"
    else
        echo "OK"
    fi
done
```

### 5.2 启动服务

```bash
# 启动主服务
sudo systemctl start myapp.service

# 等待服务就绪
echo "Waiting for service to be ready..."
sleep 5

# 检查服务状态
systemctl status myapp.service

# 启用开机自启
sudo systemctl enable myapp.service
```

### 5.3 启动 Timer

```bash
# 启用并启动健康检查 Timer
sudo systemctl enable --now myapp-health.timer

# 启用并启动日志清理 Timer
sudo systemctl enable --now myapp-logrotate.timer

# 查看所有 Timer 状态
systemctl list-timers --all | grep myapp
```

### 5.4 安全审计

```bash
# 对主服务进行安全审计
echo "=== Security Audit ==="
sudo systemd-analyze security myapp.service

# 预期：评分应该 < 5.0
# 如果评分过高，检查哪些项目标记为红色，考虑添加更多加固
```

**预期输出示例**：

```
  NAME                            DESCRIPTION                           EXPOSURE
✓ NoNewPrivileges=                Service processes cannot acquire...       0.0
✓ PrivateDevices=                 Service has no access to hardware...      0.0
✓ ProtectHome=                    Service cannot access home direct...      0.0
✓ ProtectSystem=                  Service cannot modify system dir...       0.0
...
→ Overall exposure level for myapp.service: 3.8 OK
```

### 5.5 验证资源限制

```bash
# 查看资源配置
echo "=== Resource Configuration ==="
systemctl show myapp -p CPUQuota,CPUWeight,MemoryMax,MemoryHigh,TasksMax

# 使用 systemd-cgtop 监控（新终端）
echo "Run in another terminal: sudo systemd-cgtop | grep myapp"

# 查看 cgroup 详情
echo "=== cgroup Details ==="
cat /sys/fs/cgroup/system.slice/myapp.service/memory.max 2>/dev/null || echo "cgroup v1 or service not running"
cat /sys/fs/cgroup/system.slice/myapp.service/cpu.max 2>/dev/null || echo "cgroup v1 or service not running"
```

### 5.6 验证日志

```bash
# 查看主服务日志
echo "=== Service Logs ==="
sudo journalctl -u myapp.service --since "5 minutes ago"

# 查看健康检查日志
echo "=== Health Check Logs ==="
sudo journalctl -u myapp-health.service --since "5 minutes ago"

# 实时跟踪日志
echo "Run for live logs: sudo journalctl -u myapp.service -f"
```

### 5.7 测试重启策略

```bash
# 手动杀死进程，观察自动重启
echo "=== Testing Restart Policy ==="
PID=$(systemctl show myapp -p MainPID --value)
echo "Main PID: $PID"

# 模拟崩溃
sudo kill -9 $PID

# 等待并检查
sleep 10
systemctl status myapp.service

# 应该看到服务已经自动重启
```

### 5.8 手动触发 Timer 测试

```bash
# 手动触发健康检查（不用等 5 分钟）
echo "=== Manual Health Check ==="
sudo systemctl start myapp-health.service
systemctl status myapp-health.service
sudo journalctl -u myapp-health.service -n 10

# 手动触发日志清理（不用等到 04:00）
echo "=== Manual Log Rotation ==="
sudo systemctl start myapp-logrotate.service
systemctl status myapp-logrotate.service
sudo journalctl -u myapp-logrotate.service -n 10
```

---

## Step 6 -- 完整文件清单（参考）

本项目创建的所有文件：

```
/opt/myapp/                         # 应用目录
├── bin/
│   ├── myapp                       # 主应用
│   ├── health-check                # 健康检查脚本
│   └── logrotate                   # 日志清理脚本
├── config/                         # 配置目录
├── logs/                           # 应用日志（旧）
└── data/                           # 应用数据

/var/lib/myapp/                     # 运行时数据
└── myapp.pid                       # PID 文件

/var/log/myapp/                     # 日志目录
├── myapp.log                       # 主服务日志
└── health-check.log                # 健康检查日志

/etc/systemd/system/                # systemd Unit 文件
├── myapp.service                   # 主服务
├── myapp.service.d/                # Drop-in 目录
│   ├── 10-resources.conf           # 资源限制
│   └── 20-security.conf            # 安全加固
├── myapp-health.service            # 健康检查服务
├── myapp-health.timer              # 健康检查定时器
├── myapp-logrotate.service         # 日志清理服务
└── myapp-logrotate.timer           # 日志清理定时器
```

---

## 评估检查清单

在提交项目之前，确保满足以下所有要求：

### 服务配置

- [ ] `systemd-analyze verify myapp.service` 无错误
- [ ] 服务使用 `Type=notify` 或适当类型
- [ ] 配置了正确的依赖关系（After, Wants）
- [ ] 配置了 `Restart=on-failure` 和 `RestartSec`
- [ ] 配置了 `StartLimitIntervalSec` 和 `StartLimitBurst`
- [ ] 使用非 root 用户运行（User/Group）

### Timer 配置

- [ ] `systemd-analyze verify myapp-health.timer` 无错误
- [ ] `systemd-analyze verify myapp-logrotate.timer` 无错误
- [ ] 日志清理 Timer 配置了 `Persistent=true`
- [ ] 日志清理 Timer 配置了 `RandomizedDelaySec`
- [ ] `systemctl list-timers` 显示正确的 NEXT 时间

### 资源控制

- [ ] 配置了 `MemoryMax`
- [ ] 配置了 `MemoryHigh`（MemoryMax 的约 75%）
- [ ] 配置了 `CPUQuota` 或 `CPUWeight`
- [ ] 配置了 `TasksMax`
- [ ] `systemctl show myapp -p MemoryMax,CPUQuota,TasksMax` 显示正确值

### 安全加固

- [ ] 配置了 `NoNewPrivileges=yes`
- [ ] 配置了 `PrivateTmp=yes`
- [ ] 配置了 `ProtectSystem=strict`
- [ ] 配置了 `ProtectHome=yes`
- [ ] `systemd-analyze security myapp.service` 评分 < 5.0

### 日志

- [ ] 配置了 `StandardOutput=journal`
- [ ] 配置了 `StandardError=journal`
- [ ] `journalctl -u myapp.service` 可以查看日志
- [ ] `journalctl -u myapp-health.service` 可以查看健康检查日志

### 功能验证

- [ ] `systemctl start myapp.service` 成功启动
- [ ] `systemctl stop myapp.service` 正常停止
- [ ] `systemctl restart myapp.service` 正常重启
- [ ] 杀死进程后服务自动重启
- [ ] 手动触发 Timer 任务成功执行

---

## 清理测试环境

完成测试后，清理创建的资源：

```bash
# 停止所有服务和 Timer
sudo systemctl stop myapp-health.timer myapp-logrotate.timer
sudo systemctl stop myapp.service

# 禁用开机自启
sudo systemctl disable myapp.service myapp-health.timer myapp-logrotate.timer

# 删除 Unit 文件
sudo rm -rf /etc/systemd/system/myapp.service
sudo rm -rf /etc/systemd/system/myapp.service.d
sudo rm -rf /etc/systemd/system/myapp-health.service
sudo rm -rf /etc/systemd/system/myapp-health.timer
sudo rm -rf /etc/systemd/system/myapp-logrotate.service
sudo rm -rf /etc/systemd/system/myapp-logrotate.timer

# 重新加载配置
sudo systemctl daemon-reload

# 删除应用和数据
sudo rm -rf /opt/myapp
sudo rm -rf /var/lib/myapp
sudo rm -rf /var/log/myapp

# 删除用户
sudo userdel myapp
```

---

## 其他 Capstone 选项（可选）

除了 Web 应用服务，你也可以选择实现以下场景：

### 选项 2：监控 Agent（監視エージェント）

| 组件 | 文件 | 用途 |
|------|------|------|
| Agent 服务 | `monitor-agent.service` | 监控 Agent 主进程 |
| 指标收集 | `metrics-collect.timer` | 每分钟收集系统指标 |
| 告警检查 | `alert-check.timer` | 每 5 分钟检查告警条件 |

**日本 IT 场景**：運用監視システムの構築

### 选项 3：批处理系统（バッチ処理システム）

| 组件 | 文件 | 用途 |
|------|------|------|
| 批处理服务 | `batch-job.service` | 数据处理任务 |
| 每日执行 | `batch-job.timer` | 每天凌晨 3 点执行 |
| 严格资源限制 | Drop-in | 防止影响生产服务 |

**日本 IT 场景**：夜間バッチ処理の確実な実行

---

## 反模式：综合项目常见错误

### 错误 1：忘记 daemon-reload

```bash
# 错误：修改文件后直接重启
sudo vim /etc/systemd/system/myapp.service
sudo systemctl restart myapp

# 正确：先 daemon-reload
sudo vim /etc/systemd/system/myapp.service
sudo systemctl daemon-reload
sudo systemctl restart myapp

# 或者使用 systemctl edit（自动 daemon-reload）
sudo systemctl edit myapp.service
```

### 错误 2：Timer 没有 Persistent=true

```ini
# 错误：服务器维护重启后丢失任务
[Timer]
OnCalendar=*-*-* 03:00:00
# 没有 Persistent=true

# 正确：确保补执行
[Timer]
OnCalendar=*-*-* 03:00:00
Persistent=true
```

### 错误 3：安全加固过度导致服务无法启动

```ini
# 错误：一次性添加所有加固指令
[Service]
PrivateNetwork=yes      # Web 服务需要网络！
ProtectSystem=strict    # 需要设置 ReadWritePaths 例外

# 正确：渐进式添加，设置必要例外
[Service]
ProtectSystem=strict
ReadWritePaths=/var/lib/myapp /var/log/myapp
# PrivateNetwork=no（默认值，不需要设置）
```

### 错误 4：资源限制设置不合理

```ini
# 错误：限制太低
[Service]
MemoryMax=64M          # Web 应用通常需要更多
CPUQuota=5%            # 太低会导致响应慢

# 正确：根据实际需求设置
[Service]
MemoryMax=512M
MemoryHigh=400M        # 不要忘记软限制
CPUQuota=50%
```

### 错误 5：依赖配置错误

```ini
# 错误：只有 After 没有 Wants
[Unit]
After=postgresql.service
# 数据库不会被自动启动！

# 正确：After + Wants 组合
[Unit]
After=postgresql.service
Wants=postgresql.service
```

---

## 职场小贴士（Japan IT Context）

### 本番環境のアプリケーション管理

在日本 IT 企业，生产环境的应用管理有严格要求：

| 日语术语 | 含义 | 本项目对应 |
|----------|------|------------|
| 本番環境 | Production Environment | 完整的生产级配置 |
| 変更管理 | Change Management | Drop-in 文件安全修改 |
| 監視 | Monitoring | Health check timer |
| 障害対応 | Incident Response | Restart 策略 + 日志 |
| セキュリティ | Security | 安全加固 Drop-in |
| リソース管理 | Resource Management | 资源限制 Drop-in |

### 运维手册模板

日本企业通常要求完整的运维文档：

```markdown
# MyApp 運用手順書

## 1. サービス概要
- サービス名: myapp.service
- 機能: Web アプリケーション
- 稼働環境: 本番環境

## 2. 起動・停止手順

### 起動
```bash
sudo systemctl start myapp.service
systemctl status myapp.service
```

### 停止
```bash
sudo systemctl stop myapp.service
```

### 再起動
```bash
sudo systemctl restart myapp.service
```

## 3. 監視項目
- ヘルスチェック: myapp-health.timer（5分間隔）
- ログローテーション: myapp-logrotate.timer（毎日04:00）

## 4. 障害対応

### サービスが起動しない場合
1. ログ確認: `journalctl -u myapp.service -n 100`
2. 設定確認: `systemctl cat myapp.service`
3. 権限確認: `ls -la /opt/myapp/bin/myapp`

### サービスが繰り返し再起動する場合
1. StartLimitBurst 到達確認: `systemctl status myapp.service`
2. エラーログ確認: `journalctl -u myapp.service --since "1 hour ago"`
3. リセット: `systemctl reset-failed myapp.service`
```

---

## 检查清单（最终确认）

完成本课后，你应该能够：

- [ ] 从零开始创建生产级 systemd 服务配置
- [ ] 正确使用 Type=notify 实现启动就绪检测
- [ ] 配置合理的 Restart 策略和 StartLimit 防止重启风暴
- [ ] 创建配套的 Timer 实现健康检查和日志清理
- [ ] 使用 Drop-in 文件分离资源限制和安全加固配置
- [ ] 使用 systemd-analyze security 审计并改进安全评分
- [ ] 使用 systemd-cgtop 和 systemctl show 验证资源限制
- [ ] 使用 journalctl 查看服务日志和排查问题
- [ ] 编写完整的运维文档

---

## 本课小结

| 概念 | 要点 | 记忆点 |
|------|------|--------|
| 生产级服务 | Type + Dependencies + Restart + User | 完整配置 |
| Drop-in | 分离关注点 | 10-resources, 20-security |
| Timer | Monotonic + Realtime | 健康检查 vs 定时任务 |
| 安全审计 | systemd-analyze security | 目标 < 5.0 |
| 资源监控 | systemd-cgtop | 实时查看 |
| 日志 | journalctl -u | 统一日志 |

---

## 面试准备

### Q: 本番サービスの systemd 設定で重要なポイントは？

**A**: 本番サービスの systemd 設定で重要なポイントは以下の 5 つです：

1. **適切な Type 設定**：サービスの特性に合わせて Type=simple/forking/notify を選択。Type=notify が推奨で、サービスが実際に準備完了した時点で systemd に通知します。

2. **依存関係**：After= と Wants= を組み合わせて使用。After= だけでは依存サービスが起動されません。

3. **リソース制限**：MemoryMax、MemoryHigh、CPUQuota、TasksMax を設定して、一つのサービスがシステム全体に影響を与えることを防ぎます。

4. **セキュリティハードニング**：NoNewPrivileges=yes、ProtectSystem=strict、PrivateTmp=yes 等を設定。systemd-analyze security でスコア 5.0 以下を目指します。

5. **ログ設定**：StandardOutput=journal、StandardError=journal で journalctl から一元的にログ確認できるようにします。

### Q: サービスが繰り返し再起動する問題の対処法は？

**A**: サービスが繰り返し再起動（再起動ループ）する場合の対処法：

1. **StartLimitIntervalSec/Burst で制限**：
   ```ini
   [Service]
   Restart=on-failure
   RestartSec=5
   StartLimitIntervalSec=300
   StartLimitBurst=5
   ```
   これにより、300 秒間で 5 回以上再起動するとサービスが停止します。

2. **ログでエラー確認**：
   ```bash
   journalctl -u myapp.service --since "1 hour ago"
   ```
   根本原因（設定エラー、ファイル権限、依存サービス等）を特定します。

3. **リセットと修正**：
   ```bash
   # 失敗状態をリセット
   systemctl reset-failed myapp.service

   # 問題を修正後、再起動
   systemctl start myapp.service
   ```

4. **根本原因の修正**：設定ミス、バイナリパス、権限問題等を修正してから再度起動します。

### Q: systemd-analyze security の活用方法は？

**A**: systemd-analyze security はサービスの安全性を評価するツールです：

```bash
# 全サービスの評価
systemd-analyze security

# 特定サービスの詳細評価
systemd-analyze security myapp.service
```

**スコアの意味**：
- 0-2: 優秀（SAFE）
- 2-5: 良好（OK）
- 5-8: 改善が必要（MEDIUM）
- 8-10: 危険（UNSAFE）

**改善方法**：
1. まず基本的な加固を追加：NoNewPrivileges=yes、PrivateTmp=yes
2. スコアを確認して、赤い項目を優先的に対処
3. 一つずつ追加してサービスが正常に動作することを確認
4. 目標スコア 5.0 以下を達成

---

## 延伸阅读

- [systemd.exec(5) man page](https://www.freedesktop.org/software/systemd/man/systemd.exec.html) -- 安全加固指令详解
- [systemd.resource-control(5) man page](https://www.freedesktop.org/software/systemd/man/systemd.resource-control.html) -- 资源控制详解
- [systemd.timer(5) man page](https://www.freedesktop.org/software/systemd/man/systemd.timer.html) -- Timer 配置详解
- 前置课程：[09 - Drop-in 与安全加固](../09-customization-security/) -- 安全加固基础

---

## 系列导航

[09 - Drop-in 与安全加固 <--](../09-customization-security/) | [系列首页](../) | **课程完成！**
