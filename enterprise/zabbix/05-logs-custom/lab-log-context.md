# Zabbix 日志监控 - 行业实践背景

> **选读内容**：本文档提供日志监控在生产环境和日本 IT 职场中的深度背景知识。

---

## 1. 为什么 Zabbix 需要文本日志文件

### 技术现实

Zabbix 的日志监控功能（`log[]`、`logrt[]`、`log.count[]`）**只能读取文本格式的日志文件**。
截至 Zabbix 7.0 LTS，**没有原生 systemd-journald 支持**。

| 方案 | 状态 | 生产环境适用性 |
|------|------|----------------|
| 原生 journald 支持 | 不可用（ZBXNEXT-7907 自 2022 年开放至今） | - |
| 社区插件 | "非常实验性" | 不推荐 |
| **rsyslog + log[] 监控项** | 生产就绪 | **推荐** |

### rsyslog 桥接模式

这是企业环境中的标准模式：

```
┌─────────────────────────────────────────────────────────────────────┐
│                       企业日志流转架构                                │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  应用程序/系统                                                        │
│       │                                                              │
│       ▼                                                              │
│  systemd-journald（二进制格式）                                       │
│       │                                                              │
│       ▼（imjournal 模块）                                            │
│  rsyslog                                                             │
│       │                                                              │
│       ├──────────────────┬──────────────────┐                       │
│       ▼                  ▼                  ▼                       │
│  /var/log/messages  /var/log/secure   集中日志服务器                  │
│       │                  │            (ELK/Splunk/CloudWatch)        │
│       ▼                  ▼                                          │
│  Zabbix log[] 监控项 → 触发器 → 告警                                  │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

---

## 2. 常见日志监控目标

### 按使用场景的优先级

| 日志文件 | 发行版 | 内容 | 监控优先级 |
|----------|--------|------|------------|
| `/var/log/messages` | RHEL/Amazon | 系统事件、服务故障 | **高** |
| `/var/log/syslog` | Debian/Ubuntu | 系统事件 | **高** |
| `/var/log/secure` | RHEL/Amazon | 认证、sudo、SSH | **关键** |
| `/var/log/auth.log` | Debian/Ubuntu | 认证事件 | **关键** |
| `/var/log/cron` | 所有 | 定时任务执行 | **高** |
| 应用日志 | 各异 | 服务特定错误 | **高** |

### 为什么 `/var/log/secure` 是关键

安全日志对合规性是强制性的：

- **ISMS（ISO 27001）**：追踪"谁在什么时候访问了什么"
- **PrivacyMark（JIS Q 15001）**：个人数据访问审计
- **PCI-DSS**：支付卡行业要求
- **SOX**：财务系统审计追踪

---

## 3. 日本 IT 职场背景

### 关键术语（日本語用語）

| 日语 | 读音 | 中文含义 | 使用场景 |
|------|------|----------|----------|
| ログ監視 | rogu kanshi | 日志监控 | 通用术语 |
| 運用監視 | un'you kanshi | 运维监控 | 更广泛范围（包括指标监控） |
| 障害検知 | shougai kenchi | 故障检测 | 错误/故障检测 |
| 死活監視 | shikatsu kanshi | 存活监控 | Ping/心跳检测 |
| 手順書 | tejunsho | 操作手册 | 运维操作规程 |
| 一次対応 | ichiji taiou | 一线响应 | 初始故障处理 |
| 障害報告書 | shougai houkokusho | 故障报告 | 事后文档 |

### 日本企业的 NOC 工作流程

```
障害検知（检测）
    │
    ▼
一次対応（一线响应）─── 手順書に従う（按手册操作）
    │
    ▼
エスカレーション（升级）─── 手册未覆盖的情况
    │
    ▼
復旧 + 報告（恢复 + 报告）
    │
    ▼
再発防止策（防止复发措施）
```

### 日本市场工具格局

| 工具 | 传统企业 | Web 系/初创 | 备注 |
|------|----------|-------------|------|
| **JP1（日立）** | ~90%（银行、政府） | <1% | SIer 的事实标准 |
| **Zabbix** | ~10% | ~40% | 日本社区活跃 |
| **Hinemos（NTT Data）** | ~3% | <1% | 日本开源方案，公共部门 |
| **Prometheus + Grafana** | ~5% | ~30% | 云原生首选 |
| **Datadog** | ~5% | ~35% | 现代可观测性 |

### SIer 与 Web 系文化差异

| 方面 | SIer / 传统 | Web 系 / 初创 |
|------|-------------|---------------|
| 理念 | "不漏报"（完全監視） | "只告警可操作的" |
| 响应方式 | 严格按手順書 | DevOps 直接修复 |
| 关键指标 | 根因分析 | MTTR（平均恢复时间） |
| 日志格式 | 严格预定义 | JSON 结构化 |

---

## 4. Zabbix 日志监控最佳实践

### 监控项配置

```
Key: log[/var/log/secure,"authentication failure",,100,skip]
     │                    │                       │   │   │
     │                    │                       │   │   └── 模式: skip 跳过历史
     │                    │                       │   └────── 每次最大行数
     │                    │                       └────────── 输出格式（空=默认）
     │                    └────────────────────────────────── 正则表达式
     └─────────────────────────────────────────────────────── 文件路径
```

### 关键设置

| 设置 | 推荐值 | 原因 |
|------|--------|------|
| **Type** | Zabbix agent (active) | 日志监控项**只能**使用主动模式 |
| **Update interval** | 1s | 较长间隔会导致批处理问题 |
| **Mode** | skip | 避免首次运行时处理历史条目 |
| **权限** | zabbix 用户加入 adm 组 | 读取日志文件的权限 |

### 常见反模式

1. **使用被动检查** - 日志监控项需要主动模式
2. **忘记 mode: skip** - 会从旧条目触发误报
3. **更新间隔过长** - 5 分钟间隔会导致负载峰值
4. **忽略权限** - 出现 "Item not supported" 错误

---

## 5. 日本 IT 职场的真实场景

### 场景 1：SSH 暴力破解检测（ISMS 合规）

```yaml
Item:
  Key: log[/var/log/secure,"Failed password",,100,skip]
  Type: Zabbix agent (active)

Trigger:
  Expression: count(/host/log[...],5m)>5
  Severity: High

# 日本职场背景：ISMS 要求检测未授权访问尝试
# 这是标准的運用監視要求
```

### 场景 2：夜间批处理监控

```yaml
Item:
  Key: log[/var/log/cron,"error|failed",,100,skip]
  Type: Zabbix agent (active)

Trigger:
  Expression: find(/host/log[...],,"regexp","error|failed")=1
  Severity: Average

# 日本职场背景：批处理在传统 IT 中至关重要
# 很多系统运行夜間バッチ（夜间批处理）任务
```

### 场景 3：Web 服务器错误检测

```yaml
Item:
  Key: logrt[/var/log/httpd/error_log.*,"error|crit|alert",,100,skip]
  Type: Zabbix agent (active)

# 注意：logrt[] 用于轮转日志（Apache 使用日期轮转）
```

---

## 6. 发行版特定说明

### Amazon Linux 2023

- **默认**：仅 systemd-journald，无 rsyslog
- **操作**：安装 rsyslog 以创建 /var/log/messages、/var/log/secure
- **参考**：[AWS Docs - journald](https://docs.aws.amazon.com/linux/al2023/ug/journald.html)

### RHEL 8/9

- **默认**：journald 和 rsyslog 都已安装
- **说明**：rsyslog 通过 imjournal 从 journald 读取

### Ubuntu 22.04+

- **默认**：journald + rsyslog
- **日志路径**：/var/log/syslog、/var/log/auth.log

---

## 参考资料

### 官方文档
- [Zabbix 日志文件监控](https://www.zabbix.com/documentation/current/en/manual/config/items/itemtypes/log_items)
- [Zabbix 功能请求 ZBXNEXT-7907](https://support.zabbix.com/browse/ZBXNEXT-7907)
- [AWS AL2023 journald](https://docs.aws.amazon.com/linux/al2023/ug/journald.html)
- [rsyslog imjournal](https://www.rsyslog.com/doc/configuration/modules/imjournal.html)

### 日本资源
- [Qiita: Zabbix ログ監視設定](https://qiita.com/search?q=zabbix+log)
- [総務省: 監査ログ管理](https://www.soumu.go.jp/main_sosiki/cybersecurity/kokumin/security/business/admin/12/)

---

*本文档是 Zabbix 课程第 05 课的补充材料。*
