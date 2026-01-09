# 03 - 元数据服务与 IMDSv2（Metadata Services & IMDSv2）

> **目标**：理解实例元数据服务，掌握 IMDSv2 安全机制，防范 SSRF 凭证窃取  
> **前置**：[01 - 云中 Linux 有何不同](../01-cloud-context/)、[02 - cloud-init 启动流程](../02-cloud-init/)  
> **时间**：2 小时  
> **实战场景**：诊断 IMDSv1 脚本在 IMDSv2 实例上的失败（The Credential Gap）  

---

## 将学到的内容

1. 理解实例元数据服务（IMDS）的作用和可用数据
2. 掌握 IMDSv2 token 机制及其工作原理
3. 了解 SSRF 凭证窃取风险（Capital One 2019 案例）
4. 配置实例强制使用 IMDSv2，设置 hop limit

---

## 先跑起来！（10 分钟）

> 在学习理论之前，先体验 IMDSv2 的 token 机制。  

在任意 EC2 实例上运行以下命令：

### 1. 尝试直接访问元数据（IMDSv1 方式）

```bash
curl -s http://169.254.169.254/latest/meta-data/instance-id
```

**可能的结果**：
- 如果实例允许 IMDSv1：返回实例 ID（如 `i-0abc123def456789`）
- 如果实例强制 IMDSv2：返回 `401 - Unauthorized`

### 2. 使用 IMDSv2 token 访问（安全方式）

```bash
# Step 1: 获取 token（PUT 请求，指定 TTL）
TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")

# Step 2: 使用 token 访问元数据
curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/instance-id
```

```
i-0abc123def456789
```

### 3. 获取 IAM 角色凭证（敏感数据！）

```bash
# 获取角色名
ROLE=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/iam/security-credentials/)

echo "IAM Role: $ROLE"

# 获取临时凭证（注意：这会显示真实凭证）
curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/iam/security-credentials/$ROLE | head -10
```

```json
{
  "Code" : "Success",
  "LastUpdated" : "2025-01-10T10:30:00Z",
  "Type" : "AWS-HMAC",
  "AccessKeyId" : "ASIA...",
  "SecretAccessKey" : "xxxxx...",
  "Token" : "FwoGZXIvYXdzE...",
  "Expiration" : "2025-01-10T16:30:00Z"
}
```

---

**你刚刚体验了 IMDSv2 的核心工作流：先获取 token，再用 token 访问数据。**

| IMDSv1 | IMDSv2 |
|--------|--------|
| 直接 GET 请求 | 先 PUT 获取 token |
| 无需认证 | Token 有效期限制 |
| 易受 SSRF 攻击 | SSRF 无法获取 token |
| 逐步淘汰 | 2025 强制要求 |

---

## Step 1 - 元数据服务基础（15 分钟）

### 1.1 什么是 169.254.169.254？

`169.254.169.254` 是一个**链路本地地址**（Link-Local Address），所有云平台都使用这个地址提供元数据服务：

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    元数据服务架构                                         │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│   ┌──────────────────────────────────────────────────────────────────┐ │
│   │                      EC2 实例                                     │ │
│   │                                                                   │ │
│   │   应用程序 ──────┐                                                │ │
│   │                  │ curl http://169.254.169.254/...               │ │
│   │   cloud-init ────┤                                                │ │
│   │                  │                                                │ │
│   │   AWS SDK/CLI ───┘                                                │ │
│   │                                                                   │ │
│   └───────────────────────────────┬──────────────────────────────────┘ │
│                                   │                                     │
│                                   │ 链路本地请求                        │
│                                   │ (不经过网络路由)                    │
│                                   ▼                                     │
│   ┌──────────────────────────────────────────────────────────────────┐ │
│   │              Instance Metadata Service (IMDS)                    │ │
│   │                                                                   │ │
│   │   ┌────────────┐  ┌────────────┐  ┌────────────┐                │ │
│   │   │ meta-data  │  │ user-data  │  │  dynamic   │                │ │
│   │   │ - ami-id   │  │ - scripts  │  │ - identity │                │ │
│   │   │ - hostname │  │ - config   │  │ - spot     │                │ │
│   │   │ - iam/     │  │            │  │            │                │ │
│   │   └────────────┘  └────────────┘  └────────────┘                │ │
│   │                                                                   │ │
│   └──────────────────────────────────────────────────────────────────┘ │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

### 1.2 可用的元数据类别

```bash
# 列出所有可用的元数据类别
TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")

curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/
```

```
ami-id
ami-launch-index
ami-manifest-path
block-device-mapping/
events/
hostname
iam/
identity-credentials/
instance-action
instance-id
instance-life-cycle
instance-type
local-hostname
local-ipv4
mac
metrics/
network/
placement/
profile
public-hostname
public-ipv4
public-keys/
reservation-id
security-groups
services/
tags/
```

### 1.3 常用元数据查询

| 路径 | 用途 | 示例值 |
|------|------|--------|
| `/meta-data/instance-id` | 实例唯一标识 | `i-0abc123def456789` |
| `/meta-data/instance-type` | 实例类型 | `t3.micro` |
| `/meta-data/local-ipv4` | 私有 IP | `10.0.1.52` |
| `/meta-data/public-ipv4` | 公有 IP | `54.123.45.67` |
| `/meta-data/placement/availability-zone` | 可用区 | `ap-northeast-1a` |
| `/meta-data/iam/security-credentials/` | IAM 角色凭证 | 临时密钥 |
| `/user-data` | 启动脚本 | cloud-init 配置 |
| `/dynamic/instance-identity/document` | 身份文档 | JSON（含签名） |

### 1.4 实例身份文档（Instance Identity Document）

```bash
curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/dynamic/instance-identity/document | python3 -m json.tool
```

```json
{
    "accountId": "123456789012",
    "architecture": "x86_64",
    "availabilityZone": "ap-northeast-1a",
    "billingProducts": null,
    "devpayProductCodes": null,
    "marketplaceProductCodes": null,
    "imageId": "ami-0abc123def456789",
    "instanceId": "i-0abc123def456789",
    "instanceType": "t3.micro",
    "kernelId": null,
    "pendingTime": "2025-01-10T10:30:00Z",
    "privateIp": "10.0.1.52",
    "ramdiskId": null,
    "region": "ap-northeast-1",
    "version": "2017-09-30"
}
```

**用途**：
- 实例向外部服务证明自己的身份
- 结合 PKCS7 签名验证真实性
- 常用于服务注册、配置管理

---

## Step 2 - IAM 凭证获取机制（20 分钟）

### 2.1 凭证链回顾

当应用程序调用 AWS API 时，SDK/CLI 按以下顺序查找凭证：

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    AWS 凭证链 (Credential Chain)                         │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  优先级 1：环境变量                                                      │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │ AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY / AWS_SESSION_TOKEN   │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│            │ 不存在                                                      │
│            ▼                                                             │
│  优先级 2：配置文件                                                      │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │ ~/.aws/credentials                                              │   │
│  │ [default]                                                       │   │
│  │ aws_access_key_id = AKIA...                                     │   │
│  │ aws_secret_access_key = xxxxx                                   │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│            │ 不存在                                                      │
│            ▼                                                             │
│  优先级 3：实例配置文件 (Instance Profile) ← 推荐！                      │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │ http://169.254.169.254/latest/meta-data/iam/security-credentials│   │
│  │                                                                 │   │
│  │ ● 临时凭证                                                      │   │
│  │ ● 自动轮换（6 小时）                                            │   │
│  │ ● 无需管理密钥                                                  │   │
│  │ ● 最小权限原则                                                  │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

### 2.2 临时凭证的结构

```bash
# 获取完整凭证
curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/iam/security-credentials/$ROLE
```

```json
{
  "Code": "Success",
  "LastUpdated": "2025-01-10T10:30:00Z",
  "Type": "AWS-HMAC",
  "AccessKeyId": "ASIAXXXXXXXXXXX",
  "SecretAccessKey": "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx",
  "Token": "FwoGZXIvYXdzEBYaDK...<very-long-token>...",
  "Expiration": "2025-01-10T16:30:00Z"
}
```

**关键字段**：

| 字段 | 说明 |
|------|------|
| `AccessKeyId` | 临时访问密钥（以 `ASIA` 开头） |
| `SecretAccessKey` | 临时密钥 |
| `Token` | 会话令牌（**必须**与密钥一起使用） |
| `Expiration` | 过期时间（通常 6 小时） |

### 2.3 凭证自动轮换

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    凭证轮换时间线                                         │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  10:00       12:00       14:00       16:00       18:00                  │
│    │           │           │           │           │                    │
│    ▼           ▼           ▼           ▼           ▼                    │
│  ┌─────────────────────────────────────────────────┐                   │
│  │         凭证 A (有效期 6 小时)                   │                   │
│  │         Expiration: 16:00                       │                   │
│  └─────────────────────────────────────────────────┘                   │
│                                                                         │
│                   ┌─────────────────────────────────────────────────┐  │
│                   │    新凭证 B（提前刷新，有重叠期）                │  │
│                   │    Expiration: 18:00                            │  │
│                   └─────────────────────────────────────────────────┘  │
│                                                                         │
│  AWS SDK 会在过期前自动刷新凭证，应用无需处理                            │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

**最佳实践**：使用 AWS SDK 而非手动解析凭证 - SDK 会自动处理刷新。

---

## Step 3 - IMDSv2 安全机制（25 分钟）

### 3.1 为什么需要 IMDSv2？

IMDSv1 的安全问题：任何能发送 HTTP 请求的代码都能获取凭证。

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    IMDSv1 的 SSRF 漏洞                                   │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│   攻击者                    Web 应用                    元数据服务        │
│     │                          │                           │            │
│     │  1. 构造恶意 URL         │                           │            │
│     │  url=http://169.254...  │                           │            │
│     │─────────────────────────>│                           │            │
│     │                          │                           │            │
│     │                          │  2. 应用发起请求          │            │
│     │                          │  GET /meta-data/iam/...   │            │
│     │                          │──────────────────────────>│            │
│     │                          │                           │            │
│     │                          │  3. 返回 IAM 凭证         │            │
│     │                          │<──────────────────────────│            │
│     │                          │                           │            │
│     │  4. 返回凭证给攻击者     │                           │            │
│     │<─────────────────────────│                           │            │
│     │                          │                           │            │
│     │  5. 攻击者使用凭证       │                           │            │
│     │  访问 AWS 资源！         │                           │            │
│     │                          │                           │            │
└─────────────────────────────────────────────────────────────────────────┘
```

### 3.2 IMDSv2 Token 机制

IMDSv2 引入了**基于 Token 的访问控制**：

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    IMDSv2 工作流程                                        │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│   Step 1: 获取 Token (PUT 请求)                                         │
│   ┌─────────────────────────────────────────────────────────────────┐  │
│   │  PUT /latest/api/token                                          │  │
│   │  X-aws-ec2-metadata-token-ttl-seconds: 21600                    │  │
│   │                                                                 │  │
│   │  返回: token-string-xxxxx...                                    │  │
│   └─────────────────────────────────────────────────────────────────┘  │
│                                                                         │
│   Step 2: 使用 Token 访问元数据 (GET 请求)                               │
│   ┌─────────────────────────────────────────────────────────────────┐  │
│   │  GET /latest/meta-data/iam/security-credentials/MyRole          │  │
│   │  X-aws-ec2-metadata-token: token-string-xxxxx...                │  │
│   │                                                                 │  │
│   │  返回: { "AccessKeyId": "...", "SecretAccessKey": "..." }       │  │
│   └─────────────────────────────────────────────────────────────────┘  │
│                                                                         │
│   为什么 SSRF 攻击无法利用 IMDSv2？                                      │
│   ─────────────────────────────────                                     │
│   ● SSRF 通常只能发送 GET 请求，无法发送 PUT 请求获取 token             │
│   ● 即使能发送 PUT，返回的 token 在 HTTP 响应 body 中                   │
│   ● SSRF 通常无法读取响应 body 并在后续请求中使用                       │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

### 3.3 Token TTL 和刷新

```bash
# Token 有效期可设置 1-21600 秒（6 小时）
# 短期任务使用短 TTL
TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 300")  # 5 分钟

# 长期运行服务使用长 TTL
TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")  # 6 小时
```

**建议**：
- 一次性脚本：300 秒（5 分钟）
- 后台服务：21600 秒（6 小时）并定期刷新

### 3.4 Hop Limit：网络层防护

**Hop Limit** 限制元数据请求的网络跳数，防止请求被转发到容器或其他网络层：

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    Hop Limit 工作原理                                     │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│   Hop Limit = 1 (默认推荐)                                              │
│   ────────────────────────                                              │
│                                                                         │
│   ┌───────────────────┐                                                │
│   │  EC2 实例         │                                                │
│   │  ┌─────────────┐  │      ✓ 可以访问                                │
│   │  │ 应用程序    │──┼───────────────────> IMDS                       │
│   │  └─────────────┘  │      (hop = 1)                                 │
│   │                   │                                                │
│   │  ┌─────────────┐  │      ✗ 被阻止                                  │
│   │  │  Docker     │──┼───────────────────> IMDS                       │
│   │  │  容器       │  │      (hop = 2)                                 │
│   │  └─────────────┘  │                                                │
│   └───────────────────┘                                                │
│                                                                         │
│   Hop Limit = 2 (容器环境)                                              │
│   ────────────────────────                                              │
│                                                                         │
│   ┌───────────────────┐                                                │
│   │  EC2 实例         │                                                │
│   │  ┌─────────────┐  │      ✓ 可以访问                                │
│   │  │  Docker     │──┼───────────────────> IMDS                       │
│   │  │  容器       │  │      (hop = 2)                                 │
│   │  └─────────────┘  │                                                │
│   └───────────────────┘                                                │
│                                                                         │
│   ⚠️  hop=2 时容器也能访问 IMDS，需要结合其他安全措施                     │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

**查看当前 hop limit**：

```bash
# 通过 AWS CLI 查看
aws ec2 describe-instances --instance-ids i-xxxxxxxxx \
  --query 'Reservations[].Instances[].MetadataOptions'
```

```json
{
    "State": "applied",
    "HttpTokens": "required",
    "HttpPutResponseHopLimit": 1,
    "HttpEndpoint": "enabled",
    "HttpProtocolIpv6": "disabled",
    "InstanceMetadataTags": "disabled"
}
```

---

## SSRF 凭证窃取：Capital One 2019 案例

> **背景**：2019 年 7 月，Capital One 遭受数据泄露，超过 1 亿用户数据被盗。  
> **根因**：WAF 配置错误导致 SSRF 漏洞，攻击者通过元数据服务获取 IAM 凭证。  

### 攻击链分析

```
┌─────────────────────────────────────────────────────────────────────────┐
│                Capital One SSRF 攻击链                                   │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  Step 1: 发现漏洞                                                       │
│  ────────────────                                                       │
│  攻击者发现 Capital One WAF 存在 SSRF 漏洞                               │
│  可以诱导服务器发送任意 HTTP 请求                                        │
│                                                                         │
│  Step 2: 获取 IAM 凭证                                                   │
│  ─────────────────                                                       │
│  攻击者构造恶意请求，让 WAF 访问：                                       │
│  http://169.254.169.254/latest/meta-data/iam/security-credentials/      │
│                                                                         │
│  IMDSv1 无需认证，直接返回临时凭证！                                     │
│                                                                         │
│  Step 3: 枚举 S3 桶                                                      │
│  ────────────────                                                       │
│  使用获取的凭证调用 AWS API：                                            │
│  aws s3 ls  # 列出可访问的 S3 桶                                         │
│                                                                         │
│  Step 4: 下载敏感数据                                                    │
│  ─────────────────                                                       │
│  aws s3 sync s3://capital-one-data /local/  # 批量下载                  │
│                                                                         │
│  结果：                                                                  │
│  ● 1 亿+ 用户数据泄露                                                   │
│  ● 社保号、银行账号、信用评分                                            │
│  ● Capital One 被罚款 8000 万美元                                        │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

### 如果使用了 IMDSv2

```
┌─────────────────────────────────────────────────────────────────────────┐
│              IMDSv2 如何阻止 Capital One 攻击                            │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  攻击者尝试：                                                           │
│  ─────────────                                                          │
│  curl http://169.254.169.254/latest/meta-data/iam/security-credentials/ │
│                                                                         │
│  返回：401 Unauthorized                                                 │
│                                                                         │
│  攻击者需要先获取 token：                                                │
│  ─────────────────────────                                              │
│  curl -X PUT http://169.254.169.254/latest/api/token \                  │
│    -H "X-aws-ec2-metadata-token-ttl-seconds: 21600"                     │
│                                                                         │
│  但是！                                                                 │
│  ─────                                                                  │
│  ● SSRF 通常只能发送 GET 请求                                           │
│  ● WAF/代理很少允许转发 PUT 请求                                        │
│  ● 即使能发送 PUT，token 在响应 body 中                                 │
│  ● 攻击者无法获取响应 body 并在后续请求中使用                           │
│                                                                         │
│  Hop Limit = 1 的额外保护：                                             │
│  ────────────────────────                                               │
│  如果 SSRF 是通过容器/函数触发的：                                       │
│  ● 请求经过网络桥接，hop > 1                                            │
│  ● IMDS 拒绝请求                                                        │
│                                                                         │
│  结论：IMDSv2 + Hop Limit = 1 可以有效防御大多数 SSRF 攻击              │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

### 教训总结

| 问题 | Capital One 的情况 | 最佳实践 |
|------|-------------------|----------|
| IMDS 版本 | 使用 IMDSv1 | 强制 IMDSv2 |
| Hop Limit | 未限制 | 设置为 1 |
| IAM 权限 | 过于宽松 | 最小权限原则 |
| S3 桶策略 | 允许广泛访问 | 严格限制访问来源 |
| 监控告警 | 未及时发现 | 异常 API 调用告警 |

---

## Step 4 - 跨云元数据对比（10 分钟）

所有主流云平台都提供类似的元数据服务：

| 云平台 | 元数据地址 | 安全机制 | 凭证服务 |
|--------|-----------|----------|----------|
| **AWS** | `169.254.169.254` | IMDSv2 + Hop Limit | Instance Profile |
| **GCP** | `169.254.169.254` | `Metadata-Flavor: Google` header | Service Account |
| **Azure** | `169.254.169.254` | `Metadata: true` header | Managed Identity |

### GCP 元数据访问

```bash
# GCP 要求特定 header
curl -H "Metadata-Flavor: Google" \
  http://169.254.169.254/computeMetadata/v1/instance/service-accounts/default/token
```

### Azure 元数据访问

```bash
# Azure 要求特定 header
curl -H "Metadata: true" \
  "http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https://management.azure.com/"
```

**共同模式**：
- 都使用 `169.254.169.254`
- 都提供临时凭证
- 都要求某种形式的认证（header 或 token）
- 凭证都会自动轮换

---

## Step 5 - 强制 IMDSv2（15 分钟）

### 5.1 实例级配置

**启动时强制 IMDSv2**：

```bash
aws ec2 run-instances \
  --image-id ami-xxxxxxxxx \
  --instance-type t3.micro \
  --metadata-options "HttpTokens=required,HttpPutResponseHopLimit=1,HttpEndpoint=enabled" \
  ...
```

**修改现有实例**：

```bash
aws ec2 modify-instance-metadata-options \
  --instance-id i-xxxxxxxxx \
  --http-tokens required \
  --http-put-response-hop-limit 1 \
  --http-endpoint enabled
```

### 5.2 Launch Template 配置

```json
{
  "MetadataOptions": {
    "HttpTokens": "required",
    "HttpPutResponseHopLimit": 1,
    "HttpEndpoint": "enabled",
    "InstanceMetadataTags": "enabled"
  }
}
```

### 5.3 组织级 SCP 策略

使用 Service Control Policy (SCP) 在组织级别强制 IMDSv2：

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "RequireIMDSv2",
      "Effect": "Deny",
      "Action": "ec2:RunInstances",
      "Resource": "arn:aws:ec2:*:*:instance/*",
      "Condition": {
        "StringNotEquals": {
          "ec2:MetadataHttpTokens": "required"
        }
      }
    },
    {
      "Sid": "PreventIMDSv2Disable",
      "Effect": "Deny",
      "Action": "ec2:ModifyInstanceMetadataOptions",
      "Resource": "arn:aws:ec2:*:*:instance/*",
      "Condition": {
        "StringEquals": {
          "ec2:MetadataHttpTokens": "optional"
        }
      }
    }
  ]
}
```

### 5.4 检测未配置 IMDSv2 的实例

```bash
# 列出所有未强制 IMDSv2 的实例
aws ec2 describe-instances \
  --query 'Reservations[].Instances[?MetadataOptions.HttpTokens!=`required`].[InstanceId,Tags[?Key==`Name`].Value|[0],MetadataOptions.HttpTokens]' \
  --output table
```

---

## Lab 1 - IMDSv2 Token 实验（25 分钟）

### 实验目标

深入理解 IMDSv2 token 机制，验证安全性。

### Step 1 - 准备环境

确保你有一台 EC2 实例，最好强制 IMDSv2：

```bash
# 检查当前配置
INSTANCE_ID=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 60" | xargs -I {} \
  curl -s -H "X-aws-ec2-metadata-token: {}" http://169.254.169.254/latest/meta-data/instance-id)

aws ec2 describe-instances --instance-ids $INSTANCE_ID \
  --query 'Reservations[].Instances[].MetadataOptions'
```

### Step 2 - Token 实验

```bash
# 实验 1: 无 token 访问
echo "=== Test 1: Access without token ==="
curl -s -w "\nHTTP Status: %{http_code}\n" \
  http://169.254.169.254/latest/meta-data/instance-id

# 实验 2: 获取短期 token (60 秒)
echo -e "\n=== Test 2: Get short-lived token ==="
SHORT_TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 60")
echo "Token obtained (first 20 chars): ${SHORT_TOKEN:0:20}..."

# 实验 3: 使用 token 访问
echo -e "\n=== Test 3: Access with token ==="
curl -s -H "X-aws-ec2-metadata-token: $SHORT_TOKEN" \
  http://169.254.169.254/latest/meta-data/instance-id

# 实验 4: 等待 token 过期 (需要等待 60 秒)
echo -e "\n=== Test 4: Wait for token expiration ==="
echo "Waiting 65 seconds for token to expire..."
sleep 65

# 实验 5: 使用过期 token
echo -e "\n=== Test 5: Access with expired token ==="
curl -s -w "\nHTTP Status: %{http_code}\n" \
  -H "X-aws-ec2-metadata-token: $SHORT_TOKEN" \
  http://169.254.169.254/latest/meta-data/instance-id
```

### Step 3 - 封装为函数

创建一个可复用的元数据查询函数：

```bash
#!/bin/bash
# imds_query.sh - IMDSv2 兼容的元数据查询函数

# 获取或刷新 token
get_imds_token() {
    local ttl=${1:-21600}  # 默认 6 小时
    curl -s -X PUT "http://169.254.169.254/latest/api/token" \
        -H "X-aws-ec2-metadata-token-ttl-seconds: $ttl" \
        --connect-timeout 2
}

# 查询元数据
query_metadata() {
    local path=$1
    local token=${2:-$(get_imds_token)}

    if [ -z "$token" ]; then
        echo "Error: Failed to get IMDS token" >&2
        return 1
    fi

    curl -s -H "X-aws-ec2-metadata-token: $token" \
        "http://169.254.169.254/latest/meta-data/$path" \
        --connect-timeout 2
}

# 使用示例
TOKEN=$(get_imds_token)
echo "Instance ID: $(query_metadata instance-id $TOKEN)"
echo "Instance Type: $(query_metadata instance-type $TOKEN)"
echo "AZ: $(query_metadata placement/availability-zone $TOKEN)"
echo "Private IP: $(query_metadata local-ipv4 $TOKEN)"
```

### 检查清单

- [ ] 理解无 token 访问会被拒绝（强制 IMDSv2 时）
- [ ] 能获取指定 TTL 的 token
- [ ] 理解 token 过期后需要重新获取
- [ ] 创建了可复用的元数据查询函数

---

## Lab 2 - Credential Gap 场景（30 分钟）

### 场景描述

> 一个备份 Python 脚本在旧实例上正常工作，但在新的「安全加固」实例群上失败，返回 "401 Unauthorized"。  

这是日本 IT 现场常见的**障害対応**场景：安全团队启用了 IMDSv2，但旧脚本还在使用 IMDSv1。

### 实验目标

诊断并修复 IMDSv1 脚本在 IMDSv2 实例上的失败。

### Step 1 - 模拟旧脚本（IMDSv1 方式）

创建一个使用 IMDSv1 的备份脚本：

```bash
cat > /tmp/backup_v1.sh << 'EOF'
#!/bin/bash
# backup_v1.sh - 使用 IMDSv1 的旧版备份脚本
# 问题：在 IMDSv2 实例上会失败

echo "=== Old Backup Script (IMDSv1) ==="

# 获取实例 ID（IMDSv1 方式 - 直接 GET）
INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)

if [ -z "$INSTANCE_ID" ]; then
    echo "ERROR: Failed to get instance ID"
    exit 1
fi

echo "Instance ID: $INSTANCE_ID"

# 获取 IAM 角色名
ROLE=$(curl -s http://169.254.169.254/latest/meta-data/iam/security-credentials/)

if [ -z "$ROLE" ]; then
    echo "ERROR: Failed to get IAM role"
    exit 1
fi

echo "IAM Role: $ROLE"

# 获取凭证
CREDS=$(curl -s http://169.254.169.254/latest/meta-data/iam/security-credentials/$ROLE)

if echo "$CREDS" | grep -q "AccessKeyId"; then
    echo "SUCCESS: Got credentials"
    # 模拟备份操作
    echo "Performing backup..."
else
    echo "ERROR: Failed to get credentials"
    echo "Response: $CREDS"
    exit 1
fi
EOF

chmod +x /tmp/backup_v1.sh
```

### Step 2 - 运行并观察失败

```bash
# 运行旧脚本
/tmp/backup_v1.sh
```

**在强制 IMDSv2 的实例上，输出**：

```
=== Old Backup Script (IMDSv1) ===
ERROR: Failed to get instance ID
```

或者：

```
=== Old Backup Script (IMDSv1) ===
Instance ID:
ERROR: Failed to get instance ID
```

### Step 3 - 诊断问题

```bash
# 检查 IMDS 配置
echo "=== IMDS Configuration ==="
curl -s -X PUT "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 60" > /dev/null && \
  echo "IMDSv2 is available"

# 尝试 IMDSv1 方式
echo -e "\n=== IMDSv1 Test ==="
curl -s -w "\nHTTP Status: %{http_code}\n" \
  http://169.254.169.254/latest/meta-data/instance-id

# 验证当前身份
echo -e "\n=== Current Identity ==="
aws sts get-caller-identity 2>&1 || echo "AWS CLI also failing?"
```

### Step 4 - 修复脚本（IMDSv2 兼容）

创建修复后的脚本：

```bash
cat > /tmp/backup_v2.sh << 'EOF'
#!/bin/bash
# backup_v2.sh - IMDSv2 兼容的备份脚本
# 最佳实践：支持 IMDSv1 和 IMDSv2

echo "=== Updated Backup Script (IMDSv2 Compatible) ==="

# 函数：获取元数据（IMDSv2 优先，fallback 到 IMDSv1）
get_metadata() {
    local path=$1
    local token=$2

    if [ -n "$token" ]; then
        # IMDSv2
        curl -s -H "X-aws-ec2-metadata-token: $token" \
            "http://169.254.169.254/latest/meta-data/$path" \
            --connect-timeout 2
    else
        # Fallback to IMDSv1 (for older instances)
        curl -s "http://169.254.169.254/latest/meta-data/$path" \
            --connect-timeout 2
    fi
}

# 尝试获取 IMDSv2 token
echo "Attempting to get IMDSv2 token..."
TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" \
    -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" \
    --connect-timeout 2)

if [ -n "$TOKEN" ]; then
    echo "IMDSv2 token obtained"
else
    echo "IMDSv2 token not available, falling back to IMDSv1"
fi

# 获取实例 ID
INSTANCE_ID=$(get_metadata "instance-id" "$TOKEN")

if [ -z "$INSTANCE_ID" ]; then
    echo "ERROR: Failed to get instance ID"
    echo "Check: Is IMDS endpoint enabled?"
    exit 1
fi

echo "Instance ID: $INSTANCE_ID"

# 获取 IAM 角色名
ROLE=$(get_metadata "iam/security-credentials/" "$TOKEN")

if [ -z "$ROLE" ]; then
    echo "ERROR: Failed to get IAM role"
    echo "Check: Is an IAM role attached to this instance?"
    exit 1
fi

echo "IAM Role: $ROLE"

# 获取凭证
CREDS=$(get_metadata "iam/security-credentials/$ROLE" "$TOKEN")

if echo "$CREDS" | grep -q "AccessKeyId"; then
    echo "SUCCESS: Got credentials"

    # 解析凭证（用于演示）
    ACCESS_KEY=$(echo "$CREDS" | python3 -c "import sys,json; print(json.load(sys.stdin)['AccessKeyId'])")
    EXPIRATION=$(echo "$CREDS" | python3 -c "import sys,json; print(json.load(sys.stdin)['Expiration'])")

    echo "Access Key ID: ${ACCESS_KEY:0:10}..."
    echo "Expiration: $EXPIRATION"

    # 模拟备份操作
    echo "Performing backup..."
    # aws s3 sync /data s3://backup-bucket/...

    echo "Backup completed successfully!"
else
    echo "ERROR: Failed to get credentials"
    echo "Response: $CREDS"
    exit 1
fi
EOF

chmod +x /tmp/backup_v2.sh
```

### Step 5 - 验证修复

```bash
# 运行修复后的脚本
/tmp/backup_v2.sh
```

**预期输出**：

```
=== Updated Backup Script (IMDSv2 Compatible) ===
Attempting to get IMDSv2 token...
IMDSv2 token obtained
Instance ID: i-0abc123def456789
IAM Role: MyBackupRole
SUCCESS: Got credentials
Access Key ID: ASIAXXX...
Expiration: 2025-01-10T16:30:00Z
Performing backup...
Backup completed successfully!
```

### 检查清单

- [ ] 理解 IMDSv1 脚本在 IMDSv2 实例上失败的原因
- [ ] 能诊断 401 Unauthorized 错误
- [ ] 能将脚本修改为 IMDSv2 兼容
- [ ] 理解 fallback 机制的设计模式

---

## 反模式演示

### 反模式 1：使用 IMDSv1

```bash
# 错误：直接 GET 请求，在 IMDSv2 实例上会失败
INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
```

**后果**：
- 在强制 IMDSv2 的实例上返回空或 401
- 脚本静默失败，难以排查
- 存在 SSRF 安全风险

**修复**：

```bash
# 正确：先获取 token，再使用 token 访问
TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
INSTANCE_ID=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/instance-id)
```

### 反模式 2：假设元数据永远可达

```bash
# 错误：没有超时和错误处理
REGION=$(curl http://169.254.169.254/latest/meta-data/placement/region)
aws s3 ls s3://my-bucket --region $REGION
```

**后果**：
- 元数据服务暂时不可用时脚本挂起
- 网络问题导致无限等待
- 变量为空导致后续命令失败

**修复**：

```bash
# 正确：添加超时和错误处理
TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 300" \
  --connect-timeout 2 --max-time 5)

if [ -z "$TOKEN" ]; then
    echo "ERROR: Cannot get IMDS token, using fallback region"
    REGION="ap-northeast-1"  # 默认值
else
    REGION=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
      http://169.254.169.254/latest/meta-data/placement/region \
      --connect-timeout 2 --max-time 5)

    if [ -z "$REGION" ]; then
        echo "WARNING: Cannot get region from metadata, using fallback"
        REGION="ap-northeast-1"
    fi
fi

aws s3 ls s3://my-bucket --region $REGION
```

### 反模式 3：Hop Limit 设置过高

```bash
# 错误：为了让容器访问 IMDS，将 hop limit 设为 2 或更高
aws ec2 modify-instance-metadata-options \
  --instance-id i-xxxxxxxxx \
  --http-put-response-hop-limit 2
```

**后果**：
- 容器可以直接访问宿主机的 IMDS
- 容器逃逸攻击可能获取宿主机凭证
- 违反最小权限原则

**修复**：

```bash
# 正确：保持 hop limit = 1，容器使用专用凭证机制
aws ec2 modify-instance-metadata-options \
  --instance-id i-xxxxxxxxx \
  --http-put-response-hop-limit 1

# 容器应使用：
# - ECS: Task Role
# - EKS: IRSA (IAM Roles for Service Accounts)
# - 手动: 通过 iptables 转发到代理
```

---

## 职场小贴士（Japan IT Context）

### FISC 金融监管要求

**FISC**（金融情报システムセンター）是日本金融厅下属机构，发布金融系统安全指南。

对于云环境，FISC 指南要求：

| 要求 | IMDS 相关措施 |
|------|--------------|
| 凭証管理 | 使用临时凭证（Instance Profile），禁止硬编码 |
| アクセス制御 | 强制 IMDSv2，设置 hop limit |
| 監査証跡 | 记录凭证访问日志 |
| 暗号化 | 凭证传输加密（IMDS 是本地访问，已隔离） |

### ISMAP 政府云认证

**ISMAP**（政府情報システムのためのセキュリティ評価制度）是日本政府的云安全认证。

AWS 等云服务商已通过 ISMAP 认证，但用户侧配置仍需满足：

- 强制 IMDSv2
- 最小权限 IAM 策略
- 凭证使用审计

### 日本 IT 术语对照

| 日语术语 | 读音 | 含义 | 场景 |
|----------|------|------|------|
| セキュリティ対策 | セキュリティたいさく | 安全措施 | "IMDSv2 はセキュリティ対策の基本です" |
| 認証・認可 | にんしょう・にんか | 认证・授权 | "IMDS で認証情報を取得" |
| 一時認証情報 | いちじにんしょうじょうほう | 临时凭证 | Instance Profile 提供的凭证 |
| 権限分離 | けんげんぶんり | 权限分离 | 最小权限原则 |
| 脆弱性 | ぜいじゃくせい | 漏洞 | "SSRF 脆弱性による認証情報漏洩" |

### 安全加固检查清单（日本企业格式）

```
┌─────────────────────────────────────────────────────────────────────────┐
│            IMDS セキュリティチェックリスト                                 │
│            (IMDS Security Checklist)                                    │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  1. IMDS バージョン確認                                                  │
│     □ HttpTokens = required (IMDSv2 強制)                               │
│     □ IMDSv1 を使用するスクリプトがないか確認                            │
│                                                                         │
│  2. Hop Limit 確認                                                      │
│     □ HttpPutResponseHopLimit = 1                                       │
│     □ コンテナ環境の場合は別途対策                                       │
│                                                                         │
│  3. IAM ロール確認                                                       │
│     □ 最小権限の原則に従っている                                         │
│     □ 不要な権限が付与されていない                                       │
│                                                                         │
│  4. 監視設定                                                             │
│     □ CloudTrail で API コール監視                                       │
│     □ 異常なメタデータアクセスのアラート                                 │
│                                                                         │
│  5. 組織ポリシー                                                         │
│     □ SCP で IMDSv2 を組織全体で強制                                     │
│     □ 新規インスタンスのデフォルト設定                                   │
│                                                                         │
│  確認日: ____________  確認者: ____________                             │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## 检查清单

完成本课后，你应该能够：

- [ ] 解释元数据服务（IMDS）的作用和访问方法
- [ ] 列出常用的元数据路径及其用途
- [ ] 演示 IMDSv2 token 获取和使用流程
- [ ] 解释 SSRF 攻击如何利用 IMDSv1 窃取凭证
- [ ] 说明 hop limit 的作用和推荐值
- [ ] 配置实例强制使用 IMDSv2
- [ ] 将 IMDSv1 脚本修改为 IMDSv2 兼容
- [ ] 解释 Capital One 事件的攻击链和防护措施

---

## 本课小结

| 概念 | 要点 |
|------|------|
| IMDS 地址 | `169.254.169.254`（链路本地地址） |
| 可用数据 | instance-id, IAM 凭证, user-data, 身份文档 |
| IMDSv2 机制 | PUT 获取 token → 用 token 访问数据 |
| Token TTL | 1-21600 秒（推荐短期任务用短 TTL） |
| Hop Limit | 限制网络跳数，推荐设为 1 |
| SSRF 防护 | IMDSv2 + Hop Limit = 1 |
| 凭证最佳实践 | 使用 Instance Profile，禁止硬编码 |

---

## 延伸阅读

- [AWS IMDSv2 文档](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/configuring-instance-metadata-service.html) - 官方配置指南
- [Add defense in depth against open firewalls, reverse proxies, and SSRF vulnerabilities](https://aws.amazon.com/blogs/security/defense-in-depth-open-firewalls-reverse-proxies-ssrf-vulnerabilities-ec2-instance-metadata-service/) - AWS 安全博客
- [Capital One Data Breach Analysis](https://krebsonsecurity.com/2019/07/capital-one-data-theft-impacts-106m-people/) - 案例分析
- 下一课：[04 - 云网络：Linux 视角](../04-cloud-networking/) - 理解安全组与 nftables 的关系
- 相关课程：[06 - IAM 与实例配置文件](../06-iam-instance-profiles/) - 深入 IAM 凭证管理

---

## 清理资源

本课实验主要是查询操作，无需特别清理。

如果你修改了实例的 IMDS 配置用于测试，记得恢复：

```bash
# 如果需要恢复允许 IMDSv1（不推荐用于生产）
aws ec2 modify-instance-metadata-options \
  --instance-id i-xxxxxxxxx \
  --http-tokens optional \
  --http-put-response-hop-limit 1
```

> **安全提醒**：生产环境应始终保持 `HttpTokens=required`。  

---

## 系列导航

[<- 02 - cloud-init 启动流程](../02-cloud-init/) | [系列首页](../) | [04 - 云网络：Linux 视角 ->](../04-cloud-networking/)
