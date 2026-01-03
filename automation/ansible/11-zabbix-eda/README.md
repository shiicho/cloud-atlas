# 11 · Zabbix 连携与 Event-Driven Ansible（EDA Integration）

> **目标**：掌握 Event-Driven Ansible 与 Zabbix 集成
> **前置**：[10 · AWX/Tower](../10-awx-tower/)、[Zabbix 04 · 触发器与告警](../../zabbix/04-triggers-alerts/)
> **时间**：45 分钟
> **版本**：ansible-rulebook 1.1+, Python 3.10+, Java 17+, Zabbix 7.0+
> **实战项目**：障害対応自動化 - 磁盘告警自动清理

---

## 将学到的内容

1. Event-Driven Ansible (EDA) 架构
2. 配置 Zabbix webhook 触发 EDA
3. 编写 Rulebook 自动响应
4. 实现 障害対応自動化 模式

---

## 准备环境

```bash
# 1. 切换到 ansible 用户（如果当前不是 ansible 用户）
[ "$(whoami)" != "ansible" ] && sudo su - ansible

# 2. 更新课程仓库（获取最新内容）
cd ~/repo && git pull

# 3. 进入本课目录
cd ~/11-zabbix-eda

# 4. 确认 Managed Nodes 可连接
ansible all -m ping
```

> 本课需要 Zabbix 环境。如未完成 [Zabbix 04 · 触发器与告警](../../zabbix/04-triggers-alerts/)，请先学习该课程。

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

### 2.1 安装前置依赖

> ⚠️ **重要**：ansible-rulebook 需要 **Java 17+** 运行时（Drools 规则引擎依赖）

```bash
# 1. 安装 Java 17+（Amazon Linux 2023 / RHEL 9）
sudo dnf install -y java-17-amazon-corretto-headless

# 验证 Java 版本
java -version
# 输出应包含: openjdk version "17.x.x"

# 2. 安装 ansible-rulebook
pip3 install ansible-rulebook ansible-runner

# 验证安装
ansible-rulebook --version
```

### 2.2 安装 Event Source 插件

```bash
# 安装 EDA Collection（包含 webhook 等 source 插件）
ansible-galaxy collection install ansible.eda

# 安装 Zabbix Collection（用于 Zabbix API 操作）
ansible-galaxy collection install community.zabbix
```

> 💡 **Collection 版本说明**：
> - `ansible.eda` 提供 `eda.builtin.webhook` 等 source 插件
> - `community.zabbix` 提供 Zabbix API 模块（可选）

---

## Step 3 — Rulebook 基础

### 3.1 Rulebook 结构

```yaml
# rulebook.yaml
---
- name: Disk Space Remediation
  hosts: all
  sources:
    - eda.builtin.webhook:
        host: 127.0.0.1      # 仅本地访问，生产环境使用反向代理
        port: 5000
        token: "{{ lookup('env', 'EDA_WEBHOOK_TOKEN') }}"  # 认证令牌

  rules:
    - name: Disk space low
      condition: event.alert.name == "Disk space low"
      action:
        run_playbook:
          name: remediation/cleanup_disk.yaml
          extra_vars:
            target_host: "{{ event.host.name }}"
```

> ⚠️ **安全警告：Webhook 防护**
>
> 生产环境 **必须** 配置以下防护：
>
> | 措施 | 说明 |
> |------|------|
> | **TLS/HTTPS** | 使用 Nginx/HAProxy 反向代理，添加 SSL 证书 |
> | **认证令牌** | 使用 `token` 参数验证请求来源 |
> | **IP 白名单** | 仅允许 Zabbix 服务器 IP 访问 |
> | **主机验证** | 验证 `target_host` 在 inventory 中存在 |
>
> 未防护的 webhook 会导致**任意主机被攻击者控制执行 Playbook**！

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

> 📌 **Zabbix 7.0+ 菜单变更**：Media types 已移至 **Alerts** 菜单

1. 在 Zabbix 中：**Alerts** → **Media types** → **Create media type**
2. 配置：
   - Name: `Ansible EDA`
   - Type: `Webhook`
   - Parameters（添加以下参数）：

   | Name | Value |
   |------|-------|
   | `URL` | `http://eda-host:5000/endpoint` |
   | `HTTPMethod` | `POST` |
   | `TRIGGER_NAME` | `{TRIGGER.NAME}` |
   | `TRIGGER_SEVERITY` | `{TRIGGER.SEVERITY}` |
   | `TRIGGER_STATUS` | `{TRIGGER.STATUS}` |
   | `HOST_NAME` | `{HOST.NAME}` |
   | `HOST_IP` | `{HOST.IP}` |
   | `ITEM_NAME` | `{ITEM.NAME}` |
   | `ITEM_VALUE` | `{ITEM.VALUE}` |

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

> 📌 **Zabbix 7.0+ 菜单变更**：Actions 已移至 **Alerts** 菜单

1. **Alerts** → **Actions** → **Trigger actions** → **Create action**
2. **Action** 标签页：
   - Name: `EDA Disk Alert`
   - Conditions: `Trigger severity >= High`
3. **Operations** 标签页：
   - Operation type: `Send message`
   - Send to users: 选择接收用户
   - Send only to: `Ansible EDA`（上一步创建的 Media type）

---

## Step 5 — 实战：磁盘告警自动清理

### 5.1 Rulebook

```yaml
# rulebooks/disk_remediation.yaml
---
- name: Disk Space Auto-Remediation
  hosts: all
  sources:
    - eda.builtin.webhook:
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

  pre_tasks:
    - name: Validate target host exists in inventory
      ansible.builtin.assert:
        that:
          - target_host is defined
          - target_host in groups['all']
        fail_msg: "Invalid target_host: {{ target_host | default('undefined') }}"
      delegate_to: localhost
      run_once: true

  tasks:
    - name: Log remediation start
      ansible.builtin.debug:
        msg: "Starting disk cleanup for alert: {{ alert_name }}"

    - name: Clean package cache (DNF)
      ansible.builtin.dnf:
        autoremove: true
      when: ansible_pkg_mgr == "dnf"

    - name: Clean package cache (APT)
      ansible.builtin.apt:
        autoclean: true
        autoremove: true
      when: ansible_pkg_mgr == "apt"

    - name: Find old log files
      ansible.builtin.find:
        paths: /var/log
        patterns:
          - "*.log.*"
          - "*.gz"
        age: 7d
        recurse: true
      register: old_logs

    - name: Remove old log files
      ansible.builtin.file:
        path: "{{ item.path }}"
        state: absent
      loop: "{{ old_logs.files }}"
      loop_control:
        label: "{{ item.path }}"

    - name: Find old tmp files
      ansible.builtin.find:
        paths:
          - /tmp
          - /var/tmp
        age: 3d
        recurse: true
        file_type: file
      register: old_tmp

    - name: Remove old tmp files
      ansible.builtin.file:
        path: "{{ item.path }}"
        state: absent
      loop: "{{ old_tmp.files }}"
      loop_control:
        label: "{{ item.path }}"

    - name: Check disk space after cleanup
      ansible.builtin.command: df -h /
      register: disk_after
      changed_when: false

    - name: Report cleanup result
      ansible.builtin.debug:
        msg: |
          Cleanup completed on {{ target_host }}
          Current disk usage:
          {{ disk_after.stdout }}
```

> 💡 **改善ポイント**：
> - 使用 `find` 模块代替 shell 命令（更安全、跨平台）
> - 使用 `dnf`/`apt` 模块代替 `shell: dnf clean all`
> - 添加主机验证防止任意主机执行
> - 移除 `ignore_errors`，让错误可见

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
      "name": "target-1",
      "dns": "target-1.ans.local"
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

## 清理资源

```bash
# 1. 停止 ansible-rulebook（Ctrl+C）

# 2. 清理 Zabbix 配置（可选）
# - 删除 Media type: Alerts → Media types → Ansible EDA → Delete
# - 删除 Action: Alerts → Actions → EDA Disk Alert → Delete

# 3. 清理测试文件（如有）
rm -f /tmp/eda_test_*
```

---

## 动手前检查清单

| # | 检查项 | 验证命令 |
|---|--------|----------|
| 1 | Python 3.10+ 已安装 | `python3 --version` |
| 2 | **Java 17+ 已安装** | `java -version` |
| 3 | ansible-rulebook 已安装 | `ansible-rulebook --version` |
| 4 | EDA collection 已安装 | `ansible-galaxy collection list \| grep eda` |
| 5 | Inventory 文件存在 | `ansible-inventory --list` |
| 6 | Webhook 端口可用 | `ss -tlnp \| grep 5000` |
| 7 | 防火墙规则配置（如需要） | `firewall-cmd --list-ports` |

---

## 日本企業現場ノート

> 💼 **EDA 的企业运维实践**

| 要点 | 说明 |
|------|------|
| **Webhook 安全** | 必须使用 HTTPS + 认证令牌，禁止公网直接暴露 |
| **IP 制限** | 仅允许 Zabbix Server IP 访问 EDA endpoint |
| **監査ログ** | 记录所有 event 和执行的 action，保留 90 天以上 |
| **変更管理** | Rulebook 变更需提交审批，测试环境验证后再上线 |
| **エスカレーション** | 自动修复失败时，必须触发告警通知人工介入 |
| **実行権限** | EDA 服务账户使用最小权限原则 |

```yaml
# 生产环境推荐配置
rules:
  - name: Disk space alert with audit
    condition: event.alert.name is match(".*disk.*")
    action:
      run_playbook:
        name: playbooks/cleanup_disk.yaml
        extra_vars:
          target_host: "{{ event.host.name }}"
          # 审计用字段
          event_id: "{{ event.id | default(now()) }}"
          zabbix_trigger_id: "{{ event.trigger_id | default('unknown') }}"
```

> 📋 **面试/入场时可能被问**：
> - 「EDA の Webhook はどうやって保護しますか？」→ HTTPS + 認証トークン + IP 制限 + ホスト検証
> - 「自動復旧が失敗したらどうしますか？」→ エスカレーション Action で通知

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
