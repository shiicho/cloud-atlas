# 05 - 循环结构（Loops）

> **目标**：掌握 Shell 脚本中的循环结构，正确遍历文件和读取数据  
> **前置**：已完成 [04 - 条件判断](../04-conditionals/)  
> **时间**：⚡ 20 分钟（速读）/ 🔬 75 分钟（完整实操）  
> **环境**：Bash 4.x+（RHEL 7/8/9, Ubuntu 18.04+ 均可）  

---

## 将学到的内容

1. 掌握 for 循环（列表迭代、C 风格）
2. 掌握 while/until 循环
3. 正确读取文件（while read）
4. 使用 break、continue 控制循环
5. 避免常见循环陷阱（重点！）

---

## 先跑起来！（5 分钟）

> 在理解原理之前，先让循环跑起来。  
> 体验脚本如何批量处理文件。  

```bash
# 创建练习目录
mkdir -p ~/shell-lab/loops && cd ~/shell-lab/loops

# 创建一个简单的批量文件处理器
cat > batch_processor.sh << 'EOF'
#!/bin/bash
# 批量文件处理器 - 演示循环的威力

# 创建测试文件
mkdir -p testfiles
for i in {1..5}; do
    echo "This is file $i content" > "testfiles/file_$i.txt"
done

echo "=== 创建的文件 ==="
ls -la testfiles/

echo ""
echo "=== 遍历处理每个文件 ==="
for file in testfiles/*.txt; do
    filename=$(basename "$file")
    lines=$(wc -l < "$file")
    size=$(stat -c %s "$file" 2>/dev/null || stat -f %z "$file")
    echo "文件: $filename | 行数: $lines | 大小: ${size} 字节"
done

echo ""
echo "=== 使用 while 循环计数 ==="
count=0
while [[ $count -lt 5 ]]; do
    echo "计数: $count"
    ((count++))
done

echo ""
echo "=== 读取文件内容 ==="
while IFS= read -r line; do
    echo "  -> $line"
done < testfiles/file_1.txt
EOF

chmod +x batch_processor.sh
./batch_processor.sh
```

**你应该看到类似的输出：**

```
=== 创建的文件 ===
total 20
drwxr-xr-x 2 user user 4096 Jan 10 14:30 .
drwxr-xr-x 3 user user 4096 Jan 10 14:30 ..
-rw-r--r-- 1 user user   23 Jan 10 14:30 file_1.txt
...

=== 遍历处理每个文件 ===
文件: file_1.txt | 行数: 1 | 大小: 23 字节
文件: file_2.txt | 行数: 1 | 大小: 23 字节
...

=== 使用 while 循环计数 ===
计数: 0
计数: 1
...

=== 读取文件内容 ===
  -> This is file 1 content
```

**恭喜！你的脚本已经能批量处理文件了！**

现在让我们深入理解循环的各种形式。

---

## Step 1 - for 循环：列表迭代（15 分钟）

### 1.1 for 循环基本语法

```
for 变量 in 列表; do
    命令...
done
```

<!-- DIAGRAM: for-loop-structure -->
```
┌─────────────────────────────────────────────────────────────────────┐
│  for 循环结构                                                        │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│    for item in list; do         ← 遍历列表中的每个元素              │
│        echo "$item"             ← 对每个元素执行命令                │
│    done                         ← 循环结束                          │
│                                                                      │
│    列表可以是：                                                      │
│    ─────────────────────────────────────────────────────────────    │
│    1. 直接列举:  for i in a b c                                     │
│    2. 花括号展开: for i in {1..10}                                  │
│    3. 通配符:    for f in *.txt                                     │
│    4. 命令输出:  for f in $(find . -name "*.sh")  [有陷阱!]        │
│    5. 数组:      for item in "${array[@]}"                          │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```
<!-- /DIAGRAM -->

### 1.2 列表迭代的各种形式

```bash
cd ~/shell-lab/loops

cat > for_basics.sh << 'EOF'
#!/bin/bash
# for 循环基础演示

echo "=== 1. 直接列举 ==="
for fruit in apple banana orange; do
    echo "水果: $fruit"
done

echo ""
echo "=== 2. 花括号展开 {start..end} ==="
for num in {1..5}; do
    echo "数字: $num"
done

echo ""
echo "=== 3. 带步长的花括号展开 {start..end..step} ==="
for even in {0..10..2}; do
    echo "偶数: $even"
done

echo ""
echo "=== 4. 遍历文件（通配符）==="
# 创建测试文件
touch test1.txt test2.txt test3.log

for file in *.txt; do
    echo "TXT 文件: $file"
done

echo ""
echo "=== 5. 遍历数组 ==="
servers=("web01" "web02" "db01" "db02")
for server in "${servers[@]}"; do
    echo "服务器: $server"
done

echo ""
echo "=== 6. 带索引遍历数组 ==="
for i in "${!servers[@]}"; do
    echo "索引 $i: ${servers[$i]}"
done

# 清理
rm -f test1.txt test2.txt test3.log
EOF

chmod +x for_basics.sh
./for_basics.sh
```

### 1.3 通配符遍历文件的正确方式

**这是本课最重要的知识点之一！**

```bash
cd ~/shell-lab/loops

cat > glob_iteration.sh << 'EOF'
#!/bin/bash
# 正确遍历文件的方法

# 创建测试环境（包含带空格的文件名）
mkdir -p demo_files
touch "demo_files/normal.txt"
touch "demo_files/with space.txt"
touch "demo_files/special-chars!@#.txt"

echo "=== 正确：使用通配符直接遍历 ==="
for file in demo_files/*.txt; do
    # 检查文件是否真实存在（处理没有匹配的情况）
    [[ -e "$file" ]] || continue
    echo "处理文件: $file"
done

echo ""
echo "=== 正确：使用 nullglob 选项 ==="
shopt -s nullglob  # 没有匹配时返回空列表而非字面值
for file in demo_files/*.xyz; do
    echo "XYZ 文件: $file"
done
echo "(没有 .xyz 文件，循环不执行)"
shopt -u nullglob  # 恢复默认

# 清理
rm -rf demo_files
EOF

chmod +x glob_iteration.sh
./glob_iteration.sh
```

---

## Step 2 - for 循环：C 风格（10 分钟）

Bash 支持类似 C 语言的 for 循环语法，适合需要计数器的场景。

### 2.1 C 风格语法

```
for ((初始化; 条件; 更新)); do
    命令...
done
```

### 2.2 实战演示

```bash
cd ~/shell-lab/loops

cat > for_cstyle.sh << 'EOF'
#!/bin/bash
# C 风格 for 循环演示

echo "=== 基本计数 ==="
for ((i = 0; i < 5; i++)); do
    echo "i = $i"
done

echo ""
echo "=== 倒数 ==="
for ((i = 5; i > 0; i--)); do
    echo "倒数: $i"
done

echo ""
echo "=== 自定义步长 ==="
for ((i = 0; i <= 20; i += 5)); do
    echo "i = $i"
done

echo ""
echo "=== 多变量 ==="
for ((i = 0, j = 10; i < 5; i++, j--)); do
    echo "i = $i, j = $j"
done

echo ""
echo "=== 实用示例：生成序列文件名 ==="
for ((n = 1; n <= 3; n++)); do
    filename=$(printf "backup_%03d.tar.gz" "$n")
    echo "创建: $filename"
done
EOF

chmod +x for_cstyle.sh
./for_cstyle.sh
```

### 2.3 何时使用 C 风格

| 场景 | 推荐方式 |
|------|----------|
| 固定范围迭代 | `for i in {1..10}` |
| 需要精确控制步长 | `for ((i=0; i<100; i+=7))` |
| 多变量同步更新 | C 风格 |
| 遍历文件 | `for f in *.txt` |
| 遍历数组 | `for item in "${array[@]}"` |

---

## Step 3 - while 循环（15 分钟）

### 3.1 while 循环语法

```
while 条件; do
    命令...
done
```

<!-- DIAGRAM: while-loop-flow -->
```
┌─────────────────────────────────────────────────────────────────────┐
│  while 循环流程                                                      │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│         ┌──────────┐                                                │
│         │  开始    │                                                │
│         └────┬─────┘                                                │
│              │                                                       │
│              ▼                                                       │
│         ┌──────────┐     否                                         │
│    ┌───▶│ 条件判断 │─────────────────────┐                          │
│    │    └────┬─────┘                     │                          │
│    │         │ 是                        │                          │
│    │         ▼                           │                          │
│    │    ┌──────────┐                     │                          │
│    │    │ 执行命令 │                     │                          │
│    │    └────┬─────┘                     │                          │
│    │         │                           │                          │
│    └─────────┘                           ▼                          │
│                                    ┌──────────┐                     │
│                                    │   结束   │                     │
│                                    └──────────┘                     │
│                                                                      │
│    注意：条件为真（退出码 0）时继续循环                               │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```
<!-- /DIAGRAM -->

### 3.2 while 循环实战

```bash
cd ~/shell-lab/loops

cat > while_demo.sh << 'EOF'
#!/bin/bash
# while 循环演示

echo "=== 1. 计数器循环 ==="
count=0
while [[ $count -lt 5 ]]; do
    echo "计数: $count"
    ((count++))
done

echo ""
echo "=== 2. 处理命令输出 ==="
# 监控进程（简化示例）
echo "PID     COMMAND"
ps aux | head -5 | while read -r line; do
    echo "$line" | awk '{print $2, $11}'
done

echo ""
echo "=== 3. 无限循环（带退出条件）==="
attempts=0
max_attempts=3

while true; do
    ((attempts++))
    echo "尝试 #$attempts"

    if [[ $attempts -ge $max_attempts ]]; then
        echo "达到最大尝试次数，退出"
        break
    fi
done

echo ""
echo "=== 4. 等待条件成立 ==="
# 模拟等待服务启动
wait_count=0
service_ready=false

while [[ $service_ready == false ]]; do
    ((wait_count++))
    echo "等待服务启动... ($wait_count)"

    # 模拟：第 3 次检查时服务就绪
    if [[ $wait_count -ge 3 ]]; then
        service_ready=true
    fi

    sleep 0.5
done
echo "服务已就绪！"
EOF

chmod +x while_demo.sh
./while_demo.sh
```

### 3.3 until 循环

`until` 是 `while` 的反面：**条件为假时继续循环**。

```bash
cd ~/shell-lab/loops

cat > until_demo.sh << 'EOF'
#!/bin/bash
# until 循环演示

echo "=== until vs while 对比 ==="

echo "while 版本（条件为真时继续）："
count=0
while [[ $count -lt 3 ]]; do
    echo "  count = $count"
    ((count++))
done

echo ""
echo "until 版本（条件为假时继续）："
count=0
until [[ $count -ge 3 ]]; do
    echo "  count = $count"
    ((count++))
done

echo ""
echo "=== 实用示例：等待文件出现 ==="
# 创建一个后台进程在 2 秒后创建文件
(sleep 2 && touch /tmp/ready_signal_$$) &

echo "等待信号文件..."
until [[ -f /tmp/ready_signal_$$ ]]; do
    echo "  文件尚未出现..."
    sleep 0.5
done
echo "信号文件已出现！"

# 清理
rm -f /tmp/ready_signal_$$
EOF

chmod +x until_demo.sh
./until_demo.sh
```

---

## Step 4 - 正确读取文件（while read）（15 分钟）

**这是面试高频考点，也是实际工作中最常用的模式！**

### 4.1 while read 基本语法

```bash
while IFS= read -r line; do
    处理 "$line"
done < 文件
```

**为什么要用 `IFS=` 和 `-r`？**

| 选项 | 作用 | 不用会怎样 |
|------|------|------------|
| `IFS=` | 保留行首尾空白 | 前导/尾随空格被删除 |
| `-r` | 不解释反斜杠 | `\n` 等被转义 |

### 4.2 正确读取文件

```bash
cd ~/shell-lab/loops

cat > read_file.sh << 'EOF'
#!/bin/bash
# 正确读取文件的方法

# 创建测试文件
cat > testdata.txt << 'DATA'
  Line with leading spaces
Line with \n escape
Normal line
	Line with tab
DATA

echo "=== 错误方法：不用 IFS= 和 -r ==="
while read line; do
    echo "[$line]"
done < testdata.txt

echo ""
echo "=== 正确方法：使用 IFS= 和 -r ==="
while IFS= read -r line; do
    echo "[$line]"
done < testdata.txt

# 清理
rm -f testdata.txt
EOF

chmod +x read_file.sh
./read_file.sh
```

### 4.3 读取带分隔符的数据

```bash
cd ~/shell-lab/loops

cat > read_csv.sh << 'EOF'
#!/bin/bash
# 读取 CSV 格式数据

# 创建测试数据
cat > users.csv << 'DATA'
username,email,role
alice,alice@example.com,admin
bob,bob@example.com,user
charlie,charlie@example.com,user
DATA

echo "=== 读取 CSV 文件 ==="
# 跳过标题行
{
    read -r header  # 读取并丢弃标题行
    while IFS=, read -r username email role; do
        echo "用户: $username"
        echo "  邮箱: $email"
        echo "  角色: $role"
        echo ""
    done
} < users.csv

# 清理
rm -f users.csv
EOF

chmod +x read_csv.sh
./read_csv.sh
```

### 4.4 读取多个字段

```bash
cd ~/shell-lab/loops

cat > read_fields.sh << 'EOF'
#!/bin/bash
# 读取多字段数据

# /etc/passwd 格式：username:password:uid:gid:gecos:home:shell
echo "=== 解析 /etc/passwd（前 5 行）==="
head -5 /etc/passwd | while IFS=: read -r user pass uid gid gecos home shell; do
    echo "用户: $user"
    echo "  UID: $uid, GID: $gid"
    echo "  主目录: $home"
    echo "  Shell: $shell"
    echo ""
done

echo "=== 使用 read -a 读取为数组 ==="
echo "a b c d e" | {
    read -ra arr
    echo "数组内容: ${arr[*]}"
    echo "第三个元素: ${arr[2]}"
}
EOF

chmod +x read_fields.sh
./read_fields.sh
```

---

## Step 5 - break 和 continue（10 分钟）

### 5.1 控制循环流程

| 命令 | 作用 |
|------|------|
| `break` | 立即退出循环 |
| `break N` | 退出 N 层循环 |
| `continue` | 跳过本次迭代，继续下一次 |
| `continue N` | 跳过 N 层循环的本次迭代 |

### 5.2 实战演示

```bash
cd ~/shell-lab/loops

cat > control_flow.sh << 'EOF'
#!/bin/bash
# break 和 continue 演示

echo "=== break：找到目标后退出 ==="
for i in {1..10}; do
    echo "检查: $i"
    if [[ $i -eq 5 ]]; then
        echo "找到 5，退出循环"
        break
    fi
done
echo "循环结束"

echo ""
echo "=== continue：跳过特定项 ==="
for i in {1..10}; do
    # 跳过偶数
    if (( i % 2 == 0 )); then
        continue
    fi
    echo "奇数: $i"
done

echo ""
echo "=== 嵌套循环中的 break 2 ==="
for i in {1..3}; do
    for j in {1..3}; do
        echo "i=$i, j=$j"
        if [[ $i -eq 2 && $j -eq 2 ]]; then
            echo "退出两层循环"
            break 2
        fi
    done
done
echo "外层循环结束"

echo ""
echo "=== 实用示例：搜索文件 ==="
target_content="root"
found_file=""

for file in /etc/passwd /etc/shadow /etc/group; do
    if [[ ! -r "$file" ]]; then
        echo "跳过不可读文件: $file"
        continue
    fi

    if grep -q "$target_content" "$file" 2>/dev/null; then
        found_file="$file"
        echo "在 $file 中找到 '$target_content'"
        break
    fi
done

if [[ -n "$found_file" ]]; then
    echo "结果: 在 $found_file 中找到"
else
    echo "结果: 未找到"
fi
EOF

chmod +x control_flow.sh
./control_flow.sh
```

---

## Step 6 - 失败实验室：for in $(ls) 陷阱（10 分钟）

**这是最常见的 Shell 脚本 Bug 之一！**

### 6.1 问题演示

```bash
cd ~/shell-lab/loops

cat > failure_lab_ls.sh << 'EOF'
#!/bin/bash
# 失败实验室：for in $(ls) 的陷阱

# 创建测试环境
mkdir -p test_ls
touch "test_ls/normal.txt"
touch "test_ls/with space.txt"       # 带空格的文件名
touch "test_ls/multi  spaces.txt"    # 多个空格
touch "test_ls/*.txt"                # 通配符作为文件名（极端情况）

echo "实际文件列表："
ls -la test_ls/
echo ""

echo "=== 错误方法：for in \$(ls) ==="
echo "（注意带空格的文件名会被分割！）"
for file in $(ls test_ls/); do
    echo "  文件: [$file]"
done

echo ""
echo "=== 正确方法：for in 通配符 ==="
for file in test_ls/*; do
    # 使用 basename 获取纯文件名
    filename=$(basename "$file")
    echo "  文件: [$filename]"
done

echo ""
echo "=== 更安全：检查文件存在 ==="
for file in test_ls/*.txt; do
    [[ -e "$file" ]] || continue
    echo "  文件: [$(basename "$file")]"
done

# 清理
rm -rf test_ls
EOF

chmod +x failure_lab_ls.sh
./failure_lab_ls.sh
```

### 6.2 为什么 $(ls) 有问题？

<!-- DIAGRAM: ls-trap-explanation -->
```
┌─────────────────────────────────────────────────────────────────────┐
│  for in $(ls) 的问题                                                 │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  实际文件:                                                           │
│    - normal.txt                                                      │
│    - with space.txt                                                  │
│                                                                      │
│  $(ls) 输出:                                                         │
│    "normal.txt\nwith space.txt"                                     │
│                                                                      │
│  Word Splitting 后 for 看到的列表:                                   │
│    "normal.txt" "with" "space.txt"    ← 三个元素！                  │
│                                                                      │
│  结果:                                                               │
│    - 第一次循环: file="normal.txt"     ✓                            │
│    - 第二次循环: file="with"           ✗ 文件不存在                 │
│    - 第三次循环: file="space.txt"      ✗ 文件不存在                 │
│                                                                      │
│  正确做法: for file in *; do ... done                               │
│    - Shell 直接处理通配符                                            │
│    - 每个文件名作为一个整体                                          │
│    - 正确处理空格和特殊字符                                          │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```
<!-- /DIAGRAM -->

### 6.3 其他危险模式

```bash
cd ~/shell-lab/loops

cat > more_traps.sh << 'EOF'
#!/bin/bash
# 更多循环陷阱

echo "=== 陷阱 1：for in \$(find ...) ==="
echo "同样有 Word Splitting 问题"
echo ""

# 错误
# for file in $(find . -name "*.txt"); do
#     echo "$file"
# done

# 正确：使用 -print0 和 while read
echo "正确方法（find + while read）："
find . -maxdepth 1 -name "*.sh" -print0 2>/dev/null | while IFS= read -r -d '' file; do
    echo "  找到: $file"
done

echo ""
echo "=== 陷阱 2：通配符未匹配 ==="
echo "当没有 *.xyz 文件时："

# 问题：如果没有匹配，循环变量会是字面值 "*.xyz"
for file in *.xyz; do
    echo "  文件: $file"
    [[ -e "$file" ]] && echo "    存在" || echo "    不存在！"
done

echo ""
echo "解决方案 1：检查文件存在"
for file in *.xyz; do
    [[ -e "$file" ]] || continue
    echo "  文件: $file"
done
echo "(循环不执行，因为检查了文件存在)"

echo ""
echo "解决方案 2：使用 nullglob"
shopt -s nullglob
for file in *.xyz; do
    echo "  文件: $file"
done
echo "(循环不执行，因为 nullglob 返回空列表)"
shopt -u nullglob
EOF

chmod +x more_traps.sh
./more_traps.sh
```

---

## Step 7 - 循环与管道的陷阱（子 shell 问题）（10 分钟）

**这是另一个常见的坑！**

### 7.1 问题演示

```bash
cd ~/shell-lab/loops

cat > subshell_trap.sh << 'EOF'
#!/bin/bash
# 子 shell 陷阱演示

echo "=== 问题：管道中的 while 循环 ==="

count=0
result=""

# 错误：管道创建子 shell，变量修改不会影响父 shell
echo -e "line1\nline2\nline3" | while read -r line; do
    ((count++))
    result+="$line "
    echo "  子 shell 内: count=$count"
done

echo "父 shell 中: count=$count"      # 仍然是 0！
echo "父 shell 中: result='$result'"  # 仍然是空的！

echo ""
echo "原因：管道 | 后面的命令在子 shell 中运行"
echo "      子 shell 中的变量修改不会影响父 shell"
EOF

chmod +x subshell_trap.sh
./subshell_trap.sh
```

### 7.2 解决方案

```bash
cd ~/shell-lab/loops

cat > subshell_solutions.sh << 'EOF'
#!/bin/bash
# 子 shell 问题的解决方案

echo "=== 解决方案 1：使用进程替换 <() ==="
count=0
result=""

while read -r line; do
    ((count++))
    result+="$line "
done < <(echo -e "line1\nline2\nline3")

echo "count=$count"      # 3
echo "result='$result'"  # line1 line2 line3

echo ""
echo "=== 解决方案 2：使用 Here String ==="
count=0
data="line1
line2
line3"

while IFS= read -r line; do
    ((count++))
done <<< "$data"

echo "count=$count"  # 3

echo ""
echo "=== 解决方案 3：读取文件 ==="
count=0

# 创建临时文件
tmpfile=$(mktemp)
echo -e "line1\nline2\nline3" > "$tmpfile"

while IFS= read -r line; do
    ((count++))
done < "$tmpfile"

rm -f "$tmpfile"
echo "count=$count"  # 3

echo ""
echo "=== 解决方案 4：lastpipe 选项（Bash 4.2+）==="
# 在非交互式脚本中，可以让管道最后一个命令在当前 shell 执行
set +m         # 关闭作业控制（脚本中默认关闭）
shopt -s lastpipe

count=0
echo -e "line1\nline2\nline3" | while read -r line; do
    ((count++))
done

echo "count=$count"  # 3 (需要 Bash 4.2+)
shopt -u lastpipe
EOF

chmod +x subshell_solutions.sh
./subshell_solutions.sh
```

### 7.3 进程替换详解

<!-- DIAGRAM: process-substitution -->
```
┌─────────────────────────────────────────────────────────────────────┐
│  进程替换 <( ) 工作原理                                              │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  管道方式（子 shell 问题）:                                          │
│  ───────────────────────────                                        │
│    command | while read line; do ... done                           │
│                                                                      │
│    ┌─────────┐     ┌─────────────────┐                              │
│    │ command │────▶│ while (子 shell) │  ← 变量修改不影响父 shell   │
│    └─────────┘     └─────────────────┘                              │
│                                                                      │
│  进程替换方式（解决问题）:                                           │
│  ───────────────────────────                                        │
│    while read line; do ... done < <(command)                        │
│                                                                      │
│    ┌─────────┐                                                       │
│    │ command │──┐                                                    │
│    └─────────┘  │  /dev/fd/N                                        │
│                 │  (虚拟文件)                                        │
│                 ▼                                                    │
│    ┌─────────────────────────┐                                      │
│    │ while (当前 shell)       │  ← 变量修改保留！                   │
│    │   read line < /dev/fd/N │                                      │
│    └─────────────────────────┘                                      │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```
<!-- /DIAGRAM -->

---

## Step 8 - Mini Project：批量文件处理器（15 分钟）

综合运用所学知识，创建一个功能完整的批量文件处理器。

### 8.1 项目要求

创建脚本 `file_organizer.sh`，要求：

1. 遍历指定目录中的所有文件
2. 根据文件扩展名分类（txt, log, sh, other）
3. 统计每类文件的数量和总大小
4. 正确处理带空格的文件名
5. 通过 ShellCheck 零警告

### 8.2 参考实现

```bash
cd ~/shell-lab/loops

cat > file_organizer.sh << 'EOF'
#!/bin/bash
# =============================================================================
# 脚本名称: file_organizer.sh
# 功能说明: 遍历目录文件，按扩展名分类统计
# 作者: [你的名字]
# 创建日期: 2026-01-10
# =============================================================================
#
# 使用方法:
#   ./file_organizer.sh [目录]
#   ./file_organizer.sh /var/log
#   ./file_organizer.sh              # 默认当前目录
#
# =============================================================================

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 打印带颜色的消息
print_header() {
    echo -e "${BLUE}$1${NC}"
}

print_category() {
    echo -e "${GREEN}$1${NC}"
}

# 显示用法
usage() {
    echo "用法: $0 [目录]"
    echo ""
    echo "示例:"
    echo "  $0 /var/log"
    echo "  $0 ~/Documents"
    exit 1
}

# 获取文件大小（跨平台）
get_size() {
    local file="$1"
    if stat --version &>/dev/null 2>&1; then
        stat -c %s "$file" 2>/dev/null || echo 0
    else
        stat -f %z "$file" 2>/dev/null || echo 0
    fi
}

# 格式化文件大小
format_size() {
    local size=$1
    if (( size >= 1073741824 )); then
        printf "%.2f GB" "$(echo "scale=2; $size/1073741824" | bc)"
    elif (( size >= 1048576 )); then
        printf "%.2f MB" "$(echo "scale=2; $size/1048576" | bc)"
    elif (( size >= 1024 )); then
        printf "%.2f KB" "$(echo "scale=2; $size/1024" | bc)"
    else
        printf "%d B" "$size"
    fi
}

# 主函数
main() {
    local target_dir="${1:-.}"

    # 检查目录是否存在
    if [[ ! -d "$target_dir" ]]; then
        echo -e "${RED}错误: 目录不存在: $target_dir${NC}" >&2
        exit 1
    fi

    print_header "============================================"
    print_header "         文件分类统计报告"
    print_header "============================================"
    echo ""
    echo "扫描目录: $target_dir"
    echo ""

    # 使用关联数组统计（Bash 4+）
    declare -A count
    declare -A size

    # 初始化分类
    local categories=("txt" "log" "sh" "other")
    for cat in "${categories[@]}"; do
        count[$cat]=0
        size[$cat]=0
    done

    local total_files=0
    local total_size=0

    # 遍历目录中的文件（正确处理空格）
    shopt -s nullglob  # 无匹配时返回空
    for file in "$target_dir"/*; do
        # 只处理普通文件
        [[ -f "$file" ]] || continue

        ((total_files++))

        # 获取文件大小
        local file_size
        file_size=$(get_size "$file")
        ((total_size += file_size))

        # 获取扩展名
        local filename
        filename=$(basename "$file")
        local ext="${filename##*.}"

        # 如果没有扩展名，或扩展名等于文件名
        if [[ "$ext" == "$filename" ]]; then
            ext="other"
        fi

        # 分类统计
        case "$ext" in
            txt)
                ((count[txt]++))
                ((size[txt] += file_size))
                ;;
            log)
                ((count[log]++))
                ((size[log] += file_size))
                ;;
            sh|bash)
                ((count[sh]++))
                ((size[sh] += file_size))
                ;;
            *)
                ((count[other]++))
                ((size[other] += file_size))
                ;;
        esac
    done
    shopt -u nullglob

    # 输出统计结果
    print_header "--- 分类统计 ---"
    echo ""
    printf "%-15s %-10s %-15s\n" "类型" "文件数" "总大小"
    printf "%-15s %-10s %-15s\n" "----" "------" "------"

    for cat in "${categories[@]}"; do
        local cat_name
        case "$cat" in
            txt)   cat_name="文本文件" ;;
            log)   cat_name="日志文件" ;;
            sh)    cat_name="Shell 脚本" ;;
            other) cat_name="其他文件" ;;
        esac

        if (( count[$cat] > 0 )); then
            printf "%-15s %-10d %-15s\n" "$cat_name" "${count[$cat]}" "$(format_size "${size[$cat]}")"
        fi
    done

    echo ""
    print_header "--- 总计 ---"
    echo "文件总数: $total_files"
    echo "总大小:   $(format_size "$total_size")"
    echo ""
    print_header "============================================"
}

# 处理参数
if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    usage
fi

# 执行主函数
main "$@"
EOF

chmod +x file_organizer.sh

# 创建测试环境
mkdir -p test_files
echo "Hello" > "test_files/doc.txt"
echo "World" > "test_files/notes.txt"
echo "Log entry" > "test_files/app.log"
echo "#!/bin/bash" > "test_files/script.sh"
echo "Data" > "test_files/data.csv"
echo "More" > "test_files/file with space.txt"

# ShellCheck 检查
echo "=== ShellCheck 检查 ==="
shellcheck file_organizer.sh || echo "(请安装 shellcheck 进行检查)"

# 运行测试
echo ""
echo "=== 运行测试 ==="
./file_organizer.sh test_files

# 清理
rm -rf test_files
```

---

## 反模式：常见错误

### 错误 1：for in $(ls)

```bash
# 错误：文件名空格会被分割
for file in $(ls); do
    echo "$file"
done

# 正确：使用通配符
for file in *; do
    [[ -e "$file" ]] || continue
    echo "$file"
done
```

### 错误 2：cat file | while read

```bash
# 错误：管道创建子 shell，变量修改不会保留
count=0
cat file.txt | while read line; do
    ((count++))
done
echo "count=$count"  # 仍然是 0！

# 正确：使用重定向
count=0
while read -r line; do
    ((count++))
done < file.txt
echo "count=$count"  # 正确的值
```

### 错误 3：不使用 IFS= 和 -r

```bash
# 错误：会丢失前导空格和处理反斜杠
while read line; do
    echo "[$line]"
done < file.txt

# 正确：保留原始内容
while IFS= read -r line; do
    echo "[$line]"
done < file.txt
```

### 错误 4：忘记引用循环变量

```bash
# 错误：文件名有空格时会出问题
for file in *.txt; do
    rm $file  # 危险！
done

# 正确：始终引用变量
for file in *.txt; do
    rm "$file"
done
```

---

## 职场小贴士（Japan IT Context）

### 运维脚本中的循环应用

在日本 IT 企业的运维现场（運用現場），循环常用于：

| 日语术语 | 含义 | 典型用法 |
|----------|------|----------|
| バッチ処理 | 批量处理 | 批量备份、日志轮转 |
| 一括置換 | 批量替换 | 配置文件批量更新 |
| ログ監視 | 日志监控 | while 循环持续读取日志 |
| 定期チェック | 定期检查 | 服务状态轮询 |

### 典型的日本企业批处理脚本

```bash
#!/bin/bash
# =============================================================================
# スクリプト名: batch_backup.sh
# 概要: 複数サーバーへのバックアップ配布
# 作成者: 田中太郎
# 作成日: 2026-01-10
# =============================================================================

# サーバーリスト
servers=(
    "web01.example.jp"
    "web02.example.jp"
    "db01.example.jp"
)

# バックアップファイル
BACKUP_FILE="/backup/daily_$(date +%Y%m%d).tar.gz"

# 各サーバーへ配布
for server in "${servers[@]}"; do
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $server へ配布開始..."

    if scp "$BACKUP_FILE" "backup@${server}:/backup/" 2>/dev/null; then
        echo "[OK] $server 配布完了"
    else
        echo "[ERROR] $server 配布失敗" >&2
    fi
done

echo "処理完了"
```

---

## 检查清单

完成本课后，你应该能够：

- [ ] 使用 for 循环遍历列表、文件、数组
- [ ] 使用 C 风格 for 循环进行计数
- [ ] 使用 while/until 循环进行条件控制
- [ ] 正确使用 `while IFS= read -r` 读取文件
- [ ] 使用 break 和 continue 控制循环流程
- [ ] 避免 `for in $(ls)` 陷阱
- [ ] 理解并解决管道中的子 shell 问题
- [ ] 使用进程替换 `<()` 替代管道

---

## 本课小结

| 概念 | 要点 |
|------|------|
| for in 列表 | `for item in list; do ... done` |
| for C 风格 | `for ((i=0; i<10; i++)); do ... done` |
| while 循环 | `while [[ 条件 ]]; do ... done` |
| until 循环 | `until [[ 条件 ]]; do ... done` |
| 读取文件 | `while IFS= read -r line; do ... done < file` |
| 遍历文件 | `for file in *.txt; do ... done`（不是 `$(ls)`！）|
| 子 shell 陷阱 | 管道后面是子 shell，用 `< <()` 进程替换解决 |
| 控制流程 | break 退出循环，continue 跳过本次迭代 |

---

## 面试准备

### ファイルを1行ずつ読む正しい方法は？

正しい方法は `while IFS= read -r line; do ... done < file` です。`IFS=` は行頭・行末の空白を保持し、`-r` はバックスラッシュを解釈しないようにします。`cat file | while read` はパイプでサブシェルが作成されるため、変数の変更が親シェルに反映されません。

### for in $(ls) の問題点は？

`$(ls)` の出力は Word Splitting されるため、スペースを含むファイル名が分割されます。例えば `my file.txt` は `my` と `file.txt` の2つの要素として処理されます。正しい方法は `for file in *; do ... done` でグロブパターンを直接使用することです。シェルがファイル名を正しく個別の要素として扱います。

---

## 延伸阅读

- [GNU Bash Manual - Looping Constructs](https://www.gnu.org/software/bash/manual/html_node/Looping-Constructs.html)
- [BashFAQ/001 - How can I read a file line-by-line?](https://mywiki.wooledge.org/BashFAQ/001)
- [Why you shouldn't parse ls output](https://mywiki.wooledge.org/ParsingLs)
- 下一课：[06 - 函数](../06-functions/) - 模块化你的脚本
- 相关课程：[03 - 引用规则](../03-quoting/) - 理解 Word Splitting

---

## 系列导航

[<- 04 - 条件判断](../04-conditionals/) | [课程首页](../) | [06 - 函数 ->](../06-functions/)
