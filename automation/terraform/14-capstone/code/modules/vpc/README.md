# VPC Module

创建完整的三层网络基础设施，包括公共子网、私有子网、数据库子网及相关路由。

## 架构

```
VPC
├── Public Subnets (2+)
│   └── Internet Gateway Route
├── Private Subnets (2+)
│   └── NAT Gateway Route
└── Database Subnets (2+)
    └── No Internet Route (隔离)
```

## 使用示例

### 最小配置

```hcl
module "vpc" {
  source = "./modules/vpc"

  project     = "myapp"
  environment = "dev"
  vpc_cidr    = "10.0.0.0/16"
}
```

### 完整配置

```hcl
module "vpc" {
  source = "./modules/vpc"

  project     = "myapp"
  environment = "prod"
  vpc_cidr    = "10.0.0.0/16"

  public_subnets   = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  private_subnets  = ["10.0.11.0/24", "10.0.12.0/24", "10.0.13.0/24"]
  database_subnets = ["10.0.21.0/24", "10.0.22.0/24", "10.0.23.0/24"]

  enable_nat_gateway = true
  single_nat_gateway = false  # 生产环境每个 AZ 一个 NAT

  enable_flow_logs         = true
  flow_logs_retention_days = 90

  tags = {
    Owner      = "platform-team"
    CostCenter = "infrastructure"
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
| environment | 环境名称 (dev/staging/prod) | `string` | n/a | yes |
| vpc\_cidr | VPC CIDR 块 | `string` | n/a | yes |
| public\_subnets | 公共子网 CIDR 列表 | `list(string)` | `["10.0.1.0/24", "10.0.2.0/24"]` | no |
| private\_subnets | 私有子网 CIDR 列表 | `list(string)` | `["10.0.11.0/24", "10.0.12.0/24"]` | no |
| database\_subnets | 数据库子网 CIDR 列表 | `list(string)` | `["10.0.21.0/24", "10.0.22.0/24"]` | no |
| enable\_nat\_gateway | 是否创建 NAT Gateway | `bool` | `true` | no |
| single\_nat\_gateway | 是否只创建一个 NAT Gateway | `bool` | `true` | no |
| enable\_flow\_logs | 是否启用 VPC Flow Logs | `bool` | `false` | no |
| flow\_logs\_retention\_days | Flow Logs 保留天数 | `number` | `30` | no |
| tags | 附加标签 | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| vpc\_id | VPC ID |
| vpc\_cidr\_block | VPC CIDR 块 |
| public\_subnet\_ids | 公共子网 ID 列表 |
| private\_subnet\_ids | 私有子网 ID 列表 |
| database\_subnet\_ids | 数据库子网 ID 列表 |
| database\_subnet\_group\_name | RDS 子网组名称 |
| nat\_gateway\_public\_ips | NAT Gateway 公网 IP 列表 |
| availability\_zones | 使用的可用区列表 |

## 成本考虑

| 资源 | 成本 | 说明 |
|------|------|------|
| NAT Gateway | ~$32/月 + 数据传输费 | 每个 NAT |
| Elastic IP | $3.6/月（未使用时） | 每个 EIP |
| VPC Flow Logs | ~$0.50/GB | CloudWatch Logs 费用 |

**省钱技巧：**
- Dev 环境使用 `single_nat_gateway = true`
- 非必要时禁用 Flow Logs
- 及时清理未使用的 EIP
