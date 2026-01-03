# 04 · 条件与循环（Conditionals & Loops）

> **目标**：掌握条件判断、循环和数组，实现批量检查脚本  
> **前置**：[03 · 管道与文本](../03-pipes/)  
> **时间**：25-30 分钟  
> **实战项目**：批量服务器/日志检查（运维团队日报场景）

## 将学到的内容

1. 条件判断（if/elif/else, test）
2. 循环（for, while）
3. 数组基础
4. 调试技巧：`trap ERR` 和文件预检查

---

## Step 1 — 条件判断

### if/then/else/fi

```bash
nano ~/bash-course/if-demo.sh
```

```bash
#!/bin/bash

count=5

if [ $count -gt 10 ]; then
    echo "大于 10"
elif [ $count -gt 5 ]; then
    echo "大于 5，小于等于 10"
else
    echo "小于等于 5"
fi
```

### test 命令和 [ ]

`[ ]` 就是 `test` 命令的简写：

```bash
# 这两个等价
test -f /etc/passwd
[ -f /etc/passwd ]
```

### [[ ]] vs [ ]

推荐使用 `[[ ]]`，更安全更强大：

```bash
# [ ] 需要注意空格和引号
[ "$name" = "value" ]

# [[ ]] 更宽容，支持正则
[[ $name == "value" ]]
[[ $name =~ ^[0-9]+$ ]]    # 正则匹配
```

### 常用测试条件

```bash
# 字符串比较
[[ $str == "value" ]]     # 相等
[[ $str != "value" ]]     # 不等
[[ -z $str ]]             # 为空
[[ -n $str ]]             # 非空

# 数值比较
[[ $num -eq 10 ]]         # 等于
[[ $num -ne 10 ]]         # 不等于
[[ $num -gt 10 ]]         # 大于
[[ $num -lt 10 ]]         # 小于
[[ $num -ge 10 ]]         # 大于等于
[[ $num -le 10 ]]         # 小于等于

# 文件测试
[[ -f $file ]]            # 是普通文件
[[ -d $dir ]]             # 是目录
[[ -e $path ]]            # 存在
[[ -r $file ]]            # 可读
[[ -w $file ]]            # 可写
[[ -x $file ]]            # 可执行

# 逻辑组合
[[ $a -gt 5 && $a -lt 10 ]]    # AND
[[ $a -lt 5 || $a -gt 10 ]]    # OR
[[ ! -f $file ]]               # NOT
```

---

## Step 2 — for 循环

### 基本语法

```bash
# 遍历列表
for item in apple banana orange; do
    echo "水果: $item"
done

# 遍历数字范围
for i in {1..5}; do
    echo "Number: $i"
done

# 遍历文件
for file in /var/log/*.log; do
    echo "日志: $file"
done

# C 风格 for 循环
for ((i=1; i<=5; i++)); do
    echo "Count: $i"
done
```

### 实用示例

```bash
nano ~/bash-course/for-demo.sh
```

```bash
#!/bin/bash
# 批量创建备份目录

for day in mon tue wed thu fri; do
    dir_name="backup_${day}"
    mkdir -p "$dir_name"
    echo "创建: $dir_name"
done

echo "完成！"
ls -la backup_*
```

---

## Step 3 — while 循环

### 基本语法

```bash
count=1
while [[ $count -le 5 ]]; do
    echo "Count: $count"
    ((count++))
done
```

### 读取文件行

```bash
# 逐行读取文件
while read line; do
    echo "行: $line"
done < /etc/passwd

# 更安全的写法（处理没有换行的最后一行）
while IFS= read -r line || [[ -n "$line" ]]; do
    echo "$line"
done < file.txt
```

### 处理命令输出

```bash
# 处理 ls 输出
ls /var/log/*.log 2>/dev/null | while read logfile; do
    size=$(du -h "$logfile" | cut -f1)
    echo "$logfile: $size"
done
```

---

## Step 4 — 数组

### 定义数组

```bash
# 方式 1：直接定义
servers=("web01" "web02" "db01" "db02")

# 方式 2：逐个添加
logs=()
logs+=("/var/log/messages")
logs+=("/var/log/secure")

# 方式 3：从命令结果创建
files=($(ls /var/log/*.log 2>/dev/null))
```

### 访问数组

```bash
servers=("web01" "web02" "db01" "db02")

# 访问单个元素（0 开始）
echo ${servers[0]}          # web01
echo ${servers[1]}          # web02

# 获取所有元素
echo ${servers[@]}          # web01 web02 db01 db02

# 获取数组长度
echo ${#servers[@]}         # 4

# 获取索引列表
echo ${!servers[@]}         # 0 1 2 3
```

### 遍历数组

```bash
servers=("web01" "web02" "db01" "db02")

# 遍历元素
for server in "${servers[@]}"; do
    echo "服务器: $server"
done

# 带索引遍历
for i in "${!servers[@]}"; do
    echo "[$i] ${servers[$i]}"
done
```

---

## Step 5 — 调试技巧

> 🔧 **调试卡片**：`trap ERR` 和文件预检查让脚本更健壮。

### trap ERR - 错误捕获

```bash
nano ~/bash-course/trap-demo.sh
```

```bash
#!/bin/bash
set -euo pipefail

# 定义错误处理函数
handle_error() {
    echo "错误发生在第 $1 行"
    echo "命令: $2"
    exit 1
}

# 设置 trap
trap 'handle_error $LINENO "$BASH_COMMAND"' ERR

echo "开始执行..."
ls /nonexistent_directory    # 这里会触发错误
echo "这行不会执行"
```

运行：

```bash
bash trap-demo.sh
```

输出：
```
开始执行...
ls: cannot access '/nonexistent_directory': No such file or directory
错误发生在第 14 行
命令: ls /nonexistent_directory
```

### 文件预检查

```bash
# 检查文件存在再操作
if [[ -f "$config_file" ]]; then
    source "$config_file"
else
    echo "错误: 配置文件不存在: $config_file"
    exit 1
fi

# 检查目录存在
if [[ ! -d "$output_dir" ]]; then
    mkdir -p "$output_dir"
fi

# 检查命令存在
if ! command -v nginx &>/dev/null; then
    echo "错误: nginx 未安装"
    exit 1
fi
```

---

## Mini-Project：批量日志检查

> **场景**：运维团队需要每天检查多台服务器的日志，统计错误数量生成日报。这在日本 IT 公司的「運用チーム」中很常见。

先创建模拟日志：

```bash
# 创建多个模拟日志文件
mkdir -p ~/bash-course/logs

# 服务器 1 日志
cat > ~/bash-course/logs/server1.log << 'EOF'
2025-01-15 10:00:01 INFO Service started
2025-01-15 10:00:05 ERROR Connection timeout
2025-01-15 10:00:10 INFO Request processed
2025-01-15 10:00:15 ERROR Database error
2025-01-15 10:00:20 INFO Healthy
EOF

# 服务器 2 日志
cat > ~/bash-course/logs/server2.log << 'EOF'
2025-01-15 10:00:01 INFO Service started
2025-01-15 10:00:05 INFO Request processed
2025-01-15 10:00:10 WARN High memory usage
2025-01-15 10:00:15 INFO Healthy
EOF

# 服务器 3 日志
cat > ~/bash-course/logs/server3.log << 'EOF'
2025-01-15 10:00:01 INFO Service started
2025-01-15 10:00:05 ERROR Disk full
2025-01-15 10:00:10 ERROR Service crashed
2025-01-15 10:00:15 ERROR Restart failed
2025-01-15 10:00:20 INFO Service recovered
EOF

echo "模拟日志已创建"
```

创建检查脚本：

```bash
nano ~/bash-course/batch-checker.sh
```

```bash
#!/bin/bash
# 批量日志检查 - Batch Log Checker
# 用途：运维日报、异常监控

set -euo pipefail

# 错误处理
trap 'echo "错误发生在第 $LINENO 行"; exit 1' ERR

# 配置
log_dir="${1:-$HOME/bash-course/logs}"
output_dir=~/reports
timestamp=$(date +%Y%m%d_%H%M%S)
report_file="${output_dir}/daily_check_${timestamp}.txt"

# 定义要检查的日志文件（数组）
log_files=(
    "${log_dir}/server1.log"
    "${log_dir}/server2.log"
    "${log_dir}/server3.log"
)

# 创建输出目录
mkdir -p "$output_dir"

# 开始检查
{
    echo "========================================"
    echo "       运维日报 - 日志检查汇总"
    echo "========================================"
    echo "检查时间: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "日志目录: $log_dir"
    echo ""
    echo "======== 检查结果 ========"
    echo ""
    printf "%-20s %8s %8s %8s\n" "服务器" "ERROR" "WARN" "总行数"
    printf "%-20s %8s %8s %8s\n" "--------------------" "--------" "--------" "--------"

    total_errors=0
    total_warns=0

    # 遍历日志文件数组
    for log_file in "${log_files[@]}"; do
        # 提取服务器名（文件名去掉路径和扩展名）
        server_name=$(basename "$log_file" .log)

        # 检查文件是否存在
        if [[ ! -f "$log_file" ]]; then
            printf "%-20s %8s %8s %8s\n" "$server_name" "N/A" "N/A" "文件不存在"
            continue
        fi

        # 统计各级别日志
        error_count=$(grep -c "ERROR" "$log_file" 2>/dev/null || echo 0)
        warn_count=$(grep -c "WARN" "$log_file" 2>/dev/null || echo 0)
        total_lines=$(wc -l < "$log_file")

        # 累加总数
        ((total_errors += error_count)) || true
        ((total_warns += warn_count)) || true

        # 输出结果
        printf "%-20s %8d %8d %8d\n" "$server_name" "$error_count" "$warn_count" "$total_lines"
    done

    echo ""
    printf "%-20s %8s %8s %8s\n" "--------------------" "--------" "--------" "--------"
    printf "%-20s %8d %8d\n" "合计" "$total_errors" "$total_warns"
    echo ""

    # 判断整体状态
    echo "======== 状态判定 ========"
    if [[ $total_errors -gt 5 ]]; then
        echo "状态: 严重 - ERROR 超过 5 条，需要立即处理！"
    elif [[ $total_errors -gt 0 ]]; then
        echo "状态: 警告 - 存在 ERROR，请关注"
    else
        echo "状态: 正常 - 无 ERROR"
    fi
    echo ""

    # 列出所有 ERROR 详情
    if [[ $total_errors -gt 0 ]]; then
        echo "======== ERROR 详情 ========"
        for log_file in "${log_files[@]}"; do
            if [[ -f "$log_file" ]]; then
                server_name=$(basename "$log_file" .log)
                errors=$(grep "ERROR" "$log_file" 2>/dev/null || true)
                if [[ -n "$errors" ]]; then
                    echo ""
                    echo "[$server_name]"
                    echo "$errors"
                fi
            fi
        done
        echo ""
    fi

    echo "========================================"
} | tee "$report_file"

echo ""
echo "报告已保存: $report_file"

exit 0
```

运行：

```bash
chmod +x ~/bash-course/batch-checker.sh
~/bash-course/batch-checker.sh
```

输出示例：

```
========================================
       运维日报 - 日志检查汇总
========================================
检查时间: 2025-01-15 15:00:00
日志目录: /home/ssm-user/bash-course/logs

======== 检查结果 ========

服务器                  ERROR     WARN   总行数
--------------------   --------  --------  --------
server1                       2        0        5
server2                       0        1        4
server3                       3        0        5

--------------------   --------  --------  --------
合计                          5        1

======== 状态判定 ========
状态: 警告 - 存在 ERROR，请关注

======== ERROR 详情 ========

[server1]
2025-01-15 10:00:05 ERROR Connection timeout
2025-01-15 10:00:15 ERROR Database error

[server3]
2025-01-15 10:00:05 ERROR Disk full
2025-01-15 10:00:10 ERROR Service crashed
2025-01-15 10:00:15 ERROR Restart failed

========================================

报告已保存: /home/ssm-user/reports/daily_check_20250115_150000.txt
```

---

## 练习挑战

1. 修改脚本，添加 INFO 级别的统计

2. 添加参数支持：指定要检查的服务器列表

3. 添加邮件通知功能（当 ERROR > 5 时）

---

## 本课小结

| 概念 | 语法 |
|------|------|
| 条件判断 | `if [[ ]]; then ... elif ... else ... fi` |
| 数值比较 | `-eq`, `-ne`, `-gt`, `-lt`, `-ge`, `-le` |
| 文件测试 | `-f`, `-d`, `-e`, `-r`, `-w`, `-x` |
| for 循环 | `for item in list; do ... done` |
| while 循环 | `while [[ ]]; do ... done` |
| 读取文件 | `while read line; do ... done < file` |
| 数组定义 | `arr=("a" "b" "c")` |
| 数组遍历 | `for item in "${arr[@]}"` |
| 错误捕获 | `trap 'handler' ERR` |

---

## 下一步

掌握了条件和循环，下一课我们学习函数封装！

→ [05 · 函数与参数](../05-functions/)

## 系列导航

← [03 · 管道与文本](../03-pipes/) | [系列首页](../) | [05 · 函数与参数](../05-functions/) →
