#!/bin/bash
# =============================================================================
# overlay-mount-demo.sh - OverlayFS 手动挂载演示
# =============================================================================
#
# 演示内容：
#   1. 创建 overlay 目录结构
#   2. 手动挂载 OverlayFS
#   3. 观察写时复制（Copy-on-Write）
#   4. 观察 whiteout 文件
#
# 使用方法：
#   sudo ./overlay-mount-demo.sh
#
# 前置要求：
#   - root 权限
#   - Linux 内核支持 OverlayFS（内核 3.18+，现代发行版都支持）
#
# =============================================================================

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 实验目录
DEMO_DIR="/tmp/overlay-mount-demo"

# 清理函数
cleanup() {
    echo -e "\n${YELLOW}=== 清理实验环境 ===${NC}"

    # 卸载 overlay
    if mount | grep -q "$DEMO_DIR/merged"; then
        echo "卸载 overlay..."
        umount "$DEMO_DIR/merged" 2>/dev/null || true
    fi

    # 删除目录
    if [ -d "$DEMO_DIR" ]; then
        echo "删除实验目录..."
        rm -rf "$DEMO_DIR"
    fi

    echo -e "${GREEN}清理完成！${NC}"
}

# 检查 root 权限
check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}错误：需要 root 权限运行此脚本${NC}"
        echo "请使用: sudo $0"
        exit 1
    fi
}

# 按任意键继续
press_any_key() {
    echo -e "\n${BLUE}按 Enter 继续...${NC}"
    read -r
}

# 主函数
main() {
    echo -e "${GREEN}"
    echo "=============================================="
    echo "   OverlayFS 手动挂载演示"
    echo "=============================================="
    echo -e "${NC}"

    check_root

    # 注册清理函数
    trap cleanup EXIT

    # 清理之前的实验环境（如果存在）
    if [ -d "$DEMO_DIR" ]; then
        echo -e "${YELLOW}发现之前的实验目录，正在清理...${NC}"
        cleanup
    fi

    # =================================================================
    # 步骤 1：创建目录结构
    # =================================================================
    echo -e "\n${GREEN}=== 步骤 1：创建目录结构 ===${NC}"
    echo "OverlayFS 需要四个目录："
    echo "  - lowerdir: 只读底层（镜像层）"
    echo "  - upperdir: 可写上层（容器层）"
    echo "  - workdir:  工作目录（内核使用）"
    echo "  - merged:   合并视图（容器看到的文件系统）"
    echo ""

    mkdir -p "$DEMO_DIR"/{lower,upper,work,merged}

    echo "目录结构："
    tree "$DEMO_DIR" 2>/dev/null || ls -la "$DEMO_DIR"

    press_any_key

    # =================================================================
    # 步骤 2：创建 lower 层内容
    # =================================================================
    echo -e "\n${GREEN}=== 步骤 2：创建 lower 层内容（模拟镜像层）===${NC}"

    mkdir -p "$DEMO_DIR/lower/etc"
    mkdir -p "$DEMO_DIR/lower/app"

    echo "# Original config from image layer" > "$DEMO_DIR/lower/etc/app.conf"
    echo "server_name = production" >> "$DEMO_DIR/lower/etc/app.conf"
    echo "port = 8080" >> "$DEMO_DIR/lower/etc/app.conf"

    echo "#!/usr/bin/env python3" > "$DEMO_DIR/lower/app/main.py"
    echo "print('Hello from image layer!')" >> "$DEMO_DIR/lower/app/main.py"

    echo "This log file is in image layer" > "$DEMO_DIR/lower/image-log.txt"

    echo "lower 层内容："
    find "$DEMO_DIR/lower" -type f -exec echo "  {}" \; -exec cat {} \; -exec echo "" \;

    press_any_key

    # =================================================================
    # 步骤 3：挂载 OverlayFS
    # =================================================================
    echo -e "\n${GREEN}=== 步骤 3：挂载 OverlayFS ===${NC}"

    echo "挂载命令："
    echo -e "${BLUE}mount -t overlay overlay \\"
    echo "    -o lowerdir=$DEMO_DIR/lower,upperdir=$DEMO_DIR/upper,workdir=$DEMO_DIR/work \\"
    echo "    $DEMO_DIR/merged${NC}"
    echo ""

    mount -t overlay overlay \
        -o lowerdir="$DEMO_DIR/lower",upperdir="$DEMO_DIR/upper",workdir="$DEMO_DIR/work" \
        "$DEMO_DIR/merged"

    echo -e "${GREEN}挂载成功！${NC}"
    echo ""

    echo "验证挂载："
    mount | grep "$DEMO_DIR/merged"
    echo ""

    echo "merged 视图（容器看到的文件系统）："
    ls -la "$DEMO_DIR/merged/"

    press_any_key

    # =================================================================
    # 步骤 4：读取文件（不触发复制）
    # =================================================================
    echo -e "\n${GREEN}=== 步骤 4：读取文件（不触发复制）===${NC}"

    echo "读取 /etc/app.conf（来自 lower 层）："
    cat "$DEMO_DIR/merged/etc/app.conf"
    echo ""

    echo "检查 upper 层（应该为空）："
    ls -la "$DEMO_DIR/upper/"
    echo ""

    echo -e "${YELLOW}要点：读取操作不会触发复制，upper 层仍为空${NC}"

    press_any_key

    # =================================================================
    # 步骤 5：写入文件（触发 Copy-on-Write）
    # =================================================================
    echo -e "\n${GREEN}=== 步骤 5：写入文件（触发 Copy-on-Write）===${NC}"

    echo "修改 /etc/app.conf（原本在 lower 层）："
    echo ""

    echo "# Modified by container runtime" > "$DEMO_DIR/merged/etc/app.conf"
    echo "server_name = development" >> "$DEMO_DIR/merged/etc/app.conf"
    echo "port = 3000" >> "$DEMO_DIR/merged/etc/app.conf"
    echo "debug = true" >> "$DEMO_DIR/merged/etc/app.conf"

    echo "修改后的内容（从 merged 读取）："
    cat "$DEMO_DIR/merged/etc/app.conf"
    echo ""

    echo "检查 lower 层（应该未变化）："
    echo -e "${BLUE}--- lower/etc/app.conf ---${NC}"
    cat "$DEMO_DIR/lower/etc/app.conf"
    echo ""

    echo "检查 upper 层（应该有副本）："
    echo -e "${BLUE}--- upper/etc/app.conf ---${NC}"
    cat "$DEMO_DIR/upper/etc/app.conf"
    echo ""

    echo -e "${YELLOW}要点：写入触发了 Copy-on-Write！${NC}"
    echo "  - lower 层文件未变化（只读）"
    echo "  - 文件被复制到 upper 层后修改"

    press_any_key

    # =================================================================
    # 步骤 6：创建新文件
    # =================================================================
    echo -e "\n${GREEN}=== 步骤 6：创建新文件 ===${NC}"

    echo "在容器中创建新文件 /container-data.txt："
    echo "This file was created at runtime" > "$DEMO_DIR/merged/container-data.txt"
    echo ""

    echo "merged 视图："
    ls -la "$DEMO_DIR/merged/"
    echo ""

    echo "检查 lower 层（新文件不在这里）："
    ls -la "$DEMO_DIR/lower/" | grep container-data || echo "  (不存在)"
    echo ""

    echo "检查 upper 层（新文件在这里）："
    ls -la "$DEMO_DIR/upper/"
    echo ""

    echo -e "${YELLOW}要点：新文件直接创建在 upper 层${NC}"

    press_any_key

    # =================================================================
    # 步骤 7：删除文件（创建 whiteout）
    # =================================================================
    echo -e "\n${GREEN}=== 步骤 7：删除文件（创建 whiteout）===${NC}"

    echo "删除 /image-log.txt（原本在 lower 层）："
    rm "$DEMO_DIR/merged/image-log.txt"
    echo ""

    echo "merged 视图（文件消失）："
    ls -la "$DEMO_DIR/merged/"
    echo ""

    echo "检查 lower 层（文件仍然存在！）："
    ls -la "$DEMO_DIR/lower/image-log.txt"
    echo ""

    echo "检查 upper 层（出现 whiteout 文件）："
    ls -la "$DEMO_DIR/upper/"
    echo ""

    echo -e "${YELLOW}要点：Whiteout 文件解析${NC}"
    echo "  - 类型：c (字符设备)"
    echo "  - Major:Minor = 0:0"
    echo "  - 作用：告诉内核「隐藏 lower 层中的同名文件」"

    press_any_key

    # =================================================================
    # 步骤 8：查看最终状态
    # =================================================================
    echo -e "\n${GREEN}=== 步骤 8：最终状态总结 ===${NC}"

    echo "lower 层（只读，未修改）："
    echo "----------------------------"
    find "$DEMO_DIR/lower" -type f -exec echo "  {}" \;
    echo ""

    echo "upper 层（所有运行时变化）："
    echo "----------------------------"
    find "$DEMO_DIR/upper" -exec ls -la {} \; 2>/dev/null | head -20
    echo ""

    echo "merged 层（容器视图）："
    echo "----------------------------"
    find "$DEMO_DIR/merged" -type f -exec echo "  {}" \;
    echo ""

    # =================================================================
    # 总结
    # =================================================================
    echo -e "\n${GREEN}=============================================="
    echo "   演示完成！"
    echo "==============================================${NC}"
    echo ""
    echo "关键收获："
    echo "  1. lowerdir 是只读的，永远不会被修改"
    echo "  2. 读取操作不触发复制"
    echo "  3. 写入操作触发 Copy-on-Write"
    echo "  4. 删除操作创建 whiteout 文件（c 0 0）"
    echo "  5. merged 是 lower + upper 的合并视图"
    echo ""
    echo "这就是 Docker/Podman 镜像层的核心原理！"
    echo ""

    press_any_key

    echo "正在清理实验环境..."
}

# 运行主函数
main
