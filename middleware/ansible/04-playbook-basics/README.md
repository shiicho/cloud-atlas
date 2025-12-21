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

## 准备环境

```bash
# 1. 切换到 ansible 用户（如果刚登录 Control Node）
sudo su - ansible

# 2. 更新课程仓库（获取最新内容）
cd ~/repo && git pull

# 3. 进入本课目录
cd ~/04-playbook-basics

# 4. 确认 Managed Nodes 可连接
ansible all -m ping
```

---

## Step 1 — YAML 语法速查

```yaml
# 键值对
name: web-server
port: 80

# 列表
packages:
  - httpd
  - vim

# 嵌套
server:
  name: al2023-1
  ports: [80, 443]

# 多行字符串
content: |
  line 1
  line 2

# 布尔值
enabled: true
```

---

## Step 2 — Playbook 结构

**基本结构**：Play → Tasks → Modules

```bash
# 查看最基础的 Playbook
cat exercises/01-motd-basic.yaml
```

```yaml
---
- name: Play 名称
  hosts: all          # 目标主机
  become: true        # sudo 权限

  vars:               # 变量
    key: value

  tasks:              # 任务列表
    - name: Task 名称
      ansible.builtin.module:
        param: value
```

**执行命令**：

```bash
# 执行 Playbook
ansible-playbook exercises/01-motd-basic.yaml

# 预期输出: CHANGED (首次), SUCCESS (重复执行)
```

---

## Step 3 — Handlers

Handler 只在被 notify 时执行，且 Play 结束时只执行一次。

```bash
# 查看 Handler 示例
cat exercises/03-motd-with-handlers.yaml
```

**核心语法**：
```yaml
tasks:
  - name: Deploy config
    ansible.builtin.copy:
      src: file.conf
      dest: /etc/file.conf
    notify: Restart service    # 触发 handler

handlers:
  - name: Restart service      # 名称必须匹配
    ansible.builtin.service:
      name: myservice
      state: restarted
```

**验证 Handler 行为**：

```bash
# 第 1 次执行 - 有变更，handler 触发
ansible-playbook exercises/03-motd-with-handlers.yaml

# 第 2 次执行 - 无变更，handler 不触发
ansible-playbook exercises/03-motd-with-handlers.yaml

# 检查 handler 日志
ansible all -a "cat /var/log/ansible/motd_changes.log" --become
```

> 💡 **面试要点**：Handler は Play 終了時に1回だけ実行。同じ Handler が複数回 notify されても1回だけ。

---

## Step 4 — Tags

使用 Tags 选择性执行任务。

```bash
# 查看带 Tags 的完整示例
cat exercises/04-webserver-deploy.yaml
```

**Tags 用法**：

```bash
# 列出所有 Tags
ansible-playbook exercises/04-webserver-deploy.yaml --list-tags

# 只执行 install 标签
ansible-playbook exercises/04-webserver-deploy.yaml --tags install

# 执行多个标签
ansible-playbook exercises/04-webserver-deploy.yaml --tags "install,deploy"

# 跳过特定标签
ansible-playbook exercises/04-webserver-deploy.yaml --skip-tags service
```

**常用 Tags**：
- `always` - 总是执行
- `never` - 默认跳过，需显式指定

---

## Step 5 — 实战：Web 服务器部署

```bash
# 完整部署示例
cat exercises/04-webserver-deploy.yaml

# 语法检查
ansible-playbook exercises/04-webserver-deploy.yaml --syntax-check

# 干运行预览
ansible-playbook exercises/04-webserver-deploy.yaml --check --diff

# 执行部署
ansible-playbook exercises/04-webserver-deploy.yaml

# 验证结果
curl http://al2023-1.ans.local/
```

**预期输出**：
```
PLAY [Deploy Web Server] *******
TASK [Install httpd] ******* changed
TASK [Deploy index.html] *** changed
TASK [Ensure httpd is started] *** changed
PLAY RECAP ***************** ok=4 changed=3
```

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

**生产执行流程**：
```bash
export ANSIBLE_LOG_PATH=~/ansible-$(date +%Y%m%d-%H%M%S).log

# 1. 语法检查 → 2. 干运行 → 3. 限定执行 → 4. 扩大范围
ansible-playbook site.yaml --syntax-check
ansible-playbook site.yaml --check --diff --limit node1
ansible-playbook site.yaml --limit node1
ansible-playbook site.yaml --limit webservers
```

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
