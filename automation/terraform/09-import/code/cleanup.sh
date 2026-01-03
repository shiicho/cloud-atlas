#!/bin/bash
# =============================================================================
# cleanup.sh - 清理所有 Lesson 09 创建的资源
# =============================================================================
#
# 使用方法: ./cleanup.sh
#
# 此脚本会：
# 1. 销毁 Terraform 管理的资源
# 2. 清理本地 state 文件
# 3. 删除手动创建的安全组（如果存在）
#
# =============================================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

REGION="${AWS_REGION:-ap-northeast-1}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# 清理 Terraform 目录
cleanup_terraform_dir() {
    local dir=$1
    log_info "清理目录: $dir"

    if [[ -d "$dir" ]]; then
        cd "$dir"

        if [[ -f "terraform.tfstate" ]] || [[ -d ".terraform" ]]; then
            # 如果有 state，尝试 destroy
            if [[ -f "terraform.tfstate" ]]; then
                log_info "销毁 Terraform 资源..."
                terraform destroy -auto-approve 2>/dev/null || true
            fi

            # 清理本地文件
            rm -rf .terraform terraform.tfstate* .terraform.lock.hcl generated.tf 2>/dev/null || true
            log_success "目录已清理"
        else
            log_info "无需清理（无 state 文件）"
        fi
    else
        log_warning "目录不存在: $dir"
    fi
}

# 清理手动创建的资源
cleanup_manual_resources() {
    log_info "清理手动创建的资源..."

    # 删除遗留 EC2 实例
    LEGACY_INSTANCES=$(aws ec2 describe-instances \
        --filters "Name=tag:Name,Values=legacy-manual-instance" "Name=instance-state-name,Values=running,stopped" \
        --query 'Reservations[*].Instances[*].InstanceId' \
        --output text \
        --region "$REGION" 2>/dev/null || echo "")

    if [[ -n "$LEGACY_INSTANCES" ]]; then
        log_info "终止遗留 EC2 实例: $LEGACY_INSTANCES"
        aws ec2 terminate-instances \
            --instance-ids $LEGACY_INSTANCES \
            --region "$REGION" >/dev/null 2>&1 || true

        # 等待实例终止
        log_info "等待实例终止..."
        aws ec2 wait instance-terminated \
            --instance-ids $LEGACY_INSTANCES \
            --region "$REGION" 2>/dev/null || true

        log_success "EC2 实例已终止"
    else
        log_info "无遗留 EC2 实例"
    fi

    # 删除安全组
    SG_ID=$(aws ec2 describe-security-groups \
        --filters "Name=group-name,Values=legacy-import-demo-sg" \
        --query 'SecurityGroups[0].GroupId' \
        --output text \
        --region "$REGION" 2>/dev/null || echo "None")

    if [[ -n "$SG_ID" && "$SG_ID" != "None" ]]; then
        log_info "删除安全组: $SG_ID"
        # 等待一会儿确保 ENI 已释放
        sleep 5
        aws ec2 delete-security-group \
            --group-id "$SG_ID" \
            --region "$REGION" 2>/dev/null || log_warning "安全组删除失败（可能仍在使用）"
    else
        log_info "无遗留安全组"
    fi

    # 清理临时文件
    rm -f /tmp/legacy-instance-id.txt 2>/dev/null || true
}

# 主程序
main() {
    echo ""
    echo "============================================================"
    echo "  Lesson 09 - 资源清理"
    echo "============================================================"
    echo ""

    # 清理各个 Terraform 目录
    cleanup_terraform_dir "$SCRIPT_DIR/import-block"
    cleanup_terraform_dir "$SCRIPT_DIR/import-command"
    cleanup_terraform_dir "$SCRIPT_DIR/generated-config"

    # 清理手动创建的资源
    cleanup_manual_resources

    echo ""
    echo "============================================================"
    log_success "清理完成!"
    echo "============================================================"
    echo ""
}

main "$@"
