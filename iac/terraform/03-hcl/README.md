# 03 · HCL 语法与资源建模

> **目标**：掌握 HCL 语法结构，理解资源依赖与 Lifecycle
> **前置**：已完成 [02 · 状态管理与远程后端](../02-state/)
> **时间**：35-40 分钟
> **费用**：VPC + Subnet + Security Group（免费层）

---

## 将学到的内容

1. 掌握 HCL 语法结构（blocks, arguments, expressions）
2. 使用 Data Sources 查询现有资源
3. 理解隐式依赖 vs 显式依赖
4. 使用 Lifecycle 控制资源行为
5. 观察资源创建/销毁顺序

---

## Step 1 — 快速验证环境（2 分钟）

连接到你的 Terraform Lab 实例：

```bash
# VS Code Remote 用户：已连接则跳过
# SSM 用户：
aws ssm start-session --target i-你的实例ID --region ap-northeast-1
```

确认上一课的资源已清理：

```bash
cd ~/cloud-atlas/iac/terraform/02-state/code/02-s3-backend
terraform state list
# 如果有资源，先清理（保留后端基础设施）
```

---

## Step 2 — 立即体验：构建 VPC 网络（5 分钟）

> 先"尝到" HCL 的味道，再理解语法细节。

### 2.1 进入示例代码目录

```bash
cd ~/cloud-atlas/iac/terraform/03-hcl/code
ls -la
```

```
.
├── main.tf           # 主资源定义（VPC/Subnet/SG）
├── data.tf           # Data Sources
├── providers.tf      # Provider 配置
├── outputs.tf        # 输出值
└── lifecycle-demo.tf # Lifecycle 演示
```

### 2.2 初始化并创建资源

```bash
terraform init
terraform plan
```

观察 Plan 输出的创建顺序提示：

```
# aws_vpc.main will be created
# aws_subnet.public will be created
# aws_security_group.web will be created
```

创建资源：

```bash
terraform apply -auto-approve
```

```
Apply complete! Resources: 4 added, 0 changed, 0 destroyed.

Outputs:

vpc_id          = "vpc-0a1b2c3d4e5f6g7h8"
subnet_id       = "subnet-0a1b2c3d4e5f6g7h8"
security_group_id = "sg-0a1b2c3d4e5f6g7h8"
az_used         = "ap-northeast-1a"
```

### 2.3 验证依赖关系

```bash
terraform graph | grep -E "(vpc|subnet|security)"
```

你会看到资源之间的依赖箭头——这是 Terraform 自动推断的。

---

## Step 3 — 发生了什么？（5 分钟）

### 3.1 HCL 基本结构

![HCL Block Structure](images/hcl-block-structure.png)

<details>
<summary>View ASCII source</summary>

```
    ● Block Type   ● Labels        ● Arguments    ● Nested Block
    ──────────────────────────────────────────────────────────────

    resource "aws_instance" "web" {
      ami           = "ami-0c55b159cbfafe1f0"
      instance_type = "t2.micro"

      tags = {
        Name = "HelloWorld"
      }
    }
```

</details>

### 3.2 资源块解剖

```hcl
resource "aws_vpc" "main" {
#        ─────┬─── ──┬──
#       资源类型   本地名称

  cidr_block = "10.0.0.0/16"
# ─────┬────   ────┬────────
#  参数名        参数值

  tags = {
    Name = "lesson-03-vpc"
  }
}
```

### 3.3 依赖关系可视化

![Resource Dependencies](images/resource-dependencies.png)

<details>
<summary>View ASCII source</summary>

```
        ┌─────────────────────┐
        │    aws_vpc.main     │
        └──────────┬──────────┘
                   │
                   ▼
          subnet 引用 vpc.id
                   │
        ┌──────────┴──────────┐
        │  aws_subnet.public  │
        └──────────┬──────────┘
                   │
                   ▼
       security_group 引用 vpc.id
                   │
        ┌──────────┴──────────┐
        │aws_security_group.web│
        └─────────────────────┘
```

</details>

Terraform 通过引用（如 `aws_vpc.main.id`）自动建立**隐式依赖**。

---

## Step 4 — 动手实验：Data Sources（8 分钟）

> 使用 Data Sources 查询 AWS 现有资源。

### 4.1 查看 Data Source 代码

```bash
cat data.tf
```

```hcl
# 查询可用区
data "aws_availability_zones" "available" {
  state = "available"
}

# 查询最新 Amazon Linux 2023 AMI
data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
}
```

### 4.2 使用 Data Source 输出

```bash
terraform output az_used
terraform output latest_ami_id
```

```
"ap-northeast-1a"
"ami-0a1b2c3d4e5f6g7h8"
```

### 4.3 Data Source vs Resource

| 类型 | 作用 | 示例 |
|------|------|------|
| `resource` | **创建**新资源 | `aws_vpc.main` |
| `data` | **查询**现有资源 | `data.aws_ami.al2023` |

**使用场景**：

- 查询最新 AMI ID（避免硬编码）
- 获取账户 ID、区域信息
- 引用手动创建的资源

---

## Step 5 — 动手实验：Lifecycle（10 分钟）

> 控制资源的创建、更新、销毁行为。

### 5.1 体验 create_before_destroy

编辑 `lifecycle-demo.tf`：

```bash
vim lifecycle-demo.tf  # 或使用 VS Code
```

找到 Security Group 规则，修改端口：

```hcl
# 将 from_port 和 to_port 从 80 改为 8080
ingress {
  from_port   = 8080   # 原来是 80
  to_port     = 8080   # 原来是 80
  ...
}
```

预览变更：

```bash
terraform plan
```

```
# aws_security_group.lifecycle_demo will be replaced
-/+ resource "aws_security_group" "lifecycle_demo" {
      ...
    }

Plan: 1 to add, 0 to change, 1 to destroy.
```

注意 `-/+`：这表示 **先创建新的，再删除旧的**（因为 `create_before_destroy = true`）。

### 5.2 体验 prevent_destroy

取消注释 `prevent_destroy`：

```hcl
lifecycle {
  create_before_destroy = true
  prevent_destroy       = true   # 取消注释
}
```

尝试销毁：

```bash
terraform destroy
```

```
Error: Instance cannot be destroyed

  on lifecycle-demo.tf line XX:
  XX: resource "aws_security_group" "lifecycle_demo" {

Resource aws_security_group.lifecycle_demo has lifecycle.prevent_destroy
set, but the plan calls for this resource to be destroyed.
```

**生产保护生效！** 恢复注释以继续。

### 5.3 体验 ignore_changes

假设运维人员手动在 Console 添加了标签：

```bash
# 模拟手动修改
aws ec2 create-tags \
  --resources $(terraform output -raw security_group_id) \
  --tags Key=ManualTag,Value=AddedByOps
```

```bash
terraform plan
```

如果配置了 `ignore_changes = [tags]`：

```
No changes. Your infrastructure matches the configuration.
```

如果没有配置：

```
# aws_security_group.web will be updated in-place
  ~ tags = {
      - "ManualTag" = "AddedByOps" -> null
    }
```

### 5.4 Lifecycle 选项总结

| 选项 | 作用 | 场景 |
|------|------|------|
| `create_before_destroy` | 先创建后删除 | 避免服务中断 |
| `prevent_destroy` | 禁止删除 | 保护关键资源 |
| `ignore_changes` | 忽略特定属性变化 | 允许手动修改 |
| `replace_triggered_by` | 关联资源变化触发替换 | 配置联动 |

---

## Step 6 — 深入理解：显式依赖（5 分钟）

### 6.1 什么时候需要 depends_on？

**通常不需要！** Terraform 通过引用自动推断依赖。

但有些情况依赖关系"不可见"：

```hcl
# IAM Policy 需要在 Role 之前创建
# 但没有直接引用
resource "aws_iam_role" "example" {
  name = "example"
  ...
}

resource "aws_iam_policy" "example" {
  name = "example"
  ...

  # 必须显式声明依赖
  depends_on = [aws_iam_role.example]
}
```

### 6.2 反模式警告

```hcl
# 错误！不要到处使用 depends_on
resource "aws_subnet" "public" {
  vpc_id = aws_vpc.main.id      # 已有隐式依赖
  depends_on = [aws_vpc.main]   # 冗余！

  # 这会隐藏真实的依赖关系，使代码难以维护
}
```

**原则**：优先使用资源引用建立隐式依赖，仅在必要时使用 `depends_on`。

---

## Step 7 — 清理资源（3 分钟）

> 完成学习后，立即清理！

```bash
cd ~/cloud-atlas/iac/terraform/03-hcl/code

# 如果有 prevent_destroy，先注释掉
vim lifecycle-demo.tf  # 注释 prevent_destroy = true

terraform destroy -auto-approve
```

```
Destroy complete! Resources: 4 destroyed.
```

验证：

```bash
aws ec2 describe-vpcs --filters "Name=tag:Name,Values=lesson-03*" --query "Vpcs[].VpcId"
# 应返回空数组 []
```

---

## 本课小结

| 概念 | 说明 |
|------|------|
| **Block** | HCL 基本单元（resource, data, provider...） |
| **Resource** | 创建新资源 |
| **Data Source** | 查询现有资源 |
| **隐式依赖** | 通过引用自动建立 |
| **显式依赖** | `depends_on`（谨慎使用） |
| **Lifecycle** | 控制资源生命周期行为 |

**反模式警告**：

| 不要这样做 | 为什么 |
|------------|--------|
| depends_on 到处使用 | 隐藏真实依赖，难维护 |
| Provisioners 做配置管理 | 不幂等，应使用 Ansible |
| -target 作为常规操作 | 累积 Drift |

---

## 下一步

掌握了 HCL 语法，但 Provider 版本管理还没深入。

→ [04 · Provider 策略与版本管理](../04-providers/)

---

## 面试准备

**よくある質問**

**Q: depends_on はいつ使いますか？**

A: 暗黙的な依存関係が存在しない場合のみ。例えば IAM Policy と Role の順序制御。通常はリソース参照（`aws_vpc.main.id` など）で自動的に依存関係が解決されるため、明示的な depends_on は不要。

**Q: create_before_destroy の用途は？**

A: ダウンタイムなしでリソースを置き換える場合。例えば Security Group のルール変更時、新しい SG を先に作成し、既存リソースを切り替えてから旧 SG を削除。サービス中断を防ぐ。

**Q: Data Source と Resource の違いは？**

A: Resource は新規リソースを**作成**、Data Source は既存リソースを**参照**。Data Source は読み取り専用で、Terraform 管理外のリソース情報を取得する際に使用。

---

## トラブルシューティング

**よくある問題**

**VPC 作成で Limit Exceeded**

```bash
# VPC 数の確認
aws ec2 describe-vpcs --query "Vpcs[].VpcId" | wc -l

# 不要な VPC を削除（デフォルト VPC は削除しない）
```

**Security Group ルール競合**

```
Error: InvalidParameterValue: cannot reference a security group
that is in a different VPC
```

→ `vpc_id` パラメータを確認。Security Group は特定の VPC に属する。

**Data Source で結果なし**

```
Error: no matching AMI found
```

→ filter 条件を確認。リージョンによって利用可能な AMI が異なる。

```bash
# 利用可能な AMI を確認
aws ec2 describe-images \
  --owners amazon \
  --filters "Name=name,Values=al2023-ami-*" \
  --query "Images[].Name" | head -5
```

---

## 系列导航

← [02 · 状態管理](../02-state/) | [Home](../) | [04 · Provider 策略 →](../04-providers/)
