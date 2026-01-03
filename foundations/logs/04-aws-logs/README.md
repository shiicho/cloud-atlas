# 04 · AWS 日志实战（CloudTrail, VPC Flow, ALB, Lambda）

> **目标**：解析 CloudTrail 审计日志，关联 VPC Flow Log 和 ALB 日志定位问题  
> **前置**：[01 · 日志分析工具与模式识别](../01-tools-patterns/)（jq 技能）  
> **区域**：ap-northeast-1（东京）  
> **费用**：CloudTrail 和 VPC Flow Logs 按数据量收费

## 将完成的内容

1. 理解 CloudTrail 审计日志结构
2. 解析 VPC Flow Log 格式
3. 分析 ALB Access Log
4. 关联多源 AWS 日志
5. 实战：追踪未授权访问

---

## CloudTrail 日志分析 {#cloudtrail}

CloudTrail 记录 AWS API 调用，是安全审计的核心日志。

### 日志结构

CloudTrail 日志是 JSON 格式，存储在 S3：

```json
{
  "eventTime": "2024-06-24T01:12:02Z",
  "eventSource": "signin.amazonaws.com",
  "eventName": "ConsoleLogin",
  "awsRegion": "ap-northeast-1",
  "sourceIPAddress": "5.6.7.8",
  "userAgent": "Mozilla/5.0...",
  "errorMessage": "Failed authentication",
  "userIdentity": {
    "type": "IAMUser",
    "userName": "admin"
  },
  "additionalEventData": {
    "MFAUsed": "No"
  }
}
```

### 重要字段

| 字段 | 含义 | 分析价值 |
|------|------|---------|
| `eventTime` | 事件时间（UTC） | 时间线重建 |
| `eventName` | API 操作名 | 识别操作类型 |
| `eventSource` | 服务来源 | 识别涉及服务 |
| `sourceIPAddress` | 调用来源 IP | 识别攻击者 |
| `userAgent` | 客户端信息 | 识别工具/浏览器 |
| `errorCode` | 错误代码 | 失败原因 |
| `errorMessage` | 错误详情 | 诊断问题 |
| `userIdentity` | 调用者身份 | 识别用户/角色 |

### jq 分析 CloudTrail

```bash
# 下载日志（通常是 .json.gz）
aws s3 cp s3://your-bucket/AWSLogs/.../cloudtrail.json.gz .
gunzip cloudtrail.json.gz

# 格式化查看
cat cloudtrail.json | jq .

# 提取登录事件
jq '.Records[] | select(.eventName == "ConsoleLogin")' cloudtrail.json

# 提取失败事件
jq '.Records[] | select(.errorCode != null)' cloudtrail.json

# 提取关键字段
jq '.Records[] | {time: .eventTime, event: .eventName, user: .userIdentity.userName, ip: .sourceIPAddress, error: .errorCode}' cloudtrail.json
```

### 常见需要关注的事件

| 事件 | 含义 | 关注点 |
|------|------|--------|
| `ConsoleLogin` | 控制台登录 | 来源 IP、MFA 状态 |
| `AssumeRole` | 角色切换 | 谁切换到什么角色 |
| `CreateUser` | 创建用户 | 权限提升攻击 |
| `AttachUserPolicy` | 附加策略 | 权限变更 |
| `RunInstances` | 启动 EC2 | 资源创建 |
| `DeleteBucket` | 删除存储桶 | 破坏性操作 |

---

## VPC Flow Log 分析 {#vpc-flow}

VPC Flow Log 记录网络流量，用于网络排查和安全分析。

### 日志格式（默认）

```
2 123456789 eni-abc 10.0.1.5 172.31.20.15 443 53122 6 5 234 1719204722 1719204730 REJECT OK
│ │         │       │        │            │   │     │ │ │   │          │          │      │
│ │         │       │        │            │   │     │ │ │   │          │          │      └─ log-status
│ │         │       │        │            │   │     │ │ │   │          │          └─ action
│ │         │       │        │            │   │     │ │ │   │          └─ end (epoch)
│ │         │       │        │            │   │     │ │ │   └─ start (epoch)
│ │         │       │        │            │   │     │ │ └─ bytes
│ │         │       │        │            │   │     │ └─ packets
│ │         │       │        │            │   │     └─ protocol (6=TCP, 17=UDP)
│ │         │       │        │            │   └─ dst-port
│ │         │       │        │            └─ src-port
│ │         │       │        └─ dst-addr
│ │         │       └─ src-addr
│ │         └─ interface-id
│ └─ account-id
└─ version
```

### 字段说明

| 字段 | 位置 | 含义 |
|------|------|------|
| `srcaddr` | $4 | 源 IP |
| `dstaddr` | $5 | 目标 IP |
| `srcport` | $6 | 源端口 |
| `dstport` | $7 | 目标端口 |
| `protocol` | $8 | 协议（6=TCP, 17=UDP, 1=ICMP） |
| `action` | $13 | ACCEPT 或 REJECT |
| `start` | $11 | 开始时间（epoch） |

### 分析命令

```bash
# 统计 REJECT 数量
awk '$13 == "REJECT"' flowlog.txt | wc -l

# 统计被拒绝的目标端口
awk '$13 == "REJECT" {print $7}' flowlog.txt | sort | uniq -c | sort -nr | head

# 统计被拒绝的源 IP
awk '$13 == "REJECT" {print $4}' flowlog.txt | sort | uniq -c | sort -nr | head
```

### Epoch 时间转换

VPC Flow Log 使用 epoch 时间戳（秒）：

```bash
# Linux 转换
date -d @1719204722
# 输出: Mon Jun 24 01:12:02 UTC 2024

# 转为 JST
TZ='Asia/Tokyo' date -d @1719204722
# 输出: Mon Jun 24 10:12:02 JST 2024
```

---

## ALB Access Log 分析 {#alb}

ALB (Application Load Balancer) 日志记录请求详情。

### 日志格式

```
h2 2024-06-24T01:12:02.123456Z app/my-alb/abc123 172.31.20.15:443 10.0.1.5:53122 0.000 0.203 0.000 504 504 0 57 "GET https://app.example.com/api/report HTTP/2.0" "curl/8.4" ECDHE-RSA-AES128-GCM-SHA256 TLSv1.2 arn:aws:... "Root=1-abc..."
```

### 关键字段

| 位置 | 内容 | 说明 |
|------|------|------|
| $1 | `h2` | 协议类型 |
| $2 | `2024-06-24T01:12:02.123456Z` | 时间（UTC） |
| $4 | `172.31.20.15:443` | 客户端 IP:端口 |
| $5 | `10.0.1.5:53122` | 目标 IP:端口 |
| $6-8 | `0.000 0.203 0.000` | 请求/目标/响应处理时间 |
| $9 | `504` | ELB 状态码 |
| $10 | `504` | 目标状态码 |

### 分析命令

```bash
# 统计 ELB 状态码
awk '{print $9}' alb-log.txt | sort | uniq -c | sort -nr

# 找 504 错误的目标 IP
awk '$9 == 504 {print $5}' alb-log.txt | sort | uniq -c | sort -nr

# 分析响应时间分布
awk '{print $7}' alb-log.txt | sort -n | awk '{a[NR]=$1} END {print "median:", a[int(NR/2)]}'
```

---

## 实战练习：追踪未授权访问

### 场景描述

安全团队收到告警：「检测到可疑的控制台登录尝试」。需要关联多源日志分析。

### 日志样本

**CloudTrail 日志：**
```json
{
  "eventTime": "2024-06-24T01:12:02Z",
  "eventName": "ConsoleLogin",
  "sourceIPAddress": "5.6.7.8",
  "errorMessage": "Failed authentication",
  "additionalEventData": {
    "MFAUsed": "No"
  }
}
```

**VPC Flow Log：**
```
2 123456789 eni-abc 10.0.1.5 172.31.20.15 443 53122 6 5 234 1719204722 1719204730 REJECT OK
```

**ALB Log：**
```
h2 172.31.20.15:443 10.0.1.5:53122 0.000 0.203 0.000 504 504 0 57 "GET https://app.example.com/api/report" "-" "curl/8.4"
```

### 分析步骤

**Step 1: 分析 CloudTrail 登录失败**

```bash
# 提取登录失败事件
jq '.Records[] | select(.eventName == "ConsoleLogin" and .errorMessage != null) | {time: .eventTime, ip: .sourceIPAddress, user: .userIdentity.userName, mfa: .additionalEventData.MFAUsed, error: .errorMessage}' cloudtrail.json
```

关注点：
- `sourceIPAddress`: 5.6.7.8（外部 IP）
- `MFAUsed`: No（未启用 MFA）
- `errorMessage`: Failed authentication

**Step 2: 检查该 IP 是否有其他活动**

```bash
# 搜索该 IP 所有活动
jq '.Records[] | select(.sourceIPAddress == "5.6.7.8")' cloudtrail.json
```

**Step 3: 分析 VPC Flow Log 中的 REJECT**

```bash
# 转换 epoch 时间
date -d @1719204722  # 2024-06-24 01:12:02 UTC

# 检查同时间段的 REJECT
awk '$13 == "REJECT" && $11 >= 1719204700 && $11 <= 1719204800' flowlog.txt
```

**Step 4: 关联 ALB 日志**

```bash
# 查找同源 IP 的请求
grep "10.0.1.5" alb-log.txt | awk '{print $9, $10}' | sort | uniq -c
```

### 发现要点

| 层次 | 发现 |
|------|------|
| **显而易见** | ConsoleLogin 失败，MFA 未启用 |
| **需要细看** | VPC Flow Log 的 epoch 需转 JST；ALB 504 与 REJECT 可能相关 |

### 关联分析结论

1. 外部 IP 5.6.7.8 尝试控制台登录失败
2. 同时间段有 VPC Flow REJECT（可能是探测行为）
3. ALB 504 可能是另一个独立问题（需确认时间和 IP）

---

## 面试常见问题

### Q1: CloudTrail 里 ConsoleLogin 失败你关注哪些字段？

**期望回答**：
> - `sourceIPAddress`: 判断是否可疑来源
> - `mfaUsed`: 是否启用 MFA
> - `userAgent`: 识别攻击工具
> - `eventTime`: 建立时间线
> - `errorMessage`: 了解失败原因
> - `userIdentity.userName`: 被攻击的账户

**红旗回答**：
- 只看 eventName
- 不关注 IP 来源

### Q2: VPC Flow Log 的 REJECT 该如何定位到安全组？

**期望回答**：
> 1. 从日志获取 `eni-id`（如 `eni-abc`）
> 2. 在 EC2 Console 找到该 ENI
> 3. 查看关联的实例
> 4. 检查实例的 Security Group 规则
> 5. 确认是入站还是出站被拒绝

**红旗回答**：
- 直接改 SG 为 0.0.0.0/0
- 不追踪 ENI 来源

---

## 常见错误

1. **不会用 jq 解析 CloudTrail JSON**
   - CloudTrail 是嵌套 JSON，必须用 jq

2. **VPC Flow Log epoch 时间戳不会转换**
   - 使用 `date -d @timestamp`
   - 注意时区转换

3. **不关联 CloudTrail + VPC Flow + ALB 多源日志**
   - 单源日志往往不够
   - 需要多源关联建立完整视图

---

## 日志位置参考

| 日志类型 | 存储位置 | 格式 |
|---------|---------|------|
| CloudTrail | S3 bucket | JSON.gz |
| VPC Flow Log | CloudWatch Logs 或 S3 | 空格分隔 |
| ALB Access Log | S3 bucket | 空格分隔 |
| Lambda | CloudWatch Logs | 各语言格式 |

---

## 快速参考

| 需求 | 命令 |
|------|------|
| CloudTrail 失败事件 | `jq '.Records[] \| select(.errorCode != null)'` |
| CloudTrail 登录事件 | `jq '.Records[] \| select(.eventName == "ConsoleLogin")'` |
| VPC Flow REJECT | `awk '$13 == "REJECT"'` |
| VPC Flow epoch 转换 | `date -d @1719204722` |
| ALB 5xx 统计 | `awk '$9 ~ /^5/' alb.log` |
| 多字段提取 | `jq '{time: .eventTime, event: .eventName}'` |

---

## 下一步

- [05 · 故障时间线重建](../05-timeline-report/) - 跨系统、跨时区重建时间线 + 撰写障害報告書

## 系列导航 / Series Nav

| 课程 | 主题 |
|------|------|
| [00 · Linux 日志系统概览](../00-linux-logs/) | journalctl, dmesg, auth.log |
| [01 · 日志分析工具与模式识别](../01-tools-patterns/) | grep/rg/jq/less |
| [02 · systemd 服务日志分析](../02-systemd-logs/) | crash loop, timeout |
| [03 · Web 服务器日志](../03-web-server-logs/) | Nginx/Apache 5xx |
| **04 · AWS 日志实战** | 当前 |
| [05 · 故障时间线重建](../05-timeline-report/) | 障害報告書 |
| [06 · RCA 根因分析实战](../06-rca-practice/) | Five Whys |
