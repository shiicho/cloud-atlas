# 06 · 文本进阶与自动化（Advanced Text & Automation）

> **目标**：掌握 grep/sed/awk 组合技巧和定时任务，创建日志报警脚本
> **前置**：[05 · 函数与参数](../05-functions/)
> **时间**：30-40 分钟
> **实战项目**：日志报警雏形（On-call 值班场景）

## 将学到的内容

1. grep 正则匹配
2. sed 流编辑器
3. awk 文本处理
4. cron 定时任务
5. 调试技巧：脚本日志记录

---

## Step 1 — grep 进阶

### 基本用法回顾

```bash
# 基本搜索
grep "error" /var/log/messages

# 忽略大小写
grep -i "error" /var/log/messages

# 显示行号
grep -n "error" /var/log/messages

# 显示上下文
grep -C 3 "error" /var/log/messages   # 前后各 3 行
grep -B 2 "error" /var/log/messages   # 前 2 行
grep -A 2 "error" /var/log/messages   # 后 2 行
```

### 正则表达式

```bash
# 基本正则
grep "^start" file.txt           # 以 start 开头
grep "end$" file.txt             # 以 end 结尾
grep "a.b" file.txt              # a 和 b 之间有任意字符

# 扩展正则 (-E)
grep -E "error|warn" file.txt           # OR 匹配
grep -E "[0-9]{3}" file.txt             # 3 位数字
grep -E "^[0-9]+\.[0-9]+\.[0-9]+" file  # IP 地址开头

# 反向匹配
grep -v "debug" file.txt         # 排除包含 debug 的行
```

### 实用示例

```bash
# 提取 IP 地址
grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' access.log

# 统计错误数
grep -c "ERROR" /var/log/messages

# 只显示匹配的文件名
grep -l "error" /var/log/*.log

# 递归搜索目录
grep -r "TODO" ~/bash-course/
```

---

## Step 2 — sed 流编辑器

### 基本替换

```bash
# 替换第一个匹配
echo "hello world" | sed 's/world/bash/'
# 输出: hello bash

# 全局替换 (g)
echo "a-b-c" | sed 's/-/_/g'
# 输出: a_b_c

# 直接修改文件 (-i)
sed -i 's/old/new/g' file.txt

# 备份后修改
sed -i.bak 's/old/new/g' file.txt
```

### 删除和打印

```bash
# 删除包含 pattern 的行
sed '/debug/d' file.txt

# 删除空行
sed '/^$/d' file.txt

# 只打印匹配的行 (-n + p)
sed -n '/error/p' file.txt

# 打印指定行
sed -n '5,10p' file.txt           # 第 5-10 行
```

### 实用示例

```bash
# 删除注释行
sed '/^#/d' config.txt

# 在行首添加内容
sed 's/^/PREFIX: /' file.txt

# 在行尾添加内容
sed 's/$/ SUFFIX/' file.txt

# 提取两个标记之间的内容
sed -n '/START/,/END/p' file.txt
```

---

## Step 3 — awk 文本处理

### 基本语法

```bash
# 打印整行
awk '{print}' file.txt

# 打印指定字段（默认空格分隔）
awk '{print $1}' file.txt         # 第 1 列
awk '{print $1, $3}' file.txt     # 第 1 和第 3 列
awk '{print $NF}' file.txt        # 最后一列

# 指定分隔符
awk -F':' '{print $1}' /etc/passwd
awk -F',' '{print $2}' data.csv
```

### 条件过滤

```bash
# 匹配模式
awk '/error/ {print}' file.txt

# 字段条件
awk '$3 > 100 {print $1, $3}' file.txt

# 组合条件
awk '$1 == "web01" && $3 > 50 {print}' file.txt
```

### 内置变量

```bash
# NR: 行号
# NF: 字段数
# FS: 字段分隔符
# OFS: 输出分隔符

# 打印行号
awk '{print NR, $0}' file.txt

# 打印每行字段数
awk '{print NF}' file.txt

# 设置输出分隔符
awk 'BEGIN{OFS=","} {print $1, $2, $3}' file.txt
```

### 计算统计

```bash
# 求和
awk '{sum += $1} END {print sum}' numbers.txt

# 平均值
awk '{sum += $1; count++} END {print sum/count}' numbers.txt

# 最大值
awk 'BEGIN{max=0} $1 > max {max=$1} END {print max}' numbers.txt

# 计数统计
awk '{count[$1]++} END {for (k in count) print k, count[k]}' file.txt
```

---

## Step 4 — 组合技巧

### grep + awk

```bash
# 筛选后提取字段
grep "ERROR" access.log | awk '{print $1, $4}'

# 统计错误 IP
grep "500" access.log | awk '{print $1}' | sort | uniq -c | sort -rn
```

### sed + awk

```bash
# 清理后计算
cat data.txt | sed 's/[^0-9]//g' | awk '{sum+=$1} END{print sum}'
```

### 日志分析组合

```bash
# 统计每小时请求量
cat access.log | \
    awk '{print $4}' | \
    sed 's/\[//; s/:/ /' | \
    cut -d' ' -f2 | \
    cut -d':' -f1 | \
    sort | uniq -c
```

---

## Step 5 — cron 定时任务

### crontab 基础

```bash
# 查看当前用户的 crontab
crontab -l

# 编辑 crontab
crontab -e

# cron 格式:
# 分 时 日 月 周 命令
# *  *  *  *  *  command
```

### 时间格式

```
┌───────────── 分钟 (0 - 59)
│ ┌───────────── 小时 (0 - 23)
│ │ ┌───────────── 日 (1 - 31)
│ │ │ ┌───────────── 月 (1 - 12)
│ │ │ │ ┌───────────── 周几 (0 - 7, 0和7都是周日)
│ │ │ │ │
* * * * * command
```

### 常见示例

```bash
# 每分钟执行
* * * * * /path/to/script.sh

# 每小时执行（整点）
0 * * * * /path/to/script.sh

# 每天凌晨 2 点
0 2 * * * /path/to/script.sh

# 每周一早上 9 点
0 9 * * 1 /path/to/script.sh

# 每 5 分钟
*/5 * * * * /path/to/script.sh

# 工作日的 9-17 点每小时
0 9-17 * * 1-5 /path/to/script.sh
```

### 注意事项

```bash
# 1. 使用绝对路径
0 * * * * /home/ssm-user/scripts/check.sh

# 2. 设置环境变量
0 * * * * export PATH=/usr/bin:$PATH && /home/ssm-user/scripts/check.sh

# 3. 重定向输出
0 * * * * /path/to/script.sh >> /var/log/myscript.log 2>&1

# 4. 避免输出邮件
0 * * * * /path/to/script.sh > /dev/null 2>&1
```

---

## Step 6 — 调试技巧

> 🔧 **调试卡片**：脚本日志记录让问题排查更容易。

### 日志记录函数

```bash
#!/bin/bash

# 日志文件
LOG_FILE="${LOG_FILE:-/var/log/myscript.log}"

# 日志函数
log() {
    local level="$1"
    shift
    local message="$@"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}

# 使用
log INFO "脚本开始执行"
log ERROR "发生错误: $error_msg"
log INFO "脚本执行完成"
```

### 使用 tee 同时输出

```bash
# 输出到终端和文件
echo "Hello" | tee output.log

# 追加模式
echo "World" | tee -a output.log

# 整个脚本输出重定向
exec > >(tee -a /var/log/script.log) 2>&1
```

---

## Mini-Project：日志报警脚本

> **场景**：值班时需要定期检查日志，当错误率超过阈值时触发告警。这是日本 IT 公司「当番/On-call」的核心需求。

先创建模拟日志（带时间戳）：

```bash
# 创建带时间戳的模拟日志
mkdir -p ~/bash-course/logs

# 生成过去 20 分钟的日志
cat > ~/bash-course/logs/app.log << 'EOF'
2025-01-15 15:40:01 INFO Request processed successfully
2025-01-15 15:41:02 INFO User login: user123
2025-01-15 15:42:03 ERROR Database connection timeout
2025-01-15 15:43:04 INFO Request processed successfully
2025-01-15 15:44:05 WARN High memory usage detected
2025-01-15 15:45:06 INFO Request processed successfully
2025-01-15 15:46:07 ERROR API rate limit exceeded
2025-01-15 15:47:08 INFO User logout: user123
2025-01-15 15:48:09 ERROR Service unavailable
2025-01-15 15:49:10 INFO Request processed successfully
2025-01-15 15:50:11 INFO Cache refreshed
2025-01-15 15:51:12 ERROR Connection reset by peer
2025-01-15 15:52:13 INFO Request processed successfully
2025-01-15 15:53:14 INFO User login: user456
2025-01-15 15:54:15 ERROR Timeout waiting for response
2025-01-15 15:55:16 INFO Request processed successfully
2025-01-15 15:56:17 INFO Healthcheck passed
2025-01-15 15:57:18 ERROR Internal server error
2025-01-15 15:58:19 INFO Request processed successfully
2025-01-15 15:59:20 INFO Session cleanup completed
EOF

echo "模拟日志已创建: ~/bash-course/logs/app.log"
```

创建报警脚本：

```bash
nano ~/bash-course/log-alerter.sh
```

```bash
#!/bin/bash
# 日志报警脚本 - Log Alerter
# 用途：值班监控、On-call 告警

set -euo pipefail

# ====================
# 配置
# ====================
readonly VERSION="1.0.0"
readonly SCRIPT_NAME=$(basename "$0")

# 默认配置
LOG_FILE="${1:-$HOME/bash-course/logs/app.log}"
TIME_WINDOW=10                     # 检查最近 N 分钟
ERROR_THRESHOLD=3                  # 错误数阈值
ALERT_FILE="$HOME/reports/alerts.log"
SCRIPT_LOG="$HOME/logs/${SCRIPT_NAME%.sh}.log"

# Webhook URL（示例，实际使用时替换）
WEBHOOK_URL=""

# ====================
# 初始化
# ====================
mkdir -p "$(dirname "$ALERT_FILE")"
mkdir -p "$(dirname "$SCRIPT_LOG")"

# ====================
# 日志函数
# ====================
log() {
    local level="$1"
    shift
    local message="$@"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" | tee -a "$SCRIPT_LOG"
}

# ====================
# 核心函数
# ====================

# 获取时间范围内的日志
get_recent_logs() {
    local log_file="$1"
    local minutes="$2"

    # 计算起始时间
    local start_time=$(date -d "$minutes minutes ago" '+%Y-%m-%d %H:%M' 2>/dev/null || \
                       date -v-${minutes}M '+%Y-%m-%d %H:%M' 2>/dev/null || \
                       echo "")

    if [[ -z "$start_time" ]]; then
        # 如果 date 命令不支持相对时间，返回所有日志
        cat "$log_file"
        return
    fi

    # 使用 awk 过滤时间范围
    awk -v start="$start_time" '
        {
            # 提取日志时间戳 (前 16 个字符: YYYY-MM-DD HH:MM)
            log_time = substr($0, 1, 16)
            if (log_time >= start) print
        }
    ' "$log_file"
}

# 统计错误
count_errors() {
    local log_file="$1"
    local minutes="$2"

    get_recent_logs "$log_file" "$minutes" | grep -c "ERROR" || echo 0
}

# 统计告警
count_warns() {
    local log_file="$1"
    local minutes="$2"

    get_recent_logs "$log_file" "$minutes" | grep -c "WARN" || echo 0
}

# 获取错误详情
get_error_details() {
    local log_file="$1"
    local minutes="$2"

    get_recent_logs "$log_file" "$minutes" | grep "ERROR"
}

# 发送 Webhook 告警
send_webhook_alert() {
    local message="$1"

    if [[ -z "$WEBHOOK_URL" ]]; then
        log WARN "Webhook URL 未配置，跳过推送"
        return 0
    fi

    # 使用 curl 发送（如果可用）
    if command -v curl &>/dev/null; then
        curl -s -X POST "$WEBHOOK_URL" \
             -H "Content-Type: application/json" \
             -d "{\"text\": \"$message\"}" \
             > /dev/null 2>&1

        if [[ $? -eq 0 ]]; then
            log INFO "Webhook 告警发送成功"
        else
            log ERROR "Webhook 告警发送失败"
        fi
    else
        log WARN "curl 不可用，跳过 Webhook 推送"
    fi
}

# 写入告警文件
write_alert() {
    local level="$1"
    local message="$2"
    local details="$3"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    {
        echo "========================================"
        echo "告警时间: $timestamp"
        echo "告警级别: $level"
        echo "告警内容: $message"
        echo "----------------------------------------"
        echo "错误详情:"
        echo "$details"
        echo "========================================"
        echo ""
    } >> "$ALERT_FILE"

    log INFO "告警已写入: $ALERT_FILE"
}

# ====================
# 主程序
# ====================

log INFO "========== 开始检查 =========="
log INFO "日志文件: $LOG_FILE"
log INFO "时间窗口: ${TIME_WINDOW} 分钟"
log INFO "错误阈值: $ERROR_THRESHOLD"

# 检查日志文件
if [[ ! -f "$LOG_FILE" ]]; then
    log ERROR "日志文件不存在: $LOG_FILE"
    exit 1
fi

# 统计错误和告警
error_count=$(count_errors "$LOG_FILE" "$TIME_WINDOW")
warn_count=$(count_warns "$LOG_FILE" "$TIME_WINDOW")
total_lines=$(get_recent_logs "$LOG_FILE" "$TIME_WINDOW" | wc -l)

log INFO "最近 ${TIME_WINDOW} 分钟统计:"
log INFO "  - 总日志行数: $total_lines"
log INFO "  - ERROR 数量: $error_count"
log INFO "  - WARN 数量: $warn_count"

# 判断是否需要告警
alert_triggered=false

if [[ $error_count -ge $ERROR_THRESHOLD ]]; then
    alert_triggered=true
    alert_level="CRITICAL"
    alert_message="错误数量超过阈值: ${error_count} >= ${ERROR_THRESHOLD}"

    log WARN "$alert_message"

    # 获取错误详情
    error_details=$(get_error_details "$LOG_FILE" "$TIME_WINDOW")

    # 写入告警文件
    write_alert "$alert_level" "$alert_message" "$error_details"

    # 尝试发送 Webhook
    send_webhook_alert "[${alert_level}] $(hostname): $alert_message"

    # 输出告警信息
    echo ""
    echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
    echo "              告警触发！"
    echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
    echo "级别: $alert_level"
    echo "原因: $alert_message"
    echo ""
    echo "错误详情:"
    echo "$error_details"
    echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
fi

if [[ "$alert_triggered" == false ]]; then
    log INFO "状态正常，无需告警"
fi

log INFO "========== 检查完成 =========="

# 返回码：0=正常，1=告警
if [[ "$alert_triggered" == true ]]; then
    exit 1
else
    exit 0
fi
```

运行测试：

```bash
chmod +x ~/bash-course/log-alerter.sh

# 运行检查
~/bash-course/log-alerter.sh

# 查看告警记录
cat ~/reports/alerts.log

# 查看脚本日志
cat ~/logs/log-alerter.log
```

输出示例：

```
[2025-01-15 16:00:00] [INFO] ========== 开始检查 ==========
[2025-01-15 16:00:00] [INFO] 日志文件: /home/ssm-user/bash-course/logs/app.log
[2025-01-15 16:00:00] [INFO] 时间窗口: 10 分钟
[2025-01-15 16:00:00] [INFO] 错误阈值: 3
[2025-01-15 16:00:00] [INFO] 最近 10 分钟统计:
[2025-01-15 16:00:00] [INFO]   - 总日志行数: 20
[2025-01-15 16:00:00] [INFO]   - ERROR 数量: 6
[2025-01-15 16:00:00] [INFO]   - WARN 数量: 1
[2025-01-15 16:00:00] [WARN] 错误数量超过阈值: 6 >= 3
[2025-01-15 16:00:00] [INFO] 告警已写入: /home/ssm-user/reports/alerts.log

!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
              告警触发！
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
级别: CRITICAL
原因: 错误数量超过阈值: 6 >= 3

错误详情:
2025-01-15 15:42:03 ERROR Database connection timeout
2025-01-15 15:46:07 ERROR API rate limit exceeded
2025-01-15 15:48:09 ERROR Service unavailable
2025-01-15 15:51:12 ERROR Connection reset by peer
2025-01-15 15:54:15 ERROR Timeout waiting for response
2025-01-15 15:57:18 ERROR Internal server error
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
[2025-01-15 16:00:00] [INFO] ========== 检查完成 ==========
```

### 设置定时任务

```bash
# 编辑 crontab
crontab -e

# 添加：每 5 分钟检查一次
*/5 * * * * /home/ssm-user/bash-course/log-alerter.sh >> /home/ssm-user/logs/cron.log 2>&1
```

---

## 练习挑战

1. 添加邮件通知功能（使用 `mail` 命令）

2. 添加 `-t` 参数自定义阈值

3. 添加多日志文件支持

4. 实现错误率计算（ERROR / 总行数 * 100%）

---

## 本课小结

| 命令/概念 | 用途 | 示例 |
|-----------|------|------|
| `grep -E` | 扩展正则 | `grep -E "error\|warn"` |
| `grep -o` | 只输出匹配 | `grep -oE '[0-9]+'` |
| `sed 's///'` | 替换 | `sed 's/old/new/g'` |
| `sed -i` | 就地修改 | `sed -i 's/a/b/' file` |
| `awk '{}'` | 字段处理 | `awk '{print $1}'` |
| `awk -F` | 指定分隔符 | `awk -F':'` |
| `crontab -e` | 编辑定时任务 | `*/5 * * * * cmd` |
| `tee` | 分流输出 | `cmd \| tee log.txt` |

---

## 系列完结

恭喜你完成了 Bash 脚本入门系列！你已经掌握了：

- 脚本基础（变量、执行、调试）
- 文件系统操作（路径、权限、重定向）
- 文本处理（管道、grep、awk、sed）
- 流程控制（条件、循环、数组）
- 模块化编程（函数、参数、返回值）
- 自动化运维（日志分析、定时任务、告警）

这些技能在日本 IT 公司的运维工作中非常实用，祝你在职场上取得成功！

---

## 系列导航

← [05 · 函数与参数](../05-functions/) | [系列首页](../)
