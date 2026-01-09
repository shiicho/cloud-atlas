#!/bin/bash
#
# bad/assignment-spaces.sh - 错误示例：赋值时有空格
#
# 这是 Shell 脚本最常见的错误之一！
# 运行这个脚本会产生错误
#

echo "=== 错误示例：赋值时有空格 ==="
echo ""

echo "尝试: NAME = \"John\""
# 下面这行会报错！
# Shell 会把 NAME 当成命令，= 和 "John" 当成参数
NAME = "John"

echo ""
echo "尝试: NAME= \"John\""
# 这也是错误的
NAME= "John"

echo ""
echo "尝试: NAME =\"John\""
# 这也是错误的
NAME ="John"

echo ""
echo "如果你看到这行，说明 Shell 没有正确处理错误"
