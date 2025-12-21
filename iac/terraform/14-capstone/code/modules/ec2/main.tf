# =============================================================================
# modules/ec2/main.tf
# EC2/ASG 模块 - 创建 Auto Scaling Group 及相关资源
# =============================================================================
#
# 本模块创建：
# - Launch Template
# - Auto Scaling Group
# - Security Group
# - IAM Instance Profile（可选）
#
# =============================================================================

# -----------------------------------------------------------------------------
# Data Sources
# -----------------------------------------------------------------------------

# 获取最新的 Amazon Linux 2023 AMI
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

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }
}

# SSM 参数获取自定义 AMI（可选）
data "aws_ssm_parameter" "ami" {
  count = var.ami_ssm_parameter != null ? 1 : 0
  name  = var.ami_ssm_parameter
}

# -----------------------------------------------------------------------------
# Local Values
# -----------------------------------------------------------------------------

locals {
  name_prefix = "${var.project}-${var.environment}"

  # 使用自定义 AMI 或默认 Amazon Linux 2023
  ami_id = coalesce(
    var.ami_id,
    var.ami_ssm_parameter != null ? data.aws_ssm_parameter.ami[0].value : null,
    data.aws_ami.amazon_linux.id
  )

  common_tags = merge(
    {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "terraform"
      Module      = "ec2"
    },
    var.tags
  )
}

# -----------------------------------------------------------------------------
# Security Group
# EC2 实例安全组
# -----------------------------------------------------------------------------

resource "aws_security_group" "ec2" {
  name        = "${local.name_prefix}-ec2-sg"
  description = "Security group for ${local.name_prefix} EC2 instances"
  vpc_id      = var.vpc_id

  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-ec2-sg"
    }
  )

  lifecycle {
    create_before_destroy = true
  }
}

# 入站规则：来自 ALB 的流量
resource "aws_vpc_security_group_ingress_rule" "from_alb" {
  count = var.alb_security_group_id != null ? 1 : 0

  security_group_id            = aws_security_group.ec2.id
  description                  = "Allow traffic from ALB"
  from_port                    = var.app_port
  to_port                      = var.app_port
  ip_protocol                  = "tcp"
  referenced_security_group_id = var.alb_security_group_id

  tags = {
    Name = "${local.name_prefix}-ec2-alb-ingress"
  }
}

# 入站规则：SSH（仅 Bastion，可选）
resource "aws_vpc_security_group_ingress_rule" "ssh" {
  count = var.enable_ssh_access ? 1 : 0

  security_group_id            = aws_security_group.ec2.id
  description                  = "Allow SSH from bastion"
  from_port                    = 22
  to_port                      = 22
  ip_protocol                  = "tcp"
  referenced_security_group_id = var.bastion_security_group_id

  tags = {
    Name = "${local.name_prefix}-ec2-ssh-ingress"
  }
}

# 出站规则：允许所有出站
resource "aws_vpc_security_group_egress_rule" "all" {
  security_group_id = aws_security_group.ec2.id
  description       = "Allow all outbound traffic"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"

  tags = {
    Name = "${local.name_prefix}-ec2-all-egress"
  }
}

# -----------------------------------------------------------------------------
# IAM Instance Profile
# EC2 实例 IAM 角色
# -----------------------------------------------------------------------------

resource "aws_iam_role" "ec2" {
  count = var.create_iam_role ? 1 : 0

  name = "${local.name_prefix}-ec2-role"

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

  tags = local.common_tags
}

# 附加 SSM 管理策略（允许 SSM Session Manager 连接）
resource "aws_iam_role_policy_attachment" "ssm" {
  count = var.create_iam_role ? 1 : 0

  role       = aws_iam_role.ec2[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# 附加 CloudWatch Agent 策略（可选）
resource "aws_iam_role_policy_attachment" "cloudwatch" {
  count = var.create_iam_role && var.enable_cloudwatch_agent ? 1 : 0

  role       = aws_iam_role.ec2[0].name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_instance_profile" "ec2" {
  count = var.create_iam_role ? 1 : 0

  name = "${local.name_prefix}-ec2-profile"
  role = aws_iam_role.ec2[0].name

  tags = local.common_tags
}

# -----------------------------------------------------------------------------
# Launch Template
# 定义 EC2 实例配置
# -----------------------------------------------------------------------------

resource "aws_launch_template" "main" {
  name        = "${local.name_prefix}-lt"
  description = "Launch template for ${local.name_prefix}"

  image_id      = local.ami_id
  instance_type = var.instance_type

  # 启用 IMDSv2（安全最佳实践）
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "enabled"
  }

  # 网络配置
  network_interfaces {
    associate_public_ip_address = false
    security_groups             = [aws_security_group.ec2.id]
    delete_on_termination       = true
  }

  # EBS 优化
  ebs_optimized = var.ebs_optimized

  # 根卷配置
  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      volume_size           = var.root_volume_size
      volume_type           = var.root_volume_type
      encrypted             = true
      delete_on_termination = true
    }
  }

  # IAM Instance Profile
  dynamic "iam_instance_profile" {
    for_each = var.create_iam_role ? [1] : (var.iam_instance_profile_arn != null ? [1] : [])
    content {
      arn = var.create_iam_role ? aws_iam_instance_profile.ec2[0].arn : var.iam_instance_profile_arn
    }
  }

  # 监控
  monitoring {
    enabled = var.enable_detailed_monitoring
  }

  # User Data
  user_data = var.user_data != null ? base64encode(var.user_data) : base64encode(<<-EOF
    #!/bin/bash
    # 默认的 User Data 脚本
    # 更新系统
    dnf update -y

    # 安装基本工具
    dnf install -y httpd

    # 启动 Apache
    systemctl start httpd
    systemctl enable httpd

    # 创建健康检查页面
    echo "OK" > /var/www/html/health

    # 创建示例页面
    INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
    cat > /var/www/html/index.html << HTML
    <!DOCTYPE html>
    <html>
    <head><title>Capstone Project</title></head>
    <body>
    <h1>Hello from Terraform Capstone!</h1>
    <p>Instance ID: $INSTANCE_ID</p>
    <p>Environment: ${var.environment}</p>
    </body>
    </html>
    HTML
  EOF
  )

  # 标签
  tag_specifications {
    resource_type = "instance"
    tags = merge(
      local.common_tags,
      {
        Name = "${local.name_prefix}-instance"
      }
    )
  }

  tag_specifications {
    resource_type = "volume"
    tags = merge(
      local.common_tags,
      {
        Name = "${local.name_prefix}-volume"
      }
    )
  }

  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-lt"
    }
  )

  lifecycle {
    create_before_destroy = true
  }
}

# -----------------------------------------------------------------------------
# Auto Scaling Group
# 管理 EC2 实例集群
# -----------------------------------------------------------------------------

resource "aws_autoscaling_group" "main" {
  name                = "${local.name_prefix}-asg"
  vpc_zone_identifier = var.private_subnet_ids
  target_group_arns   = var.target_group_arns

  min_size         = var.min_size
  max_size         = var.max_size
  desired_capacity = var.desired_capacity

  # 健康检查配置
  health_check_type         = "ELB"
  health_check_grace_period = var.health_check_grace_period

  # 启动模板
  launch_template {
    id      = aws_launch_template.main.id
    version = "$Latest"
  }

  # 实例刷新配置
  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 50
      instance_warmup        = var.instance_warmup
    }
  }

  # 终止策略
  termination_policies = ["OldestLaunchTemplate", "OldestInstance"]

  # 启用指标收集
  enabled_metrics = [
    "GroupMinSize",
    "GroupMaxSize",
    "GroupDesiredCapacity",
    "GroupInServiceInstances",
    "GroupPendingInstances",
    "GroupStandbyInstances",
    "GroupTerminatingInstances",
    "GroupTotalInstances"
  ]

  # 标签传播
  dynamic "tag" {
    for_each = merge(
      local.common_tags,
      {
        Name = "${local.name_prefix}-asg"
      }
    )
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }

  lifecycle {
    create_before_destroy = true
    ignore_changes        = [desired_capacity] # 允许手动调整
  }
}

# -----------------------------------------------------------------------------
# Auto Scaling Policies（可选）
# 自动扩缩策略
# -----------------------------------------------------------------------------

resource "aws_autoscaling_policy" "scale_up" {
  count = var.enable_autoscaling ? 1 : 0

  name                   = "${local.name_prefix}-scale-up"
  scaling_adjustment     = 1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 300
  autoscaling_group_name = aws_autoscaling_group.main.name
}

resource "aws_autoscaling_policy" "scale_down" {
  count = var.enable_autoscaling ? 1 : 0

  name                   = "${local.name_prefix}-scale-down"
  scaling_adjustment     = -1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 300
  autoscaling_group_name = aws_autoscaling_group.main.name
}

# CloudWatch 告警触发扩缩
resource "aws_cloudwatch_metric_alarm" "high_cpu" {
  count = var.enable_autoscaling ? 1 : 0

  alarm_name          = "${local.name_prefix}-high-cpu"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 120
  statistic           = "Average"
  threshold           = var.scale_up_threshold

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.main.name
  }

  alarm_description = "Scale up if CPU > ${var.scale_up_threshold}%"
  alarm_actions     = [aws_autoscaling_policy.scale_up[0].arn]

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "low_cpu" {
  count = var.enable_autoscaling ? 1 : 0

  alarm_name          = "${local.name_prefix}-low-cpu"
  comparison_operator = "LessThanOrEqualToThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 120
  statistic           = "Average"
  threshold           = var.scale_down_threshold

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.main.name
  }

  alarm_description = "Scale down if CPU < ${var.scale_down_threshold}%"
  alarm_actions     = [aws_autoscaling_policy.scale_down[0].arn]

  tags = local.common_tags
}
