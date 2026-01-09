#!/bin/bash
# ============================================================
# io-analysis.sh - I/O 性能分析脚本
# ============================================================
#
# 用法: ./io-analysis.sh [采集秒数]
#
# 功能:
#   1. 使用 USE Method 系统分析 Disk I/O
#   2. 输出详细的 I/O 指标和解读
#   3. 生成 I/O 分析报告
#
# 依赖:
#   - iostat (sysstat 包)
#   - iotop (可选，需要 root)
#   - pidstat (sysstat 包)
#
# ============================================================

DURATION=${1:-30}
REPORT="io_report_$(date +%Y%m%d_%H%M%S).txt"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 函数：打印带颜色的状态
print_status() {
    local value=$1
    local threshold_warn=$2
    local threshold_crit=$3
    local metric=$4

    if (( $(echo "$value > $threshold_crit" | bc -l) )); then
        echo -e "${RED}$metric = $value (CRITICAL)${NC}"
    elif (( $(echo "$value > $threshold_warn" | bc -l) )); then
        echo -e "${YELLOW}$metric = $value (WARNING)${NC}"
    else
        echo -e "${GREEN}$metric = $value (OK)${NC}"
    fi
}

echo "============================================" | tee $REPORT
echo "  I/O 性能分析报告（USE Method）" | tee -a $REPORT
echo "  采集时间: $(date)" | tee -a $REPORT
echo "  采集时长: $DURATION 秒" | tee -a $REPORT
echo "  主机名: $(hostname)" | tee -a $REPORT
echo "============================================" | tee -a $REPORT
echo "" | tee -a $REPORT

# ============================================
# 系统概览
# ============================================
echo "【系统概览】" | tee -a $REPORT
echo "内核版本: $(uname -r)" | tee -a $REPORT
echo "" | tee -a $REPORT

# 列出块设备
echo "块设备列表:" | tee -a $REPORT
lsblk -d -o NAME,SIZE,TYPE,ROTA,SCHED 2>/dev/null | tee -a $REPORT
echo "" | tee -a $REPORT

# ============================================
# PSI I/O 压力（首先检查）
# ============================================
echo "============================================" | tee -a $REPORT
echo "  PSI I/O 压力检测" | tee -a $REPORT
echo "============================================" | tee -a $REPORT
echo "" | tee -a $REPORT

if [ -f /proc/pressure/io ]; then
    PSI_IO=$(cat /proc/pressure/io)
    echo "$PSI_IO" | tee -a $REPORT

    # 解析 PSI 值
    SOME_AVG10=$(echo "$PSI_IO" | grep "some" | awk -F'=' '{print $2}' | awk '{print $1}')
    FULL_AVG10=$(echo "$PSI_IO" | grep "full" | awk -F'=' '{print $2}' | awk '{print $1}')

    echo "" | tee -a $REPORT
    echo "解读:" | tee -a $REPORT

    if (( $(echo "$SOME_AVG10 > 20" | bc -l) )); then
        echo -e "${RED}  ⚠️  I/O 压力严重！some avg10 = $SOME_AVG10%${NC}" | tee -a $REPORT
    elif (( $(echo "$SOME_AVG10 > 5" | bc -l) )); then
        echo -e "${YELLOW}  ⚡ I/O 有一定压力，some avg10 = $SOME_AVG10%${NC}" | tee -a $REPORT
    else
        echo -e "${GREEN}  ✅ I/O 压力正常，some avg10 = $SOME_AVG10%${NC}" | tee -a $REPORT
    fi
else
    echo "PSI 不可用（需要 Linux 4.20+）" | tee -a $REPORT
fi
echo "" | tee -a $REPORT

# ============================================
# USE Method - Utilization
# ============================================
echo "============================================" | tee -a $REPORT
echo "  U - Utilization（利用率）" | tee -a $REPORT
echo "============================================" | tee -a $REPORT
echo "" | tee -a $REPORT

echo "iostat 采样 (5 秒):" | tee -a $REPORT
iostat -xz 1 5 2>/dev/null | grep -E "Device|sd|nvme|vd|xvd|dm-" | tee -a $REPORT

echo "" | tee -a $REPORT
echo "各设备 %util 概览:" | tee -a $REPORT
iostat -xz 1 3 2>/dev/null | awk '/sd|nvme|vd|xvd|dm-/ {
    util=$NF
    if (util > 80) status="[HIGH]"
    else if (util > 50) status="[MODERATE]"
    else status="[OK]"
    print "  " $1 ": %util = " util "% " status
}' | tail -10 | tee -a $REPORT

echo "" | tee -a $REPORT

# ============================================
# USE Method - Saturation
# ============================================
echo "============================================" | tee -a $REPORT
echo "  S - Saturation（饱和度）" | tee -a $REPORT
echo "============================================" | tee -a $REPORT
echo "" | tee -a $REPORT

echo "I/O 队列深度 (aqu-sz) 和延迟 (await):" | tee -a $REPORT
iostat -xz 1 3 2>/dev/null | awk '/sd|nvme|vd|xvd|dm-/ {
    device=$1
    # 列位置可能因版本不同而变化，尝试常见格式
    # 通常: r/s w/s rkB/s wkB/s ... await aqu-sz %util
    # 获取 await 和 aqu-sz
    await=$(NF-2)
    aqu=$(NF-4)
    print "  " device ":"
    print "    aqu-sz = " aqu " (队列深度，> 4 需关注)"
    print "    await = " await " ms (延迟，HDD > 20ms / SSD > 5ms 需关注)"
}' | tail -15 | tee -a $REPORT

echo "" | tee -a $REPORT
echo "vmstat I/O 指标 (bi/bo = blocks in/out per second):" | tee -a $REPORT
vmstat 1 3 | tee -a $REPORT

echo "" | tee -a $REPORT

# ============================================
# USE Method - Errors
# ============================================
echo "============================================" | tee -a $REPORT
echo "  E - Errors（错误）" | tee -a $REPORT
echo "============================================" | tee -a $REPORT
echo "" | tee -a $REPORT

echo "检查 dmesg 中的 I/O 错误:" | tee -a $REPORT
IO_ERRORS=$(dmesg 2>/dev/null | grep -ci "I/O error\|medium error\|disk error\|blk_update_request")
echo "  I/O 错误数: $IO_ERRORS" | tee -a $REPORT

if [ "$IO_ERRORS" -gt 0 ]; then
    echo "" | tee -a $REPORT
    echo "最近的 I/O 错误:" | tee -a $REPORT
    dmesg 2>/dev/null | grep -i "I/O error\|medium error\|disk error" | tail -5 | tee -a $REPORT
fi

echo "" | tee -a $REPORT

# ============================================
# I/O 调度器
# ============================================
echo "============================================" | tee -a $REPORT
echo "  I/O 调度器状态" | tee -a $REPORT
echo "============================================" | tee -a $REPORT
echo "" | tee -a $REPORT

for sched in /sys/block/*/queue/scheduler; do
    if [ -f "$sched" ]; then
        device=$(echo $sched | cut -d'/' -f4)
        current=$(cat "$sched" | tr -d '[]' | awk '{for(i=1;i<=NF;i++) if($i ~ /^\[/) print $i}')
        echo "  $device: $(cat $sched)" | tee -a $REPORT
    fi
done

echo "" | tee -a $REPORT

# ============================================
# 进程级 I/O（如果有权限）
# ============================================
echo "============================================" | tee -a $REPORT
echo "  进程级 I/O 分析" | tee -a $REPORT
echo "============================================" | tee -a $REPORT
echo "" | tee -a $REPORT

if command -v pidstat &> /dev/null; then
    echo "pidstat -d 输出 (Top I/O 消耗进程):" | tee -a $REPORT
    pidstat -d 1 3 2>/dev/null | awk '
        NR>3 && $4 != "0.00" && $5 != "0.00" {
            print "  PID " $4 ": read=" $5 " KB/s, write=" $6 " KB/s, iodelay=" $8 " - " $NF
        }
    ' | head -10 | tee -a $REPORT
else
    echo "pidstat 不可用，请安装 sysstat 包" | tee -a $REPORT
fi

echo "" | tee -a $REPORT

# ============================================
# iotop 提示
# ============================================
if ! command -v iotop &> /dev/null; then
    echo "提示: 安装 iotop 可获得更详细的进程 I/O 信息" | tee -a $REPORT
    echo "  Ubuntu/Debian: sudo apt install iotop" | tee -a $REPORT
    echo "  RHEL/CentOS: sudo yum install iotop" | tee -a $REPORT
elif [ "$EUID" -ne 0 ]; then
    echo "提示: 以 root 运行可使用 iotop 获取更详细信息" | tee -a $REPORT
fi

echo "" | tee -a $REPORT

# ============================================
# io_uring 检测提示
# ============================================
echo "============================================" | tee -a $REPORT
echo "  io_uring 检测提示" | tee -a $REPORT
echo "============================================" | tee -a $REPORT
echo "" | tee -a $REPORT

KERNEL_VERSION=$(uname -r | cut -d'.' -f1,2)
KERNEL_MAJOR=$(echo $KERNEL_VERSION | cut -d'.' -f1)
KERNEL_MINOR=$(echo $KERNEL_VERSION | cut -d'.' -f2)

if [ "$KERNEL_MAJOR" -ge 5 ] && [ "$KERNEL_MINOR" -ge 1 ]; then
    echo "内核 $KERNEL_VERSION 支持 io_uring" | tee -a $REPORT
    echo "" | tee -a $REPORT
    echo "检测应用是否使用 io_uring:" | tee -a $REPORT
    echo "  strace -e io_uring_enter,io_uring_setup -p <PID>" | tee -a $REPORT
    echo "  perf trace -e 'io_uring:*' -p <PID>" | tee -a $REPORT
else
    echo "内核 $KERNEL_VERSION 不支持 io_uring（需要 5.1+）" | tee -a $REPORT
fi

echo "" | tee -a $REPORT

# ============================================
# 总结
# ============================================
echo "============================================" | tee -a $REPORT
echo "  分析完成" | tee -a $REPORT
echo "============================================" | tee -a $REPORT
echo "" | tee -a $REPORT
echo "报告已保存: $REPORT" | tee -a $REPORT
echo "" | tee -a $REPORT

echo "快速诊断命令:" | tee -a $REPORT
echo "  iostat -xz 1        # 实时 I/O 统计" | tee -a $REPORT
echo "  sudo iotop -o       # 进程 I/O（需要 root）" | tee -a $REPORT
echo "  pidstat -d 1        # 进程 I/O 统计" | tee -a $REPORT
echo "  cat /proc/pressure/io  # PSI I/O 压力" | tee -a $REPORT
