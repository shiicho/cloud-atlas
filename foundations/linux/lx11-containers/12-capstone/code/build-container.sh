#!/bin/bash
# =============================================================================
# build-container.sh - 从零构建容器（完整流程）
# =============================================================================
#
# 综合运用所有容器原语，构建完整的隔离容器环境：
#   1. Filesystem (OverlayFS)
#   2. Namespaces (PID, Mount, UTS, Net, IPC)
#   3. Network (veth + bridge + NAT)
#   4. Resource Limits (cgroups v2)
#   5. Run (pivot_root + exec)
#
# 用法：
#   sudo ./build-container.sh [options]
#
# 选项：
#   --rootfs <path>     根文件系统路径（默认: ./rootfs）
#   --name <name>       容器名称（默认: my-container）
#   --memory <limit>    内存限制（默认: 256M）
#   --cpu <percent>     CPU 百分比（默认: 50）
#   --ip <ip>           容器 IP（默认: 172.20.0.2）
#   --cleanup           清理之前的容器残留
#   --help              显示帮助
#
# 示例：
#   sudo ./build-container.sh
#   sudo ./build-container.sh --rootfs /path/to/alpine --name web-container
#   sudo ./build-container.sh --memory 512M --cpu 75
#
# =============================================================================

set -e

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# 打印函数
info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
cmd() { echo -e "${CYAN}[CMD]${NC} $1"; }
phase() {
    echo ""
    echo -e "${BOLD}${BLUE}=============================================="
    echo -e "  Phase: $1"
    echo -e "==============================================${NC}"
    echo ""
}

# =============================================================================
# 默认配置
# =============================================================================

ROOTFS_PATH="./rootfs"
CONTAINER_NAME="my-container"
MEMORY_LIMIT="256M"
CPU_PERCENT="50"
CONTAINER_IP="172.20.0.2"
DO_CLEANUP=false

# 派生配置
WORK_DIR="/tmp/container-${CONTAINER_NAME}"
OVERLAY_LOWER="${WORK_DIR}/lower"
OVERLAY_UPPER="${WORK_DIR}/upper"
OVERLAY_WORK="${WORK_DIR}/work"
OVERLAY_MERGED="${WORK_DIR}/merged"

BRIDGE_NAME="br-container"
BRIDGE_IP="172.20.0.1"
BRIDGE_SUBNET="172.20.0.0/24"
BRIDGE_MASK="24"

CGROUP_NAME="container-${CONTAINER_NAME}"
NFT_TABLE="container-nat"

# 容器 PID（运行时填充）
CONTAINER_PID=""

# =============================================================================
# 参数解析
# =============================================================================

show_help() {
    echo "用法: $0 [options]"
    echo ""
    echo "从零构建容器 - 综合运用 Namespace, cgroups, OverlayFS, 网络"
    echo ""
    echo "选项:"
    echo "  --rootfs <path>     根文件系统路径（默认: ./rootfs）"
    echo "  --name <name>       容器名称（默认: my-container）"
    echo "  --memory <limit>    内存限制（默认: 256M）"
    echo "  --cpu <percent>     CPU 百分比（默认: 50）"
    echo "  --ip <ip>           容器 IP（默认: 172.20.0.2）"
    echo "  --cleanup           清理之前的容器残留"
    echo "  --help              显示帮助"
    echo ""
    echo "示例:"
    echo "  $0"
    echo "  $0 --rootfs /path/to/alpine --name web-container"
    echo "  $0 --memory 512M --cpu 75"
    echo "  $0 --cleanup  # 清理后退出"
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --rootfs)
                ROOTFS_PATH="$2"
                shift 2
                ;;
            --name)
                CONTAINER_NAME="$2"
                shift 2
                ;;
            --memory)
                MEMORY_LIMIT="$2"
                shift 2
                ;;
            --cpu)
                CPU_PERCENT="$2"
                shift 2
                ;;
            --ip)
                CONTAINER_IP="$2"
                shift 2
                ;;
            --cleanup)
                DO_CLEANUP=true
                shift
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                warn "未知参数: $1"
                shift
                ;;
        esac
    done

    # 更新派生配置
    WORK_DIR="/tmp/container-${CONTAINER_NAME}"
    OVERLAY_LOWER="${WORK_DIR}/lower"
    OVERLAY_UPPER="${WORK_DIR}/upper"
    OVERLAY_WORK="${WORK_DIR}/work"
    OVERLAY_MERGED="${WORK_DIR}/merged"
    CGROUP_NAME="container-${CONTAINER_NAME}"
}

# =============================================================================
# 前置检查
# =============================================================================

check_prerequisites() {
    info "检查前置条件..."

    # 检查 root 权限
    if [[ $EUID -ne 0 ]]; then
        error "请使用 sudo 运行此脚本"
    fi

    # 检查 rootfs
    if [[ ! -d "$ROOTFS_PATH" ]]; then
        error "rootfs 目录不存在: $ROOTFS_PATH"
    fi

    # 检查 rootfs 内容
    if [[ ! -f "$ROOTFS_PATH/bin/sh" ]]; then
        error "rootfs 缺少 /bin/sh，请确保是有效的 Linux 根文件系统"
    fi

    # 检查 cgroups v2
    if ! mount | grep -q "cgroup2 on /sys/fs/cgroup"; then
        error "此系统未启用 cgroups v2"
    fi

    # 检查必要命令
    for cmd in ip nft unshare nsenter; do
        if ! command -v "$cmd" &>/dev/null; then
            error "缺少必要命令: $cmd"
        fi
    done

    info "前置条件检查通过"
}

# =============================================================================
# 清理函数
# =============================================================================

cleanup() {
    info "清理容器资源..."

    # 清理网络
    local veth_host="veth-${CONTAINER_NAME}-h"
    if ip link show "$veth_host" &>/dev/null; then
        ip link del "$veth_host" 2>/dev/null || true
    fi

    # 只在没有其他连接时删除 bridge
    if ip link show "$BRIDGE_NAME" &>/dev/null; then
        local veth_count=$(ip link show master "$BRIDGE_NAME" 2>/dev/null | wc -l)
        if [[ "$veth_count" -eq 0 ]]; then
            ip link del "$BRIDGE_NAME" 2>/dev/null || true
        fi
    fi

    # 清理 NAT
    if nft list table ip "$NFT_TABLE" &>/dev/null; then
        nft delete table ip "$NFT_TABLE" 2>/dev/null || true
    fi

    # 清理 cgroup
    local cgroup_path="/sys/fs/cgroup/$CGROUP_NAME"
    if [[ -d "$cgroup_path" ]]; then
        # 杀死 cgroup 中的进程
        for pid in $(cat "${cgroup_path}/cgroup.procs" 2>/dev/null); do
            kill -9 "$pid" 2>/dev/null || true
        done
        sleep 1
        rmdir "$cgroup_path" 2>/dev/null || true
    fi

    # 卸载 OverlayFS
    if mountpoint -q "$OVERLAY_MERGED" 2>/dev/null; then
        umount "$OVERLAY_MERGED" 2>/dev/null || true
    fi

    # 清理工作目录
    if [[ -d "$WORK_DIR" ]]; then
        rm -rf "$WORK_DIR" 2>/dev/null || true
    fi

    info "清理完成"
}

# 捕获退出信号
trap cleanup EXIT

# =============================================================================
# Phase 1: Filesystem (OverlayFS)
# =============================================================================

setup_filesystem() {
    phase "1. Filesystem (OverlayFS)"

    info "创建 OverlayFS 目录结构..."
    mkdir -p "$OVERLAY_LOWER" "$OVERLAY_UPPER" "$OVERLAY_WORK" "$OVERLAY_MERGED"

    info "复制 rootfs 到 lower 层..."
    cmd "cp -a $ROOTFS_PATH/* $OVERLAY_LOWER/"
    cp -a "$ROOTFS_PATH"/* "$OVERLAY_LOWER/"

    info "挂载 OverlayFS..."
    cmd "mount -t overlay overlay -o lowerdir=$OVERLAY_LOWER,upperdir=$OVERLAY_UPPER,workdir=$OVERLAY_WORK $OVERLAY_MERGED"
    mount -t overlay overlay \
        -o "lowerdir=$OVERLAY_LOWER,upperdir=$OVERLAY_UPPER,workdir=$OVERLAY_WORK" \
        "$OVERLAY_MERGED"

    # 验证
    if mountpoint -q "$OVERLAY_MERGED"; then
        info "OverlayFS 挂载成功"
        echo ""
        echo "  lower (只读): $OVERLAY_LOWER"
        echo "  upper (可写): $OVERLAY_UPPER"
        echo "  merged (合并): $OVERLAY_MERGED"
    else
        error "OverlayFS 挂载失败"
    fi
}

# =============================================================================
# Phase 2: Namespaces
# =============================================================================

# 这个函数在新的 namespace 中运行
container_init() {
    # 设置主机名
    hostname "$CONTAINER_NAME"

    # 等待网络配置
    echo "$$" > /tmp/container-${CONTAINER_NAME}.pid

    # 信号处理
    trap 'exit 0' TERM INT

    # 等待网络配置完成
    while [[ ! -f /tmp/container-${CONTAINER_NAME}.network_ready ]]; do
        sleep 0.1
    done

    # 切换根目录
    cd "$OVERLAY_MERGED"
    mkdir -p oldroot
    pivot_root . oldroot

    # 切换到新根
    cd /

    # 挂载必要的伪文件系统
    mount -t proc proc /proc
    mount -t sysfs sysfs /sys
    mount -t devtmpfs devtmpfs /dev 2>/dev/null || true
    mkdir -p /dev/pts
    mount -t devpts devpts /dev/pts 2>/dev/null || true

    # 清理旧根
    umount -l /oldroot 2>/dev/null || true
    rmdir /oldroot 2>/dev/null || true

    # 配置 DNS
    echo "nameserver 8.8.8.8" > /etc/resolv.conf

    # 执行 shell
    exec /bin/sh
}

setup_namespaces() {
    phase "2. Namespaces"

    info "创建隔离的 namespace 环境..."
    info "  PID:     隔离进程 ID"
    info "  Mount:   隔离挂载点"
    info "  UTS:     隔离主机名"
    info "  Network: 隔离网络栈"
    info "  IPC:     隔离进程间通信"
    echo ""

    # 清理可能存在的信号文件
    rm -f /tmp/container-${CONTAINER_NAME}.pid
    rm -f /tmp/container-${CONTAINER_NAME}.network_ready

    # 导出必要的变量和函数供子进程使用
    export CONTAINER_NAME OVERLAY_MERGED

    # 在后台启动容器进程
    # 使用 unshare 创建新的 namespace
    cmd "unshare --pid --fork --mount --uts --net --ipc /bin/bash"

    (
        # 在新 namespace 中
        unshare --pid --fork --mount --uts --net --ipc /bin/bash -c "
            # 设置主机名
            hostname $CONTAINER_NAME

            # 写入 PID
            echo \$\$ > /tmp/container-${CONTAINER_NAME}.pid

            # 等待网络配置
            while [[ ! -f /tmp/container-${CONTAINER_NAME}.network_ready ]]; do
                sleep 0.1
            done

            # 切换根目录
            cd $OVERLAY_MERGED
            mkdir -p oldroot
            pivot_root . oldroot
            cd /

            # 挂载伪文件系统
            mount -t proc proc /proc
            mount -t sysfs sysfs /sys

            # 清理旧根
            umount -l /oldroot 2>/dev/null || true
            rmdir /oldroot 2>/dev/null || true

            # 配置 DNS
            echo 'nameserver 8.8.8.8' > /etc/resolv.conf

            # 等待用户输入
            exec /bin/sh
        "
    ) &

    # 等待容器启动并获取 PID
    local wait_count=0
    while [[ ! -f /tmp/container-${CONTAINER_NAME}.pid ]]; do
        sleep 0.1
        ((wait_count++))
        if [[ $wait_count -gt 50 ]]; then
            error "等待容器启动超时"
        fi
    done

    CONTAINER_PID=$(cat /tmp/container-${CONTAINER_NAME}.pid)
    info "容器 PID: $CONTAINER_PID"
}

# =============================================================================
# Phase 3: Network
# =============================================================================

setup_network() {
    phase "3. Network (veth + bridge + NAT)"

    local veth_host="veth-${CONTAINER_NAME}-h"
    local veth_container="veth-${CONTAINER_NAME}-c"

    # 创建 bridge（如果不存在）
    if ! ip link show "$BRIDGE_NAME" &>/dev/null; then
        info "创建 bridge: $BRIDGE_NAME"
        cmd "ip link add $BRIDGE_NAME type bridge"
        ip link add "$BRIDGE_NAME" type bridge
        ip addr add "$BRIDGE_IP/$BRIDGE_MASK" dev "$BRIDGE_NAME"
        ip link set "$BRIDGE_NAME" up
    else
        info "bridge 已存在: $BRIDGE_NAME"
    fi

    # 创建 veth pair
    info "创建 veth pair..."
    cmd "ip link add $veth_host type veth peer name $veth_container"
    ip link add "$veth_host" type veth peer name "$veth_container"

    # 连接到 bridge
    info "连接 veth 到 bridge..."
    ip link set "$veth_host" master "$BRIDGE_NAME"
    ip link set "$veth_host" up

    # 移动 veth 到容器 namespace
    info "移动 veth 到容器 namespace..."
    cmd "ip link set $veth_container netns $CONTAINER_PID"
    ip link set "$veth_container" netns "$CONTAINER_PID"

    # 在容器内配置网络
    info "配置容器网络..."
    nsenter -t "$CONTAINER_PID" -n ip link set "$veth_container" name eth0 2>/dev/null || true
    nsenter -t "$CONTAINER_PID" -n ip addr add "$CONTAINER_IP/$BRIDGE_MASK" dev eth0 2>/dev/null || \
        nsenter -t "$CONTAINER_PID" -n ip addr add "$CONTAINER_IP/$BRIDGE_MASK" dev "$veth_container"
    nsenter -t "$CONTAINER_PID" -n ip link set eth0 up 2>/dev/null || \
        nsenter -t "$CONTAINER_PID" -n ip link set "$veth_container" up
    nsenter -t "$CONTAINER_PID" -n ip link set lo up
    nsenter -t "$CONTAINER_PID" -n ip route add default via "$BRIDGE_IP"

    # 启用 IP 转发
    info "启用 IP 转发..."
    echo 1 > /proc/sys/net/ipv4/ip_forward

    # 配置 NAT
    if ! nft list table ip "$NFT_TABLE" &>/dev/null; then
        info "配置 NAT (nftables)..."
        cmd "nft add table ip $NFT_TABLE"
        nft add table ip "$NFT_TABLE"
        nft add chain ip "$NFT_TABLE" postrouting { type nat hook postrouting priority 100 \; }
        nft add rule ip "$NFT_TABLE" postrouting ip saddr "$BRIDGE_SUBNET" masquerade
    else
        info "NAT 规则已存在"
    fi

    info "网络配置完成"
    echo ""
    echo "  bridge: $BRIDGE_NAME ($BRIDGE_IP)"
    echo "  container: $CONTAINER_IP"
    echo "  NAT: $BRIDGE_SUBNET -> masquerade"
}

# =============================================================================
# Phase 4: Resource Limits (cgroups)
# =============================================================================

setup_cgroups() {
    phase "4. Resource Limits (cgroups v2)"

    local cgroup_path="/sys/fs/cgroup/$CGROUP_NAME"

    # 创建 cgroup
    info "创建 cgroup: $CGROUP_NAME"
    mkdir -p "$cgroup_path"

    # 配置内存限制
    info "设置内存限制: $MEMORY_LIMIT"
    echo "$MEMORY_LIMIT" > "$cgroup_path/memory.max"

    # 设置软限制（80%）
    if [[ "$MEMORY_LIMIT" =~ ^([0-9]+)M$ ]]; then
        local mb="${BASH_REMATCH[1]}"
        local high="$((mb * 80 / 100))M"
        echo "$high" > "$cgroup_path/memory.high"
        info "设置内存软限制: $high"
    fi

    # 配置 CPU 限制
    local period=100000
    local quota=$((CPU_PERCENT * period / 100))
    info "设置 CPU 限制: ${CPU_PERCENT}%"
    echo "$quota $period" > "$cgroup_path/cpu.max"

    # 将容器进程加入 cgroup
    info "将容器进程加入 cgroup..."
    echo "$CONTAINER_PID" > "$cgroup_path/cgroup.procs"

    info "资源限制配置完成"
    echo ""
    echo "  memory.max:  $(cat $cgroup_path/memory.max)"
    echo "  memory.high: $(cat $cgroup_path/memory.high 2>/dev/null || echo 'N/A')"
    echo "  cpu.max:     $(cat $cgroup_path/cpu.max)"
}

# =============================================================================
# Phase 5: Run
# =============================================================================

run_container() {
    phase "5. Run"

    info "=============================================="
    info "  容器构建完成！"
    info "=============================================="
    echo ""
    echo "容器配置:"
    echo "  名称:     $CONTAINER_NAME"
    echo "  PID:      $CONTAINER_PID"
    echo "  rootfs:   $OVERLAY_MERGED"
    echo "  IP:       $CONTAINER_IP"
    echo "  内存限制: $MEMORY_LIMIT"
    echo "  CPU 限制: ${CPU_PERCENT}%"
    echo ""

    # 通知容器网络已就绪
    touch /tmp/container-${CONTAINER_NAME}.network_ready

    info "进入容器..."
    echo ""
    echo "=========================================="
    echo "  你现在在容器内！"
    echo "=========================================="
    echo ""
    echo "验证命令:"
    echo "  ps aux          # 验证 PID 隔离"
    echo "  hostname        # 验证主机名隔离"
    echo "  ip addr         # 验证网络隔离"
    echo "  ping 8.8.8.8    # 验证外网连接"
    echo ""
    echo "输入 'exit' 退出容器"
    echo ""

    # 等待容器进程
    wait "$CONTAINER_PID" 2>/dev/null || true

    # 或者使用 nsenter 进入容器
    # nsenter -t "$CONTAINER_PID" -a /bin/sh
}

# =============================================================================
# 简化版本：单进程容器
# =============================================================================

# 这个版本更简单，直接在当前 shell 中运行
run_simple() {
    phase "5. Run (简化版)"

    info "=============================================="
    info "  容器构建完成！"
    info "=============================================="
    echo ""
    echo "容器配置:"
    echo "  名称:     $CONTAINER_NAME"
    echo "  rootfs:   $OVERLAY_MERGED"
    echo "  IP:       $CONTAINER_IP"
    echo "  内存限制: $MEMORY_LIMIT"
    echo "  CPU 限制: ${CPU_PERCENT}%"
    echo ""

    info "启动容器..."
    echo ""
    echo "=========================================="
    echo "  你即将进入容器！"
    echo "=========================================="
    echo ""
    echo "验证命令:"
    echo "  ps aux          # 验证 PID 隔离"
    echo "  hostname        # 验证主机名隔离"
    echo "  ip addr         # 验证网络隔离"
    echo "  ping 8.8.8.8    # 验证外网连接"
    echo ""
    echo "输入 'exit' 退出容器"
    echo ""

    # 使用 unshare 直接进入容器
    # 取消 trap 以避免过早清理
    trap - EXIT

    exec unshare --pid --fork --mount --uts --net --ipc /bin/bash << CONTAINER_SCRIPT
# 设置主机名
hostname $CONTAINER_NAME

# 写入 PID 供网络配置使用
echo \$\$ > /tmp/container-${CONTAINER_NAME}.pid
CONTAINER_PID=\$\$

# 后台配置网络（在 namespace 创建后）
(
    sleep 0.5

    # 配置 bridge（如果不存在）
    if ! ip link show $BRIDGE_NAME &>/dev/null 2>&1; then
        ip link add $BRIDGE_NAME type bridge 2>/dev/null || true
        ip addr add $BRIDGE_IP/$BRIDGE_MASK dev $BRIDGE_NAME 2>/dev/null || true
        ip link set $BRIDGE_NAME up 2>/dev/null || true
    fi

    # 创建 veth pair
    veth_host="veth-${CONTAINER_NAME}-h"
    veth_container="veth-${CONTAINER_NAME}-c"

    ip link add \$veth_host type veth peer name \$veth_container 2>/dev/null || true
    ip link set \$veth_host master $BRIDGE_NAME 2>/dev/null || true
    ip link set \$veth_host up 2>/dev/null || true

    # 配置容器端
    ip addr add $CONTAINER_IP/$BRIDGE_MASK dev \$veth_container 2>/dev/null || true
    ip link set \$veth_container up 2>/dev/null || true
    ip link set lo up 2>/dev/null || true
    ip route add default via $BRIDGE_IP 2>/dev/null || true

    # 启用 IP 转发和 NAT（需要在宿主机执行）
    # 这里只配置容器内的网络
) &

# 等待网络配置
sleep 1

# 切换根目录
cd $OVERLAY_MERGED
mkdir -p oldroot
pivot_root . oldroot
cd /

# 挂载伪文件系统
mount -t proc proc /proc
mount -t sysfs sysfs /sys

# 清理旧根
umount -l /oldroot 2>/dev/null || true
rmdir /oldroot 2>/dev/null || true

# 配置 DNS
echo "nameserver 8.8.8.8" > /etc/resolv.conf

# 运行 shell
exec /bin/sh
CONTAINER_SCRIPT
}

# =============================================================================
# 主函数
# =============================================================================

main() {
    parse_args "$@"

    echo ""
    echo -e "${BOLD}${BLUE}=============================================="
    echo "  从零构建容器 - Capstone"
    echo -e "==============================================${NC}"
    echo ""
    echo "配置:"
    echo "  rootfs:     $ROOTFS_PATH"
    echo "  name:       $CONTAINER_NAME"
    echo "  memory:     $MEMORY_LIMIT"
    echo "  cpu:        ${CPU_PERCENT}%"
    echo "  ip:         $CONTAINER_IP"
    echo ""

    # 如果只是清理，执行清理后退出
    if [[ "$DO_CLEANUP" == "true" ]]; then
        cleanup
        exit 0
    fi

    # 前置检查
    check_prerequisites

    # 清理可能存在的残留
    cleanup 2>/dev/null || true
    trap cleanup EXIT

    # Phase 1: Filesystem
    setup_filesystem

    # Phase 2-5: 使用简化版本（更可靠）
    # 先配置网络和 cgroup，然后启动容器

    phase "2-4. 准备 Network + cgroups"

    # 预先配置网络基础设施
    info "配置网络基础设施..."

    # 创建 bridge
    if ! ip link show "$BRIDGE_NAME" &>/dev/null; then
        ip link add "$BRIDGE_NAME" type bridge
        ip addr add "$BRIDGE_IP/$BRIDGE_MASK" dev "$BRIDGE_NAME"
        ip link set "$BRIDGE_NAME" up
        info "创建 bridge: $BRIDGE_NAME"
    fi

    # 启用 IP 转发
    echo 1 > /proc/sys/net/ipv4/ip_forward
    info "启用 IP 转发"

    # 配置 NAT
    if ! nft list table ip "$NFT_TABLE" &>/dev/null; then
        nft add table ip "$NFT_TABLE"
        nft add chain ip "$NFT_TABLE" postrouting { type nat hook postrouting priority 100 \; }
        nft add rule ip "$NFT_TABLE" postrouting ip saddr "$BRIDGE_SUBNET" masquerade
        info "配置 NAT"
    fi

    # 预先创建 cgroup
    local cgroup_path="/sys/fs/cgroup/$CGROUP_NAME"
    mkdir -p "$cgroup_path"
    echo "$MEMORY_LIMIT" > "$cgroup_path/memory.max"
    local period=100000
    local quota=$((CPU_PERCENT * period / 100))
    echo "$quota $period" > "$cgroup_path/cpu.max"
    info "创建 cgroup: $CGROUP_NAME"

    # 运行容器
    run_simple
}

main "$@"
