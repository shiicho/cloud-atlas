#!/bin/bash
# =============================================================================
# Terraform State Lock 解除スクリプト
# =============================================================================
#
# 概要:
#   残留した Terraform State Lock を解除する
#
# 使用方法:
#   ./unlock.sh <lock-table> <state-bucket> <state-key>
#
# 例:
#   ./unlock.sh myproject-terraform-locks myproject-tfstate env/prod/terraform.tfstate
#
# 警告:
#   このスクリプトは Lock を強制解除します。
#   他の作業者がいないことを確認してから実行してください。
#
# =============================================================================

set -euo pipefail

# -----------------------------------------------------------------------------
# 引数チェック
# -----------------------------------------------------------------------------
if [ $# -lt 3 ]; then
    echo "Usage: $0 <lock-table> <state-bucket> <state-key>"
    echo ""
    echo "Example:"
    echo "  $0 myproject-terraform-locks myproject-tfstate env/prod/terraform.tfstate"
    exit 1
fi

LOCK_TABLE="$1"
STATE_BUCKET="$2"
STATE_KEY="$3"
DATE=$(date +%Y%m%d-%H%M%S)

# -----------------------------------------------------------------------------
# カラー出力
# -----------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# -----------------------------------------------------------------------------
# Lock 情報の確認
# -----------------------------------------------------------------------------
check_lock() {
    log_step "1/3: Lock 情報を確認中..."

    # DynamoDB から Lock を検索
    LOCK_ID="$STATE_BUCKET/$STATE_KEY"

    log_info "検索する Lock ID パターン: $LOCK_ID"
    echo ""

    # Lock エントリを取得
    LOCK_ITEMS=$(aws dynamodb scan \
        --table-name "$LOCK_TABLE" \
        --filter-expression "contains(LockID, :prefix)" \
        --expression-attribute-values "{\":prefix\":{\"S\":\"$STATE_KEY\"}}" \
        --query 'Items' \
        --output json)

    if [ "$LOCK_ITEMS" == "[]" ]; then
        log_info "Lock が見つかりませんでした（正常な状態です）"
        exit 0
    fi

    echo "$LOCK_ITEMS" | jq '.'

    # Lock 数を取得
    LOCK_COUNT=$(echo "$LOCK_ITEMS" | jq 'length')
    log_warn "$LOCK_COUNT 件の Lock が見つかりました"
}

# -----------------------------------------------------------------------------
# Lock 解除
# -----------------------------------------------------------------------------
unlock() {
    log_step "2/3: Lock 解除の確認..."
    echo ""
    log_warn "================== 警告 =================="
    log_warn "Lock を強制解除しようとしています"
    log_warn "他の terraform 作業者がいないことを確認してください"
    log_warn "=========================================="
    echo ""

    read -p "続行しますか？ (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        log_info "キャンセルしました"
        exit 0
    fi

    log_step "3/3: Lock を解除中..."

    # Lock エントリを取得
    LOCK_ITEMS=$(aws dynamodb scan \
        --table-name "$LOCK_TABLE" \
        --filter-expression "contains(LockID, :prefix)" \
        --expression-attribute-values "{\":prefix\":{\"S\":\"$STATE_KEY\"}}" \
        --query 'Items[*].LockID.S' \
        --output text)

    for lock_id in $LOCK_ITEMS; do
        log_info "Lock を削除: $lock_id"

        aws dynamodb delete-item \
            --table-name "$LOCK_TABLE" \
            --key "{\"LockID\":{\"S\":\"$lock_id\"}}"

        log_info "削除完了: $lock_id"
    done

    echo ""
    log_info "======================================"
    log_info "Lock 解除完了"
    log_info "======================================"

    echo ""
    log_info "次のステップ:"
    echo "  1. terraform plan を実行して動作確認"
    echo "  2. 問題がある場合は terraform init を再実行"
}

# -----------------------------------------------------------------------------
# terraform コマンドでの解除を試行
# -----------------------------------------------------------------------------
try_terraform_unlock() {
    log_info "terraform force-unlock を試行中..."

    # terraform plan を実行して Lock ID を取得
    PLAN_OUTPUT=$(terraform plan 2>&1 || true)

    if echo "$PLAN_OUTPUT" | grep -q "Error acquiring the state lock"; then
        LOCK_ID=$(echo "$PLAN_OUTPUT" | grep "ID:" | head -1 | awk '{print $2}')

        if [ -n "$LOCK_ID" ]; then
            log_info "Lock ID を検出: $LOCK_ID"
            echo ""
            read -p "terraform force-unlock を実行しますか？ (yes/no): " confirm
            if [ "$confirm" == "yes" ]; then
                terraform force-unlock "$LOCK_ID"
                return 0
            fi
        fi
    else
        log_info "Lock は検出されませんでした"
        return 0
    fi

    return 1
}

# -----------------------------------------------------------------------------
# メイン処理
# -----------------------------------------------------------------------------
main() {
    log_info "Terraform State Lock 解除スクリプト"
    log_info "Lock Table: $LOCK_TABLE"
    log_info "State Bucket: $STATE_BUCKET"
    log_info "State Key: $STATE_KEY"
    echo ""

    # まず terraform コマンドでの解除を試行
    if command -v terraform &> /dev/null; then
        log_info "terraform コマンドが利用可能です"
        echo ""
        read -p "terraform force-unlock を先に試しますか？ (yes/no): " try_tf
        if [ "$try_tf" == "yes" ]; then
            if try_terraform_unlock; then
                exit 0
            fi
            echo ""
            log_info "DynamoDB からの直接削除に進みます"
        fi
    fi

    check_lock
    unlock
}

main "$@"
