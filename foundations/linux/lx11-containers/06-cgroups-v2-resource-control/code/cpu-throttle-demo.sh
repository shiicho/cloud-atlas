#!/bin/bash
# =============================================================================
# cpu-throttle-demo.sh - cgroups v2 CPU 限制演示
# =============================================================================
#
# 演示 cpu.max 限制 CPU 使用时间
# 用于 LX11-CONTAINERS Lesson 06
#
# 用法：
#   sudo ./cpu-throttle-demo.sh
#
# 演示内容：
#   1. 无限制时 CPU 密集任务占用接近 100%
#   2. 设置 cpu.max 后限制为 50%
#   3. 查看 cpu.stat 中的 throttle 统计
#
# 前置要求：
#   - stress 工具已安装
#   - cgroups v2 已启用
#   - root 权限
#
# =============================================================================

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# cgroup 路径
CGROUP_BASE="/sys/fs/cgroup"
DEMO_CPU="${CGROUP_BASE}/demo-cpu-throttle"

# 打印分隔线
print_section() {
    echo ""
    echo -e "${BLUE}=================================================================${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}=================================================================${NC}"
    echo ""
}

# 打印信息
info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

# 打印警告
warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

# 打印错误
error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 打印命令
cmd() {
    echo -e "${CYAN}[CMD]${NC} $1"
}

# 检查 root 权限
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "请使用 sudo 运行此脚本"
        exit 1
    fi
}

# 检查 cgroups v2
check_cgroup_v2() {
    if ! mount | grep -q "cgroup2 on /sys/fs/cgroup"; then
        error "此系统未启用 cgroups v2"
        error "请使用 Ubuntu 22.04+, RHEL 9+, 或配置 cgroup v2"
        exit 1
    fi
    info "cgroups v2 已启用"
}

# 检查 stress 工具
check_stress() {
    if ! command -v stress &> /dev/null; then
        error "stress 工具未安装"
        echo ""
        echo "安装方法："
        echo "  Ubuntu/Debian: sudo apt-get install -y stress"
        echo "  RHEL/CentOS:   sudo dnf install -y stress"
        exit 1
    fi
    info "stress 工具可用"
}

# 清理 cgroup（如果存在）
cleanup_cgroup() {
    local cgroup_path="$1"
    if [[ -d "$cgroup_path" ]]; then
        # 先杀死 cgroup 中的进程
        if [[ -f "${cgroup_path}/cgroup.procs" ]]; then
            for pid in $(cat "${cgroup_path}/cgroup.procs" 2>/dev/null); do
                kill -9 "$pid" 2>/dev/null || true
            done
        fi
        sleep 1
        rmdir "$cgroup_path" 2>/dev/null || true
    fi
}

# 获取进程 CPU 使用率
get_cpu_usage() {
    local pid=$1
    if ps -p "$pid" > /dev/null 2>&1; then
        ps -p "$pid" -o %cpu= 2>/dev/null | tr -d ' ' || echo "N/A"
    else
        echo "N/A"
    fi
}

# 演示 1：无限制的 CPU 使用
demo_no_limit() {
    print_section "演示 1：无限制的 CPU 使用"

    info "启动 CPU 密集任务（无限制）..."
    info "观察 CPU 使用率接近 100%"
    echo ""

    # 启动 stress 在后台
    cmd "stress --cpu 1 --timeout 10s &"
    stress --cpu 1 --timeout 10s &
    STRESS_PID=$!

    sleep 2  # 等待 stress 稳定

    info "stress 进程 PID: $STRESS_PID"
    echo ""

    # 多次采样 CPU 使用率
    info "采样 CPU 使用率（每秒一次，共 5 次）："
    for i in {1..5}; do
        CPU_USAGE=$(get_cpu_usage $STRESS_PID)
        echo "  采样 $i: ${CPU_USAGE}%"
        sleep 1
    done

    # 等待 stress 完成或杀死
    kill $STRESS_PID 2>/dev/null || true
    wait $STRESS_PID 2>/dev/null || true

    echo ""
    info "结论：无限制时，CPU 密集任务占用接近 100% CPU"
}

# 演示 2：50% CPU 限制
demo_50_percent() {
    print_section "演示 2：50% CPU 限制"

    info "cpu.max 格式说明："
    info "  'quota period'"
    info "  quota: 每个周期允许使用的 CPU 时间（微秒）"
    info "  period: 周期长度（微秒，通常 100000 = 100ms）"
    echo ""
    info "示例："
    info "  '50000 100000' = 每 100ms 只能使用 50ms = 50% CPU"
    info "  '100000 100000' = 100% (一个核)"
    info "  '200000 100000' = 200% (两个核)"
    echo ""

    # 创建 cgroup
    cleanup_cgroup "$DEMO_CPU"
    cmd "mkdir $DEMO_CPU"
    mkdir -p "$DEMO_CPU"

    # 设置 50% CPU 限制
    cmd "echo '50000 100000' > $DEMO_CPU/cpu.max"
    echo "50000 100000" > "$DEMO_CPU/cpu.max"

    info "配置完成："
    echo "  cpu.max = $(cat $DEMO_CPU/cpu.max)"
    echo ""

    info "启动 CPU 密集任务（50% 限制）..."
    echo ""

    # 在 cgroup 中运行 stress
    bash -c "echo \$\$ > $DEMO_CPU/cgroup.procs && stress --cpu 1 --timeout 15s" &
    STRESS_PID=$!

    sleep 2  # 等待 stress 稳定

    # 找到实际的 stress worker 进程
    WORKER_PID=$(pgrep -P $STRESS_PID stress 2>/dev/null | head -1)
    if [[ -z "$WORKER_PID" ]]; then
        WORKER_PID=$STRESS_PID
    fi

    info "stress 父进程 PID: $STRESS_PID"
    info "stress worker PID: $WORKER_PID"
    echo ""

    # 多次采样 CPU 使用率
    info "采样 CPU 使用率（每秒一次，共 5 次）："
    for i in {1..5}; do
        CPU_USAGE=$(get_cpu_usage $WORKER_PID)
        echo "  采样 $i: ${CPU_USAGE}%"
        sleep 1
    done

    echo ""
    info "查看 cpu.stat 统计："
    cmd "cat $DEMO_CPU/cpu.stat"
    cat "$DEMO_CPU/cpu.stat"
    echo ""

    info "关键指标解释："
    echo "  usage_usec    - 总 CPU 使用时间"
    echo "  nr_periods    - 调度周期数"
    echo "  nr_throttled  - 被限制的周期数（> 0 表示限制生效）"
    echo "  throttled_usec - 被限制的总时间"

    # 等待 stress 完成或杀死
    kill $STRESS_PID 2>/dev/null || true
    wait $STRESS_PID 2>/dev/null || true

    echo ""
    info "结论：CPU 使用率被限制在 50% 左右"
    info "nr_throttled > 0 证明 CPU 限制正在生效"

    # 清理
    cleanup_cgroup "$DEMO_CPU"
}

# 演示 3：不同限制级别对比
demo_comparison() {
    print_section "演示 3：不同限制级别对比"

    info "对比不同 CPU 限制的效果"
    echo ""

    declare -A LIMITS=(
        ["25%"]="25000 100000"
        ["50%"]="50000 100000"
        ["75%"]="75000 100000"
    )

    for label in "25%" "50%" "75%"; do
        limit="${LIMITS[$label]}"

        echo "----------------------------------------"
        info "测试 $label 限制 (cpu.max = $limit)"

        # 创建 cgroup
        DEMO_TEMP="${CGROUP_BASE}/demo-cpu-${label//\%/pct}"
        cleanup_cgroup "$DEMO_TEMP"
        mkdir -p "$DEMO_TEMP"

        echo "$limit" > "$DEMO_TEMP/cpu.max"

        # 运行 stress
        bash -c "echo \$\$ > $DEMO_TEMP/cgroup.procs && stress --cpu 1 --timeout 6s" &
        STRESS_PID=$!

        sleep 2

        # 采样
        WORKER_PID=$(pgrep -P $STRESS_PID stress 2>/dev/null | head -1)
        [[ -z "$WORKER_PID" ]] && WORKER_PID=$STRESS_PID

        CPU_USAGE=$(get_cpu_usage $WORKER_PID)
        echo "  CPU 使用率: ${CPU_USAGE}%"

        # 等待完成
        wait $STRESS_PID 2>/dev/null || true

        # 显示 throttle 统计
        NR_THROTTLED=$(grep nr_throttled "$DEMO_TEMP/cpu.stat" | awk '{print $2}')
        echo "  nr_throttled: $NR_THROTTLED"

        # 清理
        cleanup_cgroup "$DEMO_TEMP"
    done

    echo "----------------------------------------"
    echo ""
    info "结论：限制越低，CPU 使用率越低，throttle 次数越多"
}

# 主函数
main() {
    print_section "cgroups v2 CPU 限制演示"

    check_root
    check_cgroup_v2
    check_stress

    echo ""
    info "本脚本将演示 cpu.max 如何限制 CPU 时间"
    info "这是容器 CPU 限制的核心机制"
    echo ""

    # 运行演示
    demo_no_limit
    demo_50_percent
    demo_comparison

    print_section "演示完成"

    info "核心要点："
    echo ""
    echo "  ┌─────────────────────────────────────────────────────────────┐"
    echo "  │                                                             │"
    echo "  │   cpu.max 格式: 'quota period'                              │"
    echo "  │                                                             │"
    echo "  │   常用配置：                                                │"
    echo "  │     '50000 100000'  = 50% CPU (1 核的一半)                  │"
    echo "  │     '100000 100000' = 100% CPU (1 核)                       │"
    echo "  │     '200000 100000' = 200% CPU (2 核)                       │"
    echo "  │     'max 100000'    = 无限制                                │"
    echo "  │                                                             │"
    echo "  │   监控指标：                                                │"
    echo "  │     cpu.stat 中的 nr_throttled                             │"
    echo "  │     值 > 0 表示 CPU 限制正在生效                           │"
    echo "  │                                                             │"
    echo "  │   Docker 对应：                                             │"
    echo "  │     docker run --cpus=0.5 ...                              │"
    echo "  │     等同于 cpu.max = '50000 100000'                        │"
    echo "  │                                                             │"
    echo "  └─────────────────────────────────────────────────────────────┘"
    echo ""
}

# 捕获退出信号，确保清理
trap 'cleanup_cgroup "$DEMO_CPU"; pkill -P $$ stress 2>/dev/null || true' EXIT

main "$@"
