# Terraform CI/CD 动手实验

> **动手实验**：体验真实的 GitHub Actions CI/CD 流水线

这个文件夹是一个完整的、即用型模板。复制到新位置，初始化为 Git 仓库，推送到 GitHub 即可体验：

- **PR 自动 Plan**：自动运行 `terraform plan`，结果作为 PR 评论发布
- **合并后自动 Apply**：自动运行 `terraform apply`，带审批门禁
- **[OIDC 认证](../../../../glossary/security/oidc.md)**：无需 AWS Access Key

---

## 前置要求

开始之前，请确保：

- [ ] GitHub 账户
- [ ] **GitHub Personal Access Token (PAT)**，需要 `repo` + `workflow` 权限 — [点击创建](https://github.com/settings/tokens/new?scopes=repo,workflow)
- [ ] AWS 账户（管理员权限）
- [ ] AWS CLI 已配置（`aws sts get-caller-identity` 可用）
- [ ] Git 已安装
- [ ] 课程代码已克隆（`~/cloud-atlas/` 存在）

> **没有课程代码？** 在实验实例上运行 `sync-course`，或参考 [lab-setup.md](../../00-concepts/lab-setup.md)

---

## 实验步骤

### Step 1：复制模板（3 分钟）

将此文件夹复制到课程仓库外的新位置：

```bash
# 在实验实例上（EC2 或本地）
cp -r ~/cloud-atlas/automation/terraform/11-cicd/terraform-cicd-demo ~/my-terraform-cicd
cd ~/my-terraform-cicd

# 验证所有文件存在
ls -la
ls -la .github/workflows/
```

**检查点**：应看到 `main.tf`、`providers.tf` 和 `.github/workflows/` 文件夹。

---

### Step 2：配置 S3 远程后端（5 分钟）

本实验使用 S3 远程后端存储 State。这对 CI/CD **至关重要**，因为：
- State 在 GitHub Actions 运行之间持久化（Runner 是临时的）
- State 锁定防止并发 apply 冲突
- `terraform destroy` 清理实际有效！

**获取 S3 Bucket 名称**（来自 terraform-lab CloudFormation Stack）：

```bash
# 获取课程设置时创建的 Bucket 名称
BUCKET=$(aws cloudformation describe-stacks \
  --stack-name terraform-lab \
  --query 'Stacks[0].Outputs[?OutputKey==`TfStateBucketName`].OutputValue' \
  --output text)

echo "Your state bucket: $BUCKET"
```

> **没有 terraform-lab Stack？** 先部署它：[lab-setup.md](../../00-concepts/lab-setup.md)

**更新 backend.tf** 中的 Bucket 名称：

```bash
cd ~/my-terraform-cicd

# 将 PLACEHOLDER 替换为实际的 Bucket 名称
sed -i "s/PLACEHOLDER/$BUCKET/" backend.tf

# 验证更改
cat backend.tf
```

应看到配置中的 Bucket 名称：

```hcl
terraform {
  backend "s3" {
    bucket       = "tfstate-terraform-course-123456789012"  # 你的 Bucket
    key          = "11-cicd/cicd-demo/terraform.tfstate"
    region       = "ap-northeast-1"
    encrypt      = true
    use_lockfile = true
  }
}
```

**检查点**：`backend.tf` 显示实际的 Bucket 名称（不是 PLACEHOLDER）。

---

### Step 3：初始化 Git（3 分钟）

将此文件夹初始化为新的 Git 仓库：

```bash
git init -b main
```

> **注意**：`-b main` 直接创建 'main' 分支（GitHub 默认）。不加此参数，git 会创建 'master' 并显示提示信息。

**配置 Git 身份**（如果尚未设置）：

```bash
# 设置提交者名称和邮箱（本地仓库配置）
git config user.name "Your Name"
git config user.email "your-email@example.com"
```

> **注意**：这是 `git commit` 的必要配置。可以使用任意名称/邮箱——它标识谁做了提交。
> 不带 `--global` 的配置只对当前仓库有效，删除仓库时会自动清理。

**暂存文件并创建初始提交**：

```bash
git add .
git commit -m "Initial commit: Terraform CI/CD demo"
```

**检查点**：`git log` 显示初始提交。

---

### Step 4：创建 GitHub 仓库（5 分钟）

1. 访问 [github.com/new](https://github.com/new)
2. Repository name：`my-terraform-cicd`（或其他名称，需与后续步骤保持一致）
3. **Public**（免费账户必须选 Public，否则 Step 8 审批功能不可用）
4. **不要**勾选 "Add a README file"（我们已有）
5. 点击 **Create repository**

> **再次运行本实验？** 如果之前的仓库已删除，可使用相同名称；否则选择新名称如 `my-terraform-cicd-v2`。

创建后，连接本地仓库：

```bash
# 将 YOUR_USERNAME 替换为你的 GitHub 用户名
git remote add origin https://github.com/YOUR_USERNAME/my-terraform-cicd.git
```

**配置 Git 认证**（首次设置）：

GitHub 不再接受 HTTPS git 操作使用密码。需要 Personal Access Token (PAT)：

<details open>
<summary><strong>📋 如何创建 GitHub PAT</strong></summary>

1. 访问 [GitHub Settings → Developer settings → Personal access tokens → Tokens (classic)](https://github.com/settings/tokens/new?scopes=repo,workflow)
2. 点击 **"Generate new token"** → **"Generate new token (classic)"**
3. 填写：
   - **Note**：`terraform-cicd-demo`（或任意描述）
   - **Expiration**：30 days（或你的偏好）
   - **Select scopes**：勾选以下两项：
     - **`repo`**（完全控制私有仓库）
     - **`workflow`**（更新 GitHub Action 工作流）← `.github/workflows/` 必需
4. 点击 **"Generate token"**
5. **⚠️ 立即复制 Token** — 之后无法再次查看！

</details>

<details>
<summary>💼 企业实践：PAT 生命周期管理</summary>

在真实项目中，PAT 管理有严格要求：

| 实践 | 说明 |
|------|------|
| **有效期** | 设置 30-90 天，绝不选择 "No expiration" |
| **定期轮换** | Token 过期前创建新 Token，更新使用位置，删除旧 Token |
| **最小权限** | 只勾选必要的 scope（本实验需要 `repo` + `workflow`）|
| **命名规范** | 包含用途和日期，如 `cicd-demo-2026-01` |
| **及时清理** | 项目结束后立即撤销（Step 14e 会教你如何操作）|

**自动化替代方案**：生产环境推荐使用 GitHub App 或 OIDC 认证代替 PAT。

</details>

```bash
# 存储凭证（首次提示输入，之后记住）
git config --global credential.helper store

# 推送 - 提示时：
#   Username: 你的 GitHub 用户名
#   Password: 粘贴 PAT（不是 GitHub 密码！）
git push -u origin main
```

> **💡 提示**：如果安装了 [GitHub CLI](https://cli.github.com/)，可以运行 `gh auth login` 更简单地设置。

**检查点**：刷新 GitHub 页面——应看到所有文件，包括 `.github/workflows/`。

---

### Step 5：部署 OIDC 基础设施（10 分钟）

OIDC 允许 GitHub Actions 无需存储 Access Key 即可认证 AWS。

```bash
cd ~/my-terraform-cicd/oidc-setup

# 部署 CloudFormation Stack
# 将 YOUR_USERNAME 替换为你的 GitHub 用户名
aws cloudformation deploy \
  --template-file github-oidc.yaml \
  --stack-name github-oidc-terraform \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides \
    GitHubOrg=YOUR_USERNAME \
    RepoName=my-terraform-cicd

# 获取 Role ARN（复制用于下一步）
aws cloudformation describe-stacks \
  --stack-name github-oidc-terraform \
  --query 'Stacks[0].Outputs[?OutputKey==`RoleArn`].OutputValue' \
  --output text
```

**检查点**：应看到类似 `arn:aws:iam::123456789012:role/github-actions-my-terraform-cicd` 的 ARN。

---

### Step 6：配置 GitHub Secret（3 分钟）

将 Role ARN 添加为 GitHub Secret：

1. 访问你的 GitHub 仓库
2. **Settings** > **Secrets and variables** > **Actions**
3. 点击 **New repository secret**
4. Name：`AWS_ROLE_ARN`
5. Value：（粘贴 Step 5 获取的 Role ARN）
6. 点击 **Add secret**

**检查点**：Secrets 页面显示 `AWS_ROLE_ARN` 已配置。

---

### Step 7：启用 GitHub Actions（2 分钟）

<details open>
<summary>💡 什么是 GitHub Actions？</summary>

GitHub Actions 是 GitHub 内置的 CI/CD 工具。它在仓库发生特定事件时（如推送代码、创建 PR）自动运行工作流（脚本）。可以把它想象成一个机器人，监视你的仓库并自动执行命令。

在本实验中，我们配置了两个工作流：
- **Terraform Plan**：PR 创建时自动运行 `terraform plan`
- **Terraform Apply**：合并到 main 后自动运行 `terraform apply`

</details>

1. 访问仓库的 **Actions** 标签页
2. **如果看到提示**要求启用工作流，点击 **"I understand my workflows, go ahead and enable them"**
3. **如果没有提示**且已看到工作流列表（Terraform Plan、Terraform Apply），说明 Actions 已自动启用——直接进入下一步

> **注意**：初次推送时可能会看到一个失败的工作流运行（因为 OIDC 尚未配置）。这是正常的，后续步骤会解决。

**检查点**：应看到 "Terraform Plan" 和 "Terraform Apply" 工作流已列出。

---

### Step 8：配置 Production 环境（5 分钟）

为 Apply 工作流设置审批门禁：

1. 访问 **Settings** > **Environments**
2. 如果已有 `production` 环境，点击它；否则点击 **New environment**
3. Name：`production`（如果是新建）
4. 点击 **Configure environment**（如果是新建）或直接进入配置页面
5. 在 "Deployment protection rules" 下，启用 **Required reviewers**
6. 添加自己为审批者
7. 点击 **Save protection rules**

**检查点**：Environment 页面显示 "1 reviewer required"。

> **日本 IT 职场**：这就是生产部署中使用的**承認フロー**（审批流程）。

---

### Step 9：创建 Feature 分支（3 分钟）

现在通过修改代码来触发 CI/CD 流水线：

```bash
cd ~/my-terraform-cicd

# 创建 feature 分支
git checkout -b feature/add-my-tag
```

编辑 `main.tf`，在 tags 块中添加自定义标签：

```hcl
  tags = {
    Name        = "CI/CD Demo Bucket"
    Environment = var.environment
    # 添加这行：
    MyName = "your-name-here"
  }
```

提交并推送：

```bash
git add main.tf
git commit -m "feat: add MyName tag"
git push -u origin feature/add-my-tag
```

**检查点**：分支在 GitHub 上可见。

---

### Step 10：创建 Pull Request（5 分钟）

1. 访问你的 GitHub 仓库
2. 应看到横幅："feature/add-my-tag had recent pushes"
3. 点击 **Compare & pull request**
4. Title：GitHub 会自动填入 commit message（如 "feat: add MyName tag"），可以保留或修改
5. 点击 **Create pull request**

**检查点**：PR 已创建，"Terraform Plan" 工作流自动开始！

<details>
<summary>🔍 幕后解密：为什么创建 PR 会自动运行 Plan？</summary>

这是 `.github/workflows/terraform-plan.yml` 中的触发器配置：

```yaml
on:
  pull_request:
    branches: [main]
    paths: ['**/*.tf']
```

含义：
- `pull_request` → 有人创建或更新 PR 时触发
- `branches: [main]` → 只针对向 main 分支的 PR
- `paths: ['**/*.tf']` → 只有 `.tf` 文件变更时触发

**这就是 "代码即配置" 的威力**：触发条件写在代码里，透明可审计！

</details>

---

### Step 11：查看 Plan 评论（5 分钟）

等待工作流完成（1-2 分钟），然后：

1. 检查 **Actions** 标签页 —— "Terraform Plan" 应显示绿色勾号
2. 返回你的 PR
3. 应看到 **bot 评论**，包含 plan 结果：
   - Format 检查状态
   - Init 状态
   - Validate 状态
   - Plan 输出（显示你的新标签！）

> **看到 Format ⚠️ 警告？** 这表示代码格式不符合 `terraform fmt` 标准。
> 虽然不影响功能，但生产环境建议在 commit 前运行 `terraform fmt` 自动格式化。

**检查点**：PR 有评论显示 `+ MyName = "your-name-here"` 在 plan 中。

> **这就是 CI/CD 的威力**：每个变更在应用前都被审查！

<details>
<summary>🔍 幕后解密：Bot 评论是从哪里来的？</summary>

这是 `.github/workflows/terraform-plan.yml` 中的 `github-script` 步骤：

```yaml
- uses: actions/github-script@v7
  with:
    script: |
      github.rest.issues.createComment({
        issue_number: context.issue.number,
        owner: context.repo.owner,
        repo: context.repo.repo,
        body: output  // Plan 结果以 Markdown 格式发布
      })
```

含义：
- `github-script` → 使用 GitHub API
- `createComment` → 在 PR 上创建评论
- `output` → 包含 format/init/validate/plan 的执行结果

**关键洞察**：Bot 评论不是 "魔法"，是 workflow 调用 GitHub API 发布的！

</details>

---

### Step 12：合并并观察 Apply（5 分钟）

1. 点击 **Merge pull request** > **Confirm merge**
2. 访问 **Actions** 标签页
3. 会看到 "Terraform Apply" 工作流被触发
4. 工作流**暂停**等待审批

<details>
<summary>🔍 幕后解密：为什么 Merge 后自动运行 Apply？</summary>

这是 `.github/workflows/terraform-apply.yml` 中的触发器配置：

```yaml
on:
  push:
    branches: [main]
```

含义：
- `push` → 有代码推送时触发
- `branches: [main]` → 只针对 main 分支

**PR Merge = 向 main push 代码**，所以触发 Apply workflow！

这是典型的 GitOps 模式：`main 分支 = 生产状态`

</details>

审批部署：

> **审批前应该检查什么？**（日本 IT 实务：本番承認）
> 1. 确认 Plan 输出与预期一致（检查 PR 中的 bot 评论）
> 2. 检查没有意外的资源删除（`-` 开头的行）
> 3. 验证变更范围是否正确
> 4. 在生产环境中，通常需要另一位团队成员审批

1. 点击工作流运行
2. 点击 **Review deployments**
3. 勾选 **production**
4. 点击 **Approve and deploy**

**检查点**：Apply 工作流完成，显示绿色勾号。

<details>
<summary>🔍 幕后解密：为什么需要人工审批？</summary>

这是 `.github/workflows/terraform-apply.yml` 中的 environment 配置：

```yaml
jobs:
  terraform-apply:
    environment: production  # ← 关键！
```

在 Step 8 中，我们为 `production` 环境配置了 "Required reviewers"。

当 workflow 指定 `environment: production` 时：
1. GitHub 检查该环境的 protection rules
2. 如果需要审批，workflow 暂停等待
3. 审批者点击 "Approve" 后继续执行

**这就是 "审批门禁"**：代码和配置共同控制部署流程！

</details>

> **日本 IT 职场**：这就是**本番承認**（生产审批）—— 变更只在人工审核后才应用。

---

### Step 12.5（可选）：体验 CI 失败（5 分钟）

> **学习目标**：理解 CI/CD 如何捕获错误，以及如何修复后重新提交。

这一步是可选的，但强烈建议体验一次——理解 CI 失败比只看成功更有价值！

**故意引入格式错误**：

```bash
cd ~/my-terraform-cicd

# 创建新分支
git checkout -b feature/test-ci-failure

# 故意破坏格式（移除空格）
sed -i 's/Name        =/Name=/' main.tf

# 查看变更
git diff main.tf

# 提交并推送
git add main.tf
git commit -m "test: intentional format error"
git push -u origin feature/test-ci-failure
```

**创建 PR 并观察失败**：

1. 在 GitHub 上为 `feature/test-ci-failure` 创建 PR
2. 等待工作流运行（约 1 分钟）
3. 观察 **Actions** 标签页——工作流显示红色 ❌
4. 查看 PR 评论——bot 会显示 `terraform fmt` 检查失败

**修复并重新推送**：

```bash
# 自动修复格式
terraform fmt

# 提交修复
git add main.tf
git commit -m "fix: correct format"
git push
```

**观察**：返回 PR 页面，工作流重新运行并显示绿色 ✅

**清理**：关闭此 PR（不合并），删除测试分支：

```bash
git checkout main
git branch -D feature/test-ci-failure
git push origin --delete feature/test-ci-failure
```

> **学到了什么**：CI/CD 自动捕获代码问题，你只需修复后重新推送！这就是 CI 的 "安全网" 价值。

---

### Step 13：验证资源（3 分钟）

验证 S3 Bucket 已创建并带有你的标签：

```bash
# 列出匹配模式的 Bucket
aws s3api list-buckets --query "Buckets[?contains(Name, 'cicd-demo')]" --output table

# 从输出获取 Bucket 名称，然后检查标签
aws s3api get-bucket-tagging --bucket cicd-demo-XXXXXXXX
```

**检查点**：应在输出中看到你的 `MyName` 标签！

---

### Step 14：清理（10 分钟）

**重要**：完整清理防止孤儿资源和凭证泄露。

#### 14a. 销毁 Terraform 资源

使用 S3 远程后端，`terraform destroy` 正常工作（State 是持久的）：

```bash
# 确保 AWS 凭证已在本地配置
aws sts get-caller-identity

# 进入 demo 文件夹
cd ~/my-terraform-cicd

# 初始化 Terraform（连接远程 State）
terraform init

# 销毁所有 Terraform 管理的资源
terraform destroy -auto-approve
```

**检查点**：输出显示 `Destroy complete! Resources: X destroyed.`

#### 14b. 删除 OIDC CloudFormation Stack

```bash
# 删除 OIDC Stack
aws cloudformation delete-stack --stack-name github-oidc-terraform

# 等待 Stack 删除完成
aws cloudformation wait stack-delete-complete --stack-name github-oidc-terraform

# 确认 OIDC Provider 已移除
aws iam list-open-id-connect-providers
```

#### 14c. 删除 GitHub 仓库

1. 访问你的 GitHub 仓库 > **Settings**
2. 滚动到底部 **Danger Zone**
3. 点击 **Delete this repository**
4. 输入仓库名称确认
5. 点击 **I understand the consequences, delete this repository**

#### 14d. 清理 Git 凭证（安全）

你使用的 GitHub PAT 存储在本地。移除它：

```bash
# 移除存储的凭证文件
rm ~/.git-credentials 2>/dev/null || true

# 移除 credential helper 配置（Step 4 设置的）
git config --global --unset credential.helper 2>/dev/null || true

# 验证清理
cat ~/.git-credentials 2>/dev/null || echo "Credentials file removed"
git config --global credential.helper 2>/dev/null || echo "Credential helper config removed"
```

#### 14e. 撤销 GitHub PAT（安全！）

**⚠️ 重要**：你创建的 PAT 具有 `repo+workflow` 权限，可以完全控制你的所有仓库。必须撤销！

1. 访问 [GitHub Settings → Developer settings → Personal access tokens](https://github.com/settings/tokens)
2. 找到你在 Step 4 创建的 token（名称类似 `terraform-cicd-demo`）
3. 点击 **Delete** 并确认删除

**检查点**：Token 列表中不再显示该 token。

> **企业实践**：在真实项目中，PAT 应设置有效期（30-90 天），过期前轮换，绝不选择 "No expiration"。

#### 14f. 清理本地文件

```bash
# 移除 demo 文件夹
cd ~
rm -rf ~/my-terraform-cicd
```

**检查点**：所有资源已清理：
- [ ] Terraform 资源已销毁（`terraform destroy`）
- [ ] CloudFormation OIDC Stack 已删除
- [ ] GitHub 仓库已删除
- [ ] Git 凭证文件已移除（`~/.git-credentials`）
- [ ] Git credential helper 配置已移除
- [ ] **GitHub PAT 已撤销**（安全！）
- [ ] 本地 demo 文件夹已移除

---

## 你学到了什么

- **OIDC 认证**：CI/CD 的安全、无密钥认证
- **PR 自动 Plan**：每个变更在应用前都被预览
- **审批门禁**：生产变更需要人工审批
- **CI 失败处理**：理解错误信息，修复后重新推送
- **全自动化**：无需手动 `terraform apply`

---

## 故障排除

### 工作流没有触发？

- 检查 Actions 标签页是否已启用
- 验证 `.github/workflows/` 文件夹已推送

### OIDC 认证失败？

- 验证 `AWS_ROLE_ARN` Secret 设置正确
- 检查 CloudFormation Stack 部署成功
- 确保仓库名称完全匹配（区分大小写）

### Plan 显示错误？

- 检查 AWS 凭证是否工作
- 验证 IAM Role 有所需权限

---

## 下一步

- 再次修改 `main.tf` 查看完整周期
- 探索添加 Infracost 实现成本可见
- 实现 Branch Protection Rules
