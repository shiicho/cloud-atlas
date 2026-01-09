#!/bin/bash
# =============================================================================
# 文件名：logger.sh
# 功能：生产级日志函数库
# 版本：1.0.0
# 作者：Cloud Atlas
# 创建日期：2026-01-10
# =============================================================================
#
# 使用方法：
#   source /path/to/lib/logger.sh
#
# 环境变量：
#   LOG_LEVEL  - 日志级别 (DEBUG, INFO, WARN, ERROR)，默认 INFO
#   LOG_FILE   - 日志文件路径，不设置则只输出到 stderr
#   LOG_FORMAT - 日志格式 (simple, full)，默认 full
#
# 示例：
#   LOG_LEVEL=DEBUG LOG_FILE=/var/log/myapp.log source logger.sh
#   log_info "Application started"
#
# =============================================================================

# 防止重复加载
if [[ -n "${_LOGGER_SH_LOADED:-}" ]]; then
    return 0
fi
declare -g _LOGGER_SH_LOADED=1

# =============================================================================
# 配置
# =============================================================================

# 可通过环境变量覆盖
declare -g LOG_LEVEL="${LOG_LEVEL:-INFO}"
declare -g LOG_FILE="${LOG_FILE:-}"
declare -g LOG_FORMAT="${LOG_FORMAT:-full}"

# 日志级别数值（用于比较）
declare -gA _LOG_LEVEL_VALUES=(
    [DEBUG]=0
    [INFO]=1
    [WARN]=2
    [ERROR]=3
)

# 颜色代码（仅终端输出时使用）
declare -g _C_RESET='\033[0m'
declare -g _C_DEBUG='\033[36m'   # 青色
declare -g _C_INFO='\033[32m'    # 绿色
declare -g _C_WARN='\033[33m'    # 黄色
declare -g _C_ERROR='\033[31m'   # 红色

# =============================================================================
# 内部函数
# =============================================================================

# 获取调用者信息（文件名:行号）
function _logger_get_caller() {
    # BASH_SOURCE[2] 是调用 log_* 函数的文件
    # BASH_LINENO[1] 是调用 log_* 函数的行号
    local source="${BASH_SOURCE[2]:-unknown}"
    local line="${BASH_LINENO[1]:-0}"
    echo "${source##*/}:$line"
}

# 核心日志函数
function _logger_log() {
    local level="$1"
    shift
    local message="$*"

    # 级别过滤
    local current_level=${_LOG_LEVEL_VALUES[${LOG_LEVEL^^}]:-1}
    local message_level=${_LOG_LEVEL_VALUES[$level]:-1}

    if (( message_level < current_level )); then
        return 0
    fi

    # 生成时间戳
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    # 获取调用位置
    local caller
    caller=$(_logger_get_caller)

    # 格式化消息
    local formatted
    if [[ "$LOG_FORMAT" == "simple" ]]; then
        formatted="[$level] $message"
    else
        formatted="[$timestamp] [$level] [$caller] $message"
    fi

    # 输出到 stderr
    if [[ -t 2 ]]; then
        # 终端：使用颜色
        local color
        case "$level" in
            DEBUG) color="$_C_DEBUG" ;;
            INFO)  color="$_C_INFO" ;;
            WARN)  color="$_C_WARN" ;;
            ERROR) color="$_C_ERROR" ;;
            *)     color="$_C_RESET" ;;
        esac
        printf "%b%s%b\n" "$color" "$formatted" "$_C_RESET" >&2
    else
        # 非终端：无颜色
        printf "%s\n" "$formatted" >&2
    fi

    # 输出到文件（如果配置了）
    if [[ -n "$LOG_FILE" ]]; then
        printf "%s\n" "$formatted" >> "$LOG_FILE"
    fi
}

# =============================================================================
# 公开接口：日志函数
# =============================================================================

function log_debug() {
    _logger_log DEBUG "$@"
}

function log_info() {
    _logger_log INFO "$@"
}

function log_warn() {
    _logger_log WARN "$@"
}

function log_error() {
    _logger_log ERROR "$@"
}

# =============================================================================
# 公开接口：配置函数
# =============================================================================

# 设置日志级别
function logger_set_level() {
    local level="${1^^}"  # 转换为大写

    if [[ -n "${_LOG_LEVEL_VALUES[$level]:-}" ]]; then
        LOG_LEVEL="$level"
        log_debug "Log level set to: $level"
    else
        log_error "Invalid log level: $1 (valid: DEBUG, INFO, WARN, ERROR)"
        return 1
    fi
}

# 设置日志文件
function logger_set_file() {
    local file="$1"

    # 检查目录是否存在
    local dir
    dir=$(dirname "$file")

    if [[ ! -d "$dir" ]]; then
        mkdir -p "$dir" || {
            log_error "Cannot create log directory: $dir"
            return 1
        }
    fi

    # 检查文件是否可写
    if [[ -e "$file" && ! -w "$file" ]]; then
        log_error "Log file not writable: $file"
        return 1
    fi

    LOG_FILE="$file"
    log_debug "Log file set to: $file"
}

# 获取当前日志级别
function logger_get_level() {
    echo "$LOG_LEVEL"
}

# 获取当前日志文件
function logger_get_file() {
    echo "${LOG_FILE:-<stderr>}"
}

# =============================================================================
# 辅助函数
# =============================================================================

# 打印分隔线
function log_separator() {
    local char="${1:--}"
    local width="${2:-60}"
    local line
    line=$(printf "%${width}s" | tr ' ' "$char")
    log_info "$line"
}

# 打印标题
function log_section() {
    local title="$1"
    log_separator "="
    log_info "$title"
    log_separator "="
}

# 带条件的 debug 输出（用于详细调试）
function log_trace() {
    if [[ "${LOG_TRACE:-}" == "1" ]]; then
        _logger_log DEBUG "[TRACE] $*"
    fi
}
