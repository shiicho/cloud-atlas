#!/bin/bash
# =============================================================================
# nsenter-debug.sh - 容器 Namespace 调试工具
# =============================================================================
#
# 用途：使用 nsenter 从宿主机调试容器
# 环境：需要 root 权限
#
# 使用方法：
#   sudo ./nsenter-debug.sh <container-name-or-pid>
#   sudo ./nsenter-debug.sh nginx
#   sudo ./nsenter-debug.sh 12345
#
# 支持：Docker, containerd (crictl), 直接 PID
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

# 打印带颜色的标题
print_section() {
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}  $1${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# 使用说明
usage() {
    echo "用法: $0 <container-name-or-pid> [options]"
    echo ""
    echo "参数:"
    echo "  <container-name-or-pid>  容器名称、ID 或进程 PID"
    echo ""
    echo "选项:"
    echo "  -n, --network    只调试网络"
    echo "  -m, --mount      只调试文件系统"
    echo "  -p, --process    只调试进程"
    echo "  -a, --all        进入完整调试 shell"
    echo "  -h, --help       显示帮助"
    echo ""
    echo "示例:"
    echo "  $0 nginx                 # 完整调试报告"
    echo "  $0 nginx -n              # 只调试网络"
    echo "  $0 12345 -a              # 进入 PID 12345 的完整 shell"
    exit 1
}

# 检查 root 权限
check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}错误：需要 root 权限${NC}"
        echo "请使用: sudo $0 $*"
        exit 1
    fi
}

# 获取容器 PID
get_container_pid() {
    local input="$1"
    local pid=""

    # 如果输入是数字，直接作为 PID
    if [[ "$input" =~ ^[0-9]+$ ]]; then
        if [ -d "/proc/$input" ]; then
            echo "$input"
            return 0
        else
            echo -e "${RED}错误：PID $input 不存在${NC}" >&2
            return 1
        fi
    fi

    # 尝试 Docker
    if command -v docker &>/dev/null; then
        pid=$(docker inspect --format '{{.State.Pid}}' "$input" 2>/dev/null)
        if [ -n "$pid" ] && [ "$pid" != "0" ]; then
            echo "$pid"
            return 0
        fi
    fi

    # 尝试 crictl (containerd/CRI-O)
    if command -v crictl &>/dev/null; then
        local container_id
        container_id=$(crictl ps --name "$input" -q 2>/dev/null | head -1)
        if [ -n "$container_id" ]; then
            pid=$(crictl inspect "$container_id" 2>/dev/null | jq -r '.info.pid' 2>/dev/null)
            if [ -n "$pid" ] && [ "$pid" != "null" ] && [ "$pid" != "0" ]; then
                echo "$pid"
                return 0
            fi
        fi
    fi

    # 尝试 podman
    if command -v podman &>/dev/null; then
        pid=$(podman inspect --format '{{.State.Pid}}' "$input" 2>/dev/null)
        if [ -n "$pid" ] && [ "$pid" != "0" ]; then
            echo "$pid"
            return 0
        fi
    fi

    echo -e "${RED}错误：无法找到容器 '$input'${NC}" >&2
    echo "请确保容器正在运行，或直接提供 PID" >&2
    return 1
}

# 网络调试
debug_network() {
    local pid="$1"
    print_section "网络调试 (Network Namespace)"

    echo -e "${YELLOW}1. 网络接口${NC}"
    echo "$ nsenter -t $pid -n ip addr"
    nsenter -t "$pid" -n ip addr
    echo ""

    echo -e "${YELLOW}2. 路由表${NC}"
    echo "$ nsenter -t $pid -n ip route"
    nsenter -t "$pid" -n ip route
    echo ""

    echo -e "${YELLOW}3. DNS 配置${NC}"
    echo "$ nsenter -t $pid -n cat /etc/resolv.conf"
    nsenter -t "$pid" -m cat /etc/resolv.conf 2>/dev/null || echo "(无法读取)"
    echo ""

    echo -e "${YELLOW}4. 监听端口${NC}"
    echo "$ nsenter -t $pid -n ss -tuln"
    nsenter -t "$pid" -n ss -tuln
    echo ""

    echo -e "${YELLOW}5. 已建立连接${NC}"
    echo "$ nsenter -t $pid -n ss -tun"
    nsenter -t "$pid" -n ss -tun | head -20
    echo ""

    echo -e "${GREEN}网络调试命令提示：${NC}"
    echo "  测试连通性: nsenter -t $pid -n ping -c 3 <target>"
    echo "  HTTP 测试:  nsenter -t $pid -n curl -v <url>"
    echo "  DNS 测试:   nsenter -t $pid -n dig <domain>"
    echo "  抓包:       nsenter -t $pid -n tcpdump -i eth0 -n"
}

# 文件系统调试
debug_mount() {
    local pid="$1"
    print_section "文件系统调试 (Mount Namespace)"

    echo -e "${YELLOW}1. 根目录内容${NC}"
    echo "$ nsenter -t $pid -m ls -la /"
    nsenter -t "$pid" -m ls -la /
    echo ""

    echo -e "${YELLOW}2. 挂载点${NC}"
    echo "$ nsenter -t $pid -m mount | head -20"
    nsenter -t "$pid" -m mount | head -20
    echo ""

    echo -e "${YELLOW}3. 磁盘使用${NC}"
    echo "$ nsenter -t $pid -m df -h"
    nsenter -t "$pid" -m df -h 2>/dev/null || echo "(无法执行 df)"
    echo ""

    echo -e "${GREEN}文件系统调试命令提示：${NC}"
    echo "  查看文件:   nsenter -t $pid -m cat <file>"
    echo "  查找文件:   nsenter -t $pid -m find / -name '<pattern>'"
    echo "  检查日志:   nsenter -t $pid -m tail -f /var/log/<log>"
}

# 进程调试
debug_process() {
    local pid="$1"
    print_section "进程调试 (PID + Mount Namespace)"

    echo -e "${YELLOW}1. 进程列表${NC}"
    echo "$ nsenter -t $pid -p -m ps aux"
    nsenter -t "$pid" -p -m ps aux 2>/dev/null || {
        echo "(需要 --mount-proc，尝试其他方式...)"
        echo ""
        echo "从 /proc/$pid 读取进程信息："
        cat "/proc/$pid/cmdline" | tr '\0' ' '
        echo ""
    }
    echo ""

    echo -e "${YELLOW}2. PID 1 信息（容器主进程）${NC}"
    echo "命令行:"
    nsenter -t "$pid" -m cat /proc/1/cmdline 2>/dev/null | tr '\0' ' '
    echo ""
    echo ""
    echo "状态:"
    nsenter -t "$pid" -m cat /proc/1/status 2>/dev/null | grep -E "^(Name|State|Pid|PPid|Uid|Gid):" || true
    echo ""

    echo -e "${YELLOW}3. 文件描述符${NC}"
    echo "$ nsenter -t $pid -m ls -la /proc/1/fd | head -10"
    nsenter -t "$pid" -m ls -la /proc/1/fd 2>/dev/null | head -10 || echo "(无法读取)"
    echo ""

    echo -e "${GREEN}进程调试命令提示：${NC}"
    echo "  调用栈:     cat /proc/$pid/stack"
    echo "  内存映射:   cat /proc/$pid/maps"
    echo "  环境变量:   nsenter -t $pid -m cat /proc/1/environ | tr '\\0' '\\n'"
}

# Namespace 信息
show_namespace_info() {
    local pid="$1"
    print_section "Namespace 信息"

    echo -e "${YELLOW}进程 $pid 的 Namespace：${NC}"
    ls -la "/proc/$pid/ns/" 2>/dev/null
    echo ""

    echo -e "${YELLOW}Namespace inode 对比（与当前 shell）：${NC}"
    echo ""
    printf "%-15s %-30s %-30s\n" "Namespace" "目标进程" "当前 Shell"
    printf "%-15s %-30s %-30s\n" "---------" "--------" "----------"

    for ns in cgroup ipc mnt net pid user uts; do
        local target_ns current_ns
        target_ns=$(readlink "/proc/$pid/ns/$ns" 2>/dev/null || echo "N/A")
        current_ns=$(readlink "/proc/$$/ns/$ns" 2>/dev/null || echo "N/A")

        if [ "$target_ns" = "$current_ns" ]; then
            printf "%-15s %-30s ${GREEN}%-30s${NC}\n" "$ns" "$target_ns" "(相同)"
        else
            printf "%-15s %-30s ${YELLOW}%-30s${NC}\n" "$ns" "$target_ns" "(不同)"
        fi
    done
}

# 完整调试报告
full_debug() {
    local pid="$1"

    echo "=============================================="
    echo "  nsenter 容器调试报告"
    echo "  目标 PID: $pid"
    echo "  生成时间: $(date)"
    echo "=============================================="

    show_namespace_info "$pid"
    debug_network "$pid"
    debug_mount "$pid"
    debug_process "$pid"

    print_section "进入完整调试 Shell"
    echo -e "${GREEN}运行以下命令进入容器的完整 shell：${NC}"
    echo ""
    echo "  sudo nsenter -t $pid -a /bin/bash"
    echo ""
    echo "或选择性进入："
    echo "  网络:     sudo nsenter -t $pid -n /bin/bash"
    echo "  文件系统: sudo nsenter -t $pid -m /bin/bash"
    echo "  所有:     sudo nsenter -t $pid -a /bin/bash"
}

# 主函数
main() {
    check_root "$@"

    if [ $# -eq 0 ]; then
        usage
    fi

    local target="$1"
    local mode="full"
    shift

    # 解析选项
    while [ $# -gt 0 ]; do
        case "$1" in
            -n|--network)
                mode="network"
                ;;
            -m|--mount)
                mode="mount"
                ;;
            -p|--process)
                mode="process"
                ;;
            -a|--all)
                mode="shell"
                ;;
            -h|--help)
                usage
                ;;
            *)
                echo -e "${RED}未知选项: $1${NC}"
                usage
                ;;
        esac
        shift
    done

    # 获取 PID
    local pid
    pid=$(get_container_pid "$target") || exit 1

    echo -e "${GREEN}目标 PID: $pid${NC}"

    # 执行调试
    case "$mode" in
        network)
            debug_network "$pid"
            ;;
        mount)
            debug_mount "$pid"
            ;;
        process)
            debug_process "$pid"
            ;;
        shell)
            echo "进入完整调试 shell..."
            exec nsenter -t "$pid" -a /bin/bash
            ;;
        full)
            full_debug "$pid"
            ;;
    esac
}

main "$@"
