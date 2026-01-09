#!/bin/bash
# ==============================================================================
# network-baseline.sh - 网络性能基线采集脚本
# ==============================================================================
#
# 用途：
#   - タイムセール（限时特卖）前的网络性能确认
#   - 建立网络基线用于后续对比
#   - 生成エビデンス（证据）报告
#
# 前置条件：
#   - 目标服务器运行 iperf3 -s
#   - 本机安装 iperf3, jq
#
# 用法：
#   ./network-baseline.sh <iperf3服务器IP> [测试时长秒数]
#
# 示例：
#   ./network-baseline.sh 10.0.1.100
#   ./network-baseline.sh 10.0.1.100 60
#
# ==============================================================================

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 配置
IPERF_SERVER="${1:-}"
DURATION="${2:-30}"
OUTPUT_DIR="network_baseline_$(date +%Y%m%d_%H%M%S)"

# 参数检查
if [ -z "$IPERF_SERVER" ]; then
    echo -e "${RED}错误: 未指定 iperf3 服务器地址${NC}"
    echo ""
    echo "用法: $0 <iperf3服务器IP> [测试时长秒数]"
    echo "示例: $0 10.0.1.100"
    echo "      $0 10.0.1.100 60"
    echo ""
    echo "注意: 目标服务器需要运行 'iperf3 -s'"
    exit 1
fi

# 检查依赖
check_deps() {
    local missing=0
    for cmd in iperf3 jq ping; do
        if ! command -v "$cmd" &> /dev/null; then
            echo -e "${RED}错误: 缺少命令 '$cmd'${NC}"
            missing=1
        fi
    done
    if [ $missing -eq 1 ]; then
        echo ""
        echo "请安装缺少的工具："
        echo "  Ubuntu/Debian: sudo apt install iperf3 jq"
        echo "  RHEL/AlmaLinux: sudo dnf install iperf3 jq"
        exit 1
    fi
}

check_deps

# 创建输出目录
mkdir -p "$OUTPUT_DIR"
cd "$OUTPUT_DIR"

echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}  网络性能基线采集${NC}"
echo -e "${BLUE}============================================${NC}"
echo -e "  目标服务器: ${GREEN}$IPERF_SERVER${NC}"
echo -e "  测试时长:   ${GREEN}${DURATION} 秒${NC}"
echo -e "  采集时间:   $(date '+%Y-%m-%d %H:%M:%S')"
echo -e "${BLUE}============================================${NC}"
echo ""

# 系统信息
echo -e "${YELLOW}[系统信息] 收集中...${NC}"
{
    echo "=== 系统信息 ==="
    echo "主机名: $(hostname)"
    echo "内核: $(uname -r)"
    echo ""
    echo "=== 网络接口 ==="
    ip -br link
    echo ""
    echo "=== IP 地址 ==="
    ip -br addr
    echo ""
    echo "=== 默认网关 ==="
    ip route | grep default
    echo ""
    echo "=== DNS 配置 ==="
    cat /etc/resolv.conf 2>/dev/null | grep -v "^#" | head -5
} > system_info.txt

# ==============================================================================
# Step 1: 基础连通性测试
# ==============================================================================
echo ""
echo -e "${YELLOW}[Step 1/6] 基础连通性测试...${NC}"
{
    echo "=== Ping 测试 ==="
    echo "目标: $IPERF_SERVER"
    echo "发送: 20 个 ICMP 包"
    echo ""
    ping -c 20 "$IPERF_SERVER" 2>&1 || echo "Ping 失败"
} > ping_test.txt

# 提取 ping 统计
if grep -q "rtt" ping_test.txt; then
    PING_RTT=$(grep "rtt" ping_test.txt | awk -F'/' '{print $5}')
    PING_LOSS=$(grep "packet loss" ping_test.txt | awk '{print $6}')
    echo -e "  RTT (avg):  ${GREEN}${PING_RTT} ms${NC}"
    echo -e "  丢包率:     ${GREEN}${PING_LOSS}${NC}"
else
    PING_RTT="N/A"
    PING_LOSS="N/A"
    echo -e "  ${RED}Ping 测试失败${NC}"
fi

# ==============================================================================
# Step 2: TCP 吞吐量测试
# ==============================================================================
echo ""
echo -e "${YELLOW}[Step 2/6] TCP 吞吐量测试 (${DURATION}秒)...${NC}"

TCP_BW="N/A"
TCP_RETRANS="N/A"

if iperf3 -c "$IPERF_SERVER" -t "$DURATION" -J > tcp_test.json 2>&1; then
    TCP_BW_RAW=$(jq -r '.end.sum_sent.bits_per_second // 0' tcp_test.json)
    TCP_BW=$(echo "$TCP_BW_RAW" | awk '{printf "%.2f Mbps", $1/1000000}')
    TCP_RETRANS=$(jq -r '.end.sum_sent.retransmits // 0' tcp_test.json)

    echo -e "  吞吐量:     ${GREEN}$TCP_BW${NC}"
    if [ "$TCP_RETRANS" -gt 0 ]; then
        echo -e "  重传次数:   ${YELLOW}$TCP_RETRANS${NC} (需关注)"
    else
        echo -e "  重传次数:   ${GREEN}$TCP_RETRANS${NC}"
    fi
else
    echo -e "  ${RED}TCP 测试失败${NC}"
    echo -e "  请确认 iperf3 服务端运行中: ${YELLOW}iperf3 -s${NC}"
fi

# ==============================================================================
# Step 3: UDP 测试（丢包率和抖动）
# ==============================================================================
echo ""
echo -e "${YELLOW}[Step 3/6] UDP 测试 (100 Mbps, ${DURATION}秒)...${NC}"

UDP_LOSS="N/A"
UDP_JITTER="N/A"

if iperf3 -c "$IPERF_SERVER" -u -b 100M -t "$DURATION" -J > udp_test.json 2>&1; then
    UDP_LOSS=$(jq -r '.end.sum.lost_percent // 0' udp_test.json)
    UDP_JITTER=$(jq -r '.end.sum.jitter_ms // 0' udp_test.json)

    if [ "$(echo "$UDP_LOSS > 1" | bc -l 2>/dev/null)" = "1" ]; then
        echo -e "  丢包率:     ${YELLOW}${UDP_LOSS}%${NC} (> 1%, 需关注)"
    else
        echo -e "  丢包率:     ${GREEN}${UDP_LOSS}%${NC}"
    fi

    if [ "$(echo "$UDP_JITTER > 30" | bc -l 2>/dev/null)" = "1" ]; then
        echo -e "  抖动:       ${YELLOW}${UDP_JITTER} ms${NC} (> 30ms, 影响实时应用)"
    else
        echo -e "  抖动:       ${GREEN}${UDP_JITTER} ms${NC}"
    fi
else
    echo -e "  ${RED}UDP 测试失败${NC}"
fi

# ==============================================================================
# Step 4: 双向吞吐量测试
# ==============================================================================
echo ""
echo -e "${YELLOW}[Step 4/6] 双向吞吐量测试 (10秒)...${NC}"

if iperf3 -c "$IPERF_SERVER" --bidir -t 10 -J > bidir_test.json 2>&1; then
    BIDIR_UPLOAD=$(jq -r '.end.sum_sent.bits_per_second // 0' bidir_test.json | awk '{printf "%.2f Mbps", $1/1000000}')
    BIDIR_DOWNLOAD=$(jq -r '.end.sum_received.bits_per_second // 0' bidir_test.json | awk '{printf "%.2f Mbps", $1/1000000}')
    echo -e "  上行:       ${GREEN}$BIDIR_UPLOAD${NC}"
    echo -e "  下行:       ${GREEN}$BIDIR_DOWNLOAD${NC}"
else
    echo -e "  ${RED}双向测试失败${NC}"
fi

# ==============================================================================
# Step 5: Socket 状态快照
# ==============================================================================
echo ""
echo -e "${YELLOW}[Step 5/6] Socket 状态快照...${NC}"
{
    echo "=== ss -s 统计 ==="
    ss -s
    echo ""
    echo "=== 连接状态分布 ==="
    ss -tan | awk '{print $1}' | sort | uniq -c | sort -rn
    echo ""
    echo "=== 非零队列连接 ==="
    echo "(Recv-Q > 0 或 Send-Q > 0 的连接)"
    ss -ntp | awk 'NR==1 || $2 > 0 || $3 > 0'
} > socket_stats.txt

SOCKET_TOTAL=$(ss -s | grep "TCP:" | awk '{print $2}')
echo -e "  TCP 连接总数: ${GREEN}$SOCKET_TOTAL${NC}"

# ==============================================================================
# Step 6: 接口统计
# ==============================================================================
echo ""
echo -e "${YELLOW}[Step 6/6] 接口统计...${NC}"
{
    echo "=== ip -s link ==="
    ip -s link show
    echo ""
    # 如果有 ethtool，收集更详细信息
    if command -v ethtool &> /dev/null; then
        for iface in $(ip -br link | awk '$2=="UP" {print $1}' | grep -v "^lo$"); do
            echo "=== ethtool $iface ==="
            sudo ethtool "$iface" 2>/dev/null | grep -E "Speed|Duplex|Link" || true
            echo ""
        done
    fi
} > interface_stats.txt

# 检查是否有丢包/错误
DROPPED=$(ip -s link show | grep -A1 "RX:" | tail -1 | awk '{print $4}')
ERRORS=$(ip -s link show | grep -A1 "RX:" | tail -1 | awk '{print $3}')

if [ "$DROPPED" -gt 0 ] || [ "$ERRORS" -gt 0 ]; then
    echo -e "  ${YELLOW}检测到接口丢包/错误，详见 interface_stats.txt${NC}"
else
    echo -e "  接口状态:   ${GREEN}正常${NC}"
fi

# ==============================================================================
# 生成摘要报告
# ==============================================================================
echo ""
echo -e "${YELLOW}[生成摘要报告...]${NC}"

{
    echo "============================================"
    echo "  网络性能基线报告"
    echo "============================================"
    echo ""
    echo "采集时间:   $(date '+%Y-%m-%d %H:%M:%S')"
    echo "目标服务器: $IPERF_SERVER"
    echo "测试时长:   ${DURATION} 秒"
    echo "采集主机:   $(hostname)"
    echo ""
    echo "============================================"
    echo "  测试结果摘要"
    echo "============================================"
    echo ""
    echo "## 连通性 (Ping)"
    echo "  - RTT (avg):  $PING_RTT ms"
    echo "  - 丢包率:     $PING_LOSS"
    echo ""
    echo "## TCP 吞吐量"
    echo "  - 带宽:       $TCP_BW"
    echo "  - 重传次数:   $TCP_RETRANS"
    echo ""
    echo "## UDP 性能"
    echo "  - 丢包率:     ${UDP_LOSS}%"
    echo "  - 抖动:       ${UDP_JITTER} ms"
    echo ""
    echo "============================================"
    echo "  性能评估"
    echo "============================================"
    echo ""

    WARNINGS=0

    if [ "$TCP_RETRANS" != "N/A" ] && [ "$TCP_RETRANS" -gt 0 ]; then
        echo "- [WARNING] TCP 重传 $TCP_RETRANS 次，建议检查网络质量"
        WARNINGS=$((WARNINGS + 1))
    fi

    if [ "$UDP_LOSS" != "N/A" ] && [ "$(echo "$UDP_LOSS > 1" | bc -l 2>/dev/null)" = "1" ]; then
        echo "- [WARNING] UDP 丢包率 ${UDP_LOSS}% > 1%，可能影响实时应用"
        WARNINGS=$((WARNINGS + 1))
    fi

    if [ "$UDP_JITTER" != "N/A" ] && [ "$(echo "$UDP_JITTER > 30" | bc -l 2>/dev/null)" = "1" ]; then
        echo "- [WARNING] UDP 抖动 ${UDP_JITTER} ms > 30ms，可能影响 VoIP/视频"
        WARNINGS=$((WARNINGS + 1))
    fi

    if [ $WARNINGS -eq 0 ]; then
        echo "- [OK] 所有指标正常"
    fi

    echo ""
    echo "============================================"
    echo "  文件清单"
    echo "============================================"
    echo ""
    echo "- system_info.txt     系统信息"
    echo "- ping_test.txt       Ping 测试原始输出"
    echo "- tcp_test.json       TCP 测试详细数据 (JSON)"
    echo "- udp_test.json       UDP 测试详细数据 (JSON)"
    echo "- bidir_test.json     双向测试详细数据 (JSON)"
    echo "- socket_stats.txt    Socket 状态快照"
    echo "- interface_stats.txt 接口统计"
    echo "- summary.txt         本摘要报告"
    echo ""
    echo "============================================"
} > summary.txt

# 显示摘要
echo ""
cat summary.txt

echo ""
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}  基线采集完成！${NC}"
echo -e "${GREEN}============================================${NC}"
echo ""
echo -e "输出目录: ${BLUE}$(pwd)${NC}"
echo ""
echo "保存此目录用于后续对比分析。"
echo "建议定期采集基线，特别是在:"
echo "  - 大规模活动前 (タイムセール等)"
echo "  - 网络变更前后"
echo "  - 定期巡检 (月次など)"
