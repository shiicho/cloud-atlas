# 代码生成示例 (Generated Config)

## 概述

本目录演示如何使用 `terraform plan -generate-config-out` 功能自动生成 Terraform 代码。

## 使用流程

### 1. 准备 Import Blocks

编辑 `import.tf`，填入要导入的资源 ID：

```hcl
import {
  id = "i-0abc123def456789"  # 替换为实际 Instance ID
  to = aws_instance.web_server
}

import {
  id = "sg-0123456789abcdef0"  # 替换为实际 SG ID
  to = aws_security_group.web_sg
}
```

### 2. 初始化

```bash
terraform init
```

### 3. 生成代码

```bash
terraform plan -generate-config-out=generated.tf
```

Terraform 会：
1. 从 AWS 读取资源当前状态
2. 自动生成对应的 Terraform 代码
3. 输出到 `generated.tf` 文件

### 4. 审查生成的代码

```bash
cat generated.tf
```

**重要**：生成的代码需要人工审查和优化！

### 5. 优化代码

生成的代码通常包含：
- 所有属性（包括默认值）
- 硬编码的 ID
- 计算属性

优化清单：

| 问题 | 处理方式 |
|------|----------|
| 硬编码 AMI ID | 改为 data source 或变量 |
| 硬编码 Subnet ID | 改为变量 |
| 硬编码 SG ID | 改为资源引用 |
| 默认值属性 | 删除（减少噪音） |
| 计算属性 | 删除（如 arn, id） |

### 6. 移动代码

将优化后的代码移动到 `main.tf`：

```bash
# 审查后，将代码移到 main.tf
cat generated.tf >> main.tf
# 编辑 main.tf 进行优化
vim main.tf
```

### 7. 执行导入

```bash
terraform apply
```

### 8. 验证

```bash
# 确认导入成功
terraform state list

# 确认无差异
terraform plan
```

## 文件说明

| 文件 | 说明 |
|------|------|
| `providers.tf` | Provider 配置 |
| `import.tf` | Import blocks 定义 |
| `generated.tf` | 自动生成（运行后产生） |
| `main.tf` | 最终资源定义（优化后） |

## 最佳实践

### 批量导入顺序

按依赖关系顺序导入：

```
1. VPC（如果需要）
2. Subnet（如果需要）
3. Security Group
4. EC2 Instance
5. 其他依赖资源
```

### 代码组织

导入完成后，建议将代码按类型拆分：

```
.
├── providers.tf     # Provider 配置
├── vpc.tf           # VPC 相关资源
├── security.tf      # 安全组
├── compute.tf       # EC2 实例
├── variables.tf     # 变量定义
├── outputs.tf       # 输出值
└── import.tf        # 可删除或保留作为文档
```

### Import Block 保留策略

导入完成后，`import.tf` 中的 import blocks：
- **可以保留**：作为导入历史文档
- **可以删除**：减少代码噪音
- **不会重复导入**：多次 apply 不会报错

## 常见问题

### Q: 生成的代码有语法错误？

A: 可能是 Provider 版本问题，运行 `terraform init -upgrade`

### Q: 某些属性无法生成？

A: 部分属性不支持自动生成，需要手动添加。查看 plan 输出中的警告。

### Q: 如何只生成部分资源的代码？

A: 注释掉不需要的 import blocks，只保留需要生成的。

## 参考链接

- [Terraform Import 官方文档](https://developer.hashicorp.com/terraform/language/import)
- [生成配置文档](https://developer.hashicorp.com/terraform/language/import/generating-configuration)
