#!/bin/bash
# =============================================================================
# 脚本名称: function-basics.sh
# 功能说明: 演示 Shell 函数的基本用法
# 作者: Cloud Atlas
# 创建日期: 2026-01-10
# =============================================================================

# 方式 1：使用 function 关键字（Bash 风格，推荐）
function say_hello() {
    echo "Hello, World!"
}

# 方式 2：不使用 function 关键字（POSIX 兼容）
say_bye() {
    echo "Goodbye, World!"
}

# 带参数的函数
function greet() {
    local name="${1:-Guest}"  # 默认值为 Guest
    echo "你好，$name！"
}

# 带多个参数的函数
function print_info() {
    echo "用户: $1"
    echo "年龄: $2"
    echo "城市: $3"
    echo "参数总数: $#"
    echo "所有参数: $*"
}

# 主程序
echo "=== 函数基础演示 ==="
echo ""

echo "--- 调用无参数函数 ---"
say_hello
say_bye

echo ""
echo "--- 调用带参数函数 ---"
greet "运维工程师"
greet  # 使用默认值

echo ""
echo "--- 调用多参数函数 ---"
print_info "张三" "28" "东京"
