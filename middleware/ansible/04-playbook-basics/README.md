# 04 · Playbook 基础（YAML, Tasks, Handlers）

> **目标**：掌握 Playbook 基础结构  
> **前置**：[03 · Ad-hoc 命令](../03-adhoc-modules/)  
> **时间**：40 分钟  
> **实战项目**：编写 Web 服务器部署 Playbook

---

## 将学到的内容

1. YAML 语法基础
2. Playbook 结构：plays, tasks, handlers
3. Handler 通知机制
4. Tags 选择性执行

---

## Step 1 — YAML 语法基础

```yaml
# 注释以 # 开头

# 键值对
name: web-server
port: 80

# 列表
packages:
  - httpd
  - vim
  - htop

# 内联列表
packages: [httpd, vim, htop]

# 嵌套结构
server:
  name: web1
  ip: 10.0.1.10
  ports:
    - 80
    - 443

# 多行字符串
description: |
  This is a multi-line
  description.

# 布尔值
enabled: true
debug: false
```

---

## Step 2 — Playbook 结构

```yaml
---
# site.yaml
- name: Configure web servers      # Play 名称
  hosts: webservers                # 目标主机
  become: true                     # 使用 sudo

  vars:                            # 变量定义
    http_port: 80

  tasks:                           # 任务列表
    - name: Install httpd          # Task 名称
      ansible.builtin.dnf:
        name: httpd
        state: present

    - name: Start httpd service
      ansible.builtin.service:
        name: httpd
        state: started
        enabled: true

  handlers:                        # 处理器
    - name: Restart httpd
      ansible.builtin.service:
        name: httpd
        state: restarted
```

### 执行 Playbook

```bash
# 执行
ansible-playbook site.yaml

# 详细输出
ansible-playbook site.yaml -v

# 检查模式
ansible-playbook site.yaml -C

# 指定 inventory
ansible-playbook -i inventory.yaml site.yaml
```

---

## Step 3 — Handlers

Handler 只在被 notify 时执行，且在 Play 结束时执行一次。

```yaml
---
- name: Configure Apache
  hosts: webservers
  become: true

  tasks:
    - name: Install httpd
      ansible.builtin.dnf:
        name: httpd
        state: present

    - name: Copy httpd config
      ansible.builtin.copy:
        src: httpd.conf
        dest: /etc/httpd/conf/httpd.conf
      notify: Restart httpd            # 触发 handler

    - name: Copy index.html
      ansible.builtin.copy:
        src: index.html
        dest: /var/www/html/index.html
      notify: Restart httpd            # 多次 notify 只执行一次

  handlers:
    - name: Restart httpd
      ansible.builtin.service:
        name: httpd
        state: restarted
```

> 💡 **面试要点**
>
> **問題**：Handler はいつ実行されますか？
>
> **回答**：
> - Play の最後に実行
> - notify された場合のみ実行
> - 同じ Handler が複数回 notify されても1回だけ実行

---

## Step 4 — Tags

使用 Tags 选择性执行任务：

```yaml
---
- name: Configure web server
  hosts: webservers
  become: true

  tasks:
    - name: Install packages
      ansible.builtin.dnf:
        name: "{{ item }}"
        state: present
      loop:
        - httpd
        - vim
      tags:
        - install
        - packages

    - name: Configure httpd
      ansible.builtin.copy:
        src: httpd.conf
        dest: /etc/httpd/conf/httpd.conf
      tags:
        - configure
        - httpd

    - name: Start service
      ansible.builtin.service:
        name: httpd
        state: started
      tags:
        - service
        - always          # always 标签总是执行
```

### 使用 Tags

```bash
# 只执行 install 标签的任务
ansible-playbook site.yaml --tags "install"

# 执行多个标签
ansible-playbook site.yaml --tags "install,configure"

# 跳过特定标签
ansible-playbook site.yaml --skip-tags "service"

# 列出所有标签
ansible-playbook site.yaml --list-tags
```

---

## Step 5 — 完整示例：Web 服务器部署

### 目录结构

```
webserver/
├── site.yaml
├── files/
│   ├── httpd.conf
│   └── index.html
└── inventory.yaml
```

### site.yaml

```yaml
---
- name: Deploy Web Server
  hosts: webservers
  become: true

  vars:
    http_port: 80
    server_name: "{{ ansible_hostname }}"

  tasks:
    - name: Install httpd
      ansible.builtin.dnf:
        name: httpd
        state: present
      tags: install

    - name: Copy custom httpd.conf
      ansible.builtin.template:
        src: httpd.conf.j2
        dest: /etc/httpd/conf/httpd.conf
        mode: '0644'
      notify: Restart httpd
      tags: configure

    - name: Deploy index.html
      ansible.builtin.copy:
        content: |
          <html>
          <head><title>{{ server_name }}</title></head>
          <body>
            <h1>Welcome to {{ server_name }}</h1>
            <p>Deployed by Ansible</p>
          </body>
          </html>
        dest: /var/www/html/index.html
        mode: '0644'
      tags: deploy

    - name: Ensure httpd is running
      ansible.builtin.service:
        name: httpd
        state: started
        enabled: true
      tags: service

    - name: Open firewall port
      ansible.posix.firewalld:
        port: "{{ http_port }}/tcp"
        permanent: true
        state: enabled
        immediate: true
      tags: firewall
      ignore_errors: true

  handlers:
    - name: Restart httpd
      ansible.builtin.service:
        name: httpd
        state: restarted
```

---

## Mini-Project：Web 服务器自动化

### 要求

1. 创建 Playbook 实现：
   - 安装 httpd
   - 部署自定义 index.html
   - 配置文件变更时重启服务
   - 使用 tags 区分 install/configure/deploy

2. 验证：
   - `curl http://<node_ip>/` 返回自定义页面

---

## 动手前检查清单

| # | 检查项 | 验证命令 |
|---|--------|----------|
| 1 | 语法正确 | `ansible-playbook site.yaml --syntax-check` |
| 2 | 连接正常 | `ansible webservers -m ping` |
| 3 | 干运行预览 | `ansible-playbook site.yaml -C -D` |
| 4 | 列出任务 | `ansible-playbook site.yaml --list-tasks` |
| 5 | 列出标签 | `ansible-playbook site.yaml --list-tags` |

---

## 日本企業現場ノート

> 💼 **Playbook 的企业实践**

| 要点 | 说明 |
|------|------|
| **必须 --check** | 生产环境执行前必须先 `--check --diff` 预览变更 |
| **必须 --limit** | 使用 `--limit` 限定目标主机，禁止直接对全量执行 |
| **変更管理** | Playbook 执行需填写変更チケット号 |
| **ログ記録** | 配置 `ANSIBLE_LOG_PATH` 记录执行日志 |
| **コードレビュー** | Playbook 变更需要 Pull Request 审批 |
| **冪等性確認** | 新 Playbook 需验证多次执行结果一致 |

```bash
# 生产环境执行流程
export ANSIBLE_LOG_PATH=~/ansible-$(date +%Y%m%d-%H%M%S).log

# 1. 语法检查
ansible-playbook site.yaml --syntax-check

# 2. 干运行（必须！）
ansible-playbook site.yaml --check --diff --limit node1

# 3. 限定范围执行
ansible-playbook site.yaml --limit node1

# 4. 确认成功后扩大范围
ansible-playbook site.yaml --limit webservers
```

> 📋 **面试/入场时可能被问**：
> - 「Playbook 実行前に何を確認しますか？」→ --syntax-check, --check --diff, --limit での限定実行
> - 「Handler と普通の Task の違いは？」→ Handler は notify 時のみ実行、Play 終了時に1回だけ

---

## 常见错误

| 错误 | 原因 | 解决 |
|------|------|------|
| `YAML syntax error` | 缩进错误 | 使用 2 空格缩进 |
| `Handler not found` | Handler 名称不匹配 | 检查 notify 和 handler name |
| `Undefined variable` | 变量未定义 | 检查 vars 或使用 default |

---

## 本课小结

| 概念 | 要点 |
|------|------|
| Play | 针对一组主机的任务集合 |
| Task | 单个操作步骤 |
| Handler | 被 notify 后在 Play 结束时执行 |
| Tags | 选择性执行任务的标签 |

---

## 系列导航

← [03 · Ad-hoc](../03-adhoc-modules/) | [Home](../) | [Next →](../05-variables-logic/)
