#!/bin/bash
# =============================================================================
# context-viewer.sh - SELinux 上下文查看器
# =============================================================================
#
# 用途：快速查看系统各处的 SELinux 安全上下文
# 适用：RHEL/CentOS/Rocky/Alma/Fedora 等使用 SELinux 的发行版
#
# 使用方法：
#   bash context-viewer.sh
#
# =============================================================================

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 分隔线
print_separator() {
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  $1${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════════${NC}"
}

# 检查 SELinux 是否可用
check_selinux() {
    if ! command -v getenforce &> /dev/null; then
        echo -e "${RED}错误: SELinux 未安装或不可用${NC}"
        echo "此脚本适用于 RHEL/CentOS/Rocky/Alma/Fedora 等发行版"
        exit 1
    fi

    local mode=$(getenforce 2>/dev/null)
    if [ "$mode" = "Disabled" ]; then
        echo -e "${RED}警告: SELinux 已禁用${NC}"
        echo "上下文信息可能不可用"
        echo ""
    fi
}

# 显示 SELinux 状态
show_selinux_status() {
    print_separator "SELinux 状态"

    echo -e "${YELLOW}当前模式:${NC}"
    local mode=$(getenforce 2>/dev/null || echo "Unknown")
    case "$mode" in
        Enforcing)
            echo -e "  ${GREEN}$mode${NC} - 策略强制执行中"
            ;;
        Permissive)
            echo -e "  ${YELLOW}$mode${NC} - 仅记录不阻止（调试模式）"
            ;;
        Disabled)
            echo -e "  ${RED}$mode${NC} - SELinux 已禁用（不推荐！）"
            ;;
        *)
            echo -e "  $mode"
            ;;
    esac

    echo ""
    echo -e "${YELLOW}详细状态 (sestatus):${NC}"
    sestatus 2>/dev/null || echo "  无法获取 sestatus"
}

# 显示文件上下文
show_file_contexts() {
    print_separator "文件上下文示例"

    echo -e "${YELLOW}系统关键文件:${NC}"
    for file in /etc/passwd /etc/shadow /etc/ssh/sshd_config; do
        if [ -e "$file" ]; then
            echo -n "  "
            ls -Z "$file" 2>/dev/null || echo "$file: 无法读取"
        fi
    done

    echo ""
    echo -e "${YELLOW}Web 服务目录:${NC}"
    if [ -d /var/www/html ]; then
        echo -n "  "
        ls -Zd /var/www/html 2>/dev/null
    else
        echo "  /var/www/html 不存在"
    fi

    echo ""
    echo -e "${YELLOW}用户目录:${NC}"
    echo -n "  "
    ls -Zd ~ 2>/dev/null || echo "无法读取主目录"
    echo -n "  "
    ls -Zd /tmp 2>/dev/null || echo "无法读取 /tmp"

    echo ""
    echo -e "${YELLOW}日志目录:${NC}"
    if [ -d /var/log ]; then
        echo -n "  "
        ls -Zd /var/log 2>/dev/null
        echo -n "  "
        ls -Z /var/log/messages 2>/dev/null || ls -Z /var/log/syslog 2>/dev/null || echo "  日志文件不可读"
    fi
}

# 显示进程上下文
show_process_contexts() {
    print_separator "进程上下文示例"

    echo -e "${YELLOW}系统服务进程:${NC}"

    # SSH 服务
    local sshd_ctx=$(ps auxZ 2>/dev/null | grep -E 'sshd.*-D' | head -1)
    if [ -n "$sshd_ctx" ]; then
        echo -e "  ${GREEN}SSH 服务 (sshd):${NC}"
        echo "  $sshd_ctx" | awk '{print "    上下文: " $1; print "    用户: " $2; print "    PID: " $3}'
    else
        echo "  sshd: 未运行或无法读取"
    fi

    echo ""

    # HTTP 服务
    local httpd_ctx=$(ps auxZ 2>/dev/null | grep -E 'httpd|nginx' | head -1)
    if [ -n "$httpd_ctx" ]; then
        echo -e "  ${GREEN}Web 服务 (httpd/nginx):${NC}"
        echo "  $httpd_ctx" | awk '{print "    上下文: " $1; print "    用户: " $2; print "    PID: " $3}'
    else
        echo "  httpd/nginx: 未运行"
    fi

    echo ""

    # systemd
    local systemd_ctx=$(ps auxZ 2>/dev/null | grep -E '/usr/lib/systemd/systemd$' | head -1)
    if [ -n "$systemd_ctx" ]; then
        echo -e "  ${GREEN}systemd:${NC}"
        echo "  $systemd_ctx" | awk '{print "    上下文: " $1; print "    用户: " $2; print "    PID: " $3}'
    fi
}

# 显示用户上下文
show_user_context() {
    print_separator "当前用户上下文"

    echo -e "${YELLOW}你的 SELinux 上下文:${NC}"
    local ctx=$(id -Z 2>/dev/null)
    if [ -n "$ctx" ]; then
        echo "  $ctx"
        echo ""
        echo -e "${YELLOW}上下文解析:${NC}"

        # 解析上下文
        local user=$(echo "$ctx" | cut -d: -f1)
        local role=$(echo "$ctx" | cut -d: -f2)
        local type=$(echo "$ctx" | cut -d: -f3)
        local level=$(echo "$ctx" | cut -d: -f4-)

        echo "  User  (SELinux 用户): $user"
        echo "  Role  (角色):         $role"
        echo "  Type  (类型):         $type"
        echo "  Level (MLS 级别):     $level"

        if [ "$type" = "unconfined_t" ]; then
            echo ""
            echo -e "  ${YELLOW}注意:${NC} unconfined_t 表示此用户不受 SELinux 策略约束"
        fi
    else
        echo "  无法获取用户上下文"
    fi
}

# 显示常见类型说明
show_common_types() {
    print_separator "常见 SELinux 类型参考"

    echo -e "${YELLOW}进程类型:${NC}"
    echo "  httpd_t            - Apache/Nginx Web 服务器进程"
    echo "  sshd_t             - SSH 守护进程"
    echo "  named_t            - DNS 服务 (BIND)"
    echo "  mysqld_t           - MySQL/MariaDB 数据库"
    echo "  container_t        - 容器进程 (Docker/Podman)"
    echo "  unconfined_t       - 不受限制的进程"

    echo ""
    echo -e "${YELLOW}文件类型:${NC}"
    echo "  httpd_sys_content_t - Web 静态内容"
    echo "  httpd_sys_script_exec_t - Web CGI 脚本"
    echo "  user_home_t        - 用户主目录文件"
    echo "  tmp_t              - /tmp 临时文件"
    echo "  var_log_t          - 日志文件"
    echo "  passwd_file_t      - /etc/passwd"
    echo "  shadow_t           - /etc/shadow"
    echo "  sshd_key_t         - SSH 主机密钥"
}

# 主函数
main() {
    echo ""
    echo -e "${GREEN}╔═══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║           SELinux 上下文查看器 (Context Viewer)                   ║${NC}"
    echo -e "${GREEN}║               cloud-atlas / LX08-SECURITY                         ║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════════════════════╝${NC}"

    check_selinux
    show_selinux_status
    show_file_contexts
    show_process_contexts
    show_user_context
    show_common_types

    echo ""
    echo -e "${GREEN}═══════════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}  查看完毕！${NC}"
    echo -e "${GREEN}═══════════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo "提示："
    echo "  - 使用 ls -Z <file> 查看任意文件的上下文"
    echo "  - 使用 ps auxZ | grep <process> 查看特定进程"
    echo "  - 使用 ausearch -m avc -ts recent 查看最近的拒绝日志"
    echo ""
}

# 运行
main
