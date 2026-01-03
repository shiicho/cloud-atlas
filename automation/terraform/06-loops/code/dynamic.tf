# dynamic.tf
# dynamic blocks 示例
#
# dynamic blocks 用于动态生成嵌套块（如 ingress, egress, tag 等）

# -----------------------------------------------------------------------------
# 获取默认 VPC
# -----------------------------------------------------------------------------

data "aws_vpc" "default" {
  default = true
}

# -----------------------------------------------------------------------------
# Security Group with dynamic blocks
# -----------------------------------------------------------------------------

resource "aws_security_group" "dynamic_demo" {
  name        = "${var.project}-sg-dynamic"
  description = "Dynamic blocks demo"
  vpc_id      = data.aws_vpc.default.id

  # -------------------------------------------------------------------------
  # dynamic block 语法
  # -------------------------------------------------------------------------
  # dynamic "块名" {
  #   for_each = 集合
  #   content {
  #     属性 = 块名.value.xxx
  #   }
  # }

  dynamic "ingress" {
    for_each = var.ingress_rules

    content {
      from_port   = ingress.value.port
      to_port     = ingress.value.port
      protocol    = "tcp"
      cidr_blocks = ingress.value.cidr_blocks
      description = ingress.value.description
    }
  }

  # 静态 egress 规则
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound"
  }

  tags = {
    Name = "${var.project}-sg-dynamic"
  }
}

# -----------------------------------------------------------------------------
# 自定义 iterator 名称
# -----------------------------------------------------------------------------
# 默认 iterator 名称与 block 名称相同
# 可以使用 iterator 参数自定义

resource "aws_security_group" "custom_iterator" {
  name        = "${var.project}-sg-custom-iter"
  description = "Custom iterator demo"
  vpc_id      = data.aws_vpc.default.id

  dynamic "ingress" {
    for_each = var.ingress_rules
    iterator = rule  # 自定义名称

    content {
      from_port   = rule.value.port    # 使用 rule 而不是 ingress
      to_port     = rule.value.port
      protocol    = "tcp"
      cidr_blocks = rule.value.cidr_blocks
      description = rule.value.description
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project}-sg-custom-iter"
  }
}

# -----------------------------------------------------------------------------
# 嵌套 dynamic blocks
# -----------------------------------------------------------------------------
# dynamic blocks 可以嵌套，但要注意可读性

# 示例：为每个 ingress 规则添加多个 CIDR
# dynamic "ingress" {
#   for_each = var.ingress_rules
#
#   content {
#     from_port = ingress.value.port
#     to_port   = ingress.value.port
#     protocol  = "tcp"
#
#     dynamic "cidr_blocks" {
#       for_each = ingress.value.cidr_blocks
#       content {
#         cidr_block = cidr_blocks.value
#       }
#     }
#   }
# }
# -----------------------------------------------------------------------------
