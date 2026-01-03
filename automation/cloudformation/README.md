# CloudFormation AWS 原生基础设施即代码

> **AWS-native Infrastructure as Code**  
> 从零开始系统学习 CloudFormation，覆盖从基础语法到企业级运维实践

---

## 课程特色

- **GUI 优先**: Console + Infrastructure Composer 可视化设计
- **真实 AWS**: 使用真实资源，培养生产思维
- **安全第一**: 强调 ChangeSets 预览、DeletionPolicy、StackPolicy
- **2024-2025 新功能**: IaC Generator、Stack Refactoring、Timeline View
- **日本 IT 场景**: 手順書、設計書、変更管理票 模板
- **面试准备**: 每课附带日语面试题

---

## 适合人群

- AWS 运维工程师
- SIer 项目成员（参与日本企业 AWS 项目）
- 云基础设施工程师
- 日本 IT 就职者
- AWS 认证备考者（SAA/SOA/SAP）

---

## CloudFormation vs Terraform

| 特性 | CloudFormation | Terraform |
|------|---------------|-----------|
| **状态管理** | AWS 自动管理（无需操心） | 需手动管理 State 文件 |
| **回滚** | 失败自动回滚 | 需手动清理 |
| **新功能支持** | AWS 新服务即日支持 | 依赖 Provider 更新 |
| **多云** | 仅 AWS | 支持多云 |
| **学习曲线** | YAML/JSON，AWS 特定语法 | HCL，更好的循环/条件 |
| **费用** | 免费（AWS 服务） | 企业版收费 |

**适用场景:**
- AWS-only 环境 → CloudFormation
- 多云/混合云 → Terraform
- 日本 SIer/金融/政府 → CloudFormation 优先

---

## 课程大纲

| 课程 | 主题 | 关键技能 |
|------|------|----------|
| [00 - 基础与第一个 Stack](./00-fundamentals/) | IaC 概念、CFN vs TF、Console 创建 Stack | 基础概念 |
| [01 - 模板语法与内置函数](./01-template-syntax/) | Parameters、Mappings、Conditions、!Ref/!GetAtt/!Sub | 模板编写 |
| [02 - 安全运维](./02-safe-operations/) | ChangeSets、StackPolicy、DeletionPolicy、回滚 | 生产安全 |
| [03 - 现代工具](./03-modern-tools/) | Infrastructure Composer、IaC Generator、Timeline View | 2024 功能 |
| [04 - 多栈架构](./04-multi-stack/) | Nested Stacks、Cross-Stack References、Exports | 模块化 |
| [05 - Drift 与导入](./05-drift-import/) | Drift 检测/修复、Resource Import、Stack Refactoring | 运维技能 |
| [06 - 企业实战](./06-enterprise-japan/) | StackSets、cfn-guard、変更管理、監査対応 | Japan IT |

---

## 快速开始

### 前置条件

- AWS 账户（Free Tier 可用）
- AWS Console 基本操作能力
- 推荐: 完成 AWS SSM 入门课程

### 克隆代码

```bash
# Sparse checkout（仅下载 CloudFormation 课程）
git clone --filter=blob:none --sparse https://github.com/shiicho/cloud-atlas ~/cloud-atlas
cd ~/cloud-atlas && git sparse-checkout set automation/cloudformation
```

### 费用提示

大部分实验使用 Free Tier 资源。完成后请立即删除 Stack，避免产生费用。

---

## 日本 IT 术语

| 日语 | 中文 | 英文 | CFN 上下文 |
|------|------|------|-----------|
| 変更管理 | 变更管理 | Change Management | ChangeSet 承認フロー |
| 監査対応 | 审计合规 | Audit Compliance | CloudTrail + Config |
| 運用監視 | 运维监控 | Operations Monitoring | CloudWatch Alarms |
| 障害対応 | 故障处理 | Incident Response | Rollback triggers |
| 設計書 | 设计文档 | Design Document | CFn template |
| 手順書 | 操作手册 | Procedure Manual | Stack 操作手順 |

---

## 延伸阅读

- [AWS CloudFormation 官方文档](https://docs.aws.amazon.com/cloudformation/)
- [CloudFormation Best Practices](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/best-practices.html)
- [AWS CloudFormation 2024 Year in Review](https://aws.amazon.com/blogs/devops/aws-cloudformation-2024-year-in-review/)

---

## 系列导航

[AWS SSM 入门](../../cloud/aws-ssm/) | [Terraform 入门](../terraform/) | **CloudFormation（本课程）**
