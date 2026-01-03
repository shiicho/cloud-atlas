# ALB Module

创建 Application Load Balancer 及相关资源，用于 Web 应用的负载均衡。

## 功能

- Application Load Balancer
- Target Group（支持健康检查配置）
- HTTP Listener（80 端口）
- HTTPS Listener（443 端口，可选）
- Security Group（自动配置 HTTP/HTTPS 入站规则）
- 访问日志（可选）

## 使用示例

### 基础配置（HTTP only）

```hcl
module "alb" {
  source = "./modules/alb"

  project           = "myapp"
  environment       = "dev"
  vpc_id            = module.vpc.vpc_id
  public_subnet_ids = module.vpc.public_subnet_ids
}
```

### 完整配置（含 HTTPS）

```hcl
module "alb" {
  source = "./modules/alb"

  project           = "myapp"
  environment       = "prod"
  vpc_id            = module.vpc.vpc_id
  public_subnet_ids = module.vpc.public_subnet_ids

  # HTTPS 配置
  certificate_arn = "arn:aws:acm:ap-northeast-1:123456789012:certificate/xxx"
  ssl_policy      = "ELBSecurityPolicy-TLS13-1-2-2021-06"

  # 目标配置
  target_port = 8080

  # 健康检查
  health_check_path     = "/health"
  health_check_matcher  = "200-299"
  health_check_interval = 15

  # 删除保护（生产环境推荐）
  enable_deletion_protection = true

  # 访问日志
  access_logs_bucket = "my-alb-logs-bucket"
  access_logs_prefix = "prod/alb"

  tags = {
    Owner = "platform-team"
  }
}
```

## Requirements

| Name | Version |
|------|---------|
| terraform | ~> 1.14 |
| aws | >= 5.0 |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| project | 项目名称 | `string` | n/a | yes |
| environment | 环境名称 | `string` | n/a | yes |
| vpc\_id | VPC ID | `string` | n/a | yes |
| public\_subnet\_ids | 公共子网 ID 列表 | `list(string)` | n/a | yes |
| target\_port | 目标端口 | `number` | `80` | no |
| certificate\_arn | ACM 证书 ARN | `string` | `null` | no |
| ssl\_policy | SSL 策略 | `string` | `"ELBSecurityPolicy-TLS13-1-2-2021-06"` | no |
| health\_check\_path | 健康检查路径 | `string` | `"/"` | no |
| health\_check\_matcher | 成功状态码 | `string` | `"200"` | no |
| health\_check\_interval | 检查间隔（秒） | `number` | `30` | no |
| deregistration\_delay | 注销延迟（秒） | `number` | `300` | no |
| enable\_deletion\_protection | 删除保护 | `bool` | `false` | no |
| access\_logs\_bucket | 访问日志 Bucket | `string` | `null` | no |

## Outputs

| Name | Description |
|------|-------------|
| alb\_arn | ALB ARN |
| alb\_dns\_name | ALB DNS 名称 |
| alb\_url | ALB 访问 URL |
| target\_group\_arn | 目标组 ARN |
| security\_group\_id | ALB 安全组 ID |
| http\_listener\_arn | HTTP 监听器 ARN |
| https\_listener\_arn | HTTPS 监听器 ARN |

## 成本

| 资源 | 成本 |
|------|------|
| ALB | ~$16/月 + LCU 费用 |
| 数据传输 | $0.008/GB（区域内） |

**注意：** LCU (Load Balancer Capacity Units) 根据连接数、新连接率、规则数和处理数据量计费。
