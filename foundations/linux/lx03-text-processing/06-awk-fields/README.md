# 06 - awk 字段处理（awk Field Processing）

> **目标**：掌握 awk 字段提取和处理，从结构化日志中精准抽取所需数据  
> **前置**：已完成 [05 - sed 文本转换](../05-sed-transformation/)  
> **时间**：⚡ 25 分钟（速读）/ 🔬 90 分钟（完整实操）  
> **实战项目**：Apache/Nginx 访问日志分析（提取 IP、状态码、响应时间）  

---

## 先跑起来（5 分钟）

> 不需要理解，先体验 awk 的字段处理威力！  

### 创建练习环境

```bash
# 创建练习目录
mkdir -p ~/awk-lab && cd ~/awk-lab

# 创建模拟的 Nginx 访问日志（Combined Log Format）
cat > access.log << 'EOF'
192.168.1.100 - - [04/Jan/2026:09:00:01 +0900] "GET /index.html HTTP/1.1" 200 1234 "-" "Mozilla/5.0" 0.023
192.168.1.101 - - [04/Jan/2026:09:00:05 +0900] "POST /api/login HTTP/1.1" 200 89 "https://example.com" "Mozilla/5.0" 0.145
10.0.0.50 - - [04/Jan/2026:09:01:22 +0900] "GET /api/orders HTTP/1.1" 504 0 "-" "curl/7.68.0" 30.001
192.168.1.100 - - [04/Jan/2026:09:01:23 +0900] "GET /api/orders HTTP/1.1" 200 5678 "-" "Mozilla/5.0" 0.089
192.168.1.102 - - [04/Jan/2026:09:05:00 +0900] "GET /health HTTP/1.1" 200 15 "-" "ELB-HealthChecker" 0.002
10.0.0.50 - - [04/Jan/2026:09:10:01 +0900] "GET /api/products HTTP/1.1" 500 0 "-" "curl/7.68.0" 0.456
192.168.1.103 - - [04/Jan/2026:09:10:05 +0900] "GET /api/products HTTP/1.1" 200 2345 "-" "Mozilla/5.0" 0.034
192.168.1.100 - - [04/Jan/2026:09:15:30 +0900] "GET /css/style.css HTTP/1.1" 304 0 "-" "Mozilla/5.0" 0.001
192.168.1.104 - - [04/Jan/2026:09:20:15 +0900] "POST /api/upload HTTP/1.1" 413 0 "-" "Mozilla/5.0" 0.567
10.0.0.51 - - [04/Jan/2026:09:25:00 +0900] "GET /api/users HTTP/1.1" 502 0 "-" "Python-requests/2.28" 15.234
EOF

echo "练习日志已创建: ~/awk-lab/access.log"
```

### 立即体验

```bash
cd ~/awk-lab

# 魔法 1: 提取所有 IP 地址（第 1 个字段）
awk '{print $1}' access.log

# 魔法 2: 提取 IP 和 HTTP 状态码
awk '{print $1, $9}' access.log

# 魔法 3: 只显示 5xx 错误的请求
awk '$9 >= 500 {print $0}' access.log

# 魔法 4: 提取响应时间超过 1 秒的慢请求
awk '$NF > 1 {print $1, $7, $NF}' access.log

# 魔法 5: 统计每个 IP 的请求次数
awk '{count[$1]++} END {for(ip in count) print count[ip], ip}' access.log
```

**观察输出**：

```
192.168.1.100
192.168.1.101
10.0.0.50
192.168.1.100
...
```

你刚刚用 awk 完成了：
- 字段提取（フィールド抽出）
- 条件过滤（根据状态码筛选）
- 访问最后一个字段（响应时间）
- 数据聚合（IP 访问统计）

这些都是日志分析和定型レポート生成的核心技能。现在让我们系统学习！

---

## 核心概念

### awk 是什么？

awk 是一个强大的文本处理语言，特别擅长处理**结构化数据**（按字段分隔的数据）。它的名字来自三位创造者：**A**ho、**W**einberger、**K**ernighan。

<!-- DIAGRAM: awk-processing-flow -->
![awk Processing Flow](images/awk-processing-flow.png)

<details>
<summary>View ASCII source</summary>

```
┌─────────────────┐     ┌─────────────────────────────┐     ┌─────────────────┐
│    输入文件      │────▶│           awk               │────▶│     stdout      │
│   (每行扫描)     │     │  ┌─────────────────────┐   │     │    (输出结果)    │
└─────────────────┘     │  │ 自动按空白分割字段   │   │     └─────────────────┘
                        │  │                     │   │
                        │  │ $1   $2   $3  ...  │   │
                        │  │  ↓    ↓    ↓       │   │
                        │  │ 字段  字段  字段    │   │
                        │  └─────────────────────┘   │
                        └─────────────────────────────┘

每行输入 → 自动分割成字段 ($1, $2, ...) → 执行动作 → 输出结果
```

</details>
<!-- /DIAGRAM -->

**awk 的核心思想**：
- 自动将每行按空白字符分割成字段
- 用 `$1`, `$2`, `$3` ... 访问各个字段
- 可以根据模式（pattern）选择性地处理某些行
- 可以在处理过程中进行计算和聚合

### 基本语法

```bash
awk 'pattern { action }' file
```

- **pattern**：条件（可选），决定哪些行执行 action
- **action**：要执行的操作（通常是 print）
- 如果省略 pattern，对所有行执行 action
- 如果省略 action，默认打印整行

```bash
# 只有 action：打印所有行的第一个字段
awk '{print $1}' file

# pattern + action：只处理包含 ERROR 的行
awk '/ERROR/ {print $1}' file

# 只有 pattern：打印匹配的整行
awk '/ERROR/' file
```

---

## 内置变量

### 字段变量

| 变量 | 含义 | 示例 |
|------|------|------|
| `$0` | 整行内容 | `awk '{print $0}'` |
| `$1` | 第 1 个字段 | `awk '{print $1}'` |
| `$2` | 第 2 个字段 | `awk '{print $2}'` |
| `$NF` | 最后一个字段 | `awk '{print $NF}'` |
| `$(NF-1)` | 倒数第 2 个字段 | `awk '{print $(NF-1)}'` |

### 特殊变量

| 变量 | 含义 | 用途 |
|------|------|------|
| `NF` | Number of Fields | 当前行的字段数 |
| `NR` | Number of Records | 当前行号（从 1 开始） |
| `FS` | Field Separator | 输入字段分隔符（默认空白） |
| `OFS` | Output Field Separator | 输出字段分隔符（默认空格） |
| `RS` | Record Separator | 记录分隔符（默认换行） |
| `ORS` | Output Record Separator | 输出记录分隔符 |

### 实际演示

```bash
cd ~/awk-lab

# 显示行号和字段数
awk '{print NR": "$0" (fields: "NF")"}' access.log | head -3
# 输出:
# 1: 192.168.1.100 - - [04/Jan/2026:09:00:01 +0900] "GET /index.html HTTP/1.1" 200 1234 "-" "Mozilla/5.0" 0.023 (fields: 12)
# 2: 192.168.1.101 - - [04/Jan/2026:09:00:05 +0900] "POST /api/login HTTP/1.1" 200 89 "https://example.com" "Mozilla/5.0" 0.145 (fields: 12)
# 3: 10.0.0.50 - - [04/Jan/2026:09:01:22 +0900] "GET /api/orders HTTP/1.1" 504 0 "-" "curl/7.68.0" 30.001 (fields: 12)

# 访问最后一个字段（响应时间）
awk '{print $1, $NF}' access.log | head -3
# 输出:
# 192.168.1.100 0.023
# 192.168.1.101 0.145
# 10.0.0.50 30.001

# 访问倒数第二个字段
awk '{print $(NF-1)}' access.log | head -3
# 输出:
# "Mozilla/5.0"
# "Mozilla/5.0"
# "curl/7.68.0"
```

---

## 字段分隔符

### 默认分隔符（空白）

awk 默认按**连续空白字符**（空格、制表符）分割字段：

```bash
echo "a   b     c" | awk '{print $2}'
# 输出: b（多个空格被视为一个分隔符）
```

### 使用 -F 指定分隔符

```bash
# 冒号分隔（适用于 /etc/passwd）
awk -F: '{print $1, $3}' /etc/passwd | head -3
# 输出:
# root 0
# daemon 1
# bin 2

# 逗号分隔（CSV 文件）
echo "name,age,city" | awk -F, '{print $2}'
# 输出: age
```

### 多字符分隔符

```bash
# 使用正则表达式作为分隔符
awk -F'[,;]' '{print $1, $2}' << 'EOF'
a,b;c
d;e,f
EOF
# 输出:
# a b
# d e

# 分隔符为 "::"
echo "a::b::c" | awk -F'::' '{print $2}'
# 输出: b
```

### 在 BEGIN 块中设置分隔符

```bash
# 使用 BEGIN 块设置分隔符
awk 'BEGIN {FS=":"} {print $1}' /etc/passwd | head -3

# 同时设置输出分隔符
awk 'BEGIN {FS=":"; OFS="\t"} {print $1, $3, $7}' /etc/passwd | head -3
# 输出: 用制表符分隔的 用户名、UID、shell
```

---

## 模式匹配

### 正则表达式模式

awk 内置正则匹配，不需要像 grep 那样单独调用：

```bash
cd ~/awk-lab

# 匹配包含 ERROR 或 5xx 状态码的行
awk '/500|502|503|504/ {print $1, $9, $7}' access.log

# 只处理 GET 请求
awk '/GET/ {print $1, $7}' access.log

# 排除健康检查请求
awk '!/health/' access.log
```

### 字段条件

```bash
# 状态码 >= 500
awk '$9 >= 500 {print $0}' access.log

# 响应时间 > 1 秒
awk '$NF > 1 {print $1, $7, $NF}' access.log

# IP 以 10. 开头
awk '$1 ~ /^10\./ {print $0}' access.log

# IP 不以 192. 开头
awk '$1 !~ /^192\./ {print $0}' access.log
```

### 组合条件

```bash
# AND: 5xx 错误且响应时间 > 10 秒
awk '$9 >= 500 && $NF > 10 {print $1, $9, $NF}' access.log

# OR: 4xx 或 5xx 错误
awk '$9 >= 400 {print $1, $9, $7}' access.log

# 复杂条件
awk 'NR > 1 && $9 != 200 {print NR, $1, $9}' access.log
```

---

## 实战项目：访问日志分析

### 场景

> 你是一名运维工程师，需要分析 Web 服务器的访问日志，生成运维报告（定型レポート）。报告需要包含：Top IP、状态码分布、慢请求列表。  

### 准备更丰富的测试数据

```bash
cd ~/awk-lab

# 创建更大的测试日志（100 行）
cat > access_large.log << 'EOF'
192.168.1.100 - - [04/Jan/2026:09:00:01 +0900] "GET /index.html HTTP/1.1" 200 1234 "-" "Mozilla/5.0" 0.023
192.168.1.101 - - [04/Jan/2026:09:00:02 +0900] "GET /api/users HTTP/1.1" 200 567 "-" "Mozilla/5.0" 0.045
192.168.1.100 - - [04/Jan/2026:09:00:03 +0900] "GET /index.html HTTP/1.1" 200 1234 "-" "Mozilla/5.0" 0.021
192.168.1.102 - - [04/Jan/2026:09:00:04 +0900] "POST /api/login HTTP/1.1" 500 89 "-" "Mozilla/5.0" 0.234
192.168.1.100 - - [04/Jan/2026:09:00:05 +0900] "GET /css/style.css HTTP/1.1" 200 456 "-" "Mozilla/5.0" 0.012
192.168.1.103 - - [04/Jan/2026:09:00:06 +0900] "GET /api/users HTTP/1.1" 200 567 "-" "Mozilla/5.0" 0.067
192.168.1.101 - - [04/Jan/2026:09:00:07 +0900] "GET /index.html HTTP/1.1" 200 1234 "-" "Mozilla/5.0" 0.019
192.168.1.104 - - [04/Jan/2026:09:00:08 +0900] "GET /api/products HTTP/1.1" 503 0 "-" "Mozilla/5.0" 1.234
192.168.1.100 - - [04/Jan/2026:09:00:09 +0900] "GET /api/users HTTP/1.1" 200 567 "-" "Mozilla/5.0" 0.089
192.168.1.102 - - [04/Jan/2026:09:00:10 +0900] "GET /index.html HTTP/1.1" 200 1234 "-" "Mozilla/5.0" 0.015
10.0.0.50 - - [04/Jan/2026:09:00:11 +0900] "GET /api/orders HTTP/1.1" 504 0 "-" "curl/7.68.0" 30.001
192.168.1.100 - - [04/Jan/2026:09:00:12 +0900] "GET /js/app.js HTTP/1.1" 200 789 "-" "Mozilla/5.0" 0.008
192.168.1.105 - - [04/Jan/2026:09:00:13 +0900] "POST /api/upload HTTP/1.1" 413 0 "-" "Mozilla/5.0" 0.456
10.0.0.51 - - [04/Jan/2026:09:00:14 +0900] "GET /api/users HTTP/1.1" 502 0 "-" "Python-requests/2.28" 15.234
192.168.1.100 - - [04/Jan/2026:09:00:15 +0900] "GET /health HTTP/1.1" 200 15 "-" "ELB-HealthChecker" 0.002
EOF

echo "大型测试日志已创建"
```

### Task 1: 提取 IP 地址

```bash
# 提取所有 IP 地址
awk '{print $1}' access_large.log

# 去重后的 IP 列表
awk '{print $1}' access_large.log | sort -u
```

### Task 2: 状态码分析

```bash
# 提取状态码（第 9 字段）
awk '{print $9}' access_large.log

# 统计各状态码数量
awk '{print $9}' access_large.log | sort | uniq -c | sort -rn
```

### Task 3: 筛选 5xx 错误

```bash
# 只显示 5xx 错误
awk '$9 >= 500 && $9 < 600 {print $1, $9, $7}' access_large.log

# 显示完整的错误行
awk '$9 >= 500' access_large.log
```

### Task 4: 慢请求分析

```bash
# 响应时间超过 1 秒的请求
awk '$NF > 1 {print $1, $7, $NF"s"}' access_large.log

# 按响应时间排序
awk '{print $NF, $1, $7}' access_large.log | sort -rn | head -5
```

### Task 5: IP 访问统计（Top N）

```bash
# 统计每个 IP 的访问次数
awk '{count[$1]++} END {for(ip in count) print count[ip], ip}' access_large.log | sort -rn

# Top 5 IP
awk '{count[$1]++} END {for(ip in count) print count[ip], ip}' access_large.log | sort -rn | head -5
```

### 完整分析脚本

```bash
cat > ~/awk-lab/log-report.sh << 'EOF'
#!/bin/bash
# 访问日志分析报告 - Access Log Analysis Report
# フィールド抽出とカラム集計（字段提取和列聚合）

set -euo pipefail

LOG_FILE="${1:-access_large.log}"

if [[ ! -f "$LOG_FILE" ]]; then
    echo "Error: Log file not found: $LOG_FILE"
    exit 1
fi

echo "========================================"
echo "       访问日志分析报告"
echo "       Access Log Analysis Report"
echo "========================================"
echo "日志文件: $LOG_FILE"
echo "分析时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo ""

# 总请求数
total=$(wc -l < "$LOG_FILE")
echo "总请求数: $total"
echo ""

echo "======== Top 5 IP 地址 ========"
awk '{count[$1]++} END {for(ip in count) print count[ip], ip}' "$LOG_FILE" | sort -rn | head -5
echo ""

echo "======== 状态码分布 ========"
awk '{count[$9]++} END {for(code in count) printf "%s: %d (%.1f%%)\n", code, count[code], count[code]*100/'$total'}' "$LOG_FILE" | sort -t: -k1 -n
echo ""

echo "======== 5xx 错误详情 ========"
awk '$9 >= 500 {print $1, $9, $7, $NF"s"}' "$LOG_FILE" || echo "(无 5xx 错误)"
echo ""

echo "======== 慢请求 (>1s) ========"
awk '$NF > 1 {printf "%-15s %-30s %ss\n", $1, $7, $NF}' "$LOG_FILE" || echo "(无慢请求)"
echo ""

echo "========================================"
EOF

chmod +x ~/awk-lab/log-report.sh
```

### 运行报告

```bash
cd ~/awk-lab
./log-report.sh access_large.log
```

**预期输出**：

```
========================================
       访问日志分析报告
       Access Log Analysis Report
========================================
日志文件: access_large.log
分析时间: 2026-01-04 14:30:00

总请求数: 15

======== Top 5 IP 地址 ========
6 192.168.1.100
2 192.168.1.101
2 192.168.1.102
1 192.168.1.103
1 192.168.1.104

======== 状态码分布 ========
200: 10 (66.7%)
413: 1 (6.7%)
500: 1 (6.7%)
502: 1 (6.7%)
503: 1 (6.7%)
504: 1 (6.7%)

======== 5xx 错误详情 ========
192.168.1.102 500 /api/login 0.234s
192.168.1.104 503 /api/products 1.234s
10.0.0.50 504 /api/orders 30.001s
10.0.0.51 502 /api/users 15.234s

======== 慢请求 (>1s) ========
192.168.1.104   /api/products                  1.234s
10.0.0.50       /api/orders                    30.001s
10.0.0.51       /api/users                     15.234s

========================================
```

---

## 反面模式（Anti-Patterns）

### Anti-Pattern 1: grep | awk（awk 自己可以做模式匹配）

```bash
# 不好: 不必要的 grep
grep 'ERROR' app.log | awk '{print $1}'

# 好: awk 自己做模式匹配
awk '/ERROR/ {print $1}' app.log
```

### Anti-Pattern 2: 字段之间忘记逗号

```bash
# 不好: $1 和 $2 直接连接，没有分隔符
awk '{print $1 $2}' access.log
# 输出: 192.168.1.100-   (字段粘在一起)

# 好: 用逗号分隔字段
awk '{print $1, $2}' access.log
# 输出: 192.168.1.100 -  (用 OFS 分隔)

# 更好: 明确指定分隔符
awk '{print $1 " | " $2}' access.log
# 输出: 192.168.1.100 | -
```

### Anti-Pattern 3: cut 处理不定空白

```bash
# 不好: cut 无法处理多空格
echo "a   b     c" | cut -d' ' -f2
# 输出: (空，因为第二个字段是空格)

# 好: awk 自动合并连续空白
echo "a   b     c" | awk '{print $2}'
# 输出: b
```

### Anti-Pattern 4: 用 awk 处理复杂 CSV

```bash
# 危险: 简单 -F, 无法处理带引号的 CSV
echo 'name,"city, state",age' | awk -F, '{print $2}'
# 输出: "city   (错误！引号内的逗号也被当成分隔符)

# 正确: 使用专门的 CSV 工具
# csvcut -c 2 file.csv
# 或使用 miller: mlr --csv cut -f column2 file.csv
```

---

## 现代替代工具：miller (mlr)

**miller** 是处理结构化数据（CSV、JSON）的现代工具，比 awk 更适合表格数据：

### 安装

```bash
# Ubuntu/Debian
sudo apt install miller

# macOS
brew install miller

# RHEL/CentOS/Amazon Linux
sudo yum install miller
```

### miller 基本用法

```bash
# 创建 CSV 测试文件
cat > ~/awk-lab/users.csv << 'EOF'
name,age,city
Alice,30,Tokyo
Bob,25,Osaka
Charlie,35,"New York"
EOF

# 显示 CSV（表格格式）
mlr --csv --opprint cat users.csv

# 筛选字段
mlr --csv cut -f name,city users.csv

# 条件筛选
mlr --csv filter '$age > 28' users.csv

# 排序
mlr --csv sort -f age users.csv

# 统计
mlr --csv stats1 -a mean,max -f age users.csv
```

### miller vs awk

| 场景 | awk | miller |
|------|-----|--------|
| 日志文件（空格分隔） | 首选 | 可用 |
| CSV 文件 | 危险（引号问题） | 首选 |
| JSON 数据 | 不支持 | 原生支持 |
| 快速字段提取 | 简单 | 稍复杂 |
| 数据统计 | 需手写 | 内置函数 |

> **建议**：日志分析用 awk，CSV/JSON 用 miller。两者都要会。  

---

## 动手练习

### 练习 1: 基础字段提取

```bash
cd ~/awk-lab

# 任务 1: 从 /etc/passwd 提取用户名和 shell
# 提示: 用 -F: 指定分隔符，字段 1 和 7
awk -F: '{print $1, $7}' /etc/passwd | head -5

# 任务 2: 从访问日志提取 IP 和请求路径
# 提示: 字段 1 和 7
awk '{print $1, $7}' access.log

# 任务 3: 显示每行的字段数
# 提示: 使用 NF
awk '{print NR, NF, $0}' access.log | head -3
```

### 练习 2: 条件筛选

```bash
# 任务 1: 找出所有 POST 请求
awk '/POST/ {print $1, $6, $7}' access.log

# 任务 2: 找出状态码不是 200 的请求
awk '$9 != 200 {print $1, $9, $7}' access.log

# 任务 3: 找出来自 10.0.0.x 网段的请求
awk '$1 ~ /^10\.0\.0\./ {print $0}' access.log
```

### 练习 3: 字段分隔符

```bash
# 创建测试数据
cat > test.csv << 'EOF'
server1:web:running:192.168.1.1
server2:db:stopped:192.168.1.2
server3:cache:running:192.168.1.3
EOF

# 任务 1: 提取服务器名和状态
awk -F: '{print $1, $3}' test.csv

# 任务 2: 只显示 running 的服务器
awk -F: '$3 == "running" {print $1, $4}' test.csv

# 任务 3: 用制表符输出
awk -F: 'BEGIN {OFS="\t"} {print $1, $2, $3}' test.csv
```

### 练习 4: 综合应用

```bash
# 创建应用日志
cat > app.log << 'EOF'
2026-01-04 09:00:01 INFO  user=alice action=login ip=192.168.1.100
2026-01-04 09:00:15 WARN  user=bob action=failed_login ip=10.0.0.50
2026-01-04 09:01:00 ERROR user=charlie action=timeout ip=192.168.1.101
2026-01-04 09:01:30 INFO  user=alice action=logout ip=192.168.1.100
2026-01-04 09:02:00 ERROR user=bob action=permission_denied ip=10.0.0.50
EOF

# 任务 1: 提取所有 ERROR 行的用户名
# 提示: 字段 4 是 user=xxx
awk '/ERROR/ {print $4}' app.log

# 任务 2: 统计每个日志级别的数量
awk '{count[$3]++} END {for(level in count) print level, count[level]}' app.log

# 任务 3: 提取 10.0.0.x 的所有操作
awk '/ip=10\.0\.0\./ {print $4, $5}' app.log
```

---

## 职场小贴士

### 日本 IT 现场术语

| 日本語 | 中文 | 场景 |
|--------|------|------|
| フィールド抽出 | 字段提取 | awk 最核心的功能 |
| カラム（列） | 列 | 表格数据的列 |
| 定型レポート | 定期报告 | 日/周/月报表 |
| ログ集計 | 日志聚合 | 统计和汇总 |
| データ抽出 | 数据提取 | 从原始数据中提取所需信息 |

### 运维中的 awk 使用场景

1. **访问日志分析**
   ```bash
   # Top 10 访问 IP
   awk '{count[$1]++} END {for(ip in count) print count[ip], ip}' access.log | sort -rn | head -10
   ```

2. **系统资源监控**
   ```bash
   # 提取内存使用率
   free -m | awk 'NR==2 {printf "Memory: %.1f%%\n", $3/$2*100}'

   # 提取磁盘使用率
   df -h | awk '$NF=="/" {print "Disk:", $5}'
   ```

3. **进程分析**
   ```bash
   # 按内存排序的进程
   ps aux | awk 'NR>1 {print $4, $11}' | sort -rn | head -10
   ```

4. **日志时间窗口提取**
   ```bash
   # 提取特定时间段的日志
   awk '$4 ~ /04\/Jan\/2026:09:0/ {print}' access.log
   ```

### 实际案例

**场景**：每天早上生成前一天的访问报告

```bash
#!/bin/bash
# 日次レポート生成スクリプト（日报生成脚本）

LOG_FILE="/var/log/nginx/access.log"
YESTERDAY=$(date -d 'yesterday' '+%d/%b/%Y')
REPORT_FILE="/var/reports/daily_$(date -d 'yesterday' '+%Y%m%d').txt"

{
    echo "===== 日次アクセスレポート ====="
    echo "対象日: $YESTERDAY"
    echo ""

    echo "--- リクエスト総数 ---"
    grep "$YESTERDAY" "$LOG_FILE" | wc -l
    echo ""

    echo "--- Top 10 IP ---"
    grep "$YESTERDAY" "$LOG_FILE" | awk '{count[$1]++} END {for(ip in count) print count[ip], ip}' | sort -rn | head -10
    echo ""

    echo "--- ステータスコード分布 ---"
    grep "$YESTERDAY" "$LOG_FILE" | awk '{count[$9]++} END {for(code in count) print code": "count[code]}' | sort
    echo ""

    echo "--- 5xx エラー ---"
    grep "$YESTERDAY" "$LOG_FILE" | awk '$9 >= 500 {print $1, $9, $7}' | head -20
} > "$REPORT_FILE"

echo "Report generated: $REPORT_FILE"
```

---

## 检查清单

完成本课后，你应该能够：

- [ ] 使用 `awk '{print $1}'` 提取字段
- [ ] 理解 `$0`, `$1`, `$NF`, `NF`, `NR` 的含义
- [ ] 使用 `-F` 指定字段分隔符
- [ ] 使用模式 `awk '/pattern/ {action}'` 进行条件处理
- [ ] 使用字段条件 `$9 >= 500` 进行筛选
- [ ] 访问最后字段 `$NF` 和倒数第二字段 `$(NF-1)`
- [ ] 避免 `grep | awk` 反模式
- [ ] 避免 `'{print $1 $2}'` 忘记分隔符的错误
- [ ] 知道何时使用 miller 处理 CSV
- [ ] 完成访问日志分析报告

**验证命令**：

```bash
cd ~/awk-lab

# 测试 1: 提取 IP
awk '{print $1}' access.log | head -1
# 预期: 192.168.1.100

# 测试 2: 提取状态码
awk '{print $9}' access.log | sort -u | head -3
# 预期: 200, 304, 413 等

# 测试 3: 条件筛选
awk '$9 >= 500' access.log | wc -l
# 预期: 4

# 测试 4: 最后字段
awk '{print $NF}' access.log | head -1
# 预期: 0.023

# 测试 5: IP 统计
awk '{count[$1]++} END {for(ip in count) print count[ip], ip}' access.log | sort -rn | head -1
# 预期: 4 192.168.1.100 (或类似)
```

---

## 快速参考

```bash
# 基础语法
awk '{print $1}'              # 打印第一个字段
awk '{print $1, $2}'          # 打印第一、二字段（空格分隔）
awk '{print $0}'              # 打印整行

# 字段变量
$0      # 整行
$1-$n   # 第 n 个字段
$NF     # 最后一个字段
$(NF-1) # 倒数第二个字段
NF      # 字段数
NR      # 行号

# 分隔符
awk -F: '{print $1}'          # 冒号分隔
awk -F'[,;]' '{print $1}'     # 多字符分隔
awk 'BEGIN {FS=","; OFS="\t"} {print $1, $2}'  # 输入逗号，输出制表符

# 模式
awk '/pattern/' file          # 匹配行（等同于 grep）
awk '/pattern/ {print $1}'    # 匹配行的字段
awk '$3 > 100' file           # 字段条件
awk '$1 ~ /^10\./' file       # 字段正则匹配
awk '$1 !~ /^192\./' file     # 字段正则不匹配

# 条件组合
awk '$3 > 100 && $5 == "OK"'  # AND
awk '$3 > 100 || $5 == "ERR"' # OR
```

---

## 延伸阅读

### 官方文档

- [GNU awk Manual](https://www.gnu.org/software/gawk/manual/)
- [awk Tutorial](https://www.grymoire.com/Unix/Awk.html)

### 现代工具

- [miller (mlr)](https://miller.readthedocs.io/) - CSV/JSON 处理工具
- [csvkit](https://csvkit.readthedocs.io/) - CSV 工具集

### 相关课程

- [05 - sed 文本转换](../05-sed-transformation/) - 文本替换和删除
- [07 - awk 程序和聚合](../07-awk-programs/) - BEGIN/END、变量、聚合统计
- [08 - 排序和去重](../08-sorting-uniqueness/) - sort/uniq 配合 awk 使用

---

## 清理

```bash
# 清理练习文件
cd ~
rm -rf ~/awk-lab
```

---

## 系列导航

| 课程 | 主题 |
|------|------|
| [01 - 管道和重定向](../01-pipes-redirection/) | stdin/stdout/stderr |
| [02 - 查看和流式处理文件](../02-viewing-files/) | cat/less/head/tail |
| [03 - grep 基础](../03-grep-fundamentals/) | 模式搜索 |
| [04 - 正则表达式](../04-regular-expressions/) | BRE/ERE |
| [05 - sed 文本转换](../05-sed-transformation/) | 替换和删除 |
| **06 - awk 字段处理** | 当前课程 |
| [07 - awk 程序和聚合](../07-awk-programs/) | 数据分析 |
| [08 - 排序、去重和字段提取](../08-sorting-uniqueness/) | sort/uniq/cut |
| [09 - 使用 find 和 xargs 查找文件](../09-find-xargs/) | 文件查找 |
| [10 - 综合项目：日志分析管道](../10-capstone-pipeline/) | 实战项目 |
