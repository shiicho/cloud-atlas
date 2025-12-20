# 02 · インベントリ管理（Static & Dynamic Inventory）

> **目标**：掌握静态和动态 Inventory 管理
> **前置**：[01 · 环境构築](../01-installation/)
> **时间**：30 分钟
> **实战项目**：创建多环境 Inventory 结构

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

---

## Step 3 — Inventory 命令

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

### 4.3 测试动态 Inventory

```bash
# 验证配置
ansible-inventory -i aws_ec2.yaml --graph

# 使用动态 Inventory
ansible -i aws_ec2.yaml all -m ping
```

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
