# 05 · 函数与参数（Functions & Parameters）

> **目标**：掌握函数封装和参数处理，创建可复用的健康检查工具
> **前置**：[04 · 条件与循环](../04-loops/)
> **时间**：25-30 分钟
> **实战项目**：健康检查脚本（自动化平台对接场景）

## 将学到的内容

1. 函数定义和调用
2. 位置参数（$1, $2, $@）
3. getopts 解析命令行选项
4. 调试技巧：返回码和输入验证

---

## Step 1 — 函数基础

### 定义函数

```bash
# 方式 1（推荐）
function greet() {
    echo "Hello, World!"
}

# 方式 2
greet() {
    echo "Hello, World!"
}
```

### 调用函数

```bash
nano ~/bash-course/func-demo.sh
```

```bash
#!/bin/bash

# 定义函数
function say_hello() {
    echo "你好！"
}

function say_goodbye() {
    echo "再见！"
}

# 调用函数
say_hello
say_goodbye
```

运行：

```bash
bash ~/bash-course/func-demo.sh
# 输出:
# 你好！
# 再见！
```

---

## Step 2 — 函数参数

### 位置参数

```bash
function greet() {
    echo "Hello, $1!"        # 第一个参数
    echo "From: $2"          # 第二个参数
    echo "All args: $@"      # 所有参数
    echo "Arg count: $#"     # 参数个数
}

greet "Alice" "Bob"
# 输出:
# Hello, Alice!
# From: Bob
# All args: Alice Bob
# Arg count: 2
```

### 实用示例

```bash
nano ~/bash-course/func-params.sh
```

```bash
#!/bin/bash

# 计算文件行数
function count_lines() {
    local file="$1"

    if [[ ! -f "$file" ]]; then
        echo "文件不存在: $file"
        return 1
    fi

    local lines=$(wc -l < "$file")
    echo "文件 $file 共 $lines 行"
    return 0
}

# 使用 local 定义局部变量
function add_numbers() {
    local a=$1
    local b=$2
    local sum=$((a + b))
    echo $sum
}

# 测试
count_lines /etc/passwd
result=$(add_numbers 5 3)
echo "5 + 3 = $result"
```

---

## Step 3 — 返回值

### return vs echo

```bash
# return：返回退出码（0-255），用于表示成功/失败
function check_file() {
    if [[ -f "$1" ]]; then
        return 0    # 成功
    else
        return 1    # 失败
    fi
}

# echo：返回数据，用于传递结果
function get_hostname() {
    echo $(hostname)
}

# 使用示例
if check_file /etc/passwd; then
    echo "文件存在"
fi

name=$(get_hostname)
echo "主机名: $name"
```

### 返回码最佳实践

```bash
nano ~/bash-course/func-return.sh
```

```bash
#!/bin/bash

# 返回码常量
readonly SUCCESS=0
readonly ERR_FILE_NOT_FOUND=1
readonly ERR_PERMISSION_DENIED=2
readonly ERR_INVALID_PARAM=3

function process_file() {
    local file="$1"

    # 参数验证
    if [[ -z "$file" ]]; then
        echo "错误: 未提供文件路径" >&2
        return $ERR_INVALID_PARAM
    fi

    # 文件存在检查
    if [[ ! -f "$file" ]]; then
        echo "错误: 文件不存在: $file" >&2
        return $ERR_FILE_NOT_FOUND
    fi

    # 权限检查
    if [[ ! -r "$file" ]]; then
        echo "错误: 无读取权限: $file" >&2
        return $ERR_PERMISSION_DENIED
    fi

    # 处理文件
    echo "处理文件: $file"
    cat "$file"
    return $SUCCESS
}

# 测试
process_file "/etc/passwd"
echo "返回码: $?"

process_file "/nonexistent"
echo "返回码: $?"

process_file ""
echo "返回码: $?"
```

---

## Step 4 — getopts 解析选项

### 基本用法

```bash
nano ~/bash-course/getopts-demo.sh
```

```bash
#!/bin/bash

# 显示帮助
function show_help() {
    cat << EOF
用法: $(basename $0) [选项]

选项:
  -h        显示帮助
  -v        详细模式
  -o FILE   输出到文件
  -n NUM    指定数量
EOF
}

# 默认值
verbose=false
output_file=""
count=10

# 解析选项
while getopts "hvo:n:" opt; do
    case $opt in
        h)
            show_help
            exit 0
            ;;
        v)
            verbose=true
            ;;
        o)
            output_file="$OPTARG"
            ;;
        n)
            count="$OPTARG"
            ;;
        \?)
            echo "无效选项: -$OPTARG" >&2
            exit 1
            ;;
        :)
            echo "选项 -$OPTARG 需要参数" >&2
            exit 1
            ;;
    esac
done

# 移除已处理的选项，剩余的是位置参数
shift $((OPTIND - 1))

# 显示解析结果
echo "verbose: $verbose"
echo "output_file: $output_file"
echo "count: $count"
echo "剩余参数: $@"
```

运行测试：

```bash
bash getopts-demo.sh -v -o result.txt -n 20 file1 file2
# 输出:
# verbose: true
# output_file: result.txt
# count: 20
# 剩余参数: file1 file2
```

### getopts 选项字符串

```bash
# "hvo:n:"
#  h   - 布尔选项（-h）
#  v   - 布尔选项（-v）
#  o:  - 需要参数（-o value）
#  n:  - 需要参数（-n value）
```

---

## Step 5 — 调试技巧

> 🔧 **调试卡片**：输入验证和有意义的返回码让脚本更可靠。

### 输入验证模式

```bash
function validate_input() {
    local param_name="$1"
    local param_value="$2"
    local param_type="$3"    # file, dir, number, string

    # 检查是否为空
    if [[ -z "$param_value" ]]; then
        echo "错误: $param_name 不能为空" >&2
        return 1
    fi

    case "$param_type" in
        file)
            if [[ ! -f "$param_value" ]]; then
                echo "错误: $param_name 文件不存在: $param_value" >&2
                return 1
            fi
            ;;
        dir)
            if [[ ! -d "$param_value" ]]; then
                echo "错误: $param_name 目录不存在: $param_value" >&2
                return 1
            fi
            ;;
        number)
            if ! [[ "$param_value" =~ ^[0-9]+$ ]]; then
                echo "错误: $param_name 必须是数字: $param_value" >&2
                return 1
            fi
            ;;
    esac

    return 0
}

# 使用示例
validate_input "config" "/etc/passwd" "file" || exit 1
validate_input "count" "abc" "number" || exit 1
```

### 调试日志函数

```bash
# 日志级别
LOG_LEVEL=${LOG_LEVEL:-INFO}

function log() {
    local level="$1"
    shift
    local message="$@"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    case "$level" in
        DEBUG)
            [[ "$LOG_LEVEL" == "DEBUG" ]] && echo "[$timestamp] DEBUG: $message" >&2
            ;;
        INFO)
            echo "[$timestamp] INFO: $message"
            ;;
        WARN)
            echo "[$timestamp] WARN: $message" >&2
            ;;
        ERROR)
            echo "[$timestamp] ERROR: $message" >&2
            ;;
    esac
}

# 使用
log INFO "开始处理..."
log DEBUG "调试信息"
log ERROR "发生错误"
```

---

## Mini-Project：健康检查脚本

> **场景**：运维需要一个通用的健康检查工具，可以被自动化平台（如 Zabbix、Prometheus）调用。支持多种输出格式，方便对接监控系统。

```bash
nano ~/bash-course/health-check.sh
```

```bash
#!/bin/bash
# 健康检查脚本 - Health Check Tool
# 用途：系统监控、自动化平台对接

set -euo pipefail

# ====================
# 配置和常量
# ====================
readonly VERSION="1.0.0"
readonly SUCCESS=0
readonly WARNING=1
readonly CRITICAL=2

# 阈值配置
CPU_WARN=70
CPU_CRIT=90
MEM_WARN=70
MEM_CRIT=90
DISK_WARN=70
DISK_CRIT=90

# 输出格式
output_format="text"

# ====================
# 帮助信息
# ====================
function show_help() {
    cat << EOF
健康检查脚本 v${VERSION}

用法: $(basename $0) [选项] [检查项...]

选项:
  -h, --help     显示帮助
  -o FORMAT      输出格式: text, json (默认: text)
  -v             详细模式

检查项:
  cpu            CPU 使用率
  memory         内存使用率
  disk           磁盘使用率
  all            所有检查 (默认)

示例:
  $(basename $0)              # 检查全部
  $(basename $0) cpu memory   # 只检查 CPU 和内存
  $(basename $0) -o json all  # JSON 格式输出
EOF
}

# ====================
# 检查函数
# ====================
function check_cpu() {
    # 获取 CPU 使用率（1 分钟平均负载 / CPU 核心数 * 100）
    local cores=$(nproc)
    local load=$(cat /proc/loadavg | cut -d' ' -f1)
    local usage=$(echo "$load $cores" | awk '{printf "%.0f", ($1/$2)*100}')

    local status=$SUCCESS
    local status_text="OK"

    if [[ $usage -ge $CPU_CRIT ]]; then
        status=$CRITICAL
        status_text="CRITICAL"
    elif [[ $usage -ge $CPU_WARN ]]; then
        status=$WARNING
        status_text="WARNING"
    fi

    echo "$status|cpu|$usage|$status_text|CPU usage: ${usage}%"
}

function check_memory() {
    # 获取内存使用率
    local total=$(free | grep Mem | awk '{print $2}')
    local used=$(free | grep Mem | awk '{print $3}')
    local usage=$(echo "$used $total" | awk '{printf "%.0f", ($1/$2)*100}')

    local status=$SUCCESS
    local status_text="OK"

    if [[ $usage -ge $MEM_CRIT ]]; then
        status=$CRITICAL
        status_text="CRITICAL"
    elif [[ $usage -ge $MEM_WARN ]]; then
        status=$WARNING
        status_text="WARNING"
    fi

    echo "$status|memory|$usage|$status_text|Memory usage: ${usage}%"
}

function check_disk() {
    # 获取根分区磁盘使用率
    local usage=$(df / | tail -1 | awk '{print $5}' | tr -d '%')

    local status=$SUCCESS
    local status_text="OK"

    if [[ $usage -ge $DISK_CRIT ]]; then
        status=$CRITICAL
        status_text="CRITICAL"
    elif [[ $usage -ge $DISK_WARN ]]; then
        status=$WARNING
        status_text="WARNING"
    fi

    echo "$status|disk|$usage|$status_text|Disk usage: ${usage}%"
}

# ====================
# 输出格式化
# ====================
function output_text() {
    local results=("$@")
    local overall_status=$SUCCESS

    echo "========================================"
    echo "       健康检查报告"
    echo "========================================"
    echo "时间: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "主机: $(hostname)"
    echo ""

    printf "%-10s %-10s %-8s %s\n" "检查项" "状态" "值" "说明"
    printf "%-10s %-10s %-8s %s\n" "----------" "----------" "--------" "--------------------"

    for result in "${results[@]}"; do
        IFS='|' read -r status name value status_text message <<< "$result"
        printf "%-10s %-10s %-8s %s\n" "$name" "$status_text" "${value}%" "$message"

        if [[ $status -gt $overall_status ]]; then
            overall_status=$status
        fi
    done

    echo ""
    echo "========================================"

    case $overall_status in
        $SUCCESS)  echo "整体状态: OK" ;;
        $WARNING)  echo "整体状态: WARNING - 需要关注" ;;
        $CRITICAL) echo "整体状态: CRITICAL - 需要处理！" ;;
    esac

    return $overall_status
}

function output_json() {
    local results=("$@")
    local overall_status=$SUCCESS

    echo "{"
    echo "  \"timestamp\": \"$(date -Iseconds)\","
    echo "  \"hostname\": \"$(hostname)\","
    echo "  \"checks\": ["

    local first=true
    for result in "${results[@]}"; do
        IFS='|' read -r status name value status_text message <<< "$result"

        if [[ $first == true ]]; then
            first=false
        else
            echo ","
        fi

        echo -n "    {\"name\": \"$name\", \"status\": \"$status_text\", \"value\": $value, \"message\": \"$message\"}"

        if [[ $status -gt $overall_status ]]; then
            overall_status=$status
        fi
    done

    echo ""
    echo "  ],"

    local overall_text="OK"
    case $overall_status in
        $WARNING)  overall_text="WARNING" ;;
        $CRITICAL) overall_text="CRITICAL" ;;
    esac

    echo "  \"overall_status\": \"$overall_text\""
    echo "}"

    return $overall_status
}

# ====================
# 主程序
# ====================

# 解析选项
while getopts "ho:v" opt; do
    case $opt in
        h)
            show_help
            exit 0
            ;;
        o)
            output_format="$OPTARG"
            ;;
        v)
            set -x
            ;;
        \?)
            echo "无效选项: -$OPTARG" >&2
            exit 1
            ;;
    esac
done

shift $((OPTIND - 1))

# 确定要执行的检查
checks=("$@")
if [[ ${#checks[@]} -eq 0 ]] || [[ "${checks[0]}" == "all" ]]; then
    checks=("cpu" "memory" "disk")
fi

# 执行检查
results=()
for check in "${checks[@]}"; do
    case $check in
        cpu)
            results+=("$(check_cpu)")
            ;;
        memory)
            results+=("$(check_memory)")
            ;;
        disk)
            results+=("$(check_disk)")
            ;;
        all)
            # 已在上面处理
            ;;
        *)
            echo "未知检查项: $check" >&2
            exit 1
            ;;
    esac
done

# 输出结果
case $output_format in
    text)
        output_text "${results[@]}"
        ;;
    json)
        output_json "${results[@]}"
        ;;
    *)
        echo "未知输出格式: $output_format" >&2
        exit 1
        ;;
esac

exit $?
```

运行测试：

```bash
chmod +x ~/bash-course/health-check.sh

# 默认文本输出
~/bash-course/health-check.sh

# JSON 输出（可对接监控系统）
~/bash-course/health-check.sh -o json

# 只检查特定项
~/bash-course/health-check.sh cpu memory
```

文本输出示例：

```
========================================
       健康检查报告
========================================
时间: 2025-01-15 16:00:00
主机: ip-10-0-1-123

检查项     状态       值       说明
---------- ---------- -------- --------------------
cpu        OK         15%      CPU usage: 15%
memory     OK         32%      Memory usage: 32%
disk       OK         27%      Disk usage: 27%

========================================
整体状态: OK
```

JSON 输出示例：

```json
{
  "timestamp": "2025-01-15T16:00:00+09:00",
  "hostname": "ip-10-0-1-123",
  "checks": [
    {"name": "cpu", "status": "OK", "value": 15, "message": "CPU usage: 15%"},
    {"name": "memory", "status": "OK", "value": 32, "message": "Memory usage: 32%"},
    {"name": "disk", "status": "OK", "value": 27, "message": "Disk usage: 27%"}
  ],
  "overall_status": "OK"
}
```

---

## 练习挑战

1. 添加服务检查功能：检查 nginx/httpd 是否运行

2. 添加 `-t` 选项：自定义阈值 `-t cpu:80:95`

3. 添加 `-f` 选项：从配置文件读取阈值

---

## 本课小结

| 概念 | 语法 |
|------|------|
| 函数定义 | `function name() { ... }` |
| 位置参数 | `$1`, `$2`, `$@`, `$#` |
| 局部变量 | `local var=value` |
| 返回码 | `return 0` (成功), `return 1` (失败) |
| 返回数据 | `echo "result"` + `var=$(func)` |
| getopts | `while getopts "hvo:n:" opt` |
| OPTARG | 获取选项参数值 |

---

## 下一步

掌握了函数封装，最后一课我们学习文本进阶和自动化！

→ [06 · 文本进阶与自动化](../06-automation/)

## 系列导航

← [04 · 条件与循环](../04-loops/) | [系列首页](../) | [06 · 文本进阶与自动化](../06-automation/) →
