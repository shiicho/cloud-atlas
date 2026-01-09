#!/bin/bash
# =============================================================================
# kernel-verify.sh - 验证容器和宿主机共享内核
# =============================================================================
#
# 演示容器（隔离进程）与宿主机共享同一个 Linux 内核
#
# 用法：
#   sudo ./kernel-verify.sh
#
# 也可以配合 Docker 使用：
#   docker run --rm alpine uname -r
#   uname -r
#   # 两者输出相同！
#
# =============================================================================

set -e

# 颜色定义
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}  容器与宿主机内核共享验证${NC}"
echo -e "${BLUE}============================================${NC}"
echo ""

# 获取宿主机内核版本
HOST_KERNEL=$(uname -r)
echo -e "${GREEN}宿主机内核版本：${NC}$HOST_KERNEL"

# 在隔离环境中获取内核版本
echo ""
echo "在隔离 Namespace 中检查..."
ISOLATED_KERNEL=$(sudo unshare --pid --net --fork --mount-proc bash -c 'uname -r')
echo -e "${GREEN}隔离环境内核版本：${NC}$ISOLATED_KERNEL"

# 比较
echo ""
if [[ "$HOST_KERNEL" == "$ISOLATED_KERNEL" ]]; then
    echo -e "${GREEN}[PASS]${NC} 内核版本相同 - 容器共享宿主机内核"
    echo ""
    echo "这证明了："
    echo "  1. 容器不是虚拟机 - 没有独立内核"
    echo "  2. 内核漏洞会影响所有容器"
    echo "  3. 容器启动快，因为不需要启动内核"
else
    echo "[UNEXPECTED] 内核版本不同？请检查环境..."
fi

# 如果有 Docker，也验证 Docker 容器
echo ""
if command -v docker &> /dev/null; then
    echo "检测到 Docker，验证 Docker 容器..."
    DOCKER_KERNEL=$(docker run --rm alpine uname -r 2>/dev/null || echo "Docker not running")
    if [[ "$DOCKER_KERNEL" != "Docker not running" ]]; then
        echo -e "${GREEN}Docker 容器内核版本：${NC}$DOCKER_KERNEL"
        if [[ "$HOST_KERNEL" == "$DOCKER_KERNEL" ]]; then
            echo -e "${GREEN}[PASS]${NC} Docker 容器也共享宿主机内核"
        fi
    fi
fi

echo ""
echo -e "${BLUE}============================================${NC}"
