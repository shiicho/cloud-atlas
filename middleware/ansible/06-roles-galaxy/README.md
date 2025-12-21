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

## 准备环境

```bash
# 1. 切换到 ansible 用户（如果当前不是 ansible 用户）
[ "$(whoami)" != "ansible" ] && sudo su - ansible

# 2. 更新课程仓库（获取最新内容）
cd ~/repo && git pull

# 3. 进入本课目录
cd ~/06-roles-galaxy

# 4. 确认 Managed Nodes 可连接
ansible all -m ping
```

---

## Step 1 — Role 目录结构

```
roles/rolename/
├── defaults/main.yaml    # 默认变量（最低优先级）
├── vars/main.yaml        # Role 变量（高优先级）
├── tasks/main.yaml       # 任务定义
├── handlers/main.yaml    # Handler 定义
├── templates/*.j2        # Jinja2 模板
├── files/*               # 静态文件
├── meta/main.yaml        # 元信息和依赖
└── README.md             # 文档
```

```bash
# 查看本课示例 Role 结构
tree roles/
```

---

## Step 2 — 创建 Role

```bash
# 创建 Role 骨架
ansible-galaxy role init roles/my_role

# 查看创建的结构
tree roles/my_role
```

```bash
# 查看已有的 common role
cat roles/common/tasks/main.yaml

# 查看已有的 webserver role
cat roles/webserver/tasks/main.yaml
cat roles/webserver/defaults/main.yaml
```

---

## Step 3 — 使用 Role

```bash
# 查看使用 roles 的 Playbook
cat site.yaml
```

**核心语法**：

```yaml
# 基本用法
roles:
  - common
  - webserver

# 传递变量
roles:
  - role: webserver
    vars:
      http_port: 8080

# 条件执行
roles:
  - role: webserver
    when: "'webservers' in group_names"
```

```bash
# 执行
ansible-playbook site.yaml

# 预期输出: 按 common → webserver 顺序执行
```

---

## Step 4 — Ansible Galaxy

```bash
# 搜索 Role
ansible-galaxy search nginx

# 查看 Role 信息
ansible-galaxy info geerlingguy.nginx

# 安装 Role
ansible-galaxy install geerlingguy.nginx -p ./roles/
```

**使用 requirements.yaml**：

```bash
# 查看依赖定义
cat requirements.yaml

# 安装所有依赖
ansible-galaxy install -r requirements.yaml

# 列出已安装
ansible-galaxy list
```

---

## Step 5 — Collections vs Roles

| 特性 | Roles | Collections |
|------|-------|-------------|
| 内容 | 任务、变量、模板 | Roles + Modules + Plugins |
| 用途 | 单一功能封装 | 完整功能包 |
| 命名空间 | 无 | namespace.collection |
| 示例 | geerlingguy.nginx | amazon.aws |

```bash
# 安装 Collection
ansible-galaxy collection install amazon.aws

# 列出已安装
ansible-galaxy collection list
```

---

## Step 6 — 实战：部署 Roles

```bash
# 语法检查
ansible-playbook site.yaml --syntax-check

# 干运行
ansible-playbook site.yaml --check --diff

# 执行部署
ansible-playbook site.yaml

# 验证结果
curl http://web-1.ans.local/
```

---

## 动手前检查清单

| # | 检查项 | 验证命令 |
|---|--------|----------|
| 1 | roles 目录存在 | `ls roles/` |
| 2 | Role 结构完整 | `tree roles/webserver` |
| 3 | 依赖已安装 | `ansible-galaxy list` |
| 4 | 语法检查 | `ansible-playbook site.yaml --syntax-check` |

---

## 日本企業現場ノート

> 💼 **Role 开发的企业实践**

| 要点 | 说明 |
|------|------|
| **命名規則** | Role 名使用统一前缀（如 `company_webserver`） |
| **バージョン管理** | requirements.yml 固定版本号 |
| **テスト必須** | 使用 Molecule 测试 Role |
| **defaults 活用** | 所有可配置项放 `defaults/main.yaml` |

> 💡 **面试要点**：Role は再利用可能なコンポーネント、Playbook は Role を組み合わせた実行単位

---

## 本课小结

| 概念 | 要点 |
|------|------|
| Role | 可重用的任务集合 |
| ansible-galaxy init | 创建 Role 骨架 |
| defaults vs vars | defaults 优先级最低，可被覆盖 |
| requirements.yml | 管理 Role/Collection 依赖 |

---

## 系列导航

← [05 · 变量逻辑](../05-variables-logic/) | [Home](../) | [Next →](../07-jinja2-templates/)
