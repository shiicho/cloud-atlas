#!/bin/bash
# =============================================================================
# scaffold-namespace.sh - Namespace 创建脚手架
# =============================================================================
#
# 处理 Namespace 创建的常见陷阱：
#   1. --fork --pid 组合的正确顺序
#   2. /proc 挂载顺序和时机
#   3. pivot_root 参数顺序陷阱
#
# 用法：
#   sudo ./scaffold-namespace.sh <rootfs-path> <container-name> [command]
#
# 示例：
#   sudo ./scaffold-namespace.sh /tmp/container/merged my-container /bin/sh
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

# 打印函数
info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
cmd() { echo -e "${CYAN}[CMD]${NC} $1"; }

# =============================================================================
# 参数检查
# =============================================================================

ROOTFS="${1:-}"
CONTAINER_NAME="${2:-my-container}"
CONTAINER_CMD="${3:-/bin/sh}"

if [[ -z "$ROOTFS" ]]; then
    echo "用法: $0 <rootfs-path> [container-name] [command]"
    echo ""
    echo "示例:"
    echo "  $0 /tmp/container/merged"
    echo "  $0 /tmp/container/merged my-container"
    echo "  $0 /tmp/container/merged my-container /bin/sh"
    exit 1
fi

if [[ ! -d "$ROOTFS" ]]; then
    error "rootfs 目录不存在: $ROOTFS"
fi

if [[ $EUID -ne 0 ]]; then
    error "请使用 sudo 运行此脚本"
fi

# =============================================================================
# Namespace 创建
# =============================================================================

info "创建 Namespace 隔离环境"
info "  rootfs: $ROOTFS"
info "  container name: $CONTAINER_NAME"
info "  command: $CONTAINER_CMD"
echo ""

# 关键陷阱 1: --fork 必须和 --pid 一起使用
# 原因：新的 PID namespace 需要 fork 来成为 PID 1
#
# 错误写法：
#   unshare --pid /bin/sh  # shell 会立即退出
#
# 正确写法：
#   unshare --pid --fork /bin/sh

# 关键陷阱 2: /proc 必须在新的 mount namespace 中挂载
# 原因：旧的 /proc 属于宿主机 PID namespace
#
# 如果忘记挂载 /proc，ps 命令会显示宿主机进程

# 关键陷阱 3: pivot_root 参数顺序
# pivot_root new_root put_old
# - new_root 是新的根目录
# - put_old 是放置旧根的目录（相对于 new_root）
#
# 常见错误：忘记在 new_root 中创建 put_old 目录

info "执行 unshare 创建新 Namespace..."
cmd "unshare --pid --fork --mount --uts --net --ipc /bin/bash"
echo ""

# 使用 heredoc 执行容器初始化
exec unshare --pid --fork --mount --uts --net --ipc /bin/bash << CONTAINER_INIT
# ==== 容器内初始化脚本 ====

# 设置主机名（UTS namespace）
hostname "$CONTAINER_NAME"
echo "[INFO] 设置主机名: $CONTAINER_NAME"

# 重要：在切换根目录之前先挂载 /proc
# 这样可以确保 /proc 属于新的 PID namespace
mount -t proc proc /proc
echo "[INFO] 挂载 /proc (新 PID namespace)"

# 切换根目录
cd "$ROOTFS"
echo "[INFO] 切换到 rootfs: $ROOTFS"

# 创建 oldroot 目录（pivot_root 需要）
mkdir -p oldroot
echo "[INFO] 创建 oldroot 目录"

# pivot_root: 将当前目录设为新根，旧根移到 oldroot
# 参数顺序：pivot_root new_root put_old
# new_root = .（当前目录，即 $ROOTFS）
# put_old = oldroot（相对于 new_root）
pivot_root . oldroot
echo "[INFO] 执行 pivot_root"

# 切换到新根
cd /
echo "[INFO] 切换到新根目录 /"

# 在新根中重新挂载必要的伪文件系统
mount -t proc proc /proc
mount -t sysfs sysfs /sys
echo "[INFO] 挂载 /proc 和 /sys"

# 尝试卸载旧根（可能会失败，这是正常的）
umount -l /oldroot 2>/dev/null && echo "[INFO] 卸载 oldroot" || echo "[WARN] 无法卸载 oldroot（可能被占用）"
rmdir /oldroot 2>/dev/null || true

echo ""
echo "=============================================="
echo "  容器已启动！"
echo "  主机名: \$(hostname)"
echo "  PID namespace: \$\$ = \$(echo \$\$)"
echo "=============================================="
echo ""
echo "提示："
echo "  - 运行 'ps aux' 验证 PID 隔离"
echo "  - 运行 'ip addr' 查看网络（需要配置）"
echo "  - 输入 'exit' 退出容器"
echo ""

# 执行容器命令
exec $CONTAINER_CMD
CONTAINER_INIT
