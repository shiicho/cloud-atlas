# 02 · 状态管理与远程后端

> **目标**：理解 State 的作用，配置 S3 远程后端，体验团队协作场景  
> **前置**：已完成 [01 · 安装配置与第一个资源](../01-first-resource/)  
> **时间**：30-35 分钟  
> **费用**：S3 Bucket（免费层）

> **Note**: Terraform 1.10+ 使用 S3 原生锁定（`use_lockfile = true`），无需 DynamoDB。

---

## 将学到的内容

1. 理解 State 文件的作用与重要性
2. 体验 Local State 在团队场景中的问题
3. 配置 S3 远程后端（原生 S3 锁定）
4. 理解 State Locking 机制
5. 完成 Local → Remote 状态迁移

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
cd ~/cloud-atlas/iac/terraform/01-first-resource/code
terraform state list
```

如果有输出，先清理：

```bash
terraform destroy -auto-approve
```

---

## Step 2 — 体验问题：Local State 的陷阱（5 分钟）

> 先"尝到"Local State 的问题，再学习解决方案。

### 2.1 创建资源（使用 Local State）

```bash
cd ~/cloud-atlas/iac/terraform/02-state/code
terraform init
terraform apply -auto-approve
```

```
Apply complete! Resources: 3 added, 0 changed, 0 destroyed.

Outputs:

bucket_arn = "arn:aws:s3:::state-demo-a1b2c3d4"
bucket_name = "state-demo-a1b2c3d4"
```

### 2.2 检查 State 文件

```bash
ls -la
```

```
-rw-r--r-- 1 ec2-user ... terraform.tfstate
-rw-r--r-- 1 ec2-user ... terraform.tfstate.backup
```

查看 State 内容：

```bash
cat terraform.tfstate | head -30
```

```json
{
  "version": 4,
  "terraform_version": "1.14.x",
  "resources": [
    {
      "type": "aws_s3_bucket",
      "name": "demo",
      ...
    }
  ]
}
```

**问题来了**：这个文件只在你的机器上。

### 2.3 模拟团队冲突（思想实验）

想象这个场景：

![Local State Conflict](images/local-state-conflict.png)

<details>
<summary>View ASCII source</summary>

```
┌─────────────────┐          ┌─────────────────┐
│    开发者 A      │          │    开发者 B      │
│                 │          │                 │
│  ┌───────────┐  │          │  ┌───────────┐  │
│  │  tfstate  │  │          │  │  tfstate  │  │
│  │(version 1)│  │          │  │(version 1)│  │
│  └───────────┘  │          │  └───────────┘  │
└────────┬────────┘          └────────┬────────┘
         │                            │
         ▼                            ▼
      apply                        apply
       同时                          同时
         │                            │
         └──────────┬─────────────────┘
                    ▼
         ┌─────────────────────┐
         │        AWS          │
         │                     │
         │  谁的修改会生效?     │
         │  谁的 State 会被覆盖? │
         └─────────────────────┘
```

</details>

**Local State 的致命问题**：

| 问题 | 后果 |
|------|------|
| 无锁机制 | 并发 apply 相互覆盖 |
| 无共享 | 每人一份 State，各行其是 |
| 敏感信息 | State 可能包含密码，本地存储不安全 |

---

## Step 3 — 体验解决方案：S3 远程后端（10 分钟）

> 现在让我们看看正确的做法。

### 3.1 获取远程后端 Bucket

好消息！在 [环境准备](../00-concepts/lab-setup.md) 时，CloudFormation 已经为你创建了 S3 State Bucket。

获取 bucket 名称：

```bash
# 从 CloudFormation 输出获取
aws cloudformation describe-stacks \
  --stack-name terraform-lab \
  --query 'Stacks[0].Outputs[?OutputKey==`TfStateBucketName`].OutputValue' \
  --output text
```

```
tfstate-terraform-course-123456789012
```

记下这个 bucket 名称！

> **为什么用 CloudFormation 预置？**  
>  
> 这是"鸡生蛋"问题的标准解法：State Bucket 本身不能用 Terraform 管理  
> （否则它的 State 存哪里？），所以用 CloudFormation 或手动创建。

### 3.2 配置远程后端

现在，让我们把刚才创建的 Local State 迁移到 S3 远程后端。

查看 `providers.tf` 中的后端配置模板：

```bash
cat providers.tf
```

你会看到被注释的 backend 块：

```hcl
# backend "s3" {
#   bucket       = "tfstate-terraform-course-你的账户ID"  # 替换为实际值
#   key          = "lesson-02/terraform.tfstate"
#   region       = "ap-northeast-1"
#   encrypt      = true
#   use_lockfile = true  # Terraform 1.10+ 原生 S3 锁定
# }
```

编辑并取消注释，填入你的 bucket 名称：

```bash
vim providers.tf   # 或使用 VS Code
```

> **提示**：检查 Terraform 版本：`terraform version`（需要 1.10+）

### 3.3 迁移到远程后端

重新初始化（Terraform 会检测 backend 变化）：

```bash
terraform init
```

```
Initializing the backend...
Do you want to copy existing state to the new backend?
  Enter a value: yes
```

输入 `yes`，Terraform 会自动迁移 State。

### 3.4 验证远程 State

```bash
# 本地 State 文件可能仍存在，但已被清空（只剩空对象）
cat terraform.tfstate

# 验证远程 State 已创建
aws s3 ls s3://你的bucket名称/lesson-02/
```

```
2025-xx-xx xx:xx:xx     xxxx terraform.tfstate
```

---

## Step 4 — 发生了什么？（5 分钟）

### 4.1 远程后端架构

![Remote Backend Architecture](images/remote-backend.png)

<details>
<summary>View ASCII source</summary>

<!-- DIAGRAM: remote-backend-architecture -->
```
┌─────────────┐          ┌─────────────┐
│ Developer A │          │ Developer B │
└──────┬──────┘          └──────┬──────┘
       │                        │
       └───────────┬────────────┘
                   ▼
    ┌─────────────────────────────────┐
    │          S3 Bucket              │
    │  ┌───────────────────────────┐  │
    │  │ terraform.tfstate (shared)│  │
    │  └───────────────────────────┘  │
    │                                 │
    │  ┌───────────────────────────┐  │
    │  │ terraform.tfstate.tflock  │  │
    │  │ (原生锁文件)               │  │
    │  └───────────────────────────┘  │
    └────────────────┬────────────────┘
                     │
                     ▼
          ┌───────────────────┐
          │   AWS Resources   │
          └───────────────────┘
```
<!-- /DIAGRAM -->

</details>

### 4.2 State Locking 机制

当你运行 `terraform apply`：

```
1. 获取锁（S3 条件写入 .tflock 文件）
   → 如果已锁定，等待或失败

2. 读取 State（S3）
   → 获取最新资源状态

3. 执行变更
   → 调用 AWS API

4. 写入 State（S3）
   → 更新资源状态

5. 释放锁（删除 .tflock 文件）
   → 允许下一个操作
```

> **技术细节**：S3 原生锁定使用 `If-None-Match` 条件写入创建 `.tflock` 文件，  
> 实现简洁的分布式锁机制。

### 4.3 State 文件内容解剖

```bash
# 从 S3 下载查看（替换为你的 bucket 名称）
aws s3 cp s3://你的bucket名称/lesson-02/terraform.tfstate - | head -50
```

State 文件包含：

| 字段 | 内容 | 敏感？ |
|------|------|--------|
| `version` | State 格式版本 | 否 |
| `terraform_version` | Terraform 版本 | 否 |
| `resources` | 资源映射 | **可能！** |
| `outputs` | 输出值 | **可能！** |

> **安全警告**：State 可能包含数据库密码、API 密钥等敏感信息！

---

## Step 5 — 动手实验：体验锁机制（8 分钟）

> 亲自感受 State Locking 如何防止冲突。

### 5.1 修改配置启用延时

编辑 `main.tf`，将 `time_sleep` 的 `create_duration` 改为 `"30s"`：

```bash
vim main.tf
```

找到这行并修改：

```hcl
resource "time_sleep" "wait" {
  create_duration = "30s"  # 从 "0s" 改为 "30s"
  ...
}
```

### 5.2 打开两个终端

**终端 1** 和 **终端 2** 都进入同一目录：

```bash
cd ~/cloud-atlas/iac/terraform/02-state/code
```

### 5.3 模拟并发 Apply

**终端 1**：

```bash
terraform apply -auto-approve
```

立即在 **终端 2** 执行：

```bash
terraform apply -auto-approve
```

**终端 2 输出：**

```
Error: Error acquiring the state lock

Error message: operation error S3: PutObject, https response error
StatusCode: 412, PreconditionFailed: At least one of the pre-conditions
you specified did not hold

Lock Info:
  ID:        xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
  Path:      tfstate-xxx/lesson-02/terraform.tfstate
  Operation: OperationTypeApply
  Who:       ec2-user@ip-10-0-1-xxx
  Version:   1.14.x
  Created:   2025-xx-xx xx:xx:xx.xxx UTC
```

**State Locking 生效了！** 第二个 apply 被阻止。

### 5.4 查看锁状态

```bash
# 替换为你的 bucket 名称
aws s3 ls s3://你的bucket名称/lesson-02/
```

运行中会看到 `.tflock` 文件；完成后锁文件会被删除。

### 5.5 恢复配置

演示完成后，记得将 `create_duration` 改回 `"0s"`：

```bash
vim main.tf
# 将 "30s" 改回 "0s"
terraform apply -auto-approve
```

---

## Step 6 — 深入理解 State（8 分钟）

### 6.1 为什么不能 commit State 到 Git？

State 文件可能包含：

- 数据库密码（明文）
- API 密钥
- 私钥内容
- 其他敏感输出

**即使设置 `sensitive = true`**，数据仍然存在于 State 中！

```hcl
# 代码中标记为敏感
output "db_password" {
  value     = random_password.db.result
  sensitive = true   # 只是屏蔽 CLI 输出
}

# 但 State 中仍是明文！
```

### 6.2 State 操作命令

| 命令 | 用途 | 场景 |
|------|------|------|
| `terraform state list` | 列出资源 | 查看管理的资源 |
| `terraform state show <resource>` | 显示详情 | 调试资源属性 |
| `terraform state mv` | 移动/重命名 | 重构代码 |
| `terraform state rm` | 取消管理 | 移交资源 |
| `terraform state pull` | 下载 State | 备份 |
| `terraform state push` | 上传 State | 恢复（危险！） |

```bash
# 列出所有资源
terraform state list

# 查看资源详情
terraform state show aws_s3_bucket.demo
```

### 6.3 State 版本控制（S3 Versioning）

```bash
# 查看 State 历史版本（替换为你的 bucket 名称）
aws s3api list-object-versions \
  --bucket 你的bucket名称 \
  --prefix lesson-02/terraform.tfstate
```

S3 Versioning 提供 State 的历史记录，可用于：

- 审计变更
- 灾难恢复
- 回滚（需谨慎）

> **深入学习**：State 版本恢复的实战操作，请参考 [16 · 監査対応と設計書](../16-jp-audit/)

---

## Step 7 — 清理资源（3 分钟）

> 完成学习后，立即清理本课创建的资源！

```bash
cd ~/cloud-atlas/iac/terraform/02-state/code
terraform destroy -auto-approve
```

**S3 State Bucket 怎么办？**

- **保留**：后续课程继续使用（**推荐**）
- Bucket 由 `terraform-lab` CloudFormation 栈管理
- 当你完成整个课程，删除 `terraform-lab` 栈时会一起删除

> **注意**：如果 Bucket 中有 State 文件，需要先清空才能删除栈：  
> ```bash  
> # 获取 bucket 名称  
> BUCKET=$(aws cloudformation describe-stacks --stack-name terraform-lab \  
>   --query 'Stacks[0].Outputs[?OutputKey==`TfStateBucketName`].OutputValue' --output text)  
>  
> # 清空 bucket（包括所有版本）  
> aws s3 rm s3://$BUCKET --recursive  
> aws s3api delete-objects --bucket $BUCKET \  
>   --delete "$(aws s3api list-object-versions --bucket $BUCKET \  
>   --query '{Objects: Versions[].{Key:Key,VersionId:VersionId}}')" 2>/dev/null || true  
> ```

---

## 本课小结

| 概念 | 说明 |
|------|------|
| **State** | Terraform 的"记忆"，记录资源现状 |
| **Local State** | 单机使用，不适合团队 |
| **Remote Backend** | S3 存储 + 锁定机制 |
| **State Locking** | 防止并发修改冲突 |

**反模式警告**：

| 不要这样做 | 为什么 |
|------------|--------|
| commit tfstate 到 Git | 敏感信息泄露 |
| 团队使用 Local State | 状态覆盖风险 |
| 共享 .terraform 目录 | 环境污染 |
| 不启用 State Locking | 并发冲突 |

---

## 下一步

State 安全存储了，但配置中还有硬编码的值。

→ [03 · HCL 语法与资源建模](../03-hcl/)

---

## 面试准备

**よくある質問**

**Q: State ファイルとは何ですか？なぜ重要？**

A: Terraform が管理するリソースの現在状態を記録するファイル。Drift 検出、依存関係追跡、チーム協業に必須。State なしでは Terraform はリソースの存在を認識できない。

**Q: State Locking の目的は？**

A: 同時 apply による競合防止。排他ロックを実現し、一人が apply 中は他の apply をブロック。

**Q: State Locking の実装方法は？**

A: S3 バックエンドで `use_lockfile = true` を設定。S3 の条件付き書き込み機能を使い、`.tflock` ファイルで排他ロックを実現。シンプルで追加コストなし。

**Q: なぜ State を Git にコミットしない？**

A: 機密情報（パスワード、API キー等）が含まれる可能性。sensitive = true でも State には平文で保存される。S3 + IAM でアクセス制御するのがベストプラクティス。

**Q: State が壊れたらどうする？**

A: S3 Versioning で過去バージョンに復旧。または terraform state pull でバックアップしておく。

---

## トラブルシューティング

**よくある問題**

**State Lock が解放されない**

```bash
# 锁文件を確認（替换为你的 bucket 名称）
aws s3 ls s3://你的bucket名称/lesson-02/ | grep tflock

# 強制解除（危険！他に apply 中でないことを確認）
terraform force-unlock <LOCK_ID>
```

**Backend 設定変更時のエラー**

```bash
# backend を変更した場合は -reconfigure
terraform init -reconfigure

# または migrate（State を新しい場所にコピー）
terraform init -migrate-state
```

**S3 Access Denied**

```bash
# IAM 権限を確認
aws sts get-caller-identity

# Bucket policy を確認
aws s3api get-bucket-policy --bucket tfstate-xxx
```

---

## 系列导航

← [01 · 第一个资源](../01-first-resource/) | [Home](../) | [03 · HCL 语法 →](../03-hcl/)
