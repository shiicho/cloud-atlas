#!/bin/bash
# =============================================================================
# Terraform State バックアップスクリプト
# =============================================================================
#
# 概要:
#   Terraform State を S3 から取得し、ローカルおよびバックアップバケットに保存
#
# 使用方法:
#   ./backup.sh <state-bucket> <state-key> [backup-bucket]
#
# 例:
#   ./backup.sh myproject-tfstate env/prod/terraform.tfstate myproject-backup
#
# =============================================================================

set -euo pipefail

# -----------------------------------------------------------------------------
# 引数チェック
# -----------------------------------------------------------------------------
if [ $# -lt 2 ]; then
    echo "Usage: $0 <state-bucket> <state-key> [backup-bucket]"
    echo ""
    echo "Examples:"
    echo "  $0 myproject-tfstate env/prod/terraform.tfstate"
    echo "  $0 myproject-tfstate env/prod/terraform.tfstate myproject-backup"
    exit 1
fi

STATE_BUCKET="$1"
STATE_KEY="$2"
BACKUP_BUCKET="${3:-}"
DATE=$(date +%Y%m%d-%H%M%S)
BACKUP_DIR="./state-backups"

# -----------------------------------------------------------------------------
# カラー出力
# -----------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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

# -----------------------------------------------------------------------------
# メイン処理
# -----------------------------------------------------------------------------
main() {
    log_info "Terraform State バックアップを開始します"
    log_info "State Bucket: $STATE_BUCKET"
    log_info "State Key: $STATE_KEY"
    log_info "Timestamp: $DATE"

    # バックアップディレクトリ作成
    mkdir -p "$BACKUP_DIR"

    # 1. 最新の State を取得
    log_info "最新の State を取得中..."
    LOCAL_BACKUP="$BACKUP_DIR/terraform-$DATE.tfstate"

    aws s3api get-object \
        --bucket "$STATE_BUCKET" \
        --key "$STATE_KEY" \
        "$LOCAL_BACKUP" > /dev/null

    # 2. バリデーション（JSON として有効か）
    log_info "State ファイルを検証中..."
    if ! jq . "$LOCAL_BACKUP" > /dev/null 2>&1; then
        log_error "State ファイルが無効な JSON です"
        exit 1
    fi

    RESOURCE_COUNT=$(jq '.resources | length' "$LOCAL_BACKUP")
    log_info "リソース数: $RESOURCE_COUNT"

    # 3. バージョン情報を取得
    log_info "State バージョン履歴を取得中..."
    aws s3api list-object-versions \
        --bucket "$STATE_BUCKET" \
        --prefix "$STATE_KEY" \
        --max-keys 10 \
        --query 'Versions[*].{VersionId:VersionId,LastModified:LastModified,Size:Size}' \
        --output table

    # 4. リモートバケットにバックアップ（オプション）
    if [ -n "$BACKUP_BUCKET" ]; then
        log_info "リモートバケット ($BACKUP_BUCKET) にバックアップ中..."
        REMOTE_KEY="terraform-state-backup/$DATE/terraform.tfstate"

        aws s3 cp "$LOCAL_BACKUP" "s3://$BACKUP_BUCKET/$REMOTE_KEY"
        log_info "リモートバックアップ完了: s3://$BACKUP_BUCKET/$REMOTE_KEY"
    fi

    # 5. メタデータを保存
    METADATA_FILE="$BACKUP_DIR/terraform-$DATE.metadata.json"
    jq -n \
        --arg bucket "$STATE_BUCKET" \
        --arg key "$STATE_KEY" \
        --arg date "$DATE" \
        --arg resources "$RESOURCE_COUNT" \
        '{
            backup_date: $date,
            source_bucket: $bucket,
            source_key: $key,
            resource_count: $resources,
            local_file: "terraform-\($date).tfstate"
        }' > "$METADATA_FILE"

    log_info "メタデータ保存: $METADATA_FILE"

    # 6. 完了
    echo ""
    log_info "======================================"
    log_info "バックアップ完了"
    log_info "======================================"
    log_info "ローカルファイル: $LOCAL_BACKUP"
    log_info "リソース数: $RESOURCE_COUNT"

    if [ -n "$BACKUP_BUCKET" ]; then
        log_info "リモートバックアップ: s3://$BACKUP_BUCKET/$REMOTE_KEY"
    fi

    echo ""
    log_info "復元コマンド（必要な場合）:"
    echo "  aws s3 cp $LOCAL_BACKUP s3://$STATE_BUCKET/$STATE_KEY"
}

main "$@"
