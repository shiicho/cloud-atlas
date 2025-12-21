# 08 · 错误处理与调试技巧（Error Handling & Debugging）

> **目标**：掌握错误处理和调试技术
> **前置**：[07 · Jinja2 模板](../07-jinja2-templates/)
> **时间**：30 分钟
> **实战项目**：健壮的部署脚本

---

## 将学到的内容

1. block/rescue/always 结构
2. ignore_errors 和 failed_when
3. 调试技巧：debug 模块、verbose 模式
4. 处理不可达主机

---

## 准备环境

```bash
# 1. 切换到 ansible 用户（如果刚登录 Control Node）
sudo su - ansible

# 2. 更新课程仓库（获取最新内容）
cd ~/repo && git pull

# 3. 进入本课目录
cd ~/08-error-handling

# 4. 确认 Managed Nodes 可连接
ansible all -m ping
```

---

## Step 1 — Block/Rescue/Always

类似于 try/catch/finally。

```bash
# 查看 block/rescue/always 示例
cat exercises/01-block-rescue.yaml

# 执行
ansible-playbook exercises/01-block-rescue.yaml
```

**核心语法**：

```yaml
block:
  - name: Try this
    ansible.builtin.command: risky-command
rescue:
  - name: Handle failure
    ansible.builtin.debug:
      msg: "Failed, running recovery"
always:
  - name: Always cleanup
    ansible.builtin.debug:
      msg: "Cleanup done"
```

> 💡 **面试要点**：block 失敗時 → rescue 実行 → always は常に実行

---

## Step 2 — 错误控制

```bash
# 查看 ignore_errors 示例
cat exercises/02-ignore-errors.yaml

# 执行
ansible-playbook exercises/02-ignore-errors.yaml
```

**核心语法**：

```yaml
# 忽略错误继续
ignore_errors: true

# 自定义失败条件
failed_when: result.rc == 0

# 自定义变更判断
changed_when: "'Updated' in result.stdout"

# 任一失败全停
any_errors_fatal: true
```

---

## Step 3 — 调试技巧

```bash
# 详细模式
ansible-playbook site.yaml -v      # 基本
ansible-playbook site.yaml -vv     # 更多
ansible-playbook site.yaml -vvv    # 连接详情

# 逐任务执行
ansible-playbook site.yaml --step

# 从特定任务开始
ansible-playbook site.yaml --start-at-task="Install httpd"

# 列出任务
ansible-playbook site.yaml --list-tasks
```

```bash
# 查看 assert 验证示例
cat exercises/04-assert-validation.yaml

# 执行
ansible-playbook exercises/04-assert-validation.yaml
```

---

## Step 4 — 重试机制

```bash
# 查看 retry/until 示例
cat exercises/03-retry-until.yaml

# 执行
ansible-playbook exercises/03-retry-until.yaml
```

**核心语法**：

```yaml
- name: Wait for service
  ansible.builtin.uri:
    url: http://localhost/health
  register: result
  retries: 5
  delay: 10
  until: result.status == 200
```

---

## Step 5 — 实战：健壮的部署

```bash
# 查看完整回滚示例
cat exercises/05-deployment-rollback.yaml

# 语法检查
ansible-playbook exercises/05-deployment-rollback.yaml --syntax-check

# 干运行
ansible-playbook exercises/05-deployment-rollback.yaml --check

# 执行
ansible-playbook exercises/05-deployment-rollback.yaml
```

---

## 动手前检查清单

| # | 检查项 | 验证命令 |
|---|--------|----------|
| 1 | 语法正确 | `ansible-playbook site.yaml --syntax-check` |
| 2 | 连接正常 | `ansible all -m ping` |
| 3 | 干运行 | `ansible-playbook site.yaml -C` |
| 4 | 列出任务 | `ansible-playbook site.yaml --list-tasks` |

---

## 常见调试场景

| 问题 | 调试方法 |
|------|----------|
| 变量值不对 | `debug` 模块输出变量 |
| SSH 连接失败 | `-vvv` 查看连接详情 |
| 任务顺序问题 | `--step` 逐步执行 |

---

## 日本企業現場ノート

> 💼 **错误处理的企业实践**

| 要点 | 说明 |
|------|------|
| **ignore_errors 慎用** | 禁止盲目忽略，必须有补救措施 |
| **block/rescue 必須** | 重要操作必须有 rescue 块 |
| **ロールバック計画** | 部署前必须准备回滚方案 |
| **通知必須** | 失败时必须通知负责人 |

> 💡 **面试要点**：障害発生時 → rescue でロールバック → 通知 → ログ記録

---

## 本课小结

| 概念 | 要点 |
|------|------|
| block/rescue/always | 错误处理结构 |
| ignore_errors | 忽略错误继续执行 |
| failed_when | 自定义失败条件 |
| retries/until | 重试机制 |
| -v/-vv/-vvv | 详细输出级别 |

---

## 系列导航

← [07 · Jinja2](../07-jinja2-templates/) | [Home](../) | [Next →](../09-vault-secrets/)
