# 进阶实验：多环境布局实践

> **目标**：动手部署 Directory Structure 和 Layered Architecture 示例，深入理解多环境管理
> **前置**：已完成 [08 - 项目布局与多环境策略](./README.md) 的 Workspaces 部分
> **时间**：30-40 分钟
> **费用**：S3 Bucket（免费层）+ EC2 t3.micro（可能产生少量费用）

---

## 实验目标

通过本实验，你将：

1. 动手部署 Directory Structure 示例，理解模块化环境隔离
2. 动手部署 Layered Architecture 示例，掌握分层依赖管理
3. 理解 `terraform_remote_state` 跨层数据共享机制
4. 体验正向部署和反向销毁的操作流程

---

## Part 1: Directory Structure 实践

### Step 1: 浏览目录结构

**命令：**

```bash
cd ~/cloud-atlas/iac/terraform/08-layout/code/directory-structure
tree -L 3
```

**期待输出：**

```
.
├── modules/
│   └── s3-bucket/
│       ├── main.tf
│       ├── variables.tf
│       └── outputs.tf
└── environments/
    ├── dev/
    │   ├── main.tf
    │   ├── variables.tf
    │   ├── terraform.tfvars
    │   ├── backend.tf
    │   ├── providers.tf
    │   └── outputs.tf
    ├── staging/
    │   └── ...
    └── prod/
        └── ...
```

**关注点：**

| 要素 | 说明 |
|------|------|
| `modules/` | 共享的可复用模块 |
| `environments/` | 每个环境独立目录 |
| `terraform.tfvars` | 环境特定配置 |
| `backend.tf` | 独立 State 存储 |

**验证点：**

```bash
# 查看三个环境的差异
diff environments/dev/terraform.tfvars environments/staging/terraform.tfvars
diff environments/staging/terraform.tfvars environments/prod/terraform.tfvars
```

---

### Step 2: 部署 dev 环境

**命令：**

```bash
# 进入 dev 环境目录
cd ~/cloud-atlas/iac/terraform/08-layout/code/directory-structure/environments/dev

# 初始化
terraform init
```

**期待输出：**

```
Initializing the backend...

Initializing provider plugins...
- Finding hashicorp/aws versions matching ">= 5.0"...
- Finding hashicorp/random versions matching ">= 3.0"...
...

Terraform has been successfully initialized!
```

**关注点：**

注意模块初始化信息：
```
Initializing modules...
- s3_bucket in ../../modules/s3-bucket
```

这表明 dev 环境正在引用 `modules/s3-bucket` 共享模块。

**继续部署：**

```bash
# 查看计划
terraform plan
```

**期待输出（关键部分）：**

```
Terraform will perform the following actions:

  # module.s3_bucket.aws_s3_bucket.this will be created
  + resource "aws_s3_bucket" "this" {
      + bucket        = (known after apply)
      + force_destroy = true          # dev 允许强制删除
      ...
    }

  # module.s3_bucket.aws_s3_bucket_versioning.this will be created
  + resource "aws_s3_bucket_versioning" "this" {
      + versioning_configuration {
          + status = "Suspended"      # dev 关闭版本控制
        }
      ...
    }

  # module.s3_bucket.aws_s3_bucket_lifecycle_configuration.this[0] will be created
  + resource "aws_s3_bucket_lifecycle_configuration" "this" {
      + rule {
          + id     = "cleanup"
          + status = "Enabled"
          + expiration {
              + days = 7              # dev: 7 天后清理
            }
        }
      ...
    }

Plan: 5 to add, 0 to change, 0 to destroy.
```

**验证点：**

观察 dev 环境的特点：
- `force_destroy = true` - 允许强制删除（便于开发测试）
- `versioning = Suspended` - 关闭版本控制（节省存储）
- `lifecycle_days = 7` - 短期保留（快速清理）

```bash
# 确认无误后部署
terraform apply -auto-approve
```

**期待输出：**

```
Apply complete! Resources: 5 added, 0 changed, 0 destroyed.

Outputs:

bucket_arn = "arn:aws:s3:::myapp-dev-a1b2c3d4"
bucket_id = "myapp-dev-a1b2c3d4"
bucket_name = "myapp-dev-a1b2c3d4"
```

---

### Step 3: 观察模块化效果

**命令：**

```bash
# 查看模块内部结构
cat ../../modules/s3-bucket/main.tf | head -30
```

**关注点：**

模块使用 `var.environment` 来区分环境，而非硬编码：

```hcl
resource "aws_s3_bucket" "this" {
  bucket = "${var.bucket_prefix}-${var.environment}-${random_id.suffix.hex}"

  # 非 prod 环境允许强制删除
  force_destroy = var.environment != "prod"
  ...
}
```

**验证点：**

```bash
# 查看 dev 环境如何调用模块
cat main.tf
```

**期待输出：**

```hcl
module "s3_bucket" {
  source = "../../modules/s3-bucket"

  environment       = var.environment       # 来自 terraform.tfvars
  bucket_prefix     = var.bucket_prefix     # 来自 terraform.tfvars
  enable_versioning = var.enable_versioning # 来自 terraform.tfvars
  lifecycle_days    = var.lifecycle_days    # 来自 terraform.tfvars

  tags = {
    Team    = "development"
    Purpose = "Dev environment storage"
  }
}
```

---

### Step 4: 对比环境配置

**命令：**

```bash
# 查看三个环境的配置差异
echo "=== DEV ===" && cat terraform.tfvars
echo ""
echo "=== STAGING ===" && cat ../staging/terraform.tfvars
echo ""
echo "=== PROD ===" && cat ../prod/terraform.tfvars
```

**期待输出：**

```
=== DEV ===
environment       = "dev"
bucket_prefix     = "myapp"
enable_versioning = false
lifecycle_days    = 7

=== STAGING ===
environment       = "staging"
bucket_prefix     = "myapp"
enable_versioning = true
lifecycle_days    = 30

=== PROD ===
environment       = "prod"
bucket_prefix     = "myapp"
enable_versioning = true
lifecycle_days    = 90
```

**关注点：**

| 配置项 | dev | staging | prod |
|--------|-----|---------|------|
| `enable_versioning` | false | true | true |
| `lifecycle_days` | 7 | 30 | 90 |

同一模块，不同配置 = 不同行为

**验证点：**

```bash
# 确认 State 是独立的
ls -la terraform.tfstate
ls -la ../staging/  # staging 目录下没有 .tfstate（未部署）
```

---

### Step 5: 清理 dev 环境

**命令：**

```bash
# 清理 dev 环境资源
terraform destroy -auto-approve
```

**期待输出：**

```
Destroy complete! Resources: 5 destroyed.
```

**验证点：**

```bash
# 确认 State 已清空
terraform state list  # 应为空
```

---

## Part 2: 分层架构实践

> **重要**：分层架构必须按顺序部署（1->2->3），反向销毁（3->2->1）

### Step 1: 理解分层依赖

**命令：**

```bash
cd ~/cloud-atlas/iac/terraform/08-layout/code/layered
tree -L 3
```

**期待输出：**

```
.
├── 01-network/
│   └── dev/
│       ├── main.tf      # VPC, Subnets, IGW
│       ├── outputs.tf   # 输出 VPC ID, Subnet IDs
│       ├── backend.tf
│       └── providers.tf
├── 02-foundations/
│   └── dev/
│       ├── main.tf      # S3, Security Groups
│       ├── data.tf      # 引用 01-network outputs
│       ├── outputs.tf
│       ├── backend.tf
│       └── providers.tf
├── 03-application/
│   └── dev/
│       ├── main.tf      # EC2, IAM
│       ├── data.tf      # 引用 01 和 02 outputs
│       ├── outputs.tf
│       ├── backend.tf
│       └── providers.tf
└── README.md
```

**关注点：**

```
Layer 1 (Network)    ← 基础层，无依赖
    ↓
Layer 2 (Foundations) ← 依赖 Layer 1
    ↓
Layer 3 (Application) ← 依赖 Layer 1 和 Layer 2
```

**验证点：**

```bash
# 查看 Layer 2 如何引用 Layer 1
cat 02-foundations/dev/data.tf
```

---

### Step 2: 部署 Layer 1 (Network)

**命令：**

```bash
cd ~/cloud-atlas/iac/terraform/08-layout/code/layered/01-network/dev

# 初始化
terraform init
```

**期待输出：**

```
Terraform has been successfully initialized!
```

**继续部署：**

```bash
# 查看计划
terraform plan
```

**期待输出（关键部分）：**

```
Terraform will perform the following actions:

  # aws_internet_gateway.main will be created
  # aws_route_table.public will be created
  # aws_security_group.default will be created
  # aws_subnet.private[0] will be created
  # aws_subnet.private[1] will be created
  # aws_subnet.public[0] will be created
  # aws_subnet.public[1] will be created
  # aws_vpc.main will be created

Plan: 11 to add, 0 to change, 0 to destroy.

Changes to Outputs:
  + availability_zones        = [...]
  + default_security_group_id = (known after apply)
  + private_subnet_ids        = (known after apply)
  + public_subnet_ids         = (known after apply)
  + vpc_cidr                  = "10.0.0.0/16"
  + vpc_id                    = (known after apply)
```

**关注点：**

Layer 1 创建的核心资源：
- 1 个 VPC
- 2 个 Public Subnets + 2 个 Private Subnets
- 1 个 Internet Gateway
- Route Tables 和 Security Group

**部署：**

```bash
terraform apply -auto-approve
```

**期待输出：**

```
Apply complete! Resources: 11 added, 0 changed, 0 destroyed.

Outputs:

availability_zones = tolist([
  "ap-northeast-1a",
  "ap-northeast-1c",
])
default_security_group_id = "sg-0abc123def456789"
private_subnet_ids = [
  "subnet-0aaa111222333444",
  "subnet-0bbb555666777888",
]
public_subnet_ids = [
  "subnet-0ccc999000111222",
  "subnet-0ddd333444555666",
]
vpc_cidr = "10.0.0.0/16"
vpc_id = "vpc-0xyz789abc123def"
```

---

### Step 3: 验证 Layer 1 输出

**命令：**

```bash
# 确认 outputs 可用
terraform output

# 查看具体值
terraform output vpc_id
terraform output public_subnet_ids
```

**期待输出：**

```
"vpc-0xyz789abc123def"

tolist([
  "subnet-0ccc999000111222",
  "subnet-0ddd333444555666",
])
```

**验证点：**

```bash
# 确认 State 文件存在
ls -la terraform.tfstate
```

这个 State 文件将被 Layer 2 通过 `terraform_remote_state` 引用。

---

### Step 4: 部署 Layer 2 (Foundations)

**命令：**

```bash
cd ~/cloud-atlas/iac/terraform/08-layout/code/layered/02-foundations/dev

# 初始化
terraform init
```

**期待输出：**

```
Terraform has been successfully initialized!
```

**继续：**

```bash
# 查看计划
terraform plan
```

**期待输出（关键部分）：**

```
data.terraform_remote_state.network: Reading...
data.terraform_remote_state.network: Read complete

Terraform will perform the following actions:

  # aws_db_subnet_group.main will be created
  + resource "aws_db_subnet_group" "main" {
      + name       = "demo-dev-db-subnet-group"
      + subnet_ids = [
          + "subnet-0aaa111222333444",  # 来自 Layer 1
          + "subnet-0bbb555666777888",
        ]
    }

  # aws_s3_bucket.data will be created
  # aws_security_group.data will be created
  + resource "aws_security_group" "data" {
      + vpc_id = "vpc-0xyz789abc123def"  # 来自 Layer 1
    }

Plan: 5 to add, 0 to change, 0 to destroy.
```

**关注点：**

注意 `data.terraform_remote_state.network: Read complete` - 这表明成功读取了 Layer 1 的 State。

**验证点：**

```bash
# 查看 data.tf 如何引用 Layer 1
cat data.tf
```

**期待输出：**

```hcl
data "terraform_remote_state" "network" {
  backend = "local"
  config = {
    path = "../../01-network/dev/terraform.tfstate"
  }
}
```

**部署：**

```bash
terraform apply -auto-approve
```

**期待输出：**

```
Apply complete! Resources: 5 added, 0 changed, 0 destroyed.

Outputs:

data_bucket_arn = "arn:aws:s3:::demo-dev-data-abc12345"
data_bucket_name = "demo-dev-data-abc12345"
data_security_group_id = "sg-0data123456789"
db_subnet_group_name = "demo-dev-db-subnet-group"
private_subnet_ids = [...]  # 透传自 Layer 1
vpc_id = "vpc-0xyz789abc123def"  # 透传自 Layer 1
```

---

### Step 5: 验证跨层引用

**命令：**

```bash
# 查看 Layer 2 如何使用 Layer 1 的数据
cat main.tf | head -20
```

**期待输出：**

```hcl
locals {
  environment = "dev"
  name_prefix = "demo-${local.environment}"

  # 从 Network Layer 获取数据
  vpc_id             = data.terraform_remote_state.network.outputs.vpc_id
  private_subnet_ids = data.terraform_remote_state.network.outputs.private_subnet_ids
}
```

**关注点：**

跨层数据共享的关键模式：
1. `data "terraform_remote_state"` - 读取其他层的 State
2. `data.terraform_remote_state.network.outputs.xxx` - 访问输出值
3. 赋值给 `locals` - 便于在资源中使用

**验证点：**

```bash
# 确认 DB Subnet Group 使用了正确的 Subnets
aws ec2 describe-subnets \
  --subnet-ids $(terraform output -json private_subnet_ids | jq -r '.[]') \
  --query 'Subnets[*].{ID:SubnetId,CIDR:CidrBlock,AZ:AvailabilityZone}' \
  --output table
```

---

### Step 6: 部署 Layer 3 (Application)

**命令：**

```bash
cd ~/cloud-atlas/iac/terraform/08-layout/code/layered/03-application/dev

# 初始化
terraform init
```

**期待输出：**

```
Terraform has been successfully initialized!
```

**继续：**

```bash
# 查看计划
terraform plan
```

**期待输出（关键部分）：**

```
data.terraform_remote_state.network: Reading...
data.terraform_remote_state.foundations: Reading...
data.terraform_remote_state.network: Read complete
data.terraform_remote_state.foundations: Read complete
data.aws_ami.amazon_linux_2023: Reading...
data.aws_ami.amazon_linux_2023: Read complete

Terraform will perform the following actions:

  # aws_instance.app will be created
  + resource "aws_instance" "app" {
      + ami                    = "ami-0abcdef123456789"
      + instance_type          = "t3.micro"
      + subnet_id              = "subnet-0ccc999000111222"  # 来自 Layer 1
      + iam_instance_profile   = (known after apply)
    }

  # aws_iam_role_policy.app_s3 will be created
  + resource "aws_iam_role_policy" "app_s3" {
      + policy = jsonencode({
          + Resource = [
              + "arn:aws:s3:::demo-dev-data-abc12345",      # 来自 Layer 2
              + "arn:aws:s3:::demo-dev-data-abc12345/*",
            ]
        })
    }

Plan: 6 to add, 0 to change, 0 to destroy.
```

**关注点：**

Layer 3 同时引用了 Layer 1 和 Layer 2：
- `subnet_id` 来自 Layer 1 (Network)
- `data_bucket_arn` 来自 Layer 2 (Foundations)

**验证点：**

```bash
# 查看 Layer 3 的 data.tf
cat data.tf
```

**期待输出：**

```hcl
# 引用 Network Layer
data "terraform_remote_state" "network" {
  backend = "local"
  config = {
    path = "../../01-network/dev/terraform.tfstate"
  }
}

# 引用 Foundations Layer
data "terraform_remote_state" "foundations" {
  backend = "local"
  config = {
    path = "../../02-foundations/dev/terraform.tfstate"
  }
}
```

**部署：**

```bash
terraform apply -auto-approve
```

**期待输出：**

```
Apply complete! Resources: 6 added, 0 changed, 0 destroyed.

Outputs:

app_instance_id = "i-0abc123def456789"
app_public_dns = "ec2-12-34-56-78.ap-northeast-1.compute.amazonaws.com"
app_public_ip = "12.34.56.78"
app_security_group_id = "sg-0app987654321"
app_url = "http://12.34.56.78"
```

---

### Step 7: 完整验证

**命令：**

```bash
# 测试应用是否可访问
APP_URL=$(terraform output -raw app_url)
echo "Testing: $APP_URL"
curl -s --connect-timeout 10 $APP_URL || echo "(需要等待 EC2 初始化完成)"
```

**期待输出：**

```
Testing: http://12.34.56.78
<h1>Hello from dev environment!</h1>
```

> **注意**：EC2 初始化可能需要 1-2 分钟。如果 curl 失败，等待后重试。

**验证整体架构：**

```bash
# 查看所有层的 State
echo "=== Layer 1: Network ==="
(cd ../../01-network/dev && terraform output | head -3)

echo ""
echo "=== Layer 2: Foundations ==="
(cd ../../02-foundations/dev && terraform output | head -3)

echo ""
echo "=== Layer 3: Application ==="
terraform output | head -3
```

**关注点：**

三个独立的 State，通过 `terraform_remote_state` 建立依赖关系：

```
01-network/dev/terraform.tfstate
    ↓ (terraform_remote_state)
02-foundations/dev/terraform.tfstate
    ↓ (terraform_remote_state)
03-application/dev/terraform.tfstate
```

---

### Step 8: 清理资源（反向顺序）

> **重要**：必须按反向顺序销毁（3->2->1），否则会因依赖关系失败！

**命令：**

```bash
# Step 8.1: 销毁 Layer 3 (Application)
cd ~/cloud-atlas/iac/terraform/08-layout/code/layered/03-application/dev
terraform destroy -auto-approve
```

**期待输出：**

```
Destroy complete! Resources: 6 destroyed.
```

```bash
# Step 8.2: 销毁 Layer 2 (Foundations)
cd ~/cloud-atlas/iac/terraform/08-layout/code/layered/02-foundations/dev
terraform destroy -auto-approve
```

**期待输出：**

```
Destroy complete! Resources: 5 destroyed.
```

```bash
# Step 8.3: 销毁 Layer 1 (Network)
cd ~/cloud-atlas/iac/terraform/08-layout/code/layered/01-network/dev
terraform destroy -auto-approve
```

**期待输出：**

```
Destroy complete! Resources: 11 destroyed.
```

**验证点：**

```bash
# 确认所有资源已清理
for layer in 01-network 02-foundations 03-application; do
  echo "=== $layer ==="
  (cd ~/cloud-atlas/iac/terraform/08-layout/code/layered/$layer/dev && terraform state list)
done
```

所有层应返回空。

---

## 本实验小结

### Part 1: Directory Structure

| 要点 | 说明 |
|------|------|
| **独立目录** | 每个环境是独立的 Terraform root module |
| **共享模块** | 环境通过 `modules/` 共享代码，避免重复 |
| **差异化配置** | `terraform.tfvars` 存储环境特定值 |
| **独立 State** | 每个环境的 State 自然隔离，无切换风险 |

### Part 2: Layered Architecture

| 要点 | 说明 |
|------|------|
| **分层依赖** | 下层依赖上层，通过 `terraform_remote_state` 共享数据 |
| **部署顺序** | 必须按 1->2->3 顺序部署 |
| **销毁顺序** | 必须按 3->2->1 反向销毁 |
| **爆炸半径** | 应用层变更不影响网络层，降低风险 |

### 职场应用（日本 IT 现场）

在日本的运维现场（運用現場），分层架构带来以下好处：

| 日本語 | 效果 |
|--------|------|
| 変更管理 | 每层可独立审批，网络层变更需额外确认 |
| 障害対応 | 问题定位更快，只需关注受影响的层 |
| 担当分離 | インフラ担当管理网络层，アプリ担当管理应用层 |
| 証跡管理 | 每层的 State 变更可独立追溯 |

---

## 下一步

- 回到主课程：[08 - 项目布局与多环境策略](./README.md)
- 继续下一课：[09 - 既存基础设施导入 (Import)](../09-import/)
