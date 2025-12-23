# 日志归档 + Athena 查询 — ログ集約・検索基盤

> **要件 (Requirements):** 将 CloudWatch Logs 归档到 S3，支持 SQL 查询，满足监管审计要求。
> **サービス (Services):** CloudWatch Logs, Amazon Data Firehose, S3, Athena, Glue
> **难度:** 中级
> **所需时间:** ~1.5 小时
> **Japan IT 场景:** 監査対応 / ログ保管義務

> **Note:** "Kinesis Data Firehose" 于 2024 年 2 月更名为 "Amazon Data Firehose"，CLI 命令仍为 `aws firehose`。

## 背景与动机 (Why This Matters)

日本企业的合规要求（FISC, ISMAP, 内部監査）通常要求：
- 日志保留 **1-7 年**
- 可追溯、可查询
- 不可篡改

**CloudWatch Logs 的局限:**
- 存储费用高（$0.03/GB/月 vs S3 $0.023/GB/月）
- 保留期限制（最长 10 年，但成本高）
- 查询能力有限（Logs Insights 不支持复杂 JOIN）

**本方案解决:**
- 实时将日志流式传输到 S3（Parquet 格式，压缩率高）
- 使用 Athena 进行 SQL 查询（按扫描量计费，空闲时零成本）
- 满足长期保留 + 可查询的审计要求

**适用场景:**
- 金融/政府系统的监管审计 (FISC, ISMAP)
- 安全事件调查（需要跨月份日志关联）
- 成本优化（从 CloudWatch Logs 迁移）

## 架构设计 (Architecture)

```
┌─────────────────┐
│  CloudWatch     │
│     Logs        │
│ (Application)   │
└────────┬────────┘
         │ Subscription Filter
         ▼
┌─────────────────┐
│  Amazon Data    │
│    Firehose     │
│ ├─ Buffer: 5min │
│ └─ Format: Parquet
└────────┬────────┘
         │
         ▼
┌─────────────────┐     ┌─────────────────┐
│       S3        │◀────│   Glue Crawler  │
│ (logs-archive)  │     │ (Schema Update) │
│ ├─ year=2025/   │     └─────────────────┘
│ ├─ month=12/    │
│ └─ day=23/      │            │
└────────┬────────┘            │
         │                     │
         ▼                     ▼
┌─────────────────┐     ┌─────────────────┐
│     Athena      │────▶│  Glue Catalog   │
│   (SQL Query)   │     │   (Schema)      │
└─────────────────┘     └─────────────────┘
```

### 设计决策 (Design Decisions)

| Decision | Choice | Rationale |
|----------|--------|-----------|
| 传输方式 | Amazon Data Firehose | 零代码，自动 buffering 和格式转换 |
| 存储格式 | Parquet | 列式存储，压缩率高，Athena 查询快 |
| 分区策略 | year/month/day | 按时间查询最常见，减少扫描量 |
| Schema 管理 | Glue Crawler | 自动推断 schema，无需手动维护 |

### 成本估算 (Cost Estimate)

| Service | Estimated Monthly Cost | Notes |
|---------|----------------------|-------|
| Amazon Data Firehose | ~$5 | 假设 10GB/月日志量 |
| S3 Storage | ~$0.50 | 10GB × $0.023 + Glacier 更便宜 |
| Athena Query | ~$1 | 按扫描量计费，Parquet 减少扫描 |
| Glue Crawler | ~$0.50 | 每日运行一次 |
| **Total** | **~$7/月** | 远低于 CloudWatch Logs 保留 |

## 前提条件 (Prerequisites)

- [ ] AWS Account with CloudWatch, Firehose, S3, Athena, Glue permissions
- [ ] AWS CLI configured (`aws configure`)
- [ ] 已有 CloudWatch Log Group（如 `/aws/lambda/my-function`）
- [ ] 推荐: 完成 [AWS SSM 系列](../../aws/ssm/)

## 实现步骤 (Implementation)

> **Status: PLANNED**  
> 本 recipe 尚未实现。以下是预计步骤大纲。

### Step 1 — 创建 S3 Bucket (日志归档桶)

> **Note:** 以下示例中的 `<YOUR-ACCOUNT-ID>` 需要替换为你的 AWS 账户 ID。

```bash
# 创建 bucket (替换 <YOUR-ACCOUNT-ID>)
aws s3 mb s3://my-logs-archive-<YOUR-ACCOUNT-ID> --region ap-northeast-1

# 设置生命周期策略（90 天后转 Glacier）
aws s3api put-bucket-lifecycle-configuration \
  --bucket my-logs-archive-<YOUR-ACCOUNT-ID> \
  --lifecycle-configuration '{
    "Rules": [
      {
        "ID": "ArchiveToGlacier",
        "Status": "Enabled",
        "Filter": {"Prefix": ""},
        "Transitions": [
          {"Days": 90, "StorageClass": "GLACIER"}
        ]
      }
    ]
  }'
```

### Step 2 — 创建 Glue Database (Schema 存储)

> **Important:** Glue Database 必须先于 Firehose 创建，因为 Firehose 的 schema 配置会引用它。

```bash
# 创建 Glue Database
aws glue create-database \
  --database-input '{"Name": "logs_db"}'
```

### Step 3 — 创建 Amazon Data Firehose Delivery Stream

```bash
# 创建 Firehose (简化版，完整配置见 code/ 目录)
# 替换 <YOUR-ACCOUNT-ID> 为你的 AWS 账户 ID
aws firehose create-delivery-stream \
  --delivery-stream-name logs-to-s3 \
  --delivery-stream-type DirectPut \
  --extended-s3-destination-configuration '{
    "BucketARN": "arn:aws:s3:::my-logs-archive-<YOUR-ACCOUNT-ID>",
    "Prefix": "logs/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/",
    "ErrorOutputPrefix": "errors/",
    "BufferingHints": {"SizeInMBs": 128, "IntervalInSeconds": 300},
    "CompressionFormat": "UNCOMPRESSED",
    "DataFormatConversionConfiguration": {
      "Enabled": true,
      "InputFormatConfiguration": {"Deserializer": {"OpenXJsonSerDe": {}}},
      "OutputFormatConfiguration": {"Serializer": {"ParquetSerDe": {}}},
      "SchemaConfiguration": {
        "DatabaseName": "logs_db",
        "TableName": "application_logs",
        "Region": "ap-northeast-1"
      }
    }
  }'
```

### Step 4 — 创建 CloudWatch Logs Subscription Filter

```bash
# 将 CloudWatch Logs 订阅到 Firehose (替换 <YOUR-ACCOUNT-ID>)
aws logs put-subscription-filter \
  --log-group-name /aws/lambda/my-function \
  --filter-name logs-to-firehose \
  --filter-pattern "" \
  --destination-arn arn:aws:firehose:ap-northeast-1:<YOUR-ACCOUNT-ID>:deliverystream/logs-to-s3
```

### Step 5 — 创建并运行 Glue Crawler

> **Note:** Crawler 在 S3 中有数据后运行效果更好。可以先写入测试数据。

```bash
# 创建 Crawler (替换 <YOUR-ACCOUNT-ID>)
aws glue create-crawler \
  --name logs-crawler \
  --role arn:aws:iam::<YOUR-ACCOUNT-ID>:role/GlueCrawlerRole \
  --database-name logs_db \
  --targets '{
    "S3Targets": [
      {"Path": "s3://my-logs-archive-<YOUR-ACCOUNT-ID>/logs/"}
    ]
  }'

# 运行 Crawler
aws glue start-crawler --name logs-crawler
```

### Step 6 — 使用 Athena 查询

```sql
-- 查询最近 7 天的错误日志
SELECT
    timestamp,
    message,
    request_id
FROM logs_db.application_logs
WHERE year = '2025'
  AND month = '12'
  AND day BETWEEN '17' AND '23'
  AND message LIKE '%ERROR%'
ORDER BY timestamp DESC
LIMIT 100;
```

## 验证 (Verification)

> **Status: PLANNED**

### Test Scenario 1: 端到端数据流

1. 向 CloudWatch Log Group 写入测试日志
2. 等待 5 分钟（Firehose buffer interval）
3. 检查 S3 是否有 Parquet 文件
4. 在 Athena 中查询数据

```bash
# 写入测试日志
aws logs put-log-events \
  --log-group-name /aws/lambda/my-function \
  --log-stream-name test-stream \
  --log-events timestamp=$(date +%s000),message="Test log message"
```

### Test Scenario 2: 分区验证

```sql
-- 确认分区正确
SHOW PARTITIONS logs_db.application_logs;
```

## 清理 (Cleanup)

> **Note:** 按创建的**逆序**删除资源，避免依赖错误。

```bash
# 替换 <YOUR-ACCOUNT-ID> 为你的 AWS 账户 ID

# 1. 删除 Subscription Filter（先停止数据流入）
aws logs delete-subscription-filter \
  --log-group-name /aws/lambda/my-function \
  --filter-name logs-to-firehose

# 2. 删除 Firehose
aws firehose delete-delivery-stream --delivery-stream-name logs-to-s3

# 3. 删除 Glue Crawler
aws glue delete-crawler --name logs-crawler

# 4. 删除 Glue Database
aws glue delete-database --name logs_db

# 5. 清空并删除 S3 Bucket
aws s3 rm s3://my-logs-archive-<YOUR-ACCOUNT-ID> --recursive
aws s3 rb s3://my-logs-archive-<YOUR-ACCOUNT-ID>
```

## 扩展思考 (Extensions)

- **多 Log Group:** 使用 CloudFormation StackSet 批量部署
- **跨账户:** 将日志归档到中央日志账户
- **告警集成:** Athena 查询结果触发 SNS 告警
- **可视化:** 连接 QuickSight 创建日志仪表盘
- **合规增强:** 启用 S3 Object Lock 防止删除

## トラブルシューティング (Troubleshooting)

| Symptom | Cause | Solution |
|---------|-------|----------|
| S3 中没有数据 | Subscription Filter 未生效 | 检查 IAM 权限，查看 Firehose 错误 |
| Athena 查询报错 | Schema 不匹配 | 重新运行 Glue Crawler |
| 查询费用高 | 未使用分区过滤 | WHERE 条件加上 year/month/day |

## 相关内容 (Related)

- **Course:** [AWS SSM Session Logging](../../aws/ssm/05-session-logging/)
- **Course:** [Log Reading 日志分析](../../skills/log-reading/)
- **Solution:** [Drift Auto-Remediation](../../solutions/aws/drift-remediation/)

---

*Part of [cloud-atlas Solutions Gallery](../README.md)*
