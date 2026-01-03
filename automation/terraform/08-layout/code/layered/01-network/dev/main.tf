# =============================================================================
# Network Layer - VPC 和网络基础设施
# =============================================================================
# 第一层：最稳定的基础设施
# 变更频率低，影响范围大
# =============================================================================

# -----------------------------------------------------------------------------
# 数据源
# -----------------------------------------------------------------------------
data "aws_availability_zones" "available" {
  state = "available"
}

# -----------------------------------------------------------------------------
# 本地变量
# -----------------------------------------------------------------------------
locals {
  environment = "dev"
  name_prefix = "demo-${local.environment}"

  vpc_cidr = "10.0.0.0/16"

  # 使用前两个可用区
  azs = slice(data.aws_availability_zones.available.names, 0, 2)

  # 子网 CIDR
  public_subnets  = ["10.0.1.0/24", "10.0.2.0/24"]
  private_subnets = ["10.0.11.0/24", "10.0.12.0/24"]
}

# -----------------------------------------------------------------------------
# VPC
# -----------------------------------------------------------------------------
resource "aws_vpc" "main" {
  cidr_block           = local.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${local.name_prefix}-vpc"
  }
}

# -----------------------------------------------------------------------------
# Internet Gateway
# -----------------------------------------------------------------------------
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${local.name_prefix}-igw"
  }
}

# -----------------------------------------------------------------------------
# Public Subnets
# -----------------------------------------------------------------------------
resource "aws_subnet" "public" {
  count = length(local.public_subnets)

  vpc_id                  = aws_vpc.main.id
  cidr_block              = local.public_subnets[count.index]
  availability_zone       = local.azs[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "${local.name_prefix}-public-${count.index + 1}"
    Type = "public"
  }
}

# -----------------------------------------------------------------------------
# Private Subnets
# -----------------------------------------------------------------------------
resource "aws_subnet" "private" {
  count = length(local.private_subnets)

  vpc_id            = aws_vpc.main.id
  cidr_block        = local.private_subnets[count.index]
  availability_zone = local.azs[count.index]

  tags = {
    Name = "${local.name_prefix}-private-${count.index + 1}"
    Type = "private"
  }
}

# -----------------------------------------------------------------------------
# Route Table (Public)
# -----------------------------------------------------------------------------
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${local.name_prefix}-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  count = length(aws_subnet.public)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# -----------------------------------------------------------------------------
# Security Group (基础)
# -----------------------------------------------------------------------------
resource "aws_security_group" "default" {
  name        = "${local.name_prefix}-default-sg"
  description = "Default security group"
  vpc_id      = aws_vpc.main.id

  # 允许内部通信
  ingress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    self      = true
  }

  # 允许所有出站
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.name_prefix}-default-sg"
  }
}
