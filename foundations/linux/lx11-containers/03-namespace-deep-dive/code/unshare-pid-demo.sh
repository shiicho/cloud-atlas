#!/bin/bash
# =============================================================================
# unshare-pid-demo.sh - PID Namespace 演示脚本
# =============================================================================
#
# 用途：演示 PID Namespace 隔离效果
# 环境：需要 root 权限
#
# 使用方法：
#   sudo ./unshare-pid-demo.sh
#
# =============================================================================

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 检查 root 权限
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}错误：需要 root 权限运行此脚本${NC}"
    echo "请使用: sudo $0"
    exit 1
fi

echo "=============================================="
echo "  PID Namespace 演示"
echo "=============================================="
echo ""

# 演示 1：不使用 --fork 的问题
echo -e "${YELLOW}【演示 1】不使用 --fork（错误方式）${NC}"
echo "命令: unshare --pid /bin/bash -c 'echo PID: \$\$; ps aux | wc -l'"
echo ""
echo "执行结果："
unshare --pid /bin/bash -c 'echo "  我的 PID: $$"; echo "  进程总数: $(ps aux | wc -l)"'
echo ""
echo -e "${RED}问题：PID 不是 1，能看到所有宿主机进程${NC}"
echo ""

# 演示 2：使用 --fork 但不使用 --mount-proc
echo -e "${YELLOW}【演示 2】使用 --fork 但不使用 --mount-proc${NC}"
echo "命令: unshare --pid --fork /bin/bash -c 'echo PID: \$\$; ps aux | wc -l'"
echo ""
echo "执行结果："
unshare --pid --fork /bin/bash -c 'echo "  我的 PID: $$"; echo "  进程总数: $(ps aux | wc -l)"'
echo ""
echo -e "${RED}问题：虽然 PID 是 1，但 ps 读取的是宿主机的 /proc${NC}"
echo ""

# 演示 3：正确使用 --fork 和 --mount-proc
echo -e "${YELLOW}【演示 3】正确使用 --fork 和 --mount-proc${NC}"
echo "命令: unshare --pid --fork --mount-proc /bin/bash -c 'echo PID: \$\$; ps aux'"
echo ""
echo "执行结果："
unshare --pid --fork --mount-proc /bin/bash -c '
echo "  我的 PID: $$"
echo ""
echo "  进程列表（只有 Namespace 内的进程）："
ps aux
'
echo ""
echo -e "${GREEN}成功：PID 是 1，只能看到 Namespace 内的进程${NC}"
echo ""

# 演示 4：从宿主机观察隔离进程
echo -e "${YELLOW}【演示 4】从宿主机视角观察${NC}"
echo "在后台创建一个隔离进程..."
echo ""

# 创建后台隔离进程
unshare --pid --fork --mount-proc /bin/bash -c '
echo "我是隔离的 PID 1" > /tmp/ns-demo-marker
sleep 10
' &

PARENT_PID=$!
sleep 1

# 找到子进程（真正在新 Namespace 中的进程）
CHILD_PID=$(pgrep -P "$PARENT_PID" 2>/dev/null | head -1)

echo "后台进程信息："
echo "  父进程 PID（宿主机视角）: $PARENT_PID"
echo "  子进程 PID（宿主机视角）: $CHILD_PID"
echo ""

if [ -n "$CHILD_PID" ] && [ -d "/proc/$CHILD_PID" ]; then
    echo "查看子进程的 Namespace："
    echo "  $ ls -la /proc/$CHILD_PID/ns/pid"
    ls -la "/proc/$CHILD_PID/ns/pid"
    echo ""

    echo "与当前 shell 的 PID Namespace 比较："
    echo "  当前 shell PID NS: $(readlink /proc/$$/ns/pid)"
    echo "  隔离进程 PID NS: $(readlink /proc/$CHILD_PID/ns/pid)"
    echo ""

    if [ "$(readlink /proc/$$/ns/pid)" != "$(readlink /proc/$CHILD_PID/ns/pid)" ]; then
        echo -e "${GREEN}  不同！确认处于不同的 PID Namespace${NC}"
    fi
fi

# 清理
kill $PARENT_PID 2>/dev/null || true
rm -f /tmp/ns-demo-marker

echo ""
echo "=============================================="
echo "  演示完成"
echo "=============================================="
echo ""
echo "关键要点："
echo "  1. --fork: 让子进程成为新 Namespace 的 PID 1"
echo "  2. --mount-proc: 重新挂载 /proc 以正确显示进程"
echo "  3. 父 Namespace 能看到子 Namespace 的进程"
echo "  4. 子 Namespace 看不到父 Namespace 的进程"
echo ""
