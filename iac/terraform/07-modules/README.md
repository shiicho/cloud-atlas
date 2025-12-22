# 07 · 模块化设计

> **目标**：创建可复用的 Terraform 模块，实现多环境部署
> **前置**：已完成 [06 · 循环条件与表达式](../06-loops/)
> **时间**：40-45 分钟
> **费用**：VPC + Subnets（免费层）

---

## 将学到的内容

1. 理解模块的价值与设计原则
2. 创建可复用的 VPC 模块
3. 在多环境中调用同一模块
4. 使用不同来源的模块（local, Git, Registry）
5. 使用 terraform-docs 生成文档

---

## Step 1 — 快速验证环境（2 分钟）

连接到你的 Terraform Lab 实例：

```bash
aws ssm start-session --target i-你的实例ID --region ap-northeast-1
```

确认上一课的资源已清理：

```bash
cd ~/cloud-atlas/iac/terraform/06-loops/code
terraform state list  # 应为空
```

---

## Step 2 — 立即体验：使用模块部署 VPC（5 分钟）

> 先"尝到"模块的便利，再理解内部结构。

### 2.1 进入示例代码目录

```bash
cd ~/cloud-atlas/iac/terraform/07-modules/code
ls -la
```

```
.
├── modules/
│   └── vpc/                 # VPC 模块
│       ├── main.tf
│       ├── variables.tf
│       ├── outputs.tf
│       └── README.md
└── environments/
    ├── dev/                 # 开发环境（含 provider 配置）
    │   ├── main.tf
    │   └── terraform.tfvars
    └── prod/                # 生产环境
        ├── main.tf
        └── terraform.tfvars
```

### 2.2 部署开发环境

```bash
cd environments/dev
terraform init
terraform plan
```

观察输出——模块创建多个资源：

```
# module.vpc.aws_vpc.main will be created
# module.vpc.aws_subnet.public[0] will be created
# module.vpc.aws_subnet.public[1] will be created
# module.vpc.aws_internet_gateway.main will be created
...

Plan: 5 to add, 0 to change, 0 to destroy.
```

```bash
terraform apply -auto-approve
```

```
Outputs:

vpc_id          = "vpc-0a1b2c3d4e5f6g7h8"
public_subnets  = ["subnet-xxx", "subnet-yyy"]
environment     = "dev"
```

### 2.3 对比生产环境配置

```bash
cd ../prod
cat terraform.tfvars
```

```hcl
environment = "prod"
vpc_cidr    = "10.1.0.0/16"  # 不同的 CIDR
```

**同一个模块，不同的配置！**

---

## Step 3 — 发生了什么？（5 分钟）

### 3.1 模块目录结构

```
modules/vpc/
├── main.tf          # 资源定义
├── variables.tf     # 输入变量
├── outputs.tf       # 输出值
└── README.md        # 文档
```

**约定大于配置**：
- `main.tf` — 主要资源
- `variables.tf` — 所有输入变量
- `outputs.tf` — 所有输出值
- `README.md` — 使用文档

### 3.2 模块调用语法

```hcl
module "vpc" {
  source = "../../modules/vpc"

  # 传递输入变量
  environment     = var.environment
  vpc_cidr        = var.vpc_cidr
  public_subnets  = var.public_subnets
}

# 引用模块输出
output "vpc_id" {
  value = module.vpc.vpc_id
}
```

### 3.3 模块封装

```
┌─────────────────────────────────────────────────────────┐
│                    Root Module (dev/)                   │
│  ┌─────────────────────────────────────────────────┐   │
│  │              module "vpc"                        │   │
│  │  ┌───────────────────────────────────────────┐  │   │
│  │  │ inputs:                                    │  │   │
│  │  │   vpc_cidr        ──────►  variables.tf   │  │   │
│  │  │   public_subnets  ──────►                 │  │   │
│  │  ├───────────────────────────────────────────┤  │   │
│  │  │ resources:                                 │  │   │
│  │  │   aws_vpc                                  │  │   │
│  │  │   aws_subnet                               │  │   │
│  │  │   aws_internet_gateway                     │  │   │
│  │  ├───────────────────────────────────────────┤  │   │
│  │  │ outputs:                                   │  │   │
│  │  │   vpc_id          ◄──────  outputs.tf     │  │   │
│  │  │   subnet_ids      ◄──────                 │  │   │
│  │  └───────────────────────────────────────────┘  │   │
│  └─────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────┘
```

---

## Step 4 — 动手实验：创建模块（15 分钟）

> 理解模块的内部结构。

### 4.1 查看模块变量

```bash
cat ../../modules/vpc/variables.tf
```

```hcl
variable "environment" {
  description = "环境名称（dev/staging/prod）"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnets" {
  description = "公共子网 CIDR 列表"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "enable_dns" {
  description = "启用 DNS 支持"
  type        = bool
  default     = true
}
```

### 4.2 查看模块资源

```bash
cat ../../modules/vpc/main.tf
```

```hcl
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = var.enable_dns
  enable_dns_support   = var.enable_dns

  tags = {
    Name        = "${var.environment}-vpc"
    Environment = var.environment
  }
}

resource "aws_subnet" "public" {
  count = length(var.public_subnets)

  vpc_id            = aws_vpc.main.id
  cidr_block        = var.public_subnets[count.index]
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name = "${var.environment}-public-${count.index + 1}"
  }
}
```

> **count vs for_each**：这里用 `count` 是因为子网列表是有序的。如果用 `for_each`（基于 key），删除中间元素时不会影响其他资源的 index。生产环境建议评估 `for_each` 以获得更稳定的状态管理。

### 4.3 查看模块输出

```bash
cat ../../modules/vpc/outputs.tf
```

```hcl
output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

output "vpc_cidr" {
  description = "VPC CIDR block"
  value       = aws_vpc.main.cidr_block
}

output "public_subnet_ids" {
  description = "公共子网 ID 列表"
  value       = aws_subnet.public[*].id
}
```

### 4.4 在 Root Module 中调用

```bash
cat main.tf
```

```hcl
module "vpc" {
  source = "../../modules/vpc"

  environment    = var.environment
  vpc_cidr       = var.vpc_cidr
  public_subnets = var.public_subnets
}

# 引用模块输出
output "vpc_id" {
  value = module.vpc.vpc_id
}
```

---

## Step 5 — 模块来源（5 分钟）

### 5.1 本地路径

```hcl
module "vpc" {
  source = "./modules/vpc"       # 相对路径
  source = "../shared/modules/vpc"  # 上级目录
  source = "/path/to/modules/vpc"   # 绝对路径
}
```

### 5.2 Git 仓库

```hcl
module "vpc" {
  source = "git::https://github.com/org/terraform-modules.git//vpc"
  # 指定分支/tag
  source = "git::https://github.com/org/terraform-modules.git//vpc?ref=v1.0.0"
}
```

### 5.3 Terraform Registry

```hcl
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.0"  # 2025-12 时点最新: 6.5.1

  name = "my-vpc"
  cidr = "10.0.0.0/16"
  ...
}
```

### 5.4 来源对比

| 来源 | 适用场景 | 版本控制 |
|------|----------|----------|
| Local | 同项目内模块 | 无（同代码） |
| Git | 组织内共享 | ref=tag/branch |
| Registry | 社区/官方模块 | version = "~> X.Y" |

---

## Step 6 — 模块设计最佳实践（5 分钟）

### 6.1 模块粒度

```
太大                     适中                      太小
──────                   ────                      ────
整个项目                 VPC 模块                  单个资源
                         EC2 模块                  包装一下
                         RDS 模块
```

**原则**：模块应封装一个**逻辑单元**，有明确的输入/输出边界。

### 6.2 变量设计

```hcl
# 好：有默认值，说明清晰
variable "enable_nat" {
  description = "是否创建 NAT Gateway（生产环境推荐启用）"
  type        = bool
  default     = false
}

# 差：无描述，无默认值
variable "x" {
  type = bool
}
```

### 6.3 输出设计

```hcl
# 好：输出常用属性
output "vpc_id" {
  value = aws_vpc.main.id
}

output "vpc_cidr" {
  value = aws_vpc.main.cidr_block
}

# 更好：输出整个对象（灵活）
output "vpc" {
  value = aws_vpc.main
}
```

### 6.4 文档

使用 terraform-docs 自动生成：

**安装 terraform-docs:**

| 平台 | 命令 |
|------|------|
| **macOS** | `brew install terraform-docs` |
| **Linux** | `curl -Lo ./terraform-docs.tar.gz https://github.com/terraform-docs/terraform-docs/releases/download/v0.21.0/terraform-docs-v0.21.0-linux-amd64.tar.gz && tar -xzf terraform-docs.tar.gz && chmod +x terraform-docs && sudo mv terraform-docs /usr/local/bin/` |
| **Windows** | `choco install terraform-docs` 或 `scoop install terraform-docs` |

```bash
# 生成文档
terraform-docs markdown table ./modules/vpc > ./modules/vpc/README.md
```

---

## Step 7 — 清理资源（3 分钟）

```bash
# 清理 dev 环境
cd ~/cloud-atlas/iac/terraform/07-modules/code/environments/dev
terraform destroy -auto-approve

# 如果部署了 prod，也要清理
cd ../prod
terraform destroy -auto-approve
```

```
Destroy complete! Resources: 5 destroyed.
```

---

## 本课小结

| 概念 | 说明 |
|------|------|
| **Module** | 可复用的 Terraform 代码单元 |
| **source** | 模块来源（local, git, registry） |
| **Input Variables** | 模块输入，通过 variables.tf 定义 |
| **Outputs** | 模块输出，供调用者使用 |
| **version** | Registry 模块的版本约束 |

**反模式警告**：

| 不要这样做 | 为什么 |
|------------|--------|
| 巨型 Root Module | 难以测试、审查、复用 |
| Registry 模块不锁版本 | Breaking changes 风险 |
| inline user_data | 难以维护，用 templatefile 或模块 |

---

## 下一步

模块设计掌握了，接下来学习项目布局与多环境策略。

→ [08 · 项目布局与多环境策略](../08-layout/)

---

## 面试准备

**よくある質問**

**Q: Module を使う利点は？**

A: 再利用性（同じモジュールを複数環境で使用）、カプセル化（実装詳細を隠蔽）、テスト容易性（独立してテスト可能）、チーム間の一貫性（標準化されたインフラパターン）。

**Q: Module のバージョン管理は？**

A: Registry モジュールは `version = "~> 1.0"` で固定。Git モジュールは `ref=v1.0.0` でタグ指定。ローカルモジュールはコードと一緒にバージョン管理。

**Q: Module の設計原則は？**

A: 単一責任（一つの論理単位）、明確な境界（input/output）、適切な粒度（大きすぎず小さすぎず）、ドキュメント必須（terraform-docs 使用）。

**Q: Root Module と Child Module の違いは？**

A: Root Module は `terraform apply` を実行するディレクトリ。Child Module は Root から呼び出されるモジュール。Child Module は直接 apply できない。

---

## トラブルシューティング

**よくある問題**

**Module source 変更後のエラー**

```
Error: Module source has changed
```

```bash
# モジュールソース変更時は -upgrade
terraform init -upgrade
```

**Module output が見つからない**

```
Error: Unsupported attribute
  module.vpc.nonexistent_output
```

→ モジュールの `outputs.tf` を確認。output が定義されているか確認。

**循環参照**

```
Error: Cycle: module.a, module.b
```

→ モジュール間の依存関係を見直し。output 経由でデータを渡す設計に変更。

---

## 系列导航

← [06 · 循环条件](../06-loops/) | [Home](../) | [08 · 项目布局 →](../08-layout/)
