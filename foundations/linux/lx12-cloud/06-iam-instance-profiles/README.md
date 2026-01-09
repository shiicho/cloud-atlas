# 06 - IAM 与实例配置文件（IAM & Instance Profiles）

> **目标**：理解实例配置文件如何提供凭证，掌握 AWS 凭证链和最小权限原则  
> **前置**：[03 - 元数据服务与 IMDSv2](../03-metadata/)、[05 - 云存储](../05-cloud-storage/)  
> **时间**：2 小时  
> **实战场景**：调试凭证链问题、实现最小权限 S3 访问  

---

## 将学到的内容

1. 理解实例配置文件（Instance Profile）如何为 EC2 提供凭证
2. 掌握 AWS 凭证链（Credential Chain）的查找顺序
3. 调试凭证相关问题（`aws sts get-caller-identity` 是你的好朋友）
4. 应用最小权限原则设计 IAM 策略
5. 理解 AssumeRole 跨账户访问模式

---

## 先跑起来！（10 分钟）

> 在学习 IAM 理论之前，先用一个命令探索你的云实例身份。  

在任意 EC2 实例上运行：

### 探索实例身份

```bash
# 最重要的 AWS 调试命令：我是谁？
aws sts get-caller-identity
```

```json
{
    "UserId": "AROAXXXXXXXXXXXXXXXXX:i-0abc123def456789",
    "Account": "123456789012",
    "Arn": "arn:aws:sts::123456789012:assumed-role/MyEC2Role/i-0abc123def456789"
}
```

**你刚刚看到了三个关键信息**：

| 字段 | 含义 | 示例 |
|------|------|------|
| `UserId` | 角色 ID + 实例 ID | `AROA...` 表示是 AssumedRole |
| `Account` | AWS 账户 ID | 用于确认账户 |
| `Arn` | 完整的身份 ARN | `assumed-role/MyEC2Role/...` 说明使用了 EC2 角色 |

### 探索凭证来源

```bash
# 凭证从哪里来？
curl -s -X PUT "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" > /tmp/imds-token

TOKEN=$(cat /tmp/imds-token)

# 获取角色名
ROLE=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/iam/security-credentials/)

echo "IAM Role: $ROLE"

# 查看凭证结构（不显示完整密钥）
curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/iam/security-credentials/$ROLE | \
  python3 -c "import sys,json; d=json.load(sys.stdin); print(f'AccessKeyId: {d[\"AccessKeyId\"][:10]}...\nExpiration: {d[\"Expiration\"]}')"
```

```
IAM Role: MyEC2Role
AccessKeyId: ASIAXXX...
Expiration: 2025-01-10T16:30:00Z
```

**关键发现**：
- 凭证以 `ASIA` 开头（临时凭证，不是永久密钥 `AKIA`）
- 凭证有过期时间（通常 6 小时）
- 凭证通过元数据服务自动提供

---

**你刚刚体验了 EC2 实例获取 AWS 凭证的核心机制。** 没有硬编码的 Access Key，没有配置文件，凭证自动轮换。这就是云原生的凭证管理方式。

---

## Step 1 - 实例配置文件概念（20 分钟）

### 1.1 什么是实例配置文件？

**Instance Profile** 是 IAM Role 和 EC2 实例之间的桥梁：

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    实例配置文件架构                                            │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│   ┌─────────────────┐                                                       │
│   │    IAM Role     │  定义权限策略                                         │
│   │  (MyEC2Role)    │  - 可以访问哪些 AWS 资源                              │
│   │                 │  - 允许哪些操作                                       │
│   └────────┬────────┘                                                       │
│            │                                                                │
│            │ 关联                                                            │
│            ▼                                                                │
│   ┌─────────────────┐                                                       │
│   │Instance Profile │  IAM Role 的"容器"                                    │
│   │ (MyEC2Profile)  │  - 1:1 关系（一个 Profile 一个 Role）                 │
│   │                 │  - 附加到 EC2 实例                                    │
│   └────────┬────────┘                                                       │
│            │                                                                │
│            │ 附加                                                            │
│            ▼                                                                │
│   ┌─────────────────────────────────────────────────────────────────────┐  │
│   │                          EC2 实例                                    │  │
│   │                                                                      │  │
│   │   应用程序 ──► AWS SDK ──► IMDS ──► 获取临时凭证 ──► 调用 AWS API    │  │
│   │                                                                      │  │
│   │   凭证特点：                                                         │  │
│   │   ● 临时凭证（ASIA 开头）                                            │  │
│   │   ● 自动轮换（约 6 小时）                                            │  │
│   │   ● 通过 IMDS 提供                                                   │  │
│   │   ● 无需存储在实例上                                                 │  │
│   └─────────────────────────────────────────────────────────────────────┘  │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 1.2 IAM Role vs Instance Profile

很多人混淆这两个概念：

| 概念 | 说明 | 类比 |
|------|------|------|
| **IAM Role** | 定义权限策略（可以做什么） | 工作职责描述 |
| **Instance Profile** | Role 的"载体"，附加到 EC2 | 工作证/通行证 |
| **Trust Policy** | 定义谁可以使用这个 Role | 入职条件 |

```bash
# 查看实例的 Instance Profile
TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")

curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/iam/info
```

```json
{
  "Code" : "Success",
  "LastUpdated" : "2025-01-10T10:30:00Z",
  "InstanceProfileArn" : "arn:aws:iam::123456789012:instance-profile/MyEC2Profile",
  "InstanceProfileId" : "AIPAXXXXXXXXXXXXXXXXX"
}
```

### 1.3 Trust Policy：谁可以使用这个 Role？

每个 IAM Role 都有一个 **Trust Policy**，定义谁可以"扮演"这个角色：

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
```

这个策略说明：**只有 EC2 服务可以使用这个角色**。

### 1.4 临时凭证的生命周期

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    临时凭证生命周期                                            │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  时间轴                                                                      │
│  ──────────────────────────────────────────────────────────────────────►   │
│                                                                             │
│  T0           T+5h           T+6h          T+11h         T+12h              │
│   │            │              │             │              │                │
│   ▼            ▼              ▼             ▼              ▼                │
│  ┌────────────────────────────────────────────┐                            │
│  │      凭证 A (有效期 6 小时)                  │                            │
│  │      AccessKeyId: ASIAXXX...               │                            │
│  └────────────────────────────────────────────┘                            │
│                                                                             │
│              ┌────────────────────────────────────────────┐                │
│              │  凭证 B (自动刷新，有效期 6 小时)            │                │
│              │  提前刷新，保证连续性                       │                │
│              └────────────────────────────────────────────┘                │
│                                                                             │
│  AWS SDK 自动处理：                                                         │
│  ● 在凭证过期前自动刷新                                                     │
│  ● 应用无感知，无需重启                                                     │
│  ● 刷新失败会有错误日志                                                     │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Step 2 - AWS 凭证链（Credential Chain）（25 分钟）

### 2.1 凭证链查找顺序

当你的应用调用 AWS API 时，SDK/CLI 按以下顺序查找凭证：

```
┌─────────────────────────────────────────────────────────────────────────────┐
│              AWS 凭证链 (Credential Chain) - 优先级从高到低                   │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  优先级 1：环境变量                                                          │
│  ┌───────────────────────────────────────────────────────────────────────┐ │
│  │ AWS_ACCESS_KEY_ID                                                     │ │
│  │ AWS_SECRET_ACCESS_KEY                                                 │ │
│  │ AWS_SESSION_TOKEN (可选，用于临时凭证)                                 │ │
│  │                                                                       │ │
│  │ 场景：CI/CD 管道、临时覆盖、测试                                       │ │
│  │ 风险：可能暴露在进程列表或日志中                                       │ │
│  └───────────────────────────────────────────────────────────────────────┘ │
│           │ 如果不存在                                                      │
│           ▼                                                                 │
│  优先级 2：配置文件 (~/.aws/credentials)                                    │
│  ┌───────────────────────────────────────────────────────────────────────┐ │
│  │ [default]                                                             │ │
│  │ aws_access_key_id = AKIAXXXXXXXXXXXXXXXX                              │ │
│  │ aws_secret_access_key = xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx      │ │
│  │                                                                       │ │
│  │ 场景：本地开发、个人电脑                                               │ │
│  │ 风险：永久凭证，泄露风险高                                             │ │
│  └───────────────────────────────────────────────────────────────────────┘ │
│           │ 如果不存在                                                      │
│           ▼                                                                 │
│  优先级 3：Web Identity Token (EKS IRSA)                                    │
│  ┌───────────────────────────────────────────────────────────────────────┐ │
│  │ AWS_WEB_IDENTITY_TOKEN_FILE                                           │ │
│  │ AWS_ROLE_ARN                                                          │ │
│  │                                                                       │ │
│  │ 场景：Kubernetes Pod (EKS IRSA)                                       │ │
│  │ 优势：Pod 级别细粒度权限                                               │ │
│  └───────────────────────────────────────────────────────────────────────┘ │
│           │ 如果不存在                                                      │
│           ▼                                                                 │
│  优先级 4：ECS 容器凭证                                                      │
│  ┌───────────────────────────────────────────────────────────────────────┐ │
│  │ AWS_CONTAINER_CREDENTIALS_RELATIVE_URI                                │ │
│  │ (由 ECS Agent 设置)                                                   │ │
│  │                                                                       │ │
│  │ 场景：ECS Task Role                                                   │ │
│  │ 优势：任务级别隔离                                                     │ │
│  └───────────────────────────────────────────────────────────────────────┘ │
│           │ 如果不存在                                                      │
│           ▼                                                                 │
│  优先级 5：实例配置文件 (Instance Profile) ★ EC2 推荐                       │
│  ┌───────────────────────────────────────────────────────────────────────┐ │
│  │ http://169.254.169.254/latest/meta-data/iam/security-credentials/     │ │
│  │                                                                       │ │
│  │ 场景：EC2 实例                                                        │ │
│  │ 优势：                                                                │ │
│  │   ● 临时凭证，自动轮换                                                │ │
│  │   ● 无需管理密钥                                                      │ │
│  │   ● 最小权限原则                                                      │ │
│  │   ● 审计可追溯                                                        │ │
│  └───────────────────────────────────────────────────────────────────────┘ │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 2.2 验证当前凭证来源

```bash
# 最重要的调试命令：我是谁？
aws sts get-caller-identity

# 查看 SDK 使用了哪个凭证（详细日志）
AWS_DEBUG=1 aws sts get-caller-identity 2>&1 | head -30

# 检查环境变量
env | grep -E '^AWS_'

# 检查配置文件
cat ~/.aws/credentials 2>/dev/null || echo "No credentials file"

# 检查实例配置文件
TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 60" --connect-timeout 2)
if [ -n "$TOKEN" ]; then
  curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
    http://169.254.169.254/latest/meta-data/iam/security-credentials/
else
  echo "Not running on EC2 or IMDS not available"
fi
```

### 2.3 凭证链的"陷阱"

**问题场景**：环境变量覆盖了实例配置文件

```bash
# 假设某脚本设置了环境变量
export AWS_ACCESS_KEY_ID="AKIAXXXXXXXXXXXXXXXX"
export AWS_SECRET_ACCESS_KEY="xxxxxxxx"

# 此时 aws 命令使用环境变量，而非实例配置文件
aws sts get-caller-identity
# 输出显示的是环境变量对应的用户，不是 EC2 角色！
```

**诊断方法**：

```bash
# 清除环境变量，验证实例配置文件
unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN

# 再次检查身份
aws sts get-caller-identity
# 现在应该显示 EC2 角色
```

### 2.4 为什么实例配置文件是首选？

| 凭证方式 | 安全性 | 管理成本 | 审计能力 | 推荐度 |
|----------|--------|----------|----------|--------|
| 硬编码在代码中 | 极差 | 高 | 差 | 禁止 |
| 环境变量 | 差 | 中 | 中 | 仅临时使用 |
| 配置文件 | 中 | 中 | 中 | 仅本地开发 |
| 实例配置文件 | 高 | 低 | 高 | EC2 首选 |
| ECS Task Role | 高 | 低 | 高 | ECS 首选 |
| EKS IRSA | 高 | 低 | 高 | EKS 首选 |

---

## Step 3 - 凭证调试（20 分钟）

### 3.1 调试工具箱

```bash
# === 身份确认 ===

# 查看当前身份
aws sts get-caller-identity

# 查看当前身份的 JSON 格式（便于脚本处理）
aws sts get-caller-identity --output json

# === 权限测试 ===

# 测试 S3 列表权限
aws s3 ls

# 测试特定桶访问
aws s3 ls s3://my-bucket/ 2>&1

# 测试 EC2 权限
aws ec2 describe-instances --max-results 1

# === 详细日志 ===

# 启用调试日志
AWS_DEBUG=1 aws s3 ls 2>&1 | head -50

# 更详细的日志（显示签名过程）
aws s3 ls --debug 2>&1 | head -100

# === 凭证来源诊断 ===

# 检查所有可能的凭证来源
echo "=== Environment Variables ==="
env | grep -E '^AWS_' || echo "None"

echo -e "\n=== Credentials File ==="
cat ~/.aws/credentials 2>/dev/null || echo "None"

echo -e "\n=== Config File ==="
cat ~/.aws/config 2>/dev/null || echo "None"

echo -e "\n=== Instance Profile ==="
TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 60" --connect-timeout 2)
if [ -n "$TOKEN" ]; then
  curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
    http://169.254.169.254/latest/meta-data/iam/security-credentials/
else
  echo "None (not on EC2)"
fi
```

### 3.2 常见错误消息解读

| 错误消息 | 原因 | 解决方法 |
|----------|------|----------|
| `Unable to locate credentials` | 没有找到任何凭证 | 检查凭证链所有来源 |
| `ExpiredTokenException` | 临时凭证过期 | SDK 通常自动刷新；手动凭证需重新获取 |
| `AccessDenied` | 有凭证但没有权限 | 检查 IAM 策略 |
| `InvalidClientTokenId` | 凭证无效（可能已删除） | 重新创建或使用其他凭证 |
| `SignatureDoesNotMatch` | 密钥错误或时间不同步 | 检查密钥、同步时间 |

### 3.3 权限问题诊断

```bash
# 使用 IAM Policy Simulator（需要 iam 权限）
aws iam simulate-principal-policy \
  --policy-source-arn arn:aws:iam::123456789012:role/MyEC2Role \
  --action-names s3:GetObject \
  --resource-arns arn:aws:s3:::my-bucket/*

# 查看角色策略（需要 iam 权限）
ROLE_NAME="MyEC2Role"
aws iam list-attached-role-policies --role-name $ROLE_NAME
aws iam list-role-policies --role-name $ROLE_NAME
```

---

## Step 4 - 最小权限原则（25 分钟）

### 4.1 什么是最小权限？

**最小权限原则（Principle of Least Privilege）**：只授予完成任务所需的最少权限。

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    最小权限 vs 过度授权                                        │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│   过度授权（危险！）                                                          │
│   ─────────────────                                                         │
│   {                                                                         │
│     "Effect": "Allow",                                                      │
│     "Action": "*",              ← 所有操作                                  │
│     "Resource": "*"             ← 所有资源                                  │
│   }                                                                         │
│                                                                             │
│   风险：                                                                     │
│   ● 凭证泄露 = 账户完全沦陷                                                 │
│   ● 应用 Bug 可能删除任意资源                                               │
│   ● 无法追溯问题来源                                                        │
│                                                                             │
│   ─────────────────────────────────────────────────────────────────────    │
│                                                                             │
│   最小权限（推荐）                                                           │
│   ───────────────                                                           │
│   {                                                                         │
│     "Effect": "Allow",                                                      │
│     "Action": [                                                             │
│       "s3:GetObject",           ← 只能读取                                  │
│       "s3:ListBucket"           ← 只能列表                                  │
│     ],                                                                      │
│     "Resource": [                                                           │
│       "arn:aws:s3:::my-app-data",           ← 只能访问特定桶               │
│       "arn:aws:s3:::my-app-data/*"          ← 桶内对象                     │
│     ]                                                                       │
│   }                                                                         │
│                                                                             │
│   优势：                                                                     │
│   ● 凭证泄露影响有限                                                        │
│   ● 应用只能做该做的事                                                      │
│   ● 审计清晰                                                                │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 4.2 IAM 策略结构

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowS3ReadOnly",
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:GetObjectVersion",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::my-app-data",
        "arn:aws:s3:::my-app-data/*"
      ],
      "Condition": {
        "StringEquals": {
          "aws:SourceVpc": "vpc-12345678"
        }
      }
    }
  ]
}
```

**策略元素说明**：

| 元素 | 说明 | 示例 |
|------|------|------|
| `Version` | 策略语言版本 | 始终使用 `2012-10-17` |
| `Statement` | 权限声明数组 | 可包含多个声明 |
| `Sid` | 声明 ID（可选） | 便于识别 |
| `Effect` | 允许或拒绝 | `Allow` 或 `Deny` |
| `Action` | 允许的操作 | `s3:GetObject`, `ec2:*` |
| `Resource` | 作用的资源 | ARN 格式 |
| `Condition` | 条件限制（可选） | VPC、IP、时间等 |

### 4.3 常用条件限制

```json
{
  "Condition": {
    "StringEquals": {
      "aws:SourceVpc": "vpc-12345678"
    },
    "IpAddress": {
      "aws:SourceIp": "10.0.0.0/8"
    },
    "DateGreaterThan": {
      "aws:CurrentTime": "2025-01-01T00:00:00Z"
    },
    "Bool": {
      "aws:SecureTransport": "true"
    }
  }
}
```

### 4.4 最小权限设计流程

```
1. 确定应用需要访问哪些 AWS 服务
   └─► 例：S3、DynamoDB、SQS

2. 确定需要哪些操作
   └─► 例：S3 只需读取，不需写入

3. 确定需要访问哪些资源
   └─► 例：只需要访问 my-app-data 桶

4. 考虑是否需要条件限制
   └─► 例：只允许从 VPC 内访问

5. 编写策略并测试
   └─► 使用 IAM Policy Simulator 验证

6. 定期审查和收紧
   └─► 使用 IAM Access Analyzer
```

---

## Step 5 - AssumeRole 跨账户访问（15 分钟）

### 5.1 什么是 AssumeRole？

**AssumeRole** 允许一个身份"扮演"另一个角色，获取该角色的临时凭证：

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    AssumeRole 工作流程                                        │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│   账户 A (111111111111)               账户 B (222222222222)                  │
│   ─────────────────────               ─────────────────────                  │
│                                                                             │
│   ┌─────────────────┐                 ┌─────────────────┐                   │
│   │   EC2 实例      │                 │  TargetRole     │                   │
│   │   (SourceRole)  │                 │  可访问 S3 桶   │                   │
│   └────────┬────────┘                 └────────┬────────┘                   │
│            │                                   │                            │
│            │ 1. AssumeRole 请求               │                            │
│            │─────────────────────────────────►│                            │
│            │                                   │                            │
│            │    (Trust Policy 验证             │                            │
│            │     SourceRole 是否被信任)        │                            │
│            │                                   │                            │
│            │ 2. 返回临时凭证                   │                            │
│            │◄─────────────────────────────────│                            │
│            │                                   │                            │
│            │ 3. 使用临时凭证访问账户 B 资源    │                            │
│            │─────────────────────────────────►│                            │
│            │                                   │                            │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 5.2 配置跨账户访问

**Step 1：在目标账户 (B) 创建角色的 Trust Policy**：

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::111111111111:role/SourceRole"
      },
      "Action": "sts:AssumeRole",
      "Condition": {
        "StringEquals": {
          "sts:ExternalId": "my-external-id-12345"
        }
      }
    }
  ]
}
```

**Step 2：在源账户 (A) 的角色添加 AssumeRole 权限**：

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "sts:AssumeRole",
      "Resource": "arn:aws:iam::222222222222:role/TargetRole"
    }
  ]
}
```

**Step 3：使用 AssumeRole 获取临时凭证**：

```bash
# AssumeRole
CREDS=$(aws sts assume-role \
  --role-arn arn:aws:iam::222222222222:role/TargetRole \
  --role-session-name MySession \
  --external-id my-external-id-12345 \
  --output json)

# 提取凭证
export AWS_ACCESS_KEY_ID=$(echo $CREDS | jq -r '.Credentials.AccessKeyId')
export AWS_SECRET_ACCESS_KEY=$(echo $CREDS | jq -r '.Credentials.SecretAccessKey')
export AWS_SESSION_TOKEN=$(echo $CREDS | jq -r '.Credentials.SessionToken')

# 验证新身份
aws sts get-caller-identity
# 现在显示的是 TargetRole
```

### 5.3 External ID 的作用

**External ID** 防止"混淆代理"攻击：

```
场景：SaaS 服务需要访问客户的 AWS 账户

没有 External ID：
- 攻击者知道 SaaS 的账户 ID
- 攻击者创建一个信任 SaaS 账户的角色
- 攻击者诱导 SaaS 服务 AssumeRole 到攻击者的角色
- SaaS 服务无意中操作了攻击者的资源

有 External ID：
- 每个客户有唯一的 External ID
- AssumeRole 需要提供正确的 External ID
- 攻击者不知道其他客户的 External ID
- 攻击失败
```

---

## Lab 1 - 最小权限实验（30 分钟）

### 实验目标

创建一个只读 S3 策略，验证最小权限的效果。

### Step 1 - 准备测试环境

```bash
# 确认当前身份
aws sts get-caller-identity

# 创建测试桶（如果没有）
BUCKET_NAME="test-least-privilege-$(date +%s)"
aws s3 mb s3://$BUCKET_NAME

# 上传测试文件
echo "test content" > /tmp/test.txt
aws s3 cp /tmp/test.txt s3://$BUCKET_NAME/

# 验证上传成功
aws s3 ls s3://$BUCKET_NAME/
```

### Step 2 - 创建只读策略

```bash
# 创建策略文件
cat > /tmp/s3-readonly-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowS3ReadOnly",
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:GetObjectVersion",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::$BUCKET_NAME",
        "arn:aws:s3:::$BUCKET_NAME/*"
      ]
    }
  ]
}
EOF

echo "Policy created:"
cat /tmp/s3-readonly-policy.json
```

### Step 3 - 附加策略到测试角色

```bash
# 创建 IAM 策略（需要 IAM 权限）
aws iam create-policy \
  --policy-name S3ReadOnlyTest \
  --policy-document file:///tmp/s3-readonly-policy.json

# 记录策略 ARN
POLICY_ARN="arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):policy/S3ReadOnlyTest"
echo "Policy ARN: $POLICY_ARN"

# 如果要测试，创建一个测试角色或附加到现有角色
# aws iam attach-role-policy --role-name TestRole --policy-arn $POLICY_ARN
```

### Step 4 - 验证权限

```bash
# 测试读取（应该成功）
aws s3 cp s3://$BUCKET_NAME/test.txt /tmp/downloaded.txt
cat /tmp/downloaded.txt

# 测试列表（应该成功）
aws s3 ls s3://$BUCKET_NAME/

# 测试写入（应该失败 - AccessDenied）
echo "new content" > /tmp/new.txt
aws s3 cp /tmp/new.txt s3://$BUCKET_NAME/ 2>&1

# 测试删除（应该失败 - AccessDenied）
aws s3 rm s3://$BUCKET_NAME/test.txt 2>&1
```

### Step 5 - 清理

```bash
# 删除测试文件和桶
aws s3 rm s3://$BUCKET_NAME/test.txt
aws s3 rb s3://$BUCKET_NAME

# 删除测试策略（如果创建了）
aws iam delete-policy --policy-arn $POLICY_ARN

rm /tmp/test.txt /tmp/new.txt /tmp/downloaded.txt /tmp/s3-readonly-policy.json
```

### 检查清单

- [ ] 理解 IAM 策略的基本结构
- [ ] 能创建限制特定资源的策略
- [ ] 能验证策略的实际效果
- [ ] 理解 Allow vs Deny 的区别

---

## Lab 2 - 凭证链调试（25 分钟）

### 实验目标

理解凭证链的优先级，诊断凭证来源问题。

### Step 1 - 查看当前凭证

```bash
# 创建诊断脚本
cat > /tmp/credential-check.sh << 'EOF'
#!/bin/bash

echo "=========================================="
echo "AWS 凭证诊断报告"
echo "=========================================="
echo ""

echo "1. 环境变量检查"
echo "-------------------------------------------"
if [ -n "$AWS_ACCESS_KEY_ID" ]; then
    echo "AWS_ACCESS_KEY_ID: ${AWS_ACCESS_KEY_ID:0:10}..."
else
    echo "AWS_ACCESS_KEY_ID: (未设置)"
fi

if [ -n "$AWS_SECRET_ACCESS_KEY" ]; then
    echo "AWS_SECRET_ACCESS_KEY: ***hidden***"
else
    echo "AWS_SECRET_ACCESS_KEY: (未设置)"
fi

if [ -n "$AWS_SESSION_TOKEN" ]; then
    echo "AWS_SESSION_TOKEN: ${AWS_SESSION_TOKEN:0:20}..."
else
    echo "AWS_SESSION_TOKEN: (未设置)"
fi

if [ -n "$AWS_PROFILE" ]; then
    echo "AWS_PROFILE: $AWS_PROFILE"
else
    echo "AWS_PROFILE: (未设置，将使用 default)"
fi

echo ""
echo "2. 配置文件检查"
echo "-------------------------------------------"
if [ -f ~/.aws/credentials ]; then
    echo "~/.aws/credentials: 存在"
    echo "配置的 profiles:"
    grep '^\[' ~/.aws/credentials
else
    echo "~/.aws/credentials: 不存在"
fi

echo ""
echo "3. 实例配置文件检查"
echo "-------------------------------------------"
TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" \
    -H "X-aws-ec2-metadata-token-ttl-seconds: 60" \
    --connect-timeout 2 --max-time 5 2>/dev/null)

if [ -n "$TOKEN" ]; then
    ROLE=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
        http://169.254.169.254/latest/meta-data/iam/security-credentials/ \
        --connect-timeout 2 --max-time 5 2>/dev/null)
    if [ -n "$ROLE" ]; then
        echo "Instance Profile Role: $ROLE"

        CREDS=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
            http://169.254.169.254/latest/meta-data/iam/security-credentials/$ROLE \
            --connect-timeout 2 --max-time 5 2>/dev/null)

        if [ -n "$CREDS" ]; then
            EXPIRATION=$(echo "$CREDS" | python3 -c "import sys,json; print(json.load(sys.stdin).get('Expiration','N/A'))" 2>/dev/null)
            echo "凭证过期时间: $EXPIRATION"
        fi
    else
        echo "没有附加 IAM 角色"
    fi
else
    echo "不在 EC2 上或 IMDS 不可用"
fi

echo ""
echo "4. 当前身份"
echo "-------------------------------------------"
aws sts get-caller-identity 2>&1

echo ""
echo "=========================================="
EOF

chmod +x /tmp/credential-check.sh
/tmp/credential-check.sh
```

### Step 2 - 模拟凭证冲突

```bash
# 保存当前环境
OLD_ACCESS_KEY=$AWS_ACCESS_KEY_ID
OLD_SECRET_KEY=$AWS_SECRET_ACCESS_KEY

# 设置一个假的环境变量（会导致认证失败）
export AWS_ACCESS_KEY_ID="AKIAIOSFODNN7EXAMPLE"
export AWS_SECRET_ACCESS_KEY="wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"

# 尝试调用 AWS API
echo "=== 使用假凭证测试 ==="
aws sts get-caller-identity 2>&1

# 错误应该显示：InvalidClientTokenId 或类似错误
```

### Step 3 - 恢复正确凭证

```bash
# 清除环境变量
unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN

# 验证恢复
echo "=== 清除环境变量后 ==="
aws sts get-caller-identity

# 现在应该使用实例配置文件
```

### Step 4 - 验证凭证链优先级

```bash
# 如果在 EC2 上，验证实例配置文件生效
echo "=== 凭证来源验证 ==="
/tmp/credential-check.sh

# 应该显示环境变量为空，使用实例配置文件
```

### 检查清单

- [ ] 理解凭证链的优先级顺序
- [ ] 能诊断凭证来源
- [ ] 理解环境变量如何覆盖实例配置文件
- [ ] 能恢复到正确的凭证配置

---

## 容器凭证概览（Container Credentials Sidebar）

虽然本课聚焦 EC2 实例配置文件，但容器环境有其专用的凭证机制：

### ECS Task Role

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    ECS Task Role                                            │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│   ┌─────────────────────────────────────────────────────────────────────┐  │
│   │                        ECS Cluster                                  │  │
│   │                                                                     │  │
│   │   ┌─────────────────┐    ┌─────────────────┐                       │  │
│   │   │   Task A        │    │   Task B        │                       │  │
│   │   │   Role: S3Admin │    │   Role: DBRead  │                       │  │
│   │   │   可写 S3       │    │   只读 RDS      │                       │  │
│   │   └─────────────────┘    └─────────────────┘                       │  │
│   │                                                                     │  │
│   └─────────────────────────────────────────────────────────────────────┘  │
│                                                                             │
│   特点：                                                                    │
│   ● 任务级隔离（不同任务不同权限）                                          │
│   ● 凭证通过 AWS_CONTAINER_CREDENTIALS_RELATIVE_URI 提供                   │
│   ● SDK 自动获取和刷新                                                     │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### EKS IRSA (IAM Roles for Service Accounts)

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    EKS IRSA                                                 │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│   ┌─────────────────────────────────────────────────────────────────────┐  │
│   │                        EKS Cluster                                  │  │
│   │                                                                     │  │
│   │   ┌─────────────────┐    ┌─────────────────┐                       │  │
│   │   │   Pod A         │    │   Pod B         │                       │  │
│   │   │   SA: s3-writer │    │   SA: db-reader │                       │  │
│   │   │   可写 S3       │    │   只读 RDS      │                       │  │
│   │   └─────────────────┘    └─────────────────┘                       │  │
│   │                                                                     │  │
│   └─────────────────────────────────────────────────────────────────────┘  │
│                                                                             │
│   特点：                                                                    │
│   ● Pod 级隔离（通过 Service Account 关联 IAM Role）                       │
│   ● 使用 OIDC 令牌交换 AWS 凭证                                            │
│   ● 比 EC2 实例配置文件更细粒度                                             │
│                                                                             │
│   配置：                                                                    │
│   apiVersion: v1                                                           │
│   kind: ServiceAccount                                                     │
│   metadata:                                                                │
│     annotations:                                                           │
│       eks.amazonaws.com/role-arn: arn:aws:iam::xxx:role/MyPodRole          │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

**详细内容参见 LX11-CONTAINERS 课程。**

---

## 反模式演示（Anti-Patterns Demo）

### 反模式 1：硬编码凭证

```bash
# 危险！凭证硬编码在脚本中
cat > /tmp/bad-script.sh << 'EOF'
#!/bin/bash
# 反模式：硬编码凭证
AWS_ACCESS_KEY_ID="AKIAIOSFODNN7EXAMPLE"
AWS_SECRET_ACCESS_KEY="wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"

aws s3 ls
EOF
```

**后果**：
- 凭证可能被提交到 Git 仓库
- 凭证在 `ps aux` 或日志中可见
- 无法轮换，泄露后必须重新生成
- 违反所有安全合规标准

**修复**：

```bash
# 正确：使用实例配置文件，无需任何凭证代码
aws s3 ls
# SDK 自动从 IMDS 获取临时凭证
```

### 反模式 2：过于宽松的 IAM 策略

```json
{
  "Effect": "Allow",
  "Action": "*",
  "Resource": "*"
}
```

**后果**：
- 应用可以做任何事情，包括删除资源
- 凭证泄露 = 账户完全沦陷
- 无法追踪问题来源
- 审计时无法解释为什么需要如此多权限

**修复**：

```json
{
  "Effect": "Allow",
  "Action": [
    "s3:GetObject",
    "s3:ListBucket"
  ],
  "Resource": [
    "arn:aws:s3:::my-app-bucket",
    "arn:aws:s3:::my-app-bucket/*"
  ]
}
```

### 反模式 3：忽略凭证来源

```bash
# 错误：不检查当前身份就执行操作
aws s3 rm s3://important-bucket/ --recursive
# 可能使用了错误的凭证！
```

**后果**：
- 使用了错误账户的凭证
- 删除了错误的资源
- 生产事故

**修复**：

```bash
# 正确：先确认身份
aws sts get-caller-identity
# 确认是正确的账户和角色后再执行操作
```

---

## 职场小贴士（Japan IT Context）

### 権限分離は監査要件

在日本企业，**权限分离（権限分離）** 是审计（監査）的基本要求：

| 日语术语 | 读音 | 含义 | IAM 实践 |
|----------|------|------|----------|
| 最小権限の原則 | さいしょうけんげんのげんそく | 最小权限原则 | 只授予必需的权限 |
| 職務分掌 | しょくむぶんしょう | 职责分离 | 开发/运维不同角色 |
| アクセス制御 | アクセスせいぎょ | 访问控制 | IAM 策略设计 |
| 監査証跡 | かんさしょうせき | 审计追踪 | CloudTrail 日志 |
| 権限レビュー | けんげんレビュー | 权限审查 | 定期权限盘点 |

### 日本企业的 IAM 治理实践

```
┌─────────────────────────────────────────────────────────────────────────────┐
│            IAM 権限管理チェックリスト（IAM 权限管理检查表）                    │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  1. 権限設計（权限设计）                                                     │
│     □ 最小権限の原則に従っているか                                          │
│     □ Resource に * を使用していないか                                      │
│     □ Condition を適切に設定しているか                                      │
│                                                                             │
│  2. 認証情報管理（凭证管理）                                                 │
│     □ EC2 にはインスタンスプロファイルを使用                                 │
│     □ ハードコードされた認証情報がないか                                    │
│     □ 一時認証情報を優先しているか                                          │
│                                                                             │
│  3. 監査対応（审计对应）                                                     │
│     □ CloudTrail が有効か                                                   │
│     □ IAM Access Analyzer を使用しているか                                  │
│     □ 権限変更の承認フローがあるか                                          │
│                                                                             │
│  4. 定期レビュー（定期审查）                                                 │
│     □ 未使用の権限を削除しているか                                          │
│     □ 退職者のアクセスを無効化しているか                                    │
│     □ 外部アクセスを定期的に確認しているか                                  │
│                                                                             │
│  確認日: ____________  確認者: ____________                                  │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### FISC / ISMAP 合规要求

日本金融行业（FISC）和政府云（ISMAP）对 IAM 有严格要求：

| 要求 | 说明 | 实践 |
|------|------|------|
| 最小権限 | 只授予必需权限 | 避免 `*` 权限 |
| 一時認証情報 | 使用临时凭证 | 使用 Instance Profile |
| 監査証跡 | 记录所有访问 | CloudTrail 必须启用 |
| 定期レビュー | 定期权限审查 | 季度 IAM 盘点 |
| MFA | 管理员 MFA 必须 | 控制台访问强制 MFA |

---

## 检查清单

完成本课后，你应该能够：

- [ ] 解释实例配置文件与 IAM 角色的关系
- [ ] 说明 AWS 凭证链的优先级顺序
- [ ] 使用 `aws sts get-caller-identity` 诊断当前身份
- [ ] 诊断常见的凭证错误（AccessDenied, ExpiredToken 等）
- [ ] 设计最小权限的 IAM 策略
- [ ] 解释 AssumeRole 的工作原理和使用场景
- [ ] 理解 External ID 在跨账户访问中的作用
- [ ] 避免硬编码凭证等反模式
- [ ] 掌握日本企业的 IAM 治理实践

---

## 本课小结

| 概念 | 要点 |
|------|------|
| Instance Profile | IAM Role 的载体，附加到 EC2 提供临时凭证 |
| 凭证链 | 环境变量 > 配置文件 > Web Identity > Container > Instance Profile |
| 调试命令 | `aws sts get-caller-identity` 是最重要的调试工具 |
| 最小权限 | 只授予必需的权限，限制资源和操作范围 |
| AssumeRole | 跨账户访问的标准模式，External ID 防止混淆代理 |
| 反模式 | 禁止硬编码凭证，禁止 `Action: *` |

---

## 延伸阅读

- [IAM Roles for Amazon EC2](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/iam-roles-for-amazon-ec2.html) - 官方文档
- [IAM Best Practices](https://docs.aws.amazon.com/IAM/latest/UserGuide/best-practices.html) - AWS IAM 最佳实践
- [IAM Policy Simulator](https://policysim.aws.amazon.com/) - 在线策略测试工具
- [Confused Deputy Problem](https://docs.aws.amazon.com/IAM/latest/UserGuide/confused-deputy.html) - External ID 背景
- 前一课：[05 - 云存储：EBS 与持久化](../05-cloud-storage/) - EBS 扩容和救援实例
- 下一课：[07 - 金色镜像策略](../07-golden-image/) - Bake vs Bootstrap 决策

---

## 清理资源

本课实验主要是查询操作，清理以下临时文件：

```bash
# 删除临时文件
rm -f /tmp/imds-token
rm -f /tmp/credential-check.sh
rm -f /tmp/s3-readonly-policy.json
rm -f /tmp/test.txt /tmp/new.txt /tmp/downloaded.txt

# 如果创建了测试 IAM 策略，记得删除
# aws iam delete-policy --policy-arn arn:aws:iam::xxx:policy/S3ReadOnlyTest

# 清除可能设置的环境变量
unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
```

---

## 系列导航

[<- 05 - 云存储：EBS 与持久化](../05-cloud-storage/) | [系列首页](../) | [07 - 金色镜像策略 ->](../07-golden-image/)
