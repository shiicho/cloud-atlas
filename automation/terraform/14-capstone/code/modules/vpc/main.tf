# =============================================================================
# modules/vpc/main.tf
# VPC 模块 - 创建完整的三层网络基础设施
# =============================================================================
#
# 本模块创建：
# - VPC
# - 公共子网（Public Subnets）- 用于 ALB
# - 私有子网（Private Subnets）- 用于应用服务器
# - 数据库子网（Database Subnets）- 用于 RDS
# - Internet Gateway
# - NAT Gateway（可选）
# - 路由表
#
# =============================================================================

# -----------------------------------------------------------------------------
# Data Sources
# 获取可用区信息
# -----------------------------------------------------------------------------

data "aws_availability_zones" "available" {
  state = "available"

  # 排除 Local Zones 和 Wavelength Zones
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

# -----------------------------------------------------------------------------
# Local Values
# 本地变量，减少重复
# -----------------------------------------------------------------------------

locals {
  # 可用区数量（取子网数量和可用区数量的较小值）
  az_count = min(
    length(var.public_subnets),
    length(data.aws_availability_zones.available.names)
  )

  # 可用区名称列表
  azs = slice(data.aws_availability_zones.available.names, 0, local.az_count)

  # 名称前缀
  name_prefix = "${var.project}-${var.environment}"

  # 通用标签
  common_tags = merge(
    {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "terraform"
      Module      = "vpc"
    },
    var.tags
  )
}

# -----------------------------------------------------------------------------
# VPC
# 主 VPC 资源
# -----------------------------------------------------------------------------

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  # 在日本的 IT 现场，VPC 通常需要详细的命名和标签
  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-vpc"
    }
  )
}

# -----------------------------------------------------------------------------
# Internet Gateway
# 允许公共子网访问互联网
# -----------------------------------------------------------------------------

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-igw"
    }
  )
}

# -----------------------------------------------------------------------------
# Public Subnets
# 公共子网 - 用于 ALB、Bastion 等需要公网访问的资源
# -----------------------------------------------------------------------------

resource "aws_subnet" "public" {
  count = length(var.public_subnets)

  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnets[count.index]
  availability_zone       = local.azs[count.index % length(local.azs)]
  map_public_ip_on_launch = true

  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-public-${local.azs[count.index % length(local.azs)]}"
      Type = "public"
      # Kubernetes 集成标签（如果需要）
      "kubernetes.io/role/elb" = "1"
    }
  )
}

# -----------------------------------------------------------------------------
# Private Subnets
# 私有子网 - 用于应用服务器（通过 NAT 访问互联网）
# -----------------------------------------------------------------------------

resource "aws_subnet" "private" {
  count = length(var.private_subnets)

  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnets[count.index]
  availability_zone = local.azs[count.index % length(local.azs)]

  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-private-${local.azs[count.index % length(local.azs)]}"
      Type = "private"
      # Kubernetes 集成标签（如果需要）
      "kubernetes.io/role/internal-elb" = "1"
    }
  )
}

# -----------------------------------------------------------------------------
# Database Subnets
# 数据库子网 - 用于 RDS（无互联网访问）
# -----------------------------------------------------------------------------

resource "aws_subnet" "database" {
  count = length(var.database_subnets)

  vpc_id            = aws_vpc.main.id
  cidr_block        = var.database_subnets[count.index]
  availability_zone = local.azs[count.index % length(local.azs)]

  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-database-${local.azs[count.index % length(local.azs)]}"
      Type = "database"
    }
  )
}

# -----------------------------------------------------------------------------
# Database Subnet Group
# RDS 需要的子网组
# -----------------------------------------------------------------------------

resource "aws_db_subnet_group" "database" {
  count = length(var.database_subnets) > 0 ? 1 : 0

  name       = "${local.name_prefix}-db-subnet-group"
  subnet_ids = aws_subnet.database[*].id

  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-db-subnet-group"
    }
  )
}

# -----------------------------------------------------------------------------
# Elastic IP for NAT Gateway
# NAT Gateway 需要固定公网 IP
# -----------------------------------------------------------------------------

resource "aws_eip" "nat" {
  count = var.enable_nat_gateway ? (var.single_nat_gateway ? 1 : local.az_count) : 0

  domain = "vpc"

  tags = merge(
    local.common_tags,
    {
      Name = var.single_nat_gateway ? "${local.name_prefix}-nat-eip" : "${local.name_prefix}-nat-eip-${count.index + 1}"
    }
  )

  # 依赖 IGW，确保先创建 IGW
  depends_on = [aws_internet_gateway.main]
}

# -----------------------------------------------------------------------------
# NAT Gateway
# 允许私有子网访问互联网（单向，出站）
# -----------------------------------------------------------------------------

resource "aws_nat_gateway" "main" {
  count = var.enable_nat_gateway ? (var.single_nat_gateway ? 1 : local.az_count) : 0

  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = merge(
    local.common_tags,
    {
      Name = var.single_nat_gateway ? "${local.name_prefix}-nat" : "${local.name_prefix}-nat-${count.index + 1}"
    }
  )

  # 依赖 IGW
  depends_on = [aws_internet_gateway.main]
}

# -----------------------------------------------------------------------------
# Public Route Table
# 公共子网路由表 - 默认路由指向 IGW
# -----------------------------------------------------------------------------

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-public-rt"
    }
  )
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main.id
}

resource "aws_route_table_association" "public" {
  count = length(aws_subnet.public)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# -----------------------------------------------------------------------------
# Private Route Tables
# 私有子网路由表 - 默认路由指向 NAT Gateway
# -----------------------------------------------------------------------------

resource "aws_route_table" "private" {
  count = var.single_nat_gateway ? 1 : local.az_count

  vpc_id = aws_vpc.main.id

  tags = merge(
    local.common_tags,
    {
      Name = var.single_nat_gateway ? "${local.name_prefix}-private-rt" : "${local.name_prefix}-private-rt-${count.index + 1}"
    }
  )
}

resource "aws_route" "private_nat" {
  count = var.enable_nat_gateway ? (var.single_nat_gateway ? 1 : local.az_count) : 0

  route_table_id         = aws_route_table.private[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.main[var.single_nat_gateway ? 0 : count.index].id
}

resource "aws_route_table_association" "private" {
  count = length(aws_subnet.private)

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[var.single_nat_gateway ? 0 : count.index % length(aws_route_table.private)].id
}

# -----------------------------------------------------------------------------
# Database Route Table
# 数据库子网路由表 - 无默认路由（隔离）
# -----------------------------------------------------------------------------

resource "aws_route_table" "database" {
  count = length(var.database_subnets) > 0 ? 1 : 0

  vpc_id = aws_vpc.main.id

  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-database-rt"
    }
  )
}

resource "aws_route_table_association" "database" {
  count = length(aws_subnet.database)

  subnet_id      = aws_subnet.database[count.index].id
  route_table_id = aws_route_table.database[0].id
}

# -----------------------------------------------------------------------------
# VPC Flow Logs（可选）
# 记录 VPC 网络流量，用于安全审计和故障排查
# -----------------------------------------------------------------------------

resource "aws_flow_log" "main" {
  count = var.enable_flow_logs ? 1 : 0

  vpc_id                   = aws_vpc.main.id
  traffic_type             = "ALL"
  iam_role_arn             = aws_iam_role.flow_log[0].arn
  log_destination_type     = "cloud-watch-logs"
  log_destination          = aws_cloudwatch_log_group.flow_log[0].arn
  max_aggregation_interval = 60

  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-flow-log"
    }
  )
}

resource "aws_cloudwatch_log_group" "flow_log" {
  count = var.enable_flow_logs ? 1 : 0

  name              = "/aws/vpc-flow-log/${local.name_prefix}"
  retention_in_days = var.flow_logs_retention_days

  tags = local.common_tags
}

resource "aws_iam_role" "flow_log" {
  count = var.enable_flow_logs ? 1 : 0

  name = "${local.name_prefix}-flow-log-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "vpc-flow-logs.amazonaws.com"
        }
      }
    ]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy" "flow_log" {
  count = var.enable_flow_logs ? 1 : 0

  name = "${local.name_prefix}-flow-log-policy"
  role = aws_iam_role.flow_log[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams"
        ]
        Effect   = "Allow"
        Resource = "*"
      }
    ]
  })
}
