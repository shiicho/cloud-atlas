#!/bin/bash
# =============================================================================
# uid-mapping-demo.sh - User Namespace UID 映射演示
# =============================================================================
#
# 用途：演示 User Namespace 的 UID 映射机制
# 环境：普通用户即可运行（部分功能需要 root）
#
# 使用方法：
#   ./uid-mapping-demo.sh
#
# 演示内容：
#   1. 创建 User Namespace 并成为 "root"
#   2. 显示 UID 映射
#   3. 证明这个 "root" 的权限有限
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

print_step() {
    echo -e "${GREEN}>>> $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}警告: $1${NC}"
}

print_error() {
    echo -e "${RED}错误: $1${NC}"
}

# 检查命令是否存在
check_command() {
    if ! command -v "$1" &>/dev/null; then
        print_error "命令 '$1' 未安装"
        return 1
    fi
}

# 演示 1：基础 User Namespace
demo_basic_user_namespace() {
    print_section "演示 1：基础 User Namespace"

    echo "当前身份（宿主机）："
    echo "$ id"
    id
    echo ""

    print_step "创建 User Namespace 并映射为 root..."
    echo ""
    echo "执行命令："
    echo '$ unshare --user --map-root-user /bin/bash -c "id && cat /proc/self/uid_map"'
    echo ""
    echo "输出："

    unshare --user --map-root-user /bin/bash -c "
        echo '容器内身份:'
        id
        echo ''
        echo 'UID 映射 (/proc/self/uid_map):'
        cat /proc/self/uid_map
        echo ''
        echo '解读: 容器内 UID 0 = 宿主机 UID $(cat /proc/self/uid_map | awk '{print \$2}')'
    " 2>/dev/null || {
        print_warning "需要启用 user namespaces"
        echo "检查: cat /proc/sys/user/max_user_namespaces"
        cat /proc/sys/user/max_user_namespaces 2>/dev/null || echo "无法读取"
    }
}

# 演示 2：权限限制证明
demo_permission_limits() {
    print_section "演示 2：User Namespace 'root' 的权限限制"

    print_step "在 User Namespace 内尝试特权操作..."
    echo ""

    unshare --user --map-root-user /bin/bash -c "
        echo '容器内身份:'
        id
        echo ''

        echo '尝试读取 /etc/shadow...'
        cat /etc/shadow 2>&1 | head -1 || true
        echo ''

        echo '尝试在 /etc 创建文件...'
        touch /etc/test_file 2>&1 || true
        echo ''

        echo '尝试挂载 proc...'
        mkdir -p /tmp/test_proc 2>/dev/null
        mount -t proc proc /tmp/test_proc 2>&1 || true
        echo ''

        echo '结论: 虽然 id 显示 root，但实际权限非常有限！'
    " 2>/dev/null || print_warning "User Namespace 可能未启用"
}

# 演示 3：从宿主机视角观察
demo_host_perspective() {
    print_section "演示 3：从宿主机视角观察"

    print_step "启动一个后台进程在 User Namespace 中..."

    # 创建后台进程
    unshare --user --map-root-user /bin/bash -c "
        echo \$\$ > /tmp/userns_demo_pid
        sleep 30
    " &

    sleep 1

    if [ -f /tmp/userns_demo_pid ]; then
        local inner_pid=$(cat /tmp/userns_demo_pid)
        local bg_pid=$!

        echo ""
        echo "后台进程信息："
        echo "  内部 PID: $inner_pid"
        echo "  宿主机 PID: $bg_pid"
        echo ""

        echo "宿主机看到的进程信息："
        echo "$ ps -p $bg_pid -o pid,uid,user,cmd"
        ps -p $bg_pid -o pid,uid,user,cmd 2>/dev/null || echo "(进程可能已结束)"
        echo ""

        echo "UID 映射:"
        echo "$ cat /proc/$bg_pid/uid_map"
        cat /proc/$bg_pid/uid_map 2>/dev/null || echo "(无法读取)"
        echo ""

        # 清理
        kill $bg_pid 2>/dev/null || true
        rm -f /tmp/userns_demo_pid

        echo -e "${GREEN}结论: 容器内的 'root' (UID 0) 在宿主机上是普通用户！${NC}"
    else
        print_warning "无法创建后台进程"
    fi
}

# 演示 4：检查 subuid/subgid 配置
demo_subuid_check() {
    print_section "演示 4：检查 subuid/subgid 配置"

    local user=$(whoami)

    echo "当前用户: $user"
    echo ""

    echo "/etc/subuid 内容："
    if [ -f /etc/subuid ]; then
        cat /etc/subuid
        echo ""

        if grep -q "^$user:" /etc/subuid; then
            echo -e "${GREEN}$user 已配置 subuid${NC}"
            grep "^$user:" /etc/subuid
        else
            echo -e "${YELLOW}$user 未配置 subuid${NC}"
            echo "配置方法:"
            echo "  sudo usermod --add-subuids 100000-165535 $user"
        fi
    else
        echo -e "${RED}/etc/subuid 文件不存在${NC}"
    fi

    echo ""

    echo "/etc/subgid 内容："
    if [ -f /etc/subgid ]; then
        cat /etc/subgid
        echo ""

        if grep -q "^$user:" /etc/subgid; then
            echo -e "${GREEN}$user 已配置 subgid${NC}"
            grep "^$user:" /etc/subgid
        else
            echo -e "${YELLOW}$user 未配置 subgid${NC}"
            echo "配置方法:"
            echo "  sudo usermod --add-subgids 100000-165535 $user"
        fi
    else
        echo -e "${RED}/etc/subgid 文件不存在${NC}"
    fi
}

# 演示 5：User Namespace 启用状态
demo_userns_status() {
    print_section "演示 5：系统 User Namespace 状态"

    echo "User Namespace 最大数量："
    echo "$ cat /proc/sys/user/max_user_namespaces"
    local max_ns=$(cat /proc/sys/user/max_user_namespaces 2>/dev/null)
    echo "$max_ns"
    echo ""

    if [ "$max_ns" = "0" ]; then
        echo -e "${RED}User Namespace 未启用！${NC}"
        echo ""
        echo "启用方法（需要 root）："
        echo "  echo 'user.max_user_namespaces = 15000' | sudo tee /etc/sysctl.d/userns.conf"
        echo "  sudo sysctl -p /etc/sysctl.d/userns.conf"
    else
        echo -e "${GREEN}User Namespace 已启用 (最大 $max_ns 个)${NC}"
    fi

    echo ""
    echo "当前 User Namespace 数量："
    echo "$ lsns -t user 2>/dev/null | wc -l"
    lsns -t user 2>/dev/null | wc -l || echo "需要 root 权限或 lsns 未安装"
}

# 主函数
main() {
    echo "=============================================="
    echo "  User Namespace UID 映射演示"
    echo "  运行用户: $(whoami)"
    echo "  时间: $(date)"
    echo "=============================================="

    # 检查必要命令
    check_command unshare || exit 1

    # 运行演示
    demo_basic_user_namespace
    demo_permission_limits
    demo_host_perspective
    demo_subuid_check
    demo_userns_status

    print_section "总结"
    echo "关键要点："
    echo "  1. User Namespace 创建独立的 UID 空间"
    echo "  2. 容器内 UID 0 ≠ 宿主机 UID 0"
    echo "  3. 即使是 'root'，也无法访问宿主机特权资源"
    echo "  4. subuid/subgid 定义可用的 UID 映射范围"
    echo ""
    echo "这就是 rootless 容器的安全基础！"
}

main "$@"
