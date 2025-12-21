# main.tf
# moved blocks 演练 - 优雅的代码重构
# =============================================================================
#
# 本文件演示 Terraform 1.1+ 的 moved blocks 特性。
# moved blocks 允许在代码中声明资源移动，替代手动的 state mv 操作。
#
# 优点:
#   - 代码即文档，变更有版本控制
#   - 所有环境运行 apply 时自动迁移
#   - Plan 清晰显示移动操作
#   - 无需在每个环境手动执行 state mv
#
# =============================================================================

# -----------------------------------------------------------------------------
# 场景说明
# -----------------------------------------------------------------------------
#
# 假设我们有以下重构需求：
#
# 重构前:
#   aws_security_group.app
#   aws_instance.app
#
# 重构后:
#   module.compute.aws_security_group.main
#   module.compute.aws_instance.main
#
# 使用 moved blocks，我们可以在代码中声明这个移动关系。
# 运行 plan/apply 时，Terraform 会自动在 State 中执行移动。
#
# -----------------------------------------------------------------------------

# =============================================================================
# 演练 Step 1: 原始资源定义
# =============================================================================
# 首次运行时，使用这些资源定义。
# 注释掉 moved blocks 和 module 调用。

# 安全组
resource "aws_security_group" "app" {
  name        = "moved-demo-app-sg"
  description = "Security group for moved blocks demo"

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "moved-demo-app-sg"
  }
}

# -----------------------------------------------------------------------------
# Data Sources
# -----------------------------------------------------------------------------

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# IAM Role for SSM
resource "aws_iam_role" "app" {
  name = "moved-demo-app-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.app.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "app" {
  name = "moved-demo-app-profile"
  role = aws_iam_role.app.name
}

# EC2 实例
resource "aws_instance" "app" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = "t3.micro"
  subnet_id              = data.aws_subnets.default.ids[0]
  vpc_security_group_ids = [aws_security_group.app.id]
  iam_instance_profile   = aws_iam_instance_profile.app.name

  tags = {
    Name = "moved-demo-app"
  }
}

# =============================================================================
# 演练 Step 2: 使用 moved blocks 重构
# =============================================================================
# 重构时，取消下面的注释。
# moved blocks 告诉 Terraform：这些资源已经移动到新地址。

# -----------------------------------------------------------------------------
# moved blocks 声明
# -----------------------------------------------------------------------------
# 告诉 Terraform：旧地址的资源现在在新地址
# 运行 plan 时会显示 "will be moved"
# 运行 apply 后，State 中的地址会更新

# 重构示例：将资源从根模块移动到本地变量命名的资源
# 注意：这里演示的是简单的重命名场景

# moved {
#   from = aws_security_group.app
#   to   = aws_security_group.application
# }
#
# moved {
#   from = aws_instance.app
#   to   = aws_instance.application
# }

# 如果上面的 moved blocks 被启用，需要同时更改资源名称:
# resource "aws_security_group" "application" { ... }
# resource "aws_instance" "application" { ... }

# -----------------------------------------------------------------------------
# moved blocks 使用说明
# -----------------------------------------------------------------------------
#
# 1. 添加 moved block 声明移动关系
# 2. 同时修改资源定义的名称
# 3. 运行 terraform plan，确认显示 "will be moved"
# 4. 运行 terraform apply，State 自动更新
# 5. 可选：保留 moved blocks 作为历史记录，或确认所有环境迁移后删除
#
# 常见移动场景:
#   - 重命名资源: aws_instance.web -> aws_instance.frontend
#   - 移入模块: aws_instance.web -> module.compute.aws_instance.main
#   - 移出模块: module.old.aws_instance.x -> aws_instance.x
#   - 模块间移动: module.a.aws_instance.x -> module.b.aws_instance.x
#
# -----------------------------------------------------------------------------
