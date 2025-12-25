# 11 - CI/CD 集成

> **目标**：在 GitHub Actions 中实现 Terraform 自动化工作流，PR 自动 plan、人工审批后 apply
> **前置**：已完成 [10 - 漂移检测](../10-drift/)
> **时间**：45-60 分钟（概念） + 60 分钟（动手实验）
> **费用**：GitHub Actions 免费额度内

---

## Hands-On Lab Available!

> **Ready to experience CI/CD yourself?**
> We've prepared a self-contained demo that you can copy, push to YOUR GitHub, and run a real CI/CD pipeline!
>
> **[Start the Hands-On Lab](terraform-cicd-demo/)** — Create PR, see plan comments, approve apply!

---

## 将学到的内容

1. 在 CI 中运行 `terraform plan`（自动化审查）
2. 实现手动审批门禁（Gated Apply）
3. 配置 OIDC 认证（无需长期 Access Key）
4. 使用 Infracost 在 PR 中显示成本变化
5. 了解 Atlantis 模式（PR-driven Terraform）

---

## Step 1 — 环境准备与连接（2 分钟）

连接到你的 Terraform Lab 实例。

**获取实例 ID：**

```bash
aws cloudformation describe-stacks \
  --stack-name terraform-lab \
  --region ap-northeast-1 \
  --query 'Stacks[0].Outputs[?OutputKey==`InstanceId`].OutputValue' \
  --output text
```

> **💡 连接方式**（选择你熟悉的）：  
> - **AWS Console**：EC2 → 选择实例 → Connect → Session Manager  
> - **AWS CLI**：`aws ssm start-session --target <实例ID> --region ap-northeast-1`  
> - **VS Code**：Remote-SSH 连接（如已配置）  
>
> **❓ 没有实例？** Stack 不存在或实例已终止？  
> → [重新部署实验环境](../00-concepts/lab-setup.md)

连接后，切换到课程用户并同步代码：

```bash
sudo su - terraform
sync-course
```

确认上一课的资源已清理：

```bash
cd ~/cloud-atlas/iac/terraform/10-drift/code/drift-detect
terraform state list  # 应为空
```

---

## Step 2 — 先跑起来：5 分钟看到效果

> 想要实际体验？跳转到 **[Hands-On Lab](terraform-cicd-demo/)**！
>
> 下面是概念理解，帮助你理解 CI/CD 流程。

### 2.1 Demo 目录结构

Hands-On Lab 使用的是 `terraform-cicd-demo/` 目录：

```
terraform-cicd-demo/           # ← 你会复制这个文件夹
├── README.md                  # 动手实验指南（13步）
├── .github/
│   └── workflows/
│       ├── terraform-plan.yml # PR 时自动 plan
│       └── terraform-apply.yml# 合并后自动 apply
├── oidc-setup/
│   └── github-oidc.yaml       # CloudFormation 配置 OIDC
├── main.tf                    # 示例资源（S3 Bucket）
├── providers.tf
├── variables.tf
└── outputs.tf
```

---

## 发生了什么？CI/CD 工作流解析

### PR-Driven Terraform 流程

![PR-Driven Terraform Workflow](images/cicd-workflow.png)

<details>
<summary>View ASCII source</summary>

```
         PR-Driven Terraform Workflow

Developer              GitHub                 AWS
    │                    │                    │
  1 │── Push branch ────▶│                    │
  2 │── Create PR ──────▶│                    │
    │                    │ 3 Trigger Plan     │
    │                    │ 4 ──OIDC Auth─────▶│
    │                    │ 5 ──terraform plan─▶│
    │                    │◀──── 6 Plan output──│
  7 │◀─Plan result in PR─│                    │
    │                    │                    │
    │     ─────────── Review Phase ───────────│
  8 │── Review+Approve ─▶│                    │
  9 │── Merge PR ───────▶│                    │
    │                    │                    │
    │    ─── Apply Phase (Manual Approval) ───│
    │                    │10─terraform apply─▶│
    │                    │◀─11 Apply complete─│
```

</details>

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
      - '**/*.tf'
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

<details>
<summary>View ASCII source</summary>

```
          OIDC Authentication Flow

  GitHub Actions                      AWS IAM
       │                                 │
     1 │ Job starts                      │
     2 │ Request OIDC token              │
     3 │──── Present OIDC token ────────▶│
       │                               4 │ Validate (issuer,
       │                                 │ audience, repo, branch)
     5 │◀── Receive temp credentials ────│
       │    (15min ~ 1h)                 │
     6 │── Use credentials for TF ──────▶│ ✓ AWS API
       │                                 │

  ─────────────────── Comparison ───────────────────

  ┌─────────────────────────┐  ┌─────────────────────────┐
  │ ✗ Access Key            │  │ ✓ OIDC (recommended)    │
  │   (not recommended)     │  │                         │
  │ • Long-term keys stored │  │ • No keys to store      │
  │ • High risk of leakage  │  │ • Temp credentials      │
  │ • Cannot restrict repo  │  │ • Restrict by repo/branch│
  └─────────────────────────┘  └─────────────────────────┘
```

</details>

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

<details>
<summary>View ASCII source</summary>

```
┌─────────────────────────────────────────────────────────────┐
│ 🔀 Add production RDS instance #123                         │
├─────────────────────────────────────────────────────────────┤
│ 🟢 infracost [bot] commented just now                       │
│                                                             │
│ 💰 Infracost Monthly Cost Estimate                          │
│                                                             │
│ Project: terraform/production                               │
│                                                             │
│ Resource              Before    After     Change            │
│ ─────────────────────────────────────────────────           │
│ aws_db_instance.main   $0      $150/mo   +$150              │
│ aws_ebs_volume.data    $0       $20/mo    +$20              │
│ aws_instance.app (x3) $45/mo    $45/mo     $0               │
│ ─────────────────────────────────────────────────           │
│ Total Monthly Cost    $45/mo → $215/mo (+$170/mo, +378%)    │
│                                                             │
│ ⚠️ Significant cost increase detected.                      │
│    Please confirm budget approval before merging.           │
└─────────────────────────────────────────────────────────────┘
```

</details>

---

## 动手实践

> **Complete Hands-On Lab Available!**
>
> We've prepared a self-contained demo repo folder: **[terraform-cicd-demo/](terraform-cicd-demo/)**
>
> Copy it, push to YOUR GitHub, and experience:
> - PR triggers automatic `terraform plan`
> - Plan results appear as PR comments
> - Merge triggers `terraform apply` with approval gate
>
> **[Start the Lab Now →](terraform-cicd-demo/)**

### Quick Reference: Key Concepts in Practice

**OIDC Authentication** (used in the lab):

```yaml
# No Access Key needed! OIDC provides temporary credentials
- name: Configure AWS credentials
  uses: aws-actions/configure-aws-credentials@v4
  with:
    role-to-assume: ${{ secrets.AWS_ROLE_ARN }}
    aws-region: ap-northeast-1
```

**GitHub Environment Approval** (used in the lab):

```yaml
jobs:
  apply:
    environment: production  # Requires approval before running
    runs-on: ubuntu-latest
```

**Plan Result as PR Comment** (you'll see this in the lab):

The bot automatically posts a comment showing:
- Format check status
- Validation status
- Full plan output
- Resources to add/change/destroy

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

A: PR で plan 自動実行、apply は手動承認、OIDC で認証（Access Key 不要）、State は S3 リモートバックエンドで管理（use_lockfile で原生ロック）。コスト可視化のため Infracost も導入。

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
2. S3 の `.tflock` ファイルを確認（use_lockfile 使用時）
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

> ⚠️ **如果你完成了 Hands-On Lab**，请务必清理：

详细的清理步骤在 [terraform-cicd-demo/README.md](terraform-cicd-demo/README.md#step-13-cleanup-5-min) 中。

**快速参考**：

```bash
# 1. 删除 Terraform 管理的资源
cd ~/my-terraform-cicd
terraform destroy -auto-approve

# 2. 删除 OIDC CloudFormation Stack
aws cloudformation delete-stack --stack-name github-oidc-terraform
aws cloudformation wait stack-delete-complete --stack-name github-oidc-terraform

# 3. 确认资源已删除
aws iam list-open-id-connect-providers
```

---

## 系列导航

← [10 · 漂移検知](../10-drift/) | [Home](../) | [12 · 安全管理 →](../12-security/)
