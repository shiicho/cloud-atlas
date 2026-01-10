# 10 · 实战：你的第一个脚本

> **目标**：综合运用所学知识，编写一个系统健康报告脚本
> **前置**：已完成 [09 · 环境变量和 PATH](../09-environment-path/)
> **时间**：⚡ 15 分钟（速读）/ 🔬 55 分钟（完整实操）
> **环境**：任意 Linux 发行版  

---

## Capstone 项目简介

恭喜你走到了这里！在这个最终项目中，你将编写一个完整的 Shell 脚本，它会：

1. 创建带时间戳的报告目录
2. 收集系统信息
3. 提取最新日志
4. 生成汇总报告

这个项目综合运用了你在整个课程中学到的所有技能。

---

## Step 1 — 先看成果：运行完整脚本（5 分钟）

> 🎯 **目标**：先看到最终效果，再学习如何构建。  

```bash
# 创建脚本
cat > /tmp/healthcheck.sh << 'SCRIPT'
#!/bin/bash
# System Health Check Script

REPORT_DIR=~/health-reports/$(date +%Y%m%d-%H%M%S)
mkdir -p "$REPORT_DIR"

echo "=== System Health Report ===" > "$REPORT_DIR/summary.txt"
echo "Generated: $(date)" >> "$REPORT_DIR/summary.txt"
echo "" >> "$REPORT_DIR/summary.txt"

uname -a > "$REPORT_DIR/system-info.txt"
df -h > "$REPORT_DIR/disk-usage.txt"
free -h > "$REPORT_DIR/memory.txt"

echo "Reports saved to: $REPORT_DIR"
ls -la "$REPORT_DIR"
SCRIPT

# 运行
chmod +x /tmp/healthcheck.sh
/tmp/healthcheck.sh
```

**看到了什么？**

```
Reports saved to: /home/terraform/health-reports/20250104-143045
total 20
drwxr-xr-x 2 terraform terraform 4096 Jan  4 14:30 .
drwxr-xr-x 3 terraform terraform 4096 Jan  4 14:30 ..
-rw-r--r-- 1 terraform terraform  234 Jan  4 14:30 disk-usage.txt
-rw-r--r-- 1 terraform terraform  156 Jan  4 14:30 memory.txt
-rw-r--r-- 1 terraform terraform   89 Jan  4 14:30 summary.txt
-rw-r--r-- 1 terraform terraform  134 Jan  4 14:30 system-info.txt
```

🎉 **这就是你将要构建的！让我们一步步来。**

---

## Step 2 — 脚本结构基础（20 分钟）

### 2.1 Shebang

每个脚本的第一行：

```bash
#!/bin/bash
```

这告诉系统用 bash 来执行这个脚本。

### 2.2 脚本基本结构

```bash
#!/bin/bash
# ===========================================
# 脚本名称: example.sh
# 描述: 示例脚本结构
# 作者: Your Name
# 日期: 2025-01-04
# ===========================================

# 变量定义
VAR1="value1"
VAR2="value2"

# 主逻辑
echo "Script is running..."
echo "VAR1 = $VAR1"

# 退出
exit 0
```

### 2.3 使脚本可执行

```bash
# 创建脚本文件
touch myscript.sh

# 添加执行权限
chmod +x myscript.sh

# 运行方式 1：相对路径
./myscript.sh

# 运行方式 2：如果在 PATH 中
myscript.sh
```

---

## Step 3 — 变量使用（20 分钟）

### 3.1 变量赋值

```bash
# 基本赋值（注意：等号两边没有空格！）
NAME="John"
COUNT=10

# 使用命令输出
TODAY=$(date +%Y-%m-%d)
HOSTNAME=$(hostname)
```

### 3.2 使用变量

```bash
# 基本使用
echo $NAME
echo "Hello, $NAME"

# 使用花括号（推荐，避免歧义）
echo "${NAME}_backup"  # John_backup
echo "$NAME_backup"    # 可能出错！变量名变成了 NAME_backup
```

### 3.3 引号的区别

```bash
NAME="World"

# 双引号：变量会被展开
echo "Hello, $NAME"    # Hello, World

# 单引号：原样输出
echo 'Hello, $NAME'    # Hello, $NAME

# 反引号/$(...)：命令替换
echo "Date: $(date)"   # Date: Sat Jan  4 14:30:45 JST 2025
```

---

## Step 4 — 逐步构建健康检查脚本（40 分钟）

### 4.1 第一步：创建报告目录

```bash
# ~/bin/healthcheck - 版本 1
cat > ~/bin/healthcheck << 'EOF'
#!/bin/bash
# Health Check Script - v1

# 创建带时间戳的目录
REPORT_DIR=~/health-reports/$(date +%Y%m%d-%H%M%S)
mkdir -p "$REPORT_DIR"

echo "Report directory created: $REPORT_DIR"
EOF

chmod +x ~/bin/healthcheck
healthcheck
```

### 4.2 第二步：收集系统信息

```bash
# ~/bin/healthcheck - 版本 2
cat > ~/bin/healthcheck << 'EOF'
#!/bin/bash
# Health Check Script - v2

# 创建报告目录
REPORT_DIR=~/health-reports/$(date +%Y%m%d-%H%M%S)
mkdir -p "$REPORT_DIR"

# 收集系统信息
echo "Collecting system info..."
uname -a > "$REPORT_DIR/system-info.txt"
hostname > "$REPORT_DIR/hostname.txt"
uptime > "$REPORT_DIR/uptime.txt"

echo "Done! Check $REPORT_DIR"
ls -la "$REPORT_DIR"
EOF

chmod +x ~/bin/healthcheck
healthcheck
```

### 4.3 第三步：添加磁盘和内存信息

```bash
# ~/bin/healthcheck - 版本 3
cat > ~/bin/healthcheck << 'EOF'
#!/bin/bash
# Health Check Script - v3

REPORT_DIR=~/health-reports/$(date +%Y%m%d-%H%M%S)
mkdir -p "$REPORT_DIR"

echo "=== Health Check Starting ==="
echo "Report: $REPORT_DIR"
echo ""

# 系统信息
echo "[1/4] Collecting system info..."
uname -a > "$REPORT_DIR/system-info.txt"

# 磁盘使用
echo "[2/4] Checking disk usage..."
df -h > "$REPORT_DIR/disk-usage.txt"

# 内存使用
echo "[3/4] Checking memory..."
free -h > "$REPORT_DIR/memory.txt"

# 进程信息
echo "[4/4] Getting process info..."
ps aux --sort=-%mem | head -10 > "$REPORT_DIR/top-processes.txt"

echo ""
echo "=== Health Check Complete ==="
ls -la "$REPORT_DIR"
EOF

chmod +x ~/bin/healthcheck
healthcheck
```

### 4.4 第四步：生成汇总报告

```bash
# ~/bin/healthcheck - 最终版本
cat > ~/bin/healthcheck << 'EOF'
#!/bin/bash
# ===========================================
# Health Check Script - Final Version
# Author: Your Name
# Date: 2025-01-04
# ===========================================

# 配置
REPORT_DIR=~/health-reports/$(date +%Y%m%d-%H%M%S)
SUMMARY="$REPORT_DIR/SUMMARY.txt"

# 创建目录
mkdir -p "$REPORT_DIR"

# 开始报告
echo "=== System Health Check ==="
echo "Timestamp: $(date)"
echo "Report: $REPORT_DIR"
echo ""

# 创建汇总文件头
cat > "$SUMMARY" << HEADER
============================================
SYSTEM HEALTH REPORT
Generated: $(date)
Host: $(hostname)
============================================

HEADER

# 1. 系统信息
echo "[1/5] System info..."
uname -a > "$REPORT_DIR/system-info.txt"
echo "System: $(uname -s) $(uname -r)" >> "$SUMMARY"

# 2. 磁盘
echo "[2/5] Disk usage..."
df -h > "$REPORT_DIR/disk-usage.txt"
echo "" >> "$SUMMARY"
echo "--- Disk Usage ---" >> "$SUMMARY"
df -h / | tail -1 >> "$SUMMARY"

# 3. 内存
echo "[3/5] Memory..."
free -h > "$REPORT_DIR/memory.txt"
echo "" >> "$SUMMARY"
echo "--- Memory ---" >> "$SUMMARY"
free -h | grep Mem >> "$SUMMARY"

# 4. 进程
echo "[4/5] Top processes..."
ps aux --sort=-%mem | head -10 > "$REPORT_DIR/top-processes.txt"

# 5. 最近日志错误
echo "[5/5] Recent errors..."
if [ -r /var/log/syslog ]; then
    grep -i error /var/log/syslog | tail -10 > "$REPORT_DIR/recent-errors.txt" 2>/dev/null
fi

# 完成
echo "" >> "$SUMMARY"
echo "============================================" >> "$SUMMARY"
echo "Full reports in: $REPORT_DIR" >> "$SUMMARY"

echo ""
echo "=== Health Check Complete ==="
echo ""
cat "$SUMMARY"
echo ""
echo "Detailed reports:"
ls -la "$REPORT_DIR"
EOF

chmod +x ~/bin/healthcheck
healthcheck
```

---

## Step 5 — 测试和验证（15 分钟）

### 5.1 运行脚本

```bash
healthcheck
```

### 5.2 检查输出

```bash
# 查看最新的报告目录
ls -lt ~/health-reports/ | head -5

# 进入最新目录
cd ~/health-reports/$(ls -t ~/health-reports/ | head -1)

# 查看汇总
cat SUMMARY.txt

# 查看详细报告
cat disk-usage.txt
cat memory.txt
cat top-processes.txt
```

### 5.3 验证清单

- [ ] 脚本可以运行 (`healthcheck`)
- [ ] 创建了带时间戳的目录
- [ ] 生成了所有报告文件
- [ ] SUMMARY.txt 包含汇总信息

---

## Step 6 — 进阶挑战（可选）（15 分钟）

### 6.1 添加命令行参数

```bash
# 添加到脚本开头
if [ "$1" = "-v" ]; then
    VERBOSE=true
fi
```

### 6.2 添加错误检查

```bash
# 检查目录创建是否成功
mkdir -p "$REPORT_DIR" || {
    echo "Error: Cannot create report directory"
    exit 1
}
```

### 6.3 添加颜色输出

```bash
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

echo -e "${GREEN}Success!${NC}"
echo -e "${RED}Error!${NC}"
```

---

## 课程回顾

恭喜你完成了 LX01-FOUNDATIONS！让我们回顾你学到的一切：

| 课程 | 主要技能 |
|------|----------|
| Lesson 01 | Linux 概念、终端 vs Shell |
| Lesson 02 | Shell 提示符、pwd、ls |
| Lesson 03 | 文件系统导航、cd、路径 |
| Lesson 04 | 文件操作、mkdir、rm、cp、mv |
| Lesson 05 | 文件查看、cat、less、tail -f |
| Lesson 06 | 获取帮助、man、--help |
| Lesson 07 | 文本编辑、nano、vim 生存 |
| Lesson 08 | Shell 配置、alias、PS1 |
| Lesson 09 | 环境变量、PATH |
| Lesson 10 | 脚本编写、Capstone 项目 |

---

## 本课小结

| 概念 | 说明 |
|------|------|
| Shebang | `#!/bin/bash` - 脚本第一行 |
| 变量 | `VAR="value"`, 使用 `$VAR` |
| 命令替换 | `$(command)` |
| 脚本权限 | `chmod +x script.sh` |
| 输出重定向 | `>` 覆盖, `>>` 追加 |

**你完成了什么？**
- 从零开始编写了一个实用的系统管理脚本
- 运用了整个课程的所有技能
- 创建了可以日常使用的工具

---

## 下一步

你已经完成了 Linux 基础课程！接下来的学习路径：

| 课程 | 内容 |
|------|------|
| [LX02-SYSADMIN](../../lx02-sysadmin/) | 用户管理、权限、服务 |
| [LX03-TEXT](../../lx03-text-processing/) | grep、sed、awk、文本处理 |
| [LX04-SHELL](../../lx04-shell-scripting/) | 高级 Shell 脚本 |

---

## 面试准备

💼 **よくある質問**

**Q: シェルスクリプトの基本構成は？**

A: 1) Shebang (`#!/bin/bash`)、2) コメントで説明、3) 変数定義、4) メインロジック、5) 終了コード。

**Q: `$()` と バッククォート の違いは？**

A: 機能は同じ（コマンド置換）。`$()` は入れ子可能で読みやすい。バッククォートは古い書き方。

**Q: スクリプトのデバッグ方法は？**

A: `bash -x script.sh` で実行すると各コマンドが表示されます。スクリプト内に `set -x` を書いても同様。

---

## トラブルシューティング

🔧 **よくある問題**

**`Permission denied` でスクリプトが実行できない**

```bash
# 実行権限を付与
chmod +x script.sh

# または bash 経由で実行
bash script.sh
```

**`command not found` でスクリプトが見つからない**

```bash
# PATH を確認
echo $PATH

# ~/bin が含まれていなければ追加
export PATH="$PATH:$HOME/bin"
```

**変数が展開されない**

```bash
# シングルクォートではなくダブルクォートを使用
echo "Value: $VAR"   # ✅ 正しい
echo 'Value: $VAR'   # ❌ 展開されない
```

---

## 检查清单

Capstone 完成確認：

- [ ] 脚本有正确的 shebang (`#!/bin/bash`)
- [ ] 创建了带时间戳的报告目录
- [ ] 收集了系统信息 (`uname -a`)
- [ ] 收集了磁盘使用 (`df -h`)
- [ ] 收集了内存使用 (`free -h`)
- [ ] 生成了汇总报告 (`SUMMARY.txt`)
- [ ] 脚本可以通过命令名直接运行

---

## 系列导航

← [09 · 环境变量](../09-environment-path/) | [Home](../) | [LX02-SYSADMIN →](../../lx02-sysadmin/)

---

## 🎉 恭喜完成！

你已经从 Linux 初学者成长为能够：
- 自信地在终端中导航
- 管理文件和目录
- 使用 man 手册自学
- 编辑配置文件
- 编写自动化脚本

终端不再是黑盒子，而是你的超能力！

继续加油！🚀
