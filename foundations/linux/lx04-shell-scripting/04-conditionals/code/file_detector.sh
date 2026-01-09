#!/bin/bash
# =============================================================================
# 脚本名称: file_detector.sh
# 功能说明: 检测文件类型并报告详细信息（Mini Project 参考实现）
# 作者: Cloud Atlas
# 创建日期: 2026-01-10
# =============================================================================
#
# 使用方法:
#   ./file_detector.sh <文件路径>
#   ./file_detector.sh /etc/passwd
#   ./file_detector.sh /etc
#
# 功能:
#   - 检测文件类型（普通文件、目录、链接等）
#   - 报告权限信息（可读/可写/可执行）
#   - 显示文件大小和所有者
#   - 对于文本文件显示行数
#
# =============================================================================

# 颜色定义（用于终端输出美化）
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 打印带颜色的消息
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 显示用法
usage() {
    echo "用法: $0 <文件路径>"
    echo ""
    echo "示例:"
    echo "  $0 /etc/passwd"
    echo "  $0 /etc"
    echo "  $0 /bin/bash"
    exit 1
}

# 检查权限
# 参数: $1 - 目标路径
# 返回: 权限描述字符串
check_permissions() {
    local target="$1"
    local perms=""

    [[ -r "$target" ]] && perms+="可读 "
    [[ -w "$target" ]] && perms+="可写 "
    [[ -x "$target" ]] && perms+="可执行 "

    if [[ -z "$perms" ]]; then
        echo "无权限"
    else
        echo "$perms"
    fi
}

# 获取文件大小（跨平台兼容）
# 参数: $1 - 目标路径
# 返回: 文件大小（字节）
get_size() {
    local target="$1"
    if stat --version &>/dev/null; then
        # GNU stat (Linux)
        stat -c %s "$target" 2>/dev/null
    else
        # BSD stat (macOS)
        stat -f %z "$target" 2>/dev/null
    fi
}

# 检测文件类型
# 参数: $1 - 目标路径
# 返回: 文件类型描述
detect_file_type() {
    local target="$1"

    # 注意检测顺序：先检测链接，因为链接可能指向文件或目录
    if [[ -L "$target" ]]; then
        echo "符号链接"
    elif [[ -f "$target" ]]; then
        echo "普通文件"
    elif [[ -d "$target" ]]; then
        echo "目录"
    elif [[ -b "$target" ]]; then
        echo "块设备"
    elif [[ -c "$target" ]]; then
        echo "字符设备"
    elif [[ -p "$target" ]]; then
        echo "命名管道"
    elif [[ -S "$target" ]]; then
        echo "套接字"
    else
        echo "未知类型"
    fi
}

# 主函数
main() {
    # 检查参数
    if [[ $# -lt 1 ]]; then
        print_error "缺少文件路径参数"
        usage
    fi

    local target="$1"

    echo "============================================"
    echo "         文件类型检测报告"
    echo "============================================"
    echo ""

    # 检查目标是否存在（-e 不检测失效链接，所以也检测 -L）
    if [[ ! -e "$target" && ! -L "$target" ]]; then
        print_error "目标不存在: $target"
        exit 1
    fi

    echo "目标路径: $target"
    echo ""

    # 获取文件类型
    local file_type
    file_type=$(detect_file_type "$target")
    print_info "文件类型: $file_type"

    # 根据类型显示不同的详细信息
    case "$file_type" in
        "普通文件")
            # 显示文件大小
            local size
            size=$(get_size "$target")
            print_info "文件大小: $size 字节"

            # 如果是文本文件，显示行数
            if file "$target" 2>/dev/null | grep -q "text"; then
                local lines
                lines=$(wc -l < "$target")
                print_info "文件行数: $lines"
            fi
            ;;
        "目录")
            # 显示目录中的项目数
            local count
            count=$(ls -1A "$target" 2>/dev/null | wc -l)
            print_info "包含项目: $count 个"
            ;;
        "符号链接")
            # 显示链接目标
            local link_target
            link_target=$(readlink "$target")
            print_info "链接目标: $link_target"

            # 检查链接是否有效
            if [[ -e "$target" ]]; then
                print_success "链接有效"
            else
                print_warning "链接失效（目标不存在）"
            fi
            ;;
    esac

    # 权限信息
    echo ""
    print_info "权限状态: $(check_permissions "$target")"

    # 所有者信息（跨平台）
    if stat --version &>/dev/null; then
        # GNU stat (Linux)
        print_info "所有者: $(stat -c '%U:%G' "$target" 2>/dev/null)"
        print_info "权限位: $(stat -c '%a' "$target" 2>/dev/null)"
    else
        # BSD stat (macOS)
        print_info "所有者: $(stat -f '%Su:%Sg' "$target" 2>/dev/null)"
        print_info "权限位: $(stat -f '%Lp' "$target" 2>/dev/null)"
    fi

    echo ""
    echo "============================================"
}

# 执行主函数，传入所有参数
main "$@"
