# 01 · 环境构築（Installation）

> **目标**：部署 Ansible Control Node，准备学习环境
> **前置**：[00 · 概念与架构导入](../00-concepts/)
> **时间**：15-20 分钟
> **费用**：约 $0.02/小时（1 台 t3.small）

---

## 将学到的内容

1. 使用 CloudFormation 部署 Control Node
2. 通过 SSM 连接到实例
3. 验证 Ansible 安装
4. 克隆课程仓库

---

## Step 1 — 部署 Control Node

> 本课使用 AWS Console 部署，无需本地 CLI 环境。

### 1.1 架构概览

```
┌──────────────────────────────────────────────────────────────┐
│                    VPC (10.0.0.0/16)                          │
│                                                               │
│   ┌─────────────────────────────────────────────────────┐    │
│   │               Public Subnet (10.0.1.0/24)           │    │
│   │                                                      │    │
│   │   ┌─────────────────┐    Route 53 Private Zone      │    │
│   │   │ ansible-control │    ┌──────────────────┐       │    │
│   │   │ (t3.small)      │    │ ans.local        │       │    │
│   │   │                 │    │ └─ control.ans.  │       │    │
│   │   │ - Ansible 2.15  │    │    local         │       │    │
│   │   │ - Python 3.9    │    └──────────────────┘       │    │
│   │   │ - AWS CLI       │                               │    │
│   │   └─────────────────┘                               │    │
│   │                                                      │    │
│   └─────────────────────────────────────────────────────┘    │
│                                                               │
│   SSM Session Manager（无需 SSH Key 从外部连接）               │
└──────────────────────────────────────────────────────────────┘
```

### 1.2 通过 Console 部署

**① 下载 CFN 模板**

[cfn/control-node.yaml](https://raw.githubusercontent.com/shiicho/cloud-atlas/main/middleware/ansible/01-installation/cfn/control-node.yaml)

**② 打开 CloudFormation Console**

1. 登录 [AWS Console](https://console.aws.amazon.com/)
2. 搜索 **CloudFormation** 并进入
3. 确认右上角区域为 **ap-northeast-1**（东京）

**③ 创建 Stack**

1. 点击 **Create stack** → **With new resources**
2. 选择 **Upload a template file**
3. 上传 `control-node.yaml`
4. 点击 **下一步 / 次へ**

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
2. 点击 **提交 / 送信**
3. 等待状态变为 **CREATE_COMPLETE**（约 5 分钟）

---

## Step 2 — 连接到 Control Node

### 2.1 使用 SSM Session Manager

1. 打开 [EC2 Console](https://console.aws.amazon.com/ec2/)
2. 在左侧菜单点击 **Instances**
3. 找到 `ansible-control` 实例
4. 选中实例 → 点击 **Connect / 接続**
5. 选择 **Session Manager** 标签页
6. 点击 **Connect / 接続**

### 2.2 切换到 ansible 用户

```bash
sudo su - ansible
```

你现在以 `ansible` 用户登录，这是执行 Ansible 命令的专用用户。

---

## Step 3 — 验证 Ansible 安装

```bash
ansible --version
```

预期输出：

```
ansible [core 2.15.x]
  config file = None
  configured module search path = ['/home/ansible/.ansible/plugins/modules', ...]
  ansible python module location = /usr/lib/python3.9/site-packages/ansible
  executable location = /usr/bin/ansible
  python version = 3.9.x
```

> **说明**：`config file = None` 是正常的。进入课程目录后会自动加载 `ansible.cfg`。

---

## Step 4 — 克隆课程仓库

```bash
# 使用 sparse checkout 只下载 Ansible 课程
git clone --filter=blob:none --sparse https://github.com/shiicho/cloud-atlas ~/repo
cd ~/repo
git sparse-checkout set middleware/ansible

# 创建快捷方式到 home 目录
ln -sf ~/repo/middleware/ansible/* ~/

# 验证
ls ~/
```

你应该看到课程目录链接：`00-concepts`, `01-installation`, `02-inventory`, ...

---

## Step 5 — 了解课程结构

```bash
cd ~/01-installation
ls -la
```

```
.
├── README.md           # 本文档
├── ansible.cfg         # Ansible 配置文件
└── cfn/
    └── control-node.yaml   # 你刚才部署的模板
```

### ansible.cfg 简介

**配置文件优先级（低→高）**：

```
┌─────────────────────────────────────────────────────────────────────┐
│  优先级        位置                        说明                      │
├─────────────────────────────────────────────────────────────────────┤
│  最低 ④    /etc/ansible/ansible.cfg    系统级（apt/dnf 安装时创建） │
│       ③    ~/.ansible.cfg              用户级（对该用户全局生效）   │
│       ②    ./ansible.cfg               项目级（本课程使用此方式 ✓） │
│  最高 ①    ANSIBLE_CONFIG 环境变量      可指定任意路径的配置文件     │
└─────────────────────────────────────────────────────────────────────┘
```

> 💡 **本课程采用项目级配置**（②）：每个课程目录都有独立的 `ansible.cfg`，进入目录后自动生效。这种方式便于管理不同项目的配置。

**动手验证优先级**：

```bash
# 回到 home 目录（无 ansible.cfg）
cd ~
ansible --version | grep config
# → config file = None

# ④ 创建系统级配置（最低优先级）
sudo mkdir -p /etc/ansible
sudo touch /etc/ansible/ansible.cfg
ansible --version | grep config
# → config file = /etc/ansible/ansible.cfg

# ③ 创建用户级配置（覆盖系统级）
touch ~/.ansible.cfg
ansible --version | grep config
# → config file = /home/ansible/.ansible.cfg

# ② 进入有 ansible.cfg 的目录（覆盖用户级）
cd ~/01-installation
ansible --version | grep config
# → config file = /home/ansible/01-installation/ansible.cfg

# ① 使用环境变量（最高优先级，覆盖一切）
touch /tmp/my-custom.cfg
export ANSIBLE_CONFIG=/tmp/my-custom.cfg
ansible --version | grep config
# → config file = /tmp/my-custom.cfg

# 清理测试文件
unset ANSIBLE_CONFIG
rm -f ~/.ansible.cfg /tmp/my-custom.cfg
sudo rm -rf /etc/ansible
```

> 💡 **要点**：高优先级的配置会覆盖低优先级的配置。

**查看本课配置内容**：

```bash
cat ansible.cfg
```

```ini
[defaults]
# No inventory in this lesson - Control Node setup only
# Inventory will be configured in lesson 02
remote_user = ansible
host_key_checking = False

[privilege_escalation]
become = True
become_method = sudo
become_user = root
become_ask_pass = False
```

---

## 本课完成

Control Node 部署完成，Ansible 已就绪。

**下一步**：部署 Managed Nodes 并学习 Inventory 管理。

→ [02 · インベントリ管理](../02-inventory/)

---

## 清理资源

> ⚠️ **保留 Control Node** - 后续课程都需要使用。
>
> 只有在完成所有课程后才删除：
> ```bash
> aws cloudformation delete-stack --stack-name ansible-control
> ```

---

## 系列导航

← [00 · 概念导入](../00-concepts/) | [Home](../) | [Next →](../02-inventory/)
