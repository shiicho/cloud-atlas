# CloudFormation Drift 自动修复 — ドリフト自動検知・修復パイプライン

> **要件 (Requirements):** 自动检测 CloudFormation 堆栈配置漂移，发现异常时通知运维或自动修复。  
> **サービス (Services):** EventBridge, Lambda, CloudFormation, SNS  
> **难度:** 中级  
> **所需时间:** ~1 小时  
> **Japan IT 场景:** 運用自動化 / 構成管理

## 背景与动机 (Why This Matters)

在生产环境中，手动修改资源（通过控制台或 CLI）会导致 CloudFormation 堆栈与实际资源状态不一致，这种现象称为 **Drift（配置漂移）**。

**问题:**
- 手动修改破坏了 IaC 的单一事实来源
- 下次 `UpdateStack` 可能覆盖手动修改或产生冲突
- 审计时无法解释"为什么实际配置与模板不同"
- 日本企业的 変更管理 流程要求配置一致性

**本方案解决:**
- 每日自动检测所有堆栈的 drift 状态
- 发现漂移时立即通知运维团队 (Slack/Email)
- 可选：自动触发修复（重新部署堆栈）

**适用场景:**
- 多人协作管理 AWS 资源的团队
- 有合规审计要求的环境 (FISC, ISMAP)
- 想要实现 GitOps 但还在过渡期的组织

## 架构设计 (Architecture)

```
┌──────────────────────┐
│   EventBridge Rule   │  (Scheduled: 毎日 09:00 JST)
│   (cron trigger)     │
└──────────┬───────────┘
           │
           ▼
┌──────────────────────┐
│   Lambda Function    │  detect-drift
│   ├─ List all stacks │
│   ├─ DetectStackDrift│
│   └─ Check results   │
└──────────┬───────────┘
           │
     ┌─────┴─────┐
     │ Drift?    │
     └─────┬─────┘
       Yes │
           ▼
┌──────────────────────┐     ┌─────────────────┐
│      SNS Topic       │────▶│    Ops Team     │
│  (drift-alert-topic) │     │  (Slack/Email)  │
└──────────┬───────────┘     └─────────────────┘
           │
           ▼ (Optional: auto-remediate)
┌──────────────────────┐
│   Lambda Function    │  remediate-drift
│   ├─ UpdateStack     │
│   └─ Log to CloudWatch│
└──────────────────────┘
```

### 设计决策 (Design Decisions)

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Drift 检测频率 | 每日 1 次 | 平衡及时性与 API 调用成本 |
| 通知渠道 | SNS → Slack/Email | 灵活，可扩展多种订阅 |
| 自动修复 | 默认关闭 | 生产环境需谨慎，先通知人工确认 |
| Lambda Runtime | Python 3.12 | boto3 内置，无需额外依赖 |

### 成本估算 (Cost Estimate)

| Service | Estimated Monthly Cost | Notes |
|---------|----------------------|-------|
| Lambda | ~$0.01 | 每天运行 1 次，执行时间 < 1 分钟 |
| EventBridge | Free | 免费额度内 |
| SNS | ~$0.01 | 每天 < 10 条通知 |
| **Total** | **< $0.05/月** | 几乎免费 |

## 前提条件 (Prerequisites)

- [ ] AWS Account with CloudFormation, Lambda, EventBridge, SNS permissions
- [ ] AWS CLI configured (`aws configure`)
- [ ] 推荐: 完成 [CloudFormation 基础课程](../../iac/cloudformation/)
- [ ] (可选) Slack Incoming Webhook URL

## 实现步骤 (Implementation)

> **Status: PLANNED**  
> 本 recipe 尚未实现。以下是预计步骤大纲。

### Step 1 — 创建 SNS Topic 和订阅

> **Note:** 以下示例中的 `<YOUR-ACCOUNT-ID>` 需要替换为你的 AWS 账户 ID。

```bash
# 创建 SNS Topic
aws sns create-topic --name drift-alert-topic

# 添加 Email 订阅 (替换 <YOUR-ACCOUNT-ID> 和邮箱地址)
aws sns subscribe \
  --topic-arn arn:aws:sns:ap-northeast-1:<YOUR-ACCOUNT-ID>:drift-alert-topic \
  --protocol email \
  --notification-endpoint your-email@example.com
```

### Step 2 — 创建 Lambda 函数 (detect-drift)

```python
# code/lambda/detect_drift.py
import boto3
import json
import os

cfn = boto3.client('cloudformation')
sns = boto3.client('sns')

def handler(event, context):
    # List all stacks
    stacks = cfn.list_stacks(StackStatusFilter=['CREATE_COMPLETE', 'UPDATE_COMPLETE'])

    drifted_stacks = []
    for stack in stacks['StackSummaries']:
        # Detect drift
        detection_id = cfn.detect_stack_drift(StackName=stack['StackName'])['StackDriftDetectionId']
        # ... check results

    if drifted_stacks:
        # Send alert
        sns.publish(
            TopicArn=os.environ['SNS_TOPIC_ARN'],
            Subject='CloudFormation Drift Detected',
            Message=json.dumps(drifted_stacks, indent=2)
        )

    return {'drifted_count': len(drifted_stacks)}
```

### Step 3 — 创建 EventBridge Rule (定时触发)

```bash
# 每天 09:00 JST (00:00 UTC) 触发
aws events put-rule \
  --name drift-detection-daily \
  --schedule-expression "cron(0 0 * * ? *)" \
  --state ENABLED
```

### Step 4 — 配置 Lambda 权限和触发器

```bash
# 替换 <YOUR-ACCOUNT-ID> 为你的 AWS 账户 ID

# 创建 Lambda 执行角色 (需要 CloudFormation, SNS 权限)
aws iam create-role \
  --role-name drift-detection-lambda-role \
  --assume-role-policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Principal": {"Service": "lambda.amazonaws.com"},
      "Action": "sts:AssumeRole"
    }]
  }'

# 附加策略（简化版，生产环境应使用最小权限）
aws iam attach-role-policy \
  --role-name drift-detection-lambda-role \
  --policy-arn arn:aws:iam::aws:policy/AWSCloudFormationReadOnlyAccess

aws iam attach-role-policy \
  --role-name drift-detection-lambda-role \
  --policy-arn arn:aws:iam::aws:policy/AmazonSNSFullAccess

aws iam attach-role-policy \
  --role-name drift-detection-lambda-role \
  --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole

# 创建 Lambda 函数
aws lambda create-function \
  --function-name detect-drift \
  --runtime python3.12 \
  --role arn:aws:iam::<YOUR-ACCOUNT-ID>:role/drift-detection-lambda-role \
  --handler detect_drift.handler \
  --zip-file fileb://code/lambda/detect_drift.zip \
  --environment Variables="{SNS_TOPIC_ARN=arn:aws:sns:ap-northeast-1:<YOUR-ACCOUNT-ID>:drift-alert-topic}" \
  --timeout 60

# 允许 EventBridge 调用 Lambda
aws lambda add-permission \
  --function-name detect-drift \
  --statement-id EventBridgeInvoke \
  --action lambda:InvokeFunction \
  --principal events.amazonaws.com \
  --source-arn arn:aws:events:ap-northeast-1:<YOUR-ACCOUNT-ID>:rule/drift-detection-daily

# 将 Lambda 设为 EventBridge Rule 目标
aws events put-targets \
  --rule drift-detection-daily \
  --targets '[{"Id": "1", "Arn": "arn:aws:lambda:ap-northeast-1:<YOUR-ACCOUNT-ID>:function:detect-drift"}]'
```

## 验证 (Verification)

> **Status: PLANNED**

### Test Scenario 1: 手动制造 Drift

1. 通过控制台修改某个 CFN 管理的资源（如修改 Security Group 规则）
2. 手动触发 Lambda 函数
3. 确认收到 SNS 通知

### Test Scenario 2: 无 Drift 情况

1. 确保所有堆栈配置一致
2. 触发 Lambda
3. 确认没有通知发送

## 清理 (Cleanup)

> **Note:** 按创建的**逆序**删除资源，避免依赖错误。替换 `<YOUR-ACCOUNT-ID>` 为你的 AWS 账户 ID。

```bash
# 1. 移除 EventBridge 目标（先解除关联）
aws events remove-targets --rule drift-detection-daily --ids 1

# 2. 删除 EventBridge Rule
aws events delete-rule --name drift-detection-daily

# 3. 删除 Lambda 函数
aws lambda delete-function --function-name detect-drift

# 4. 分离并删除 IAM 角色
aws iam detach-role-policy \
  --role-name drift-detection-lambda-role \
  --policy-arn arn:aws:iam::aws:policy/AWSCloudFormationReadOnlyAccess
aws iam detach-role-policy \
  --role-name drift-detection-lambda-role \
  --policy-arn arn:aws:iam::aws:policy/AmazonSNSFullAccess
aws iam detach-role-policy \
  --role-name drift-detection-lambda-role \
  --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
aws iam delete-role --role-name drift-detection-lambda-role

# 5. 删除 SNS Topic
aws sns delete-topic --topic-arn arn:aws:sns:ap-northeast-1:<YOUR-ACCOUNT-ID>:drift-alert-topic
```

## 扩展思考 (Extensions)

- **Slack 集成:** 将 SNS 连接到 AWS Chatbot 或自定义 Lambda 推送 Slack
- **自动修复:** 检测到 drift 后自动 `UpdateStack` (需谨慎)
- **白名单:** 某些堆栈允许 drift（开发环境）
- **详细报告:** 输出到 S3，保留历史记录用于审计

## 相关内容 (Related)

- **Course:** [CloudFormation Drift 检测与导入](../../iac/cloudformation/05-drift-import/)
- **Solution:** [Cost Anomaly Alert](../cost-anomaly-alert/)

---

*Part of [cloud-atlas Solutions Gallery](../README.md)*
