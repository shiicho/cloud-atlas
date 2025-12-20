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

### 主 Lab: ansible-lab.yaml

部署 3 节点 Ansible 实验环境:

```
┌─────────────────┐     SSH     ┌─────────────────┐
│  ansible-control│────────────▶│  ansible-node-1 │
│  (t3.small)     │             │  (t3.micro)     │
│  Ansible 2.15+  │             │  Web Server     │
└─────────────────┘             └─────────────────┘
         │
         │ SSH
         ▼
┌─────────────────┐
│  ansible-node-2 │
│  (t3.micro)     │
│  DB Server      │
└─────────────────┘
```

**部署命令:**
```bash
aws cloudformation create-stack \
  --stack-name ansible-lab \
  --template-body file://cfn/ansible-lab.yaml \
  --capabilities CAPABILITY_IAM
```

### AWX Lab: ansible-awx-lab.yaml

Lesson 10 使用，部署 AWX 容器环境:
- t3.medium (Docker 预装)
- AWX Web UI (port 80)

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
