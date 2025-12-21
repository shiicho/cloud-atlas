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

## 准备环境

```bash
# 1. 切换到 ansible 用户（如果当前不是 ansible 用户）
[ "$(whoami)" != "ansible" ] && sudo su - ansible

# 2. 更新课程仓库（获取最新内容）
cd ~/repo && git pull

# 3. 进入本课目录
cd ~/02-inventory
```

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
│   │          │            │ ├─ web-1.ans.local   │   │    │
│   │          │ SSH        │ └─ db-1.ans.local   │   │    │
│   │          ▼            └─────────────────────────┘   │    │
│   │   ┌─────────────┐  ┌─────────────┐                  │    │
│   │   │ web-1    │  │ db-1    │  ← 本课部署      │    │
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

# 部署 Managed Nodes（每个节点自包含 IAM/SG/Instance）
for node in web-1 db-1; do
  aws cloudformation deploy \
    --stack-name ansible-${node} \
    --template-file cfn/${node}.yaml \
    --parameter-overrides PublicKey="$PUBLIC_KEY" \
    --capabilities CAPABILITY_NAMED_IAM \
    --no-fail-on-empty-changeset
done

# 验证部署状态
aws cloudformation describe-stacks \
  --query "Stacks[?starts_with(StackName,'ansible-')].{Name:StackName,Status:StackStatus}" \
  --output table
```

### 1.4 验证 DNS 解析

CloudFormation 自动创建 Route 53 DNS 记录：

```bash
nslookup web-1.ans.local
nslookup db-1.ans.local
```

---

## Step 2 — 第一次 Ansible 连接

### 2.1 查看 Inventory 文件

```bash
cat inventory/hosts.ini
```

```ini
[webservers]
web-1.ans.local

[dbservers]
db-1.ans.local

[all:vars]
ansible_python_interpreter=/usr/bin/python3
```

### 2.2 测试连接

```bash
ansible all -m ping
```

**默认输出**（多行格式）：
```
web-1.ans.local | SUCCESS => {
    "changed": false,
    "ping": "pong"
}
db-1.ans.local | SUCCESS => {
    "changed": false,
    "ping": "pong"
}
```

**使用 `-o` 选项**（单行格式，主机多时更易阅读）：
```bash
ansible all -m ping -o
```
```
web-1.ans.local | SUCCESS => {"changed": false,"ping": "pong"}
db-1.ans.local | SUCCESS => {"changed": false,"ping": "pong"}
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
web-1.ans.local

[dbservers]
db-1.ans.local

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

### 3.2 渐进式示例

本课提供 6 个渐进式示例，位于 `inventory/examples/`：

| 示例 | 新概念 | 测试命令 |
|------|--------|----------|
| `01-basic-hosts` | 基本主机列表 | `ansible -i 01-basic-hosts all --list-hosts` |
| `02-with-groups` | 功能分组 | `ansible -i 02-with-groups webservers -m ping` |
| `03-host-ranges` | 范围表示法 | `ansible -i 03-host-ranges amazon_linux --list-hosts` |
| `04-group-vars` | 组变量 | `ansible -i 04-group-vars all -m debug -a "var=http_port"` |
| `05-children-groups` | 层级分组 | `ansible -i 05-children-groups production --list-hosts` |
| `06-control-local` | 本地连接 | `ansible -i 06-control-local control -m ping` |

```bash
# 动手试试
cd ~/02-inventory/inventory/examples
ansible-inventory -i 05-children-groups --graph
```

---

## Step 4 — host_vars 和 group_vars

### Ansible 设计哲学：分离「谁」和「做什么」

**核心原则**：Inventory 定义「谁 + 他们的配置」，Playbook 定义「做什么」。

```
┌─────────────────────────────────────────────────────────────────┐
│                     Ansible 的分离设计                           │
├────────────────────────────┬────────────────────────────────────┤
│     Inventory 文件          │         Playbook 文件              │
│     (hosts.ini)            │         (site.yaml)                │
├────────────────────────────┼────────────────────────────────────┤
│  WHO:  管理哪些服务器        │  WHAT: 执行什么任务                │
│  WHERE: 服务器地址/分组      │  HOW:  怎么执行                    │
│  CONFIG: 每组/每台的配置值   │  LOGIC: 通用的业务逻辑             │
├────────────────────────────┼────────────────────────────────────┤
│  ✅ 每个环境不同            │  ✅ 所有环境相同                    │
│  ✅ 运维人员维护            │  ✅ 开发/架构师编写                 │
└────────────────────────────┴────────────────────────────────────┘
```

### 为什么变量放在 Inventory 而不是 Playbook？

**反例：硬编码在 Playbook 中**（❌ 不推荐）

```yaml
# site.yaml - 硬编码版本
- name: Deploy web server
  hosts: webservers
  tasks:
    - name: Configure nginx
      template:
        src: nginx.conf.j2
        dest: /etc/nginx/nginx.conf
      vars:
        http_port: 80           # ❌ 硬编码
        max_connections: 1000   # ❌ 生产环境需要不同值怎么办？
```

问题：开发环境用 80 端口，生产环境用 8080 怎么办？复制一份 Playbook 改数字？

**正确做法：配置放 Inventory，逻辑放 Playbook**（✅ 推荐）

```ini
# inventory/dev/hosts.ini
[webservers]
dev-web-1.local

[webservers:vars]
http_port=80
max_connections=100
```

```ini
# inventory/prod/hosts.ini
[webservers]
prod-web-1.local
prod-web-2.local

[webservers:vars]
http_port=8080
max_connections=10000
```

```yaml
# site.yaml - 同一个 Playbook，不改任何代码
- name: Deploy web server
  hosts: webservers
  tasks:
    - name: Configure nginx
      template:
        src: nginx.conf.j2
        dest: /etc/nginx/nginx.conf
      # http_port 和 max_connections 自动从 Inventory 读取
```

```bash
# 执行时选择环境
ansible-playbook -i inventory/dev  site.yaml   # 用 dev 的配置
ansible-playbook -i inventory/prod site.yaml   # 用 prod 的配置
```

**效果**：一套 Playbook 代码，多套环境配置，零修改切换。

### 变量类型和作用域

| 变量位置 | 作用范围 | 使用场景 |
|----------|----------|----------|
| `group_vars/all` | 所有服务器 | Python 路径、NTP 服务器、管理员邮箱 |
| `group_vars/webservers` | webservers 组 | HTTP 端口、DocumentRoot |
| `group_vars/dbservers` | dbservers 组 | DB 端口、数据目录 |
| `host_vars/web-1` | 仅 web-1 | 该服务器的特殊配置 |

> 💡 **记住**：Inventory 是「数据」，Playbook 是「代码」。数据和代码分离，才能复用。

### 4.1 定义变量的两种方式

**方式 1：直接写在 INI 文件中**（简单场景推荐）

```ini
[webservers]
web-1.ans.local

[dbservers]
db-1.ans.local

[webservers:vars]
http_port=80

[dbservers:vars]
db_port=3306

[all:vars]
ansible_python_interpreter=/usr/bin/python3
```

**方式 2：独立的变量目录**（变量多时更清晰）

```
inventory/
├── hosts.ini           # 只放主机列表
├── group_vars/         # 组变量（独立文件）
│   ├── all             # 所有主机
│   ├── webservers      # webservers 组
│   └── dbservers       # dbservers 组
└── host_vars/          # 主机变量（独立文件）
    └── web-1.ans.local
```

> 💡 变量文件可以是 YAML 格式（`.yaml`）或无扩展名的 key=value 格式。

### 4.2 变量优先级（低→高）

```
[all:vars]  或  group_vars/all
    ↓
[group:vars]  或  group_vars/<group>
    ↓
host_vars/<host>
    ↓
命令行 -e "var=value"
```

### 4.3 动手试试

```bash
cd ~/02-inventory/inventory/examples

# 查看带变量的 inventory 示例
cat 04-group-vars

# 测试变量值
ansible -i 04-group-vars webservers -m debug -a "var=http_port"
ansible -i 04-group-vars dbservers -m debug -a "var=db_port"
```

---

## Step 5 — Inventory 命令

```bash
# 列出所有主机
ansible-inventory --list

# 图形化显示
ansible-inventory --graph

# 查看特定主机变量
ansible-inventory --host web-1.ans.local

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

### 实战：环境分离的两种模式

**模式 1：主机名包含环境标识**

```ini
# 日本企业常见命名规则：{env}-{role}{number}.{domain}
[webservers]
dev-web01.company.local
stg-web01.company.local
prd-web01.company.local
prd-web02.company.local

[dbservers]
dev-db01.company.local
stg-db01.company.local
prd-db01.company.local

# 按环境分组
[dev:children]
dev_all

[stg:children]
stg_all

[prd:children]
prd_all

[dev_all]
dev-web01.company.local
dev-db01.company.local

[prd_all]
prd-web01.company.local
prd-web02.company.local
prd-db01.company.local
```

**模式 2：独立 Inventory 文件（推荐 ✓）**

```
inventory/
├── dev/
│   ├── hosts.ini
│   └── group_vars/
├── stg/
│   ├── hosts.ini
│   └── group_vars/
└── prd/
    ├── hosts.ini
    └── group_vars/
```

使用方式：
```bash
# 明确指定环境，防止误操作
ansible-playbook -i inventory/dev  site.yaml   # 开发环境
ansible-playbook -i inventory/prd  site.yaml   # 生产环境
```

> ⚠️ **模式 2 更安全**：必须显式指定环境，不会误操作生产环境。

---

## 清理资源

> **保留 Managed Nodes** - 后续课程（03-adhoc, 04-playbook 等）都需要使用。
>
> 学完所有课程后，请参考 [课程首页的清理资源](../#清理资源) 删除所有节点。

---

## 下一步

Managed Nodes 已就绪，学习 Ad-hoc 命令和模块。

→ [03 · Ad-hoc 命令与模块](../03-adhoc-modules/)

---

## 系列导航

← [01 · 环境构築](../01-installation/) | [Home](../) | [Next →](../03-adhoc-modules/)
