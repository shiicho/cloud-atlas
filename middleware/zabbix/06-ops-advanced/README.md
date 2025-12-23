# 06 · 扩展与运维实践（Advanced Ops - Capstone）

> **目标**：掌握 LLD、Proxy 概念，创建 Dashboard 和監視設計書
> **前置**：[05 · 日志 + 自定义指标](../05-logs-custom/)
> **费用**：实验环境持续产生费用（约 $0.03/小时）；完成本课后请删除堆栈
> **时间**：35-40 分钟
> **Capstone**：编写完整的監視設計書

## 将学到的内容

1. Low-Level Discovery (LLD) 低级别发现
2. Zabbix Proxy 架构与使用场景
3. 创建运维 Dashboard
4. 配置定期报告
5. （可选）Slack Webhook 集成
6. 【Capstone】编写監視設計書
7. 性能调优基础

---

## Step 1 — Low-Level Discovery (LLD)

> 🎯 **面试高频问题**：LLD の仕組みは？

### 1.1 LLD 工作原理

```
┌─────────────────────────────────────────────────────────────┐
│                    LLD 工作流程                              │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  1. Discovery Rule 执行                                      │
│     ┌─────────────────────────────────────────────┐         │
│     │ vfs.fs.discovery                            │         │
│     │ 返回: [{#FSNAME}: "/", {#FSTYPE}: "xfs"},   │         │
│     │       [{#FSNAME}: "/home", ...}]            │         │
│     └─────────────────────────────────────────────┘         │
│                         │                                    │
│                         ▼                                    │
│  2. Item Prototype 实例化                                    │
│     ┌─────────────────────────────────────────────┐         │
│     │ vfs.fs.size[{#FSNAME},free]                 │         │
│     │ ───────────────────────────                 │         │
│     │ 生成:                                        │         │
│     │   - vfs.fs.size[/,free]                     │         │
│     │   - vfs.fs.size[/home,free]                 │         │
│     └─────────────────────────────────────────────┘         │
│                         │                                    │
│                         ▼                                    │
│  3. Trigger Prototype 实例化                                 │
│     ┌─────────────────────────────────────────────┐         │
│     │ {#FSNAME} 空间不足告警                       │         │
│     │ ───────────────────────────                 │         │
│     │ 生成:                                        │         │
│     │   - / 空间不足告警                           │         │
│     │   - /home 空间不足告警                       │         │
│     └─────────────────────────────────────────────┘         │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### 1.2 查看 Filesystem Discovery

Linux by Zabbix agent 模板已包含 LLD 规则。

1. 「Data collection」→「Hosts」→ 点击 `monitored-host-01`
2. 切换到「Discovery rules」标签页
3. 找到「Mounted filesystem discovery」

查看：
- **Key**: `vfs.fs.discovery`
- **Filter**: 排除 tmpfs 等临时文件系统

### 1.3 查看自动创建的 Items

1. 切换到「Items」标签页
2. 筛选包含 `vfs.fs` 的 Items
3. 应看到每个文件系统的独立监控项：
   - `Space utilization /`
   - `Space utilization /boot`
   - 等等

### 1.4 LLD 宏

| 宏 | 说明 | 适用 Discovery |
|----|------|--------------|
| `{#FSNAME}` | 文件系统名（如 `/`, `/home`） | Filesystem |
| `{#FSTYPE}` | 文件系统类型（如 `xfs`, `ext4`） | Filesystem |
| `{#FSLABEL}` | 文件系统卷标（Zabbix 6.0+） | Filesystem |
| `{#IFNAME}` | 网络接口名（如 `eth0`） | Network interface |
| `{#IFTYPE}` | 接口类型（如 `loopback`, `ethernetCsmacd`） | Network interface |

**查看网络接口 Discovery**：

1. 在 Host 的「Discovery rules」页面
2. 找到「Network interface discovery」
3. 自动发现所有网卡并创建监控项（网卡流量、错误包等）

### 1.5 自定义 LLD 规则（进阶）

创建自定义发现规则示例：

```bash
# 安装 jq（JSON 处理工具，LLD 输出需要 JSON 格式）
sudo dnf install -y jq

# 创建发现脚本
sudo vim /etc/zabbix/zabbix_agent2.d/discovery_apps.conf
```

```ini
# 发现运行中的 Java 应用
UserParameter=custom.java.discovery,ps aux | grep -E 'java.*-jar' | awk '{print $NF}' | sed 's/.*\///' | sort -u | jq -R -s 'split("\n") | map(select(length > 0)) | map({"{#APPNAME}": .})'
```

> 💡 **LLD 输出格式**：自定义 LLD 规则必须返回 JSON 格式的宏数组，如 `[{"{#APPNAME}": "app1"}, {"{#APPNAME}": "app2"}]`。

---

## Step 2 — Zabbix Proxy 概念

> 本课仅介绍概念，不实际部署 Proxy

### 2.1 Proxy 架构

```
┌─────────────────────────────────────────────────────────────┐
│                    Proxy 架构                                │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌─────────────────┐              ┌─────────────────┐       │
│  │   Head Office   │              │   Branch Office │       │
│  │                 │              │                 │       │
│  │ ┌─────────────┐ │   WAN Link   │ ┌─────────────┐ │       │
│  │ │   Zabbix    │ │◄────────────►│ │   Zabbix    │ │       │
│  │ │   Server    │ │  (encrypted) │ │   Proxy     │ │       │
│  │ └─────────────┘ │              │ └─────────────┘ │       │
│  │       ▲         │              │       ▲         │       │
│  │       │         │              │       │         │       │
│  │ ┌─────┴─────┐   │              │ ┌─────┴─────┐   │       │
│  │ │ Local     │   │              │ │ Remote    │   │       │
│  │ │ Agents    │   │              │ │ Agents    │   │       │
│  │ └───────────┘   │              │ └───────────┘   │       │
│  │                 │              │                 │       │
│  └─────────────────┘              └─────────────────┘       │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### 2.2 Proxy 使用场景

| 场景 | 说明 |
|------|------|
| **多站点监控** | 各分支部署 Proxy，本地收集后汇总 |
| **DMZ 监控** | Proxy 放在 DMZ，只需开放到 Server 的连接 |
| **WAN 负载分散** | Proxy 缓存数据，批量发送，减少 WAN 流量 |
| **高可用** | 多 Proxy 分担负载 |

### 2.3 Proxy 模式

| 模式 | 方向 | 端口 | 适用场景 |
|------|------|------|----------|
| Active | Proxy → Server | 10051 | Proxy 在 NAT 后 |
| Passive | Server → Proxy | 10051 | Server 可直接访问 Proxy |

### 2.4 Proxy Groups（Zabbix 7.0 新功能）

Zabbix 7.0 引入了 Proxy Groups，用于高可用和负载均衡：

| 功能 | 说明 |
|------|------|
| **HA 高可用** | 多个 Proxy 组成 Group，自动故障切换 |
| **负载均衡** | 主机自动分配到不同 Proxy |
| **配置同步** | Group 内 Proxy 共享配置 |

> 💡 **生产环境建议**：关键站点部署 Proxy Group（至少 2 个 Proxy），确保单点故障不影响监控。

---

## Step 3 — 创建运维 Dashboard

### 3.1 创建新 Dashboard

1. 「Dashboards」→「Create dashboard」
2. 输入名称：`Ops Overview`

### 3.2 添加 Problems Widget

1. 点击「Add widget」
2. 配置：

| 字段 | 值 |
|------|-----|
| Type | Problems |
| Name | Current Problems |
| Host groups | Lab/Linux servers |
| Show | Recent problems |
| Show tags | 3 (plain text) |

### 3.3 添加 Graph Widget

1. 添加另一个 Widget
2. 配置：

| 字段 | 值 |
|------|-----|
| Type | Graph (classic) |
| Name | CPU Utilization |
| Host | monitored-host-01 |
| Graph | CPU utilization |

### 3.4 添加 Host Availability Widget

| 字段 | 值 |
|------|-----|
| Type | Host availability |
| Name | Host Status |
| Host groups | Lab/Linux servers |
| Interface type | Agent |

### 3.5 Dashboard 布局

```
┌─────────────────────────────────────────────────────────────┐
│                    Ops Overview Dashboard                    │
├─────────────────┬─────────────────┬─────────────────────────┤
│   Problems      │   CPU Graph     │   Host Availability     │
│   Widget        │   Widget        │   Widget                │
│                 │                 │                         │
│   [当前问题列表] │   [CPU 趋势图]  │   [主机状态统计]        │
│                 │                 │                         │
├─────────────────┴─────────────────┴─────────────────────────┤
│                    Memory Graph Widget                       │
│                    [内存使用趋势图]                           │
└─────────────────────────────────────────────────────────────┘
```

### 3.6 设为默认 Dashboard

1. 保存 Dashboard
2. 点击齿轮图标 → 「Set as default」

### 3.7 Zabbix 7.0 新 Widget 类型

| Widget | 用途 |
|--------|------|
| **Honeycomb** | 蜂窝状显示主机状态 |
| **Gauge** | 仪表盘式数值显示 |
| **Top triggers** | 最频繁触发的告警 |
| **SLA report** | SLA 达成率报告 |
| **Item navigator** | Item 值浏览器 |

> 💡 探索「Add widget」菜单查看所有可用 Widget 类型。

---

## Step 4 — 配置定期报告

### 4.1 导出 CSV 报告

使用 Zabbix API 或 Web UI 导出数据：

1. 「Monitoring」→「Latest data」
2. 筛选所需主机和 Items
3. 点击「Export」（CSV 格式）

### 4.2 使用 cron 自动导出（进阶）

```bash
# 创建报告脚本
cat > ~/generate_report.sh << 'EOF'
#!/bin/bash
# Zabbix Daily Report Generator

ZABBIX_API="http://localhost/zabbix/api_jsonrpc.php"
REPORT_DIR="/var/reports/zabbix"
DATE=$(date +%Y%m%d)

mkdir -p "$REPORT_DIR"

# 使用 zabbix_sender 或 API 导出数据
# （实际实现需要 API Token）

echo "Report generated: $REPORT_DIR/report_$DATE.csv"
EOF

chmod +x ~/generate_report.sh
```

### 4.3 Scheduled Reports（Zabbix 7.0+）

> ⚠️ **前置条件**：Scheduled Reports 需要以下组件：
> - Zabbix Web Service（独立服务，用于 PDF 生成）
> - Google Chrome 或 Chromium（PDF 渲染）
> - 正确配置的 Frontend URL

**检查前置条件**：

```bash
# 确认 zabbix-web-service 已安装
rpm -qa | grep zabbix-web-service
# 如未安装（本实验环境可选）：
# sudo dnf install -y zabbix-web-service chromium

# 确认服务运行
systemctl status zabbix-web-service
```

**配置 Scheduled Report**：

1. 「Reports」→「Scheduled reports」
2. 点击「Create scheduled report」
3. 基本配置：

| 字段 | 值 |
|------|-----|
| Name | `Daily Ops Report` |
| Dashboard | 选择之前创建的 Dashboard |
| Period | `Previous day` |
| Cycle | `Daily` |
| Start time | `08:00` |

4. 配置接收者（Subscriptions 标签页）
5. 点击「Add」

> 💡 **生产环境提示**：Scheduled Reports 生成 PDF 需要较多资源，建议安排在非高峰时段。

---

## Step 5 — Slack 通知（可选）

> ⚠️ **可选内容**：此步骤需要 Slack 工作区管理员权限，实验环境可跳过。

### 5.1 Slack 集成方式选择

| 方式 | 状态 | 推荐度 |
|------|------|--------|
| Incoming Webhook | ⚠️ 旧版，功能受限 | 不推荐 |
| **Bot OAuth Token** | ✅ 官方推荐 | **推荐** |
| Zabbix 官方模板 | ✅ Zabbix 7.0 内置 | **最推荐** |

### 5.2 使用 Zabbix 官方 Slack 模板（推荐）

Zabbix 7.0 内置了官方 Slack 模板，无需自定义脚本：

1. 「Alerts」→「Media types」
2. 找到「Slack」（预置模板）
3. 点击配置

**创建 Slack Bot**：

1. 访问 https://api.slack.com/apps
2. 点击「Create New App」→「From scratch」
3. 输入 App 名称（如 `Zabbix Alerts`），选择 Workspace
4. 左侧菜单「OAuth & Permissions」
5. 在「Scopes」→「Bot Token Scopes」添加：
   - `chat:write`（发送消息）
   - `chat:write.public`（发送到公开频道）
6. 点击「Install to Workspace」
7. 复制「Bot User OAuth Token」（以 `xoxb-` 开头）

**配置 Media Type**：

| 参数 | 值 |
|------|-----|
| bot_token | `xoxb-your-token-here` |
| channel | `#alerts` 或 Channel ID |

### 5.3 配置 User Media

1. 「Users」→ 编辑用户 → 「Media」标签
2. 点击「Add」
3. Type: `Slack`
4. Send to: 频道名（如 `#zabbix-alerts`）或用户 ID
5. 点击「Add」→「Update」

### 5.4 测试 Slack 通知

1. 在「Media types」页面找到 Slack
2. 点击「Test」
3. 填写测试参数：
   - Send to: `#test-channel`
   - Subject: `Test Alert`
   - Message: `This is a test from Zabbix`
4. 检查 Slack 频道是否收到消息

---

## Step 6 — 【Capstone】監視設計書

> 日本企业的监控项目必须有監視設計書（监控设计文档）

### 6.1 監視設計書模板

```markdown
# 監視設計書

## 1. 文書情報
| 項目 | 内容 |
|------|------|
| 文書名 | XXX システム監視設計書 |
| 版数 | 1.0 |
| 作成日 | 2025-XX-XX |
| 作成者 | XXX |
| 承認者 | XXX |

## 2. 目的・スコープ

### 2.1 監視目的
- システムの安定稼働を確保する
- 障害を早期検知し、影響を最小化する
- キャパシティ計画に必要なデータを収集する

### 2.2 監視範囲
| 環境 | 対象サーバー数 | 備考 |
|------|----------------|------|
| Production | XX 台 | |
| Staging | XX 台 | |
| Development | XX 台 | 営業時間のみ |

## 3. 監視体制

### 3.1 通常運用
| 時間帯 | 担当 | 連絡先 |
|--------|------|--------|
| 平日 9:00-18:00 | 運用チーム | xxx@example.com |
| 夜間・休日 | 待機者 | On-call |

### 3.2 エスカレーションフロー
```
Level 1: 運用チーム (15分以内対応)
    ↓ 30分未解決
Level 2: システム担当者
    ↓ 1時間未解決
Level 3: マネージャー
```

### 3.3 ゴールデンウィーク対応
- 期間: 5/3 - 5/7
- 体制: 縮小体制（待機者のみ）
- Disaster 以外はメンテナンスウィンドウ設定

## 4. 監視項目一覧

### 4.1 基本監視
| 監視項目 | 閾値(Warning) | 閾値(Critical) | 対象 |
|----------|---------------|----------------|------|
| CPU使用率 | 80% | 95% | 全サーバー |
| メモリ使用率 | 80% | 95% | 全サーバー |
| ディスク使用率 | 80% | 90% | 全サーバー |
| プロセス死活 | - | 0 | 指定プロセス |

### 4.2 サービス死活監視
| 監視項目 | 方式 | 間隔 | 対象 |
|----------|------|------|------|
| HTTP応答 | net.tcp.service | 1分 | Webサーバー |
| DB接続 | proc.num | 1分 | DBサーバー |

### 4.3 ログ監視
| 対象ログ | パターン | 重要度 |
|----------|----------|--------|
| /var/log/messages | ERROR | Average |
| /var/log/httpd/error_log | 5xx | High |

## 5. 通知設計

### 5.1 通知マトリクス
| 重要度 | 通知先 | 方式 | 時間帯 |
|--------|--------|------|--------|
| Information | - | - | - |
| Warning | 運用ML | Email | 24h |
| Average | 運用ML | Email | 24h |
| High | 運用ML + Slack | Email + Slack | 24h |
| Disaster | 担当者 + 管理者 | Email + 電話 | 24h |

### 5.2 通知抑制
- メンテナンスウィンドウ中は Disaster 以外を抑制
- 依存関係設定により連鎖アラートを抑制

## 6. データ保持設計

| データ種別 | 保持期間 | 理由 |
|------------|----------|------|
| History | 14日 | 障害分析に十分 |
| Trends | 365日 | 年次キャパシティ計画 |
| Events | 365日 | 監査要件 |

## 7. バックアップ・DR

### 7.1 バックアップ
| 対象 | 方式 | 頻度 | 保持 |
|------|------|------|------|
| DB | mysqldump | 日次 | 7世代 |
| 設定ファイル | rsync | 日次 | 30世代 |

### 7.2 DR
- RTO: 4時間
- RPO: 24時間
- 復旧手順: 別紙「復旧手順書」参照

## 8. 変更履歴
| 版数 | 日付 | 変更者 | 変更内容 |
|------|------|--------|----------|
| 1.0 | 2025-XX-XX | XXX | 初版作成 |
```

### 6.2 作成練習

上記テンプレートを使用して、実験環境の監視設計書を作成してください：

1. **監視対象**: Zabbix Lab 環境（Server + Monitored Host）
2. **監視項目**: 本シリーズで設定したすべての監視
3. **閾値設計**: 適切な Warning/Critical 閾値
4. **通知設計**: Email 通知のマトリクス
5. **メンテナンス**: Golden Week 対応

---

## Step 7 — 性能调优 {#性能调优}

> 当监控规模扩大时（100+ 主机），可能需要调整 Server 性能参数

### 7.1 何时需要调优？

| 症状 | 检查位置 | 可能原因 |
|------|----------|----------|
| 数据延迟 | `Monitoring → Queue` | Pollers 不足 |
| 日志显示 "cache is full" | Server log | Cache 太小 |
| Web UI 响应慢 | DB 查询 | 需要优化 DB |

### 7.2 关键性能参数

编辑 `/etc/zabbix/zabbix_server.conf`：

```ini
# =============================================================================
# 进程配置（根据监控规模调整）
# =============================================================================

# 主动轮询进程数（用于获取 Passive Agent 数据）
StartPollers=5              # 默认 5，大规模可增至 50-100

# 不可达主机轮询进程数
StartPollersUnreachable=1   # 默认 1，网络不稳定时增加

# Trapper 进程数（用于接收 Active Agent 数据）
StartTrappers=5             # 默认 5，Active Agent 多时增加

# Discovery 进程数
StartDiscoverers=1          # 默认 1，LLD 规则多时增加

# =============================================================================
# 缓存配置（根据内存调整）
# =============================================================================

# 配置缓存（存放 hosts/items/triggers 配置）
CacheSize=32M               # 默认 8M，大规模需 128M-256M

# 历史数据写入缓存
HistoryCacheSize=16M        # 默认 16M

# 历史索引缓存
HistoryIndexCacheSize=4M    # 默认 4M

# 趋势数据缓存
TrendCacheSize=4M           # 默认 4M

# 触发器计算用值缓存
ValueCacheSize=8M           # 默认 8M，触发器多时增加
```

### 7.3 规模参考值

| 环境规模 | 主机数 | 推荐实例 | CacheSize | StartPollers |
|----------|--------|----------|-----------|--------------|
| 小型（Lab） | 1-10 | t3.small | 32M（默认） | 5（默认） |
| 中型 | 10-100 | t3.medium | 64M | 10-20 |
| 大型 | 100-500 | t3.large | 128M | 30-50 |
| 企业级 | 500+ | 专用服务器 | 256M+ | 100+ |

### 7.4 调优后验证

```bash
# 修改后重启服务
systemctl restart zabbix-server

# 检查日志确认无错误
tail -50 /var/log/zabbix/zabbix_server.log

# 检查 Queue 是否正常
# Web UI: Monitoring → Queue
```

> 💡 **最佳实践**：先监控 Queue，只在出现问题时才调优。过度配置会浪费内存。

---

## 面试问答

### Q: LLD の仕組みは？

**A**:
- **Discovery rule**: 定期的にリソース（ファイルシステム、ネットワーク IF など）を検出
- **Item prototype**: 発見したリソースごとに Item を自動生成（例：各 FS の使用率）
- **Trigger prototype**: 発見したリソースごとに Trigger を自動生成
- **LLD マクロ**: `{#FSNAME}` などで発見したリソース名を参照
- **フィルター**: tmpfs など監視不要なリソースを除外

### Q: Proxy を使う場面は？

**A**:
- **多拠点監視**: 各拠点に Proxy を配置、WAN 越しの負荷を軽減
- **DMZ 内サーバー**: Proxy のみ内部ネットワークと通信
- **ネットワーク分離**: セキュリティ要件でサーバーと直接通信できない場合
- **スケーラビリティ**: 大規模環境で Server の負荷分散

---

## 常见错误

| 错误 | 原因 | 解决方案 |
|------|------|----------|
| LLD Item 未生成 | Discovery 未执行 | 检查 Discovery rule 间隔 |
| Dashboard 无数据 | Widget 配置错误 | 检查 Host/Graph 选择 |
| Slack 403 | Webhook URL 无效 | 重新创建 Webhook |
| 报告生成失败 | API Token 问题 | 确认 Token 权限 |

---

## 系列总结

恭喜完成 Zabbix 监控入门系列！你已经掌握了：

| 技能 | 对应课程 |
|------|----------|
| Zabbix 架构理解 | 00 |
| Server 安装配置 | 01 |
| Agent 部署管理 | 02 |
| 模板和死活监控 | 03 |
| 触发器和告警 | 04 |
| 日志和自定义监控 | 05 |
| LLD 和 Proxy 概念 | 06 |
| Dashboard 和报告 | 06 |
| 性能调优 | 06 |
| 監視設計書编写 | 06 |

### 日本 IT 职场应用

| 场景 | 技能 |
|------|------|
| 運用監視 | 全系列 |
| 障害対応 | 03, 04 |
| ログ監視 | 05 |
| 監視設計書 | 06 |
| 面接対策 | 各课 Q&A |

---

## 清理资源

### 清理本地资源

```bash
# 删除本课创建的脚本和文件
rm -f ~/generate_report.sh
rm -rf /var/reports/zabbix

# 如果配置了自定义 LLD
sudo rm -f /etc/zabbix/zabbix_agent2.d/discovery_apps.conf
```

### 清理 Slack 配置（如配置了）

1. 访问 https://api.slack.com/apps
2. 找到创建的 Zabbix App
3. 点击「Delete App」

### 删除 AWS 资源

完成学习后，删除 CloudFormation 堆栈：

```bash
aws cloudformation delete-stack --stack-name zabbix-lab

# 确认删除完成
aws cloudformation describe-stacks --stack-name zabbix-lab
# 应返回 "Stack not found" 错误
```

> ⚠️ **费用提醒**：不删除堆栈将持续产生费用（约 $0.03/小时 ≈ $22/月）。

---

## 下一步学习建议

| 方向 | 推荐课程 |
|------|----------|
| 日志分析深入 | [日志分析与故障排查](../../../skills/log-reading/) |
| 日本 IT 文化 | [日本 IT 职场沟通](../../../skills/jp-communication/) |
| 高级 Zabbix | Zabbix 官方文档、HA 配置 |

---

## 系列导航

← [05 · 日志 + 自定义指标](../05-logs-custom/) | [系列首页](../)

---

*感谢学习本系列！祝你在日本 IT 职场取得成功！*
