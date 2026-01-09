#!/bin/bash
# =============================================================================
# capabilities-demo.sh - Capabilities 演示脚本
# =============================================================================
#
# 本脚本演示 Docker 容器的 Capabilities 配置：
# 1. 默认 Capabilities 列表
# 2. --cap-drop=ALL 移除所有权限
# 3. --cap-add 添加特定权限
# 4. 最小权限配置示例
#
# 使用方法：
#   ./capabilities-demo.sh
#
# =============================================================================

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Capabilities 演示${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# 检查 Docker
if ! command -v docker &> /dev/null; then
    echo -e "${RED}错误：Docker 未安装${NC}"
    exit 1
fi

# ============================================================================
# 演示 1：查看默认 Capabilities
# ============================================================================
echo -e "${GREEN}=== 演示 1：查看容器默认 Capabilities ===${NC}"
echo ""
echo "命令：docker run --rm alpine cat /proc/1/status | grep Cap"
echo ""

docker run --rm alpine cat /proc/1/status | grep Cap

echo ""
echo "解码 Capabilities（CapEff）..."
echo ""

# 获取 CapEff 值并解码
CAP_VALUE=$(docker run --rm alpine cat /proc/1/status | grep CapEff | awk '{print $2}')
echo "CapEff: $CAP_VALUE"
echo ""

# 尝试使用 capsh 解码（如果可用）
if command -v capsh &> /dev/null; then
    echo "解码结果："
    capsh --decode=$CAP_VALUE
else
    echo -e "${YELLOW}提示：安装 libcap 可以使用 capsh --decode 解码${NC}"
    echo "常见 Capabilities："
    echo "  cap_chown, cap_dac_override, cap_fowner, cap_fsetid"
    echo "  cap_kill, cap_setgid, cap_setuid, cap_setpcap"
    echo "  cap_net_bind_service, cap_net_raw, cap_sys_chroot"
    echo "  cap_mknod, cap_audit_write, cap_setfcap"
fi
echo ""

# ============================================================================
# 演示 2：CAP_CHOWN 测试
# ============================================================================
echo -e "${GREEN}=== 演示 2：CAP_CHOWN 测试 ===${NC}"
echo ""
echo "测试 1：默认容器可以 chown"
echo "命令：docker run --rm alpine chown nobody /etc/passwd"
echo ""

if docker run --rm alpine chown nobody /etc/passwd 2>&1; then
    echo -e "${GREEN}成功！${NC}"
else
    echo -e "${RED}失败${NC}"
fi

echo ""
echo "测试 2：--cap-drop=ALL 后不能 chown"
echo "命令：docker run --rm --cap-drop=ALL alpine chown nobody /etc/passwd"
echo ""

if docker run --rm --cap-drop=ALL alpine chown nobody /etc/passwd 2>&1; then
    echo -e "${GREEN}成功${NC}"
else
    echo -e "${RED}失败（预期行为 - CAP_CHOWN 被移除）${NC}"
fi

echo ""
echo "测试 3：--cap-drop=ALL --cap-add=CHOWN 恢复 chown 能力"
echo "命令：docker run --rm --cap-drop=ALL --cap-add=CHOWN alpine chown nobody /etc/passwd"
echo ""

if docker run --rm --cap-drop=ALL --cap-add=CHOWN alpine chown nobody /etc/passwd 2>&1; then
    echo -e "${GREEN}成功！最小权限原则生效${NC}"
else
    echo -e "${RED}失败${NC}"
fi
echo ""

# ============================================================================
# 演示 3：CAP_NET_RAW 测试（ping 需要）
# ============================================================================
echo -e "${GREEN}=== 演示 3：CAP_NET_RAW 测试（ping 需要）===${NC}"
echo ""
echo "测试 1：默认容器可以 ping"
echo "命令：docker run --rm alpine ping -c 1 -W 2 127.0.0.1"
echo ""

docker run --rm alpine ping -c 1 -W 2 127.0.0.1 2>&1 || echo ""

echo ""
echo "测试 2：--cap-drop=NET_RAW 后不能 ping"
echo "命令：docker run --rm --cap-drop=NET_RAW alpine ping -c 1 127.0.0.1"
echo ""

docker run --rm --cap-drop=NET_RAW alpine ping -c 1 -W 2 127.0.0.1 2>&1 || echo -e "${YELLOW}（CAP_NET_RAW 被移除，ping 失败）${NC}"

echo ""

# ============================================================================
# 演示 4：查看 --cap-drop=ALL 后的 Capabilities
# ============================================================================
echo -e "${GREEN}=== 演示 4：查看 --cap-drop=ALL 后的 Capabilities ===${NC}"
echo ""
echo "命令：docker run --rm --cap-drop=ALL alpine cat /proc/1/status | grep Cap"
echo ""

docker run --rm --cap-drop=ALL alpine cat /proc/1/status | grep Cap

echo ""
echo -e "${YELLOW}说明：所有 Cap 字段都是 0，表示没有任何 Capability${NC}"
echo ""

# ============================================================================
# 演示 5：最小权限 Nginx 示例
# ============================================================================
echo -e "${GREEN}=== 演示 5：Nginx 最小权限配置 ===${NC}"
echo ""
echo "启动一个使用最小权限的 Nginx 容器..."
echo ""
echo "命令："
echo "docker run -d --rm --name nginx-minimal \\"
echo "  --cap-drop=ALL \\"
echo "  --cap-add=NET_BIND_SERVICE \\"
echo "  --cap-add=CHOWN \\"
echo "  --cap-add=SETUID \\"
echo "  --cap-add=SETGID \\"
echo "  --cap-add=DAC_OVERRIDE \\"
echo "  nginx:alpine"
echo ""

docker run -d --rm --name nginx-minimal \
  --cap-drop=ALL \
  --cap-add=NET_BIND_SERVICE \
  --cap-add=CHOWN \
  --cap-add=SETUID \
  --cap-add=SETGID \
  --cap-add=DAC_OVERRIDE \
  nginx:alpine

# 等待启动
sleep 2

echo ""
echo "检查容器状态..."
docker ps --filter name=nginx-minimal --format "table {{.Names}}\t{{.Status}}"

echo ""
echo "检查容器的 Capabilities..."
echo ""
docker exec nginx-minimal cat /proc/1/status | grep Cap

echo ""
echo "清理..."
docker rm -f nginx-minimal > /dev/null 2>&1 || true

echo ""
echo -e "${GREEN}成功！Nginx 使用最小权限运行${NC}"
echo ""

# ============================================================================
# 演示 6：危险 Capability 警告
# ============================================================================
echo -e "${GREEN}=== 演示 6：危险 Capability 说明 ===${NC}"
echo ""
echo -e "${RED}以下 Capabilities 应避免授予：${NC}"
echo ""
echo "  CAP_SYS_ADMIN    - 系统管理，接近 root 权限"
echo "                     可以：mount, umount, 修改内核参数等"
echo ""
echo "  CAP_NET_ADMIN    - 网络管理"
echo "                     可以：修改路由表、防火墙规则等"
echo ""
echo "  CAP_SYS_PTRACE   - 进程调试"
echo "                     可以：调试任意进程，读取内存"
echo ""
echo "  CAP_DAC_READ_SEARCH - 绕过文件读取权限"
echo "                     可以：读取任意文件"
echo ""

# ============================================================================
# 清理和总结
# ============================================================================
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  演示完成${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo "关键点："
echo "1. Docker 默认保留 14 个 Capabilities"
echo "2. 使用 --cap-drop=ALL 移除所有权限"
echo "3. 使用 --cap-add=XXX 只添加必需的权限"
echo "4. 最小权限原则：只授予必要的能力"
echo ""
echo -e "${YELLOW}安全最佳实践：${NC}"
echo "  docker run --cap-drop=ALL --cap-add=<only-needed> ..."
echo ""
echo -e "${RED}避免使用：${NC}"
echo "  --privileged"
echo "  --cap-add=SYS_ADMIN"
