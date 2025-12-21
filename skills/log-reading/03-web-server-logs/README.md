# 03 · Web 服务器日志（Nginx/Apache 5xx spike, top IPs）

> **目标**：分析 Nginx/Apache access log 中的 5xx spike，识别 User-Agent 和 IP 分布异常  
> **前置**：[01 · 日志分析工具与模式识别](../01-tools-patterns/)  
> **区域**：任意（本课在本地/EC2 均可练习）  
> **费用**：无额外费用

## 将完成的内容

1. 理解 Nginx/Apache access log 格式
2. 分析 HTTP 状态码分布
3. 统计 Top IP 和 User-Agent
4. 识别 5xx spike 模式
5. 实战：定位 504 错误的触发源

---

## Access Log 格式解析

### Nginx Combined Log Format（默认）

```
10.0.3.21 - - [23/Jun/2024:14:05:10 +0900] "GET /api/users HTTP/1.1" 200 1234 "https://example.com/" "Mozilla/5.0..."
│         │ │  │                         │                          │   │    │                      │
│         │ │  │                         │                          │   │    │                      └─ User-Agent
│         │ │  │                         │                          │   │    └─ Referer
│         │ │  │                         │                          │   └─ Body bytes sent
│         │ │  │                         │                          └─ Status code
│         │ │  │                         └─ Request line
│         │ │  └─ Timestamp [日/月/年:时:分:秒 时区]
│         │ └─ Remote user (auth)
│         └─ Ident (usually -)
└─ Client IP
```

### 常用字段位置（awk）

| 字段 | awk 位置 | 内容 |
|------|---------|------|
| IP | `$1` | 客户端 IP |
| 时间 | `$4` | [23/Jun/2024:14:05:10 |
| 方法 | `$6` | "GET |
| URI | `$7` | /api/users |
| 状态码 | `$9` | 200 |
| 字节数 | `$10` | 1234 |

### Apache Common/Combined Log

格式与 Nginx 相似，主要区别在配置方式。

---

## 状态码统计分析

### 统计各状态码数量

```bash
# 统计状态码分布
awk '{print $9}' access.log | sort | uniq -c | sort -nr

# 输出示例：
#  45678 200
#   1234 304
#    567 404
#     89 502
#     45 504
```

### 计算错误率

```bash
# 总请求数
total=$(wc -l < access.log)

# 5xx 错误数
errors=$(awk '$9 ~ /^5/' access.log | wc -l)

# 错误率
echo "scale=4; $errors / $total * 100" | bc
# 输出: 0.3500 (0.35%)
```

### 按时间段统计

```bash
# 按小时统计请求数
awk '{print substr($4, 14, 2)}' access.log | sort | uniq -c

# 按分钟统计（找 spike）
awk '{print substr($4, 14, 5)}' access.log | sort | uniq -c | sort -k2

# 只统计 5xx 按分钟
awk '$9 ~ /^5/ {print substr($4, 14, 5)}' access.log | sort | uniq -c
```

---

## Top IP 统计 {#top-ip}

### 统计请求最多的 IP

```bash
# Top 10 IP
awk '{print $1}' access.log | sort | uniq -c | sort -nr | head -10

# 输出示例：
#  12345 10.0.3.21
#   8901 192.168.1.100
#   5678 203.0.113.50
```

### 只统计 5xx 错误的 IP

```bash
# 哪些 IP 产生最多 5xx
awk '$9 ~ /^5/ {print $1}' access.log | sort | uniq -c | sort -nr | head -10
```

### 区分内外网

```bash
# 外网 IP 请求统计（排除内网）
awk '{print $1}' access.log | \
  grep -v -E '^(10\.|172\.(1[6-9]|2[0-9]|3[01])\.|192\.168\.)' | \
  sort | uniq -c | sort -nr | head
```

---

## User-Agent 分析

### 统计 Top User-Agent

```bash
# 提取并统计 User-Agent（最后一个引号字段）
awk -F'"' '{print $6}' access.log | sort | uniq -c | sort -nr | head -10
```

### 识别特殊 UA

常见需要注意的 User-Agent：

| UA 特征 | 含义 |
|---------|------|
| `ELB-HealthChecker` | AWS ALB 健康检查 |
| `kube-probe` | Kubernetes 探针 |
| `Googlebot`, `bingbot` | 搜索引擎爬虫 |
| `curl/`, `wget/` | 命令行工具 |
| `Excel/` | Microsoft Excel 直接访问 |
| `python-requests` | Python 脚本 |

### 过滤健康检查

```bash
# 排除健康检查，只看真实用户请求
awk -F'"' '$6 !~ /HealthChecker|kube-probe/' access.log | \
  awk '{print $9}' | sort | uniq -c | sort -nr
```

---

## HTTP 错误码详解

### 5xx 错误区别

| 状态码 | 含义 | 常见原因 |
|--------|------|---------|
| **500** | Internal Server Error | 应用代码错误、未捕获异常 |
| **502** | Bad Gateway | upstream 连接失败、upstream 返回无效响应 |
| **503** | Service Unavailable | 服务过载、维护模式 |
| **504** | Gateway Timeout | upstream 响应超时 |

### 502 vs 504 的区别

```
502 Bad Gateway:
- Nginx 无法连接到 upstream（upstream 挂了）
- Upstream 返回无效响应

504 Gateway Timeout:
- Nginx 连接成功，但 upstream 响应太慢
- 超过 proxy_read_timeout 设置
```

---

## 时区注意事项

**重要**：日本环境日志时区处理！

```
[23/Jun/2024:14:05:10 +0900]   ← JST 时区
                      ^^^^^
                      +0900 = UTC+9 = 日本标准时间
```

### 时区转换

```bash
# JST 14:05 = UTC 05:05
# 因为 JST = UTC + 9

# 如果需要和 UTC 日志关联：
# 14:05 JST → 05:05 UTC
```

### 检查日志时区配置

```nginx
# Nginx 日志时区由 log_format 控制
# $time_local 使用系统时区
# $time_iso8601 使用 ISO 格式
log_format main '$remote_addr - $remote_user [$time_local] ...';
```

---

## 实战练习：定位 504 Spike 原因

### 场景描述

运维收到告警：「14:05 左右 504 错误激增」。需要分析原因。

### 日志样本

```
10.0.3.21 - - [23/Jun/2024:14:05:10 +0900] "GET /report/export.csv HTTP/1.1" 504 182 "-" "Excel/16.77"
10.0.3.21 - - [23/Jun/2024:14:05:12 +0900] "GET /report/export.csv HTTP/1.1" 504 182 "-" "Excel/16.77"
198.51.100.10 - - [23/Jun/2024:14:05:20 +0900] "GET /healthz HTTP/1.1" 200 2 "-" "ELB-HealthChecker/2.0"
```

### 分析步骤

**Step 1: 统计 14:05 时间段的状态码分布**

```bash
awk '$4 ~ /23\/Jun\/2024:14:05/' access.log | \
  awk '{print $9}' | sort | uniq -c | sort -nr
```

**Step 2: 找出 504 的请求路径**

```bash
awk '$9 == 504 {print $7}' access.log | sort | uniq -c | sort -nr | head
# 输出：
#   25 /report/export.csv
#    3 /api/orders
```

**Step 3: 分析触发 504 的 User-Agent**

```bash
awk '$9 == 504' access.log | \
  awk -F'"' '{print $6}' | sort | uniq -c | sort -nr
# 输出：
#   25 Excel/16.77
#    3 Mozilla/5.0...
```

**Step 4: 确认健康检查是否正常**

```bash
awk '$4 ~ /23\/Jun\/2024:14:05/ && $6 ~ /HealthChecker/' access.log | \
  awk '{print $9}' | sort | uniq -c
# 输出：
#   30 200   ← 健康检查全部正常
```

### 发现要点

| 层次 | 发现 |
|------|------|
| **显而易见** | 504 错误来自 `/report/export.csv` 请求 |
| **需要细看** | 时区 +0900 (JST)；Excel UA 触发大文件导出导致超时 |

### 根因分析

1. Excel 用户直接访问 `/report/export.csv`
2. 该接口生成大 CSV 文件，耗时超过 Nginx `proxy_read_timeout`
3. 健康检查正常，说明应用本身没挂

### 解决方案

```nginx
# 对特定路径增加超时时间
location /report/ {
    proxy_read_timeout 300s;  # 5 分钟
}
```

或优化应用：使用异步导出 + 下载链接。

---

## 面试常见问题

### Q1: Nginx 504 与 502 区别、常见原因？

**期望回答**：
> - 504 是 upstream timeout，Nginx 连接成功但 upstream 响应太慢
> - 502 是 upstream reset/bad gateway，Nginx 无法连接或收到无效响应
>
> 504 常见原因：数据库慢查询、大文件处理、外部 API 超时
> 502 常见原因：upstream 进程挂掉、端口未监听、连接数耗尽

**红旗回答**：
- 颠倒两者
- 只说「服务器错误」

### Q2: 如何用日志确认健康检查没问题但用户 5xx 激增？

**期望回答**：
> 过滤 User-Agent 为 `ELB-HealthChecker` 或 `kube-probe` 的请求，统计其状态码全是 200。
> 然后排除这些请求，统计真实用户的 5xx 分布。
> 这说明应用没完全挂，而是特定请求触发问题。

**红旗回答**：
- 只看平均值或总体错误率
- 不过滤健康检查

---

## 常见错误

1. **不过滤健康检查/爬虫，导致误判 5xx 比例**
   - 健康检查频率高，会稀释真实错误率

2. **忽略时区（+0900 JST vs UTC）**
   - 和其他系统日志关联时必须统一时区

3. **不分析 User-Agent 和请求路径**
   - 不同 UA/路径的错误模式可能完全不同

---

## 快速参考

| 需求 | 命令 |
|------|------|
| 状态码统计 | `awk '{print $9}' access.log \| sort \| uniq -c \| sort -nr` |
| Top IP | `awk '{print $1}' access.log \| sort \| uniq -c \| sort -nr \| head` |
| Top UA | `awk -F'"' '{print $6}' access.log \| sort \| uniq -c \| sort -nr \| head` |
| 5xx 错误 | `awk '$9 ~ /^5/' access.log` |
| 特定时间段 | `awk '$4 ~ /23\/Jun\/2024:14:0/' access.log` |
| 特定路径 | `awk '$7 ~ /\/api\//' access.log` |
| 排除健康检查 | `awk -F'"' '$6 !~ /HealthChecker/'` |

---

## 下一步

- [04 · AWS 日志实战](../04-aws-logs/) - CloudTrail, VPC Flow Log, ALB 日志关联

## 系列导航 / Series Nav

| 课程 | 主题 |
|------|------|
| [00 · Linux 日志系统概览](../00-linux-logs/) | journalctl, dmesg, auth.log |
| [01 · 日志分析工具与模式识别](../01-tools-patterns/) | grep/rg/jq/less |
| [02 · systemd 服务日志分析](../02-systemd-logs/) | crash loop, timeout |
| **03 · Web 服务器日志** | 当前 |
| [04 · AWS 日志实战](../04-aws-logs/) | CloudTrail, VPC Flow |
| [05 · 故障时间线重建](../05-timeline-report/) | 障害報告書 |
| [06 · RCA 根因分析实战](../06-rca-practice/) | Five Whys |
