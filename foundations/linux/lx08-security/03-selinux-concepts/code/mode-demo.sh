#!/bin/bash
# =============================================================================
# mode-demo.sh - SELinux 模式演示脚本
# =============================================================================
#
# 用途：演示 SELinux 三种模式的区别，展示切换方法（不实际切换）
# 适用：RHEL/CentOS/Rocky/Alma/Fedora 等使用 SELinux 的发行版
#
# 使用方法：
#   bash mode-demo.sh          # 演示模式（只展示信息）
#   bash mode-demo.sh --live   # 实际切换模式（需要 root）
#
# =============================================================================

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# 分隔线
print_header() {
    echo ""
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║                  SELinux 模式演示                                  ║${NC}"
    echo -e "${CYAN}║               cloud-atlas / LX08-SECURITY                         ║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════════╝${NC}"
}

print_separator() {
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════════${NC}"
}

# 检查 SELinux 是否可用
check_selinux() {
    if ! command -v getenforce &> /dev/null; then
        echo -e "${RED}错误: SELinux 未安装或不可用${NC}"
        echo "此脚本适用于 RHEL/CentOS/Rocky/Alma/Fedora 等发行版"
        exit 1
    fi
}

# 显示当前状态
show_current_status() {
    print_separator "当前 SELinux 状态"

    local current_mode=$(getenforce 2>/dev/null || echo "Unknown")
    local config_mode=$(grep "^SELINUX=" /etc/selinux/config 2>/dev/null | cut -d= -f2 || echo "unknown")

    echo -e "${YELLOW}运行时模式 (getenforce):${NC}"
    case "$current_mode" in
        Enforcing)
            echo -e "  ${GREEN}●${NC} ${GREEN}$current_mode${NC}"
            echo "     策略强制执行中 - 违规操作会被阻止"
            ;;
        Permissive)
            echo -e "  ${YELLOW}●${NC} ${YELLOW}$current_mode${NC}"
            echo "     调试模式 - 违规操作只记录不阻止"
            ;;
        Disabled)
            echo -e "  ${RED}●${NC} ${RED}$current_mode${NC}"
            echo "     已禁用 - 没有保护！"
            ;;
        *)
            echo "  $current_mode"
            ;;
    esac

    echo ""
    echo -e "${YELLOW}配置文件模式 (/etc/selinux/config):${NC}"
    echo "  $config_mode"

    if [ "$current_mode" != "Disabled" ] && [ "$current_mode" != "$config_mode" ]; then
        echo ""
        echo -e "${YELLOW}注意:${NC} 运行时模式与配置文件不同"
        echo "       重启后将恢复为配置文件设置: $config_mode"
    fi
}

# 演示三种模式
demo_modes() {
    print_separator "SELinux 三种模式详解"

    echo ""
    echo -e "${GREEN}${BOLD}1. Enforcing (强制模式)${NC}"
    echo "   ┌─────────────────────────────────────────────────────────────┐"
    echo "   │ 状态: 策略完全生效                                          │"
    echo "   │ 行为: 违规操作被阻止，并记录到 audit 日志                   │"
    echo "   │ 用途: 生产环境的唯一正确选择                                │"
    echo "   │                                                             │"
    echo "   │ 示例:                                                       │"
    echo "   │   httpd_t 尝试读取 user_home_t → 阻止 + 记录               │"
    echo "   └─────────────────────────────────────────────────────────────┘"

    echo ""
    echo -e "${YELLOW}${BOLD}2. Permissive (宽容模式)${NC}"
    echo "   ┌─────────────────────────────────────────────────────────────┐"
    echo "   │ 状态: 策略不强制执行，但仍然记录                            │"
    echo "   │ 行为: 违规操作被允许，但写入日志供分析                      │"
    echo "   │ 用途: 调试排错时临时使用                                    │"
    echo "   │                                                             │"
    echo "   │ 示例:                                                       │"
    echo "   │   httpd_t 尝试读取 user_home_t → 允许 + 记录               │"
    echo "   │                                                             │"
    echo "   │ ⚠️  仅用于调试！排错完成后必须恢复 Enforcing                │"
    echo "   └─────────────────────────────────────────────────────────────┘"

    echo ""
    echo -e "${RED}${BOLD}3. Disabled (禁用模式)${NC}"
    echo "   ┌─────────────────────────────────────────────────────────────┐"
    echo "   │ 状态: SELinux 完全关闭                                      │"
    echo "   │ 行为: 没有保护，没有日志                                    │"
    echo "   │ 用途: ❌ 永远不要使用！                                     │"
    echo "   │                                                             │"
    echo "   │ 问题:                                                       │"
    echo "   │   - 系统失去 MAC 保护层                                     │"
    echo "   │   - 重新启用需要完整 relabel（可能耗时数小时）              │"
    echo "   │   - 安全审计立即失败                                        │"
    echo "   └─────────────────────────────────────────────────────────────┘"
}

# 演示模式切换命令
demo_commands() {
    print_separator "模式切换命令参考"

    echo ""
    echo -e "${YELLOW}临时切换 (setenforce):${NC}"
    echo "  重启后失效，只能在 Enforcing ↔ Permissive 之间切换"
    echo ""
    echo "  # 切换到 Permissive（调试用）"
    echo -e "  ${CYAN}sudo setenforce 0${NC}"
    echo ""
    echo "  # 切换回 Enforcing"
    echo -e "  ${CYAN}sudo setenforce 1${NC}"
    echo ""
    echo "  # 查看当前模式"
    echo -e "  ${CYAN}getenforce${NC}"

    echo ""
    echo -e "${YELLOW}永久配置 (/etc/selinux/config):${NC}"
    echo "  修改后需要重启才生效"
    echo ""
    echo "  # 编辑配置文件"
    echo -e "  ${CYAN}sudo vim /etc/selinux/config${NC}"
    echo ""
    echo "  # 设置为 Enforcing（推荐）"
    echo "  SELINUX=enforcing"
    echo ""
    echo "  # 设置为 Permissive（仅调试）"
    echo "  SELINUX=permissive"
    echo ""
    echo -e "  ${RED}# 永远不要这样做！${NC}"
    echo -e "  ${RED}SELINUX=disabled${NC}"
}

# 模式切换实战演示（实际切换）
live_demo() {
    print_separator "实时模式切换演示"

    # 检查是否有 root 权限
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}需要 root 权限运行实时演示${NC}"
        echo "请使用: sudo bash mode-demo.sh --live"
        return 1
    fi

    local original_mode=$(getenforce)
    echo -e "原始模式: ${GREEN}$original_mode${NC}"
    echo ""

    if [ "$original_mode" = "Disabled" ]; then
        echo -e "${RED}SELinux 已禁用，无法进行切换演示${NC}"
        echo "需要先在 /etc/selinux/config 中启用，然后重启系统"
        return 1
    fi

    echo "演示步骤："
    echo ""

    # 步骤 1：如果是 Enforcing，切换到 Permissive
    if [ "$original_mode" = "Enforcing" ]; then
        echo "1. 切换到 Permissive 模式..."
        setenforce 0
        echo -e "   当前模式: ${YELLOW}$(getenforce)${NC}"
        sleep 1

        echo ""
        echo "2. 恢复到 Enforcing 模式..."
        setenforce 1
        echo -e "   当前模式: ${GREEN}$(getenforce)${NC}"
    else
        # 如果是 Permissive，切换到 Enforcing
        echo "1. 切换到 Enforcing 模式..."
        setenforce 1
        echo -e "   当前模式: ${GREEN}$(getenforce)${NC}"
        sleep 1

        echo ""
        echo "2. 恢复到原始模式 ($original_mode)..."
        setenforce 0
        echo -e "   当前模式: ${YELLOW}$(getenforce)${NC}"
    fi

    echo ""
    echo -e "${GREEN}演示完成！${NC}"
    echo "最终模式: $(getenforce)"
}

# 显示最佳实践
show_best_practices() {
    print_separator "SELinux 最佳实践"

    echo ""
    echo -e "${GREEN}✓ 正确做法:${NC}"
    echo "  1. 生产环境始终保持 Enforcing 模式"
    echo "  2. 排错时临时使用 Permissive，完成后立即恢复"
    echo "  3. 查看 audit 日志理解拒绝原因"
    echo "  4. 使用 setsebool、semanage 解决问题"
    echo ""

    echo -e "${RED}✗ 错误做法:${NC}"
    echo "  1. setenforce 0 作为「解决方案」"
    echo "  2. 在配置文件中设置 SELINUX=disabled"
    echo "  3. 不看日志就放弃"
    echo "  4. 遇到问题第一反应是关闭 SELinux"
    echo ""

    echo -e "${YELLOW}调试工作流:${NC}"
    echo "  ┌─────────────────────────────────────────────────────────────┐"
    echo "  │  1. 遇到 SELinux 拒绝                                       │"
    echo "  │        ↓                                                    │"
    echo "  │  2. sudo setenforce 0  (临时切换 Permissive)                │"
    echo "  │        ↓                                                    │"
    echo "  │  3. 查看日志: ausearch -m avc -ts recent                    │"
    echo "  │        ↓                                                    │"
    echo "  │  4. 分析原因: audit2why                                     │"
    echo "  │        ↓                                                    │"
    echo "  │  5. 应用修复: setsebool -P 或 semanage fcontext             │"
    echo "  │        ↓                                                    │"
    echo "  │  6. sudo setenforce 1  (恢复 Enforcing)                     │"
    echo "  │        ↓                                                    │"
    echo "  │  7. 验证问题解决                                            │"
    echo "  └─────────────────────────────────────────────────────────────┘"
}

# 主函数
main() {
    print_header
    check_selinux

    if [ "$1" = "--live" ]; then
        show_current_status
        live_demo
    else
        show_current_status
        demo_modes
        demo_commands
        show_best_practices

        echo ""
        echo -e "${CYAN}═══════════════════════════════════════════════════════════════════${NC}"
        echo ""
        echo "提示："
        echo "  - 这是演示模式，未实际切换 SELinux 模式"
        echo "  - 使用 'bash mode-demo.sh --live' 进行实际切换演示（需要 root）"
        echo "  - 下一课 (04-selinux-troubleshooting) 将学习如何排查 SELinux 问题"
        echo ""
    fi
}

# 运行
main "$@"
