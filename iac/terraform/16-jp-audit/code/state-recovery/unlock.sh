#!/bin/bash
# =============================================================================
# Terraform State Lock 解除スクリプト（S3 原生锁定版）
# =============================================================================
#
# 概要:
#   残留した Terraform State Lock を解除する
#   Terraform 1.10+ の S3 原生锁定（use_lockfile = true）対応
#
# 使用方法:
#   ./unlock.sh <state-bucket> <state-key>
#
# 例:
#   ./unlock.sh myproject-tfstate env/prod/terraform.tfstate
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
if [ $# -lt 2 ]; then
    echo "Usage: $0 <state-bucket> <state-key>"
    echo ""
    echo "Example:"
    echo "  $0 myproject-tfstate env/prod/terraform.tfstate"
    echo ""
    echo "Note: Terraform 1.10+ uses S3 native locking (use_lockfile = true)"
    echo "      Lock files are stored as <state-key>.tflock in S3"
    exit 1
fi

STATE_BUCKET="$1"
STATE_KEY="$2"
LOCK_KEY="${STATE_KEY}.tflock"
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
# Lock 情報の確認（S3 .tflock ファイル）
# -----------------------------------------------------------------------------
check_lock() {
    log_step "1/3: Lock 情報を確認中..."

    log_info "State Bucket: $STATE_BUCKET"
    log_info "State Key: $STATE_KEY"
    log_info "Lock Key: $LOCK_KEY"
    echo ""

    # S3 から .tflock ファイルを確認
    if aws s3 ls "s3://$STATE_BUCKET/$LOCK_KEY" &>/dev/null; then
        log_warn ".tflock ファイルが見つかりました"
        echo ""

        # Lock ファイルの内容を表示
        log_info "Lock ファイルの内容:"
        aws s3 cp "s3://$STATE_BUCKET/$LOCK_KEY" - 2>/dev/null | jq '.' || cat
        echo ""
        return 0
    else
        log_info ".tflock ファイルは存在しません（正常な状態です）"
        return 1
    fi
}

# -----------------------------------------------------------------------------
# terraform force-unlock での解除を試行
# -----------------------------------------------------------------------------
try_terraform_unlock() {
    log_step "2/3: terraform force-unlock を試行..."

    if ! command -v terraform &> /dev/null; then
        log_warn "terraform コマンドが見つかりません"
        return 1
    fi

    # terraform plan を実行して Lock ID を取得
    log_info "terraform plan で Lock ID を検出中..."
    PLAN_OUTPUT=$(terraform plan 2>&1 || true)

    if echo "$PLAN_OUTPUT" | grep -q "Error acquiring the state lock"; then
        LOCK_ID=$(echo "$PLAN_OUTPUT" | grep "ID:" | head -1 | awk '{print $2}')

        if [ -n "$LOCK_ID" ]; then
            log_info "Lock ID を検出: $LOCK_ID"
            echo ""
            log_warn "================== 警告 =================="
            log_warn "Lock を強制解除しようとしています"
            log_warn "他の terraform 作業者がいないことを確認してください"
            log_warn "=========================================="
            echo ""

            read -p "terraform force-unlock を実行しますか？ (yes/no): " confirm
            if [ "$confirm" == "yes" ]; then
                terraform force-unlock "$LOCK_ID"
                log_info "Lock 解除完了"
                return 0
            else
                log_info "キャンセルしました"
                return 1
            fi
        fi
    else
        log_info "terraform による Lock は検出されませんでした"
    fi

    return 1
}

# -----------------------------------------------------------------------------
# S3 から直接 .tflock ファイルを削除
# -----------------------------------------------------------------------------
delete_lock_file() {
    log_step "3/3: S3 から .tflock ファイルを直接削除..."
    echo ""
    log_warn "================== 警告 =================="
    log_warn ".tflock ファイルを S3 から直接削除します"
    log_warn "他の terraform 作業者がいないことを確認してください"
    log_warn "=========================================="
    echo ""

    read -p "続行しますか？ (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        log_info "キャンセルしました"
        exit 0
    fi

    # バックアップを作成
    log_info "バックアップを作成中: lock-backup-$DATE.json"
    aws s3 cp "s3://$STATE_BUCKET/$LOCK_KEY" "lock-backup-$DATE.json" 2>/dev/null || true

    # .tflock ファイルを削除
    log_info ".tflock ファイルを削除中..."
    aws s3 rm "s3://$STATE_BUCKET/$LOCK_KEY"

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
# メイン処理
# -----------------------------------------------------------------------------
main() {
    log_info "Terraform State Lock 解除スクリプト"
    log_info "（S3 原生锁定 use_lockfile = true 対応）"
    echo ""

    # Lock ファイルの存在確認
    if ! check_lock; then
        exit 0
    fi

    echo ""
    log_info "解除方法を選択してください:"
    echo "  1) terraform force-unlock（推奨）"
    echo "  2) S3 から .tflock ファイルを直接削除"
    echo "  3) キャンセル"
    echo ""

    read -p "選択 (1/2/3): " choice

    case $choice in
        1)
            try_terraform_unlock || {
                log_warn "terraform force-unlock が失敗しました"
                read -p "S3 からの直接削除を試しますか？ (yes/no): " try_s3
                if [ "$try_s3" == "yes" ]; then
                    delete_lock_file
                fi
            }
            ;;
        2)
            delete_lock_file
            ;;
        3)
            log_info "キャンセルしました"
            exit 0
            ;;
        *)
            log_error "無効な選択です"
            exit 1
            ;;
    esac
}

main "$@"
