# 06 · Roles 与 Ansible Galaxy（Roles & Project Structure）

> **目标**：掌握 Role 结构和 Ansible Galaxy  
> **前置**：[05 · 变量与逻辑](../05-variables-logic/)  
> **时间**：40 分钟  
> **实战项目**：创建标准化 Role 库

---

## 将学到的内容

1. Role 目录结构
2. 使用 ansible-galaxy 创建 Role
3. 从 Galaxy 导入社区 Roles
4. Collections vs Roles
5. 管理依赖（requirements.yml）

---

## Step 1 — Role 目录结构

```
roles/
└── webserver/
    ├── defaults/          # 默认变量（最低优先级）
    │   └── main.yaml
    ├── vars/              # Role 变量（高优先级）
    │   └── main.yaml
    ├── tasks/             # 任务定义
    │   └── main.yaml
    ├── handlers/          # Handler 定义
    │   └── main.yaml
    ├── templates/         # Jinja2 模板
    │   └── httpd.conf.j2
    ├── files/             # 静态文件
    │   └── index.html
    ├── meta/              # Role 元信息和依赖
    │   └── main.yaml
    └── README.md          # 文档
```

---

## Step 2 — 创建 Role

### 2.1 使用 ansible-galaxy init

```bash
# 创建 Role 骨架
ansible-galaxy role init roles/webserver

# 查看创建的结构
tree roles/webserver
```

### 2.2 编写 Role

**roles/webserver/defaults/main.yaml**

```yaml
---
http_port: 80
document_root: /var/www/html
server_name: "{{ ansible_hostname }}"
```

**roles/webserver/tasks/main.yaml**

```yaml
---
- name: Install httpd
  ansible.builtin.dnf:
    name: httpd
    state: present

- name: Deploy httpd.conf
  ansible.builtin.template:
    src: httpd.conf.j2
    dest: /etc/httpd/conf/httpd.conf
  notify: Restart httpd

- name: Deploy index.html
  ansible.builtin.copy:
    src: index.html
    dest: "{{ document_root }}/index.html"

- name: Ensure httpd is running
  ansible.builtin.service:
    name: httpd
    state: started
    enabled: true
```

**roles/webserver/handlers/main.yaml**

```yaml
---
- name: Restart httpd
  ansible.builtin.service:
    name: httpd
    state: restarted
```

**roles/webserver/templates/httpd.conf.j2**

```apache
ServerRoot "/etc/httpd"
Listen {{ http_port }}
ServerName {{ server_name }}
DocumentRoot "{{ document_root }}"
```

---

## Step 3 — 使用 Role

### 3.1 基本用法

```yaml
---
- name: Configure web servers
  hosts: webservers
  become: true
  roles:
    - webserver
```

### 3.2 传递变量

```yaml
---
- hosts: webservers
  become: true
  roles:
    - role: webserver
      vars:
        http_port: 8080
        server_name: custom.example.com
```

### 3.3 条件执行

```yaml
---
- hosts: all
  become: true
  roles:
    - role: webserver
      when: "'webservers' in group_names"
```

---

## Step 4 — Role 依赖

**roles/webserver/meta/main.yaml**

```yaml
---
dependencies:
  - role: common
  - role: firewall
    vars:
      firewall_ports:
        - 80
        - 443
```

---

## Step 5 — Ansible Galaxy

### 5.1 搜索 Role

```bash
# 在 galaxy.ansible.com 搜索
ansible-galaxy search nginx

# 查看 Role 信息
ansible-galaxy info geerlingguy.nginx
```

### 5.2 安装 Role

```bash
# 安装单个 Role
ansible-galaxy install geerlingguy.nginx

# 安装到指定目录
ansible-galaxy install geerlingguy.nginx -p ./roles/
```

### 5.3 requirements.yml

```yaml
# requirements.yaml
---
roles:
  - name: geerlingguy.nginx
    version: "3.1.0"
  - name: geerlingguy.docker
  - src: https://github.com/user/role.git
    scm: git
    version: main
    name: custom_role

collections:
  - name: amazon.aws
    version: ">=5.0.0"
  - name: community.general
```

```bash
# 安装所有依赖
ansible-galaxy install -r requirements.yaml
```

---

## Step 6 — Collections vs Roles

| 特性 | Roles | Collections |
|------|-------|-------------|
| 内容 | 任务、变量、模板 | Roles + Modules + Plugins |
| 用途 | 单一功能封装 | 完整功能包 |
| 命名空间 | 无 | namespace.collection |
| 示例 | geerlingguy.nginx | amazon.aws |

### 使用 Collection

```yaml
# 安装
ansible-galaxy collection install amazon.aws

# 在 Playbook 中使用
- name: Create EC2
  amazon.aws.ec2_instance:
    name: my-instance
    instance_type: t3.micro
```

---

## Mini-Project：标准化 Role 库

创建三个 Role：

### 1. common

基础配置（NTP, timezone, 基础包）

```yaml
# roles/common/tasks/main.yaml
- name: Set timezone
  ansible.builtin.timezone:
    name: Asia/Tokyo

- name: Install base packages
  ansible.builtin.dnf:
    name:
      - vim
      - htop
      - tree
    state: present
```

### 2. webserver

Web 服务器配置

### 3. monitoring-agent

监控 Agent（Zabbix Agent 预配置）

### 使用 Roles

```yaml
---
- name: Configure all servers
  hosts: all
  become: true
  roles:
    - common

- name: Configure web servers
  hosts: webservers
  become: true
  roles:
    - webserver
    - monitoring-agent
```

---

## 动手前检查清单

| # | 检查项 | 验证命令 |
|---|--------|----------|
| 1 | roles 目录存在 | `ls roles/` |
| 2 | Role 结构完整 | `tree roles/webserver` |
| 3 | 依赖已安装 | `ansible-galaxy list` |
| 4 | 语法检查 | `ansible-playbook site.yaml --syntax-check` |
| 5 | requirements.yml 格式正确 | `ansible-galaxy install -r requirements.yml --dry-run` |

---

## 日本企業現場ノート

> 💼 **Role 开发的企业实践**

| 要点 | 说明 |
|------|------|
| **命名規則** | Role 名使用统一前缀（如 `company_webserver`） |
| **バージョン管理** | Role 变更需打 tag，requirements.yml 固定版本号 |
| **テスト必須** | 使用 Molecule 测试 Role（`molecule test`） |
| **ドキュメント** | 每个 Role 必须有 README.md 说明参数 |
| **defaults 活用** | 所有可配置项放 `defaults/main.yaml`，便于覆盖 |
| **社内 Galaxy** | 大型组织可搭建私有 Galaxy 服务器 |

```yaml
# requirements.yml - 生产环境务必固定版本
roles:
  - name: geerlingguy.nginx
    version: "3.1.0"   # ← 必须指定版本！
  - name: company.common
    src: git@github.com:company/ansible-role-common.git
    version: v2.3.1    # ← 使用 Git tag
```

> 📋 **面试/入场时可能被问**：
> - 「Role を作るときに気をつけることは？」→ defaults で設定可能に、README 必須、バージョン管理
> - 「既存の Role をどう評価しますか？」→ Galaxy の評価、GitHub Stars、メンテナンス頻度、ライセンス確認

---

## 面试要点

> **問題**：Role と Playbook の使い分けは？
>
> **回答**：
> - Role は再利用可能なコンポーネント（部品）
> - Playbook は Role を組み合わせた実行単位
> - チーム開発では Role 化が標準、変更影響を局所化

---

## 本课小结

| 概念 | 要点 |
|------|------|
| Role | 可重用的任务集合 |
| ansible-galaxy init | 创建 Role 骨架 |
| defaults vs vars | defaults 优先级最低，可被覆盖 |
| requirements.yml | 管理 Role/Collection 依赖 |
| Collections | 包含 Roles + Modules 的完整包 |

---

## 系列导航

← [05 · 变量逻辑](../05-variables-logic/) | [Home](../) | [Next →](../07-jinja2-templates/)
