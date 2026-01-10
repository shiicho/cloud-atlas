# 09 - 可观测性集成（Observability Integration）

> **目标**：配置 CloudWatch Agent 收集指标和日志，集成 journald，建立事故响应证据收集流程  
> **前置**：[08 - 镜像加固与供应链安全](../08-image-hardening/)、[LX03 - 文本处理](../../lx03-text-processing/)（日志分析基础）  
> **时间**：⚡ 40 分钟（速读）/ 🔬 150 分钟（完整实操）  
> **实战场景**：CloudWatch Agent 配置、证据保全（証跡保全）、紧急响应（緊急対応）  

---

## 将学到的内容

1. 安装和配置 CloudWatch Agent 收集指标和日志
2. 集成 journald 日志到 CloudWatch Logs
3. 创建和发送自定义指标
4. 理解云原生监控架构（CloudWatch vs Prometheus）
5. 建立事故响应的证据收集流程
6. 配置 SSM Session Manager 替代 SSH

---

## 先跑起来！（10 分钟）

> 在学习可观测性理论之前，先检查你的实例是否已经在"被观测"。  

在任意 EC2 实例上运行：

### 检查当前监控状态

```bash
# 检查 CloudWatch Agent 是否已安装
if command -v /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl &>/dev/null; then
    echo "CloudWatch Agent 已安装"
    /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a status
else
    echo "CloudWatch Agent 未安装"
fi

# 检查 SSM Agent 状态
echo ""
echo "=== SSM Agent 状态 ==="
systemctl status amazon-ssm-agent --no-pager | head -10

# 检查 journald 配置
echo ""
echo "=== journald 配置 ==="
journalctl --disk-usage
cat /etc/systemd/journald.conf | grep -v "^#" | grep -v "^$"

# 查看最近的系统日志
echo ""
echo "=== 最近 5 条系统日志 ==="
journalctl -n 5 --no-pager
```

**你应该看到类似这样的输出**：

```
CloudWatch Agent 未安装
（或）
CloudWatch Agent 已安装
status: running

=== SSM Agent 状态 ===
● amazon-ssm-agent.service - amazon-ssm-agent
     Active: active (running) since ...

=== journald 配置 ===
Archived and active journals take up 48.0M in the file system.
[Journal]
Storage=persistent

=== 最近 5 条系统日志 ===
Jan 10 10:30:01 ip-172-31-xx-xx systemd[1]: Started Session 42 of User ec2-user.
...
```

**关键发现**：
- 大多数 AWS AMI 预装了 SSM Agent，但不一定有 CloudWatch Agent
- journald 是现代 Linux 的日志核心，但日志默认不会离开实例
- 没有 CloudWatch Agent，AWS 控制台只能看到基础 CPU/网络指标

---

**你刚刚完成了监控状态检查。** 接下来我们将配置完整的可观测性栈，让你的实例"说话"。

---

## Step 1 - CloudWatch Agent 基础（30 分钟）

### 1.1 为什么需要 CloudWatch Agent？

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    EC2 指标收集层级                                           │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│   AWS 控制台默认指标（Hypervisor 层）                                        │
│   ─────────────────────────────────                                         │
│   ┌─────────────────────────────────────────────────────────────────────┐  │
│   │  ● CPUUtilization        ← Hypervisor 看到的 vCPU 使用率            │  │
│   │  ● NetworkIn/Out         ← VPC 网络层的流量                          │  │
│   │  ● DiskReadOps/WriteOps  ← EBS 层的 I/O 操作                        │  │
│   │  ● StatusCheckFailed     ← 实例和系统状态                            │  │
│   └─────────────────────────────────────────────────────────────────────┘  │
│                                                                             │
│   ❌ 看不到：                                                               │
│   ● 内存使用率（Linux 内核管理，Hypervisor 不可见）                         │
│   ● 磁盘空间使用率（文件系统层，EBS 不知道）                                │
│   ● 进程级 CPU 和内存                                                      │
│   ● 应用日志                                                               │
│                                                                             │
│   ─────────────────────────────────────────────────────────────────────    │
│                                                                             │
│   CloudWatch Agent（操作系统内部）                                          │
│   ─────────────────────────────                                             │
│   ┌─────────────────────────────────────────────────────────────────────┐  │
│   │  指标收集：                                                          │  │
│   │  ● mem_used_percent      ← /proc/meminfo                           │  │
│   │  ● disk_used_percent     ← df / statfs()                           │  │
│   │  ● cpu_usage_idle        ← /proc/stat                              │  │
│   │  ● processes_running     ← /proc/loadavg                           │  │
│   │  ● netstat_tcp_established ← /proc/net/tcp                         │  │
│   │                                                                     │  │
│   │  日志收集：                                                          │  │
│   │  ● /var/log/messages     → CloudWatch Logs                         │  │
│   │  ● /var/log/secure       → CloudWatch Logs                         │  │
│   │  ● journald              → CloudWatch Logs                         │  │
│   │  ● 应用日志              → CloudWatch Logs                         │  │
│   └─────────────────────────────────────────────────────────────────────┘  │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 1.2 安装 CloudWatch Agent

```bash
# 下载并安装 CloudWatch Agent（Amazon Linux 2023 / x86_64）
sudo dnf install -y amazon-cloudwatch-agent

# 或者手动下载
# wget https://amazoncloudwatch-agent.s3.amazonaws.com/amazon_linux/amd64/latest/amazon-cloudwatch-agent.rpm
# sudo rpm -U ./amazon-cloudwatch-agent.rpm

# 验证安装
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a status
```

### 1.3 配置文件结构

CloudWatch Agent 使用 JSON 配置文件：

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    CloudWatch Agent 配置结构                                  │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│   /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json        │
│                                                                             │
│   {                                                                         │
│     "agent": {                    ← 全局设置                                │
│       "metrics_collection_interval": 60,                                   │
│       "run_as_user": "cwagent"                                             │
│     },                                                                      │
│                                                                             │
│     "metrics": {                  ← 指标收集配置                            │
│       "namespace": "CWAgent",                                              │
│       "metrics_collected": {                                               │
│         "mem": { ... },          ← 内存指标                                │
│         "disk": { ... },         ← 磁盘指标                                │
│         "cpu": { ... }           ← CPU 指标                                │
│       }                                                                     │
│     },                                                                      │
│                                                                             │
│     "logs": {                     ← 日志收集配置                            │
│       "logs_collected": {                                                  │
│         "files": { ... },        ← 文件日志                                │
│         "journal": { ... }       ← journald 日志                           │
│       }                                                                     │
│     }                                                                       │
│   }                                                                         │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 1.4 基础配置示例

```bash
# 创建配置目录
sudo mkdir -p /opt/aws/amazon-cloudwatch-agent/etc

# 创建基础配置
sudo tee /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json << 'EOF'
{
  "agent": {
    "metrics_collection_interval": 60,
    "run_as_user": "cwagent",
    "logfile": "/opt/aws/amazon-cloudwatch-agent/logs/amazon-cloudwatch-agent.log"
  },
  "metrics": {
    "namespace": "CWAgent",
    "append_dimensions": {
      "InstanceId": "${aws:InstanceId}",
      "AutoScalingGroupName": "${aws:AutoScalingGroupName}"
    },
    "metrics_collected": {
      "mem": {
        "measurement": [
          "mem_used_percent",
          "mem_available_percent"
        ],
        "metrics_collection_interval": 60
      },
      "disk": {
        "measurement": [
          "disk_used_percent",
          "disk_free"
        ],
        "metrics_collection_interval": 60,
        "resources": [
          "/"
        ],
        "ignore_file_system_types": [
          "tmpfs",
          "devtmpfs"
        ]
      },
      "cpu": {
        "measurement": [
          "cpu_usage_idle",
          "cpu_usage_user",
          "cpu_usage_system"
        ],
        "metrics_collection_interval": 60,
        "totalcpu": true
      }
    }
  },
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/messages",
            "log_group_name": "/ec2/var/log/messages",
            "log_stream_name": "{instance_id}",
            "timezone": "UTC"
          },
          {
            "file_path": "/var/log/secure",
            "log_group_name": "/ec2/var/log/secure",
            "log_stream_name": "{instance_id}",
            "timezone": "UTC"
          }
        ]
      }
    }
  }
}
EOF

# 验证配置
cat /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json | python3 -m json.tool
```

### 1.5 启动 Agent

```bash
# 应用配置并启动
sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config \
  -m ec2 \
  -s \
  -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json

# 检查状态
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a status

# 查看日志
sudo tail -20 /opt/aws/amazon-cloudwatch-agent/logs/amazon-cloudwatch-agent.log
```

### 1.6 IAM 权限要求

CloudWatch Agent 需要 IAM 权限才能发送数据：

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "cloudwatch:PutMetricData",
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogGroups",
        "logs:DescribeLogStreams"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "ec2:DescribeTags"
      ],
      "Resource": "*"
    }
  ]
}
```

> **提示**：AWS 提供托管策略 `CloudWatchAgentServerPolicy`，可直接附加到实例角色。  

---

## Step 2 - 日志导出配置（25 分钟）

### 2.1 journald 集成

现代 Linux 使用 systemd-journald 作为日志核心。CloudWatch Agent 可以直接读取 journald：

```bash
# 修改配置，添加 journald 收集
sudo tee /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json << 'EOF'
{
  "agent": {
    "metrics_collection_interval": 60,
    "run_as_user": "cwagent"
  },
  "metrics": {
    "namespace": "CWAgent",
    "append_dimensions": {
      "InstanceId": "${aws:InstanceId}"
    },
    "metrics_collected": {
      "mem": {
        "measurement": ["mem_used_percent"]
      },
      "disk": {
        "measurement": ["disk_used_percent"],
        "resources": ["/"]
      }
    }
  },
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/messages",
            "log_group_name": "/ec2/var/log/messages",
            "log_stream_name": "{instance_id}"
          }
        ]
      },
      "journal": {
        "log_group_name": "/ec2/journald",
        "log_stream_name": "{instance_id}",
        "retention_in_days": 7
      }
    }
  }
}
EOF

# 重新加载配置
sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config \
  -m ec2 \
  -s \
  -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json
```

### 2.2 日志格式和解析

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    日志格式处理                                               │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│   原始日志（/var/log/messages）：                                            │
│   Jan 10 10:30:01 ip-172-31-1-100 systemd[1]: Started Session 42.          │
│                                                                             │
│   CloudWatch Logs 存储：                                                     │
│   {                                                                         │
│     "timestamp": 1704884001000,                                            │
│     "message": "Jan 10 10:30:01 ip-172-31-1-100 systemd[1]: Started..."    │
│   }                                                                         │
│                                                                             │
│   ─────────────────────────────────────────────────────────────────────    │
│                                                                             │
│   结构化日志（JSON 格式应用日志）：                                           │
│   {"time":"2025-01-10T10:30:01Z","level":"INFO","msg":"Request handled"}   │
│                                                                             │
│   CloudWatch Logs Insights 查询：                                            │
│   fields @timestamp, @message                                              │
│   | filter level = "ERROR"                                                 │
│   | sort @timestamp desc                                                   │
│   | limit 100                                                              │
│                                                                             │
│   ─────────────────────────────────────────────────────────────────────    │
│                                                                             │
│   最佳实践：                                                                 │
│   ● 应用日志使用 JSON 格式，便于查询和分析                                    │
│   ● 系统日志保持原格式，使用时间戳过滤                                        │
│   ● 设置日志组保留期限，控制成本                                              │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 2.3 避免日志轮转冲突

```bash
# 问题：logrotate 和 CloudWatch Agent 可能冲突
# CloudWatch Agent 跟踪文件位置，轮转后可能丢失日志

# 解决方案 1：使用 copytruncate（推荐）
cat /etc/logrotate.d/messages
# 确保包含：copytruncate

# 解决方案 2：配置 Agent 跟踪轮转
# 在配置中添加：
# "auto_removal": true,
# "retention_in_days": 7

# 检查 logrotate 配置
cat /etc/logrotate.d/syslog
```

### 2.4 rsyslog 转发（备选方案）

如果需要更精细的日志控制，可以使用 rsyslog：

```bash
# /etc/rsyslog.d/cloudwatch.conf 示例
# （通过 rsyslog 预处理后再发送）

# 这种方式适用于：
# - 需要实时过滤敏感信息
# - 需要日志聚合后再发送
# - 需要支持多目标（CloudWatch + SIEM）

# 大多数情况下，直接使用 CloudWatch Agent 即可
```

---

## Step 3 - 自定义指标（20 分钟）

### 3.1 使用 Agent 收集自定义指标

CloudWatch Agent 支持 StatsD 和 collectd 协议接收自定义指标：

```bash
# 修改配置，启用 StatsD
sudo tee /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json << 'EOF'
{
  "agent": {
    "metrics_collection_interval": 60,
    "run_as_user": "cwagent"
  },
  "metrics": {
    "namespace": "CWAgent",
    "append_dimensions": {
      "InstanceId": "${aws:InstanceId}"
    },
    "metrics_collected": {
      "mem": {
        "measurement": ["mem_used_percent"]
      },
      "disk": {
        "measurement": ["disk_used_percent"],
        "resources": ["/"]
      },
      "statsd": {
        "service_address": ":8125",
        "metrics_collection_interval": 60,
        "metrics_aggregation_interval": 60
      }
    }
  },
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/messages",
            "log_group_name": "/ec2/var/log/messages",
            "log_stream_name": "{instance_id}"
          }
        ]
      }
    }
  }
}
EOF

# 重启 Agent
sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config -m ec2 -s \
  -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json
```

### 3.2 发送自定义指标

```bash
# 方法 1：通过 StatsD 协议
# 安装 netcat（如果没有）
sudo dnf install -y nc

# 发送计数器指标
echo "myapp.requests.count:1|c" | nc -u -w 1 127.0.0.1 8125

# 发送计量指标
echo "myapp.response.time:235|ms" | nc -u -w 1 127.0.0.1 8125

# 发送仪表指标
echo "myapp.queue.size:42|g" | nc -u -w 1 127.0.0.1 8125
```

```bash
# 方法 2：通过 AWS CLI 直接发送（需要 IAM 权限）
aws cloudwatch put-metric-data \
  --namespace "MyApplication" \
  --metric-name "ActiveConnections" \
  --value 42 \
  --unit Count \
  --dimensions "InstanceId=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)"

# 发送多个指标
aws cloudwatch put-metric-data \
  --namespace "MyApplication" \
  --metric-data '[
    {
      "MetricName": "RequestCount",
      "Value": 150,
      "Unit": "Count"
    },
    {
      "MetricName": "ErrorRate",
      "Value": 0.02,
      "Unit": "Percent"
    }
  ]'
```

### 3.3 高基数维度陷阱

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    高基数维度陷阱（Cardinality Trap）                          │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│   ❌ 错误做法：使用高基数维度                                                 │
│   ─────────────────────────────────                                         │
│   aws cloudwatch put-metric-data \                                         │
│     --dimensions "UserId=user-12345" \   ← 每个用户一个维度组合！           │
│     --metric-name "RequestLatency" \                                       │
│     --value 150                                                            │
│                                                                             │
│   问题：                                                                    │
│   ● 100,000 用户 = 100,000 个时间序列                                       │
│   ● CloudWatch 按指标数量计费                                               │
│   ● 账单可能爆炸                                                            │
│                                                                             │
│   ─────────────────────────────────────────────────────────────────────    │
│                                                                             │
│   ✓ 正确做法：使用低基数维度                                                 │
│   ─────────────────────────────────                                         │
│   aws cloudwatch put-metric-data \                                         │
│     --dimensions "Environment=prod,Service=api" \                          │
│     --metric-name "RequestLatency" \                                       │
│     --value 150                                                            │
│                                                                             │
│   合理的维度：                                                               │
│   ● Environment: prod, staging, dev （3 个）                               │
│   ● Service: api, web, worker （少量）                                     │
│   ● Region: us-east-1, ap-northeast-1 （有限）                             │
│   ● InstanceId: 仅用于调试，生产环境谨慎                                    │
│                                                                             │
│   总组合数 = 3 × 3 × 2 = 18 个时间序列 ✓                                   │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Step 4 - 云监控架构（20 分钟）

### 4.1 CloudWatch vs Prometheus

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    监控架构对比                                               │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│   CloudWatch（Push 模型）                                                    │
│   ─────────────────────                                                     │
│   ┌─────────┐                   ┌─────────────────┐                        │
│   │ Instance│──► CloudWatch ──► │  CloudWatch     │                        │
│   │ + Agent │    Agent Push     │  (AWS Managed)  │                        │
│   └─────────┘                   └─────────────────┘                        │
│                                                                             │
│   优点：                        缺点：                                       │
│   ● 无需管理监控基础设施        ● 查询语言不如 PromQL 强大                   │
│   ● 与 AWS 服务深度集成         ● 高基数指标成本高                           │
│   ● 自动扩展                    ● 1 分钟最小粒度（标准）                     │
│                                                                             │
│   ─────────────────────────────────────────────────────────────────────    │
│                                                                             │
│   Prometheus（Pull 模型）                                                    │
│   ─────────────────────                                                     │
│   ┌─────────┐                   ┌─────────────────┐                        │
│   │ Instance│◄── Prometheus ──► │  Prometheus     │                        │
│   │ Exporter│    Scrape         │  Server         │                        │
│   └─────────┘                   └─────────────────┘                        │
│                                                                             │
│   优点：                        缺点：                                       │
│   ● PromQL 强大查询语言         ● 需要管理 Prometheus 服务器                 │
│   ● 高基数友好                  ● 需要服务发现配置                           │
│   ● 15 秒粒度                   ● 存储管理                                   │
│                                                                             │
│   ─────────────────────────────────────────────────────────────────────    │
│                                                                             │
│   推荐架构（混合）：                                                         │
│   ┌─────────────────────────────────────────────────────────────────────┐  │
│   │                                                                     │  │
│   │  AWS 原生指标 ──────► CloudWatch                                    │  │
│   │  (EC2, RDS, ALB)      (告警、仪表板)                                 │  │
│   │                                                                     │  │
│   │  应用指标 ──────────► Prometheus / CloudWatch                       │  │
│   │  (高基数)             (取决于规模和预算)                             │  │
│   │                                                                     │  │
│   │  日志 ─────────────► CloudWatch Logs                               │  │
│   │                       (集中存储、Insights 查询)                      │  │
│   │                                                                     │  │
│   └─────────────────────────────────────────────────────────────────────┘  │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 4.2 告警配置

```bash
# 创建 CPU 告警
aws cloudwatch put-metric-alarm \
  --alarm-name "HighCPU-$(hostname)" \
  --alarm-description "CPU utilization exceeds 80%" \
  --metric-name CPUUtilization \
  --namespace AWS/EC2 \
  --statistic Average \
  --period 300 \
  --threshold 80 \
  --comparison-operator GreaterThanThreshold \
  --evaluation-periods 2 \
  --dimensions Name=InstanceId,Value=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)

# 创建内存告警（需要 CloudWatch Agent）
aws cloudwatch put-metric-alarm \
  --alarm-name "HighMemory-$(hostname)" \
  --alarm-description "Memory utilization exceeds 90%" \
  --metric-name mem_used_percent \
  --namespace CWAgent \
  --statistic Average \
  --period 300 \
  --threshold 90 \
  --comparison-operator GreaterThanThreshold \
  --evaluation-periods 2 \
  --dimensions Name=InstanceId,Value=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)

# 列出告警
aws cloudwatch describe-alarms \
  --alarm-name-prefix "High" \
  --query 'MetricAlarms[].{Name:AlarmName,State:StateValue}' \
  --output table
```

---

## Step 5 - 事故响应集成（25 分钟）

### 5.1 SSM Run Command 诊断

当出现问题时，可以使用 SSM Run Command 批量执行诊断命令：

```bash
# 在单个实例上运行诊断
INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)

aws ssm send-command \
  --instance-ids "$INSTANCE_ID" \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=[
    "echo === System Info ===",
    "uname -a",
    "uptime",
    "echo === Memory ===",
    "free -h",
    "echo === Disk ===",
    "df -h",
    "echo === Top Processes ===",
    "ps aux --sort=-%mem | head -10"
  ]' \
  --output-s3-bucket-name "your-bucket" \
  --output-s3-key-prefix "diagnostics" \
  --query 'Command.CommandId' \
  --output text

# 获取命令结果
COMMAND_ID="your-command-id"
aws ssm get-command-invocation \
  --command-id "$COMMAND_ID" \
  --instance-id "$INSTANCE_ID" \
  --query 'StandardOutputContent' \
  --output text
```

### 5.2 证据保全脚本

```bash
# 创建证据收集脚本
cat > /tmp/evidence-collection.sh << 'EOF'
#!/bin/bash
# Evidence Collection Script (証跡収集スクリプト)
# Run before any recovery action (reboot, restart, etc.)

set -e

TIMESTAMP=$(date +%Y%m%d%H%M%S)
INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id 2>/dev/null || hostname)
EVIDENCE_DIR="/tmp/evidence-${INSTANCE_ID}-${TIMESTAMP}"

echo "=== Evidence Collection Started at $(date -Iseconds) ==="
echo "Evidence Directory: ${EVIDENCE_DIR}"

mkdir -p "${EVIDENCE_DIR}"

# System Information
echo "Collecting system information..."
{
  echo "=== Hostname ==="
  hostname
  echo ""
  echo "=== Uptime ==="
  uptime
  echo ""
  echo "=== Kernel ==="
  uname -a
  echo ""
  echo "=== OS Release ==="
  cat /etc/os-release
} > "${EVIDENCE_DIR}/system-info.txt"

# Process Information
echo "Collecting process information..."
{
  echo "=== Process List (sorted by CPU) ==="
  ps aux --sort=-%cpu | head -50
  echo ""
  echo "=== Process List (sorted by Memory) ==="
  ps aux --sort=-%mem | head -50
  echo ""
  echo "=== Process Tree ==="
  ps axjf | head -100
} > "${EVIDENCE_DIR}/processes.txt"

# Memory Information
echo "Collecting memory information..."
{
  echo "=== Memory Summary ==="
  free -h
  echo ""
  echo "=== Memory Details ==="
  cat /proc/meminfo
  echo ""
  echo "=== Swap ==="
  swapon -s
} > "${EVIDENCE_DIR}/memory.txt"

# Disk Information
echo "Collecting disk information..."
{
  echo "=== Disk Usage ==="
  df -h
  echo ""
  echo "=== Block Devices ==="
  lsblk
  echo ""
  echo "=== Mount Points ==="
  mount
  echo ""
  echo "=== IO Statistics ==="
  iostat -x 1 3 2>/dev/null || echo "iostat not available"
} > "${EVIDENCE_DIR}/disk.txt"

# Network Information
echo "Collecting network information..."
{
  echo "=== Network Interfaces ==="
  ip addr
  echo ""
  echo "=== Routing Table ==="
  ip route
  echo ""
  echo "=== Listening Ports ==="
  ss -tulpn
  echo ""
  echo "=== Established Connections ==="
  ss -tupn state established
  echo ""
  echo "=== Connection Statistics ==="
  ss -s
} > "${EVIDENCE_DIR}/network.txt"

# Service Status
echo "Collecting service status..."
{
  echo "=== Failed Services ==="
  systemctl --failed
  echo ""
  echo "=== All Services Status ==="
  systemctl list-units --type=service --all
} > "${EVIDENCE_DIR}/services.txt"

# Recent Logs
echo "Collecting recent logs..."
{
  echo "=== Last 500 lines of journald ==="
  journalctl -n 500 --no-pager
} > "${EVIDENCE_DIR}/journal.txt"

{
  echo "=== dmesg (kernel messages) ==="
  dmesg -T | tail -500
} > "${EVIDENCE_DIR}/dmesg.txt"

# Resource Limits
echo "Collecting resource limits..."
{
  echo "=== System Limits ==="
  ulimit -a
  echo ""
  echo "=== Open Files Count ==="
  cat /proc/sys/fs/file-nr
  echo ""
  echo "=== Per-Process Open Files ==="
  lsof 2>/dev/null | awk '{print $1}' | sort | uniq -c | sort -rn | head -20
} > "${EVIDENCE_DIR}/limits.txt" 2>/dev/null || true

# Create archive
echo "Creating archive..."
ARCHIVE_NAME="evidence-${INSTANCE_ID}-${TIMESTAMP}.tar.gz"
tar -czf "/tmp/${ARCHIVE_NAME}" -C /tmp "evidence-${INSTANCE_ID}-${TIMESTAMP}"

echo ""
echo "=== Evidence Collection Completed ==="
echo "Archive: /tmp/${ARCHIVE_NAME}"
echo "Size: $(du -h /tmp/${ARCHIVE_NAME} | cut -f1)"

# Upload to S3 (if bucket is configured)
if [ -n "${EVIDENCE_BUCKET}" ]; then
  echo "Uploading to S3: s3://${EVIDENCE_BUCKET}/evidence/${ARCHIVE_NAME}"
  aws s3 cp "/tmp/${ARCHIVE_NAME}" "s3://${EVIDENCE_BUCKET}/evidence/${ARCHIVE_NAME}"
  echo "Upload completed"
fi

echo ""
echo "Evidence collection completed at $(date -Iseconds)"
EOF

chmod +x /tmp/evidence-collection.sh

# 运行脚本
# EVIDENCE_BUCKET=your-bucket /tmp/evidence-collection.sh
```

### 5.3 重启前检查清单

```bash
# 创建重启前检查脚本
cat > /tmp/pre-reboot-checklist.sh << 'EOF'
#!/bin/bash
# Pre-Reboot Checklist (再起動前チェックリスト)
# Must complete before any reboot operation

echo "=============================================="
echo "  PRE-REBOOT CHECKLIST"
echo "  再起動前チェックリスト"
echo "=============================================="
echo ""

PASS=0
FAIL=0

check() {
  local description="$1"
  local command="$2"

  printf "%-50s" "$description"
  if eval "$command" > /dev/null 2>&1; then
    echo "[PASS]"
    ((PASS++))
  else
    echo "[FAIL]"
    ((FAIL++))
  fi
}

echo "=== 1. Evidence Collection (証跡収集) ==="
check "Evidence script exists" "[ -f /tmp/evidence-collection.sh ]"
check "Evidence collected today" "ls /tmp/evidence-*.tar.gz 2>/dev/null | head -1"
echo ""

echo "=== 2. Snapshot Verification (スナップショット確認) ==="
# In real scenario, check if recent snapshot exists
check "Root volume accessible" "df -h / > /dev/null"
echo "NOTE: Manually verify EBS snapshot was taken"
echo ""

echo "=== 3. Service Status (サービス状態) ==="
check "No failed services" "[ $(systemctl --failed --no-legend | wc -l) -eq 0 ]"
check "SSM Agent running" "systemctl is-active amazon-ssm-agent"
check "CloudWatch Agent running" "/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a status 2>/dev/null | grep -q running" || true
echo ""

echo "=== 4. Configuration Validation (設定検証) ==="
check "SSH config valid" "sshd -t"
check "fstab syntax valid" "mount -fav"
echo ""

echo "=== 5. Communication (連絡確認) ==="
echo "NOTE: Manually confirm:"
echo "  - [ ] Stakeholders notified (関係者への連絡)"
echo "  - [ ] Maintenance window approved (メンテナンスウィンドウ承認)"
echo "  - [ ] Rollback plan documented (ロールバック手順書)"
echo ""

echo "=============================================="
echo "Results: PASS=$PASS, FAIL=$FAIL"
echo "=============================================="

if [ $FAIL -gt 0 ]; then
  echo ""
  echo "WARNING: Some checks failed. Review before proceeding."
  exit 1
fi
EOF

chmod +x /tmp/pre-reboot-checklist.sh
/tmp/pre-reboot-checklist.sh
```

---

## Lab 1 - CloudWatch Agent 配置（30 分钟）

### 实验目标

完整配置 CloudWatch Agent，收集系统指标和日志。

### 前提条件

- EC2 实例附加了包含 `CloudWatchAgentServerPolicy` 的 IAM 角色
- 实例可以访问 CloudWatch 端点（VPC 内需要 NAT 或 VPC Endpoint）

### Step 1 - 安装 Agent

```bash
# 安装 CloudWatch Agent
sudo dnf install -y amazon-cloudwatch-agent

# 验证安装
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent --version
```

### Step 2 - 创建配置

```bash
# 创建完整配置
sudo tee /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json << 'EOF'
{
  "agent": {
    "metrics_collection_interval": 60,
    "run_as_user": "cwagent",
    "logfile": "/opt/aws/amazon-cloudwatch-agent/logs/amazon-cloudwatch-agent.log"
  },
  "metrics": {
    "namespace": "CWAgent",
    "append_dimensions": {
      "InstanceId": "${aws:InstanceId}"
    },
    "aggregation_dimensions": [["InstanceId"]],
    "metrics_collected": {
      "mem": {
        "measurement": [
          "mem_used_percent",
          "mem_available_percent",
          "mem_used",
          "mem_available"
        ],
        "metrics_collection_interval": 60
      },
      "disk": {
        "measurement": [
          "disk_used_percent",
          "disk_free",
          "disk_used"
        ],
        "metrics_collection_interval": 60,
        "resources": ["/"],
        "ignore_file_system_types": ["tmpfs", "devtmpfs", "squashfs"]
      },
      "cpu": {
        "measurement": [
          "cpu_usage_idle",
          "cpu_usage_user",
          "cpu_usage_system",
          "cpu_usage_iowait"
        ],
        "metrics_collection_interval": 60,
        "totalcpu": true
      },
      "diskio": {
        "measurement": [
          "reads",
          "writes",
          "read_bytes",
          "write_bytes"
        ],
        "metrics_collection_interval": 60,
        "resources": ["*"]
      },
      "netstat": {
        "measurement": [
          "tcp_established",
          "tcp_time_wait"
        ],
        "metrics_collection_interval": 60
      }
    }
  },
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/messages",
            "log_group_name": "/ec2/messages",
            "log_stream_name": "{instance_id}",
            "timezone": "UTC",
            "retention_in_days": 7
          },
          {
            "file_path": "/var/log/secure",
            "log_group_name": "/ec2/secure",
            "log_stream_name": "{instance_id}",
            "timezone": "UTC",
            "retention_in_days": 30
          },
          {
            "file_path": "/opt/aws/amazon-cloudwatch-agent/logs/amazon-cloudwatch-agent.log",
            "log_group_name": "/ec2/cloudwatch-agent",
            "log_stream_name": "{instance_id}",
            "timezone": "UTC",
            "retention_in_days": 3
          }
        ]
      }
    }
  }
}
EOF

# 验证 JSON 语法
cat /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json | python3 -m json.tool > /dev/null && echo "JSON syntax valid"
```

### Step 3 - 启动并验证

```bash
# 加载配置并启动
sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config \
  -m ec2 \
  -s \
  -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json

# 检查状态
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a status

# 查看日志
sudo tail -20 /opt/aws/amazon-cloudwatch-agent/logs/amazon-cloudwatch-agent.log

# 验证指标发送（等待 1-2 分钟后）
aws cloudwatch list-metrics \
  --namespace CWAgent \
  --query 'Metrics[?MetricName==`mem_used_percent`].{Name:MetricName,Dimensions:Dimensions}' \
  --output table

# 验证日志组创建
aws logs describe-log-groups \
  --log-group-name-prefix "/ec2/" \
  --query 'logGroups[].logGroupName' \
  --output table
```

### 检查清单

- [ ] CloudWatch Agent 安装成功
- [ ] 配置文件语法正确
- [ ] Agent 状态为 running
- [ ] CloudWatch 中可以看到 CWAgent 命名空间的指标
- [ ] CloudWatch Logs 中可以看到日志组

---

## Lab 2 - Evidence Preservation 场景（証跡保全）（30 分钟）

### 场景描述

> 你是一个日本企业的基础设施工程师。生产服务器出现高 CPU 告警，服务响应变慢。  
> 运营团队想立即重启恢复服务，但公司要求进行「原因究明」（根因分析）。  
> 你需要在重启前收集所有必要的证据。  

### 学习目标

- 在恢复操作前收集系统状态证据
- 创建可审计的证据存档
- 建立标准化的事故响应流程

### Step 1 - 模拟高负载场景

```bash
# 创建 CPU 负载（后台运行）
for i in {1..2}; do
  dd if=/dev/zero of=/dev/null bs=1M &
done

# 创建内存压力（分配 200MB）
stress-ng --vm 1 --vm-bytes 200M --timeout 300 &

# 如果没有 stress-ng，用这个替代
# python3 -c "x = 'A' * (200 * 1024 * 1024); import time; time.sleep(300)" &

# 查看负载
uptime
top -bn1 | head -15
```

### Step 2 - 收集证据

```bash
# 运行证据收集脚本
cat > /tmp/evidence-collection.sh << 'SCRIPT'
#!/bin/bash
# Evidence Collection for Incident Response

TIMESTAMP=$(date +%Y%m%d%H%M%S)
INSTANCE_ID=$(curl -s --connect-timeout 2 http://169.254.169.254/latest/meta-data/instance-id 2>/dev/null || hostname)
EVIDENCE_DIR="/tmp/evidence-${INSTANCE_ID}-${TIMESTAMP}"

echo "=== Starting Evidence Collection ==="
echo "Time: $(date -Iseconds)"
echo "Instance: ${INSTANCE_ID}"
echo ""

mkdir -p "${EVIDENCE_DIR}"

# Collect evidence
echo "1. Collecting system info..."
{
  echo "=== Timestamp ==="
  date -Iseconds
  echo ""
  echo "=== Hostname ==="
  hostname
  echo ""
  echo "=== Uptime ==="
  uptime
  echo ""
  echo "=== Load Average ==="
  cat /proc/loadavg
} > "${EVIDENCE_DIR}/01-system.txt"

echo "2. Collecting process info..."
{
  echo "=== Top CPU Processes ==="
  ps aux --sort=-%cpu | head -20
  echo ""
  echo "=== Top Memory Processes ==="
  ps aux --sort=-%mem | head -20
} > "${EVIDENCE_DIR}/02-processes.txt"

echo "3. Collecting memory info..."
{
  echo "=== Memory Summary ==="
  free -h
  echo ""
  echo "=== /proc/meminfo ==="
  cat /proc/meminfo
} > "${EVIDENCE_DIR}/03-memory.txt"

echo "4. Collecting disk info..."
{
  echo "=== Disk Usage ==="
  df -h
  echo ""
  echo "=== Block Devices ==="
  lsblk
} > "${EVIDENCE_DIR}/04-disk.txt"

echo "5. Collecting network info..."
{
  echo "=== Network Connections ==="
  ss -tulpn
  echo ""
  echo "=== Connection Summary ==="
  ss -s
} > "${EVIDENCE_DIR}/05-network.txt"

echo "6. Collecting logs..."
journalctl -n 200 --no-pager > "${EVIDENCE_DIR}/06-journal.txt"
dmesg -T | tail -100 > "${EVIDENCE_DIR}/07-dmesg.txt"

# Create archive
ARCHIVE="/tmp/evidence-${INSTANCE_ID}-${TIMESTAMP}.tar.gz"
tar -czf "${ARCHIVE}" -C /tmp "evidence-${INSTANCE_ID}-${TIMESTAMP}"

echo ""
echo "=== Evidence Collection Complete ==="
echo "Archive: ${ARCHIVE}"
echo "Size: $(du -h ${ARCHIVE} | cut -f1)"
echo ""
echo "Contents:"
tar -tzf "${ARCHIVE}"
SCRIPT

chmod +x /tmp/evidence-collection.sh
/tmp/evidence-collection.sh
```

### Step 3 - 上传证据到 S3

```bash
# 查找证据文件
EVIDENCE_FILE=$(ls -t /tmp/evidence-*.tar.gz | head -1)
echo "Evidence file: ${EVIDENCE_FILE}"

# 上传到 S3（需要配置 bucket）
# aws s3 cp "${EVIDENCE_FILE}" s3://your-evidence-bucket/incidents/

# 或者查看本地证据
tar -tzf "${EVIDENCE_FILE}"
tar -xzf "${EVIDENCE_FILE}" -C /tmp --strip-components=0
ls -la /tmp/evidence-*/
```

### Step 4 - 清理测试负载

```bash
# 停止测试负载
pkill -f "dd if=/dev/zero"
pkill -f "stress-ng"

# 验证负载恢复
sleep 2
uptime
```

### 检查清单

- [ ] 能识别系统负载异常
- [ ] 能运行证据收集脚本
- [ ] 证据存档创建成功
- [ ] 理解证据保全的重要性
- [ ] 知道何时可以进行恢复操作

---

## Lab 3 - Break-Glass Procedure 场景（緊急対応）（25 分钟）

### 场景描述

> 公司安全策略要求生产服务器禁用 SSH（Port 22）。  
> 开发者需要访问服务器调试一个崩溃的应用。  
> 你需要使用 SSM Session Manager 提供访问，同时确保所有操作被审计记录。  

### 学习目标

- 配置 SSM Session Manager 作为 SSH 替代方案
- 理解为什么 SSM 比传统 SSH 更安全
- 启用会话日志记录用于审计

### Step 1 - 验证 SSM Agent

```bash
# 检查 SSM Agent 状态
systemctl status amazon-ssm-agent --no-pager

# 如果未运行，启动它
sudo systemctl start amazon-ssm-agent
sudo systemctl enable amazon-ssm-agent

# 验证实例已注册到 SSM
aws ssm describe-instance-information \
  --query 'InstanceInformationList[].{Id:InstanceId,Status:PingStatus,Agent:AgentVersion}' \
  --output table
```

### Step 2 - 理解 SSM vs SSH 的安全优势

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    SSM Session Manager vs SSH 对比                           │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│   安全方面                SSH                    SSM Session Manager        │
│   ─────────────────────────────────────────────────────────────────────    │
│   入站端口              需要开放 22              不需要开放任何端口          │
│   密钥管理              PEM 文件、~/.ssh         IAM 身份验证               │
│   堡垒机                通常需要                 不需要                     │
│   审计日志              需要额外配置              内置，可发送到 S3/CW Logs  │
│   会话记录              需要额外工具              内置录制功能               │
│   访问控制              OS 级别                  IAM 策略细粒度控制         │
│   网络要求              可达 TCP 22             HTTPS 出站（VPC Endpoint） │
│                                                                             │
│   ─────────────────────────────────────────────────────────────────────    │
│                                                                             │
│   工作流程对比：                                                             │
│                                                                             │
│   SSH 方式：                                                                │
│   用户 ─► 堡垒机 ─► (Port 22) ─► 目标实例                                   │
│          需要 PEM 密钥                                                      │
│                                                                             │
│   SSM 方式：                                                                │
│   用户 ─► AWS Console/CLI ─► (HTTPS) ─► SSM ─► 目标实例                    │
│          IAM 身份验证，无需密钥                                             │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Step 3 - 通过 CLI 启动 Session

```bash
# 获取实例 ID
INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
echo "Instance ID: ${INSTANCE_ID}"

# 通过 AWS CLI 启动会话（从另一台机器或 CloudShell）
# aws ssm start-session --target ${INSTANCE_ID}

# 或者使用 AWS Console:
# EC2 → Instances → Select Instance → Connect → Session Manager
```

### Step 4 - 配置会话日志（可选，需要管理员权限）

```bash
# 查看 SSM 文档设置
aws ssm describe-document \
  --name "SSM-SessionManagerRunShell" \
  --query 'Document.Content' \
  --output text 2>/dev/null | python3 -m json.tool || echo "使用默认配置"

# 会话日志可以配置到：
# - S3 Bucket
# - CloudWatch Logs
# - 两者都启用

# 配置示例（需要通过 AWS Console 或 Terraform）
# Settings → Session Manager → Preferences
# - S3 bucket name: your-session-logs-bucket
# - CloudWatch log group: /aws/ssm/sessions
# - Enable encryption
```

### Step 5 - 紧急访问 SOP

```bash
# 创建紧急访问标准操作流程（SOP）文档
cat > /tmp/break-glass-sop.md << 'EOF'
# 緊急アクセス手順書 (Break-Glass Procedure SOP)

## 適用シナリオ
- SSH (Port 22) が無効化されている本番サーバー
- 緊急のトラブルシューティングが必要
- 通常のデプロイプロセスでは対応できない

## 前提条件
- [ ] SSM Agent が対象インスタンスで実行中
- [ ] IAM ポリシーに ssm:StartSession 権限あり
- [ ] インスタンスが SSM に登録済み

## 手順

### 1. アクセス申請（必須）
- 申請者: ____________
- 承認者: ____________
- 対象インスタンス: ____________
- 理由: ____________
- 予定作業時間: ____________

### 2. セッション開始
```bash
aws ssm start-session --target <instance-id>
```

### 3. 作業記録
- 実行したコマンドは自動的に CloudWatch Logs に記録される
- 重要な操作は手動でもメモを残す

### 4. セッション終了
```bash
exit
```

### 5. 事後報告
- [ ] 作業内容の報告書作成
- [ ] セッションログの確認
- [ ] 必要に応じて変更管理チケット作成

## 注意事項
- 本手順は緊急時のみ使用
- すべての操作は監査ログに記録される
- 不正使用は懲戒対象

---
最終更新: $(date +%Y-%m-%d)
EOF

cat /tmp/break-glass-sop.md
```

### 检查清单

- [ ] SSM Agent 状态正常
- [ ] 实例已注册到 SSM
- [ ] 理解 SSM vs SSH 的安全优势
- [ ] 知道如何通过 CLI/Console 启动 SSM Session
- [ ] 理解会话日志的审计价值

---

## 常被忽视的运维话题（Missing Topics Sidebar）

### 1. 时间同步（Chrony）

```bash
# Amazon Time Sync Service
# 地址: 169.254.169.123 (链路本地，无需网络访问)

# 检查时间同步状态
chronyc sources -v

# 验证 Amazon Time Sync 配置
grep "169.254.169.123" /etc/chrony.conf

# 强制同步
sudo chronyc makestep

# 为什么重要：
# - 日志时间戳必须准确
# - TLS 证书验证依赖时间
# - 分布式系统需要时间一致性
```

### 2. 熵源（Entropy）

```bash
# 虚拟机随机性不足会导致密钥生成慢

# 检查可用熵
cat /proc/sys/kernel/random/entropy_avail

# 如果 < 200，可能需要：
# - 安装 haveged 或 rng-tools
# - 使用硬件 RNG（某些实例类型支持）

# Amazon Linux 2023 默认配置通常足够
# 但加密密集型应用可能需要注意
```

### 3. Agent 疲劳（Agent Fatigue）

```bash
# 多个 Agent 竞争资源

# 常见 Agent：
# - amazon-ssm-agent (SSM)
# - amazon-cloudwatch-agent (监控)
# - amazon-inspector-agent (漏洞扫描)
# - qualys/tenable agent (第三方安全)
# - datadog/newrelic agent (APM)

# 检查 Agent 资源使用
ps aux | grep -E "(ssm|cloudwatch|inspector|agent)" | grep -v grep

# 使用 cgroup 限制资源（如果需要）
systemctl show amazon-cloudwatch-agent | grep -E "(Memory|CPU)"
```

### 4. EC2 Serial Console

```bash
# 网络完全不可用时的最后手段

# 前提条件：
# - 实例支持 Serial Console（Nitro 实例）
# - 设置了密码或 SSH 密钥
# - IAM 有 ec2-instance-connect:SendSerialConsoleSSHPublicKey 权限

# 设置 root 密码（用于 Serial Console 登录）
# sudo passwd root

# 通过 AWS Console 访问：
# EC2 → Instance → Connect → Serial Console

# 这是"物理访问"的云端替代
# 用于恢复网络配置错误、fstab 错误等
```

---

## 职场小贴士（Japan IT Context）

### 運用監視とログ管理は日本企業の基本

在日本企业，**运维监控（運用監視）** 和 **日志管理（ログ管理）** 是基础设施运维的核心能力：

| 日语术语 | 读音 | 含义 | 实践 |
|----------|------|------|------|
| 運用監視 | うんようかんし | 运维监控 | CloudWatch 仪表板和告警 |
| ログ管理 | ログかんり | 日志管理 | CloudWatch Logs 集中存储 |
| 証跡保全 | しょうせきほぜん | 证据保全 | 事故前收集系统状态 |
| 原因究明 | げんいんきゅうめい | 根因分析 | RCA 报告基于收集的证据 |
| 緊急対応 | きんきゅうたいおう | 紧急响应 | Break-Glass Procedure |
| 監査証跡 | かんさしょうせき | 审计追踪 | SSM 会话日志 |

### 証跡保全と原因究明

日本企业对事故处理有严格的流程要求：

```
┌─────────────────────────────────────────────────────────────────────────────┐
│            日本企業の障害対応フロー                                           │
│            (Japan Enterprise Incident Response Flow)                        │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│   1. 障害検知 (Incident Detection)                                          │
│      └─ CloudWatch 告警 or 顧客報告                                         │
│                                                                             │
│   2. 初動対応 (First Response)                                              │
│      └─ 影響範囲確認、関係者連絡                                             │
│                                                                             │
│   3. 証跡保全 (Evidence Preservation) ← 本課のフォーカス                    │
│      └─ 復旧作業前に証拠収集                                                 │
│      └─ スナップショット取得                                                 │
│      └─ ログ・状態の保存                                                    │
│                                                                             │
│   4. 復旧作業 (Recovery)                                                    │
│      └─ サービス復旧を優先                                                   │
│      └─ 暫定対応 vs 恒久対応                                                │
│                                                                             │
│   5. 原因究明 (Root Cause Analysis)                                         │
│      └─ 収集した証跡を分析                                                   │
│      └─ タイムライン作成                                                    │
│      └─ 真因特定                                                            │
│                                                                             │
│   6. 報告書作成 (Incident Report)                                           │
│      └─ 経緯、原因、対策を文書化                                             │
│      └─ 再発防止策                                                          │
│                                                                             │
│   7. 改善実施 (Improvement)                                                 │
│      └─ 監視強化                                                            │
│      └─ 自動化                                                              │
│      └─ 手順書更新                                                          │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 监控告警最佳实践

```bash
# 日本企业常见的告警阈值设定

# CPU 告警
# - Warning: 70% (5分間平均)
# - Critical: 90% (5分間平均)

# Memory 告警
# - Warning: 80%
# - Critical: 95%

# Disk 告警
# - Warning: 70%
# - Critical: 85%

# 告警通知先
# - 日中: Slack/Teams + メール
# - 夜間: PagerDuty/OpsGenie → 当番携帯
```

---

## 检查清单

完成本课后，你应该能够：

- [ ] 安装和配置 CloudWatch Agent
- [ ] 收集自定义系统指标（内存、磁盘使用率）
- [ ] 配置日志收集（文件日志和 journald）
- [ ] 发送自定义应用指标
- [ ] 避免高基数维度陷阱
- [ ] 理解 CloudWatch vs Prometheus 的适用场景
- [ ] 创建 CloudWatch 告警
- [ ] 使用 SSM Run Command 进行远程诊断
- [ ] 执行证据保全流程
- [ ] 配置 SSM Session Manager 替代 SSH
- [ ] 理解日本企业的事故响应流程

---

## 本课小结

| 概念 | 要点 |
|------|------|
| CloudWatch Agent | 收集 OS 级别指标和日志，弥补 Hypervisor 层监控的不足 |
| 日志收集 | 支持文件日志和 journald，注意日志轮转冲突 |
| 自定义指标 | StatsD 协议或 PutMetricData API，避免高基数维度 |
| 云监控架构 | CloudWatch 适合 AWS 集成，Prometheus 适合高基数/跨云 |
| 证据保全 | 恢复操作前收集系统状态，支持事后根因分析 |
| SSM Session Manager | 比 SSH 更安全，无需开放端口，内置审计日志 |

---

## 延伸阅读

- [CloudWatch Agent User Guide](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/Install-CloudWatch-Agent.html) - 官方文档
- [CloudWatch Agent Configuration](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/CloudWatch-Agent-Configuration-File-Details.html) - 配置详解
- [SSM Session Manager](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager.html) - SSM 会话管理
- [CloudWatch Logs Insights](https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/AnalyzingLogData.html) - 日志查询语言
- 前一课：[08 - 镜像加固与供应链安全](../08-image-hardening/) - CIS Benchmark 和漏洞扫描
- 下一课：[10 - Capstone：不可变金色镜像管道](../10-capstone/) - 综合项目

---

## 清理资源

```bash
# 停止 CloudWatch Agent（如果只是测试）
sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a stop

# 删除临时文件
rm -f /tmp/evidence-collection.sh
rm -f /tmp/pre-reboot-checklist.sh
rm -f /tmp/break-glass-sop.md
rm -rf /tmp/evidence-*

# 删除测试告警（可选）
# aws cloudwatch delete-alarms --alarm-names "HighCPU-$(hostname)" "HighMemory-$(hostname)"

# 注意：CloudWatch Logs 和指标会产生费用
# 考虑删除测试用的日志组
# aws logs delete-log-group --log-group-name "/ec2/messages"
# aws logs delete-log-group --log-group-name "/ec2/secure"
# aws logs delete-log-group --log-group-name "/ec2/cloudwatch-agent"
```

---

## 系列导航

[<- 08 - 镜像加固与供应链安全](../08-image-hardening/) | [系列首页](../) | [10 - Capstone ->](../10-capstone/)
