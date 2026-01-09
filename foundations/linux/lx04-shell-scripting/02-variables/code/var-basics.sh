#!/bin/bash
#
# var-basics.sh - Shell 变量基础演示
#
# 演示变量赋值、引用、引号的区别
#

echo "=== 1. 变量赋值 ==="

# 正确的赋值方式
NAME="Linux"
AGE=30
IS_ADMIN=true

echo "NAME=$NAME"
echo "AGE=$AGE"
echo "IS_ADMIN=$IS_ADMIN"

echo ""
echo "=== 2. 变量引用方式 ==="

PREFIX="hello"
# $VAR 和 ${VAR} 的区别
echo "使用 \$PREFIX: $PREFIX"
echo "使用 \${PREFIX}: ${PREFIX}"

# 拼接时 ${} 更清晰
echo "使用 \$PREFIX_world: $PREFIX_world"    # 空！因为变量名是 PREFIX_world
echo "使用 \${PREFIX}_world: ${PREFIX}_world"  # 正确

echo ""
echo "=== 3. 引号的区别 ==="

USER_NAME="World"

# 双引号：变量展开
echo "双引号: Hello, $USER_NAME"

# 单引号：原样输出
echo '单引号: Hello, $USER_NAME'

# 无引号的危险（演示）
FILES="*.sh"
echo "双引号 \"\$FILES\": \"$FILES\""
echo "无引号 \$FILES:"
ls $FILES 2>/dev/null || echo "  (当前目录没有 .sh 文件)"

echo ""
echo "=== 4. 字符串操作 ==="

GREETING="Hello World"

# 字符串长度
echo "字符串: $GREETING"
echo "长度: ${#GREETING}"

# 子串提取 (Bash 特性)
echo "前 5 个字符: ${GREETING:0:5}"
echo "从位置 6 开始: ${GREETING:6}"

echo ""
echo "=== 脚本执行完成 ==="
