# =============================================================================
# Plan Role - 読み取り専用の IAM Role
# =============================================================================
#
# terraform plan のみを実行するための IAM Role です。
# 開発者が PR を作成した際に GitHub Actions で使用されます。
#
# 特徴:
# - 読み取り専用（Describe*, Get*, List* のみ）
# - PR（Pull Request）からのみ assume 可能
# - State ファイルの読み取りは可能、書き込みは不可
#
# =============================================================================

# -----------------------------------------------------------------------------
# Plan Role
# -----------------------------------------------------------------------------

resource "aws_iam_role" "terraform_plan" {
  name        = "TerraformPlanRole-${var.project_prefix}"
  description = "Terraform Plan 用の読み取り専用 Role（${var.project_prefix}）"

  # 最大セッション時間: 1時間（Plan は通常短時間で完了）
  max_session_duration = 3600

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowGitHubActionsOIDC"
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.github.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringLike = {
            # PR（Pull Request）からのみ assume 可能
            # main ブランチへの直接 push では使用不可
            "token.actions.githubusercontent.com:sub" = "repo:${var.github_org}/${var.github_repo}:pull_request"
          }
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = {
    Name        = "TerraformPlanRole-${var.project_prefix}"
    Purpose     = "terraform-plan"
    Environment = "all"
    AccessLevel = "read-only"
  }
}

# -----------------------------------------------------------------------------
# Plan Role Policy - 読み取り専用権限
# -----------------------------------------------------------------------------

resource "aws_iam_role_policy" "terraform_plan" {
  name = "TerraformPlanPolicy"
  role = aws_iam_role.terraform_plan.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # -----------------------------------------------------------------------
      # EC2 関連の読み取り権限
      # -----------------------------------------------------------------------
      {
        Sid    = "EC2ReadOnly"
        Effect = "Allow"
        Action = [
          "ec2:Describe*",
          "ec2:Get*"
        ]
        Resource = "*"
      },

      # -----------------------------------------------------------------------
      # S3 関連の読み取り権限
      # -----------------------------------------------------------------------
      {
        Sid    = "S3ReadOnly"
        Effect = "Allow"
        Action = [
          "s3:Get*",
          "s3:List*"
        ]
        Resource = "*"
      },

      # -----------------------------------------------------------------------
      # RDS 関連の読み取り権限
      # -----------------------------------------------------------------------
      {
        Sid    = "RDSReadOnly"
        Effect = "Allow"
        Action = [
          "rds:Describe*",
          "rds:List*"
        ]
        Resource = "*"
      },

      # -----------------------------------------------------------------------
      # IAM 関連の読み取り権限
      # -----------------------------------------------------------------------
      {
        Sid    = "IAMReadOnly"
        Effect = "Allow"
        Action = [
          "iam:Get*",
          "iam:List*"
        ]
        Resource = "*"
      },

      # -----------------------------------------------------------------------
      # VPC 関連の読み取り権限（EC2 に含まれるが明示的に記載）
      # -----------------------------------------------------------------------
      {
        Sid    = "VPCReadOnly"
        Effect = "Allow"
        Action = [
          "vpc:Describe*"
        ]
        Resource = "*"
      },

      # -----------------------------------------------------------------------
      # ELB 関連の読み取り権限
      # -----------------------------------------------------------------------
      {
        Sid    = "ELBReadOnly"
        Effect = "Allow"
        Action = [
          "elasticloadbalancing:Describe*"
        ]
        Resource = "*"
      },

      # -----------------------------------------------------------------------
      # Auto Scaling 関連の読み取り権限
      # -----------------------------------------------------------------------
      {
        Sid    = "AutoScalingReadOnly"
        Effect = "Allow"
        Action = [
          "autoscaling:Describe*"
        ]
        Resource = "*"
      },

      # -----------------------------------------------------------------------
      # CloudWatch 関連の読み取り権限
      # -----------------------------------------------------------------------
      {
        Sid    = "CloudWatchReadOnly"
        Effect = "Allow"
        Action = [
          "cloudwatch:Describe*",
          "cloudwatch:Get*",
          "cloudwatch:List*"
        ]
        Resource = "*"
      },

      # -----------------------------------------------------------------------
      # SSM Parameter Store の読み取り権限（機密情報取得用）
      # -----------------------------------------------------------------------
      {
        Sid    = "SSMParameterReadOnly"
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters",
          "ssm:GetParametersByPath",
          "ssm:DescribeParameters"
        ]
        Resource = [
          "arn:aws:ssm:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:parameter/${var.project_prefix}/*"
        ]
      },

      # -----------------------------------------------------------------------
      # KMS の読み取り権限（SSM Parameter の復号用）
      # -----------------------------------------------------------------------
      {
        Sid    = "KMSReadOnly"
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:DescribeKey"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "kms:ViaService" = "ssm.${data.aws_region.current.name}.amazonaws.com"
          }
        }
      },

      # -----------------------------------------------------------------------
      # Terraform State の読み取り権限
      # -----------------------------------------------------------------------
      {
        Sid    = "TerraformStateRead"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:ListBucket",
          "s3:GetBucketVersioning"
        ]
        Resource = [
          "arn:aws:s3:::${var.state_bucket}",
          "arn:aws:s3:::${var.state_bucket}/*"
        ]
      },

      # -----------------------------------------------------------------------
      # Terraform State Locking（S3 原生锁定 - .tflock 文件）
      # Terraform 1.10+ 使用 use_lockfile = true
      # -----------------------------------------------------------------------
      {
        Sid    = "TerraformLockRead"
        Effect = "Allow"
        Action = [
          "s3:GetObject"
        ]
        Resource = "arn:aws:s3:::${var.state_bucket}/*.tflock"
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# Plan Role に AWS 管理ポリシーを追加（オプション）
# -----------------------------------------------------------------------------
#
# より広範囲の読み取り権限が必要な場合は、以下のようにマネージドポリシーを
# アタッチすることもできます。ただし、権限が広くなるため注意が必要です。
#
# resource "aws_iam_role_policy_attachment" "plan_readonly" {
#   role       = aws_iam_role.terraform_plan.name
#   policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
# }
