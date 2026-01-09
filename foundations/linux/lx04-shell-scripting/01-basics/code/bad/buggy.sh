#!/bin/bash
# =============================================================================
# 反模式演示：这个脚本故意包含常见错误
# 运行 shellcheck buggy.sh 查看问题
# =============================================================================

# 反模式 1：使用反引号代替 $()
# ShellCheck SC2006: Use $(...) notation instead of legacy backticked `...`
files=`ls`
echo $files

# 反模式 2：变量未加引号
# ShellCheck SC2086: Double quote to prevent globbing and word splitting
name=Alice
echo $name

# 反模式 3：无用的 cat
# ShellCheck SC2002: Useless use of cat
cat /etc/passwd | grep root
cat /etc/hostname | wc -c

# 这些都是真实场景中常见的错误
# 请参考 ../fixed.sh 查看修复后的版本
