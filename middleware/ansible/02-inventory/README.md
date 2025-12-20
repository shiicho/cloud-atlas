# 02 · インベントリ管理（Inventory Management）

> **目标**：部署 Managed Nodes，掌握 Inventory 管理
> **前置**：[01 · 环境构築](../01-installation/)
> **时间**：30 分钟
> **费用**：约 $0.02/小时（2x t3.micro）

---

## 将学到的内容

1. 部署 Managed Nodes（自动配置 SSH）
2. 第一次 `ansible all -m ping`
3. 理解 Inventory 文件格式（INI / YAML）
4. 使用 Groups、host_vars、group_vars

---

## Step 1 — 部署 Managed Nodes

### 1.1 架构概览

```
┌──────────────────────────────────────────────────────────────┐
│                    VPC (10.0.0.0/16)                          │
│                                                               │
│   ┌─────────────────────────────────────────────────────┐    │
│   │               Public Subnet (10.0.1.0/24)           │    │
│   │                                                      │    │
│   │   ┌─────────────┐                                   │    │
│   │   │ control.    │     Route 53 Private Hosted Zone  │    │
│   │   │ ans.local   │     ┌─────────────────────────┐   │    │
│   │   │ (Control)   │     │ ans.local               │   │    │
│   │   └──────┬──────┘     │ ├─ control.ans.local    │   │    │
│   │          │            │ ├─ al2023-1.ans.local   │   │    │
│   │          │ SSH        │ └─ al2023-2.ans.local   │   │    │
│   │          ▼            └─────────────────────────┘   │    │
│   │   ┌─────────────┐  ┌─────────────┐                  │    │
│   │   │ al2023-1    │  │ al2023-2    │  ← 本课部署      │    │
│   │   │ (webserver) │  │ (dbserver)  │                  │    │
│   │   └─────────────┘  └─────────────┘                  │    │
│   │                                                      │    │
│   └─────────────────────────────────────────────────────┘    │
└──────────────────────────────────────────────────────────────┘
```

### 1.2 生成 SSH 密钥

首先生成 SSH 密钥对（用于连接 Managed Nodes）：

```bash
# 生成 Ed25519 密钥（无密码）
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -N ""

# 查看公钥
cat ~/.ssh/id_ed25519.pub
```

### 1.3 部署命令

```bash
# 进入课程目录
cd ~/02-inventory

# 获取 SSH 公钥
PUBLIC_KEY=$(cat ~/.ssh/id_ed25519.pub)

# 部署 Managed Nodes（SSH 密钥自动注入）
aws cloudformation create-stack \
  --stack-name ansible-lesson-02 \
  --template-body file://cfn/managed-nodes.yaml \
  --parameters ParameterKey=PublicKey,ParameterValue="$PUBLIC_KEY" \
  --capabilities CAPABILITY_NAMED_IAM

# 等待完成（约 3 分钟）
aws cloudformation wait stack-create-complete --stack-name ansible-lesson-02
```

### 1.4 验证 DNS 解析

CloudFormation 自动创建 Route 53 DNS 记录：

```bash
nslookup al2023-1.ans.local
nslookup al2023-2.ans.local
```

---

## Step 2 — 第一次 Ansible 连接

### 2.1 查看 Inventory 文件

```bash
cat inventory/hosts.ini
```

```ini
[webservers]
al2023-1.ans.local

[dbservers]
al2023-2.ans.local

[all:vars]
ansible_python_interpreter=/usr/bin/python3
```

### 2.2 测试连接

```bash
ansible all -m ping
```

**预期输出**：
```
al2023-1.ans.local | SUCCESS => { "ping": "pong" }
al2023-2.ans.local | SUCCESS => { "ping": "pong" }
```

如果成功，你已完成 Ansible 的第一次远程连接！

### 2.3 测试指定组

```bash
# 只测试 webservers 组
ansible webservers -m ping

# 只测试 dbservers 组
ansible dbservers -m ping
```

---

## Step 3 — Inventory 格式

### 3.1 INI 格式（默认）

```ini
# 主机列表
[webservers]
al2023-1.ans.local

[dbservers]
al2023-2.ans.local

# 组变量
[webservers:vars]
http_port=80

# 嵌套组
[production:children]
webservers
dbservers

# 全局变量
[all:vars]
ansible_python_interpreter=/usr/bin/python3
```

### 3.2 YAML 格式

```yaml
all:
  vars:
    ansible_python_interpreter: /usr/bin/python3
  children:
    webservers:
      hosts:
        al2023-1.ans.local:
      vars:
        http_port: 80
    dbservers:
      hosts:
        al2023-2.ans.local:
    production:
      children:
        webservers:
        dbservers:
```

### 3.3 渐进式示例

本课提供 7 个渐进式示例，位于 `inventory/examples/`：

| 示例 | 新概念 | 测试命令 |
|------|--------|----------|
| `01-basic-hosts` | 基本主机列表 | `ansible -i 01-basic-hosts all --list-hosts` |
| `02-with-groups` | 功能分组 | `ansible -i 02-with-groups webservers -m ping` |
| `03-host-ranges` | 范围表示法 | `ansible -i 03-host-ranges amazon_linux --list-hosts` |
| `04-group-vars` | 组变量 | `ansible -i 04-group-vars all -m debug -a "var=http_port"` |
| `05-children-groups` | 层级分组 | `ansible -i 05-children-groups production --list-hosts` |
| `06-yaml-format/` | YAML 格式 | `ansible -i hosts.yaml all --list-hosts` |
| `07-control-local` | 本地连接 | `ansible -i 07-control-local control -m ping` |

```bash
# 动手试试
cd ~/02-inventory/inventory/examples
ansible-inventory -i 05-children-groups --graph
```

---

## Step 4 — host_vars 和 group_vars

### 4.1 目录结构

```
inventory/
├── hosts.ini           # 主机清单
├── group_vars/         # 组变量
│   ├── all.yaml        # 所有主机
│   ├── webservers.yaml # webservers 组
│   └── dbservers.yaml  # dbservers 组
└── host_vars/          # 主机变量
    └── al2023-1.ans.local.yaml
```

### 4.2 变量优先级（低→高）

```
group_vars/all.yaml
    ↓
group_vars/<group>.yaml
    ↓
host_vars/<host>.yaml
    ↓
命令行 -e "var=value"
```

### 4.3 查看示例

```bash
# 查看预配置的 group_vars
cat inventory/04-group-vars/group_vars/all.yaml
cat inventory/04-group-vars/group_vars/webservers.yaml

# 查看 host_vars
cat inventory/04-group-vars/host_vars/al2023-1.ans.local.yaml
```

### 4.4 验证变量

```bash
cd ~/02-inventory/inventory/04-group-vars

# 查看主机的所有变量
ansible-inventory -i hosts.ini --host al2023-1.ans.local

# 测试变量值
ansible -i hosts.ini all -m debug -a "var=http_port"
```

---

## Step 5 — Inventory 命令

```bash
# 列出所有主机
ansible-inventory --list

# 图形化显示
ansible-inventory --graph

# 查看特定主机变量
ansible-inventory --host al2023-1.ans.local

# 使用不同的 inventory
ansible -i inventory/hosts.ini all -m ping
```

---

## 本课小结

| 概念 | 要点 |
|------|------|
| 部署方式 | CFN + PublicKey 参数自动配置 SSH |
| DNS 解析 | Route 53 Private Hosted Zone |
| INI vs YAML | 两种格式均可，YAML 更结构化 |
| group_vars | 组级别变量，按目录组织 |
| host_vars | 主机级别变量，最高优先级 |

---

## 日本企業現場ノート

> 💼 **Inventory 管理的企业实践**

| 要点 | 说明 |
|------|------|
| **環境分離** | dev/staging/prod 三套 Inventory 严格分离 |
| **命名規則** | 主机名使用统一命名规则 |
| **変更管理** | Inventory 文件纳入 Git |
| **機密情報** | 敏感信息使用 Vault 加密 |

---

## 清理资源

> **保留 Managed Nodes** - 后续课程（03-adhoc, 04-playbook 等）都需要使用。
>
> 学完所有课程后删除：
> ```bash
> aws cloudformation delete-stack --stack-name ansible-lesson-02
> ```

---

## 下一步

Managed Nodes 已就绪，学习 Ad-hoc 命令和模块。

→ [03 · Ad-hoc 命令与模块](../03-adhoc-modules/)

---

## 系列导航

← [01 · 环境构築](../01-installation/) | [Home](../) | [Next →](../03-adhoc-modules/)
