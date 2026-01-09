#!/bin/bash
# =============================================================================
# 脚本名称: fixed.sh
# 功能说明: 修复后的脚本 - 对比 bad/buggy.sh
# 作者: Cloud Atlas
# 创建日期: 2026-01-10
# =============================================================================

# 修复 1：使用 $() 代替反引号
# $() 更易读，支持嵌套
files=$(ls)
echo "$files"

# 修复 2：变量加双引号
# 防止 word splitting 和 glob expansion
name="Alice"
echo "$name"

# 修复 3：去掉无用的 cat
# 直接把文件作为参数传给命令
grep root /etc/passwd
wc -c < /etc/hostname

# 运行 shellcheck fixed.sh 验证：应该没有警告
