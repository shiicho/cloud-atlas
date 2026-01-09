#!/bin/bash
# =============================================================================
# 脚本名称: local-vars.sh
# 功能说明: 演示 local 局部变量的重要性
# 作者: Cloud Atlas
# 创建日期: 2026-01-10
# =============================================================================

# 全局变量
counter=0
name="全局名字"

# 错误示范：不使用 local（会污染全局作用域）
function bad_function() {
    # 这些变量会泄漏到全局！
    name="被函数修改的名字"
    temp="临时变量"
    counter=$((counter + 1))
}

# 正确示范：使用 local 声明局部变量
function good_function() {
    local name="函数内的局部名字"
    local temp="局部临时变量"

    # 注意：这里仍然会修改全局 counter
    # 如果要保护全局变量，也需要用 local
    local local_counter=$((counter + 1))

    echo "函数内 - name: $name"
    echo "函数内 - temp: $temp"
    echo "函数内 - local_counter: $local_counter"
}

echo "=== 局部变量演示 ==="
echo ""

echo "--- 调用 bad_function 前 ---"
echo "name: $name"
echo "counter: $counter"
echo "temp: ${temp:-未定义}"

echo ""
echo "--- 调用 bad_function ---"
bad_function

echo ""
echo "--- 调用 bad_function 后 ---"
echo "name: $name"           # 被修改了！
echo "counter: $counter"     # 被修改了！
echo "temp: ${temp:-未定义}" # 泄漏了！

echo ""
echo "=========================================="
echo ""

# 重置变量
name="全局名字"
unset temp

echo "--- 调用 good_function 前 ---"
echo "name: $name"
echo "temp: ${temp:-未定义}"

echo ""
echo "--- 调用 good_function ---"
good_function

echo ""
echo "--- 调用 good_function 后 ---"
echo "name: $name"           # 未被修改
echo "temp: ${temp:-未定义}" # 未泄漏

echo ""
echo "=== 结论 ==="
echo "始终使用 local 声明函数内的变量，避免意外修改全局变量！"
