# Zabbix Log Monitoring - Industry Context

> **Optional Reading**: This document provides deeper context on log monitoring practices in production environments and Japanese IT workplaces.

---

## 1. Why Zabbix Needs Text Log Files

### The Technical Reality

Zabbix's log monitoring feature (`log[]`, `logrt[]`, `log.count[]`) can **only read text-based log files**.
As of Zabbix 7.0 LTS, there is **no native systemd-journald support**.

| Approach | Status | Production Use |
|----------|--------|----------------|
| Native journald | Not available (ZBXNEXT-7907 open since 2022) | - |
| Community plugin | "Very experimental" | Not recommended |
| **rsyslog + log[] items** | Production-ready | **Recommended** |

### The rsyslog Bridge Pattern

This is the standard pattern used in enterprise environments:

```
┌─────────────────────────────────────────────────────────────────────┐
│                     Enterprise Log Flow                              │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  Application/System                                                  │
│       │                                                              │
│       ▼                                                              │
│  systemd-journald (binary)                                          │
│       │                                                              │
│       ▼ (imjournal module)                                          │
│  rsyslog                                                             │
│       │                                                              │
│       ├──────────────────┬──────────────────┐                       │
│       ▼                  ▼                  ▼                       │
│  /var/log/messages  /var/log/secure   Central Log Server            │
│       │                  │              (ELK/Splunk/CloudWatch)     │
│       ▼                  ▼                                          │
│  Zabbix log[] items → Triggers → Alerts                             │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

---

## 2. Common Log Monitoring Targets

### Priority by Use Case

| Log File | Distribution | Content | Monitoring Priority |
|----------|--------------|---------|---------------------|
| `/var/log/messages` | RHEL/Amazon | System events, service failures | **High** |
| `/var/log/syslog` | Debian/Ubuntu | System events | **High** |
| `/var/log/secure` | RHEL/Amazon | Authentication, sudo, SSH | **Critical** |
| `/var/log/auth.log` | Debian/Ubuntu | Authentication | **Critical** |
| `/var/log/cron` | All | Scheduled job execution | **High** |
| Application logs | Varies | Service-specific errors | **High** |

### Why `/var/log/secure` is Critical

Security logs are mandatory for compliance:

- **ISMS (ISO 27001)**: Track "who accessed what and when"
- **PrivacyMark (JIS Q 15001)**: Personal data access audit
- **PCI-DSS**: Payment card industry requirements
- **SOX**: Financial system audit trails

---

## 3. Japanese IT Workplace Context

### Key Terminology (日本語用語)

| Japanese | Reading | English | Usage |
|----------|---------|---------|-------|
| ログ監視 | rogu kanshi | Log monitoring | General term |
| 運用監視 | un'you kanshi | Operations monitoring | Broader scope (includes metrics) |
| 障害検知 | shougai kenchi | Incident detection | Error/failure detection |
| 死活監視 | shikatsu kanshi | Alive monitoring | Ping/heartbeat checks |
| 手順書 | tejunsho | Procedure manual | Runbook for operations |
| 一次対応 | ichiji taiou | First-line response | Initial incident handling |
| 障害報告書 | shougai houkokusho | Incident report | Post-incident documentation |

### NOC Workflow in Japanese Companies

```
障害検知 (Detection)
    │
    ▼
一次対応 (First Response) ─── 手順書に従う (Follow Runbook)
    │
    ▼
エスカレーション (Escalation) ─── If runbook doesn't cover it
    │
    ▼
復旧 + 報告 (Resolution + Reporting)
    │
    ▼
再発防止策 (Recurrence Prevention)
```

### Tool Landscape in Japan

| Tool | Traditional Enterprise | Web-kei/Startup | Notes |
|------|------------------------|-----------------|-------|
| **JP1 (Hitachi)** | ~90% (banking, gov) | <1% | De-facto standard in SIer |
| **Zabbix** | ~10% | ~40% | Strong Japanese community |
| **Hinemos (NTT Data)** | ~3% | <1% | Japanese OSS, public sector |
| **Prometheus + Grafana** | ~5% | ~30% | Cloud-native preference |
| **Datadog** | ~5% | ~35% | Modern observability |

### SIer vs Web-kei Culture Differences

| Aspect | SIer / Traditional | Web-kei / Startup |
|--------|-------------------|-------------------|
| Philosophy | "Miss nothing" (完全監視) | "Alert on actionable" |
| Response | Follow strict 手順書 | DevOps fixes directly |
| Key Metric | Root cause analysis | MTTR (Mean Time To Recovery) |
| Log Format | Strict, pre-defined | JSON, structured |

---

## 4. Zabbix Log Monitoring Best Practices

### Item Configuration

```
Key: log[/var/log/secure,"authentication failure",,100,skip]
     │                    │                       │   │   │
     │                    │                       │   │   └── Mode: skip historical
     │                    │                       │   └────── Max lines per check
     │                    │                       └────────── Output format (empty=default)
     │                    └────────────────────────────────── Regex pattern
     └─────────────────────────────────────────────────────── File path
```

### Critical Settings

| Setting | Recommended | Reason |
|---------|-------------|--------|
| **Type** | Zabbix agent (active) | Log items ONLY work with Active checks |
| **Update interval** | 1s | Longer intervals cause batching issues |
| **Mode** | skip | Avoid processing historical entries on first run |
| **Permissions** | zabbix user in adm group | Read access to log files |

### Common Anti-Patterns

1. **Using Passive checks** - Log items require Active mode
2. **Forgetting mode: skip** - Triggers false alerts from old entries
3. **Wrong update interval** - 5-minute intervals cause load spikes
4. **Ignoring permissions** - "Item not supported" errors

---

## 5. Real-World Scenarios for Japan IT

### Scenario 1: SSH Brute Force Detection (ISMS Compliance)

```yaml
Item:
  Key: log[/var/log/secure,"Failed password",,100,skip]
  Type: Zabbix agent (active)

Trigger:
  Expression: count(/host/log[...],5m)>5
  Severity: High

# Japanese context: ISMS requires detecting unauthorized access attempts
# This is a standard 運用監視 requirement
```

### Scenario 2: Nightly Batch Job Monitoring

```yaml
Item:
  Key: log[/var/log/cron,"error|failed",,100,skip]
  Type: Zabbix agent (active)

Trigger:
  Expression: find(/host/log[...],,"regexp","error|failed")=1
  Severity: Average

# Japanese context: Batch processing is critical in traditional IT
# Many systems run 夜間バッチ (nightly batch) jobs
```

### Scenario 3: Web Server Error Detection

```yaml
Item:
  Key: logrt[/var/log/httpd/error_log.*,"error|crit|alert",,100,skip]
  Type: Zabbix agent (active)

# Note: logrt[] for rotating logs (Apache uses date-based rotation)
```

---

## 6. Distribution-Specific Notes

### Amazon Linux 2023

- **Default**: systemd-journald only, no rsyslog
- **Action**: Install rsyslog to create /var/log/messages, /var/log/secure
- **Reference**: [AWS Docs - journald](https://docs.aws.amazon.com/linux/al2023/ug/journald.html)

### RHEL 8/9

- **Default**: Both journald and rsyslog installed
- **Note**: rsyslog reads from journald via imjournal

### Ubuntu 22.04+

- **Default**: journald + rsyslog
- **Log paths**: /var/log/syslog, /var/log/auth.log

---

## References

### Official Documentation
- [Zabbix Log File Monitoring](https://www.zabbix.com/documentation/current/en/manual/config/items/itemtypes/log_items)
- [Zabbix Feature Request ZBXNEXT-7907](https://support.zabbix.com/browse/ZBXNEXT-7907)
- [AWS AL2023 journald](https://docs.aws.amazon.com/linux/al2023/ug/journald.html)
- [rsyslog imjournal](https://www.rsyslog.com/doc/configuration/modules/imjournal.html)

### Japanese Resources
- [Qiita: Zabbix ログ監視設定](https://qiita.com/search?q=zabbix+log)
- [総務省: 監査ログ管理](https://www.soumu.go.jp/main_sosiki/cybersecurity/kokumin/security/business/admin/12/)

---

*This document supplements Lesson 05 of the Zabbix course.*
