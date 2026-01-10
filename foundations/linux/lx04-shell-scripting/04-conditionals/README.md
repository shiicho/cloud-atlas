# 04 - 条件判断（Conditionals）

> **目标**：掌握 Shell 脚本中的条件判断语法和各类测试操作符  
> **前置**：已完成 [03 - 引用规则](../03-quoting/)  
> **时间**：⚡ 20 分钟（速读）/ 🔬 75 分钟（完整实操）  
> **环境**：Bash 4.x+（RHEL 7/8/9, Ubuntu 18.04+ 均可）  

---

## 将学到的内容

1. 掌握 if/elif/else/fi 语法
2. 理解 test、`[ ]`、`[[ ]]` 的区别
3. 使用文件测试（-f, -d, -e, -r, -w, -x）
4. 使用字符串测试（=, !=, -z, -n）
5. 使用数值比较（-eq, -ne, -lt, -gt, -le, -ge）
6. 掌握 case 语句处理模式匹配

---

## 先跑起来！（5 分钟）

> 在理解原理之前，先让条件判断跑起来。  
> 体验脚本如何根据情况做出不同决策。  

```bash
# 创建练习目录
mkdir -p ~/shell-lab/conditionals && cd ~/shell-lab/conditionals

# 创建一个简单的文件类型检测器
cat > filetype.sh << 'EOF'
#!/bin/bash
# 文件类型检测器 - 检测给定路径是什么类型

TARGET="${1:-/etc/passwd}"

echo "检测目标: $TARGET"
echo "-------------------"

if [[ -f "$TARGET" ]]; then
    echo "类型: 普通文件"
    echo "大小: $(stat -c %s "$TARGET" 2>/dev/null || stat -f %z "$TARGET") 字节"
elif [[ -d "$TARGET" ]]; then
    echo "类型: 目录"
    echo "内容: $(ls -1 "$TARGET" | wc -l) 个项目"
elif [[ -L "$TARGET" ]]; then
    echo "类型: 符号链接"
    echo "指向: $(readlink "$TARGET")"
else
    echo "类型: 不存在或特殊文件"
fi

echo "-------------------"
echo "权限检查:"
[[ -r "$TARGET" ]] && echo "  - 可读"
[[ -w "$TARGET" ]] && echo "  - 可写"
[[ -x "$TARGET" ]] && echo "  - 可执行"
EOF

chmod +x filetype.sh

# 测试不同类型
./filetype.sh /etc/passwd
echo ""
./filetype.sh /etc
echo ""
./filetype.sh /bin/bash
```

**你应该看到类似的输出：**

```
检测目标: /etc/passwd
-------------------
类型: 普通文件
大小: 2456 字节
-------------------
权限检查:
  - 可读

检测目标: /etc
-------------------
类型: 目录
内容: 156 个项目
-------------------
权限检查:
  - 可读
  - 可执行

检测目标: /bin/bash
-------------------
类型: 普通文件
大小: 1183448 字节
-------------------
权限检查:
  - 可读
  - 可执行
```

**恭喜！你的脚本已经能根据文件类型做出不同判断！**

现在让我们理解条件判断的原理。

---

## Step 1 - if 语句基础（15 分钟）

### 1.1 if 语句语法结构

```
if 条件; then
    命令...
elif 条件; then
    命令...
else
    命令...
fi
```

<!-- DIAGRAM: if-statement-structure -->
```
┌─────────────────────────────────────────────────────────────────────┐
│  if 语句结构                                                          │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│    if [ 条件 ]; then         ← 条件为真（退出码 0）时执行            │
│        命令1                                                         │
│        命令2                                                         │
│    elif [ 另一条件 ]; then   ← 可选，可以有多个 elif                 │
│        命令3                                                         │
│    else                       ← 可选，所有条件都不满足时执行         │
│        命令4                                                         │
│    fi                         ← 必须用 fi 结束（if 倒过来）          │
│                                                                      │
│    注意：then 可以和 if 同行（用 ; 分隔）或另起一行                  │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```
<!-- /DIAGRAM -->

### 1.2 Shell 中的"真"与"假"

**关键概念：Shell 用命令的退出码判断真假**

- **退出码 0 = 真（成功）**
- **退出码非 0 = 假（失败）**

这和大多数编程语言相反！

```bash
# 实验：理解退出码
cd ~/shell-lab/conditionals

# true 命令总是返回 0
true
echo "true 的退出码: $?"    # 0

# false 命令总是返回 1
false
echo "false 的退出码: $?"   # 1

# 命令成功 = 退出码 0
ls / > /dev/null
echo "ls / 的退出码: $?"    # 0

# 命令失败 = 退出码非 0
ls /nonexistent 2> /dev/null
echo "ls /nonexistent 的退出码: $?"  # 2
```

### 1.3 if 的实际工作原理

```bash
# if 后面跟的是命令，不是布尔表达式
# 如果命令返回 0，条件为真

# 示例 1：直接使用命令
if ls /etc > /dev/null 2>&1; then
    echo "/etc 存在且可访问"
fi

# 示例 2：使用 grep 检查内容
if grep -q "root" /etc/passwd; then
    echo "passwd 文件中包含 root"
fi

# 示例 3：使用 test 命令
if test -f /etc/passwd; then
    echo "/etc/passwd 是一个文件"
fi
```

**重点**：`[ ]` 实际上是 `test` 命令的语法糖！

```bash
# 这两个是完全等价的
test -f /etc/passwd
[ -f /etc/passwd ]
```

---

## Step 2 - test、[ ] 与 [[ ]] 的区别（20 分钟）

这是面试高频考点！

### 2.1 三种测试方式对比

| 语法 | 类型 | 特点 | 推荐度 |
|------|------|------|--------|
| `test` | 命令 | POSIX 标准，最古老 | 了解即可 |
| `[ ]` | 命令 | test 的别名，需要空格 | sh 兼容时用 |
| `[[ ]]` | Bash 关键字 | 增强版，更安全 | Bash 脚本首选 |

### 2.2 语法差异演示

```bash
cd ~/shell-lab/conditionals

cat > test_comparison.sh << 'EOF'
#!/bin/bash
# 演示 [ ] 和 [[ ]] 的区别

VAR=""
FILE="my file.txt"

echo "=== 测试 1：空变量处理 ==="

# [ ] 中空变量会导致语法错误
# [ $VAR = "hello" ]  # 错误！展开后变成 [ = "hello" ]

# 必须加引号
if [ "$VAR" = "hello" ]; then
    echo "[ ] 匹配成功"
else
    echo "[ ] 匹配失败（变量为空）"
fi

# [[ ]] 中不需要引号也安全
if [[ $VAR = "hello" ]]; then
    echo "[[ ]] 匹配成功"
else
    echo "[[ ]] 匹配失败（变量为空）"
fi

echo ""
echo "=== 测试 2：逻辑运算符 ==="

A=5
B=10

# [ ] 中使用 -a 和 -o
if [ "$A" -lt 10 -a "$B" -gt 5 ]; then
    echo "[ ] 使用 -a: A<10 且 B>5"
fi

# [[ ]] 中使用 && 和 ||
if [[ $A -lt 10 && $B -gt 5 ]]; then
    echo "[[ ]] 使用 &&: A<10 且 B>5"
fi

echo ""
echo "=== 测试 3：模式匹配（[[ ]] 专属）==="

TEXT="hello_world"

# [[ ]] 支持通配符模式匹配
if [[ $TEXT == hello* ]]; then
    echo "TEXT 以 'hello' 开头"
fi

if [[ $TEXT == *world ]]; then
    echo "TEXT 以 'world' 结尾"
fi

# [[ ]] 支持正则表达式
if [[ $TEXT =~ ^hello.*world$ ]]; then
    echo "TEXT 匹配正则 ^hello.*world$"
fi

echo ""
echo "=== 测试 4：处理带空格的文件名 ==="

# 创建带空格的测试文件
touch "my file.txt"

# [ ] 中必须引用变量
if [ -f "$FILE" ]; then
    echo "[ ] 找到文件: $FILE"
fi

# [[ ]] 中引号可选（但推荐加上）
if [[ -f $FILE ]]; then
    echo "[[ ]] 找到文件: $FILE"
fi

# 清理
rm -f "my file.txt"
EOF

chmod +x test_comparison.sh
./test_comparison.sh
```

### 2.3 [[ ]] 的优势总结

<!-- DIAGRAM: test-vs-brackets -->
```
┌─────────────────────────────────────────────────────────────────────┐
│  [ ] vs [[ ]] 对比                                                    │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  [ ] (test 命令)                  [[ ]] (Bash 关键字)               │
│  ─────────────────                ──────────────────────             │
│                                                                      │
│  - POSIX 兼容                     - Bash/Zsh 扩展                   │
│  - 变量必须加引号 "$var"          - 变量可以不加引号                │
│  - 逻辑：-a, -o, !                - 逻辑：&&, ||, !                 │
│  - 字符串比较：=, !=              - 支持模式匹配：==, !=, =~       │
│  - 不支持正则                     - 支持正则表达式 =~              │
│  - 词分割和通配符展开             - 不做词分割和通配符展开         │
│                                                                      │
│  何时用 [ ]？                     何时用 [[ ]]？                    │
│  ─────────────                    ──────────────                     │
│  - 需要 sh/POSIX 兼容             - Bash 脚本（推荐）              │
│  - 极简脚本                       - 需要模式匹配                   │
│                                   - 需要更安全的语法               │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```
<!-- /DIAGRAM -->

### 2.4 语法细节：空格很重要！

```bash
# [ ] 是命令，所以括号两边必须有空格

# 正确
if [ "$VAR" = "hello" ]; then echo "yes"; fi

# 错误 - 缺少空格
if ["$VAR" = "hello"]; then echo "yes"; fi    # [hello: command not found
if [ "$VAR"="hello" ]; then echo "yes"; fi    # 总是为真！

# [[ ]] 同样需要空格
if [[ $VAR == "hello" ]]; then echo "yes"; fi  # 正确
```

---

## Step 3 - 文件测试操作符（15 分钟）

Shell 提供了丰富的文件测试操作符，这在运维脚本中极其常用。

### 3.1 常用文件测试操作符

| 操作符 | 含义 | 示例 |
|--------|------|------|
| `-e` | 存在（exists） | `[[ -e /path ]]` |
| `-f` | 是普通文件 | `[[ -f /etc/passwd ]]` |
| `-d` | 是目录 | `[[ -d /etc ]]` |
| `-L` / `-h` | 是符号链接 | `[[ -L /bin/sh ]]` |
| `-r` | 可读 | `[[ -r /etc/passwd ]]` |
| `-w` | 可写 | `[[ -w /tmp ]]` |
| `-x` | 可执行 | `[[ -x /bin/bash ]]` |
| `-s` | 文件大小 > 0 | `[[ -s /var/log/syslog ]]` |
| `-O` | 当前用户拥有 | `[[ -O ~/file ]]` |
| `-G` | 属于当前用户组 | `[[ -G ~/file ]]` |

### 3.2 文件比较操作符

| 操作符 | 含义 | 示例 |
|--------|------|------|
| `-nt` | 比另一个文件新（newer than） | `[[ file1 -nt file2 ]]` |
| `-ot` | 比另一个文件旧（older than） | `[[ file1 -ot file2 ]]` |
| `-ef` | 是同一个文件（硬链接） | `[[ file1 -ef file2 ]]` |

### 3.3 实战练习

```bash
cd ~/shell-lab/conditionals

cat > file_tests.sh << 'EOF'
#!/bin/bash
# 文件测试操作符大全演示

# 创建测试环境
TEST_DIR="/tmp/file_test_$$"
mkdir -p "$TEST_DIR"
cd "$TEST_DIR"

echo "测试目录: $TEST_DIR"
echo ""

# 创建各种测试文件
echo "Hello" > regular_file.txt
mkdir subdir
ln -s regular_file.txt symlink.txt
touch empty_file.txt
chmod 000 no_access.txt 2>/dev/null || touch no_access.txt && chmod 000 no_access.txt
chmod +x executable.sh 2>/dev/null || echo '#!/bin/bash' > executable.sh && chmod +x executable.sh

echo "=== 文件存在性测试 ==="
[[ -e regular_file.txt ]] && echo "-e: regular_file.txt 存在"
[[ -e nonexistent ]] || echo "-e: nonexistent 不存在"

echo ""
echo "=== 文件类型测试 ==="
[[ -f regular_file.txt ]] && echo "-f: regular_file.txt 是普通文件"
[[ -d subdir ]] && echo "-d: subdir 是目录"
[[ -L symlink.txt ]] && echo "-L: symlink.txt 是符号链接"

echo ""
echo "=== 文件大小测试 ==="
[[ -s regular_file.txt ]] && echo "-s: regular_file.txt 非空"
[[ -s empty_file.txt ]] || echo "-s: empty_file.txt 是空文件"

echo ""
echo "=== 权限测试 ==="
[[ -r regular_file.txt ]] && echo "-r: regular_file.txt 可读"
[[ -w regular_file.txt ]] && echo "-w: regular_file.txt 可写"
[[ -x executable.sh ]] && echo "-x: executable.sh 可执行"
[[ -r no_access.txt ]] || echo "-r: no_access.txt 不可读"

echo ""
echo "=== 文件比较测试 ==="
sleep 1
touch newer_file.txt
[[ newer_file.txt -nt regular_file.txt ]] && echo "-nt: newer_file.txt 比 regular_file.txt 新"

# 清理（可选，便于检查）
echo ""
echo "测试文件在: $TEST_DIR"
echo "清理命令: rm -rf $TEST_DIR"
EOF

chmod +x file_tests.sh
./file_tests.sh
```

### 3.4 运维实用模式

```bash
# 模式 1：检查配置文件存在
CONFIG="/etc/myapp/config.conf"
if [[ ! -f "$CONFIG" ]]; then
    echo "错误: 配置文件不存在: $CONFIG" >&2
    exit 1
fi

# 模式 2：检查目录存在，不存在则创建
LOG_DIR="/var/log/myapp"
if [[ ! -d "$LOG_DIR" ]]; then
    mkdir -p "$LOG_DIR"
    echo "创建日志目录: $LOG_DIR"
fi

# 模式 3：检查脚本是否以 root 运行
if [[ ! -w /etc/passwd ]]; then
    echo "此脚本需要 root 权限运行" >&2
    exit 1
fi

# 模式 4：检查命令是否存在
if [[ ! -x "$(command -v docker)" ]]; then
    echo "错误: 未安装 docker" >&2
    exit 1
fi
```

---

## Step 4 - 字符串测试（10 分钟）

### 4.1 字符串比较操作符

| 操作符 | 含义 | 示例 |
|--------|------|------|
| `=` / `==` | 相等 | `[[ "$a" == "$b" ]]` |
| `!=` | 不相等 | `[[ "$a" != "$b" ]]` |
| `-z` | 长度为零（空）| `[[ -z "$str" ]]` |
| `-n` | 长度非零（非空）| `[[ -n "$str" ]]` |
| `<` | 字典序小于（需 [[ ]]）| `[[ "$a" < "$b" ]]` |
| `>` | 字典序大于（需 [[ ]]）| `[[ "$a" > "$b" ]]` |

### 4.2 字符串测试实战

```bash
cd ~/shell-lab/conditionals

cat > string_tests.sh << 'EOF'
#!/bin/bash
# 字符串测试演示

echo "=== 空字符串测试 ==="

EMPTY=""
SPACE=" "
TEXT="hello"

# -z 测试空字符串
if [[ -z "$EMPTY" ]]; then
    echo "-z: EMPTY 是空字符串"
fi

if [[ -z "$SPACE" ]]; then
    echo "-z: SPACE 是空字符串"
else
    echo "-z: SPACE 不是空字符串（包含空格）"
fi

# -n 测试非空字符串
if [[ -n "$TEXT" ]]; then
    echo "-n: TEXT 非空"
fi

echo ""
echo "=== 字符串比较 ==="

STR1="apple"
STR2="banana"
STR3="apple"

if [[ "$STR1" == "$STR3" ]]; then
    echo "== : STR1 等于 STR3"
fi

if [[ "$STR1" != "$STR2" ]]; then
    echo "!= : STR1 不等于 STR2"
fi

if [[ "$STR1" < "$STR2" ]]; then
    echo "< : STR1 在字典序中排在 STR2 前面"
fi

echo ""
echo "=== 模式匹配（[[ ]] 专属）==="

FILENAME="report_2025_01.txt"

# 通配符匹配
if [[ "$FILENAME" == *.txt ]]; then
    echo "FILENAME 是 .txt 文件"
fi

if [[ "$FILENAME" == report_* ]]; then
    echo "FILENAME 以 report_ 开头"
fi

# 正则匹配
if [[ "$FILENAME" =~ ^report_[0-9]{4}_[0-9]{2}\.txt$ ]]; then
    echo "FILENAME 匹配日期格式正则"
fi

echo ""
echo "=== 常见陷阱 ==="

# 陷阱：未引用的空变量
MAYBE_EMPTY=""

# 错误写法（在 [ ] 中会报错）
# [ $MAYBE_EMPTY = "test" ]  # 错误！

# 正确写法
if [[ $MAYBE_EMPTY == "test" ]]; then
    echo "匹配"
else
    echo "不匹配（变量为空）"
fi
EOF

chmod +x string_tests.sh
./string_tests.sh
```

### 4.3 常见错误：引号问题

```bash
# 反模式：[ ] 中未引用变量
VAR=""
[ $VAR = "test" ]   # 错误！展开后变成 [ = "test" ]

# 正确做法
[ "$VAR" = "test" ]         # [ ] 中始终引用
[[ $VAR == "test" ]]        # [[ ]] 中可以不引用（但推荐引用）
[[ "$VAR" == "test" ]]      # 最安全的写法
```

---

## Step 5 - 数值比较（10 分钟）

### 5.1 数值比较操作符

**注意：数值比较使用特殊操作符，不是 `<` `>` `=`！**

| 操作符 | 含义 | 英文全称 |
|--------|------|----------|
| `-eq` | 等于 | equal |
| `-ne` | 不等于 | not equal |
| `-lt` | 小于 | less than |
| `-le` | 小于等于 | less or equal |
| `-gt` | 大于 | greater than |
| `-ge` | 大于等于 | greater or equal |

### 5.2 数值比较 vs 字符串比较

```bash
cd ~/shell-lab/conditionals

cat > number_vs_string.sh << 'EOF'
#!/bin/bash
# 数值比较 vs 字符串比较的区别

A="10"
B="9"

echo "A=$A, B=$B"
echo ""

echo "=== 数值比较（正确）==="
if [[ $A -gt $B ]]; then
    echo "-gt: $A 大于 $B（数值比较）"
fi

echo ""
echo "=== 字符串比较（可能不符合预期）==="
if [[ "$A" > "$B" ]]; then
    echo "> : $A 大于 $B（字符串比较）"
else
    echo "> : $A 不大于 $B（字符串比较）"
fi

# 解释：字符串比较是按字典序
# "10" 的第一个字符 '1' < '9'
# 所以字符串比较时 "10" < "9"

echo ""
echo "=== 更明显的例子 ==="
X="100"
Y="20"

echo "X=$X, Y=$Y"

if [[ $X -gt $Y ]]; then
    echo "-gt: $X > $Y（数值：正确）"
fi

if [[ "$X" > "$Y" ]]; then
    echo "> : $X > $Y（字符串）"
else
    echo "> : $X < $Y（字符串：因为 '1' < '2'）"
fi
EOF

chmod +x number_vs_string.sh
./number_vs_string.sh
```

### 5.3 (( )) 算术条件

Bash 提供 `(( ))` 进行算术运算和比较，语法更接近 C 语言：

```bash
cd ~/shell-lab/conditionals

cat > arithmetic_test.sh << 'EOF'
#!/bin/bash
# (( )) 算术条件演示

A=10
B=20

echo "A=$A, B=$B"
echo ""

# (( )) 中可以用常规比较符号
if (( A < B )); then
    echo "(( A < B )): $A 小于 $B"
fi

if (( A + 5 == 15 )); then
    echo "(( A + 5 == 15 )): 算术表达式成立"
fi

# (( )) 中变量不需要 $
if (( A >= 10 && B <= 20 )); then
    echo "(( A >= 10 && B <= 20 )): 多条件"
fi

# 实用示例：检查变量是否为数字
is_number() {
    local value="$1"
    if [[ "$value" =~ ^[0-9]+$ ]]; then
        return 0
    else
        return 1
    fi
}

VALUE="42"
if is_number "$VALUE" && (( VALUE > 0 )); then
    echo "$VALUE 是正整数"
fi

VALUE="abc"
if ! is_number "$VALUE"; then
    echo "$VALUE 不是数字"
fi

# 循环示例
echo ""
echo "=== 使用 (( )) 做计数器 ==="
count=0
while (( count < 5 )); do
    echo "计数: $count"
    (( count++ ))
done
EOF

chmod +x arithmetic_test.sh
./arithmetic_test.sh
```

---

## Step 6 - 逻辑运算（10 分钟）

### 6.1 逻辑运算符对比

| 语法环境 | AND | OR | NOT |
|----------|-----|-----|-----|
| `[ ]` | `-a` | `-o` | `!` |
| `[[ ]]` | `&&` | `\|\|` | `!` |
| 命令之间 | `&&` | `\|\|` | `!` |

### 6.2 实战演示

```bash
cd ~/shell-lab/conditionals

cat > logic_ops.sh << 'EOF'
#!/bin/bash
# 逻辑运算符演示

FILE="/etc/passwd"
VALUE=50

echo "FILE=$FILE, VALUE=$VALUE"
echo ""

echo "=== 方法 1：[ ] 中使用 -a/-o ==="
if [ -f "$FILE" -a -r "$FILE" ]; then
    echo "文件存在且可读（-a 方式）"
fi

echo ""
echo "=== 方法 2：[[ ]] 中使用 &&/|| ==="
if [[ -f "$FILE" && -r "$FILE" ]]; then
    echo "文件存在且可读（&& 方式）"
fi

echo ""
echo "=== 方法 3：多个 [[ ]] 用 && 连接 ==="
if [[ -f "$FILE" ]] && [[ -r "$FILE" ]]; then
    echo "文件存在且可读（独立测试）"
fi

echo ""
echo "=== 复杂条件 ==="
# 条件：文件存在 且 (值在 1-100 之间 或 值为 0)
if [[ -f "$FILE" ]] && { [[ $VALUE -ge 1 && $VALUE -le 100 ]] || [[ $VALUE -eq 0 ]]; }; then
    echo "复杂条件满足"
fi

echo ""
echo "=== NOT 运算 ==="
if [[ ! -d "$FILE" ]]; then
    echo "$FILE 不是目录"
fi

if ! grep -q "nonexistent" "$FILE" 2>/dev/null; then
    echo "文件中不包含 'nonexistent'"
fi
EOF

chmod +x logic_ops.sh
./logic_ops.sh
```

### 6.3 推荐写法

```bash
# 推荐：使用 [[ ]] 和 &&/||
if [[ -f "$FILE" && -r "$FILE" ]]; then
    process_file "$FILE"
fi

# 不推荐：使用 -a/-o（可读性差，易出错）
if [ -f "$FILE" -a -r "$FILE" ]; then
    process_file "$FILE"
fi
```

---

## Step 7 - case 语句（15 分钟）

`case` 语句用于模式匹配，比多个 `if-elif` 更清晰。

### 7.1 case 语句语法

```
case 表达式 in
    模式1)
        命令...
        ;;
    模式2 | 模式3)
        命令...
        ;;
    *)
        默认命令...
        ;;
esac
```

### 7.2 case 语句实战

```bash
cd ~/shell-lab/conditionals

cat > case_demo.sh << 'EOF'
#!/bin/bash
# case 语句演示

# 示例 1：处理用户输入
echo "=== 示例 1：处理用户选项 ==="
read -p "选择操作 (start/stop/restart/status): " ACTION

case "$ACTION" in
    start)
        echo "启动服务..."
        ;;
    stop)
        echo "停止服务..."
        ;;
    restart)
        echo "重启服务..."
        ;;
    status)
        echo "检查状态..."
        ;;
    *)
        echo "未知操作: $ACTION"
        echo "用法: start|stop|restart|status"
        ;;
esac

echo ""
echo "=== 示例 2：根据文件扩展名处理 ==="
process_file() {
    local file="$1"

    case "$file" in
        *.txt | *.md)
            echo "文本文件: $file"
            ;;
        *.sh | *.bash)
            echo "Shell 脚本: $file"
            ;;
        *.tar.gz | *.tgz)
            echo "压缩包: $file"
            ;;
        *.jpg | *.png | *.gif)
            echo "图片文件: $file"
            ;;
        *)
            echo "未知类型: $file"
            ;;
    esac
}

process_file "document.txt"
process_file "script.sh"
process_file "archive.tar.gz"
process_file "photo.jpg"
process_file "unknown.xyz"

echo ""
echo "=== 示例 3：使用通配符模式 ==="

RESPONSE="Yes"

case "$RESPONSE" in
    [Yy] | [Yy][Ee][Ss])
        echo "用户确认: 是"
        ;;
    [Nn] | [Nn][Oo])
        echo "用户确认: 否"
        ;;
    *)
        echo "无效响应: $RESPONSE"
        ;;
esac
EOF

chmod +x case_demo.sh
./case_demo.sh
```

### 7.3 运维常用模式：服务管理脚本

```bash
cd ~/shell-lab/conditionals

cat > service_script.sh << 'EOF'
#!/bin/bash
# 模拟服务管理脚本结构
# 这是日本 IT 企业中常见的運用スクリプト模式

SERVICE_NAME="myapp"
PID_FILE="/var/run/${SERVICE_NAME}.pid"

usage() {
    echo "用法: $0 {start|stop|restart|status}"
    exit 1
}

do_start() {
    echo "Starting $SERVICE_NAME..."
    # 实际启动逻辑
}

do_stop() {
    echo "Stopping $SERVICE_NAME..."
    # 实际停止逻辑
}

do_status() {
    echo "Checking $SERVICE_NAME status..."
    # 实际状态检查逻辑
}

# 主逻辑
case "${1:-}" in
    start)
        do_start
        ;;
    stop)
        do_stop
        ;;
    restart)
        do_stop
        sleep 1
        do_start
        ;;
    status)
        do_status
        ;;
    *)
        usage
        ;;
esac
EOF

chmod +x service_script.sh
./service_script.sh start
./service_script.sh status
./service_script.sh
```

---

## Step 8 - Mini Project：文件类型检测器（15 分钟）

综合运用所学知识，创建一个功能完整的文件类型检测器。

### 8.1 项目要求

创建脚本 `file_detector.sh`，要求：

1. 接受文件路径作为参数
2. 检测是文件、目录、链接还是其他
3. 报告权限信息（可读/可写/可执行）
4. 对于文本文件，显示行数
5. 通过 ShellCheck 零警告

### 8.2 参考实现

```bash
cd ~/shell-lab/conditionals

cat > file_detector.sh << 'EOF'
#!/bin/bash
# =============================================================================
# 脚本名称: file_detector.sh
# 功能说明: 检测文件类型并报告详细信息
# 作者: [你的名字]
# 创建日期: 2026-01-10
# =============================================================================
#
# 使用方法:
#   ./file_detector.sh <文件路径>
#   ./file_detector.sh /etc/passwd
#   ./file_detector.sh /etc
#
# =============================================================================

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 打印带颜色的消息
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 显示用法
usage() {
    echo "用法: $0 <文件路径>"
    echo ""
    echo "示例:"
    echo "  $0 /etc/passwd"
    echo "  $0 /etc"
    echo "  $0 /bin/bash"
    exit 1
}

# 检查权限
check_permissions() {
    local target="$1"
    local perms=""

    [[ -r "$target" ]] && perms+="可读 "
    [[ -w "$target" ]] && perms+="可写 "
    [[ -x "$target" ]] && perms+="可执行 "

    if [[ -z "$perms" ]]; then
        echo "无权限"
    else
        echo "$perms"
    fi
}

# 获取文件大小（跨平台）
get_size() {
    local target="$1"
    if stat --version &>/dev/null; then
        # GNU stat (Linux)
        stat -c %s "$target" 2>/dev/null
    else
        # BSD stat (macOS)
        stat -f %z "$target" 2>/dev/null
    fi
}

# 检测文件类型
detect_file_type() {
    local target="$1"

    if [[ -L "$target" ]]; then
        echo "符号链接"
    elif [[ -f "$target" ]]; then
        echo "普通文件"
    elif [[ -d "$target" ]]; then
        echo "目录"
    elif [[ -b "$target" ]]; then
        echo "块设备"
    elif [[ -c "$target" ]]; then
        echo "字符设备"
    elif [[ -p "$target" ]]; then
        echo "命名管道"
    elif [[ -S "$target" ]]; then
        echo "套接字"
    else
        echo "未知类型"
    fi
}

# 主函数
main() {
    # 检查参数
    if [[ $# -lt 1 ]]; then
        print_error "缺少文件路径参数"
        usage
    fi

    local target="$1"

    echo "============================================"
    echo "         文件类型检测报告"
    echo "============================================"
    echo ""

    # 检查是否存在
    if [[ ! -e "$target" && ! -L "$target" ]]; then
        print_error "目标不存在: $target"
        exit 1
    fi

    echo "目标路径: $target"
    echo ""

    # 文件类型
    local file_type
    file_type=$(detect_file_type "$target")
    print_info "文件类型: $file_type"

    # 根据类型显示不同信息
    case "$file_type" in
        "普通文件")
            local size
            size=$(get_size "$target")
            print_info "文件大小: $size 字节"

            # 检查是否是文本文件
            if file "$target" 2>/dev/null | grep -q "text"; then
                local lines
                lines=$(wc -l < "$target")
                print_info "文件行数: $lines"
            fi
            ;;
        "目录")
            local count
            count=$(ls -1A "$target" 2>/dev/null | wc -l)
            print_info "包含项目: $count 个"
            ;;
        "符号链接")
            local link_target
            link_target=$(readlink "$target")
            print_info "链接目标: $link_target"

            if [[ -e "$target" ]]; then
                print_success "链接有效"
            else
                print_warning "链接失效（目标不存在）"
            fi
            ;;
    esac

    # 权限信息
    echo ""
    print_info "权限状态: $(check_permissions "$target")"

    # 所有者信息
    if stat --version &>/dev/null; then
        # GNU stat
        print_info "所有者: $(stat -c '%U:%G' "$target" 2>/dev/null)"
        print_info "权限位: $(stat -c '%a' "$target" 2>/dev/null)"
    else
        # BSD stat
        print_info "所有者: $(stat -f '%Su:%Sg' "$target" 2>/dev/null)"
        print_info "权限位: $(stat -f '%Lp' "$target" 2>/dev/null)"
    fi

    echo ""
    echo "============================================"
}

# 执行主函数
main "$@"
EOF

chmod +x file_detector.sh

# ShellCheck 检查
echo "=== ShellCheck 检查 ==="
shellcheck file_detector.sh || echo "(请安装 shellcheck 进行检查)"

# 测试运行
echo ""
echo "=== 测试运行 ==="
./file_detector.sh /etc/passwd
echo ""
./file_detector.sh /etc
echo ""
./file_detector.sh /bin/bash
```

---

## 反模式：常见错误

### 错误 1：[ ] 中未引用变量

```bash
# 错误：空变量会导致语法错误
VAR=""
if [ $VAR = "test" ]; then    # 展开后变成 [ = "test" ]
    echo "匹配"
fi

# 正确：始终引用变量
if [ "$VAR" = "test" ]; then
    echo "匹配"
fi

# 或使用 [[ ]]
if [[ $VAR == "test" ]]; then
    echo "匹配"
fi
```

### 错误 2：使用 -a/-o 而不是 &&/||

```bash
# 不推荐：可读性差，容易出错
if [ -f "$FILE" -a -r "$FILE" -a ! -d "$FILE" ]; then
    echo "..."
fi

# 推荐：使用 [[ ]] 和 &&/||
if [[ -f "$FILE" && -r "$FILE" && ! -d "$FILE" ]]; then
    echo "..."
fi
```

### 错误 3：混淆数值和字符串比较

```bash
A="10"
B="9"

# 错误：字符串比较，结果可能不符合预期
if [[ "$A" > "$B" ]]; then    # 字典序："10" < "9" 因为 '1' < '9'
    echo "$A > $B"
fi

# 正确：数值比较
if [[ $A -gt $B ]]; then
    echo "$A > $B"
fi
```

### 错误 4：= 两边缺少空格

```bash
# 错误：被解释为赋值而非比较
if [ "$VAR"="test" ]; then    # 总是为真！
    echo "匹配"
fi

# 正确：= 两边有空格
if [ "$VAR" = "test" ]; then
    echo "匹配"
fi
```

---

## 职场小贴士（Japan IT Context）

### 运维脚本中的条件判断

在日本 IT 企业的运维现场（運用現場），条件判断常用于：

| 日语术语 | 含义 | 典型用法 |
|----------|------|----------|
| 前提条件チェック | 前提条件检查 | 脚本开始时检查环境 |
| ファイル存在確認 | 文件存在确认 | 处理前确认输入文件 |
| 権限チェック | 权限检查 | 确保有操作权限 |
| 戻り値判定 | 返回值判定 | 检查命令是否成功 |

### 典型的日本企业脚本模式

```bash
#!/bin/bash
# =============================================================================
# スクリプト名: check_system.sh
# 概要: システム状態チェック
# 作成者: 田中太郎
# 作成日: 2026-01-10
# =============================================================================

# 前提条件チェック
check_prerequisites() {
    # root 権限チェック
    if [[ $EUID -ne 0 ]]; then
        echo "[ERROR] root 権限が必要です" >&2
        exit 1
    fi

    # 必要コマンド存在確認
    for cmd in df free top; do
        if ! command -v "$cmd" &>/dev/null; then
            echo "[ERROR] $cmd コマンドが見つかりません" >&2
            exit 1
        fi
    done

    echo "[OK] 前提条件チェック完了"
}

# ディスク使用率チェック
check_disk() {
    local threshold=80
    local usage
    usage=$(df -h / | awk 'NR==2 {print $5}' | tr -d '%')

    if [[ $usage -gt $threshold ]]; then
        echo "[WARN] ディスク使用率が ${usage}% です（閾値: ${threshold}%）"
        return 1
    else
        echo "[OK] ディスク使用率: ${usage}%"
        return 0
    fi
}

# メイン処理
main() {
    check_prerequisites
    check_disk
}

main "$@"
```

---

## 检查清单

完成本课后，你应该能够：

- [ ] 编写 if/elif/else/fi 条件语句
- [ ] 解释 test、`[ ]`、`[[ ]]` 的区别和使用场景
- [ ] 使用文件测试操作符（-f, -d, -e, -r, -w, -x）
- [ ] 使用字符串测试操作符（=, !=, -z, -n）
- [ ] 正确使用数值比较操作符（-eq, -ne, -lt, -gt）
- [ ] 使用 `(( ))` 进行算术条件判断
- [ ] 使用 `&&`、`||`、`!` 进行逻辑运算
- [ ] 使用 case 语句处理多分支模式匹配
- [ ] 避免常见的条件判断反模式

---

## 本课小结

| 概念 | 要点 |
|------|------|
| if 语法 | `if [[ 条件 ]]; then ... elif ... else ... fi` |
| 退出码 | 0 = 真/成功，非 0 = 假/失败 |
| `[ ]` vs `[[ ]]` | `[[ ]]` 更安全，支持模式匹配和正则 |
| 文件测试 | `-f`（文件）、`-d`（目录）、`-e`（存在）、`-r`/`-w`/`-x`（权限）|
| 字符串测试 | `=`/`==`、`!=`、`-z`（空）、`-n`（非空）|
| 数值比较 | `-eq`、`-ne`、`-lt`、`-gt`、`-le`、`-ge` |
| 逻辑运算 | `&&`（与）、`||`（或）、`!`（非）|
| case 语句 | 模式匹配，用 `;;` 结束每个分支 |

---

## 面试准备

### [ ] と [[ ]] の違いは？

`[ ]` は `test` コマンドのシノニムで、POSIX 準拠ですが、変数のクォートが必須です。`[[ ]]` は Bash 拡張で、変数のクォートが不要、`&&`/`||` が使用可能、パターンマッチングと正則表現（`=~`）をサポートします。Bash スクリプトでは `[[ ]]` の使用を推奨します。

### 文字列比較と数値比較の違いは？

文字列比較は `=`、`!=`、`<`、`>` を使用し、辞書順で比較します。数値比較は `-eq`、`-ne`、`-lt`、`-gt`、`-le`、`-ge` を使用します。例えば、文字列として `"10" < "9"`（'1' < '9'）ですが、数値として `10 -gt 9` です。間違えると予期しない動作になります。

---

## 延伸阅读

- [GNU Bash Manual - Conditional Constructs](https://www.gnu.org/software/bash/manual/html_node/Conditional-Constructs.html)
- [Bash Reference Manual - Bash Conditional Expressions](https://www.gnu.org/software/bash/manual/html_node/Bash-Conditional-Expressions.html)
- [ShellCheck Wiki](https://github.com/koalaman/shellcheck/wiki)
- 下一课：[05 - 循环结构](../05-loops/) - 掌握 for、while、until 循环
- 相关课程：[LX03 - 引用规则](../03-quoting/) - 变量引用的重要性

---

## 系列导航

[<- 03 - 引用规则](../03-quoting/) | [课程首页](../) | [05 - 循环结构 ->](../05-loops/)
