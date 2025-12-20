# 05 · 变量・Facts・条件・循环（Variables, Facts, Conditionals, Loops）

> **目标**：掌握变量、Facts、条件判断和循环
> **前置**：[04 · Playbook 基础](../04-playbook-basics/)
> **时间**：40 分钟
> **实战项目**：多环境配置管理

---

## 将学到的内容

1. 变量优先级（22 levels）
2. Ansible Facts
3. 条件判断（when）
4. 循环（loop）
5. 使用 register 保存输出

---

## Step 1 — 变量定义

### 1.1 在 Playbook 中定义

```yaml
---
- name: Variable demo
  hosts: all
  vars:
    http_port: 80
    app_name: myapp
    packages:
      - httpd
      - vim
```

### 1.2 在 vars_files 中定义

```yaml
# vars/main.yaml
http_port: 80
app_name: myapp

# playbook.yaml
- hosts: all
  vars_files:
    - vars/main.yaml
```

### 1.3 命令行传入

```bash
ansible-playbook site.yaml -e "http_port=8080"
ansible-playbook site.yaml -e "@vars.json"
```

---

## Step 2 — 变量优先级

从低到高（后者覆盖前者）：

```
 1. role defaults
 2. inventory file vars
 3. inventory group_vars/all
 4. inventory group_vars/<group>
 5. inventory host_vars/<host>
 6. playbook group_vars/all
 7. playbook group_vars/<group>
 8. playbook host_vars/<host>
 9. host facts
10. play vars
11. play vars_prompt
12. play vars_files
13. role vars
14. block vars
15. task vars
16. include_vars
17. set_facts
18. registered vars
19. role parameters
20. include parameters
21. extra vars (-e)  ← 最高优先级
```

> 💡 **面试要点**
>
> **問題**：変数の優先順位で最も高いのは？
>
> **回答**：extra_vars (-e) が最優先。デバッグや緊急時に使用。

---

## Step 3 — Ansible Facts

### 3.1 收集 Facts

```bash
# 查看所有 Facts
ansible node1 -m setup

# 过滤特定 Facts
ansible node1 -m setup -a "filter=ansible_distribution*"
```

### 3.2 常用 Facts

| Fact | 说明 |
|------|------|
| `ansible_hostname` | 主机名 |
| `ansible_distribution` | 发行版 (Amazon, RedHat) |
| `ansible_os_family` | 系统族 (RedHat, Debian) |
| `ansible_memtotal_mb` | 总内存 (MB) |
| `ansible_processor_vcpus` | CPU 核数 |
| `ansible_default_ipv4.address` | 默认 IP |

### 3.3 在 Playbook 中使用

```yaml
- name: Show facts
  hosts: all
  tasks:
    - name: Display OS info
      ansible.builtin.debug:
        msg: "OS: {{ ansible_distribution }} {{ ansible_distribution_version }}"

    - name: Display memory
      ansible.builtin.debug:
        msg: "Memory: {{ ansible_memtotal_mb }} MB"
```

### 3.4 禁用 Facts 收集

```yaml
- hosts: all
  gather_facts: false   # 加速执行
  tasks:
    - name: Quick task
      ansible.builtin.ping:
```

---

## Step 4 — 条件判断（when）

```yaml
- name: Conditional tasks
  hosts: all
  tasks:
    # 基本条件
    - name: Install on RedHat
      ansible.builtin.dnf:
        name: httpd
        state: present
      when: ansible_os_family == "RedHat"

    # 多条件（AND）
    - name: Install on Amazon Linux 2023
      ansible.builtin.dnf:
        name: httpd
      when:
        - ansible_distribution == "Amazon"
        - ansible_distribution_major_version == "2023"

    # OR 条件
    - name: Install on RedHat or Amazon
      ansible.builtin.dnf:
        name: httpd
      when: ansible_os_family == "RedHat" or ansible_distribution == "Amazon"

    # 变量存在检查
    - name: Run if var defined
      ansible.builtin.debug:
        msg: "Variable is {{ my_var }}"
      when: my_var is defined

    # 布尔条件
    - name: Run if enabled
      ansible.builtin.debug:
        msg: "Feature enabled"
      when: feature_enabled | default(false) | bool
```

---

## Step 5 — 循环（loop）

### 5.1 简单循环

```yaml
- name: Install packages
  ansible.builtin.dnf:
    name: "{{ item }}"
    state: present
  loop:
    - httpd
    - vim
    - htop
```

### 5.2 字典循环

```yaml
- name: Create users
  ansible.builtin.user:
    name: "{{ item.name }}"
    groups: "{{ item.groups }}"
    state: present
  loop:
    - { name: 'user1', groups: 'wheel' }
    - { name: 'user2', groups: 'users' }
```

### 5.3 with_items（旧语法）

```yaml
# 旧语法，仍然可用
- name: Install packages
  ansible.builtin.dnf:
    name: "{{ item }}"
  with_items:
    - httpd
    - vim
```

### 5.4 循环控制

```yaml
- name: Loop with index
  ansible.builtin.debug:
    msg: "{{ index }}: {{ item }}"
  loop:
    - apple
    - banana
    - orange
  loop_control:
    index_var: index
    label: "{{ item }}"   # 简化输出
```

---

## Step 6 — Register 保存输出

```yaml
- name: Register demo
  hosts: all
  tasks:
    - name: Check disk space
      ansible.builtin.shell: df -h /
      register: disk_result

    - name: Display result
      ansible.builtin.debug:
        var: disk_result.stdout_lines

    - name: Fail if disk usage > 80%
      ansible.builtin.fail:
        msg: "Disk usage too high!"
      when: "'80%' in disk_result.stdout"
```

### Register 常用属性

| 属性 | 说明 |
|------|------|
| `.stdout` | 标准输出 |
| `.stdout_lines` | 输出按行分割的列表 |
| `.stderr` | 标准错误 |
| `.rc` | 返回码 |
| `.changed` | 是否有变更 |
| `.failed` | 是否失败 |

---

## Mini-Project：多环境配置

### 目录结构

```
multi-env/
├── site.yaml
├── group_vars/
│   ├── all.yaml
│   ├── dev.yaml
│   └── prod.yaml
└── inventory.yaml
```

### group_vars/dev.yaml

```yaml
env_name: development
debug_enabled: true
log_level: DEBUG
instances: 1
```

### group_vars/prod.yaml

```yaml
env_name: production
debug_enabled: false
log_level: INFO
instances: 3
```

### site.yaml

```yaml
---
- name: Multi-environment config
  hosts: all
  tasks:
    - name: Display environment
      ansible.builtin.debug:
        msg: "Environment: {{ env_name }}"

    - name: Enable debug mode
      ansible.builtin.debug:
        msg: "Debug mode enabled"
      when: debug_enabled | bool

    - name: Configure based on OS
      ansible.builtin.debug:
        msg: "Configuring for {{ ansible_distribution }}"
      when: ansible_os_family == "RedHat"
```

---

## 本课小结

| 概念 | 要点 |
|------|------|
| 变量优先级 | extra_vars (-e) 最高 |
| Facts | ansible_* 系统信息 |
| when | 条件判断 |
| loop | 循环执行 |
| register | 保存任务输出 |

---

## 系列导航

← [04 · Playbook](../04-playbook-basics/) | [Home](../) | [Next →](../06-roles-galaxy/)
