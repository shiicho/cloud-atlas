# 00 · 概念与架构导入（Ansible Architecture & Agentless Philosophy）

> **目标**：理解 Ansible 核心架构和 Agentless 设计哲学  
> **前置**：无（入门课程）  
> **时间**：30 分钟  
> **实战项目**：调研一家日本 SIer 的 Ansible 导入案例

---

## 将学到的内容

1. 理解 Agentless 架构的优势
2. 区分 Control Node 与 Managed Nodes
3. 对比 Ansible vs Puppet/Chef vs Terraform
4. 了解 Ansible 生态系统（Core, Collections, Galaxy, AAP）

---

## Step 1 — 什么是 Ansible？

Ansible 是一个开源的 **IT 自动化工具**，用于：

- **Configuration Management** - 配置管理
- **Application Deployment** - 应用部署
- **Orchestration** - 编排多系统任务
- **Provisioning** - 基础设施配置

### 核心特点

| 特点 | 说明 |
|------|------|
| **[Agentless](../../../glossary/devops/agent-agentless.md)** | 无需在目标机器安装代理 |
| **SSH-based** | 通过 SSH 连接目标机器 |
| **YAML** | 使用 YAML 编写 Playbook |
| **Idempotent** | 多次执行结果一致（[幂等性](../../../glossary/devops/idempotency.md)） |
| **Push Model** | 从控制节点推送配置 |

---

## Step 2 — Ansible 架构

```
┌─────────────────────────────────────────────────────────────┐
│                        CONTROL NODE                          │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐  │
│  │  Inventory  │  │  Playbooks  │  │  ansible.cfg        │  │
│  │  (主机列表)  │  │  (任务定义)  │  │  (配置文件)          │  │
│  └─────────────┘  └─────────────┘  └─────────────────────┘  │
│                           │                                   │
│                    Ansible Engine                             │
│                           │                                   │
└───────────────────────────┼───────────────────────────────────┘
                            │
                     SSH (Port 22)
                            │
         ┌──────────────────┼──────────────────┐
         │                  │                  │
         ▼                  ▼                  ▼
┌─────────────────┐ ┌─────────────────┐ ┌─────────────────┐
│  MANAGED NODE   │ │  MANAGED NODE   │ │  MANAGED NODE   │
│  (Web Server)   │ │  (DB Server)    │ │  (App Server)   │
│                 │ │                 │ │                 │
│  Requirements:  │ │  Requirements:  │ │  Requirements:  │
│  - Python 3     │ │  - Python 3     │ │  - Python 3     │
│  - SSH Server   │ │  - SSH Server   │ │  - SSH Server   │
└─────────────────┘ └─────────────────┘ └─────────────────┘
```

### 组件说明

| 组件 | 英文 | 说明 |
|------|------|------|
| **控制节点** | Control Node | 运行 Ansible 的机器，执行 playbook |
| **被管节点** | Managed Node | 被 Ansible 管理的目标机器 |
| **Inventory** | Inventory | 定义被管节点的清单文件 |
| **Module** | Module | 执行具体任务的代码单元（最小执行单位） |
| **Task** | Task | 调用一个 Module 的单个操作步骤 |
| **Playbook** | Playbook | 包含多个 Task 的 YAML 任务定义文件 |

---

## Step 3 — Agentless vs Agent-based

### 对比表

| 特性 | Ansible (Agentless) | Puppet/Chef (Agent-based) |
|------|---------------------|---------------------------|
| **代理安装** | 不需要 | 需要在每台机器安装 |
| **通信方式** | SSH (Push) | Agent 定期拉取 (Pull) |
| **资源占用** | 只在执行时使用 | Agent 常驻内存 |
| **安全性** | SSH 密钥管理 | Agent 证书管理 |
| **学习曲线** | 低 (YAML) | 高 (DSL) |
| **实时性** | 按需执行 | 定期同步 |

### 为什么选择 Agentless？

```
┌─────────────────────────────────────────────────────────────┐
│                     Agent-based (Puppet)                     │
│                                                              │
│   Server ◄──────── Agent ──────► Agent ──────► Agent        │
│     │                │             │             │          │
│     │           (常驻进程)     (常驻进程)    (常驻进程)        │
│     │                │             │             │          │
│     └── 证书管理 ────┴─────────────┴─────────────┘          │
│                                                              │
│   问题: 需要维护 Agent、证书过期、资源占用                      │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│                     Agentless (Ansible)                      │
│                                                              │
│   Control ──SSH──► Node ──SSH──► Node ──SSH──► Node         │
│     │                                                        │
│     │           (按需连接，执行完断开)                          │
│     │                                                        │
│     └── SSH 密钥管理（已有基础设施）                           │
│                                                              │
│   优势: 无额外维护、利用现有 SSH、执行完释放资源                  │
└─────────────────────────────────────────────────────────────┘
```

> **日本 IT 现场**：很多企业有严格的安全策略，禁止在服务器上安装额外软件。Agentless 的 Ansible 因此更容易获得审批。

---

## Step 4 — Ansible vs Terraform vs CloudFormation

这是面试常见问题：三者有什么区别？

| 维度 | Ansible | Terraform | CloudFormation |
|------|---------|-----------|----------------|
| **主要用途** | Configuration Management | Infrastructure Provisioning | Infrastructure Provisioning |
| **关注点** | 服务器内部配置 | 多云资源创建/销毁 | AWS 资源创建/销毁 |
| **语言** | YAML (Playbook) | HCL | YAML / JSON |
| **状态管理** | 无状态 | 有状态 (terraform.tfstate) | 有状态 (Stack) |
| **幂等性** | 通过模块实现 | 原生支持 | 原生支持 |
| **云平台** | 任意（通过模块） | 多云支持 | 仅 AWS |
| **典型任务** | 安装软件、配置服务 | 创建 VPC、EC2、RDS | 创建 VPC、EC2、RDS |

### 定位区别

```
┌─────────────────────────────────────────────────────────────────────┐
│                         工具定位对比                                  │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│   CloudFormation / Terraform          Ansible                       │
│   ┌──────────────────────┐           ┌──────────────────────┐       │
│   │  Infrastructure as   │           │  Configuration       │       │
│   │  Code (IaC)          │    ───►   │  Management          │       │
│   │                      │           │                      │       │
│   │  • 创建 EC2 实例      │           │  • 安装软件包         │       │
│   │  • 创建 VPC 网络      │           │  • 配置系统服务       │       │
│   │  • 创建 RDS 数据库    │           │  • 部署应用程序       │       │
│   │                      │           │                      │       │
│   │  "创建什么资源"       │           │  "如何配置资源"       │       │
│   └──────────────────────┘           └──────────────────────┘       │
│                                                                      │
├─────────────────────────────────────────────────────────────────────┤
│   CloudFormation vs Terraform                                        │
│   ┌─────────────────────┐           ┌─────────────────────┐         │
│   │   CloudFormation    │           │     Terraform       │         │
│   │                     │           │                     │         │
│   │  • AWS 原生          │           │  • 多云支持          │         │
│   │  • 无需安装          │           │  • 需要安装 CLI      │         │
│   │  • 状态由 AWS 管理    │           │  • 状态需自行管理    │         │
│   │  • 与 AWS 服务深度集成│           │  • 社区模块丰富      │         │
│   └─────────────────────┘           └─────────────────────┘         │
└─────────────────────────────────────────────────────────────────────┘
```

### 本课程的选择

本课程使用 **CloudFormation** 创建实验环境（EC2、VPC、Route 53），然后用 **Ansible** 配置服务器。

```bash
# Step 1: CloudFormation 创建基础设施
aws cloudformation create-stack --stack-name ansible-lab ...

# Step 2: Ansible 配置服务器
ansible-playbook -i inventory/hosts.ini site.yaml
```

> 💡 **面试要点**
>
> **問題**：Ansible と Terraform/CloudFormation の違いは何ですか？
>
> **期望回答**：
> - Terraform/CloudFormation は Infrastructure as Code、クラウドリソースの作成・管理
> - Ansible は Configuration Management、サーバー内部の設定・アプリデプロイ
> - 両者は補完関係、IaC でインフラ作成 → Ansible で設定という流れが一般的
> - CloudFormation は AWS 専用、Terraform はマルチクラウド対応

---

## Step 5 — Ansible 生态系统

```
┌─────────────────────────────────────────────────────────────┐
│                    Ansible Ecosystem                         │
│                                                              │
│   ┌──────────────────────────────────────────────────────┐  │
│   │                  Ansible Core                         │  │
│   │  - 核心引擎                                            │  │
│   │  - 基础模块 (ansible.builtin)                          │  │
│   │  - 命令行工具 (ansible, ansible-playbook)              │  │
│   └──────────────────────────────────────────────────────┘  │
│                           │                                   │
│   ┌───────────────────────┼───────────────────────────────┐  │
│   │                       ▼                               │  │
│   │              Ansible Collections                      │  │
│   │  ┌─────────────┐ ┌─────────────┐ ┌─────────────────┐ │  │
│   │  │ amazon.aws  │ │ community.  │ │ cisco.ios       │ │  │
│   │  │             │ │ general     │ │                 │ │  │
│   │  │ AWS 模块    │ │ 通用模块    │ │ 网络设备模块    │ │  │
│   │  └─────────────┘ └─────────────┘ └─────────────────┘ │  │
│   └───────────────────────────────────────────────────────┘  │
│                           │                                   │
│   ┌───────────────────────┼───────────────────────────────┐  │
│   │                       ▼                               │  │
│   │                 Ansible Galaxy                        │  │
│   │  - 社区共享 Roles 和 Collections                       │  │
│   │  - galaxy.ansible.com                                 │  │
│   └───────────────────────────────────────────────────────┘  │
│                           │                                   │
│   ┌───────────────────────┼───────────────────────────────┐  │
│   │                       ▼                               │  │
│   │         Ansible Automation Platform (AAP)             │  │
│   │  - Red Hat 商用版本                                    │  │
│   │  - AWX (开源上游)                                      │  │
│   │  - Web UI, RBAC, 调度, API                            │  │
│   └───────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

### 版本说明

| 组件 | 说明 | 适用场景 |
|------|------|----------|
| **Ansible Core** | 最小安装，仅核心功能 | 开发/测试 |
| **Ansible** | Core + 常用 Collections | 生产使用 |
| **AWX** | 开源 Web UI | 团队协作 |
| **AAP** | Red Hat 商用版 | 企业生产 |

---

## Step 6 — 日本市场 Ansible 现状

### 日本 SIer 导入案例

| 企業 | Ansible 活用 |
|------|--------------|
| SCSK | Red Hat Ansible Automation Platform 導入支援 |
| 兼松エレクトロニクス | システム運用自動化ソリューション |
| 日立ソリューションズ | Automation 2.0 推進 |
| ライトウェル | Ansible 導入支援サービス |

### RHCE との関係

- **RHCE (EX294)**: Red Hat Certified Engineer
- 試験内容: Ansible Playbook の作成・管理
- 日本語試験あり
- 本コースは EX294 の主要トピックをカバー

---

## 日本企業現場ノート

> 💼 **Ansible 導入時の現場感**

| 要点 | 説明 |
|------|------|
| **セキュリティ審査** | Agentless だから「追加ソフト不要」で審査通過しやすい |
| **SSH 管理** | 既存の SSH 鍵基盤を活用可能（新規インフラ不要） |
| **変更管理** | Playbook は Git 管理、変更履歴が残る（監査対応） |
| **承認フロー** | AWX/AAP なら実行前に承認を挟める |
| **引き継ぎ** | YAML だから引き継ぎが容易（属人化防止） |

> 📋 **面接/入場時によく聞かれる質問**：
> - 「なぜ Ansible を選んだのですか？」→ Agentless で導入障壁が低い、既存 SSH 基盤を活用
> - 「Puppet/Chef との違いは？」→ Agent 不要、YAML で学習コストが低い、Push 型で即時反映
> - 「Terraform との使い分けは？」→ Terraform はインフラ作成、Ansible は設定管理

---

## Mini-Project：SIer 調研

> **场景**：你作为新入职的基础设施工程师，需要调研公司是否应该导入 Ansible。

### 要求

1. **选择一家日本 SIer**（SCSK, KEL, 日立ソリューションズ等）
2. **调研其 Ansible 导入案例**
   - 导入背景是什么？
   - 解决了什么问题？
   - 取得了什么效果？
3. **整理成 A4 一页的报告**（日语或中文）

### 参考资料

- [Ansible Automates 2024 Japan](https://tekunabe.hatenablog.jp/entry/2024/08/09/ansible_automates_2024_japan)
- [SCSK Ansible Platform](https://www.scsk.jp/sp/jboss/products/ansible/)
- [兼松エレクトロニクス Ansible](https://www.kel.co.jp/service/dx/ansible.html)

---

## 常见问题

| 问题 | 回答 |
|------|------|
| Windows 可以作为 Control Node 吗？ | 官方不支持，推荐 WSL2 或 Linux VM |
| Managed Node 需要安装什么？ | Python 3 + SSH Server |
| Ansible 收费吗？ | Ansible Core 免费开源，AAP 需要订阅 |

---

## 本课小结

| 概念 | 要点 |
|------|------|
| Agentless | 无需安装代理，通过 SSH 通信 |
| Control Node | 运行 Ansible 的机器 |
| Managed Node | 被管理的目标机器 |
| Ansible vs Terraform | 配置管理 vs 基础设施创建 |
| AAP/AWX | 企业级 Web UI 平台 |

---

## 下一步

概念理解完成，准备动手部署 Lab 环境。

→ [01 · 环境构築与初期配置](../01-installation/)

---

## 系列导航

[Home](../) | [Next →](../01-installation/)
