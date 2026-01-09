# 01 · 脚本基础与执行方式（Script Basics and Execution）

> **目标**：创建并运行你的第一个规范的 Shell 脚本  
> **前置**：LX01 基础命令行操作 + LX03 文本处理基础  
> **时间**：60-90 分钟  
> **环境**：Bash 4.x+（RHEL 7/8/9, Ubuntu 18.04+ 均可）  

---

## 将学到的内容

1. 理解脚本结构：shebang、注释、代码
2. 掌握脚本执行方式：直接执行、bash 调用、source
3. 理解执行权限（chmod +x）
4. 认识 ShellCheck 静态分析工具
5. 写出第一个规范的 Shell 脚本

---

## 先跑起来！（5 分钟）

> 在理解原理之前，先让脚本跑起来。  
> 体验从零到运行的完整过程。  

```bash
# 创建练习目录
mkdir -p ~/shell-lab && cd ~/shell-lab

# 创建你的第一个脚本
cat > hello.sh << 'EOF'
#!/bin/bash
# 我的第一个 Shell 脚本
# 作者：你的名字
# 日期：$(date +%Y-%m-%d)

echo "Hello, Shell Scripting!"
echo "当前用户: $(whoami)"
echo "当前时间: $(date)"
EOF

# 查看脚本内容
cat hello.sh

# 给脚本执行权限
chmod +x hello.sh

# 运行它！
./hello.sh
```

**你应该看到类似的输出：**

```
Hello, Shell Scripting!
当前用户: terraform
当前时间: Sat Jan 10 14:30:45 JST 2026
```

**恭喜！你刚刚创建并运行了你的第一个 Shell 脚本！**

现在让我们理解每一步背后的原理。

---

## Step 1 — 脚本结构：三大组成部分（15 分钟）

### 1.1 Shebang：脚本的灵魂

脚本第一行的 `#!/bin/bash` 叫做 **shebang**（也叫 hashbang）。

![Script Structure](images/script-structure.png)

<details>
<summary>View ASCII source</summary>

<!-- DIAGRAM: script-structure -->
```
┌─────────────────────────────────────────────────────────────────────┐
│  Shell Script 结构                                                   │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  #!/bin/bash                    ← Shebang（指定解释器）              │
│  ─────────────────────────────────────────────────────────────────  │
│  # 这是注释                     ← 注释（说明用途）                   │
│  # 作者：张三                                                        │
│  # 日期：2026-01-10                                                  │
│  ─────────────────────────────────────────────────────────────────  │
│  VAR="value"                    ← 代码（变量、命令、逻辑）           │
│  echo "Hello, $VAR"                                                  │
│  if [ -f "$file" ]; then                                             │
│      process_file "$file"                                            │
│  fi                                                                  │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```
<!-- /DIAGRAM -->

</details>

**Shebang 的作用：**

```bash
# 当你运行 ./hello.sh 时：
# 1. 系统读取第一行 #!/bin/bash
# 2. 系统用 /bin/bash 来解释执行这个文件
# 3. 相当于运行：/bin/bash ./hello.sh
```

### 1.2 两种 Shebang 写法

| 写法 | 示例 | 特点 |
|------|------|------|
| **绝对路径** | `#!/bin/bash` | 固定位置，快速 |
| **env 查找** | `#!/usr/bin/env bash` | 从 PATH 查找，跨平台 |

**实际演示：**

```bash
cd ~/shell-lab

# 方法 1：绝对路径
cat > shebang-absolute.sh << 'EOF'
#!/bin/bash
echo "Bash 位置: /bin/bash"
EOF

# 方法 2：env 查找
cat > shebang-env.sh << 'EOF'
#!/usr/bin/env bash
echo "Bash 位置: 从 PATH 查找"
EOF

chmod +x shebang-absolute.sh shebang-env.sh
./shebang-absolute.sh
./shebang-env.sh
```

**什么时候用哪种？**

- `#!/bin/bash` — 企业内部脚本，环境统一
- `#!/usr/bin/env bash` — 开源项目，需要跨平台（macOS Bash 在 `/usr/local/bin/bash`）

> **日本 IT 小贴士**：在日本企业的运维环境中，服务器通常是 RHEL/CentOS，  
> Bash 固定在 `/bin/bash`，使用绝对路径更常见。  

### 1.3 注释：代码的说明书

```bash
#!/bin/bash
# =========================================================================
# 脚本名称：backup.sh
# 功能说明：每日备份 /var/log 目录
# 作者：张三
# 创建日期：2026-01-10
# 修改历史：
#   2026-01-15 - 添加压缩功能
# =========================================================================

# 单行注释：说明下一行代码的作用
backup_dir="/backup"  # 行尾注释：简短说明

# 注释规范：
# 1. 文件头部说明脚本用途
# 2. 复杂逻辑前添加说明
# 3. 关键变量说明含义
```

---

## Step 2 — 执行方式对比（15 分钟）

Shell 脚本有三种主要执行方式，理解它们的区别非常重要。

### 2.1 三种执行方式

![Execution Modes](images/execution-modes.png)

<details>
<summary>View ASCII source</summary>

<!-- DIAGRAM: execution-modes -->
```
┌─────────────────────────────────────────────────────────────────────┐
│  三种执行方式对比                                                    │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  1. ./script.sh  或  bash script.sh                                  │
│     ┌──────────────┐      ┌──────────────┐                          │
│     │  父 Shell    │─────▶│  子 Shell    │  ← 脚本在新进程中执行     │
│     │  (当前终端)   │      │  (新进程)    │                          │
│     └──────────────┘      └──────────────┘                          │
│           │                     │                                    │
│           │                     └── 变量改变不影响父 Shell           │
│           │                                                          │
│  2. source script.sh  或  . script.sh                               │
│     ┌──────────────────────────────────────┐                        │
│     │            当前 Shell                 │  ← 直接在当前进程执行  │
│     │                                       │                        │
│     │    执行脚本内容                       │                        │
│     │    变量改变保留在当前 Shell           │                        │
│     └──────────────────────────────────────┘                        │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```
<!-- /DIAGRAM -->

</details>

### 2.2 实际演示

```bash
cd ~/shell-lab

# 创建测试脚本
cat > set-var.sh << 'EOF'
#!/bin/bash
MY_VAR="我是脚本设置的变量"
echo "脚本内部: MY_VAR = $MY_VAR"
EOF

chmod +x set-var.sh

# 方法 1：子 shell 执行（变量不会保留）
echo "=== 执行前 ==="
echo "MY_VAR = $MY_VAR"

./set-var.sh

echo "=== 执行后 ==="
echo "MY_VAR = $MY_VAR"  # 仍然是空的！
```

```bash
# 方法 2：source 执行（变量会保留）
echo "=== source 执行前 ==="
echo "MY_VAR = $MY_VAR"

source set-var.sh

echo "=== source 执行后 ==="
echo "MY_VAR = $MY_VAR"  # 变量已设置！
```

### 2.3 执行方式速查表

| 方式 | 语法 | 需要权限 | 变量作用域 | 常用场景 |
|------|------|----------|------------|----------|
| 直接执行 | `./script.sh` | 需要 +x | 子 shell | 运行独立程序 |
| bash 调用 | `bash script.sh` | 不需要 | 子 shell | 调试、临时运行 |
| source | `source script.sh` 或 `. script.sh` | 不需要 | 当前 shell | 加载环境变量、函数库 |

### 2.4 source 的实际应用

```bash
# ~/.bashrc 中常见的用法
source ~/.bash_aliases    # 加载别名定义
source /opt/app/env.sh    # 加载应用环境变量

# 加载函数库
source /usr/local/lib/logging.sh
log_info "程序启动"
```

> **面试考点**：`source` 和 `.` 是完全等价的。`.` 是 POSIX 标准，`source` 是 Bash 扩展。  

---

## Step 3 — 执行权限（10 分钟）

### 3.1 为什么需要执行权限？

```bash
cd ~/shell-lab

# 创建一个新脚本（默认没有执行权限）
echo '#!/bin/bash' > new-script.sh
echo 'echo "Hello"' >> new-script.sh

# 查看权限
ls -l new-script.sh
# -rw-r--r--  说明：rw- 读写，没有 x 执行权限

# 尝试执行
./new-script.sh
# bash: ./new-script.sh: Permission denied
```

### 3.2 chmod +x 赋予执行权限

```bash
# 添加执行权限
chmod +x new-script.sh

# 再次查看权限
ls -l new-script.sh
# -rwxr-xr-x  现在有 x 了！

# 现在可以执行
./new-script.sh
# Hello
```

### 3.3 权限数字表示法

```bash
# 常用权限组合
chmod 755 script.sh   # rwxr-xr-x  所有人可执行，只有所有者可修改
chmod 700 script.sh   # rwx------  只有所有者可以运行
chmod 644 script.sh   # rw-r--r-- 普通文件，不可执行
```

| 数字 | 权限 | 说明 |
|------|------|------|
| 7 | rwx | 读 + 写 + 执行 |
| 5 | r-x | 读 + 执行 |
| 4 | r-- | 只读 |

---

## Step 4 — ShellCheck：你的代码检查员（10 分钟）

### 4.1 什么是 ShellCheck？

ShellCheck 是 Shell 脚本的静态分析工具，能在运行前发现问题。

**从第一天就用 ShellCheck 是本课程的核心理念！**

### 4.2 安装 ShellCheck

```bash
# Ubuntu/Debian
sudo apt install shellcheck

# RHEL/CentOS 8+
sudo dnf install ShellCheck

# macOS
brew install shellcheck

# 验证安装
shellcheck --version
```

### 4.3 ShellCheck 实战

```bash
cd ~/shell-lab

# 创建一个有问题的脚本
cat > buggy.sh << 'EOF'
#!/bin/bash
# 这个脚本故意包含常见错误

name=Alice
echo "Hello, $name"

# 反模式 1：使用反引号
files=`ls`
echo $files

# 反模式 2：无用的 cat
cat /etc/passwd | grep root
EOF

# 运行 ShellCheck
shellcheck buggy.sh
```

**ShellCheck 输出：**

```
In buggy.sh line 8:
files=`ls`
      ^--^ SC2006: Use $(...) notation instead of legacy backticked `...`.

In buggy.sh line 9:
echo $files
     ^----^ SC2086: Double quote to prevent globbing and word splitting.

In buggy.sh line 12:
cat /etc/passwd | grep root
^-- SC2002: Useless use of cat. Consider 'grep root /etc/passwd' instead.
```

### 4.4 修复 ShellCheck 警告

```bash
cat > fixed.sh << 'EOF'
#!/bin/bash
# 修复后的脚本

name="Alice"
echo "Hello, $name"

# 修复 1：使用 $() 代替反引号
files=$(ls)
echo "$files"

# 修复 2：去掉无用的 cat
grep root /etc/passwd
EOF

# 再次检查
shellcheck fixed.sh
# 没有警告了！
```

### 4.5 常见 ShellCheck 规则

| 规则 | 含义 | 修复方法 |
|------|------|----------|
| SC2006 | 使用反引号 | 改用 `$()` |
| SC2086 | 变量未加引号 | 使用 `"$var"` |
| SC2002 | 无用的 cat | 直接把文件作为命令参数 |
| SC2046 | 命令替换未加引号 | 使用 `"$(command)"` |

> **开发习惯**：每次保存脚本后运行 `shellcheck script.sh`，像编译前的语法检查一样。  

---

## Step 5 — 脚本模板：标准化你的代码（10 分钟）

### 5.1 推荐的脚本模板

```bash
cd ~/shell-lab

cat > template.sh << 'TEMPLATE'
#!/bin/bash
# =============================================================================
# 脚本名称: template.sh
# 功能说明: [简短描述脚本用途]
# 作者: [你的名字]
# 创建日期: [YYYY-MM-DD]
# 版本: 1.0.0
# =============================================================================
#
# 使用方法:
#   ./template.sh [参数]
#
# 依赖:
#   - bash 4.0+
#   - [其他依赖]
#
# =============================================================================

# 严格模式（Lesson 09 会详细讲解）
# set -euo pipefail

# 全局变量
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_NAME="$(basename "$0")"

# 主逻辑
main() {
    echo "脚本路径: $SCRIPT_DIR"
    echo "脚本名称: $SCRIPT_NAME"
    echo "Hello from template!"
}

# 执行主函数
main "$@"
TEMPLATE

chmod +x template.sh
./template.sh
```

### 5.2 脚本命名规范

| 规范 | 好的例子 | 不好的例子 |
|------|----------|------------|
| 使用 .sh 后缀 | `backup.sh` | `backup` |
| 有意义的名字 | `daily-backup.sh` | `script1.sh` |
| 小写 + 连字符 | `log-rotate.sh` | `LogRotate.sh` |
| 动词开头 | `check-disk.sh` | `disk.sh` |

---

## Step 6 — Mini Project：Hello World 脚本（15 分钟）

> **项目目标**：创建一个规范的脚本，通过 ShellCheck 检查。  

### 6.1 项目要求

创建一个脚本 `system-info.sh`，要求：

1. 正确的 shebang
2. 完整的头部注释
3. 显示系统信息（主机名、日期、用户、内核版本）
4. 通过 ShellCheck 零警告

### 6.2 参考实现

```bash
cd ~/shell-lab

cat > system-info.sh << 'EOF'
#!/bin/bash
# =============================================================================
# 脚本名称: system-info.sh
# 功能说明: 显示系统基本信息
# 作者: [你的名字]
# 创建日期: 2026-01-10
# =============================================================================

echo "=========================================="
echo "         系统信息报告"
echo "=========================================="
echo ""
echo "主机名:     $(hostname)"
echo "当前用户:   $(whoami)"
echo "当前日期:   $(date '+%Y-%m-%d %H:%M:%S')"
echo "内核版本:   $(uname -r)"
echo "操作系统:   $(cat /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2)"
echo ""
echo "=========================================="
EOF

chmod +x system-info.sh

# ShellCheck 检查
shellcheck system-info.sh

# 运行脚本
./system-info.sh
```

**预期输出：**

```
==========================================
         系统信息报告
==========================================

主机名:     my-server
当前用户:   terraform
当前日期:   2026-01-10 14:45:30
内核版本:   5.15.0-91-generic
操作系统:   Ubuntu 22.04.3 LTS

==========================================
```

---

## 反模式：常见错误

### 错误 1：缺少 Shebang

```bash
# 错误：没有 shebang
echo "Hello"

# 问题：脚本行为依赖当前 shell，不可预测
# 可能在 bash 正常，在 dash 报错

# 正确：始终添加 shebang
#!/bin/bash
echo "Hello"
```

### 错误 2：使用反引号

```bash
# 错误：反引号难以阅读和嵌套
files=`ls`
nested=`echo \`date\``

# 正确：使用 $()
files=$(ls)
nested=$(echo "$(date)")
```

### 错误 3：无用的 cat

```bash
# 错误：多余的 cat
cat file.txt | grep "pattern"
cat file.txt | wc -l

# 正确：直接使用文件参数
grep "pattern" file.txt
wc -l < file.txt
```

> **记住**：ShellCheck 会自动发现这些问题！养成运行 ShellCheck 的习惯。  

---

## 职场小贴士（Japan IT Context）

### 运维脚本（運用スクリプト）的规范

在日本 IT 企业，运维脚本有严格的规范要求：

| 日语术语 | 含义 | 要求 |
|----------|------|------|
| ドキュメント | 文档 | 脚本头部必须有详细说明 |
| 変更履歴 | 修改历史 | 记录每次修改的日期、内容、作者 |
| テスト | 测试 | 脚本需要在测试环境验证 |
| レビュー | 审查 | 上线前需要同事审查代码 |

### 典型的日本企业脚本头部

```bash
#!/bin/bash
# ==============================================================================
# スクリプト名: daily-backup.sh
# 概要: 日次バックアップ処理
# 作成者: 田中太郎
# 作成日: 2026-01-10
#
# 変更履歴:
#   2026-01-10 新規作成 (田中)
#   2026-01-15 圧縮機能追加 (佐藤)
#
# 使用方法:
#   ./daily-backup.sh [対象ディレクトリ]
#
# 戻り値:
#   0: 正常終了
#   1: 引数エラー
#   2: バックアップ失敗
# ==============================================================================
```

---

## Bash 版本检查

本课程的实验在 Bash 4.x+ 均可运行。高级功能会标注版本要求。

```bash
# 检查你的 Bash 版本
bash --version

# 在脚本中检查版本（可选）
if ((BASH_VERSINFO[0] < 4)); then
    echo "This script requires Bash 4.0+" >&2
    exit 1
fi
```

| 发行版 | 默认 Bash 版本 |
|--------|----------------|
| RHEL 7 | 4.2 |
| RHEL 8 | 4.4 |
| RHEL 9 | 5.1 |
| Ubuntu 20.04 | 5.0 |
| Ubuntu 22.04 | 5.1 |

---

## 检查清单

完成本课后，你应该能够：

- [ ] 解释 shebang 的作用和两种写法的区别
- [ ] 编写包含 shebang、注释、代码的规范脚本
- [ ] 使用 `chmod +x` 赋予执行权限
- [ ] 区分 `./script.sh`、`bash script.sh`、`source script.sh` 的区别
- [ ] 安装并使用 ShellCheck 检查脚本
- [ ] 避免反引号和无用 cat 的反模式

---

## 本课小结

| 概念 | 要点 |
|------|------|
| Shebang | `#!/bin/bash` 或 `#!/usr/bin/env bash` |
| 脚本结构 | shebang + 注释 + 代码 |
| 执行权限 | `chmod +x script.sh` |
| 执行方式 | `./script.sh`（子 shell）vs `source script.sh`（当前 shell） |
| ShellCheck | 静态分析，从第一天就用 |
| 命名规范 | 小写 + 连字符 + .sh 后缀 |

---

## 面试准备

### **#!/bin/bash と #!/usr/bin/env bash の違いは？**

`/bin/bash` は固定パスで直接 Bash を呼び出します。`/usr/bin/env bash` は PATH 環境変数から Bash を検索するため、異なるシステム（macOS など）でも動作します。移植性が必要な場合は `env` を使用します。

### **source と実行の違いは？**

`./script.sh` はサブシェル（新しいプロセス）で実行されるため、スクリプト内の変数変更は親シェルに影響しません。`source script.sh`（または `. script.sh`）は現在のシェルで直接実行されるため、変数や関数の変更が保持されます。環境設定ファイル（`.bashrc` など）の読み込みに使用されます。

---

## 延伸阅读

- [GNU Bash Manual](https://www.gnu.org/software/bash/manual/)
- [ShellCheck Wiki](https://github.com/koalaman/shellcheck/wiki)
- 下一课：[02 · 变量与环境](../02-variables/) — 理解变量作用域
- 相关课程：[LX03 · 文本处理](../../text-processing/) — 管道和重定向基础

---

## 系列导航

[课程首页](../) | [02 · 变量与环境 →](../02-variables/)
