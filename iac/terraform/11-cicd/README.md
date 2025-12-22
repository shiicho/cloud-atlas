# 11 - CI/CD 集成

> **目标**：在 GitHub Actions 中实现 Terraform 自动化工作流，PR 自动 plan、人工审批后 apply
> **前置**：已完成 [10 - 漂移检测](../10-drift/)
> **时间**：45-60 分钟
> **费用**：GitHub Actions 免费额度内

---

## 将学到的内容

1. 在 CI 中运行 `terraform plan`（自动化审查）
2. 实现手动审批门禁（Gated Apply）
3. 配置 OIDC 认证（无需长期 Access Key）
4. 使用 Infracost 在 PR 中显示成本变化
5. 了解 Atlantis 模式（PR-driven Terraform）

---

## 先跑起来：5 分钟看到效果

> 我们先用最简单的方式跑通 GitHub Actions + Terraform，再理解细节。

### 快速体验步骤

```bash
# 1. 克隆示例代码（如果尚未克隆）
# GitHub（海外用户）
git clone --filter=blob:none --sparse https://github.com/shiicho/cloud-atlas ~/cloud-atlas
cd ~/cloud-atlas && git sparse-checkout set iac/terraform

# Gitee（中国大陆用户）
git clone --filter=blob:none --sparse https://gitee.com/shiicho/cloud-atlas ~/cloud-atlas
cd ~/cloud-atlas && git sparse-checkout set iac/terraform

# 2. 进入示例目录
cd ~/cloud-atlas/iac/terraform/11-cicd/code
```

查看文件结构：

```
code/
├── .github/
│   └── workflows/
│       ├── terraform-plan.yml      # PR 时自动 plan
│       └── terraform-apply.yml     # 手动触发 apply
├── oidc-setup/
│   └── github-oidc.yaml            # CloudFormation 配置 OIDC
├── infracost/
│   └── infracost.yml               # Infracost 配置
├── main.tf                         # 示例资源
├── providers.tf
└── backend.tf                      # S3 远程后端
```

---

## 发生了什么？CI/CD 工作流解析

### PR-Driven Terraform 流程

![PR-Driven Terraform Workflow](images/cicd-workflow.png)

### 关键设计原则

| 原则 | 说明 | 日本 IT 对应 |
|------|------|-------------|
| **Plan 自动化** | PR 时自动运行 plan，结果作为评论 | 変更内容の可視化 |
| **Apply 门禁** | 需要人工审批才能 apply | 承認フロー |
| **OIDC 认证** | 无需存储 Access Key，临时凭证 | セキュリティ強化 |
| **成本可见** | PR 中显示预估成本变化 | コスト管理 |

---

## 核心概念

### 1. Plan in PR：自动化审查

每次 PR 创建或更新时，自动运行 `terraform plan`：

**优势**：
- 代码审查者能看到实际变更
- 避免 "合并后才发现问题"
- 成本变化一目了然

**工作流触发条件**：

```yaml
on:
  pull_request:
    branches: [main]
    paths:
      - 'terraform/**'
      - '.github/workflows/terraform-*.yml'
```

### 2. Gated Apply：人工审批门禁

Apply 不能自动执行——必须有人工审批：

**两种实现方式**：

| 方式 | 配置 | 适用场景 |
|------|------|----------|
| GitHub Environments | `environment: production` + 审批者 | 推荐，原生支持 |
| 手动触发 | `workflow_dispatch` | 简单场景 |

### 3. OIDC 认证：告别长期密钥

![OIDC Authentication Flow](images/oidc-flow.png)

**OIDC 信任策略条件**：

```json
{
  "Condition": {
    "StringEquals": {
      "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
    },
    "StringLike": {
      "token.actions.githubusercontent.com:sub": "repo:your-org/your-repo:*"
    }
  }
}
```

### 4. Atlantis 模式（简介）

Atlantis 是另一种 PR-driven Terraform 方案：

| 特性 | GitHub Actions | Atlantis |
|------|---------------|----------|
| 部署方式 | SaaS（GitHub 托管） | 自托管服务器 |
| 触发方式 | YAML 工作流 | PR 评论命令 |
| 成本 | 免费额度内免费 | 服务器成本 |
| 复杂度 | 低 | 中等 |
| 适用场景 | 大多数团队 | 大型企业、多 VCS |

**Atlantis 命令示例**：

```
# 在 PR 评论中输入
atlantis plan
atlantis apply
```

> **建议**：新团队从 GitHub Actions 开始，需要更多控制时再考虑 Atlantis。

### 5. Infracost：成本可见化

在 PR 中显示基础设施成本变化：

![Infracost PR Comment](images/infracost-comment.png)

---

## 动手实践：构建 Plan-on-PR Pipeline

### Step 1：配置 AWS OIDC Provider

首先在 AWS 中创建 OIDC Identity Provider：

```bash
cd ~/cloud-atlas/iac/terraform/11-cicd/code/oidc-setup

# 查看 CloudFormation 模板
cat github-oidc.yaml
```

部署 OIDC Provider（一次性操作）：

```bash
aws cloudformation deploy \
  --template-file github-oidc.yaml \
  --stack-name github-oidc-terraform \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides \
    GitHubOrg=your-github-org \
    RepoName=your-repo-name
```

> **注意**：替换 `your-github-org` 和 `your-repo-name` 为你的实际值。

### Step 2：配置 GitHub Secrets

在 GitHub 仓库设置中添加：

| Secret 名称 | 值 |
|------------|-----|
| `AWS_ROLE_ARN` | OIDC IAM Role ARN（CloudFormation 输出） |
| `INFRACOST_API_KEY` | Infracost API Key（可选） |

**获取 Role ARN**：

```bash
aws cloudformation describe-stacks \
  --stack-name github-oidc-terraform \
  --query 'Stacks[0].Outputs[?OutputKey==`RoleArn`].OutputValue' \
  --output text
```

### Step 3：创建 GitHub Actions 工作流

查看 Plan 工作流：

```bash
cat .github/workflows/terraform-plan.yml
```

**关键配置说明**：

```yaml
# 权限：允许 OIDC 认证 + 写入 PR 评论
permissions:
  id-token: write      # OIDC 令牌
  contents: read       # 读取代码
  pull-requests: write # 写入 PR 评论

# OIDC 认证步骤
- name: Configure AWS credentials
  uses: aws-actions/configure-aws-credentials@v4
  with:
    role-to-assume: ${{ secrets.AWS_ROLE_ARN }}
    aws-region: ap-northeast-1
```

### Step 4：测试工作流

1. **创建测试分支**：

```bash
git checkout -b test-cicd
```

2. **修改资源**（例如添加标签）：

```bash
# 编辑 main.tf，添加一个标签
vim main.tf
```

3. **推送并创建 PR**：

```bash
git add .
git commit -m "test: add tag for CI/CD testing"
git push -u origin test-cicd
```

4. **观察 GitHub Actions**：
   - 进入 GitHub 仓库 > Actions
   - 查看 "Terraform Plan" 工作流运行
   - PR 中会出现 plan 结果评论

### Step 5：配置 Production 环境审批

1. **创建 GitHub Environment**：
   - 仓库 Settings > Environments > New environment
   - 名称：`production`
   - 添加审批者（Required reviewers）

2. **Apply 工作流使用 Environment**：

```yaml
jobs:
  apply:
    environment: production  # 需要审批
    runs-on: ubuntu-latest
```

---

## 职场小贴士

### 日本 IT 企业的変更管理

在日本企业，基础设施变更通常需要：

| 阶段 | 日本术语 | CI/CD 对应 |
|------|----------|-----------|
| 変更申請 | 変更管理票 | PR 创建 |
| 影響範囲確認 | 影響調査 | terraform plan 输出 |
| 承認 | 承認フロー | GitHub Environment 审批 |
| 実施 | 本番適用 | terraform apply |
| 確認 | 動作確認 | Apply 后验证 |

**典型的审批流程**：

```
開発者 → チームリード → インフラ責任者 → 実施
  ↓         ↓              ↓
 PR作成   コードレビュー    本番承認
```

### 変更凍結期間（Change Freeze）

日本企业通常在以下时期禁止变更：

- **年末年始**（12/28 - 1/3）
- **ゴールデンウィーク**（4/29 - 5/5）
- **決算期末**（3月末、9月末）

**CI/CD 中的实现**：

```yaml
# 在 workflow 中检查冻结期
- name: Check change freeze
  run: |
    MONTH=$(date +%m)
    DAY=$(date +%d)
    if [[ "$MONTH" == "12" && "$DAY" -ge "28" ]] || \
       [[ "$MONTH" == "01" && "$DAY" -le "03" ]]; then
      echo "::error::変更凍結期間中です。緊急変更の場合は承認を取得してください。"
      exit 1
    fi
```

---

## 检查清单

完成以下检查项，确认你已掌握本课内容：

- [ ] 理解 Plan in PR 的价值（自动化审查，成本可见）
- [ ] 能配置 AWS OIDC Provider（无需 Access Key）
- [ ] 能编写 GitHub Actions 工作流（plan + apply）
- [ ] 理解 Gated Apply 的实现方式（Environment 审批）
- [ ] 了解 Infracost 的作用（成本估算）
- [ ] 了解 Atlantis 模式（PR 评论驱动）
- [ ] 理解日本企业的変更管理流程

---

## 面试准备

**Q: Terraform の CI/CD ベストプラクティスは？**

A: PR で plan 自動実行、apply は手動承認、OIDC で認証（Access Key 不要）、State は S3+DynamoDB でリモート管理。コスト可視化のため Infracost も導入。

**Q: OIDC 認証のメリットは？**

A: 長期的な認証情報の保存が不要、一時的なクレデンシャルで自動期限切れ、リポジトリ・ブランチ単位でアクセス制御可能。

**Q: なぜ apply は手動承認が必要？**

A: インフラ変更は影響範囲が大きい。plan の結果を確認し、承認フローを経てから実施することで、事故を防止。日本企業では変更管理票との連携も重要。

---

## トラブルシューティング

### OIDC 認証失敗

```
Error: Could not assume role with OIDC
```

**確認ポイント**：
1. IAM Role の信頼ポリシーで `repo:org/repo:*` が正しいか
2. GitHub Actions の `permissions.id-token: write` が設定されているか
3. AWS Region が正しいか

### Plan がコメントされない

**確認ポイント**：
1. `permissions.pull-requests: write` が設定されているか
2. Workflow のトリガーが `pull_request` になっているか

### State Lock エラー

```
Error: Error acquiring the state lock
```

**対処**：
1. 他の apply が実行中でないか確認
2. DynamoDB のロックレコードを確認
3. 必要に応じて `terraform force-unlock`

---

## 延伸阅读

- [GitHub Actions - AWS OIDC](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/configuring-openid-connect-in-amazon-web-services)
- [Terraform GitHub Actions](https://github.com/hashicorp/setup-terraform)
- [Infracost](https://www.infracost.io/docs/)
- [Atlantis](https://www.runatlantis.io/)
- [12 - 安全与机密管理](../12-security/) - 下一课

---

## 清理资源

> ⚠️ **本课涉及 IAM Role 和 OIDC Provider**，请务必清理：

```bash
cd ~/cloud-atlas/iac/terraform/11-cicd/code

# 删除 OIDC Provider 和 IAM Role
terraform destroy -auto-approve

# 确认资源已删除
aws iam list-open-id-connect-providers
```

---

## 系列导航

← [10 · 漂移検知](../10-drift/) | [Home](../) | [12 · 安全管理 →](../12-security/)
