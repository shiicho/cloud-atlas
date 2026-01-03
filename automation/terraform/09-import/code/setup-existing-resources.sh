#!/bin/bash
# =============================================================================
# setup-existing-resources.sh
#
# 创建"遗留"资源，模拟手动在 AWS Console 创建的 EC2 实例
# 用于 Terraform Import 练习
#
# 用法: ./setup-existing-resources.sh
# =============================================================================

set -euo pipefail

# -----------------------------------------------------------------------------
# 颜色定义
# -----------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# -----------------------------------------------------------------------------
# 配置
# -----------------------------------------------------------------------------
REGION="${AWS_REGION:-ap-northeast-1}"
INSTANCE_TYPE="t3.micro"
INSTANCE_NAME="legacy-manual-instance"

# -----------------------------------------------------------------------------
# 函数
# -----------------------------------------------------------------------------
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 获取最新的 Amazon Linux 2023 AMI
get_latest_ami() {
    log_info "获取最新的 Amazon Linux 2023 AMI..."

    AMI_ID=$(aws ec2 describe-images \
        --owners amazon \
        --filters \
            "Name=name,Values=al2023-ami-2023*-x86_64" \
            "Name=state,Values=available" \
        --query 'sort_by(Images, &CreationDate)[-1].ImageId' \
        --output text \
        --region "$REGION")

    if [[ -z "$AMI_ID" || "$AMI_ID" == "None" ]]; then
        log_error "无法获取 AMI ID"
        exit 1
    fi

    log_success "AMI ID: $AMI_ID"
}

# 获取默认 VPC 和子网
get_default_vpc() {
    log_info "获取默认 VPC..."

    VPC_ID=$(aws ec2 describe-vpcs \
        --filters "Name=isDefault,Values=true" \
        --query 'Vpcs[0].VpcId' \
        --output text \
        --region "$REGION")

    if [[ -z "$VPC_ID" || "$VPC_ID" == "None" ]]; then
        log_error "无法获取默认 VPC"
        log_warning "请确保区域 $REGION 有默认 VPC"
        exit 1
    fi

    log_success "VPC ID: $VPC_ID"

    log_info "获取默认子网..."

    SUBNET_ID=$(aws ec2 describe-subnets \
        --filters "Name=vpc-id,Values=$VPC_ID" \
        --query 'Subnets[0].SubnetId' \
        --output text \
        --region "$REGION")

    if [[ -z "$SUBNET_ID" || "$SUBNET_ID" == "None" ]]; then
        log_error "无法获取子网"
        exit 1
    fi

    log_success "Subnet ID: $SUBNET_ID"
}

# 创建或获取安全组
get_or_create_security_group() {
    log_info "检查安全组..."

    SG_NAME="legacy-import-demo-sg"

    # 检查是否已存在
    SG_ID=$(aws ec2 describe-security-groups \
        --filters "Name=group-name,Values=$SG_NAME" "Name=vpc-id,Values=$VPC_ID" \
        --query 'SecurityGroups[0].GroupId' \
        --output text \
        --region "$REGION" 2>/dev/null || echo "None")

    if [[ -z "$SG_ID" || "$SG_ID" == "None" ]]; then
        log_info "创建安全组: $SG_NAME"

        SG_ID=$(aws ec2 create-security-group \
            --group-name "$SG_NAME" \
            --description "Security group for Terraform import demo" \
            --vpc-id "$VPC_ID" \
            --query 'GroupId' \
            --output text \
            --region "$REGION")

        # 添加 SSH 规则（仅用于演示，生产环境请限制 IP）
        aws ec2 authorize-security-group-ingress \
            --group-id "$SG_ID" \
            --protocol tcp \
            --port 22 \
            --cidr 0.0.0.0/0 \
            --region "$REGION" >/dev/null 2>&1 || true

        log_success "创建安全组: $SG_ID"
    else
        log_success "使用现有安全组: $SG_ID"
    fi
}

# 创建 EC2 实例
create_ec2_instance() {
    log_info "创建 EC2 实例..."
    log_info "  AMI: $AMI_ID"
    log_info "  Instance Type: $INSTANCE_TYPE"
    log_info "  Subnet: $SUBNET_ID"
    log_info "  Security Group: $SG_ID"

    INSTANCE_ID=$(aws ec2 run-instances \
        --image-id "$AMI_ID" \
        --instance-type "$INSTANCE_TYPE" \
        --subnet-id "$SUBNET_ID" \
        --security-group-ids "$SG_ID" \
        --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$INSTANCE_NAME},{Key=Environment,Value=legacy},{Key=ManagedBy,Value=manual},{Key=Purpose,Value=terraform-import-demo}]" \
        --query 'Instances[0].InstanceId' \
        --output text \
        --region "$REGION")

    if [[ -z "$INSTANCE_ID" || "$INSTANCE_ID" == "None" ]]; then
        log_error "无法创建 EC2 实例"
        exit 1
    fi

    log_success "实例已创建: $INSTANCE_ID"

    # 等待实例运行
    log_info "等待实例启动..."
    aws ec2 wait instance-running \
        --instance-ids "$INSTANCE_ID" \
        --region "$REGION"

    log_success "实例已运行!"
}

# 输出信息
print_summary() {
    echo ""
    echo "============================================================"
    echo -e "${GREEN}遗留资源创建完成!${NC}"
    echo "============================================================"
    echo ""
    echo "实例信息:"
    echo "  Instance ID:     $INSTANCE_ID"
    echo "  Instance Name:   $INSTANCE_NAME"
    echo "  Instance Type:   $INSTANCE_TYPE"
    echo "  AMI ID:          $AMI_ID"
    echo "  Subnet ID:       $SUBNET_ID"
    echo "  Security Group:  $SG_ID"
    echo "  Region:          $REGION"
    echo ""
    echo "============================================================"
    echo -e "${YELLOW}下一步: 使用此 Instance ID 进行 Terraform Import 练习${NC}"
    echo "============================================================"
    echo ""
    echo "# 方式 1: Import Block (推荐)"
    echo "cd import-block"
    echo "vim import.tf  # 将 id 改为 $INSTANCE_ID"
    echo "terraform init"
    echo "terraform plan -generate-config-out=generated.tf"
    echo "terraform apply"
    echo ""
    echo "# 方式 2: terraform import 命令"
    echo "cd import-command"
    echo "terraform init"
    echo "terraform import aws_instance.legacy $INSTANCE_ID"
    echo ""

    # 保存 Instance ID 到文件供后续使用
    echo "$INSTANCE_ID" > /tmp/legacy-instance-id.txt
    log_info "Instance ID 已保存到 /tmp/legacy-instance-id.txt"
}

# -----------------------------------------------------------------------------
# 主程序
# -----------------------------------------------------------------------------
main() {
    echo ""
    echo "============================================================"
    echo "  Terraform Import Demo - 创建遗留资源"
    echo "============================================================"
    echo ""

    # 检查 AWS CLI
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI 未安装"
        exit 1
    fi

    # 检查 AWS 凭证
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS 凭证无效或未配置"
        exit 1
    fi

    log_success "AWS CLI 已配置"

    # 执行步骤
    get_latest_ami
    get_default_vpc
    get_or_create_security_group
    create_ec2_instance
    print_summary
}

main "$@"
