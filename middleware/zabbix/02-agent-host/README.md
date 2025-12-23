# 02 · Agent 安装与主机管理（Agent & Host Management）

> **目标**：配置 Zabbix Agent 2，在 Web UI 注册主机
> **前置**：[01 · Server 初始化](../01-server-setup/)
> **费用**：实验环境持续产生费用（约 $0.03/小时）；完成系列后请删除堆栈
> **时间**：20-25 分钟
> **实战项目**：配置 Active Agent，创建 Host Groups 和 Tags

## 将学到的内容

1. 配置 Zabbix Agent 2（Active 模式）
2. 理解 Agent 配置关键参数
3. 在 Web UI 注册主机
4. 使用 Host Groups 和 Tags 组织主机
5. 了解 Auto-registration 机制

---

## Step 1 — 配置 Zabbix Agent 2

通过 SSM 连接到 **Monitored Host**（不是 Server）：

```bash
# 切换到 root
sudo -i

# 确认 Agent2 已安装
rpm -qa | grep zabbix-agent2
# 预期输出：zabbix-agent2-7.0.x
```

> ⚠️ **如果 Agent 2 未安装**（CloudFormation 应已安装，但如需手动安装）：
> ```bash
> rpm -Uvh https://repo.zabbix.com/zabbix/7.0/amazonlinux/2023/x86_64/zabbix-release-latest-7.0.amzn2023.noarch.rpm
> dnf clean all
> dnf install -y zabbix-agent2 zabbix-agent2-plugin-*
> ```

### 1.1 编辑 Agent 配置

```bash
# 备份原配置
cp /etc/zabbix/zabbix_agent2.conf /etc/zabbix/zabbix_agent2.conf.bak

# 编辑配置
vim /etc/zabbix/zabbix_agent2.conf
```

### 1.2 关键配置项

找到并修改以下配置（推荐 Active 模式）：

```ini
# =============================================================================
# 基础配置
# =============================================================================

# Passive mode: Server 轮询 Agent（可选，留空禁用）
# Server=

# Active mode: Agent 主动连接 Server（推荐）
ServerActive=<ZabbixServerPrivateIP>

# 主机名（⚠️ 必须与 Web UI 注册名完全一致！大小写敏感）
Hostname=monitored-host-01

# 或使用系统主机名
# HostnameItem=system.hostname

# =============================================================================
# 性能配置
# =============================================================================

# 日志级别 (0-5, 3=warnings)
DebugLevel=3

# 数据缓冲（网络中断时缓存数据）
BufferSize=1000

# 超时设置
Timeout=10

# =============================================================================
# 安全配置
# =============================================================================

# 允许的 Server（Passive mode 用）
# Server=<ZabbixServerPrivateIP>

# 允许远程命令（谨慎启用，Zabbix 7.0+ 使用 AllowKey/DenyKey）
# AllowKey=system.run[*]
# DenyKey=system.run[*]  # 默认禁用，更安全
```

> 💡 **提示**：从 CloudFormation 输出获取 `ZabbixServerPrivateIP`

### 1.3 Active vs Passive 配置对比

| 配置项 | Passive Mode | Active Mode |
|--------|--------------|-------------|
| `Server` | Server IP | 留空或注释 |
| `ServerActive` | 留空 | Server IP |
| `Hostname` | 必须设置 | 必须设置 |
| 端口 | Agent 监听 10050 | Server 监听 10051 |

### 1.4 启动 Agent

```bash
# 启动 Agent2
systemctl start zabbix-agent2

# 设置开机自启
systemctl enable zabbix-agent2

# 检查状态
systemctl status zabbix-agent2
```

预期输出：`Active: active (running)`

### 1.5 验证 Agent

```bash
# 查看日志
tail -20 /var/log/zabbix/zabbix_agent2.log
```

Active 模式成功连接时，日志显示：
```
enabling Zabbix agent checks on server [<ServerIP>:10051]
```

本地测试 Agent：

```bash
# 测试 agent.ping
zabbix_agent2 -t agent.ping

# 测试系统负载
zabbix_agent2 -t system.cpu.load[all,avg1]

# 测试主机名
zabbix_agent2 -t system.hostname
```

---

## Step 2 — 在 Web UI 注册主机

### 2.1 创建 Host Group

> Host Group 用于批量管理主机，是权限控制和模板应用的基础

1. 登录 Zabbix Web UI
2. 「Data collection」→「Host groups」→「Create host group」

3. 创建以下 Host Groups：

   | Group name | 用途 |
   |------------|------|
   | `Lab/Linux servers` | 实验室 Linux 服务器 |
   | `Lab/Web servers` | 实验室 Web 服务器 |

4. 点击「Add」

### 2.2 注册主机

1. 「Data collection」→「Hosts」→「Create host」

2. **Host 标签页**：

   > ⚠️ **CRITICAL**：`Host name` 必须与 Agent 配置的 `Hostname` **完全一致**（大小写敏感，无空格）！
   > 这是 Active Agent 无数据的 #1 原因。

   | 字段 | 值 | 说明 |
   |------|-----|------|
   | Host name | `monitored-host-01` | **必须与 Agent 配置一致！** |
   | Visible name | `Lab Web Server` | 显示名称（可选） |
   | Host groups | `Lab/Linux servers`, `Lab/Web servers` | 选择刚创建的组 |

3. **Interfaces 区域**（Active 模式配置）：

   点击「Add」→「Agent」

   | 字段 | 值 |
   |------|-----|
   | IP address | `<MonitoredHostPrivateIP>` |
   | DNS name | 留空 |
   | Connect to | IP |
   | Port | 10050 |

   > 💡 **Active 模式说明**：即使使用 Active 模式，也需要配置 Interface。
   > 此时 Server 不会主动连接 Agent 的 10050 端口，但 Interface 用于主机识别和 IP 匹配。

4. **Tags 标签页**（添加标签便于筛选）：

   | Name | Value |
   |------|-------|
   | env | lab |
   | role | web |
   | location | tokyo |

5. 点击「Add」

### 2.3 验证主机状态

1. 返回「Hosts」列表
2. 查看 `monitored-host-01` 行

   | 列 | 预期状态 |
   |----|----------|
   | Availability | 绿色 ZBX 图标（稍等 1-2 分钟） |
   | Agent | `ZBX` 绿色 |

如果显示红色或灰色：
- 检查 Agent 配置的 `Hostname` 是否与 Web UI 完全一致
- 检查 Agent 日志
- 检查安全组规则

---

## Step 3 — 理解 Host 可用性

### 可用性图标含义

| 图标 | 状态 | 说明 |
|------|------|------|
| 🟢 ZBX | 正常 | Agent 正常响应 |
| 🟡 ZBX | 不可达 | 连接失败，状态过渡中 |
| 🔴 ZBX | 异常 | Agent 无法连接 |
| ⚪ ZBX | 未知 | 尚未检查或未配置 |
| 🟢 SNMP | 正常 | SNMP 响应正常 |

### 检查连接详情

1. 点击主机名进入编辑
2. 「Interfaces」区域查看错误信息
3. 或查看「Monitoring」→「Latest data」→ 筛选该主机

---

## Step 4 — 使用 Tags 筛选

Tags 是 Zabbix 7.0 的重要特性，用于灵活筛选和权限控制。

### 4.1 按 Tag 筛选主机

1. 「Data collection」→「Hosts」
2. 点击「Filter」展开筛选器
3. 在「Tags」区域添加：
   - Name: `env`, Operator: `Equals`, Value: `lab`
4. 点击「Apply」

### 4.2 Tag 命名最佳实践

| Tag Name | 示例值 | 用途 |
|----------|--------|------|
| `env` | dev, staging, prod | 环境区分 |
| `role` | web, db, app, cache | 角色区分 |
| `location` | tokyo, osaka, singapore | 地理位置 |
| `team` | infra, dev, sre | 负责团队 |
| `criticality` | high, medium, low | 重要程度 |

---

## Step 5 — 了解 Auto-registration（预备知识）

> Auto-registration 允许 Agent 自动注册到 Server，无需手动创建主机

### 工作原理

```
┌─────────────────────────────────────────────────────────────┐
│                  Auto-registration Flow                      │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  1. Agent 启动，发送 HostMetadata                            │
│     ┌────────┐                      ┌────────┐              │
│     │ Agent  │ ───HostMetadata───► │ Server │              │
│     └────────┘                      └────────┘              │
│                                          │                   │
│  2. Server 匹配 Action 条件              │                   │
│                                          ▼                   │
│  3. 自动创建 Host，应用模板    ┌─────────────────┐          │
│                                │ Auto-created    │          │
│                                │ Host            │          │
│                                └─────────────────┘          │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### Agent 配置（启用 Auto-registration）

```ini
# zabbix_agent2.conf
ServerActive=<ServerIP>
Hostname=auto-web-01
HostMetadata=Linux WebServer Production
```

### Server Action 配置

1. 「Alerts」→「Actions」→「Autoregistration actions」
2. 创建 Action，设置条件（如 HostMetadata 包含 "WebServer"）
3. 设置操作：添加到 Host Group、链接 Template

> 💡 **概念预习**：本课仅介绍 Auto-registration 概念，用于面试准备。实际配置为进阶内容，本系列不包含完整实操。

---

## Mini-Project：主机分组设计

> 场景：你需要为一个中型系统设计 Host Group 和 Tag 策略

要求：
- 3 个环境：Development, Staging, Production
- 4 种角色：Web, API, Database, Cache
- 2 个数据中心：Tokyo, Osaka

设计你的：

1. **Host Group 结构**
   ```
   例如：
   Production/Tokyo/Web servers
   Production/Tokyo/Database servers
   ...
   ```

2. **Tag 策略**

   | Tag | 可选值 |
   |-----|--------|
   | env | ? |
   | role | ? |
   | dc | ? |

3. **思考**
   - Host Group 和 Tag 哪个更适合权限控制？
   - 哪个更适合动态筛选？

---

## 面试问答

### Q: なぜ Active Agent を推奨？

**A**:
- NAT/ファイアウォール越しに動作可能（エージェントが接続を開始）
- サーバーのポーリング負荷を分散
- エージェント側でデータをバッファリング、ネットワーク断時にも再送可能
- 大規模環境でスケーラブル

### Q: Host Group と Tag の使い分けは？

**A**:
- **Host Group**: 権限制御に使用（User groups に紐付け）、テンプレートの一括適用
- **Tag**: 柔軟なフィルタリング、動的なグループ化、アラートルーティング
- 併用が一般的：Group で大分類、Tag で詳細属性

---

## 常见错误

| 错误 | 原因 | 解决方案 |
|------|------|----------|
| Host 状态红色 | Hostname 不匹配 | 确认 Agent 配置和 Web UI 完全一致 |
| Availability 灰色 | 未配置 Interface | 添加 Agent Interface |
| Active agent 无数据 | ServerActive 配置错误 | 检查 Server Private IP |
| 连接超时 | 安全组未开放 | 确认 10051 端口（Active）或 10050（Passive） |

### 排查命令

```bash
# 检查 Agent 日志
tail -f /var/log/zabbix/zabbix_agent2.log

# 检查 Agent 配置
grep -E "^(Server|ServerActive|Hostname)" /etc/zabbix/zabbix_agent2.conf

# 测试到 Server 的连接（Active 模式）
nc -zv <ServerPrivateIP> 10051

# 从 Server 测试到 Agent（Passive 模式）
# 在 Server 上执行：
zabbix_get -s <AgentIP> -k agent.ping
```

---

## 本课小结

| 配置项 | 位置/说明 |
|--------|-----------|
| Agent 配置 | `/etc/zabbix/zabbix_agent2.conf` |
| Agent 日志 | `/var/log/zabbix/zabbix_agent2.log` |
| ServerActive | Active 模式的 Server 地址 |
| Hostname | 必须与 Web UI 注册名一致 |
| Host Groups | 权限控制和批量管理 |
| Tags | 灵活筛选和路由 |

---

## 清理提醒

> ⚠️ **费用提醒**：实验环境持续产生费用。完成整个系列后，请删除 CloudFormation 堆栈。
> 详见 → [00 · 清理资源](../00-architecture-lab/#清理资源)

---

## 下一步

主机已注册！下一课我们将应用监控模板，配置基础监控和死活检查。

→ [03 · 基础监控 + 死活检查](../03-monitoring-basics/)

## 系列导航

← [01 · Server 初始化](../01-server-setup/) | [系列首页](../) | [03 · 基础监控](../03-monitoring-basics/) →
