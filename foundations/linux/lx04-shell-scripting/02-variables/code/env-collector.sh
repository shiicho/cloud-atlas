#!/bin/bash
#
# env-collector.sh - 环境信息收集器 (Mini Project)
#
# 用途：收集系统和环境信息，生成格式化报告
# 用法：./env-collector.sh [options]
#
# 演示内容：
#   - 变量赋值和引用
#   - 环境变量读取
#   - 命令替换
#   - 特殊变量使用
#   - 只读变量
#

# =============================================================================
# 只读配置（防止意外修改）
# =============================================================================
readonly SCRIPT_NAME=$(basename "$0")
readonly SCRIPT_DIR=$(dirname "$0")
readonly REPORT_DIR="/tmp"
readonly REPORT_FILE="${REPORT_DIR}/env_report_$(date +%Y%m%d_%H%M%S).txt"

# =============================================================================
# 收集系统信息
# =============================================================================

# 基本系统信息
HOSTNAME=$(hostname 2>/dev/null || echo "unknown")
KERNEL=$(uname -r 2>/dev/null || echo "unknown")
ARCH=$(uname -m 2>/dev/null || echo "unknown")

# 操作系统信息
if [ -f /etc/os-release ]; then
    OS_NAME=$(grep "^PRETTY_NAME" /etc/os-release 2>/dev/null | cut -d'"' -f2)
else
    OS_NAME=$(uname -s)
fi

# 硬件信息
CPU_MODEL=$(grep "model name" /proc/cpuinfo 2>/dev/null | head -1 | cut -d':' -f2 | xargs)
CPU_CORES=$(nproc 2>/dev/null || grep -c "processor" /proc/cpuinfo 2>/dev/null || echo "unknown")
MEM_TOTAL=$(free -h 2>/dev/null | awk '/Mem:/{print $2}' || echo "unknown")
MEM_USED=$(free -h 2>/dev/null | awk '/Mem:/{print $3}' || echo "unknown")

# 磁盘信息
DISK_USAGE=$(df -h / 2>/dev/null | awk 'NR==2{print $5}' || echo "unknown")
DISK_FREE=$(df -h / 2>/dev/null | awk 'NR==2{print $4}' || echo "unknown")

# 运行时间
UPTIME=$(uptime -p 2>/dev/null || uptime | sed 's/.*up /up /' | cut -d',' -f1)

# 网络信息
IP_ADDR=$(hostname -I 2>/dev/null | awk '{print $1}' || echo "unknown")

# =============================================================================
# 生成报告
# =============================================================================

generate_report() {
    cat << EOF
================================================================================
                         环境信息报告
================================================================================
生成时间: $(date '+%Y-%m-%d %H:%M:%S')
报告文件: $REPORT_FILE
================================================================================

--- 脚本信息 ---
脚本名称: $SCRIPT_NAME
脚本目录: $SCRIPT_DIR
脚本 PID: $$
参数个数: $#
传入参数: $@

--- 用户信息 ---
当前用户: $USER
用户 ID:  $(id -u)
组 ID:    $(id -g)
家目录:   $HOME
当前目录: $PWD

--- 系统信息 ---
主机名:   $HOSTNAME
操作系统: ${OS_NAME:-Unknown}
内核版本: $KERNEL
系统架构: $ARCH
运行时间: $UPTIME

--- 硬件信息 ---
CPU 型号: ${CPU_MODEL:-Unknown}
CPU 核心: $CPU_CORES
总内存:   $MEM_TOTAL
已用内存: $MEM_USED

--- 存储信息 ---
根分区使用率: $DISK_USAGE
根分区剩余:   $DISK_FREE

--- 网络信息 ---
IP 地址: $IP_ADDR

--- Shell 环境 ---
默认 Shell:   $SHELL
Bash 版本:    ${BASH_VERSION:-unknown}
TERM 类型:    ${TERM:-unknown}
语言设置:     ${LANG:-not set}
PATH 目录数:  $(echo "$PATH" | tr ':' '\n' | wc -l)

--- PATH 列表 ---
$(echo "$PATH" | tr ':' '\n' | nl)

================================================================================
                         报告结束
================================================================================
EOF
}

# =============================================================================
# 主程序
# =============================================================================

echo "正在收集环境信息..."
echo ""

# 生成报告并保存到文件
generate_report | tee "$REPORT_FILE"

# 显示状态
echo ""
echo "==============================================="
echo "报告已保存到: $REPORT_FILE"
echo "最后命令退出状态: $?"
echo "==============================================="
