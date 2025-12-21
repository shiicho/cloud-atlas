# 05 · 日志监控 + 自定义指标（Logs & Custom Metrics）

> **目标**：配置日志监控、UserParameter 自定义指标和 SNMP 入门  
> **前置**：[04 · 触发器与告警](../04-triggers-alerts/)  
> **时间**：30-35 分钟  
> **实战项目**：配置 ERROR 日志告警 + 自定义队列深度监控

## 将学到的内容

1. 配置日志监控（log[] vs logrt[]）
2. 创建日志触发器
3. UserParameter 自定义指标
4. Template 继承和 Macro 优先级
5. SNMP 监控入门

---

## Step 1 — 理解日志监控

### 1.1 log[] vs logrt[]

| Key | 用途 | 特点 |
|-----|------|------|
| `log[file,regexp]` | 监控静态文件 | 文件名固定 |
| `logrt[regexp,regexp]` | 监控轮转日志 | 支持日期通配符 |

### 1.2 日志监控工作原理

```
┌─────────────────────────────────────────────────────────────┐
│                   日志监控流程                               │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  /var/log/messages                                           │
│  ┌─────────────────────────────────────────┐                │
│  │ Dec  8 10:00:01 host INFO: Started      │                │
│  │ Dec  8 10:00:02 host ERROR: Failed      │ ◄── 新行      │
│  │ Dec  8 10:00:03 host INFO: Completed    │                │
│  └─────────────────────────────────────────┘                │
│                      │                                       │
│                      ▼                                       │
│  ┌─────────────────────────────────────────┐                │
│  │ Zabbix Agent                            │                │
│  │ - 记录上次读取位置                       │                │
│  │ - 检测新行                               │                │
│  │ - 正则匹配 (ERROR)                       │                │
│  │ - 发送匹配行到 Server                    │                │
│  └─────────────────────────────────────────┘                │
│                      │                                       │
│                      ▼                                       │
│  ┌─────────────────────────────────────────┐                │
│  │ Zabbix Server                           │                │
│  │ - 存储日志内容                           │                │
│  │ - 评估触发器                             │                │
│  │ - 生成告警                               │                │
│  └─────────────────────────────────────────┘                │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

---

## Step 2 — 配置日志监控

### 2.1 创建日志监控 Item

1. 「Data collection」→「Hosts」→ 点击 `monitored-host-01`
2. 切换到「Items」→「Create item」

**基本配置**：

| 字段 | 值 |
|------|-----|
| Name | `System log ERROR messages` |
| Type | `Zabbix agent (active)` |
| Key | `log[/var/log/messages,ERROR,,100,skip]` |
| Type of information | `Log` |
| Update interval | `1m` |

**Key 参数说明**：
```
log[file, regexp, encoding, maxlines, mode]
    │      │       │         │        │
    │      │       │         │        └─ skip: 跳过已有内容
    │      │       │         └─ 每次最多读取行数
    │      │       └─ 字符编码
    │      └─ 正则表达式匹配
    └─ 日志文件路径
```

3. 点击「Add」

### 2.2 创建日志触发器

1. 在同一主机，「Triggers」→「Create trigger」

| 字段 | 值 |
|------|-----|
| Name | `ERROR detected in system log on {HOST.NAME}` |
| Severity | `Average` |
| Expression | `count(/monitored-host-01/log[/var/log/messages,ERROR,,100,skip],5m)>0` |

这个触发器在 5 分钟内检测到任何 ERROR 时触发。

### 2.3 测试日志监控

```bash
# 在 Monitored Host 上生成测试日志
sudo logger "ERROR: Test error message for Zabbix monitoring"

# 等待 1-2 分钟
```

在 Web UI 验证：
1. 「Monitoring」→「Latest data」→ 找到日志 Item
2. 点击「History」查看捕获的日志
3. 「Monitoring」→「Problems」查看触发的告警

### 2.4 防止 DB 膨胀

> ⚠️ 日志监控可能导致数据库快速增长

**最佳实践**：
- 设置合理的 `maxlines`（如 100）
- 缩短 History 保留期（如 7 天）
- 使用精确的正则表达式，避免匹配过多

```ini
# Item 设置
History storage period: 7d
Trends storage period: 0 (日志不需要 Trends)
```

---

## Step 3 — UserParameter 自定义指标

> 🎯 **面试高频问题**：UserParameter の注意点は？

### 3.1 什么是 UserParameter

UserParameter 允许你定义自定义监控命令：

```ini
# 格式
UserParameter=<key>,<command>

# 示例
UserParameter=custom.queue.depth,cat /var/app/queue/depth.txt
UserParameter=custom.cpu.temp,sensors | grep "Core 0" | awk '{print $3}'
```

### 3.2 创建 UserParameter

在 Monitored Host 上：

```bash
# 创建配置文件
sudo vim /etc/zabbix/zabbix_agent2.d/userparameter_custom.conf
```

添加自定义监控：

```ini
# 应用队列深度（模拟）
UserParameter=custom.queue.depth,cat /tmp/queue_depth.txt 2>/dev/null || echo 0

# httpd 连接数
UserParameter=custom.httpd.connections,ss -tn state established | grep -c :80 || echo 0

# 自定义带参数
UserParameter=custom.file.linecount[*],wc -l < $1 2>/dev/null || echo 0
```

创建测试数据：

```bash
# 创建模拟队列深度文件
echo "42" | sudo tee /tmp/queue_depth.txt
```

重启 Agent：

```bash
sudo systemctl restart zabbix-agent2
```

### 3.3 测试 UserParameter

```bash
# 测试自定义 Key
zabbix_agent2 -t custom.queue.depth
# 预期输出: 42

zabbix_agent2 -t custom.httpd.connections
# 预期输出: 当前连接数

zabbix_agent2 -t 'custom.file.linecount[/etc/passwd]'
# 预期输出: /etc/passwd 行数
```

### 3.4 在 Web UI 创建 Item

1. 「Data collection」→「Hosts」→「Items」→「Create item」

| 字段 | 值 |
|------|-----|
| Name | `Application queue depth` |
| Type | `Zabbix agent` |
| Key | `custom.queue.depth` |
| Type of information | `Numeric (unsigned)` |
| Update interval | `30s` |

2. 创建触发器：

| 字段 | 值 |
|------|-----|
| Name | `Queue depth too high on {HOST.NAME}` |
| Expression | `last(/monitored-host-01/custom.queue.depth)>100` |

### 3.5 UserParameter 最佳实践

| 注意点 | 说明 |
|--------|------|
| **Timeout** | 确保命令在 Timeout 内完成（默认 3s） |
| **返回值** | 必须返回正确类型（数字/字符串） |
| **重启** | 修改后必须重启 Agent |
| **安全** | 避免执行用户输入，使用白名单 |
| **测试** | 先用 `zabbix_agent2 -t` 测试 |

---

## Step 4 — Template 继承与 Macro

### 4.1 Macro 优先级

```
Macro 优先级（高 → 低）：
┌─────────────────────────────────────┐
│ 1. Host macro                       │ ← 最高优先级
├─────────────────────────────────────┤
│ 2. Host prototype macro (LLD)       │
├─────────────────────────────────────┤
│ 3. Template macro (直接链接)        │
├─────────────────────────────────────┤
│ 4. Template macro (嵌套继承)        │
├─────────────────────────────────────┤
│ 5. Global macro                     │ ← 最低优先级
└─────────────────────────────────────┘
```

### 4.2 使用 Macro 自定义阈值

1. 编辑 Trigger Expression，使用 Macro：
   ```
   last(/host/vfs.fs.size[/,pused])>{$DISK_WARN_THRESHOLD}
   ```

2. 在 Host 级别定义 Macro：
   - 「Data collection」→「Hosts」→ 编辑主机
   - 「Macros」标签页
   - 添加：`{$DISK_WARN_THRESHOLD}` = `80`

3. 不同主机可以有不同阈值，无需修改 Trigger

### 4.3 Clone Template 进行定制

1. 「Data collection」→「Templates」
2. 找到要定制的模板
3. 点击「Full clone」
4. 修改名称和内容
5. 将定制模板链接到特定主机

---

## Step 5 — SNMP 监控入门

### 5.1 SNMP 基础概念

| 术语 | 说明 |
|------|------|
| OID | Object Identifier，唯一标识监控项 |
| MIB | Management Information Base，OID 定义库 |
| Community | 认证字符串（v1/v2c） |
| SNMPv3 | 支持加密和认证的版本 |

### 5.2 验证 SNMP 服务

在 Monitored Host 上：

```bash
# 确认 snmpd 运行
sudo systemctl status snmpd

# 本地测试 SNMP
snmpwalk -v2c -c public localhost .1.3.6.1.2.1.1.1
# 应返回系统描述
```

### 5.3 从 Server 测试 SNMP

在 Zabbix Server 上：

```bash
# 安装 SNMP 工具
sudo dnf install -y net-snmp-utils

# 测试到 Monitored Host 的 SNMP
snmpwalk -v2c -c public <MonitoredHostPrivateIP> .1.3.6.1.2.1.1.1
```

### 5.4 添加 SNMP Interface

1. 「Data collection」→「Hosts」→ 编辑 `monitored-host-01`
2. 「Interfaces」→「Add」→「SNMP」

| 字段 | 值 |
|------|-----|
| IP address | `<MonitoredHostPrivateIP>` |
| Port | `161` |
| SNMP version | `SNMPv2` |
| SNMP community | `public` |

3. 点击「Update」

### 5.5 创建 SNMP Item

1. 「Items」→「Create item」

| 字段 | 值 |
|------|-----|
| Name | `System description (SNMP)` |
| Type | `SNMP agent` |
| Key | `sysDescr` |
| SNMP OID | `.1.3.6.1.2.1.1.1.0` |
| Type of information | `Character` |

### 5.6 Agent vs SNMP 选择

| 场景 | 推荐 |
|------|------|
| Linux/Windows 服务器 | Zabbix Agent（更多指标） |
| 网络设备（交换机、路由器） | SNMP |
| 无法安装 Agent 的设备 | SNMP |
| 需要深度应用监控 | Agent + UserParameter |

---

## Mini-Project：完整日志 + 自定义监控

> 场景：监控一个 Web 应用的错误日志和队列深度

### 要求

1. **日志监控**
   - 监控 `/var/log/httpd/error_log`（或创建模拟日志）
   - 触发器：5 分钟内超过 10 条 ERROR

2. **自定义指标**
   - 创建 UserParameter 监控应用连接数
   - 触发器：连接数 > 50 告警

3. **SNMP 监控**
   - 添加 SNMP Interface
   - 创建系统运行时间 (sysUpTime) Item

### 模拟环境

```bash
# 创建模拟日志
sudo mkdir -p /var/log/myapp
sudo touch /var/log/myapp/app.log
sudo chmod 644 /var/log/myapp/app.log

# 生成测试错误日志
for i in {1..15}; do
  echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: Test error $i" | sudo tee -a /var/log/myapp/app.log
done
```

---

## 面试问答

### Q: UserParameter の注意点は？

**A**:
- **Timeout**: デフォルト 3 秒以内に完了する必要あり。長いコマンドは非同期処理
- **戻り値の型**: Item の Type of information と一致させる
- **再起動必要**: 設定変更後は `systemctl restart zabbix-agent2`
- **セキュリティ**: ユーザー入力をそのまま実行しない、パス/コマンドのホワイトリスト化
- **テスト**: 本番登録前に `zabbix_agent2 -t` でローカルテスト

### Q: SNMP と Agent、どちらをいつ使う？

**A**:
- **Agent**: サーバー監視に最適。詳細なメトリクス、カスタム監視、Active モードで NAT 越し可能
- **SNMP**: ネットワーク機器（ルーター、スイッチ）に必須。Agent インストール不可の環境
- **併用**: サーバーでも Agent + SNMP 両方設定し、Agent 障害時の代替監視

---

## 常见错误

| 错误 | 原因 | 解决方案 |
|------|------|----------|
| Log item 无数据 | Agent 无读取权限 | 确认 zabbix 用户可读取日志 |
| UserParameter 返回空 | 命令错误或超时 | 本地测试 `zabbix_agent2 -t` |
| SNMP timeout | 防火墙阻止 UDP 161 | 检查安全组 |
| DB 快速增长 | 日志 maxlines 过大 | 减小 maxlines，缩短 History |

---

## 本课小结

| 概念 | 要点 |
|------|------|
| log[] | 静态日志文件监控 |
| logrt[] | 轮转日志监控 |
| maxlines | 每次最大读取行数，防止 DB 膨胀 |
| UserParameter | 自定义监控命令 |
| Macro | 可配置参数，支持继承优先级 |
| SNMP | 网络设备标准协议 |

---

## 下一步

日志和自定义监控已配置！最后一课我们将学习 LLD、Proxy 概念和监视設計書。

→ [06 · 扩展与运维实践](../06-ops-advanced/)

## 系列导航

← [04 · 触发器与告警](../04-triggers-alerts/) | [系列首页](../) | [06 · 扩展与运维实践](../06-ops-advanced/) →
