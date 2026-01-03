#!/bin/bash
# =============================================================================
# check_errors.sh - Log Error Checker Script
# =============================================================================
#
# A simple script demonstrating grep exit codes for automation.
# This is a common pattern in operations monitoring (運用監視).
#
# Usage: ./check_errors.sh [log_file]
#
# Exit codes:
#   0 - No errors found
#   1 - Errors found (alert condition)
#   2 - Script error (file not found, etc.)
#
# =============================================================================

# 设置默认日志文件
LOG_FILE="${1:-/var/log/app.log}"

# 检查日志文件是否存在
if [[ ! -f "$LOG_FILE" ]]; then
    echo "Error: Log file not found: $LOG_FILE" >&2
    exit 2
fi

# 使用 -q (quiet) 选项只检查是否存在错误
# grep -q 不输出任何内容，只设置退出码
if grep -q 'ERROR' "$LOG_FILE"; then
    # 统计错误数量
    ERROR_COUNT=$(grep -c 'ERROR' "$LOG_FILE")

    echo "====================================="
    echo "ALERT: Errors detected in log file"
    echo "====================================="
    echo "File: $LOG_FILE"
    echo "Error count: $ERROR_COUNT"
    echo ""

    # 显示最近的错误（最后 5 条）
    echo "Recent errors (last 5):"
    echo "-------------------------------------"
    grep -n 'ERROR' "$LOG_FILE" | tail -5
    echo ""

    # 按错误类型分组统计
    echo "Error breakdown:"
    echo "-------------------------------------"
    grep 'ERROR' "$LOG_FILE" | \
        awk '{print $4}' | \
        sort | \
        uniq -c | \
        sort -rn | \
        head -10

    exit 1  # 返回 1 表示发现错误
else
    echo "OK: No errors found in $LOG_FILE"
    exit 0  # 返回 0 表示正常
fi
