# 06 - 函数（Functions）

> **目标**：掌握函数封装与复用，创建可维护的日志函数库  
> **前置**：[05 - 循环结构](../05-loops/)  
> **时间**：90-120 分钟  
> **环境**：Bash 4.x+（RHEL 7/8/9, Ubuntu 18.04+ 均可）  

---

## 将学到的内容

1. 定义和调用函数
2. 理解函数参数（$1, $2, $@, $#）
3. 使用 local 声明局部变量
4. 函数返回值：exit code vs 输出捕获
5. 创建可复用的函数库

---

## 先跑起来！（5 分钟）

> 在理解原理之前，先让函数跑起来。  
> 体验从定义到调用的完整过程。  

```bash
# 创建练习目录
mkdir -p ~/function-lab && cd ~/function-lab

# 创建你的第一个函数脚本
cat > first-function.sh << 'EOF'
#!/bin/bash
# 我的第一个函数

# 定义一个简单的问候函数
greet() {
    echo "你好，$1！现在是 $(date +%H:%M)"
}

# 定义一个计算函数
add() {
    local sum=$(( $1 + $2 ))
    echo "$sum"
}

# 调用函数
greet "运维工程师"
result=$(add 10 20)
echo "10 + 20 = $result"
EOF

# 运行它！
bash first-function.sh
```

**你应该看到类似的输出：**

```
你好，运维工程师！现在是 14:30
10 + 20 = 30
```

**恭喜！你刚刚创建并使用了 Shell 函数！**

函数是脚本模块化的基础——把重复代码封装成函数，让脚本更易维护、更易复用。

现在让我们深入理解函数的各个方面。

---

## Step 1 — 函数定义语法（15 分钟）

### 1.1 两种定义方式

Shell 函数有两种定义语法，都是有效的：

```bash
cd ~/function-lab

cat > define-syntax.sh << 'EOF'
#!/bin/bash

# 方式 1：使用 function 关键字（Bash 风格）
function say_hello() {
    echo "Hello from function keyword!"
}

# 方式 2：不使用 function 关键字（POSIX 兼容）
say_bye() {
    echo "Bye from POSIX style!"
}

# 调用两种方式定义的函数
say_hello
say_bye
EOF

bash define-syntax.sh
```

![Function Definition Syntax](images/function-syntax.png)

<details>
<summary>View ASCII source</summary>

<!-- DIAGRAM: function-syntax -->
```
┌─────────────────────────────────────────────────────────────────┐
│  函数定义语法对比                                                 │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  方式 1：Bash 风格（推荐）                                        │
│  ┌─────────────────────────────────────────────┐                │
│  │  function 函数名() {                         │                │
│  │      命令1                                   │                │
│  │      命令2                                   │                │
│  │      ...                                    │                │
│  │  }                                          │                │
│  └─────────────────────────────────────────────┘                │
│                                                                  │
│  方式 2：POSIX 风格（兼容 sh）                                    │
│  ┌─────────────────────────────────────────────┐                │
│  │  函数名() {                                  │                │
│  │      命令1                                   │                │
│  │      命令2                                   │                │
│  │      ...                                    │                │
│  │  }                                          │                │
│  └─────────────────────────────────────────────┘                │
│                                                                  │
│  注意：                                                          │
│  - 花括号 { } 与函数体之间要有空格或换行                          │
│  - 函数名后的 () 内不放参数                                       │
│  - 调用时不需要 ()                                               │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```
<!-- /DIAGRAM -->

</details>

### 1.2 哪种风格更好？

| 风格 | 语法 | 优点 | 缺点 |
|------|------|------|------|
| Bash | `function name() { }` | 明确是函数，可读性好 | 仅 Bash 支持 |
| POSIX | `name() { }` | 兼容 sh、dash | 不如 `function` 明显 |

**推荐**：在 Bash 脚本中使用 `function` 关键字，提高可读性。

### 1.3 函数定义的关键点

```bash
# 正确：函数名后有空格
function my_func() {
    echo "OK"
}

# 正确：单行定义需要分号
my_func2() { echo "OK"; }

# 错误：花括号前没有空格
# my_func3(){ echo "ERROR" }  # 语法错误！
```

> **记住**：函数必须在调用之前定义。Shell 脚本是顺序执行的。  

---

## Step 2 — 函数参数（20 分钟）

### 2.1 位置参数

函数内部使用 `$1`, `$2`, ... 获取传入的参数，与脚本参数相同：

![Function Parameters](images/function-params.png)

<details>
<summary>View ASCII source</summary>

<!-- DIAGRAM: function-params -->
```
┌─────────────────────────────────────────────────────────────────┐
│  函数参数                                                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  调用：my_func "arg1" "arg2" "arg3"                              │
│                 │       │       │                                │
│                 ▼       ▼       ▼                                │
│  函数内部：    $1      $2      $3                                │
│                                                                  │
│  特殊变量：                                                      │
│  ┌─────────┬────────────────────────────────────────┐           │
│  │ 变量    │ 含义                                    │           │
│  ├─────────┼────────────────────────────────────────┤           │
│  │ $1-$9   │ 第 1-9 个参数                          │           │
│  │ ${10}+  │ 第 10 个及以后（需要花括号）            │           │
│  │ $#      │ 参数个数                               │           │
│  │ $@      │ 所有参数（保持分隔，推荐）              │           │
│  │ $*      │ 所有参数（合并为一个字符串）            │           │
│  │ $0      │ 脚本名称（不是函数名！）                │           │
│  └─────────┴────────────────────────────────────────┘           │
│                                                                  │
│  注意：$@ 和 $* 的区别在引号内才体现                              │
│  - "$@" → "arg1" "arg2" "arg3"  （各自独立）                    │
│  - "$*" → "arg1 arg2 arg3"       （合并为一个）                  │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```
<!-- /DIAGRAM -->

</details>

### 2.2 参数使用示例

```bash
cd ~/function-lab

cat > params-demo.sh << 'EOF'
#!/bin/bash

# 演示函数参数的使用
function show_params() {
    echo "=== 函数参数演示 ==="
    echo "第一个参数 (\$1): $1"
    echo "第二个参数 (\$2): $2"
    echo "参数个数 (\$#): $#"
    echo "所有参数 (\$@): $@"
    echo ""

    # 遍历所有参数
    echo "遍历所有参数："
    local i=1
    for arg in "$@"; do
        echo "  参数 $i: $arg"
        ((i++))
    done
}

# 测试调用
show_params "Hello" "World" "Shell" "Function"
EOF

bash params-demo.sh
```

**输出：**

```
=== 函数参数演示 ===
第一个参数 ($1): Hello
第二个参数 ($2): World
参数个数 ($#): 4
所有参数 ($@): Hello World Shell Function

遍历所有参数：
  参数 1: Hello
  参数 2: World
  参数 3: Shell
  参数 4: Function
```

### 2.3 参数验证

生产级脚本需要验证参数：

```bash
cd ~/function-lab

cat > validate-params.sh << 'EOF'
#!/bin/bash

# 带参数验证的函数
function create_backup() {
    # 参数验证
    if [[ $# -lt 2 ]]; then
        echo "错误: 需要两个参数" >&2
        echo "用法: create_backup <源目录> <备份目录>" >&2
        return 1
    fi

    local source_dir="$1"
    local backup_dir="$2"

    # 验证源目录存在
    if [[ ! -d "$source_dir" ]]; then
        echo "错误: 源目录不存在: $source_dir" >&2
        return 2
    fi

    # 创建备份目录（如果不存在）
    if [[ ! -d "$backup_dir" ]]; then
        mkdir -p "$backup_dir" || return 3
    fi

    # 执行备份
    local backup_name="backup_$(date +%Y%m%d_%H%M%S).tar.gz"
    tar -czf "$backup_dir/$backup_name" -C "$(dirname "$source_dir")" "$(basename "$source_dir")"

    echo "备份完成: $backup_dir/$backup_name"
    return 0
}

# 测试
create_backup /etc /tmp/backups
echo "返回码: $?"

# 测试错误情况
create_backup
echo "返回码: $?"
EOF

bash validate-params.sh
```

---

## Step 3 — 局部变量 local（15 分钟）

### 3.1 为什么需要 local？

**问题演示**：不使用 local 会污染全局作用域

```bash
cd ~/function-lab

cat > without-local.sh << 'EOF'
#!/bin/bash

# 全局变量
name="全局的名字"

# 函数不使用 local
function bad_function() {
    name="函数内修改的名字"  # 修改了全局变量！
    temp="临时变量"          # 泄漏到全局！
}

echo "调用前: name = $name"
bad_function
echo "调用后: name = $name"      # 被修改了！
echo "调用后: temp = $temp"      # 变量泄漏！
EOF

bash without-local.sh
```

**输出：**

```
调用前: name = 全局的名字
调用后: name = 函数内修改的名字
调用后: temp = 临时变量
```

### 3.2 使用 local 声明局部变量

![Variable Scope](images/variable-scope.png)

<details>
<summary>View ASCII source</summary>

<!-- DIAGRAM: variable-scope -->
```
┌─────────────────────────────────────────────────────────────────┐
│  变量作用域                                                      │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  全局作用域                                                      │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  name="全局"                                             │   │
│  │  count=0                                                 │   │
│  │                                                          │   │
│  │  ┌─────────────────────────────────────────────┐        │   │
│  │  │  函数作用域（使用 local）                    │        │   │
│  │  │                                              │        │   │
│  │  │  local temp="临时"  ← 只在函数内可见         │        │   │
│  │  │  local name="局部"  ← 遮蔽全局的 name        │        │   │
│  │  │                                              │        │   │
│  │  │  count=$((count+1)) ← 修改全局变量           │        │   │
│  │  │                                              │        │   │
│  │  └─────────────────────────────────────────────┘        │   │
│  │                                                          │   │
│  │  # 函数返回后                                            │   │
│  │  # temp 不存在                                           │   │
│  │  # name 仍是"全局"                                       │   │
│  │  # count 已被修改                                        │   │
│  │                                                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                  │
│  黄金法则：函数内的变量，除非特意要修改全局，否则都用 local      │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```
<!-- /DIAGRAM -->

</details>

```bash
cd ~/function-lab

cat > with-local.sh << 'EOF'
#!/bin/bash

# 全局变量
name="全局的名字"

# 函数使用 local
function good_function() {
    local name="函数内的名字"   # 不影响全局
    local temp="临时变量"       # 函数结束后自动消失

    echo "函数内: name = $name"
    echo "函数内: temp = $temp"
}

echo "调用前: name = $name"
good_function
echo "调用后: name = $name"      # 未被修改！
echo "调用后: temp = ${temp:-未定义}"  # 不存在！
EOF

bash with-local.sh
```

**输出：**

```
调用前: name = 全局的名字
函数内: name = 函数内的名字
函数内: temp = 临时变量
调用后: name = 全局的名字
调用后: temp = 未定义
```

### 3.3 local 最佳实践

```bash
# 好的习惯：在函数开头声明所有局部变量
function process_file() {
    local file="$1"
    local line_count
    local status=0

    # 声明和赋值分开（避免掩盖命令替换的退出码）
    local content
    content=$(cat "$file") || return 1

    line_count=$(wc -l < "$file")
    echo "文件 $file 有 $line_count 行"

    return $status
}
```

> **注意**：`local var=$(command)` 会掩盖 command 的退出码，因为 local 本身总是成功的。  
> 所以建议分开写：先 `local var`，再 `var=$(command)`。  

---

## Step 4 — 返回值：exit code vs 输出捕获（20 分钟）

### 4.1 两种"返回"方式

Shell 函数有两种返回值机制，理解区别非常重要：

![Return Value vs Output](images/return-vs-output.png)

<details>
<summary>View ASCII source</summary>

<!-- DIAGRAM: return-vs-output -->
```
┌─────────────────────────────────────────────────────────────────┐
│  函数返回值的两种方式                                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  1. return - 返回退出码（Exit Code）                             │
│  ┌─────────────────────────────────────────────┐                │
│  │  function check_file() {                    │                │
│  │      if [[ -f "$1" ]]; then                 │                │
│  │          return 0    # 成功                 │                │
│  │      else                                   │                │
│  │          return 1    # 失败                 │                │
│  │      fi                                     │                │
│  │  }                                          │                │
│  │                                             │                │
│  │  调用方式：                                  │                │
│  │  check_file "/etc/passwd"                   │                │
│  │  if [[ $? -eq 0 ]]; then ...               │                │
│  │  # 或者                                     │                │
│  │  if check_file "/etc/passwd"; then ...     │                │
│  └─────────────────────────────────────────────┘                │
│                                                                  │
│  特点：                                                          │
│  - 只能返回 0-255 的整数                                         │
│  - 0 表示成功，非 0 表示各种错误                                 │
│  - 通过 $? 获取，或用于 if 判断                                  │
│                                                                  │
│  2. echo - 输出数据（Output Capture）                            │
│  ┌─────────────────────────────────────────────┐                │
│  │  function get_hostname() {                  │                │
│  │      echo "$(hostname)"                     │                │
│  │  }                                          │                │
│  │                                             │                │
│  │  function calculate() {                     │                │
│  │      local result=$(( $1 + $2 ))            │                │
│  │      echo "$result"                         │                │
│  │  }                                          │                │
│  │                                             │                │
│  │  调用方式：                                  │                │
│  │  name=$(get_hostname)                       │                │
│  │  sum=$(calculate 10 20)                     │                │
│  └─────────────────────────────────────────────┘                │
│                                                                  │
│  特点：                                                          │
│  - 可以返回任意字符串、数字、多行文本                            │
│  - 通过命令替换 $() 捕获                                         │
│  - 函数内其他 echo 也会被捕获（注意！）                          │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```
<!-- /DIAGRAM -->

</details>

### 4.2 return 用于状态码

```bash
cd ~/function-lab

cat > return-demo.sh << 'EOF'
#!/bin/bash

# return 返回退出码（0-255）
function is_root() {
    if [[ $(id -u) -eq 0 ]]; then
        return 0   # 是 root
    else
        return 1   # 不是 root
    fi
}

# 定义返回码常量（好习惯）
readonly SUCCESS=0
readonly ERR_NOT_FOUND=1
readonly ERR_PERMISSION=2
readonly ERR_INVALID_ARG=3

function check_file() {
    local file="$1"

    if [[ -z "$file" ]]; then
        echo "错误: 未提供文件名" >&2
        return $ERR_INVALID_ARG
    fi

    if [[ ! -e "$file" ]]; then
        echo "错误: 文件不存在: $file" >&2
        return $ERR_NOT_FOUND
    fi

    if [[ ! -r "$file" ]]; then
        echo "错误: 无读取权限: $file" >&2
        return $ERR_PERMISSION
    fi

    return $SUCCESS
}

# 使用 if 判断函数返回值
if is_root; then
    echo "当前是 root 用户"
else
    echo "当前不是 root 用户"
fi

# 使用 $? 获取返回码
check_file "/etc/passwd"
case $? in
    $SUCCESS)        echo "文件检查通过" ;;
    $ERR_NOT_FOUND)  echo "处理文件不存在的情况" ;;
    $ERR_PERMISSION) echo "处理权限不足的情况" ;;
    $ERR_INVALID_ARG) echo "处理参数错误的情况" ;;
esac
EOF

bash return-demo.sh
```

### 4.3 echo 用于输出数据

```bash
cd ~/function-lab

cat > output-demo.sh << 'EOF'
#!/bin/bash

# echo 输出数据，用 $() 捕获
function get_timestamp() {
    echo "$(date '+%Y-%m-%d %H:%M:%S')"
}

function get_file_size() {
    local file="$1"
    if [[ -f "$file" ]]; then
        stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null
    else
        echo "0"
    fi
}

function get_largest_file() {
    local dir="${1:-.}"
    # 返回最大文件的路径
    find "$dir" -maxdepth 1 -type f -exec ls -s {} \; 2>/dev/null | \
        sort -n -r | head -1 | awk '{print $2}'
}

# 捕获函数输出
timestamp=$(get_timestamp)
echo "当前时间: $timestamp"

size=$(get_file_size "/etc/passwd")
echo "/etc/passwd 大小: $size 字节"

largest=$(get_largest_file /etc)
echo "/etc 中最大的文件: $largest"
EOF

bash output-demo.sh
```

### 4.4 常见错误：用 return 返回字符串

```bash
cd ~/function-lab

cat > return-mistake.sh << 'EOF'
#!/bin/bash

# 错误示范：用 return 返回字符串
function bad_get_name() {
    return "Alice"    # 错误！return 只接受数字
}

# 正确做法：用 echo 输出字符串
function good_get_name() {
    echo "Alice"
}

# 测试错误用法
bad_get_name
echo "bad_get_name 返回: $?"  # 会显示 0 或奇怪的数字

# 测试正确用法
name=$(good_get_name)
echo "good_get_name 返回: $name"
EOF

bash return-mistake.sh 2>&1
```

**输出：**

```
return-mistake.sh: line 5: return: Alice: numeric argument required
bad_get_name 返回: 2
good_get_name 返回: Alice
```

### 4.5 组合使用：同时返回状态和数据

```bash
cd ~/function-lab

cat > combined-return.sh << 'EOF'
#!/bin/bash

# 最佳实践：用 return 返回状态，用 echo 返回数据
function get_user_info() {
    local username="$1"

    # 检查用户是否存在
    if ! id "$username" &>/dev/null; then
        echo ""
        return 1
    fi

    # 返回用户信息
    local uid=$(id -u "$username")
    local gid=$(id -g "$username")
    echo "$username:$uid:$gid"
    return 0
}

# 调用并检查
if info=$(get_user_info "root"); then
    echo "用户信息: $info"
    IFS=':' read -r name uid gid <<< "$info"
    echo "  用户名: $name"
    echo "  UID: $uid"
    echo "  GID: $gid"
else
    echo "用户不存在"
fi

# 测试不存在的用户
if info=$(get_user_info "nonexistent_user_12345"); then
    echo "用户信息: $info"
else
    echo "用户 nonexistent_user_12345 不存在"
fi
EOF

bash combined-return.sh
```

---

## Step 5 — 函数库模式（15 分钟）

### 5.1 创建可复用的函数库

把常用函数放到单独文件中，其他脚本通过 `source` 引入：

```bash
cd ~/function-lab

# 创建函数库目录
mkdir -p lib

# 创建日志函数库
cat > lib/logging.sh << 'EOF'
#!/bin/bash
# =============================================================================
# 文件名：logging.sh
# 功能：日志记录函数库
# 用法：source /path/to/lib/logging.sh
# =============================================================================

# 日志级别
declare -g LOG_LEVEL="${LOG_LEVEL:-INFO}"

# 日志级别数值（用于比较）
declare -gA _LOG_LEVELS=(
    [DEBUG]=0
    [INFO]=1
    [WARN]=2
    [ERROR]=3
)

# 颜色定义
declare -g _COLOR_RESET='\033[0m'
declare -g _COLOR_DEBUG='\033[36m'   # 青色
declare -g _COLOR_INFO='\033[32m'    # 绿色
declare -g _COLOR_WARN='\033[33m'    # 黄色
declare -g _COLOR_ERROR='\033[31m'   # 红色

# 获取调用者信息
function _get_caller() {
    echo "${BASH_SOURCE[2]##*/}:${BASH_LINENO[1]}"
}

# 内部日志函数
function _log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local caller
    caller=$(_get_caller)

    # 检查日志级别
    local current_level=${_LOG_LEVELS[$LOG_LEVEL]:-1}
    local msg_level=${_LOG_LEVELS[$level]:-1}

    if [[ $msg_level -lt $current_level ]]; then
        return 0
    fi

    # 选择颜色
    local color
    case "$level" in
        DEBUG) color="$_COLOR_DEBUG" ;;
        INFO)  color="$_COLOR_INFO" ;;
        WARN)  color="$_COLOR_WARN" ;;
        ERROR) color="$_COLOR_ERROR" ;;
        *)     color="$_COLOR_RESET" ;;
    esac

    # 输出日志
    if [[ -t 2 ]]; then
        # 终端输出：带颜色
        printf "${color}[%s] [%-5s] [%s] %s${_COLOR_RESET}\n" \
            "$timestamp" "$level" "$caller" "$message" >&2
    else
        # 非终端（重定向到文件）：无颜色
        printf "[%s] [%-5s] [%s] %s\n" \
            "$timestamp" "$level" "$caller" "$message" >&2
    fi
}

# 公开的日志函数
function log_debug() {
    _log DEBUG "$@"
}

function log_info() {
    _log INFO "$@"
}

function log_warn() {
    _log WARN "$@"
}

function log_error() {
    _log ERROR "$@"
}

# 设置日志级别
function set_log_level() {
    local level="${1^^}"  # 转大写
    if [[ -n "${_LOG_LEVELS[$level]}" ]]; then
        LOG_LEVEL="$level"
        log_debug "Log level set to: $level"
    else
        log_error "Invalid log level: $1 (valid: DEBUG, INFO, WARN, ERROR)"
        return 1
    fi
}
EOF
```

### 5.2 使用函数库

```bash
cd ~/function-lab

cat > use-logging.sh << 'EOF'
#!/bin/bash
# 使用日志函数库的示例脚本

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 引入函数库
source "$SCRIPT_DIR/lib/logging.sh"

# 使用日志函数
log_info "程序启动"
log_debug "这条在 INFO 级别不会显示"

set_log_level DEBUG
log_debug "现在这条会显示了"

log_warn "这是一个警告"
log_error "这是一个错误"

log_info "程序结束"
EOF

bash use-logging.sh
```

**输出：**

```
[2026-01-10 14:30:00] [INFO ] [use-logging.sh:10] 程序启动
[2026-01-10 14:30:00] [DEBUG] [use-logging.sh:14] Log level set to: DEBUG
[2026-01-10 14:30:00] [DEBUG] [use-logging.sh:15] 现在这条会显示了
[2026-01-10 14:30:00] [WARN ] [use-logging.sh:17] 这是一个警告
[2026-01-10 14:30:00] [ERROR] [use-logging.sh:18] 这是一个错误
[2026-01-10 14:30:00] [INFO ] [use-logging.sh:20] 程序结束
```

### 5.3 函数库最佳实践

```bash
# 1. 防止重复加载
if [[ -n "${_LOGGING_SH_LOADED:-}" ]]; then
    return 0
fi
declare -g _LOGGING_SH_LOADED=1

# 2. 检查依赖
function _check_dependencies() {
    local deps=("date" "printf")
    for cmd in "${deps[@]}"; do
        if ! command -v "$cmd" &>/dev/null; then
            echo "错误: 缺少依赖命令: $cmd" >&2
            return 1
        fi
    done
}
_check_dependencies || return 1

# 3. 使用命名前缀避免冲突
function mylib_init() { ... }
function mylib_cleanup() { ... }
```

---

## Step 6 — Mini Project：日志函数库（20 分钟）

> **项目目标**：创建一个完整的、可在生产环境使用的日志函数库。  

### 6.1 项目要求

创建 `lib/logger.sh`，包含：

1. `log_info`, `log_error`, `log_debug`, `log_warn` 函数
2. 支持日志级别控制（环境变量 `LOG_LEVEL`）
3. 支持输出到文件（环境变量 `LOG_FILE`）
4. 包含时间戳和调用位置
5. 通过 ShellCheck 检查

### 6.2 完整实现

```bash
cd ~/function-lab

cat > lib/logger.sh << 'EOF'
#!/bin/bash
# =============================================================================
# 文件名：logger.sh
# 功能：生产级日志函数库
# 版本：1.0.0
# =============================================================================
#
# 使用方法：
#   source /path/to/lib/logger.sh
#
# 环境变量：
#   LOG_LEVEL  - 日志级别 (DEBUG, INFO, WARN, ERROR)，默认 INFO
#   LOG_FILE   - 日志文件路径，不设置则只输出到 stderr
#   LOG_FORMAT - 日志格式 (simple, full)，默认 full
#
# 示例：
#   LOG_LEVEL=DEBUG LOG_FILE=/var/log/myapp.log source logger.sh
#   log_info "Application started"
#
# =============================================================================

# 防止重复加载
if [[ -n "${_LOGGER_SH_LOADED:-}" ]]; then
    return 0
fi
declare -g _LOGGER_SH_LOADED=1

# 配置（可通过环境变量覆盖）
declare -g LOG_LEVEL="${LOG_LEVEL:-INFO}"
declare -g LOG_FILE="${LOG_FILE:-}"
declare -g LOG_FORMAT="${LOG_FORMAT:-full}"

# 日志级别数值
declare -gA _LOG_LEVEL_VALUES=(
    [DEBUG]=0
    [INFO]=1
    [WARN]=2
    [ERROR]=3
)

# 颜色（仅终端输出时使用）
declare -g _C_RESET='\033[0m'
declare -g _C_DEBUG='\033[36m'
declare -g _C_INFO='\033[32m'
declare -g _C_WARN='\033[33m'
declare -g _C_ERROR='\033[31m'

# 核心日志函数
function _logger_log() {
    local level="$1"
    shift
    local message="$*"

    # 级别过滤
    local current=${_LOG_LEVEL_VALUES[${LOG_LEVEL^^}]:-1}
    local target=${_LOG_LEVEL_VALUES[$level]:-1}
    if (( target < current )); then
        return 0
    fi

    # 时间戳
    local ts
    ts=$(date '+%Y-%m-%d %H:%M:%S')

    # 调用位置
    local caller="${BASH_SOURCE[2]##*/}:${BASH_LINENO[1]}"

    # 格式化消息
    local formatted
    if [[ "$LOG_FORMAT" == "simple" ]]; then
        formatted="[$level] $message"
    else
        formatted="[$ts] [$level] [$caller] $message"
    fi

    # 输出到 stderr（带颜色）
    if [[ -t 2 ]]; then
        local color
        case "$level" in
            DEBUG) color="$_C_DEBUG" ;;
            INFO)  color="$_C_INFO" ;;
            WARN)  color="$_C_WARN" ;;
            ERROR) color="$_C_ERROR" ;;
            *)     color="$_C_RESET" ;;
        esac
        printf "%b%s%b\n" "$color" "$formatted" "$_C_RESET" >&2
    else
        printf "%s\n" "$formatted" >&2
    fi

    # 输出到文件（无颜色）
    if [[ -n "$LOG_FILE" ]]; then
        printf "%s\n" "$formatted" >> "$LOG_FILE"
    fi
}

# 公开接口
function log_debug() {
    _logger_log DEBUG "$@"
}

function log_info() {
    _logger_log INFO "$@"
}

function log_warn() {
    _logger_log WARN "$@"
}

function log_error() {
    _logger_log ERROR "$@"
}

# 辅助函数
function logger_set_level() {
    local level="${1^^}"
    if [[ -n "${_LOG_LEVEL_VALUES[$level]:-}" ]]; then
        LOG_LEVEL="$level"
    else
        log_error "Invalid log level: $1"
        return 1
    fi
}

function logger_set_file() {
    local file="$1"
    local dir
    dir=$(dirname "$file")

    if [[ ! -d "$dir" ]]; then
        mkdir -p "$dir" || {
            log_error "Cannot create log directory: $dir"
            return 1
        }
    fi

    LOG_FILE="$file"
    log_debug "Log file set to: $file"
}
EOF
```

### 6.3 测试日志库

```bash
cd ~/function-lab

cat > test-logger.sh << 'EOF'
#!/bin/bash
# 测试日志函数库

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/logger.sh"

echo "=== 测试 1: 默认配置 ==="
log_info "这是 INFO 消息"
log_debug "这是 DEBUG 消息（默认不显示）"
log_warn "这是 WARN 消息"
log_error "这是 ERROR 消息"

echo ""
echo "=== 测试 2: 设置 DEBUG 级别 ==="
logger_set_level DEBUG
log_debug "现在 DEBUG 消息会显示"

echo ""
echo "=== 测试 3: 输出到文件 ==="
logger_set_file "/tmp/test-logger.log"
log_info "这条会同时写入文件"
echo "文件内容:"
cat /tmp/test-logger.log

echo ""
echo "=== 测试 4: ShellCheck ==="
shellcheck "$SCRIPT_DIR/lib/logger.sh" && echo "ShellCheck 通过！"
EOF

bash test-logger.sh
```

---

## 反模式：常见错误

### 错误 1：不使用 local（变量污染）

```bash
# 错误：变量泄漏到全局
function process_data() {
    result="处理结果"     # 污染全局！
    temp_file="/tmp/temp" # 污染全局！
}

# 正确：使用 local
function process_data() {
    local result="处理结果"
    local temp_file="/tmp/temp"
    echo "$result"
}
```

### 错误 2：用 return 返回字符串

```bash
# 错误：return 只接受 0-255 的数字
function get_name() {
    return "Alice"  # 语法错误！
}

# 正确：用 echo 输出字符串
function get_name() {
    echo "Alice"
}
name=$(get_name)
```

### 错误 3：函数名覆盖系统命令

```bash
# 危险：覆盖了 test 命令！
function test() {
    echo "My test function"
}

# 现在 [ -f file ] 和 test -f file 都不工作了！

# 安全：使用有意义的前缀
function myapp_test() {
    echo "My test function"
}
```

### 错误 4：函数内 echo 被意外捕获

```bash
# 问题：调试输出被捕获
function get_value() {
    echo "Debug: entering function"  # 被捕获！
    echo "42"
}
result=$(get_value)
echo "$result"  # 输出 "Debug: entering function\n42"

# 正确：调试输出到 stderr
function get_value() {
    echo "Debug: entering function" >&2  # 输出到 stderr，不被捕获
    echo "42"
}
```

---

## 职场小贴士（Japan IT Context）

### 函数库的运维场景

在日本 IT 企业，共用函数库是运维自动化的基础：

| 日语术语 | 含义 | 场景 |
|----------|------|------|
| 共通関数 | 公共函数 | 多个脚本共用的函数库 |
| ログ出力 | 日志输出 | log_info, log_error 等 |
| 戻り値 | 返回值 | return 的退出码 |
| ローカル変数 | 局部变量 | 用 local 声明 |

### 日本企业的函数库规范

```bash
#!/bin/bash
# ==============================================================================
# ファイル名：common_functions.sh
# 概要：共通関数ライブラリ
# 作成者：田中太郎
# 作成日：2026-01-10
# 変更履歴：
#   2026-01-10 新規作成（田中）
#   2026-01-15 log_error 追加（佐藤）
# ==============================================================================

# ログ出力関数
function log_info() {
    local message="$1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $message" | tee -a "$LOG_FILE"
}

# エラー出力関数（stderr）
function log_error() {
    local message="$1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $message" | tee -a "$LOG_FILE" >&2
}
```

### 监控对接（Zabbix 连携）

```bash
# Zabbix 自定义检查脚本中的函数使用
#!/bin/bash
source /opt/scripts/lib/common.sh
source /opt/scripts/lib/logging.sh

function check_process() {
    local proc_name="$1"
    local count
    count=$(pgrep -c "$proc_name" 2>/dev/null || echo 0)
    echo "$count"
}

# Zabbix UserParameter 调用
# UserParameter=custom.proc.count[*],/opt/scripts/check_proc.sh "$1"
result=$(check_process "$1")
echo "$result"
```

---

## 检查清单

完成本课后，你应该能够：

- [ ] 使用两种语法定义函数（`function name()` 和 `name()`）
- [ ] 理解函数参数 `$1`, `$2`, `$@`, `$#` 的含义
- [ ] 使用 `local` 声明局部变量
- [ ] 理解 `return` 和 `echo` 的区别
- [ ] 用 `return` 返回退出码（0-255）
- [ ] 用 `echo` + `$()` 返回字符串数据
- [ ] 创建和使用函数库（`source lib.sh`）
- [ ] 避免函数名覆盖系统命令
- [ ] 避免变量污染全局作用域

**验证命令：**

```bash
cd ~/function-lab

# 测试 1: ShellCheck 检查函数库
shellcheck lib/logger.sh
# 预期: 无错误

# 测试 2: 函数参数
bash -c 'f() { echo "$#"; }; f a b c'
# 预期: 3

# 测试 3: 局部变量
bash -c 'x=1; f() { local x=2; }; f; echo $x'
# 预期: 1（全局 x 未被修改）

# 测试 4: 返回值
bash -c 'f() { return 42; }; f; echo $?'
# 预期: 42
```

---

## 本课小结

| 概念 | 语法/要点 |
|------|-----------|
| 函数定义 | `function name() { }` 或 `name() { }` |
| 函数参数 | `$1`, `$2`, `$@`, `$#` |
| 局部变量 | `local var=value` |
| 返回退出码 | `return 0`（成功），`return 1`（失败） |
| 返回数据 | `echo "result"` + `var=$(func)` |
| 函数库 | `source lib.sh` 引入 |
| 命名规范 | 使用前缀避免冲突，如 `myapp_init` |

---

## 面试准备

### **関数で文字列を返す方法は？**

`echo` で文字列を出力し、呼び出し側で `$(func)` でキャプチャします。`return` は終了コード（0-255）のみを返せます。

```bash
function get_name() {
    echo "Alice"  # 文字列を出力
}
name=$(get_name)  # キャプチャ
echo "$name"      # Alice
```

### **local 変数が重要な理由は？**

グローバル変数の汚染を防ぎ、関数を安全に再利用可能にします。`local` を使わないと、関数内で設定した変数がグローバルスコープに残り、予期しない動作の原因になります。

```bash
function bad() {
    temp="leaked"  # グローバルに漏れる
}

function good() {
    local temp="safe"  # 関数内のみ
}
```

---

## 延伸阅读

- [Bash Functions](https://www.gnu.org/software/bash/manual/html_node/Shell-Functions.html) - GNU Bash 官方文档
- [Google Shell Style Guide - Functions](https://google.github.io/styleguide/shellguide.html#s7-naming-conventions) - Google Shell 风格指南
- 上一课：[05 - 循环结构](../05-loops/) — for、while、until 循环
- 下一课：[07 - 数组](../07-arrays/) — 索引数组与关联数组

---

## 清理

```bash
# 清理练习文件
cd ~
rm -rf ~/function-lab
```

---

## 系列导航

[<-- 05 - 循环结构](../05-loops/) | [课程首页](../) | [07 - 数组 -->](../07-arrays/)
