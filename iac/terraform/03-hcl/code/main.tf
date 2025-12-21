# main.tf
# HCL 语法演示：VPC 网络资源
#
# 本文件演示：
# 1. Resource block 语法结构
# 2. 资源间的隐式依赖（通过引用）
# 3. 嵌套块（nested blocks）
#
# 资源创建顺序由 Terraform 自动推断：
#   VPC → Subnet → Security Group

# -----------------------------------------------------------------------------
# VPC - 虚拟私有云
# -----------------------------------------------------------------------------
# Block 结构：resource "资源类型" "本地名称" { ... }
#
# 资源类型格式：provider_resource
#   aws_vpc = AWS Provider 的 VPC 资源
#
# 本地名称：在 Terraform 中引用此资源的名称
#   其他资源可以用 aws_vpc.main.id 引用此 VPC

resource "aws_vpc" "main" {
  # 参数（Arguments）
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  # 嵌套块或 Map 类型参数
  tags = {
    Name        = "lesson-03-vpc"
    Environment = "learning"
  }
}

# -----------------------------------------------------------------------------
# Subnet - 子网
# -----------------------------------------------------------------------------
# 隐式依赖演示：
#   vpc_id = aws_vpc.main.id
#
# 通过引用 aws_vpc.main.id，Terraform 自动推断：
#   必须先创建 VPC，再创建 Subnet
#
# 这比显式使用 depends_on 更好：
# 1. 代码可读性更强
# 2. 依赖关系更清晰
# 3. 不会遗漏依赖

resource "aws_subnet" "public" {
  # 引用其他资源的属性
  # 格式：资源类型.本地名称.属性名
  vpc_id = aws_vpc.main.id

  # 使用 Data Source 获取可用区
  availability_zone = data.aws_availability_zones.available.names[0]

  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true

  tags = {
    Name = "lesson-03-subnet-public"
    Type = "public"
  }
}

# -----------------------------------------------------------------------------
# Security Group - 安全组
# -----------------------------------------------------------------------------
# 多个隐式依赖：
#   vpc_id = aws_vpc.main.id
#
# 嵌套块演示：
#   ingress { ... }  - 允许入站流量
#   egress { ... }   - 允许出站流量

resource "aws_security_group" "web" {
  name        = "lesson-03-sg-web"
  description = "Allow HTTP and SSH inbound traffic"
  vpc_id      = aws_vpc.main.id

  # 嵌套块（Nested Block）
  # 与 Map 不同，嵌套块有自己的 schema
  ingress {
    description = "HTTP from anywhere"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SSH from anywhere"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "lesson-03-sg-web"
  }
}

# -----------------------------------------------------------------------------
# 依赖关系说明
# -----------------------------------------------------------------------------
#
# Terraform 通过分析引用自动构建依赖图：
#
#   ┌─────────────────────────────────────────┐
#   │        data.aws_availability_zones      │
#   │                   │                     │
#   │                   ▼                     │
#   │   ┌───────────────────────────┐         │
#   │   │       aws_vpc.main        │         │
#   │   └─────────────┬─────────────┘         │
#   │                 │                       │
#   │        ┌───────┴────────┐               │
#   │        ▼                ▼               │
#   │ aws_subnet.public  aws_security_group   │
#   │                        .web             │
#   └─────────────────────────────────────────┘
#
# 运行 terraform graph 可以查看完整依赖图。
# -----------------------------------------------------------------------------
