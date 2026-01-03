# Lesson 04 - Playbook 基础练习

本目录包含渐进式的 Playbook 示例，帮助你理解 Playbook 的各个组成部分。

## 练习清单

### 01-motd-basic.yaml - 最基础的结构
**学习目标**: 理解 Play 的基本结构 (hosts, tasks)

```bash
ansible-playbook 01-motd-basic.yaml
```

**知识点**:
- `---` 和 `...` 标记 YAML 文档
- `hosts:` 指定目标主机
- `tasks:` 任务列表

---

### 02-motd-with-vars.yaml - 添加变量
**学习目标**: 理解 vars 区块和变量引用

```bash
ansible-playbook 02-motd-with-vars.yaml
```

**知识点**:
- `vars:` 定义变量
- `{{ variable }}` 引用变量
- 多行字符串 `|`

---

### 03-motd-with-handlers.yaml - 添加 Handlers
**学习目标**: 理解 notify 和 handlers 机制

```bash
# 第一次执行 - handler 会触发
ansible-playbook 03-motd-with-handlers.yaml

# 第二次执行 - 无变化，handler 不触发
ansible-playbook 03-motd-with-handlers.yaml
```

**知识点**:
- `notify:` 触发 handler
- `handlers:` 定义处理器
- Handler 只在 Play 结束时执行一次

---

### 04-webserver-deploy.yaml - 完整部署示例
**学习目标**: 综合运用 vars, tasks, handlers, tags

```bash
# 完整执行
ansible-playbook 04-webserver-deploy.yaml

# 仅安装
ansible-playbook 04-webserver-deploy.yaml --tags install

# 仅部署内容
ansible-playbook 04-webserver-deploy.yaml --tags deploy

# 预览变更
ansible-playbook 04-webserver-deploy.yaml --check --diff
```

**知识点**:
- 完整的 Web 服务器部署流程
- Tags 选择性执行
- 多个 Tags 组合

---

### 05-multi-play.yaml - 多 Play 示例
**学习目标**: 理解一个 Playbook 可以包含多个 Play

```bash
ansible-playbook 05-multi-play.yaml
```

**知识点**:
- 一个 Playbook 可以有多个 Play
- 每个 Play 可以针对不同的主机组
- Play 按顺序执行

---

## 验证结果

```bash
# 检查 MOTD
ansible all -a "cat /etc/motd"

# 检查 Web 服务
curl http://web-1.ans.local/

# 查看 handler 日志
ansible all -a "cat /var/log/ansible/motd_changes.log" --become
```

## 清理环境

```bash
# 恢复默认 MOTD
ansible all -m copy -a "content='' dest=/etc/motd" --become

# 停止 httpd
ansible webservers -m service -a "name=httpd state=stopped" --become
```
