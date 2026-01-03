# lifecycle-demo.tf
# Lifecycle Meta-Arguments 演示
#
# Lifecycle 控制资源的创建、更新、销毁行为。
# 常用选项：
# - create_before_destroy: 先创建新资源，再删除旧资源
# - prevent_destroy: 禁止删除资源
# - ignore_changes: 忽略特定属性的变化
# - replace_triggered_by: 关联资源变化时触发替换

# -----------------------------------------------------------------------------
# Security Group with Lifecycle
# -----------------------------------------------------------------------------
# 演示 create_before_destroy 和 prevent_destroy
#
# 实验步骤：
# 1. 修改 name（如添加 -v2 后缀），观察 -/+ 替换行为
# 2. 运行 terraform plan，观察 create_before_destroy 效果
# 3. 取消 prevent_destroy 注释，尝试 terraform destroy
#
# 注意：ingress 规则变更是 in-place 更新，不会触发替换
#       只有 name/vpc_id 等变更才会触发替换

resource "aws_security_group" "lifecycle_demo" {
  # 实验：将 name 改为 "lesson-03-sg-lifecycle-demo-v2"，观察替换行为
  name        = "lesson-03-sg-lifecycle-demo"
  description = "Lifecycle meta-arguments demo"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "lesson-03-sg-lifecycle"
  }

  # -------------------------------------------------------------------------
  # Lifecycle Block
  # -------------------------------------------------------------------------
  lifecycle {
    # create_before_destroy
    # ---------------------
    # 默认行为：先删除旧资源，再创建新资源（可能导致服务中断）
    # 设为 true：先创建新资源，切换引用，再删除旧资源
    #
    # 适用场景：
    # - Security Group（EC2 实例引用中）
    # - IAM Role（服务引用中）
    # - 任何需要零停机替换的资源
    create_before_destroy = true

    # prevent_destroy
    # ---------------
    # 禁止 terraform destroy 删除此资源
    # 尝试删除会报错，保护关键基础设施
    #
    # 取消注释以体验保护效果：
    # prevent_destroy = true

    # ignore_changes
    # --------------
    # 忽略特定属性的变化，即使手动修改也不会被 Terraform 覆盖
    #
    # 适用场景：
    # - 运维人员手动添加的标签
    # - 自动扩展组的容量（由 ASG 控制）
    # - 被其他系统修改的属性
    #
    # 取消注释以忽略标签变化：
    # ignore_changes = [tags]
  }
}

# -----------------------------------------------------------------------------
# replace_triggered_by 演示（Terraform 1.2+）
# -----------------------------------------------------------------------------
# 当关联资源变化时，触发此资源替换
#
# 场景示例：
# - 当 user_data 模板文件变化时，重建 EC2 实例
# - 当配置对象变化时，重启服务

resource "null_resource" "config_watcher" {
  # 当这个触发器变化时，null_resource 会被替换
  triggers = {
    # 监控 security group 的变化
    sg_id = aws_security_group.lifecycle_demo.id
  }

  # null_resource 使用 hashicorp/null provider（已在 providers.tf 中配置）
}

# -----------------------------------------------------------------------------
# Lifecycle 最佳实践
# -----------------------------------------------------------------------------
#
# 1. create_before_destroy
#    - 用于需要零停机替换的资源
#    - 注意：可能需要处理命名冲突（如 Security Group 名称）
#
# 2. prevent_destroy
#    - 仅用于真正关键的资源（生产数据库、State Bucket）
#    - 不要滥用，否则清理环境会很麻烦
#
# 3. ignore_changes
#    - 谨慎使用，可能导致配置漂移
#    - 记录为什么需要忽略（注释说明）
#
# 4. replace_triggered_by
#    - 用于建立"如果 X 变化，Y 也需要更新"的关系
#    - 比 depends_on 更精细的控制
#
# -----------------------------------------------------------------------------
