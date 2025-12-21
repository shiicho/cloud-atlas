#!/bin/bash
# cleanup.sh
# 清理本课程创建的所有资源
#
# 使用方法：
#   chmod +x cleanup.sh
#   ./cleanup.sh

set -e

echo "=========================================="
echo "  Terraform Lesson 01 - 资源清理脚本"
echo "=========================================="
echo ""

# 检查 terraform 命令
if ! command -v terraform &> /dev/null; then
    echo "❌ 错误：未找到 terraform 命令"
    echo "   请确保 Terraform 已安装并在 PATH 中"
    exit 1
fi

# 检查是否在正确的目录
if [ ! -f "main.tf" ]; then
    echo "❌ 错误：当前目录没有 main.tf 文件"
    echo "   请切换到课程代码目录后再运行"
    echo "   cd ~/terraform-examples/lesson-01-first-resource/code"
    exit 1
fi

# 检查是否有 state 文件
if [ ! -f "terraform.tfstate" ]; then
    echo "ℹ️  未找到 terraform.tfstate 文件"
    echo "   可能资源已经被清理，或者尚未创建"
    exit 0
fi

# 显示当前管理的资源
echo "📋 当前 Terraform 管理的资源："
echo ""
terraform state list 2>/dev/null || echo "   (无资源)"
echo ""

# 确认清理
read -p "⚠️  确定要销毁以上所有资源吗？(yes/no): " confirm

if [ "$confirm" != "yes" ]; then
    echo "❌ 已取消清理操作"
    exit 0
fi

echo ""
echo "🗑️  开始清理资源..."
echo ""

# 执行 destroy
terraform destroy -auto-approve

echo ""
echo "✅ 资源清理完成！"
echo ""

# 可选：清理本地文件
read -p "是否同时清理本地 Terraform 文件？(.terraform/, terraform.tfstate*) (yes/no): " clean_local

if [ "$clean_local" == "yes" ]; then
    rm -rf .terraform/
    rm -f terraform.tfstate*
    rm -f .terraform.lock.hcl
    echo "✅ 本地文件已清理"
fi

echo ""
echo "=========================================="
echo "  清理完成！"
echo "=========================================="
