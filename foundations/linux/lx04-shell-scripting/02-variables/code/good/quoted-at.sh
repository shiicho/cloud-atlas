#!/bin/bash
#
# good/quoted-at.sh - 正确示例：循环中使用引号包裹 $@
#
# 使用 "$@" 可以正确保持每个参数的边界
#
# 用法: ./quoted-at.sh "hello world" "foo bar"
# 正确输出 2 个参数
#

echo "=== 正确示例：引号包裹的 \"\$@\" ==="
echo ""
echo "传入的参数个数: $#"
echo "传入的参数: $@"
echo ""

echo "--- 使用引号包裹的 \"\$@\" (正确) ---"
count=0
# 正确："$@" 加了引号
for arg in "$@"; do
    ((count++))
    echo "  参数 $count: [$arg]"
done

echo ""
echo "参数个数 ($#) 和循环次数 ($count) 一致！"
echo ""

echo "=== 对比 \"\$@\" 和 \"\$*\" ==="
echo ""

echo "--- \"\$@\" 保持独立参数 ---"
for arg in "$@"; do
    echo "  [$arg]"
done

echo ""
echo "--- \"\$*\" 合并为一个字符串 ---"
for arg in "$*"; do
    echo "  [$arg]"
done

echo ""
echo "=== 总结 ==="
echo "处理参数时，总是使用 \"\$@\" 而不是 \$@ 或 \"\$*\""
