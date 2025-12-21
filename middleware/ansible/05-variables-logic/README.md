# 05 · 变量・Facts・条件・循环（Variables, Facts, Conditionals, Loops）

> **目标**：掌握变量、Facts、条件判断和循环
> **前置**：[04 · Playbook 基础](../04-playbook-basics/)
> **时间**：40 分钟
> **实战项目**：多环境配置管理

---

## 将学到的内容

1. 变量优先级
2. Ansible Facts
3. 条件判断（when）
4. 循环（loop）
5. 使用 register 保存输出

---

## 准备环境

```bash
# 1. 切换到 ansible 用户（如果刚登录 Control Node）
sudo su - ansible

# 2. 更新课程仓库（获取最新内容）
cd ~/repo && git pull

# 3. 进入本课目录
cd ~/05-variables-logic

# 4. 确认 Managed Nodes 可连接
ansible all -m ping
```

---

## Step 1 — 变量定义

**三种定义方式**：

```yaml
# 1. Playbook vars
vars:
  http_port: 80

# 2. vars_files
vars_files:
  - vars/main.yaml

# 3. 命令行 (最高优先级)
# ansible-playbook site.yaml -e "http_port=8080"
```

**变量优先级**（简化版）：
```
role defaults < group_vars < host_vars < play vars < extra vars (-e)
```

> 💡 **核心记忆**：`-e` 最高，`role defaults` 最低，`host_vars` > `group_vars`

---

## Step 2 — Ansible Facts

```bash
# 查看所有 Facts
ansible all -m setup | head -50

# 过滤特定 Facts
ansible all -m setup -a "filter=ansible_distribution*"
```

**常用 Facts**：

| Fact | 说明 |
|------|------|
| `ansible_hostname` | 主机名 |
| `ansible_distribution` | 发行版 (Amazon, RedHat) |
| `ansible_os_family` | 系统族 (RedHat, Debian) |
| `ansible_default_ipv4.address` | 默认 IP |

**Magic Variables（特殊变量）**：

Ansible 内置的变量，无需定义即可使用：

| 变量 | 说明 | 示例值 |
|------|------|--------|
| `inventory_hostname` | Inventory 中定义的主机名 | `al2023-1.ans.local` |
| `inventory_hostname_short` | 短主机名（不含域名） | `al2023-1` |
| `group_names` | 当前主机所属的组列表 | `['webservers', 'production']` |
| `groups` | 所有组及其成员 | `{'webservers': ['node1', 'node2']}` |
| `hostvars` | 访问其他主机的变量 | `hostvars['node2'].ansible_host` |

```bash
# 查看 magic variables
ansible all -m debug -a "var=inventory_hostname"
ansible all -m debug -a "var=group_names"
```

> 💡 `inventory_hostname` vs `ansible_hostname`：前者来自 Inventory 文件，后者来自系统 `hostname` 命令。

```bash
# 查看 Facts 使用示例
cat exercises/01-facts-explore.yaml

# 执行
ansible-playbook exercises/01-facts-explore.yaml
```

---

## Step 3 — 条件判断（when）

```bash
# 查看条件判断示例
cat exercises/03-conditionals.yaml
```

**核心语法**：

```yaml
# 基本条件
when: ansible_os_family == "RedHat"

# AND（列表形式）
when:
  - ansible_distribution == "Amazon"
  - ansible_distribution_major_version == "2023"

# OR
when: var1 == "a" or var2 == "b"

# 变量检查
when: my_var is defined
when: my_var | default(false) | bool
```

```bash
# 执行验证
ansible-playbook exercises/03-conditionals.yaml

# 预期: 根据 OS 类型跳过或执行不同任务
```

---

## Step 4 — 循环（loop）

```bash
# 查看循环示例
cat exercises/04-loops-basic.yaml
cat exercises/05-loops-advanced.yaml
```

**核心语法**：

```yaml
# 简单循环
loop:
  - httpd
  - vim

# 字典循环
loop:
  - { name: 'user1', groups: 'wheel' }
  - { name: 'user2', groups: 'users' }

# 循环控制
loop_control:
  index_var: idx
  label: "{{ item.name }}"
```

```bash
# 执行循环示例
ansible-playbook exercises/04-loops-basic.yaml
```

> 💡 `with_items` 是旧语法，新代码请使用 `loop`

---

## Step 5 — Register 保存输出

```bash
# 查看 register 示例
cat exercises/02-register-output.yaml
```

**核心语法**：

```yaml
- name: Run command
  ansible.builtin.command: df -h /
  register: result
  changed_when: false

- name: Show output
  ansible.builtin.debug:
    var: result.stdout_lines
```

**Register 常用属性**：

| 属性 | 说明 |
|------|------|
| `.stdout` | 标准输出 |
| `.stdout_lines` | 按行分割列表 |
| `.rc` | 返回码 |
| `.changed` | 是否变更 |

```bash
# 执行
ansible-playbook exercises/02-register-output.yaml
```

---

## Step 6 — 实战：多环境配置

```bash
# 查看目录结构
ls -la group_vars/

# 查看环境变量
cat group_vars/dev.yaml
cat group_vars/prod.yaml

# 查看多 OS 支持示例
cat exercises/07-multi-os.yaml

# 执行
ansible-playbook exercises/07-multi-os.yaml
```

---

## 动手前检查清单

| # | 检查项 | 验证命令 |
|---|--------|----------|
| 1 | 语法正确 | `ansible-playbook site.yaml --syntax-check` |
| 2 | 变量解析 | `ansible-inventory --host node1 --yaml` |
| 3 | 干运行 | `ansible-playbook site.yaml --check --diff` |

---

## 日本企業現場ノート

> 💼 **变量管理的企业实践**

| 要点 | 说明 |
|------|------|
| **避免 `-e` 滥用** | 生产用 `group_vars`/`host_vars`，`-e` 仅紧急调试 |
| **敏感变量** | 使用 `ansible-vault` 加密 |
| **環境分離** | `group_vars/dev.yaml` 和 `group_vars/prod.yaml` 严格分开 |

> 💡 **面试要点**：変数優先順位で最も高いのは extra_vars (-e)

---

## 本课小结

| 概念 | 要点 |
|------|------|
| 变量优先级 | extra_vars (-e) 最高，role defaults 最低 |
| Facts | ansible_* 系统信息，可禁用加速执行 |
| when | 条件判断，支持 AND/OR/defined |
| loop | 循环执行，优于旧版 with_items |
| register | 保存任务输出 |

---

## 系列导航

← [04 · Playbook](../04-playbook-basics/) | [Home](../) | [Next →](../06-roles-galaxy/)
