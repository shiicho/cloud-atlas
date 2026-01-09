#!/bin/bash
# =============================================================================
# isolation-demo.sh - 容器 vs 虚拟机隔离演示
# =============================================================================
#
# 演示 Linux Namespace 隔离效果
# 用于 LX11-CONTAINERS Lesson 01
#
# 用法：
#   sudo ./isolation-demo.sh
#
# 演示内容：
#   1. Network Namespace 隔离
#   2. PID Namespace 隔离
#   3. UTS (hostname) Namespace 隔离
#   4. 内核共享验证
#
# =============================================================================

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

# 检查 root 权限
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}[ERROR]${NC} 请使用 sudo 运行此脚本"
        exit 1
    fi
}

# 演示 1：Network Namespace
demo_network_ns() {
    print_section "演示 1：Network Namespace 隔离"

    info "宿主机网络接口："
    ip -br link show
    echo ""

    info "创建隔离的 Network Namespace..."
    info "在隔离环境中查看网络接口："
    echo ""

    # 在隔离环境中执行命令
    unshare --net bash -c '
        echo "隔离环境内的网络接口："
        ip -br link show
        echo ""
        echo "尝试 ping 外网："
        ping -c 1 -W 1 8.8.8.8 2>&1 || echo "(预期失败 - 网络已隔离)"
    '

    echo ""
    info "结论：隔离环境只有 lo 接口，无法访问外网"
}

# 演示 2：PID Namespace
demo_pid_ns() {
    print_section "演示 2：PID Namespace 隔离"

    info "宿主机进程数量："
    ps aux | wc -l
    echo ""

    info "创建隔离的 PID Namespace..."
    info "在隔离环境中查看进程："
    echo ""

    # 在隔离环境中执行命令（需要挂载 /proc）
    unshare --pid --fork --mount-proc bash -c '
        echo "隔离环境内的进程："
        ps aux
        echo ""
        echo "当前 shell 的 PID："
        echo $$
        echo "(在隔离环境中，这个 shell 是 PID 1)"
    '

    echo ""
    info "结论：隔离环境中只能看到自己的进程，bash 成为 PID 1"
}

# 演示 3：UTS Namespace (hostname)
demo_uts_ns() {
    print_section "演示 3：UTS Namespace 隔离（主机名）"

    ORIGINAL_HOSTNAME=$(hostname)
    info "宿主机主机名：$ORIGINAL_HOSTNAME"
    echo ""

    info "创建隔离的 UTS Namespace 并修改主机名..."
    echo ""

    # 在隔离环境中修改主机名
    unshare --uts bash -c '
        echo "隔离环境原始主机名：$(hostname)"
        hostname container-demo-12345
        echo "隔离环境修改后主机名：$(hostname)"
    '

    echo ""
    info "宿主机主机名（未改变）：$(hostname)"
    info "结论：主机名修改只影响隔离环境，不影响宿主机"
}

# 演示 4：内核共享验证
demo_kernel_sharing() {
    print_section "演示 4：内核共享验证"

    HOST_KERNEL=$(uname -r)
    info "宿主机内核版本：$HOST_KERNEL"
    echo ""

    info "在隔离环境中查看内核版本..."

    ISOLATED_KERNEL=$(unshare --pid --net --fork --mount-proc bash -c 'uname -r')
    info "隔离环境内核版本：$ISOLATED_KERNEL"
    echo ""

    if [[ "$HOST_KERNEL" == "$ISOLATED_KERNEL" ]]; then
        info "${GREEN}内核版本相同！容器共享宿主机内核。${NC}"
    else
        warn "内核版本不同？这不应该发生..."
    fi

    echo ""
    info "这就是容器与虚拟机的核心区别："
    info "  - 虚拟机：每个 VM 有独立内核"
    info "  - 容器：所有容器共享宿主机内核"
}

# 演示 5：进程在宿主机可见
demo_process_visibility() {
    print_section "演示 5：「容器」进程在宿主机可见"

    info "启动一个长时间运行的隔离进程..."

    # 在后台启动隔离进程
    unshare --pid --net --fork --mount-proc sleep 30 &
    ISOLATED_PID=$!

    sleep 1  # 等待进程启动

    info "隔离进程的宿主机 PID：$ISOLATED_PID"
    echo ""

    info "在宿主机上查看该进程："
    ps aux | grep -E "^[^ ]+ +$ISOLATED_PID " || ps aux | head -1 && ps aux | grep "sleep 30" | grep -v grep
    echo ""

    info "结论：容器进程在宿主机上完全可见！"
    info "      这与虚拟机不同 - VM 内部进程在宿主机上看不到"

    # 清理
    kill $ISOLATED_PID 2>/dev/null || true
}

# 综合演示
demo_combined() {
    print_section "综合演示：完整的容器隔离"

    info "创建一个具有多种隔离的环境..."
    info "（PID + Network + UTS + Mount Namespace）"
    echo ""

    info "进入隔离环境，执行以下命令验证隔离效果："
    echo ""
    echo "  hostname                 # 查看/修改主机名"
    echo "  ps aux                   # 查看进程（只有自己）"
    echo "  ip addr                  # 查看网络（只有 lo）"
    echo "  uname -r                 # 查看内核（与宿主机相同）"
    echo "  exit                     # 退出隔离环境"
    echo ""

    warn "即将进入隔离环境，输入 'exit' 返回..."
    echo ""

    unshare --pid --net --uts --mount --fork --mount-proc bash

    echo ""
    info "已返回宿主机环境"
}

# 主函数
main() {
    check_root

    print_section "Linux 容器隔离演示"

    info "本脚本将演示 Linux Namespace 的隔离效果"
    info "这是容器技术的核心原语"
    echo ""

    # 选择演示模式
    if [[ "$1" == "--all" ]]; then
        demo_network_ns
        demo_pid_ns
        demo_uts_ns
        demo_kernel_sharing
        demo_process_visibility
    elif [[ "$1" == "--interactive" ]]; then
        demo_combined
    else
        echo "用法："
        echo "  sudo $0 --all          # 运行所有自动演示"
        echo "  sudo $0 --interactive  # 进入交互式隔离环境"
        echo ""
        echo "默认运行所有演示..."
        echo ""

        demo_network_ns
        demo_pid_ns
        demo_uts_ns
        demo_kernel_sharing
        demo_process_visibility
    fi

    print_section "演示完成"

    info "核心要点："
    info "  1. 容器 = 进程 + 约束（Namespace + cgroups + ...）"
    info "  2. 容器共享宿主机内核"
    info "  3. 容器进程在宿主机上可见"
    info "  4. 隔离是「看不到」，不是「不存在」"
    echo ""
}

main "$@"
