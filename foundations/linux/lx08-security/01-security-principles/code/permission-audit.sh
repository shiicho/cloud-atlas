#!/bin/bash
# ==============================================================================
# permission-audit.sh - Linux 权限审计脚本
# ==============================================================================
#
# 用于检查系统常见的权限问题和安全配置。
#
# 使用方法:
#   sudo ./permission-audit.sh
#
# 输出:
#   - SUID/SGID 文件列表
#   - 世界可写文件检查
#   - 关键文件权限验证
#   - SELinux 状态
#   - 开放端口列表
#   - 失败登录记录
#
# 注意: 需要 root 权限才能完整运行
#
# ==============================================================================

set -euo pipefail

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 检查是否 root
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo -e "${YELLOW}警告: 建议以 root 权限运行以获取完整结果${NC}"
        echo "使用: sudo $0"
        echo
    fi
}

# 打印标题
print_header() {
    echo "=========================================="
    echo " Linux 权限审计报告"
    echo " 生成时间: $(date '+%Y-%m-%d %H:%M:%S')"
    echo " 主机名: $(hostname)"
    echo " 内核版本: $(uname -r)"
    echo "=========================================="
    echo
}

# 检查 SUID/SGID 文件
check_suid_files() {
    echo "[1] SUID/SGID 文件检查"
    echo "-------------------------------------------"
    echo "SUID 文件允许以文件所有者权限执行，可能被利用提权。"
    echo "SGID 文件允许以文件所属组权限执行。"
    echo

    local count=0
    echo "SUID 文件 (setuid):"
    while IFS= read -r file; do
        if [ -n "$file" ]; then
            echo "  $file"
            ((count++)) || true
        fi
    done < <(find /usr /bin /sbin -perm -4000 -type f 2>/dev/null | head -20)

    if [ $count -eq 0 ]; then
        echo "  (未发现)"
    fi

    echo
    echo "SGID 文件 (setgid):"
    count=0
    while IFS= read -r file; do
        if [ -n "$file" ]; then
            echo "  $file"
            ((count++)) || true
        fi
    done < <(find /usr /bin /sbin -perm -2000 -type f 2>/dev/null | head -10)

    if [ $count -eq 0 ]; then
        echo "  (未发现)"
    fi

    echo
    echo -e "${YELLOW}建议: 确认每个 SUID/SGID 文件是否必要，不需要的可用 chmod -s 移除${NC}"
    echo
}

# 检查世界可写文件
check_world_writable() {
    echo "[2] 世界可写文件检查"
    echo "-------------------------------------------"
    echo "世界可写文件可能被任何用户修改，存在安全风险。"
    echo "排除: /tmp, /var/tmp, /dev"
    echo

    local found=0

    # 检查 /etc 目录
    echo "在 /etc 中的世界可写文件:"
    while IFS= read -r file; do
        if [ -n "$file" ]; then
            echo -e "  ${RED}$file${NC}"
            found=1
        fi
    done < <(find /etc -xdev -type f -perm -0002 2>/dev/null | head -10)

    if [ $found -eq 0 ]; then
        echo -e "  ${GREEN}未发现${NC}"
    fi

    echo

    # 检查 /home 目录
    found=0
    echo "在 /home 中的世界可写文件:"
    while IFS= read -r file; do
        if [ -n "$file" ]; then
            echo -e "  ${RED}$file${NC}"
            found=1
        fi
    done < <(find /home -xdev -type f -perm -0002 2>/dev/null | head -10)

    if [ $found -eq 0 ]; then
        echo -e "  ${GREEN}未发现${NC}"
    fi

    echo
}

# 检查关键文件权限
check_critical_files() {
    echo "[3] 关键文件权限检查"
    echo "-------------------------------------------"

    check_permission() {
        local file=$1
        local expected=$2
        local description=$3

        if [ -f "$file" ]; then
            actual=$(stat -c %a "$file" 2>/dev/null)
            if [ "$actual" = "$expected" ]; then
                echo -e "  ${GREEN}✓${NC} $file: $actual (期望: $expected) - $description"
            else
                echo -e "  ${RED}✗${NC} $file: $actual (期望: $expected) - $description"
            fi
        else
            echo -e "  ${YELLOW}-${NC} $file: 文件不存在"
        fi
    }

    check_permission "/etc/passwd" "644" "用户数据库"
    check_permission "/etc/shadow" "000" "密码哈希"
    check_permission "/etc/group" "644" "组数据库"
    check_permission "/etc/gshadow" "000" "组密码"
    check_permission "/etc/ssh/sshd_config" "600" "SSH 服务配置"
    check_permission "/etc/sudoers" "440" "sudo 配置"
    check_permission "/etc/crontab" "600" "系统 cron"

    echo
}

# 检查无密码用户
check_empty_passwords() {
    echo "[4] 无密码/锁定用户检查"
    echo "-------------------------------------------"

    if [ -r /etc/shadow ]; then
        local found=0
        while IFS=: read -r user pass rest; do
            # 跳过系统账户（通常使用 nologin 或 false）
            shell=$(grep "^$user:" /etc/passwd 2>/dev/null | cut -d: -f7)
            if [[ "$shell" =~ (nologin|false)$ ]]; then
                continue
            fi

            if [ -z "$pass" ]; then
                echo -e "  ${RED}警告: $user 没有设置密码${NC}"
                found=1
            elif [ "$pass" = "!" ] || [ "$pass" = "*" ] || [ "$pass" = "!!" ]; then
                echo -e "  ${YELLOW}信息: $user 账户被锁定${NC}"
            fi
        done < /etc/shadow

        if [ $found -eq 0 ]; then
            echo -e "  ${GREEN}所有可登录用户都设置了密码${NC}"
        fi
    else
        echo "  无法读取 /etc/shadow（需要 root 权限）"
    fi

    echo
}

# 检查 SELinux 状态
check_selinux() {
    echo "[5] SELinux / AppArmor 状态"
    echo "-------------------------------------------"

    if command -v getenforce &>/dev/null; then
        status=$(getenforce)
        case $status in
            Enforcing)
                echo -e "  ${GREEN}✓ SELinux: $status${NC}"
                ;;
            Permissive)
                echo -e "  ${YELLOW}⚠ SELinux: $status (仅记录不强制)${NC}"
                echo "    建议: 生产环境应使用 Enforcing 模式"
                ;;
            Disabled)
                echo -e "  ${RED}✗ SELinux: $status${NC}"
                echo "    警告: SELinux 已禁用，建议启用"
                ;;
        esac

        # 检查配置文件
        if [ -f /etc/selinux/config ]; then
            config_status=$(grep "^SELINUX=" /etc/selinux/config | cut -d= -f2)
            echo "    配置文件设置: $config_status"
        fi
    elif command -v aa-status &>/dev/null; then
        echo "  系统使用 AppArmor（Ubuntu/Debian）"
        if aa-status --enabled 2>/dev/null; then
            echo -e "  ${GREEN}✓ AppArmor: 已启用${NC}"
            # 显示 profile 统计
            aa-status 2>/dev/null | grep -E "profiles|processes" | head -5 | while read line; do
                echo "    $line"
            done
        else
            echo -e "  ${RED}✗ AppArmor: 未启用${NC}"
        fi
    else
        echo "  未检测到 SELinux 或 AppArmor"
    fi

    echo
}

# 检查开放端口
check_listening_ports() {
    echo "[6] 监听端口检查"
    echo "-------------------------------------------"
    echo "显示所有监听的 TCP/UDP 端口:"
    echo

    if command -v ss &>/dev/null; then
        ss -tulpn 2>/dev/null | grep LISTEN | awk '
            BEGIN { printf "  %-10s %-25s %-20s\n", "协议", "监听地址:端口", "进程" }
            BEGIN { printf "  %-10s %-25s %-20s\n", "----", "----------------", "----" }
            {
                proto = $1
                addr = $5
                proc = $7
                # 提取进程名
                gsub(/users:\(\("|",.*/, "", proc)
                printf "  %-10s %-25s %-20s\n", proto, addr, proc
            }
        ' | head -15
    else
        netstat -tulpn 2>/dev/null | grep LISTEN | head -10
    fi

    echo
    echo -e "${YELLOW}建议: 确认每个监听端口是否必要，关闭不需要的服务${NC}"
    echo
}

# 检查失败登录
check_failed_logins() {
    echo "[7] 最近失败登录（最近 10 条）"
    echo "-------------------------------------------"

    local log_file=""
    if [ -f /var/log/secure ]; then
        log_file="/var/log/secure"
    elif [ -f /var/log/auth.log ]; then
        log_file="/var/log/auth.log"
    fi

    if [ -n "$log_file" ] && [ -r "$log_file" ]; then
        local count=0
        while IFS= read -r line; do
            echo "  $line"
            ((count++)) || true
        done < <(grep -i "failed\|failure\|invalid" "$log_file" 2>/dev/null | tail -10)

        if [ $count -eq 0 ]; then
            echo -e "  ${GREEN}未发现最近的失败登录${NC}"
        else
            echo
            echo -e "${YELLOW}建议: 如果失败登录频繁，考虑配置 Fail2Ban${NC}"
        fi
    else
        echo "  无法读取认证日志（需要 root 权限或日志不存在）"
    fi

    echo
}

# 检查 sudo 配置
check_sudo_config() {
    echo "[8] sudo 配置检查"
    echo "-------------------------------------------"

    # 检查 NOPASSWD 配置
    echo "NOPASSWD 配置（无需密码的 sudo）:"
    if [ -r /etc/sudoers ]; then
        local found=0
        grep -r "NOPASSWD" /etc/sudoers /etc/sudoers.d/ 2>/dev/null | grep -v "^#" | while read line; do
            echo -e "  ${YELLOW}$line${NC}"
            found=1
        done

        if [ $found -eq 0 ]; then
            echo -e "  ${GREEN}未发现 NOPASSWD 配置${NC}"
        fi
    else
        echo "  无法读取 sudoers 文件（需要 root 权限）"
    fi

    echo
}

# 检查 SSH 配置
check_ssh_config() {
    echo "[9] SSH 配置安全检查"
    echo "-------------------------------------------"

    local sshd_config="/etc/ssh/sshd_config"

    if [ -r "$sshd_config" ]; then
        # 检查关键配置
        check_ssh_setting() {
            local setting=$1
            local safe_value=$2
            local description=$3

            local value=$(grep -E "^${setting}\s+" "$sshd_config" 2>/dev/null | awk '{print $2}' | head -1)

            if [ -z "$value" ]; then
                echo -e "  ${YELLOW}-${NC} $setting: (未设置，使用默认值)"
            elif [ "$value" = "$safe_value" ]; then
                echo -e "  ${GREEN}✓${NC} $setting: $value"
            else
                echo -e "  ${RED}✗${NC} $setting: $value (建议: $safe_value)"
            fi
        }

        check_ssh_setting "PermitRootLogin" "no" "禁止 root 直接登录"
        check_ssh_setting "PasswordAuthentication" "no" "禁用密码认证"
        check_ssh_setting "PermitEmptyPasswords" "no" "禁止空密码"
        check_ssh_setting "X11Forwarding" "no" "禁用 X11 转发"

    else
        echo "  无法读取 SSH 配置文件"
    fi

    echo
}

# 生成摘要
print_summary() {
    echo "=========================================="
    echo " 审计摘要"
    echo "=========================================="
    echo
    echo "本次审计检查了以下项目:"
    echo "  1. SUID/SGID 文件"
    echo "  2. 世界可写文件"
    echo "  3. 关键文件权限"
    echo "  4. 用户密码状态"
    echo "  5. SELinux/AppArmor 状态"
    echo "  6. 监听端口"
    echo "  7. 失败登录记录"
    echo "  8. sudo 配置"
    echo "  9. SSH 配置"
    echo
    echo "后续步骤:"
    echo "  - 修复标记为 ✗ 的问题"
    echo "  - 评估标记为 ⚠ 的警告"
    echo "  - 定期运行此脚本进行检查"
    echo
    echo "=========================================="
    echo " 审计完成: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "=========================================="
}

# 主函数
main() {
    check_root
    print_header
    check_suid_files
    check_world_writable
    check_critical_files
    check_empty_passwords
    check_selinux
    check_listening_ports
    check_failed_logins
    check_sudo_config
    check_ssh_config
    print_summary
}

main "$@"
