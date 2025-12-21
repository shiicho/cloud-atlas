# EC2/ASG Module

创建 Auto Scaling Group 和相关资源，用于部署应用服务器。

## 功能

- Launch Template（支持 IMDSv2）
- Auto Scaling Group
- Security Group
- IAM Instance Profile（支持 SSM Session Manager）
- 自动扩缩策略（可选）
- CloudWatch 告警触发扩缩

## 使用示例

### 基础配置

```hcl
module "app" {
  source = "./modules/ec2"

  project            = "myapp"
  environment        = "dev"
  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids

  target_group_arns     = [module.alb.target_group_arn]
  alb_security_group_id = module.alb.security_group_id
}
```

### 完整配置

```hcl
module "app" {
  source = "./modules/ec2"

  project            = "myapp"
  environment        = "prod"
  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids

  # 实例配置
  instance_type    = "t3.small"
  root_volume_size = 50
  root_volume_type = "gp3"

  # ASG 配置
  min_size         = 2
  max_size         = 10
  desired_capacity = 4

  # 目标组
  target_group_arns     = [module.alb.target_group_arn]
  alb_security_group_id = module.alb.security_group_id

  # 自动扩缩
  enable_autoscaling   = true
  scale_up_threshold   = 70
  scale_down_threshold = 30

  # 监控
  enable_detailed_monitoring = true
  enable_cloudwatch_agent    = true

  # 自定义 User Data
  user_data = file("${path.module}/scripts/user-data.sh")

  tags = {
    Owner = "platform-team"
  }
}
```

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.5.0 |
| aws | >= 5.0 |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| project | 项目名称 | `string` | n/a | yes |
| environment | 环境名称 | `string` | n/a | yes |
| vpc\_id | VPC ID | `string` | n/a | yes |
| private\_subnet\_ids | 私有子网 ID 列表 | `list(string)` | n/a | yes |
| instance\_type | 实例类型 | `string` | `"t3.micro"` | no |
| ami\_id | AMI ID | `string` | `null` | no |
| min\_size | ASG 最小实例数 | `number` | `1` | no |
| max\_size | ASG 最大实例数 | `number` | `3` | no |
| desired\_capacity | ASG 期望实例数 | `number` | `2` | no |
| target\_group\_arns | ALB 目标组 ARN 列表 | `list(string)` | `[]` | no |
| alb\_security\_group\_id | ALB 安全组 ID | `string` | `null` | no |
| enable\_autoscaling | 是否启用自动扩缩 | `bool` | `true` | no |
| user\_data | 自定义 User Data | `string` | `null` | no |

## Outputs

| Name | Description |
|------|-------------|
| asg\_name | Auto Scaling Group 名称 |
| asg\_arn | Auto Scaling Group ARN |
| launch\_template\_id | Launch Template ID |
| security\_group\_id | EC2 安全组 ID |
| iam\_role\_arn | EC2 IAM Role ARN |
| ami\_id | 使用的 AMI ID |

## 安全特性

- **IMDSv2**: 强制使用 Token 访问实例元数据
- **EBS 加密**: 根卷自动加密
- **SSM 支持**: 可通过 Session Manager 连接，无需 SSH Key
- **最小权限**: IAM Role 仅包含必要权限

## 成本

| 资源 | 成本（ap-northeast-1） |
|------|------------------------|
| t3.micro | ~$0.0136/小时 (~$10/月) |
| t3.small | ~$0.0272/小时 (~$20/月) |
| t3.medium | ~$0.0544/小时 (~$40/月) |
| CloudWatch 详细监控 | ~$3/月/实例 |

**省钱技巧：**
- Dev 环境使用 t3.micro
- 非必要时禁用详细监控
- 设置合理的 max_size 防止意外扩容
