# Zabbix 监控入门系列

> **目标**：从零开始掌握 Zabbix 企业级监控，培养日本 IT 业界所需的運用監視技能  
> **适合**：运维工程师、SRE、基础设施工程师  
> **前置**：[AWS SSM 01 · CloudFormation 部署](../../cloud/aws-ssm/01-cfn-deploy/)（了解堆栈部署即可）

## 系列概览

本系列采用「架构先行」设计理念——先理解概念，再动手部署。每课包含：
- 面试重点问答（日本基础设施面试常考）
- 实战 Mini-Project（贴近日本 IT 现场）
- 常见错误与排查

## 课程目录

| 课程 | 主题 | 关键技能 |
|------|------|----------|
| [00 · 环境与架构导入](./00-architecture-lab/) | 概念先行 + CloudFormation 部署 | Server/Agent/Proxy 架构、Active vs Passive |
| [01 · Server 初始化](./01-server-setup/) | Web UI + Housekeeping 设置 | 安装配置、History vs Trends |
| [02 · Agent 与主机管理](./02-agent-host/) | Active 模式 + Host Groups | Agent2 配置、主机注册、Tags |
| [03 · 基础监控 + 死活检查](./03-monitoring-basics/) | 模板 + proc/HTTP/TCP | 死活監視、服务可用性检查 |
| [04 · 触发器与告警](./04-triggers-alerts/) | Trigger + Maintenance + Email | 告警通知、维护窗口、Golden Week |
| [05 · 日志 + 自定义指标](./05-logs-custom/) | Log + UserParameter + SNMP | 日志监控、自定义指标、SNMP 入门 |
| [06 · 扩展与运维实践](./06-ops-advanced/) | LLD + Proxy + Dashboard | 低级别发现、監視設計書 |

## 实验环境

本系列使用 CloudFormation 一键部署：
- **Zabbix Server**: t3.small, Amazon Linux 2023, Zabbix 7.0 LTS
- **Monitored Host**: t3.micro, 预装 Agent2 + httpd + SNMP

```bash
# 部署（约 5 分钟）
aws cloudformation create-stack \
  --stack-name zabbix-lab \
  --template-body file://cfn/zabbix-lab.yaml \
  --capabilities CAPABILITY_NAMED_IAM

# 清理（避免扣费）
aws cloudformation delete-stack --stack-name zabbix-lab
```

## 日本 IT 职场应用场景

| 场景 | 对应课程 |
|------|----------|
| 基本監視（CPU/Mem/Disk） | 03 |
| 死活監視（服务可用性） | 03 |
| ログ監視（日志监控） | 05 |
| アラート通知（告警通知） | 04 |
| 定期メンテ（维护窗口） | 04 |
| 障害対応（故障响应） | 04, 06 |
| 監視設計書（监控设计文档） | 06 |

## 面试高频问题预览

- Active Agent と Passive Agent の違いは？
- History と Trends の違い、保存期間の設計は？
- トリガーのフラッピング（Flapping）を防ぐには？
- LLD（低レベルディスカバリ）の仕組みは？
- Zabbix Proxy を使う場面は？

## 技术栈

- **Zabbix**: 7.0 LTS
- **OS**: Amazon Linux 2023
- **Database**: MariaDB 10.5+
- **Web Server**: Apache + php-fpm
- **Agent**: Zabbix Agent 2 (Go-based)

---

开始学习 → [00 · 环境与架构导入](./00-architecture-lab/)
