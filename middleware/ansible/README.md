# Ansible 自动化入门到实战

> **Ansible Zero-to-Hero: 从基础到企业级自动化**

本系列课程从零开始讲解 Ansible 自动化运维，覆盖从基础概念到 AWX/Event-Driven Ansible 的完整知识体系。适用于个人学习和企业内训。

---

## 课程特色

| 特色 | 说明 |
|------|------|
| **零基础友好** | 从 Agentless 概念讲起，无需 Puppet/Chef 经验 |
| **RHCE 对齐** | 覆盖 EX294 考试核心内容 |
| **日本职场实战** | 運用巡検、標準化、障害対応自動化场景 |
| **完整 Lab 环境** | CloudFormation 一键部署，即开即用 |

---

## 课程大纲 (12 Lessons)

### 基础篇 (00-03)

| # | 课程 | 主题 |
|---|------|------|
| 00 | [概念与架构导入](./00-concepts/) | Agentless 哲学、Control/Managed Nodes |
| 01 | [环境构築与初期配置](./01-installation/) | 安装、ansible.cfg、SSH 配置 |
| 02 | [インベントリ管理](./02-inventory/) | 静态/动态 Inventory、aws_ec2 插件 |
| 02a | [AWS SSM 连接](./02a-ssm-connection/) *(选修)* | Zero-Trust 替代方案、SSM 连接插件 |
| 03 | [Ad-hoc 命令与模块](./03-adhoc-modules/) | 核心模块、幂等性 |

### 进阶篇 (04-07)

| # | 课程 | 主题 |
|---|------|------|
| 04 | [Playbook 基础](./04-playbook-basics/) | YAML、Tasks、Handlers、Tags |
| 05 | [变量・Facts・条件・循环](./05-variables-logic/) | 变量优先级、when、loop、register |
| 06 | [Roles 与 Galaxy](./06-roles-galaxy/) | Role 结构、Collections、Galaxy |
| 07 | [Jinja2 模板引擎](./07-jinja2-templates/) | 过滤器、控制结构、配置生成 |

### 高级篇 (08-11)

| # | 课程 | 主题 |
|---|------|------|
| 08 | [错误处理与调试](./08-error-handling/) | block/rescue/always、debug |
| 09 | [Vault 与机密管理](./09-vault-secrets/) | 加密、AWS Secrets Manager |
| 10 | [AWX/Tower 入门](./10-awx-tower/) | GUI 平台、Job Templates、Workflows |
| 11 | [Zabbix 连携与 EDA](./11-zabbix-eda/) | Event-Driven Ansible、障害対応自動化 |

---

## 前置要求

| 类型 | 要求 |
|------|------|
| **必须** | Linux 基础命令行操作 |
| **推荐** | Bash 脚本基础 |
| **Lesson 11** | Zabbix 课程 Lesson 04 (触发器与告警) |

---

## Lab 环境

### 架构设计

```
┌──────────────────────────────────────────────────────────────────────────┐
│                        CONTROL NODE (永久运行)                            │
│                                                                          │
│   部署: 01-installation/cfn/control-node.yaml (via Console)             │
│   包含: Ansible, aws-cli, git, 课程代码                                   │
│                                                                          │
│   ~/course/content/middleware/ansible/                                   │
│   ├── 01-installation/                                                   │
│   │   ├── README.md         ← 课程内容 + 部署说明                         │
│   │   └── cfn/              ← CFN 模板                                   │
│   ├── 02-inventory/                                                      │
│   │   ├── README.md                                                      │
│   │   ├── cfn/                                                           │
│   │   └── inventory/        ← Inventory 文件                             │
│   └── ...                                                                │
│                                                                          │
└────────────────────────────────────────────────────────────────────────┬─┘
                                                                         │
                        每课部署各自的 Managed Nodes                       │
                                                                         ▼
┌──────────────────────────────────────────────────────────────────────────┐
│                     MANAGED NODES (按需部署)                              │
│                                                                          │
│   Lesson 01: 2 nodes (手动 SSH - 教学用)                                  │
│   Lesson 02-04: 2 nodes (自动 SSH)                                       │
│   Lesson 05: 3 nodes (Multi-OS: Amazon + Ubuntu)                        │
│   Lesson 10: AWX server + target                                        │
│   Lesson 11: Zabbix server + 2 targets                                  │
│                                                                          │
│   SSH 密钥通过 SSM Parameter Store 自动配置                               │
└──────────────────────────────────────────────────────────────────────────┘
```

### 快速开始

**Step 1: 部署 Control Node (via Console)**

> 首次部署使用 AWS Console，无需本地 CLI。

1. 下载模板：[01-installation/cfn/control-node.yaml](./01-installation/cfn/control-node.yaml)
2. 打开 [CloudFormation Console](https://console.aws.amazon.com/cloudformation/)
3. Create stack → Upload template → 上传 `control-node.yaml`
4. Stack name: `ansible-control`
5. 勾选 IAM 确认 → Submit
6. 等待 `CREATE_COMPLETE`（约 5 分钟）

**Step 2: 连接到 Control Node**

1. 打开 [EC2 Console](https://console.aws.amazon.com/ec2/)
2. 找到 `ansible-control` 实例
3. Connect → Session Manager → Connect
4. 切换到 ansible 用户：`sudo su - ansible`

**Step 3: 下载课程代码**

```bash
# 使用 sparse checkout 只下载 Ansible 课程
git clone --filter=blob:none --sparse https://github.com/shiicho/cloud-atlas ~/repo
cd ~/repo
git sparse-checkout set middleware/ansible

# 创建快捷方式到 home 目录
ln -s ~/repo/middleware/ansible/* ~/
```

现在你的 home 目录结构：
```
~/
├── 00-concepts/
├── 01-installation/
├── 02-inventory/
├── ...
└── 11-zabbix-eda/
```

**Step 4: 开始学习**

```bash
# 直接进入课程目录
cd ~/02-inventory

# 按 README.md 学习（包含部署说明）
cat README.md
```

### 课程间切换

```bash
# 如果下一课使用相同基础设施 → 保留 stack
# 如果下一课需要不同基础设施 → 删除并重新部署

# 删除旧 stack
aws cloudformation delete-stack --stack-name ansible-lesson-02

# 进入新课程目录，按 README.md 部署
cd ~/05-variables-logic
```

### 每课 CFN 模板

每个课程目录包含 `cfn/managed-nodes.yaml`：

| 课程 | 模板类型 | 节点数 |
|------|----------|--------|
| 01 | 手动 SSH（教学用） | 2 |
| 02-04, 06-09 | 自动 SSH | 2 |
| 05 | Multi-OS (Amazon + Ubuntu) | 3 |
| 10 | AWX 容器 | 2 |
| 11 | Zabbix + EDA | 3 |

---

## RHCE EX294 对照

| EX294 考点 | 对应课程 |
|------------|----------|
| Core components | 00-01 |
| Inventory | 02 |
| Playbooks | 04 |
| Modules | 03-04 |
| Variables/Facts | 05 |
| Roles | 06 |
| Templates | 07 |
| Vault | 09 |

---

## 日本职场场景

每课包含 Japan IT 实战 Mini-Project:

| 场景 | 日语 | 对应课程 |
|------|------|----------|
| 运维巡检 | 運用巡検 | 03 |
| 多环境配置 | 開発/検証/本番 | 05 |
| 标准化 | 標準化 | 06 |
| 安全合规 | セキュリティ | 09 |
| 自动修复 | 障害対応自動化 | 11 |

---

## 开始学习

从 [00 · 概念与架构导入](./00-concepts/) 开始。

---

## 系列导航

| 系列 | 说明 |
|------|------|
| [Zabbix 监控入门](../zabbix/) | 监控基础，Lesson 11 前置 |
| [HULFT 传输入门](../hulft/) | 日本特有中间件 |
