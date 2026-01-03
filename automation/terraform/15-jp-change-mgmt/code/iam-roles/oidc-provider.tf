# =============================================================================
# GitHub OIDC Provider - GitHub Actions 用の認証設定
# =============================================================================
#
# GitHub Actions から AWS へ OIDC 認証するための Identity Provider です。
# Access Key を使わずに一時的な認証情報を取得できます。
#
# 参考: https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/configuring-openid-connect-in-amazon-web-services
#
# =============================================================================

# -----------------------------------------------------------------------------
# GitHub OIDC Identity Provider
# -----------------------------------------------------------------------------
#
# 一度作成すれば、同一 AWS アカウント内の複数リポジトリで共有できます。
# すでに存在する場合は、data source で参照してください。
#
# -----------------------------------------------------------------------------

resource "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"

  client_id_list = [
    "sts.amazonaws.com"
  ]

  # GitHub の証明書サムプリント
  # 参考: https://github.blog/changelog/2023-06-27-github-actions-update-on-oidc-integration-with-aws/
  thumbprint_list = [
    "6938fd4d98bab03faadb97b34396831e3780aea1",
    "1c58a3a8518e8759bf075b76b750d4f2df264fcd"
  ]

  tags = {
    Name        = "github-actions-oidc"
    Description = "GitHub Actions OIDC Provider for Terraform"
  }
}

# -----------------------------------------------------------------------------
# 既存の OIDC Provider を参照する場合（コメントアウト）
# -----------------------------------------------------------------------------
#
# 既に OIDC Provider が作成されている場合は、上記 resource を削除し、
# 以下の data source を使用してください。
#
# data "aws_iam_openid_connect_provider" "github" {
#   url = "https://token.actions.githubusercontent.com"
# }
