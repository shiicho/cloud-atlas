## Summary / 変更概要

<!-- Brief description of what this PR does -->
<!-- この PR で行う変更を簡潔に説明してください -->


## Background / 背景

<!-- Why is this change needed? Link to issue/ticket -->
<!-- なぜこの変更が必要ですか？Issue/Ticket へのリンク -->

- Issue: #
- Ticket:

## Changes / 変更内容

<!-- List the specific changes made -->
<!-- 変更内容を箇条書きで記載 -->

- [ ] Change 1 / 変更点 1
- [ ] Change 2 / 変更点 2
- [ ] Change 3 / 変更点 3

## Impact Analysis / 影響範囲

<!-- Which environments/services are affected? -->
<!-- どの環境・サービスに影響がありますか？ -->

### Environments / 対象環境

- [ ] dev / 開発環境
- [ ] staging / ステージング環境
- [ ] prod / 本番環境

### Services / 影響サービス

<!-- List affected services -->
<!-- 影響を受けるサービスを記載 -->

-

### Downtime / ダウンタイム

- [ ] No downtime / ダウンタイムなし
- [ ] Brief interruption (~__ minutes) / 短時間の中断（約__分）
- [ ] Maintenance window required / メンテナンスウィンドウが必要

## Testing / テスト方法

<!-- How were these changes tested? -->
<!-- どのようにテストしましたか？ -->

### Test Commands / テストコマンド

```bash
# terraform plan output
terraform plan
```

### Test Results / テスト結果

<!-- Attach terraform plan output or test results -->
<!-- terraform plan の出力やテスト結果を添付 -->

<details>
<summary>Terraform Plan Output</summary>

```
# Paste terraform plan output here
```

</details>

## Rollback Plan / 切り戻し手順

<!-- How to revert if something goes wrong -->
<!-- 問題発生時の復旧方法 -->

### Automatic Rollback / 自動切り戻し

```bash
git revert HEAD
terraform apply
```

### Manual Rollback / 手動切り戻し

<!-- Steps if automatic rollback is not possible -->
<!-- 自動で戻せない場合の手順 -->

1.
2.
3.

### Rollback Decision Criteria / 切り戻し判断基準

- [ ] Error rate exceeds X% / エラー率が X% を超えた場合
- [ ] Response time exceeds Y ms / レスポンスタイムが Y ms を超えた場合
- [ ] User impact reported / ユーザー影響の報告があった場合

## Pre-Merge Checklist / マージ前チェックリスト

### Code Quality / コード品質

- [ ] `terraform fmt` passed / フォーマット確認済み
- [ ] `terraform validate` passed / 構文検証済み
- [ ] No hardcoded secrets / ハードコードされた機密情報なし
- [ ] Variables have descriptions / 変数に説明あり
- [ ] Resources have appropriate tags / リソースに適切なタグあり

### Documentation / ドキュメント

- [ ] README updated if needed / 必要に応じて README 更新済み
- [ ] Comments added for complex logic / 複雑なロジックにコメント追加済み
- [ ] CHANGELOG updated / CHANGELOG 更新済み

### Review / レビュー

- [ ] Self-review completed / セルフレビュー完了
- [ ] `terraform plan` reviewed / Plan 結果確認済み
- [ ] No unintended destroy/recreate / 意図しない destroy/recreate なし

## Security Considerations / セキュリティ考慮事項

<!-- Any security implications of this change? -->
<!-- この変更によるセキュリティへの影響は？ -->

- [ ] No security impact / セキュリティへの影響なし
- [ ] Security review required / セキュリティレビューが必要
- [ ] Security team notified / セキュリティチームに通知済み

## Screenshots / スクリーンショット

<!-- If applicable, add screenshots -->
<!-- 該当する場合はスクリーンショットを添付 -->

## Additional Notes / 補足事項

<!-- Any other information reviewers should know -->
<!-- レビュアーに伝えたいその他の情報 -->


---

## Reviewer Checklist / レビュアーチェックリスト

<!-- For reviewers to check before approving -->
<!-- 承認前にレビュアーが確認する項目 -->

- [ ] Plan output reviewed / Plan 出力を確認
- [ ] No unintended changes / 意図しない変更がない
- [ ] Security implications considered / セキュリティ影響を検討
- [ ] Cost implications considered / コスト影響を検討
- [ ] Rollback plan is viable / 切り戻し手順が実行可能

---

*Template version: 1.0 | Last updated: 2026-01*
