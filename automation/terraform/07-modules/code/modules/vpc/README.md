# VPC Module

创建 VPC 及相关网络资源。

## 使用示例

```hcl
module "vpc" {
  source = "./modules/vpc"

  environment    = "dev"
  vpc_cidr       = "10.0.0.0/16"
  public_subnets = ["10.0.1.0/24", "10.0.2.0/24"]
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| environment | 环境名称（dev/staging/prod） | `string` | n/a | yes |
| vpc_cidr | VPC CIDR block | `string` | `"10.0.0.0/16"` | no |
| public_subnets | 公共子网 CIDR 列表 | `list(string)` | `["10.0.1.0/24", "10.0.2.0/24"]` | no |
| enable_dns | 启用 DNS 支持和主机名 | `bool` | `true` | no |
| enable_nat | 是否创建 NAT Gateway | `bool` | `false` | no |
| tags | 额外标签 | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| vpc_id | VPC ID |
| vpc_cidr | VPC CIDR block |
| public_subnet_ids | 公共子网 ID 列表 |
| internet_gateway_id | Internet Gateway ID |

## 创建的资源

- aws_vpc
- aws_internet_gateway
- aws_subnet (public)
- aws_route_table (public)
- aws_route_table_association
