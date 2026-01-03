# 14 - 实战项目：三层 Web 架构

> **目标**：综合运用所学知识，从零构建生产级三层 Web 架构
> **前置**：已完成 [13 - 测试与质量保证](../13-testing/)
> **时间**：8-10 小时（分 4 个阶段完成）
> **费用**：$10-20/环境（及时清理！完成后立即 `terraform destroy`）

---

## !! 成本警告 !!

```
+------------------------------------------------------------------+
|  本项目会创建真实 AWS 资源！                                      |
|                                                                   |
|  预估成本: $10-20/环境（如果及时清理）                            |
|                                                                   |
|  建议:                                                            |
|  - 使用 t3.micro/small 实例                                       |
|  - RDS 使用 db.t3.micro                                           |
|  - 只在练习时部署 staging/prod（可选）                             |
|  - 每阶段完成后评估是否需要保留                                    |
|  - 项目结束后立即 terraform destroy 所有环境                       |
|  - 设置 AWS Budget Alert（$50 阈值）                              |
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
3. **配置远程后端** - 复用课程 S3 Bucket，lesson-specific state key
4. **配置 CI/CD Pipeline** - 参考 [11-cicd](../11-cicd/) 实现 GitHub Actions
5. **理解 Import in CI/CD** - 通过 PR 声明式导入（与本地 import 的区别）
6. **运维演练** - Drift 检测/修复、State Lock 解锁、Provider 升级

---

## 项目阶段

| 阶段 | 名称 | 预计时间 | 主要任务 |
|------|------|----------|----------|
| 1 | Environment Setup | ~1.5 小时 | 后端配置、CI/CD 基础设施 |
| 2 | Build Three-Tier | ~4 小时 | dev 环境部署、staging 配置 |
| 3 | CI/CD Integration | ~2 小时 | OIDC、PR 工作流、Import 演示 |
| 4 | Operations Drill + Prod | ~2 小时 | prod 部署、Drift/Lock 演练 |

---

## Step 0 — 环境准备与连接（2 分钟）

连接到你的 Terraform Lab 实例。

**获取实例 ID：**

```bash
aws cloudformation describe-stacks \
  --stack-name terraform-lab \
  --region ap-northeast-1 \
  --query 'Stacks[0].Outputs[?OutputKey==`InstanceId`].OutputValue' \
  --output text
```

> **💡 连接方式**（选择你熟悉的）：
> - **AWS Console**：EC2 → 选择实例 → Connect → Session Manager
> - **AWS CLI**：`aws ssm start-session --target <实例ID> --region ap-northeast-1`
> - **VS Code**：Remote-SSH 连接（如已配置）
>
> **❓ 没有实例？** Stack 不存在或实例已终止？
> → [重新部署实验环境](../00-concepts/lab-setup.md)

连接后，切换到课程用户并同步代码：

```bash
sudo su - terraform
sync-course
```

确认上一课的资源已清理：

```bash
cd ~/cloud-atlas/iac/terraform/13-testing/code
terraform state list  # 应为空
```

---

## Phase 1: Environment Setup（~1.5 小时）

### 1.1 项目目录结构

```bash
cd ~/cloud-atlas/iac/terraform/14-capstone/code
tree -L 2
```

```
code/
├── modules/                    # 可复用模块（已提供）
│   ├── vpc/                    # VPC 模块
│   ├── alb/                    # ALB 模块
│   ├── ec2/                    # EC2/ASG 模块
│   └── rds/                    # RDS 模块
├── environments/               # 环境配置
│   ├── dev/                    # 开发环境（本阶段部署）
│   ├── staging/                # 预发布环境（Phase 2）
│   └── prod/                   # 生产环境（Phase 4）
├── .github/
│   └── workflows/
│       ├── terraform-plan.yml  # PR 时自动 plan
│       ├── terraform-apply.yml # 手动审批 apply
│       └── infracost.yml       # 成本估算
└── docs/
    └── runbook.md              # 操作手册
```

### 1.2 获取远程后端配置

**课程 S3 Bucket 已由 CloudFormation 创建**，无需手动创建！

获取 Bucket 名称：

```bash
# 从 CloudFormation 输出获取
aws cloudformation describe-stacks \
  --stack-name terraform-lab \
  --region ap-northeast-1 \
  --query 'Stacks[0].Outputs[?OutputKey==`TfStateBucketName`].OutputValue' \
  --output text
```

输出示例：`tfstate-terraform-lab-635958930059`

> **💡 为什么复用课程 Bucket？**
>
> - **成本节约**：不需要创建额外的 S3 Bucket
> - **一致性**：所有课程使用同一个 Bucket，不同的 state key
> - **自动清理**：删除 terraform-lab stack 时自动清理 Bucket
>
> 每个 lesson 使用独立的 state key 路径：
> - `02-state/terraform.tfstate`
> - `14-capstone/dev/terraform.tfstate`
> - `14-capstone/staging/terraform.tfstate`

### 1.3 配置后端（environments/dev/backend.tf）

更新 `environments/dev/backend.tf`，替换 Bucket 名称：

```bash
cd environments/dev
cat backend.tf
```

```hcl
terraform {
  backend "s3" {
    # 替换为你的 Bucket 名称（从 CloudFormation 输出获取）
    bucket = "tfstate-terraform-lab-YOUR_ACCOUNT_ID"

    # 每个 lesson + 环境使用独立的 state key
    key = "14-capstone/dev/terraform.tfstate"

    region       = "ap-northeast-1"
    encrypt      = true
    use_lockfile = true  # Terraform 1.10+ 原生 S3 锁定
  }
}
```

**修改 Bucket 名称**：

```bash
# 获取你的 Bucket 名称
BUCKET=$(aws cloudformation describe-stacks \
  --stack-name terraform-lab \
  --query 'Stacks[0].Outputs[?OutputKey==`TfStateBucketName`].OutputValue' \
  --output text)

echo "Your bucket: $BUCKET"

# 更新 backend.tf
sed -i "s/tfstate-terraform-lab-REPLACE_WITH_YOUR_BUCKET/$BUCKET/" backend.tf
cat backend.tf
```

### 1.4 初始化后端

```bash
terraform init
```

成功输出：

```
Initializing the backend...

Successfully configured the backend "s3"! Terraform will automatically
use this backend unless the backend configuration changes.

Initializing modules...
...
Terraform has been successfully initialized!
```

### 1.5 验证检查点

- [ ] 获取到 S3 Bucket 名称（`tfstate-terraform-lab-xxx`）
- [ ] `backend.tf` 已更新为实际 Bucket 名称
- [ ] `terraform init` 成功连接远程后端
- [ ] State key 使用 `14-capstone/dev/terraform.tfstate`（lesson-specific）

---

## Phase 2: Build Three-Tier Architecture（~4 小时）

### 2.1 模块概览

本项目已提供 4 个模块：

| 模块 | 主要资源 | 文档 |
|------|----------|------|
| `modules/vpc` | VPC, Subnets, NAT, IGW, Route Tables | [README](code/modules/vpc/README.md) |
| `modules/alb` | ALB, Target Group, Listener, Security Group | [README](code/modules/alb/README.md) |
| `modules/ec2` | Launch Template, ASG, Scaling Policies | [README](code/modules/ec2/README.md) |
| `modules/rds` | RDS Instance, Subnet Group, Security Group | [README](code/modules/rds/README.md) |

> **💡 模块设计原则**（参考 [07-modules](../07-modules/)）
>
> - 单一职责：每个模块只做一件事
> - 明确边界：通过 variables 和 outputs 定义接口
> - 可配置性：环境差异通过变量控制

### 2.2 环境差异配置

三个环境的主要差异：

| 设置 | Dev | Staging | Prod |
|------|-----|---------|------|
| **NAT Gateway** | Single | Single | Per-AZ（高可用） |
| **RDS Multi-AZ** | No | No | Yes |
| **Deletion Protection** | No | No | Yes |
| **ASG Size** | 1-3 | 2-4 | 2-6 |
| **Backup Retention** | 1 day | 7 days | 30 days |
| **Flow Logs** | No | Yes | Yes |

### 2.3 部署 Dev 环境

```bash
cd ~/cloud-atlas/iac/terraform/14-capstone/code/environments/dev

# 1. 检查变量
cat terraform.tfvars

# 2. 预览变更
terraform plan

# 3. 部署（需要 15-20 分钟，RDS 较慢）
terraform apply
```

**预期输出**：

```
Apply complete! Resources: 30 added, 0 changed, 0 destroyed.

Outputs:

alb_dns_name = "dev-alb-xxxxxxxxx.ap-northeast-1.elb.amazonaws.com"
alb_url = "http://dev-alb-xxxxxxxxx.ap-northeast-1.elb.amazonaws.com"
...
```

### 2.4 验证 Dev 环境

```bash
# 获取 ALB URL
ALB_URL=$(terraform output -raw alb_url)
echo "ALB URL: $ALB_URL"

# 等待目标健康（可能需要 2-3 分钟）
sleep 180

# 测试访问
curl -s -o /dev/null -w "%{http_code}" $ALB_URL
# 应返回 200 或 503（如果应用未部署）
```

### 2.5 查看 State 在 S3 中的位置

```bash
# 确认 state 文件位置
BUCKET=$(terraform output -raw vpc_id | cut -d'-' -f1)  # 取 VPC ID 前缀作占位
BUCKET=$(aws cloudformation describe-stacks \
  --stack-name terraform-lab \
  --query 'Stacks[0].Outputs[?OutputKey==`TfStateBucketName`].OutputValue' \
  --output text)

aws s3 ls s3://$BUCKET/14-capstone/
# 应显示: dev/terraform.tfstate
```

### 2.6 验证检查点（Phase 2）

- [ ] VPC 创建成功（包含 6 个子网）
- [ ] NAT Gateway 创建成功（单个）
- [ ] ALB 创建成功（可访问）
- [ ] ASG 创建成功（实例运行中）
- [ ] RDS 创建成功（端点可用）
- [ ] State 文件在 S3 正确位置

---

## Phase 3: CI/CD Integration（~2 小时）

本阶段将项目与 GitHub Actions 集成，实现 PR-driven Terraform 工作流。

> **💡 参考课程**
>
> CI/CD 基础知识和 Hands-On Lab 在 [11-cicd](../11-cicd/) 中详细介绍。
> 本阶段重点是**应用**这些知识到多环境 Capstone 项目。

### 3.1 CI/CD 架构回顾

![PR-Driven Terraform Workflow](../11-cicd/images/cicd-workflow.png)

关键原则：
- **Plan 自动化**：PR 创建/更新时自动运行 `terraform plan`
- **Apply 门禁**：需要人工审批才能 apply（GitHub Environment）
- **OIDC 认证**：无需存储 Access Key，临时凭证

### 3.2 设置 GitHub 仓库（如果需要 CI/CD 实践）

如果你想实际体验 CI/CD，需要：

1. **创建 GitHub 仓库**
2. **部署 OIDC CloudFormation**（参考 [11-cicd/terraform-cicd-demo/oidc-setup/](../11-cicd/terraform-cicd-demo/oidc-setup/)）
3. **配置 GitHub Secrets**

> **⏭️ 跳过提示**
>
> 如果你在 [11-cicd](../11-cicd/) 已完成 Hands-On Lab，可以跳过 CI/CD 设置，
> 直接进入 3.4 了解 Import in CI/CD 的概念。

### 3.3 工作流配置（已提供）

项目已提供 CI/CD 工作流：

```
.github/workflows/
├── terraform-plan.yml    # PR 时自动 plan
├── terraform-apply.yml   # 合并后 apply（需审批）
└── infracost.yml         # 成本估算
```

**关键配置点**：

```yaml
# terraform-plan.yml
on:
  pull_request:
    paths:
      - 'environments/**/*.tf'

jobs:
  plan:
    strategy:
      matrix:
        environment: [dev, staging, prod]  # 多环境支持
```

### 3.4 Import in CI/CD Context（重要概念）

在 [09-import](../09-import/) 中，我们学习了本地 import：

```bash
# 本地 import（命令式）
terraform import aws_instance.legacy i-1234567890abcdef0
```

**在 CI/CD 环境中，import 使用声明式方式**：

```hcl
# 在 main.tf 中添加 import block
import {
  to = aws_instance.legacy
  id = "i-1234567890abcdef0"
}

resource "aws_instance" "legacy" {
  ami           = "ami-0c3fd0f5d33134a76"
  instance_type = "t3.micro"
  # ... 其他配置
}
```

**CI/CD Import 工作流**：

```
1. 创建 PR，包含 import block + resource 配置
2. CI 运行 terraform plan → 显示 "1 to import"
3. 代码审查 → 确认 import 配置正确
4. 合并 PR
5. CI 运行 terraform apply → 执行 import
6. 下一个 PR 移除 import block（import 是一次性操作）
```

> **💡 为什么 CI/CD 使用声明式 Import？**
>
> - **可审查**：import 操作通过 PR 可见
> - **可重复**：配置在代码中，不依赖本地操作
> - **安全**：apply 需要审批，防止误操作

### 3.5 验证检查点（Phase 3）

如果实际设置了 CI/CD：
- [ ] OIDC CloudFormation 部署成功
- [ ] GitHub Secrets 配置完成
- [ ] 创建 PR 后能看到 plan 结果
- [ ] 理解 Import in CI/CD 的声明式方式

概念理解：
- [ ] 理解 Plan in PR 的价值
- [ ] 理解 OIDC vs Access Key 的区别
- [ ] 理解声明式 Import 的工作流

---

## Phase 4: Operations Drill + Prod（~2 小时）

### 4.1 部署 Staging 环境（可选）

```bash
cd ~/cloud-atlas/iac/terraform/14-capstone/code/environments/staging

# 更新 backend.tf 中的 Bucket 名称
BUCKET=$(aws cloudformation describe-stacks \
  --stack-name terraform-lab \
  --query 'Stacks[0].Outputs[?OutputKey==`TfStateBucketName`].OutputValue' \
  --output text)

sed -i "s/tfstate-terraform-lab-REPLACE_WITH_YOUR_BUCKET/$BUCKET/" backend.tf

# 初始化并部署
terraform init
terraform plan
terraform apply  # 需要 15-20 分钟
```

### 4.2 部署 Prod 环境（可选）

> **⚠️ 成本警告**：Prod 环境使用 Multi-AZ RDS 和多个 NAT Gateway，成本更高！

```bash
cd ~/cloud-atlas/iac/terraform/14-capstone/code/environments/prod

# 更新 backend.tf
sed -i "s/tfstate-terraform-lab-REPLACE_WITH_YOUR_BUCKET/$BUCKET/" backend.tf

terraform init
terraform plan  # 注意查看成本相关资源
terraform apply
```

### 4.3 Drift 检测与修复

**注入 Drift**：

1. 在 AWS Console 手动修改 Dev 环境的一个资源标签
2. 例如：EC2 Console → Auto Scaling Groups → 选择 ASG → Tags → 添加 `ModifiedManually=true`

**检测 Drift**：

```bash
cd ~/cloud-atlas/iac/terraform/14-capstone/code/environments/dev

# 检测 Drift
terraform plan -refresh-only
```

输出会显示：

```
Note: Objects have changed outside of Terraform

  # module.app.aws_autoscaling_group.main has changed
  ~ tags = [
      + {
          + key                 = "ModifiedManually"
          + propagate_at_launch = false
          + value               = "true"
        },
      ...
    ]
```

**修复 Drift**：

```bash
# 方式 1：恢复到 Terraform 配置（删除手动添加的标签）
terraform apply

# 方式 2：如果要保留手动修改，更新配置或使用 ignore_changes
```

### 4.4 State Lock 处理

使用 Terraform 1.10+ 原生 S3 锁定（`use_lockfile = true`），锁文件是 `.tflock`。

**查看锁文件**（如果有）：

```bash
BUCKET=$(aws cloudformation describe-stacks \
  --stack-name terraform-lab \
  --query 'Stacks[0].Outputs[?OutputKey==`TfStateBucketName`].OutputValue' \
  --output text)

aws s3 ls s3://$BUCKET/14-capstone/dev/ | grep tflock
```

**模拟锁定场景**：

1. 在一个终端运行 `terraform apply`（不要按回车）
2. 在另一个终端尝试 `terraform plan`
3. 会看到锁定错误

**解锁**（仅在确认无其他操作时）：

```bash
terraform force-unlock LOCK_ID
```

### 4.5 Provider 升级演练

```bash
# 1. 查看当前 Provider 版本
cat .terraform.lock.hcl | grep -A5 "provider"

# 2. 升级 Provider
terraform init -upgrade

# 3. 验证无破坏性变更
terraform plan

# 4. 查看新版本
cat .terraform.lock.hcl | grep -A5 "provider"
```

### 4.6 验证检查点（Phase 4）

- [ ] 能检测并修复 Drift
- [ ] 理解 State Lock 机制（`use_lockfile = true`）
- [ ] 成功升级 Provider 版本
- [ ] 了解 [Runbook](code/docs/runbook.md) 内容

---

## 交付物清单

完成项目后，你应该有以下交付物：

| 交付物 | 位置 | 说明 |
|--------|------|------|
| **Dev 环境** | AWS | VPC + ALB + EC2 + RDS（记得 destroy！） |
| **Staging 环境** | AWS（可选） | 同上，不同配置 |
| **Prod 环境** | AWS（可选） | Multi-AZ 配置 |
| **模块文档** | `modules/*/README.md` | terraform-docs 生成 |
| **CI/CD 工作流** | `.github/workflows/` | plan + apply（概念或实践） |
| **Runbook** | `docs/runbook.md` | 操作手册 |
| **Interview Story** | 你的记录 | 遇到的问题及解决方案 |

---

## 清理资源（重要！）

**立即清理所有创建的资源**：

```bash
# 按环境逆序清理（如果部署了多个环境）

# 1. Prod（如果部署了）
cd ~/cloud-atlas/iac/terraform/14-capstone/code/environments/prod
terraform destroy -auto-approve

# 2. Staging（如果部署了）
cd ~/cloud-atlas/iac/terraform/14-capstone/code/environments/staging
terraform destroy -auto-approve

# 3. Dev
cd ~/cloud-atlas/iac/terraform/14-capstone/code/environments/dev
terraform destroy -auto-approve
```

**验证清理**：

```bash
# 确认 state 为空
terraform state list  # 应为空

# 检查 AWS 资源
aws ec2 describe-vpcs --filters "Name=tag:Project,Values=capstone"
# 应返回空数组
```

> **Note**: S3 Bucket 中的 state 文件不需要手动清理，它会在删除 terraform-lab stack 时自动清理。

---

## 面试故事准备

### 项目概述模板

```
プロジェクト名: Terraform 三層 Web アーキテクチャ
期間: X 日
役割: インフラエンジニア（個人プロジェクト）

技術スタック:
- Terraform (v1.14+)
- AWS (VPC, ALB, EC2/ASG, RDS)
- GitHub Actions (CI/CD)
- S3 Remote Backend with native locking

成果:
- 4 つの再利用可能なモジュールを作成
- 3 環境（dev/staging/prod）を構築
- CI/CD パイプラインを構築（PR で自動 plan、手動承認で apply）
- Drift 検知/修復と State Lock 解除を実践
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

**Q: Import をチームで行う場合の注意点は？**

A: CI/CD 環境では import block を使った宣言的な方法を推奨。PR で可視化でき、承認フローを経由する。ローカルでの `terraform import` コマンドは避ける。

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
- [11 - CI/CD 集成](../11-cicd/) - OIDC 和 GitHub Actions 详细教程

---

## 系列导航

← [13 · 测试](../13-testing/) | [Home](../) | [15 · 変更管理 →](../15-jp-change-mgmt/)
