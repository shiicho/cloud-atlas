# =============================================================================
# Outputs - IAM Role の出力値
# =============================================================================
#
# 作成した IAM Role の ARN などを出力します。
# GitHub Secrets に設定する値として使用します。
#
# =============================================================================

# -----------------------------------------------------------------------------
# OIDC Provider
# -----------------------------------------------------------------------------

output "oidc_provider_arn" {
  description = "GitHub OIDC Provider の ARN"
  value       = aws_iam_openid_connect_provider.github.arn
}

output "oidc_provider_url" {
  description = "GitHub OIDC Provider の URL"
  value       = aws_iam_openid_connect_provider.github.url
}

# -----------------------------------------------------------------------------
# Plan Role
# -----------------------------------------------------------------------------

output "plan_role_arn" {
  description = "Plan Role の ARN - GitHub Secrets 'AWS_PLAN_ROLE_ARN' に設定"
  value       = aws_iam_role.terraform_plan.arn
}

output "plan_role_name" {
  description = "Plan Role の名前"
  value       = aws_iam_role.terraform_plan.name
}

# -----------------------------------------------------------------------------
# Apply Role
# -----------------------------------------------------------------------------

output "apply_role_arn" {
  description = "Apply Role の ARN - GitHub Secrets 'AWS_APPLY_ROLE_ARN' に設定"
  value       = aws_iam_role.terraform_apply.arn
}

output "apply_role_name" {
  description = "Apply Role の名前"
  value       = aws_iam_role.terraform_apply.name
}

# -----------------------------------------------------------------------------
# Emergency Role
# -----------------------------------------------------------------------------

output "emergency_role_arn" {
  description = "Emergency Role の ARN - 緊急時のみ使用"
  value       = aws_iam_role.terraform_emergency.arn
}

output "emergency_role_name" {
  description = "Emergency Role の名前"
  value       = aws_iam_role.terraform_emergency.name
}

# -----------------------------------------------------------------------------
# GitHub Secrets 設定用コマンド
# -----------------------------------------------------------------------------

output "github_secrets_commands" {
  description = "GitHub Secrets を設定するためのコマンド"
  value       = <<-EOT

    # ================================================================
    # GitHub Secrets 設定コマンド
    # ================================================================
    #
    # 以下のコマンドを実行して GitHub Secrets を設定してください。
    # gh CLI がインストールされている必要があります。
    #
    # ================================================================

    # Plan Role ARN を設定
    gh secret set AWS_PLAN_ROLE_ARN --body "${aws_iam_role.terraform_plan.arn}"

    # Apply Role ARN を設定
    gh secret set AWS_APPLY_ROLE_ARN --body "${aws_iam_role.terraform_apply.arn}"

    # Emergency Role ARN を設定（オプション - 緊急時用）
    # gh secret set AWS_EMERGENCY_ROLE_ARN --body "${aws_iam_role.terraform_emergency.arn}"

    # ================================================================
    # 確認コマンド
    # ================================================================

    # 設定された Secrets を確認
    gh secret list

  EOT
}

# -----------------------------------------------------------------------------
# Emergency Role 有効化コマンド
# -----------------------------------------------------------------------------

output "emergency_role_enable_command" {
  description = "緊急時に Emergency Role を有効化するコマンド"
  value       = <<-EOT

    # ================================================================
    # Emergency Role 有効化コマンド（緊急時のみ使用）
    # ================================================================
    #
    # 以下のコマンドで Emergency Role を有効化します。
    # 緊急対応完了後は必ず無効化してください。
    #
    # ================================================================

    # 有効化
    aws iam update-assume-role-policy \
      --role-name ${aws_iam_role.terraform_emergency.name} \
      --policy-document '${local.emergency_trust_policy_enabled}'

    # 無効化（緊急対応完了後）
    aws iam update-assume-role-policy \
      --role-name ${aws_iam_role.terraform_emergency.name} \
      --policy-document '{"Version":"2012-10-17","Statement":[{"Sid":"DenyAll","Effect":"Deny","Principal":"*","Action":"sts:AssumeRole"}]}'

  EOT
}

# -----------------------------------------------------------------------------
# サマリー
# -----------------------------------------------------------------------------

output "summary" {
  description = "設定サマリー"
  value       = <<-EOT

    ================================================================
    Terraform 変更管理 IAM Role 設定完了
    ================================================================

    OIDC Provider:
      ARN: ${aws_iam_openid_connect_provider.github.arn}

    Plan Role (PR 用 - 読み取り専用):
      ARN:  ${aws_iam_role.terraform_plan.arn}
      Name: ${aws_iam_role.terraform_plan.name}

    Apply Role (main ブランチ用 - 書き込み可):
      ARN:  ${aws_iam_role.terraform_apply.arn}
      Name: ${aws_iam_role.terraform_apply.name}

    Emergency Role (緊急時用 - 現在無効):
      ARN:  ${aws_iam_role.terraform_emergency.arn}
      Name: ${aws_iam_role.terraform_emergency.name}

    ================================================================
    次のステップ
    ================================================================

    1. GitHub Secrets を設定:
       gh secret set AWS_PLAN_ROLE_ARN --body "${aws_iam_role.terraform_plan.arn}"
       gh secret set AWS_APPLY_ROLE_ARN --body "${aws_iam_role.terraform_apply.arn}"

    2. GitHub Actions ワークフローを設定:
       .github/workflows/terraform-plan.yml
       .github/workflows/terraform-apply.yml

    3. テスト:
       - 新しい PR を作成して Plan が実行されることを確認
       - main にマージして Apply が実行されることを確認

    ================================================================

  EOT
}
