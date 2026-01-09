#!/bin/bash
# =============================================================================
# runc-demo.sh - OCI 低级运行时演示脚本
# =============================================================================
#
# 本脚本演示如何直接使用 runc 运行 OCI 容器，
# 绕过 Docker/containerd，理解容器运行时的核心原理。
#
# 使用方法:
#   ./runc-demo.sh          # 完整演示
#   ./runc-demo.sh cleanup  # 只清理
#
# 前提条件:
#   - 需要 root 权限
#   - 已安装 runc
#   - 已安装 Docker（用于导出 rootfs）
#
# =============================================================================

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 配置
DEMO_DIR="${HOME}/runc-demo"
CONTAINER_NAME="demo-container"
CONTAINER_ID="oci-demo-$$"

# =============================================================================
# 辅助函数
# =============================================================================

print_header() {
    echo ""
    echo -e "${BLUE}============================================================${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}============================================================${NC}"
    echo ""
}

print_step() {
    echo -e "${GREEN}>>> $1${NC}"
}

print_info() {
    echo -e "${YELLOW}    $1${NC}"
}

print_error() {
    echo -e "${RED}[ERROR] $1${NC}"
}

wait_for_input() {
    echo ""
    echo -e "${YELLOW}按 Enter 继续...${NC}"
    read -r
}

check_root() {
    if [ "$EUID" -ne 0 ]; then
        print_error "此脚本需要 root 权限运行"
        print_info "请使用: sudo $0"
        exit 1
    fi
}

check_prerequisites() {
    print_step "检查前提条件..."

    # 检查 runc
    if ! command -v runc &> /dev/null; then
        print_error "runc 未安装"
        print_info "Ubuntu/Debian: apt-get install runc"
        print_info "RHEL/CentOS: dnf install runc"
        exit 1
    fi
    print_info "runc 版本: $(runc --version | head -1)"

    # 检查 docker
    if ! command -v docker &> /dev/null; then
        print_error "docker 未安装（用于导出 rootfs）"
        exit 1
    fi
    print_info "docker 版本: $(docker --version)"

    echo ""
}

cleanup() {
    print_step "清理环境..."

    # 尝试删除运行中的容器
    runc kill "$CONTAINER_ID" SIGKILL 2>/dev/null || true
    runc delete "$CONTAINER_ID" 2>/dev/null || true

    # 删除演示目录
    if [ -d "$DEMO_DIR" ]; then
        rm -rf "$DEMO_DIR"
        print_info "已删除: $DEMO_DIR"
    fi

    print_info "清理完成"
}

# =============================================================================
# 演示步骤
# =============================================================================

demo_prepare_bundle() {
    print_header "步骤 1: 准备 OCI Bundle"

    print_step "创建目录结构..."
    mkdir -p "$DEMO_DIR/rootfs"
    print_info "创建: $DEMO_DIR/rootfs"

    print_step "导出 Alpine rootfs..."
    print_info "这将创建一个最小化的 Linux 根文件系统"

    # 创建临时容器并导出文件系统
    local cid
    cid=$(docker create alpine:latest)
    docker export "$cid" | tar -C "$DEMO_DIR/rootfs" -xf -
    docker rm "$cid" > /dev/null

    print_info "rootfs 大小: $(du -sh "$DEMO_DIR/rootfs" | cut -f1)"
    print_info "rootfs 内容预览:"
    ls -la "$DEMO_DIR/rootfs" | head -10

    wait_for_input
}

demo_generate_config() {
    print_header "步骤 2: 生成 OCI 配置文件"

    cd "$DEMO_DIR"

    print_step "生成默认 config.json..."
    runc spec

    print_info "config.json 是 OCI Runtime Spec 的核心文件"
    print_info "它定义了容器的运行参数"

    echo ""
    print_step "关键配置字段:"
    echo ""

    echo -e "${YELLOW}process.args (启动命令):${NC}"
    grep -A2 '"args"' config.json
    echo ""

    echo -e "${YELLOW}root.path (根文件系统):${NC}"
    grep -A2 '"root"' config.json
    echo ""

    echo -e "${YELLOW}hostname (主机名):${NC}"
    grep '"hostname"' config.json
    echo ""

    echo -e "${YELLOW}linux.namespaces (隔离类型):${NC}"
    grep -A10 '"namespaces"' config.json | head -12

    wait_for_input
}

demo_modify_config() {
    print_header "步骤 3: 自定义配置"

    cd "$DEMO_DIR"

    print_step "修改启动命令为交互式 shell..."

    # 创建一个修改后的配置
    # 保持 terminal: true 用于交互式演示

    print_step "修改主机名..."
    sed -i 's/"runc"/"oci-demo"/' config.json

    print_info "修改后的 hostname:"
    grep '"hostname"' config.json

    wait_for_input
}

demo_run_container() {
    print_header "步骤 4: 运行 OCI 容器"

    cd "$DEMO_DIR"

    print_step "使用 runc run 启动容器..."
    print_info "容器 ID: $CONTAINER_ID"
    print_info ""
    print_info "你将进入容器的 shell 环境"
    print_info "请尝试以下命令:"
    print_info "  hostname        # 查看主机名"
    print_info "  ps aux          # 查看进程（只有自己）"
    print_info "  cat /etc/os-release  # 查看系统信息"
    print_info "  ip addr         # 查看网络（隔离的）"
    print_info "  exit            # 退出容器"
    print_info ""

    echo -e "${YELLOW}按 Enter 启动容器...${NC}"
    read -r

    # 运行容器
    runc run "$CONTAINER_ID"

    print_info "容器已退出"
    wait_for_input
}

demo_container_lifecycle() {
    print_header "步骤 5: 容器生命周期管理"

    cd "$DEMO_DIR"

    print_step "创建后台运行的容器..."

    # 修改配置为非交互式
    cat > config.json << 'EOF'
{
    "ociVersion": "1.0.2-dev",
    "process": {
        "terminal": false,
        "user": { "uid": 0, "gid": 0 },
        "args": ["sleep", "300"],
        "env": [
            "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
        ],
        "cwd": "/"
    },
    "root": { "path": "rootfs", "readonly": true },
    "hostname": "background-demo",
    "mounts": [
        {
            "destination": "/proc",
            "type": "proc",
            "source": "proc"
        },
        {
            "destination": "/dev",
            "type": "tmpfs",
            "source": "tmpfs",
            "options": ["nosuid", "strictatime", "mode=755", "size=65536k"]
        }
    ],
    "linux": {
        "namespaces": [
            { "type": "pid" },
            { "type": "ipc" },
            { "type": "uts" },
            { "type": "mount" }
        ]
    }
}
EOF

    local bg_id="bg-demo-$$"

    print_step "启动后台容器: $bg_id"
    runc run -d "$bg_id"

    print_step "列出容器..."
    runc list

    echo ""
    print_step "查看容器状态..."
    runc state "$bg_id"

    echo ""
    print_step "在容器内执行命令..."
    runc exec "$bg_id" hostname
    runc exec "$bg_id" ps aux

    echo ""
    print_step "停止容器..."
    runc kill "$bg_id" SIGKILL
    sleep 1

    print_step "删除容器..."
    runc delete "$bg_id"

    print_step "确认容器已删除..."
    runc list

    wait_for_input
}

demo_config_deep_dive() {
    print_header "步骤 6: config.json 深入解析"

    cd "$DEMO_DIR"

    print_step "理解 OCI Runtime Spec 配置结构..."

    echo ""
    echo -e "${YELLOW}config.json 字段与内核机制对应:${NC}"
    echo ""
    cat << 'EOF'
    ┌──────────────────┬─────────────────────────────────────────────┐
    │ config.json 字段 │ 对应的内核机制                               │
    ├──────────────────┼─────────────────────────────────────────────┤
    │ process.args     │ execve() 系统调用                           │
    │ root.path        │ pivot_root() 切换根目录                     │
    │ hostname         │ UTS namespace + sethostname()               │
    │ namespaces       │ clone() flags (CLONE_NEWPID, CLONE_NEWNS)   │
    │ linux.resources  │ cgroups v2 写入配置                         │
    │ mounts           │ mount() 系统调用                            │
    └──────────────────┴─────────────────────────────────────────────┘
EOF

    echo ""
    print_step "runc 执行 config.json 的流程:"
    echo ""
    cat << 'EOF'
    1. 解析 config.json
    2. 创建子进程
    3. 应用 namespace 隔离 (clone)
    4. 配置 cgroups 资源限制
    5. 设置根文件系统 (pivot_root)
    6. 挂载 /proc, /dev 等
    7. 设置主机名
    8. 执行 process.args 指定的命令
EOF

    wait_for_input
}

show_summary() {
    print_header "演示总结"

    cat << 'EOF'

    你刚刚学到了:

    1. OCI Bundle 结构
       - rootfs/: 容器根文件系统
       - config.json: OCI Runtime Spec 配置文件

    2. runc 基本命令
       - runc spec: 生成默认配置
       - runc run: 创建并运行容器
       - runc run -d: 后台运行
       - runc list: 列出容器
       - runc state: 查看状态
       - runc exec: 执行命令
       - runc kill: 发送信号
       - runc delete: 删除容器

    3. config.json 关键字段
       - process: 容器内运行的进程
       - root: 根文件系统路径
       - hostname: 主机名
       - namespaces: 启用的隔离类型

    4. 容器运行时层级
       Docker/K8s → containerd/CRI-O → runc → Linux Kernel

    下一步:
    - 尝试修改 config.json 中的 namespaces 配置
    - 比较 runc 和 crun 的性能差异
    - 使用 containerd 的 ctr 命令管理容器

EOF
}

# =============================================================================
# 主程序
# =============================================================================

main() {
    # 处理清理参数
    if [ "${1:-}" = "cleanup" ]; then
        check_root
        cleanup
        exit 0
    fi

    check_root
    check_prerequisites

    # 先清理可能存在的旧数据
    cleanup 2>/dev/null || true

    print_header "OCI 低级运行时 (runc) 演示"

    cat << 'EOF'
    本演示将帮助你理解:

    1. OCI Bundle 的目录结构
    2. config.json 的配置内容
    3. 如何直接使用 runc 运行容器
    4. 容器生命周期管理

    这是 Docker/Kubernetes 底层使用的技术！

EOF

    wait_for_input

    # 执行演示步骤
    demo_prepare_bundle
    demo_generate_config
    demo_modify_config
    demo_run_container
    demo_container_lifecycle
    demo_config_deep_dive
    show_summary

    # 清理
    print_step "是否清理演示环境？[Y/n]"
    read -r answer
    if [ "${answer:-Y}" != "n" ] && [ "${answer:-Y}" != "N" ]; then
        cleanup
    else
        print_info "演示文件保留在: $DEMO_DIR"
        print_info "手动清理: rm -rf $DEMO_DIR"
    fi

    echo ""
    print_info "演示完成！"
}

main "$@"
