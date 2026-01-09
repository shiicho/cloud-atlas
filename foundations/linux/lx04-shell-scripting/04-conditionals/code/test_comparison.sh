#!/bin/bash
# =============================================================================
# 脚本名称: test_comparison.sh
# 功能说明: 演示 [ ] 和 [[ ]] 的区别
# 作者: Cloud Atlas
# 创建日期: 2026-01-10
# =============================================================================
#
# 本脚本演示 Shell 中三种条件测试方式的差异:
#   1. test 命令
#   2. [ ] (test 的语法糖)
#   3. [[ ]] (Bash 增强版)
#
# =============================================================================

VAR=""
FILE="my file.txt"

echo "=== 测试 1：空变量处理 ==="
echo "VAR 的值是: '$VAR' (空字符串)"
echo ""

# [ ] 中空变量会导致语法错误（演示注释掉，避免脚本出错）
# 错误示例: [ $VAR = "hello" ]  # 展开后变成 [ = "hello" ]，语法错误

# [ ] 中必须加引号
if [ "$VAR" = "hello" ]; then
    echo "[ ] 匹配成功"
else
    echo "[ ] 匹配失败（变量为空）"
fi

# [[ ]] 中不需要引号也安全
if [[ $VAR = "hello" ]]; then
    echo "[[ ]] 匹配成功"
else
    echo "[[ ]] 匹配失败（变量为空）"
fi

echo ""
echo "=== 测试 2：逻辑运算符 ==="

A=5
B=10
echo "A=$A, B=$B"
echo ""

# [ ] 中使用 -a (AND) 和 -o (OR)
if [ "$A" -lt 10 -a "$B" -gt 5 ]; then
    echo "[ ] 使用 -a: A<10 且 B>5 成立"
fi

# [[ ]] 中使用 && (AND) 和 || (OR)
if [[ $A -lt 10 && $B -gt 5 ]]; then
    echo "[[ ]] 使用 &&: A<10 且 B>5 成立"
fi

echo ""
echo "=== 测试 3：模式匹配（[[ ]] 专属）==="

TEXT="hello_world"
echo "TEXT='$TEXT'"
echo ""

# [[ ]] 支持通配符模式匹配（= 或 == 都可以）
if [[ $TEXT == hello* ]]; then
    echo "通配符: TEXT 以 'hello' 开头"
fi

if [[ $TEXT == *world ]]; then
    echo "通配符: TEXT 以 'world' 结尾"
fi

if [[ $TEXT == *_* ]]; then
    echo "通配符: TEXT 包含下划线"
fi

# [[ ]] 支持正则表达式匹配 (=~)
if [[ $TEXT =~ ^hello.*world$ ]]; then
    echo "正则: TEXT 匹配 ^hello.*world$"
fi

# 正则匹配可以捕获分组
if [[ $TEXT =~ ^(.*)_(.*)$ ]]; then
    echo "正则捕获: 前半部分='${BASH_REMATCH[1]}', 后半部分='${BASH_REMATCH[2]}'"
fi

echo ""
echo "=== 测试 4：处理带空格的文件名 ==="

# 创建带空格的测试文件
touch "$FILE"
echo "创建了测试文件: '$FILE'"

# [ ] 中必须引用变量
if [ -f "$FILE" ]; then
    echo "[ ] 找到文件: '$FILE'"
fi

# [[ ]] 中引号可选（但仍推荐加上）
if [[ -f $FILE ]]; then
    echo "[[ ]] 找到文件: '$FILE'"
fi

# 清理测试文件
rm -f "$FILE"
echo "已清理测试文件"

echo ""
echo "=== 测试 5：< > 比较符号 ==="

# 在 [ ] 中，< > 需要转义（否则被解释为重定向）
# [ "apple" \< "banana" ]   # 需要转义

# 在 [[ ]] 中，< > 可以直接使用
if [[ "apple" < "banana" ]]; then
    echo "[[ ]]: 'apple' < 'banana' (字典序)"
fi

echo ""
echo "=== 总结 ==="
echo "推荐在 Bash 脚本中使用 [[ ]]:"
echo "  1. 不需要对变量加引号（更安全）"
echo "  2. 支持 && || 逻辑运算符（更可读）"
echo "  3. 支持模式匹配和正则表达式"
echo "  4. < > 不需要转义"
