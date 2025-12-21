# =============================================================================
# Emergency Role - 緊急変更用の IAM Role
# =============================================================================
#
# 緊急変更（Break-glass）時に使用する IAM Role です。
# 通常は無効化されており、緊急時にのみ有効化されます。
#
# 特徴:
# - 広範な権限を持つ
# - hotfix-* ブランチからのみ assume 可能
# - デフォルトでは Trust Policy が空（無効状態）
# - 緊急時に管理者が Trust Policy を更新して有効化
#
# =============================================================================

# -----------------------------------------------------------------------------
# Emergency Role
# -----------------------------------------------------------------------------

resource "aws_iam_role" "terraform_emergency" {
  name        = "TerraformEmergencyRole-${var.project_prefix}"
  description = "緊急変更用の Role（${var.project_prefix}）- 通常は無効"

  # 最大セッション時間: 4時間（緊急対応に備えて長め）
  max_session_duration = 14400

  # デフォルトでは無効（誰も assume できない）
  # 緊急時に管理者が有効化する
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyAll"
        Effect    = "Deny"
        Principal = "*"
        Action    = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name        = "TerraformEmergencyRole-${var.project_prefix}"
    Purpose     = "emergency-change"
    Environment = var.environment
    AccessLevel = "full"
    Status      = "disabled"
    Warning     = "緊急時のみ使用"
  }
}

# -----------------------------------------------------------------------------
# Emergency Role の有効化用 Trust Policy（参考）
# -----------------------------------------------------------------------------
#
# 緊急時に管理者が以下のコマンドで有効化します：
#
# aws iam update-assume-role-policy \
#   --role-name TerraformEmergencyRole-myapp \
#   --policy-document '{
#     "Version": "2012-10-17",
#     "Statement": [
#       {
#         "Effect": "Allow",
#         "Principal": {
#           "Federated": "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
#         },
#         "Action": "sts:AssumeRoleWithWebIdentity",
#         "Condition": {
#           "StringLike": {
#             "token.actions.githubusercontent.com:sub": "repo:org/repo:ref:refs/heads/hotfix-*"
#           }
#         }
#       }
#     ]
#   }'
#
# 緊急対応完了後は、必ず無効化してください：
#
# aws iam update-assume-role-policy \
#   --role-name TerraformEmergencyRole-myapp \
#   --policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Deny","Principal":"*","Action":"sts:AssumeRole"}]}'
#
# -----------------------------------------------------------------------------

# Emergency Trust Policy テンプレート（ローカル変数として保持）
locals {
  emergency_trust_policy_enabled = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowHotfixBranch"
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.github.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringLike = {
            # hotfix-* ブランチからのみ assume 可能
            "token.actions.githubusercontent.com:sub" = "repo:${var.github_org}/${var.github_repo}:ref:refs/heads/hotfix-*"
          }
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# Emergency Role Policy - 広範な権限
# -----------------------------------------------------------------------------

resource "aws_iam_role_policy" "terraform_emergency" {
  name = "TerraformEmergencyPolicy"
  role = aws_iam_role.terraform_emergency.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # -----------------------------------------------------------------------
      # EC2 完全な権限（緊急時はタグ条件なし）
      # -----------------------------------------------------------------------
      {
        Sid      = "EC2FullAccess"
        Effect   = "Allow"
        Action   = "ec2:*"
        Resource = "*"
      },

      # -----------------------------------------------------------------------
      # S3 完全な権限
      # -----------------------------------------------------------------------
      {
        Sid      = "S3FullAccess"
        Effect   = "Allow"
        Action   = "s3:*"
        Resource = "*"
      },

      # -----------------------------------------------------------------------
      # RDS 完全な権限
      # -----------------------------------------------------------------------
      {
        Sid      = "RDSFullAccess"
        Effect   = "Allow"
        Action   = "rds:*"
        Resource = "*"
      },

      # -----------------------------------------------------------------------
      # IAM 権限（PassRole のみ、Role 作成は不可）
      # -----------------------------------------------------------------------
      {
        Sid    = "IAMPassRole"
        Effect = "Allow"
        Action = [
          "iam:PassRole",
          "iam:Get*",
          "iam:List*"
        ]
        Resource = "*"
      },

      # -----------------------------------------------------------------------
      # ELB 完全な権限
      # -----------------------------------------------------------------------
      {
        Sid      = "ELBFullAccess"
        Effect   = "Allow"
        Action   = "elasticloadbalancing:*"
        Resource = "*"
      },

      # -----------------------------------------------------------------------
      # Auto Scaling 完全な権限
      # -----------------------------------------------------------------------
      {
        Sid      = "AutoScalingFullAccess"
        Effect   = "Allow"
        Action   = "autoscaling:*"
        Resource = "*"
      },

      # -----------------------------------------------------------------------
      # CloudWatch 完全な権限
      # -----------------------------------------------------------------------
      {
        Sid    = "CloudWatchFullAccess"
        Effect = "Allow"
        Action = [
          "cloudwatch:*",
          "logs:*"
        ]
        Resource = "*"
      },

      # -----------------------------------------------------------------------
      # SSM 権限
      # -----------------------------------------------------------------------
      {
        Sid    = "SSMAccess"
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters",
          "ssm:GetParametersByPath",
          "ssm:PutParameter"
        ]
        Resource = "*"
      },

      # -----------------------------------------------------------------------
      # KMS 権限
      # -----------------------------------------------------------------------
      {
        Sid    = "KMSAccess"
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:Encrypt",
          "kms:GenerateDataKey*",
          "kms:DescribeKey",
          "kms:CreateGrant"
        ]
        Resource = "*"
      },

      # -----------------------------------------------------------------------
      # Terraform State の完全な権限
      # -----------------------------------------------------------------------
      {
        Sid    = "TerraformStateFullAccess"
        Effect = "Allow"
        Action = "s3:*"
        Resource = [
          "arn:aws:s3:::${var.state_bucket}",
          "arn:aws:s3:::${var.state_bucket}/*"
        ]
      },

      # -----------------------------------------------------------------------
      # Terraform Lock Table の完全な権限
      # -----------------------------------------------------------------------
      {
        Sid      = "TerraformLockFullAccess"
        Effect   = "Allow"
        Action   = "dynamodb:*"
        Resource = "arn:aws:dynamodb:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:table/${var.lock_table}"
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# 緊急変更の CloudWatch アラーム
# -----------------------------------------------------------------------------
#
# Emergency Role が使用されたときに通知するアラームを設定できます。
#
# resource "aws_cloudwatch_metric_alarm" "emergency_role_used" {
#   alarm_name          = "TerraformEmergencyRoleUsed"
#   comparison_operator = "GreaterThanThreshold"
#   evaluation_periods  = "1"
#   metric_name         = "AssumeRole"
#   namespace           = "AWS/IAM"
#   period              = "60"
#   statistic           = "Sum"
#   threshold           = "0"
#   alarm_description   = "Emergency Role が使用されました"
#
#   dimensions = {
#     RoleName = aws_iam_role.terraform_emergency.name
#   }
#
#   alarm_actions = [aws_sns_topic.alerts.arn]
# }
