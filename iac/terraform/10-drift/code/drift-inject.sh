#!/bin/bash
# =============================================================================
# drift-inject.sh
# Drift 注入脚本 - 用于练习 Drift 检测和修复
# =============================================================================
#
# 本脚本通过 AWS CLI 直接修改资源，模拟真实世界中的 Drift 场景：
# - 有人在 Console 直接修改了标签
# - 紧急修复时绕过 Terraform 直接操作
#
# 使用方法:
#   cd drift-detect
#   terraform apply -auto-approve
#   ../drift-inject.sh
#   terraform plan  # 检测 Drift
#
# =============================================================================

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Drift 注入脚本 (Drift Injection)${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# 检查是否在正确的目录
if [ ! -f "terraform.tfstate" ]; then
    echo -e "${RED}错误: 未找到 terraform.tfstate${NC}"
    echo "请确保:"
    echo "  1. 在 drift-detect 目录下运行"
    echo "  2. 已执行 terraform apply"
    exit 1
fi

# 获取 Instance ID
INSTANCE_ID=$(terraform output -raw instance_id 2>/dev/null)

if [ -z "$INSTANCE_ID" ]; then
    echo -e "${RED}错误: 无法获取 Instance ID${NC}"
    echo "请确保已执行 terraform apply"
    exit 1
fi

echo -e "${YELLOW}目标实例: ${INSTANCE_ID}${NC}"
echo ""

# =============================================================================
# Drift 注入操作
# =============================================================================

echo -e "${GREEN}[1/3] 修改 Environment 标签...${NC}"
echo "      dev -> production"
aws ec2 create-tags \
    --resources "$INSTANCE_ID" \
    --tags Key=Environment,Value=production

echo -e "${GREEN}[2/3] 添加未定义的标签...${NC}"
echo "      ModifiedBy=console-user"
echo "      ModifiedAt=$(date +%Y-%m-%d)"
aws ec2 create-tags \
    --resources "$INSTANCE_ID" \
    --tags \
        Key=ModifiedBy,Value=console-user \
        Key=ModifiedAt,Value="$(date +%Y-%m-%d)" \
        Key=Reason,Value="Emergency hotfix simulation"

echo -e "${GREEN}[3/3] 删除 Owner 标签...${NC}"
aws ec2 delete-tags \
    --resources "$INSTANCE_ID" \
    --tags Key=Owner

# =============================================================================
# 结果报告
# =============================================================================

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Drift 注入完成！${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo "已执行的修改:"
echo -e "  ${YELLOW}1. Environment: dev -> production${NC}"
echo -e "  ${YELLOW}2. 新增标签: ModifiedBy, ModifiedAt, Reason${NC}"
echo -e "  ${YELLOW}3. 删除标签: Owner${NC}"
echo ""
echo "当前标签状态:"
aws ec2 describe-tags \
    --filters "Name=resource-id,Values=$INSTANCE_ID" \
    --query 'Tags[*].[Key,Value]' \
    --output table
echo ""
echo -e "${GREEN}下一步: 运行 terraform plan 检测 Drift${NC}"
echo ""
echo "可选操作:"
echo "  terraform apply              # 恢复到代码定义"
echo "  terraform apply -refresh-only # 接受现实状态"
echo ""
