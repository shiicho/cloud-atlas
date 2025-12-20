# 01 · 环境构築与初期配置（Installation & Configuration）

> **目标**：部署 Ansible Lab 环境，完成初期配置
> **前置**：[00 · 概念与架构导入](../00-concepts/)
> **时间**：30-40 分钟
> **费用**：约 $0.05/小时（3 台 EC2）；完成后请删除堆栈
> **实战项目**：部署 Lab 环境，验证 ansible all -m ping

---

## 将学到的内容

1. 使用 CloudFormation 部署 Ansible Lab
2. 在 Amazon Linux 2023 上安装 Ansible
3. 配置 ansible.cfg
4. 设置 SSH 密钥认证
5. 验证连通性

---

## Step 1 — 部署 Lab 环境

### 1.1 架构概览

```
┌─────────────────────────────────────────────────────────────┐
│                         VPC (10.0.0.0/16)                    │
│                                                              │
│   ┌─────────────────────────────────────────────────────┐   │
│   │                Public Subnet (10.0.1.0/24)           │   │
│   │                                                      │   │
│   │   ┌─────────────┐  ┌─────────────┐  ┌─────────────┐ │   │
│   │   │ ansible-    │  │ ansible-    │  │ ansible-    │ │   │
│   │   │ control     │  │ node1       │  │ node2       │ │   │
│   │   │ (t3.small)  │  │ (t3.micro)  │  │ (t3.micro)  │ │   │
│   │   │             │  │             │  │             │ │   │
│   │   │ 10.0.1.x    │  │ 10.0.1.x    │  │ 10.0.1.x    │ │   │
│   │   └──────┬──────┘  └──────┬──────┘  └──────┬──────┘ │   │
│   │          │                │                │        │   │
│   │          └────── SSH ─────┴──── SSH ───────┘        │   │
│   │                                                      │   │
│   └─────────────────────────────────────────────────────┘   │
│                                                              │
│   SSM 访问（无需 SSH 密钥从外部连接）                          │
└─────────────────────────────────────────────────────────────┘
```

### 1.2 部署 CloudFormation Stack

```bash
# 下载模板（如果需要）
# 模板位置: cfn/ansible-lab.yaml

# 部署堆栈
aws cloudformation create-stack \
  --stack-name ansible-lab \
  --template-body file://cfn/ansible-lab.yaml \
  --capabilities CAPABILITY_IAM

# 等待部署完成
aws cloudformation wait stack-create-complete --stack-name ansible-lab

# 查看输出
aws cloudformation describe-stacks --stack-name ansible-lab \
  --query 'Stacks[0].Outputs' --output table
```

### 1.3 连接到 Control Node

```bash
# 获取 Instance ID
CONTROL_ID=$(aws cloudformation describe-stacks --stack-name ansible-lab \
  --query 'Stacks[0].Outputs[?OutputKey==`ControlNodeInstanceId`].OutputValue' \
  --output text)

# 使用 SSM 连接
aws ssm start-session --target $CONTROL_ID
```

---

## Step 2 — 验证 Ansible 安装

CFN 模板已预装 Ansible，验证安装：

```bash
# 切换到 ansible 用户
sudo su - ansible

# 验证版本
ansible --version
```

预期输出：

```
ansible [core 2.15.x]
  config file = /home/ansible/ansible.cfg
  configured module search path = ...
  ansible python module location = ...
  ansible collection location = ...
  executable location = /usr/bin/ansible
  python version = 3.x.x
```

### 手动安装（参考）

如果需要在其他机器上安装：

```bash
# Amazon Linux 2023 / RHEL 9
sudo dnf install -y ansible-core

# 安装额外 Collections
ansible-galaxy collection install amazon.aws community.general

# 验证
ansible --version
```

---

## Step 3 — 理解 ansible.cfg

### 3.1 配置文件优先级

```
┌─────────────────────────────────────────────────────────────┐
│                  ansible.cfg 优先级（高→低）                  │
│                                                              │
│   1. ANSIBLE_CONFIG 环境变量指定的文件                        │
│   2. ./ansible.cfg (当前目录)           ← 推荐               │
│   3. ~/.ansible.cfg (用户目录)                               │
│   4. /etc/ansible/ansible.cfg (系统级)                       │
└─────────────────────────────────────────────────────────────┘
```

### 3.2 查看当前配置

```bash
# 查看预配置的 ansible.cfg
cat ~/ansible.cfg
```

```ini
[defaults]
inventory = ./inventory
remote_user = ansible
host_key_checking = False

[privilege_escalation]
become = True
become_method = sudo
become_user = root
become_ask_pass = False
```

### 3.3 关键配置项

| 配置项 | 说明 | 默认值 |
|--------|------|--------|
| `inventory` | Inventory 文件路径 | /etc/ansible/hosts |
| `remote_user` | SSH 连接用户 | 当前用户 |
| `host_key_checking` | 是否检查 SSH 主机密钥 | True |
| `become` | 是否启用提权 | False |
| `become_method` | 提权方式 | sudo |

> 💡 **面试要点**
>
> **問題**：ansible.cfg の優先順位を説明してください。
>
> **期望回答**：
> 1. ANSIBLE_CONFIG 環境変数
> 2. カレントディレクトリの ansible.cfg
> 3. ホームディレクトリの ~/.ansible.cfg
> 4. /etc/ansible/ansible.cfg

---

## Step 4 — 配置 SSH 密钥认证

### 4.1 查看 Control Node 公钥

```bash
# 在 Control Node 上
cat ~/.ssh/id_ed25519.pub
```

复制输出的公钥内容。

### 4.2 分发公钥到 Managed Nodes

在另一个终端窗口，连接到 Managed Node 1：

```bash
# 获取 Node1 Instance ID
NODE1_ID=$(aws cloudformation describe-stacks --stack-name ansible-lab \
  --query 'Stacks[0].Outputs[?OutputKey==`ManagedNode1InstanceId`].OutputValue' \
  --output text 2>/dev/null || \
  aws ec2 describe-instances --filters "Name=tag:Name,Values=ansible-lab-node1" \
  --query 'Reservations[0].Instances[0].InstanceId' --output text)

aws ssm start-session --target $NODE1_ID
```

在 Managed Node 上添加公钥：

```bash
# 切换到 ansible 用户
sudo su - ansible

# 添加公钥（替换为实际公钥）
echo "ssh-ed25519 AAAA... ansible@control" >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
```

对 Node2 重复相同操作。

### 4.3 验证 SSH 连接

回到 Control Node：

```bash
# 获取 Managed Node IP（查看 inventory）
cat ~/inventory

# 测试 SSH 连接
ssh ansible@<node1_ip> "hostname"
ssh ansible@<node2_ip> "hostname"
```

---

## Step 5 — 验证 Ansible 连通性

### 5.1 使用 ping 模块

```bash
# 测试所有主机
ansible all -m ping
```

预期输出：

```
node1 | SUCCESS => {
    "changed": false,
    "ping": "pong"
}
node2 | SUCCESS => {
    "changed": false,
    "ping": "pong"
}
```

### 5.2 测试特定组

```bash
# 测试 webservers 组
ansible webservers -m ping

# 测试 dbservers 组
ansible dbservers -m ping
```

### 5.3 收集系统信息

```bash
# 收集 Facts（系统信息）
ansible all -m setup -a "filter=ansible_distribution*"
```

---

## Step 6 — 常见问题排查

### 问题 1：SSH 连接失败

```
node1 | UNREACHABLE! => {
    "msg": "Failed to connect to the host via ssh..."
}
```

**排查步骤**：

```bash
# 1. 验证 SSH 密钥
ssh -v ansible@<node_ip>

# 2. 检查 Security Group
# 确认 Control Node SG 允许访问 Managed Node SG 的 22 端口

# 3. 检查 authorized_keys
# 在 Managed Node 上：
cat /home/ansible/.ssh/authorized_keys
```

### 问题 2：Python 解释器警告

```
[WARNING]: Platform linux on host node1 is using the discovered Python interpreter at /usr/bin/python3...
```

**解决**：在 inventory 中指定 Python 解释器：

```ini
[all:vars]
ansible_python_interpreter=/usr/bin/python3
```

### 问题 3：权限不足

```
node1 | FAILED! => {
    "msg": "Missing sudo password"
}
```

**解决**：确认 sudoers 配置：

```bash
# 在 Managed Node 上检查
sudo cat /etc/sudoers.d/ansible
# 应包含: ansible ALL=(ALL) NOPASSWD:ALL
```

---

## Mini-Project：Lab 环境部署

> **场景**：作为基础设施工程师，部署 Ansible 测试环境。

### 要求

1. **部署 CFN Stack**
   - 确认 3 台 EC2 正常运行
   - 记录所有 Private IP

2. **配置 SSH 认证**
   - 在 Control Node 生成密钥（已完成）
   - 分发公钥到 Managed Nodes

3. **验证连通性**
   - `ansible all -m ping` 成功
   - `ansible all -m setup -a "filter=ansible_distribution"` 成功

4. **记录环境信息**（填写下表）

| 项目 | 值 |
|------|-----|
| Control Node IP | |
| Node1 IP | |
| Node2 IP | |
| Ansible Version | |
| Python Version | |

---

## 常见错误

| 错误 | 原因 | 解决方案 |
|------|------|----------|
| `UNREACHABLE` | SSH 连接失败 | 检查密钥、Security Group |
| `Permission denied` | 密钥未添加 | 添加公钥到 authorized_keys |
| `sudo: a password is required` | sudoers 配置问题 | 检查 /etc/sudoers.d/ansible |

---

## 清理资源

完成学习后，删除堆栈避免产生费用：

```bash
aws cloudformation delete-stack --stack-name ansible-lab

# 确认删除完成
aws cloudformation wait stack-delete-complete --stack-name ansible-lab
```

---

## 本课小结

| 概念 | 要点 |
|------|------|
| Lab 架构 | Control Node + 2 Managed Nodes |
| ansible.cfg | 优先级：环境变量 > 当前目录 > 用户目录 > 系统 |
| SSH 认证 | 公钥分发到 Managed Nodes |
| 验证命令 | `ansible all -m ping` |

---

## 下一步

环境就绪，开始学习 Inventory 管理。

→ [02 · インベントリ管理](../02-inventory/)

---

## 系列导航

← [00 · 概念导入](../00-concepts/) | [Home](../) | [Next →](../02-inventory/)
