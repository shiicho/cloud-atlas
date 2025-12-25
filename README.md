# cloud-atlas｜云上地图

A mapped guide to **Cloud & DevOps** — reproducible labs by **shiicho**.
面向中文读者的 DevOps 实战教程，每个课堂都提供「可复现」的代码与步骤。

## 仓库定位 / What this repo is

面向 **DevOps 工程师** 的技能培养路径：
- 以 **小而快的课程**（bite-size lessons）讲解云/基础设施/自动化知识
- 覆盖 DevOps 核心技能：IaC、监控、自动化、CI/CD
- 代码先行：clone 即用，边做边学

## DevOps 技能树 / Skill Tree

```
DevOps Engineer
├── Infrastructure as Code
│   ├── Terraform (17课)
│   └── CloudFormation (7课)
├── Cloud Platform
│   └── AWS SSM (7课)
├── Automation
│   └── Ansible (12课)
├── Monitoring
│   └── Zabbix (7课)
├── Middleware
│   └── HULFT (7课)
├── Foundation
│   ├── Linux/Bash (7课)
│   └── Log Reading (7课)
└── Soft Skills
    └── JP Communication (7课)
```

## 目录结构｜Repository Structure

```
cloud-atlas/
├── iac/                    # Infrastructure as Code
│   ├── terraform/          # Terraform (17课)
│   └── cloudformation/     # CloudFormation (7课)
├── aws/
│   └── ssm/                # Systems Manager (7课)
├── linux/
│   └── bash/               # Bash 脚本 (7课)
├── middleware/
│   ├── ansible/            # Ansible 自动化
│   ├── zabbix/             # Zabbix 监控
│   └── hulft/              # HULFT 文件传输
├── skills/
│   ├── log-reading/        # 日志分析
│   └── jp-communication/   # 日本职场沟通
├── glossary/               # 术语词典
├── solutions/              # 解决方案集
└── README.md
```

## 课程目录 / Course Index

### Infrastructure as Code

- **[Terraform 基础设施即代码：从入门到生产实战](./iac/terraform/)**
  - [00 · 概念导入与 Terraform 生态](./iac/terraform/00-concepts/)
  - [01 · 安装配置与第一个资源](./iac/terraform/01-first-resource/)
  - [02 · 状态管理与远程后端](./iac/terraform/02-state/)
  - [03 · HCL 语法与资源建模](./iac/terraform/03-hcl/)
  - [04 · Provider 策略与版本管理](./iac/terraform/04-providers/)
  - [05 · 变量系统](./iac/terraform/05-variables/)
  - [06 · 循环条件与表达式](./iac/terraform/06-loops/)
  - [07 · 模块化设计](./iac/terraform/07-modules/)
  - [08 · 项目布局与多环境策略](./iac/terraform/08-layout/)
  - [09 · 既存インフラ導入（Import）](./iac/terraform/09-import/)
  - [10 · 漂移検知与状態操作](./iac/terraform/10-drift/)
  - [11 · CI/CD 集成](./iac/terraform/11-cicd/)
  - [12 · 安全与机密管理](./iac/terraform/12-security/)
  - [13 · 测试与质量保证](./iac/terraform/13-testing/)
  - [14 · 实战项目：三层 Web 架构](./iac/terraform/14-capstone/)
  - [15 · 日本 IT：変更管理と承認フロー](./iac/terraform/15-jp-change-mgmt/)
  - [16 · 日本 IT：監査対応とドキュメント](./iac/terraform/16-jp-audit/)

- **[CloudFormation AWS 原生基础设施即代码](./iac/cloudformation/)**
  - [00 · CloudFormation 基础与第一个 Stack](./iac/cloudformation/00-fundamentals/)
  - [01 · 模板语法与内置函数](./iac/cloudformation/01-template-syntax/)
  - [02 · 安全运维：ChangeSets 与回滚策略](./iac/cloudformation/02-safe-operations/)
  - [03 · 现代工具：Infrastructure Composer 与 IaC Generator](./iac/cloudformation/03-modern-tools/)
  - [04 · 多栈架构与跨栈引用](./iac/cloudformation/04-multi-stack/)
  - [05 · Drift 检测与资源导入](./iac/cloudformation/05-drift-import/)
  - [06 · 企业实战与日本 IT 运维](./iac/cloudformation/06-enterprise-japan/)

### Cloud Platform

- **[AWS Systems Manager 入门（GUI 版）](./aws/ssm/)**
  - [01 · CloudFormation 部署最小 SSM 实验环境](./aws/ssm/01-cfn-deploy/)
  - [02 · Session Manager 免密登录 EC2](./aws/ssm/02-session-manager/)
  - [03 · Run Command 批量执行脚本](./aws/ssm/03-run-command/)
  - [04 · Parameter Store 参数存储](./aws/ssm/04-parameter-store/)
  - [05 · 会话日志落地（CloudWatch）](./aws/ssm/05-session-logging/)
  - [06 · State Manager 状态管理器](./aws/ssm/06-state-manager/)
  - [07 · Hybrid 托管 On-Prem](./aws/ssm/07-hybrid/) *(planned)*

### Foundation

- **[Bash 脚本入门系列](./linux/bash/)**
  - [00 · 环境准备](./linux/bash/00-setup/)
  - [01 · 第一个脚本](./linux/bash/01-first-script/)
  - [02 · 文件系统操作](./linux/bash/02-filesystem/)
  - [03 · 管道与重定向](./linux/bash/03-pipes/)
  - [04 · 循环与条件](./linux/bash/04-loops/)
  - [05 · 函数与模块化](./linux/bash/05-functions/)
  - [06 · 自动化运维脚本](./linux/bash/06-automation/)

### Automation

- **[Ansible 自动化入门](./middleware/ansible/)**
  - [00 · 核心概念](./middleware/ansible/00-concepts/)
  - [01 · 安装配置](./middleware/ansible/01-installation/)
  - [02 · Inventory 管理](./middleware/ansible/02-inventory/)
  - [03 · Ad-hoc 命令与模块](./middleware/ansible/03-adhoc-modules/)
  - [04 · Playbook 基础](./middleware/ansible/04-playbook-basics/)
  - [05 · 变量与逻辑控制](./middleware/ansible/05-variables-logic/)
  - [06 · Roles 与 Galaxy](./middleware/ansible/06-roles-galaxy/)
  - [07 · Jinja2 模板](./middleware/ansible/07-jinja2-templates/)
  - [08 · 错误处理](./middleware/ansible/08-error-handling/)
  - [09 · Vault 密钥管理](./middleware/ansible/09-vault-secrets/)
  - [10 · AWX/Ansible Tower 入门](./middleware/ansible/10-awx-tower/)
  - [11 · Zabbix 连携与 EDA 集成](./middleware/ansible/11-zabbix-eda/)

### Monitoring

- **[Zabbix 监控入门](./middleware/zabbix/)**
  - [00 · 架构与环境部署](./middleware/zabbix/00-architecture-lab/)
  - [01 · Server 初始化](./middleware/zabbix/01-server-setup/)
  - [02 · Agent 与主机管理](./middleware/zabbix/02-agent-host/)
  - [03 · 基础监控](./middleware/zabbix/03-monitoring-basics/)
  - [04 · 触发器与告警](./middleware/zabbix/04-triggers-alerts/)
  - [05 · 日志与自定义指标](./middleware/zabbix/05-logs-custom/)
  - [06 · 运维进阶](./middleware/zabbix/06-ops-advanced/)

### Middleware

- **[HULFT 文件传输](./middleware/hulft/)**
  - [00 · 概念与架构](./middleware/hulft/00-concepts/)
  - [01 · 网络与安全基础](./middleware/hulft/01-network-security/)
  - [02 · 安装配置](./middleware/hulft/02-installation/)
  - [03 · 字符编码处理](./middleware/hulft/03-encoding/)
  - [04 · 集信/配信实战](./middleware/hulft/04-operations/)
  - [05 · 作业连携与错误处理](./middleware/hulft/05-job-integration/)
  - [06 · 云迁移](./middleware/hulft/06-cloud-migration/)

### Skills

- **[日志分析与故障排查](./skills/log-reading/)**
  - [00 · Linux 日志基础](./skills/log-reading/00-linux-logs/)
  - [01 · 工具与模式](./skills/log-reading/01-tools-patterns/)
  - [02 · Systemd 日志](./skills/log-reading/02-systemd-logs/)
  - [03 · Web 服务器日志](./skills/log-reading/03-web-server-logs/)
  - [04 · AWS 日志](./skills/log-reading/04-aws-logs/)
  - [05 · 时间线与报告](./skills/log-reading/05-timeline-report/)
  - [06 · RCA 实战](./skills/log-reading/06-rca-practice/)

- **[日本职场沟通](./skills/jp-communication/)**
  - [00 · ホウレンソウ（报连相）](./skills/jp-communication/00-horenso/)
  - [01 · 敬语基础](./skills/jp-communication/01-keigo-basics/)
  - [02 · 根回し实战](./skills/jp-communication/02-nemawashi/)
  - [03 · 障害报告](./skills/jp-communication/03-incident-reporting/)
  - [04 · 会议文化](./skills/jp-communication/04-meeting-culture/)
  - [05 · 异步沟通](./skills/jp-communication/05-async-communication/)
  - [06 · 空気を読む](./skills/jp-communication/06-kuuki-wo-yomu/)

### Glossary

- **[术语词典](./glossary/)**
  - [Linux 概念](./glossary/linux/) - MOTD, Heredoc
  - [AWS 概念](./glossary/aws/) - SSM Session
  - [网络概念](./glossary/networking/) - NAT, Polling vs Pushing
  - [DevOps 概念](./glossary/devops/) - Idempotency, Agent vs Agentless
  - [安全概念](./glossary/security/) - MITM, OIDC

## 前置条件 / Prerequisites

- 可用的 **AWS 账号**（建议区域 `ap-northeast-1` 东京）
- 学习环境可使用 **AdministratorAccess**（正式环境请最小权限）
- 若仅按 GUI 操作，可暂不安装 CLI

## 镜像仓库 / Mirrors

- GitHub：**[shiicho/cloud-atlas](https://github.com/shiicho/cloud-atlas)**
- 中国大陆镜像：**[shiicho/cloud-atlas（Gitee）](https://gitee.com/shiicho/cloud-atlas)**

> 如果你也在大陆网络环境，建议同时拉取镜像仓库以获得更稳定的访问。

## 许可证 / License

**[MIT License](./LICENSE)** © 2025 shiicho
