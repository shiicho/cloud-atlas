# 11 - 调试技巧与最佳实践

> **目标**：掌握 Shell 脚本调试技术和 ShellCheck 静态分析，写出生产级可维护代码  
> **前置**：[10 - 命令行参数处理](../10-arguments/)  
> **时间**：⚡ 25 分钟（速读）/ 🔬 90 分钟（完整实操）  
> **环境**：Bash 4.x+（RHEL 7/8/9, Ubuntu 18.04+ 均可）  

---

## 将学到的内容

1. 使用 `set -x` 和 PS4 调试脚本
2. 实现条件性调试输出
3. 深度集成 ShellCheck 静态分析
4. 在 CI/CD 中使用 ShellCheck
5. 掌握编码规范与团队协作
6. 了解何时应该使用其他工具代替脚本

---

## 先跑起来！（5 分钟）

> 在深入学习之前，先体验调试的威力。  
> 一个难以排查的 Bug，用对方法瞬间定位。  

```bash
# 创建练习目录
mkdir -p ~/debug-lab && cd ~/debug-lab

# 创建一个有 Bug 的脚本
cat > buggy-script.sh << 'EOF'
#!/bin/bash
# 这个脚本有一个隐藏的 Bug

process_files() {
    local dir=$1
    local count=0

    for file in $dir/*.txt; do
        if [ -f $file ]; then
            echo "Processing: $file"
            ((count++))
        fi
    done

    echo "Processed $count files"
}

# 创建测试数据
mkdir -p "test data"
touch "test data/file 1.txt"
touch "test data/file 2.txt"
touch "test data/report.txt"

# 处理文件
process_files "test data"
EOF

chmod +x buggy-script.sh

echo "=== 运行有 Bug 的脚本 ==="
./buggy-script.sh

echo ""
echo "=== 开启调试模式找出 Bug ==="
bash -x ./buggy-script.sh 2>&1 | head -30
```

**你会看到**：脚本说处理了 0 个文件，但明明有 3 个！

使用 `bash -x` 后，你能看到实际执行的命令：
- `for file in test data/*.txt` — 空格导致目录名被分割！
- `[ -f test ]` — 检查的是 "test" 而不是 "test data/file 1.txt"

**Bug 根因**：变量未加引号，空格导致 Word Splitting。

现在让我们系统学习调试技巧，让你成为 Bug 猎手！

---

## Step 1 — set -x 与 PS4（25 分钟）

### 1.1 set -x：执行跟踪

`set -x` 是最基本也是最强大的调试工具，它打印每条命令在执行前的展开结果：

![set -x Debugging](images/set-x-debugging.png)

<details>
<summary>View ASCII source</summary>

<!-- DIAGRAM: set-x-debugging -->
```
+-------------------------------------------------------------------------+
|  set -x 调试模式                                                          |
+-------------------------------------------------------------------------+
|                                                                          |
|  开启方式：                                                               |
|  +-----------------------------------------------------------+          |
|  |  1. 脚本内：set -x        # 从此处开始跟踪                   |          |
|  |  2. 命令行：bash -x script.sh  # 跟踪整个脚本               |          |
|  |  3. Shebang：#!/bin/bash -x    # 始终跟踪                   |          |
|  +-----------------------------------------------------------+          |
|                                                                          |
|  关闭方式：                                                               |
|  +-----------------------------------------------------------+          |
|  |  set +x                    # 关闭跟踪                        |          |
|  +-----------------------------------------------------------+          |
|                                                                          |
|  输出格式：                                                               |
|  +-----------------------------------------------------------+          |
|  |  + command arg1 arg2       # + 是默认前缀（PS4 变量）         |          |
|  |  ++ nested command         # ++ 表示子 shell 或命令替换      |          |
|  |  +++ deeper nesting        # 嵌套层级越深，+ 越多            |          |
|  +-----------------------------------------------------------+          |
|                                                                          |
|  实际示例：                                                               |
|  +-----------------------------------------------------------+          |
|  |  脚本：name="Alice"                                        |          |
|  |       echo "Hello, $name"                                  |          |
|  |                                                            |          |
|  |  输出：+ name=Alice                                        |          |
|  |       + echo 'Hello, Alice'                                |          |
|  |       Hello, Alice                                         |          |
|  +-----------------------------------------------------------+          |
|                                                                          |
|  注意：跟踪输出到 stderr（不影响 stdout）                                  |
|                                                                          |
+-------------------------------------------------------------------------+
```
<!-- /DIAGRAM -->

</details>

### 1.2 基础 set -x 演示

```bash
cd ~/debug-lab

cat > set-x-demo.sh << 'EOF'
#!/bin/bash
# set -x 基础演示

name="World"
greeting="Hello"

# 开启跟踪
set -x

message="$greeting, $name!"
echo "$message"

# 关闭跟踪
set +x

echo "跟踪已关闭，这行不会显示调试信息"

# 再次开启
set -x
result=$((1 + 2))
echo "1 + 2 = $result"
EOF

chmod +x set-x-demo.sh
./set-x-demo.sh
```

**输出解读**：
- `+ message='Hello, World!'` — 变量赋值被展开
- `+ echo 'Hello, World!'` — 命令和参数被展开
- 关闭跟踪后的 echo 没有 `+` 前缀

### 1.3 PS4：自定义调试输出格式

默认的 `+` 前缀信息量太少，PS4 变量让你自定义调试输出格式：

```bash
cd ~/debug-lab

cat > ps4-demo.sh << 'EOF'
#!/bin/bash
# PS4 自定义演示

# 默认 PS4
echo "=== 默认 PS4 ('+') ==="
set -x
echo "Line 1"
set +x

# 显示行号
echo ""
echo "=== 带行号的 PS4 ==="
PS4='+ [Line $LINENO]: '
set -x
echo "Line 2"
echo "Line 3"
set +x

# 显示更多信息
echo ""
echo "=== 完整调试信息 ==="
PS4='+ ${BASH_SOURCE[0]}:${LINENO}:${FUNCNAME[0]:-main}(): '
set -x
echo "Line 4"
set +x

# 带时间戳
echo ""
echo "=== 带时间戳 ==="
PS4='+ $(date +%T.%3N) [${LINENO}]: '
set -x
echo "Line 5"
sleep 0.1
echo "Line 6"
set +x
EOF

chmod +x ps4-demo.sh
./ps4-demo.sh
```

### 1.4 生产级 PS4 配置

```bash
cd ~/debug-lab

cat > ps4-production.sh << 'EOF'
#!/bin/bash
# 生产级 PS4 配置

# 推荐的 PS4 格式（包含：脚本名、行号、函数名）
export PS4='+ ${BASH_SOURCE[0]##*/}:${LINENO}:${FUNCNAME[0]:-main}(): '

# 或者更简洁的版本
# export PS4='+ [${LINENO}] ${FUNCNAME[0]:-main}(): '

# 带颜色的版本（终端支持时）
# export PS4=$'\e[33m+ ${BASH_SOURCE[0]##*/}:${LINENO}:${FUNCNAME[0]:-main}():\e[0m '

set -x

# 测试函数
greet() {
    local name="$1"
    echo "Hello, $name"
}

process() {
    local input="$1"
    local result
    result=$(echo "$input" | tr '[:lower:]' '[:upper:]')
    echo "$result"
}

# 主逻辑
greet "Alice"
process "hello world"
EOF

chmod +x ps4-production.sh
./ps4-production.sh
```

### 1.5 局部调试：只跟踪问题代码

```bash
cd ~/debug-lab

cat > partial-debug.sh << 'EOF'
#!/bin/bash
# 局部调试演示

# 配置 PS4
PS4='+ [${LINENO}]: '

# 正常代码（不跟踪）
echo "Starting script..."
config_file="/etc/myapp.conf"
log_dir="/var/log/myapp"

# 问题区域开始跟踪
echo "Processing data..."
set -x

# 这是有问题的代码区域
data="hello world"
for word in $data; do  # 这里会发生 Word Splitting
    echo "Word: $word"
done

set +x
# 问题区域结束

# 继续正常执行
echo "Script completed."
EOF

chmod +x partial-debug.sh
./partial-debug.sh
```

### 1.6 调试重定向到文件

生产环境中，你可能想把调试信息保存到文件：

```bash
cd ~/debug-lab

cat > debug-to-file.sh << 'EOF'
#!/bin/bash
# 调试输出重定向到文件

# 方法 1：重定向 stderr
exec 2>debug.log
set -x

echo "This goes to stdout"
name="test"
echo "Hello, $name"

set +x
exec 2>&1  # 恢复 stderr
echo "Debug info saved to debug.log"
EOF

chmod +x debug-to-file.sh
./debug-to-file.sh

echo ""
echo "=== debug.log 内容 ==="
cat debug.log
```

---

## Step 2 — 条件性调试（20 分钟）

### 2.1 DEBUG 环境变量模式

生产脚本需要可控的调试输出，不能总是打开 `set -x`：

![Conditional Debugging](images/conditional-debugging.png)

<details>
<summary>View ASCII source</summary>

<!-- DIAGRAM: conditional-debugging -->
```
+-------------------------------------------------------------------------+
|  条件性调试模式                                                            |
+-------------------------------------------------------------------------+
|                                                                          |
|  环境变量控制：                                                           |
|  +-----------------------------------------------------------+          |
|  |  DEBUG=1 ./script.sh        # 开启调试                      |          |
|  |  DEBUG=2 ./script.sh        # 更详细的调试                   |          |
|  |  ./script.sh                # 正常运行，无调试               |          |
|  +-----------------------------------------------------------+          |
|                                                                          |
|  脚本内检查：                                                             |
|  +-----------------------------------------------------------+          |
|  |  # 方式 1：条件开启 set -x                                  |          |
|  |  [[ "${DEBUG:-}" ]] && set -x                              |          |
|  |                                                            |          |
|  |  # 方式 2：调试函数                                         |          |
|  |  debug() {                                                 |          |
|  |      [[ "${DEBUG:-}" ]] && echo "DEBUG: $*" >&2            |          |
|  |  }                                                         |          |
|  |                                                            |          |
|  |  # 方式 3：日志级别                                         |          |
|  |  LOG_LEVEL="${LOG_LEVEL:-INFO}"                            |          |
|  |  log_debug() {                                             |          |
|  |      [[ "$LOG_LEVEL" == "DEBUG" ]] && echo "[DEBUG] $*"    |          |
|  |  }                                                         |          |
|  +-----------------------------------------------------------+          |
|                                                                          |
|  最佳实践：                                                               |
|  +-----------------------------------------------------------+          |
|  |  - 调试输出始终到 stderr（不干扰正常输出）                    |          |
|  |  - 支持多级调试（DEBUG=1 基础，DEBUG=2 详细）                |          |
|  |  - 生产环境默认关闭                                          |          |
|  +-----------------------------------------------------------+          |
|                                                                          |
+-------------------------------------------------------------------------+
```
<!-- /DIAGRAM -->

</details>

### 2.2 基础条件调试

```bash
cd ~/debug-lab

cat > conditional-debug.sh << 'EOF'
#!/bin/bash
# 条件性调试演示
set -euo pipefail

# 检查 DEBUG 环境变量，开启 set -x
[[ "${DEBUG:-}" ]] && set -x

# 配置 PS4
PS4='+ [${LINENO}] ${FUNCNAME[0]:-main}(): '

# 主逻辑
process_data() {
    local input="$1"
    echo "Processing: $input"
    sleep 0.1
    echo "Done: $input"
}

echo "Starting..."
process_data "file1.txt"
process_data "file2.txt"
echo "Completed."
EOF

chmod +x conditional-debug.sh

echo "=== 正常运行 ==="
./conditional-debug.sh

echo ""
echo "=== 调试模式 ==="
DEBUG=1 ./conditional-debug.sh
```

### 2.3 调试函数

```bash
cd ~/debug-lab

cat > debug-function.sh << 'EOF'
#!/bin/bash
# 调试函数模式
set -euo pipefail

# 调试函数
debug() {
    if [[ "${DEBUG:-}" ]]; then
        echo "DEBUG: $*" >&2
    fi
}

# 更详细的调试（DEBUG=2）
trace() {
    if [[ "${DEBUG:-0}" -ge 2 ]]; then
        echo "TRACE: [${BASH_SOURCE[1]##*/}:${BASH_LINENO[0]}] $*" >&2
    fi
}

# 使用调试函数
process_file() {
    local file="$1"
    debug "Entering process_file with: $file"
    trace "Checking file existence"

    if [[ -f "$file" ]]; then
        debug "File exists, processing..."
        cat "$file" | wc -l
    else
        debug "File not found: $file"
        return 1
    fi

    debug "Exiting process_file"
}

# 创建测试文件
echo -e "line1\nline2\nline3" > test.txt

echo "=== 运行脚本 ==="
echo "结果: $(process_file test.txt) 行"
EOF

chmod +x debug-function.sh

echo "=== 正常运行（无调试输出）==="
./debug-function.sh

echo ""
echo "=== DEBUG=1（基础调试）==="
DEBUG=1 ./debug-function.sh

echo ""
echo "=== DEBUG=2（详细跟踪）==="
DEBUG=2 ./debug-function.sh
```

### 2.4 生产级日志框架

```bash
cd ~/debug-lab

cat > logging-framework.sh << 'EOF'
#!/bin/bash
# 生产级日志框架
set -euo pipefail

# =============================================================================
# 日志配置
# =============================================================================
readonly LOG_LEVEL="${LOG_LEVEL:-INFO}"

# 日志级别定义（数字越大越详细）
declare -A LOG_LEVELS=(
    [ERROR]=0
    [WARN]=1
    [INFO]=2
    [DEBUG]=3
    [TRACE]=4
)

# 颜色定义
declare -A LOG_COLORS=(
    [ERROR]='\033[0;31m'  # 红色
    [WARN]='\033[0;33m'   # 黄色
    [INFO]='\033[0;32m'   # 绿色
    [DEBUG]='\033[0;36m'  # 青色
    [TRACE]='\033[0;35m'  # 紫色
)
readonly NC='\033[0m'

# =============================================================================
# 日志函数
# =============================================================================
_log() {
    local level="$1"
    shift
    local message="$*"

    # 检查日志级别
    local current_level="${LOG_LEVELS[$LOG_LEVEL]:-2}"
    local msg_level="${LOG_LEVELS[$level]:-2}"

    if [[ $msg_level -le $current_level ]]; then
        local timestamp
        timestamp=$(date '+%Y-%m-%d %H:%M:%S')
        local color="${LOG_COLORS[$level]:-}"

        # 输出到 stderr
        if [[ -t 2 ]]; then
            # 终端：带颜色
            echo -e "${color}[$timestamp] [$level] $message${NC}" >&2
        else
            # 非终端：无颜色
            echo "[$timestamp] [$level] $message" >&2
        fi
    fi
}

log_error() { _log ERROR "$@"; }
log_warn()  { _log WARN "$@"; }
log_info()  { _log INFO "$@"; }
log_debug() { _log DEBUG "$@"; }
log_trace() { _log TRACE "$@"; }

# =============================================================================
# 示例使用
# =============================================================================
main() {
    log_info "Script started"
    log_debug "LOG_LEVEL=$LOG_LEVEL"

    log_trace "Entering main function"

    for i in {1..3}; do
        log_debug "Processing item $i"
        log_trace "Item $i details: value=$((i * 10))"
    done

    log_warn "This is a warning"
    log_error "This is an error (but script continues)"

    log_info "Script completed"
}

main "$@"
EOF

chmod +x logging-framework.sh

echo "=== 默认级别 (INFO) ==="
./logging-framework.sh

echo ""
echo "=== DEBUG 级别 ==="
LOG_LEVEL=DEBUG ./logging-framework.sh

echo ""
echo "=== TRACE 级别（最详细）==="
LOG_LEVEL=TRACE ./logging-framework.sh

echo ""
echo "=== ERROR 级别（只显示错误）==="
LOG_LEVEL=ERROR ./logging-framework.sh
```

---

## Step 3 — ShellCheck 深度集成（25 分钟）

### 3.1 ShellCheck 简介

ShellCheck 是 Shell 脚本的静态分析工具，能在运行前发现 Bug。这是**生产级脚本的必备工具**。

![ShellCheck Workflow](images/shellcheck-workflow.png)

<details>
<summary>View ASCII source</summary>

<!-- DIAGRAM: shellcheck-workflow -->
```
+-------------------------------------------------------------------------+
|  ShellCheck 工作流程                                                       |
+-------------------------------------------------------------------------+
|                                                                          |
|  静态分析：不运行代码，只分析代码                                           |
|                                                                          |
|  ┌─────────────┐     ┌─────────────┐     ┌─────────────┐               |
|  │  script.sh  │────▶│  ShellCheck │────▶│  问题报告    │               |
|  │  (源代码)    │     │  (分析器)    │     │  (建议修复)  │               |
|  └─────────────┘     └─────────────┘     └─────────────┘               |
|                                                                          |
|  检查类别：                                                               |
|  +-----------------------------------------------------------+          |
|  |  SC1xxx  语法错误（Syntax）                                 |          |
|  |  SC2xxx  警告（Warning）- 最常见的 Bug 源                   |          |
|  |  SC3xxx  Shell 兼容性（Portability）                        |          |
|  |  SC4xxx  弃用/过时（Deprecation）                           |          |
|  +-----------------------------------------------------------+          |
|                                                                          |
|  常见规则：                                                               |
|  +-----------------------------------------------------------+          |
|  |  SC2086  变量未引用（Word Splitting 风险）                   |          |
|  |  SC2046  命令替换未引用                                      |          |
|  |  SC2034  变量未使用                                          |          |
|  |  SC2155  声明和赋值应分开                                    |          |
|  |  SC2164  cd 失败应处理                                       |          |
|  +-----------------------------------------------------------+          |
|                                                                          |
|  集成方式：                                                               |
|  +-----------------------------------------------------------+          |
|  |  - 命令行：shellcheck script.sh                             |          |
|  |  - 编辑器：VS Code, Vim, Emacs 插件                         |          |
|  |  - CI/CD：GitHub Actions, GitLab CI                        |          |
|  |  - pre-commit hook：提交前自动检查                          |          |
|  +-----------------------------------------------------------+          |
|                                                                          |
+-------------------------------------------------------------------------+
```
<!-- /DIAGRAM -->

</details>

### 3.2 安装 ShellCheck

```bash
# Ubuntu/Debian
sudo apt-get install shellcheck

# RHEL/CentOS/Fedora
sudo dnf install ShellCheck

# macOS
brew install shellcheck

# 验证安装
shellcheck --version
```

### 3.3 ShellCheck 基础使用

```bash
cd ~/debug-lab

# 创建一个有问题的脚本
cat > problematic.sh << 'EOF'
#!/bin/bash
# 这个脚本有很多 ShellCheck 能检测到的问题

# SC2034: 未使用的变量
unused_var="hello"

# SC2086: 变量未引用
filename="my file.txt"
cat $filename

# SC2046: 命令替换未引用
files=$(ls *.txt)
for f in $files; do
    echo $f
done

# SC2164: cd 可能失败
cd /some/directory
rm -rf *

# SC2155: 声明和赋值应分开
local result=$(some_command)

# SC2162: read 没有 -r
read line < file.txt

# SC2002: 无用的 cat
cat file.txt | grep pattern
EOF

echo "=== ShellCheck 分析 ==="
shellcheck problematic.sh || true

echo ""
echo "=== 只显示错误码 ==="
shellcheck -f gcc problematic.sh 2>&1 | head -10 || true
```

### 3.4 ShellCheck 常见规则详解

```bash
cd ~/debug-lab

cat > shellcheck-rules.sh << 'EOF'
#!/bin/bash
# ShellCheck 常见规则演示

# =============================================================================
# SC2086: Double quote to prevent globbing and word splitting
# =============================================================================
echo "=== SC2086: 变量引用 ==="

# 错误示例
filename="my file.txt"
# cat $filename  # ShellCheck: SC2086

# 正确示例
cat "$filename"

# =============================================================================
# SC2046: Quote this to prevent word splitting
# =============================================================================
echo ""
echo "=== SC2046: 命令替换引用 ==="

# 错误示例
# for file in $(ls); do  # ShellCheck: SC2046 + SC2012

# 正确示例
for file in *; do
    [[ -f "$file" ]] && echo "File: $file"
done

# =============================================================================
# SC2155: Declare and assign separately
# =============================================================================
echo ""
echo "=== SC2155: 声明与赋值分离 ==="

# 错误示例（在函数中）
bad_function() {
    # local result=$(command)  # SC2155: 如果 command 失败，$? 被 local 覆盖
    true
}

# 正确示例
good_function() {
    local result
    result=$(echo "hello")
    echo "$result"
}
good_function

# =============================================================================
# SC2164: Use 'cd ... || exit' in case cd fails
# =============================================================================
echo ""
echo "=== SC2164: cd 错误处理 ==="

# 错误示例
# cd /some/dir
# rm -rf *  # 危险！如果 cd 失败，会删除当前目录！

# 正确示例
cd /tmp || exit 1
# 或者
cd /tmp || { echo "Failed to cd" >&2; exit 1; }

# =============================================================================
# SC2034: Variable appears unused
# =============================================================================
echo ""
echo "=== SC2034: 未使用变量 ==="

# 会警告（除非导出或在其他脚本中使用）
# unused="value"  # SC2034

# 抑制警告的方法
export USED_BY_CHILD="value"  # 导出的不会警告
# shellcheck disable=SC2034
intentionally_unused="for documentation"

echo "演示完成"
EOF

shellcheck shellcheck-rules.sh || true
echo ""
echo "=== 修复后的脚本可以通过检查 ==="
```

### 3.5 .shellcheckrc 配置文件

```bash
cd ~/debug-lab

# 创建 ShellCheck 配置文件
cat > .shellcheckrc << 'EOF'
# ShellCheck 配置文件
# 放在项目根目录或 ~/.shellcheckrc

# 指定默认 shell（bash, sh, dash, ksh）
shell=bash

# 全局禁用某些规则
# disable=SC2059,SC2034

# 启用所有警告（包括 info 级别）
# enable=all

# 设置严格程度：error, warning, info, style
severity=warning

# 外部文件（source 的脚本）
# external-sources=true
EOF

echo "=== .shellcheckrc 内容 ==="
cat .shellcheckrc

echo ""
echo "=== 使用配置检查 ==="
shellcheck shellcheck-rules.sh
```

### 3.6 内联指令（禁用特定警告）

```bash
cd ~/debug-lab

cat > inline-directives.sh << 'EOF'
#!/bin/bash
# ShellCheck 内联指令演示

# 禁用下一行的警告
# shellcheck disable=SC2034
unused_but_documented="This is intentional"

# 禁用整个函数的警告
# shellcheck disable=SC2086
legacy_function() {
    # 这是遗留代码，暂时无法修复
    echo $1 $2 $3
}

# 禁用整个脚本的警告（放在文件开头）
# #!/bin/bash
# # shellcheck disable=SC2086,SC2046

# 给出原因（最佳实践）
# shellcheck disable=SC2034 # Used by sourcing scripts
LIBRARY_VERSION="1.0.0"

# 禁用后再启用
# shellcheck disable=SC2086
echo $PATH  # 这里不会警告
# shellcheck enable=SC2086
echo "$PATH"  # 推荐写法
EOF

shellcheck inline-directives.sh || true
```

---

## Step 4 — CI/CD 集成（20 分钟）

### 4.1 GitHub Actions 集成

```bash
cd ~/debug-lab

# 创建 GitHub Actions 工作流
mkdir -p .github/workflows

cat > .github/workflows/shellcheck.yml << 'EOF'
# ShellCheck GitHub Action
name: ShellCheck

on:
  push:
    branches: [main, develop]
    paths:
      - '**.sh'
      - '**.bash'
  pull_request:
    branches: [main]
    paths:
      - '**.sh'
      - '**.bash'

jobs:
  shellcheck:
    name: ShellCheck
    runs-on: ubuntu-latest

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Run ShellCheck
        uses: ludeeus/action-shellcheck@master
        with:
          severity: warning
          scandir: './scripts'
          format: tty
        env:
          SHELLCHECK_OPTS: -e SC1091  # 忽略 source 文件不存在

      # 或者使用命令行方式
      - name: Manual ShellCheck
        run: |
          # 安装 ShellCheck
          sudo apt-get update && sudo apt-get install -y shellcheck

          # 检查所有脚本
          find . -name "*.sh" -type f -print0 | \
            xargs -0 shellcheck --severity=warning

          echo "ShellCheck passed!"
EOF

echo "=== GitHub Actions 配置 ==="
cat .github/workflows/shellcheck.yml
```

### 4.2 pre-commit hook

```bash
cd ~/debug-lab

# 创建 pre-commit hook
mkdir -p .git-hooks

cat > .git-hooks/pre-commit << 'EOF'
#!/bin/bash
# Git pre-commit hook for ShellCheck
# 安装: ln -sf ../../.git-hooks/pre-commit .git/hooks/pre-commit

set -euo pipefail

echo "Running ShellCheck on staged shell scripts..."

# 获取暂存的 .sh 文件
staged_files=$(git diff --cached --name-only --diff-filter=ACM | grep -E '\.sh$' || true)

if [[ -z "$staged_files" ]]; then
    echo "No shell scripts to check."
    exit 0
fi

# 检查 ShellCheck 是否安装
if ! command -v shellcheck &> /dev/null; then
    echo "Warning: ShellCheck not installed. Skipping..."
    exit 0
fi

# 运行 ShellCheck
error_count=0
for file in $staged_files; do
    echo "Checking: $file"
    if ! shellcheck -S warning "$file"; then
        ((error_count++)) || true
    fi
done

if [[ $error_count -gt 0 ]]; then
    echo ""
    echo "ShellCheck found issues in $error_count file(s)."
    echo "Please fix the issues or use 'git commit --no-verify' to skip."
    exit 1
fi

echo "ShellCheck passed!"
exit 0
EOF

chmod +x .git-hooks/pre-commit

echo "=== pre-commit hook 创建完成 ==="
echo "安装命令: ln -sf ../../.git-hooks/pre-commit .git/hooks/pre-commit"
```

### 4.3 完整的 Mini Project：ShellCheck CI 配置

```bash
cd ~/debug-lab

# 创建项目结构
mkdir -p my-shell-project/{scripts,lib,.github/workflows}

# 创建示例脚本
cat > my-shell-project/scripts/deploy.sh << 'EOF'
#!/usr/bin/env bash
# 部署脚本示例
set -euo pipefail

# shellcheck source=../lib/common.sh
source "$(dirname "$0")/../lib/common.sh"

main() {
    log_info "Starting deployment..."

    local env="${1:-production}"
    log_debug "Target environment: $env"

    # 部署逻辑
    log_info "Deploying to $env..."
    sleep 1

    log_info "Deployment completed!"
}

main "$@"
EOF

# 创建共享库
cat > my-shell-project/lib/common.sh << 'EOF'
#!/usr/bin/env bash
# 共享函数库

log_info() {
    echo "[INFO] $*"
}

log_debug() {
    [[ "${DEBUG:-}" ]] && echo "[DEBUG] $*" >&2 || true
}

log_error() {
    echo "[ERROR] $*" >&2
}
EOF

# 创建 .shellcheckrc
cat > my-shell-project/.shellcheckrc << 'EOF'
shell=bash
severity=warning
external-sources=true
EOF

# 创建 GitHub Actions
cat > my-shell-project/.github/workflows/ci.yml << 'EOF'
name: CI

on: [push, pull_request]

jobs:
  shellcheck:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: ShellCheck
        uses: ludeeus/action-shellcheck@master
        with:
          scandir: './scripts'
          severity: warning

  test:
    runs-on: ubuntu-latest
    needs: shellcheck
    steps:
      - uses: actions/checkout@v4
      - name: Run tests
        run: |
          chmod +x scripts/*.sh
          ./scripts/deploy.sh test
EOF

# 创建 pre-commit hook
cat > my-shell-project/.git-hooks/pre-commit << 'EOF'
#!/bin/bash
set -euo pipefail

echo "Running pre-commit checks..."

# ShellCheck
if command -v shellcheck &> /dev/null; then
    echo "Running ShellCheck..."
    find . -name "*.sh" -type f | xargs shellcheck -S warning
fi

echo "All checks passed!"
EOF
chmod +x my-shell-project/.git-hooks/pre-commit

echo "=== 项目结构 ==="
find my-shell-project -type f | sort

echo ""
echo "=== 测试 ShellCheck ==="
shellcheck my-shell-project/scripts/*.sh my-shell-project/lib/*.sh && echo "All scripts passed ShellCheck!"
```

---

## Step 5 — 脚本版本控制（10 分钟）

### 5.1 Git 管理脚本

> **注意**：这是简要介绍，详细 Git 学习请参考 DevOps Git 课程。  

运维脚本也是代码，应该纳入版本控制：

```bash
cd ~/debug-lab

echo "=== 初始化脚本仓库 ==="

# 创建脚本目录
mkdir -p ~/my-scripts
cd ~/my-scripts

# 初始化 Git
git init

# 创建 .gitignore
cat > .gitignore << 'EOF'
# 临时文件
*.tmp
*.log
*.bak
*~

# 敏感信息（永远不要提交！）
*.key
*.pem
.env
secrets/

# 编辑器文件
.vscode/
.idea/
EOF

# 创建示例脚本
cat > log-rotate.sh << 'EOF'
#!/bin/bash
# 日志轮转脚本
# 版本：1.0.0
set -euo pipefail

LOG_DIR="${1:-/var/log/myapp}"
DAYS_TO_KEEP="${2:-7}"

find "$LOG_DIR" -name "*.log" -mtime +$DAYS_TO_KEEP -delete
echo "Cleaned logs older than $DAYS_TO_KEEP days"
EOF
chmod +x log-rotate.sh

# 提交
git add .
git commit -m "Initial commit: log rotation script"

echo ""
echo "=== Git 日志 ==="
git log --oneline
```

### 5.2 etckeeper：/etc 版本控制

```bash
# etckeeper 是管理 /etc 目录变更的工具
# 在日本运维现场，/etc 的变更追踪是必须的

echo "=== etckeeper 简介 ==="
cat << 'EOF'
etckeeper 自动追踪 /etc 目录变更：

安装：
  sudo apt install etckeeper  # Ubuntu/Debian
  sudo dnf install etckeeper  # RHEL/CentOS

使用：
  sudo etckeeper init         # 初始化
  sudo etckeeper commit "变更说明"  # 手动提交

  # 自动集成包管理器
  # apt/dnf 安装软件时自动记录 /etc 变更

优势：
  - 配置文件变更可追溯
  - 出问题可回滚
  - 符合日本企业变更管理要求（変更管理）

注意：
  - 生产环境强烈推荐使用
  - 配合变更管理流程
EOF
```

---

## Step 6 — 什么时候不该用脚本（Bridge to IaC）

### 6.1 幂等性问题

Shell 脚本有一个根本性问题：**天生不是幂等的**。

```bash
cd ~/debug-lab

cat > idempotency-problem.sh << 'EOF'
#!/bin/bash
# 幂等性问题演示

echo "=== 非幂等操作示例 ==="

# 创建用户 - 第二次运行会报错
echo "创建用户 testuser..."
# useradd testuser  # 运行两次会失败

# 创建目录 - 幸运的是 -p 是幂等的
echo "创建目录..."
mkdir -p /tmp/test-dir  # 多次运行不会出错

# 追加内容 - 每次运行都会追加
echo "追加配置..."
echo "config=value" >> /tmp/test-config.conf
# 运行两次，config=value 出现两次！

echo ""
echo "=== /tmp/test-config.conf 内容 ==="
cat /tmp/test-config.conf

echo ""
echo "问题：运行脚本两次，配置被重复添加！"
echo "这就是非幂等的问题。"

# 清理
rm -f /tmp/test-config.conf
rm -rf /tmp/test-dir
EOF

chmod +x idempotency-problem.sh

# 运行两次
./idempotency-problem.sh
./idempotency-problem.sh
```

### 6.2 什么时候应该换工具

![When NOT to Script](images/when-not-to-script.png)

<details>
<summary>View ASCII source</summary>

<!-- DIAGRAM: when-not-to-script -->
```
+-------------------------------------------------------------------------+
|  什么时候不该用 Shell 脚本                                                  |
+-------------------------------------------------------------------------+
|                                                                          |
|  反模式：用 Bash 管理 50 台服务器配置                                       |
|  +-----------------------------------------------------------+          |
|  |  问题：                                                     |          |
|  |  - 配置漂移（Configuration Drift）                          |          |
|  |  - 无法回滚                                                  |          |
|  |  - 难以审计（谁改了什么？）                                   |          |
|  |  - 执行顺序问题                                              |          |
|  |  - 网络中断导致部分执行                                      |          |
|  +-----------------------------------------------------------+          |
|                                                                          |
|  命令式 vs 声明式：                                                        |
|  +-----------------------------------------------------------+          |
|  |                                                            |          |
|  |  Bash 脚本（命令式）         Ansible/Terraform（声明式）    |          |
|  |  "怎么做"                   "要什么"                        |          |
|  |                                                            |          |
|  |  apt install nginx         state: present                 |          |
|  |  systemctl start nginx     enabled: true                  |          |
|  |  echo "config" > file      content: "config"              |          |
|  |                                                            |          |
|  |  问题：运行两次？           自动幂等！                       |          |
|  |  - 可能报错                 - 无变化跳过                    |          |
|  |  - 可能重复执行             - 仅在需要时执行                |          |
|  +-----------------------------------------------------------+          |
|                                                                          |
|  继续用 Bash 的场景：                                                      |
|  +-----------------------------------------------------------+          |
|  |  - 一次性任务、快速原型                                      |          |
|  |  - 简单的本地自动化                                          |          |
|  |  - 构建管道中的胶水脚本                                      |          |
|  |  - 交互式工具                                               |          |
|  |  - 系统启动脚本                                             |          |
|  +-----------------------------------------------------------+          |
|                                                                          |
|  应该换工具的信号：                                                        |
|  +-----------------------------------------------------------+          |
|  |  - 写大量 "if already exists then skip"                    |          |
|  |  - 管理多台服务器                                           |          |
|  |  - 需要回滚能力                                             |          |
|  |  - 需要审计追踪                                             |          |
|  |  - 配置管理（不是一次性任务）                                |          |
|  +-----------------------------------------------------------+          |
|                                                                          |
|  推荐工具：                                                               |
|  - 配置管理：Ansible, Puppet, Chef                                       |
|  - 基础设施：Terraform, CloudFormation                                   |
|  - 容器编排：Docker, Kubernetes                                          |
|                                                                          |
+-------------------------------------------------------------------------+
```
<!-- /DIAGRAM -->

</details>

### 6.3 Bridge to Ansible

```bash
cd ~/debug-lab

echo "=== Bash vs Ansible 对比 ==="

cat << 'EOF'
# Bash 方式安装 Nginx
#!/bin/bash
apt-get update
apt-get install -y nginx
systemctl enable nginx
systemctl start nginx
echo "server { ... }" > /etc/nginx/sites-available/default
systemctl reload nginx

# 问题：
# - 运行两次？apt-get 可能报错
# - 如何检查是否已安装？
# - 如何回滚？

---

# Ansible 方式（声明式）
- name: Install and configure Nginx
  hosts: webservers
  tasks:
    - name: Install Nginx
      apt:
        name: nginx
        state: present
        update_cache: yes

    - name: Enable and start Nginx
      service:
        name: nginx
        state: started
        enabled: yes

    - name: Configure Nginx
      template:
        src: nginx.conf.j2
        dest: /etc/nginx/sites-available/default
      notify: Reload Nginx

  handlers:
    - name: Reload Nginx
      service:
        name: nginx
        state: reloaded

# 优势：
# - 幂等：运行 100 次结果相同
# - 声明式：只说"要什么"
# - 可回滚：配置变更可追溯
# - 批量执行：自动处理 50 台服务器
EOF

echo ""
echo "想学习 Ansible？参考我们的 Ansible 课程！"
echo "路径：automation/ansible/"
```

---

## 代码审查检查清单

在日本 IT 企业，代码审查是必须的。以下是 Shell 脚本审查清单：

```bash
cd ~/debug-lab

cat > code-review-checklist.md << 'EOF'
# Shell 脚本代码审查检查清单

## 必须检查（Must Have）

### 1. 严格模式
- [ ] 使用 `set -euo pipefail`
- [ ] 理解 `set -e` 的例外情况

### 2. 变量引用
- [ ] 所有变量使用双引号：`"$var"` 而不是 `$var`
- [ ] 数组展开使用 `"${array[@]}"`

### 3. ShellCheck
- [ ] 通过 ShellCheck 检查（无 error/warning）
- [ ] 必要的 disable 有注释说明原因

### 4. 错误处理
- [ ] 关键命令检查退出码或使用 `set -e`
- [ ] `cd` 命令使用 `cd ... || exit`
- [ ] 使用 `trap EXIT` 清理临时资源

### 5. 安全性
- [ ] 不硬编码密码或密钥
- [ ] 临时文件使用 `mktemp`
- [ ] 权限最小化原则

## 建议检查（Should Have）

### 6. 可读性
- [ ] 函数有注释说明
- [ ] 复杂逻辑有注释
- [ ] 变量名有意义

### 7. 可维护性
- [ ] 魔法数字使用常量
- [ ] 可配置项使用变量或参数
- [ ] 函数职责单一

### 8. CLI 规范
- [ ] 支持 `-h/--help`
- [ ] 支持 `--version`
- [ ] 错误输出到 stderr
- [ ] 使用标准退出码

### 9. 日志
- [ ] 关键操作有日志
- [ ] 错误有详细信息
- [ ] 支持调试模式（DEBUG 环境变量）

### 10. 文档
- [ ] 脚本头部有用途说明
- [ ] README 有使用示例
- [ ] 变更有版本记录

## 日本企业特别要求

- [ ] 脚本头部有作成者、作成日
- [ ] 支持日志输出到文件
- [ ] 符合社内编码规范
- [ ] 变更履历有记录
EOF

cat code-review-checklist.md
```

---

## 速查表（Cheatsheet）

```bash
# =============================================================================
# 调试技巧速查表
# =============================================================================

# --- set -x 调试 ---
set -x              # 开启执行跟踪
set +x              # 关闭执行跟踪
bash -x script.sh   # 命令行开启跟踪

# --- PS4 自定义 ---
PS4='+ '                              # 默认
PS4='+ [${LINENO}]: '                 # 带行号
PS4='+ ${FUNCNAME[0]:-main}(): '      # 带函数名
PS4='+ ${BASH_SOURCE[0]}:${LINENO}: ' # 带文件名和行号

# --- 条件调试 ---
[[ "${DEBUG:-}" ]] && set -x          # DEBUG 环境变量控制

debug() {                             # 调试函数
    [[ "${DEBUG:-}" ]] && echo "DEBUG: $*" >&2
}

# --- ShellCheck ---
shellcheck script.sh                  # 基本检查
shellcheck -S warning script.sh       # 只显示 warning 以上
shellcheck -f gcc script.sh           # GCC 格式输出
shellcheck -x script.sh               # 检查 source 的文件

# --- ShellCheck 内联指令 ---
# shellcheck disable=SC2086           # 禁用特定规则
# shellcheck disable=SC2086,SC2046    # 禁用多个规则
# shellcheck source=./lib.sh          # 指定 source 文件

# --- 常见 ShellCheck 规则 ---
SC2086   # 变量未引用
SC2046   # 命令替换未引用
SC2034   # 变量未使用
SC2155   # 声明和赋值应分开
SC2164   # cd 失败应处理

# --- Git 管理脚本 ---
git init ~/bin                        # 初始化脚本目录
git add script.sh
git commit -m "Add script"

# =============================================================================
# 生产级脚本模板
# =============================================================================
#!/usr/bin/env bash
set -euo pipefail
PS4='+ [${LINENO}] ${FUNCNAME[0]:-main}(): '
[[ "${DEBUG:-}" ]] && set -x

# 日志函数
log_info()  { echo "[INFO] $*"; }
log_error() { echo "[ERROR] $*" >&2; }
log_debug() { [[ "${DEBUG:-}" ]] && echo "[DEBUG] $*" >&2 || true; }

# 清理函数
cleanup() { rm -f "$TMPFILE"; }
trap cleanup EXIT

# 主逻辑
main() {
    log_info "Starting..."
    # your code here
    log_info "Done."
}

main "$@"
```

---

## 反模式：常见错误

### 错误 1：调试代码残留

```bash
# 错误：提交了调试代码
set -x  # 忘记删除！
echo "Deploying..."

# 正确：使用条件调试
[[ "${DEBUG:-}" ]] && set -x
echo "Deploying..."
```

### 错误 2：忽略 ShellCheck 警告

```bash
# 错误：用 disable 掩盖真正的问题
# shellcheck disable=SC2086
rm -rf $dir/*  # 危险！

# 正确：修复问题
rm -rf "${dir:?}"/*  # 安全：如果 $dir 为空会报错
```

### 错误 3：调试信息到 stdout

```bash
# 错误：调试信息混入正常输出
debug() {
    echo "DEBUG: $*"  # 会干扰管道
}

# 正确：调试信息到 stderr
debug() {
    echo "DEBUG: $*" >&2
}
```

### 错误 4：不可控的 set -x

```bash
# 错误：全局开启 set -x
#!/bin/bash -x
# 生产环境也会输出调试信息！

# 正确：可控的调试
#!/bin/bash
[[ "${DEBUG:-}" ]] && set -x
```

---

## 职场小贴士（Japan IT Context）

### 日本企业的脚本规范

| 日语术语 | 含义 | 要求 |
|----------|------|------|
| デバッグ | 调试 | 必须支持 DEBUG 模式 |
| 静的解析 | 静态分析 | ShellCheck 必须通过 |
| コードレビュー | 代码审查 | 所有脚本需要审查 |
| 変更履歴 | 变更历史 | 脚本头部记录变更 |
| 単体テスト | 单元测试 | 关键脚本需要测试 |

### 日本企业脚本头部模板

```bash
#!/bin/bash
# ==============================================================================
# スクリプト名：process-logs.sh
# 概要：ログファイルの処理と分析
# 作成者：田中太郎
# 作成日：2026-01-10
# 変更履歴：
#   2026-01-10 初版作成
#   2026-01-15 エラーハンドリング追加
# ==============================================================================
#
# 使用方法：
#   ./process-logs.sh [-v] [-o OUTPUT] INPUT_DIR
#
# オプション：
#   -v          詳細出力
#   -o FILE     出力ファイル指定
#   -h          ヘルプ表示
#
# 依存関係：
#   - bash 4.0+
#   - jq (JSON処理用)
#
# ==============================================================================
```

### 运维现场的调试流程

```bash
# 日本运维现场の障害対応フロー

# 1. 情報収集
echo "=== システム情報 ==="
uname -a
cat /etc/os-release

# 2. ログ確認
echo "=== 最新エラーログ ==="
journalctl -p err -n 20

# 3. スクリプトデバッグ
echo "=== スクリプト実行（デバッグモード）==="
DEBUG=1 ./problematic-script.sh 2>&1 | tee debug.log

# 4. 分析
echo "=== エラー箇所特定 ==="
grep -n "ERROR\|WARN" debug.log

# 5. 対応記録
echo "=== 対応記録 ==="
cat << EOF >> incident-$(date +%Y%m%d).log
日時：$(date)
担当：$(whoami)
概要：○○スクリプトのエラー
原因：変数の引用漏れ
対応：修正版をデプロイ
EOF
```

---

## 检查清单

完成本课后，你应该能够：

- [ ] 使用 `set -x` 跟踪脚本执行
- [ ] 使用 PS4 自定义调试输出格式
- [ ] 实现条件性调试（DEBUG 环境变量）
- [ ] 创建调试函数和日志框架
- [ ] 使用 ShellCheck 检查脚本
- [ ] 理解常见 ShellCheck 规则（SC2086, SC2046 等）
- [ ] 创建 .shellcheckrc 配置文件
- [ ] 配置 GitHub Actions 运行 ShellCheck
- [ ] 创建 pre-commit hook
- [ ] 理解何时应该使用 Ansible 代替脚本
- [ ] 使用 Git 管理脚本版本

**验证命令：**

```bash
cd ~/debug-lab

# 测试 1: set -x
bash -c 'set -x; echo "test"' 2>&1 | grep -q "^+ echo" && echo "PASS: set -x 工作正常"

# 测试 2: PS4
bash -c 'PS4="[LINE \$LINENO]: "; set -x; echo test' 2>&1 | grep -q "LINE" && echo "PASS: PS4 工作正常"

# 测试 3: 条件调试
bash -c '[[ "${DEBUG:-}" ]] && echo "debug mode"' && echo "PASS: 无 DEBUG 时无输出"
DEBUG=1 bash -c '[[ "${DEBUG:-}" ]] && echo "debug mode"' | grep -q "debug" && echo "PASS: DEBUG 模式工作"

# 测试 4: ShellCheck
echo '#!/bin/bash
echo "$1"' > /tmp/test-sc.sh
shellcheck /tmp/test-sc.sh && echo "PASS: ShellCheck 通过"

# 测试 5: Mini Project
shellcheck my-shell-project/scripts/*.sh && echo "PASS: 项目通过 ShellCheck"
```

---

## 本课小结

| 技术 | 用途 | 命令/配置 |
|------|------|-----------|
| `set -x` | 执行跟踪 | `set -x` / `set +x` |
| PS4 | 自定义调试格式 | `PS4='+ [${LINENO}]: '` |
| 条件调试 | 可控调试输出 | `[[ "${DEBUG:-}" ]] && set -x` |
| 调试函数 | 结构化调试 | `debug() { ... }` |
| ShellCheck | 静态分析 | `shellcheck script.sh` |
| .shellcheckrc | ShellCheck 配置 | 项目根目录 |
| pre-commit | 提交前检查 | Git hook |
| CI/CD | 自动化检查 | GitHub Actions |

---

## 面试准备

### **ShellCheck とは何ですか？**

ShellCheck はシェルスクリプトの静的解析ツールです。実行せずにコードを分析し、バグ、セキュリティ問題、スタイル違反を検出します。SC2086（変数のクォート漏れ）やSC2164（cd失敗時の処理漏れ）など、よくあるミスを自動で検出できます。

```bash
# 使用例
shellcheck script.sh
shellcheck -S warning script.sh  # warning以上のみ表示
```

### **デバッグで set -x を使う方法は？**

`set -x` は実行トレースを有効にし、各コマンドの実行前に展開結果を表示します。PS4変数でフォーマットをカスタマイズできます。

```bash
# 基本的な使い方
set -x    # トレース開始
set +x    # トレース終了

# カスタムフォーマット
PS4='+ [${LINENO}] ${FUNCNAME[0]:-main}(): '
set -x

# 条件付きデバッグ（本番環境向け）
[[ "${DEBUG:-}" ]] && set -x
```

### **Bash スクリプトより Ansible を使うべき場面は？**

以下の場合は Ansible が適切です：

1. **複数サーバーの設定管理** - Bash で 50 台管理は困難
2. **冪等性が必要な場合** - Ansible は宣言的で自動的に冪等
3. **ロールバックが必要な場合** - 変更追跡と復元が容易
4. **設定ドリフト防止** - 定期実行で設定を維持

Bash を使い続けるべき場面：
- 一回限りのタスク
- ローカル自動化
- ビルドパイプラインのグルースクリプト
- インタラクティブツール

---

## 延伸阅读

- [ShellCheck Wiki](https://www.shellcheck.net/wiki/) - ShellCheck 规则详解
- [Google Shell Style Guide](https://google.github.io/styleguide/shellguide.html) - Google Shell 编码规范
- [Bash Debugging Techniques](https://www.gnu.org/software/bash/manual/html_node/The-Set-Builtin.html) - GNU Bash 调试选项
- [GitHub Actions for ShellCheck](https://github.com/marketplace/actions/shellcheck) - ShellCheck GitHub Action
- 上一课：[10 - 命令行参数处理](../10-arguments/) — getopts 与 CLI 设计
- 下一课：[12 - 综合项目](../12-capstone/) — 自动化工具开发
- 相关课程：[Ansible 课程](../../../automation/ansible/) — 声明式配置管理

---

## 清理

```bash
# 清理练习文件
cd ~
rm -rf ~/debug-lab
rm -rf ~/my-scripts
```

---

## 系列导航

[<-- 10 - 命令行参数处理](../10-arguments/) | [课程首页](../) | [12 - 综合项目 -->](../12-capstone/)
