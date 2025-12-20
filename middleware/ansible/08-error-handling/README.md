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

## Step 1 — Block/Rescue/Always

类似于 try/catch/finally：

```yaml
- name: Error handling demo
  hosts: all
  tasks:
    - name: Attempt risky operation
      block:
        - name: Do something risky
          ansible.builtin.command: /usr/bin/risky-command

        - name: This runs if above succeeds
          ansible.builtin.debug:
            msg: "Risky command succeeded"

      rescue:
        - name: Handle failure
          ansible.builtin.debug:
            msg: "Risky command failed, running recovery"

        - name: Send alert
          ansible.builtin.mail:
            to: admin@example.com
            subject: "Task failed on {{ inventory_hostname }}"

      always:
        - name: Always run cleanup
          ansible.builtin.debug:
            msg: "Cleanup completed"
```

> 💡 **面试要点**
>
> **問題**：block/rescue/always の実行順序は？
>
> **回答**：
> 1. block 内のタスク実行
> 2. 失敗時に rescue 実行
> 3. 成功/失敗に関わらず always 実行

---

## Step 2 — 错误控制

### 2.1 ignore_errors

```yaml
- name: Continue on failure
  ansible.builtin.command: /usr/bin/maybe-fails
  ignore_errors: true
  register: result

- name: Check result
  ansible.builtin.debug:
    msg: "Command {{ 'failed' if result.failed else 'succeeded' }}"
```

### 2.2 failed_when

```yaml
- name: Custom failure condition
  ansible.builtin.shell: grep "ERROR" /var/log/app.log
  register: grep_result
  failed_when: grep_result.rc == 0   # 找到 ERROR 才失败

- name: Check HTTP response
  ansible.builtin.uri:
    url: http://localhost/health
  register: health
  failed_when: "'OK' not in health.content"
```

### 2.3 changed_when

```yaml
- name: Run command
  ansible.builtin.shell: /usr/bin/update-something
  register: update_result
  changed_when: "'Updated' in update_result.stdout"
```

### 2.4 any_errors_fatal

```yaml
- name: Critical operation
  hosts: all
  any_errors_fatal: true   # 任一主机失败则停止所有

  tasks:
    - name: Critical task
      ansible.builtin.command: /usr/bin/critical
```

---

## Step 3 — 调试技巧

### 3.1 debug 模块

```yaml
- name: Show variable
  ansible.builtin.debug:
    var: my_variable

- name: Show message
  ansible.builtin.debug:
    msg: "Value is {{ my_variable }}"

- name: Show with verbosity
  ansible.builtin.debug:
    msg: "Detailed info"
    verbosity: 2   # 只在 -vv 以上显示
```

### 3.2 Verbose 模式

```bash
# 增加详细程度
ansible-playbook site.yaml -v      # 基本
ansible-playbook site.yaml -vv     # 更多
ansible-playbook site.yaml -vvv    # 连接详情
ansible-playbook site.yaml -vvvv   # 包括插件
```

### 3.3 逐步执行

```bash
# 逐任务确认
ansible-playbook site.yaml --step

# 从特定任务开始
ansible-playbook site.yaml --start-at-task="Install httpd"

# 列出所有任务
ansible-playbook site.yaml --list-tasks
```

### 3.4 assert 模块

```yaml
- name: Validate configuration
  ansible.builtin.assert:
    that:
      - http_port is defined
      - http_port > 0
      - http_port < 65536
    fail_msg: "Invalid http_port value"
    success_msg: "http_port is valid"
```

---

## Step 4 — 处理不可达主机

### 4.1 ignore_unreachable

```yaml
- name: Handle unreachable
  ansible.builtin.ping:
  ignore_unreachable: true
  register: ping_result

- name: Skip if unreachable
  ansible.builtin.debug:
    msg: "Host is reachable"
  when: not ping_result.unreachable | default(false)
```

### 4.2 max_fail_percentage

```yaml
- name: Allow some failures
  hosts: webservers
  max_fail_percentage: 30   # 允许 30% 失败
  serial: 10                # 每批 10 台

  tasks:
    - name: Rolling update
      ansible.builtin.command: /usr/bin/update
```

---

## Step 5 — 实战：健壮的部署脚本

```yaml
---
- name: Robust deployment
  hosts: webservers
  become: true
  serial: "30%"           # 滚动部署

  tasks:
    - name: Deployment block
      block:
        - name: Stop service
          ansible.builtin.service:
            name: myapp
            state: stopped

        - name: Backup current version
          ansible.builtin.command: >
            cp -r /opt/myapp /opt/myapp.bak.{{ ansible_date_time.epoch }}
          args:
            creates: /opt/myapp.bak.*

        - name: Deploy new version
          ansible.builtin.unarchive:
            src: myapp-{{ version }}.tar.gz
            dest: /opt/myapp

        - name: Start service
          ansible.builtin.service:
            name: myapp
            state: started

        - name: Health check
          ansible.builtin.uri:
            url: http://localhost:8080/health
            status_code: 200
          retries: 5
          delay: 10
          register: health
          until: health.status == 200

      rescue:
        - name: Rollback on failure
          ansible.builtin.command: >
            mv /opt/myapp.bak.* /opt/myapp
          ignore_errors: true

        - name: Restart old version
          ansible.builtin.service:
            name: myapp
            state: restarted

        - name: Notify failure
          ansible.builtin.debug:
            msg: "Deployment failed on {{ inventory_hostname }}"

      always:
        - name: Cleanup old backups
          ansible.builtin.shell: >
            find /opt -name "myapp.bak.*" -mtime +7 -delete
          ignore_errors: true
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

## 日本企業現場ノート

> 💼 **错误处理的企业实践**

| 要点 | 说明 |
|------|------|
| **ignore_errors 慎用** | 生产环境禁止盲目忽略错误，必须有对应的补救措施 |
| **block/rescue 必須** | 重要操作必须有 rescue 块处理失败场景 |
| **ロールバック計画** | 部署前必须准备回滚方案并测试 |
| **通知必須** | 失败时必须通过 Slack/邮件通知负责人 |
| **ログ保存** | 配置 `ANSIBLE_LOG_PATH` 保存执行日志供事后分析 |
| **冪等性確認** | 恢复操作也必须是幂等的 |

```yaml
# 企业级错误处理模板
- name: Critical deployment
  block:
    - name: Deploy application
      # ... 部署任务 ...

  rescue:
    - name: Rollback on failure
      # ... 回滚操作 ...

    - name: Notify team
      ansible.builtin.uri:
        url: "{{ slack_webhook_url }}"
        method: POST
        body_format: json
        body:
          text: "⚠️ Deployment failed on {{ inventory_hostname }}"

  always:
    - name: Record deployment result
      ansible.builtin.lineinfile:
        path: /var/log/ansible-deploys.log
        line: "{{ ansible_date_time.iso8601 }} - {{ inventory_hostname }} - {{ 'FAILED' if ansible_failed_result is defined else 'SUCCESS' }}"
      delegate_to: localhost
```

> 📋 **面试/入场时可能被问**：
> - 「障害発生時の対応フローは？」→ rescue でロールバック → 通知 → ログ記録 → 原因調査
> - 「ignore_errors はいつ使いますか？」→ 情報収集タスクのみ、本番変更操作では使わない

---

## 常见调试场景

| 问题 | 调试方法 |
|------|----------|
| 变量值不对 | `debug` 模块输出变量 |
| SSH 连接失败 | `-vvv` 查看连接详情 |
| 模块参数错误 | `--check` 模式验证 |
| 任务顺序问题 | `--step` 逐步执行 |
| 条件不生效 | 输出 `when` 条件中的变量 |

---

## 本课小结

| 概念 | 要点 |
|------|------|
| block/rescue/always | 错误处理结构 |
| ignore_errors | 忽略错误继续执行 |
| failed_when | 自定义失败条件 |
| debug | 输出变量和消息 |
| -v/-vv/-vvv | 详细输出级别 |

---

## 系列导航

← [07 · Jinja2](../07-jinja2-templates/) | [Home](../) | [Next →](../09-vault-secrets/)
