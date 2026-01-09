#!/bin/bash
# =============================================================================
# seccomp-demo.sh - seccomp Profile 演示脚本
# =============================================================================
#
# 本脚本演示 Docker seccomp 安全机制：
# 1. 默认 seccomp profile 如何阻止危险系统调用
# 2. 禁用 seccomp 后的行为差异
# 3. 如何查看 seccomp 拒绝日志
#
# 使用方法：
#   sudo ./seccomp-demo.sh
#
# 警告：部分演示涉及禁用安全机制，仅用于教育目的！
# =============================================================================

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  seccomp Profile 演示${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# 检查 Docker
if ! command -v docker &> /dev/null; then
    echo -e "${RED}错误：Docker 未安装${NC}"
    exit 1
fi

# ============================================================================
# 演示 1：默认 seccomp 阻止危险操作
# ============================================================================
echo -e "${GREEN}=== 演示 1：默认 seccomp 阻止 mount 系统调用 ===${NC}"
echo ""
echo "尝试在容器中执行 mount 命令（应该失败）..."
echo ""
echo "命令：docker run --rm alpine mount -t proc proc /tmp"
echo ""

docker run --rm alpine mount -t proc proc /tmp 2>&1 || true

echo ""
echo -e "${YELLOW}说明：即使容器内是 root，seccomp 也阻止了 mount 系统调用。${NC}"
echo ""

# ============================================================================
# 演示 2：查看容器的 seccomp 状态
# ============================================================================
echo -e "${GREEN}=== 演示 2：查看容器的 seccomp 状态 ===${NC}"
echo ""
echo "查看 /proc/1/status 中的 Seccomp 字段..."
echo ""

docker run --rm alpine cat /proc/1/status | grep -E '^(Seccomp|NoNewPrivs)'

echo ""
echo -e "${YELLOW}说明：Seccomp: 2 表示 seccomp filter 模式（最严格）${NC}"
echo -e "${YELLOW}      0=disabled, 1=strict, 2=filter${NC}"
echo ""

# ============================================================================
# 演示 3：禁用 seccomp 后的差异
# ============================================================================
echo -e "${GREEN}=== 演示 3：禁用 seccomp 后查看状态 ===${NC}"
echo ""
echo -e "${RED}警告：这是危险操作，仅用于演示！${NC}"
echo ""
echo "命令：docker run --rm --security-opt seccomp=unconfined ..."
echo ""

docker run --rm --security-opt seccomp=unconfined alpine cat /proc/1/status | grep -E '^(Seccomp|NoNewPrivs)'

echo ""
echo -e "${YELLOW}说明：Seccomp: 0 表示 seccomp 已禁用${NC}"
echo ""

# ============================================================================
# 演示 4：尝试需要 unshare 的操作
# ============================================================================
echo -e "${GREEN}=== 演示 4：unshare 系统调用测试 ===${NC}"
echo ""
echo "测试 1：默认 seccomp（应该失败或受限）..."
echo ""

# 尝试创建新的 PID namespace（需要 unshare 系统调用）
echo "docker run --rm alpine unshare --fork --pid echo 'In new PID namespace'"
docker run --rm alpine unshare --fork --pid echo 'In new PID namespace' 2>&1 || echo -e "${YELLOW}（unshare 被限制）${NC}"

echo ""
echo "测试 2：禁用 seccomp 后..."
echo ""

docker run --rm --security-opt seccomp=unconfined alpine unshare --fork --pid echo 'In new PID namespace' 2>&1 || echo "(失败)"

echo ""

# ============================================================================
# 演示 5：查看 dmesg 中的 seccomp 拒绝日志
# ============================================================================
echo -e "${GREEN}=== 演示 5：检查 seccomp 拒绝日志 ===${NC}"
echo ""
echo "查看最近的 seccomp 相关内核日志..."
echo ""
echo "命令：dmesg | grep -i seccomp | tail -5"
echo ""

if dmesg 2>/dev/null | grep -i seccomp | tail -5; then
    echo ""
else
    echo -e "${YELLOW}（需要 root 权限或没有 seccomp 日志）${NC}"
    echo "请使用：sudo dmesg | grep -i seccomp"
fi

echo ""
echo -e "${YELLOW}说明：type=1326 是 SECCOMP 审计类型，syscall=XX 是被拒绝的系统调用编号${NC}"
echo ""

# ============================================================================
# 清理和总结
# ============================================================================
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  演示完成${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo "关键点："
echo "1. Docker 默认启用 seccomp profile"
echo "2. seccomp 在内核层面阻止危险系统调用"
echo "3. 使用 dmesg 查看 seccomp 拒绝日志"
echo "4. --security-opt seccomp=unconfined 禁用保护（危险！）"
echo ""
echo -e "${RED}安全建议：永远不要在生产环境禁用 seccomp！${NC}"
