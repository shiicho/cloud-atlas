#!/bin/bash
# =============================================================================
# 脚本名称: library-pattern.sh
# 功能说明: 演示如何创建和使用可复用的函数库
# 作者: Cloud Atlas
# 创建日期: 2026-01-10
# =============================================================================

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/../lib"

# =============================================================================
# 内联的迷你函数库（实际项目中应该放在单独文件）
# =============================================================================

# 防止重复加载
if [[ -z "${_DEMO_LIB_LOADED:-}" ]]; then
    declare -g _DEMO_LIB_LOADED=1

    # 日志级别
    declare -g LOG_LEVEL="${LOG_LEVEL:-INFO}"

    # 日志级别数值
    declare -gA _LEVELS=([DEBUG]=0 [INFO]=1 [WARN]=2 [ERROR]=3)

    # 内部日志函数
    function _log() {
        local level="$1"
        shift
        local message="$*"

        # 级别过滤
        local current=${_LEVELS[$LOG_LEVEL]:-1}
        local target=${_LEVELS[$level]:-1}
        (( target < current )) && return 0

        # 格式化输出
        local ts
        ts=$(date '+%Y-%m-%d %H:%M:%S')
        printf "[%s] [%-5s] %s\n" "$ts" "$level" "$message" >&2
    }

    # 公开接口
    function log_debug() { _log DEBUG "$@"; }
    function log_info()  { _log INFO "$@"; }
    function log_warn()  { _log WARN "$@"; }
    function log_error() { _log ERROR "$@"; }

    # 工具函数
    function demo_lib_version() {
        echo "1.0.0"
    }

    function demo_lib_check_command() {
        local cmd="$1"
        if command -v "$cmd" &>/dev/null; then
            return 0
        else
            return 1
        fi
    }

    function demo_lib_require_command() {
        local cmd="$1"
        if ! demo_lib_check_command "$cmd"; then
            log_error "Required command not found: $cmd"
            return 1
        fi
        return 0
    }
fi

# =============================================================================
# 使用函数库的主程序
# =============================================================================

echo "=== 函数库模式演示 ==="
echo ""

# 显示库版本
echo "函数库版本: $(demo_lib_version)"
echo ""

# 使用日志函数
echo "--- 默认日志级别 (INFO) ---"
log_debug "这条不会显示"
log_info "这是 INFO 消息"
log_warn "这是 WARN 消息"
log_error "这是 ERROR 消息"

echo ""
echo "--- 设置为 DEBUG 级别 ---"
LOG_LEVEL=DEBUG
log_debug "现在 DEBUG 也会显示"

echo ""
echo "--- 命令检查函数 ---"

# 检查常用命令
for cmd in bash grep nonexistent_cmd_12345; do
    if demo_lib_check_command "$cmd"; then
        echo "$cmd: 存在"
    else
        echo "$cmd: 不存在"
    fi
done

echo ""
echo "--- require 模式 ---"
LOG_LEVEL=ERROR  # 只显示错误
demo_lib_require_command "bash" && echo "bash 检查通过"
demo_lib_require_command "nonexistent_cmd" || echo "nonexistent_cmd 检查失败"

echo ""
echo "=== 函数库最佳实践 ==="
cat << 'EOF'
1. 防止重复加载：
   if [[ -n "${_MY_LIB_LOADED:-}" ]]; then return 0; fi
   declare -g _MY_LIB_LOADED=1

2. 使用命名前缀避免冲突：
   function mylib_init() { ... }
   function mylib_cleanup() { ... }

3. 提供版本信息：
   function mylib_version() { echo "1.0.0"; }

4. 检查依赖：
   function mylib_require_command() { ... }

5. 分离公开接口和内部函数：
   function _mylib_internal() { ... }  # 内部，下划线前缀
   function mylib_public() { ... }     # 公开接口
EOF
