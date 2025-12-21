# =============================================================================
# Application Layer - 应用服务
# =============================================================================
# 第三层：EC2、ECS、Lambda 等应用层资源
# 变更频率高，影响范围小
# =============================================================================

# -----------------------------------------------------------------------------
# 本地变量
# -----------------------------------------------------------------------------
locals {
  environment = "dev"
  name_prefix = "demo-${local.environment}"

  # 从 Network Layer 获取数据
  vpc_id            = data.terraform_remote_state.network.outputs.vpc_id
  public_subnet_ids = data.terraform_remote_state.network.outputs.public_subnet_ids

  # 从 Foundations Layer 获取数据
  data_bucket_arn       = data.terraform_remote_state.foundations.outputs.data_bucket_arn
  data_security_group_id = data.terraform_remote_state.foundations.outputs.data_security_group_id
}

# -----------------------------------------------------------------------------
# Security Group for Application
# -----------------------------------------------------------------------------
resource "aws_security_group" "app" {
  name        = "${local.name_prefix}-app-sg"
  description = "Security group for application layer"
  vpc_id      = local.vpc_id

  # HTTP
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTP"
  }

  # HTTPS
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTPS"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.name_prefix}-app-sg"
  }
}

# -----------------------------------------------------------------------------
# IAM Role for EC2
# -----------------------------------------------------------------------------
resource "aws_iam_role" "app" {
  name = "${local.name_prefix}-app-role"

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

  tags = {
    Name = "${local.name_prefix}-app-role"
  }
}

# S3 访问策略
resource "aws_iam_role_policy" "app_s3" {
  name = "${local.name_prefix}-app-s3-policy"
  role = aws_iam_role.app.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket"
        ]
        Resource = [
          local.data_bucket_arn,
          "${local.data_bucket_arn}/*"
        ]
      }
    ]
  })
}

# SSM 托管策略
resource "aws_iam_role_policy_attachment" "app_ssm" {
  role       = aws_iam_role.app.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "app" {
  name = "${local.name_prefix}-app-profile"
  role = aws_iam_role.app.name
}

# -----------------------------------------------------------------------------
# EC2 Instance（示例应用服务器）
# -----------------------------------------------------------------------------
# 注意：这只是示例，生产环境应使用 ASG + ALB
resource "aws_instance" "app" {
  ami           = data.aws_ami.amazon_linux_2023.id
  instance_type = "t3.micro"

  subnet_id                   = local.public_subnet_ids[0]
  vpc_security_group_ids      = [aws_security_group.app.id]
  iam_instance_profile        = aws_iam_instance_profile.app.name
  associate_public_ip_address = true

  # 简单的 user_data
  user_data = <<-EOF
    #!/bin/bash
    yum update -y
    yum install -y httpd
    systemctl start httpd
    systemctl enable httpd
    echo "<h1>Hello from ${local.environment} environment!</h1>" > /var/www/html/index.html
  EOF

  tags = {
    Name = "${local.name_prefix}-app-server"
  }

  # 在 dev 环境中，允许就地修改 user_data
  lifecycle {
    ignore_changes = [ami]  # 不因 AMI 更新而重建
  }
}
