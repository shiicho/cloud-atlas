# AWS 费用异常检测 + Slack 告警 — コスト異常検知パイプライン

> **要件 (Requirements):** 使用 ML 自动检测 AWS 账单异常，第一时间推送告警到 Slack 或 Email。  
> **サービス (Services):** AWS Cost Anomaly Detection, SNS, Lambda  
> **难度:** 初级  
> **所需时间:** ~30 分钟  
> **Japan IT 场景:** コスト管理 / FinOps

## 背景与动机 (Why This Matters)

AWS 账单意外暴涨是每个团队的噩梦。常见原因：
- 开发环境忘记关机
- 数据传输费用超预期
- 恶意挖矿（账号泄露）
- 配置错误导致资源超配

**传统方案的问题:**
- AWS Budgets 需要预设阈值，无法应对"正常增长 vs 异常增长"
- 月底才发现已经太晚
- 手动检查 Cost Explorer 效率低

**AWS Cost Anomaly Detection 的优势:**
- **ML-based:** 自动学习历史消费模式，无需手动设阈值
- **实时检测:** 发现异常后立即通知
- **归因分析:** 告诉你是哪个服务/账户导致的异常

**适用场景:**
- 多账户组织 (AWS Organizations)
- 开发/测试环境成本失控
- FinOps 初期建设

## 架构设计 (Architecture)

```
┌─────────────────────────┐
│ AWS Cost Anomaly        │  (ML 模型持续学习)
│ Detection               │
│ ├─ Monitor: AWS Services│
│ └─ Threshold: $10       │
└───────────┬─────────────┘
            │ 检测到异常
            ▼
┌─────────────────────────┐     ┌─────────────────┐
│       SNS Topic         │────▶│     Lambda      │
│ (cost-anomaly-alerts)   │     │  (formatter)    │
└─────────────────────────┘     └────────┬────────┘
                                         │
                                         ▼
                                ┌─────────────────┐
                                │     Slack       │
                                │   Webhook       │
                                └─────────────────┘
```

### 设计决策 (Design Decisions)

| Decision | Choice | Rationale |
|----------|--------|-----------|
| 异常阈值 | $10 | 小团队适用，大企业可调高 |
| Monitor 范围 | AWS Services | 按服务维度监控，最常用 |
| 通知频率 | 实时 | 发现即通知，不等待 |
| Slack 格式 | Block Kit | 可读性好，含链接到 Cost Explorer |

### 成本估算 (Cost Estimate)

| Service | Estimated Monthly Cost | Notes |
|---------|----------------------|-------|
| Cost Anomaly Detection | Free | 免费功能 |
| SNS | ~$0.01 | 每月 < 100 条通知 |
| Lambda | ~$0.01 | 仅在异常时触发 |
| **Total** | **< $0.05/月** | 几乎免费 |

## 前提条件 (Prerequisites)

- [ ] AWS Account (需要 Cost Explorer 已启用)
- [ ] AWS CLI configured (`aws configure`)
- [ ] (可选) Slack Workspace 和 Incoming Webhook URL
- [ ] 账户需有 **至少 2 周** 的历史账单数据（ML 需要学习）

## 实现步骤 (Implementation)

> **Status: PLANNED**
> 本 recipe 尚未实现。以下是预计步骤大纲。

> **Note:** 以下示例中的 `<YOUR-ACCOUNT-ID>` 需要替换为你的 AWS 账户 ID。

### Step 1 — 创建 Cost Anomaly Monitor

**通过控制台 (推荐):**

1. 打开 **AWS Cost Management** → **Cost Anomaly Detection**
2. 点击 **Create monitor**
3. 选择 **AWS services** 类型
4. 设置阈值: **$10** (或你的预期值)
5. 创建 SNS Topic 用于告警

**通过 CLI:**

```bash
# 创建 Anomaly Monitor
aws ce create-anomaly-monitor \
  --anomaly-monitor '{
    "MonitorName": "cost-anomaly-monitor",
    "MonitorType": "DIMENSIONAL",
    "MonitorDimension": "SERVICE"
  }'
```

### Step 2 — 创建 SNS Topic 和 Subscription

```bash
# 创建 Topic
aws sns create-topic --name cost-anomaly-alerts

# 添加 Email 订阅 (替换 <YOUR-ACCOUNT-ID>)
aws sns subscribe \
  --topic-arn arn:aws:sns:us-east-1:<YOUR-ACCOUNT-ID>:cost-anomaly-alerts \
  --protocol email \
  --notification-endpoint your-email@example.com
```

### Step 3 — 创建 Anomaly Subscription (连接 Monitor 和 SNS)

> **Note:** `Threshold` 参数已废弃，需使用 `ThresholdExpression`。

```bash
# 替换 <YOUR-ACCOUNT-ID> 和 <MONITOR-ID> (从 Step 1 输出获取)
aws ce create-anomaly-subscription \
  --anomaly-subscription '{
    "SubscriptionName": "cost-anomaly-subscription",
    "ThresholdExpression": {
      "Dimensions": {
        "Key": "ANOMALY_TOTAL_IMPACT_ABSOLUTE",
        "MatchOptions": ["GREATER_THAN_OR_EQUAL"],
        "Values": ["10"]
      }
    },
    "Frequency": "IMMEDIATE",
    "MonitorArnList": ["arn:aws:ce::<YOUR-ACCOUNT-ID>:anomalymonitor/<MONITOR-ID>"],
    "Subscribers": [
      {
        "Type": "SNS",
        "Address": "arn:aws:sns:us-east-1:<YOUR-ACCOUNT-ID>:cost-anomaly-alerts"
      }
    ]
  }'
```

### Step 4 — (可选) Lambda 格式化推送 Slack

```python
# code/lambda/slack_formatter.py
import json
import urllib.request
import os

SLACK_WEBHOOK_URL = os.environ['SLACK_WEBHOOK_URL']

def handler(event, context):
    message = json.loads(event['Records'][0]['Sns']['Message'])

    slack_message = {
        "blocks": [
            {
                "type": "header",
                "text": {"type": "plain_text", "text": "AWS Cost Anomaly Detected"}
            },
            {
                "type": "section",
                "text": {
                    "type": "mrkdwn",
                    "text": f"*Service:* {message.get('service', 'Unknown')}\n*Impact:* ${message.get('impact', 'N/A')}"
                }
            }
        ]
    }

    req = urllib.request.Request(
        SLACK_WEBHOOK_URL,
        data=json.dumps(slack_message).encode('utf-8'),
        headers={'Content-Type': 'application/json'}
    )
    urllib.request.urlopen(req)

    return {'statusCode': 200}
```

## 验证 (Verification)

> **Status: PLANNED**

### Test Scenario 1: 模拟异常

Cost Anomaly Detection 不支持手动触发测试。验证方法：
1. 创建配置后等待 2-3 天
2. 启动一个大型 EC2 实例几小时（会触发异常）
3. 确认收到通知

### Test Scenario 2: 测试 SNS → Slack 链路

```bash
# 手动发布测试消息到 SNS (替换 <YOUR-ACCOUNT-ID>)
aws sns publish \
  --topic-arn arn:aws:sns:us-east-1:<YOUR-ACCOUNT-ID>:cost-anomaly-alerts \
  --message '{"service": "EC2", "impact": "50.00"}'
```

## 清理 (Cleanup)

```bash
# 替换 <YOUR-ACCOUNT-ID>, <SUBSCRIPTION-ID>, <MONITOR-ID> 为实际值

# 删除 Anomaly Subscription
aws ce delete-anomaly-subscription \
  --subscription-arn arn:aws:ce::<YOUR-ACCOUNT-ID>:anomalysubscription/<SUBSCRIPTION-ID>

# 删除 Anomaly Monitor
aws ce delete-anomaly-monitor \
  --monitor-arn arn:aws:ce::<YOUR-ACCOUNT-ID>:anomalymonitor/<MONITOR-ID>

# 删除 SNS Topic
aws sns delete-topic \
  --topic-arn arn:aws:sns:us-east-1:<YOUR-ACCOUNT-ID>:cost-anomaly-alerts

# 删除 Lambda (如果创建了)
aws lambda delete-function --function-name cost-anomaly-slack-formatter
```

## 扩展思考 (Extensions)

- **多账户:** 在 Management Account 创建跨账户 Monitor
- **按团队分组:** 使用 Cost Categories 按团队监控
- **PagerDuty 集成:** 严重异常升级到 on-call
- **自动响应:** 检测到异常后自动 Stop 开发环境 EC2

## トラブルシューティング (Troubleshooting)

| Symptom | Cause | Solution |
|---------|-------|----------|
| Monitor 创建后没有检测到异常 | 历史数据不足 | 等待 2+ 周让 ML 学习 |
| SNS 通知未收到 | Email 未确认订阅 | 检查邮箱确认链接 |
| Slack 消息格式错误 | Lambda 代码问题 | 检查 CloudWatch Logs |

## 相关内容 (Related)

- **Solution:** [Drift Auto-Remediation](../drift-remediation/)
- **Glossary:** [FinOps 基础概念](../../glossary/finops/)

---

*Part of [cloud-atlas Solutions Gallery](../README.md)*
