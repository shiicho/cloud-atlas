#!/bin/bash
#
# good/correct-assignment.sh - 正确示例：变量赋值
#
# 正确的变量赋值：等号两边没有空格
#

echo "=== 正确示例：变量赋值 ==="
echo ""

# 正确：等号两边没有空格
NAME="John"
AGE=30
IS_ADMIN=true
EMPTY=""  # 空字符串

echo "NAME=$NAME"
echo "AGE=$AGE"
echo "IS_ADMIN=$IS_ADMIN"
echo "EMPTY='$EMPTY' (空字符串)"

echo ""
echo "=== 赋值后立即 export ==="

# 声明时 export
export PROJECT="MyProject"

# 或者先声明后 export
VERSION="1.0.0"
export VERSION

echo "PROJECT=$PROJECT (已 export)"
echo "VERSION=$VERSION (已 export)"

echo ""
echo "=== 使用命令输出赋值 ==="

# 使用 $() 捕获命令输出
CURRENT_DATE=$(date +%Y-%m-%d)
HOSTNAME_VAR=$(hostname)

echo "CURRENT_DATE=$CURRENT_DATE"
echo "HOSTNAME_VAR=$HOSTNAME_VAR"

echo ""
echo "=== 记住：等号两边不能有空格！ ==="
