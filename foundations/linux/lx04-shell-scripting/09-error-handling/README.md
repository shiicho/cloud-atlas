# 09 - 错误处理与 trap（重点课）

> **目标**：掌握生产级脚本的错误处理机制，让脚本在出错时能正确响应  
> **前置**：[08 - 参数展开](../08-expansion/)  
> **时间**：120-150 分钟  
> **环境**：Bash 4.x+（RHEL 7/8/9, Ubuntu 18.04+ 均可）  
> **重要性**：这是生产级脚本必备的核心技能！  

---

## 将学到的内容

1. 理解 `set -e`（errexit）及其局限性
2. 理解 `set -u`（nounset）
3. 理解 `set -o pipefail`
4. 掌握 trap 机制（EXIT, ERR, INT, TERM）
5. 实现清理逻辑（临时文件、锁文件）
6. 处理信号实现优雅退出

---

## 为什么这课如此重要？

> **生产环境的脚本与练习脚本最大的区别，就是错误处理。**  

在日本 IT 企业的运维现场，脚本出错可能导致：
- 数据丢失（临时文件没有清理）
- 资源泄漏（锁文件残留导致其他任务阻塞）
- 连锁故障（错误后继续执行导致更大问题）
- 难以排查（静默失败没有任何日志）

这就是为什么日本企业常说「障害対応」（故障处理）时，首先检查的就是脚本的エラーハンドリング（Error Handling）。

---

## 先跑起来！（5 分钟）

> 在理解原理之前，先体验一个没有错误处理的脚本是多么危险。  

### 失败实验室：静默失败演示

```bash
# 创建练习目录
mkdir -p ~/error-lab && cd ~/error-lab

# 创建一个「危险」的脚本
cat > dangerous-script.sh << 'EOF'
#!/bin/bash
# 这个脚本展示没有错误处理的危险

echo "Step 1: 进入工作目录..."
cd /nonexistent/directory   # 这个目录不存在！

echo "Step 2: 删除临时文件..."
rm -rf *                    # 危险！如果 cd 失败，会删除当前目录的文件！

echo "Step 3: 完成！"
EOF

# 创建一些测试文件
mkdir -p test_dir
touch test_dir/important_file.txt
echo "重要数据" > test_dir/data.txt

echo "=== 当前目录内容 ==="
ls -la test_dir/

echo ""
echo "=== 运行危险脚本 ==="
cd test_dir && bash ../dangerous-script.sh

echo ""
echo "=== 脚本退出码: $? ==="
echo "=== 当前目录内容 ==="
ls -la
```

**你会看到：**

```
Step 1: 进入工作目录...
../dangerous-script.sh: line 5: cd: /nonexistent/directory: No such file or directory
Step 2: 删除临时文件...
Step 3: 完成！
```

**问题**：
1. `cd` 失败了，但脚本继续执行！
2. `rm -rf *` 在当前目录执行，删除了重要文件！
3. 脚本退出码是 0（成功），没有人知道出了问题！

这就是为什么我们需要错误处理。现在让我们学习如何写出安全的脚本。

---

## Step 1 — 严格模式：set -euo pipefail（30 分钟）

### 1.1 set -e（errexit）：命令失败时退出

`set -e` 让脚本在任何命令返回非零退出码时立即退出：

```bash
cd ~/error-lab

cat > set-e-demo.sh << 'EOF'
#!/bin/bash
set -e  # 启用 errexit

echo "Step 1: 进入工作目录..."
cd /nonexistent/directory   # 失败！脚本在这里退出

echo "Step 2: 这行不会执行"
echo "Step 3: 这行也不会执行"
EOF

bash set-e-demo.sh
echo "退出码: $?"
```

**输出：**

```
Step 1: 进入工作目录...
set-e-demo.sh: line 5: cd: /nonexistent/directory: No such file or directory
退出码: 1
```

现在脚本在失败时立即停止，不会继续执行危险操作！

### 1.2 set -e 的例外情况（重要！）

`set -e` 不是万能的，以下情况**不会**触发退出：

![set -e Exceptions](images/set-e-exceptions.png)

<details>
<summary>View ASCII source</summary>

<!-- DIAGRAM: set-e-exceptions -->
```
+-------------------------------------------------------------------------+
|  set -e 的例外情况（不会退出）                                            |
+-------------------------------------------------------------------------+
|                                                                          |
|  1. 条件判断中的命令                                                      |
|  +-----------------------------------------------------------+          |
|  |  if command; then ...      # command 失败不会退出          |          |
|  |  command && echo "ok"      # command 失败不会退出          |          |
|  |  command || echo "failed"  # command 失败不会退出          |          |
|  |  while command; do ...     # command 失败不会退出          |          |
|  |  until command; do ...     # command 失败不会退出          |          |
|  +-----------------------------------------------------------+          |
|                                                                          |
|  2. 管道中非最后一个命令                                                  |
|  +-----------------------------------------------------------+          |
|  |  false | true              # false 失败，但 true 成功，     |          |
|  |                            # 整体成功，不退出               |          |
|  |                                                            |          |
|  |  解决方案：set -o pipefail                                 |          |
|  +-----------------------------------------------------------+          |
|                                                                          |
|  3. 命令替换 $() 中的命令                                                 |
|  +-----------------------------------------------------------+          |
|  |  result=$(false)           # false 失败                    |          |
|  |  echo "继续执行"           # 这行仍然执行！                 |          |
|  |                                                            |          |
|  |  原因：$() 的退出码被赋值操作「吃掉」了                     |          |
|  +-----------------------------------------------------------+          |
|                                                                          |
|  4. 函数中的命令（除非使用 set -E）                                       |
|  +-----------------------------------------------------------+          |
|  |  my_func() {                                               |          |
|  |      false  # 失败                                         |          |
|  |  }                                                         |          |
|  |  my_func   # 函数返回失败，脚本退出                        |          |
|  |                                                            |          |
|  |  # 但如果函数在条件中调用：                                 |          |
|  |  if my_func; then ...  # 不会退出                          |          |
|  +-----------------------------------------------------------+          |
|                                                                          |
+-------------------------------------------------------------------------+
```
<!-- /DIAGRAM -->

</details>

### 1.3 实际演示：set -e 的陷阱

```bash
cd ~/error-lab

cat > set-e-traps.sh << 'EOF'
#!/bin/bash
set -e

echo "=== 陷阱 1: 条件判断 ==="
if false; then
    echo "不会到这里"
fi
echo "脚本继续执行（条件判断中的失败不触发 -e）"

echo ""
echo "=== 陷阱 2: && 和 || ==="
false && echo "不会执行"
echo "脚本继续执行（&& 左边的失败不触发 -e）"

false || echo "失败时执行这里"
echo "脚本继续执行（|| 左边的失败不触发 -e）"

echo ""
echo "=== 陷阱 3: 命令替换 ==="
result=$(cat /nonexistent/file 2>/dev/null || echo "默认值")
echo "result = $result"
echo "脚本继续执行！"

# 这里才会真正失败
echo ""
echo "=== 真正的失败 ==="
cat /nonexistent/file
echo "这行不会执行"
EOF

bash set-e-traps.sh
```

### 1.4 set -u（nounset）：使用未定义变量时报错

没有 `set -u` 时，未定义变量默认为空字符串，可能导致危险行为：

```bash
cd ~/error-lab

cat > without-set-u.sh << 'EOF'
#!/bin/bash
# 没有 set -u

echo "删除目录: $IMPORTANT_DIR"
# IMPORTANT_DIR 未定义，等于空字符串
# rm -rf "$IMPORTANT_DIR/" 会变成 rm -rf "/" ！！！

# 模拟（不实际执行）
echo "模拟执行: rm -rf \"$IMPORTANT_DIR/\""
echo "等价于: rm -rf \"/\""
EOF

bash without-set-u.sh
```

使用 `set -u` 保护：

```bash
cd ~/error-lab

cat > with-set-u.sh << 'EOF'
#!/bin/bash
set -u  # 启用 nounset

echo "删除目录: $IMPORTANT_DIR"  # 未定义，脚本退出！
echo "这行不会执行"
EOF

bash with-set-u.sh
echo "退出码: $?"
```

**输出：**

```
with-set-u.sh: line 4: IMPORTANT_DIR: unbound variable
退出码: 1
```

### 1.5 set -o pipefail：管道中任意命令失败即失败

默认情况下，管道的退出码是**最后一个**命令的退出码：

```bash
cd ~/error-lab

cat > pipeline-default.sh << 'EOF'
#!/bin/bash
set -e
# 注意：没有 pipefail

echo "=== 默认行为 ==="
cat /nonexistent/file 2>/dev/null | grep "something" | head -1
echo "管道退出码: ${PIPESTATUS[@]}"
# PIPESTATUS 数组保存管道中每个命令的退出码

echo ""
echo "脚本继续执行！（因为 head 成功了）"
EOF

bash pipeline-default.sh
```

使用 `set -o pipefail`：

```bash
cd ~/error-lab

cat > pipeline-pipefail.sh << 'EOF'
#!/bin/bash
set -eo pipefail

echo "=== 启用 pipefail ==="
cat /nonexistent/file 2>/dev/null | grep "something" | head -1
echo "这行不会执行"
EOF

bash pipeline-pipefail.sh
echo "退出码: $?"
```

### 1.6 严格模式组合：推荐的脚本头部

```bash
cd ~/error-lab

cat > strict-mode-template.sh << 'EOF'
#!/usr/bin/env bash
# =============================================================================
# 严格模式模板
# =============================================================================

# 启用严格模式
set -euo pipefail

# 可选：设置 IFS 为换行和制表符（避免空格分割问题）
IFS=$'\n\t'

# 你的脚本从这里开始...
echo "这是一个安全的脚本！"

# 测试各选项
echo ""
echo "=== 测试 set -e ==="
true
echo "true 成功后继续"

echo ""
echo "=== 测试 set -u ==="
: "${OPTIONAL_VAR:=默认值}"  # 安全地设置默认值
echo "OPTIONAL_VAR = $OPTIONAL_VAR"

echo ""
echo "=== 测试 pipefail ==="
echo "hello" | grep "hello" | cat
echo "管道成功"
EOF

bash strict-mode-template.sh
```

### 1.7 set -E：ERR trap 在函数中继承

默认情况下，ERR trap 不会在函数内触发。使用 `set -E` 让 ERR trap 传播到函数中：

```bash
cd ~/error-lab

cat > set-E-demo.sh << 'EOF'
#!/bin/bash
set -e

# 设置 ERR trap
trap 'echo "ERR trap triggered at line $LINENO"' ERR

my_function() {
    echo "在函数内..."
    false  # 这会触发 ERR trap 吗？
}

echo "=== 没有 set -E ==="
my_function || true

# 启用 set -E
set -E

echo ""
echo "=== 有 set -E ==="
my_function
EOF

bash set-E-demo.sh 2>&1 || true
```

---

## Step 2 — trap 机制详解（35 分钟）

### 2.1 什么是 trap？

`trap` 命令让你在脚本收到信号或特定事件时执行指定的命令。这是实现清理逻辑和优雅退出的关键。

![Trap Mechanism](images/trap-mechanism.png)

<details>
<summary>View ASCII source</summary>

<!-- DIAGRAM: trap-mechanism -->
```
+-------------------------------------------------------------------------+
|  trap 机制：信号与事件处理                                                |
+-------------------------------------------------------------------------+
|                                                                          |
|  语法：trap 'commands' SIGNAL [SIGNAL ...]                               |
|                                                                          |
|  +------------------+--------------------------------------------------+ |
|  |     信号         |  触发时机                                        | |
|  +------------------+--------------------------------------------------+ |
|  | EXIT             | 脚本退出时（无论正常还是异常）                    | |
|  | ERR              | 命令返回非零退出码时（需要 set -e 或 set -E）     | |
|  | INT              | 收到 SIGINT（Ctrl+C）                            | |
|  | TERM             | 收到 SIGTERM（kill 默认信号）                    | |
|  | HUP              | 收到 SIGHUP（终端关闭）                          | |
|  | DEBUG            | 每条命令执行前（用于调试）                        | |
|  | RETURN           | 函数或 source 返回时                             | |
|  +------------------+--------------------------------------------------+ |
|                                                                          |
|  常见用途：                                                               |
|  +-----------------------------------------------------------+          |
|  |  trap cleanup EXIT        # 脚本退出时清理                  |          |
|  |  trap 'rm -f "$tmpfile"' EXIT  # 删除临时文件              |          |
|  |  trap 'echo "Interrupted"; exit 1' INT TERM  # 优雅退出    |          |
|  +-----------------------------------------------------------+          |
|                                                                          |
|  取消 trap：                                                              |
|  +-----------------------------------------------------------+          |
|  |  trap - EXIT              # 取消 EXIT trap                 |          |
|  |  trap '' INT              # 忽略 INT 信号                  |          |
|  +-----------------------------------------------------------+          |
|                                                                          |
+-------------------------------------------------------------------------+
```
<!-- /DIAGRAM -->

</details>

### 2.2 EXIT trap：脚本退出时清理

这是最重要的 trap，确保无论脚本如何退出，清理逻辑都会执行：

```bash
cd ~/error-lab

cat > exit-trap-demo.sh << 'EOF'
#!/bin/bash
set -euo pipefail

# 创建临时文件
TMPFILE=$(mktemp)
echo "创建临时文件: $TMPFILE"

# 设置 EXIT trap - 脚本退出时清理
cleanup() {
    local exit_code=$?
    echo ""
    echo "=== cleanup 函数被调用 ==="
    echo "退出码: $exit_code"

    if [[ -f "$TMPFILE" ]]; then
        echo "删除临时文件: $TMPFILE"
        rm -f "$TMPFILE"
    fi

    echo "清理完成！"
}
trap cleanup EXIT

# 模拟工作
echo "写入数据到临时文件..."
echo "一些临时数据" > "$TMPFILE"
cat "$TMPFILE"

# 模拟选择：正常退出还是失败退出
echo ""
echo "选择退出方式："
echo "1. 正常退出 (exit 0)"
echo "2. 失败退出 (exit 1)"
echo "3. 触发错误 (false)"

# 这里用参数模拟选择
case "${1:-1}" in
    1) echo "正常退出..."; exit 0 ;;
    2) echo "失败退出..."; exit 1 ;;
    3) echo "触发错误..."; false ;;
esac
EOF

echo "=== 测试 1: 正常退出 ==="
bash exit-trap-demo.sh 1

echo ""
echo "=== 测试 2: 失败退出 ==="
bash exit-trap-demo.sh 2 || true

echo ""
echo "=== 测试 3: 错误触发 ==="
bash exit-trap-demo.sh 3 || true
```

**关键点**：
- EXIT trap **总是**被调用，无论脚本如何退出
- 可以在 cleanup 函数中通过 `$?` 获取原始退出码
- 这是确保资源清理的最可靠方式

### 2.3 ERR trap：错误时执行

ERR trap 在命令返回非零退出码时触发（受 `set -e` 例外规则影响）：

```bash
cd ~/error-lab

cat > err-trap-demo.sh << 'EOF'
#!/bin/bash
set -eEuo pipefail  # 注意 -E 让 ERR trap 在函数中也生效

# ERR trap - 错误发生时
on_error() {
    local exit_code=$?
    local line_no=$1
    echo ""
    echo "!!! 错误发生 !!!"
    echo "  退出码: $exit_code"
    echo "  行号:   $line_no"
    echo "  命令:   $BASH_COMMAND"
}
trap 'on_error $LINENO' ERR

# EXIT trap - 最终清理
trap 'echo "脚本退出"' EXIT

echo "Step 1: 开始执行..."
true

echo "Step 2: 继续执行..."
true

echo "Step 3: 这里会失败..."
cat /nonexistent/file

echo "Step 4: 这行不会执行"
EOF

bash err-trap-demo.sh 2>&1 || true
```

### 2.4 INT/TERM trap：处理 Ctrl+C 和 kill

生产脚本需要优雅地处理中断信号：

```bash
cd ~/error-lab

cat > signal-trap-demo.sh << 'EOF'
#!/bin/bash
set -euo pipefail

# 状态标志
INTERRUPTED=false

# INT trap - Ctrl+C
on_interrupt() {
    echo ""
    echo ">>> 收到中断信号 (SIGINT)..."
    INTERRUPTED=true
}
trap on_interrupt INT

# TERM trap - kill
on_terminate() {
    echo ""
    echo ">>> 收到终止信号 (SIGTERM)..."
    INTERRUPTED=true
}
trap on_terminate TERM

# EXIT trap - 清理
cleanup() {
    echo ""
    echo "=== 执行清理 ==="
    if [[ "$INTERRUPTED" == true ]]; then
        echo "脚本被中断，清理临时资源..."
    else
        echo "脚本正常退出..."
    fi
    echo "清理完成"
}
trap cleanup EXIT

# 长时间运行的任务
echo "开始长时间任务（按 Ctrl+C 中断）..."
for i in {1..10}; do
    if [[ "$INTERRUPTED" == true ]]; then
        echo "检测到中断，退出循环..."
        break
    fi
    echo "  工作中... ($i/10)"
    sleep 1
done

echo "任务完成！"
EOF

echo "运行脚本，3 秒后按 Ctrl+C..."
timeout 5 bash signal-trap-demo.sh || true
```

### 2.5 trap 的最佳实践

```bash
cd ~/error-lab

cat > trap-best-practices.sh << 'EOF'
#!/usr/bin/env bash
# =============================================================================
# trap 最佳实践模板
# =============================================================================

set -euo pipefail

# -----------------------------------------------------------------------------
# 全局变量
# -----------------------------------------------------------------------------
readonly SCRIPT_NAME="${0##*/}"
readonly SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

TMPDIR=""
LOCKFILE=""
CLEANUP_DONE=false

# -----------------------------------------------------------------------------
# 日志函数
# -----------------------------------------------------------------------------
log_info()  { echo "[INFO]  $*" >&2; }
log_warn()  { echo "[WARN]  $*" >&2; }
log_error() { echo "[ERROR] $*" >&2; }

# -----------------------------------------------------------------------------
# 清理函数（只执行一次）
# -----------------------------------------------------------------------------
cleanup() {
    # 防止重复执行
    if [[ "$CLEANUP_DONE" == true ]]; then
        return 0
    fi
    CLEANUP_DONE=true

    local exit_code=$?
    log_info "执行清理（退出码: $exit_code）..."

    # 删除临时目录
    if [[ -n "${TMPDIR:-}" && -d "$TMPDIR" ]]; then
        log_info "删除临时目录: $TMPDIR"
        rm -rf "$TMPDIR"
    fi

    # 释放锁文件
    if [[ -n "${LOCKFILE:-}" && -f "$LOCKFILE" ]]; then
        log_info "释放锁文件: $LOCKFILE"
        rm -f "$LOCKFILE"
    fi

    log_info "清理完成"
    return $exit_code
}

# -----------------------------------------------------------------------------
# 错误处理
# -----------------------------------------------------------------------------
on_error() {
    local exit_code=$?
    local line_no=$1
    log_error "命令失败（行 $line_no，退出码 $exit_code）"
    log_error "失败命令: $BASH_COMMAND"
}

# -----------------------------------------------------------------------------
# 信号处理
# -----------------------------------------------------------------------------
on_interrupt() {
    log_warn "收到中断信号，正在退出..."
    exit 130  # 128 + 2 (SIGINT)
}

on_terminate() {
    log_warn "收到终止信号，正在退出..."
    exit 143  # 128 + 15 (SIGTERM)
}

# -----------------------------------------------------------------------------
# 设置 trap
# -----------------------------------------------------------------------------
trap cleanup EXIT
trap 'on_error $LINENO' ERR
trap on_interrupt INT
trap on_terminate TERM

# -----------------------------------------------------------------------------
# 主程序
# -----------------------------------------------------------------------------
main() {
    log_info "脚本启动: $SCRIPT_NAME"

    # 创建临时目录
    TMPDIR=$(mktemp -d)
    log_info "创建临时目录: $TMPDIR"

    # 创建锁文件
    LOCKFILE="/tmp/${SCRIPT_NAME}.lock"
    if [[ -f "$LOCKFILE" ]]; then
        log_error "另一个实例正在运行（锁文件: $LOCKFILE）"
        exit 1
    fi
    echo $$ > "$LOCKFILE"
    log_info "创建锁文件: $LOCKFILE"

    # 模拟工作
    log_info "开始执行任务..."
    for i in {1..3}; do
        echo "  处理中... ($i/3)"
        sleep 1
    done

    log_info "任务完成！"
}

main "$@"
EOF

bash trap-best-practices.sh
```

---

## Step 3 — 实战模式（25 分钟）

### 3.1 锁文件模式：防止并发执行

生产环境中，经常需要确保脚本不会同时运行多个实例：

```bash
cd ~/error-lab

cat > lock-file-pattern.sh << 'EOF'
#!/usr/bin/env bash
set -euo pipefail

readonly SCRIPT_NAME="${0##*/}"
readonly LOCKFILE="/tmp/${SCRIPT_NAME}.lock"

# 清理函数
cleanup() {
    if [[ -f "$LOCKFILE" ]]; then
        rm -f "$LOCKFILE"
        echo "释放锁文件"
    fi
}
trap cleanup EXIT

# 获取锁
acquire_lock() {
    # 使用 flock（更安全，但需要 fd）
    # 这里使用简单的文件检查方式

    if [[ -f "$LOCKFILE" ]]; then
        local pid
        pid=$(cat "$LOCKFILE" 2>/dev/null || echo "unknown")

        # 检查进程是否还在运行
        if [[ "$pid" != "unknown" ]] && kill -0 "$pid" 2>/dev/null; then
            echo "错误: 另一个实例正在运行 (PID: $pid)"
            exit 1
        else
            echo "警告: 发现陈旧的锁文件，清理中..."
            rm -f "$LOCKFILE"
        fi
    fi

    # 创建锁文件
    echo $$ > "$LOCKFILE"
    echo "获取锁成功 (PID: $$)"
}

# 主程序
main() {
    acquire_lock

    echo "执行任务..."
    sleep 5  # 模拟长时间任务
    echo "任务完成"
}

main "$@"
EOF

echo "=== 测试 1: 正常运行 ==="
bash lock-file-pattern.sh &
sleep 1

echo ""
echo "=== 测试 2: 尝试并发运行（应该失败）==="
bash lock-file-pattern.sh || true

wait
echo ""
echo "=== 锁已释放 ==="
```

### 3.2 使用 flock 的更安全锁文件

`flock` 命令提供更可靠的文件锁定机制：

```bash
cd ~/error-lab

cat > flock-pattern.sh << 'EOF'
#!/usr/bin/env bash
set -euo pipefail

readonly LOCKFILE="/tmp/${0##*/}.lock"

# 使用 flock 获取排他锁
exec 200>"$LOCKFILE"
if ! flock -n 200; then
    echo "错误: 另一个实例正在运行"
    exit 1
fi

# 锁文件会在脚本退出时自动释放（文件描述符关闭）

echo "获取锁成功，执行任务..."
sleep 3
echo "任务完成"
EOF

bash flock-pattern.sh &
sleep 1
bash flock-pattern.sh || true
wait
```

### 3.3 原子写入模式：安全更新文件

直接修改文件可能导致数据损坏（如果脚本中途被中断）。使用原子写入模式更安全：

```bash
cd ~/error-lab

cat > atomic-write-pattern.sh << 'EOF'
#!/usr/bin/env bash
set -euo pipefail

readonly TARGET_FILE="config.txt"
TMPFILE=""

# 清理临时文件
cleanup() {
    if [[ -n "${TMPFILE:-}" && -f "$TMPFILE" ]]; then
        rm -f "$TMPFILE"
    fi
}
trap cleanup EXIT

# 原子写入函数
atomic_write() {
    local target="$1"
    local content="$2"

    # 创建临时文件（在同一目录，确保同一文件系统）
    TMPFILE=$(mktemp "${target}.XXXXXX")

    # 写入临时文件
    echo "$content" > "$TMPFILE"

    # 设置权限（与目标文件相同，如果存在）
    if [[ -f "$target" ]]; then
        chmod --reference="$target" "$TMPFILE" 2>/dev/null || true
    fi

    # 原子替换（mv 在同一文件系统是原子的）
    mv -f "$TMPFILE" "$target"
    TMPFILE=""  # 清除变量，避免 cleanup 删除

    echo "文件已更新: $target"
}

# 演示
echo "=== 原始文件 ==="
echo "version=1.0" > "$TARGET_FILE"
cat "$TARGET_FILE"

echo ""
echo "=== 原子更新 ==="
atomic_write "$TARGET_FILE" "version=2.0
updated=$(date)"

echo ""
echo "=== 更新后 ==="
cat "$TARGET_FILE"

rm -f "$TARGET_FILE"
EOF

bash atomic-write-pattern.sh
```

### 3.4 安全的临时文件处理

```bash
cd ~/error-lab

cat > safe-tmpfile.sh << 'EOF'
#!/usr/bin/env bash
set -euo pipefail

# 全局变量保存临时文件列表
declare -a TMPFILES=()
TMPDIR=""

# 清理所有临时资源
cleanup() {
    local exit_code=$?

    # 删除临时文件
    for tmpfile in "${TMPFILES[@]:-}"; do
        if [[ -f "$tmpfile" ]]; then
            rm -f "$tmpfile"
            echo "删除临时文件: $tmpfile"
        fi
    done

    # 删除临时目录
    if [[ -n "${TMPDIR:-}" && -d "$TMPDIR" ]]; then
        rm -rf "$TMPDIR"
        echo "删除临时目录: $TMPDIR"
    fi

    return $exit_code
}
trap cleanup EXIT

# 创建临时文件的安全函数
make_temp() {
    local tmpfile
    tmpfile=$(mktemp)
    TMPFILES+=("$tmpfile")
    echo "$tmpfile"
}

# 创建临时目录的安全函数
make_temp_dir() {
    TMPDIR=$(mktemp -d)
    echo "$TMPDIR"
}

# 演示
main() {
    echo "=== 创建临时资源 ==="

    local file1
    file1=$(make_temp)
    echo "临时文件 1: $file1"

    local file2
    file2=$(make_temp)
    echo "临时文件 2: $file2"

    local dir
    dir=$(make_temp_dir)
    echo "临时目录: $dir"

    # 使用临时文件
    echo "写入数据..."
    echo "data1" > "$file1"
    echo "data2" > "$file2"
    touch "$dir/test.txt"

    echo ""
    echo "=== 临时文件内容 ==="
    ls -la "${TMPFILES[@]}" "$TMPDIR"

    echo ""
    echo "脚本正常结束，清理将自动执行..."
}

main "$@"
EOF

bash safe-tmpfile.sh
```

---

## Step 4 — Mini Project：安全的临时文件处理（20 分钟）

> **项目目标**：创建一个使用临时文件进行数据处理的脚本，确保无论如何退出，临时文件都会被清理。  

### 4.1 项目要求

创建 `safe-processor.sh`：

1. 使用严格模式（`set -euo pipefail`）
2. 创建临时文件存储中间数据
3. 实现 EXIT trap 确保清理
4. 处理 INT/TERM 信号实现优雅退出
5. 实现锁文件防止并发执行
6. 通过 ShellCheck 检查

### 4.2 完整实现

```bash
cd ~/error-lab

cat > safe-processor.sh << 'EOF'
#!/usr/bin/env bash
# =============================================================================
# 文件名：safe-processor.sh
# 功能：安全的数据处理脚本（演示错误处理最佳实践）
# 用法：./safe-processor.sh <输入文件>
# =============================================================================

# -----------------------------------------------------------------------------
# 严格模式
# -----------------------------------------------------------------------------
set -euo pipefail
IFS=$'\n\t'

# -----------------------------------------------------------------------------
# 常量
# -----------------------------------------------------------------------------
readonly SCRIPT_NAME="${0##*/}"
readonly SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
readonly LOCKFILE="/tmp/${SCRIPT_NAME}.lock"

# -----------------------------------------------------------------------------
# 全局变量
# -----------------------------------------------------------------------------
TMPDIR=""
INTERRUPTED=false
CLEANUP_DONE=false

# -----------------------------------------------------------------------------
# 颜色
# -----------------------------------------------------------------------------
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[0;33m'
readonly NC='\033[0m'

# -----------------------------------------------------------------------------
# 日志函数
# -----------------------------------------------------------------------------
log_info()  { echo -e "${GREEN}[INFO]${NC}  $*" >&2; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $*" >&2; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# -----------------------------------------------------------------------------
# 帮助信息
# -----------------------------------------------------------------------------
usage() {
    cat << HELP
用法: $SCRIPT_NAME [选项] <输入文件>

安全地处理数据文件，演示错误处理最佳实践。

选项:
    -h, --help      显示此帮助信息
    -v, --verbose   显示详细输出
    -o, --output    指定输出文件（默认: stdout）

示例:
    $SCRIPT_NAME input.txt
    $SCRIPT_NAME -o result.txt input.txt

特性:
    - 严格模式（set -euo pipefail）
    - 临时文件自动清理（trap EXIT）
    - 信号处理（INT, TERM）
    - 锁文件防止并发
HELP
}

# -----------------------------------------------------------------------------
# 清理函数
# -----------------------------------------------------------------------------
cleanup() {
    # 防止重复执行
    if [[ "$CLEANUP_DONE" == true ]]; then
        return 0
    fi
    CLEANUP_DONE=true

    local exit_code=$?
    log_info "执行清理..."

    # 删除临时目录及其内容
    if [[ -n "${TMPDIR:-}" && -d "$TMPDIR" ]]; then
        rm -rf "$TMPDIR"
        log_info "已删除临时目录: $TMPDIR"
    fi

    # 释放锁文件
    if [[ -f "$LOCKFILE" ]]; then
        rm -f "$LOCKFILE"
        log_info "已释放锁文件"
    fi

    if [[ $exit_code -eq 0 ]]; then
        log_info "脚本正常退出"
    else
        log_warn "脚本异常退出（退出码: $exit_code）"
    fi

    return $exit_code
}

# -----------------------------------------------------------------------------
# 错误处理
# -----------------------------------------------------------------------------
on_error() {
    local exit_code=$?
    local line_no=$1
    log_error "命令失败"
    log_error "  位置: 行 $line_no"
    log_error "  命令: $BASH_COMMAND"
    log_error "  退出码: $exit_code"
}

# -----------------------------------------------------------------------------
# 信号处理
# -----------------------------------------------------------------------------
on_interrupt() {
    log_warn ""
    log_warn "收到中断信号 (Ctrl+C)..."
    INTERRUPTED=true
    exit 130
}

on_terminate() {
    log_warn ""
    log_warn "收到终止信号..."
    INTERRUPTED=true
    exit 143
}

# -----------------------------------------------------------------------------
# 设置 trap
# -----------------------------------------------------------------------------
trap cleanup EXIT
trap 'on_error $LINENO' ERR
trap on_interrupt INT
trap on_terminate TERM

# -----------------------------------------------------------------------------
# 获取锁
# -----------------------------------------------------------------------------
acquire_lock() {
    if [[ -f "$LOCKFILE" ]]; then
        local pid
        pid=$(cat "$LOCKFILE" 2>/dev/null || echo "")

        if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
            log_error "另一个实例正在运行 (PID: $pid)"
            log_error "如果确定没有运行，请删除: $LOCKFILE"
            exit 1
        fi

        log_warn "发现陈旧的锁文件，清理..."
        rm -f "$LOCKFILE"
    fi

    echo $$ > "$LOCKFILE"
    log_info "获取锁成功 (PID: $$)"
}

# -----------------------------------------------------------------------------
# 数据处理函数
# -----------------------------------------------------------------------------
process_data() {
    local input_file="$1"
    local output_file="${2:-}"

    log_info "开始处理: $input_file"

    # 创建临时目录
    TMPDIR=$(mktemp -d)
    log_info "创建临时目录: $TMPDIR"

    # 临时文件
    local tmp_sorted="$TMPDIR/sorted.tmp"
    local tmp_unique="$TMPDIR/unique.tmp"
    local tmp_result="$TMPDIR/result.tmp"

    # 步骤 1：排序
    log_info "步骤 1/3：排序..."
    sort "$input_file" > "$tmp_sorted"

    # 检查中断
    if [[ "$INTERRUPTED" == true ]]; then
        log_warn "处理被中断"
        return 1
    fi

    # 步骤 2：去重
    log_info "步骤 2/3：去重..."
    uniq "$tmp_sorted" > "$tmp_unique"

    # 步骤 3：统计
    log_info "步骤 3/3：统计..."
    {
        echo "=== 处理结果 ==="
        echo "处理时间: $(date)"
        echo "输入文件: $input_file"
        echo "原始行数: $(wc -l < "$input_file")"
        echo "去重后行数: $(wc -l < "$tmp_unique")"
        echo ""
        echo "=== 去重后内容 ==="
        cat "$tmp_unique"
    } > "$tmp_result"

    # 输出结果
    if [[ -n "$output_file" ]]; then
        mv "$tmp_result" "$output_file"
        log_info "结果已保存到: $output_file"
    else
        cat "$tmp_result"
    fi

    log_info "处理完成！"
}

# -----------------------------------------------------------------------------
# 主程序
# -----------------------------------------------------------------------------
main() {
    local verbose=false
    local output_file=""
    local input_file=""

    # 解析参数
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                usage
                exit 0
                ;;
            -v|--verbose)
                verbose=true
                shift
                ;;
            -o|--output)
                output_file="$2"
                shift 2
                ;;
            -*)
                log_error "未知选项: $1"
                usage
                exit 1
                ;;
            *)
                input_file="$1"
                shift
                ;;
        esac
    done

    # 验证参数
    if [[ -z "$input_file" ]]; then
        log_error "缺少输入文件"
        usage
        exit 1
    fi

    if [[ ! -f "$input_file" ]]; then
        log_error "输入文件不存在: $input_file"
        exit 1
    fi

    # 获取锁
    acquire_lock

    # 处理数据
    process_data "$input_file" "$output_file"
}

main "$@"
EOF

chmod +x safe-processor.sh

# 创建测试数据
cat > test-input.txt << 'EOF'
apple
banana
apple
cherry
banana
date
apple
EOF

echo "=== 测试 1: 正常处理 ==="
./safe-processor.sh test-input.txt

echo ""
echo "=== 测试 2: 输出到文件 ==="
./safe-processor.sh -o result.txt test-input.txt
cat result.txt

echo ""
echo "=== 测试 3: ShellCheck ==="
shellcheck safe-processor.sh && echo "ShellCheck 通过！"

rm -f test-input.txt result.txt
```

---

## 速查表（Cheatsheet）

```bash
# =============================================================================
# 错误处理速查表
# =============================================================================

# --- 严格模式 ---
set -e              # 命令失败时退出
set -u              # 使用未定义变量时报错
set -o pipefail     # 管道中任意命令失败即失败
set -E              # ERR trap 在函数中继承
set -euo pipefail   # 组合使用（推荐）

# --- trap 语法 ---
trap 'commands' SIGNAL    # 设置 trap
trap - SIGNAL             # 取消 trap
trap '' SIGNAL            # 忽略信号

# --- 常用信号 ---
EXIT    # 脚本退出（最重要！）
ERR     # 命令失败（需要 set -e 或 set -E）
INT     # Ctrl+C (SIGINT)
TERM    # kill 默认信号 (SIGTERM)
HUP     # 终端关闭 (SIGHUP)

# --- 退出码约定 ---
0       # 成功
1       # 一般错误
2       # 参数错误
126     # 权限拒绝
127     # 命令不存在
128+N   # 信号 N 导致退出（如 130 = 128+2 = SIGINT）

# --- 常用模式 ---
# 清理临时文件
trap 'rm -f "$TMPFILE"' EXIT

# 错误信息
trap 'echo "Error at line $LINENO" >&2' ERR

# 优雅退出
trap 'echo "Interrupted"; exit 1' INT TERM

# 锁文件
exec 200>"$LOCKFILE"
flock -n 200 || exit 1

# 原子写入
tmp=$(mktemp "${target}.XXXXXX")
echo "content" > "$tmp"
mv -f "$tmp" "$target"
```

---

## 反模式：常见错误

### 错误 1：没有任何错误处理

```bash
# 危险：cd 失败后继续执行 rm
cd /some/directory
rm -rf *

# 正确：使用 set -e 或显式检查
set -e
cd /some/directory
rm -rf *

# 或者
cd /some/directory || exit 1
rm -rf *
```

### 错误 2：不理解 set -e 的例外

```bash
# 错误认知：以为 set -e 能捕获所有错误
set -e

# 这个失败不会退出脚本！
if grep "pattern" file; then
    echo "found"
fi

# 这个失败也不会退出！
result=$(cat /nonexistent 2>/dev/null || echo "default")
```

### 错误 3：忘记清理临时文件

```bash
# 危险：如果脚本中途退出，临时文件残留
tmpfile=$(mktemp)
# ... 一堆操作 ...
rm -f "$tmpfile"  # 可能永远执行不到！

# 正确：使用 trap 确保清理
tmpfile=$(mktemp)
trap 'rm -f "$tmpfile"' EXIT
# ... 一堆操作 ...
# 不需要显式 rm，trap 会处理
```

### 错误 4：忽略信号处理

```bash
# 问题：长时间运行的脚本被 Ctrl+C 中断后没有清理
for file in *.txt; do
    process "$file"  # 如果中途 Ctrl+C，可能留下半成品
done

# 正确：处理中断信号
interrupted=false
trap 'interrupted=true' INT

for file in *.txt; do
    if [[ "$interrupted" == true ]]; then
        echo "中断，清理中..."
        break
    fi
    process "$file"
done
```

---

## 职场小贴士（Japan IT Context）

### 日本企业的脚本规范

在日本 IT 企业的运维现场，エラーハンドリング（错误处理）是代码审查的重点：

| 日语术语 | 含义 | 要求 |
|----------|------|------|
| エラーハンドリング | Error Handling | 必须有 set -e 或显式检查 |
| 後処理 | 后处理/清理 | 必须用 trap EXIT 清理临时资源 |
| 排他制御 | 互斥控制 | 关键脚本必须有锁文件 |
| ログ出力 | 日志输出 | 错误信息输出到 stderr |
| 戻り値 | 返回值 | 必须检查命令的退出码 |

### 运维脚本标准头部

```bash
#!/usr/bin/env bash
# ==============================================================================
# ファイル名：script_name.sh
# 概要：スクリプトの説明
# 作成者：山田太郎
# 作成日：2026-01-10
# 変更履歴：
#   2026-01-10 新規作成
# ==============================================================================

set -euo pipefail

# ログ関数
log_info()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO]  $*" | tee -a "$LOG_FILE"; }
log_error() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $*" | tee -a "$LOG_FILE" >&2; }

# クリーンアップ
cleanup() {
    local exit_code=$?
    # 一時ファイル削除
    [[ -f "${TMPFILE:-}" ]] && rm -f "$TMPFILE"
    # ロックファイル解放
    [[ -f "${LOCKFILE:-}" ]] && rm -f "$LOCKFILE"
    log_info "スクリプト終了（終了コード: $exit_code）"
}
trap cleanup EXIT
```

### 监控脚本的错误处理

```bash
#!/bin/bash
# 監視スクリプト - Zabbix UserParameter 用

set -euo pipefail

# エラー時は N/A を返す
on_error() {
    echo "N/A"
    exit 0  # Zabbix に異常を伝える
}
trap on_error ERR

# 監視対象のチェック
check_process() {
    pgrep -c "$1" 2>/dev/null || echo "0"
}

check_process "${1:-nginx}"
```

---

## 检查清单

完成本课后，你应该能够：

- [ ] 使用 `set -e` 让命令失败时退出
- [ ] 理解 `set -e` 的例外情况
- [ ] 使用 `set -u` 检测未定义变量
- [ ] 使用 `set -o pipefail` 处理管道错误
- [ ] 使用 `trap EXIT` 确保清理逻辑执行
- [ ] 使用 `trap ERR` 在错误时执行处理
- [ ] 使用 `trap INT TERM` 处理中断信号
- [ ] 实现锁文件模式防止并发
- [ ] 实现原子写入模式安全更新文件
- [ ] 创建临时文件并确保清理

**验证命令：**

```bash
cd ~/error-lab

# 测试 1: set -e
bash -c 'set -e; false; echo "不应该到这里"' || echo "正确：脚本退出了"

# 测试 2: set -u
bash -c 'set -u; echo "$UNDEFINED"' 2>&1 | grep -q "unbound" && echo "正确：检测到未定义变量"

# 测试 3: pipefail
bash -c 'set -eo pipefail; false | true; echo "不应该到这里"' || echo "正确：管道失败退出了"

# 测试 4: trap EXIT
bash -c 'trap "echo 清理完成" EXIT; exit 0' | grep -q "清理" && echo "正确：trap 被执行"

# 测试 5: ShellCheck
shellcheck safe-processor.sh && echo "ShellCheck 通过"
```

---

## 本课小结

| 机制 | 语法 | 用途 |
|------|------|------|
| `set -e` | errexit | 命令失败时退出 |
| `set -u` | nounset | 使用未定义变量时报错 |
| `set -o pipefail` | pipefail | 管道中任意命令失败即失败 |
| `set -E` | errtrace | ERR trap 在函数中继承 |
| `trap 'cmd' EXIT` | EXIT trap | 脚本退出时执行清理 |
| `trap 'cmd' ERR` | ERR trap | 命令失败时执行 |
| `trap 'cmd' INT TERM` | 信号 trap | 处理中断和终止信号 |

**严格模式模板（必背！）：**

```bash
#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

cleanup() {
    rm -f "$TMPFILE"
}
trap cleanup EXIT

TMPFILE=$(mktemp)
# 你的代码...
```

---

## 面试准备

### **set -e の制限は何ですか？**

`set -e` は以下の場合に終了しません：
- 条件文内のコマンド（`if command; then`）
- `&&` や `||` の左辺
- `$()` 内のコマンド（代入時）
- パイプラインの最後以外のコマンド（`pipefail` なしの場合）

```bash
set -e
if false; then echo "no"; fi  # 終了しない
false || true                  # 終了しない
result=$(false)               # 終了しない（代入が成功）
false | true                  # 終了しない（pipefail なし）
```

### **trap EXIT の用途は？**

スクリプト終了時のクリーンアップ（一時ファイル削除、ロック解除など）に使用します。正常終了でも異常終了でも必ず実行されるため、リソースリークを防げます。

```bash
TMPFILE=$(mktemp)
trap 'rm -f "$TMPFILE"' EXIT

# スクリプトがどう終了しても $TMPFILE は削除される
```

---

## 延伸阅读

- [Bash Reference Manual - The Set Builtin](https://www.gnu.org/software/bash/manual/html_node/The-Set-Builtin.html) - GNU Bash 官方文档
- [Bash Reference Manual - Signals](https://www.gnu.org/software/bash/manual/html_node/Signals.html) - 信号处理
- [Bash Strict Mode](http://redsymbol.net/articles/unofficial-bash-strict-mode/) - 非官方严格模式指南
- 上一课：[08 - 参数展开](../08-expansion/) — 字符串操作与默认值
- 下一课：[10 - 命令行参数处理](../10-arguments/) — getopts 与 CLI 设计

---

## 清理

```bash
# 清理练习文件
cd ~
rm -rf ~/error-lab
```

---

## 系列导航

[<-- 08 - 参数展开](../08-expansion/) | [课程首页](../) | [10 - 命令行参数处理 -->](../10-arguments/)
