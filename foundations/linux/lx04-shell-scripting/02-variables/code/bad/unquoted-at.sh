#!/bin/bash
#
# bad/unquoted-at.sh - 错误示例：循环中使用未引用的 $@
#
# 当参数包含空格时，未引用的 $@ 会导致参数被错误拆分
#
# 用法: ./unquoted-at.sh "hello world" "foo bar"
# 期望输出 2 个参数，但实际输出 4 个
#

echo "=== 错误示例：未引用的 \$@ ==="
echo ""
echo "传入的参数个数: $#"
echo "传入的参数: $@"
echo ""

echo "--- 使用未引用的 \$@ (错误) ---"
count=0
# 错误：$@ 没有加引号
for arg in $@; do
    ((count++))
    echo "  参数 $count: [$arg]"
done

echo ""
echo "预期是 $# 个参数，但循环了 $count 次！"
echo ""
echo "原因：空格导致参数被拆分"
echo ""
echo "正确做法请看 good/quoted-at.sh"
