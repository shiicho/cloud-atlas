#!/bin/bash
# =============================================================================
# 脚本名称: case_demo.sh
# 功能说明: 演示 case 语句的多种用法
# 作者: Cloud Atlas
# 创建日期: 2026-01-10
# =============================================================================
#
# case 语句语法:
#   case 表达式 in
#       模式1)
#           命令...
#           ;;
#       模式2 | 模式3)
#           命令...
#           ;;
#       *)
#           默认命令...
#           ;;
#   esac
#
# =============================================================================

# 示例 1：处理命令行参数（服务管理模式）
demo_service_control() {
    echo "=== 示例 1：服务控制命令 ==="

    local action="${1:-help}"

    case "$action" in
        start)
            echo "  [ACTION] 启动服务..."
            ;;
        stop)
            echo "  [ACTION] 停止服务..."
            ;;
        restart)
            echo "  [ACTION] 重启服务..."
            ;;
        status)
            echo "  [ACTION] 检查状态..."
            ;;
        help | --help | -h)
            echo "  [HELP] 可用命令: start|stop|restart|status"
            ;;
        *)
            echo "  [ERROR] 未知操作: $action"
            echo "  [HELP] 用法: start|stop|restart|status"
            ;;
    esac
}

# 示例 2：根据文件扩展名处理
demo_file_extension() {
    echo ""
    echo "=== 示例 2：文件扩展名处理 ==="

    local files=("document.txt" "script.sh" "archive.tar.gz" "photo.jpg" "data.unknown")

    for file in "${files[@]}"; do
        case "$file" in
            *.txt | *.md | *.rst)
                echo "  [$file] -> 文本文件，使用 cat/less 查看"
                ;;
            *.sh | *.bash | *.zsh)
                echo "  [$file] -> Shell 脚本，使用 bash 执行"
                ;;
            *.tar.gz | *.tgz)
                echo "  [$file] -> Gzip 压缩包，使用 tar -xzf 解压"
                ;;
            *.tar.bz2 | *.tbz2)
                echo "  [$file] -> Bzip2 压缩包，使用 tar -xjf 解压"
                ;;
            *.zip)
                echo "  [$file] -> ZIP 压缩包，使用 unzip 解压"
                ;;
            *.jpg | *.jpeg | *.png | *.gif | *.bmp)
                echo "  [$file] -> 图片文件，使用图片查看器打开"
                ;;
            *.mp3 | *.wav | *.flac)
                echo "  [$file] -> 音频文件，使用播放器播放"
                ;;
            *.mp4 | *.avi | *.mkv)
                echo "  [$file] -> 视频文件，使用视频播放器播放"
                ;;
            *)
                echo "  [$file] -> 未知类型，无法确定处理方式"
                ;;
        esac
    done
}

# 示例 3：使用字符类模式
demo_character_class() {
    echo ""
    echo "=== 示例 3：字符类模式（处理用户确认）==="

    local responses=("Yes" "y" "NO" "n" "maybe" "Y")

    for response in "${responses[@]}"; do
        case "$response" in
            [Yy])
                echo "  [$response] -> 确认（单字符 Y/y）"
                ;;
            [Yy][Ee][Ss])
                echo "  [$response] -> 确认（Yes 变体）"
                ;;
            [Nn])
                echo "  [$response] -> 拒绝（单字符 N/n）"
                ;;
            [Nn][Oo])
                echo "  [$response] -> 拒绝（No 变体）"
                ;;
            *)
                echo "  [$response] -> 无效响应，请输入 yes 或 no"
                ;;
        esac
    done
}

# 示例 4：处理命令行选项
demo_options() {
    echo ""
    echo "=== 示例 4：命令行选项处理 ==="

    local options=("-v" "--version" "-h" "--help" "-f" "--force" "-x")

    for opt in "${options[@]}"; do
        case "$opt" in
            -v | --version)
                echo "  [$opt] -> 显示版本信息"
                ;;
            -h | --help)
                echo "  [$opt] -> 显示帮助信息"
                ;;
            -f | --force)
                echo "  [$opt] -> 强制执行"
                ;;
            -*)
                echo "  [$opt] -> 未知选项"
                ;;
        esac
    done
}

# 示例 5：实际应用 - 根据操作系统执行不同命令
demo_os_detection() {
    echo ""
    echo "=== 示例 5：操作系统检测 ==="

    local os_type
    os_type=$(uname -s)

    case "$os_type" in
        Linux)
            echo "  检测到 Linux 系统"
            echo "  包管理器: apt/yum/dnf"
            ;;
        Darwin)
            echo "  检测到 macOS 系统"
            echo "  包管理器: brew"
            ;;
        MINGW* | CYGWIN* | MSYS*)
            echo "  检测到 Windows (Git Bash/Cygwin/MSYS)"
            echo "  包管理器: choco/scoop"
            ;;
        FreeBSD)
            echo "  检测到 FreeBSD 系统"
            echo "  包管理器: pkg"
            ;;
        *)
            echo "  未知操作系统: $os_type"
            ;;
    esac
}

# 主程序
main() {
    echo "============================================"
    echo "       case 语句用法演示"
    echo "============================================"

    # 运行所有演示
    demo_service_control "${1:-status}"
    demo_file_extension
    demo_character_class
    demo_options
    demo_os_detection

    echo ""
    echo "============================================"
    echo "演示完成！"
}

# 执行主函数
main "$@"
