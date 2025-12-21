# =============================================================================
# main.tf - 资源定义（传统 Import 命令方式）
# =============================================================================
#
# 传统方式的痛点：
#   1. 必须手动编写资源代码
#   2. 需要查询 AWS 获取所有属性值
#   3. 容易遗漏属性，导致 plan 出现差异
#   4. 导入命令不会被记录在代码中
#
# 使用流程：
#   1. 查询 AWS 资源属性
#   2. 手动编写下面的资源代码
#   3. 运行 terraform init
#   4. 运行 terraform import aws_instance.legacy <instance-id>
#   5. 运行 terraform plan 检查差异
#   6. 修改代码直到 plan 无差异
#
# =============================================================================

# -----------------------------------------------------------------------------
# 查询现有资源信息
# -----------------------------------------------------------------------------
# 在编写代码前，先用 AWS CLI 查询资源属性：
#
# # 获取实例详情
# aws ec2 describe-instances --instance-ids i-0abc123def456789 \
#   --query 'Reservations[0].Instances[0]' \
#   --region ap-northeast-1
#
# # 获取 AMI ID
# aws ec2 describe-instances --instance-ids i-0abc123def456789 \
#   --query 'Reservations[0].Instances[0].ImageId' \
#   --output text
#
# # 获取 Instance Type
# aws ec2 describe-instances --instance-ids i-0abc123def456789 \
#   --query 'Reservations[0].Instances[0].InstanceType' \
#   --output text
#
# # 获取 Subnet ID
# aws ec2 describe-instances --instance-ids i-0abc123def456789 \
#   --query 'Reservations[0].Instances[0].SubnetId' \
#   --output text
#
# # 获取 Security Groups
# aws ec2 describe-instances --instance-ids i-0abc123def456789 \
#   --query 'Reservations[0].Instances[0].SecurityGroups[*].GroupId' \
#   --output text

# -----------------------------------------------------------------------------
# EC2 实例资源定义
# -----------------------------------------------------------------------------
# 重要：必须在执行 import 命令之前填写正确的属性值！
# 如果属性值不匹配，terraform plan 会显示差异

resource "aws_instance" "legacy" {
  # ==========================================================================
  # 必填项 - 必须与实际资源匹配
  # ==========================================================================

  # AMI ID - 从 AWS 查询获取
  # 格式: ami-xxxxxxxxxxxxxxxxx
  ami = "ami-0abcd1234efgh5678"  # TODO: 替换为实际值

  # 实例类型
  instance_type = "t3.micro"  # TODO: 确认实际值

  # ==========================================================================
  # 网络配置 - 必须与实际资源匹配
  # ==========================================================================

  # 子网 ID
  subnet_id = "subnet-12345678"  # TODO: 替换为实际值

  # 安全组 ID 列表
  vpc_security_group_ids = [
    "sg-12345678",  # TODO: 替换为实际值
  ]

  # ==========================================================================
  # 标签 - 应与实际资源匹配
  # ==========================================================================

  tags = {
    Name        = "legacy-manual-instance"
    Environment = "legacy"
    ManagedBy   = "manual"  # 导入后可改为 "Terraform"
    Purpose     = "terraform-import-demo"
  }

  # ==========================================================================
  # 可选项 - 根据实际情况添加
  # ==========================================================================

  # 如果实例有 Key Pair
  # key_name = "my-key-pair"

  # 如果有 IAM 实例配置文件
  # iam_instance_profile = "my-instance-profile"

  # 如果有特定的可用区要求
  # availability_zone = "ap-northeast-1a"

  # ==========================================================================
  # Lifecycle 配置
  # ==========================================================================

  lifecycle {
    # 练习时设为 false，生产环境考虑设为 true
    prevent_destroy = false

    # 如果某些属性会在 AWS 侧被自动修改，可以忽略
    # ignore_changes = [
    #   tags["LastModified"],
    # ]
  }
}

# -----------------------------------------------------------------------------
# 执行 Import 命令
# -----------------------------------------------------------------------------
# 完成上面的代码后，执行以下命令：
#
# # 初始化
# terraform init
#
# # 导入资源
# terraform import aws_instance.legacy i-0abc123def456789
#
# # 检查差异
# terraform plan
#
# # 如果有差异，修改代码后再次 plan
# # 重复直到 "No changes"
#
# # 确认无差异后，可以正常管理该资源
# terraform apply  # 应该没有变更

# -----------------------------------------------------------------------------
# 常见问题
# -----------------------------------------------------------------------------
#
# Q: Import 后 plan 显示很多差异怎么办？
# A: 逐个对比差异，将代码中的值改为 plan 显示的实际值
#
# Q: 有些属性我不想管理怎么办？
# A: 使用 lifecycle { ignore_changes = [...] }
#
# Q: 如何取消导入？
# A: terraform state rm aws_instance.legacy（仅从 state 移除，不删除资源）
