# 02 · 变量与文件系统（Variables & Filesystem）

> **目标**：掌握变量高级用法和文件系统操作，生成磁盘空间快照  
> **前置**：[01 · 第一个脚本](../01-first-script/)  
> **时间**：20-30 分钟  
> **实战项目**：磁盘空间快照（运维巡检场景）  

## 将学到的内容

1. 变量高级用法（引号、命令替换）
2. 路径操作（绝对/相对路径）
3. 文件系统命令（ls, du, find）
4. 输入/输出重定向
5. 调试技巧：`set -x` 和 `$?`

---

## Step 1 — 变量进阶

### 引号的区别（复习+进阶）

```bash
nano ~/bash-course/quotes-demo.sh
```

```bash
#!/bin/bash

name="World"
path="/home/ssm-user"

# 双引号：展开变量，保留空格
echo "Hello, $name"           # Hello, World
echo "Path: $path"            # Path: /home/ssm-user

# 单引号：原样输出
echo 'Hello, $name'           # Hello, $name

# 命令替换
echo "Today: $(date +%F)"     # Today: 2025-01-15
echo "Files: $(ls | wc -l)"   # Files: 5

# 变量中包含空格 - 必须用双引号！
filename="my report.txt"
touch "$filename"             # ✅ 创建一个文件
# touch $filename             # ❌ 会创建两个文件: my 和 report.txt
```

### 常见错误

```bash
# ❌ 等号两边有空格
name = "value"    # 报错！

# ❌ 变量名以数字开头
1name="value"     # 报错！

# ✅ 正确写法
name="value"
name1="value"
_name="value"
```

---

## Step 2 — 路径操作

### 绝对路径 vs 相对路径

```bash
# 绝对路径：从 / 开始，完整路径
cd /var/log
cat /etc/os-release

# 相对路径：从当前目录开始
cd bash-course        # 进入当前目录下的 bash-course
cd ..                 # 返回上级目录
cd ../..              # 返回上两级

# 特殊符号
~     # 家目录 (/home/ssm-user)
.     # 当前目录
..    # 上级目录
```

### 路径相关命令

```bash
# 显示当前目录
pwd

# 切换目录
cd /var/log
cd ~
cd -                  # 返回上一个目录

# 创建目录
mkdir mydir
mkdir -p a/b/c        # 递归创建

# 列出内容
ls                    # 基本列表
ls -la                # 详细 + 隐藏文件
ls -lh                # 人类可读大小
ls -lt                # 按时间排序
```

---

## Step 3 — 文件大小与磁盘空间

运维必备命令：

### df - 磁盘使用情况

```bash
# 查看所有分区
df -h

# 只看根分区
df -h /

# 输出示例:
# Filesystem      Size  Used Avail Use% Mounted on
# /dev/xvda1      8.0G  2.1G  5.9G  27% /
```

### du - 目录大小

```bash
# 当前目录总大小
du -sh .

# 查看子目录大小
du -sh /var/log/*

# Top 5 最大目录
du -sh /var/log/* 2>/dev/null | sort -rh | head -5
```

### find - 查找文件

```bash
# 按名称查找
find /var/log -name "*.log"

# 按大小查找（大于 10MB）
find /var -size +10M 2>/dev/null

# 按时间查找（7天内修改）
find /home -mtime -7
```

---

## Step 4 — 输入/输出重定向

### 基本重定向

```bash
# > 覆盖写入
echo "Hello" > output.txt
date > timestamp.txt

# >> 追加写入
echo "Line 1" >> log.txt
echo "Line 2" >> log.txt

# < 从文件读取
wc -l < /etc/passwd
```

### 错误输出

```bash
# 标准输出 (stdout) = 1
# 标准错误 (stderr) = 2

# 只重定向错误
ls /nonexistent 2> errors.txt

# 丢弃错误（发送到黑洞）
ls /nonexistent 2>/dev/null

# 同时重定向输出和错误
ls /var /nonexistent &> all.txt

# 分别重定向
ls /var /nonexistent > stdout.txt 2> stderr.txt
```

### 实用技巧

```bash
# 同时显示和保存
df -h | tee disk_report.txt

# 追加模式
date | tee -a daily_log.txt
```

---

## Step 5 — 调试技巧

> 🔧 **调试卡片**：从本课开始，每课都会介绍调试技巧，帮助你排查脚本问题。  

### set -x：跟踪执行

```bash
nano ~/bash-course/debug-demo.sh
```

```bash
#!/bin/bash

# 开启调试模式
set -x

name="Atlas"
echo "Hello, $name"
date_now=$(date +%F)
echo "Today: $date_now"

# 关闭调试模式
set +x

echo "调试已关闭"
```

运行查看：

```bash
bash debug-demo.sh
```

输出：
```
+ name=Atlas
+ echo 'Hello, Atlas'
Hello, Atlas
++ date +%F
+ date_now=2025-01-15
+ echo 'Today: 2025-01-15'
Today: 2025-01-15
+ set +x
调试已关闭
```

### $?：检查退出码

```bash
# 成功的命令
ls /tmp
echo "Exit code: $?"    # 0

# 失败的命令
ls /nonexistent 2>/dev/null
echo "Exit code: $?"    # 2

# 在脚本中使用
if [ $? -eq 0 ]; then
    echo "命令成功"
else
    echo "命令失败"
fi
```

---

## Mini-Project：磁盘空间快照

> **场景**：运维巡检时，需要记录磁盘使用情况，输出 Top 目录到 CSV 文件便于分析和存档。  

```bash
nano ~/bash-course/disk-snapshot.sh
```

```bash
#!/bin/bash
# 磁盘空间快照 - Disk Space Snapshot
# 用途：运维巡检、容量规划

set -x  # 调试模式，可以看到每步执行

# 配置
target_dir="/var"
top_n=5
output_dir=~/reports
timestamp=$(date +%Y%m%d_%H%M%S)
csv_file="${output_dir}/disk_snapshot_${timestamp}.csv"

# 创建输出目录
mkdir -p "$output_dir"

# 生成 CSV 头
echo "rank,size,directory" > "$csv_file"

# 获取 Top N 目录并写入 CSV
du -sh ${target_dir}/* 2>/dev/null | sort -rh | head -${top_n} | \
while read size dir; do
    rank=$((${rank:-0} + 1))
    echo "${rank},${size},${dir}" >> "$csv_file"
done

set +x  # 关闭调试

# 显示结果
echo ""
echo "===== 磁盘空间快照 ====="
echo "目标目录: $target_dir"
echo "检查时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo ""
echo "Top ${top_n} 目录:"
cat "$csv_file"
echo ""
echo "CSV 已保存: $csv_file"

# 额外：显示总体磁盘使用
echo ""
echo "===== 磁盘总览 ====="
df -h /

exit 0
```

运行：

```bash
chmod +x ~/bash-course/disk-snapshot.sh
~/bash-course/disk-snapshot.sh
```

输出示例：
```
===== 磁盘空间快照 =====
目标目录: /var
检查时间: 2025-01-15 14:30:00

Top 5 目录:
rank,size,directory
1,120M,/var/cache
2,45M,/var/lib
3,12M,/var/log
4,8.0M,/var/tmp
5,4.0K,/var/empty

CSV 已保存: /home/ssm-user/reports/disk_snapshot_20250115_143000.csv

===== 磁盘总览 =====
Filesystem      Size  Used Avail Use% Mounted on
/dev/xvda1      8.0G  2.1G  5.9G  27% /
```

---

## 练习挑战

1. 修改脚本，增加对 `/home` 目录的扫描

2. 添加参数支持：`./disk-snapshot.sh /var 10` 指定目录和 Top N

---

## 本课小结

| 概念 | 语法/命令 |
|------|-----------|
| 双引号 | `"$var"` 展开变量 |
| 单引号 | `'$var'` 原样输出 |
| 绝对路径 | `/var/log` |
| 相对路径 | `../parent` |
| 覆盖输出 | `>` |
| 追加输出 | `>>` |
| 错误重定向 | `2>` 或 `2>/dev/null` |
| 调试跟踪 | `set -x` / `set +x` |
| 退出码 | `$?` |

---

## 下一步

掌握了变量和文件系统，下一课我们学习管道和文本处理！

→ [03 · 管道与文本](../03-pipes/)

## 系列导航

← [01 · 第一个脚本](../01-first-script/) | [系列首页](../) | [03 · 管道与文本](../03-pipes/) →
