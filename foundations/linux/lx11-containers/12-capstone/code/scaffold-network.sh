#!/bin/bash
# =============================================================================
# scaffold-network.sh - 容器网络设置脚手架
# =============================================================================
#
# 处理容器网络配置的常见陷阱：
#   1. veth pair 创建和命名
#   2. bridge 设置
#   3. nftables NAT 规则（非 iptables）
#   4. IP 转发启用
#
# 用法：
#   sudo ./scaffold-network.sh <action> [options]
#
# 动作：
#   setup   - 完整网络设置
#   cleanup - 清理网络配置
#   status  - 显示网络状态
#
# 示例：
#   sudo ./scaffold-network.sh setup --pid 12345 --name my-container
#   sudo ./scaffold-network.sh cleanup --name my-container
#   sudo ./scaffold-network.sh status
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
# 默认配置
# =============================================================================

# bridge 配置
BRIDGE_NAME="br-container"
BRIDGE_IP="172.20.0.1"
BRIDGE_SUBNET="172.20.0.0/24"
BRIDGE_MASK="24"

# 容器配置（默认值，可通过参数覆盖）
CONTAINER_NAME="container1"
CONTAINER_IP="172.20.0.2"
CONTAINER_PID=""

# nftables 表名
NFT_TABLE="container-nat"

# =============================================================================
# 参数解析
# =============================================================================

ACTION=""

parse_args() {
    if [[ $# -lt 1 ]]; then
        show_usage
        exit 1
    fi

    ACTION="$1"
    shift

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --pid)
                CONTAINER_PID="$2"
                shift 2
                ;;
            --name)
                CONTAINER_NAME="$2"
                shift 2
                ;;
            --ip)
                CONTAINER_IP="$2"
                shift 2
                ;;
            --bridge)
                BRIDGE_NAME="$2"
                shift 2
                ;;
            --help|-h)
                show_usage
                exit 0
                ;;
            *)
                warn "未知参数: $1"
                shift
                ;;
        esac
    done
}

show_usage() {
    echo "用法: $0 <action> [options]"
    echo ""
    echo "动作:"
    echo "  setup   - 完整网络设置"
    echo "  cleanup - 清理网络配置"
    echo "  status  - 显示网络状态"
    echo ""
    echo "选项:"
    echo "  --pid <pid>       容器进程 PID（setup 必需）"
    echo "  --name <name>     容器名称（用于 veth 命名）"
    echo "  --ip <ip>         容器 IP 地址（默认: $CONTAINER_IP）"
    echo "  --bridge <name>   bridge 名称（默认: $BRIDGE_NAME）"
    echo ""
    echo "示例:"
    echo "  $0 setup --pid 12345 --name my-container"
    echo "  $0 cleanup --name my-container"
    echo "  $0 status"
}

# =============================================================================
# 检查依赖
# =============================================================================

check_dependencies() {
    # 检查 root 权限
    if [[ $EUID -ne 0 ]]; then
        error "请使用 sudo 运行此脚本"
    fi

    # 检查 ip 命令
    if ! command -v ip &>/dev/null; then
        error "ip 命令不可用（需要 iproute2 包）"
    fi

    # 检查 nft 命令
    if ! command -v nft &>/dev/null; then
        error "nft 命令不可用（需要 nftables 包）"
    fi
}

# =============================================================================
# Bridge 管理
# =============================================================================

create_bridge() {
    info "检查/创建 bridge: $BRIDGE_NAME"

    # 检查 bridge 是否存在
    if ip link show "$BRIDGE_NAME" &>/dev/null; then
        info "bridge 已存在: $BRIDGE_NAME"
        return 0
    fi

    # 创建 bridge
    cmd "ip link add $BRIDGE_NAME type bridge"
    ip link add "$BRIDGE_NAME" type bridge

    # 配置 bridge IP
    cmd "ip addr add $BRIDGE_IP/$BRIDGE_MASK dev $BRIDGE_NAME"
    ip addr add "$BRIDGE_IP/$BRIDGE_MASK" dev "$BRIDGE_NAME"

    # 启用 bridge
    cmd "ip link set $BRIDGE_NAME up"
    ip link set "$BRIDGE_NAME" up

    info "bridge 创建成功: $BRIDGE_NAME ($BRIDGE_IP/$BRIDGE_MASK)"
}

delete_bridge() {
    if ip link show "$BRIDGE_NAME" &>/dev/null; then
        info "删除 bridge: $BRIDGE_NAME"
        cmd "ip link del $BRIDGE_NAME"
        ip link del "$BRIDGE_NAME" 2>/dev/null || true
    fi
}

# =============================================================================
# veth pair 管理
# =============================================================================

create_veth_pair() {
    local veth_host="veth-${CONTAINER_NAME}-h"
    local veth_container="veth-${CONTAINER_NAME}-c"

    info "创建 veth pair: $veth_host <-> $veth_container"

    # 检查是否已存在
    if ip link show "$veth_host" &>/dev/null; then
        warn "veth pair 已存在，删除后重建..."
        ip link del "$veth_host" 2>/dev/null || true
    fi

    # 创建 veth pair
    cmd "ip link add $veth_host type veth peer name $veth_container"
    ip link add "$veth_host" type veth peer name "$veth_container"

    info "veth pair 创建成功"
}

connect_to_bridge() {
    local veth_host="veth-${CONTAINER_NAME}-h"

    info "连接 veth 到 bridge"

    # 将宿主机端连接到 bridge
    cmd "ip link set $veth_host master $BRIDGE_NAME"
    ip link set "$veth_host" master "$BRIDGE_NAME"

    # 启用宿主机端
    cmd "ip link set $veth_host up"
    ip link set "$veth_host" up

    info "veth 已连接到 bridge"
}

move_to_namespace() {
    local veth_container="veth-${CONTAINER_NAME}-c"

    if [[ -z "$CONTAINER_PID" ]]; then
        error "未指定容器 PID（使用 --pid 参数）"
    fi

    # 验证 PID 存在
    if ! kill -0 "$CONTAINER_PID" 2>/dev/null; then
        error "进程 $CONTAINER_PID 不存在"
    fi

    info "将 veth 移到容器 namespace (PID: $CONTAINER_PID)"

    # 移动 veth 到容器 namespace
    cmd "ip link set $veth_container netns $CONTAINER_PID"
    ip link set "$veth_container" netns "$CONTAINER_PID"

    info "veth 已移到容器 namespace"
}

configure_container_network() {
    local veth_container="veth-${CONTAINER_NAME}-c"

    info "配置容器网络接口"

    # 使用 nsenter 在容器 namespace 中配置网络
    # -t: target PID
    # -n: network namespace

    # 重命名为 eth0（可选，更符合习惯）
    cmd "nsenter -t $CONTAINER_PID -n ip link set $veth_container name eth0"
    nsenter -t "$CONTAINER_PID" -n ip link set "$veth_container" name eth0 2>/dev/null || \
        warn "无法重命名 veth（可能已重命名或不在 namespace 中）"

    # 配置 IP 地址
    cmd "nsenter -t $CONTAINER_PID -n ip addr add $CONTAINER_IP/$BRIDGE_MASK dev eth0"
    nsenter -t "$CONTAINER_PID" -n ip addr add "$CONTAINER_IP/$BRIDGE_MASK" dev eth0 2>/dev/null || \
        nsenter -t "$CONTAINER_PID" -n ip addr add "$CONTAINER_IP/$BRIDGE_MASK" dev "$veth_container" 2>/dev/null || \
        warn "无法配置 IP 地址"

    # 启用接口
    cmd "nsenter -t $CONTAINER_PID -n ip link set eth0 up"
    nsenter -t "$CONTAINER_PID" -n ip link set eth0 up 2>/dev/null || \
        nsenter -t "$CONTAINER_PID" -n ip link set "$veth_container" up 2>/dev/null || true

    # 启用 loopback
    cmd "nsenter -t $CONTAINER_PID -n ip link set lo up"
    nsenter -t "$CONTAINER_PID" -n ip link set lo up 2>/dev/null || true

    # 添加默认路由
    cmd "nsenter -t $CONTAINER_PID -n ip route add default via $BRIDGE_IP"
    nsenter -t "$CONTAINER_PID" -n ip route add default via "$BRIDGE_IP" 2>/dev/null || \
        warn "无法添加默认路由（可能已存在）"

    info "容器网络配置完成"
}

delete_veth() {
    local veth_host="veth-${CONTAINER_NAME}-h"

    if ip link show "$veth_host" &>/dev/null; then
        info "删除 veth pair"
        cmd "ip link del $veth_host"
        ip link del "$veth_host" 2>/dev/null || true
    fi
}

# =============================================================================
# NAT 配置 (nftables)
# =============================================================================

enable_ip_forward() {
    info "启用 IP 转发"

    local current=$(cat /proc/sys/net/ipv4/ip_forward)
    if [[ "$current" == "1" ]]; then
        info "IP 转发已启用"
        return 0
    fi

    cmd "echo 1 > /proc/sys/net/ipv4/ip_forward"
    echo 1 > /proc/sys/net/ipv4/ip_forward

    info "IP 转发已启用"
}

setup_nat() {
    info "配置 NAT (nftables)"

    # 为什么使用 nftables 而不是 iptables？
    # 1. nftables 是 Linux 内核 3.13+ 的现代防火墙框架
    # 2. 语法更清晰，性能更好
    # 3. 是 iptables 的继任者，Ubuntu 21.04+, RHEL 8+ 默认使用

    # 检查表是否存在
    if nft list table ip "$NFT_TABLE" &>/dev/null; then
        warn "nftables 表已存在: $NFT_TABLE"
        return 0
    fi

    # 创建 NAT 表
    cmd "nft add table ip $NFT_TABLE"
    nft add table ip "$NFT_TABLE"

    # 创建 postrouting 链（SNAT/MASQUERADE）
    # type nat: NAT 类型
    # hook postrouting: 在包离开本机前处理
    # priority 100: 优先级（srcnat 标准值）
    cmd "nft add chain ip $NFT_TABLE postrouting { type nat hook postrouting priority 100 \\; }"
    nft add chain ip "$NFT_TABLE" postrouting { type nat hook postrouting priority 100 \; }

    # 添加 MASQUERADE 规则
    # 源地址在容器子网的包，做地址伪装
    cmd "nft add rule ip $NFT_TABLE postrouting ip saddr $BRIDGE_SUBNET masquerade"
    nft add rule ip "$NFT_TABLE" postrouting ip saddr "$BRIDGE_SUBNET" masquerade

    info "NAT 配置完成"

    # 显示规则
    echo ""
    info "当前 NAT 规则："
    nft list table ip "$NFT_TABLE"
}

cleanup_nat() {
    if nft list table ip "$NFT_TABLE" &>/dev/null; then
        info "删除 NAT 表: $NFT_TABLE"
        cmd "nft delete table ip $NFT_TABLE"
        nft delete table ip "$NFT_TABLE" 2>/dev/null || true
    fi
}

# =============================================================================
# 状态显示
# =============================================================================

show_status() {
    echo ""
    info "=============================================="
    info "  容器网络状态"
    info "=============================================="
    echo ""

    # Bridge 状态
    echo "=== Bridge ==="
    if ip link show "$BRIDGE_NAME" &>/dev/null; then
        ip addr show "$BRIDGE_NAME"
        echo ""
        echo "Bridge 成员:"
        ip link show master "$BRIDGE_NAME" 2>/dev/null || echo "  (无)"
    else
        echo "  bridge $BRIDGE_NAME 不存在"
    fi
    echo ""

    # veth 状态
    echo "=== veth pairs ==="
    ip link show type veth 2>/dev/null | grep -E "^[0-9]+:" || echo "  (无)"
    echo ""

    # NAT 规则
    echo "=== NAT 规则 (nftables) ==="
    if nft list table ip "$NFT_TABLE" &>/dev/null; then
        nft list table ip "$NFT_TABLE"
    else
        echo "  NAT 表 $NFT_TABLE 不存在"
    fi
    echo ""

    # IP 转发状态
    echo "=== IP 转发 ==="
    local forward=$(cat /proc/sys/net/ipv4/ip_forward)
    if [[ "$forward" == "1" ]]; then
        echo "  已启用"
    else
        echo "  未启用"
    fi
    echo ""
}

# =============================================================================
# 主要操作
# =============================================================================

do_setup() {
    echo ""
    info "=============================================="
    info "  容器网络设置"
    info "=============================================="
    echo ""
    info "配置信息："
    echo "  bridge:       $BRIDGE_NAME ($BRIDGE_IP/$BRIDGE_MASK)"
    echo "  container:    $CONTAINER_NAME"
    echo "  container IP: $CONTAINER_IP"
    echo "  container PID: ${CONTAINER_PID:-<未指定>}"
    echo ""

    if [[ -z "$CONTAINER_PID" ]]; then
        error "setup 需要指定 --pid 参数"
    fi

    # 执行设置步骤
    create_bridge
    create_veth_pair
    connect_to_bridge
    move_to_namespace
    configure_container_network
    enable_ip_forward
    setup_nat

    echo ""
    info "=============================================="
    info "  网络设置完成！"
    info "=============================================="
    echo ""
    info "验证命令："
    echo "  # 在容器内测试外网连接："
    echo "  nsenter -t $CONTAINER_PID -n ping -c 3 8.8.8.8"
    echo ""
    echo "  # 在容器内查看网络配置："
    echo "  nsenter -t $CONTAINER_PID -n ip addr"
    echo "  nsenter -t $CONTAINER_PID -n ip route"
    echo ""
}

do_cleanup() {
    echo ""
    info "=============================================="
    info "  清理容器网络"
    info "=============================================="
    echo ""

    delete_veth
    cleanup_nat

    # 只在没有其他 veth 连接时删除 bridge
    local veth_count=$(ip link show master "$BRIDGE_NAME" 2>/dev/null | wc -l)
    if [[ "$veth_count" -eq 0 ]]; then
        delete_bridge
    else
        warn "bridge 仍有其他连接，保留"
    fi

    info "清理完成"
}

# =============================================================================
# 主函数
# =============================================================================

main() {
    parse_args "$@"
    check_dependencies

    case "$ACTION" in
        setup)
            do_setup
            ;;
        cleanup)
            do_cleanup
            ;;
        status)
            show_status
            ;;
        *)
            error "未知动作: $ACTION"
            ;;
    esac
}

main "$@"
