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

> ⚠️ **重要更新（2024+）**：AWX 已**不再支持 docker-compose 部署**。
> 目前唯一官方支持的方式是 **AWX Operator on Kubernetes**。

**部署方式选择**：

| 方式 | 说明 | 适用场景 |
|------|------|----------|
| **AWX Operator** | 官方唯一支持 | 生产环境 |
| **Minikube + AWX Operator** | 本地测试用 | Lab 学习 |
| ~~docker-compose~~ | 已废弃 | ❌ 不再可用 |

**Minikube 快速部署（Lab 用）**：

```bash
# 1. 安装 Minikube（如未安装）
curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
sudo install minikube-linux-amd64 /usr/local/bin/minikube

# 2. 启动 Minikube（需要 4GB+ 内存）
minikube start --cpus=2 --memory=4096

# 3. 安装 AWX Operator
kubectl apply -f https://raw.githubusercontent.com/ansible/awx-operator/devel/deploy/awx-operator.yaml

# 4. 创建 AWX 实例
cat <<EOF | kubectl apply -f -
apiVersion: awx.ansible.com/v1beta1
kind: AWX
metadata:
  name: awx-demo
spec:
  service_type: NodePort
EOF

# 5. 等待部署完成（约 5-10 分钟）
kubectl get pods -w

# 6. 获取访问信息
minikube service awx-demo-service --url
kubectl get secret awx-demo-admin-password -o jsonpath="{.data.password}" | base64 --decode
```

> 📖 详细部署指南请参考 [AWX Operator 官方文档](https://github.com/ansible/awx-operator)

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

> ⚠️ **安全最佳实践**：
> - 使用带 passphrase 的密钥，AWX 支持解密
> - 生产环境考虑使用 **HashiCorp Vault** 集成
> - 限制 Credential 的使用权限（RBAC）
> - 定期轮换密钥

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

> ⚠️ **安全提醒**：生产环境必须使用 **HTTPS**，以下示例使用 http 仅为 Lab 演示。

### 6.1 认证方式

AWX 支持多种认证方式：

| 方式 | 适用场景 | 说明 |
|------|----------|------|
| **Basic Auth** | 快速测试 | 用户名:密码 |
| **OAuth Token** | API 调用 | 推荐，可设置过期时间 |
| **Session Cookie** | Web UI | 浏览器自动处理 |

### 6.2 使用 Basic Auth

```bash
# 使用 Basic Auth 快速测试
curl -u admin:password \
  https://awx.example.com/api/v2/me/
```

### 6.3 创建 OAuth Token

```bash
# 通过 Web UI 创建 Token:
# Settings → Users → admin → Tokens → Add

# 或使用 awx CLI（推荐）
pip install awxkit
awx login --conf.host https://awx.example.com \
          --conf.username admin \
          --conf.password password

# 获取 Token 后使用
export AWX_TOKEN="your-oauth-token"
```

### 6.4 触发 Job

```bash
# 启动 Job Template（使用 OAuth Token）
curl -X POST \
  -H "Authorization: Bearer $AWX_TOKEN" \
  -H "Content-Type: application/json" \
  https://awx.example.com/api/v2/job_templates/1/launch/

# 查看 Job 状态
curl -H "Authorization: Bearer $AWX_TOKEN" \
  https://awx.example.com/api/v2/jobs/1/
```

### 6.5 使用 awx CLI（推荐）

```bash
# 比 curl 更方便
awx job_templates launch "Deploy Web Server" --monitor
awx jobs list --status running
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

## 部署验证清单

| # | 检查项 | 验证方法 |
|---|--------|----------|
| 1 | AWX Pods 运行中 | `kubectl get pods -n awx` 全部 Running |
| 2 | Web UI 可访问 | 浏览器打开 AWX URL |
| 3 | 管理员登录成功 | 使用 admin 密码登录 |
| 4 | Project 同步成功 | Project 状态显示绿色 |
| 5 | Inventory ping 成功 | 运行 Ad-hoc ping 命令 |

---

## 日本企業現場ノート

> 💼 **AWX/AAP 的企业运维实践**

| 要点 | 说明 |
|------|------|
| **RBAC 分离** | 开发只能查看 Job，运维才能执行，管理员管理 Credential |
| **Workflow 审批** | 重要变更使用 Approval Node，需人工确认 |
| **監査ログ** | 启用 Activity Stream，导出到 SIEM（Splunk/ELK） |
| **変更管理** | Job 启动时要求填写 change ticket ID（Survey 功能） |
| **SSO 集成** | 使用 SAML/LDAP 统一认证，禁用本地 admin |
| **备份策略** | 定期备份 PostgreSQL 和配置 |

```yaml
# 使用 Survey 强制填写变更单号
extra_vars:
  change_ticket: "{{ survey_change_ticket }}"
```

> 📋 **面试/入场时可能被问**：
> - 「AWX の監査ログはどこで確認できますか？」→ Activity Stream
> - 「権限管理はどうしていますか？」→ RBAC (Organizations, Teams, Roles)

---

## 本课小结

| 概念 | 要点 |
|------|------|
| AWX | 开源 Ansible Web UI，需 Kubernetes 部署 |
| AAP | Red Hat 商用版（含支持） |
| Project | Git 仓库中的 Playbooks |
| Job Template | Playbook 执行模板 |
| Workflow | Job Template 编排，支持审批节点 |
| RBAC | 基于角色的访问控制（Organizations/Teams） |

---

## 系列导航

← [09 · Vault](../09-vault-secrets/) | [Home](../) | [Next →](../11-zabbix-eda/)
