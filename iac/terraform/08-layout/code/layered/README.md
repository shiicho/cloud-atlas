# 分层架构示例

本示例演示 Terraform 分层设计模式。

## 目录结构

```
layered/
├── 01-network/          # 第一层：网络基础设施
│   └── dev/
│       ├── main.tf      # VPC, Subnets, IGW, NAT
│       ├── outputs.tf   # 输出 VPC ID, Subnet IDs 等
│       └── backend.tf   # State 存储
│
├── 02-foundations/      # 第二层：数据层
│   └── dev/
│       ├── main.tf      # RDS, ElastiCache, S3
│       ├── data.tf      # 引用 01-network 的 outputs
│       └── backend.tf
│
└── 03-application/      # 第三层：应用层
    └── dev/
        ├── main.tf      # EC2, ECS, Lambda
        ├── data.tf      # 引用 01 和 02 的 outputs
        └── backend.tf
```

## 部署顺序

```bash
# 必须按顺序部署！
cd 01-network/dev && terraform apply
cd 02-foundations/dev && terraform apply
cd 03-application/dev && terraform apply
```

## 销毁顺序

```bash
# 销毁必须反向进行！
cd 03-application/dev && terraform destroy
cd 02-foundations/dev && terraform destroy
cd 01-network/dev && terraform destroy
```

## 跨层数据共享

使用 `terraform_remote_state` 数据源读取其他层的输出：

```hcl
data "terraform_remote_state" "network" {
  backend = "s3"
  config = {
    bucket = "my-terraform-state"
    key    = "dev/network/terraform.tfstate"
    region = "ap-northeast-1"
  }
}

# 使用
resource "aws_instance" "app" {
  subnet_id = data.terraform_remote_state.network.outputs.private_subnet_ids[0]
}
```
