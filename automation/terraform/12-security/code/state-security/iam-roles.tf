# =============================================================================
# IAM Roles - Terraform 最小权限设计
# IAM Roles - Terraform Least Privilege Design
# =============================================================================
#
# 设计原则：
# - 分离 Plan 和 Apply 权限
# - Plan 只需读权限（可在 CI 中自动运行）
# - Apply 需要写权限（需要人工审批）
# - 额外限制：资源标签条件、区域限制
#
# =============================================================================

# =============================================================================
# Plan Role - 只读权限
# =============================================================================

resource "aws_iam_role" "terraform_plan" {
  name               = "TerraformPlanRole-${var.project_name}"
  description        = "Role for Terraform plan operations (read-only)"
  assume_role_policy = data.aws_iam_policy_document.github_oidc_assume.json

  tags = {
    Name    = "Terraform Plan Role"
    Purpose = "terraform-ci"
  }
}

resource "aws_iam_role_policy" "terraform_plan" {
  name   = "TerraformPlanPolicy"
  role   = aws_iam_role.terraform_plan.id
  policy = data.aws_iam_policy_document.terraform_plan.json
}

data "aws_iam_policy_document" "terraform_plan" {
  # 读取 State
  statement {
    sid    = "ReadState"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:ListBucket"
    ]
    resources = [
      aws_s3_bucket.tfstate.arn,
      "${aws_s3_bucket.tfstate.arn}/*"
    ]
  }

  # State Locking（S3 原生锁定 - .tflock 文件）
  # Terraform 1.10+ 使用 use_lockfile = true
  statement {
    sid    = "StateLocking"
    effect = "Allow"
    actions = [
      "s3:PutObject",
      "s3:DeleteObject"
    ]
    resources = [
      "${aws_s3_bucket.tfstate.arn}/*.tflock"
    ]
  }

  # KMS 解密权限
  statement {
    sid    = "KMSDecrypt"
    effect = "Allow"
    actions = [
      "kms:Decrypt",
      "kms:GenerateDataKey*",
      "kms:DescribeKey"
    ]
    resources = [
      aws_kms_key.tfstate.arn
    ]
  }

  # 读取所有资源（用于 plan）
  statement {
    sid    = "ReadResources"
    effect = "Allow"
    actions = [
      "ec2:Describe*",
      "s3:Get*",
      "s3:List*",
      "rds:Describe*",
      "iam:Get*",
      "iam:List*",
      "ssm:GetParameter*",
      "ssm:DescribeParameters",
      "kms:Describe*",
      "kms:List*",
      "logs:Describe*",
      "logs:List*"
    ]
    resources = ["*"]
  }
}

# =============================================================================
# Apply Role - 写权限（需要审批）
# =============================================================================

resource "aws_iam_role" "terraform_apply" {
  name               = "TerraformApplyRole-${var.project_name}"
  description        = "Role for Terraform apply operations (write access, requires approval)"
  assume_role_policy = data.aws_iam_policy_document.github_oidc_assume_apply.json

  tags = {
    Name    = "Terraform Apply Role"
    Purpose = "terraform-cd"
  }
}

resource "aws_iam_role_policy" "terraform_apply" {
  name   = "TerraformApplyPolicy"
  role   = aws_iam_role.terraform_apply.id
  policy = data.aws_iam_policy_document.terraform_apply.json
}

data "aws_iam_policy_document" "terraform_apply" {
  # State 读写
  statement {
    sid    = "ManageState"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:ListBucket"
    ]
    resources = [
      aws_s3_bucket.tfstate.arn,
      "${aws_s3_bucket.tfstate.arn}/*"
    ]
  }

  # State Locking（S3 原生锁定 - .tflock 文件）
  # Terraform 1.10+ 使用 use_lockfile = true
  statement {
    sid    = "StateLocking"
    effect = "Allow"
    actions = [
      "s3:PutObject",
      "s3:DeleteObject"
    ]
    resources = [
      "${aws_s3_bucket.tfstate.arn}/*.tflock"
    ]
  }

  # KMS 加解密
  statement {
    sid    = "KMSAccess"
    effect = "Allow"
    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:DescribeKey"
    ]
    resources = [
      aws_kms_key.tfstate.arn
    ]
  }

  # EC2 权限（限制区域和标签）
  statement {
    sid    = "EC2Manage"
    effect = "Allow"
    actions = [
      "ec2:*"
    ]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [data.aws_region.current.name]
    }
  }

  # S3 权限（排除 State bucket）
  statement {
    sid    = "S3Manage"
    effect = "Allow"
    actions = [
      "s3:*"
    ]
    resources = ["*"]
    condition {
      test     = "StringNotEquals"
      variable = "s3:ResourceAccount"
      values   = ["${data.aws_caller_identity.current.account_id}:${aws_s3_bucket.tfstate.id}"]
    }
  }

  # RDS 权限
  statement {
    sid    = "RDSManage"
    effect = "Allow"
    actions = [
      "rds:*"
    ]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [data.aws_region.current.name]
    }
  }

  # IAM 权限（受限）
  statement {
    sid    = "IAMRead"
    effect = "Allow"
    actions = [
      "iam:Get*",
      "iam:List*"
    ]
    resources = ["*"]
  }

  statement {
    sid    = "IAMPassRole"
    effect = "Allow"
    actions = [
      "iam:PassRole"
    ]
    resources = [
      "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/myapp-*"
    ]
  }

  # SSM 权限
  statement {
    sid    = "SSMRead"
    effect = "Allow"
    actions = [
      "ssm:GetParameter*",
      "ssm:DescribeParameters"
    ]
    resources = [
      "arn:aws:ssm:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:parameter/myapp/*"
    ]
  }
}

# =============================================================================
# OIDC Assume Role Policies
# =============================================================================

data "aws_iam_policy_document" "github_oidc_assume" {
  statement {
    effect = "Allow"
    principals {
      type        = "Federated"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/token.actions.githubusercontent.com"]
    }
    actions = ["sts:AssumeRoleWithWebIdentity"]

    # 限制到特定仓库
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_org}/${var.github_repo}:*"]
    }
  }
}

data "aws_iam_policy_document" "github_oidc_assume_apply" {
  statement {
    effect = "Allow"
    principals {
      type        = "Federated"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/token.actions.githubusercontent.com"]
    }
    actions = ["sts:AssumeRoleWithWebIdentity"]

    # 限制到特定仓库和 production 环境
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = [
        "repo:${var.github_org}/${var.github_repo}:environment:production",
        "repo:${var.github_org}/${var.github_repo}:ref:refs/heads/main"
      ]
    }
  }
}

# =============================================================================
# 额外变量
# =============================================================================

variable "github_org" {
  type        = string
  description = "GitHub organization name"
  default     = "your-org"
}

variable "github_repo" {
  type        = string
  description = "GitHub repository name"
  default     = "your-repo"
}
