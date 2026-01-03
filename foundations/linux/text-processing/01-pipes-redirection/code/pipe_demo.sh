#!/bin/bash
# =============================================================================
# pipe_demo.sh - 管道操作演示脚本
# =============================================================================
#
# 用途：
#   演示管道如何连接命令，以及实际的日志分析场景
#
# 运行方式：
#   ./pipe_demo.sh
#
# =============================================================================

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ACCESS_LOG="$SCRIPT_DIR/access.log"

echo "=== 管道演示 ==="
echo ""

# -----------------------------------------------------------------------------
# 演示 1: 基本管道
# -----------------------------------------------------------------------------
echo "--- 演示 1: 基本管道 ---"

echo "统计当前目录文件数量:"
ls -1 | wc -l

echo ""
echo "查看系统进程中的 bash:"
ps aux | grep bash | head -5
echo ""

# -----------------------------------------------------------------------------
# 演示 2: 多级管道
# -----------------------------------------------------------------------------
echo "--- 演示 2: 多级管道 (日志分析) ---"

if [ -f "$ACCESS_LOG" ]; then
    echo "使用示例日志: $ACCESS_LOG"
    echo ""

    echo "1) 提取所有 IP 地址:"
    cat "$ACCESS_LOG" | awk '{print $1}' | head -5
    echo "..."
    echo ""

    echo "2) 统计每个 IP 的访问次数 (按频率排序):"
    cat "$ACCESS_LOG" | awk '{print $1}' | sort | uniq -c | sort -rn
    echo ""

    echo "3) 统计 HTTP 状态码分布:"
    cat "$ACCESS_LOG" | awk '{print $9}' | sort | uniq -c | sort -rn
    echo ""

    echo "4) 找出所有 5xx 错误:"
    cat "$ACCESS_LOG" | awk '$9 >= 500 && $9 < 600 {print $0}'
    echo ""
else
    echo "警告: 找不到示例日志 $ACCESS_LOG"
    echo "请确保 access.log 存在于 code/ 目录中"
fi

# -----------------------------------------------------------------------------
# 演示 3: 管道与 stderr
# -----------------------------------------------------------------------------
echo "--- 演示 3: 管道与 stderr ---"

echo "默认情况下，管道只传递 stdout:"
echo "(stderr 会直接显示在终端)"
echo ""

echo "命令: ls /home /nonexistent | grep home"
ls /home /nonexistent | grep home 2>/dev/null
echo ""

echo "使用 2>&1 合并后再管道:"
echo "命令: ls /home /nonexistent 2>&1 | grep -E '(home|No such)'"
ls /home /nonexistent 2>&1 | grep -E "(home|No such)"
echo ""

# -----------------------------------------------------------------------------
# 演示 4: tee 分流
# -----------------------------------------------------------------------------
echo "--- 演示 4: tee 分流 ---"

TEMP_FILE="/tmp/tee_demo_$$.txt"

echo "使用 tee 同时输出到屏幕和文件:"
echo "命令: echo 'Hello, tee!' | tee $TEMP_FILE"
echo "Hello, tee!" | tee "$TEMP_FILE"

echo ""
echo "文件内容验证:"
cat "$TEMP_FILE"

# 清理
rm -f "$TEMP_FILE"
echo ""

# -----------------------------------------------------------------------------
# 演示 5: 实战场景
# -----------------------------------------------------------------------------
echo "--- 演示 5: 实战场景 (运维监控) ---"

echo "场景: 实时监控日志中的错误"
echo "命令: tail -f /var/log/syslog | grep -i error | tee errors.log"
echo "(这是一个持续运行的命令，按 Ctrl+C 停止)"
echo ""

echo "场景: 统计某时间段的访问量"
if [ -f "$ACCESS_LOG" ]; then
    echo "10:00:00 到 10:00:10 之间的请求数:"
    cat "$ACCESS_LOG" | grep "10:00:0" | wc -l
fi
echo ""

echo "=== 演示结束 ==="
