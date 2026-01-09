#!/bin/bash
# =============================================================================
# 脚本名称: shebang-demo.sh
# 功能说明: 演示 shebang 的两种写法及其区别
# 作者: Cloud Atlas
# 创建日期: 2026-01-10
# =============================================================================
#
# Shebang 写法对比:
#   #!/bin/bash         - 绝对路径，直接调用 /bin/bash
#   #!/usr/bin/env bash - 从 PATH 查找 bash，更具可移植性
#
# 使用场景:
#   - 企业内部脚本（环境统一）: 使用 #!/bin/bash
#   - 开源项目（跨平台需求）: 使用 #!/usr/bin/env bash
#
# =============================================================================

echo "=== Shebang 演示 ==="
echo ""

# 显示当前使用的 Bash
echo "当前 Bash 路径: $BASH"
echo "Bash 版本: $BASH_VERSION"
echo ""

# 显示 Bash 在 PATH 中的位置
echo "which bash 结果: $(which bash)"
echo ""

# 在不同系统上 Bash 的常见位置：
# - Linux:  /bin/bash
# - macOS:  /bin/bash (系统自带 3.2) 或 /usr/local/bin/bash (Homebrew 安装的新版)
# - BSD:    /usr/local/bin/bash

echo "=== 建议 ==="
echo "日本企业服务器（RHEL/CentOS）: 使用 #!/bin/bash"
echo "跨平台开源项目: 使用 #!/usr/bin/env bash"
