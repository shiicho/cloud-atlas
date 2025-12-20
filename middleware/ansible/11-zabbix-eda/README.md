# 11 · Zabbix 连携与 Event-Driven Ansible（EDA Integration）

> **目标**：掌握 Event-Driven Ansible 与 Zabbix 集成
> **前置**：[10 · AWX/Tower](../10-awx-tower/)、[Zabbix 04 · 触发器与告警](../../zabbix/04-triggers-alerts/)
> **时间**：45 分钟
> **实战项目**：障害対応自動化 - 磁盘告警自动清理

---

## 将学到的内容

1. Event-Driven Ansible (EDA) 架构
2. 配置 Zabbix webhook 触发 EDA
3. 编写 Rulebook 自动响应
4. 实现 障害対応自動化 模式

---

## Step 1 — Event-Driven Ansible 概述

### 1.1 架构

```
┌─────────────────────────────────────────────────────────────┐
│                 Event-Driven Ansible 架构                    │
│                                                              │
│   ┌──────────────┐     Event      ┌──────────────────────┐  │
│   │   Zabbix     │ ─────────────► │  ansible-rulebook    │  │
│   │   Server     │   (webhook)    │                      │  │
│   └──────────────┘                │  ┌────────────────┐  │  │
│                                   │  │   Rulebook     │  │  │
│   ┌──────────────┐                │  │   (rules.yaml) │  │  │
│   │   Kafka      │ ─────────────► │  └───────┬────────┘  │  │
│   └──────────────┘   (stream)     │          │           │  │
│                                   │          ▼           │  │
│   ┌──────────────┐                │  ┌────────────────┐  │  │
│   │   Webhook    │ ─────────────► │  │   Action       │  │  │
│   │   (any)      │                │  │   (Playbook)   │  │  │
│   └──────────────┘                │  └────────────────┘  │  │
│                                   └──────────────────────┘  │
│                                              │               │
│                                              ▼               │
│                                   ┌──────────────────────┐  │
│                                   │   Managed Nodes      │  │
│                                   │   (自动修复)          │  │
│                                   └──────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

### 1.2 核心组件

| 组件 | 说明 |
|------|------|
| **Event Source** | 事件来源（Zabbix, Kafka, Webhook） |
| **Rulebook** | 事件匹配规则和动作定义 |
| **Action** | 触发的动作（运行 Playbook） |
| **ansible-rulebook** | EDA 运行时 |

---

## Step 2 — 安装 EDA

### 2.1 安装 ansible-rulebook

```bash
# 安装依赖
pip3 install ansible-rulebook ansible-runner

# 验证安装
ansible-rulebook --version
```

### 2.2 安装 Event Source 插件

```bash
# 安装 Zabbix 相关 Collection
ansible-galaxy collection install ansible.eda
ansible-galaxy collection install community.zabbix
```

---

## Step 3 — Rulebook 基础

### 3.1 Rulebook 结构

```yaml
# rulebook.yaml
---
- name: Disk Space Remediation
  hosts: all
  sources:
    - ansible.eda.webhook:
        host: 0.0.0.0
        port: 5000

  rules:
    - name: Disk space low
      condition: event.alert.name == "Disk space low"
      action:
        run_playbook:
          name: remediation/cleanup_disk.yaml
          extra_vars:
            target_host: "{{ event.host.name }}"
```

### 3.2 Rulebook 元素

| 元素 | 说明 |
|------|------|
| `sources` | 事件来源配置 |
| `rules` | 规则列表 |
| `condition` | 触发条件（Jinja2 表达式） |
| `action` | 匹配后执行的动作 |

### 3.3 运行 Rulebook

```bash
ansible-rulebook --rulebook rulebook.yaml -i inventory.yaml --verbose
```

---

## Step 4 — Zabbix Webhook 配置

### 4.1 创建 Media Type

1. 在 Zabbix 中：**Administration** → **Media types** → **Create**
2. 配置：
   - Name: `Ansible EDA`
   - Type: `Webhook`
   - Parameters:
     ```
     URL: http://eda-host:5000/endpoint
     HTTPMethod: POST
     ```

### 4.2 Webhook 脚本

```javascript
// Zabbix Webhook 脚本
var params = JSON.parse(value);

var request = new HttpRequest();
request.addHeader('Content-Type: application/json');

var payload = {
    "alert": {
        "name": params.TRIGGER_NAME,
        "severity": params.TRIGGER_SEVERITY,
        "status": params.TRIGGER_STATUS
    },
    "host": {
        "name": params.HOST_NAME,
        "ip": params.HOST_IP
    },
    "item": {
        "name": params.ITEM_NAME,
        "value": params.ITEM_VALUE
    }
};

var response = request.post(
    params.URL,
    JSON.stringify(payload)
);

return 'OK';
```

### 4.3 创建 Action

1. **Configuration** → **Actions** → **Trigger actions** → **Create**
2. Conditions: Trigger severity = High
3. Operations: Send to Ansible EDA (media type)

---

## Step 5 — 实战：磁盘告警自动清理

### 5.1 Rulebook

```yaml
# rulebooks/disk_remediation.yaml
---
- name: Disk Space Auto-Remediation
  hosts: all
  sources:
    - ansible.eda.webhook:
        host: 0.0.0.0
        port: 5000

  rules:
    - name: Handle disk space alert
      condition: |
        event.alert.name is match(".*[Dd]isk.*", ignorecase=true) and
        event.alert.status == "PROBLEM"
      action:
        run_playbook:
          name: playbooks/cleanup_disk.yaml
          extra_vars:
            target_host: "{{ event.host.name }}"
            alert_name: "{{ event.alert.name }}"

    - name: Log all events
      condition: event is defined
      action:
        debug:
          msg: "Received event: {{ event }}"
```

### 5.2 Cleanup Playbook

```yaml
# playbooks/cleanup_disk.yaml
---
- name: Disk Cleanup Remediation
  hosts: "{{ target_host }}"
  become: true

  tasks:
    - name: Log remediation start
      ansible.builtin.debug:
        msg: "Starting disk cleanup for alert: {{ alert_name }}"

    - name: Clean package cache
      ansible.builtin.shell: dnf clean all
      ignore_errors: true

    - name: Clean old logs
      ansible.builtin.shell: |
        find /var/log -type f -name "*.log.*" -mtime +7 -delete
        find /var/log -type f -name "*.gz" -mtime +7 -delete
      ignore_errors: true

    - name: Clean tmp files
      ansible.builtin.shell: |
        find /tmp -type f -mtime +3 -delete
        find /var/tmp -type f -mtime +3 -delete
      ignore_errors: true

    - name: Check disk space after cleanup
      ansible.builtin.shell: df -h /
      register: disk_after

    - name: Report cleanup result
      ansible.builtin.debug:
        msg: |
          Cleanup completed on {{ target_host }}
          Current disk usage:
          {{ disk_after.stdout }}
```

### 5.3 测试流程

```bash
# 1. 启动 EDA
ansible-rulebook --rulebook rulebooks/disk_remediation.yaml \
  -i inventory.yaml --verbose

# 2. 模拟 Zabbix webhook（测试）
curl -X POST http://localhost:5000/endpoint \
  -H "Content-Type: application/json" \
  -d '{
    "alert": {
      "name": "Disk space low on /",
      "severity": "High",
      "status": "PROBLEM"
    },
    "host": {
      "name": "node1",
      "ip": "10.0.1.10"
    }
  }'
```

---

## Step 6 — 高级场景

### 6.1 多条件规则

```yaml
rules:
  - name: Critical disk and business hours
    condition: |
      event.alert.severity == "Disaster" and
      event.alert.name is match(".*disk.*") and
      now().hour >= 9 and now().hour <= 18
    action:
      run_playbook:
        name: playbooks/emergency_cleanup.yaml
```

### 6.2 条件触发通知

```yaml
rules:
  - name: Notify on remediation failure
    condition: event.remediation.status == "failed"
    action:
      run_playbook:
        name: playbooks/notify_oncall.yaml
```

---

## Mini-Project：障害対応自動化

### 要求

1. **配置 Zabbix 触发器**
   - 磁盘使用率 > 80% 告警

2. **配置 Zabbix Webhook**
   - 发送到 EDA endpoint

3. **创建 EDA Rulebook**
   - 接收磁盘告警
   - 触发清理 Playbook

4. **验证自动修复**
   - 填充磁盘触发告警
   - 确认自动清理执行
   - 确认磁盘空间恢复

---

## 面试要点

> **問題**：Event-Driven Ansible の利点は何ですか？
>
> **回答**：
> - 監視アラートに対する自動復旧
> - 人手介入なしで障害対応
> - MTTR（平均復旧時間）の大幅短縮
> - 24/7 の自動運用実現

---

## 本课小结

| 概念 | 要点 |
|------|------|
| Event-Driven Ansible | 事件驱动的自动化 |
| Rulebook | 事件匹配规则定义 |
| ansible-rulebook | EDA 运行时 |
| Zabbix Webhook | 告警事件源 |
| 障害対応自動化 | 自动故障修复 |

---

## 课程总结

恭喜完成 Ansible Zero-to-Hero 课程！

| 课程 | 核心技能 |
|------|----------|
| 00-03 | 基础概念、Ad-hoc 命令 |
| 04-07 | Playbook、Roles、Templates |
| 08-09 | 错误处理、Vault 加密 |
| 10-11 | AWX 平台、Event-Driven 自动化 |

### 下一步建议

- [ ] 实践：在工作中应用 Ansible 自动化
- [ ] 认证：考取 RHCE (EX294)
- [ ] 进阶：学习 Ansible Automation Platform
- [ ] 集成：结合 Terraform 实现完整 IaC

---

## 系列导航

← [10 · AWX/Tower](../10-awx-tower/) | [Home](../)
