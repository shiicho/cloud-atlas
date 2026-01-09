#!/bin/bash
# =============================================================================
# process-visibility.sh - 演示容器进程在宿主机可见
# =============================================================================
#
# 证明「容器 = 进程」—— 容器内的进程在宿主机上完全可见
# 这是容器与虚拟机的核心区别之一
#
# 用法：
#   sudo ./process-visibility.sh
#
# =============================================================================

set -e

# 颜色定义
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}  容器进程可见性演示${NC}"
echo -e "${BLUE}============================================${NC}"
echo ""

# 检查 root 权限
if [[ $EUID -ne 0 ]]; then
    echo "请使用 sudo 运行此脚本"
    exit 1
fi

# 创建一个隔离进程
echo -e "${GREEN}步骤 1：创建隔离的「容器」进程${NC}"
echo "  执行: unshare --pid --net --fork --mount-proc sleep 60"
echo ""

# 后台运行隔离进程
unshare --pid --net --fork --mount-proc sleep 60 &
ISOLATED_PID=$!

sleep 1  # 等待进程完全启动

echo -e "${GREEN}步骤 2：隔离进程信息${NC}"
echo "  宿主机 PID: $ISOLATED_PID"
echo ""

# 查找 sleep 进程的实际 PID（unshare 的子进程）
SLEEP_PID=$(pgrep -P $ISOLATED_PID sleep 2>/dev/null || echo "")
if [[ -n "$SLEEP_PID" ]]; then
    echo "  sleep 进程 PID: $SLEEP_PID"
    echo ""
fi

echo -e "${GREEN}步骤 3：在宿主机上查看进程${NC}"
echo "  执行: ps aux | grep sleep"
echo ""
ps aux | head -1
ps aux | grep "sleep 60" | grep -v grep || echo "  (未找到)"
echo ""

echo -e "${GREEN}步骤 4：查看进程的 Namespace 信息${NC}"
echo "  执行: ls -la /proc/$ISOLATED_PID/ns/"
echo ""

if [[ -d "/proc/$ISOLATED_PID/ns" ]]; then
    ls -la /proc/$ISOLATED_PID/ns/ 2>/dev/null || echo "  无法读取 namespace"
    echo ""

    # 对比宿主机进程的 namespace
    echo -e "${GREEN}步骤 5：对比宿主机 shell 的 Namespace${NC}"
    echo "  执行: ls -la /proc/$$/ns/"
    echo ""
    ls -la /proc/$$/ns/
    echo ""

    echo -e "${YELLOW}注意：${NC}net 和 pid namespace 的 inode 号不同，表示隔离成功"
fi

# 清理
echo ""
echo -e "${GREEN}步骤 6：清理${NC}"
kill $ISOLATED_PID 2>/dev/null || true
echo "  已终止隔离进程"

echo ""
echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}  结论${NC}"
echo -e "${BLUE}============================================${NC}"
echo ""
echo "  1. 容器进程在宿主机上可见（ps aux）"
echo "  2. 容器进程有独立的 Namespace（/proc/PID/ns/）"
echo "  3. 容器 = 带 Namespace 约束的普通进程"
echo "  4. 虚拟机内部进程在宿主机上不可见"
echo ""
echo "  这就是「Container = Process + Constraints」"
echo ""
