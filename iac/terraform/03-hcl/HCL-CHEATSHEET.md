# HCL 语法速查表 | HCL Syntax Cheatsheet

> CloudFormation 用户的 Terraform 心智模型转换指南

---

## 1. 核心概念：Block vs Argument

**HCL 有两种完全不同的语法结构：**

```
┌─────────────────────────────────────────────────────────────────┐
│                        Block（块）                               │
│  ─────────────────────────────────────────────────────────────  │
│                                                                 │
│   lifecycle {                    ← 无等号！                      │
│     ignore_changes = [tags]                                     │
│   }                                                             │
│                                                                 │
│   用途：Terraform 定义的结构容器                                  │
│   特征：有固定 schema，不能用变量替换整个块                        │
│                                                                 │
├─────────────────────────────────────────────────────────────────┤
│                      Argument（参数）                            │
│  ─────────────────────────────────────────────────────────────  │
│                                                                 │
│   tags = {                       ← 有等号！                      │
│     Name = "example"                                            │
│   }                                                             │
│                                                                 │
│   用途：给属性赋值（可以是 map、list、string 等）                  │
│   特征：可以用变量、表达式、函数                                   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 常见 Block 类型（无 `=`）

| Block | 用途 | 示例 |
|-------|------|------|
| `resource` | 定义资源 | `resource "aws_vpc" "main" { }` |
| `data` | 查询数据 | `data "aws_ami" "latest" { }` |
| `provider` | 配置提供商 | `provider "aws" { }` |
| `module` | 调用模块 | `module "vpc" { }` |
| `terraform` | 全局配置 | `terraform { }` |
| `backend` | 状态后端 | `backend "s3" { }` |
| `lifecycle` | 生命周期 | `lifecycle { }` |
| `provisioner` | 配置器 | `provisioner "local-exec" { }` |
| `ingress/egress` | SG 规则 | `ingress { }` |
| `ebs_block_device` | EBS 卷 | `ebs_block_device { }` |
| `dynamic` | 动态块 | `dynamic "ingress" { }` |

### 常见 Argument 类型（有 `=`）

| Argument | 用途 | 示例 |
|----------|------|------|
| `tags` | 资源标签 | `tags = { Name = "x" }` |
| `environment` | 环境变量 | `environment = { DEBUG = "1" }` |
| `variables` | 变量映射 | `variables = var.my_map` |
| 任何接受表达式的属性 | 动态值 | `ami = data.aws_ami.latest.id` |

---

## 2. 判断流程：该用哪种语法？

```
                    ┌─────────────────────┐
                    │ 我要写的配置是什么？ │
                    └──────────┬──────────┘
                               │
              ┌────────────────┴────────────────┐
              ▼                                 ▼
     ┌────────────────┐               ┌────────────────┐
     │ Terraform 关键字 │               │  资源的属性    │
     │ (lifecycle,     │               │  (tags, ami,   │
     │  backend, etc.) │               │   cidr, etc.)  │
     └───────┬────────┘               └───────┬────────┘
             │                                 │
             ▼                                 ▼
      使用 Block 语法                   查看 Provider 文档
      name { ... }                            │
                                ┌─────────────┴─────────────┐
                                ▼                           ▼
                       文档说 "Block"              文档说 "Attribute"
                       或有嵌套结构                 或 "map of string"
                                │                           │
                                ▼                           ▼
                         使用 Block 语法            使用 Argument 语法
                         name { ... }              name = { ... }
```

### 快速判断技巧

1. **看文档标题**：Provider Registry 文档会标注 "Argument Reference" 和 "Nested Blocks"
2. **能否用 `merge()`**：如果可以，是 Argument（如 `tags = merge(...)`）
3. **能否重复出现**：如果能有多个（如多个 `ingress`），通常是 Block
4. **是否是 Terraform 关键字**：`lifecycle`、`backend`、`provisioner` 等永远是 Block

---

## 3. 错误信息解读器

| 错误信息 | 原因 | 修复方法 |
|----------|------|----------|
| `An argument named "lifecycle" is not expected here` | 写成了 `lifecycle = { }` | 改成 `lifecycle { }`（去掉 `=`） |
| `Blocks of type "tags" are not expected here` | 写成了 `tags { }` | 改成 `tags = { }`（加上 `=`） |
| `Unsupported block type` | Block 名称拼错或不存在 | 检查拼写，查阅文档 |
| `Variables may not be used here` | 在 `lifecycle` 等元参数中用了变量 | 改用字面值 |
| `Reference to undeclared resource` | 引用的资源不存在 | 检查资源名称和类型 |

### 你遇到的错误

```hcl
# 错误写法
lifecycle = {
  ignore_changes = [tags]
}

# 正确写法
lifecycle {
  ignore_changes = [tags]
}
```

**根本原因**：`lifecycle` 是 Terraform 内置的 **Block**，不是可赋值的属性。

---

## 4. CloudFormation → Terraform 心智转换

> 如果你熟悉 CloudFormation，可参考 [CloudFormation 基础](../../cloudformation/00-fundamentals/) 了解更多对比。

### 语法对比

| 概念 | CloudFormation (YAML) | Terraform (HCL) |
|------|----------------------|-----------------|
| 定义资源 | `Type: AWS::EC2::VPC` | `resource "aws_vpc" "name" { }` |
| 属性 | 全在 `Properties:` 下 | 混合 Block 和 Argument |
| 引用资源 | `!Ref MyVpc` | `aws_vpc.my_vpc.id` |
| 获取属性 | `!GetAtt MyVpc.VpcId` | `aws_vpc.my_vpc.id` |
| 字符串拼接 | `!Sub "arn:aws:s3:::${Bucket}"` | `"arn:aws:s3:::${aws_s3_bucket.b.id}"` |
| 条件 | `!If [Cond, A, B]` | `condition ? a : b` |

### 引用方式对比

```yaml
# CloudFormation - 两种引用方式，返回值取决于资源类型
Resources:
  MyVpc:
    Type: AWS::EC2::VPC
    Properties:
      CidrBlock: 10.0.0.0/16

  MySubnet:
    Type: AWS::EC2::Subnet
    Properties:
      VpcId: !Ref MyVpc          # 返回 VPC ID（魔法默认值）
      CidrBlock: 10.0.1.0/24
```

```hcl
# Terraform - 引用始终显式
resource "aws_vpc" "my_vpc" {
  cidr_block = "10.0.0.0/16"
}

resource "aws_subnet" "my_subnet" {
  vpc_id     = aws_vpc.my_vpc.id    # 显式指定 .id
  cidr_block = "10.0.1.0/24"
}
```

### 思维模式转换

| CloudFormation 思维 | Terraform 思维 |
|--------------------|----------------|
| "YAML 是数据格式，一切皆键值对" | "HCL 是配置语言，有结构和表达式" |
| "`!Ref` 返回资源的默认值" | "显式写出 `resource.name.attribute`" |
| "Change Set 是可选的" | "`terraform plan` 是必须的工作流" |
| "状态由 AWS 管理，不可见" | "状态文件是核心，要管理好" |
| "嵌套用 YAML 缩进" | "嵌套用 `block { }` 或 `arg = { }`" |

---

## 5. 常用 Meta-Arguments（元参数）

所有 Meta-Arguments 都使用 **Block 语法**（无 `=`）：

```hcl
resource "aws_instance" "example" {
  ami           = "ami-12345678"
  instance_type = "t3.micro"

  # lifecycle - 控制资源生命周期
  lifecycle {
    create_before_destroy = true
    prevent_destroy       = false
    ignore_changes        = [tags, ami]
    # replace_triggered_by = [null_resource.trigger.id]
  }

  # depends_on - 显式依赖（尽量用隐式）
  depends_on = [aws_vpc.main]

  # count - 创建多个实例
  count = 3

  # for_each - 基于 map/set 创建
  # for_each = toset(["a", "b", "c"])

  # provider - 指定 provider
  # provider = aws.west
}
```

---

## 6. 读文档技巧

### Terraform Registry 文档结构

```
aws_security_group
├── Example Usage          ← 先看例子
├── Argument Reference     ← 这些用 name = value
│   ├── name (Required)
│   ├── description (Optional)
│   └── tags (Optional)    ← Map 类型，用 =
├── Nested Blocks          ← 这些用 name { }
│   ├── ingress
│   └── egress
└── Attribute Reference    ← 这些是输出，用于引用
    ├── id
    └── arn
```

### 识别 Block vs Argument

**文档中看到这些，用 Block（无 `=`）：**
- "Nested Blocks"
- "Block List" / "Block Set"
- 有缩进的子属性列表

**文档中看到这些，用 Argument（有 `=`）：**
- "map of string"
- "list of string"
- "(Optional)" 后跟简单类型
- 可以接受变量或表达式

---

## 7. 一句话总结

> **Block 是容器（Terraform 定义结构），Argument 是赋值（你定义内容）**  
>
> - `lifecycle { }` ← Terraform 说："这里面只能放我规定的东西"  
> - `tags = { }` ← Terraform 说："你想放什么 key-value 都行"

---

## 参考资源

- [Terraform Configuration Syntax](https://developer.hashicorp.com/terraform/language/syntax/configuration)
- [Attributes as Blocks](https://developer.hashicorp.com/terraform/language/attr-as-blocks)
- [Lifecycle Meta-Argument](https://developer.hashicorp.com/terraform/language/meta-arguments/lifecycle)
- [HCL Native Syntax Spec](https://github.com/hashicorp/hcl/blob/main/hclsyntax/spec.md)
