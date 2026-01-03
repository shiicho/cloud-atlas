# 03 · 基础监控 + 死活检查（Monitoring Basics）

> **目标**：应用监控模板，配置进程和服务死活检查  
> **前置**：[02 · Agent 与主机管理](../02-agent-host/)  
> **费用**：实验环境持续产生费用（约 $0.03/小时）；完成系列后请删除堆栈  
> **时间**：25-30 分钟  
> **实战项目**：配置 httpd 进程和 HTTP 服务死活监控

## 将学到的内容

1. 链接 Linux 监控模板
2. 理解 Items、Triggers、Graphs 关系
3. 配置进程监控（proc.num）
4. 配置服务死活检查（net.tcp.service）
5. 理解 History vs Trends 数据存储

---

## Step 1 — 链接监控模板

### 1.1 什么是 Template？

Template（模板）是预定义的监控配置集合，包含：
- Items（监控项）
- Triggers（触发器）
- Graphs（图表）
- Discovery rules（发现规则）

### 1.2 链接 Linux 模板

1. 「Data collection」→「Hosts」
2. 点击 `monitored-host-01`
3. 切换到「Templates」标签页
4. 点击「Link new templates」
5. 搜索 `Linux by Zabbix agent active`
6. 选择「Linux by Zabbix agent active」

   > ⚠️ **重要**：必须选择 **active** 版本的模板！
   >
   > Zabbix 提供两种 Linux 模板：
   > | 模板名 | Item 类型 | 适用场景 |
   > |--------|----------|----------|
   > | `Linux by Zabbix agent` | Passive | Agent 配置了 `Server=` |
   > | `Linux by Zabbix agent active` | Active | Agent 配置了 `ServerActive=` |
   >
   > 我们在 [Lesson 02](../02-agent-host/) 配置了 Active-only 模式，所以必须使用 Active 版本模板。
   > **选错模板会导致所有监控项显示 "Without data"**——这是面试常考的排障场景。

7. 点击「Update」

### 1.3 查看继承的监控项

1. 「Data collection」→「Hosts」
2. 点击主机名旁的「Items」链接
3. 可看到大量继承的监控项：

   | Item 类型 | 示例 |
   |-----------|------|
   | CPU | CPU utilization, CPU load |
   | Memory | Memory utilization, Available memory |
   | Disk | Filesystem space usage |
   | Network | Network interface stats |
   | System | Uptime, Number of processes |

---

## Step 2 — 查看监控数据

### 2.1 Latest data（最新数据）

1. 「Monitoring」→「Latest data」
2. 在 Host 筛选器中选择 `monitored-host-01`
3. 等待 1-2 分钟，数据开始出现

常用筛选：
- Name: 输入 `cpu` 筛选 CPU 相关
- Name: 输入 `memory` 筛选内存相关

### 2.2 查看图表

1. 「Monitoring」→「Hosts」
2. 点击主机行的「Graphs」链接
3. 查看预定义图表：
   - CPU utilization
   - Memory usage
   - Network traffic

### 2.3 理解 Item 详情

点击任意 Item 名称查看详情：

| 字段 | 说明 |
|------|------|
| Key | 监控项唯一标识（如 `system.cpu.load[all,avg1]`） |
| Type | 采集方式（Zabbix agent, SNMP 等） |
| Update interval | 采集频率 |
| History | 原始数据保留时间 |
| Trends | 趋势数据保留时间 |

---

## Step 3 — 配置进程监控（死活監視）

> 🎯 **面试高频问题**：死活監視で使う Item は？

### 3.0 排障技巧：Item 无数据怎么办？

> 🎯 **面试高频场景**：Item 显示 "Without data"，如何排查？

如果遇到 Item 显示 "Without data"，按以下顺序检查：

**1. 检查 Agent 配置模式**
```bash
# 在 Monitored Host 上
grep -E "^(Server|ServerActive)=" /etc/zabbix/zabbix_agent2.conf
```
- 有 `ServerActive=` → 需要 Active 类型 Items/模板
- 有 `Server=` → 可以使用 Passive 类型 Items/模板

**2. 检查模板版本**
| 模板名 | Item 类型 | 适用场景 |
|--------|----------|----------|
| `Linux by Zabbix agent` | Passive | Agent 配置了 `Server=` |
| `Linux by Zabbix agent active` | Active | Agent 配置了 `ServerActive=` |

**3. 检查手动创建的 Item**
| Item Type | 数据流向 | 适用场景 |
|-----------|----------|----------|
| `Zabbix agent` | Server → Agent（被动） | Agent 配置了 `Server=` |
| `Zabbix agent (active)` | Agent → Server（主动） | Agent 配置了 `ServerActive=` |

> 💡 **本课使用 `Linux by Zabbix agent active` 模板**，所有继承的 Items 都自动使用 Active 类型。  
> 手动创建的 Items 也需要选择 **`Zabbix agent (active)`** 类型以匹配 Agent 配置。

### 3.1 proc.num - 进程数量监控

监控 httpd 进程是否运行：

> 💡 **注意**：`httpd` 运行在 **Monitored Host**（被监控主机），用于演示进程和服务监控。  
> Zabbix Server 也使用 Apache（httpd）作为 Web 服务器，但本课监控的是 Monitored Host 上的 httpd 进程。

**前置确认**：确保 Monitored Host 上 httpd 正在运行（CloudFormation 模板应已启动）：

```bash
# 在 Monitored Host 上检查
systemctl status httpd
# 如未运行：
# sudo dnf install -y httpd && sudo systemctl enable --now httpd
```

1. 「Data collection」→「Hosts」→ 点击 `monitored-host-01`
2. 切换到「Items」标签页
3. 点击「Create item」

   | 字段 | 值 |
   |------|-----|
   | Name | `httpd process count` |
   | Type | `Zabbix agent (active)` |
   | Key | `proc.num[httpd]` |
   | Type of information | `Numeric (unsigned)` |
   | Update interval | `1m` |
   | History storage period | `14d` |
   | Trend storage period | `365d` |

   > 💡 **为什么用 Active 类型？** 在 Lesson 02 中，我们配置了 Agent 为 Active 模式（`ServerActive`）。
   > Active 类型的 Item 由 Agent 主动推送数据，与 Agent 配置一致。

4. 点击「Add」

### 3.2 验证进程监控

```bash
# 在 Monitored Host 上
# 检查 httpd 状态
systemctl status httpd

# 手动测试 proc.num
zabbix_agent2 -t 'proc.num[httpd]'
# 预期输出: proc.num[httpd]                         [s|X]
# X = 进程数量（如 5）
```

在 Web UI「Latest data」中验证数据出现。

---

## Step 4 — 配置服务死活检查

### 4.1 net.tcp.service - HTTP 服务检查

检查 HTTP 端口是否响应：

> ⚠️ **重要**：`net.tcp.service` 是 **Simple check** 类型，由 Zabbix Server 直接检测目标端口，不经过 Agent。  
> 这是常见错误点：如果选择 "Zabbix agent" 类型，Item 会显示 "Unsupported"。

1. 在同一主机，「Items」→「Create item」

   | 字段 | 值 |
   |------|-----|
   | Name | `HTTP service status` |
   | Type | **`Simple check`** |
   | Key | `net.tcp.service[http,,80]` |
   | Type of information | `Numeric (unsigned)` |
   | Update interval | `1m` |
   | Description | `1 = 服务正常, 0 = 服务异常` |

2. 点击「Add」

### 4.2 net.tcp.port - TCP 端口检查

更简单的端口检查方式（同样是 Simple check）：

| 字段 | 值 |
|------|-----|
| Name | `Port 80 status` |
| Type | **`Simple check`** |
| Key | `net.tcp.port[,80]` |
| Type of information | `Numeric (unsigned)` |

> 💡 **Agent 本地端口检查**：如需从 Agent 侧检查本机端口监听状态，使用 `net.tcp.listen[80]`（Type: Zabbix agent (active)）。

### 4.3 死活检查 Key 对比

| Key | Item Type | 用途 | 返回值 |
|-----|-----------|------|--------|
| `proc.num[name]` | Zabbix agent (active) | 进程数量 | 进程数（0=未运行） |
| `net.tcp.listen[port]` | Zabbix agent (active) | 本机端口监听 | 1=监听, 0=未监听 |
| `net.tcp.service[service,,port]` | **Simple check** | 服务响应（Server 侧检测） | 1=正常, 0=异常 |
| `net.tcp.port[,port]` | **Simple check** | 端口连接（Server 侧检测） | 1=连接成功, 0=失败 |
| `net.tcp.service.perf[service,,port]` | **Simple check** | 响应时间 | 秒数 |

> 💡 **Item Type 选择规则**：  
> - `proc.*`、`net.tcp.listen` = Agent 本地检查 → 选 **Zabbix agent (active)**（配合 Active 模式 Agent）  
> - `net.tcp.service`、`net.tcp.port` = Server 远程检查 → 选 **Simple check**

---

## Step 5 — 创建简单触发器

为 httpd 进程创建告警触发器：

1. 「Data collection」→「Hosts」→ 点击主机「Triggers」
2. 点击「Create trigger」

   | 字段 | 值 |
   |------|-----|
   | Name | `httpd process not running on {HOST.NAME}` |
   | Severity | `High` |
   | Expression | 点击「Add」打开表达式构建器 |

3. **构建表达式**：
   - Item: 选择 `httpd process count`
   - Function: `last()` = 0
   - 或直接输入：`last(/monitored-host-01/proc.num[httpd])=0`

4. **Recovery expression**（可选，防止 flapping）：
   - `last(/monitored-host-01/proc.num[httpd])>=1`

5. 点击「Add」

---

## Step 6 — 测试死活监控

### 6.1 停止 httpd 触发告警

在 Monitored Host 上：

```bash
# 停止 httpd
sudo systemctl stop httpd

# 等待 1-2 分钟
```

在 Web UI：
1. 「Monitoring」→「Problems」
2. 应看到 `httpd process not running` 告警

### 6.2 恢复服务

```bash
# 启动 httpd
sudo systemctl start httpd
```

在 Web UI：
1. 问题应自动恢复（如果配置了 Recovery expression）
2. 或手动确认（Acknowledge）

---

## Step 7 — 理解数据存储

### History vs Trends 实际数据

```
                     History (原始数据)
Time        Value
─────────────────────────
10:00:00    45.2%
10:01:00    47.8%
10:02:00    43.1%
...
10:59:00    51.2%

                     Trends (聚合数据)
Hour        Min    Max    Avg
─────────────────────────────────
10:00       41.0   52.3   46.8
11:00       38.5   55.1   44.2
```

### 查看存储差异

1. 「Monitoring」→「Latest data」
2. 点击任意 Item 的「History」
3. 对比短期（History）和长期（Trends）数据

---

## Mini-Project：完整死活监控配置

> 场景：配置一套完整的 Web 服务器死活监控

### 要求

为 `monitored-host-01` 配置：

1. **进程监控**
   - httpd 进程数量
   - 触发器：进程为 0 时告警

2. **服务监控**
   - HTTP 80 端口响应
   - 触发器：服务无响应时告警

3. **响应时间监控**
   - HTTP 响应时间
   - 触发器：响应时间 > 3 秒告警

### 参考 Key

| 监控项 | Key |
|--------|-----|
| httpd 进程数 | `proc.num[httpd]` |
| HTTP 服务 | `net.tcp.service[http,,80]` |
| HTTP 响应时间 | `net.tcp.service.perf[http,,80]` |

### 测试场景

```bash
# 场景 1：停止服务
sudo systemctl stop httpd
# 预期：进程=0，服务=0

# 场景 2：启动服务
sudo systemctl start httpd
# 预期：进程>0，服务=1

# 场景 3：模拟慢响应（高级）
# 使用 tc 添加网络延迟
```

---

## 面试问答

### Q: 死活監視で使う Item は？

**A**:
- **proc.num**: プロセス数を監視。`proc.num[httpd]` で httpd プロセス数を取得
- **net.tcp.service**: サービス応答を確認。`net.tcp.service[http,,80]` で HTTP 応答チェック
- **net.tcp.port**: ポート開放を確認。よりシンプルな死活チェック
- **proc.mem**: プロセスのメモリ使用量も併せて監視することが多い

### Q: Item Type の違いは？

**A**:
- **Zabbix agent**: エージェント経由でデータ取得（Passive/Active）
- **Zabbix agent (active)**: Active チェック専用（バッファリング対応）
- **Simple check**: サーバーから直接チェック（ping, tcp port）
- **SNMP agent**: SNMP 経由でデータ取得

---

## 常见错误

| 错误 | 原因 | 解决方案 |
|------|------|----------|
| Item 显示 Unsupported | Agent 权限不足 | 检查 zabbix 用户权限 |
| Graph 无数据 | 采集未开始 | 等待 Update interval |
| proc.num 返回 0 | 进程名错误 | 使用 `ps aux` 确认进程名 |
| Trigger 不触发 | Expression 错误 | 检查 Item key 和语法 |

### 排查技巧

```bash
# 确认进程名
ps aux | grep -i http

# 测试 Agent 取值
zabbix_agent2 -t 'proc.num[httpd]'
zabbix_agent2 -t 'net.tcp.service[http,,80]'

# 检查 Agent 日志
tail -f /var/log/zabbix/zabbix_agent2.log
```

---

## 本课小结

| 概念 | 要点 |
|------|------|
| Template | 预定义监控配置集合，继承给主机 |
| Item | 单个监控项，定义采集什么数据 |
| Trigger | 基于 Item 数据的告警条件 |
| proc.num | 进程数量监控 |
| net.tcp.service | 服务响应监控 |
| History | 原始数据，短期保留 |
| Trends | 聚合数据，长期保留 |

---

## 清理提醒

> ⚠️ **费用提醒**：实验环境持续产生费用。完成整个系列后，请删除 CloudFormation 堆栈。  
> 详见 → [00 · 清理资源](../00-architecture-lab/#清理资源)

---

## 下一步

监控数据已开始采集！下一课我们将配置触发器告警、邮件通知和维护窗口。

→ [04 · 触发器与告警](../04-triggers-alerts/)

## 系列导航

← [02 · Agent 与主机管理](../02-agent-host/) | [系列首页](../) | [04 · 触发器与告警](../04-triggers-alerts/) →
