# 01 · 环境构築与初期配置（Installation & Configuration）

> **目标**：部署 Ansible Lab 环境，完成初期配置
> **前置**：[00 · 概念与架构导入](../00-concepts/)
> **时间**：30-40 分钟
> **费用**：约 $0.05/小时（3 台 EC2）

---

## 将学到的内容

1. 使用 CloudFormation 部署 Ansible Lab
2. 验证 Ansible 安装
3. 配置 ansible.cfg
4. **手动设置 SSH 密钥认证**（本课重点）
5. 验证连通性

---

## Step 1 — 部署 Control Node（AWS Console）

> 本课使用 AWS Console（控制台）部署，无需本地 CLI 环境。

### 1.1 架构概览

```
┌──────────────────────────────────────────────────────────────┐
│                         VPC (10.0.0.0/16)                     │
│                                                               │
│   ┌─────────────────────────────────────────────────────┐    │
│   │                Public Subnet (10.0.1.0/24)           │    │
│   │                                                      │    │
│   │   ┌─────────────┐  ┌─────────────┐  ┌─────────────┐ │    │
│   │   │ ansible-    │  │ node1-      │  │ node2-      │ │    │
│   │   │ control     │  │ webserver   │  │ dbserver    │ │    │
│   │   │ (t3.small)  │  │ (t3.micro)  │  │ (t3.micro)  │ │    │
│   │   └──────┬──────┘  └──────┬──────┘  └──────┬──────┘ │    │
│   │          │                │                │        │    │
│   │          └────── SSH ─────┴──── SSH ───────┘        │    │
│   │                                                      │    │
│   └─────────────────────────────────────────────────────┘    │
│                                                               │
│   SSM 访问（无需 SSH 密钥从外部连接）                           │
└──────────────────────────────────────────────────────────────┘
```

### 1.2 通过 Console 部署 Control Node

**① 下载 CFN 模板**

从 GitHub 下载模板文件：[cfn/control-node.yaml](https://raw.githubusercontent.com/shiicho/cloud-atlas/main/middleware/ansible/01-installation/cfn/control-node.yaml)

或在本仓库：`01-installation/cfn/control-node.yaml`

**② 打开 CloudFormation Console**

1. 登录 [AWS Console](https://console.aws.amazon.com/)
2. 搜索 **CloudFormation** 并进入
3. 确认右上角区域为 **ap-northeast-1**（东京）

**③ 创建 Stack**

1. 点击 **Create stack** → **With new resources**
2. 选择 **Upload a template file**
3. 点击 **Choose file**，上传 `control-node.yaml`
4. 点击 **Next**

**④ 配置 Stack**

| 项目 | 值 |
|------|-----|
| Stack name | `ansible-control` |
| InstanceType | `t3.small`（默认） |

点击 **下一步 / 次へ** → **下一步 / 次へ**

**⑤ 确认并创建**

1. 勾选 IAM 资源确认框：
   - 中文：**我确认，AWS CloudFormation 可能创建 IAM 资源。**
   - 日本語：**AWS CloudFormation によって IAM リソースが作成される場合があることを承認します。**
2. 点击 **下一步 / 次へ** 或 **提交 / 送信**
3. 等待状态变为 **CREATE_COMPLETE**（约 5 分钟）

### 1.3 连接到 Control Node

**① 获取 Instance ID**

Stack 创建完成后：
1. 点击 **Outputs** 标签页
2. 找到 `ControlNodeId`，复制值（如 `i-0abc123def456`）

**② 使用 SSM 连接**

1. 打开 [EC2 Console](https://console.aws.amazon.com/ec2/)
2. 在左侧菜单点击 **Instances**
3. 找到 `ansible-control` 实例
4. 选中实例 → 点击 **Connect**
5. 选择 **Session Manager** 标签页
6. 点击 **Connect**

**③ 切换到 ansible 用户**

```bash
sudo su - ansible
```

---

## Step 2 — 部署 Managed Nodes

现在你已经在 Control Node 上了，可以使用 CLI 部署 Managed Nodes。

```bash
# 使用 sparse checkout 只下载 Ansible 课程
git clone --filter=blob:none --sparse https://github.com/shiicho/cloud-atlas ~/repo
cd ~/repo
git sparse-checkout set middleware/ansible

# 创建快捷方式到 home 目录
ln -s ~/repo/middleware/ansible/* ~/

# 进入课程目录
cd ~/01-installation

# 部署 Managed Nodes（无自动 SSH，用于学习手动配置）
aws cloudformation create-stack \
  --stack-name ansible-lesson-01 \
  --template-body file://cfn/managed-nodes.yaml \
  --capabilities CAPABILITY_NAMED_IAM

# 等待完成（约 3 分钟）
aws cloudformation wait stack-create-complete --stack-name ansible-lesson-01

# 获取节点信息
aws cloudformation describe-stacks --stack-name ansible-lesson-01 \
  --query 'Stacks[0].Outputs' --output table
```

---

## Step 3 — 验证 Ansible 安装

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

<details>
<summary>💡 输出解读（点击展开）</summary>

| 行 | 含义 |
|---|------|
| `ansible [core 2.15.x]` | Ansible Core 版本号 |
| `config file` | 当前生效的配置文件路径，优先级：`$ANSIBLE_CONFIG` > `./ansible.cfg` > `~/.ansible.cfg` > `/etc/ansible/ansible.cfg` |
| `configured module search path` | 自定义模块搜索路径 |
| `ansible python module location` | Ansible Python 库安装位置 |
| `ansible collection location` | Collections 安装目录（`~/.ansible/collections`） |
| `executable location` | `ansible` 命令的实际路径 |
| `python version` | Ansible 使用的 Python 版本（需 3.9+） |

> **排错提示**：如果 `config file = None`，说明没有找到配置文件，Ansible 将使用默认值。

</details>

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

## Step 4 — 理解 ansible.cfg

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

### 3.2 动手验证优先级

让我们亲手验证配置文件优先级。这是理解 Ansible 行为的关键！

**① 无配置文件时**

如果没有任何 ansible.cfg，Ansible 会显示 `config file = None`：

```bash
[ansible@ip-10-0-1-180 ~]$ ansible --version
ansible [core 2.15.3]
  config file = None      # ← 没有找到配置文件
  configured module search path = ['/home/ansible/.ansible/plugins/modules', '/usr/share/ansible/plugins/modules']
  ansible python module location = /usr/lib/python3.9/site-packages/ansible
  ...
```

**② 创建系统级配置文件**

```bash
# 需要 root 权限
sudo touch /etc/ansible/ansible.cfg

# 再次检查
ansible --version
```

输出变化：
```bash
[ansible@ip-10-0-1-180 ~]$ ansible --version
ansible [core 2.15.3]
  config file = /etc/ansible/ansible.cfg    # ← 找到系统级配置
  ...
```

**③ 用户目录优先级更高**

```bash
# 在用户 home 目录创建配置
touch ~/ansible.cfg

ansible --version
```

输出：
```bash
[ansible@ip-10-0-1-180 ~]$ ansible --version
ansible [core 2.15.3]
  config file = /home/ansible/ansible.cfg   # ← 用户目录覆盖系统级
  ...
```

**④ 当前目录优先级最高**

```bash
# 创建子目录并复制配置
mkdir testdir && cd testdir
cp ~/ansible.cfg .

ansible --version
```

输出：
```bash
[ansible@ip-10-0-1-180 testdir]$ ansible --version
ansible [core 2.15.3]
  config file = /home/ansible/testdir/ansible.cfg   # ← 当前目录最优先
  ...
```

> 💡 **关键理解**
>
> 这就是为什么推荐每个项目都有自己的 `ansible.cfg`！
> 放在项目根目录（当前目录）的配置会覆盖所有其他配置，确保项目环境隔离。

### 3.3 查看预配置的 ansible.cfg

```bash
# 查看 Lab 预配置的 ansible.cfg
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

### 3.4 关键配置项

| 配置项 | 说明 | 默认值 |
|--------|------|--------|
| `inventory` | Inventory 文件路径 | /etc/ansible/hosts |
| `remote_user` | SSH 连接用户 | 当前用户 |
| `host_key_checking` | 是否检查 SSH 主机密钥 | True |
| `become` | 是否启用提权 | False |
| `become_method` | 提权方式 | sudo |

> ⚠️ **安全警告：`host_key_checking=False`**
>
> 本 Lab 为了简化流程设置 `host_key_checking=False`，**生产环境绝对禁止这样做！**
>
> | 环境 | 推荐做法 |
> |------|----------|
> | **Lab/测试** | `host_key_checking=False` 可接受 |
> | **生产环境** | 必须 `True`，提前分发 `known_hosts` |
>
> 生产环境正确做法：
> ```bash
> # 1. 收集所有主机指纹
> ssh-keyscan -H node1 node2 node3 >> ~/.ssh/known_hosts
>
> # 2. 或使用 Ansible 预先分发
> ansible all -m known_hosts -a "name={{ inventory_hostname }} key={{ lookup('pipe', 'ssh-keyscan ' + inventory_hostname) }}"
> ```
>
> 禁用 host key 检查会让[中间人攻击（MITM）](../../../glossary/devops/mitm-attack.md)成为可能，攻击者可以伪装成目标服务器截获你的命令和数据。

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

## Step 5 — 配置 SSH 密钥认证

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

# 确保 .ssh 目录存在且权限正确
install -d -m700 ~/.ssh

# 添加公钥（用 heredoc 避免复制粘贴错误）
cat <<'EOF' >> ~/.ssh/authorized_keys
ssh-ed25519 AAAA...your-actual-key... ansible@control
EOF

# 设置正确权限
chmod 600 ~/.ssh/authorized_keys
chown -R ansible:ansible ~/.ssh
```

> ⚠️ **常见错误**：直接用 `echo` 粘贴公钥容易出现换行符/空格问题。使用 `cat <<'EOF'` 更可靠。

对 Node2 重复相同操作。

### 4.3 验证 SSH 连接

回到 Control Node，测试能否 SSH 到 Managed Nodes：

```bash
# 1. 先查看 inventory 文件（使用 DNS 名称）
cat ~/01-installation/inventory/hosts.ini
```

输出：
```ini
[webservers]
al2023-1.ans.local

[dbservers]
al2023-2.ans.local

[all:vars]
ansible_python_interpreter=/usr/bin/python3
```

```bash
# 2. 使用 DNS 名称测试 SSH
ssh ansible@al2023-1.ans.local "hostname"
ssh ansible@al2023-2.ans.local "hostname"
```

首次连接会提示确认主机指纹，输入 `yes`：
```
The authenticity of host 'al2023-1.ans.local' can't be established.
ED25519 key fingerprint is SHA256:xxxxx...
Are you sure you want to continue connecting (yes/no)? yes
```

成功后会输出目标机器的 hostname：
```
al2023-1
```

---

## Step 6 — Ansible 初体验

### 5.0 动手前检查清单

在执行 Ansible 命令之前，确认以下项目都已完成：

| # | 检查项 | 验证命令 | 预期结果 |
|---|--------|----------|----------|
| 1 | ansible 用户已登录 | `whoami` | `ansible` |
| 2 | inventory 文件存在 | `cat ~/inventory` | 显示 node1, node2 |
| 3 | SSH 密钥已生成 | `ls ~/.ssh/id_ed25519` | 文件存在 |
| 4 | 可以 SSH 到 node1 | `ssh node1 hostname` | 返回主机名 |
| 5 | 可以 SSH 到 node2 | `ssh node2 hostname` | 返回主机名 |

> 💡 如果任何一项失败，请回到对应的 Step 排查问题。

环境配置完成，来尝试第一条 Ansible 命令！

### 5.1 Ansible 命令格式

先了解命令结构，后面的命令都遵循这个模式：

```
ansible  <目标>  -m <模块>  -a "<参数>"  [选项]
   │       │        │          │          │
   │       │        │          │          └── 可选：-b(sudo) -v(详细) -i(inventory)
   │       │        │          └── 传给模块的参数
   │       │        └── 使用哪个模块（ping/shell/copy/dnf...）
   │       └── 对谁执行（all/webservers/node1...）
   └── Ansible 命令
```

| 部分 | 说明 | 示例 |
|------|------|------|
| `<目标>` | 主机或组名 | `all`, `webservers`, `node1` |
| `-m <模块>` | 执行什么操作 | `-m ping`, `-m shell`, `-m copy` |
| `-a "<参数>"` | 模块需要的参数 | `-a "name=httpd state=started"` |
| `-b` | 用 sudo 执行 | `ansible all -b -m dnf ...` |
| `-v/-vv/-vvv` | 显示详细信息 | 调试时使用 |

### 5.2 动手试试

理解了格式，来试几条命令：

**① 测试连通性（ping 模块）**

```bash
ansible all -m ping
```

> 这不是 ICMP ping，而是 Ansible 通过 SSH 连接目标机器并执行 Python 测试。

<details>
<summary>🔍 ping 模块背后发生了什么？（点击展开）</summary>

```
Control Node                              Managed Node
     │                                         │
     │  1. SSH 连接                             │
     ├────────────────────────────────────────▶│
     │                                         │
     │  2. 创建临时目录 ~/.ansible/tmp/         │
     ├────────────────────────────────────────▶│
     │                                         │
     │  3. 上传 ping 模块（Python 脚本）         │
     ├────────────────────────────────────────▶│
     │                                         │
     │  4. 执行: python3 ping.py               │
     │     └── 测试 Python 是否正常工作         │
     ├────────────────────────────────────────▶│
     │                                         │
     │  5. 返回结果 {"ping": "pong"}           │
     │◀────────────────────────────────────────┤
     │                                         │
     │  6. 清理临时文件                         │
     ├────────────────────────────────────────▶│
     │                                         │
```

**所以 `ping` 模块实际验证了：**
- ✅ SSH 连接正常
- ✅ 目标机器有 Python
- ✅ 用户有执行权限
- ✅ 临时目录可写

**与 ICMP ping 的区别：**

| | ICMP ping | Ansible ping |
|---|-----------|--------------|
| 协议 | ICMP | SSH + Python |
| 验证 | 网络可达 | SSH + Python + 权限 |
| 返回 | 延迟(ms) | `pong` 或错误信息 |

</details>

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

**② 只测试某个组**

```bash
ansible webservers -m ping    # 只测试 [webservers] 组
ansible dbservers -m ping     # 只测试 [dbservers] 组
```

**③ 执行远程命令（shell 模块）**

```bash
ansible all -m shell -a "hostname"           # 查看主机名
ansible all -m shell -a "df -h /"            # 查看磁盘使用
ansible all -m shell -a "cat /etc/os-release | head -2"  # 查看系统版本
```

**④ 收集系统信息（setup 模块）**

```bash
ansible all -m setup -a "filter=ansible_distribution*"
```

> `setup` 模块收集目标机器的所有系统信息（称为 Facts），`filter` 参数过滤只显示发行版相关信息。

<details>
<summary>💡 更多初体验命令（点击展开）</summary>

```bash
# 查看内存
ansible all -m shell -a "free -m"

# 查看 CPU 信息
ansible all -m setup -a "filter=ansible_processor*"

# 查看所有网络接口
ansible all -m setup -a "filter=ansible_interfaces"

# 查看运行时间
ansible all -m shell -a "uptime"
```

</details>

### 5.3 体验幂等性（Idempotency）

幂等性是 Ansible 的核心特性——**同一操作执行多次，结果不变**。

用 `dnf` 模块安装 htop，执行两次观察区别：

```bash
# 第一次执行：htop 未安装 → 会安装
ansible all -b -m dnf -a "name=htop state=present"
```

输出（注意 `CHANGED` 和 `"changed": true`）：
```
node1 | CHANGED => {
    "changed": true,
    "msg": "",
    "rc": 0,
    "results": ["Installed: htop-3.2.1-87.amzn2023.0.3.x86_64"]
}
```

```bash
# 第二次执行：htop 已安装 → 什么都不做
ansible all -b -m dnf -a "name=htop state=present"
```

输出（注意 `SUCCESS` 和 `"changed": false`）：
```
node1 | SUCCESS => {
    "changed": false,
    "msg": "Nothing to do",
    "rc": 0,
    "results": []
}
```

| 执行次数 | changed | 实际行为 |
|----------|---------|----------|
| 第 1 次 | `true` | 安装 htop |
| 第 2 次 | `false` | 检测已安装，跳过 |
| 第 N 次 | `false` | 检测已安装，跳过 |

**反向操作：卸载 htop**

```bash
# 卸载 htop（state=absent）
ansible all -b -m dnf -a "name=htop state=absent"
```

输出：
```
node1 | CHANGED => {
    "changed": true,
    "msg": "",
    "rc": 0,
    "results": ["Removed: htop-3.2.1-87.amzn2023.0.3.x86_64"]
}
```

```bash
# 再执行一次：已经不存在 → 什么都不做
ansible all -b -m dnf -a "name=htop state=absent"
```

输出：
```
node1 | SUCCESS => {
    "changed": false,
    "msg": "Nothing to do",
    "rc": 0,
    "results": []
}
```

| state | 含义 | 幂等行为 |
|-------|------|----------|
| `present` | 确保已安装 | 已装→跳过，未装→安装 |
| `absent` | 确保未安装 | 已装→卸载，未装→跳过 |
| `latest` | 确保最新版 | 有新版→升级，已最新→跳过 |

> 💡 **为什么这很重要？**
>
> 你可以放心地重复执行 Playbook（比如定时任务、CI/CD），Ansible 只会执行「需要变更」的部分。这与 shell 脚本最大的区别——shell 脚本重复执行可能导致重复安装、配置覆盖等问题。
>
> → 详细了解：[幂等性（Idempotency）](../../../glossary/devops/idempotency.md)

### 5.4 获取课程示例代码

环境验证完成后，下载课程配套的示例代码：

```bash
# 克隆课程示例仓库
git clone https://github.com/shiicho/cloud-atlas.git ~/cloud-atlas

# 进入 Ansible 示例目录
cd ~/cloud-atlas/content/middleware/ansible/examples

# 查看目录结构
ls -la
```

**示例库结构**：

```
examples/
├── 01-inventory/        # Inventory 格式示例
├── 02-playbook-basics/  # Playbook 基础
├── 03-variables-logic/  # 变量与条件
├── 04-loops/            # 循环示例（12 种）
├── 05-async-serial/     # 异步与串行
├── 06-roles-galaxy/     # Roles 结构
├── 07-aws-ssm/          # AWS SSM 集成
├── 08-error-handling/   # 错误处理
└── 09-vault/            # 密钥管理
```

**使用方法**：

```bash
# 直接运行示例
ansible-playbook 02-playbook-basics/solution/01-minimal-play.yaml

# 比较两个版本的差异（理解增量变化）
diff 02-playbook-basics/solution/01-minimal-play.yaml \
     02-playbook-basics/solution/02-with-vars.yaml
```

> 💡 **学习技巧**
>
> 每个主题都有 `template/`（空白骨架）和 `solution/01-0n/`（递进解决方案）。
> 先看 template，自己尝试，再对比 solution，最后用 `diff` 理解每步变化。

---

## Step 7 — 常见问题排查

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

## 日本企業現場ノート

> 💼 **在日本 SIer/企业工作时的注意事项**

日本企业（特别是金融、制造业）对自动化工具有严格的管理要求：

| 要求 | 说明 | 对应措施 |
|------|------|----------|
| **変更管理** | 所有变更需申请・承認 | Playbook 需提前审批，禁止直接执行 ad-hoc 命令 |
| **監査ログ** | 谁在什么时候做了什么 | 使用 `ANSIBLE_LOG_PATH` 或 AWX/AAP |
| **環境分離** | 本番環境隔离 | Control Node 专用跳板机，inventory 分环境管理 |
| **権限管理** | 最小権限原則 | ansible 用户按需授权，避免 `ALL=(ALL)` |

```bash
# 生产环境必备：开启日志记录
export ANSIBLE_LOG_PATH=~/ansible-$(date +%Y%m%d).log

# 每次执行前确认目标环境
ansible-inventory --list | head -20
```

> 📋 **面试/入场时可能被问**：「Ansible の実行ログはどこに保存されますか？」「変更管理はどうしていますか？」

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
