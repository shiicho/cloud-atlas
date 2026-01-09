#!/bin/bash
# =============================================================================
# memory-limit-demo.sh - cgroups v2 内存限制演示
# =============================================================================
#
# 演示 memory.high（软限制）和 memory.max（硬限制）的区别
# 用于 LX11-CONTAINERS Lesson 06
#
# 用法：
#   sudo ./memory-limit-demo.sh
#
# 演示内容：
#   1. memory.high（软限制）- 进程变慢但继续运行
#   2. memory.max（硬限制）- 触发 OOM Kill
#   3. memory.events 事件统计
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
DEMO_HIGH="${CGROUP_BASE}/demo-memory-high"
DEMO_MAX="${CGROUP_BASE}/demo-memory-max"

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

# 清理所有演示 cgroup
cleanup_all() {
    info "清理演示 cgroup..."
    cleanup_cgroup "$DEMO_HIGH"
    cleanup_cgroup "$DEMO_MAX"
}

# 演示 1：memory.high（软限制）
demo_memory_high() {
    print_section "演示 1：memory.high（软限制）"

    info "memory.high 是软限制："
    info "  - 超过此值后，系统积极回收内存"
    info "  - 进程变慢但不会被杀死"
    echo ""

    # 创建 cgroup
    cmd "mkdir $DEMO_HIGH"
    mkdir -p "$DEMO_HIGH"

    # 只设置 memory.high（软限制）
    cmd "echo '50M' > $DEMO_HIGH/memory.high"
    echo "50M" > "$DEMO_HIGH/memory.high"

    info "配置完成："
    echo "  memory.high = $(cat $DEMO_HIGH/memory.high)"
    echo "  memory.max  = $(cat $DEMO_HIGH/memory.max)"
    echo ""

    info "运行 stress 尝试分配 80M 内存（超过 50M 限制）..."
    cmd "stress --vm 1 --vm-bytes 80M --timeout 5s"
    echo ""

    # 在 cgroup 中运行 stress
    # 使用子 shell 避免影响当前 shell
    bash -c "echo \$\$ > $DEMO_HIGH/cgroup.procs && stress --vm 1 --vm-bytes 80M --timeout 5s" || true

    echo ""
    info "查看 memory.events："
    cmd "cat $DEMO_HIGH/memory.events"
    cat "$DEMO_HIGH/memory.events"
    echo ""

    info "结论：进程完成了（没有被杀死），但可能变慢"
    info "'high' 事件计数增加表示触发了内存回收"

    # 清理
    cleanup_cgroup "$DEMO_HIGH"
}

# 演示 2：memory.max（硬限制）
demo_memory_max() {
    print_section "演示 2：memory.max（硬限制）"

    info "memory.max 是硬限制："
    info "  - 超过此值后，触发 OOM Kill"
    info "  - 进程被杀死"
    echo ""

    # 创建 cgroup
    cmd "mkdir $DEMO_MAX"
    mkdir -p "$DEMO_MAX"

    # 设置 memory.max（硬限制）
    cmd "echo '50M' > $DEMO_MAX/memory.max"
    echo "50M" > "$DEMO_MAX/memory.max"

    info "配置完成："
    echo "  memory.high = $(cat $DEMO_MAX/memory.high)"
    echo "  memory.max  = $(cat $DEMO_MAX/memory.max)"
    echo ""

    info "运行 stress 尝试分配 80M 内存（超过 50M 限制）..."
    cmd "stress --vm 1 --vm-bytes 80M --timeout 10s"
    echo ""

    # 在 cgroup 中运行 stress（预期会失败）
    bash -c "echo \$\$ > $DEMO_MAX/cgroup.procs && stress --vm 1 --vm-bytes 80M --timeout 10s" || true

    echo ""
    info "查看 memory.events："
    cmd "cat $DEMO_MAX/memory.events"
    cat "$DEMO_MAX/memory.events"
    echo ""

    info "查看 dmesg 中的 OOM Kill 记录："
    cmd "dmesg | grep -i oom | tail -5"
    dmesg | grep -i oom | tail -5 || echo "(可能需要更高权限查看)"
    echo ""

    info "结论：进程被 OOM Kill（收到 SIGKILL）"
    info "'oom_kill' 事件计数增加"

    # 清理
    cleanup_cgroup "$DEMO_MAX"
}

# 演示 3：memory.high + memory.max 组合
demo_combined() {
    print_section "演示 3：推荐配置 - memory.high + memory.max 组合"

    info "推荐配置模式："
    info "  memory.high = 目标的 80%（软限制，缓冲区）"
    info "  memory.max  = 目标值（硬限制，绝对上限）"
    echo ""

    # 创建 cgroup
    DEMO_COMBINED="${CGROUP_BASE}/demo-combined"
    cleanup_cgroup "$DEMO_COMBINED"
    mkdir -p "$DEMO_COMBINED"

    # 配置：目标 100M，high 设为 80M
    cmd "echo '80M' > memory.high"
    echo "80M" > "$DEMO_COMBINED/memory.high"

    cmd "echo '100M' > memory.max"
    echo "100M" > "$DEMO_COMBINED/memory.max"

    info "配置完成："
    echo "  memory.high = $(cat $DEMO_COMBINED/memory.high)"
    echo "  memory.max  = $(cat $DEMO_COMBINED/memory.max)"
    echo ""

    info "效果说明："
    echo ""
    echo "  使用量 < 80M：正常运行"
    echo "       ↓"
    echo "  80M < 使用量 < 100M：积极回收内存，进程变慢但继续"
    echo "       ↓"
    echo "  使用量 = 100M：OOM Kill"
    echo ""

    info "这种配置给系统一个缓冲区，避免突然死亡"

    # 清理
    cleanup_cgroup "$DEMO_COMBINED"
}

# 主函数
main() {
    print_section "cgroups v2 内存限制演示"

    check_root
    check_cgroup_v2
    check_stress

    echo ""
    info "本脚本将演示 memory.high 和 memory.max 的区别"
    info "这是理解容器资源限制的关键"
    echo ""

    # 清理之前可能残留的 cgroup
    cleanup_all

    # 运行演示
    demo_memory_high
    demo_memory_max
    demo_combined

    print_section "演示完成"

    info "核心要点："
    echo ""
    echo "  ┌─────────────────────────────────────────────────────────────┐"
    echo "  │                                                             │"
    echo "  │   memory.high (软限制)                                      │"
    echo "  │     - 超过后触发内存回收                                    │"
    echo "  │     - 进程变慢但继续运行                                    │"
    echo "  │     - 给系统「喘息」机会                                    │"
    echo "  │                                                             │"
    echo "  │   memory.max (硬限制)                                       │"
    echo "  │     - 超过后触发 OOM Kill                                   │"
    echo "  │     - 进程被杀死                                            │"
    echo "  │     - 绝对上限                                              │"
    echo "  │                                                             │"
    echo "  │   推荐配置：                                                │"
    echo "  │     memory.high = 目标 × 80%                                │"
    echo "  │     memory.max  = 目标                                      │"
    echo "  │                                                             │"
    echo "  └─────────────────────────────────────────────────────────────┘"
    echo ""
}

# 捕获退出信号，确保清理
trap cleanup_all EXIT

main "$@"
