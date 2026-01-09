#!/bin/bash
# =============================================================================
# 脚本名称: return-values.sh
# 功能说明: 演示函数返回值的两种方式：exit code vs 输出捕获
# 作者: Cloud Atlas
# 创建日期: 2026-01-10
# =============================================================================

# 返回码常量（好习惯）
readonly SUCCESS=0
readonly ERR_NOT_FOUND=1
readonly ERR_PERMISSION=2
readonly ERR_INVALID_ARG=3

# =============================================================================
# 方式 1：return 返回退出码（0-255）
# 用于表示成功/失败状态
# =============================================================================

# 检查文件是否存在
function check_file_exists() {
    local file="$1"

    if [[ -z "$file" ]]; then
        return $ERR_INVALID_ARG
    fi

    if [[ -f "$file" ]]; then
        return $SUCCESS
    else
        return $ERR_NOT_FOUND
    fi
}

# 检查当前用户是否是 root
function is_root() {
    if [[ $(id -u) -eq 0 ]]; then
        return 0  # 是 root
    else
        return 1  # 不是 root
    fi
}

# =============================================================================
# 方式 2：echo 输出数据
# 用于返回字符串、数字等数据
# =============================================================================

# 获取当前时间戳
function get_timestamp() {
    echo "$(date '+%Y-%m-%d %H:%M:%S')"
}

# 计算两数之和
function add_numbers() {
    local a=${1:-0}
    local b=${2:-0}
    echo $((a + b))
}

# 获取文件行数
function count_lines() {
    local file="$1"
    if [[ -f "$file" ]]; then
        wc -l < "$file"
    else
        echo "0"
    fi
}

# =============================================================================
# 方式 3：组合使用（最佳实践）
# 用 return 返回状态，用 echo 返回数据
# =============================================================================

# 获取用户 UID
function get_user_uid() {
    local username="$1"

    # 参数验证
    if [[ -z "$username" ]]; then
        echo ""
        return $ERR_INVALID_ARG
    fi

    # 检查用户是否存在
    if ! id "$username" &>/dev/null; then
        echo ""
        return $ERR_NOT_FOUND
    fi

    # 返回 UID
    id -u "$username"
    return $SUCCESS
}

# =============================================================================
# 演示
# =============================================================================

echo "=== 函数返回值演示 ==="
echo ""

echo "--- 方式 1：return 返回退出码 ---"
echo ""

# 使用 if 判断
echo "检查 /etc/passwd："
if check_file_exists "/etc/passwd"; then
    echo "  文件存在"
else
    echo "  文件不存在"
fi

echo "检查 /nonexistent："
if check_file_exists "/nonexistent"; then
    echo "  文件存在"
else
    echo "  文件不存在"
fi

# 使用 $? 获取返回码
check_file_exists ""
echo "空参数的返回码: $?"

echo ""
# 判断是否 root
if is_root; then
    echo "当前用户是 root"
else
    echo "当前用户不是 root"
fi

echo ""
echo "--- 方式 2：echo 输出数据 ---"
echo ""

# 捕获函数输出
timestamp=$(get_timestamp)
echo "当前时间: $timestamp"

sum=$(add_numbers 15 27)
echo "15 + 27 = $sum"

lines=$(count_lines /etc/passwd)
echo "/etc/passwd 有 $lines 行"

echo ""
echo "--- 方式 3：组合使用 ---"
echo ""

# 同时检查状态和获取数据
if uid=$(get_user_uid "root"); then
    echo "root 的 UID: $uid"
else
    echo "获取 root UID 失败"
fi

if uid=$(get_user_uid "nonexistent_user_12345"); then
    echo "nonexistent 的 UID: $uid"
else
    echo "用户 nonexistent_user_12345 不存在"
fi

echo ""
echo "=== 错误示范：用 return 返回字符串 ==="
echo ""

# 这是错误的！
function bad_return_string() {
    # return "Hello"  # 这会报错！
    echo "return 只能返回 0-255 的数字"
}
bad_return_string
