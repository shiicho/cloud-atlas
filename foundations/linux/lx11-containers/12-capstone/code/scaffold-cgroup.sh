#!/bin/bash
# =============================================================================
# scaffold-cgroup.sh - cgroups v2 设置脚手架
# =============================================================================
#
# 处理 cgroups 配置的常见陷阱：
#   1. 检测 cgroup v2 挂载点
#   2. 创建 cgroup 目录结构
#   3. 正确写入 memory.max 和 cpu.max
#   4. 将进程加入 cgroup
#
# 用法：
#   sudo ./scaffold-cgroup.sh <cgroup-name> [memory-limit] [cpu-percent] [pid]
#
# 示例：
#   sudo ./scaffold-cgroup.sh my-container 256M 50
#   sudo ./scaffold-cgroup.sh my-container 256M 50 12345
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

# 打印函数
info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
cmd() { echo -e "${CYAN}[CMD]${NC} $1"; }

# =============================================================================
# 参数处理
# =============================================================================

CGROUP_NAME="${1:-}"
MEMORY_LIMIT="${2:-256M}"
CPU_PERCENT="${3:-50}"
TARGET_PID="${4:-}"

if [[ -z "$CGROUP_NAME" ]]; then
    echo "用法: $0 <cgroup-name> [memory-limit] [cpu-percent] [pid]"
    echo ""
    echo "参数:"
    echo "  cgroup-name   cgroup 名称"
    echo "  memory-limit  内存限制（默认: 256M）"
    echo "  cpu-percent   CPU 百分比（默认: 50）"
    echo "  pid           要加入 cgroup 的进程 ID（可选）"
    echo ""
    echo "示例:"
    echo "  $0 my-container"
    echo "  $0 my-container 512M 75"
    echo "  $0 my-container 256M 50 12345"
    exit 1
fi

if [[ $EUID -ne 0 ]]; then
    error "请使用 sudo 运行此脚本"
fi

# =============================================================================
# 检测 cgroup v2
# =============================================================================

detect_cgroup_v2() {
    info "检测 cgroups 版本..."

    # 方法 1：检查 /sys/fs/cgroup 挂载类型
    if mount | grep -q "cgroup2 on /sys/fs/cgroup"; then
        CGROUP_BASE="/sys/fs/cgroup"
        info "检测到 cgroups v2（挂载点: $CGROUP_BASE）"
        return 0
    fi

    # 方法 2：检查 /sys/fs/cgroup/cgroup.controllers 是否存在
    if [[ -f "/sys/fs/cgroup/cgroup.controllers" ]]; then
        CGROUP_BASE="/sys/fs/cgroup"
        info "检测到 cgroups v2（通过 cgroup.controllers）"
        return 0
    fi

    # 方法 3：检查是否是混合模式
    if [[ -d "/sys/fs/cgroup/unified" ]]; then
        CGROUP_BASE="/sys/fs/cgroup/unified"
        warn "检测到 cgroups 混合模式（使用 unified 层级）"
        return 0
    fi

    error "未检测到 cgroups v2！请确保系统支持 cgroups v2"
}

# =============================================================================
# 创建 cgroup
# =============================================================================

create_cgroup() {
    local cgroup_path="${CGROUP_BASE}/${CGROUP_NAME}"

    # 检查是否已存在
    if [[ -d "$cgroup_path" ]]; then
        warn "cgroup 已存在: $cgroup_path"
        return 0
    fi

    info "创建 cgroup: $cgroup_path"
    cmd "mkdir $cgroup_path"
    mkdir -p "$cgroup_path"

    # 验证创建成功
    if [[ ! -d "$cgroup_path" ]]; then
        error "创建 cgroup 失败"
    fi

    info "cgroup 创建成功"
}

# =============================================================================
# 配置内存限制
# =============================================================================

configure_memory() {
    local cgroup_path="${CGROUP_BASE}/${CGROUP_NAME}"
    local memory_max_file="${cgroup_path}/memory.max"

    info "配置内存限制: $MEMORY_LIMIT"

    # 检查 memory.max 文件是否存在
    if [[ ! -f "$memory_max_file" ]]; then
        warn "memory.max 文件不存在，检查控制器是否启用..."

        # 检查可用控制器
        local available=$(cat "${CGROUP_BASE}/cgroup.controllers" 2>/dev/null || echo "")
        if [[ "$available" != *"memory"* ]]; then
            error "memory 控制器未启用。可用控制器: $available"
        fi

        # 尝试启用 memory 控制器
        warn "尝试在父 cgroup 启用 memory 控制器..."
        echo "+memory" > "${CGROUP_BASE}/cgroup.subtree_control" 2>/dev/null || true
    fi

    # 写入内存限制
    # 支持格式：100M, 1G, 1073741824 (bytes)
    cmd "echo '$MEMORY_LIMIT' > $memory_max_file"
    echo "$MEMORY_LIMIT" > "$memory_max_file"

    # 验证
    local actual=$(cat "$memory_max_file")
    info "内存限制已设置: $actual"

    # 可选：设置软限制 (memory.high = 80% of memory.max)
    local memory_high_file="${cgroup_path}/memory.high"
    if [[ -f "$memory_high_file" ]]; then
        # 简单计算 80%（仅支持 M/G 格式）
        local high_limit=""
        if [[ "$MEMORY_LIMIT" =~ ^([0-9]+)M$ ]]; then
            local mb="${BASH_REMATCH[1]}"
            high_limit="$((mb * 80 / 100))M"
        elif [[ "$MEMORY_LIMIT" =~ ^([0-9]+)G$ ]]; then
            local gb="${BASH_REMATCH[1]}"
            high_limit="$((gb * 800))M"  # 80% in MB
        fi

        if [[ -n "$high_limit" ]]; then
            cmd "echo '$high_limit' > $memory_high_file"
            echo "$high_limit" > "$memory_high_file"
            info "内存软限制已设置: $high_limit (80%)"
        fi
    fi
}

# =============================================================================
# 配置 CPU 限制
# =============================================================================

configure_cpu() {
    local cgroup_path="${CGROUP_BASE}/${CGROUP_NAME}"
    local cpu_max_file="${cgroup_path}/cpu.max"

    info "配置 CPU 限制: ${CPU_PERCENT}%"

    # 检查 cpu.max 文件是否存在
    if [[ ! -f "$cpu_max_file" ]]; then
        warn "cpu.max 文件不存在，检查控制器是否启用..."

        # 尝试启用 cpu 控制器
        echo "+cpu" > "${CGROUP_BASE}/cgroup.subtree_control" 2>/dev/null || true
    fi

    # cpu.max 格式：'quota period'
    # quota: 微秒，每个周期内可使用的 CPU 时间
    # period: 微秒，周期长度（通常 100000 = 100ms）
    #
    # 例如：50% CPU = '50000 100000'
    #       100% CPU = '100000 100000' 或 'max 100000'
    #       200% CPU (2 核) = '200000 100000'

    local period=100000
    local quota=$((CPU_PERCENT * period / 100))
    local cpu_max_value="$quota $period"

    cmd "echo '$cpu_max_value' > $cpu_max_file"
    echo "$cpu_max_value" > "$cpu_max_file"

    # 验证
    local actual=$(cat "$cpu_max_file")
    info "CPU 限制已设置: $actual"
}

# =============================================================================
# 添加进程到 cgroup
# =============================================================================

add_process() {
    local cgroup_path="${CGROUP_BASE}/${CGROUP_NAME}"
    local procs_file="${cgroup_path}/cgroup.procs"

    if [[ -z "$TARGET_PID" ]]; then
        info "未指定 PID，跳过进程添加"
        info "手动添加进程："
        cmd "echo <PID> > $procs_file"
        return 0
    fi

    # 验证 PID 存在
    if ! kill -0 "$TARGET_PID" 2>/dev/null; then
        error "进程 $TARGET_PID 不存在"
    fi

    info "将进程 $TARGET_PID 加入 cgroup"
    cmd "echo '$TARGET_PID' > $procs_file"
    echo "$TARGET_PID" > "$procs_file"

    # 验证
    if grep -q "^${TARGET_PID}$" "$procs_file" 2>/dev/null; then
        info "进程 $TARGET_PID 已加入 cgroup"
    else
        warn "进程可能已加入，但验证失败"
    fi
}

# =============================================================================
# 显示 cgroup 状态
# =============================================================================

show_status() {
    local cgroup_path="${CGROUP_BASE}/${CGROUP_NAME}"

    echo ""
    info "=== cgroup 状态 ==="
    echo ""
    echo "路径: $cgroup_path"
    echo ""
    echo "内存配置:"
    echo "  memory.max:     $(cat ${cgroup_path}/memory.max 2>/dev/null || echo 'N/A')"
    echo "  memory.high:    $(cat ${cgroup_path}/memory.high 2>/dev/null || echo 'N/A')"
    echo "  memory.current: $(cat ${cgroup_path}/memory.current 2>/dev/null || echo 'N/A')"
    echo ""
    echo "CPU 配置:"
    echo "  cpu.max:        $(cat ${cgroup_path}/cpu.max 2>/dev/null || echo 'N/A')"
    echo ""
    echo "进程列表:"
    local procs=$(cat ${cgroup_path}/cgroup.procs 2>/dev/null | head -5)
    if [[ -n "$procs" ]]; then
        echo "$procs" | while read pid; do
            local cmd_name=$(cat /proc/$pid/comm 2>/dev/null || echo "unknown")
            echo "  $pid ($cmd_name)"
        done
    else
        echo "  (无进程)"
    fi
    echo ""
}

# =============================================================================
# 清理函数
# =============================================================================

cleanup_cgroup() {
    local cgroup_path="${CGROUP_BASE}/${CGROUP_NAME}"

    if [[ -d "$cgroup_path" ]]; then
        warn "清理 cgroup: $cgroup_path"

        # 杀死 cgroup 中的进程
        for pid in $(cat "${cgroup_path}/cgroup.procs" 2>/dev/null); do
            kill -9 "$pid" 2>/dev/null || true
        done
        sleep 1

        # 删除 cgroup
        rmdir "$cgroup_path" 2>/dev/null || warn "无法删除 cgroup（可能仍有进程）"
    fi
}

# =============================================================================
# 主函数
# =============================================================================

main() {
    echo ""
    info "=============================================="
    info "  cgroups v2 配置脚手架"
    info "=============================================="
    echo ""

    # 检测 cgroup v2
    detect_cgroup_v2

    # 创建 cgroup
    create_cgroup

    # 配置资源限制
    configure_memory
    configure_cpu

    # 添加进程
    add_process

    # 显示状态
    show_status

    info "=============================================="
    info "  配置完成！"
    info "=============================================="
    echo ""
    info "后续操作："
    if [[ -z "$TARGET_PID" ]]; then
        echo "  1. 将进程加入 cgroup："
        echo "     echo <PID> | sudo tee ${CGROUP_BASE}/${CGROUP_NAME}/cgroup.procs"
    fi
    echo "  2. 监控资源使用："
    echo "     watch cat ${CGROUP_BASE}/${CGROUP_NAME}/memory.current"
    echo "  3. 查看 OOM 事件："
    echo "     cat ${CGROUP_BASE}/${CGROUP_NAME}/memory.events"
    echo "  4. 删除 cgroup："
    echo "     sudo rmdir ${CGROUP_BASE}/${CGROUP_NAME}"
    echo ""
}

# 运行主函数
main
