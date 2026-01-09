#!/bin/bash
#
# command-substitution.sh - 命令替换演示
#
# 演示 $(command) 的用法和实际应用场景
#

echo "=========================================="
echo "   命令替换演示"
echo "=========================================="
echo ""

echo "=== 1. 基本语法 ==="
echo ""

# 推荐语法：$()
TODAY=$(date +%Y-%m-%d)
HOSTNAME_VAR=$(hostname)

echo "今天的日期: $TODAY"
echo "主机名: $HOSTNAME_VAR"

# 旧式语法：反引号（不推荐）
YEAR=`date +%Y`
echo "年份 (反引号): $YEAR"

echo ""
echo "=== 2. 嵌套命令替换 ==="
echo ""

# $() 可以轻松嵌套
NESTED=$(echo "Current year is $(date +%Y)")
echo "$NESTED"

# 反引号嵌套需要转义（可读性差）
# NESTED=`echo "Current year is \`date +%Y\`"`

echo ""
echo "=== 3. 实际应用场景 ==="
echo ""

# 生成带时间戳的文件名
BACKUP_FILE="backup_$(date +%Y%m%d_%H%M%S).tar.gz"
echo "备份文件名: $BACKUP_FILE"

# 获取系统信息
KERNEL=$(uname -r)
ARCH=$(uname -m)
echo "内核版本: $KERNEL"
echo "系统架构: $ARCH"

# 计算文件数量
FILE_COUNT=$(ls -1 2>/dev/null | wc -l)
echo "当前目录文件数: $FILE_COUNT"

# 获取脚本所在目录
SCRIPT_DIR=$(dirname "$0")
echo "脚本目录: $SCRIPT_DIR"

echo ""
echo "=== 4. 捕获多行输出 ==="
echo ""

# 捕获命令的多行输出
PROCESS_LIST=$(ps aux | head -5)

echo "--- 使用双引号（保持换行）---"
echo "$PROCESS_LIST"

echo ""
echo "--- 不使用双引号（换行变空格）---"
echo $PROCESS_LIST

echo ""
echo "=== 5. 结合条件判断 ==="
echo ""

# 检查命令是否存在
if command -v git >/dev/null 2>&1; then
    GIT_VERSION=$(git --version)
    echo "Git 已安装: $GIT_VERSION"
else
    echo "Git 未安装"
fi

# 检查用户是否是 root
CURRENT_UID=$(id -u)
if [ "$CURRENT_UID" -eq 0 ]; then
    echo "当前用户是 root"
else
    echo "当前用户不是 root (UID: $CURRENT_UID)"
fi

echo ""
echo "=== 6. 算术运算 ==="
echo ""

# 使用命令替换进行计算
FILE_SIZE=$(du -sh /etc 2>/dev/null | cut -f1)
echo "/etc 目录大小: $FILE_SIZE"

# 计算两个数的和
A=5
B=3
SUM=$((A + B))
echo "$A + $B = $SUM"

# 使用 expr（旧方式）
PRODUCT=$(expr $A \* $B)
echo "$A * $B = $PRODUCT"

echo ""
echo "=========================================="
echo "   演示完成"
echo "=========================================="
