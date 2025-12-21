# =============================================================================
# 数据源 - 引用 Network 和 Foundations Layer 的输出
# =============================================================================

# -----------------------------------------------------------------------------
# 引用 Network Layer
# -----------------------------------------------------------------------------
data "terraform_remote_state" "network" {
  backend = "local"
  config = {
    path = "../../01-network/dev/terraform.tfstate"
  }
}

# -----------------------------------------------------------------------------
# 引用 Foundations Layer
# -----------------------------------------------------------------------------
data "terraform_remote_state" "foundations" {
  backend = "local"
  config = {
    path = "../../02-foundations/dev/terraform.tfstate"
  }
}

# -----------------------------------------------------------------------------
# 获取最新的 Amazon Linux 2023 AMI
# -----------------------------------------------------------------------------
data "aws_ami" "amazon_linux_2023" {
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
