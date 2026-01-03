#!/bin/bash
# =============================================================================
# Terraform State リストアスクリプト
# =============================================================================
#
# 概要:
#   S3 Versioning から過去の Terraform State を復元する
#
# 使用方法:
#   ./restore.sh <state-bucket> <state-key> [version-id]
#
# 例:
#   # バージョン一覧を表示（version-id 省略時）
#   ./restore.sh myproject-tfstate env/prod/terraform.tfstate
#
#   # 特定バージョンを復元
#   ./restore.sh myproject-tfstate env/prod/terraform.tfstate ABC123...
#
# =============================================================================

set -euo pipefail

# -----------------------------------------------------------------------------
# 引数チェック
# -----------------------------------------------------------------------------
if [ $# -lt 2 ]; then
    echo "Usage: $0 <state-bucket> <state-key> [version-id]"
    echo ""
    echo "Examples:"
    echo "  $0 myproject-tfstate env/prod/terraform.tfstate"
    echo "  $0 myproject-tfstate env/prod/terraform.tfstate ABC123..."
    exit 1
fi

STATE_BUCKET="$1"
STATE_KEY="$2"
VERSION_ID="${3:-}"
DATE=$(date +%Y%m%d-%H%M%S)
BACKUP_DIR="./state-backups"

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
# バージョン一覧表示
# -----------------------------------------------------------------------------
list_versions() {
    log_info "State バージョン一覧を取得中..."
    echo ""

    aws s3api list-object-versions \
        --bucket "$STATE_BUCKET" \
        --prefix "$STATE_KEY" \
        --max-keys 20 \
        --query 'Versions[*].{VersionId:VersionId,LastModified:LastModified,Size:Size,IsLatest:IsLatest}' \
        --output table

    echo ""
    log_info "復元するには以下のコマンドを実行:"
    echo "  $0 $STATE_BUCKET $STATE_KEY <VersionId>"
}

# -----------------------------------------------------------------------------
# バージョン復元
# -----------------------------------------------------------------------------
restore_version() {
    local version_id="$1"

    log_step "1/5: 復元前の確認"
    echo ""
    log_warn "================== 警告 =================="
    log_warn "State バージョン $version_id を復元します"
    log_warn "現在の State は上書きされます"
    log_warn "=========================================="
    echo ""

    read -p "続行しますか？ (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        log_info "キャンセルしました"
        exit 0
    fi

    # バックアップディレクトリ作成
    mkdir -p "$BACKUP_DIR"

    log_step "2/5: 現在の State をバックアップ中..."
    CURRENT_BACKUP="$BACKUP_DIR/terraform-current-$DATE.tfstate"

    aws s3api get-object \
        --bucket "$STATE_BUCKET" \
        --key "$STATE_KEY" \
        "$CURRENT_BACKUP" > /dev/null 2>&1 || true

    if [ -f "$CURRENT_BACKUP" ]; then
        log_info "現在の State をバックアップ: $CURRENT_BACKUP"
    else
        log_warn "現在の State が取得できませんでした（新規作成または破損）"
    fi

    log_step "3/5: 指定バージョンを取得中..."
    RESTORE_FILE="$BACKUP_DIR/terraform-restore-$DATE.tfstate"

    aws s3api get-object \
        --bucket "$STATE_BUCKET" \
        --key "$STATE_KEY" \
        --version-id "$version_id" \
        "$RESTORE_FILE" > /dev/null

    # バリデーション
    log_step "4/5: State ファイルを検証中..."
    if ! jq . "$RESTORE_FILE" > /dev/null 2>&1; then
        log_error "復元対象の State ファイルが無効な JSON です"
        exit 1
    fi

    RESOURCE_COUNT=$(jq '.resources | length' "$RESTORE_FILE")
    log_info "復元対象のリソース数: $RESOURCE_COUNT"

    # 復元実行
    log_step "5/5: State を復元中..."
    aws s3api copy-object \
        --bucket "$STATE_BUCKET" \
        --copy-source "$STATE_BUCKET/$STATE_KEY?versionId=$version_id" \
        --key "$STATE_KEY" > /dev/null

    echo ""
    log_info "======================================"
    log_info "復元完了"
    log_info "======================================"
    log_info "復元元バージョン: $version_id"
    log_info "リソース数: $RESOURCE_COUNT"
    log_info "バックアップファイル: $CURRENT_BACKUP"

    echo ""
    log_warn "次のステップ:"
    echo "  1. terraform plan で差分を確認"
    echo "  2. 想定外の差分がある場合は調査"
    echo "  3. 問題なければ terraform apply で同期"
    echo ""
    echo "  # 復元を取り消す場合（バックアップから戻す）:"
    echo "  aws s3 cp $CURRENT_BACKUP s3://$STATE_BUCKET/$STATE_KEY"
}

# -----------------------------------------------------------------------------
# メイン処理
# -----------------------------------------------------------------------------
main() {
    log_info "Terraform State リストアスクリプト"
    log_info "State Bucket: $STATE_BUCKET"
    log_info "State Key: $STATE_KEY"
    echo ""

    if [ -z "$VERSION_ID" ]; then
        list_versions
    else
        restore_version "$VERSION_ID"
    fi
}

main "$@"
