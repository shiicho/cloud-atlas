# 10 · AWX/Ansible Tower 入门（GUI Automation Platform）

> **目标**：掌握 AWX 企业级自动化平台
> **前置**：[09 · Vault 机密管理](../09-vault-secrets/)
> **时间**：45 分钟
> **费用**：约 $0.05/小时（t3.medium）
> **实战项目**：部署 AWX 并创建 Workflow

---

## 将学到的内容

1. AWX vs AAP vs Tower 关系
2. 使用 Docker 部署 AWX
3. 配置 Projects, Inventories, Credentials
4. 创建 Job Templates 和 Workflows

---

## Step 1 — AWX 概述

### 1.1 产品关系

```
┌─────────────────────────────────────────────────────────────┐
│                    Ansible 生态系统                          │
│                                                              │
│   ┌──────────────┐      ┌──────────────┐                   │
│   │ Ansible Core │      │    AWX       │                   │
│   │   (CLI)      │      │  (开源 GUI)  │                   │
│   │              │      │              │                   │
│   │  免费开源     │      │  免费开源     │                   │
│   └──────────────┘      └──────────────┘                   │
│                               ↓                              │
│                    ┌──────────────────┐                     │
│                    │ Ansible          │                     │
│                    │ Automation       │                     │
│                    │ Platform (AAP)   │                     │
│                    │                  │                     │
│                    │ Red Hat 商用版   │                     │
│                    │ (含支持和认证)   │                     │
│                    └──────────────────┘                     │
└─────────────────────────────────────────────────────────────┘
```

### 1.2 AWX 功能

| 功能 | 说明 |
|------|------|
| **Web UI** | 可视化管理 Playbooks |
| **RBAC** | 基于角色的访问控制 |
| **调度** | 定时执行 Job |
| **API** | REST API 集成 |
| **Workflow** | 多 Job 编排 |
| **凭证管理** | 安全存储密钥 |

> 💡 **面试要点**
>
> **問題**：AWX と Ansible Automation Platform の違いは？
>
> **回答**：
> - AWX はオープンソースの upstream プロジェクト
> - AAP は Red Hat 商用版、サポート・認証・セキュリティパッチ付き
> - 企業は安定性とサポートのため AAP を選択することが多い

---

## Step 2 — 部署 AWX Lab

### 2.1 部署 CFN Stack

```bash
# 部署 AWX Lab
aws cloudformation create-stack \
  --stack-name ansible-awx-lab \
  --template-body file://cfn/ansible-awx-lab.yaml \
  --capabilities CAPABILITY_IAM

# 等待完成
aws cloudformation wait stack-create-complete --stack-name ansible-awx-lab
```

### 2.2 连接到 AWX 主机

```bash
# 获取 Instance ID
AWX_ID=$(aws cloudformation describe-stacks --stack-name ansible-awx-lab \
  --query 'Stacks[0].Outputs[?OutputKey==`AWXInstanceId`].OutputValue' \
  --output text)

# SSM 连接
aws ssm start-session --target $AWX_ID
```

### 2.3 安装 AWX

```bash
# 切换到 root
sudo -i

# 安装 docker-compose
curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

# 克隆 AWX Operator（推荐方式）
git clone https://github.com/ansible/awx-operator.git
cd awx-operator

# 或使用简化的 docker-compose 方式
# (详见 AWX 官方文档)
```

> 注意：AWX 部署方式经常更新，请参考官方文档获取最新方法。

---

## Step 3 — AWX 基本概念

### 3.1 核心对象

```
┌─────────────────────────────────────────────────────────────┐
│                      AWX 对象关系                            │
│                                                              │
│   ┌──────────────┐                                          │
│   │  Project     │  ← Git 仓库中的 Playbooks                │
│   └──────┬───────┘                                          │
│          │                                                   │
│   ┌──────▼───────┐   ┌──────────────┐                       │
│   │ Job Template │ ← │  Inventory   │  ← 目标主机           │
│   └──────┬───────┘   └──────────────┘                       │
│          │                                                   │
│          │           ┌──────────────┐                       │
│          └─────────► │ Credential   │  ← SSH/Vault 密钥     │
│                      └──────────────┘                       │
│                                                              │
│   ┌──────────────┐                                          │
│   │   Workflow   │  ← 多个 Job Template 编排                │
│   └──────────────┘                                          │
└─────────────────────────────────────────────────────────────┘
```

### 3.2 对象说明

| 对象 | 说明 |
|------|------|
| **Organization** | 组织单位，资源隔离 |
| **Project** | Playbook 源（Git 仓库） |
| **Inventory** | 目标主机清单 |
| **Credential** | 认证凭证（SSH, Vault, Cloud） |
| **Job Template** | Playbook 执行模板 |
| **Workflow** | Job Template 编排 |

---

## Step 4 — 配置 AWX

### 4.1 创建 Project

1. 导航到 **Projects** → **Add**
2. 填写：
   - Name: `My Ansible Project`
   - Source Control Type: `Git`
   - Source Control URL: `https://github.com/your/repo.git`
   - Source Control Branch: `main`

### 4.2 创建 Inventory

1. 导航到 **Inventories** → **Add** → **Inventory**
2. 填写 Name: `Lab Inventory`
3. 添加主机：**Hosts** → **Add**
   - Name: `node1`
   - Variables:
   ```yaml
   ansible_host: 10.0.1.x
   ansible_user: ansible
   ```

### 4.3 创建 Credential

1. 导航到 **Credentials** → **Add**
2. 选择类型：**Machine**
3. 填写：
   - Name: `Lab SSH Key`
   - SSH Private Key: (粘贴私钥)

### 4.4 创建 Job Template

1. 导航到 **Templates** → **Add** → **Job Template**
2. 填写：
   - Name: `Deploy Web Server`
   - Job Type: `Run`
   - Inventory: `Lab Inventory`
   - Project: `My Ansible Project`
   - Playbook: `site.yaml`
   - Credentials: `Lab SSH Key`

### 4.5 执行 Job

1. 点击 Job Template 旁的 **Launch** 按钮
2. 查看实时输出
3. 查看 Job 历史

---

## Step 5 — Workflow

### 5.1 创建 Workflow Template

1. **Templates** → **Add** → **Workflow Template**
2. Name: `Full Deployment`
3. **Workflow Visualizer** → 设计流程

### 5.2 Workflow 示例

```
┌─────────────┐     成功     ┌─────────────┐
│   Deploy    │ ───────────► │   Test      │
│   App       │              │   App       │
└─────────────┘              └──────┬──────┘
                                    │
                        ┌───────────┴───────────┐
                        │                       │
                   成功 ▼                   失败 ▼
              ┌─────────────┐          ┌─────────────┐
              │   Notify    │          │   Rollback  │
              │   Success   │          │   App       │
              └─────────────┘          └─────────────┘
```

---

## Step 6 — API 使用

### 6.1 获取 Token

```bash
# 创建 Token
curl -X POST -H "Content-Type: application/json" \
  -d '{"username": "admin", "password": "password"}' \
  http://awx.example.com/api/v2/tokens/
```

### 6.2 触发 Job

```bash
# 启动 Job Template
curl -X POST -H "Authorization: Bearer $TOKEN" \
  http://awx.example.com/api/v2/job_templates/1/launch/

# 查看 Job 状态
curl -H "Authorization: Bearer $TOKEN" \
  http://awx.example.com/api/v2/jobs/1/
```

---

## Mini-Project：团队自动化平台

1. **部署 AWX**
2. **创建以下资源**：
   - Project (Git 仓库)
   - Inventory (3 台测试主机)
   - Credential (SSH 密钥)
   - Job Template (部署 Web 服务器)
3. **创建 Workflow**：
   - Deploy → Test → Notify
4. **执行并查看结果**

---

## 清理资源

```bash
aws cloudformation delete-stack --stack-name ansible-awx-lab
```

---

## 本课小结

| 概念 | 要点 |
|------|------|
| AWX | 开源 Ansible Web UI |
| AAP | Red Hat 商用版 |
| Project | Git 仓库中的 Playbooks |
| Job Template | Playbook 执行模板 |
| Workflow | Job Template 编排 |

---

## 系列导航

← [09 · Vault](../09-vault-secrets/) | [Home](../) | [Next →](../11-zabbix-eda/)
