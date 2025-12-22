# =============================================================================
# Apply Role - 書き込み可能な IAM Role
# =============================================================================
#
# terraform apply を実行するための IAM Role です。
# main ブランチへのマージ後、GitHub Actions で使用されます。
#
# 特徴:
# - 書き込み権限を持つ（リソースの作成/変更/削除）
# - main ブランチからのみ assume 可能
# - タグ条件でリソースを制限
# - State ファイルの読み書きが可能
#
# =============================================================================

# -----------------------------------------------------------------------------
# Apply Role
# -----------------------------------------------------------------------------

resource "aws_iam_role" "terraform_apply" {
  name        = "TerraformApplyRole-${var.project_prefix}"
  description = "Terraform Apply 用の書き込み Role（${var.project_prefix}）"

  # 最大セッション時間: 2時間（大規模な apply に備えて）
  max_session_duration = 7200

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
          StringEquals = {
            # main ブランチからのみ assume 可能
            # PR や feature ブランチからは使用不可
            "token.actions.githubusercontent.com:sub" = "repo:${var.github_org}/${var.github_repo}:ref:refs/heads/main"
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = {
    Name        = "TerraformApplyRole-${var.project_prefix}"
    Purpose     = "terraform-apply"
    Environment = var.environment
    AccessLevel = "read-write"
    Restricted  = "true"
  }
}

# -----------------------------------------------------------------------------
# Apply Role Policy - 書き込み権限（スコープ付き）
# -----------------------------------------------------------------------------

resource "aws_iam_role_policy" "terraform_apply" {
  name = "TerraformApplyPolicy"
  role = aws_iam_role.terraform_apply.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # -----------------------------------------------------------------------
      # EC2 関連の完全な権限（タグ条件付き）
      # -----------------------------------------------------------------------
      {
        Sid    = "EC2FullAccessWithTagCondition"
        Effect = "Allow"
        Action = [
          "ec2:*"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            # ManagedBy=terraform タグが付いたリソースのみ操作可能
            "ec2:ResourceTag/ManagedBy" = "terraform"
          }
        }
      },
      {
        Sid    = "EC2CreateWithTags"
        Effect = "Allow"
        Action = [
          "ec2:RunInstances",
          "ec2:CreateVolume",
          "ec2:CreateSecurityGroup",
          "ec2:CreateVpc",
          "ec2:CreateSubnet",
          "ec2:CreateInternetGateway",
          "ec2:CreateNatGateway",
          "ec2:CreateRouteTable",
          "ec2:AllocateAddress"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            # 新規作成時に ManagedBy=terraform タグが必須
            "aws:RequestTag/ManagedBy" = "terraform"
          }
        }
      },
      {
        Sid    = "EC2TagOperations"
        Effect = "Allow"
        Action = [
          "ec2:CreateTags",
          "ec2:DeleteTags"
        ]
        Resource = "*"
      },
      {
        Sid    = "EC2DescribeAll"
        Effect = "Allow"
        Action = [
          "ec2:Describe*",
          "ec2:Get*"
        ]
        Resource = "*"
      },

      # -----------------------------------------------------------------------
      # S3 関連の権限（プレフィックス制限）
      # -----------------------------------------------------------------------
      {
        Sid    = "S3FullAccessWithPrefix"
        Effect = "Allow"
        Action = [
          "s3:*"
        ]
        Resource = [
          "arn:aws:s3:::${var.project_prefix}-*",
          "arn:aws:s3:::${var.project_prefix}-*/*"
        ]
      },
      {
        Sid    = "S3ListAll"
        Effect = "Allow"
        Action = [
          "s3:ListAllMyBuckets",
          "s3:GetBucketLocation"
        ]
        Resource = "*"
      },

      # -----------------------------------------------------------------------
      # RDS 関連の権限（プレフィックス制限）
      # -----------------------------------------------------------------------
      {
        Sid    = "RDSFullAccessWithPrefix"
        Effect = "Allow"
        Action = [
          "rds:*"
        ]
        Resource = [
          "arn:aws:rds:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:db:${var.project_prefix}-*",
          "arn:aws:rds:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:cluster:${var.project_prefix}-*",
          "arn:aws:rds:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:subgrp:${var.project_prefix}-*",
          "arn:aws:rds:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:pg:${var.project_prefix}-*"
        ]
      },
      {
        Sid    = "RDSDescribeAll"
        Effect = "Allow"
        Action = [
          "rds:Describe*",
          "rds:List*"
        ]
        Resource = "*"
      },

      # -----------------------------------------------------------------------
      # IAM 関連の権限（制限付き）
      # -----------------------------------------------------------------------
      {
        Sid    = "IAMPassRole"
        Effect = "Allow"
        Action = [
          "iam:PassRole"
        ]
        Resource = [
          "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${var.project_prefix}-*"
        ]
        Condition = {
          StringEquals = {
            "iam:PassedToService" = [
              "ec2.amazonaws.com",
              "rds.amazonaws.com",
              "ecs.amazonaws.com",
              "lambda.amazonaws.com"
            ]
          }
        }
      },
      {
        Sid    = "IAMRoleManagement"
        Effect = "Allow"
        Action = [
          "iam:CreateRole",
          "iam:DeleteRole",
          "iam:UpdateRole",
          "iam:AttachRolePolicy",
          "iam:DetachRolePolicy",
          "iam:PutRolePolicy",
          "iam:DeleteRolePolicy",
          "iam:CreateInstanceProfile",
          "iam:DeleteInstanceProfile",
          "iam:AddRoleToInstanceProfile",
          "iam:RemoveRoleFromInstanceProfile"
        ]
        Resource = [
          "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${var.project_prefix}-*",
          "arn:aws:iam::${data.aws_caller_identity.current.account_id}:instance-profile/${var.project_prefix}-*"
        ]
      },
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
      # ELB 関連の権限
      # -----------------------------------------------------------------------
      {
        Sid    = "ELBFullAccess"
        Effect = "Allow"
        Action = [
          "elasticloadbalancing:*"
        ]
        Resource = "*"
      },

      # -----------------------------------------------------------------------
      # Auto Scaling 関連の権限
      # -----------------------------------------------------------------------
      {
        Sid    = "AutoScalingFullAccess"
        Effect = "Allow"
        Action = [
          "autoscaling:*"
        ]
        Resource = "*"
      },

      # -----------------------------------------------------------------------
      # CloudWatch 関連の権限
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
      # SSM Parameter Store の読み取り権限
      # -----------------------------------------------------------------------
      {
        Sid    = "SSMParameterReadOnly"
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters",
          "ssm:GetParametersByPath"
        ]
        Resource = [
          "arn:aws:ssm:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:parameter/${var.project_prefix}/*"
        ]
      },

      # -----------------------------------------------------------------------
      # KMS の権限
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
      # Terraform State の読み書き権限
      # -----------------------------------------------------------------------
      {
        Sid    = "TerraformStateReadWrite"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:PutObject",
          "s3:DeleteObject",
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
        Sid    = "TerraformLockReadWrite"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = "arn:aws:s3:::${var.state_bucket}/*.tflock"
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# Apply Role の権限境界（Permission Boundary）- オプション
# -----------------------------------------------------------------------------
#
# より厳格な制御が必要な場合は、Permission Boundary を設定します。
# これにより、管理者が意図しない権限の昇格を防ぎます。
#
# resource "aws_iam_role_policy_attachment" "apply_permission_boundary" {
#   role       = aws_iam_role.terraform_apply.name
#   policy_arn = aws_iam_policy.permission_boundary.arn
# }
