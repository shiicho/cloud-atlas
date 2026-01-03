# 06 - 日本 IT 应用指南

> **目标**：将 Git 技能映射到日本 IT 企业的工作场景和面试准备  
> **前置**：已完成 [05 - Pull Request](../05-pull-requests/) 或具备 Git 协作经验  
> **时间**：45-60 分钟  
> **费用**：无（本地练习）  
> **标记**：[OPTIONAL] 非日本就职者可跳过

---

## 将学到的内容

1. 理解日本 IT 企业的 **Git 使用惯例**
2. 掌握 **Commit Message 规范**（Conventional Commits、日语、双语）
3. 理解 **Git 与変更管理** 的对应关系（PR 约等于 稟議書）
4. 建立 **IaC 仓库的标准结构**（生产级别）
5. 准备 **5 道 Git 面试题**（附日语答案）

---

## 先跑起来：5 分钟搭建标准 IaC 仓库

> 先做出来，再理解为什么。

### 创建项目结构

```bash
mkdir -p ~/my-infrastructure/{.github/workflows,modules,environments/{dev,staging,prod},docs}
cd ~/my-infrastructure
git init
```

### 添加核心配置文件

**1. 创建 .gitignore（IaC 专用）：**

```bash
cat > .gitignore << 'EOF'
# =============================================
# IaC Project .gitignore
# For Terraform / Ansible / CloudFormation
# =============================================

# ---------------------------------------------
# Terraform
# ---------------------------------------------
*.tfstate
*.tfstate.*
*.tfplan
.terraform/
.terraform.lock.hcl
crash.log
crash.*.log
override.tf
override.tf.json
*_override.tf
*_override.tf.json

# ---------------------------------------------
# Ansible
# ---------------------------------------------
*.retry

# ---------------------------------------------
# Secrets & Credentials (CRITICAL!)
# ---------------------------------------------
.env
.env.*
*.pem
*.key
credentials.json
secrets.yaml
**/secrets/
!**/secrets/.gitkeep

# ---------------------------------------------
# IDE & Editor
# ---------------------------------------------
.idea/
.vscode/
*.swp
*.swo
*~
.DS_Store

# ---------------------------------------------
# Logs
# ---------------------------------------------
*.log
logs/

# ---------------------------------------------
# Temporary
# ---------------------------------------------
tmp/
temp/
EOF
```

**2. 创建 Commit Message 模板：**

```bash
cat > .gitmessage << 'EOF'
# <type>: <subject>
#
# Types:
#   feat     - New feature
#   fix      - Bug fix
#   docs     - Documentation only
#   style    - Formatting, no code change
#   refactor - Code restructure, no behavior change
#   test     - Adding tests
#   chore    - Maintenance, dependencies
#
# Subject: imperative mood, no period, max 50 chars
#
# Example:
#   feat: add VPC module for production environment
#   fix: correct security group ingress rule
#   docs: update README with setup instructions
#
# Body (optional): explain what and why, not how
# Wrap at 72 characters
#
# Footer (optional): reference issues
#   Closes #123
#   Related to #456

EOF

# 配置 Git 使用此模板
git config commit.template .gitmessage
```

**3. 创建 PR 模板（双语）：**

```bash
mkdir -p .github
cat > .github/pull_request_template.md << 'EOF'
## Summary / 変更概要

<!-- Brief description of what this PR does -->
<!-- この PR で行う変更を簡潔に説明 -->


## Changes / 変更内容

- [ ] Change 1 / 変更点 1
- [ ] Change 2 / 変更点 2


## Impact / 影響範囲

<!-- Which environments/services are affected? -->
<!-- どの環境/サービスに影響がありますか？ -->

- [ ] dev
- [ ] staging
- [ ] prod


## Testing / テスト方法

<!-- How to test these changes -->
<!-- テスト方法を記載 -->

```bash
terraform plan
```


## Rollback Plan / 切り戻し手順

<!-- How to revert if something goes wrong -->
<!-- 問題発生時の復旧方法 -->

```bash
git revert HEAD
terraform apply
```


## Checklist / チェックリスト

- [ ] `terraform fmt` passed / フォーマット確認済み
- [ ] `terraform validate` passed / 構文検証済み
- [ ] `terraform plan` reviewed / Plan 結果確認済み
- [ ] No secrets in code / 機密情報なし
- [ ] Documentation updated / ドキュメント更新済み


## Related Issues / 関連チケット

<!-- Link to JIRA/Backlog/GitHub Issues -->
Closes #
EOF
```

**4. 创建 README：**

```bash
cat > README.md << 'EOF'
# my-infrastructure

Infrastructure as Code repository for our cloud environment.

## Structure

```
my-infrastructure/
├── .github/
│   ├── pull_request_template.md
│   └── workflows/
├── modules/           # Reusable Terraform modules
├── environments/
│   ├── dev/           # Development environment
│   ├── staging/       # Staging environment
│   └── prod/          # Production environment
└── docs/              # Documentation
```

## Branch Strategy

- `main` - Production-ready code (protected)
- `develop` - Integration branch
- `feature/*` - Feature branches
- `hotfix/*` - Emergency fixes

## Commit Convention

We follow [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/).

```
feat: add new VPC module
fix: correct security group rule
docs: update deployment guide
```

## Getting Started

1. Clone the repository
2. Navigate to the environment directory
3. Run `terraform init`
4. Run `terraform plan`

## Maintainers

- @your-team
EOF
```

### 做第一批规范提交

```bash
# 初始提交
git add .gitignore
git commit -m "chore: add IaC-specific .gitignore"

# 添加模板
git add .gitmessage .github/
git commit -m "chore: add commit message template and PR template"

# 添加项目结构
git add README.md
git commit -m "docs: add project README with structure overview"

# 查看提交历史
git log --oneline
```

**预期输出：**

```
abc1234 docs: add project README with structure overview
def5678 chore: add commit message template and PR template
ghi9012 chore: add IaC-specific .gitignore
```

你已经创建了一个符合日本 IT 企业标准的 IaC 仓库！

---

## 发生了什么？

### 为什么这些规范很重要？

在日本的 IT 企业（特别是 SIer、金融、保险行业），代码管理有严格的规范要求：

1. **可追溯性**（トレーサビリティ）：每个变更都能追溯到原因和批准者
2. **标准化**（標準化）：统一的格式便于团队协作和交接
3. **审计对应**（監査対応）：满足 J-SOX、ISMS 等合规要求

---

## 核心概念

### 1. 日本企业的 Git 惯例

![Japan Git Workflow](images/japan-git-workflow.png)

<details>
<summary>View ASCII source</summary>

<!-- DIAGRAM: japan-git-workflow -->
```
              日本 IT 企業の Git ワークフロー

    ┌─────────────────────────────────────────────────────────┐
    │                                                         │
    │   Developer        Team Lead        Infra Manager       │
    │       │                │                  │             │
    │       │  ① Create PR   │                  │             │
    │       │   (変更申請)    │                  │             │
    │       ▼                │                  │             │
    │   ┌────────┐           │                  │             │
    │   │feature │           │                  │             │
    │   │branch  │           │                  │             │
    │   └───┬────┘           │                  │             │
    │       │                │                  │             │
    │       │ ② Code Review  │                  │             │
    │       ├───────────────▶│                  │             │
    │       │                │ ③ Approve        │             │
    │       │                │  (承認)          │             │
    │       │                ▼                  │             │
    │       │           ┌────────┐              │             │
    │       │           │LGTM    │              │             │
    │       │           └───┬────┘              │             │
    │       │               │                   │             │
    │       │               │ ④ 本番承認         │             │
    │       │               ├──────────────────▶│             │
    │       │               │                   │ ⑤ 最終承認   │
    │       │               │                   ▼             │
    │       │               │              ┌────────┐         │
    │       │               │              │Approved│         │
    │       │               │              └───┬────┘         │
    │       │               │                  │              │
    │       ▼               ▼                  ▼              │
    │   ┌──────────────────────────────────────────┐          │
    │   │              Merge to main               │          │
    │   │              (本番反映)                   │          │
    │   └──────────────────────────────────────────┘          │
    │                                                         │
    └─────────────────────────────────────────────────────────┘
```
<!-- /DIAGRAM -->

</details>

**日本企业的特点：**

| 项目 | 日本企業 | 欧美/スタートアップ |
|------|---------|-------------------|
| 分支策略 | Git Flow 较多 | GitHub Flow / Trunk-based |
| 承认层级 | 多层（开发 → Lead → Manager） | 1-2 层 |
| 提交粒度 | 小步提交，文档完整 | 功能完成即可 |
| PR 描述 | 详细（変更管理書）| 简洁 |
| 代码审查 | 丁寧なコメント | 直接的 |

### 2. Commit Message 规范

日本 IT 现场常见三种风格：

#### 2.1 Conventional Commits（推荐）

```bash
# 英语前缀 + 英语描述
feat: add memory check function
fix: correct security group ingress rule
docs: update deployment guide
refactor: simplify VPC module structure
chore: update terraform to 1.14.3
```

**优点**：
- 国际通用，自动化工具友好
- 便于生成 CHANGELOG
- CI/CD 可自动打标签

#### 2.2 纯日语提交

```bash
# 日语描述（日本团队内部常见）
git commit -m "メモリチェック機能を追加"
git commit -m "セキュリティグループのルールを修正"
git commit -m "デプロイ手順書を更新"
```

**适用场景**：纯日本团队，无海外协作

#### 2.3 混合风格

```bash
# 英语前缀 + 日语描述
feat: メモリチェック機能追加
fix: セキュリティグループルール修正

# 或者：英语前缀 + 中英日混合
feat: add memory check function (メモリチェック)
```

**建议**：跟随团队规范。没有规范时，建议使用 Conventional Commits。

### 3. 分支命名规范

```bash
# 标准格式
feature/add-user-auth          # 新功能
feature/JIRA-123-add-vpc       # 包含 Ticket 编号
fix/memory-leak-issue          # Bug 修复
hotfix/critical-security-patch # 紧急修复
release/v1.2.0                 # 发布分支
```

**命名规则**：

| 规则 | 正确 | 错误 |
|------|------|------|
| 使用英语 | `feature/add-auth` | `feature/認証追加` |
| 使用连字符 | `add-user-auth` | `add_user_auth` |
| 小写字母 | `feature/vpc` | `Feature/VPC` |
| 包含 Ticket | `JIRA-123-add-vpc` | `add-vpc` |

### 4. Git 与変更管理的对应

![Git Change Management](images/git-change-management.png)

<details>
<summary>View ASCII source</summary>

<!-- DIAGRAM: git-change-management -->
```
          Git ワークフロー ↔ 変更管理プロセス

    ┌─────────────────────────────────────────────────────────┐
    │                                                         │
    │   Git Concept              日本 IT 変更管理             │
    │                                                         │
    │   ┌──────────────┐         ┌──────────────┐             │
    │   │ Pull Request │ ═══════ │  変更申請書   │             │
    │   │ Description  │         │  稟議書       │             │
    │   └──────────────┘         └──────────────┘             │
    │          │                        │                     │
    │          ▼                        ▼                     │
    │   ┌──────────────┐         ┌──────────────┐             │
    │   │ Code Review  │ ═══════ │  技術レビュー  │             │
    │   │              │         │              │             │
    │   └──────────────┘         └──────────────┘             │
    │          │                        │                     │
    │          ▼                        ▼                     │
    │   ┌──────────────┐         ┌──────────────┐             │
    │   │  Approval    │ ═══════ │    承認      │             │
    │   │  (LGTM)      │         │   決裁印     │             │
    │   └──────────────┘         └──────────────┘             │
    │          │                        │                     │
    │          ▼                        ▼                     │
    │   ┌──────────────┐         ┌──────────────┐             │
    │   │    Merge     │ ═══════ │    実施      │             │
    │   │              │         │   本番反映   │             │
    │   └──────────────┘         └──────────────┘             │
    │          │                        │                     │
    │          ▼                        ▼                     │
    │   ┌──────────────┐         ┌──────────────┐             │
    │   │  Git Log     │ ═══════ │  変更履歴    │             │
    │   │  History     │         │  監査証跡    │             │
    │   └──────────────┘         └──────────────┘             │
    │                                                         │
    └─────────────────────────────────────────────────────────┘
```
<!-- /DIAGRAM -->

</details>

**详细对应表：**

| Git 概念 | 日本語 | 説明 |
|----------|--------|------|
| PR Description | 変更管理書 / 稟議書 | 变更内容、影响范围、切り戻し手順 |
| Create PR | 起票 | 发起变更申请 |
| Code Review | コードレビュー | 技术审查 |
| Approval | 承認 | 上长批准（可能多层） |
| Merge | 決裁 / 実施 | 最终批准并执行 |
| Git Log | 変更履歴 | 审计证跡 |
| Protected Branch | 本番環境制限 | 直接 push 禁止 |
| Revert | 切り戻し | 回滚操作 |

**为什么 PR-based 工作流适合日本企业？**

1. **天然的审批流程**：PR 的 Approval 机制符合稟議制度
2. **完整的记录**：所有讨论和批准都在 PR 中保留
3. **权限分离**：main 分支保护 = 本番環境的変更制限
4. **可追溯性**：`git log` + PR 历史 = 完整的監査証跡

### 5. IaC 仓库标准结构

![IaC Repo Structure](images/iac-repo-structure.png)

<details>
<summary>View ASCII source</summary>

<!-- DIAGRAM: iac-repo-structure -->
```
            Production-Ready IaC Repository Structure

    my-infrastructure/
    │
    ├── .github/
    │   ├── pull_request_template.md    ← PR テンプレート
    │   ├── CODEOWNERS                  ← 承認者定義
    │   └── workflows/
    │       ├── terraform-plan.yml      ← PR 時に自動 plan
    │       ├── terraform-apply.yml     ← main マージで apply
    │       └── security-scan.yml       ← セキュリティチェック
    │
    ├── modules/                        ← 再利用可能モジュール
    │   ├── vpc/
    │   │   ├── main.tf
    │   │   ├── variables.tf
    │   │   └── outputs.tf
    │   ├── ec2/
    │   └── rds/
    │
    ├── environments/                   ← 環境別設定
    │   ├── dev/
    │   │   ├── main.tf
    │   │   ├── terraform.tfvars
    │   │   └── backend.tf
    │   ├── staging/
    │   └── prod/                       ← 本番（承認必須）
    │
    ├── docs/                           ← ドキュメント
    │   ├── architecture.md
    │   ├── runbook.md
    │   └── disaster-recovery.md
    │
    ├── .gitignore                      ← IaC 専用
    ├── .gitmessage                     ← Commit テンプレート
    ├── .pre-commit-config.yaml         ← Pre-commit hooks
    └── README.md
```
<!-- /DIAGRAM -->

</details>

---

## 動手练习：完善仓库设置

### 练习 1：创建 CODEOWNERS

CODEOWNERS 定义谁必须审批特定路径的变更：

```bash
cat > .github/CODEOWNERS << 'EOF'
# Default owner for everything
* @your-team

# Production environment requires senior approval
/environments/prod/ @senior-engineer @infra-manager

# Security-related files require security team review
/modules/*/security*.tf @security-team

# CI/CD configuration requires DevOps team approval
/.github/workflows/ @devops-team
EOF

git add .github/CODEOWNERS
git commit -m "chore: add CODEOWNERS for approval routing"
```

### 练习 2：配置 Git Hooks（本地检查）

使用 pre-commit 确保提交前检查：

```bash
cat > .pre-commit-config.yaml << 'EOF'
repos:
  - repo: https://github.com/pre-commit/pre-commit-hooks
    rev: v6.0.0
    hooks:
      - id: trailing-whitespace
      - id: end-of-file-fixer
      - id: check-yaml
      - id: check-added-large-files
        args: ['--maxkb=500']
      - id: detect-private-key
      - id: detect-aws-credentials

  - repo: https://github.com/antonbabenko/pre-commit-terraform
    rev: v1.104.0  # Check latest: github.com/antonbabenko/pre-commit-terraform/releases
    hooks:
      - id: terraform_fmt
      - id: terraform_validate
      - id: terraform_docs
EOF

git add .pre-commit-config.yaml
git commit -m "chore: add pre-commit hooks for code quality"
```

### 练习 3：Feature 分支工作流

模拟实际的开发流程：

```bash
# 1. 创建 feature 分支
git checkout -b feature/JIRA-001-add-vpc-module

# 2. 创建模块文件
mkdir -p modules/vpc
cat > modules/vpc/main.tf << 'EOF'
# VPC Module for my-infrastructure
# Author: Your Name
# Created: 2026-01-02

resource "aws_vpc" "main" {
  cidr_block           = var.cidr_block
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name        = var.name
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}
EOF

cat > modules/vpc/variables.tf << 'EOF'
variable "name" {
  description = "Name of the VPC"
  type        = string
}

variable "cidr_block" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "environment" {
  description = "Environment name (dev/staging/prod)"
  type        = string
}
EOF

cat > modules/vpc/outputs.tf << 'EOF'
output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.main.id
}

output "cidr_block" {
  description = "CIDR block of the VPC"
  value       = aws_vpc.main.cidr_block
}
EOF

# 3. 提交（符合 Conventional Commits）
git add modules/vpc/
git commit -m "feat: add VPC module with basic configuration

- Add main.tf with VPC resource
- Add variables.tf for customization
- Add outputs.tf for downstream modules

JIRA-001"

# 4. 查看分支状态
git log --oneline main..HEAD
```

**预期输出：**

```
xyz7890 feat: add VPC module with basic configuration
```

```bash
# 5. 切换回 main（实际工作中，这里会创建 PR）
git checkout main
git merge feature/JIRA-001-add-vpc-module --no-ff -m "Merge feature/JIRA-001-add-vpc-module

Approved-by: @senior-engineer
JIRA-001"

# 6. 删除已合并分支
git branch -d feature/JIRA-001-add-vpc-module

# 7. 查看完整历史
git log --oneline --graph
```

---

## 職場小贴士

### 日本 IT 企業での実態

#### 大手 SIer / 金融系

| 項目 | 現場の実態 | Git での対応 |
|------|-----------|-------------|
| 変更管理票 | Excel / 社内システム | PR description |
| 承認 | ハンコ / 電子承認 | GitHub Approval |
| 実施記録 | 作業報告書（Word） | Git log + PR history |
| 変更凍結 | 年末年始・決算期 | Protected branch rules |

#### スタートアップ / Web 系

| 項目 | 現場の実態 | Git での対応 |
|------|-----------|-------------|
| 変更管理 | PR ベースで完結 | 同じ |
| 承認 | Slack + GitHub | 1-2 人の Approval |
| 実施記録 | Git log のみ | 同じ |
| デプロイ | 日に複数回 | CI/CD 自動化 |

### よく使う表現

| 場面 | 日本語 | 英語 |
|------|--------|------|
| PR 作成時 | レビューお願いします | Please review |
| 承認時 | LGTM | Looks Good To Me |
| 修正依頼 | こちらの修正をお願いできますか | Could you fix this? |
| マージ時 | マージしました | Merged |
| 感謝 | レビューありがとうございます | Thanks for the review |

---

## 面试准备：5 道 Git 问题

### 問題 1: Git と SVN の違いは？

**質問（日本語）：**

> Git と SVN（Subversion）の違いを説明してください。

**回答例：**

```
Git は分散型バージョン管理システムで、全ての開発者がリポジトリの
完全なコピーを持ちます。

主な違い：
1. 分散 vs 集中：Git は各自がフルの履歴を持つ。SVN は中央サーバーに依存
2. オフライン作業：Git は可能。SVN は不可
3. ブランチ：Git は軽量で高速。SVN は重い
4. マージ：Git の方が高度なマージ機能を持つ

Git を選ぶ理由は、オフライン作業、高速なブランチ操作、
GitHub/GitLab との連携です。
```

### 問題 2: コンフリクトが発生したらどう対応しますか？

**質問（日本語）：**

> マージ時にコンフリクトが発生した場合、どのように対応しますか？

**回答例：**

```
コンフリクト発生時の対応手順：

1. git status でコンフリクトファイルを確認
2. ファイルを開き、<<<< ==== >>>> マーカーを確認
3. 両方の変更を理解し、適切な内容に修正
4. マーカーを削除
5. git add でステージング
6. git commit でマージ完了
7. テストを実行して問題ないことを確認

重要なのは、両方の変更の意図を理解してから修正することです。
不明な場合は、変更者に確認を取ります。
```

### 問題 3: ブランチ戦略の経験は？

**質問（日本語）：**

> どのようなブランチ戦略を使った経験がありますか？

**回答例：**

```
Git Flow と GitHub Flow の両方を使った経験があります。

Git Flow：
- main, develop, feature, release, hotfix ブランチ
- リリースサイクルが明確な場合に適している
- 金融系プロジェクトで使用

GitHub Flow：
- main と feature ブランチのみ
- 継続的デリバリーに適している
- スタートアップで使用

チーム規模、リリース頻度、承認フローに応じて選択します。
日本企業では承認フローとの相性から Git Flow が多い印象です。
```

### 問題 4: コードレビューで気をつけていることは？

**質問（日本語）：**

> コードレビューで気をつけていることを教えてください。

**回答例：**

```
レビュアーとして：
1. 変更の目的を理解してからレビュー
2. ロジックと設計に焦点、フォーマットは自動化
3. 建設的なフィードバック（「なぜ」を説明）
4. 必須修正と提案を明確に区別
5. 良い点も指摘する

レビューイとして：
1. 小さい PR を心がける（レビューしやすい）
2. 変更理由を PR 説明に明記
3. セルフレビューを先に実施
4. フィードバックには感謝の姿勢

目標はコード品質の向上と知識共有です。
```

### 問題 5: Git のベストプラクティスは？

**質問（日本語）：**

> Git 使用のベストプラクティスを教えてください。

**回答例：**

```
1. コミット
   - 小さく頻繁にコミット
   - 意味のあるコミットメッセージ
   - Conventional Commits 形式

2. ブランチ
   - feature ブランチで開発
   - main への直接プッシュ禁止
   - マージ後はブランチ削除

3. レビュー
   - PR でレビューを必須化
   - CI/CD でテスト自動実行
   - Approval なしでマージ不可

4. セキュリティ
   - .gitignore で機密ファイル除外
   - シークレットは環境変数で管理
   - git-secrets で事前チェック

5. 履歴
   - 履歴を綺麗に保つ
   - rebase は慎重に（チーム合意）
   - force push は原則禁止
```

---

## 检查清单

完成以下检查项，确认你已掌握本课内容：

- [ ] 创建了标准的 IaC 仓库结构
- [ ] 设置了 Commit Message 模板
- [ ] 创建了双语 PR 模板
- [ ] 理解 Git 与変更管理的对应关系
- [ ] 能用 Conventional Commits 格式写提交信息
- [ ] 能用 feature 分支工作流开发
- [ ] 能用日语回答 5 道面试题

---

## 延伸阅读

### Git 规范

- [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/)
- [Git Flow](https://nvie.com/posts/a-successful-git-branching-model/)
- [GitHub Flow](https://docs.github.com/en/get-started/using-github/github-flow)

<details>
<summary>💡 跨平台协作：CRLF 问题详解</summary>

### 什么是换行符问题？

不同操作系统使用不同的换行符：

| 系统 | 换行符 | 表示 |
|------|--------|------|
| Windows | CRLF | `\r\n` |
| Linux/macOS | LF | `\n` |

### 会导致什么问题？

1. **Shell 脚本无法运行**
   ```
   bash: ./check.sh: /bin/bash^M: bad interpreter
   ```
   （`^M` 就是多余的 `\r`）

2. **Git diff 显示整个文件被修改**（实际只是换行符不同）

3. **团队协作时产生不必要的冲突**

### 解决方案

**方案 1：Git 配置（个人设置）**

```bash
# Windows 用户
git config --global core.autocrlf true

# Linux/macOS 用户
git config --global core.autocrlf input
```

**方案 2：.gitattributes（项目级，推荐）**

```gitattributes
# 自动检测文本文件并统一换行符
* text=auto

# 强制 LF（Linux 格式）
*.sh text eol=lf
*.tf text eol=lf
*.yaml text eol=lf
*.yml text eol=lf
*.json text eol=lf

# 强制 CRLF（Windows 格式）
*.bat text eol=crlf
*.ps1 text eol=crlf
```

> **最佳实践**：在项目根目录创建 `.gitattributes`，团队所有成员自动生效。

</details>

### 日本 IT 文化

- [Systems Integrator (SIer)](https://en.wikipedia.org/wiki/Systems_integrator) - 英文维基百科
- [Information technology in Japan](https://en.wikipedia.org/wiki/Information_technology_in_Japan) - 日本 IT 产业概述

### 相关课程

- [Terraform 15 · 日本 IT 変更管理](../../automation/terraform/15-jp-change-mgmt/) - OIDC 权限分离
- [Git 00 · 概念导入](../00-concepts/) - Git 基础理念
- [Git 05 · Pull Request](../05-pull-requests/) - PR 工作流详解

---

## 系列导航

← [05 · Pull Request](../05-pull-requests/) | [Home](../) | [Course Complete!]

---

## 附录：模板文件

本课使用的模板文件已在练习中创建，你也可以从以下路径获取完整版本：

> **路径说明**：模板位于 `cloud-atlas/foundations/git/06-japan-it/templates/`

| 文件 | 路径 | 用途 |
|------|------|------|
| Commit Message 模板 | `templates/gitmessage` | Git 提交时使用 |
| PR 模板（完整版） | `templates/pull_request_template.md` | 生产级 PR 模板，含安全检查 |
| IaC .gitignore | `templates/gitignore-iac` | Terraform/Ansible 项目 |
| CODEOWNERS | `templates/CODEOWNERS` | 审批路由 |

> **提示**：课文中的 PR 模板是简化版，`templates/` 目录中的是生产级完整版（含安全审查、回滚计划等）。

---

*本课程为日本 IT 就职者设计。如果你的目标是其他地区，可以跳过本课，直接应用前五课的 Git 技能。*
