# 01 · 安装配置与第一个资源

> **目标**：5 分钟内创建你的第一个 AWS 资源，体验 Terraform 工作流
> **前置**：已完成 [00 · 概念导入](../00-concepts/) 和 [环境准备](../00-concepts/lab-setup.md)
> **时间**：25-30 分钟
> **费用**：S3 Bucket（免费层）

---

## 将学到的内容

1. 体验 `terraform init → plan → apply → destroy` 完整工作流
2. 理解 Terraform 如何追踪资源状态
3. 学会修改配置并观察变更
4. 掌握 `.tf` 文件的基本结构

---

## Step 1 — 快速验证环境（2 分钟）

> 如果尚未部署开发环境，请先完成 [环境准备](../00-concepts/lab-setup.md)。

连接到你的 Terraform Lab 实例：

```bash
# VS Code Remote 用户：已连接则跳过
# SSM 用户：
aws ssm start-session --target i-你的实例ID --region ap-northeast-1
```

验证 Terraform 已安装：

```bash
terraform version
```

```
Terraform v1.14.x
on linux_amd64
```

看到版本号？继续下一步！

---

## Step 2 — 立即体验：创建第一个资源（5 分钟）

> 🎯 **目标**：先"尝到"Terraform 的味道，再理解原理。

### 2.1 进入示例代码目录

```bash
cd ~/cloud-atlas/iac/terraform/01-first-resource/code
ls -la
```

```
.
├── main.tf         # 资源定义
├── providers.tf    # Provider 配置
├── outputs.tf      # 输出值
└── cleanup.sh      # 清理脚本
```

### 2.2 初始化 → 预览 → 创建！

**一气呵成：**

```bash
# 初始化（下载 Provider）
terraform init

# 预览变更
terraform plan

# 创建资源！
terraform apply
```

当看到这个提示时，输入 `yes`：

```
Do you want to perform these actions?
  Enter a value: yes
```

**观察输出：**

```
random_id.bucket_suffix: Creating...
random_id.bucket_suffix: Creation complete after 0s
aws_s3_bucket.first_bucket: Creating...
aws_s3_bucket.first_bucket: Creation complete after 2s
aws_s3_bucket_versioning.first_bucket: Creating...
aws_s3_bucket_versioning.first_bucket: Creation complete after 1s

Apply complete! Resources: 3 added, 0 changed, 0 destroyed.

Outputs:

bucket_name = "my-first-terraform-bucket-a1b2c3d4"
```

### 2.3 验证资源存在

```bash
aws s3 ls | grep my-first-terraform
```

```
2025-xx-xx xx:xx:xx my-first-terraform-bucket-a1b2c3d4
```

🎉 **恭喜！你刚刚用 Terraform 创建了一个 S3 Bucket！**

---

## Step 3 — 发生了什么？（5 分钟）

现在你已经"尝到"了 Terraform，让我们理解刚才发生了什么。

### 3.1 三个命令，三个阶段

![Terraform Workflow](images/terraform-workflow.png)

<details>
<summary>View ASCII source</summary>

```
┌──────────────────┐      ┌──────────────────┐      ┌──────────────────┐
│  terraform init  │      │  terraform plan  │      │ terraform apply  │
│                  │ ───▶ │                  │ ───▶ │                  │
│  下载 Provider   │      │  对比代码与      │      │  调用 AWS API    │
│  准备工作目录    │      │  当前状态        │      │  创建资源        │
└──────────────────┘      └────────┬─────────┘      └────────┬─────────┘
                                   │                         │
                                   ▼                         │
                          ┌──────────────────┐               │
                          │terraform.tfstate │ ◀─── 更新状态 ─┘
                          └──────────────────┘
```

</details>

### 3.2 新生成的文件

```bash
ls -la
```

| 文件 | 作用 | Git? |
|------|------|------|
| `.terraform/` | Provider 插件 | ❌ 不提交 |
| `.terraform.lock.hcl` | 版本锁定 | ✅ 提交 |
| `terraform.tfstate` | 资源状态 | ❌ 不提交（敏感！） |

### 3.3 状态文件 = Terraform 的记忆

```bash
terraform state list
```

```
random_id.bucket_suffix
aws_s3_bucket.first_bucket
aws_s3_bucket_versioning.first_bucket
```

Terraform 通过状态文件知道它管理着哪些资源。

---

## Step 4 — 动手实验：修改配置（8 分钟）

> 🎯 **目标**：修改代码，观察 Terraform 如何处理变更。

### 4.1 添加一个标签

编辑 `main.tf`：

```bash
vim main.tf   # 或用 VS Code
```

找到 `tags` 块，添加 `Owner` 标签：

```hcl
  tags = {
    Name        = "My First Terraform Bucket"
    Environment = "learning"
    Purpose     = "Terraform 课程练习"
    Owner       = "your-name"              # ← 添加这行
  }
```

### 4.2 预览变更

```bash
terraform plan
```

**观察输出：**

```
  # aws_s3_bucket.first_bucket will be updated in-place
  ~ resource "aws_s3_bucket" "first_bucket" {
      ~ tags     = {
          + "Owner" = "your-name"
            # (3 unchanged elements hidden)
        }
    }

Plan: 0 to add, 1 to change, 0 to destroy.
```

注意符号：
- `~` = 修改（不是重建）
- `+` = 新增属性
- `0 to add, 1 to change` = 增量更新

### 4.3 应用变更

```bash
terraform apply
```

输入 `yes`，观察：只修改了标签，没有重建 Bucket。

### 4.4 验证

```bash
aws s3api get-bucket-tagging --bucket $(terraform output -raw bucket_name)
```

```json
{
    "TagSet": [
        { "Key": "Owner", "Value": "your-name" },
        ...
    ]
}
```

### 4.5 思考题

> ❓ 如果你直接在 AWS Console 修改标签，再运行 `terraform plan`，会发生什么？
>
> 试试看！这就是 **Drift（漂移）** — [Lesson 10](../10-drift/) 会深入讲解。

---

## Step 5 — 理解代码结构（8 分钟）

现在你知道 Terraform 能做什么了，让我们看看代码怎么写的。

### 5.1 providers.tf — 用什么工具？

```bash
cat providers.tf
```

```hcl
terraform {
  required_version = ">= 1.9.0, < 2.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"  # AWS Provider 6.x available with breaking changes - see upgrade guide
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

provider "aws" {
  region = "ap-northeast-1"           # 东京区域
}
```

**要点**：声明需要 AWS Provider 和 Random Provider。

### 5.2 main.tf — 创建什么资源？

```bash
cat main.tf
```

```hcl
resource "random_id" "bucket_suffix" {
  byte_length = 4                     # 生成随机后缀
}

resource "aws_s3_bucket" "first_bucket" {
  bucket = "my-first-terraform-bucket-${random_id.bucket_suffix.hex}"
  tags   = { ... }
}

resource "aws_s3_bucket_versioning" "first_bucket" {
  bucket = aws_s3_bucket.first_bucket.id    # 引用上面的 bucket
  versioning_configuration {
    status = "Enabled"
  }
}
```

**要点**：

| 语法 | 含义 |
|------|------|
| `resource "类型" "名称"` | 定义资源 |
| `${random_id.xxx.hex}` | 引用其他资源的属性 |
| `aws_s3_bucket.first_bucket.id` | 资源引用格式 |

**依赖关系自动推断**：

```
random_id ──► aws_s3_bucket ──► aws_s3_bucket_versioning
```

### 5.3 outputs.tf — 输出什么？

```bash
cat outputs.tf
```

```hcl
output "bucket_name" {
  value = aws_s3_bucket.first_bucket.bucket
}
```

**用途**：脚本读取 `terraform output -raw bucket_name`

<details>
<summary>📖 更多代码细节（点击展开）</summary>

**版本约束语法**：

| 语法 | 含义 |
|------|------|
| `= 5.0.0` | 精确版本 |
| `>= 5.0` | 最低版本 |
| `~> 5.0` | 5.x（推荐） |

**资源块结构**：

```hcl
resource "资源类型" "本地名称" {
  参数 = 值
}
```

</details>

---

## Step 6 — 清理资源（3 分钟）

> ⚠️ **重要**：完成学习后，立即清理！

```bash
terraform destroy
```

输入 `yes`：

```
Destroy complete! Resources: 3 destroyed.
```

验证：

```bash
aws s3 ls | grep my-first-terraform
# 无输出 = 已删除
```

---

## 本课小结

| 命令 | 作用 | 你学到了 |
|------|------|----------|
| `terraform init` | 下载 Provider | 准备工作环境 |
| `terraform plan` | 预览变更 | 看懂 `+` `~` `-` 符号 |
| `terraform apply` | 创建/修改资源 | 增量更新 |
| `terraform destroy` | 删除资源 | 清理环境 |

**核心理念**：

```
代码 (.tf)  ──plan──►  对比  ──apply──►  AWS API  ──►  真实资源
                        ▲                              │
                        └────────── State ◄────────────┘
```

---

## 下一步

状态文件（`terraform.tfstate`）还在本地——这对团队协作是个问题。

→ [02 · 状态管理与远程后端](../02-state/)

---

## 面试准备

💼 **よくある質問**

**Q: terraform plan と apply の違いは？**

A: `plan` は Dry Run（実行なし）、`apply` は実際にリソースを作成。本番では必ず `plan` → レビュー → `apply`。

**Q: State ファイルの役割は？**

A: 管理リソースの現在状態を記録。`plan` 時にコードと比較して差分を計算。

**Q: なぜ State を Git にコミットしない？**

A: 機密情報（パスワード等）が含まれる可能性。リモート State（S3）を使う。

---

## トラブルシューティング

🔧 **よくある問題**

**`terraform init` 失敗**

```bash
curl -I https://registry.terraform.io  # ネットワーク確認
```

**`apply` で Access Denied**

```bash
aws sts get-caller-identity  # IAM 確認
```

**Bucket 名重複**

→ `random_id` が生成するので通常は発生しない。発生したら再実行。

---

## 系列导航

← [00 · 概念导入](../00-concepts/) | [Home](../) | [02 · 状態管理 →](../02-state/)
