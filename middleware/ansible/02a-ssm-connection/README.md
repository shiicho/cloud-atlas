# 02a · AWS SSM 连接（Zero-Trust Alternative）

> **目标**：掌握 AWS SSM 连接插件作为 SSH 的替代方案
> **前置**：[02 · インベントリ管理](../02-inventory/)、[AWS SSM 课程](../../../aws/ssm/)
> **时间**：25 分钟
> **性质**：选修 / AWS 专用

---

## 本课定位

> **重要说明**：本课是 **可选进阶内容**，不影响主线学习。

Ansible 核心理念是 **Agentless**（无需安装 Ansible 代理）。传统方式通过 SSH 连接目标机器，这是最通用、最便携的方式。

然而在 AWS 环境中，存在另一种连接方式：**SSM Session Manager**。

### SSH vs SSM — 诚实对比

| 维度 | SSH (传统) | SSM (AWS) |
|------|-----------|-----------|
| **代理要求** | 无 Ansible 代理 | 需要 SSM Agent |
| **端口** | 需开放 22 端口 | 无需入站端口 |
| **认证** | SSH 密钥 | IAM 角色 |
| **审计** | 自行配置 | CloudTrail 自动记录 |
| **可移植性** | 任何 Linux/Unix | **仅限 AWS** |
| **学习价值** | 通用技能 | AWS 专用技能 |

### 何时考虑 SSM？

```
┌─────────────────────────────────────────────────────────────┐
│                  使用 SSM 的适合场景                          │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ✅ 团队已使用 SSM Session Manager 进行日常运维                │
│  ✅ 安全策略禁止开放 SSH 端口 (Port 22)                        │
│  ✅ 需要 IAM-based 访问控制和 CloudTrail 审计                  │
│  ✅ 100% AWS 环境，无多云/混合云需求                           │
│                                                             │
│  ❌ 不适合：需要管理 AWS 以外的服务器                           │
│  ❌ 不适合：追求厂商中立的技能栈                                │
│  ❌ 不适合：网络延迟敏感的大批量操作                            │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

> **日本 IT 现场**：很多日本企业 CTO 担心 vendor lock-in（ベンダーロックイン）。SSH 技能可移植，SSM 技能仅限 AWS。在面试中强调你同时掌握两者。

---

## 将学到的内容

1. 理解 SSM 连接的工作原理
2. 配置 `amazon.aws.aws_ssm` 连接插件
3. 结合动态 Inventory 使用 SSM
4. 了解性能限制与解决方案

---

## Step 1 — SSM 连接原理

### 1.1 架构对比

**传统 SSH 模式：**

```
Control Node ──[SSH:22]──► Managed Node
                 │
                 └── 需要: SSH 密钥 + 开放端口
```

**SSM 连接模式：**

```
┌─────────────────────────────────────────────────────────────┐
│                    ZERO-TRUST PATTERN                        │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│   Control Node                      EC2 Instance            │
│   ┌─────────────────┐               ┌─────────────────┐     │
│   │ ansible-playbook│               │ SSM Agent       │     │
│   │                 │               │ (预装于 AL2023) │     │
│   └────────┬────────┘               └────────▲────────┘     │
│            │                                 │              │
│            │  amazon.aws.aws_ssm             │              │
│            │  connection plugin              │              │
│            ▼                                 │              │
│   ┌─────────────────┐    AWS API            │              │
│   │ SSM Session     │────────────────────────┘              │
│   │ Manager         │                                       │
│   └────────┬────────┘                                       │
│            │                                                │
│            ▼                                                │
│   ┌─────────────────┐                                       │
│   │ S3 Bucket       │  (文件传输中转)                        │
│   └─────────────────┘                                       │
│                                                             │
│   ✅ 无 SSH 密钥      ✅ 无入站端口      ✅ IAM 认证          │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### 1.2 前提条件

| 组件 | 要求 |
|------|------|
| **Control Node** | 安装 Session Manager Plugin |
| **EC2 Instance** | SSM Agent 运行中（AL2023/AL2 默认预装） |
| **IAM Role** | EC2 需附加 `AmazonSSMManagedInstanceCore` |
| **S3 Bucket** | 用于文件传输（copy/template 模块需要） |
| **Python** | boto3, botocore 已安装 |

---

## Step 2 — 环境准备

### 2.1 Control Node 安装 Session Manager Plugin

**Amazon Linux 2023 / Amazon Linux 2：**

```bash
# 下载并安装 Session Manager Plugin
sudo dnf install -y \
  https://s3.amazonaws.com/session-manager-downloads/plugin/latest/linux_64bit/session-manager-plugin.rpm

# 验证安装
session-manager-plugin --version
```

### 2.2 安装 Python 依赖

```bash
pip3 install boto3 botocore
```

### 2.3 安装 AWS Collection

```bash
ansible-galaxy collection install amazon.aws
```

### 2.4 验证 EC2 IAM Role

EC2 实例需要附加包含以下权限的 IAM Role：

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ssm:UpdateInstanceInformation",
        "ssmmessages:CreateControlChannel",
        "ssmmessages:CreateDataChannel",
        "ssmmessages:OpenControlChannel",
        "ssmmessages:OpenDataChannel"
      ],
      "Resource": "*"
    }
  ]
}
```

> **提示**：使用 AWS 托管策略 `AmazonSSMManagedInstanceCore` 更简单。

---

## Step 3 — 配置 SSM 连接

### 3.1 创建 S3 Bucket（文件传输用）

```bash
aws s3 mb s3://my-ansible-ssm-bucket-$(aws sts get-caller-identity --query Account --output text)
```

### 3.2 动态 Inventory + SSM 连接

创建 `aws_ec2_ssm.yaml`：

```yaml
# aws_ec2_ssm.yaml
plugin: amazon.aws.aws_ec2
regions:
  - ap-northeast-1

filters:
  instance-state-name: running
  "tag:ManagedBy": ansible

# 主机名使用 Instance ID（SSM 需要）
hostnames:
  - instance-id

# 分组
keyed_groups:
  - key: tags.Role
    prefix: role
  - key: tags.Environment
    prefix: env

# 关键配置：使用 SSM 连接
compose:
  ansible_host: instance_id
  ansible_connection: 'amazon.aws.aws_ssm'
  ansible_aws_ssm_bucket_name: 'my-ansible-ssm-bucket-123456789012'
  ansible_aws_ssm_region: 'ap-northeast-1'
```

### 3.3 验证 Inventory

```bash
# 查看主机列表
ansible-inventory -i aws_ec2_ssm.yaml --graph

# 测试连接
ansible -i aws_ec2_ssm.yaml all -m ping
```

---

## Step 4 — Playbook 使用 SSM

### 4.1 基本 Playbook

```yaml
# ssm-test.yaml
---
- name: Test SSM Connection
  hosts: all
  gather_facts: true

  vars:
    ansible_connection: amazon.aws.aws_ssm
    ansible_aws_ssm_bucket_name: my-ansible-ssm-bucket-123456789012
    ansible_aws_ssm_region: ap-northeast-1

  tasks:
    - name: Show OS information
      debug:
        msg: "{{ ansible_distribution }} {{ ansible_distribution_version }}"

    - name: Check disk usage
      command: df -h /
      register: disk_result

    - name: Display disk usage
      debug:
        var: disk_result.stdout_lines
```

### 4.2 执行

```bash
ansible-playbook -i aws_ec2_ssm.yaml ssm-test.yaml
```

---

## Step 5 — 性能考虑与限制

### 5.1 SSM vs SSH 性能

| 操作 | SSH | SSM | 差异原因 |
|------|-----|-----|----------|
| 简单命令 | 快 | 较慢 | API 调用开销 |
| 文件传输 | 直接 SCP | 经 S3 中转 | 额外网络跳转 |
| 批量操作 | 高效 | 受限 | 并发会话限制 |

### 5.2 优化建议

```yaml
# 减少任务数量，合并操作
- name: Install multiple packages (一次性)
  dnf:
    name:
      - httpd
      - mod_ssl
      - php
    state: present

# 使用 async 避免超时
- name: Long running task
  command: /opt/scripts/long-task.sh
  async: 300
  poll: 10

# 大文件预置于 S3，避免通过 SSM 传输
- name: Download artifact from S3
  aws_s3:
    bucket: my-artifacts
    object: app-v1.2.3.tar.gz
    dest: /tmp/app.tar.gz
    mode: get
```

### 5.3 文件传输限制

SSM 文件传输经过 S3 中转，存在大小限制：

| 限制 | 值 |
|------|-----|
| 单文件大小 | 建议 < 1GB |
| 传输速度 | 比 SCP 慢 2-5x |

**解决方案**：大文件直接使用 `aws_s3` 模块，不走 SSM 通道。

---

## 动手前检查清单

| # | 检查项 | 验证命令 |
|---|--------|----------|
| 1 | Session Manager Plugin 已安装 | `session-manager-plugin --version` |
| 2 | boto3 已安装 | `pip3 show boto3` |
| 3 | AWS 凭证配置 | `aws sts get-caller-identity` |
| 4 | S3 Bucket 存在 | `aws s3 ls s3://your-bucket-name` |
| 5 | EC2 SSM Agent 运行中 | `aws ssm describe-instance-information` |
| 6 | amazon.aws Collection 已安装 | `ansible-galaxy collection list \| grep amazon.aws` |

---

## 日本企業現場ノート

> 💼 **SSM 连接的企业实践**

| 要点 | 说明 |
|------|------|
| **セキュリティ審査** | SSM 因无需开放端口，更易通过安全审查 |
| **CloudTrail 連携** | 所有 SSM Session 自动记录到 CloudTrail，满足监査要件 |
| **IAM 権限分離** | 使用 IAM Policy 限制可连接的 EC2 实例 |
| **S3 バケット保護** | SSM 用 S3 Bucket 需启用加密和版本控制 |
| **ハイブリッド運用** | 生产环境 SSM，开发环境 SSH（减少 IAM 复杂度） |
| **コスト考慮** | S3 传输有成本，大文件考虑直接使用 aws_s3 模块 |

```yaml
# 企业标准：IAM Policy 限制 SSM 连接范围
{
  "Effect": "Allow",
  "Action": "ssm:StartSession",
  "Resource": [
    "arn:aws:ec2:ap-northeast-1:123456789012:instance/*"
  ],
  "Condition": {
    "StringEquals": {
      "ssm:resourceTag/Environment": ["development", "staging"]
    }
  }
}
```

> 📋 **面试/入场时可能被问**：
> - 「なぜ SSM を選んだのですか？」→ ポート開放不要、IAM 認証、CloudTrail 監査ログ
> - 「SSH と SSM のどちらを推奨しますか？」→ AWS 専用環境なら SSM、マルチクラウドなら SSH

---

## 面试要点

> **問題**：Ansible で AWS SSM 接続を使用するメリット・デメリットは？
>
> **回答**：
>
> **メリット**：
> - ポート 22 を開放する必要がない（セキュリティ向上）
> - IAM ベースの認証で SSH 鍵管理が不要
> - CloudTrail で全操作が自動記録される
>
> **デメリット**：
> - SSM Agent が必要（完全な Agentless ではない）
> - AWS 以外の環境では使用不可
> - ファイル転送が S3 経由で遅い

---

## 本课小结

| 概念 | 要点 |
|------|------|
| SSM 连接 | AWS 专用的 Zero-Trust 替代方案 |
| 前提条件 | SSM Agent + IAM Role + S3 Bucket |
| 配置方式 | `ansible_connection: amazon.aws.aws_ssm` |
| 性能限制 | 比 SSH 慢，大文件用 S3 直传 |
| 可移植性 | **仅限 AWS**，非通用技能 |

---

## 相关资源

- [AWS SSM 课程 · Session Manager 免密登录](../../../aws/ssm/02-session-manager/)
- [Ansible 官方文档 · aws_ssm connection](https://docs.ansible.com/ansible/latest/collections/amazon/aws/aws_ssm_connection.html)
- [AWS 博客 · Zero Trust Automation](https://developers.redhat.com/articles/2025/09/22/zero-trust-automation-aws-ansible-and-terraform)

---

## 系列导航

← [02 · インベントリ管理](../02-inventory/) | [Home](../) | [03 · Ad-hoc 命令 →](../03-adhoc-modules/)

> **注意**：这是选修课程。主线学习请继续 [03 · Ad-hoc 命令与模块](../03-adhoc-modules/)。
