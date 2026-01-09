# 07 - journalctl 日志掌控

> **目标**：掌握 journalctl 日志查询、过滤和持久化配置  
> **前置**：掌握 systemctl 基本操作（Lesson 02）  
> **时间**：60-90 分钟  
> **实战场景**：運用監視 -- 集中ログ分析与故障排查  

---

## 先跑起来！（10 分钟）

> 在学习理论之前，先体验 journalctl 的核心功能。  
> 运行这些命令，观察输出 -- 这就是日志分析的基本功。  

```bash
# 1. 查看 sshd 服务的日志
journalctl -u sshd -n 20

# 2. 只看错误级别的日志
journalctl -p err -n 20

# 3. 查看最近 1 小时的日志
journalctl --since "1 hour ago" -n 50

# 4. 实时跟踪日志（类似 tail -f）
journalctl -f
# 按 Ctrl+C 退出

# 5. 查看本次启动的日志
journalctl -b

# 6. 检查日志磁盘使用量
journalctl --disk-usage
```

**你刚刚完成了日志分析的核心操作！**

- 按服务过滤日志（`-u sshd`）
- 按优先级过滤（`-p err`）
- 按时间范围过滤（`--since`）
- 实时跟踪日志（`-f`）
- 查看启动日志（`-b`）
- 检查磁盘使用（`--disk-usage`）

现在让我们深入理解这些功能的完整用法。

---

## 将学到的内容

1. 掌握 journalctl 过滤技巧（Unit、优先级、时间）
2. 配置日志持久化存储
3. 管理日志磁盘空间
4. 分析启动日志和多次启动历史
5. 使用 JSON 输出集成 SIEM 系统
6. 验证日志完整性

---

## Step 1 -- 基本过滤技巧（15 分钟）

### 1.1 按 Unit 过滤

```bash
# 查看特定服务的日志
journalctl -u nginx

# 查看多个服务的日志
journalctl -u nginx -u php-fpm

# 查看服务最近 N 条日志
journalctl -u sshd -n 50

# 实时跟踪服务日志
journalctl -u nginx -f
```

### 1.2 按优先级过滤

日志优先级（从高到低）：

| 级别 | 数字 | 含义 | 使用场景 |
|------|------|------|----------|
| `emerg` | 0 | 系统不可用 | 严重故障 |
| `alert` | 1 | 需要立即处理 | 紧急问题 |
| `crit` | 2 | 关键错误 | 服务崩溃 |
| `err` | 3 | 错误 | **日常排查重点** |
| `warning` | 4 | 警告 | 潜在问题 |
| `notice` | 5 | 重要通知 | 状态变化 |
| `info` | 6 | 信息 | 正常运行 |
| `debug` | 7 | 调试 | 开发调试 |

```bash
# 只看错误及以上级别（err, crit, alert, emerg）
journalctl -p err

# 只看警告及以上
journalctl -p warning

# 查看特定服务的错误
journalctl -u nginx -p err

# 指定优先级范围
journalctl -p warning..err
```

### 1.3 按时间范围过滤

```bash
# 从某个时间点开始
journalctl --since "2026-01-04 10:00:00"

# 到某个时间点结束
journalctl --until "2026-01-04 12:00:00"

# 时间范围
journalctl --since "2026-01-04 10:00" --until "2026-01-04 12:00"

# 相对时间（更常用）
journalctl --since "1 hour ago"
journalctl --since "30 minutes ago"
journalctl --since "yesterday"
journalctl --since "today"

# 组合使用
journalctl -u nginx --since "1 hour ago" -p err
```

### 1.4 实时跟踪

```bash
# 跟踪所有日志（类似 tail -f /var/log/messages）
journalctl -f

# 跟踪特定服务
journalctl -u nginx -f

# 跟踪内核日志
journalctl -k -f
```

---

## Step 2 -- 启动日志分析（15 分钟）

### 2.1 查看当前/历史启动日志

```bash
# 当前启动的日志
journalctl -b

# 当前启动的日志（从开头显示）
journalctl -b -e

# 上次启动的日志
journalctl -b -1

# 前两次启动
journalctl -b -2

# 列出所有启动记录
journalctl --list-boots
```

`--list-boots` 输出示例：

```
-3 abc123... Mon 2026-01-01 10:00:00 JST—Mon 2026-01-01 18:00:00 JST
-2 def456... Tue 2026-01-02 09:00:00 JST—Tue 2026-01-02 20:00:00 JST
-1 ghi789... Wed 2026-01-03 08:00:00 JST—Wed 2026-01-03 22:00:00 JST
 0 jkl012... Thu 2026-01-04 07:00:00 JST—Thu 2026-01-04 15:00:00 JST
```

### 2.2 内核日志

```bash
# 只看内核日志（类似 dmesg）
journalctl -k

# 当前启动的内核日志
journalctl -k -b

# 上次启动的内核日志（排查重启前的问题）
journalctl -k -b -1
```

### 2.3 启动问题排查流程

<!-- DIAGRAM: boot-log-analysis -->
```
┌─────────────────────────────────────────────────────────────────┐
│                    启动日志分析流程                               │
│                                                                  │
│   系统重启后发现服务异常                                          │
│              │                                                   │
│              ▼                                                   │
│   ┌──────────────────┐                                          │
│   │ journalctl -b -1 │ ◀─── 查看上次启动日志                     │
│   └────────┬─────────┘                                          │
│            │                                                     │
│            ▼                                                     │
│   ┌────────────────────────┐                                    │
│   │ journalctl -b -1 -p err│ ◀─── 只看错误                       │
│   └────────┬───────────────┘                                    │
│            │                                                     │
│            ▼                                                     │
│   ┌──────────────────────────────┐                              │
│   │ journalctl -b -1 -u nginx    │ ◀─── 定位到具体服务           │
│   └────────┬─────────────────────┘                              │
│            │                                                     │
│            ▼                                                     │
│   ┌──────────────────────────────┐                              │
│   │ journalctl -k -b -1          │ ◀─── 如果是硬件/驱动问题      │
│   └──────────────────────────────┘                              │
└─────────────────────────────────────────────────────────────────┘
```
<!-- /DIAGRAM -->

**重要提示**：要查看历史启动日志，需要配置日志持久化（见 Step 4）。

---

## Step 3 -- 输出格式（10 分钟）

### 3.1 常用输出格式

```bash
# 默认格式（short）
journalctl -u nginx

# 精确时间戳（微秒级）
journalctl -u nginx -o short-precise

# 详细格式（显示所有字段）
journalctl -u nginx -o verbose

# JSON 格式（单行）
journalctl -u nginx -o json

# JSON 格式（美化）
journalctl -u nginx -o json-pretty

# 只显示消息内容
journalctl -u nginx -o cat

# 导出格式（二进制，用于备份）
journalctl -u nginx -o export
```

### 3.2 输出格式对比

| 格式 | 用途 | 示例场景 |
|------|------|----------|
| `short` | 日常查看 | 默认格式 |
| `short-precise` | 精确时间排查 | 并发问题调试 |
| `verbose` | 查看所有元数据 | 高级分析 |
| `json-pretty` | 程序处理 | SIEM 集成 |
| `cat` | 只看消息 | 快速浏览 |

### 3.3 JSON 输出（SIEM 集成）

```bash
# JSON 格式输出
journalctl -u nginx -o json-pretty -n 5
```

输出示例：

```json
{
    "__REALTIME_TIMESTAMP" : "1704348000000000",
    "__MONOTONIC_TIMESTAMP" : "12345678901",
    "_HOSTNAME" : "server1",
    "_SYSTEMD_UNIT" : "nginx.service",
    "PRIORITY" : "6",
    "MESSAGE" : "Started A high performance web server and reverse proxy server.",
    "_PID" : "1234",
    "_UID" : "0",
    "_GID" : "0",
    "_COMM" : "nginx"
}
```

**SIEM 集成场景**：

```bash
# 导出最近 1 小时的错误日志为 JSON
journalctl --since "1 hour ago" -p err -o json > /tmp/errors.json

# 实时流式输出到日志收集器
journalctl -f -o json | nc logserver.example.com 5514
```

### 3.4 附加解释信息

```bash
# -x 添加解释信息（如果可用）
journalctl -xe

# -e 跳转到日志末尾
journalctl -e

# 组合：最近日志 + 解释
journalctl -u nginx -xe
```

---

## Step 4 -- 日志持久化配置（15 分钟）

### 4.1 默认行为

默认情况下，journal 日志存储在 `/run/log/journal/`（内存中），系统重启后丢失。

```bash
# 检查当前存储位置
ls -la /run/log/journal/
ls -la /var/log/journal/  # 如果存在，说明已配置持久化
```

### 4.2 配置持久化存储

**方法 1：创建目录（推荐）**

```bash
# 创建持久化目录
sudo mkdir -p /var/log/journal

# 设置正确的权限
sudo systemd-tmpfiles --create --prefix /var/log/journal

# 重启 journald 服务
sudo systemctl restart systemd-journald

# 验证
ls -la /var/log/journal/
journalctl --disk-usage
```

**方法 2：修改配置文件**

```bash
# 编辑 journald 配置
sudo vim /etc/systemd/journald.conf
```

修改内容：

```ini
[Journal]
# Storage 选项：
#   volatile  = 只存内存
#   persistent = 存磁盘
#   auto = 有目录就存磁盘（默认）
#   none = 不存储
Storage=persistent
```

```bash
# 重启服务使配置生效
sudo systemctl restart systemd-journald
```

### 4.3 验证持久化

```bash
# 检查日志存储位置
journalctl --header | grep "File path"

# 列出启动历史（只有持久化后才有历史）
journalctl --list-boots

# 查看磁盘使用
journalctl --disk-usage
```

---

## Step 5 -- 空间管理（10 分钟）

### 5.1 配置空间限制

编辑 `/etc/systemd/journald.conf`：

```ini
[Journal]
Storage=persistent

# 最大使用磁盘空间（绝对值）
SystemMaxUse=500M

# 保留最小空闲空间
SystemKeepFree=1G

# 单个日志文件最大大小
SystemMaxFileSize=50M

# 最大文件数
SystemMaxFiles=100

# 运行时（内存）限制
RuntimeMaxUse=100M
RuntimeKeepFree=50M
```

**配置说明**：

| 配置项 | 含义 | 推荐值 |
|--------|------|--------|
| `SystemMaxUse` | 持久化日志最大空间 | 磁盘的 10-15% |
| `SystemKeepFree` | 磁盘最小保留空间 | 至少 1G |
| `SystemMaxFileSize` | 单文件最大 | 50M-100M |
| `RuntimeMaxUse` | 内存日志最大 | 100M-200M |

### 5.2 手动清理日志

```bash
# 查看当前使用量
journalctl --disk-usage

# 清理到指定大小
sudo journalctl --vacuum-size=500M

# 清理到指定时间（保留最近 1 个月）
sudo journalctl --vacuum-time=1month

# 清理到指定文件数
sudo journalctl --vacuum-files=10

# 同时应用多个条件
sudo journalctl --vacuum-size=500M --vacuum-time=1month
```

### 5.3 日志轮转

systemd-journald 自动进行日志轮转，无需像传统 logrotate 那样配置。

```bash
# 查看日志文件
ls -la /var/log/journal/*/

# 查看归档日志
journalctl --file=/var/log/journal/*/system@*.journal
```

---

## Step 6 -- 高级功能（10 分钟）

### 6.1 验证日志完整性

```bash
# 验证日志文件完整性
journalctl --verify

# 验证特定目录
journalctl --verify --directory=/var/log/journal/
```

输出示例：

```
PASS: /var/log/journal/abc123/system.journal
PASS: /var/log/journal/abc123/user-1000.journal
```

**用途**：检测日志是否被篡改或损坏（安全审计场景）。

### 6.2 日志转发到 syslog

编辑 `/etc/systemd/journald.conf`：

```ini
[Journal]
# 转发到 rsyslog（或其他 syslog 守护进程）
ForwardToSyslog=yes

# 转发到控制台
ForwardToConsole=no

# 转发到 kmsg（内核日志）
ForwardToKMsg=no

# 转发到 wall（广播）
ForwardToWall=yes
```

**场景**：需要同时使用 journald 和传统 syslog 时（如 rsyslog 远程日志收集）。

### 6.3 按进程/用户过滤

```bash
# 按 PID 过滤
journalctl _PID=1234

# 按用户过滤
journalctl _UID=1000

# 按可执行文件过滤
journalctl _COMM=nginx

# 按主机名过滤（多主机日志收集时）
journalctl _HOSTNAME=server1

# 组合条件
journalctl _SYSTEMD_UNIT=nginx.service _PID=1234
```

### 6.4 字段说明

```bash
# 查看所有可用字段
journalctl -o verbose -n 1

# 常用字段
# _SYSTEMD_UNIT - 服务名
# _PID          - 进程 ID
# _UID          - 用户 ID
# _HOSTNAME     - 主机名
# _COMM         - 命令名
# PRIORITY      - 优先级
# MESSAGE       - 日志消息
```

---

## 命令速查表（Cheatsheet）

```bash
# ========================================
# 基本过滤
# ========================================
journalctl -u nginx              # 按 Unit 过滤
journalctl -p err                # 只看错误
journalctl --since "1 hour ago"  # 时间范围
journalctl -f                    # 实时跟踪

# ========================================
# 启动分析
# ========================================
journalctl -b                    # 当前启动
journalctl -b -1                 # 上次启动
journalctl --list-boots          # 列出所有启动
journalctl -k                    # 内核日志

# ========================================
# 输出格式
# ========================================
journalctl -o json-pretty        # JSON 格式
journalctl -o short-precise      # 精确时间戳
journalctl -o verbose            # 详细字段
journalctl -xe                   # 最近日志 + 解释

# ========================================
# 组合查询
# ========================================
journalctl -u nginx -p err --since "1 hour ago"
journalctl -b -1 -u sshd -p warning

# ========================================
# 空间管理
# ========================================
journalctl --disk-usage          # 查看使用量
journalctl --vacuum-size=500M    # 清理到 500M
journalctl --vacuum-time=1month  # 保留最近 1 个月
journalctl --verify              # 验证完整性

# ========================================
# 持久化配置
# ========================================
sudo mkdir -p /var/log/journal
sudo systemctl restart systemd-journald
journalctl --list-boots          # 验证历史可用

# ========================================
# 高级过滤
# ========================================
journalctl _PID=1234             # 按 PID
journalctl _UID=1000             # 按用户
journalctl _COMM=nginx           # 按命令
```

---

## Mini-Project：日志持久化与分析

> **目标**：配置日志持久化，编写脚本分析启动错误  

### 需求分析

在日本 IT 运维现场，日志分析（ログ分析）是故障排查的基础。系统重启后能够查看之前的日志对于「障害対応」至关重要。

### Part 1：配置日志持久化

```bash
# 1. 检查当前状态
journalctl --disk-usage
journalctl --list-boots

# 2. 创建持久化目录
sudo mkdir -p /var/log/journal
sudo systemd-tmpfiles --create --prefix /var/log/journal

# 3. 配置空间限制
sudo tee /etc/systemd/journald.conf.d/persistent.conf << 'EOF'
[Journal]
Storage=persistent
SystemMaxUse=500M
SystemKeepFree=1G
SystemMaxFileSize=50M
EOF

# 4. 重启服务
sudo systemctl restart systemd-journald

# 5. 验证
journalctl --disk-usage
journalctl --list-boots
```

### Part 2：启动错误分析脚本

创建 `boot-error-analyzer.sh`：

```bash
#!/bin/bash
# 启动错误分析脚本
# Boot Error Analyzer Script

# 颜色定义
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

echo "=========================================="
echo "启动错误分析报告"
echo "Boot Error Analysis Report"
echo "时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo "主机: $(hostname)"
echo "=========================================="
echo ""

# 检查可用的启动记录数
BOOT_COUNT=$(journalctl --list-boots 2>/dev/null | wc -l)
echo "【可用启动记录】"
echo "共有 $BOOT_COUNT 次启动记录"
echo ""

if [ "$BOOT_COUNT" -eq 0 ]; then
    echo -e "${YELLOW}警告: 没有启动历史记录。请配置日志持久化：${NC}"
    echo "  sudo mkdir -p /var/log/journal"
    echo "  sudo systemctl restart systemd-journald"
    exit 1
fi

# 分析函数
analyze_boot() {
    local boot_id=$1
    local boot_label=$2

    echo "----------------------------------------"
    echo "【$boot_label 启动分析】(boot $boot_id)"
    echo ""

    # 统计错误数量
    ERROR_COUNT=$(journalctl -b $boot_id -p err --no-pager 2>/dev/null | wc -l)
    WARNING_COUNT=$(journalctl -b $boot_id -p warning --no-pager 2>/dev/null | wc -l)

    if [ "$ERROR_COUNT" -gt 0 ]; then
        echo -e "${RED}错误数量: $ERROR_COUNT${NC}"
    else
        echo -e "${GREEN}错误数量: 0${NC}"
    fi
    echo "警告数量: $WARNING_COUNT"
    echo ""

    # 显示错误详情
    if [ "$ERROR_COUNT" -gt 0 ]; then
        echo "【错误详情】(最近 10 条)"
        journalctl -b $boot_id -p err --no-pager -n 10 -o short-precise 2>/dev/null
        echo ""
    fi

    # 检查失败的服务
    echo "【启动时失败的服务】"
    FAILED_UNITS=$(journalctl -b $boot_id -p err --no-pager 2>/dev/null | \
                   grep -oP '_SYSTEMD_UNIT=\K[^\s]+' | sort -u)

    if [ -n "$FAILED_UNITS" ]; then
        echo "$FAILED_UNITS"
    else
        echo -e "${GREEN}无失败服务${NC}"
    fi
    echo ""
}

# 分析当前启动
analyze_boot 0 "当前"

# 分析上次启动（如果存在）
if [ "$BOOT_COUNT" -ge 2 ]; then
    analyze_boot -1 "上次"
fi

# 磁盘使用情况
echo "=========================================="
echo "【日志磁盘使用】"
journalctl --disk-usage
echo ""

# 验证日志完整性
echo "【日志完整性验证】"
if journalctl --verify 2>&1 | grep -q "PASS"; then
    echo -e "${GREEN}日志文件完整性: PASS${NC}"
else
    echo -e "${YELLOW}日志文件完整性: 请检查 journalctl --verify 输出${NC}"
fi

echo ""
echo "=========================================="
echo "分析完成"
echo "=========================================="
```

### 使用方法

```bash
# 添加执行权限
chmod +x boot-error-analyzer.sh

# 运行脚本
./boot-error-analyzer.sh

# 保存报告
./boot-error-analyzer.sh > boot-report-$(date +%Y%m%d).txt
```

### Part 3：JSON 日志导出（SIEM 集成）

```bash
# 导出最近 1 小时的错误日志
journalctl --since "1 hour ago" -p err -o json > /tmp/errors-$(date +%Y%m%d%H%M).json

# 导出特定服务的日志
journalctl -u nginx --since "today" -o json > /tmp/nginx-$(date +%Y%m%d).json

# 验证 JSON 格式
cat /tmp/errors-*.json | python3 -m json.tool > /dev/null && echo "JSON valid"
```

---

## 职场小贴士（Japan IT Context）

### 運用監視（Operations Monitoring）场景

在日本 IT 企业，集中日志分析（集中ログ分析）是运维基础：

```bash
# 日常巡检：检查最近 1 小时的错误
journalctl --since "1 hour ago" -p err

# 服务故障：查看特定服务日志
journalctl -u nginx -p err --since "30 minutes ago"

# 系统重启后：分析上次启动的问题
journalctl -b -1 -p err

# 生成报告：导出 JSON 供 SIEM 分析
journalctl --since "today" -p warning -o json > daily-warnings.json
```

### 运维常用日语术语

| 日语术语 | 读音 | 含义 | journalctl 场景 |
|----------|------|------|-----------------|
| ログ分析 | ろぐぶんせき | 日志分析 | 基本过滤操作 |
| 障害解析 | しょうがいかいせき | 故障分析 | 错误日志排查 |
| 永続化 | えいぞくか | 持久化 | Storage=persistent |
| ディスク容量管理 | ディスクようりょうかんり | 磁盘空间管理 | --vacuum-size |
| 再起動前ログ | さいきどうまえログ | 重启前日志 | -b -1 参数 |

### 日志分析最佳实践

```bash
# 1. 故障报告时的日志提取（障害報告用）
journalctl -u nginx --since "2026-01-04 10:00" --until "2026-01-04 11:00" \
    -o short-precise > incident-nginx-20260104.log

# 2. 多服务关联分析
journalctl -u nginx -u php-fpm --since "1 hour ago" -o short-precise

# 3. 安全审计日志导出
journalctl _SYSTEMD_UNIT=sshd.service --since "yesterday" -o json-pretty \
    > ssh-audit-$(date +%Y%m%d).json
```

**重要**：在日本企业，任何故障都需要详细的日志记录作为证据（エビデンス）。

---

## 面试准备（Interview Prep）

### Q1: journalctl で特定サービスのエラーを確認する方法は？

**回答**：

```bash
# nginx のエラーログのみ表示
journalctl -u nginx -p err

# 時間範囲を指定して確認
journalctl -u nginx -p err --since "1 hour ago"

# リアルタイムで追跡
journalctl -u nginx -p err -f
```

ポイント：
- `-u` でサービス指定
- `-p err` でエラー以上のレベルのみフィルタ
- 時間範囲を `--since` で絞ると効率的

### Q2: ログの永続化を設定する方法は？

**回答**：

2つの方法があります：

**方法1：ディレクトリ作成（推奨）**
```bash
sudo mkdir -p /var/log/journal
sudo systemd-tmpfiles --create --prefix /var/log/journal
sudo systemctl restart systemd-journald
```

**方法2：設定ファイル変更**
```bash
# /etc/systemd/journald.conf を編集
[Journal]
Storage=persistent
```

確認方法：
```bash
journalctl --list-boots  # 複数のブートが表示されれば成功
```

### Q3: ログのディスク容量が増えすぎた時の対処法は？

**回答**：

```bash
# 現在の使用量確認
journalctl --disk-usage

# 500MB に削減
sudo journalctl --vacuum-size=500M

# 1ヶ月分のみ保持
sudo journalctl --vacuum-time=1month

# 恒久的な設定（/etc/systemd/journald.conf）
[Journal]
SystemMaxUse=500M
SystemKeepFree=1G
```

---

## 检查清单

完成本课后，你应该能够：

- [ ] 使用 `-u` 按服务过滤日志
- [ ] 使用 `-p` 按优先级过滤（err, warning, info）
- [ ] 使用 `--since` / `--until` 按时间范围过滤
- [ ] 使用 `-f` 实时跟踪日志
- [ ] 使用 `-b` 查看当前/历史启动日志
- [ ] 使用 `--list-boots` 列出所有启动记录
- [ ] 使用 `-o json-pretty` 输出 JSON 格式
- [ ] 配置日志持久化（创建 `/var/log/journal`）
- [ ] 使用 `--vacuum-size` 和 `--vacuum-time` 管理磁盘空间
- [ ] 使用 `--disk-usage` 检查日志使用量
- [ ] 使用 `--verify` 验证日志完整性
- [ ] 组合多个过滤条件进行精确查询

---

## 本课小结

| 功能 | 命令 | 记忆点 |
|------|------|--------|
| 按服务过滤 | `journalctl -u nginx` | 最常用 |
| 按优先级 | `journalctl -p err` | err = 错误 |
| 按时间 | `journalctl --since "1 hour ago"` | 相对时间更方便 |
| 实时跟踪 | `journalctl -f` | 类似 tail -f |
| 当前启动 | `journalctl -b` | 重启后从头 |
| 上次启动 | `journalctl -b -1` | 排查重启前问题 |
| JSON 格式 | `journalctl -o json-pretty` | SIEM 集成 |
| 查看使用量 | `journalctl --disk-usage` | 空间管理 |
| 清理日志 | `journalctl --vacuum-size=500M` | 手动清理 |
| 持久化 | `mkdir /var/log/journal` | 保留重启历史 |

---

## 延伸阅读

- [journalctl man page](https://man7.org/linux/man-pages/man1/journalctl.1.html)
- [journald.conf man page](https://man7.org/linux/man-pages/man5/journald.conf.5.html)
- 上一课：[06 - Timer（现代 cron 替代）](../06-timers/) -- 定时任务管理
- 下一课：[08 - 资源控制（cgroup v2）](../08-resource-control/) -- CPU/内存限制
- 相关课程：[02 - 服务管理](../02-systemctl/) -- systemctl 基础操作

---

## 系列导航

[<-- 06 - Timer](../06-timers/) | [系列首页](../) | [08 - 资源控制 -->](../08-resource-control/)
