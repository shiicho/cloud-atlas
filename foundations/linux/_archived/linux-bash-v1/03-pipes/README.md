# 03 · 管道与文本基础（Pipes & Text Basics）

> **目标**：掌握管道和文本处理命令，分析 Web 日志  
> **前置**：[02 · 变量与文件系统](../02-filesystem/)  
> **时间**：20-30 分钟  
> **实战项目**：Web 日志 Top 分析（故障初查场景）  

## 将学到的内容

1. 管道 `|` 的原理和用法
2. 文本处理命令（cat, head, tail, sort, uniq, wc, cut）
3. 常见日志路径
4. 调试技巧：`set -euo pipefail`

---

## Step 1 — 理解管道

### 什么是管道？

管道 `|` 把一个命令的输出传给下一个命令作为输入：

```bash
# 命令1 的输出 → 命令2 的输入
command1 | command2 | command3
```

### 简单示例

```bash
# 列出文件，只看前 5 个
ls -la /var/log | head -5

# 统计文件数量
ls /var/log | wc -l

# 查找包含 error 的进程
ps aux | grep nginx
```

### 数据流

```
stdin (0) → [命令] → stdout (1)
                   → stderr (2)

命令1 stdout → | → 命令2 stdin → | → 命令3 stdin
```

---

## Step 2 — 文本处理命令

### cat - 显示文件内容

```bash
# 显示整个文件
cat /etc/os-release

# 显示行号
cat -n /etc/passwd

# 合并多个文件
cat file1.txt file2.txt > combined.txt
```

### head / tail - 头部/尾部

```bash
# 显示前 10 行（默认）
head /var/log/messages

# 显示前 5 行
head -5 /var/log/messages

# 显示后 10 行
tail /var/log/messages

# 实时跟踪日志（常用！）
tail -f /var/log/messages
```

### wc - 统计

```bash
# 统计行数
wc -l /etc/passwd

# 统计单词数
wc -w /etc/passwd

# 统计字符数
wc -c /etc/passwd

# 组合使用
cat /etc/passwd | wc -l
```

### sort - 排序

```bash
# 字母排序
sort names.txt

# 数字排序
sort -n numbers.txt

# 逆序
sort -r names.txt

# 按第 2 列排序
sort -k2 data.txt

# 人类可读大小排序（如 1K, 2M, 3G）
du -sh /var/* | sort -h
du -sh /var/* | sort -rh    # 逆序，最大在前
```

### uniq - 去重

```bash
# 去重（必须先排序！）
sort names.txt | uniq

# 显示重复次数
sort names.txt | uniq -c

# 只显示重复的行
sort names.txt | uniq -d
```

### cut - 提取字段

```bash
# 按分隔符提取字段
cut -d':' -f1 /etc/passwd          # 用户名
cut -d':' -f1,3 /etc/passwd        # 用户名和 UID
cut -d':' -f1-3 /etc/passwd        # 第 1-3 字段

# 按字符位置提取
cut -c1-10 /etc/passwd             # 前 10 个字符
```

---

## Step 3 — 组合技巧

### 经典组合

```bash
# 统计某类文件数量
ls /var/log/*.log 2>/dev/null | wc -l

# Top 5 最大文件
ls -lS /var/log | head -6

# 统计每种 shell 的用户数
cut -d':' -f7 /etc/passwd | sort | uniq -c | sort -rn

# 查看最近登录的用户
last | head -10
```

### 日志分析入门

```bash
# 查看最近的系统日志
sudo tail -20 /var/log/messages

# 统计包含 error 的行数
sudo grep -i error /var/log/messages | wc -l

# 提取时间和消息
sudo tail -100 /var/log/messages | cut -c1-15,45-
```

---

## Step 4 — 常见日志路径

> 在日本 IT 公司做运维，经常需要分析各种日志。熟悉这些路径很重要。  

| 路径 | 用途 |
|------|------|
| `/var/log/messages` | 系统日志（Amazon Linux 2023） |
| `/var/log/syslog` | 系统日志（Ubuntu/Debian） |
| `/var/log/secure` | 安全/认证日志 |
| `/var/log/nginx/` | Nginx 访问/错误日志 |
| `/var/log/httpd/` | Apache 访问/错误日志 |
| `/var/log/cron` | 定时任务日志 |

### 创建练习用的模拟日志

```bash
# 创建模拟 Web 访问日志
mkdir -p ~/bash-course/logs

cat > ~/bash-course/logs/access.log << 'EOF'
192.168.1.100 - - [15/Jan/2025:10:00:01 +0900] "GET /index.html HTTP/1.1" 200 1234
192.168.1.101 - - [15/Jan/2025:10:00:02 +0900] "GET /api/users HTTP/1.1" 200 567
192.168.1.100 - - [15/Jan/2025:10:00:03 +0900] "GET /index.html HTTP/1.1" 200 1234
192.168.1.102 - - [15/Jan/2025:10:00:04 +0900] "POST /api/login HTTP/1.1" 500 89
192.168.1.100 - - [15/Jan/2025:10:00:05 +0900] "GET /css/style.css HTTP/1.1" 200 456
192.168.1.103 - - [15/Jan/2025:10:00:06 +0900] "GET /api/users HTTP/1.1" 200 567
192.168.1.101 - - [15/Jan/2025:10:00:07 +0900] "GET /index.html HTTP/1.1" 200 1234
192.168.1.104 - - [15/Jan/2025:10:00:08 +0900] "GET /api/products HTTP/1.1" 503 0
192.168.1.100 - - [15/Jan/2025:10:00:09 +0900] "GET /api/users HTTP/1.1" 200 567
192.168.1.102 - - [15/Jan/2025:10:00:10 +0900] "GET /index.html HTTP/1.1" 200 1234
192.168.1.105 - - [15/Jan/2025:10:00:11 +0900] "GET /api/login HTTP/1.1" 500 89
192.168.1.100 - - [15/Jan/2025:10:00:12 +0900] "GET /js/app.js HTTP/1.1" 200 789
EOF

echo "模拟日志已创建: ~/bash-course/logs/access.log"
```

---

## Step 5 — 调试技巧

> 🔧 **调试卡片**：`set -euo pipefail` 是 Bash 脚本的最佳实践。  

### set -euo pipefail

```bash
#!/bin/bash
set -euo pipefail

# -e: 遇到错误立即退出
# -u: 使用未定义变量时报错
# -o pipefail: 管道中任一命令失败则整体失败
```

### 对比演示

```bash
nano ~/bash-course/pipefail-demo.sh
```

```bash
#!/bin/bash

echo "=== 没有 pipefail ==="
# 即使 grep 失败，echo 仍会执行
cat /nonexistent 2>/dev/null | grep "pattern" | echo "Done 1"
echo "继续执行..."

echo ""
echo "=== 使用 pipefail ==="
set -o pipefail

# 现在管道中的失败会被检测到
if cat /nonexistent 2>/dev/null | grep "pattern" > /dev/null; then
    echo "Done 2"
else
    echo "管道失败，退出码: $?"
fi
```

运行：

```bash
bash ~/bash-course/pipefail-demo.sh
```

---

## Mini-Project：Web 日志 Top 分析

> **场景**：网站出现故障时，运维需要快速分析访问日志，找出 Top IP 和 Top 路径。这是日本 IT 公司「障害対応」的基本功。  

```bash
nano ~/bash-course/log-analyzer.sh
```

```bash
#!/bin/bash
# Web 日志 Top 分析 - Log Analyzer
# 用途：故障初查、流量分析

set -euo pipefail

# 配置
log_file="${1:-$HOME/bash-course/logs/access.log}"
top_n=5
output_dir=~/reports
timestamp=$(date +%Y%m%d_%H%M%S)
report_file="${output_dir}/log_analysis_${timestamp}.txt"

# 检查日志文件是否存在
if [[ ! -f "$log_file" ]]; then
    echo "错误: 日志文件不存在: $log_file"
    exit 1
fi

# 创建输出目录
mkdir -p "$output_dir"

# 开始分析
{
    echo "========================================"
    echo "       Web 日志分析报告"
    echo "========================================"
    echo "日志文件: $log_file"
    echo "分析时间: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "总请求数: $(wc -l < "$log_file")"
    echo ""

    echo "======== Top ${top_n} IP 地址 ========"
    # 提取 IP（第 1 列），排序，计数，取 Top N
    cut -d' ' -f1 "$log_file" | sort | uniq -c | sort -rn | head -${top_n}
    echo ""

    echo "======== Top ${top_n} 请求路径 ========"
    # 提取路径（第 7 列），排序，计数，取 Top N
    cut -d' ' -f7 "$log_file" | sort | uniq -c | sort -rn | head -${top_n}
    echo ""

    echo "======== 状态码统计 ========"
    # 提取状态码（第 9 列），排序，计数
    cut -d' ' -f9 "$log_file" | sort | uniq -c | sort -rn
    echo ""

    echo "======== 5xx 错误详情 ========"
    # 筛选 5xx 错误
    grep -E '" 5[0-9]{2} ' "$log_file" || echo "(无 5xx 错误)"
    echo ""

    echo "========================================"
} | tee "$report_file"

echo ""
echo "报告已保存: $report_file"

exit 0
```

运行：

```bash
chmod +x ~/bash-course/log-analyzer.sh
~/bash-course/log-analyzer.sh
```

输出示例：

```
========================================
       Web 日志分析报告
========================================
日志文件: /home/ssm-user/bash-course/logs/access.log
分析时间: 2025-01-15 14:30:00
总请求数: 12

======== Top 5 IP 地址 ========
      5 192.168.1.100
      2 192.168.1.101
      2 192.168.1.102
      1 192.168.1.103
      1 192.168.1.104

======== Top 5 请求路径 ========
      4 /index.html
      3 /api/users
      1 /api/products
      1 /api/login
      1 /css/style.css

======== 状态码统计 ========
      9 200
      2 500
      1 503

======== 5xx 错误详情 ========
192.168.1.102 - - [15/Jan/2025:10:00:04 +0900] "POST /api/login HTTP/1.1" 500 89
192.168.1.104 - - [15/Jan/2025:10:00:08 +0900] "GET /api/products HTTP/1.1" 503 0
192.168.1.105 - - [15/Jan/2025:10:00:11 +0900] "GET /api/login HTTP/1.1" 500 89

========================================

报告已保存: /home/ssm-user/reports/log_analysis_20250115_143000.txt
```

---

## 练习挑战

1. 修改脚本，添加「按小时统计请求量」功能

2. 添加参数 `-n 10` 支持自定义 Top N 数量

---

## 本课小结

| 命令 | 用途 | 示例 |
|------|------|------|
| `\|` | 管道连接 | `cmd1 \| cmd2` |
| `cat` | 显示文件 | `cat file.txt` |
| `head` | 显示头部 | `head -5 file` |
| `tail` | 显示尾部 | `tail -f log` |
| `sort` | 排序 | `sort -rn` |
| `uniq` | 去重计数 | `uniq -c` |
| `wc` | 统计 | `wc -l` |
| `cut` | 提取字段 | `cut -d':' -f1` |

**调试技巧**：`set -euo pipefail` 让脚本更健壮。

---

## 下一步

掌握了管道和文本处理，下一课我们学习条件判断和循环！

→ [04 · 条件与循环](../04-loops/)

## 系列导航

← [02 · 变量与文件系统](../02-filesystem/) | [系列首页](../) | [04 · 条件与循环](../04-loops/) →
