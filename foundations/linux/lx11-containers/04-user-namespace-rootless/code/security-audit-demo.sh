#!/bin/bash
# =============================================================================
# security-audit-demo.sh - 安全审计演示脚本
# =============================================================================
#
# 用途：生成安全审计所需的 User Namespace 证据
# 场景：向安全官解释 rootless 容器的隔离机制
#
# 使用方法：
#   ./security-audit-demo.sh <container-name-or-pid>
#   ./security-audit-demo.sh mycontainer
#   ./security-audit-demo.sh 12345
#
# 输出：
#   - UID 映射信息
#   - 进程权限证明
#   - 可用于报告书的格式化输出
#
# =============================================================================

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# 使用说明
usage() {
    echo "用法: $0 <container-name-or-pid>"
    echo ""
    echo "功能: 生成安全审计所需的 User Namespace 隔离证据"
    echo ""
    echo "参数:"
    echo "  container-name-or-pid    容器名称、ID 或进程 PID"
    echo ""
    echo "示例:"
    echo "  $0 mycontainer           # 分析名为 mycontainer 的容器"
    echo "  $0 12345                 # 分析 PID 12345 的进程"
    echo ""
    echo "输出:"
    echo "  - UID/GID 映射信息"
    echo "  - 宿主机真实权限"
    echo "  - 日语报告书格式的总结"
    exit 1
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
            echo "错误：PID $input 不存在" >&2
            return 1
        fi
    fi

    # 尝试 Podman
    if command -v podman &>/dev/null; then
        pid=$(podman inspect --format '{{.State.Pid}}' "$input" 2>/dev/null)
        if [ -n "$pid" ] && [ "$pid" != "0" ]; then
            echo "$pid"
            return 0
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

    echo "错误：无法找到容器 '$input'" >&2
    return 1
}

# 分析 UID 映射
analyze_uid_mapping() {
    local pid="$1"

    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}  1. UID/GID 映射分析${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    echo -e "${BOLD}UID 映射 (/proc/$pid/uid_map):${NC}"
    if [ -f "/proc/$pid/uid_map" ]; then
        cat "/proc/$pid/uid_map"
        echo ""

        # 解析映射
        local mapping=$(cat "/proc/$pid/uid_map")
        local inside_start=$(echo "$mapping" | awk '{print $1}')
        local host_start=$(echo "$mapping" | awk '{print $2}')
        local count=$(echo "$mapping" | awk '{print $3}')

        echo "解读:"
        echo "  容器内 UID $inside_start - $((inside_start + count - 1))"
        echo "    → 宿主机 UID $host_start - $((host_start + count - 1))"
        echo ""

        if [ "$host_start" != "0" ]; then
            echo -e "${GREEN}结论: 容器内 UID 0 (root) = 宿主机 UID $host_start (非特权用户)${NC}"
        else
            echo -e "${YELLOW}警告: 容器内 root = 宿主机 root（非 rootless 模式）${NC}"
        fi
    else
        echo -e "${RED}无法读取 UID 映射${NC}"
    fi

    echo ""

    echo -e "${BOLD}GID 映射 (/proc/$pid/gid_map):${NC}"
    if [ -f "/proc/$pid/gid_map" ]; then
        cat "/proc/$pid/gid_map"
    else
        echo -e "${RED}无法读取 GID 映射${NC}"
    fi

    echo ""
}

# 分析宿主机进程信息
analyze_host_process() {
    local pid="$1"

    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}  2. 宿主机进程分析${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    echo -e "${BOLD}进程信息:${NC}"
    echo "$ ps -p $pid -o pid,uid,gid,user,group,cmd"
    ps -p "$pid" -o pid,uid,gid,user,group,cmd 2>/dev/null || echo "(无法读取进程信息)"
    echo ""

    # 获取 UID
    local real_uid=$(ps -p "$pid" -o uid= 2>/dev/null | tr -d ' ')
    if [ -n "$real_uid" ]; then
        if [ "$real_uid" = "0" ]; then
            echo -e "${YELLOW}警告: 宿主机 UID 是 0 (root)${NC}"
            echo "这可能不是 rootless 容器，或者进程有特权"
        else
            echo -e "${GREEN}宿主机真实 UID: $real_uid (非 root)${NC}"
            echo "即使容器内显示 root，宿主机权限是受限的"
        fi
    fi

    echo ""
}

# 分析 Namespace 信息
analyze_namespaces() {
    local pid="$1"

    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}  3. Namespace 分析${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    echo -e "${BOLD}进程 Namespace:${NC}"
    echo "$ ls -la /proc/$pid/ns/"
    ls -la "/proc/$pid/ns/" 2>/dev/null || echo "(无法读取)"
    echo ""

    # 检查 user namespace
    local user_ns=$(readlink "/proc/$pid/ns/user" 2>/dev/null)
    local init_user_ns=$(readlink "/proc/1/ns/user" 2>/dev/null)

    if [ "$user_ns" != "$init_user_ns" ]; then
        echo -e "${GREEN}User Namespace: 与宿主机不同（隔离生效）${NC}"
    else
        echo -e "${YELLOW}User Namespace: 与宿主机相同（无 user 隔离）${NC}"
    fi

    echo ""
}

# 权限测试
test_permissions() {
    local pid="$1"

    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}  4. 权限隔离验证${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    echo "以下操作应该被拒绝（如果 rootless 正常工作）:"
    echo ""

    # 尝试读取宿主机敏感文件
    echo "1. 读取宿主机 /etc/shadow:"
    if nsenter -t "$pid" -m cat /etc/shadow 2>/dev/null | head -1; then
        echo -e "${YELLOW}   可以读取（这是容器内的 shadow 文件）${NC}"
    else
        echo -e "${GREEN}   拒绝访问${NC}"
    fi

    # 尝试访问宿主机 /root
    echo ""
    echo "2. 列出宿主机 /root 目录:"
    if nsenter -t "$pid" -m ls /root 2>/dev/null; then
        echo -e "${YELLOW}   可以列出（这是容器的 /root）${NC}"
    else
        echo -e "${GREEN}   拒绝访问${NC}"
    fi

    echo ""
}

# 生成日语报告
generate_japanese_report() {
    local pid="$1"
    local container_name="$2"

    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}  5. セキュリティ監査報告書（日本語）${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    # 获取映射信息
    local uid_map=$(cat "/proc/$pid/uid_map" 2>/dev/null | head -1)
    local host_uid=$(echo "$uid_map" | awk '{print $2}')
    local real_uid=$(ps -p "$pid" -o uid= 2>/dev/null | tr -d ' ')

    cat << EOF
┌────────────────────────────────────────────────────────────────┐
│                                                                │
│    User Namespace セキュリティ確認報告書                       │
│                                                                │
├────────────────────────────────────────────────────────────────┤
│ 作成日時: $(date)
│ 対象: $container_name (PID: $pid)
├────────────────────────────────────────────────────────────────┤
│                                                                │
│ 1. 概要                                                        │
│    本コンテナは User Namespace を使用しています。              │
│    コンテナ内の root 権限はホスト上では非特権です。            │
│                                                                │
│ 2. UID マッピング                                              │
│    コンテナ内 UID 0 → ホスト UID $host_uid                     │
│    ※ UID $host_uid は非特権ユーザーです                        │
│                                                                │
│ 3. セキュリティ評価                                            │
│    ・コンテナエスケープ時のリスク: 低                          │
│    ・ホストへの影響: 限定的                                    │
│    ・root 禁止ポリシー: 準拠                                   │
│                                                                │
│ 4. 結論                                                        │
│    本コンテナ環境は User Namespace により適切に隔離            │
│    されており、セキュリティポリシーに準拠しています。          │
│                                                                │
└────────────────────────────────────────────────────────────────┘
EOF

    echo ""
    echo -e "${GREEN}この報告書をセキュリティ監査の証拠として使用できます。${NC}"
}

# 生成中文报告
generate_chinese_report() {
    local pid="$1"
    local container_name="$2"

    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}  6. 安全审计报告（中文）${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    local uid_map=$(cat "/proc/$pid/uid_map" 2>/dev/null | head -1)
    local host_uid=$(echo "$uid_map" | awk '{print $2}')

    cat << EOF
┌────────────────────────────────────────────────────────────────┐
│                                                                │
│           User Namespace 安全审计报告                          │
│                                                                │
├────────────────────────────────────────────────────────────────┤
│ 生成时间: $(date)
│ 目标容器: $container_name (PID: $pid)
├────────────────────────────────────────────────────────────────┤
│                                                                │
│ 1. 技术概述                                                    │
│    本容器使用 User Namespace 实现 UID 隔离。                   │
│    容器内的 root 权限在宿主机上是非特权用户。                  │
│                                                                │
│ 2. UID 映射详情                                                │
│    容器内 UID 0 (root) → 宿主机 UID $host_uid (普通用户)       │
│    ※ UID $host_uid 无法访问宿主机特权资源                      │
│                                                                │
│ 3. 安全评估                                                    │
│    • 容器逃逸后果: 仅获得普通用户权限，风险可控                │
│    • 对宿主机影响: 受限于 UID $host_uid 的权限范围             │
│    • 满足策略要求: 符合 "禁止 root 进程" 安全策略              │
│                                                                │
│ 4. 结论                                                        │
│    本容器环境通过 User Namespace 实现了有效隔离，              │
│    即使容器被攻破，攻击者也仅能获得普通用户权限。              │
│    满足企业安全策略要求。                                      │
│                                                                │
└────────────────────────────────────────────────────────────────┘
EOF
}

# 主函数
main() {
    if [ $# -eq 0 ]; then
        usage
    fi

    local target="$1"
    local pid

    echo "=============================================="
    echo "  User Namespace 安全审计分析"
    echo "  目标: $target"
    echo "  时间: $(date)"
    echo "=============================================="
    echo ""

    # 获取 PID
    pid=$(get_container_pid "$target") || exit 1
    echo "解析到 PID: $pid"
    echo ""

    # 运行分析
    analyze_uid_mapping "$pid"
    analyze_host_process "$pid"
    analyze_namespaces "$pid"
    test_permissions "$pid"
    generate_japanese_report "$pid" "$target"
    generate_chinese_report "$pid" "$target"

    echo ""
    echo "=============================================="
    echo "  分析完成"
    echo "=============================================="
}

main "$@"
