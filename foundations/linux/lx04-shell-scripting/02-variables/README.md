# 02 · 变量与环境

> **目标**：掌握 Shell 变量系统，理解环境变量与 Shell 变量的区别  
> **前置**：已完成 [01 · 脚本基础与执行方式](../01-basics/)  
> **时间**：⚡ 15 分钟（速读）/ 🔬 60 分钟（完整实操）  
> **环境**：任意 Linux 发行版（Bash 4.0+）  

---

## 将学到的内容

1. 理解 Shell 变量与环境变量的区别
2. 掌握变量赋值、读取、导出
3. 理解变量作用域（local、export）
4. 使用特殊变量（$?, $$, $!, $0, $#, $@, $*）
5. 理解命令替换 $(command)

---

## Step 1 — 先跑起来：环境信息收集器（3 分钟）

> 先"尝到"变量的威力，再理解原理。  

创建一个脚本，自动收集系统信息：

```bash
# 创建脚本
cat > ~/sysinfo.sh << 'EOF'
#!/bin/bash

# 使用变量收集系统信息
HOSTNAME=$(hostname)
CURRENT_USER=$USER
CURRENT_DATE=$(date '+%Y-%m-%d %H:%M:%S')
UPTIME=$(uptime -p 2>/dev/null || uptime)

# 格式化输出
echo "================================"
echo "   系统信息报告"
echo "================================"
echo "主机名: $HOSTNAME"
echo "用户名: $CURRENT_USER"
echo "时  间: $CURRENT_DATE"
echo "运行时间: $UPTIME"
echo "================================"
EOF

# 运行
chmod +x ~/sysinfo.sh
~/sysinfo.sh
```

**看到了什么？**

```
================================
   系统信息报告
================================
主机名: ip-10-0-1-100
用户名: terraform
时  间: 2025-01-04 15:30:45
运行时间: up 2 hours, 15 minutes
================================
```

你刚刚用变量收集并展示了系统信息！

---

## Step 2 — 发生了什么？（5 分钟）

刚才的脚本使用了两种获取变量值的方式：

```bash
# 方式 1：读取已有的环境变量
CURRENT_USER=$USER

# 方式 2：命令替换 - 捕获命令输出
HOSTNAME=$(hostname)
CURRENT_DATE=$(date '+%Y-%m-%d %H:%M:%S')
```

### 变量的核心概念

| 概念 | 说明 | 示例 |
|------|------|------|
| **赋值** | 创建/修改变量 | `NAME="value"` |
| **引用** | 读取变量值 | `$NAME` 或 `${NAME}` |
| **命令替换** | 捕获命令输出 | `$(command)` |
| **环境变量** | 可被子进程继承 | `export VAR` |

---

## Step 3 — 变量赋值基础（15 分钟）

### 3.1 基本语法

```bash
# ✅ 正确：等号两边没有空格
NAME="John"

# ❌ 错误：等号两边有空格
NAME = "John"    # 错误！Shell 会把 NAME 当命令执行
NAME= "John"     # 错误！
NAME ="John"     # 错误！
```

**这是 Shell 脚本最常见的错误之一！**

```bash
# 实验：看看错误是什么样的
NAME = "John"
```

```
NAME: command not found
```

Shell 把 `NAME` 当成了命令名，`=` 和 `"John"` 当成了参数。

### 3.2 变量引用

```bash
NAME="World"

# 两种引用方式
echo $NAME         # World
echo ${NAME}       # World

# ${} 在字符串拼接时更清晰
PREFIX="hello"
echo "$PREFIX_world"    # 空！Shell 找的是 $PREFIX_world
echo "${PREFIX}_world"  # hello_world ✓
```

### 3.3 引号的区别

```bash
NAME="Linux"

# 双引号：变量会展开
echo "Hello, $NAME"    # Hello, Linux

# 单引号：原样输出
echo 'Hello, $NAME'    # Hello, $NAME

# 无引号：变量展开 + 词分割 + 通配符展开（危险！）
FILES="*.txt"
echo $FILES            # 会列出所有 .txt 文件
echo "$FILES"          # *.txt（原样）
```

> **黄金法则**：始终用双引号包裹变量 `"$VAR"`，除非你明确知道为什么不需要。  

---

## Step 4 — 环境变量 vs Shell 变量（15 分钟）

### 4.1 核心区别

<!-- DIAGRAM: variable-scope -->
```
┌─────────────────────────────────────────────────────────────────┐
│                      变量作用域示意图                             │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│    父 Shell (bash)                                              │
│    ┌────────────────────────────────────────────┐              │
│    │  Shell 变量（不 export）                    │              │
│    │  ┌──────────────────────────────────────┐ │              │
│    │  │ LOCAL_VAR="只在这里可见"               │ │              │
│    │  └──────────────────────────────────────┘ │              │
│    │                                            │              │
│    │  环境变量（export 过的）                    │              │
│    │  ┌──────────────────────────────────────┐ │              │
│    │  │ export SHARED_VAR="子进程也能看到"    │ │              │
│    │  └───────────────────┬──────────────────┘ │              │
│    └──────────────────────┼─────────────────────┘              │
│                           │                                     │
│                           │ 继承                                │
│                           ▼                                     │
│    ┌────────────────────────────────────────────┐              │
│    │  子进程（脚本/子 Shell）                    │              │
│    │  ┌──────────────────────────────────────┐ │              │
│    │  │ SHARED_VAR="子进程也能看到" ✓         │ │              │
│    │  │ LOCAL_VAR=???  ✗ 看不到！             │ │              │
│    │  └──────────────────────────────────────┘ │              │
│    └────────────────────────────────────────────┘              │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```
<!-- /DIAGRAM -->

### 4.2 动手验证

```bash
# 设置 Shell 变量（不 export）
MY_VAR="I am local"

# 设置环境变量（export）
export MY_ENV="I am exported"

# 在当前 Shell 中都能访问
echo $MY_VAR     # I am local
echo $MY_ENV     # I am exported

# 启动子 Shell 测试
bash -c 'echo "MY_VAR=$MY_VAR"'   # MY_VAR=（空！）
bash -c 'echo "MY_ENV=$MY_ENV"'   # MY_ENV=I am exported
```

### 4.3 查看所有变量

```bash
# 查看所有环境变量
env

# 查看所有变量（包括 Shell 变量）
set

# 查看单个变量
echo $PATH
```

### 4.4 删除变量

```bash
# 删除变量
unset MY_VAR

# 验证
echo $MY_VAR  # 空
```

### 4.5 常用环境变量

| 变量 | 说明 | 示例值 |
|------|------|--------|
| `$USER` | 当前用户名 | `terraform` |
| `$HOME` | 家目录 | `/home/terraform` |
| `$PATH` | 命令搜索路径 | `/usr/bin:/bin:...` |
| `$PWD` | 当前工作目录 | `/home/terraform` |
| `$SHELL` | 默认 Shell | `/bin/bash` |
| `$LANG` | 语言设置 | `en_US.UTF-8` |
| `$TERM` | 终端类型 | `xterm-256color` |

---

## Step 5 — 特殊变量（15 分钟）

Shell 提供了一组特殊变量，在脚本中非常有用：

### 5.1 脚本相关变量

| 变量 | 含义 |
|------|------|
| `$0` | 脚本名称 |
| `$1`, `$2`, ... | 位置参数（第 1、2... 个参数） |
| `$#` | 参数个数 |
| `$@` | 所有参数（每个参数是独立的） |
| `$*` | 所有参数（合并为一个字符串） |

### 5.2 进程相关变量

| 变量 | 含义 |
|------|------|
| `$$` | 当前脚本的 PID |
| `$!` | 最后一个后台进程的 PID |
| `$?` | 上一个命令的退出状态（0=成功） |

### 5.3 动手实验

```bash
# 创建测试脚本
cat > ~/test_vars.sh << 'EOF'
#!/bin/bash

echo "=== 脚本信息 ==="
echo "脚本名称 (\$0): $0"
echo "参数个数 (\$#): $#"
echo "所有参数 (\$@): $@"
echo "当前 PID (\$\$): $$"

echo ""
echo "=== 逐个参数 ==="
echo "第 1 个 (\$1): $1"
echo "第 2 个 (\$2): $2"
echo "第 3 个 (\$3): $3"

echo ""
echo "=== 退出状态 ==="
ls /nonexistent 2>/dev/null
echo "ls 不存在目录的退出码 (\$?): $?"

ls / >/dev/null
echo "ls 存在目录的退出码 (\$?): $?"
EOF

chmod +x ~/test_vars.sh
```

运行测试：

```bash
~/test_vars.sh hello world "third arg"
```

**输出：**

```
=== 脚本信息 ===
脚本名称 ($0): /home/terraform/test_vars.sh
参数个数 ($#): 3
所有参数 ($@): hello world third arg
当前 PID ($$): 12345

=== 逐个参数 ===
第 1 个 ($1): hello
第 2 个 ($2): world
第 3 个 ($3): third arg

=== 退出状态 ===
ls 不存在目录的退出码 ($?): 2
ls 存在目录的退出码 ($?): 0
```

### 5.4 $@ vs $* 的区别

这是面试常考点！

```bash
cat > ~/at_vs_star.sh << 'EOF'
#!/bin/bash

echo "=== 使用 \$@ ==="
for arg in "$@"; do
    echo "  参数: [$arg]"
done

echo ""
echo "=== 使用 \$* ==="
for arg in "$*"; do
    echo "  参数: [$arg]"
done
EOF

chmod +x ~/at_vs_star.sh
~/at_vs_star.sh "hello world" "foo bar"
```

**输出：**

```
=== 使用 $@ ===
  参数: [hello world]
  参数: [foo bar]

=== 使用 $* ===
  参数: [hello world foo bar]
```

**区别总结：**

- `"$@"` 保持每个参数的边界（推荐使用）
- `"$*"` 把所有参数合并成一个字符串

---

## Step 6 — 命令替换（10 分钟）

### 6.1 两种语法

```bash
# 推荐：$() 语法
TODAY=$(date +%Y-%m-%d)
FILES=$(ls *.txt 2>/dev/null)

# 旧式：反引号（不推荐）
TODAY=`date +%Y-%m-%d`
```

### 6.2 为什么 $() 更好？

```bash
# $() 可以嵌套
NESTED=$(echo $(date +%Y))

# 反引号嵌套需要转义，很丑
NESTED=`echo \`date +%Y\``
```

### 6.3 实用示例

```bash
# 生成带时间戳的文件名
BACKUP_FILE="backup_$(date +%Y%m%d_%H%M%S).tar.gz"
echo $BACKUP_FILE  # backup_20250104_153045.tar.gz

# 获取系统信息
KERNEL=$(uname -r)
CPU_COUNT=$(nproc)
MEM_MB=$(free -m | awk '/Mem:/{print $2}')

echo "内核: $KERNEL"
echo "CPU 核心: $CPU_COUNT"
echo "内存: ${MEM_MB}MB"
```

### 6.4 捕获多行输出

```bash
# 捕获命令的多行输出
FILE_LIST=$(ls -la)
echo "$FILE_LIST"  # 保持换行
echo $FILE_LIST    # 换行变成空格（不推荐）
```

---

## Step 7 — 只读变量（5 分钟）

有些变量设置后不应该被修改：

```bash
# 定义只读变量
readonly VERSION="1.0.0"
readonly CONFIG_FILE="/etc/myapp/config.conf"

# 尝试修改
VERSION="2.0.0"
```

```
bash: VERSION: readonly variable
```

### 实用场景

```bash
#!/bin/bash

# 脚本配置（只读，防止意外修改）
readonly SCRIPT_DIR=$(dirname "$0")
readonly LOG_FILE="/var/log/myapp.log"
readonly MAX_RETRIES=3

# 后续代码即使不小心写了
# MAX_RETRIES=10
# 也会报错，避免 Bug
```

---

## Step 8 — Mini Project：环境信息收集器（10 分钟）

综合运用所学知识，创建一个实用的系统信息收集脚本：

```bash
cat > ~/env_collector.sh << 'EOF'
#!/bin/bash
#
# env_collector.sh - 系统环境信息收集器
# 用途：收集系统信息，生成报告文件
#

# 只读配置
readonly SCRIPT_NAME=$(basename "$0")
readonly REPORT_FILE="/tmp/env_report_$(date +%Y%m%d_%H%M%S).txt"

# 收集系统信息
HOSTNAME=$(hostname)
KERNEL=$(uname -r)
OS=$(cat /etc/os-release 2>/dev/null | grep "^PRETTY_NAME" | cut -d'"' -f2)
CPU_MODEL=$(grep "model name" /proc/cpuinfo 2>/dev/null | head -1 | cut -d':' -f2 | xargs)
CPU_CORES=$(nproc 2>/dev/null || echo "unknown")
MEM_TOTAL=$(free -h 2>/dev/null | awk '/Mem:/{print $2}' || echo "unknown")
DISK_USAGE=$(df -h / 2>/dev/null | awk 'NR==2{print $5}' || echo "unknown")
UPTIME=$(uptime -p 2>/dev/null || uptime)

# 生成报告
{
    echo "========================================"
    echo "   环境信息报告"
    echo "   生成时间: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "========================================"
    echo ""
    echo "--- 基本信息 ---"
    echo "脚本名称: $SCRIPT_NAME"
    echo "当前用户: $USER"
    echo "家目录: $HOME"
    echo "当前目录: $PWD"
    echo ""
    echo "--- 系统信息 ---"
    echo "主机名: $HOSTNAME"
    echo "操作系统: ${OS:-Unknown}"
    echo "内核版本: $KERNEL"
    echo "运行时间: $UPTIME"
    echo ""
    echo "--- 硬件信息 ---"
    echo "CPU: ${CPU_MODEL:-Unknown}"
    echo "CPU 核心数: $CPU_CORES"
    echo "总内存: $MEM_TOTAL"
    echo "根分区使用率: $DISK_USAGE"
    echo ""
    echo "--- Shell 环境 ---"
    echo "默认 Shell: $SHELL"
    echo "当前 Shell PID: $$"
    echo "PATH 目录数: $(echo "$PATH" | tr ':' '\n' | wc -l)"
    echo ""
    echo "--- 脚本参数 ---"
    echo "参数个数: $#"
    echo "所有参数: $@"
    echo ""
    echo "========================================"
    echo "报告文件: $REPORT_FILE"
    echo "========================================"
} | tee "$REPORT_FILE"

# 显示退出状态
echo ""
echo "脚本执行完成，退出状态: $?"
EOF

chmod +x ~/env_collector.sh
```

运行测试：

```bash
~/env_collector.sh --verbose test-mode
```

验证报告文件：

```bash
ls -la /tmp/env_report_*.txt
cat /tmp/env_report_*.txt
```

---

## 本课小结

| 概念 | 语法 | 说明 |
|------|------|------|
| 变量赋值 | `VAR=value` | 等号两边**无空格** |
| 变量引用 | `$VAR` / `${VAR}` | 推荐用 `"${VAR}"` |
| 环境变量 | `export VAR` | 子进程可见 |
| 删除变量 | `unset VAR` | 移除变量 |
| 只读变量 | `readonly VAR` | 不可修改 |
| 命令替换 | `$(command)` | 捕获命令输出 |

**特殊变量速查：**

| 变量 | 含义 |
|------|------|
| `$0` | 脚本名称 |
| `$1`-`$9` | 位置参数 |
| `$#` | 参数个数 |
| `$@` | 所有参数（独立） |
| `$*` | 所有参数（合并） |
| `$?` | 上个命令退出码 |
| `$$` | 当前 PID |
| `$!` | 后台进程 PID |

---

## 常见错误总结

### 错误 1：赋值时有空格

```bash
# ❌ 错误
VAR = "value"

# ✅ 正确
VAR="value"
```

### 错误 2：在循环中使用未引用的 $@

```bash
# ❌ 错误：包含空格的参数会被拆分
for arg in $@; do
    echo "$arg"
done

# ✅ 正确：用引号保护
for arg in "$@"; do
    echo "$arg"
done
```

### 错误 3：混淆 Shell 变量和环境变量

```bash
# 脚本里设置的变量，子脚本看不到
MY_VAR="hello"
./child_script.sh  # 里面 $MY_VAR 是空的！

# 需要 export
export MY_VAR="hello"
./child_script.sh  # 现在可以了
```

---

## 下一步

变量是数据的容器，但如何正确处理包含空格和特殊字符的变量值？这是 Shell 脚本最容易出 Bug 的地方！

-> [03 · 引用规则（重点课）](../03-quoting/)

---

## 面试准备

**よくある質問**

**Q: 環境変数とシェル変数の違いは？**

A: 環境変数は `export` され子プロセスに継承される。シェル変数は現在のシェルのみで有効。例えば PATH は環境変数、ループカウンタは通常シェル変数。

**Q: $@ と $* の違いは？**

A: 引用符内で `"$@"` は各引数を個別の文字列として保持し、`"$*"` は全引数を一つの文字列として扱う。スペースを含む引数を正しく処理するには `"$@"` を使用。

**Q: コマンド置換で $() とバッククォートの違いは？**

A: `$()` は入れ子が簡単でモダン。バッククォートは入れ子にエスケープが必要で可読性が低い。`$()` を推奨。

**Q: readonly 変数の用途は？**

A: スクリプト内で定数を定義し、誤って変更されることを防ぐ。設定値、パスなどに使用。セキュリティと保守性の向上。

---

## トラブルシューティング

**よくある問題**

**変数が空になる**

```bash
# 子プロセスで変数が見えない
MY_VAR="test"
bash -c 'echo $MY_VAR'  # 空

# 解決：export する
export MY_VAR="test"
bash -c 'echo $MY_VAR'  # test
```

**代入でエラー**

```bash
# スペースがある
VAR = "value"
# bash: VAR: command not found

# 解決：スペースを削除
VAR="value"
```

**変数展開が効かない**

```bash
# シングルクォート内は展開されない
echo 'Hello $USER'  # Hello $USER

# 解決：ダブルクォートを使用
echo "Hello $USER"  # Hello terraform
```

---

## 检查清单

在继续下一课之前，确认你能：

- [ ] 正确使用变量赋值语法（无空格）
- [ ] 解释环境变量和 Shell 变量的区别
- [ ] 使用 `export` 导出变量给子进程
- [ ] 使用特殊变量 `$?`, `$$`, `$#`, `$@`
- [ ] 使用 `$()` 进行命令替换
- [ ] 解释 `$@` 和 `$*` 的区别

---

## 延伸阅读

- [Bash Reference Manual - Shell Parameters](https://www.gnu.org/software/bash/manual/html_node/Shell-Parameters.html)
- [Advanced Bash-Scripting Guide - Variables](https://tldp.org/LDP/abs/html/variables.html)

---

## 系列导航

<- [01 · 脚本基础](../01-basics/) | [Home](../) | [03 · 引用规则 ->](../03-quoting/)
