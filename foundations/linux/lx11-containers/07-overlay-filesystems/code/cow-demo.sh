#!/bin/bash
# =============================================================================
# cow-demo.sh - 写时复制（Copy-on-Write）演示
# =============================================================================
#
# 演示内容：
#   1. 创建包含大文件的 overlay
#   2. 读取大文件（不触发复制）
#   3. 修改大文件（触发完整复制）
#   4. 观察 CoW 对大文件的性能影响
#
# 使用方法：
#   sudo ./cow-demo.sh
#
# 前置要求：
#   - root 权限
#   - Linux 内核支持 OverlayFS
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

# 实验目录
DEMO_DIR="/tmp/cow-demo"

# 大文件大小（MB）
BIG_FILE_SIZE=50

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

# 显示目录大小
show_dir_size() {
    local dir=$1
    local label=$2
    local size
    size=$(du -sh "$dir" 2>/dev/null | cut -f1)
    echo -e "${label}: ${CYAN}${size}${NC}"
}

# 主函数
main() {
    echo -e "${GREEN}"
    echo "=============================================="
    echo "   写时复制（Copy-on-Write）演示"
    echo "=============================================="
    echo -e "${NC}"

    check_root

    # 注册清理函数
    trap cleanup EXIT

    # 清理之前的实验环境
    if [ -d "$DEMO_DIR" ]; then
        echo -e "${YELLOW}发现之前的实验目录，正在清理...${NC}"
        cleanup
    fi

    # =================================================================
    # 步骤 1：创建包含大文件的 lower 层
    # =================================================================
    echo -e "\n${GREEN}=== 步骤 1：创建包含大文件的 lower 层 ===${NC}"

    mkdir -p "$DEMO_DIR"/{lower,upper,work,merged}

    echo "创建 ${BIG_FILE_SIZE}MB 大文件..."
    dd if=/dev/zero of="$DEMO_DIR/lower/bigfile.bin" bs=1M count=$BIG_FILE_SIZE status=progress 2>&1 | tail -1

    echo ""
    echo "lower 层内容："
    ls -lh "$DEMO_DIR/lower/"

    # 添加一些小文件
    echo "small file content" > "$DEMO_DIR/lower/small.txt"
    echo "config data" > "$DEMO_DIR/lower/config.ini"

    echo ""
    show_dir_size "$DEMO_DIR/lower" "lower 层总大小"

    press_any_key

    # =================================================================
    # 步骤 2：挂载 OverlayFS
    # =================================================================
    echo -e "\n${GREEN}=== 步骤 2：挂载 OverlayFS ===${NC}"

    mount -t overlay overlay \
        -o lowerdir="$DEMO_DIR/lower",upperdir="$DEMO_DIR/upper",workdir="$DEMO_DIR/work" \
        "$DEMO_DIR/merged"

    echo -e "${GREEN}挂载成功！${NC}"
    echo ""

    echo "各层大小："
    show_dir_size "$DEMO_DIR/lower" "  lower 层"
    show_dir_size "$DEMO_DIR/upper" "  upper 层"
    echo ""

    echo "merged 视图："
    ls -lh "$DEMO_DIR/merged/"

    press_any_key

    # =================================================================
    # 步骤 3：读取大文件（不触发复制）
    # =================================================================
    echo -e "\n${GREEN}=== 步骤 3：读取大文件（不触发复制）===${NC}"

    echo "读取前 upper 层状态："
    ls -la "$DEMO_DIR/upper/"
    show_dir_size "$DEMO_DIR/upper" "upper 层大小"
    echo ""

    echo "读取大文件并计算 MD5..."
    time md5sum "$DEMO_DIR/merged/bigfile.bin"
    echo ""

    echo "读取后 upper 层状态："
    ls -la "$DEMO_DIR/upper/"
    show_dir_size "$DEMO_DIR/upper" "upper 层大小"
    echo ""

    echo -e "${YELLOW}要点：读取操作不触发复制！${NC}"
    echo "  - 文件直接从 lower 层读取"
    echo "  - upper 层仍然为空"
    echo "  - 这就是为什么多个容器可以共享同一个镜像层"

    press_any_key

    # =================================================================
    # 步骤 4：修改小文件（触发复制）
    # =================================================================
    echo -e "\n${GREEN}=== 步骤 4：修改小文件（触发复制）===${NC}"

    echo "修改前 upper 层："
    ls -la "$DEMO_DIR/upper/"
    echo ""

    echo "修改 small.txt..."
    echo "modified content" > "$DEMO_DIR/merged/small.txt"

    echo "修改后 upper 层："
    ls -la "$DEMO_DIR/upper/"
    echo ""

    echo -e "${YELLOW}要点：小文件复制很快，几乎无感知${NC}"

    press_any_key

    # =================================================================
    # 步骤 5：修改大文件（触发完整复制 - 关键演示）
    # =================================================================
    echo -e "\n${GREEN}=== 步骤 5：修改大文件（触发完整复制）===${NC}"

    echo "修改前 upper 层："
    ls -lh "$DEMO_DIR/upper/"
    show_dir_size "$DEMO_DIR/upper" "upper 层大小"
    echo ""

    echo -e "${RED}注意：即使只追加 1 个字节，也会复制整个 ${BIG_FILE_SIZE}MB 文件！${NC}"
    echo ""

    echo "追加 1 个字节到大文件..."
    START_TIME=$(date +%s.%N)

    echo "x" >> "$DEMO_DIR/merged/bigfile.bin"

    END_TIME=$(date +%s.%N)
    DURATION=$(echo "$END_TIME - $START_TIME" | bc)

    echo ""
    echo -e "复制耗时: ${CYAN}${DURATION} 秒${NC}"
    echo ""

    echo "修改后 upper 层："
    ls -lh "$DEMO_DIR/upper/"
    show_dir_size "$DEMO_DIR/upper" "upper 层大小"
    echo ""

    echo -e "${YELLOW}要点：这就是 Copy-on-Write 的「代价」${NC}"
    echo "  - 修改 1 字节 → 复制 ${BIG_FILE_SIZE}MB"
    echo "  - 这就是为什么容器不适合频繁修改大文件"
    echo "  - 数据库、日志等应该放在 volume 中"

    press_any_key

    # =================================================================
    # 步骤 6：再次修改（无需复制）
    # =================================================================
    echo -e "\n${GREEN}=== 步骤 6：再次修改同一文件（无需复制）===${NC}"

    echo "当前 upper 层大小："
    show_dir_size "$DEMO_DIR/upper" "upper 层大小"
    echo ""

    echo "再次追加内容..."
    START_TIME=$(date +%s.%N)

    echo "another byte" >> "$DEMO_DIR/merged/bigfile.bin"

    END_TIME=$(date +%s.%N)
    DURATION=$(echo "$END_TIME - $START_TIME" | bc)

    echo -e "耗时: ${CYAN}${DURATION} 秒${NC}"
    echo ""

    echo "修改后 upper 层大小："
    show_dir_size "$DEMO_DIR/upper" "upper 层大小"
    echo ""

    echo -e "${YELLOW}要点：文件已在 upper 层，无需再复制${NC}"
    echo "  - 第一次修改：复制 + 修改（慢）"
    echo "  - 后续修改：直接修改（快）"

    press_any_key

    # =================================================================
    # 步骤 7：磁盘空间分析
    # =================================================================
    echo -e "\n${GREEN}=== 步骤 7：磁盘空间分析 ===${NC}"

    echo "各层磁盘使用："
    echo "--------------------"
    show_dir_size "$DEMO_DIR/lower" "lower 层（只读）"
    show_dir_size "$DEMO_DIR/upper" "upper 层（可写）"
    echo ""

    LOWER_SIZE=$(du -s "$DEMO_DIR/lower" | cut -f1)
    UPPER_SIZE=$(du -s "$DEMO_DIR/upper" | cut -f1)
    TOTAL=$((LOWER_SIZE + UPPER_SIZE))

    echo "总磁盘占用: $(echo "$TOTAL" | awk '{printf "%.1f MB", $1/1024}')"
    echo ""

    echo -e "${YELLOW}问题演示：${NC}"
    echo "  - 原始镜像: ${BIG_FILE_SIZE}MB"
    echo "  - 修改 1 字节后: 额外占用 ${BIG_FILE_SIZE}MB"
    echo "  - 如果有 10 个这样的容器，各自修改该文件..."
    echo "    磁盘占用 = ${BIG_FILE_SIZE}MB (镜像) + 10 × ${BIG_FILE_SIZE}MB (容器层) = $((BIG_FILE_SIZE + 10 * BIG_FILE_SIZE))MB"
    echo ""

    echo -e "${RED}这就是为什么：${NC}"
    echo "  1. 日志、数据库文件应该放在 volume"
    echo "  2. Dockerfile 应该尽量减少层数"
    echo "  3. 不要在容器内生成大量临时文件"

    press_any_key

    # =================================================================
    # 步骤 8：对比测试
    # =================================================================
    echo -e "\n${GREEN}=== 步骤 8：直接写入 vs Overlay 写入对比 ===${NC}"

    echo "创建测试文件..."

    # 直接写入（不经过 overlay）
    echo "直接写入 ext4/xfs（不经过 overlay）..."
    START_TIME=$(date +%s.%N)
    dd if=/dev/zero of="/tmp/direct-write.bin" bs=1M count=$BIG_FILE_SIZE status=none
    END_TIME=$(date +%s.%N)
    DIRECT_TIME=$(echo "$END_TIME - $START_TIME" | bc)
    rm -f "/tmp/direct-write.bin"

    # 通过 overlay 写入新文件
    echo "通过 overlay 写入新文件..."
    START_TIME=$(date +%s.%N)
    dd if=/dev/zero of="$DEMO_DIR/merged/new-big.bin" bs=1M count=$BIG_FILE_SIZE status=none
    END_TIME=$(date +%s.%N)
    OVERLAY_TIME=$(echo "$END_TIME - $START_TIME" | bc)

    echo ""
    echo "写入 ${BIG_FILE_SIZE}MB 文件耗时对比："
    echo "  直接写入:   ${DIRECT_TIME} 秒"
    echo "  Overlay 写入: ${OVERLAY_TIME} 秒"
    echo ""

    # 计算百分比差异
    if command -v bc &> /dev/null; then
        DIFF_PERCENT=$(echo "scale=1; (($OVERLAY_TIME - $DIRECT_TIME) / $DIRECT_TIME) * 100" | bc)
        echo -e "${YELLOW}Overlay 写入比直接写入慢约 ${DIFF_PERCENT}%${NC}"
    fi

    press_any_key

    # =================================================================
    # 总结
    # =================================================================
    echo -e "\n${GREEN}=============================================="
    echo "   演示完成！"
    echo "==============================================${NC}"
    echo ""
    echo "关键收获："
    echo ""
    echo "  1. 读取操作不触发复制（零成本）"
    echo "     → 多容器共享镜像层的基础"
    echo ""
    echo "  2. 第一次写入触发完整复制"
    echo "     → 修改 1 字节 = 复制整个文件"
    echo ""
    echo "  3. 大文件修改有性能代价"
    echo "     → 日志、数据库应该用 volume"
    echo ""
    echo "  4. Overlay 写入比直接写入慢"
    echo "     → I/O 密集型任务应该用 volume"
    echo ""
    echo "最佳实践："
    echo "  - docker run -v /data:/app/data ..."
    echo "  - 不要在容器层存储大量数据"
    echo "  - Dockerfile 合并 RUN 命令减少层数"
    echo ""

    press_any_key

    echo "正在清理实验环境..."
}

# 运行主函数
main
