# RDS Module

创建 RDS 数据库实例及相关资源，支持 MySQL、PostgreSQL 和 MariaDB。

## 功能

- RDS Instance
- DB Subnet Group
- Security Group（仅允许应用层访问）
- Parameter Group（可选）
- 自动生成密码并存储到 SSM Parameter Store
- Enhanced Monitoring（可选）
- Performance Insights（可选）
- CloudWatch Alarms（可选）

## 使用示例

### 基础配置（Dev 环境）

```hcl
module "database" {
  source = "./modules/rds"

  project             = "myapp"
  environment         = "dev"
  vpc_id              = module.vpc.vpc_id
  database_subnet_ids = module.vpc.database_subnet_ids

  engine         = "mysql"
  engine_version = "8.0"
  instance_class = "db.t3.micro"

  app_security_group_id = module.app.security_group_id
}
```

### 生产环境配置

```hcl
module "database" {
  source = "./modules/rds"

  project             = "myapp"
  environment         = "prod"
  vpc_id              = module.vpc.vpc_id
  database_subnet_ids = module.vpc.database_subnet_ids

  # 引擎配置
  engine         = "mysql"
  engine_version = "8.0"
  instance_class = "db.r6g.large"

  # 存储配置
  allocated_storage     = 100
  max_allocated_storage = 500
  storage_type          = "gp3"

  # 高可用
  multi_az = true

  # 备份配置
  backup_retention_period = 30
  backup_window           = "03:00-04:00"
  maintenance_window      = "Mon:04:00-Mon:05:00"

  # 监控
  monitoring_interval          = 60
  performance_insights_enabled = true
  enabled_cloudwatch_logs_exports = ["error", "slowquery"]

  # 安全
  deletion_protection = true
  skip_final_snapshot = false

  # 告警
  create_cloudwatch_alarms = true
  alarm_actions            = [aws_sns_topic.alerts.arn]

  app_security_group_id = module.app.security_group_id

  tags = {
    Owner = "dba-team"
  }
}
```

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.5.0 |
| aws | >= 5.0 |
| random | >= 3.0 |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| project | 项目名称 | `string` | n/a | yes |
| environment | 环境名称 | `string` | n/a | yes |
| vpc\_id | VPC ID | `string` | n/a | yes |
| database\_subnet\_ids | 数据库子网 ID 列表 | `list(string)` | n/a | yes |
| engine | 数据库引擎 | `string` | `"mysql"` | no |
| engine\_version | 引擎版本 | `string` | `"8.0"` | no |
| instance\_class | 实例类型 | `string` | `"db.t3.micro"` | no |
| allocated\_storage | 初始存储（GB） | `number` | `20` | no |
| max\_allocated\_storage | 最大存储（GB） | `number` | `100` | no |
| multi\_az | Multi-AZ 部署 | `bool` | `false` | no |
| backup\_retention\_period | 备份保留天数 | `number` | `7` | no |
| master\_password | 主密码（不设置则自动生成） | `string` | `null` | no |
| app\_security\_group\_id | 应用层安全组 ID | `string` | `null` | no |
| deletion\_protection | 删除保护 | `bool` | `false` | no |

## Outputs

| Name | Description |
|------|-------------|
| db\_instance\_endpoint | RDS 端点 |
| db\_instance\_address | RDS 地址 |
| db\_instance\_port | RDS 端口 |
| db\_name | 数据库名称 |
| db\_username | 用户名 |
| db\_password\_ssm\_parameter | 密码的 SSM Parameter 名称 |
| security\_group\_id | RDS 安全组 ID |
| connection\_string | 连接字符串模板 |

## 安全特性

- **存储加密**: 默认启用 EBS 加密
- **密码管理**: 自动生成强密码并存储到 SSM Parameter Store
- **网络隔离**: 部署在私有子网，无公网访问
- **安全组**: 仅允许应用层访问

## 获取数据库密码

```bash
# 从 SSM Parameter Store 获取密码
aws ssm get-parameter \
  --name "/myapp/dev/rds/master-password" \
  --with-decryption \
  --query "Parameter.Value" \
  --output text
```

## 成本

| 实例类型 | 成本（ap-northeast-1） | 适用场景 |
|----------|------------------------|----------|
| db.t3.micro | ~$15/月 | Dev/Test |
| db.t3.small | ~$30/月 | Small Prod |
| db.t3.medium | ~$60/月 | Medium Prod |
| db.r6g.large | ~$150/月 | Large Prod |

**额外成本：**
- Multi-AZ: 约 2x 实例成本
- 存储: ~$0.12/GB/月 (gp3)
- 备份: 超过配额后 ~$0.095/GB/月
- Performance Insights: $0/月（7天保留免费）

**省钱技巧：**
- Dev 环境使用 db.t3.micro，禁用 Multi-AZ
- 非必要时设置较短的备份保留期
- 使用 gp3 代替 io1
