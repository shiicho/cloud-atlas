# 操作手册 (Runbook)

> **運用手順書** - Terraform 三層 Web 架构操作手册

本文档记录 Capstone 项目的日常操作流程、故障处理步骤和紧急恢复流程。

---

## 目录

1. [日常操作](#日常操作)
2. [Drift 检测与修复](#drift-检测与修复)
3. [State Lock 处理](#state-lock-处理)
4. [紧急回滚](#紧急回滚)
5. [资源清理](#资源清理)
6. [联系人](#联系人)

---

## 日常操作

### 1.1 查看基础设施状态

```bash
cd environments/dev

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

# 强制不询问确认（慎用！）
terraform apply -auto-approve
```

### 1.4 刷新状态

```bash
# 只刷新状态，不做变更
terraform apply -refresh-only

# 查看刷新后的变化
terraform plan -refresh-only
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

定期运行 Drift 检测：

```bash
#!/bin/bash
# scripts/detect-drift.sh

cd environments/dev
terraform init -input=false

DRIFT=$(terraform plan -detailed-exitcode 2>&1)
EXIT_CODE=$?

if [ $EXIT_CODE -eq 2 ]; then
    echo "DRIFT DETECTED!"
    echo "$DRIFT"
    # 发送告警（Slack、Email 等）
elif [ $EXIT_CODE -eq 0 ]; then
    echo "No drift detected"
else
    echo "Error running plan"
    exit 1
fi
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
# 查看 S3 中的锁文件
aws s3 ls s3://tfstate-capstone-YOUR_ACCOUNT_ID/dev/ | grep tflock

# 输出示例（有锁时）：
# 2025-01-15 10:00:00        256 terraform.tfstate.tflock
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
# 列出 State 版本
aws s3api list-object-versions \
  --bucket tfstate-capstone-YOUR_ACCOUNT_ID \
  --prefix dev/terraform.tfstate

# 下载旧版本
aws s3api get-object \
  --bucket tfstate-capstone-YOUR_ACCOUNT_ID \
  --key dev/terraform.tfstate \
  --version-id VERSION_ID \
  terraform.tfstate.backup

# 恢复旧版本（危险！先备份当前版本）
aws s3 cp terraform.tfstate.backup \
  s3://tfstate-capstone-YOUR_ACCOUNT_ID/dev/terraform.tfstate
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
cd environments/dev

# 预览销毁
terraform plan -destroy

# 执行销毁
terraform destroy

# 强制销毁（不询问）
terraform destroy -auto-approve
```

### 5.2 销毁顺序

如果 `terraform destroy` 失败，按以下顺序手动清理：

1. **RDS** - 先删除数据库（最耗时）
2. **EC2/ASG** - 删除 Auto Scaling Group
3. **ALB** - 删除负载均衡器
4. **NAT Gateway** - 删除 NAT（释放 EIP）
5. **VPC** - 最后删除 VPC

### 5.3 清理远程后端

项目完全结束后，清理远程后端：

```bash
# 删除 S3 Bucket
aws s3 rb s3://tfstate-capstone-YOUR_ACCOUNT_ID --force
```

### 5.4 检查残留资源

使用 AWS Cost Explorer 或 Resource Groups 确认无残留：

```bash
# 按标签查找资源
aws resourcegroupstaggingapi get-resources \
  --tag-filters Key=Project,Values=capstone
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

### 6.2 日志收集

```bash
# Terraform 详细日志
export TF_LOG=DEBUG
terraform plan 2>&1 | tee terraform.log
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

---

## 附录

### A. 环境信息

| 环境 | State Bucket | 用途 |
|------|--------------|------|
| dev | tfstate-capstone-xxx/dev/ | 开发测试 |
| staging | tfstate-capstone-xxx/staging/ | 预发布 |
| prod | tfstate-capstone-xxx/prod/ | 生产 |

### B. 相关文档

- [Terraform 官方文档](https://www.terraform.io/docs)
- [AWS Provider 文档](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [项目 README](../README.md)

### C. 日语术语对照

| 中文 | 日语 | 英语 |
|------|------|------|
| 操作手册 | 運用手順書 | Runbook |
| 故障处理 | 障害対応 | Incident Response |
| 变更管理 | 変更管理 | Change Management |
| 紧急对应 | 緊急対応 | Emergency Response |
| 回滚 | ロールバック | Rollback |
