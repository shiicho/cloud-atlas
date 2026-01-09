#!/bin/bash
# =============================================================================
# 脚本名称: file_organizer.sh
# 功能说明: 遍历目录文件，按扩展名分类统计（Mini Project）
# 作者: [你的名字]
# 创建日期: 2026-01-10
# 课程: LX04-SHELL Lesson 05 - 循环结构
# =============================================================================
#
# 使用方法:
#   ./file_organizer.sh [目录]
#   ./file_organizer.sh /var/log
#   ./file_organizer.sh              # 默认当前目录
#
# =============================================================================

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 打印带颜色的消息
print_header() {
    echo -e "${BLUE}$1${NC}"
}

# 显示用法
usage() {
    echo "用法: $0 [目录]"
    echo ""
    echo "示例:"
    echo "  $0 /var/log"
    echo "  $0 ~/Documents"
    exit 1
}

# 获取文件大小（跨平台）
get_size() {
    local file="$1"
    if stat --version &>/dev/null 2>&1; then
        stat -c %s "$file" 2>/dev/null || echo 0
    else
        stat -f %z "$file" 2>/dev/null || echo 0
    fi
}

# 格式化文件大小
format_size() {
    local size=$1
    if (( size >= 1073741824 )); then
        printf "%.2f GB" "$(echo "scale=2; $size/1073741824" | bc)"
    elif (( size >= 1048576 )); then
        printf "%.2f MB" "$(echo "scale=2; $size/1048576" | bc)"
    elif (( size >= 1024 )); then
        printf "%.2f KB" "$(echo "scale=2; $size/1024" | bc)"
    else
        printf "%d B" "$size"
    fi
}

# 主函数
main() {
    local target_dir="${1:-.}"

    # 检查目录是否存在
    if [[ ! -d "$target_dir" ]]; then
        echo -e "${RED}错误: 目录不存在: $target_dir${NC}" >&2
        exit 1
    fi

    print_header "============================================"
    print_header "         文件分类统计报告"
    print_header "============================================"
    echo ""
    echo "扫描目录: $target_dir"
    echo ""

    # 使用关联数组统计（Bash 4+）
    declare -A count
    declare -A size

    # 初始化分类
    local categories=("txt" "log" "sh" "other")
    for cat in "${categories[@]}"; do
        count[$cat]=0
        size[$cat]=0
    done

    local total_files=0
    local total_size=0

    # 遍历目录中的文件（正确处理空格）
    shopt -s nullglob
    for file in "$target_dir"/*; do
        # 只处理普通文件
        [[ -f "$file" ]] || continue

        ((total_files++))

        # 获取文件大小
        local file_size
        file_size=$(get_size "$file")
        ((total_size += file_size))

        # 获取扩展名
        local filename
        filename=$(basename "$file")
        local ext="${filename##*.}"

        # 如果没有扩展名，或扩展名等于文件名
        if [[ "$ext" == "$filename" ]]; then
            ext="other"
        fi

        # 分类统计
        case "$ext" in
            txt)
                ((count[txt]++))
                ((size[txt] += file_size))
                ;;
            log)
                ((count[log]++))
                ((size[log] += file_size))
                ;;
            sh|bash)
                ((count[sh]++))
                ((size[sh] += file_size))
                ;;
            *)
                ((count[other]++))
                ((size[other] += file_size))
                ;;
        esac
    done
    shopt -u nullglob

    # 输出统计结果
    print_header "--- 分类统计 ---"
    echo ""
    printf "%-15s %-10s %-15s\n" "类型" "文件数" "总大小"
    printf "%-15s %-10s %-15s\n" "----" "------" "------"

    for cat in "${categories[@]}"; do
        local cat_name
        case "$cat" in
            txt)   cat_name="文本文件" ;;
            log)   cat_name="日志文件" ;;
            sh)    cat_name="Shell 脚本" ;;
            other) cat_name="其他文件" ;;
        esac

        if (( count[$cat] > 0 )); then
            printf "%-15s %-10d %-15s\n" "$cat_name" "${count[$cat]}" "$(format_size "${size[$cat]}")"
        fi
    done

    echo ""
    print_header "--- 总计 ---"
    echo "文件总数: $total_files"
    echo "总大小:   $(format_size "$total_size")"
    echo ""
    print_header "============================================"
}

# 处理参数
if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    usage
fi

# 执行主函数
main "$@"
