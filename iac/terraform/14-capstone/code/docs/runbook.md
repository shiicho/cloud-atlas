# 操作手册 (Runbook)

> **運用手順書** - Terraform 三層 Web 架构操作手册

本文档记录 Capstone 项目的日常操作流程、故障处理步骤和紧急恢复流程。

---

## 目录

1. [环境概述](#环境概述)
2. [日常操作](#日常操作)
3. [Drift 检测与修复](#drift-检测与修复)
4. [State Lock 处理](#state-lock-处理)
5. [紧急回滚](#紧急回滚)
6. [资源清理](#资源清理)
7. [故障排除](#故障排除)
8. [联系人](#联系人)

---

## 环境概述

### 环境配置差异

| 设置 | Dev | Staging | Prod |
|------|-----|---------|------|
| **VPC CIDR** | 10.0.0.0/16 | 10.1.0.0/16 | 10.2.0.0/16 |
| **NAT Gateway** | Single | Single | Per-AZ |
| **RDS Multi-AZ** | No | No | Yes |
| **Deletion Protection** | No | No | Yes |
| **ASG Size** | 1-3 | 2-4 | 2-6 |
| **Backup Retention** | 1 day | 7 days | 30 days |
| **Flow Logs** | No | Yes | Yes |

### State 文件位置

所有环境使用同一个 S3 Bucket（课程提供），不同的 state key：

```
s3://tfstate-terraform-lab-{AccountId}/
├── 14-capstone/dev/terraform.tfstate
├── 14-capstone/staging/terraform.tfstate
└── 14-capstone/prod/terraform.tfstate
```

获取 Bucket 名称：

```bash
aws cloudformation describe-stacks \
  --stack-name terraform-lab \
  --query 'Stacks[0].Outputs[?OutputKey==`TfStateBucketName`].OutputValue' \
  --output text
```

---

## 日常操作

### 1.1 查看基础设施状态

```bash
# 选择环境
ENV=dev  # 或 staging, prod
cd environments/$ENV

# 查看当前管理的资源
terraform state list

# 查看特定资源详情
terraform state show module.vpc.aws_vpc.main

# 查看所有输出
terraform output
```

### 1.2 计划变更

```bash
# 预览变更（Dry Run）
terraform plan

# 保存 Plan 到文件
terraform plan -out=tfplan

# 查看 Plan 详情
terraform show tfplan
```

### 1.3 应用变更

```bash
# 应用已保存的 Plan
terraform apply tfplan

# 或直接应用（会再次显示 Plan）
terraform apply

# 强制不询问确认（慎用！仅限 dev 环境）
terraform apply -auto-approve
```

### 1.4 刷新状态

```bash
# 只刷新状态，不做变更
terraform apply -refresh-only

# 查看刷新后的变化
terraform plan -refresh-only
```

### 1.5 跨环境部署

```bash
# 部署顺序：dev → staging → prod
for env in dev staging prod; do
  echo "=== Deploying $env ==="
  cd environments/$env
  terraform init
  terraform plan
  terraform apply
  cd ../..
done
```

---

## Drift 检测与修复

### 2.1 什么是 Drift

Drift（漂移）是指 Terraform 配置与实际 AWS 资源状态不一致。

常见原因：
- 手动在 Console 修改资源
- 其他工具修改资源
- AWS 自动修改（如 Auto Scaling）

### 2.2 检测 Drift

```bash
# 方法 1: terraform plan
terraform plan

# 如果输出显示 "~ update in-place" 或 "- destroy"
# 说明存在 Drift

# 方法 2: 只刷新状态
terraform plan -refresh-only
```

### 2.3 修复 Drift

**方式 A：恢复到 Terraform 配置**

```bash
# 应用配置，覆盖手动修改
terraform apply
```

**方式 B：接受手动修改**

1. 更新 Terraform 配置以匹配实际状态
2. 或使用 `ignore_changes`:

```hcl
resource "aws_instance" "example" {
  # ...

  lifecycle {
    ignore_changes = [tags["ModifiedManually"]]
  }
}
```

**方式 C：导入手动创建的资源**

```bash
# 如果资源是手动创建的
terraform import aws_instance.new i-1234567890abcdef0
```

### 2.4 Drift 检测自动化

定期运行 Drift 检测脚本：

```bash
#!/bin/bash
# scripts/detect-drift.sh

for ENV in dev staging prod; do
  echo "=== Checking $ENV ==="
  cd environments/$ENV
  terraform init -input=false

  DRIFT=$(terraform plan -detailed-exitcode 2>&1)
  EXIT_CODE=$?

  if [ $EXIT_CODE -eq 2 ]; then
    echo "⚠️  DRIFT DETECTED in $ENV!"
    echo "$DRIFT"
    # 发送告警（Slack、Email 等）
  elif [ $EXIT_CODE -eq 0 ]; then
    echo "✅ No drift in $ENV"
  else
    echo "❌ Error checking $ENV"
  fi

  cd ../..
done
```

---

## State Lock 处理

### 3.1 什么是 State Lock

Terraform 使用 S3 原生锁定（`.tflock` 文件）防止并发 apply。

Lock 卡住的常见原因：
- apply 过程中网络中断
- 进程被强制终止
- CI/CD 任务超时

### 3.2 查看当前 Lock

```bash
# 获取 Bucket 名称
BUCKET=$(aws cloudformation describe-stacks \
  --stack-name terraform-lab \
  --query 'Stacks[0].Outputs[?OutputKey==`TfStateBucketName`].OutputValue' \
  --output text)

# 检查各环境的锁文件
for ENV in dev staging prod; do
  echo "=== $ENV ==="
  aws s3 ls s3://$BUCKET/14-capstone/$ENV/ | grep tflock
done
```

### 3.3 解锁流程

**Step 1: 确认没有其他操作进行中**

```bash
# 检查是否有其他人在操作
# 联系团队成员确认
```

**Step 2: 获取 Lock ID**

```bash
# 从 terraform 错误信息获取
# Error: Error acquiring the state lock
# Lock Info:
#   ID:        xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
```

**Step 3: 强制解锁**

```bash
terraform force-unlock LOCK_ID

# 例如：
terraform force-unlock 12345678-1234-1234-1234-123456789012
```

**Step 4: 验证**

```bash
terraform plan  # 应该能正常运行
```

### 3.4 预防措施

- 设置合理的 CI/CD 超时时间
- 使用稳定的网络环境
- 不要强制终止 terraform 进程

---

## 紧急回滚

### 4.1 使用 State 历史回滚

S3 版本控制保留了 State 历史：

```bash
# 获取 Bucket 名称
BUCKET=$(aws cloudformation describe-stacks \
  --stack-name terraform-lab \
  --query 'Stacks[0].Outputs[?OutputKey==`TfStateBucketName`].OutputValue' \
  --output text)

# 列出 State 版本
aws s3api list-object-versions \
  --bucket $BUCKET \
  --prefix 14-capstone/dev/terraform.tfstate

# 下载旧版本
aws s3api get-object \
  --bucket $BUCKET \
  --key 14-capstone/dev/terraform.tfstate \
  --version-id VERSION_ID \
  terraform.tfstate.backup

# 恢复旧版本（危险！先备份当前版本）
aws s3 cp terraform.tfstate.backup \
  s3://$BUCKET/14-capstone/dev/terraform.tfstate
```

### 4.2 使用 Git 回滚配置

```bash
# 回滚到之前的 commit
git checkout <commit-hash> -- environments/dev/

# 应用旧配置
terraform plan
terraform apply
```

### 4.3 紧急资源替换

```bash
# 强制替换特定资源
terraform apply -replace="module.app.aws_autoscaling_group.main"
```

---

## 资源清理

### 5.1 销毁所有资源

```bash
# 按环境逆序销毁（先 prod，后 dev）
for ENV in prod staging dev; do
  echo "=== Destroying $ENV ==="
  cd environments/$ENV

  # 预览销毁
  terraform plan -destroy

  # 执行销毁
  terraform destroy

  # 强制销毁（不询问）
  # terraform destroy -auto-approve

  cd ../..
done
```

### 5.2 Prod 环境清理（需要禁用删除保护）

Prod 环境启用了删除保护，需要先禁用：

```bash
# 1. 获取资源 ID
cd environments/prod
RDS_ID=$(terraform output -raw rds_endpoint | cut -d: -f1)
ALB_ARN=$(terraform output -raw alb_arn)

# 2. 禁用 RDS 删除保护
aws rds modify-db-instance \
  --db-instance-identifier $RDS_ID \
  --no-deletion-protection

# 3. 禁用 ALB 删除保护
aws elbv2 modify-load-balancer-attributes \
  --load-balancer-arn $ALB_ARN \
  --attributes Key=deletion_protection.enabled,Value=false

# 4. 等待修改完成
sleep 60

# 5. 现在可以 destroy
terraform destroy
```

### 5.3 销毁顺序

如果 `terraform destroy` 失败，按以下顺序手动清理：

1. **RDS** - 先删除数据库（最耗时）
2. **EC2/ASG** - 删除 Auto Scaling Group
3. **ALB** - 删除负载均衡器
4. **NAT Gateway** - 删除 NAT（释放 EIP）
5. **VPC** - 最后删除 VPC

### 5.4 检查残留资源

使用 AWS Resource Groups 确认无残留：

```bash
# 按标签查找资源
aws resourcegroupstaggingapi get-resources \
  --tag-filters Key=Project,Values=capstone

# 应返回空列表
```

---

## 故障排除

### 6.1 常见错误

**Error: Error acquiring the state lock**

```
解决：参考 "State Lock 处理" 章节
```

**Error: Error creating VPC: VpcLimitExceeded**

```bash
# 检查 VPC 配额
aws ec2 describe-vpcs --query 'Vpcs[*].VpcId'

# 删除未使用的 VPC
aws ec2 delete-vpc --vpc-id vpc-xxxxx
```

**Error: Error creating DB Instance: DBSubnetGroupDoesNotCoverEnoughAZs**

```
解决：确保 database_subnets 至少跨 2 个可用区
```

**Error: Error creating ALB: AccessDenied**

```bash
# 检查 IAM 权限
aws sts get-caller-identity

# 确认有 elasticloadbalancing:* 权限
```

**Error: DeletionProtected**

```bash
# 禁用删除保护后重试
# 参考 "Prod 环境清理" 章节
```

### 6.2 日志收集

```bash
# Terraform 详细日志
export TF_LOG=DEBUG
terraform plan 2>&1 | tee terraform.log

# AWS CLI 调试
aws --debug ec2 describe-instances 2>&1 | tee aws.log
```

---

## 联系人

| 角色 | 联系方式 | 职责 |
|------|----------|------|
| 项目负责人 | your-email@example.com | 项目决策 |
| 基础设施负责人 | infra-team@example.com | 技术问题 |
| AWS Support | AWS Console | 平台问题 |

### 升级流程

```
Level 1: 项目成员自行处理
    ↓ (30分钟未解决)
Level 2: 基础设施负责人
    ↓ (1小时未解决)
Level 3: AWS Support
```

---

## 变更记录

| 日期 | 版本 | 变更内容 | 作者 |
|------|------|----------|------|
| 2025-XX-XX | 1.0 | 初始版本 | Your Name |
| 2025-XX-XX | 1.1 | 添加多环境支持 | Your Name |

---

## 附录

### A. 环境信息

| 环境 | State Key | 用途 |
|------|-----------|------|
| dev | 14-capstone/dev/ | 开发测试 |
| staging | 14-capstone/staging/ | 预发布验证 |
| prod | 14-capstone/prod/ | 生产环境 |

### B. 相关文档

- [Terraform 官方文档](https://www.terraform.io/docs)
- [AWS Provider 文档](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [项目 README](../README.md)
- [11 - CI/CD 集成](../../11-cicd/) - OIDC 和 GitHub Actions

### C. 日语术语对照

| 中文 | 日语 | 英语 |
|------|------|------|
| 操作手册 | 運用手順書 | Runbook |
| 故障处理 | 障害対応 | Incident Response |
| 变更管理 | 変更管理 | Change Management |
| 紧急对应 | 緊急対応 | Emergency Response |
| 回滚 | ロールバック | Rollback |
| 删除保护 | 削除保護 | Deletion Protection |
| 多可用区 | マルチAZ | Multi-AZ |

### D. 常用命令速查

```bash
# 环境切换
cd environments/{dev|staging|prod}

# 初始化
terraform init

# 计划变更
terraform plan

# 应用变更
terraform apply

# 查看状态
terraform state list
terraform output

# 检测 Drift
terraform plan -refresh-only

# 销毁资源
terraform destroy

# 强制解锁
terraform force-unlock LOCK_ID
```
