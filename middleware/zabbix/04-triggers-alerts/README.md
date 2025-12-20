# 04 · 触发器与告警通知（Triggers & Alerts）

> **目标**：配置触发器、邮件通知和维护窗口
> **前置**：[03 · 基础监控 + 死活检查](../03-monitoring-basics/)
> **时间**：30-35 分钟
> **实战项目**：配置磁盘告警 + Golden Week 维护窗口

## 将学到的内容

1. 创建自定义触发器
2. 理解 Severity 级别和依赖关系
3. 配置 Email 通知
4. 创建 Action（触发器 → 通知）
5. 设置维护窗口（Maintenance Window）
6. 实践告警确认（Acknowledgment）

---

## Step 1 — 创建自定义触发器

### 1.1 触发器工作原理

```
┌─────────────────────────────────────────────────────────────┐
│                    Trigger 工作流程                          │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  Item 采集数据                                               │
│       │                                                      │
│       ▼                                                      │
│  ┌─────────────────┐     ┌─────────────────┐                │
│  │ Expression 评估 │────►│ 状态: OK/PROBLEM │               │
│  │ last() < 20     │     └─────────────────┘                │
│  └─────────────────┘              │                          │
│                                   ▼                          │
│                         ┌─────────────────┐                  │
│                         │ Event 生成      │                  │
│                         └─────────────────┘                  │
│                                   │                          │
│                                   ▼                          │
│                         ┌─────────────────┐                  │
│                         │ Action 执行     │                  │
│                         │ (发送通知)      │                  │
│                         └─────────────────┘                  │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### 1.2 创建磁盘空间触发器

1. 「Data collection」→「Hosts」→ 点击 `monitored-host-01`
2. 切换到「Triggers」标签页
3. 点击「Create trigger」

**基本配置**：

| 字段 | 值 |
|------|-----|
| Name | `Disk space is low on {HOST.NAME} ({ITEM.LASTVALUE})` |
| Severity | `Warning` |
| Expression | 见下方 |

**构建 Expression**：

点击「Add」打开表达式构建器：

| 字段 | 值 |
|------|-----|
| Item | `Linux: Space utilization` 或手动输入 |
| Function | `last()` |
| Result | `>=80` |

完整表达式示例：
```
last(/monitored-host-01/vfs.fs.size[/,pused])>=80
```

**Recovery expression**（防止 Flapping）：
```
last(/monitored-host-01/vfs.fs.size[/,pused])<75
```

> 💡 **Hysteresis（滞后）**：Problem 阈值 80%，Recovery 阈值 75%，避免在临界值附近反复触发

4. 点击「Add」

### 1.3 Severity 级别

| 级别 | 颜色 | 用途 |
|------|------|------|
| Not classified | 灰色 | 未分类 |
| Information | 浅蓝 | 信息提示 |
| Warning | 黄色 | 警告，需关注 |
| Average | 橙色 | 一般严重 |
| High | 红色 | 严重问题 |
| Disaster | 深红 | 灾难级别 |

---

## Step 2 — 理解触发器依赖

### 2.1 依赖关系场景

```
场景：网络设备故障导致所有服务器不可达

不使用依赖：
  - Switch down ← 触发
  - Server A unreachable ← 触发
  - Server B unreachable ← 触发
  - Server C unreachable ← 触发
  = 大量重复告警！

使用依赖：
  - Switch down ← 触发
  - Server A unreachable ← 被抑制（依赖 Switch）
  - Server B unreachable ← 被抑制
  - Server C unreachable ← 被抑制
  = 只收到 1 个告警
```

### 2.2 配置依赖

1. 编辑 Trigger
2. 切换到「Dependencies」标签页
3. 点击「Add」选择父触发器
4. 保存

---

## Step 3 — 配置 Email 通知

### 3.1 配置 Media Type

1. 「Alerts」→「Media types」
2. 点击「Email」（系统预置）

配置 SMTP：

| 字段 | 值（示例：Gmail） |
|------|-------------------|
| SMTP server | smtp.gmail.com |
| SMTP server port | 587 |
| SMTP helo | gmail.com |
| SMTP email | your-email@gmail.com |
| Connection security | STARTTLS |
| Authentication | Username and password |
| Username | your-email@gmail.com |
| Password | App password（非登录密码） |

对于 AWS SES：

| 字段 | 值 |
|------|-----|
| SMTP server | email-smtp.ap-northeast-1.amazonaws.com |
| SMTP server port | 587 |
| Connection security | STARTTLS |
| Username | SES SMTP username |
| Password | SES SMTP password |

3. 点击「Test」验证
4. 点击「Update」

### 3.2 为用户配置 Media

1. 「Users」→「Users」
2. 点击你的用户名
3. 切换到「Media」标签页
4. 点击「Add」

   | 字段 | 值 |
   |------|-----|
   | Type | Email |
   | Send to | your-email@example.com |
   | When active | 1-7,00:00-24:00（全天候） |
   | Use if severity | 勾选需要接收的级别 |

5. 点击「Add」→「Update」

---

## Step 4 — 创建 Action

Action 定义「触发器触发时做什么」。

### 4.1 创建通知 Action

1. 「Alerts」→「Actions」→「Trigger actions」
2. 点击「Create action」

**Action 标签页**：

| 字段 | 值 |
|------|-----|
| Name | `Notify on High severity problems` |
| Conditions | 添加条件（见下） |

**添加 Conditions**：
- Trigger severity `>=` `High`
- Host group `=` `Lab/Linux servers`

**Operations 标签页**：

点击「Add」添加操作：

| 字段 | 值 |
|------|-----|
| Operation type | Send message |
| Send to user groups | 选择用户组（如 Zabbix administrators） |
| Send only to | Email |

**Default subject**：
```
[{TRIGGER.SEVERITY}] {TRIGGER.NAME}
```

**Default message**：
```
Host: {HOST.NAME}
Problem: {TRIGGER.NAME}
Severity: {TRIGGER.SEVERITY}
Time: {EVENT.DATE} {EVENT.TIME}
Current value: {ITEM.LASTVALUE}

Original problem ID: {EVENT.ID}
```

**Recovery operations 标签页**：

添加恢复通知：
- Operation type: Send message
- 使用相同用户组

3. 点击「Add」

### 4.2 测试告警

触发磁盘告警测试：

```bash
# 在 Monitored Host 上创建大文件
sudo dd if=/dev/zero of=/tmp/bigfile bs=1M count=5000

# 检查磁盘使用率
df -h /
```

在 Web UI 检查：
1. 「Monitoring」→「Problems」查看告警
2. 检查邮箱是否收到通知

清理：
```bash
sudo rm /tmp/bigfile
```

---

## Step 5 — 配置维护窗口

> 场景：Golden Week（日本黄金周）期间抑制告警

### 5.1 创建维护窗口

1. 「Data collection」→「Maintenance」
2. 点击「Create maintenance period」

**Maintenance 标签页**：

| 字段 | 值 |
|------|-----|
| Name | `Golden Week 2025` |
| Maintenance type | `With data collection`（继续采集但不告警） |
| Active since | `2025-05-03 00:00` |
| Active till | `2025-05-07 23:59` |

**Periods 标签页**：

点击「Add」：
- Period type: One time only
- Date: 2025-05-03
- Maintenance period length: 5 days

**Hosts & groups 标签页**：

- Host groups: 选择需要维护的组
- 或 Hosts: 选择特定主机

3. 点击「Add」

### 5.2 维护窗口类型

| 类型 | 数据采集 | 告警 | 用途 |
|------|----------|------|------|
| With data collection | ✅ | ❌ | 计划内停机、假期 |
| No data collection | ❌ | ❌ | 硬件维护、网络切割 |

### 5.3 验证维护窗口

1. 在维护期间，主机图标显示维护标记
2. 「Problems」中告警被抑制（但仍记录）
3. 维护结束后自动恢复

---

## Step 6 — 告警确认（Acknowledgment）

### 6.1 确认问题

1. 「Monitoring」→「Problems」
2. 点击问题行的时间戳
3. 点击「Acknowledge」

填写：
- Message: 描述处理情况
- 可选操作：
  - Close problem（手动关闭）
  - Change severity（调整严重级别）

### 6.2 确认流程最佳实践

```
┌─────────────────────────────────────────────────────────────┐
│                  告警处理流程                                │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  1. 收到告警 ──► 2. 确认收到（Ack）                         │
│                      │                                       │
│                      ▼                                       │
│               3. 开始处理（记录）                            │
│                      │                                       │
│                      ▼                                       │
│               4. 问题解决                                    │
│                      │                                       │
│               ┌──────┴──────┐                               │
│               │             │                                │
│               ▼             ▼                                │
│          自动恢复      手动关闭                              │
│         (Recovery)   (Close problem)                         │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

---

## Mini-Project：完整告警链路配置

> 场景：为生产环境配置完整的磁盘告警链路

### 要求

1. **创建触发器**
   - Warning: 磁盘 > 80%
   - High: 磁盘 > 90%
   - Disaster: 磁盘 > 95%

2. **配置 Action**
   - Warning: 发送邮件给运维组
   - High: 发送邮件 + 短信（如有）
   - Disaster: 发送邮件 + 短信 + 电话升级

3. **配置维护窗口**
   - 每周日 02:00-06:00 系统维护
   - 抑制非 Disaster 级别告警

4. **测试**
   - 用 dd 创建文件触发各级别告警
   - 验证通知正常发送
   - 验证维护窗口抑制

---

## 面试问答

### Q: トリガーのフラッピングを防ぐには？

**A**:
- **ヒステリシス設定**: Problem expression と Recovery expression で異なる閾値を設定（例：80% で警告、75% で回復）
- **{$THRESHOLD} マクロ**: 閾値をマクロ化して調整しやすく
- **Multiple PROBLEM events**: 同じトリガーからの重複イベント生成を制御
- **nodata() 関数**: データ欠損時の誤検知を防止

### Q: Maintenance Window の使い方は？

**A**:
- **計画停止**: サーバーメンテナンス、パッチ適用時
- **定期メンテ**: 毎週日曜深夜など定期作業時間
- **長期休暇**: Golden Week、年末年始など
- **With/Without data collection**: データ継続の必要性で選択
- **一時抑制**: 誤報対応中の一時的な抑制にも使用

---

## 常见错误

| 错误 | 原因 | 解决方案 |
|------|------|----------|
| 邮件未发送 | SMTP 配置错误 | 使用 Test 功能验证 |
| Action 不触发 | Conditions 不匹配 | 检查严重级别、Host group 条件 |
| 维护窗口无效 | 时区设置错误 | 确认 Zabbix 时区为 Asia/Tokyo |
| 重复告警 | 未配置 Recovery | 添加 Recovery expression |

### 排查 Action

1. 「Reports」→「Action log」
2. 查看 Action 执行历史
3. 检查失败原因

---

## 本课小结

| 概念 | 要点 |
|------|------|
| Trigger | 基于 Item 数据的告警条件 |
| Expression | 触发条件表达式 |
| Recovery | 恢复条件，防止 Flapping |
| Severity | 6 个级别，用于分级响应 |
| Action | 触发器 → 通知的映射 |
| Maintenance | 计划内抑制告警 |
| Acknowledgment | 告警确认和处理记录 |

---

## 下一步

告警已配置！下一课我们将学习日志监控、自定义指标和 SNMP 入门。

→ [05 · 日志 + 自定义指标](../05-logs-custom/)

## 系列导航

← [03 · 基础监控](../03-monitoring-basics/) | [系列首页](../) | [05 · 日志 + 自定义指标](../05-logs-custom/) →
