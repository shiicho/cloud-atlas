#!/bin/bash
#
# special-vars.sh - 特殊变量演示
#
# 演示 $0, $1, $#, $@, $*, $?, $$, $! 等特殊变量
#
# 用法: ./special-vars.sh arg1 arg2 "arg with space"
#

echo "=========================================="
echo "   特殊变量演示"
echo "=========================================="
echo ""

echo "=== 脚本和参数变量 ==="
echo "\$0  (脚本名称): $0"
echo "\$#  (参数个数): $#"
echo "\$1  (第1个参数): ${1:-未提供}"
echo "\$2  (第2个参数): ${2:-未提供}"
echo "\$3  (第3个参数): ${3:-未提供}"

echo ""
echo "=== \$@ vs \$* 的区别 ==="
echo ""
echo "--- 使用 \"\$@\" (推荐) ---"
echo "每个参数保持独立："
count=0
for arg in "$@"; do
    ((count++))
    echo "  参数 $count: [$arg]"
done

echo ""
echo "--- 使用 \"\$*\" ---"
echo "所有参数合并为一个字符串："
count=0
for arg in "$*"; do
    ((count++))
    echo "  参数 $count: [$arg]"
done

echo ""
echo "=== 进程相关变量 ==="
echo "\$\$  (当前脚本 PID): $$"

# 启动一个后台进程来演示 $!
sleep 0.1 &
BACKGROUND_PID=$!
echo "\$!  (后台进程 PID): $BACKGROUND_PID"
wait $BACKGROUND_PID 2>/dev/null

echo ""
echo "=== 退出状态 \$? ==="

# 成功的命令
ls / > /dev/null 2>&1
echo "ls / 的退出状态: $?"

# 失败的命令
ls /nonexistent_directory > /dev/null 2>&1
echo "ls /nonexistent 的退出状态: $?"

# grep 找到匹配
echo "hello" | grep -q "hello"
echo "grep 找到匹配的退出状态: $?"

# grep 没找到匹配
echo "hello" | grep -q "world"
echo "grep 没找到匹配的退出状态: $?"

echo ""
echo "=== 退出状态含义 ==="
echo "0   = 成功"
echo "1   = 一般错误"
echo "2   = 命令使用错误"
echo "126 = 文件不可执行"
echo "127 = 命令未找到"
echo "128+N = 被信号 N 终止"

echo ""
echo "=========================================="
echo "   演示完成"
echo "=========================================="
