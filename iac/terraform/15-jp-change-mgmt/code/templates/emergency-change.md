# 緊急変更手順書（Break-glass Emergency Change Procedure）

> 本手順書は、変更凍結期間中または通常承認フローを待てない緊急事態時に使用します。
> **事後報告書の作成は必須です。**

---

## 緊急変更とは

通常の変更管理フローを省略して実施する変更です。以下の場合にのみ使用してください：

| 緊急度 | 状況例 | 対応 |
|--------|--------|------|
| **Critical** | 本番サービス停止、セキュリティインシデント | 即時対応必須 |
| **High** | 重大な機能障害、データ損失リスク | 数時間以内に対応 |
| **Medium** | パフォーマンス低下、一部機能影響 | 通常フロー推奨 |

---

## 緊急変更フロー

### Phase 1: 緊急連絡（5分以内）

```
┌─────────────────────────────────────────────────────────────┐
│                     緊急連絡先                               │
├─────────────────────────────────────────────────────────────┤
│  1次連絡: インフラチームリーダー                             │
│     - Slack: #infra-emergency                               │
│     - 電話: XXX-XXXX-XXXX                                   │
│                                                             │
│  2次連絡（1次不在時）: SRE マネージャー                      │
│     - Slack: @sre-manager                                   │
│     - 電話: XXX-XXXX-XXXX                                   │
│                                                             │
│  3次連絡（深夜/休日）: オンコール担当                        │
│     - PagerDuty: infrastructure-oncall                      │
└─────────────────────────────────────────────────────────────┘
```

### 連絡時に伝える内容

```
【緊急変更申請】

■ 障害概要:
  - 発生日時: YYYY-MM-DD HH:MM
  - 影響範囲:
  - 現在の状況:

■ 必要な変更:
  - 変更内容:
  - 対象リソース:

■ 緊急度: Critical / High

■ 申請者: @your-name
```

---

### Phase 2: 緊急承認の取得

#### オンラインの場合

1. Slack で上記連絡を送信
2. 承認者からの「承認します」の返信を取得
3. スクリーンショットを保存（証跡用）

#### 電話の場合

1. 口頭で状況を説明
2. 承認を取得
3. 以下を記録:
   - 承認者名:
   - 承認日時:
   - 承認内容:

---

### Phase 3: Emergency Role の有効化

#### 方法 1: GitHub Secret の更新（推奨）

管理者が GitHub Secrets を更新して Emergency Role を有効化：

```bash
# 管理者が実施
gh secret set AWS_EMERGENCY_ROLE_ARN --body "arn:aws:iam::123456789012:role/TerraformEmergencyRole"
```

#### 方法 2: IAM Trust Policy の一時更新

```bash
# 管理者が実施
aws iam update-assume-role-policy \
  --role-name TerraformEmergencyRole \
  --policy-document file://emergency-trust-policy.json
```

**emergency-trust-policy.json**:
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:sub": "repo:org/repo:ref:refs/heads/hotfix-*"
        }
      }
    }
  ]
}
```

---

### Phase 4: 緊急変更の実施

#### 4.1 ブランチ作成

```bash
# 緊急変更用ブランチを作成
git checkout -b hotfix-$(date +%Y%m%d)-incident-description
```

#### 4.2 変更を実施

```bash
# 変更を実施
vim main.tf

# Plan を確認
terraform plan -out=emergency.tfplan

# Apply を実行
terraform apply emergency.tfplan
```

#### 4.3 結果を確認

```bash
# リソースの状態を確認
terraform show

# AWS Console で直接確認
aws ec2 describe-instances --instance-ids i-xxxxx
```

---

### Phase 5: 事後処理（必須）

#### 5.1 通常フローで PR を作成

```bash
# 変更をコミット
git add .
git commit -m "hotfix: [INCIDENT-XXX] 緊急変更の内容"

# PR を作成
git push -u origin hotfix-$(date +%Y%m%d)-incident-description
gh pr create --title "[EMERGENCY] 緊急変更の事後記録" --body-file emergency-pr-template.md
```

#### 5.2 事後報告書の作成

以下のテンプレートに従って事後報告書を作成してください：

---

## 緊急変更事後報告書

### 基本情報

| 項目 | 内容 |
|------|------|
| 報告日 | YYYY-MM-DD |
| 報告者 | @your-name |
| 緊急変更ID | EMG-YYYYMMDD-NNN |

### 1. インシデント概要

| 項目 | 内容 |
|------|------|
| 発生日時 | YYYY-MM-DD HH:MM |
| 検知方法 | 監視アラート / ユーザー報告 / その他 |
| 影響範囲 | |
| 影響時間 | XX 分 |

### 2. 緊急変更内容

#### 実施した変更

| 変更内容 | 対象リソース | 実施日時 |
|----------|-------------|----------|
| | | |

#### Terraform Plan/Apply ログ

```
# terraform plan の結果
```

```
# terraform apply の結果
```

### 3. 承認記録

| 項目 | 内容 |
|------|------|
| 承認者 | @approver-name |
| 承認方法 | Slack / 電話 / その他 |
| 承認日時 | YYYY-MM-DD HH:MM |
| 証跡 | スクリーンショット / 通話記録 |

### 4. タイムライン

| 時刻 | アクション | 担当者 |
|------|-----------|--------|
| HH:MM | インシデント検知 | |
| HH:MM | 緊急連絡実施 | |
| HH:MM | 承認取得 | |
| HH:MM | 変更実施 | |
| HH:MM | 復旧確認 | |
| HH:MM | 関係者への報告 | |

### 5. 根本原因分析（RCA）

#### 直接原因


#### 根本原因


### 6. 再発防止策

| 対策 | 担当者 | 期限 | ステータス |
|------|--------|------|-----------|
| | | | [ ] 未着手 [ ] 進行中 [ ] 完了 |

### 7. 教訓（Lessons Learned）


### 8. 関連リンク

- インシデントチケット: #XXX
- 事後の PR: #XXX
- 監視アラート: URL
- 関連ドキュメント: URL

---

## Emergency Role の無効化

緊急変更完了後、管理者は Emergency Role を無効化してください：

```bash
# Trust Policy を元に戻す
aws iam update-assume-role-policy \
  --role-name TerraformEmergencyRole \
  --policy-document file://normal-trust-policy.json

# または GitHub Secret を削除
gh secret remove AWS_EMERGENCY_ROLE_ARN
```

---

## 緊急変更の監査ログ

すべての緊急変更は以下で追跡されます：

1. **Git コミット履歴**: `hotfix-*` ブランチ
2. **GitHub PR**: `[EMERGENCY]` プレフィックス
3. **CloudTrail**: API 呼び出し記録
4. **事後報告書**: 社内 Wiki / Confluence

---

## 注意事項

1. **緊急変更は最後の手段です** - 可能な限り通常フローを使用してください
2. **事後報告書は必須です** - 監査時に問われます
3. **Emergency Role は一時的です** - 使用後は必ず無効化してください
4. **記録を残してください** - スクリーンショット、ログ、通話記録など

---

*このテンプレートは [cloud-atlas Terraform 課程](https://github.com/shiicho/cloud-atlas) の一部です。*
