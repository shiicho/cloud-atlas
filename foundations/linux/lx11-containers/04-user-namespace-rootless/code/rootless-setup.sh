#!/bin/bash
# =============================================================================
# rootless-setup.sh - Rootless 容器环境配置脚本
# =============================================================================
#
# 用途：配置 subuid/subgid，启用 rootless 容器支持
# 环境：需要 sudo 权限来修改系统配置
#
# 使用方法：
#   sudo ./rootless-setup.sh [username]
#   sudo ./rootless-setup.sh              # 为当前用户配置
#   sudo ./rootless-setup.sh testuser     # 为指定用户配置
#
# 配置内容：
#   1. 检查并启用 user namespaces
#   2. 配置 /etc/subuid
#   3. 配置 /etc/subgid
#   4. 验证配置
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

# 默认配置
DEFAULT_SUBUID_START=100000
DEFAULT_SUBUID_COUNT=65536

print_step() {
    echo -e "${GREEN}[STEP]${NC} $1"
}

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

# 使用说明
usage() {
    echo "用法: $0 [username]"
    echo ""
    echo "参数:"
    echo "  username    要配置的用户名（默认：当前用户）"
    echo ""
    echo "示例:"
    echo "  sudo $0               # 为当前用户配置"
    echo "  sudo $0 testuser      # 为 testuser 配置"
    echo ""
    echo "此脚本将："
    echo "  1. 检查并启用 user namespaces"
    echo "  2. 为用户配置 /etc/subuid"
    echo "  3. 为用户配置 /etc/subgid"
    echo "  4. 验证 rootless 容器支持"
    exit 1
}

# 检查 root 权限
check_root() {
    if [ "$EUID" -ne 0 ]; then
        print_error "需要 root 权限"
        echo "请使用: sudo $0 $*"
        exit 1
    fi
}

# 检查用户存在
check_user() {
    local user="$1"
    if ! id "$user" &>/dev/null; then
        print_error "用户 '$user' 不存在"
        exit 1
    fi
}

# 获取下一个可用的 subuid 范围
get_next_subuid_start() {
    local start=$DEFAULT_SUBUID_START

    if [ -f /etc/subuid ]; then
        # 找到最后一个范围的结束位置
        local last_end=$(awk -F: '{print $2 + $3}' /etc/subuid | sort -n | tail -1)
        if [ -n "$last_end" ] && [ "$last_end" -gt "$start" ]; then
            start=$last_end
        fi
    fi

    echo $start
}

# 步骤 1: 检查并启用 user namespaces
setup_user_namespaces() {
    print_step "检查 User Namespaces 状态..."

    local max_ns=$(cat /proc/sys/user/max_user_namespaces 2>/dev/null)

    if [ -z "$max_ns" ]; then
        print_error "无法读取 user namespace 配置"
        print_info "内核可能不支持 user namespaces"
        return 1
    fi

    if [ "$max_ns" = "0" ]; then
        print_warning "User Namespaces 未启用 (max_user_namespaces = 0)"
        print_info "正在启用..."

        # 创建 sysctl 配置
        echo "user.max_user_namespaces = 15000" > /etc/sysctl.d/99-userns.conf
        sysctl -p /etc/sysctl.d/99-userns.conf

        # 验证
        max_ns=$(cat /proc/sys/user/max_user_namespaces)
        if [ "$max_ns" != "0" ]; then
            print_success "User Namespaces 已启用 (max = $max_ns)"
        else
            print_error "启用 User Namespaces 失败"
            return 1
        fi
    else
        print_success "User Namespaces 已启用 (max = $max_ns)"
    fi
}

# 步骤 2: 配置 subuid
setup_subuid() {
    local user="$1"
    print_step "配置 /etc/subuid..."

    # 检查是否已配置
    if [ -f /etc/subuid ] && grep -q "^$user:" /etc/subuid; then
        local current=$(grep "^$user:" /etc/subuid)
        print_info "用户 '$user' 已有 subuid 配置: $current"
        read -p "是否覆盖？(y/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_info "保留现有配置"
            return 0
        fi
        # 删除旧配置
        sed -i "/^$user:/d" /etc/subuid
    fi

    # 获取下一个可用范围
    local start=$(get_next_subuid_start)
    local count=$DEFAULT_SUBUID_COUNT

    # 添加配置
    echo "$user:$start:$count" >> /etc/subuid
    print_success "已配置: $user:$start:$count"
}

# 步骤 3: 配置 subgid
setup_subgid() {
    local user="$1"
    print_step "配置 /etc/subgid..."

    # 检查是否已配置
    if [ -f /etc/subgid ] && grep -q "^$user:" /etc/subgid; then
        local current=$(grep "^$user:" /etc/subgid)
        print_info "用户 '$user' 已有 subgid 配置: $current"
        read -p "是否覆盖？(y/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_info "保留现有配置"
            return 0
        fi
        # 删除旧配置
        sed -i "/^$user:/d" /etc/subgid
    fi

    # 使用与 subuid 相同的范围
    local start=$(grep "^$user:" /etc/subuid | cut -d: -f2)
    local count=$DEFAULT_SUBUID_COUNT

    # 添加配置
    echo "$user:$start:$count" >> /etc/subgid
    print_success "已配置: $user:$start:$count"
}

# 步骤 4: 验证配置
verify_setup() {
    local user="$1"
    print_step "验证配置..."

    echo ""
    echo "/etc/subuid 内容："
    grep "^$user:" /etc/subuid || print_warning "未找到 $user 的 subuid 配置"

    echo ""
    echo "/etc/subgid 内容："
    grep "^$user:" /etc/subgid || print_warning "未找到 $user 的 subgid 配置"

    echo ""
    echo "newuidmap 和 newgidmap 权限："
    ls -la /usr/bin/newuidmap /usr/bin/newgidmap 2>/dev/null || print_warning "工具未安装"

    echo ""

    # 检查 setuid 位
    if [ -f /usr/bin/newuidmap ]; then
        if [ -u /usr/bin/newuidmap ]; then
            print_success "newuidmap 有 setuid 位"
        else
            print_warning "newuidmap 缺少 setuid 位，可能需要: chmod u+s /usr/bin/newuidmap"
        fi
    fi

    if [ -f /usr/bin/newgidmap ]; then
        if [ -u /usr/bin/newgidmap ]; then
            print_success "newgidmap 有 setuid 位"
        else
            print_warning "newgidmap 缺少 setuid 位，可能需要: chmod u+s /usr/bin/newgidmap"
        fi
    fi
}

# 步骤 5: 测试 User Namespace
test_user_namespace() {
    local user="$1"
    print_step "测试 User Namespace..."

    echo ""
    print_info "以 $user 身份测试 unshare..."

    # 切换到目标用户执行测试
    if su - "$user" -c "unshare --user --map-root-user id" 2>/dev/null; then
        print_success "User Namespace 测试通过！"
    else
        print_warning "User Namespace 测试失败"
        print_info "可能需要重新登录或等待系统更新"
    fi
}

# 显示后续步骤
show_next_steps() {
    local user="$1"

    echo ""
    echo "=============================================="
    echo "  配置完成"
    echo "=============================================="
    echo ""
    echo "后续步骤："
    echo ""
    echo "1. 用户 $user 需要重新登录以使配置生效"
    echo ""
    echo "2. 如果使用 Podman，运行："
    echo "   podman system migrate"
    echo ""
    echo "3. 测试 rootless 容器："
    echo "   podman run --rm alpine id"
    echo ""
    echo "4. 验证 UID 映射："
    echo "   podman run -d --name test alpine sleep 300"
    echo "   PID=\$(podman inspect --format '{{.State.Pid}}' test)"
    echo "   cat /proc/\$PID/uid_map"
    echo "   podman rm -f test"
    echo ""
}

# 主函数
main() {
    check_root "$@"

    # 解析参数
    local target_user="${1:-${SUDO_USER:-$(whoami)}}"

    if [ "$target_user" = "root" ]; then
        print_error "不应该为 root 用户配置 rootless 容器"
        print_info "请指定普通用户: sudo $0 <username>"
        exit 1
    fi

    echo "=============================================="
    echo "  Rootless 容器环境配置"
    echo "  目标用户: $target_user"
    echo "  时间: $(date)"
    echo "=============================================="
    echo ""

    # 检查用户存在
    check_user "$target_user"

    # 执行配置步骤
    setup_user_namespaces
    setup_subuid "$target_user"
    setup_subgid "$target_user"
    verify_setup "$target_user"
    test_user_namespace "$target_user"
    show_next_steps "$target_user"
}

main "$@"
