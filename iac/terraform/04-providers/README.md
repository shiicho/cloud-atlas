# 04 · Provider 策略与版本管理

> **目标**：掌握 Provider 版本约束与多区域配置
> **前置**：已完成 [03 · HCL 语法与资源建模](../03-hcl/)
> **时间**：30-35 分钟
> **费用**：S3 Bucket（免费层）

---

## 将学到的内容

1. 理解 `required_providers` 配置
2. 掌握版本约束语法（`~>`, `>=`, `=`）
3. 理解 `.terraform.lock.hcl` 的作用
4. 完成 Provider 升级流程
5. 配置多区域 Provider（alias）

---

## Step 1 — 快速验证环境（2 分钟）

连接到你的 Terraform Lab 实例：

```bash
# VS Code Remote 用户：已连接则跳过
aws ssm start-session --target i-你的实例ID --region ap-northeast-1
```

确认 Terraform 版本：

```bash
terraform version
```

```
Terraform v1.9.x
on linux_amd64
```

---

## Step 2 — 立即体验：版本锁定机制（5 分钟）

> 先"尝到" Provider 版本管理的重要性。

### 2.1 进入示例代码目录

```bash
cd ~/cloud-atlas/iac/terraform/04-providers/code
ls -la
```

```
.
├── main.tf              # 简单 S3 资源
├── providers.tf         # Provider 配置（版本约束）
├── multi-region.tf      # 多区域 Provider alias
└── outputs.tf           # 输出值
```

### 2.2 初始化并观察锁文件

```bash
terraform init
```

观察生成的 `.terraform.lock.hcl`：

```bash
cat .terraform.lock.hcl
```

```hcl
provider "registry.terraform.io/hashicorp/aws" {
  version     = "5.82.2"
  constraints = "~> 5.0"
  hashes = [
    "h1:xxx...",
    "zh:xxx...",
  ]
}
```

**关键信息**：

| 字段 | 含义 |
|------|------|
| `version` | 实际安装的精确版本 |
| `constraints` | 代码中声明的约束 |
| `hashes` | Provider 二进制的校验和 |

### 2.3 为什么这个文件很重要？

```bash
# 查看 Provider 版本
terraform providers
```

```
Providers required by configuration:
.
├── provider[registry.terraform.io/hashicorp/aws] ~> 5.0
```

**没有锁文件时**：每次 `init` 可能下载不同版本

**有锁文件时**：团队成员使用完全相同的版本

---

## Step 3 — 发生了什么？（5 分钟）

### 3.1 版本约束语法

```hcl
required_providers {
  aws = {
    source  = "hashicorp/aws"
    version = "~> 5.0"    # 版本约束
  }
}
```

| 语法 | 含义 | 允许范围 |
|------|------|----------|
| `= 5.0.0` | 精确版本 | 只能 5.0.0 |
| `>= 5.0` | 最低版本 | 5.0, 5.1, 6.0... |
| `~> 5.0` | 悲观约束 | 5.x（不超过 6.0） |
| `~> 5.0.0` | 更严格 | 5.0.x（不超过 5.1） |
| `>= 5.0, < 6.0` | 范围 | 5.0 到 5.x |

### 3.2 版本约束流程

![terraform init 流程](images/init-flow.png)

<details>
<summary>View ASCII source</summary>

```
                    ┌─────────────────┐
                    │  terraform init │
                    └────────┬────────┘
                             ▼
                ┌────────────────────────┐
                │       Step 1           │
                │  required_providers    │
                │  (version constraints) │
                └────────────┬───────────┘
                             ▼
                ┌────────────────────────┐
                │       Step 2           │
                │  .terraform.lock.hcl   │
                │   (locked version)     │
                └─────┬──────┬──────┬────┘
                      │      │      │
          ┌───────────┘      │      └───────────┐
          ▼                  ▼                  ▼
  ┌───────────────┐  ┌──────────────┐  ┌────────────────┐
  │lock.hcl exists│  │ No lock file │  │Version mismatch│
  └───────┬───────┘  └──────┬───────┘  └───────┬────────┘
          ▼                  ▼                  ▼
  ┌───────────────┐  ┌──────────────┐  ┌────────────────┐
  │Use locked ver │  │Download latest│  │-upgrade needed │
  └───────────────┘  └──────────────┘  └────────────────┘
```

</details>

### 3.3 锁文件的 Git 策略

| 文件 | Git 提交？ | 原因 |
|------|------------|------|
| `.terraform.lock.hcl` | **是** | 确保团队一致性 |
| `.terraform/` | **否** | 可重建的缓存 |
| `terraform.tfstate` | **否** | 敏感信息，用远程后端 |

---

## Step 4 — 动手实验：Provider 升级（10 分钟）

> 体验安全的 Provider 升级流程。

### 4.1 查看当前版本

```bash
terraform version -json | jq '.provider_selections'
```

```json
{
  "registry.terraform.io/hashicorp/aws": "5.82.2"
}
```

### 4.2 查看可用版本

```bash
# 使用 Terraform Registry 查看
curl -s "https://registry.terraform.io/v1/providers/hashicorp/aws/versions" | \
  jq '.versions[-5:][].version'
```

### 4.3 升级 Provider

```bash
# 在约束范围内升级到最新版本
terraform init -upgrade
```

```
Upgrading provider plugin registry.terraform.io/hashicorp/aws...
- Finding hashicorp/aws versions matching "~> 5.0"...
- Installing hashicorp/aws v5.83.0...
```

### 4.4 验证无破坏性变更

```bash
# 升级后必须运行 plan 确认
terraform plan
```

```
No changes. Your infrastructure matches the configuration.
```

如果 plan 显示意外变更：

1. 查看变更详情
2. 检查 Provider changelog
3. 决定是否接受或回滚

### 4.5 锁文件已更新

```bash
git diff .terraform.lock.hcl
```

```diff
- version     = "5.82.2"
+ version     = "5.83.0"
```

**提交锁文件更新**：

```bash
git add .terraform.lock.hcl
git commit -m "chore: upgrade aws provider to 5.83.0"
```

---

## Step 5 — 动手实验：多区域 Provider（10 分钟）

> 配置 Provider alias 实现多区域部署。

### 5.1 查看多区域配置

```bash
cat multi-region.tf
```

```hcl
# 默认 Provider（东京）
provider "aws" {
  region = "ap-northeast-1"
}

# 别名 Provider（大阪）
provider "aws" {
  alias  = "osaka"
  region = "ap-northeast-3"
}
```

### 5.2 资源指定 Provider

```hcl
# 使用默认 Provider（东京）
resource "aws_s3_bucket" "tokyo" {
  bucket = "demo-tokyo-${random_id.suffix.hex}"
}

# 使用 alias Provider（大阪）
resource "aws_s3_bucket" "osaka" {
  provider = aws.osaka
  bucket   = "demo-osaka-${random_id.suffix.hex}"
}
```

### 5.3 创建多区域资源

```bash
terraform apply -auto-approve
```

```
Outputs:

tokyo_bucket = "demo-tokyo-a1b2c3d4"
osaka_bucket = "demo-osaka-a1b2c3d4"
```

验证区域：

```bash
# 东京
aws s3api get-bucket-location --bucket $(terraform output -raw tokyo_bucket)
# {"LocationConstraint": "ap-northeast-1"}

# 大阪
aws s3api get-bucket-location --bucket $(terraform output -raw osaka_bucket)
# {"LocationConstraint": "ap-northeast-3"}
```

### 5.4 多 Provider 应用场景

| 场景 | Provider 配置 |
|------|---------------|
| 多区域灾备 | `alias = "dr"` |
| 多账户管理 | `alias = "prod"` + assume_role |
| 混合云 | aws + azurerm + google |

---

## Step 6 — 深入理解：Terraform 版本约束（5 分钟）

### 6.1 required_version

```hcl
terraform {
  # Terraform CLI 版本约束
  required_version = ">= 1.5.0, < 2.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}
```

### 6.2 版本不匹配时

```bash
# 如果 Terraform 版本不满足约束
terraform init
```

```
Error: Unsupported Terraform Core version

  on providers.tf line 2, in terraform:
   2:   required_version = ">= 1.5.0, < 2.0.0"

This configuration does not support Terraform version 1.4.0.
```

### 6.3 最佳实践

```hcl
terraform {
  # 推荐：设置上下限，避免跨大版本
  required_version = ">= 1.5.0, < 2.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      # 推荐：使用 ~> 允许 patch 更新
      version = "~> 5.0"
    }
  }
}
```

---

## Step 7 — 清理资源（2 分钟）

```bash
cd ~/cloud-atlas/iac/terraform/04-providers/code
terraform destroy -auto-approve
```

```
Destroy complete! Resources: 3 destroyed.
```

---

## 本课小结

| 概念 | 说明 |
|------|------|
| `required_providers` | 声明需要的 Provider 及版本 |
| `~> 5.0` | 悲观约束（5.x，不超过 6.0） |
| `.terraform.lock.hcl` | 锁定精确版本，**提交到 Git** |
| `-upgrade` | 在约束范围内升级 |
| `alias` | 配置多个同类 Provider |

**升级安全流程**：

```
1. terraform init -upgrade
2. terraform plan（确认无破坏性变更）
3. git commit .terraform.lock.hcl
```

---

## 下一步

Provider 配置好了，但代码中还有很多硬编码值。

→ [05 · 变量系统](../05-variables/)

---

## 面试准备

**よくある質問**

**Q: Provider バージョン固定が重要な理由は？**

A: 再現性確保、予期しない Breaking Change 防止、チーム間の一貫性。`.terraform.lock.hcl` を Git にコミットすることで、全員が同じバージョンを使用。

**Q: ~> 5.0 と ~> 5.0.0 の違いは？**

A: `~> 5.0` は 5.x まで許可（5.1, 5.2...）、`~> 5.0.0` は 5.0.x まで許可（5.0.1, 5.0.2...）。前者は Minor バージョン更新を許可、後者は Patch のみ。

**Q: Provider alias の用途は？**

A: 同じ Provider を複数設定する場合。例えば multi-region（東京と大阪）、multi-account（本番と開発）。resource で `provider = aws.alias_name` を指定して使い分ける。

**Q: Provider 更新時のベストプラクティスは？**

A: 1) `terraform init -upgrade`、2) `terraform plan` で差分確認、3) Changelog を確認、4) `.terraform.lock.hcl` をコミット。本番では慎重に。

---

## トラブルシューティング

**よくある問題**

**Provider バージョン不一致**

```
Error: Failed to query available provider packages
```

```bash
# ロックファイルを更新
terraform init -upgrade
```

**Multi-platform チームで hash 不一致**

```bash
# 複数 OS 用の hash を生成
terraform providers lock -platform=linux_amd64 -platform=darwin_arm64
```

**古い Provider で API 変更**

```
Error: Invalid attribute "xxx" for resource
```

→ Provider のバージョンが古すぎる。`-upgrade` で更新するか、バージョン制約を確認。

---

## 系列导航

← [03 · HCL 语法](../03-hcl/) | [Home](../) | [05 · 変数系统 →](../05-variables/)
