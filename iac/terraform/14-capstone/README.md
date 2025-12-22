# 14 - 实战项目：三层 Web 架构

> **目标**：综合运用所学知识，从零构建生产级三层 Web 架构  
> **前置**：已完成 [13 - 测试与质量保证](../13-testing/)  
> **时间**：8-10 小时（分 4 个阶段完成）  
> **费用**：$10-20（及时清理！完成后立即 `terraform destroy`）

---

## !! 成本警告 !!

```
+------------------------------------------------------------------+
|  本项目会创建真实 AWS 资源！                                      |
|                                                                   |
|  预估成本: $10-20（如果及时清理）                                  |
|                                                                   |
|  建议:                                                            |
|  - 使用 t3.micro/small 实例                                       |
|  - RDS 使用 db.t3.micro                                           |
|  - 每阶段完成后评估是否需要保留                                    |
|  - 项目结束后立即 terraform destroy 所有环境                       |
|  - 设置 AWS Budget Alert（$20 阈值）                              |
+------------------------------------------------------------------+
```

---

## 项目概述

本 Capstone 项目将综合运用 Terraform 课程的所有知识，构建一个完整的三层 Web 架构：

![Three-Tier Architecture](images/three-tier-architecture.png)

<details>
<summary>View ASCII source</summary>

```
                   Three-Tier Web Architecture

                        ┌─────────────┐
                        │   Users     │
                        └──────┬──────┘
                               │
                               ▼
  ┌─────────────────────────────────────────────────────────────┐
  │                    Public Subnets                            │
  │  ┌─────────────────────────────────────────────────────┐    │
  │  │              Application Load Balancer              │    │
  │  │                  (HTTPS:443)                        │    │
  │  └──────────────────────┬──────────────────────────────┘    │
  └─────────────────────────┼───────────────────────────────────┘
                            │
  ┌─────────────────────────┼───────────────────────────────────┐
  │                    Private Subnets (App Tier)                │
  │                         │                                    │
  │       ┌─────────────────┼─────────────────┐                  │
  │       │                 ▼                 │                  │
  │  ┌────┴────┐      ┌───────────┐     ┌────┴────┐              │
  │  │   EC2   │      │    EC2    │     │   EC2   │              │
  │  │  (ASG)  │      │   (ASG)   │     │  (ASG)  │              │
  │  └────┬────┘      └─────┬─────┘     └────┬────┘              │
  │       │                 │                │                   │
  └───────┼─────────────────┼────────────────┼───────────────────┘
          │                 │                │
  ┌───────┼─────────────────┼────────────────┼───────────────────┐
  │       └─────────────────┼────────────────┘                   │
  │                    Private Subnets (DB Tier)                 │
  │                         │                                    │
  │                         ▼                                    │
  │               ┌─────────────────┐                            │
  │               │     RDS MySQL   │                            │
  │               │   (Multi-AZ)    │                            │
  │               └─────────────────┘                            │
  └──────────────────────────────────────────────────────────────┘
```

</details>

---

## 学习目标

完成本项目后，你将能够：

1. **设计多环境项目布局** - dev/staging/prod 目录结构
2. **构建可复用模块库** - VPC、ALB、EC2、RDS 模块
3. **导入现有资源并重构** - terraform import + moved blocks
4. **配置 CI/CD Pipeline** - GitHub Actions plan + apply 工作流
5. **运维演练** - Drift 检测/修复、State Lock 解锁、Provider 升级

---

## 项目阶段

| 阶段 | 名称 | 预计时间 | 主要任务 |
|------|------|----------|----------|
| 1 | Scaffold & Setup | ~2 小时 | 项目结构、远程后端、CI 工作流 |
| 2 | Build via Modules | ~4 小时 | VPC/ALB/EC2/RDS 模块开发 |
| 3 | Import & Refactor | ~2 小时 | 导入资源、Policy Gate |
| 4 | Operations Drill | ~2 小时 | Drift/Lock/升级演练 |

---

## Phase 1: Scaffold & Setup（~2 小时）

### 1.1 项目目录结构

```bash
cd ~/cloud-atlas/iac/terraform/14-capstone/code
tree
```

```
code/
├── modules/                    # 可复用模块
│   ├── vpc/                    # VPC 模块
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   └── README.md
│   ├── alb/                    # ALB 模块
│   ├── ec2/                    # EC2/ASG 模块
│   └── rds/                    # RDS 模块
├── environments/               # 环境配置
│   ├── dev/                    # 开发环境
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   ├── backend.tf
│   │   └── terraform.tfvars
│   ├── staging/                # 预发布环境
│   └── prod/                   # 生产环境
├── .github/
│   └── workflows/
│       ├── terraform-plan.yml  # PR 时自动 plan
│       └── terraform-apply.yml # 手动审批 apply
└── docs/
    └── runbook.md              # 操作手册
```

### 1.2 创建远程后端（Bootstrap）

首先需要创建 S3 bucket 用于存储 state：

```bash
# 创建 S3 bucket（替换 YOUR_ACCOUNT_ID）
aws s3 mb s3://tfstate-capstone-YOUR_ACCOUNT_ID --region ap-northeast-1

# 启用版本控制
aws s3api put-bucket-versioning \
  --bucket tfstate-capstone-YOUR_ACCOUNT_ID \
  --versioning-configuration Status=Enabled
```

> **Note**: Terraform 1.10+ 支持原生 S3 锁定 (`use_lockfile = true`)，通过 `.tflock` 文件实现锁机制。

### 1.3 配置后端（environments/dev/backend.tf）

```hcl
terraform {
  backend "s3" {
    bucket       = "tfstate-capstone-YOUR_ACCOUNT_ID"
    key          = "dev/terraform.tfstate"
    region       = "ap-northeast-1"
    use_lockfile = true  # Terraform 1.10+ 原生 S3 锁定
    encrypt      = true
  }
}
```

### 1.4 Tagging 规范

定义统一的标签策略：

```hcl
# 在 environments/dev/locals.tf 中定义
locals {
  common_tags = {
    Project     = "capstone"
    Environment = var.environment
    ManagedBy   = "terraform"
    Owner       = "your-team"
    CostCenter  = "training"
  }
}
```

### 1.5 验证检查点

- [ ] S3 bucket 已创建并启用版本控制
- [ ] `terraform init` 成功连接远程后端
- [ ] GitHub Actions 工作流文件已创建

---

## Phase 2: Build via Modules（~4 小时）

### 2.1 VPC 模块设计

VPC 模块创建完整的网络基础设施：

**输入变量：**
- `vpc_cidr` - VPC CIDR 块
- `environment` - 环境名称
- `public_subnets` - 公共子网 CIDR 列表
- `private_subnets` - 私有子网 CIDR 列表
- `database_subnets` - 数据库子网 CIDR 列表
- `enable_nat_gateway` - 是否启用 NAT Gateway

**输出值：**
- `vpc_id` - VPC ID
- `public_subnet_ids` - 公共子网 ID 列表
- `private_subnet_ids` - 私有子网 ID 列表
- `database_subnet_ids` - 数据库子网 ID 列表
- `nat_gateway_ip` - NAT Gateway 公网 IP

### 2.2 ALB 模块设计

**输入变量：**
- `name` - ALB 名称
- `vpc_id` - VPC ID
- `subnet_ids` - 子网 ID 列表
- `security_group_ids` - 安全组 ID 列表

**输出值：**
- `alb_arn` - ALB ARN
- `alb_dns_name` - ALB DNS 名称
- `target_group_arn` - 目标组 ARN
- `listener_arn` - 监听器 ARN

### 2.3 EC2/ASG 模块设计

**输入变量：**
- `name` - ASG 名称
- `instance_type` - 实例类型
- `min_size` / `max_size` / `desired_capacity` - ASG 容量
- `subnet_ids` - 子网 ID 列表
- `target_group_arns` - 目标组 ARN 列表
- `user_data` - 启动脚本

**输出值：**
- `asg_name` - ASG 名称
- `launch_template_id` - 启动模板 ID

### 2.4 RDS 模块设计

**输入变量：**
- `identifier` - RDS 实例标识
- `engine` / `engine_version` - 数据库引擎
- `instance_class` - 实例类型
- `allocated_storage` - 存储大小
- `db_name` / `username` / `password` - 数据库凭证
- `subnet_ids` - 子网 ID 列表
- `vpc_security_group_ids` - 安全组 ID 列表

**输出值：**
- `db_instance_endpoint` - 数据库端点
- `db_instance_id` - 实例 ID

### 2.5 组装三层架构（Dev 环境）

```hcl
# environments/dev/main.tf

module "vpc" {
  source = "../../modules/vpc"

  environment        = var.environment
  vpc_cidr           = "10.0.0.0/16"
  public_subnets     = ["10.0.1.0/24", "10.0.2.0/24"]
  private_subnets    = ["10.0.11.0/24", "10.0.12.0/24"]
  database_subnets   = ["10.0.21.0/24", "10.0.22.0/24"]
  enable_nat_gateway = true  # Dev 可以用单 NAT 省钱

  tags = local.common_tags
}

module "alb" {
  source = "../../modules/alb"

  name               = "${var.environment}-alb"
  vpc_id             = module.vpc.vpc_id
  subnet_ids         = module.vpc.public_subnet_ids
  security_group_ids = [aws_security_group.alb.id]

  tags = local.common_tags
}

module "app" {
  source = "../../modules/ec2"

  name             = "${var.environment}-app"
  instance_type    = "t3.micro"
  min_size         = 1
  max_size         = 3
  desired_capacity = 2
  subnet_ids       = module.vpc.private_subnet_ids
  target_group_arns = [module.alb.target_group_arn]

  tags = local.common_tags
}

module "database" {
  source = "../../modules/rds"

  identifier         = "${var.environment}-db"
  engine             = "mysql"
  engine_version     = "8.0"  # AWS RDS EOL: 2026-07, 新项目考虑 8.4+
  instance_class     = "db.t3.micro"
  allocated_storage  = 20
  db_name            = "appdb"
  username           = "admin"
  # password 从 SSM Parameter Store 获取
  subnet_ids         = module.vpc.database_subnet_ids
  security_group_ids = [aws_security_group.rds.id]

  tags = local.common_tags
}
```

### 2.6 验证检查点

- [ ] VPC 模块：VPC + Subnets + IGW + NAT + Route Tables 创建成功
- [ ] ALB 模块：ALB + Target Group + Listener 创建成功
- [ ] EC2 模块：Launch Template + ASG 创建成功
- [ ] RDS 模块：RDS 实例创建成功
- [ ] 所有模块有 README.md（使用 terraform-docs 生成）

---

## Phase 3: Import & Refactor（~2 小时）

### 3.1 导入手动创建的资源

假设有一个手动在 Console 创建的 EC2 实例需要纳入管理：

```bash
# 1. 在 Console 创建一个 "legacy" EC2 实例（用于练习）

# 2. 编写对应的 Terraform 配置
cat >> main.tf << 'EOF'
resource "aws_instance" "legacy" {
  ami           = "ami-0c3fd0f5d33134a76"
  instance_type = "t3.micro"

  tags = {
    Name = "legacy-instance"
  }
}
EOF

# 3. 导入资源
terraform import aws_instance.legacy i-xxxxxxxxx

# 4. 调整配置使 plan 无变更
terraform plan
```

### 3.2 使用 moved blocks 重构

当需要将资源移入模块或重命名时：

```hcl
# 在 main.tf 中添加 moved block
moved {
  from = aws_instance.legacy
  to   = module.legacy_app.aws_instance.main
}
```

### 3.3 添加 Policy Gate

配置 Trivy 和 tflint 在 CI 中运行：

```yaml
# .github/workflows/terraform-plan.yml
- name: Run Trivy
  uses: aquasecurity/trivy-action@0.33.1
  with:
    scan-type: 'config'
    scan-ref: 'environments/dev'
    severity: 'HIGH,CRITICAL'

- name: Run tflint
  uses: terraform-linters/setup-tflint@v6
  with:
    tflint_version: latest
```

### 3.4 配置 Infracost

在 PR 中显示成本变化：

```yaml
# .github/workflows/infracost.yml
- name: Setup Infracost
  uses: infracost/actions/setup@v3
  with:
    api-key: ${{ secrets.INFRACOST_API_KEY }}

- name: Post Infracost comment
  run: |
    infracost diff --path=environments/dev \
      --format=json --out-file=/tmp/infracost.json
    infracost comment github --path=/tmp/infracost.json \
      --repo=$GITHUB_REPOSITORY \
      --github-token=${{ github.token }} \
      --pull-request=${{ github.event.pull_request.number }} \
      --behavior=update
```

### 3.5 验证检查点

- [ ] 成功导入一个手动创建的资源
- [ ] moved block 正常工作（无资源重建）
- [ ] Trivy/tflint 在 CI 中运行并通过
- [ ] Infracost PR 评论显示成本

---

## Phase 4: Operations Drill（~2 小时）

### 4.1 Drift 检测与修复

**注入 Drift：**

1. 在 AWS Console 手动修改一个资源标签
2. 运行 `terraform plan` 检测 Drift
3. 决定：恢复到 Terraform 配置 or 更新配置接受变更

```bash
# 检测 Drift
terraform plan -refresh-only

# 修复方式 1：应用配置恢复
terraform apply

# 修复方式 2：使用 ignore_changes 接受变更
# lifecycle {
#   ignore_changes = [tags["ModifiedManually"]]
# }
```

### 4.2 State Lock 解锁演练

模拟 Lock 卡住的场景：

```bash
# 查看 .tflock 文件（S3 原生锁定）
aws s3 ls s3://tfstate-capstone-YOUR_ACCOUNT_ID/dev/

# 强制解锁（谨慎！确认无其他操作进行中）
terraform force-unlock LOCK_ID
```

### 4.3 Provider 升级演练

```bash
# 1. 查看当前版本
cat .terraform.lock.hcl

# 2. 升级 Provider
terraform init -upgrade

# 3. 验证无破坏性变更
terraform plan

# 4. 提交 lock 文件
git add .terraform.lock.hcl
git commit -m "chore: upgrade AWS provider to x.y.z"
```

### 4.4 编写 Runbook

完成 `docs/runbook.md`，包含：

- 日常操作流程
- Drift 修复步骤
- 紧急回滚流程
- 联系人信息

### 4.5 验证检查点

- [ ] 能检测并修复 Drift
- [ ] 知道如何解锁 State Lock
- [ ] 成功升级 Provider 版本
- [ ] Runbook 文档完成

---

## 交付物清单

完成项目后，你应该有以下交付物：

| 交付物 | 位置 | 说明 |
|--------|------|------|
| **基础设施** | AWS | VPC + ALB + EC2 + RDS（记得 destroy！） |
| **模块文档** | `modules/*/README.md` | terraform-docs 生成 |
| **CI/CD Pipeline** | `.github/workflows/` | plan + apply 工作流 |
| **Runbook** | `docs/runbook.md` | 操作手册 |
| **Interview Story** | 你的记录 | 遇到的问题及解决方案 |

---

## 面试故事准备

完成项目后，整理以下内容用于面试：

### 项目概述模板

```
プロジェクト名: Terraform 三層 Web アーキテクチャ
期間: X 日
役割: インフラエンジニア（個人プロジェクト）

技術スタック:
- Terraform (v1.x)
- AWS (VPC, ALB, EC2, RDS)
- GitHub Actions (CI/CD)
- Trivy, tflint (Policy as Code)

成果:
- 4 つの再利用可能なモジュールを作成
- CI/CD パイプラインを構築（PR で自動 plan、手動承認で apply）
- 既存リソースの Import と Drift 検知/修復を実践
```

### 问题解决记录模板

```
課題: [遇到的问题]
原因: [根本原因分析]
解決策: [采取的解决方案]
学び: [学到的教训]
```

**示例：**

```
課題: terraform apply 中に State Lock がタイムアウトで残留
原因: ネットワーク切断により apply が中断、S3 の .tflock ファイルが残った
解決策: terraform force-unlock で手動解除後、正常に apply 完了
学び: CI 環境でのタイムアウト設定見直し、ロック監視アラート追加を検討
```

---

## 清理资源

**重要！** 项目完成后立即清理所有资源：

```bash
# 逆序销毁（先销毁依赖资源）
cd environments/dev
terraform destroy -auto-approve

# 清理远程后端（可选，如果不再需要）
aws s3 rb s3://tfstate-capstone-YOUR_ACCOUNT_ID --force
```

---

## 职场小贴士

### 日本 IT 企业的 IaC 实践

在日本企业，Terraform 项目通常需要：

| 项目 | 日本术语 | 说明 |
|------|----------|------|
| 设计文档 | 設計書 | 详细的架构图和参数一览表 |
| 变更申请 | 変更管理票 | 记录变更内容、影响范围、回滚计划 |
| 审批流程 | 承認フロー | 开发 → 组长 → 基础设施负责人 |
| 操作手册 | 運用手順書 | 日常操作、故障对应步骤 |
| 证迹保存 | エビデンス | 操作日志、截图保存 |

### 面试高频问题

**Q: Terraform プロジェクトで苦労したことは？**

A: State の管理が最も難しかった。チーム開発では State Lock の競合、Drift の検知と修復、Import 時のコード生成など、State 関連の課題が多い。解決策として、S3 リモートバックエンド（TF 1.10+ の `use_lockfile` による原生ロック）、定期的な Drift 検知、コードレビューでの plan 結果確認を導入した。

**Q: モジュール設計で気をつけていることは？**

A: 単一責任の原則、適切な粒度（大きすぎず小さすぎず）、明確な Input/Output 境界、terraform-docs によるドキュメント自動生成。

**Q: CI/CD パイプラインの設計は？**

A: PR で plan 自動実行、結果をコメントで可視化、apply は Environment 承認が必要。OIDC 認証で長期クレデンシャル不要。Infracost でコスト可視化。

---

## コミュニティでの次の一歩

Capstone プロジェクトを完成させたら、コミュニティで発表してみましょう！

- **JAWS-UG IaC Night** - AWS Japan User Group の IaC 分科会
  - https://jawsug.connpass.com/
- **HashiCorp User Group Japan** - Terraform/Vault/Consul ユーザーコミュニティ
  - https://www.meetup.com/hashicorp-user-group-japan/

実績 + ネットワーク拡大のチャンス！

---

## 下一步

恭喜你完成 Terraform 主课程的 Capstone 项目！

接下来可以学习日本 IT 专题：

- [15 - 日本 IT：変更管理と承認フロー](../15-jp-change-mgmt/)
- [16 - 日本 IT：監査対応とドキュメント](../16-jp-audit/)

---

## 延伸阅读

- [Terraform Best Practices](https://www.terraform-best-practices.com/)
- [AWS Well-Architected Framework](https://aws.amazon.com/architecture/well-architected/)
- [terraform-aws-modules](https://github.com/terraform-aws-modules) - 社区模块参考
- [Gruntwork Lessons Learned](https://blog.gruntwork.io/5-lessons-learned-from-writing-over-300000-lines-of-infrastructure-code-36ba7fadebd4)

---

## 系列导航

← [13 · 测试](../13-testing/) | [Home](../) | [15 · 変更管理 →](../15-jp-change-mgmt/)
