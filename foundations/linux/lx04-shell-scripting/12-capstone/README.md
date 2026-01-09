# 12 - 综合项目：自动化工具开发（Capstone: Automation Tool）

> **目标**：综合运用所有课程知识，构建一个生产级的自动化工具  
> **前置**：完成 Lessons 01-11（变量、引用、条件、循环、函数、数组、参数展开、错误处理、CLI、调试）  
> **时间**：3-4 小时  
> **实战场景**：日本 IT 企业的运维自动化脚本开发  

---

## 项目背景

你是一家日本 IT 公司的运维工程师。公司需要自动化日常运维任务，减少人工操作和人为错误。

这是典型的「運用自動化」（Operations Automation）任务，在日本 IT 现场非常常见。

### 三个项目选项

你需要选择以下**一个**项目完成（推荐选择与你未来工作最相关的）：

| 项目 | 适用场景 | 难度 |
|------|----------|------|
| **日志轮转工具** | 运维监控、定型作業 | 中等 |
| **系统健康检查** | 障害対応、初動確認 | 中等 |
| **备份与恢复工具** | 災害復旧、BCP | 较高 |

本课程将提供**日志轮转工具**的完整实现作为参考，另外两个项目提供设计框架和启动模板。

---

## 评估标准

### 技术要求（必须全部满足）

| 要求 | 检查方式 | 说明 |
|------|----------|------|
| 通过 ShellCheck | `shellcheck script.sh` | 无错误或警告 |
| 严格模式 | `set -euo pipefail` | 脚本头部包含 |
| trap 清理 | `trap cleanup EXIT` | 退出时清理临时资源 |
| 变量引用 | `"$var"` | 所有变量正确引用 |
| local 变量 | `local var` | 函数内使用局部变量 |

### 文档要求

| 交付物 | 说明 |
|--------|------|
| `--help` 输出 | 包含 Usage、Options、Examples |
| README.md | 用途说明、安装方法、使用示例 |
| 代码注释 | 复杂逻辑处有清晰注释 |

### 日本 IT 职场加分项

| 项目 | 日语术语 | 说明 |
|------|----------|------|
| 日志输出 | ログ出力 | 操作有日志记录 |
| 配置文件 | 設定ファイル | 支持外部配置 |
| 幂等性 | 冪等性（べきとうせい） | 重复执行结果一致 |
| 锁文件 | 排他制御 | 防止并发执行 |

---

## 项目 1：日志轮转工具（完整实现）

### 1.1 需求分析

日志轮转是运维的基础任务。在日本 IT 现场，这被称为「ログローテーション」。

**核心功能：**
- 按大小或日期轮转日志文件
- 压缩旧日志节省空间
- 保留指定天数的日志
- 支持多目录配置
- 锁文件防止并发执行

**为什么需要自己写？**

虽然 Linux 有 `logrotate`，但在实际工作中：
1. 某些嵌入式系统没有 logrotate
2. 需要自定义的轮转逻辑
3. 需要与监控系统集成
4. 作为学习 Shell 的综合练习

### 1.2 架构设计

![Log Rotator Architecture](images/log-rotator-architecture.png)

<details>
<summary>View ASCII source</summary>

<!-- DIAGRAM: log-rotator-architecture -->
```
日志轮转工具架构 (Log Rotator Architecture)
═══════════════════════════════════════════════════════════════════════════

主程序流程:
┌─────────────────────────────────────────────────────────────────────────┐
│                                                                          │
│  ┌──────────┐   ┌──────────┐   ┌──────────┐   ┌──────────┐              │
│  │  解析参数 │──▶│ 读取配置  │──▶│  获取锁  │──▶│  验证配置 │             │
│  └──────────┘   └──────────┘   └──────────┘   └──────────┘              │
│        │                                            │                    │
│        ▼                                            ▼                    │
│  ┌──────────────────────────────────────────────────────────────────┐   │
│  │                     对每个日志目录循环                            │   │
│  │  ┌──────────┐   ┌──────────┐   ┌──────────┐   ┌──────────┐      │   │
│  │  │  检查条件 │──▶│  轮转日志 │──▶│  压缩旧档 │──▶│  清理过期 │     │   │
│  │  │(大小/日期)│   │ (rename) │   │  (gzip)  │   │  (find)  │      │   │
│  │  └──────────┘   └──────────┘   └──────────┘   └──────────┘      │   │
│  └──────────────────────────────────────────────────────────────────┘   │
│        │                                                                 │
│        ▼                                                                 │
│  ┌──────────┐   ┌──────────┐                                            │
│  │  生成报告 │──▶│  释放锁  │                                           │
│  └──────────┘   └──────────┘                                            │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘

轮转示例:
┌─────────────────────────────────────────────────────────────────────────┐
│                                                                          │
│  轮转前:                        轮转后:                                   │
│  ┌─────────────────┐           ┌─────────────────┐                      │
│  │ app.log (10MB)  │           │ app.log (0KB)   │  ← 新文件            │
│  │ app.log.1.gz    │    ──▶    │ app.log.1.gz    │  ← 旧 app.log 压缩   │
│  │ app.log.2.gz    │           │ app.log.2.gz    │  ← 旧 .1.gz          │
│  │ app.log.3.gz    │           │ app.log.3.gz    │  ← 旧 .2.gz          │
│  └─────────────────┘           └─────────────────┘                      │
│                                (app.log.4.gz 超过保留数量，被删除)         │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘

文件命名规则:
┌─────────────────────────────────────────────────────────────────────────┐
│  app.log         当前日志文件                                            │
│  app.log.1       最近一次轮转（未压缩或压缩中）                           │
│  app.log.1.gz    最近一次轮转（已压缩）                                   │
│  app.log.2.gz    上一次轮转                                              │
│  app.log.N.gz    第 N 次轮转（N 越大越旧）                               │
└─────────────────────────────────────────────────────────────────────────┘
```
<!-- /DIAGRAM -->

</details>

### 1.3 完整实现

创建项目目录并编写脚本：

```bash
# 创建项目目录
mkdir -p ~/capstone-project/{bin,config,logs,test}
cd ~/capstone-project
```

#### 主脚本：log-rotator.sh

```bash
cat > bin/log-rotator.sh << 'EOF'
#!/usr/bin/env bash
# =============================================================================
# log-rotator.sh - 日志轮转工具
# =============================================================================
# 功能：自动轮转、压缩、清理日志文件
# 作成日：2026-01-10
# 用途：運用自動化（日本 IT 企业定型作業）
# =============================================================================

# -----------------------------------------------------------------------------
# 严格模式
# -----------------------------------------------------------------------------
set -euo pipefail
IFS=$'\n\t'

# -----------------------------------------------------------------------------
# 常量定义
# -----------------------------------------------------------------------------
readonly SCRIPT_NAME="${0##*/}"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_VERSION="1.0.0"

# 退出码
readonly EXIT_SUCCESS=0
readonly EXIT_ERROR=1
readonly EXIT_USAGE=2
readonly EXIT_LOCKED=3

# 默认配置
readonly DEFAULT_CONFIG="/etc/log-rotator/config.conf"
readonly DEFAULT_LOCKFILE="/var/run/log-rotator.lock"
readonly DEFAULT_MAX_SIZE="10M"
readonly DEFAULT_KEEP_DAYS=7
readonly DEFAULT_KEEP_COUNT=5

# -----------------------------------------------------------------------------
# 全局变量
# -----------------------------------------------------------------------------
CONFIG_FILE=""
LOCKFILE=""
DRY_RUN=false
VERBOSE=false
FORCE=false
CLEANUP_DONE=false

# 运行时配置
declare -a LOG_DIRS=()
declare -A LOG_CONFIG=()
MAX_SIZE=""
KEEP_DAYS=""
KEEP_COUNT=""

# 统计
ROTATED_COUNT=0
COMPRESSED_COUNT=0
DELETED_COUNT=0

# -----------------------------------------------------------------------------
# 颜色定义（终端支持时）
# -----------------------------------------------------------------------------
if [[ -t 1 ]]; then
    readonly C_RED='\033[0;31m'
    readonly C_GREEN='\033[0;32m'
    readonly C_YELLOW='\033[0;33m'
    readonly C_BLUE='\033[0;34m'
    readonly C_NC='\033[0m'
else
    readonly C_RED='' C_GREEN='' C_YELLOW='' C_BLUE='' C_NC=''
fi

# -----------------------------------------------------------------------------
# 日志函数
# -----------------------------------------------------------------------------
timestamp() {
    date '+%Y-%m-%d %H:%M:%S'
}

log_info() {
    echo -e "${C_GREEN}[$(timestamp)] [INFO]${C_NC} $*"
}

log_warn() {
    echo -e "${C_YELLOW}[$(timestamp)] [WARN]${C_NC} $*" >&2
}

log_error() {
    echo -e "${C_RED}[$(timestamp)] [ERROR]${C_NC} $*" >&2
}

log_debug() {
    if [[ "$VERBOSE" == true ]]; then
        echo -e "${C_BLUE}[$(timestamp)] [DEBUG]${C_NC} $*" >&2
    fi
}

# -----------------------------------------------------------------------------
# 帮助信息
# -----------------------------------------------------------------------------
usage() {
    cat << HELP
Usage: $SCRIPT_NAME [OPTIONS] [LOG_DIR ...]

日志轮转工具 - Log Rotation Tool

自动轮转、压缩、清理日志文件。支持按大小和日期轮转，
适用于日本 IT 企业的運用自動化场景。

Options:
    -c, --config FILE     配置文件路径 (default: $DEFAULT_CONFIG)
    -s, --max-size SIZE   触发轮转的最大文件大小 (default: $DEFAULT_MAX_SIZE)
                          支持 K, M, G 后缀 (e.g., 10M, 100K)
    -d, --keep-days N     保留最近 N 天的日志 (default: $DEFAULT_KEEP_DAYS)
    -k, --keep-count N    保留最近 N 个轮转文件 (default: $DEFAULT_KEEP_COUNT)
    -l, --lockfile FILE   锁文件路径 (default: $DEFAULT_LOCKFILE)
    -n, --dry-run         模拟运行，不实际修改文件
    -f, --force           强制轮转，忽略大小检查
    -v, --verbose         详细输出
    -h, --help            显示此帮助
    --version             显示版本

Arguments:
    LOG_DIR ...           要处理的日志目录（可指定多个）
                          如果不指定，从配置文件读取

Examples:
    # 使用配置文件
    $SCRIPT_NAME -c /etc/log-rotator/myapp.conf

    # 直接指定目录
    $SCRIPT_NAME -s 50M -d 14 /var/log/myapp /var/log/nginx

    # 模拟运行
    $SCRIPT_NAME -n -v /var/log/myapp

    # 强制轮转
    $SCRIPT_NAME -f /var/log/myapp

Exit Codes:
    0   成功
    1   一般错误
    2   参数错误
    3   无法获取锁（另一个实例正在运行）

Configuration File Format:
    # /etc/log-rotator/config.conf
    LOG_DIRS="/var/log/app1 /var/log/app2"
    MAX_SIZE="10M"
    KEEP_DAYS=7
    KEEP_COUNT=5

Report bugs to: <your-email@example.com>
HELP
}

version() {
    echo "$SCRIPT_NAME version $SCRIPT_VERSION"
}

# -----------------------------------------------------------------------------
# 错误处理
# -----------------------------------------------------------------------------
die() {
    log_error "$*"
    exit $EXIT_ERROR
}

die_usage() {
    log_error "$*"
    echo "Use '$SCRIPT_NAME --help' for more information." >&2
    exit $EXIT_USAGE
}

# -----------------------------------------------------------------------------
# 清理函数
# -----------------------------------------------------------------------------
cleanup() {
    if [[ "$CLEANUP_DONE" == true ]]; then
        return 0
    fi
    CLEANUP_DONE=true

    local exit_code=$?
    log_debug "执行清理..."

    # 释放锁文件
    if [[ -n "${LOCKFILE:-}" && -f "$LOCKFILE" ]]; then
        rm -f "$LOCKFILE"
        log_debug "已释放锁文件: $LOCKFILE"
    fi

    return $exit_code
}

# -----------------------------------------------------------------------------
# 信号处理
# -----------------------------------------------------------------------------
on_error() {
    local exit_code=$?
    local line_no=$1
    log_error "命令失败（行 $line_no）"
    log_error "失败命令: $BASH_COMMAND"
}

on_interrupt() {
    log_warn "收到中断信号，正在退出..."
    exit 130
}

on_terminate() {
    log_warn "收到终止信号，正在退出..."
    exit 143
}

# -----------------------------------------------------------------------------
# 设置 trap
# -----------------------------------------------------------------------------
trap cleanup EXIT
trap 'on_error $LINENO' ERR
trap on_interrupt INT
trap on_terminate TERM

# -----------------------------------------------------------------------------
# 锁文件管理
# -----------------------------------------------------------------------------
acquire_lock() {
    local lockfile="$1"
    local lockdir
    lockdir="$(dirname "$lockfile")"

    # 创建锁文件目录
    if [[ ! -d "$lockdir" ]]; then
        mkdir -p "$lockdir" 2>/dev/null || true
    fi

    # 检查现有锁
    if [[ -f "$lockfile" ]]; then
        local pid
        pid=$(cat "$lockfile" 2>/dev/null || echo "")

        if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
            log_error "另一个实例正在运行 (PID: $pid)"
            log_error "如果确定没有运行，请删除: $lockfile"
            return 1
        fi

        log_warn "发现陈旧的锁文件，清理..."
        rm -f "$lockfile"
    fi

    # 创建锁文件
    echo $$ > "$lockfile"
    log_debug "获取锁成功 (PID: $$)"
    return 0
}

# -----------------------------------------------------------------------------
# 大小解析
# -----------------------------------------------------------------------------
parse_size() {
    local size_str="$1"
    local size_bytes=0

    # 匹配数字和单位
    if [[ "$size_str" =~ ^([0-9]+)([KMG])?$ ]]; then
        local num="${BASH_REMATCH[1]}"
        local unit="${BASH_REMATCH[2]:-}"

        case "$unit" in
            K) size_bytes=$((num * 1024)) ;;
            M) size_bytes=$((num * 1024 * 1024)) ;;
            G) size_bytes=$((num * 1024 * 1024 * 1024)) ;;
            *) size_bytes=$num ;;
        esac
    else
        die_usage "无效的大小格式: $size_str (使用数字或 K/M/G 后缀)"
    fi

    echo "$size_bytes"
}

# -----------------------------------------------------------------------------
# 配置文件加载
# -----------------------------------------------------------------------------
load_config() {
    local config_file="$1"

    if [[ ! -f "$config_file" ]]; then
        log_debug "配置文件不存在: $config_file"
        return 1
    fi

    log_debug "加载配置: $config_file"

    # 安全地读取配置（避免代码注入）
    while IFS='=' read -r key value; do
        # 跳过注释和空行
        [[ "$key" =~ ^[[:space:]]*# ]] && continue
        [[ -z "$key" ]] && continue

        # 去除引号
        value="${value%\"}"
        value="${value#\"}"
        value="${value%\'}"
        value="${value#\'}"

        # 去除前后空白
        key="${key// /}"

        case "$key" in
            LOG_DIRS)
                # 分割目录列表
                IFS=' ' read -ra LOG_DIRS <<< "$value"
                ;;
            MAX_SIZE)
                [[ -z "$MAX_SIZE" ]] && MAX_SIZE="$value"
                ;;
            KEEP_DAYS)
                [[ -z "$KEEP_DAYS" ]] && KEEP_DAYS="$value"
                ;;
            KEEP_COUNT)
                [[ -z "$KEEP_COUNT" ]] && KEEP_COUNT="$value"
                ;;
        esac
    done < "$config_file"

    return 0
}

# -----------------------------------------------------------------------------
# 获取文件大小
# -----------------------------------------------------------------------------
get_file_size() {
    local file="$1"
    if [[ -f "$file" ]]; then
        stat -c %s "$file" 2>/dev/null || stat -f %z "$file" 2>/dev/null || echo 0
    else
        echo 0
    fi
}

# -----------------------------------------------------------------------------
# 轮转单个日志文件
# -----------------------------------------------------------------------------
rotate_file() {
    local log_file="$1"
    local keep_count="$2"

    if [[ ! -f "$log_file" ]]; then
        log_warn "日志文件不存在: $log_file"
        return 1
    fi

    local log_dir
    local log_name
    log_dir="$(dirname "$log_file")"
    log_name="$(basename "$log_file")"

    log_info "轮转: $log_file"

    # 从最旧到最新轮转
    # 先删除超出保留数量的文件
    local i=$keep_count
    while [[ $i -ge 1 ]]; do
        local old_file="${log_file}.$i.gz"
        local older_file="${log_file}.$((i + 1)).gz"

        if [[ -f "$old_file" ]]; then
            if [[ $i -eq $keep_count ]]; then
                # 删除超出保留数量的文件
                if [[ "$DRY_RUN" == true ]]; then
                    log_info "[DRY-RUN] 将删除: $old_file"
                else
                    rm -f "$old_file"
                    log_debug "删除旧文件: $old_file"
                    ((DELETED_COUNT++))
                fi
            else
                # 重命名
                if [[ "$DRY_RUN" == true ]]; then
                    log_info "[DRY-RUN] 将重命名: $old_file -> $older_file"
                else
                    mv "$old_file" "$older_file"
                    log_debug "重命名: $old_file -> $older_file"
                fi
            fi
        fi
        ((i--))
    done

    # 处理未压缩的 .1 文件
    if [[ -f "${log_file}.1" ]]; then
        if [[ "$DRY_RUN" == true ]]; then
            log_info "[DRY-RUN] 将压缩: ${log_file}.1"
        else
            gzip "${log_file}.1"
            log_debug "压缩: ${log_file}.1"
            ((COMPRESSED_COUNT++))
        fi

        if [[ -f "${log_file}.1.gz" && -f "${log_file}.2.gz" ]]; then
            if [[ "$DRY_RUN" != true ]]; then
                mv "${log_file}.2.gz" "${log_file}.3.gz" 2>/dev/null || true
                mv "${log_file}.1.gz" "${log_file}.2.gz"
            fi
        fi
    fi

    # 轮转当前日志文件
    if [[ "$DRY_RUN" == true ]]; then
        log_info "[DRY-RUN] 将轮转: $log_file -> ${log_file}.1"
    else
        cp "$log_file" "${log_file}.1"
        : > "$log_file"  # 清空文件（保持文件描述符）
        log_info "已轮转: $log_file"
        ((ROTATED_COUNT++))
    fi

    return 0
}

# -----------------------------------------------------------------------------
# 检查是否需要轮转
# -----------------------------------------------------------------------------
should_rotate() {
    local log_file="$1"
    local max_size_bytes="$2"

    if [[ ! -f "$log_file" ]]; then
        return 1
    fi

    # 强制轮转
    if [[ "$FORCE" == true ]]; then
        log_debug "强制轮转: $log_file"
        return 0
    fi

    # 按大小检查
    local file_size
    file_size=$(get_file_size "$log_file")

    if [[ $file_size -ge $max_size_bytes ]]; then
        log_debug "大小触发轮转: $log_file ($file_size >= $max_size_bytes)"
        return 0
    fi

    return 1
}

# -----------------------------------------------------------------------------
# 清理过期日志
# -----------------------------------------------------------------------------
cleanup_old_logs() {
    local log_dir="$1"
    local keep_days="$2"

    log_debug "清理 $keep_days 天前的日志: $log_dir"

    local old_files
    old_files=$(find "$log_dir" -name "*.gz" -type f -mtime +"$keep_days" 2>/dev/null || true)

    if [[ -z "$old_files" ]]; then
        log_debug "没有过期日志需要清理"
        return 0
    fi

    echo "$old_files" | while read -r file; do
        if [[ -n "$file" ]]; then
            if [[ "$DRY_RUN" == true ]]; then
                log_info "[DRY-RUN] 将删除过期: $file"
            else
                rm -f "$file"
                log_info "删除过期: $file"
                ((DELETED_COUNT++))
            fi
        fi
    done
}

# -----------------------------------------------------------------------------
# 处理单个目录
# -----------------------------------------------------------------------------
process_directory() {
    local log_dir="$1"
    local max_size_bytes="$2"
    local keep_count="$3"
    local keep_days="$4"

    if [[ ! -d "$log_dir" ]]; then
        log_warn "目录不存在: $log_dir"
        return 1
    fi

    log_info "处理目录: $log_dir"

    # 查找日志文件（不包括已轮转的）
    local log_files
    log_files=$(find "$log_dir" -maxdepth 1 -name "*.log" -type f ! -name "*.*.log" 2>/dev/null || true)

    if [[ -z "$log_files" ]]; then
        log_debug "没有日志文件: $log_dir"
        return 0
    fi

    # 处理每个日志文件
    echo "$log_files" | while read -r log_file; do
        if [[ -n "$log_file" ]]; then
            if should_rotate "$log_file" "$max_size_bytes"; then
                rotate_file "$log_file" "$keep_count"
            else
                log_debug "跳过（未达到轮转条件）: $log_file"
            fi
        fi
    done

    # 清理过期日志
    cleanup_old_logs "$log_dir" "$keep_days"
}

# -----------------------------------------------------------------------------
# 生成报告
# -----------------------------------------------------------------------------
generate_report() {
    echo ""
    echo "========================================"
    echo "  日志轮转完成 (Log Rotation Complete)"
    echo "========================================"
    echo "  轮转文件数: $ROTATED_COUNT"
    echo "  压缩文件数: $COMPRESSED_COUNT"
    echo "  删除文件数: $DELETED_COUNT"
    echo "  处理目录数: ${#LOG_DIRS[@]}"
    echo "========================================"
    if [[ "$DRY_RUN" == true ]]; then
        echo "  [DRY-RUN 模式 - 未实际修改文件]"
        echo "========================================"
    fi
}

# -----------------------------------------------------------------------------
# 参数解析
# -----------------------------------------------------------------------------
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -c|--config)
                [[ -n "${2:-}" ]] || die_usage "-c/--config 需要参数"
                CONFIG_FILE="$2"
                shift 2
                ;;
            --config=*)
                CONFIG_FILE="${1#*=}"
                shift
                ;;
            -s|--max-size)
                [[ -n "${2:-}" ]] || die_usage "-s/--max-size 需要参数"
                MAX_SIZE="$2"
                shift 2
                ;;
            --max-size=*)
                MAX_SIZE="${1#*=}"
                shift
                ;;
            -d|--keep-days)
                [[ -n "${2:-}" ]] || die_usage "-d/--keep-days 需要参数"
                KEEP_DAYS="$2"
                shift 2
                ;;
            --keep-days=*)
                KEEP_DAYS="${1#*=}"
                shift
                ;;
            -k|--keep-count)
                [[ -n "${2:-}" ]] || die_usage "-k/--keep-count 需要参数"
                KEEP_COUNT="$2"
                shift 2
                ;;
            --keep-count=*)
                KEEP_COUNT="${1#*=}"
                shift
                ;;
            -l|--lockfile)
                [[ -n "${2:-}" ]] || die_usage "-l/--lockfile 需要参数"
                LOCKFILE="$2"
                shift 2
                ;;
            --lockfile=*)
                LOCKFILE="${1#*=}"
                shift
                ;;
            -n|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -f|--force)
                FORCE=true
                shift
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -h|--help)
                usage
                exit $EXIT_SUCCESS
                ;;
            --version)
                version
                exit $EXIT_SUCCESS
                ;;
            --)
                shift
                break
                ;;
            -*)
                die_usage "未知选项: $1"
                ;;
            *)
                # 位置参数作为日志目录
                LOG_DIRS+=("$1")
                shift
                ;;
        esac
    done

    # 追加剩余参数
    LOG_DIRS+=("$@")
}

# -----------------------------------------------------------------------------
# 主函数
# -----------------------------------------------------------------------------
main() {
    parse_args "$@"

    log_info "日志轮转工具启动 (v$SCRIPT_VERSION)"

    # 设置默认值
    CONFIG_FILE="${CONFIG_FILE:-$DEFAULT_CONFIG}"
    LOCKFILE="${LOCKFILE:-$DEFAULT_LOCKFILE}"

    # 加载配置文件（如果存在）
    if [[ -f "$CONFIG_FILE" ]]; then
        load_config "$CONFIG_FILE"
    fi

    # 应用默认值
    MAX_SIZE="${MAX_SIZE:-$DEFAULT_MAX_SIZE}"
    KEEP_DAYS="${KEEP_DAYS:-$DEFAULT_KEEP_DAYS}"
    KEEP_COUNT="${KEEP_COUNT:-$DEFAULT_KEEP_COUNT}"

    # 检查是否有日志目录
    if [[ ${#LOG_DIRS[@]} -eq 0 ]]; then
        die_usage "没有指定日志目录。使用 -c 指定配置文件或直接提供目录路径"
    fi

    # 解析大小
    local max_size_bytes
    max_size_bytes=$(parse_size "$MAX_SIZE")

    log_debug "配置: MAX_SIZE=$MAX_SIZE ($max_size_bytes bytes)"
    log_debug "配置: KEEP_DAYS=$KEEP_DAYS"
    log_debug "配置: KEEP_COUNT=$KEEP_COUNT"
    log_debug "配置: LOG_DIRS=${LOG_DIRS[*]}"

    # 获取锁
    if ! acquire_lock "$LOCKFILE"; then
        exit $EXIT_LOCKED
    fi

    # 处理每个目录
    for log_dir in "${LOG_DIRS[@]}"; do
        process_directory "$log_dir" "$max_size_bytes" "$KEEP_COUNT" "$KEEP_DAYS"
    done

    # 生成报告
    generate_report

    log_info "日志轮转完成"
}

# -----------------------------------------------------------------------------
# 入口
# -----------------------------------------------------------------------------
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
EOF

chmod +x bin/log-rotator.sh
```

#### 配置文件示例

```bash
cat > config/log-rotator.conf << 'EOF'
# =============================================================================
# log-rotator 配置文件
# =============================================================================
# 日志轮转工具配置
# 作成日：2026-01-10
# =============================================================================

# 要处理的日志目录（空格分隔）
LOG_DIRS="/var/log/myapp /var/log/webapp"

# 触发轮转的文件大小阈值
# 支持: K (KB), M (MB), G (GB)
MAX_SIZE="10M"

# 保留最近多少天的日志
KEEP_DAYS=7

# 保留最近多少个轮转文件
KEEP_COUNT=5
EOF

echo "配置文件创建完成: config/log-rotator.conf"
```

### 1.4 测试脚本

```bash
cat > test/test-log-rotator.sh << 'EOF'
#!/bin/bash
# =============================================================================
# log-rotator 测试脚本
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
ROTATOR="$PROJECT_DIR/bin/log-rotator.sh"

# 颜色
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

TESTS_PASSED=0
TESTS_FAILED=0

# 测试函数
test_case() {
    local name="$1"
    local expected="$2"
    local actual="$3"

    if [[ "$expected" == "$actual" ]]; then
        echo -e "${GREEN}[PASS]${NC} $name"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}[FAIL]${NC} $name"
        echo "  Expected: $expected"
        echo "  Actual:   $actual"
        ((TESTS_FAILED++))
    fi
}

# 设置测试环境
setup() {
    echo "Setting up test environment..."
    TEST_DIR=$(mktemp -d)
    mkdir -p "$TEST_DIR/logs"

    # 创建测试日志文件
    dd if=/dev/zero of="$TEST_DIR/logs/app.log" bs=1M count=11 2>/dev/null
    dd if=/dev/zero of="$TEST_DIR/logs/small.log" bs=1K count=100 2>/dev/null

    echo "Test directory: $TEST_DIR"
}

# 清理测试环境
teardown() {
    echo "Cleaning up..."
    rm -rf "$TEST_DIR"
}

# 测试 1: 帮助信息
test_help() {
    echo ""
    echo "=== Test: Help Output ==="
    local output
    output=$("$ROTATOR" --help)
    if [[ "$output" == *"Usage:"* ]] && [[ "$output" == *"Options:"* ]]; then
        test_case "Help contains Usage and Options" "true" "true"
    else
        test_case "Help contains Usage and Options" "true" "false"
    fi
}

# 测试 2: 版本信息
test_version() {
    echo ""
    echo "=== Test: Version Output ==="
    local output
    output=$("$ROTATOR" --version)
    if [[ "$output" == *"version"* ]]; then
        test_case "Version output" "true" "true"
    else
        test_case "Version output" "true" "false"
    fi
}

# 测试 3: ShellCheck
test_shellcheck() {
    echo ""
    echo "=== Test: ShellCheck ==="
    if command -v shellcheck &>/dev/null; then
        if shellcheck "$ROTATOR"; then
            test_case "ShellCheck passes" "true" "true"
        else
            test_case "ShellCheck passes" "true" "false"
        fi
    else
        echo "[SKIP] ShellCheck not installed"
    fi
}

# 测试 4: Dry-run 模式
test_dry_run() {
    echo ""
    echo "=== Test: Dry-run Mode ==="
    local before_count
    local after_count

    before_count=$(ls -1 "$TEST_DIR/logs/" | wc -l)
    "$ROTATOR" -n -v -s 1M "$TEST_DIR/logs" >/dev/null 2>&1
    after_count=$(ls -1 "$TEST_DIR/logs/" | wc -l)

    test_case "Dry-run doesn't modify files" "$before_count" "$after_count"
}

# 测试 5: 实际轮转
test_rotation() {
    echo ""
    echo "=== Test: Actual Rotation ==="

    # 强制轮转
    "$ROTATOR" -f -v -s 1M "$TEST_DIR/logs" >/dev/null 2>&1 || true

    if [[ -f "$TEST_DIR/logs/app.log.1" ]] || [[ -f "$TEST_DIR/logs/app.log.1.gz" ]]; then
        test_case "Rotation creates .1 file" "true" "true"
    else
        test_case "Rotation creates .1 file" "true" "false"
    fi

    # 检查原文件被清空
    local size
    size=$(stat -c %s "$TEST_DIR/logs/app.log" 2>/dev/null || stat -f %z "$TEST_DIR/logs/app.log" 2>/dev/null || echo 999999)
    if [[ $size -lt 1000 ]]; then
        test_case "Original file is truncated" "true" "true"
    else
        test_case "Original file is truncated" "true" "false"
    fi
}

# 测试 6: 锁文件
test_lockfile() {
    echo ""
    echo "=== Test: Lock File ==="

    # 创建假锁文件
    local lockfile="/tmp/test-log-rotator-$$.lock"
    echo "99999" > "$lockfile"

    # 尝试运行（应该失败）
    if "$ROTATOR" -l "$lockfile" "$TEST_DIR/logs" 2>&1 | grep -q "正在运行"; then
        test_case "Lock file prevents concurrent run" "true" "true"
    else
        test_case "Lock file prevents concurrent run" "true" "false"
    fi

    rm -f "$lockfile"
}

# 主测试流程
main() {
    echo "========================================"
    echo "  log-rotator Test Suite"
    echo "========================================"

    setup

    test_help
    test_version
    test_shellcheck
    test_dry_run
    test_rotation
    test_lockfile

    teardown

    echo ""
    echo "========================================"
    echo "  Test Results"
    echo "========================================"
    echo -e "  ${GREEN}Passed: $TESTS_PASSED${NC}"
    echo -e "  ${RED}Failed: $TESTS_FAILED${NC}"
    echo "========================================"

    if [[ $TESTS_FAILED -eq 0 ]]; then
        exit 0
    else
        exit 1
    fi
}

main "$@"
EOF

chmod +x test/test-log-rotator.sh

echo "测试脚本创建完成: test/test-log-rotator.sh"
```

### 1.5 README 文档

```bash
cat > README.md << 'EOF'
# Log Rotator - 日志轮转工具

## 概要

日志轮转工具，自动轮转、压缩、清理日志文件。适用于日本 IT 企业的運用自動化场景。

## 功能特性

- 按文件大小触发轮转
- 自动压缩旧日志（gzip）
- 保留指定天数的日志
- 锁文件防止并发执行
- 支持配置文件
- Dry-run 模式预览
- 详细的日志输出

## 安装

```bash
# 克隆或复制到目标机器
cp bin/log-rotator.sh /usr/local/bin/
chmod +x /usr/local/bin/log-rotator.sh

# 创建配置目录
mkdir -p /etc/log-rotator
cp config/log-rotator.conf /etc/log-rotator/config.conf
```

## 使用方法

### 基本用法

```bash
# 使用配置文件
log-rotator.sh -c /etc/log-rotator/config.conf

# 直接指定目录
log-rotator.sh -s 50M -d 14 /var/log/myapp

# 模拟运行（不实际修改）
log-rotator.sh -n -v /var/log/myapp

# 强制轮转
log-rotator.sh -f /var/log/myapp
```

### 配置文件

```bash
# /etc/log-rotator/config.conf
LOG_DIRS="/var/log/app1 /var/log/app2"
MAX_SIZE="10M"
KEEP_DAYS=7
KEEP_COUNT=5
```

### Cron 定时任务

```bash
# 每天凌晨 3 点执行
0 3 * * * /usr/local/bin/log-rotator.sh -c /etc/log-rotator/config.conf >> /var/log/log-rotator.log 2>&1
```

## 选项

| 选项 | 说明 | 默认值 |
|------|------|--------|
| `-c, --config` | 配置文件路径 | /etc/log-rotator/config.conf |
| `-s, --max-size` | 触发轮转的文件大小 | 10M |
| `-d, --keep-days` | 保留天数 | 7 |
| `-k, --keep-count` | 保留文件数 | 5 |
| `-n, --dry-run` | 模拟运行 | - |
| `-f, --force` | 强制轮转 | - |
| `-v, --verbose` | 详细输出 | - |

## 测试

```bash
# 运行测试套件
./test/test-log-rotator.sh

# ShellCheck 检查
shellcheck bin/log-rotator.sh
```

## 日本 IT 职场术语

| 术语 | 含义 |
|------|------|
| ログローテーション | Log Rotation |
| 運用自動化 | Operations Automation |
| 定型作業 | Routine Task |
| 排他制御 | Exclusive Control (Lock) |

## License

MIT License

## 作成者

System Administrator
EOF

echo "README 创建完成: README.md"
```

### 1.6 运行测试

```bash
# 运行测试
cd ~/capstone-project
./test/test-log-rotator.sh

# ShellCheck 检查
shellcheck bin/log-rotator.sh
```

---

## 项目 2：系统健康检查（设计框架）

### 2.1 需求概述

系统健康检查是障害対応（故障处理）的初动确认工具。

**核心功能：**
- 检查 CPU、内存、磁盘使用率
- 检查关键服务状态
- 检查网络连通性
- 生成 HTML 或 Markdown 报告
- 支持阈值告警

### 2.2 架构设计

![System Health Check Architecture](images/health-check-architecture.png)

<details>
<summary>View ASCII source</summary>

<!-- DIAGRAM: health-check-architecture -->
```
系统健康检查架构 (System Health Check Architecture)
═══════════════════════════════════════════════════════════════════════════

检查项目:
┌─────────────────────────────────────────────────────────────────────────┐
│                                                                          │
│  ┌───────────────┐  ┌───────────────┐  ┌───────────────┐               │
│  │    CPU 检查    │  │   内存检查    │  │   磁盘检查    │               │
│  │               │  │               │  │               │               │
│  │ • 使用率      │  │ • 使用率      │  │ • 使用率      │               │
│  │ • 负载平均    │  │ • Swap 使用   │  │ • Inode 使用  │               │
│  │ • 进程数      │  │ • 可用内存    │  │ • 挂载状态    │               │
│  └───────────────┘  └───────────────┘  └───────────────┘               │
│                                                                          │
│  ┌───────────────┐  ┌───────────────┐  ┌───────────────┐               │
│  │   服务检查    │  │   网络检查    │  │   进程检查    │               │
│  │               │  │               │  │               │               │
│  │ • systemd 状态│  │ • 端口监听    │  │ • 关键进程    │               │
│  │ • 失败服务    │  │ • 远程连通    │  │ • 僵尸进程    │               │
│  │ • 自启服务    │  │ • DNS 解析    │  │ • 资源占用    │               │
│  └───────────────┘  └───────────────┘  └───────────────┘               │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘

输出格式:
┌─────────────────────────────────────────────────────────────────────────┐
│                                                                          │
│  检查结果        阈值比较         状态判定         报告生成             │
│  ┌────────┐    ┌────────┐    ┌────────┐    ┌────────┐                  │
│  │ 收集数据 │──▶│ 对比阈值 │──▶│ OK/WARN │──▶│ MD/HTML│                 │
│  │        │    │        │    │ /CRITICAL│    │ /JSON │                  │
│  └────────┘    └────────┘    └────────┘    └────────┘                  │
│                                                                          │
│  状态定义:                                                               │
│  ┌────────────────────────────────────────────────────────────────────┐ │
│  │  OK (0)       正常，所有指标在阈值内                                 │ │
│  │  WARNING (1)  警告，某些指标超过警告阈值                             │ │
│  │  CRITICAL (2) 危险，某些指标超过危险阈值                             │ │
│  │  UNKNOWN (3)  未知，检查过程出错                                     │ │
│  └────────────────────────────────────────────────────────────────────┘ │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```
<!-- /DIAGRAM -->

</details>

### 2.3 启动模板

```bash
cat > health-check-template.sh << 'TEMPLATE'
#!/usr/bin/env bash
# =============================================================================
# health-check.sh - 系统健康检查工具
# =============================================================================
# 功能：检查系统各项指标，生成健康报告
# 用途：障害対応の初動確認（日本 IT 企业）
# =============================================================================

set -euo pipefail
IFS=$'\n\t'

# -----------------------------------------------------------------------------
# 常量定义
# -----------------------------------------------------------------------------
readonly SCRIPT_NAME="${0##*/}"
readonly SCRIPT_VERSION="1.0.0"

# 阈值（使用关联数组）
declare -A WARN_THRESHOLD=(
    [cpu]=70
    [memory]=80
    [disk]=80
    [load]=4
)

declare -A CRIT_THRESHOLD=(
    [cpu]=90
    [memory]=90
    [disk]=90
    [load]=8
)

# 状态码
readonly STATUS_OK=0
readonly STATUS_WARN=1
readonly STATUS_CRIT=2
readonly STATUS_UNKNOWN=3

# 全局状态
OVERALL_STATUS=$STATUS_OK

# -----------------------------------------------------------------------------
# TODO: 实现以下函数
# -----------------------------------------------------------------------------

# 检查 CPU 使用率
check_cpu() {
    local usage
    # TODO: 使用 top/mpstat 获取 CPU 使用率
    # usage=$(...)
    # 比较阈值，返回状态
    echo "TODO: Implement CPU check"
}

# 检查内存使用率
check_memory() {
    # TODO: 使用 free 命令获取内存信息
    echo "TODO: Implement memory check"
}

# 检查磁盘使用率
check_disk() {
    # TODO: 使用 df 命令检查各分区
    echo "TODO: Implement disk check"
}

# 检查系统负载
check_load() {
    # TODO: 使用 uptime 或 /proc/loadavg
    echo "TODO: Implement load check"
}

# 检查服务状态
check_services() {
    local services=("sshd" "crond" "rsyslog")
    # TODO: 使用 systemctl 检查服务状态
    echo "TODO: Implement services check"
}

# 检查网络连通性
check_network() {
    local targets=("8.8.8.8" "google.com")
    # TODO: 使用 ping 检查连通性
    echo "TODO: Implement network check"
}

# 生成 Markdown 报告
generate_report_md() {
    # TODO: 生成 Markdown 格式报告
    echo "TODO: Implement Markdown report"
}

# 生成 HTML 报告
generate_report_html() {
    # TODO: 生成 HTML 格式报告
    echo "TODO: Implement HTML report"
}

# -----------------------------------------------------------------------------
# 主函数
# -----------------------------------------------------------------------------
main() {
    echo "System Health Check - v$SCRIPT_VERSION"
    echo "Hostname: $(hostname)"
    echo "Date: $(date)"
    echo ""

    check_cpu
    check_memory
    check_disk
    check_load
    check_services
    check_network

    generate_report_md

    exit $OVERALL_STATUS
}

main "$@"
TEMPLATE

chmod +x health-check-template.sh
echo "模板创建完成: health-check-template.sh"
```

---

## 项目 3：备份与恢复工具（设计框架）

### 3.1 需求概述

备份工具是災害復旧対策（灾难恢复）的核心。在日本企业，这属于 BCP（事業継続計画）的一部分。

**核心功能：**
- 全量和增量备份
- 压缩和加密
- 远程备份（rsync）
- 恢复指定日期版本
- 保留策略管理

### 3.2 架构设计

![Backup Tool Architecture](images/backup-architecture.png)

<details>
<summary>View ASCII source</summary>

<!-- DIAGRAM: backup-architecture -->
```
备份与恢复工具架构 (Backup Tool Architecture)
═══════════════════════════════════════════════════════════════════════════

备份策略 (3-2-1 Rule):
┌─────────────────────────────────────────────────────────────────────────┐
│                                                                          │
│  3 份副本        2 种介质        1 份异地                                │
│  ┌────────┐    ┌────────┐    ┌────────┐                                │
│  │ 原始数据 │    │ 本地磁盘 │    │ 远程存储 │                              │
│  │ 本地备份 │    │ 远程存储 │    │ (异地)  │                              │
│  │ 远程备份 │    │        │    │        │                                │
│  └────────┘    └────────┘    └────────┘                                │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘

备份类型:
┌─────────────────────────────────────────────────────────────────────────┐
│                                                                          │
│  全量备份 (Full Backup)                                                  │
│  ┌──────────────────────────────────────────────────────────────────┐   │
│  │  第1天     第2天     第3天     第4天     第5天     第6天     第7天│    │
│  │  ┌────┐   ┌────┐   ┌────┐   ┌────┐   ┌────┐   ┌────┐   ┌────┐  │   │
│  │  │FULL│   │FULL│   │FULL│   │FULL│   │FULL│   │FULL│   │FULL│  │   │
│  │  │100M│   │100M│   │100M│   │100M│   │100M│   │100M│   │100M│  │   │
│  │  └────┘   └────┘   └────┘   └────┘   └────┘   └────┘   └────┘  │   │
│  │  总计: 700M                                                      │   │
│  └──────────────────────────────────────────────────────────────────┘   │
│                                                                          │
│  增量备份 (Incremental Backup)                                           │
│  ┌──────────────────────────────────────────────────────────────────┐   │
│  │  第1天     第2天     第3天     第4天     第5天     第6天     第7天│    │
│  │  ┌────┐   ┌────┐   ┌────┐   ┌────┐   ┌────┐   ┌────┐   ┌────┐  │   │
│  │  │FULL│   │INCR│   │INCR│   │INCR│   │INCR│   │INCR│   │INCR│  │   │
│  │  │100M│   │ 5M │   │ 5M │   │ 5M │   │ 5M │   │ 5M │   │ 5M │  │   │
│  │  └────┘   └────┘   └────┘   └────┘   └────┘   └────┘   └────┘  │   │
│  │  总计: 130M（节省 81%）                                          │   │
│  └──────────────────────────────────────────────────────────────────┘   │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘

恢复流程:
┌─────────────────────────────────────────────────────────────────────────┐
│                                                                          │
│  ┌──────────┐   ┌──────────┐   ┌──────────┐   ┌──────────┐             │
│  │ 列出版本  │──▶│ 选择日期  │──▶│  验证完整 │──▶│  恢复数据 │            │
│  │          │   │          │   │  性校验   │   │          │             │
│  └──────────┘   └──────────┘   └──────────┘   └──────────┘             │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```
<!-- /DIAGRAM -->

</details>

### 3.3 启动模板

```bash
cat > backup-tool-template.sh << 'TEMPLATE'
#!/usr/bin/env bash
# =============================================================================
# backup-tool.sh - 备份与恢复工具
# =============================================================================
# 功能：增量备份、压缩、远程同步、版本恢复
# 用途：災害復旧対策、BCP（事業継続計画）
# =============================================================================

set -euo pipefail
IFS=$'\n\t'

# -----------------------------------------------------------------------------
# 常量定义
# -----------------------------------------------------------------------------
readonly SCRIPT_NAME="${0##*/}"
readonly SCRIPT_VERSION="1.0.0"

# 默认配置
readonly DEFAULT_BACKUP_DIR="/backup"
readonly DEFAULT_KEEP_DAYS=30
readonly DEFAULT_COMPRESS=true

# -----------------------------------------------------------------------------
# 子命令
# -----------------------------------------------------------------------------

# 执行备份
cmd_backup() {
    local source_dir="${1:-}"
    local backup_dir="${2:-$DEFAULT_BACKUP_DIR}"
    local full="${FULL_BACKUP:-false}"

    if [[ -z "$source_dir" ]]; then
        echo "Usage: $SCRIPT_NAME backup <source_dir> [backup_dir]" >&2
        exit 1
    fi

    echo "TODO: Implement backup"
    echo "  Source: $source_dir"
    echo "  Destination: $backup_dir"
    echo "  Full backup: $full"

    # TODO: 实现以下逻辑
    # 1. 创建备份目录结构
    # 2. 使用 rsync --link-dest 实现增量备份
    # 3. 压缩备份（可选）
    # 4. 生成校验和
    # 5. 清理过期备份
}

# 恢复数据
cmd_restore() {
    local backup_date="${1:-}"
    local restore_dir="${2:-}"

    if [[ -z "$backup_date" || -z "$restore_dir" ]]; then
        echo "Usage: $SCRIPT_NAME restore <backup_date> <restore_dir>" >&2
        exit 1
    fi

    echo "TODO: Implement restore"
    echo "  Backup date: $backup_date"
    echo "  Restore to: $restore_dir"

    # TODO: 实现以下逻辑
    # 1. 验证备份存在
    # 2. 验证校验和
    # 3. 恢复文件
    # 4. 验证恢复完整性
}

# 列出可用备份
cmd_list() {
    local backup_dir="${1:-$DEFAULT_BACKUP_DIR}"

    echo "TODO: Implement list"
    echo "  Backup dir: $backup_dir"

    # TODO: 实现以下逻辑
    # 1. 扫描备份目录
    # 2. 列出所有备份日期和大小
    # 3. 显示备份类型（全量/增量）
}

# 验证备份
cmd_verify() {
    local backup_date="${1:-}"

    echo "TODO: Implement verify"

    # TODO: 实现以下逻辑
    # 1. 读取校验和文件
    # 2. 验证每个文件的完整性
    # 3. 报告结果
}

# 清理过期备份
cmd_cleanup() {
    local keep_days="${1:-$DEFAULT_KEEP_DAYS}"

    echo "TODO: Implement cleanup"
    echo "  Keep days: $keep_days"

    # TODO: 实现以下逻辑
    # 1. 找出过期备份
    # 2. 确认删除（除非 --force）
    # 3. 删除并记录日志
}

# -----------------------------------------------------------------------------
# 帮助信息
# -----------------------------------------------------------------------------
usage() {
    cat << EOF
Usage: $SCRIPT_NAME <command> [options]

Backup and Restore Tool

Commands:
    backup <src> [dest]     Create backup
    restore <date> <dest>   Restore from backup
    list [backup_dir]       List available backups
    verify <date>           Verify backup integrity
    cleanup [keep_days]     Remove old backups

Options:
    -f, --full              Force full backup
    -c, --compress          Compress backup (default)
    -n, --dry-run           Dry run
    -v, --verbose           Verbose output
    -h, --help              Show this help

Examples:
    $SCRIPT_NAME backup /data /backup
    $SCRIPT_NAME restore 2026-01-10 /restore
    $SCRIPT_NAME list
    $SCRIPT_NAME cleanup 30
EOF
}

# -----------------------------------------------------------------------------
# 主函数
# -----------------------------------------------------------------------------
main() {
    local command="${1:-}"

    case "$command" in
        backup)
            shift
            cmd_backup "$@"
            ;;
        restore)
            shift
            cmd_restore "$@"
            ;;
        list)
            shift
            cmd_list "$@"
            ;;
        verify)
            shift
            cmd_verify "$@"
            ;;
        cleanup)
            shift
            cmd_cleanup "$@"
            ;;
        -h|--help|help|"")
            usage
            ;;
        *)
            echo "Unknown command: $command" >&2
            usage >&2
            exit 1
            ;;
    esac
}

main "$@"
TEMPLATE

chmod +x backup-tool-template.sh
echo "模板创建完成: backup-tool-template.sh"
```

---

## 评估与验收

### 最终检查清单

完成项目后，使用以下检查清单自我评估：

```bash
# 创建评估脚本
cat > evaluate-capstone.sh << 'EOF'
#!/bin/bash
# =============================================================================
# Capstone 项目评估脚本
# =============================================================================

set -euo pipefail

SCRIPT_PATH="${1:-}"
PASS=0
FAIL=0

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m'

check() {
    local desc="$1"
    local result="$2"

    if [[ "$result" == "pass" ]]; then
        echo -e "${GREEN}[PASS]${NC} $desc"
        ((PASS++))
    else
        echo -e "${RED}[FAIL]${NC} $desc"
        ((FAIL++))
    fi
}

if [[ -z "$SCRIPT_PATH" ]]; then
    echo "Usage: $0 <script_path>"
    exit 1
fi

if [[ ! -f "$SCRIPT_PATH" ]]; then
    echo "File not found: $SCRIPT_PATH"
    exit 1
fi

echo "========================================"
echo "  Capstone Project Evaluation"
echo "========================================"
echo "Script: $SCRIPT_PATH"
echo ""

# 1. 检查 ShellCheck
echo "--- Technical Requirements ---"
if command -v shellcheck &>/dev/null; then
    if shellcheck "$SCRIPT_PATH" 2>/dev/null; then
        check "ShellCheck passes" "pass"
    else
        check "ShellCheck passes" "fail"
    fi
else
    echo -e "${YELLOW}[SKIP]${NC} ShellCheck not installed"
fi

# 2. 检查严格模式
if grep -q "set -euo pipefail" "$SCRIPT_PATH"; then
    check "Uses strict mode (set -euo pipefail)" "pass"
else
    check "Uses strict mode (set -euo pipefail)" "fail"
fi

# 3. 检查 trap EXIT
if grep -q "trap.*EXIT" "$SCRIPT_PATH"; then
    check "Has EXIT trap for cleanup" "pass"
else
    check "Has EXIT trap for cleanup" "fail"
fi

# 4. 检查变量引用
unquoted=$(grep -c '\$[a-zA-Z_][a-zA-Z0-9_]*[^"]' "$SCRIPT_PATH" 2>/dev/null || echo 0)
if [[ "$unquoted" -lt 5 ]]; then
    check "Variables are properly quoted" "pass"
else
    check "Variables are properly quoted" "fail"
fi

# 5. 检查 local 变量
if grep -q "local " "$SCRIPT_PATH"; then
    check "Uses local variables in functions" "pass"
else
    check "Uses local variables in functions" "fail"
fi

# 6. 检查 --help
echo ""
echo "--- Documentation Requirements ---"
if grep -qE "\-\-help|usage\(\)" "$SCRIPT_PATH"; then
    check "Has --help option" "pass"
else
    check "Has --help option" "fail"
fi

# 7. 检查 --version
if grep -qE "\-\-version|VERSION" "$SCRIPT_PATH"; then
    check "Has --version option" "pass"
else
    check "Has --version option" "fail"
fi

# 8. 检查注释
comment_lines=$(grep -c "^[[:space:]]*#" "$SCRIPT_PATH" 2>/dev/null || echo 0)
if [[ "$comment_lines" -ge 10 ]]; then
    check "Has adequate comments (>10 lines)" "pass"
else
    check "Has adequate comments (>10 lines)" "fail"
fi

# 9. 检查日志函数
echo ""
echo "--- Japan IT Standards ---"
if grep -qE "log_info|log_error|log_warn" "$SCRIPT_PATH"; then
    check "Has logging functions" "pass"
else
    check "Has logging functions" "fail"
fi

# 10. 检查锁文件
if grep -qE "lock|flock|排他" "$SCRIPT_PATH"; then
    check "Has lock file support" "pass"
else
    check "Has lock file support" "fail"
fi

# 总结
echo ""
echo "========================================"
echo "  Evaluation Summary"
echo "========================================"
echo -e "  ${GREEN}Passed: $PASS${NC}"
echo -e "  ${RED}Failed: $FAIL${NC}"
echo "========================================"

TOTAL=$((PASS + FAIL))
PERCENT=$((PASS * 100 / TOTAL))

if [[ $PERCENT -ge 80 ]]; then
    echo -e "  ${GREEN}Score: $PERCENT% - Excellent!${NC}"
elif [[ $PERCENT -ge 60 ]]; then
    echo -e "  ${YELLOW}Score: $PERCENT% - Good${NC}"
else
    echo -e "  ${RED}Score: $PERCENT% - Needs Improvement${NC}"
fi

exit $((FAIL > 0 ? 1 : 0))
EOF

chmod +x evaluate-capstone.sh
```

运行评估：

```bash
./evaluate-capstone.sh bin/log-rotator.sh
```

---

## 职场小贴士（Japan IT Context）

### Capstone 对应的日本 IT 职场术语

| 本课内容 | 日语术语 | 场景 |
|----------|----------|------|
| 日志轮转 | ログローテーション | 運用監視、定型作業 |
| 健康检查 | ヘルスチェック | 障害対応の初動 |
| 备份恢复 | バックアップリストア | 災害復旧、BCP |
| 自动化脚本 | 運用自動化スクリプト | 定型作業の自動化 |
| 错误处理 | エラーハンドリング | 本番運用の必須要件 |
| 文档化 | ドキュメント化 | 引継ぎ、監査対応 |

### 运维脚本在日本企业的标准

在日本 IT 企业，本番環境（生产环境）的脚本需要满足以下标准：

1. **エラーハンドリング**：必须有完整的错误处理
2. **ログ出力**：所有操作都要有日志记录
3. **排他制御**：防止并发执行
4. **ドキュメント**：完整的使用说明和设计文档
5. **テスト**：有测试脚本验证功能

### 面试常见问题

**Q: 運用自動化スクリプトで重要なポイントは？**

A: エラーハンドリング、ログ出力、冪等性、ドキュメントが重要です。本番環境では失敗を想定した設計が必須で、set -euo pipefail と trap EXIT を使って安全に実行できるようにします。

**Q: このスクリプトをどう改善しますか？**

A: 具体例で回答：
- テストの追加（unit test, integration test）
- 設定ファイルの外部化
- 監視システム（Zabbix/Prometheus）との連携
- Ansible での配布自動化
- CI/CD パイプラインでの ShellCheck 実行

---

## 检查清单

完成本 Capstone 后，你应该能够：

- [ ] 综合运用变量、引用、条件、循环、函数
- [ ] 使用关联数组存储配置
- [ ] 实现 `set -euo pipefail` 严格模式
- [ ] 实现 `trap EXIT` 清理逻辑
- [ ] 实现 `trap INT TERM` 信号处理
- [ ] 实现锁文件防止并发执行
- [ ] 设计完整的 CLI 接口（getopts 或 while+case）
- [ ] 编写 `--help` 帮助信息
- [ ] 编写 README 文档
- [ ] 通过 ShellCheck 检查
- [ ] 编写测试脚本

---

## 延伸挑战

完成基础项目后，可以尝试以下扩展：

### 挑战 1：添加邮件通知

```bash
# 提示：使用 mail/sendmail 命令
send_notification() {
    local subject="$1"
    local body="$2"
    echo "$body" | mail -s "$subject" admin@example.com
}
```

### 挑战 2：Zabbix/Prometheus 集成

```bash
# 提示：输出监控系统可解析的格式
# Zabbix UserParameter 格式
echo "log_rotator.status $STATUS"

# Prometheus 格式
echo "log_rotator_rotated_total $ROTATED_COUNT"
```

### 挑战 3：配置文件验证

```bash
# 提示：在加载配置后验证必需字段
validate_config() {
    [[ -z "${LOG_DIRS:-}" ]] && die "Config: LOG_DIRS is required"
    [[ -z "${MAX_SIZE:-}" ]] && die "Config: MAX_SIZE is required"
}
```

---

## 系列导航

[<-- 11 - 调试技巧与最佳实践](../11-debugging/) | [系列首页](../)

---

## 课程总结

恭喜！完成这个 Capstone，你已经掌握了 Shell 脚本编程的核心技能：

1. **基础语法** - 变量、引用、条件、循环
2. **函数与数组** - 模块化代码、数据结构
3. **参数处理** - getopts、CLI 设计
4. **错误处理** - 严格模式、trap、信号
5. **调试与最佳实践** - ShellCheck、调试技巧

这些技能是 DevOps 和 SRE 工程师的基础能力，无论是在日本还是全球的 IT 行业都是必备技能。

**下一步学习建议**：

- [LX05-SYSTEMD](../../systemd/) - systemd 服务管理，将脚本变成服务
- [Ansible 课程](../../../automation/ansible/) - 声明式配置管理，超越 Shell 脚本
- [Docker 课程](../../../devops/docker/) - 容器化，现代运维必备

祝你在 Shell 脚本编程的道路上继续前进！
