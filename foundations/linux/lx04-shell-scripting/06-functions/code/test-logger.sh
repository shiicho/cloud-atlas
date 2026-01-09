#!/bin/bash
# =============================================================================
# 脚本名称: test-logger.sh
# 功能说明: 测试 logger.sh 函数库
# 作者: Cloud Atlas
# 创建日期: 2026-01-10
# =============================================================================

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 引入日志函数库
source "$SCRIPT_DIR/lib/logger.sh"

echo "=== 日志函数库测试 ==="
echo ""

# 测试 1: 默认配置
echo "--- 测试 1: 默认配置 (LOG_LEVEL=INFO) ---"
log_info "这是 INFO 消息"
log_debug "这是 DEBUG 消息（默认不显示）"
log_warn "这是 WARN 消息"
log_error "这是 ERROR 消息"

echo ""

# 测试 2: 设置 DEBUG 级别
echo "--- 测试 2: 设置 DEBUG 级别 ---"
logger_set_level DEBUG
log_debug "现在 DEBUG 消息会显示"
log_info "INFO 仍然显示"

echo ""

# 测试 3: 测试辅助函数
echo "--- 测试 3: 辅助函数 ---"
log_separator
log_section "这是一个章节标题"

echo ""

# 测试 4: 显示当前配置
echo "--- 测试 4: 当前配置 ---"
echo "日志级别: $(logger_get_level)"
echo "日志文件: $(logger_get_file)"

echo ""

# 测试 5: 输出到文件
echo "--- 测试 5: 输出到文件 ---"
LOG_FILE_PATH="/tmp/test-logger-$$.log"
logger_set_file "$LOG_FILE_PATH"
log_info "这条消息会同时写入文件"
log_error "这条错误也会写入文件"

echo ""
echo "日志文件内容:"
cat "$LOG_FILE_PATH"

# 清理
rm -f "$LOG_FILE_PATH"

echo ""

# 测试 6: ShellCheck 验证
echo "--- 测试 6: ShellCheck 验证 ---"
if command -v shellcheck &>/dev/null; then
    if shellcheck "$SCRIPT_DIR/lib/logger.sh"; then
        echo "ShellCheck: 通过！"
    else
        echo "ShellCheck: 有警告"
    fi
else
    echo "ShellCheck 未安装，跳过检查"
fi

echo ""
echo "=== 测试完成 ==="
