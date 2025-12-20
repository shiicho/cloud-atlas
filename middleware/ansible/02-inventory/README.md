# 02 · インベントリ管理（Static & Dynamic Inventory）

> **目标**：掌握静态和动态 Inventory 管理
> **前置**：[01 · 环境构築](../01-installation/)
> **时间**：30 分钟
> **实战项目**：创建多环境 Inventory 结构

---

## 环境准备

> **CFN 模板**：`cfn/managed-nodes.yaml`（2 节点，自动 SSH）
> **部署时间**：约 3 分钟
> **费用**：约 $0.02/小时（2x t3.micro）

### 部署 Managed Nodes

```bash
# 进入课程目录
cd ~/02-inventory

# 部署 Managed Nodes
aws cloudformation create-stack \
  --stack-name ansible-lesson-02 \
  --template-body file://cfn/managed-nodes.yaml \
  --capabilities CAPABILITY_NAMED_IAM

# 等待完成（约 3 分钟）
aws cloudformation wait stack-create-complete --stack-name ansible-lesson-02
```

### 配置 Inventory

```bash
# 获取节点 IP
NODE1_IP=$(aws cloudformation describe-stacks --stack-name ansible-lesson-02 \
  --query 'Stacks[0].Outputs[?OutputKey==`Node1PrivateIp`].OutputValue' --output text)
NODE2_IP=$(aws cloudformation describe-stacks --stack-name ansible-lesson-02 \
  --query 'Stacks[0].Outputs[?OutputKey==`Node2PrivateIp`].OutputValue' --output text)

# 生成 inventory 文件
cat > inventory/hosts.ini << EOF
[webservers]
node1 ansible_host=$NODE1_IP

[dbservers]
node2 ansible_host=$NODE2_IP

[all:vars]
ansible_python_interpreter=/usr/bin/python3
EOF
```

### 验证连接

```bash
ansible -i inventory/hosts.ini all -m ping
```

**预期输出**：
```
node1 | SUCCESS => { "ping": "pong" }
node2 | SUCCESS => { "ping": "pong" }
```

---

## 将学到的内容

1. 创建 INI 和 YAML 格式的静态 Inventory
2. 使用 host groups 和 nested groups
3. 配置 host_vars 和 group_vars
4. 使用 aws_ec2 动态 Inventory 插件

---

## Step 1 — 静态 Inventory 基础

### 1.1 INI 格式

```ini
# inventory.ini

# 单独主机
web1.example.com

# 带别名的主机
node1 ansible_host=10.0.1.10

# 主机组
[webservers]
web1.example.com
web2.example.com

[dbservers]
db1.example.com
db2.example.com

# 组变量
[webservers:vars]
http_port=80
ansible_user=deploy

# 嵌套组
[production:children]
webservers
dbservers
```

### 1.2 YAML 格式

```yaml
# inventory.yaml
all:
  hosts:
    node1:
      ansible_host: 10.0.1.10
  children:
    webservers:
      hosts:
        web1.example.com:
        web2.example.com:
      vars:
        http_port: 80
    dbservers:
      hosts:
        db1.example.com:
    production:
      children:
        webservers:
        dbservers:
```

### 1.3 动手练习：创建你的第一个 Inventory

现在用你的 Lab 节点来练习！

```bash
# 1. 查看当前 inventory（预置的）
cat ~/inventory

# 2. 创建一个新的 inventory 目录
mkdir -p ~/my-inventory

# 3. 创建 INI 格式的 inventory
cat > ~/my-inventory/hosts.ini << 'EOF'
# 我的第一个 Inventory

# 使用实际节点 IP（从 ~/inventory 获取）
[webservers]
node1 ansible_host=10.0.1.53  # 替换为你的实际 IP

[dbservers]
node2 ansible_host=10.0.1.26  # 替换为你的实际 IP

[all:vars]
ansible_python_interpreter=/usr/bin/python3
EOF

# 4. 测试新 inventory
ansible -i ~/my-inventory/hosts.ini all -m ping

# 5. 只测试 webservers 组
ansible -i ~/my-inventory/hosts.ini webservers -m ping
```

**验证问题**：
- `ansible -i ~/my-inventory/hosts.ini webservers -m ping` 应该只返回 node1
- `ansible -i ~/my-inventory/hosts.ini dbservers -m ping` 应该只返回 node2

> 💡 **提示**：获取节点 IP 的命令：
> ```bash
> cat ~/inventory | grep ansible_host
> ```

### 1.4 比较 INI 和 YAML 格式

用示例代码对比两种格式：

```bash
# 查看示例代码（如果已克隆）
cd ~/cloud-atlas/content/middleware/ansible/examples/01-inventory/solution

# 对比 INI 和 YAML
diff 02-with-groups.ini 03-yaml-format.yaml

# 验证两种格式输出相同
ansible-inventory -i 02-with-groups.ini --graph
ansible-inventory -i 03-yaml-format.yaml --graph
```

---

## Step 2 — Host 和 Group 变量

### 2.1 目录结构

```
inventory/
├── hosts              # 主机清单
├── host_vars/         # 主机变量
│   ├── node1.yaml
│   └── node2.yaml
└── group_vars/        # 组变量
    ├── all.yaml       # 所有主机
    ├── webservers.yaml
    └── dbservers.yaml
```

### 2.2 group_vars/all.yaml

```yaml
---
# 所有主机共享的变量
ansible_python_interpreter: /usr/bin/python3
ntp_server: ntp.example.com
timezone: Asia/Tokyo
```

### 2.3 group_vars/webservers.yaml

```yaml
---
http_port: 80
https_port: 443
document_root: /var/www/html
```

### 2.4 host_vars/node1.yaml

```yaml
---
# 主机特定变量
server_role: primary
backup_enabled: true
```

### 2.5 动手练习：创建 group_vars 结构

在你的 Lab 环境中创建完整的 group_vars 结构：

```bash
# 1. 创建目录结构
mkdir -p ~/my-inventory/{group_vars,host_vars}

# 2. 创建 group_vars/all.yaml（所有主机共享）
cat > ~/my-inventory/group_vars/all.yaml << 'EOF'
---
# 所有主机共享变量
ansible_python_interpreter: /usr/bin/python3
env: lab
region: ap-northeast-1
common_packages:
  - htop
  - vim
EOF

# 3. 创建 group_vars/webservers.yaml
cat > ~/my-inventory/group_vars/webservers.yaml << 'EOF'
---
# Webservers 组专用变量
http_port: 80
app_user: www-data
EOF

# 4. 创建 host_vars/node1.yaml（主机特定）
cat > ~/my-inventory/host_vars/node1.yaml << 'EOF'
---
# node1 特定变量（覆盖 group_vars）
http_port: 8080  # 覆盖 webservers.yaml 的值
is_primary: true
EOF

# 5. 验证变量优先级
echo "=== 测试变量优先级 ==="
ansible -i ~/my-inventory/hosts.ini node1 -m debug -a "var=http_port"
ansible -i ~/my-inventory/hosts.ini node2 -m debug -a "var=http_port"
```

**预期结果**：
- `node1` 的 `http_port` = `8080`（来自 host_vars）
- `node2` 的 `http_port` = `undefined`（不在 webservers 组）

> 💡 **变量优先级**（低→高）：
> `group_vars/all` → `group_vars/<group>` → `host_vars/<host>` → 命令行 `-e`

### 2.6 验证变量继承

```bash
# 查看 node1 的所有变量
ansible-inventory -i ~/my-inventory/hosts.ini --host node1

# 应该看到合并后的所有变量
# - env: lab (from all.yaml)
# - http_port: 8080 (from host_vars, 覆盖了 group_vars)
# - is_primary: true (from host_vars)
```

---

## Step 3 — Inventory 命令

### 3.1 常用命令

```bash
# 列出所有主机
ansible-inventory --list

# 图形化显示
ansible-inventory --graph

# 查看特定主机变量
ansible-inventory --host node1

# 使用自定义 inventory
ansible -i inventory.yaml all -m ping
```

### 3.2 动手练习：探索 Inventory 命令

```bash
# 使用你刚创建的 inventory
cd ~/my-inventory

# 1. 查看图形化结构
ansible-inventory -i hosts.ini --graph

# 预期输出:
# @all:
#   |--@dbservers:
#   |  |--node2
#   |--@webservers:
#   |  |--node1
#   |--@ungrouped:

# 2. 查看完整 JSON 格式（便于调试）
ansible-inventory -i hosts.ini --list | head -30

# 3. 查看特定主机的所有变量
ansible-inventory -i hosts.ini --host node1 | jq .

# 4. 查看变量来源（调试利器）
ansible-inventory -i hosts.ini --host node1 --yaml
```

> 💡 **调试技巧**：当变量不生效时，用 `ansible-inventory --host <host>` 查看 Ansible 实际看到的变量值。

---

## Step 4 — 动态 Inventory (aws_ec2)

### 4.1 安装 Amazon AWS Collection

```bash
ansible-galaxy collection install amazon.aws
pip3 install boto3 botocore
```

### 4.2 创建 aws_ec2.yaml

```yaml
# aws_ec2.yaml
plugin: amazon.aws.aws_ec2
regions:
  - ap-northeast-1
  - ap-northeast-3

# 过滤条件
filters:
  instance-state-name: running
  "tag:Environment": production

# 根据标签分组
keyed_groups:
  - key: tags.Role
    prefix: role
  - key: placement.availability_zone
    prefix: az

# 主机变量
hostnames:
  - private-ip-address

# 组合器
compose:
  ansible_host: private_ip_address
```

### 4.3 动手练习：用你的 Lab 测试动态 Inventory

你的 Lab 环境正是 AWS EC2 实例，可以直接测试动态 Inventory！

```bash
# 1. 创建动态 inventory 目录
mkdir -p ~/my-inventory/dynamic

# 2. 创建 aws_ec2.yaml
cat > ~/my-inventory/dynamic/aws_ec2.yaml << 'EOF'
---
plugin: amazon.aws.aws_ec2
regions:
  - ap-northeast-1

# 只获取 ansible-lab 相关实例
filters:
  instance-state-name: running
  "tag:aws:cloudformation:stack-name": ansible-lab

# 根据 Name 标签命名主机
hostnames:
  - tag:Name
  - private-ip-address

# 根据标签创建组
keyed_groups:
  - key: tags.Name
    prefix: name
  - key: instance_type
    prefix: type

# 设置连接变量
compose:
  ansible_host: private_ip_address
  ansible_user: ansible
  ansible_python_interpreter: /usr/bin/python3
EOF

# 3. 测试动态 inventory
ansible-inventory -i ~/my-inventory/dynamic/aws_ec2.yaml --graph
```

**预期输出**（类似）：
```
@all:
  |--@aws_ec2:
  |  |--ansible-lab-control
  |  |--ansible-lab-node1
  |  |--ansible-lab-node2
  |--@type_t3_micro:
  |  |--ansible-lab-node1
  |  |--ansible-lab-node2
  |--@type_t3_small:
  |  |--ansible-lab-control
```

```bash
# 4. 用动态 inventory 执行命令
ansible -i ~/my-inventory/dynamic/aws_ec2.yaml all -m ping

# 5. 只对 t3.micro 实例执行（按实例类型分组）
ansible -i ~/my-inventory/dynamic/aws_ec2.yaml type_t3_micro -m shell -a "hostname"
```

> ⚠️ **注意**：动态 Inventory 需要 AWS 凭证。Lab 的 Control Node 已配置 IAM Role，无需手动配置。

### 4.4 静态 vs 动态 Inventory 选择

| 场景 | 推荐 |
|------|------|
| 开发/测试环境，主机固定 | 静态 INI/YAML |
| 生产环境，Auto Scaling | 动态 aws_ec2 |
| 混合环境 | 两者结合（不同目录） |

---

## Step 5 — 实战：多环境 Inventory

### 5.1 目录结构

```
inventories/
├── dev/
│   ├── hosts.yaml
│   └── group_vars/
│       └── all.yaml
├── staging/
│   ├── hosts.yaml
│   └── group_vars/
│       └── all.yaml
└── production/
    ├── aws_ec2.yaml    # 动态
    └── group_vars/
        └── all.yaml
```

### 5.2 使用特定环境

```bash
# 开发环境
ansible-playbook -i inventories/dev/ playbook.yaml

# 生产环境（动态）
ansible-playbook -i inventories/production/ playbook.yaml
```

---

## Mini-Project：多环境 Inventory

创建 dev/staging/prod 三套 Inventory：

1. **dev/** - 静态 INI，2 台主机
2. **staging/** - 静态 YAML，3 台主机
3. **production/** - 动态 aws_ec2

验证：`ansible-inventory -i inventories/<env>/ --graph`

---

## 动手前检查清单

| # | 检查项 | 验证命令 |
|---|--------|----------|
| 1 | Ansible 已安装 | `ansible --version` |
| 2 | inventory 文件语法正确 | `ansible-inventory -i inventory.yaml --list` |
| 3 | SSH 连接正常 | `ansible all -m ping` |
| 4 | boto3 已安装（动态 Inventory） | `pip3 show boto3` |
| 5 | AWS 凭证配置（动态 Inventory） | `aws sts get-caller-identity` |

---

## 日本企業現場ノート

> 💼 **Inventory 管理的企业实践**

| 要点 | 说明 |
|------|------|
| **環境分離** | dev/staging/prod 三套 Inventory 严格分离 |
| **命名規則** | 主机名使用统一命名规则（如 `{env}-{role}-{seq}`） |
| **変更管理** | Inventory 文件纳入 Git，变更需审批 |
| **機密情報** | `ansible_ssh_pass` 等敏感信息使用 Vault 加密 |
| **動的 Inventory** | 生产环境推荐使用 aws_ec2 插件，避免手动维护 |
| **棚卸し** | 定期核对 Inventory 与实际主机，删除废弃条目 |

```bash
# 验证 Inventory 与实际环境一致性
ansible all -m ping -o | grep -c SUCCESS
```

> 📋 **面试/入场时可能被问**：
> - 「インベントリはどう管理していますか？」→ Git 管理 + 環境別ディレクトリ構成
> - 「本番環境のホストはどう追跡しますか？」→ aws_ec2 動的インベントリ + タグベースのグループ化

---

## 面试要点

> **問題**：動的インベントリのメリットは何ですか？
>
> **回答**：
> - オートスケール環境で自動的にホスト追跡
> - EC2 タグでグループ化（Role, Environment）
> - 手動管理不要、常に最新状態

---

## 本课小结

| 概念 | 要点 |
|------|------|
| INI vs YAML | 两种格式均可，YAML 更结构化 |
| host_vars | 主机级别变量 |
| group_vars | 组级别变量 |
| aws_ec2 | AWS 动态 Inventory 插件 |

---

## 系列导航

← [01 · 环境构築](../01-installation/) | [Home](../) | [Next →](../03-adhoc-modules/)
