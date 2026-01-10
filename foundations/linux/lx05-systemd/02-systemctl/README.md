# 02 - 服务管理（systemctl 实战）

> **目标**：掌握 systemctl 命令，实现服务的启动、停止、重启和开机自启管理  
> **前置**：理解 systemd 架构（Lesson 01）  
> **时间**：⚡ 20 分钟（速读）/ 🔬 75 分钟（完整实操）  
> **实战场景**：障害対応 第一步 -- 快速确认服务状态  

---

## 先跑起来！（10 分钟）

> 在学习理论之前，先体验服务管理的核心操作。  
> 运行这些命令，观察输出 -- 这就是你将要掌握的技能。  

```bash
# 1. 检查 SSH 服务状态
systemctl status sshd

# 2. 列出所有正在运行的服务
systemctl list-units --type=service --state=running

# 3. 查看 SSH 最近 10 分钟的日志
journalctl -u sshd --since '10 minutes ago'

# 4. 检查 SSH 是否开机自启
systemctl is-enabled sshd

# 5. 查看 SSH 的依赖关系
systemctl list-dependencies sshd
```

**你刚刚完成了服务管理的核心操作！**

- 检查了 sshd 的运行状态
- 列出了系统所有运行中的服务
- 查看了 sshd 的最近日志
- 确认了 sshd 是否开机自启
- 查看了 sshd 的依赖关系

现在让我们深入理解这些命令的完整用法。

---

## 将学到的内容

1. 掌握服务生命周期控制（start, stop, restart, reload）
2. 理解 enable 与 start 的本质区别
3. 使用 systemctl status 诊断服务状态
4. 列出和筛选系统中的 Unit
5. 使用 mask/unmask 完全禁用服务
6. 了解远程服务管理方法

---

## Step 1 -- 服务生命周期控制（15 分钟）

### 1.1 生命周期概览

<!-- DIAGRAM: service-lifecycle -->
```
┌─────────────────────────────────────────────────────────────────┐
│                     服务生命周期                                  │
│                                                                   │
│   ┌─────────┐   start   ┌─────────┐   stop    ┌─────────┐       │
│   │ stopped │ ────────► │ running │ ────────► │ stopped │       │
│   └─────────┘           └────┬────┘           └─────────┘       │
│                              │                                    │
│                    ┌─────────┴─────────┐                         │
│                    │                   │                         │
│                    ▼                   ▼                         │
│              ┌──────────┐       ┌──────────┐                    │
│              │ restart  │       │  reload  │                    │
│              │ (重启)   │       │ (重载)   │                    │
│              │ 停止+启动 │       │ 不中断   │                    │
│              └──────────┘       └──────────┘                    │
│                                                                   │
│   restart = stop + start（服务中断）                              │
│   reload  = 重新加载配置（服务不中断，发送 SIGHUP）               │
└─────────────────────────────────────────────────────────────────┘
```
<!-- /DIAGRAM -->

### 1.2 基本命令

```bash
# 启动服务
sudo systemctl start nginx

# 停止服务
sudo systemctl stop nginx

# 重启服务（先停后启，服务会中断）
sudo systemctl restart nginx

# 重载配置（不中断服务，发送 SIGHUP 信号）
sudo systemctl reload nginx

# 如果不确定服务是否支持 reload，使用 reload-or-restart
sudo systemctl reload-or-restart nginx
```

### 1.3 reload vs restart

| 操作 | 行为 | 服务中断 | 使用场景 |
|------|------|----------|----------|
| restart | 停止 + 启动 | 是（短暂） | 更新程序、修复问题 |
| reload | 发送 SIGHUP | 否 | 只修改配置文件 |

**重要**：并非所有服务都支持 reload！使用前请确认：

```bash
# 查看服务是否支持 reload
systemctl show nginx -p CanReload
# 输出：CanReload=yes
```

### 1.4 动手实验

```bash
# 以 chronyd 或 crond 为例（系统自带服务）
# 查看当前状态
systemctl status chronyd

# 重启服务
sudo systemctl restart chronyd

# 再次查看状态，注意 Active 时间变化
systemctl status chronyd
```

---

## Step 2 -- 开机自启配置（15 分钟）

### 2.1 enable vs start 的区别

<!-- DIAGRAM: enable-vs-start -->
```
┌─────────────────────────────────────────────────────────────────┐
│                   enable vs start                                │
│                                                                  │
│   systemctl start nginx                                          │
│   ┌──────────────────────────────────────────────────────┐      │
│   │  现在启动服务（只影响当前运行状态）                    │      │
│   │  重启系统后：服务不会自动启动                          │      │
│   └──────────────────────────────────────────────────────┘      │
│                                                                  │
│   systemctl enable nginx                                         │
│   ┌──────────────────────────────────────────────────────┐      │
│   │  设置开机自启（只影响下次开机）                        │      │
│   │  现在：服务状态不变（不会立即启动）                    │      │
│   └──────────────────────────────────────────────────────┘      │
│                                                                  │
│   systemctl enable --now nginx                                   │
│   ┌──────────────────────────────────────────────────────┐      │
│   │  同时完成两件事：                                      │      │
│   │  1. 设置开机自启                                       │      │
│   │  2. 立即启动服务                                       │      │
│   │  推荐方式！                                            │      │
│   └──────────────────────────────────────────────────────┘      │
└─────────────────────────────────────────────────────────────────┘
```
<!-- /DIAGRAM -->

### 2.2 enable 的原理

enable 实际上是创建符号链接：

```bash
# enable 创建符号链接
sudo systemctl enable nginx
# Created symlink /etc/systemd/system/multi-user.target.wants/nginx.service
#              → /usr/lib/systemd/system/nginx.service

# disable 删除符号链接
sudo systemctl disable nginx
# Removed /etc/systemd/system/multi-user.target.wants/nginx.service
```

### 2.3 推荐用法

```bash
# 部署新服务时：enable --now 一步到位
sudo systemctl enable --now nginx

# 临时禁用服务（下次开机不启动）
sudo systemctl disable nginx

# 禁用并立即停止
sudo systemctl disable --now nginx
```

### 2.4 验证开机自启状态

```bash
# 方法 1：is-enabled 命令
systemctl is-enabled nginx
# 输出：enabled / disabled / masked / static

# 方法 2：list-unit-files 查看
systemctl list-unit-files --type=service | grep nginx

# 方法 3：查看符号链接
ls -la /etc/systemd/system/multi-user.target.wants/ | grep nginx
```

---

## Step 3 -- 状态检查（10 分钟）

### 3.1 systemctl status 详解

```bash
systemctl status sshd
```

输出示例：

```
● sshd.service - OpenSSH server daemon
     Loaded: loaded (/usr/lib/systemd/system/sshd.service; enabled; preset: enabled)
     Active: active (running) since Mon 2026-01-04 10:30:00 JST; 2h ago
       Docs: man:sshd(8)
             man:sshd_config(5)
   Main PID: 1234 (sshd)
      Tasks: 1 (limit: 4915)
     Memory: 4.2M
        CPU: 123ms
     CGroup: /system.slice/sshd.service
             └─1234 sshd: /usr/sbin/sshd -D [listener] 0 of 10-100 startups

Jan 04 10:30:00 server1 systemd[1]: Starting OpenSSH server daemon...
Jan 04 10:30:00 server1 sshd[1234]: Server listening on 0.0.0.0 port 22.
```

### 3.2 解读 status 输出

| 字段 | 含义 |
|------|------|
| `●` 颜色 | 绿色=运行，红色=失败，白色=停止 |
| `Loaded` | Unit 文件位置，enabled/disabled 状态 |
| `Active` | 运行状态，启动时间，运行时长 |
| `Main PID` | 主进程 ID |
| `Tasks` | 当前任务数/限制 |
| `Memory` | 内存使用量 |
| `CGroup` | cgroup 层级和进程列表 |
| 日志行 | 最近的 journal 日志 |

### 3.3 快速状态检查命令

```bash
# 检查是否正在运行
systemctl is-active nginx
# 输出：active / inactive / failed

# 检查是否开机自启
systemctl is-enabled nginx
# 输出：enabled / disabled / masked / static

# 检查是否失败
systemctl is-failed nginx
# 输出：failed / active

# 脚本中使用（返回码）
if systemctl is-active --quiet nginx; then
    echo "nginx is running"
else
    echo "nginx is not running"
fi
```

---

## Step 4 -- 列出和筛选 Unit（10 分钟）

### 4.1 list-units：查看活跃 Unit

```bash
# 列出所有活跃的 Unit
systemctl list-units

# 只看服务
systemctl list-units --type=service

# 只看运行中的服务
systemctl list-units --type=service --state=running

# 只看失败的 Unit
systemctl list-units --failed

# 查看所有 Unit（包括未加载的）
systemctl list-units --all
```

### 4.2 list-unit-files：查看 Unit 文件

```bash
# 列出所有 Unit 文件
systemctl list-unit-files

# 只看服务类型
systemctl list-unit-files --type=service

# 查看 enabled 状态的服务
systemctl list-unit-files --type=service --state=enabled

# 搜索特定服务
systemctl list-unit-files | grep nginx
```

### 4.3 Unit 文件状态说明

| 状态 | 含义 |
|------|------|
| `enabled` | 开机自启 |
| `disabled` | 不自动启动 |
| `static` | 无 [Install] 段，不能 enable/disable |
| `masked` | 被屏蔽，无法启动 |
| `indirect` | 通过其他 Unit 间接启用 |

### 4.4 查看依赖关系

```bash
# 查看服务依赖什么
systemctl list-dependencies nginx

# 查看什么依赖这个服务（反向依赖）
systemctl list-dependencies --reverse nginx

# 只看 Wants 依赖
systemctl list-dependencies --after nginx
```

---

## Step 5 -- 高级操作（10 分钟）

### 5.1 mask/unmask：完全禁用服务

mask 比 disable 更彻底，服务完全无法启动：

```bash
# mask：创建到 /dev/null 的符号链接
sudo systemctl mask nginx
# Created symlink /etc/systemd/system/nginx.service → /dev/null

# 尝试启动被 mask 的服务会失败
sudo systemctl start nginx
# Failed to start nginx.service: Unit nginx.service is masked.

# unmask：移除屏蔽
sudo systemctl unmask nginx
```

**使用场景**：
- 临时禁用危险服务
- 防止自动依赖拉起服务
- 彻底禁用不需要的服务

### 5.2 daemon-reload：重载 Unit 文件

```bash
# 修改 Unit 文件后必须执行
sudo systemctl daemon-reload

# 然后重启服务使配置生效
sudo systemctl restart nginx
```

**重要**：修改 `/etc/systemd/system/` 下的 Unit 文件后，必须先执行 `daemon-reload`！

### 5.3 reset-failed：清除失败状态

```bash
# 查看失败的 Unit
systemctl list-units --failed

# 清除单个服务的失败状态
sudo systemctl reset-failed nginx

# 清除所有失败状态
sudo systemctl reset-failed
```

### 5.4 远程服务管理

```bash
# 通过 SSH 管理远程服务器
systemctl -H user@remote-host status nginx

# 需要远程服务器支持 systemctl over SSH
```

---

## Step 6 -- 命令速查表（Cheatsheet）

```bash
# ========================================
# 服务生命周期
# ========================================
systemctl start nginx          # 启动服务
systemctl stop nginx           # 停止服务
systemctl restart nginx        # 重启服务
systemctl reload nginx         # 重载配置（SIGHUP）
systemctl status nginx         # 查看状态

# ========================================
# 开机自启配置
# ========================================
systemctl enable nginx         # 设置开机自启
systemctl disable nginx        # 取消开机自启
systemctl enable --now nginx   # 开机自启 + 立即启动

# ========================================
# 状态检查
# ========================================
systemctl is-active nginx      # 是否运行
systemctl is-enabled nginx     # 是否开机自启
systemctl is-failed nginx      # 是否失败

# ========================================
# 列出 Unit
# ========================================
systemctl list-units                         # 活跃 Unit
systemctl list-units --type=service          # 只看服务
systemctl list-units --failed                # 失败的 Unit
systemctl list-unit-files                    # 所有 Unit 文件
systemctl list-unit-files --state=enabled    # enabled 的服务

# ========================================
# 高级操作
# ========================================
systemctl mask nginx           # 完全禁用（无法启动）
systemctl unmask nginx         # 解除禁用
systemctl daemon-reload        # 重载 Unit 文件
systemctl reset-failed         # 清除失败状态

# ========================================
# 依赖关系
# ========================================
systemctl list-dependencies nginx            # 查看依赖
systemctl list-dependencies --reverse nginx  # 反向依赖
```

---

## Mini-Project：服务健康巡检脚本

> **目标**：编写脚本检查关键服务状态，报告失败服务  

### 需求分析

在日本 IT 运维现场，定期巡检（定期点検）是基本工作。自动化巡检可以：
- 早期发现问题
- 记录服务状态历史
- 生成报告供团队审阅

### 脚本实现

创建 `service-health-check.sh`：

```bash
#!/bin/bash
# 服务健康巡检脚本
# Service Health Check Script

# 定义关键服务列表
CRITICAL_SERVICES=(
    sshd
    chronyd
    rsyslog
    firewalld
)

# 输出时间戳
echo "=========================================="
echo "服务健康巡检报告"
echo "Service Health Check Report"
echo "时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo "主机: $(hostname)"
echo "=========================================="
echo ""

# 检查失败的服务
echo "【失败服务检查】"
FAILED_COUNT=$(systemctl list-units --failed --no-legend | wc -l)
if [ "$FAILED_COUNT" -gt 0 ]; then
    echo "警告: 发现 $FAILED_COUNT 个失败服务："
    systemctl list-units --failed --no-legend
    echo ""
else
    echo "OK: 没有失败的服务"
    echo ""
fi

# 检查关键服务
echo "【关键服务状态】"
printf "%-20s %-10s %-10s\n" "服务名" "运行状态" "开机自启"
printf "%-20s %-10s %-10s\n" "-------" "--------" "--------"

for service in "${CRITICAL_SERVICES[@]}"; do
    ACTIVE=$(systemctl is-active "$service" 2>/dev/null || echo "unknown")
    ENABLED=$(systemctl is-enabled "$service" 2>/dev/null || echo "unknown")
    printf "%-20s %-10s %-10s\n" "$service" "$ACTIVE" "$ENABLED"
done

echo ""
echo "【运行中的服务数量】"
RUNNING_COUNT=$(systemctl list-units --type=service --state=running --no-legend | wc -l)
echo "当前运行中的服务: $RUNNING_COUNT 个"

echo ""
echo "=========================================="
echo "巡检完成"
echo "=========================================="
```

### 使用方法

```bash
# 添加执行权限
chmod +x service-health-check.sh

# 运行脚本
./service-health-check.sh

# 保存报告
./service-health-check.sh > report-$(date +%Y%m%d).txt
```

### 扩展建议

- 添加邮件通知功能
- 配置 cron 或 systemd timer 定期执行
- 将报告发送到监控系统

---

## Failure Lab：排查失败服务

> **目标**：故意创建一个会失败的服务，练习使用 systemctl status 和 journalctl 定位问题  

### Step 1：创建一个有问题的服务

```bash
# 创建一个会失败的服务（ExecStart 路径不存在）
sudo tee /etc/systemd/system/broken.service << 'EOF'
[Unit]
Description=Intentionally Broken Service for Learning

[Service]
Type=simple
ExecStart=/usr/bin/this-command-does-not-exist

[Install]
WantedBy=multi-user.target
EOF

# 重载 Unit 文件
sudo systemctl daemon-reload
```

### Step 2：尝试启动并观察失败

```bash
# 尝试启动服务
sudo systemctl start broken.service

# 查看状态
systemctl status broken.service
```

你会看到类似输出：

```
× broken.service - Intentionally Broken Service for Learning
     Loaded: loaded (/etc/systemd/system/broken.service; disabled; preset: disabled)
     Active: failed (Result: exit-code) since Mon 2026-01-04 15:00:00 JST; 5s ago
    Process: 12345 ExecStart=/usr/bin/this-command-does-not-exist (code=exited, status=203/EXEC)
   Main PID: 12345 (code=exited, status=203/EXEC)
        CPU: 1ms

Jan 04 15:00:00 server1 systemd[1]: Started Intentionally Broken Service for Learning.
Jan 04 15:00:00 server1 systemd[12345]: broken.service: Failed to execute /usr/bin/this-command-does-not-exist: No such file or directory
```

### Step 3：使用 journalctl 深入分析

```bash
# 查看服务的详细日志
journalctl -u broken.service --no-pager

# 只看错误级别
journalctl -u broken.service -p err --no-pager

# 查看最近的日志
journalctl -u broken.service -n 20
```

### Step 4：分析错误原因

关键信息：
- `status=203/EXEC` = 可执行文件问题
- `No such file or directory` = 文件不存在

常见退出码：

| 退出码 | 含义 | 排查方向 |
|--------|------|----------|
| 203/EXEC | 执行失败 | 检查 ExecStart 路径、权限 |
| 217/USER | 用户问题 | 检查 User= 配置的用户是否存在 |
| 200/CHDIR | 目录问题 | 检查 WorkingDirectory= |
| 1 | 一般错误 | 查看程序本身的错误信息 |

### Step 5：修复并验证

```bash
# 创建一个正确的服务
sudo tee /etc/systemd/system/broken.service << 'EOF'
[Unit]
Description=Fixed Service

[Service]
Type=oneshot
ExecStart=/bin/echo "Hello from systemd!"

[Install]
WantedBy=multi-user.target
EOF

# 重载并重启
sudo systemctl daemon-reload
sudo systemctl start broken.service

# 验证成功
systemctl status broken.service
journalctl -u broken.service -n 5
```

### Step 6：清理

```bash
# 清除失败状态
sudo systemctl reset-failed broken.service

# 删除测试服务
sudo rm /etc/systemd/system/broken.service
sudo systemctl daemon-reload
```

---

## 职场小贴士（Japan IT Context）

### 障害対応（Incident Response）第一步

在日本 IT 企业，遇到服务故障时的标准流程：

```bash
# 1. 确认服务状态（まずステータス確認）
systemctl status nginx

# 2. 查看最近日志（ログ確認）
journalctl -u nginx --since "10 minutes ago"

# 3. 查看是否有失败的依赖（依存関係確認）
systemctl list-dependencies nginx

# 4. 如果需要重启
sudo systemctl restart nginx

# 5. 确认恢复
systemctl status nginx
```

### 运维常用日语术语

| 日语术语 | 读音 | 含义 | systemctl 场景 |
|----------|------|------|----------------|
| 障害対応 | しょうがいたいおう | 故障处理 | status 确认状态 |
| サービス再起動 | さーびすさいきどう | 服务重启 | restart 命令 |
| 自動起動設定 | じどうきどうせってい | 开机自启设置 | enable 命令 |
| 起動確認 | きどうかくにん | 启动确认 | is-active 检查 |

### 变更管理（変更管理）最佳实践

```bash
# 修改配置前先确认当前状态
systemctl status nginx

# 修改配置后，先 reload（如果支持）
sudo nginx -t && sudo systemctl reload nginx

# 如果不支持 reload，用 restart
sudo nginx -t && sudo systemctl restart nginx

# 确认服务正常
systemctl status nginx
journalctl -u nginx -n 10
```

**重要**：在日本企业，任何变更都需要记录（変更履歴）。

---

## 面试准备（Interview Prep）

### Q1: enable と start の違いは？

**回答**：
- `start` は今すぐサービスを起動します。再起動すると止まります
- `enable` はブート時の自動起動を設定します。今すぐは起動しません
- `enable --now` で両方を同時に実行できます。これが推奨パターンです

```bash
# 実例
systemctl enable nginx      # 自動起動のみ設定
systemctl start nginx       # 今すぐ起動のみ
systemctl enable --now nginx  # 両方実行（推奨）
```

### Q2: サービスが起動しない時の調査手順は？

**回答**：

1. **ステータス確認**
   ```bash
   systemctl status nginx
   ```

2. **詳細ログ確認**
   ```bash
   journalctl -u nginx -n 50
   journalctl -u nginx -p err
   ```

3. **ExecStart のパスと権限確認**
   ```bash
   systemctl cat nginx | grep ExecStart
   ls -la /usr/sbin/nginx
   ```

4. **設定ファイルの検証**
   ```bash
   nginx -t
   ```

5. **依存サービスの確認**
   ```bash
   systemctl list-dependencies nginx
   ```

---

## 检查清单

完成本课后，你应该能够：

- [ ] 使用 `systemctl start/stop/restart/reload` 控制服务生命周期
- [ ] 理解 `enable` 和 `start` 的区别
- [ ] 使用 `enable --now` 一步完成开机自启和立即启动
- [ ] 读懂 `systemctl status` 的输出信息
- [ ] 使用 `is-active`, `is-enabled`, `is-failed` 进行快速检查
- [ ] 使用 `list-units` 和 `list-unit-files` 列出服务
- [ ] 使用 `list-dependencies` 查看服务依赖
- [ ] 使用 `mask/unmask` 完全禁用/解禁服务
- [ ] 理解何时需要执行 `daemon-reload`
- [ ] 使用 `journalctl -u` 查看服务日志

---

## 本课小结

| 操作 | 命令 | 记忆点 |
|------|------|--------|
| 启动服务 | `systemctl start` | 只影响现在 |
| 停止服务 | `systemctl stop` | 只影响现在 |
| 重启服务 | `systemctl restart` | 服务会中断 |
| 重载配置 | `systemctl reload` | 不中断服务 |
| 开机自启 | `systemctl enable` | 只影响下次开机 |
| 立即启动+自启 | `systemctl enable --now` | **推荐用法** |
| 查看状态 | `systemctl status` | 最常用命令 |
| 是否运行 | `systemctl is-active` | 脚本中使用 |
| 列出服务 | `systemctl list-units --type=service` | 加 --failed 看故障 |
| 完全禁用 | `systemctl mask` | 比 disable 更彻底 |
| 重载配置 | `systemctl daemon-reload` | 修改 Unit 文件后必须执行 |

---

## 延伸阅读

- [systemctl man page](https://man7.org/linux/man-pages/man1/systemctl.1.html)
- [systemd.service man page](https://man7.org/linux/man-pages/man5/systemd.service.5.html)
- 下一课：[03 - Unit 文件解剖](../03-unit-files/) -- 深入理解 Unit 文件的结构和配置
- 相关课程：[07 - journalctl 日志掌控](../07-journalctl/) -- 日志查询与分析

---

## 系列导航

[<-- 01 - 架构与设计哲学](../01-architecture/) | [系列首页](../) | [03 - Unit 文件解剖 -->](../03-unit-files/)
