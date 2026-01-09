# 10 - 命令行参数处理（Argument Parsing）

> **目标**：掌握 getopts 和 getopt，创建用户友好的 CLI 接口  
> **前置**：[09 - 错误处理与 trap](../09-error-handling/)  
> **时间**：90-120 分钟  
> **环境**：Bash 4.x+（RHEL 7/8/9, Ubuntu 18.04+ 均可）  

---

## 将学到的内容

1. 使用位置参数（$1, $2, shift）
2. 使用 getopts 解析短选项
3. 使用 getopt 解析长选项（GNU）
4. 设计用户友好的 CLI 接口
5. 实现 --help 和 --version

---

## 先跑起来！（5 分钟）

> 在理解原理之前，先体验一个完整的 CLI 脚本。  
> 感受专业命令行工具的交互方式。  

```bash
# 创建练习目录
mkdir -p ~/arguments-lab && cd ~/arguments-lab

# 创建一个完整的 CLI 脚本
cat > greet.sh << 'EOF'
#!/bin/bash
set -euo pipefail

VERSION="1.0.0"
VERBOSE=false
NAME=""
COUNT=1

usage() {
    cat << HELP
Usage: $(basename "$0") [OPTIONS] NAME

A friendly greeting script.

Arguments:
    NAME            Name to greet (required)

Options:
    -c, --count N   Number of greetings (default: 1)
    -v, --verbose   Verbose output
    -h, --help      Show this help
    --version       Show version

Examples:
    $(basename "$0") Alice
    $(basename "$0") -c 3 Bob
    $(basename "$0") --verbose --count 2 Charlie
HELP
}

# 解析参数
while [[ $# -gt 0 ]]; do
    case "$1" in
        -c|--count)
            COUNT="$2"
            shift 2
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        --version)
            echo "greet.sh version $VERSION"
            exit 0
            ;;
        -*)
            echo "Error: Unknown option: $1" >&2
            usage >&2
            exit 1
            ;;
        *)
            NAME="$1"
            shift
            ;;
    esac
done

# 验证必需参数
if [[ -z "$NAME" ]]; then
    echo "Error: NAME is required" >&2
    usage >&2
    exit 1
fi

# 执行主逻辑
if $VERBOSE; then
    echo "Greeting $NAME $COUNT time(s)..."
fi

for ((i=1; i<=COUNT; i++)); do
    echo "Hello, $NAME!"
done
EOF

chmod +x greet.sh

# 测试各种用法
echo "=== 基本用法 ==="
./greet.sh Alice

echo ""
echo "=== 带选项 ==="
./greet.sh -c 3 Bob

echo ""
echo "=== 长选项 ==="
./greet.sh --verbose --count 2 Charlie

echo ""
echo "=== 帮助信息 ==="
./greet.sh --help
```

**你应该看到类似的输出：**

```
=== 基本用法 ===
Hello, Alice!

=== 带选项 ===
Hello, Bob!
Hello, Bob!
Hello, Bob!

=== 长选项 ===
Greeting Charlie 2 time(s)...
Hello, Charlie!
Hello, Charlie!

=== 帮助信息 ===
Usage: greet.sh [OPTIONS] NAME
...
```

**这就是专业 CLI 工具的样子！** 支持短选项、长选项、帮助信息、版本信息。

现在让我们从基础开始，逐步理解参数处理的各种方式。

---

## Step 1 — 位置参数基础（15 分钟）

### 1.1 位置参数概览

Shell 脚本通过位置参数接收命令行参数：

![Positional Parameters](images/positional-params.png)

<details>
<summary>View ASCII source</summary>

<!-- DIAGRAM: positional-params -->
```
┌─────────────────────────────────────────────────────────────────────────┐
│  位置参数（Positional Parameters）                                        │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  命令行：./script.sh arg1 arg2 arg3 ... arg10 arg11                      │
│                │      │    │    │       │     │                          │
│                ▼      ▼    ▼    ▼       ▼     ▼                          │
│  脚本内部：   $0     $1   $2   $3    ${10} ${11}                          │
│                                                                          │
│  特殊变量：                                                               │
│  ┌──────────┬────────────────────────────────────────────────────────┐  │
│  │ 变量      │ 含义                                                    │  │
│  ├──────────┼────────────────────────────────────────────────────────┤  │
│  │ $0       │ 脚本名称（包含路径）                                     │  │
│  │ $1-$9    │ 第 1-9 个参数                                           │  │
│  │ ${10}+   │ 第 10 个及以后（必须用花括号）                           │  │
│  │ $#       │ 参数个数（不含 $0）                                      │  │
│  │ $@       │ 所有参数，保持分隔（推荐）                               │  │
│  │ $*       │ 所有参数，合并为一个字符串                               │  │
│  │ "$@"     │ "arg1" "arg2" "arg3"  ← 各自独立，推荐                  │  │
│  │ "$*"     │ "arg1 arg2 arg3"      ← 合并为一个                      │  │
│  └──────────┴────────────────────────────────────────────────────────┘  │
│                                                                          │
│  注意：$10 会被解释为 ${1}0，必须用 ${10}                                 │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```
<!-- /DIAGRAM -->

</details>

### 1.2 基本位置参数演示

```bash
cd ~/arguments-lab

cat > positional-demo.sh << 'EOF'
#!/bin/bash
# 位置参数演示

echo "=== 基本位置参数 ==="
echo "脚本名称 (\$0):    $0"
echo "第一个参数 (\$1):  ${1:-未提供}"
echo "第二个参数 (\$2):  ${2:-未提供}"
echo "第三个参数 (\$3):  ${3:-未提供}"
echo "参数个数 (\$#):    $#"
echo ""

echo "=== 所有参数 ==="
echo "\$@: $@"
echo "\$*: $*"
echo ""

echo "=== 遍历参数 ==="
echo "使用 \"\$@\" 遍历："
count=1
for arg in "$@"; do
    echo "  参数 $count: '$arg'"
    ((count++))
done

echo ""
echo "参数中包含空格时，\"\$@\" 和 \"\$*\" 的区别："
echo "  \"\$@\" 保持各参数独立"
echo "  \"\$*\" 将所有参数合并"
EOF

chmod +x positional-demo.sh

# 测试
echo "=== 测试 1: 简单参数 ==="
./positional-demo.sh hello world

echo ""
echo "=== 测试 2: 参数包含空格 ==="
./positional-demo.sh "hello world" "foo bar" baz
```

### 1.3 超过 9 个参数

```bash
cd ~/arguments-lab

cat > many-params.sh << 'EOF'
#!/bin/bash
# 处理超过 9 个参数

echo "参数个数: $#"
echo ""

# 错误方式
echo "错误方式 - \$10 被解释为 \${1}0："
echo "  \$10 = $10"   # 实际是 ${1}0

# 正确方式
echo ""
echo "正确方式 - 使用花括号 \${10}："
if [[ $# -ge 10 ]]; then
    echo "  \${10} = ${10}"
    echo "  \${11} = ${11:-未提供}"
fi

echo ""
echo "遍历所有参数（推荐方式）："
i=1
for arg in "$@"; do
    echo "  参数 $i: $arg"
    ((i++))
done
EOF

chmod +x many-params.sh
./many-params.sh a b c d e f g h i j k l
```

---

## Step 2 — shift 命令（15 分钟）

### 2.1 shift 的作用

`shift` 命令将位置参数左移，是处理命令行参数的核心技巧：

![Shift Command](images/shift-command.png)

<details>
<summary>View ASCII source</summary>

<!-- DIAGRAM: shift-command -->
```
┌─────────────────────────────────────────────────────────────────────────┐
│  shift 命令：位置参数左移                                                 │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  初始状态：./script.sh -v -o output.txt input.txt                        │
│                                                                          │
│      $1      $2      $3           $4                                     │
│      ↓       ↓       ↓            ↓                                      │
│     -v      -o    output.txt   input.txt        $# = 4                  │
│                                                                          │
│  执行 shift 后：                                                         │
│                                                                          │
│      $1      $2          $3                                              │
│      ↓       ↓           ↓                                               │
│     -o    output.txt   input.txt                $# = 3                  │
│                                                                          │
│  再执行 shift 2 后：                                                      │
│                                                                          │
│      $1                                                                  │
│      ↓                                                                   │
│   input.txt                                     $# = 1                  │
│                                                                          │
│  用法：                                                                   │
│  - shift      左移 1 位（等同 shift 1）                                  │
│  - shift N    左移 N 位                                                  │
│  - 原来的 $1 被丢弃，无法恢复                                             │
│                                                                          │
│  常见模式：                                                               │
│  while [[ $# -gt 0 ]]; do                                               │
│      case "$1" in                                                       │
│          -o) output="$2"; shift 2 ;;   # 带值选项：移动 2 位            │
│          -v) verbose=true; shift ;;     # 标志选项：移动 1 位            │
│          *)  args+=("$1"); shift ;;     # 位置参数：保存并移动           │
│      esac                                                               │
│  done                                                                   │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```
<!-- /DIAGRAM -->

</details>

### 2.2 shift 基础演示

```bash
cd ~/arguments-lab

cat > shift-demo.sh << 'EOF'
#!/bin/bash
# shift 命令演示

show_params() {
    echo "  \$# = $#"
    echo "  \$1 = ${1:-空}"
    echo "  \$2 = ${2:-空}"
    echo "  \$3 = ${3:-空}"
    echo "  \$@ = $@"
    echo ""
}

echo "=== 初始状态 ==="
show_params "$@"

echo "=== 执行 shift ==="
shift
show_params "$@"

echo "=== 再执行 shift 2 ==="
if [[ $# -ge 2 ]]; then
    shift 2
    show_params "$@"
else
    echo "参数不足，无法 shift 2"
fi
EOF

chmod +x shift-demo.sh
./shift-demo.sh one two three four five
```

### 2.3 使用 shift 处理选项

```bash
cd ~/arguments-lab

cat > shift-options.sh << 'EOF'
#!/bin/bash
# 使用 shift 处理命令行选项

# 默认值
verbose=false
output=""
files=()

# 处理参数
while [[ $# -gt 0 ]]; do
    case "$1" in
        -v|--verbose)
            verbose=true
            shift
            ;;
        -o|--output)
            if [[ -n "${2:-}" ]]; then
                output="$2"
                shift 2
            else
                echo "Error: --output requires a value" >&2
                exit 1
            fi
            ;;
        -*)
            echo "Error: Unknown option: $1" >&2
            exit 1
            ;;
        *)
            # 非选项参数，保存到数组
            files+=("$1")
            shift
            ;;
    esac
done

# 显示解析结果
echo "解析结果："
echo "  verbose: $verbose"
echo "  output:  ${output:-未指定}"
echo "  files:   ${files[*]:-无}"
EOF

chmod +x shift-options.sh

# 测试各种组合
echo "=== 测试 1: 基本选项 ==="
./shift-options.sh -v -o result.txt file1.txt file2.txt

echo ""
echo "=== 测试 2: 长选项 ==="
./shift-options.sh --verbose --output=result.txt data.csv

echo ""
echo "=== 测试 3: 混合顺序 ==="
./shift-options.sh file1.txt -v file2.txt -o out.txt file3.txt
```

### 2.4 shift 的注意事项

```bash
cd ~/arguments-lab

cat > shift-caution.sh << 'EOF'
#!/bin/bash
# shift 注意事项

# 1. shift 超过参数个数会失败
echo "=== shift 超限 ==="
set -- one two  # 设置位置参数
echo "参数: $@"
shift 3 2>/dev/null || echo "Error: shift 3 失败（只有 2 个参数）"

# 2. 检查后再 shift
echo ""
echo "=== 安全的 shift ==="
set -- -o
if [[ "$1" == "-o" ]]; then
    if [[ -n "${2:-}" ]]; then
        echo "output = $2"
        shift 2
    else
        echo "Error: -o 需要一个值" >&2
    fi
fi

# 3. 保存原始参数
echo ""
echo "=== 保存原始参数 ==="
original_args=("$@")
set -- one two three
shift 2
echo "当前参数: $@"
echo "原始参数: ${original_args[*]}"
EOF

bash shift-caution.sh
```

---

## Step 3 — getopts 内置命令（25 分钟）

### 3.1 getopts 基础

`getopts` 是 Bash 内置命令，用于解析**短选项**（如 `-a`, `-b value`）：

![getopts Syntax](images/getopts-syntax.png)

<details>
<summary>View ASCII source</summary>

<!-- DIAGRAM: getopts-syntax -->
```
┌─────────────────────────────────────────────────────────────────────────┐
│  getopts 语法详解                                                         │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  语法：getopts "optstring" varname                                       │
│                                                                          │
│  optstring 定义：                                                        │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  "vho:f:"                                                        │   │
│  │   │││ │                                                          │   │
│  │   │││ └─ f: → -f 需要参数值                                      │   │
│  │   ││└─── o: → -o 需要参数值                                      │   │
│  │   │└──── h  → -h 不需要参数值（标志）                            │   │
│  │   └───── v  → -v 不需要参数值（标志）                            │   │
│  │                                                                  │   │
│  │  冒号规则：                                                       │   │
│  │  - 字母后有 : → 该选项需要参数值                                  │   │
│  │  - 字母后无 : → 该选项是标志（开关）                              │   │
│  │  - 开头有 :   → 静默模式（自己处理错误）                          │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                          │
│  特殊变量：                                                              │
│  ┌──────────┬────────────────────────────────────────────────────────┐ │
│  │ 变量      │ 含义                                                    │ │
│  ├──────────┼────────────────────────────────────────────────────────┤ │
│  │ OPTARG   │ 当前选项的参数值（如 -o value 中的 value）              │ │
│  │ OPTIND   │ 下一个要处理的参数索引（从 1 开始）                      │ │
│  │ varname  │ 当前选项字母（如 o, v, h）                              │ │
│  └──────────┴────────────────────────────────────────────────────────┘ │
│                                                                          │
│  基本模式：                                                              │
│  while getopts "vho:f:" opt; do                                         │
│      case "$opt" in                                                     │
│          v) verbose=true ;;                                             │
│          h) show_help; exit 0 ;;                                        │
│          o) output="$OPTARG" ;;                                         │
│          f) file="$OPTARG" ;;                                           │
│          ?) exit 1 ;;  # 未知选项                                       │
│      esac                                                               │
│  done                                                                   │
│  shift $((OPTIND - 1))  # 移除已处理的选项，剩余是位置参数              │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```
<!-- /DIAGRAM -->

</details>

### 3.2 getopts 基础示例

```bash
cd ~/arguments-lab

cat > getopts-basic.sh << 'EOF'
#!/bin/bash
# getopts 基础演示

# 默认值
verbose=false
debug=false
output=""
file=""

# 显示帮助
usage() {
    cat << HELP
Usage: $(basename "$0") [OPTIONS] [ARGS...]

Options:
    -v          Verbose mode
    -d          Debug mode
    -o FILE     Output file
    -f FILE     Input file
    -h          Show this help
HELP
}

# 解析选项
# optstring: vdho:f:
# - v, d, h 是标志选项（不需要值）
# - o:, f: 是带值选项（冒号表示需要值）
while getopts "vdho:f:" opt; do
    case "$opt" in
        v)
            verbose=true
            ;;
        d)
            debug=true
            ;;
        h)
            usage
            exit 0
            ;;
        o)
            output="$OPTARG"
            ;;
        f)
            file="$OPTARG"
            ;;
        ?)
            # 未知选项或缺少参数
            usage >&2
            exit 1
            ;;
    esac
done

# 移除已处理的选项，剩余的是位置参数
shift $((OPTIND - 1))

# 显示结果
echo "=== 解析结果 ==="
echo "verbose: $verbose"
echo "debug:   $debug"
echo "output:  ${output:-未指定}"
echo "file:    ${file:-未指定}"
echo "剩余参数: $@"
echo "OPTIND:  $OPTIND"
EOF

chmod +x getopts-basic.sh

# 测试
echo "=== 测试 1: 标志选项 ==="
./getopts-basic.sh -v -d

echo ""
echo "=== 测试 2: 带值选项 ==="
./getopts-basic.sh -o output.txt -f input.txt

echo ""
echo "=== 测试 3: 组合选项 ==="
./getopts-basic.sh -vd -o result.txt arg1 arg2

echo ""
echo "=== 测试 4: 选项粘连 ==="
./getopts-basic.sh -vdo result.txt file1.txt file2.txt
```

### 3.3 getopts 错误处理

```bash
cd ~/arguments-lab

cat > getopts-errors.sh << 'EOF'
#!/bin/bash
# getopts 错误处理

# 默认模式：getopts 自动报错
echo "=== 默认模式 ==="
while getopts "a:b:" opt; do
    case "$opt" in
        a) echo "a = $OPTARG" ;;
        b) echo "b = $OPTARG" ;;
        ?) echo "遇到错误，opt = ?" ;;
    esac
done

OPTIND=1  # 重置 OPTIND

echo ""
echo "=== 静默模式（optstring 以 : 开头）==="
# 静默模式：自己处理错误
while getopts ":a:b:" opt; do
    case "$opt" in
        a)
            echo "a = $OPTARG"
            ;;
        b)
            echo "b = $OPTARG"
            ;;
        :)
            # 选项缺少参数
            echo "Error: -$OPTARG requires an argument" >&2
            ;;
        ?)
            # 未知选项
            echo "Error: Unknown option -$OPTARG" >&2
            ;;
    esac
done
EOF

chmod +x getopts-errors.sh

echo "测试未知选项 -x："
bash getopts-errors.sh -x 2>&1

echo ""
echo "测试缺少参数 -a："
bash getopts-errors.sh -a 2>&1
```

### 3.4 完整的 getopts 模板

```bash
cd ~/arguments-lab

cat > getopts-template.sh << 'EOF'
#!/bin/bash
# =============================================================================
# getopts 标准模板
# =============================================================================
set -euo pipefail

# 脚本信息
readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_VERSION="1.0.0"

# 默认值
verbose=false
debug=false
output=""
config_file=""

# 帮助信息
usage() {
    cat << EOF
Usage: $SCRIPT_NAME [OPTIONS] FILE...

Description:
    Process one or more files with configurable options.

Options:
    -c, --config FILE   Configuration file
    -o, --output FILE   Output file (default: stdout)
    -v, --verbose       Verbose output
    -d, --debug         Debug mode
    -h, --help          Show this help
    --version           Show version

Arguments:
    FILE...             One or more input files

Examples:
    $SCRIPT_NAME -v input.txt
    $SCRIPT_NAME -c config.ini -o result.txt data.csv
    $SCRIPT_NAME --verbose --output=out.txt file1 file2
EOF
}

# 版本信息
version() {
    echo "$SCRIPT_NAME version $SCRIPT_VERSION"
}

# 错误处理函数
die() {
    echo "Error: $*" >&2
    exit 1
}

# 解析短选项（getopts）
parse_options() {
    while getopts ":vdhc:o:" opt; do
        case "$opt" in
            v) verbose=true ;;
            d) debug=true ;;
            h) usage; exit 0 ;;
            c) config_file="$OPTARG" ;;
            o) output="$OPTARG" ;;
            :) die "Option -$OPTARG requires an argument" ;;
            ?) die "Unknown option: -$OPTARG" ;;
        esac
    done
}

# 验证参数
validate_args() {
    # 检查是否有输入文件
    if [[ $# -eq 0 ]]; then
        die "At least one input file is required"
    fi

    # 检查配置文件是否存在
    if [[ -n "$config_file" && ! -f "$config_file" ]]; then
        die "Config file not found: $config_file"
    fi

    # 检查输入文件是否存在
    for file in "$@"; do
        if [[ ! -f "$file" ]]; then
            die "Input file not found: $file"
        fi
    done
}

# 主逻辑
main() {
    parse_options "$@"
    shift $((OPTIND - 1))

    # 检查特殊选项（通常在 getopts 之外处理）
    for arg in "$@"; do
        case "$arg" in
            --version) version; exit 0 ;;
            --help) usage; exit 0 ;;
        esac
    done

    validate_args "$@"

    # 调试输出
    if $debug; then
        echo "DEBUG: verbose=$verbose"
        echo "DEBUG: output=$output"
        echo "DEBUG: config_file=$config_file"
        echo "DEBUG: files=$*"
    fi

    # 处理文件
    for file in "$@"; do
        if $verbose; then
            echo "Processing: $file"
        fi

        # 实际处理逻辑
        if [[ -n "$output" ]]; then
            cat "$file" >> "$output"
        else
            cat "$file"
        fi
    done
}

main "$@"
EOF

chmod +x getopts-template.sh

# 测试
echo "创建测试文件..."
echo "Line 1" > test1.txt
echo "Line 2" > test2.txt

echo ""
echo "=== 测试帮助 ==="
./getopts-template.sh -h

echo ""
echo "=== 测试基本功能 ==="
./getopts-template.sh -v test1.txt test2.txt
```

---

## Step 4 — getopt 外部命令（20 分钟）

### 4.1 getopts vs getopt

![getopts vs getopt](images/getopts-vs-getopt.png)

<details>
<summary>View ASCII source</summary>

<!-- DIAGRAM: getopts-vs-getopt -->
```
┌─────────────────────────────────────────────────────────────────────────┐
│  getopts vs getopt 对比                                                   │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  ┌───────────────────────────────────────────────────────────────────┐  │
│  │  getopts（Bash 内置）                                              │  │
│  ├───────────────────────────────────────────────────────────────────┤  │
│  │  优点：                                                            │  │
│  │  - Bash/POSIX sh 内置，无外部依赖                                  │  │
│  │  - 语法简洁                                                        │  │
│  │  - 自动处理粘连选项（-abc 等同 -a -b -c）                          │  │
│  │                                                                    │  │
│  │  缺点：                                                            │  │
│  │  - 只支持短选项（-a, -b）                                          │  │
│  │  - 不支持长选项（--verbose）                                       │  │
│  │  - 选项必须在位置参数之前                                          │  │
│  └───────────────────────────────────────────────────────────────────┘  │
│                                                                          │
│  ┌───────────────────────────────────────────────────────────────────┐  │
│  │  getopt（GNU 外部命令）                                            │  │
│  ├───────────────────────────────────────────────────────────────────┤  │
│  │  优点：                                                            │  │
│  │  - 支持长选项（--verbose, --output=file）                         │  │
│  │  - 选项可以在任意位置                                              │  │
│  │  - 更灵活的参数处理                                                │  │
│  │                                                                    │  │
│  │  缺点：                                                            │  │
│  │  - 需要安装 util-linux（大多数 Linux 自带）                       │  │
│  │  - macOS 默认的 getopt 是 BSD 版本，功能受限                      │  │
│  │  - 语法稍复杂                                                      │  │
│  └───────────────────────────────────────────────────────────────────┘  │
│                                                                          │
│  选择建议：                                                              │
│  - 只需要短选项 → 用 getopts（更简单、更兼容）                          │
│  - 需要长选项   → 用 getopt（GNU 版本）或手动 while+case               │
│  - 跨平台脚本   → 手动 while+case（最大兼容性）                         │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```
<!-- /DIAGRAM -->

</details>

### 4.2 GNU getopt 基础

```bash
cd ~/arguments-lab

# 检查 getopt 版本
echo "=== getopt 版本检查 ==="
getopt --version 2>/dev/null || echo "BSD getopt（功能受限）"

cat > getopt-demo.sh << 'EOF'
#!/bin/bash
# GNU getopt 演示（长选项支持）
set -euo pipefail

# 检查是否是 GNU getopt
if ! getopt --test > /dev/null 2>&1; then
    if [[ $? -ne 4 ]]; then
        echo "Error: GNU getopt required (util-linux package)" >&2
        echo "On macOS: brew install gnu-getopt" >&2
        exit 1
    fi
fi

# 默认值
verbose=false
dry_run=false
source_dir=""
dest_dir=""
files=()

# 帮助信息
usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS] [FILES...]

Options:
    -s, --source DIR      Source directory
    -d, --dest DIR        Destination directory
    -v, --verbose         Verbose output
    -n, --dry-run         Dry run (no actual changes)
    -h, --help            Show this help
    --version             Show version

Examples:
    $(basename "$0") -s /src -d /dest
    $(basename "$0") --verbose --source=/data --dest=/backup
EOF
}

# 定义选项
# 短选项: s:d:vnh
# 长选项: source:,dest:,verbose,dry-run,help,version
SHORT_OPTS="s:d:vnh"
LONG_OPTS="source:,dest:,verbose,dry-run,help,version"

# 解析选项
# -o: 短选项
# -l: 长选项
# -n: 脚本名（用于错误消息）
# --: 分隔选项和参数
PARSED=$(getopt -o "$SHORT_OPTS" -l "$LONG_OPTS" -n "$(basename "$0")" -- "$@")

# 检查 getopt 是否成功
if [[ $? -ne 0 ]]; then
    usage >&2
    exit 1
fi

# 将解析结果设置为位置参数
eval set -- "$PARSED"

# 处理选项
while true; do
    case "$1" in
        -s|--source)
            source_dir="$2"
            shift 2
            ;;
        -d|--dest)
            dest_dir="$2"
            shift 2
            ;;
        -v|--verbose)
            verbose=true
            shift
            ;;
        -n|--dry-run)
            dry_run=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        --version)
            echo "$(basename "$0") version 1.0.0"
            exit 0
            ;;
        --)
            shift
            break
            ;;
        *)
            echo "Error: Unexpected option: $1" >&2
            exit 1
            ;;
    esac
done

# 剩余参数是文件列表
files=("$@")

# 显示解析结果
echo "=== 解析结果 ==="
echo "verbose:    $verbose"
echo "dry_run:    $dry_run"
echo "source_dir: ${source_dir:-未指定}"
echo "dest_dir:   ${dest_dir:-未指定}"
echo "files:      ${files[*]:-无}"
EOF

chmod +x getopt-demo.sh

# 测试（如果是 GNU getopt）
if getopt --test > /dev/null 2>&1; [[ $? -eq 4 ]]; then
    echo "=== 测试短选项 ==="
    ./getopt-demo.sh -v -s /src -d /dest file1.txt

    echo ""
    echo "=== 测试长选项 ==="
    ./getopt-demo.sh --verbose --source=/data --dest=/backup

    echo ""
    echo "=== 测试混合选项 ==="
    ./getopt-demo.sh -v --source=/src -d /dest --dry-run file1 file2
else
    echo "跳过测试（需要 GNU getopt）"
fi
```

### 4.3 macOS 兼容方案

macOS 默认的 getopt 是 BSD 版本，不支持长选项。推荐使用**手动 while+case** 方案：

```bash
cd ~/arguments-lab

cat > portable-options.sh << 'EOF'
#!/bin/bash
# 跨平台选项解析（手动 while+case）
# 不依赖 GNU getopt，在 macOS 和 Linux 都能工作
set -euo pipefail

# 默认值
verbose=false
dry_run=false
source_dir=""
dest_dir=""
files=()

# 帮助信息
usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS] [FILES...]

Options:
    -s, --source DIR      Source directory
    -d, --dest DIR        Destination directory
    -v, --verbose         Verbose output
    -n, --dry-run         Dry run (no actual changes)
    -h, --help            Show this help
    --version             Show version

Examples:
    $(basename "$0") -s /src -d /dest
    $(basename "$0") --verbose --source=/data --dest=/backup
EOF
}

# 解析选项
while [[ $# -gt 0 ]]; do
    case "$1" in
        -s|--source)
            source_dir="$2"
            shift 2
            ;;
        --source=*)
            source_dir="${1#*=}"
            shift
            ;;
        -d|--dest)
            dest_dir="$2"
            shift 2
            ;;
        --dest=*)
            dest_dir="${1#*=}"
            shift
            ;;
        -v|--verbose)
            verbose=true
            shift
            ;;
        -n|--dry-run)
            dry_run=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        --version)
            echo "$(basename "$0") version 1.0.0"
            exit 0
            ;;
        --)
            shift
            break
            ;;
        -*)
            echo "Error: Unknown option: $1" >&2
            usage >&2
            exit 1
            ;;
        *)
            # 位置参数
            files+=("$1")
            shift
            ;;
    esac
done

# 追加 -- 后面的参数
files+=("$@")

# 显示解析结果
echo "=== 解析结果 ==="
echo "verbose:    $verbose"
echo "dry_run:    $dry_run"
echo "source_dir: ${source_dir:-未指定}"
echo "dest_dir:   ${dest_dir:-未指定}"
echo "files:      ${files[*]:-无}"
EOF

chmod +x portable-options.sh

# 测试
echo "=== 测试短选项 ==="
./portable-options.sh -v -s /src -d /dest file1.txt

echo ""
echo "=== 测试长选项 ==="
./portable-options.sh --verbose --source=/data --dest=/backup

echo ""
echo "=== 测试等号语法 ==="
./portable-options.sh --source=/src --dest=/backup file1 file2
```

---

## Step 5 — CLI 设计最佳实践（15 分钟）

### 5.1 CLI 设计原则

![CLI Design Principles](images/cli-design.png)

<details>
<summary>View ASCII source</summary>

<!-- DIAGRAM: cli-design -->
```
┌─────────────────────────────────────────────────────────────────────────┐
│  CLI 设计最佳实践                                                         │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  1. 遵循 Unix 哲学                                                       │
│  ┌───────────────────────────────────────────────────────────────────┐  │
│  │  - 默认静默，只在出错时输出（除非 -v/--verbose）                   │  │
│  │  - 成功退出码 0，失败非 0                                          │  │
│  │  - 输出适合管道处理                                                │  │
│  │  - 错误信息输出到 stderr                                           │  │
│  └───────────────────────────────────────────────────────────────────┘  │
│                                                                          │
│  2. 提供标准选项                                                         │
│  ┌───────────────────────────────────────────────────────────────────┐  │
│  │  -h, --help      显示帮助信息                                      │  │
│  │  --version       显示版本信息                                      │  │
│  │  -v, --verbose   详细输出                                          │  │
│  │  -q, --quiet     静默模式                                          │  │
│  │  -n, --dry-run   模拟运行（不做实际更改）                          │  │
│  │  -f, --force     强制执行（跳过确认）                              │  │
│  │  --              选项结束标记                                      │  │
│  └───────────────────────────────────────────────────────────────────┘  │
│                                                                          │
│  3. 帮助信息格式                                                         │
│  ┌───────────────────────────────────────────────────────────────────┐  │
│  │  Usage: command [OPTIONS] REQUIRED_ARG [OPTIONAL_ARG]              │  │
│  │                                                                    │  │
│  │  Description:                                                      │  │
│  │      Brief description of what the command does.                   │  │
│  │                                                                    │  │
│  │  Options:                                                          │  │
│  │      -s, --short ARG    Short description (default: value)         │  │
│  │      -f, --flag         Another option                             │  │
│  │                                                                    │  │
│  │  Examples:                                                         │  │
│  │      command -s value file.txt                                     │  │
│  │      command --verbose input.csv                                   │  │
│  └───────────────────────────────────────────────────────────────────┘  │
│                                                                          │
│  4. 退出码规范                                                           │
│  ┌───────────────────────────────────────────────────────────────────┐  │
│  │  0   成功                                                          │  │
│  │  1   一般错误                                                      │  │
│  │  2   命令行语法错误                                                │  │
│  │  126 命令不可执行                                                  │  │
│  │  127 命令未找到                                                    │  │
│  │  128+N 被信号 N 终止                                               │  │
│  └───────────────────────────────────────────────────────────────────┘  │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```
<!-- /DIAGRAM -->

</details>

### 5.2 专业 CLI 模板

```bash
cd ~/arguments-lab

cat > professional-cli.sh << 'EOF'
#!/usr/bin/env bash
# =============================================================================
# 文件名：professional-cli.sh
# 功能：专业 CLI 脚本模板
# 版本：1.0.0
# =============================================================================

set -euo pipefail

# =============================================================================
# 常量定义
# =============================================================================
readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_VERSION="1.0.0"

# 退出码
readonly EXIT_SUCCESS=0
readonly EXIT_ERROR=1
readonly EXIT_USAGE=2

# 颜色（如果终端支持）
if [[ -t 1 ]]; then
    readonly RED='\033[0;31m'
    readonly GREEN='\033[0;32m'
    readonly YELLOW='\033[0;33m'
    readonly NC='\033[0m'
else
    readonly RED=''
    readonly GREEN=''
    readonly YELLOW=''
    readonly NC=''
fi

# =============================================================================
# 默认配置
# =============================================================================
verbose=false
quiet=false
dry_run=false
force=false
source_dir=""
dest_dir=""

# =============================================================================
# 辅助函数
# =============================================================================

# 日志函数
log_info() {
    if ! $quiet; then
        echo -e "${GREEN}[INFO]${NC} $*"
    fi
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*" >&2
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

log_debug() {
    if $verbose; then
        echo -e "[DEBUG] $*" >&2
    fi
}

# 错误退出
die() {
    log_error "$*"
    exit $EXIT_ERROR
}

# 使用错误退出
die_usage() {
    log_error "$*"
    echo "Try '$SCRIPT_NAME --help' for more information." >&2
    exit $EXIT_USAGE
}

# 确认提示
confirm() {
    local prompt="${1:-Are you sure?}"
    if $force; then
        return 0
    fi
    read -r -p "$prompt [y/N] " response
    case "$response" in
        [yY][eE][sS]|[yY]) return 0 ;;
        *) return 1 ;;
    esac
}

# =============================================================================
# 帮助信息
# =============================================================================
usage() {
    cat << EOF
Usage: $SCRIPT_NAME [OPTIONS] -s SOURCE -d DEST

Synchronize files from source to destination directory.

Required Options:
    -s, --source DIR      Source directory
    -d, --dest DIR        Destination directory

Options:
    -v, --verbose         Verbose output
    -q, --quiet           Quiet mode (suppress non-error output)
    -n, --dry-run         Show what would be done without doing it
    -f, --force           Skip confirmation prompts
    -h, --help            Show this help message
    --version             Show version information

Examples:
    $SCRIPT_NAME -s /data -d /backup
    $SCRIPT_NAME --verbose --source=/src --dest=/dest
    $SCRIPT_NAME -n -s /home/user -d /mnt/backup

Exit codes:
    0   Success
    1   General error
    2   Usage error

Report bugs to: <your-email@example.com>
EOF
}

version() {
    echo "$SCRIPT_NAME $SCRIPT_VERSION"
}

# =============================================================================
# 参数解析
# =============================================================================
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -s|--source)
                [[ -n "${2:-}" ]] || die_usage "Option $1 requires an argument"
                source_dir="$2"
                shift 2
                ;;
            --source=*)
                source_dir="${1#*=}"
                shift
                ;;
            -d|--dest)
                [[ -n "${2:-}" ]] || die_usage "Option $1 requires an argument"
                dest_dir="$2"
                shift 2
                ;;
            --dest=*)
                dest_dir="${1#*=}"
                shift
                ;;
            -v|--verbose)
                verbose=true
                shift
                ;;
            -q|--quiet)
                quiet=true
                shift
                ;;
            -n|--dry-run)
                dry_run=true
                shift
                ;;
            -f|--force)
                force=true
                shift
                ;;
            -h|--help)
                usage
                exit $EXIT_SUCCESS
                ;;
            --version)
                version
                exit $EXIT_SUCCESS
                ;;
            --)
                shift
                break
                ;;
            -*)
                die_usage "Unknown option: $1"
                ;;
            *)
                die_usage "Unexpected argument: $1"
                ;;
        esac
    done
}

# =============================================================================
# 验证参数
# =============================================================================
validate_args() {
    # 检查必需参数
    [[ -n "$source_dir" ]] || die_usage "Source directory is required (-s/--source)"
    [[ -n "$dest_dir" ]] || die_usage "Destination directory is required (-d/--dest)"

    # 检查源目录存在
    [[ -d "$source_dir" ]] || die "Source directory does not exist: $source_dir"

    # verbose 和 quiet 互斥
    if $verbose && $quiet; then
        die_usage "Options --verbose and --quiet are mutually exclusive"
    fi
}

# =============================================================================
# 主逻辑
# =============================================================================
sync_files() {
    log_info "Syncing from $source_dir to $dest_dir"
    log_debug "verbose=$verbose, quiet=$quiet, dry_run=$dry_run, force=$force"

    # 创建目标目录
    if [[ ! -d "$dest_dir" ]]; then
        if $dry_run; then
            log_info "[DRY-RUN] Would create directory: $dest_dir"
        else
            if confirm "Create destination directory $dest_dir?"; then
                mkdir -p "$dest_dir"
                log_info "Created directory: $dest_dir"
            else
                die "Aborted by user"
            fi
        fi
    fi

    # 同步文件
    local rsync_opts="-a"
    $verbose && rsync_opts+="v"
    $dry_run && rsync_opts+="n"

    if $dry_run; then
        log_info "[DRY-RUN] Would execute: rsync $rsync_opts $source_dir/ $dest_dir/"
    else
        rsync $rsync_opts "$source_dir/" "$dest_dir/"
        log_info "Sync completed successfully"
    fi
}

# =============================================================================
# 主入口
# =============================================================================
main() {
    parse_args "$@"
    validate_args
    sync_files
}

# 只在直接执行时运行，被 source 时不运行
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
EOF

chmod +x professional-cli.sh

# 测试
echo "=== 帮助信息 ==="
./professional-cli.sh --help

echo ""
echo "=== 版本信息 ==="
./professional-cli.sh --version

echo ""
echo "=== 缺少必需参数 ==="
./professional-cli.sh -v 2>&1 || true

echo ""
echo "=== Dry-run 模式 ==="
mkdir -p /tmp/test-src
touch /tmp/test-src/file{1,2,3}.txt
./professional-cli.sh --dry-run -v -s /tmp/test-src -d /tmp/test-dest
```

---

## Step 6 — Mini Project：备份脚本 CLI（20 分钟）

> **项目目标**：创建一个支持完整 CLI 选项的备份脚本。  

### 6.1 项目要求

创建 `backup-cli.sh`，支持：
1. `-s, --source DIR` 源目录（必需）
2. `-d, --dest DIR` 目标目录（必需）
3. `-v, --verbose` 详细输出
4. `-n, --dry-run` 模拟运行
5. `-h, --help` 帮助信息
6. `--version` 版本信息
7. 使用 rsync 进行实际备份
8. 通过 ShellCheck 检查

### 6.2 完整实现

```bash
cd ~/arguments-lab

cat > backup-cli.sh << 'EOF'
#!/usr/bin/env bash
# =============================================================================
# 文件名：backup-cli.sh
# 功能：支持完整 CLI 选项的备份脚本
# 版本：1.0.0
# =============================================================================

set -euo pipefail

# =============================================================================
# 常量
# =============================================================================
readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_VERSION="1.0.0"

# 退出码
readonly EXIT_SUCCESS=0
readonly EXIT_ERROR=1
readonly EXIT_USAGE=2

# 颜色
if [[ -t 1 ]]; then
    readonly C_RED='\033[0;31m'
    readonly C_GREEN='\033[0;32m'
    readonly C_YELLOW='\033[0;33m'
    readonly C_BLUE='\033[0;34m'
    readonly C_NC='\033[0m'
else
    readonly C_RED='' C_GREEN='' C_YELLOW='' C_BLUE='' C_NC=''
fi

# =============================================================================
# 默认配置
# =============================================================================
source_dir=""
dest_dir=""
verbose=false
dry_run=false
compress=false
exclude_patterns=()

# =============================================================================
# 日志函数
# =============================================================================
log_info()  { echo -e "${C_GREEN}[INFO]${C_NC} $*"; }
log_warn()  { echo -e "${C_YELLOW}[WARN]${C_NC} $*" >&2; }
log_error() { echo -e "${C_RED}[ERROR]${C_NC} $*" >&2; }
log_debug() { $verbose && echo -e "${C_BLUE}[DEBUG]${C_NC} $*" >&2 || true; }

die() { log_error "$*"; exit $EXIT_ERROR; }
die_usage() { log_error "$*"; echo "Use '$SCRIPT_NAME --help' for help." >&2; exit $EXIT_USAGE; }

# =============================================================================
# 帮助信息
# =============================================================================
usage() {
    cat << EOF
Usage: $SCRIPT_NAME [OPTIONS] -s SOURCE -d DEST

Backup files from source to destination using rsync.

Required:
    -s, --source DIR      Source directory to backup
    -d, --dest DIR        Destination directory

Options:
    -v, --verbose         Show detailed progress
    -n, --dry-run         Simulate backup (no actual changes)
    -z, --compress        Compress data during transfer
    -e, --exclude PATTERN Exclude files matching PATTERN (can repeat)
    -h, --help            Show this help
    --version             Show version

Examples:
    # Basic backup
    $SCRIPT_NAME -s /home/user -d /backup/user

    # Verbose with compression
    $SCRIPT_NAME -v -z -s /data -d /mnt/backup

    # Dry-run with exclusions
    $SCRIPT_NAME -n -e '*.log' -e '*.tmp' -s /src -d /dest

Exit Codes:
    0   Success
    1   Error
    2   Usage error
EOF
}

version() {
    echo "$SCRIPT_NAME version $SCRIPT_VERSION"
    echo "Built with rsync $(rsync --version | head -1 | awk '{print $3}')"
}

# =============================================================================
# 参数解析
# =============================================================================
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -s|--source)
                [[ -n "${2:-}" ]] || die_usage "-s/--source requires a directory"
                source_dir="$2"
                shift 2
                ;;
            --source=*)
                source_dir="${1#*=}"
                [[ -n "$source_dir" ]] || die_usage "--source requires a value"
                shift
                ;;
            -d|--dest)
                [[ -n "${2:-}" ]] || die_usage "-d/--dest requires a directory"
                dest_dir="$2"
                shift 2
                ;;
            --dest=*)
                dest_dir="${1#*=}"
                [[ -n "$dest_dir" ]] || die_usage "--dest requires a value"
                shift
                ;;
            -v|--verbose)
                verbose=true
                shift
                ;;
            -n|--dry-run)
                dry_run=true
                shift
                ;;
            -z|--compress)
                compress=true
                shift
                ;;
            -e|--exclude)
                [[ -n "${2:-}" ]] || die_usage "-e/--exclude requires a pattern"
                exclude_patterns+=("$2")
                shift 2
                ;;
            --exclude=*)
                local pattern="${1#*=}"
                [[ -n "$pattern" ]] || die_usage "--exclude requires a pattern"
                exclude_patterns+=("$pattern")
                shift
                ;;
            -h|--help)
                usage
                exit $EXIT_SUCCESS
                ;;
            --version)
                version
                exit $EXIT_SUCCESS
                ;;
            --)
                shift
                break
                ;;
            -*)
                die_usage "Unknown option: $1"
                ;;
            *)
                die_usage "Unexpected argument: $1"
                ;;
        esac
    done
}

# =============================================================================
# 验证
# =============================================================================
validate() {
    # 必需参数检查
    [[ -n "$source_dir" ]] || die_usage "Source directory required (-s/--source)"
    [[ -n "$dest_dir" ]] || die_usage "Destination directory required (-d/--dest)"

    # 源目录检查
    [[ -d "$source_dir" ]] || die "Source directory not found: $source_dir"

    # rsync 检查
    command -v rsync &>/dev/null || die "rsync is not installed"

    log_debug "Validation passed"
}

# =============================================================================
# 备份执行
# =============================================================================
do_backup() {
    local rsync_opts=("-a" "--delete")
    local rsync_cmd

    # 构建选项
    $verbose && rsync_opts+=("-v" "--progress")
    $dry_run && rsync_opts+=("-n")
    $compress && rsync_opts+=("-z")

    # 添加排除模式
    for pattern in "${exclude_patterns[@]}"; do
        rsync_opts+=("--exclude=$pattern")
    done

    # 确保目标目录存在
    if [[ ! -d "$dest_dir" ]]; then
        if $dry_run; then
            log_info "[DRY-RUN] Would create: $dest_dir"
        else
            log_info "Creating destination: $dest_dir"
            mkdir -p "$dest_dir"
        fi
    fi

    # 构建命令
    rsync_cmd=(rsync "${rsync_opts[@]}" "$source_dir/" "$dest_dir/")

    # 显示命令
    log_debug "Command: ${rsync_cmd[*]}"

    # 执行备份
    log_info "Starting backup: $source_dir -> $dest_dir"
    $dry_run && log_info "(Dry-run mode - no changes will be made)"

    local start_time
    start_time=$(date +%s)

    if "${rsync_cmd[@]}"; then
        local end_time elapsed
        end_time=$(date +%s)
        elapsed=$((end_time - start_time))
        log_info "Backup completed in ${elapsed}s"
        return $EXIT_SUCCESS
    else
        log_error "Backup failed"
        return $EXIT_ERROR
    fi
}

# =============================================================================
# 主入口
# =============================================================================
main() {
    parse_args "$@"
    validate
    do_backup
}

[[ "${BASH_SOURCE[0]}" == "${0}" ]] && main "$@"
EOF

chmod +x backup-cli.sh

# 测试
echo "=== 帮助信息 ==="
./backup-cli.sh --help

echo ""
echo "=== 版本信息 ==="
./backup-cli.sh --version

echo ""
echo "=== 创建测试数据 ==="
mkdir -p /tmp/backup-test/src
echo "File 1" > /tmp/backup-test/src/file1.txt
echo "File 2" > /tmp/backup-test/src/file2.txt
echo "Log data" > /tmp/backup-test/src/app.log

echo ""
echo "=== Dry-run 测试 ==="
./backup-cli.sh -v -n -e '*.log' -s /tmp/backup-test/src -d /tmp/backup-test/dest

echo ""
echo "=== 实际备份 ==="
./backup-cli.sh -v -e '*.log' -s /tmp/backup-test/src -d /tmp/backup-test/dest

echo ""
echo "=== 检查结果 ==="
ls -la /tmp/backup-test/dest/

echo ""
echo "=== ShellCheck ==="
shellcheck backup-cli.sh && echo "ShellCheck passed!"
```

---

## 速查表（Cheatsheet）

```bash
# =============================================================================
# 命令行参数处理速查表
# =============================================================================

# --- 位置参数 ---
$0          # 脚本名称
$1 - $9     # 第 1-9 个参数
${10}+      # 第 10 个及以后（需要花括号）
$#          # 参数个数
$@          # 所有参数（保持分隔，推荐）
$*          # 所有参数（合并为字符串）
"$@"        # 正确引用所有参数（推荐）

# --- shift 命令 ---
shift       # 左移 1 位
shift N     # 左移 N 位

# --- getopts（Bash 内置，短选项）---
while getopts ":vhf:o:" opt; do
    case "$opt" in
        v) verbose=true ;;
        h) usage; exit 0 ;;
        f) file="$OPTARG" ;;
        o) output="$OPTARG" ;;
        :) die "-$OPTARG requires argument" ;;
        ?) die "Unknown option -$OPTARG" ;;
    esac
done
shift $((OPTIND - 1))

# --- getopt（GNU，长选项）---
PARSED=$(getopt -o "vhf:o:" -l "verbose,help,file:,output:" -n "$0" -- "$@")
eval set -- "$PARSED"

# --- 手动 while+case（跨平台推荐）---
while [[ $# -gt 0 ]]; do
    case "$1" in
        -v|--verbose) verbose=true; shift ;;
        -f|--file) file="$2"; shift 2 ;;
        --file=*) file="${1#*=}"; shift ;;
        -h|--help) usage; exit 0 ;;
        --) shift; break ;;
        -*) die "Unknown: $1" ;;
        *) args+=("$1"); shift ;;
    esac
done

# --- 帮助信息模板 ---
usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS] REQUIRED [OPTIONAL]

Description here.

Options:
    -v, --verbose    Verbose output
    -h, --help       Show help

Examples:
    $(basename "$0") -v input.txt
EOF
}

# --- 退出码 ---
exit 0    # 成功
exit 1    # 一般错误
exit 2    # 用法错误
```

---

## 反模式：常见错误

### 错误 1：不验证必需参数

```bash
# 错误：直接使用参数，未检查
source_dir="$1"
cp -r "$source_dir" /backup/  # 如果 $1 为空，会出问题

# 正确：先验证
source_dir="${1:?Error: source directory required}"
[[ -d "$source_dir" ]] || die "Not a directory: $source_dir"
```

### 错误 2：shift 超过参数个数

```bash
# 错误：可能 shift 失败
case "$1" in
    -f) file="$2"; shift 2 ;;  # 如果没有 $2 会出错
esac

# 正确：先检查
case "$1" in
    -f)
        [[ -n "${2:-}" ]] || die "-f requires an argument"
        file="$2"
        shift 2
        ;;
esac
```

### 错误 3：长选项等号处理不当

```bash
# 错误：只处理空格分隔
--output) output="$2"; shift 2 ;;

# 正确：同时处理等号和空格
--output) output="$2"; shift 2 ;;
--output=*) output="${1#*=}"; shift ;;
```

### 错误 4：忘记 `--` 结束标记

```bash
# 问题：文件名以 - 开头会被当作选项
./script.sh -delete-me.txt  # 被解释为 -d, -e, -l, ...

# 正确：使用 -- 结束选项
./script.sh -- -delete-me.txt

# 脚本中处理
case "$1" in
    --) shift; break ;;  # 重要！
esac
```

---

## 职场小贴士（Japan IT Context）

### 运维脚本的 CLI 规范

在日本 IT 企业，命令行工具需要遵循统一规范：

| 日语术语 | 含义 | CLI 设计要点 |
|----------|------|--------------|
| ヘルプ | 帮助 | `-h`, `--help` 必须支持 |
| バージョン | 版本 | `--version` 显示版本号 |
| ドライラン | 模拟运行 | `-n`, `--dry-run` 不做实际更改 |
| 詳細モード | 详细模式 | `-v`, `--verbose` 输出详细信息 |
| 強制実行 | 强制执行 | `-f`, `--force` 跳过确认 |

### 日本企业脚本模板

```bash
#!/bin/bash
# ==============================================================================
# スクリプト名：backup.sh
# 概要：データバックアップスクリプト
# 作成者：田中太郎
# 作成日：2026-01-10
# 使用方法：./backup.sh -s <源ディレクトリ> -d <宛先ディレクトリ>
# ==============================================================================

# ヘルプ表示
usage() {
    cat << EOF
使用方法: $(basename "$0") [オプション] -s 源 -d 宛先

オプション:
    -s, --source DIR    バックアップ元ディレクトリ（必須）
    -d, --dest DIR      バックアップ先ディレクトリ（必須）
    -v, --verbose       詳細出力
    -n, --dry-run       ドライラン（実際の変更なし）
    -h, --help          このヘルプを表示

例:
    $(basename "$0") -s /home/data -d /backup/data
    $(basename "$0") -v -n -s /var/log -d /mnt/backup
EOF
}

# エラーログ出力
log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $*" >&2
}

# 情報ログ出力
log_info() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $*"
}
```

### 監視連携（Zabbix/Nagios）

运维监控脚本需要标准退出码：

```bash
# Zabbix/Nagios 对接脚本
readonly EXIT_OK=0
readonly EXIT_WARNING=1
readonly EXIT_CRITICAL=2
readonly EXIT_UNKNOWN=3

check_backup() {
    local backup_dir="$1"
    local max_age_hours="${2:-24}"

    # 检查最新备份时间
    local latest
    latest=$(find "$backup_dir" -type f -name "*.tar.gz" -mmin -$((max_age_hours * 60)) | head -1)

    if [[ -z "$latest" ]]; then
        echo "CRITICAL: No backup in last ${max_age_hours} hours"
        exit $EXIT_CRITICAL
    fi

    echo "OK: Latest backup: $(basename "$latest")"
    exit $EXIT_OK
}
```

---

## 检查清单

完成本课后，你应该能够：

- [ ] 使用位置参数 `$1`, `$2`, `$@`, `$#`
- [ ] 理解 `$@` 和 `$*` 的区别
- [ ] 使用 `shift` 命令移动参数
- [ ] 使用 `getopts` 解析短选项
- [ ] 理解 `OPTARG` 和 `OPTIND` 的作用
- [ ] 使用手动 while+case 解析长选项
- [ ] 设计标准的帮助信息
- [ ] 实现 `--help` 和 `--version`
- [ ] 正确处理选项参数验证
- [ ] 使用标准退出码

**验证命令：**

```bash
cd ~/arguments-lab

# 测试 1: 位置参数
bash -c 'echo "第一个: $1, 个数: $#"' _ arg1 arg2 arg3
# 预期: 第一个: arg1, 个数: 3

# 测试 2: shift
bash -c 'echo "$1"; shift; echo "$1"' _ a b c
# 预期: a \n b

# 测试 3: getopts
bash -c 'while getopts "a:b" opt; do echo "$opt: $OPTARG"; done' _ -a val -b
# 预期: a: val \n b:

# 测试 4: ShellCheck
shellcheck backup-cli.sh
# 预期: 无错误
```

---

## 本课小结

| 方法 | 适用场景 | 优点 | 缺点 |
|------|----------|------|------|
| 位置参数 + shift | 简单脚本 | 无依赖 | 手动处理 |
| getopts | 短选项 | Bash 内置 | 不支持长选项 |
| getopt (GNU) | 长选项 | 功能完整 | 需要 util-linux |
| 手动 while+case | 跨平台 | 最大兼容 | 代码较多 |

---

## 面试准备

### **getopts と getopt の違いは？**

`getopts` は Bash 内蔵コマンドで短いオプション（`-a`, `-b`）のみ対応します。`getopt` は GNU の外部コマンドで、長いオプション（`--verbose`）にも対応しています。

```bash
# getopts - 短オプションのみ
while getopts "vf:" opt; do ...

# getopt - 長オプション対応
getopt -o "vf:" -l "verbose,file:" -- "$@"
```

### **shift コマンドの用途は？**

位置パラメータを左にシフトします。ループで全引数を処理する際に使用し、処理済みの引数を捨てて次の引数を `$1` にします。

```bash
while [[ $# -gt 0 ]]; do
    case "$1" in
        -v) verbose=true; shift ;;     # 1 つシフト
        -f) file="$2"; shift 2 ;;      # 2 つシフト（オプション+値）
    esac
done
```

---

## 延伸阅读

- [Bash Reference - getopts](https://www.gnu.org/software/bash/manual/html_node/Bourne-Shell-Builtins.html#index-getopts) - GNU Bash 官方文档
- [getopt(1) man page](https://man7.org/linux/man-pages/man1/getopt.1.html) - GNU getopt 手册
- [Command Line Interface Guidelines](https://clig.dev/) - CLI 设计最佳实践
- 上一课：[09 - 错误处理与 trap](../09-error-handling/) — 生产级脚本必备
- 下一课：[11 - 调试技巧与最佳实践](../11-debugging/) — ShellCheck 与调试

---

## 清理

```bash
# 清理练习文件
cd ~
rm -rf ~/arguments-lab
rm -rf /tmp/backup-test
rm -rf /tmp/test-src /tmp/test-dest
rm -f /tmp/test-logger.log
```

---

## 系列导航

[<-- 09 - 错误处理与 trap](../09-error-handling/) | [课程首页](../) | [11 - 调试技巧与最佳实践 -->](../11-debugging/)
