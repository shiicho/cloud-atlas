# Drift 深度解析：CloudFormation 更新机制与漂移行为

> **补充材料**：本文档为 [Lesson 05 - Drift 检测与资源导入](../README.md) 的高级补充内容。
> 适合想要深入理解 CloudFormation 更新机制的进阶学习者。

---

## 1. CloudFormation 的 Delta 更新模型

### 1.1 最常见的误解

**误解**：执行 `Update Stack` 时，CloudFormation 会将资源状态恢复到模板定义的状态。

**现实**：CloudFormation 使用 **模板对模板** 的比较（delta update），而不是 **模板对实际资源** 的比较。

```
传统理解（错误）:
┌─────────────┐                    ┌─────────────┐
│ 新模板       │ ──── 比较 ────▶  │ AWS 实际资源 │
│ Environment │                    │ Environment │
│ = "dev"     │                    │ = "prod"    │
└─────────────┘                    └─────────────┘
                                          │
                                          ▼
                                   修复为 "dev"? ❌ 不会！


实际行为（正确）:
┌─────────────┐       ┌─────────────┐
│ 新模板       │       │ 旧模板       │
│ Environment │◀─比较─▶│ Environment │
│ = "dev"     │       │ = "dev"     │
└─────────────┘       └─────────────┘
      │
      ▼
  没有变化 = 不执行 API 调用 = Drift 保持！
```

### 1.2 实际测试验证

以下是真实 AWS 环境的测试结果，展示了这个行为：

```
测试场景：EC2 实例 Tags 的 Drift 行为

Step 1: 创建 Stack
- 模板定义: Environment = "dev"
- 实际资源: Environment = "dev" ✓

Step 2: 手动制造 Drift
- 在 Console 修改: Environment = "production"
- Drift Detection: MODIFIED (dev ≠ production)

Step 3: Update Stack（尝试修复 - 使用原模板）
- 新模板: Environment = "dev"（未改变）
- 旧模板: Environment = "dev"（未改变）
- CloudFormation 判断: 无变化，不执行任何操作
- 结果: Environment 仍为 "production" ❌

Step 4: Update Stack（添加新 Tag，但 Environment 不变）
- 新模板: 添加 NewTag = "value", Environment = "dev"
- 旧模板: Environment = "dev"
- CloudFormation 判断: NewTag 是新增的，执行添加
- 结果: NewTag 被添加，但 Environment 仍为 "production" ❌

Step 5: Update Stack（修改 Environment 参数值）
- 新模板: Environment = "staging"
- 旧模板: Environment = "dev"
- CloudFormation 判断: Environment 变化了，执行更新
- 结果: Environment 变为 "staging" ✓

结论: 只有模板中的值发生变化，CloudFormation 才会调用 AWS API 更新资源。
```

### 1.3 与 Terraform 的根本差异

| 特性 | CloudFormation | Terraform |
|------|----------------|-----------|
| 比较对象 | 新模板 vs 旧模板 | 期望状态 vs 实际状态 |
| Drift 修复 | 需要手动改变模板值 | `terraform apply` 自动修复 |
| State 文件 | 无（AWS 内部管理） | 必须（记录期望状态） |
| 更新触发条件 | 模板值发生变化 | 实际资源与 State 不一致 |

**Terraform 的期望状态模型**：

```hcl
# Terraform 配置
resource "aws_instance" "example" {
  tags = {
    Environment = "dev"  # 期望状态
  }
}

# 即使手动改成 "production"
# terraform apply 会自动恢复为 "dev"
# 因为 Terraform 比较的是：期望状态 vs 实际状态
```

---

## 2. Drift-Aware Change Sets（2025 年 11 月新功能）

### 2.1 REVERT_DRIFT 模式原理

AWS 在 2025 年 11 月发布了 **Drift-Aware Change Sets**，引入 `REVERT_DRIFT` deployment mode，实现三向比较：

```
传统 ChangeSet（两向比较）:
新模板 vs 旧模板 → 计算变更

REVERT_DRIFT ChangeSet（三向比较）:
新模板 vs 旧模板 vs 实际资源状态 → 计算变更 + 修复 Drift
```

### 2.2 CLI 使用方法

```bash
# 创建 Drift-Aware ChangeSet
aws cloudformation create-change-set \
  --stack-name my-stack \
  --change-set-name fix-drift-changeset \
  --template-body file://template.yaml \
  --deployment-mode REVERT_DRIFT

# 查看 ChangeSet 详情（包含 Drift 修复项）
aws cloudformation describe-change-set \
  --stack-name my-stack \
  --change-set-name fix-drift-changeset \
  --include-property-values

# 确认无误后执行
aws cloudformation execute-change-set \
  --stack-name my-stack \
  --change-set-name fix-drift-changeset
```

### 2.3 Console 使用方法

1. 选择 Stack → **Update**
2. 上传或选择模板
3. 在 **Change set options** 中选择 **Deployment mode: REVERT_DRIFT**
4. 预览 ChangeSet，确认 Drift 修复项
5. 执行 ChangeSet

### 2.4 ChangeSet 结果解读

使用 `REVERT_DRIFT` 模式时，ChangeSet 会显示两类变更：

| 变更类型 | 来源 | 说明 |
|----------|------|------|
| Template Change | 模板修改 | 新模板与旧模板的差异 |
| Drift Reversion | Drift 修复 | 实际状态与期望状态的差异 |

```json
{
  "Changes": [
    {
      "Type": "Resource",
      "ResourceChange": {
        "Action": "Modify",
        "LogicalResourceId": "MyInstance",
        "Details": [
          {
            "Target": {
              "Attribute": "Tags",
              "Name": "Environment"
            },
            "ChangeSource": "DriftReversion",  // ← 来自 Drift 修复
            "Evaluation": "Dynamic"
          }
        ]
      }
    }
  ]
}
```

### 2.5 推荐工作流

```
生产环境 Drift 修复推荐流程:

1. Detect Drift（确认 Drift 范围）
   aws cloudformation detect-stack-drift --stack-name my-stack

2. 分析 Drift 详情
   aws cloudformation describe-stack-resource-drifts --stack-name my-stack

3. 决策：修复还是接受？
   - 如果是错误的手动修改 → 修复
   - 如果是合理的紧急变更 → 更新模板接受

4. 创建 REVERT_DRIFT ChangeSet
   aws cloudformation create-change-set ... --deployment-mode REVERT_DRIFT

5. 预览 + 审批
   - 确认变更范围
   - 检查是否有 Replacement（破坏性变更）
   - 获取变更管理审批

6. 执行 ChangeSet

7. 验证
   aws cloudformation detect-stack-drift --stack-name my-stack
   # 确认状态为 IN_SYNC
```

---

## 3. 资源类型 Drift 支持

### 3.1 并非所有资源支持 Drift Detection

CloudFormation Drift Detection 仅支持部分资源类型。使用前务必确认：

**支持 Drift Detection 的常见资源**：

| 资源类型 | 说明 |
|----------|------|
| AWS::EC2::Instance | 实例配置、Tags |
| AWS::EC2::SecurityGroup | 入站/出站规则 |
| AWS::EC2::VPC | CIDR、Tags |
| AWS::EC2::Subnet | CIDR、Tags |
| AWS::S3::Bucket | 配置、Tags |
| AWS::RDS::DBInstance | 实例配置 |
| AWS::Lambda::Function | 配置、代码 |
| AWS::IAM::Role | 信任策略（部分） |
| AWS::DynamoDB::Table | 表配置 |

**不支持 Drift Detection 的常见资源**：

| 资源类型 | 原因 |
|----------|------|
| AWS::AutoScaling::AutoScalingGroup | 实例数量动态变化 |
| AWS::ECS::Cluster | 容器动态调度 |
| AWS::EKS::Cluster | Kubernetes 内部状态 |
| AWS::IAM::RolePolicy (inline) | 内联策略不跟踪 |
| AWS::EC2::VPCGatewayAttachment | 关联关系 |
| AWS::CloudFormation::Stack (Nested) | 嵌套栈不直接检测 |

### 3.2 查询支持状态

```bash
# 检查特定资源类型是否支持 Import 和 Drift Detection
aws cloudformation describe-type \
  --type RESOURCE \
  --type-name AWS::EC2::Instance \
  --query 'Handlers.[Read,List]'

# 如果 Read 和 List 都存在，通常支持 Drift Detection
```

**官方参考**：[AWS CloudFormation resource type support for import and drift detection](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/resource-import-supported-resources.html)

---

## 4. 属性级别 Drift 规则

### 4.1 属性类别与 Drift 检测

并非资源的所有属性都支持 Drift Detection：

| 属性类别 | Drift 检测？ | 说明 |
|----------|--------------|------|
| 显式设置的属性 | **YES** | 模板中明确定义的值 |
| 使用默认值的属性 | **NO** | 必须显式设置才跟踪 |
| readOnlyProperties | **NO** | 系统生成的值（ARN, ID） |
| writeOnlyProperties | **NO** | 无法读取的值（密码） |
| createOnlyProperties | 部分 | 创建后不可变更的属性 |

### 4.2 关键洞察：显式设置的重要性

**如果你想让 CloudFormation 跟踪某个属性的 Drift，必须在模板中显式设置它**。

```yaml
# 不跟踪 Drift（使用默认值）
Resources:
  MyBucket:
    Type: AWS::S3::Bucket
    # Versioning 使用默认值，不跟踪 Drift

# 跟踪 Drift（显式设置）
Resources:
  MyBucket:
    Type: AWS::S3::Bucket
    Properties:
      VersioningConfiguration:
        Status: Suspended  # 显式设置，即使是默认值也会跟踪
```

### 4.3 特殊情况：KMSKeyId

`KMSKeyId` 属性永远不会检测到 Drift：

```
原因：KMS Key 可以有多个别名（alias）
- 模板可能使用 alias/my-key
- AWS 可能返回 arn:aws:kms:...
- 两者指向同一个 Key，但字符串不同
- CloudFormation 无法准确判断是否 Drift
```

### 4.4 EC2 安全组规则的特殊行为

跨栈引用的安全组规则可能导致不准确的 Drift 检测结果：

```yaml
# Stack A - 定义安全组
Resources:
  MySecurityGroup:
    Type: AWS::EC2::SecurityGroup
    # ...

# Stack B - 添加规则到 Stack A 的安全组
Resources:
  IngressRule:
    Type: AWS::EC2::SecurityGroupIngress
    Properties:
      GroupId: !ImportValue Stack-A-SG-ID  # 跨栈引用
      # ...

# 问题：Stack A 检测 Drift 时，会报告 Stack B 添加的规则为 "unexpected"
```

**解决方案**：使用独立的 `AWS::EC2::SecurityGroupIngress` 资源，而不是在 SecurityGroup 内定义规则。

---

## 5. Update 行为与 Drift 修复

### 5.1 Update 行为类型

修复 Drift 前，务必了解属性的 Update 行为：

| Update 行为 | Physical ID | 影响 | 示例 |
|-------------|-------------|------|------|
| **No Interruption** | 不变 | 可安全修复 | Tags, Description |
| **Some Interruption** | 不变 | 服务短暂中断 | InstanceType (需停机) |
| **Replacement** | **新 ID** | 资源重建 | ImageId, SubnetId |

### 5.2 EC2 Instance 属性 Update 行为

| 属性 | Update 行为 | Drift 修复风险 |
|------|-------------|----------------|
| Tags | No Interruption | **安全** |
| InstanceType | Some Interruption | 需要停机 |
| SecurityGroupIds | No Interruption | **安全** |
| ImageId | **Replacement** | **危险！新实例** |
| SubnetId | **Replacement** | **危险！新实例** |
| AvailabilityZone | **Replacement** | **危险！新实例** |
| KeyName | No Interruption | 安全（仅影响新连接） |

### 5.3 修复 Drift 前的检查

```bash
# 1. 检测 Drift
aws cloudformation detect-stack-drift --stack-name my-stack

# 2. 查看 Drift 详情
aws cloudformation describe-stack-resource-drifts \
  --stack-name my-stack \
  --query 'StackResourceDrifts[?DriftStatus==`MODIFIED`]'

# 3. 对于每个 Drifted 属性，查询 Update 行为
# 参考 AWS 文档确认是 No Interruption / Some Interruption / Replacement

# 4. 创建 ChangeSet 预览
aws cloudformation create-change-set \
  --stack-name my-stack \
  --change-set-name preview-fix \
  --template-body file://template.yaml \
  --deployment-mode REVERT_DRIFT

# 5. 检查是否有 Replacement
aws cloudformation describe-change-set \
  --stack-name my-stack \
  --change-set-name preview-fix \
  --query 'Changes[?ResourceChange.Replacement==`True`]'

# 如果有 Replacement，谨慎决策！
```

---

## 6. 反模式与最佳实践

### 6.1 反模式清单

| 反模式 | 问题 | 正确做法 |
|--------|------|----------|
| 假设 Update Stack 能修复 Drift | 模板值未变不会触发更新 | 使用 REVERT_DRIFT 模式 |
| 不显式设置想跟踪的属性 | 默认值不跟踪 Drift | 显式设置所有关键属性 |
| 跨栈安全组规则 | 导致不准确的 Drift 结果 | 使用独立的 Ingress/Egress 资源 |
| 修复前不检查 Update 行为 | 可能触发 Replacement | 先创建 ChangeSet 预览 |
| 忽略 Drift 长期不处理 | 配置管理失控 | 定期 Drift Detection + 修复 |

### 6.2 Drift 管理最佳实践

**1. 预防 Drift**

```yaml
# 使用 StackPolicy 保护关键资源
{
  "Statement": [
    {
      "Effect": "Deny",
      "Action": "Update:*",
      "Principal": "*",
      "Resource": "LogicalResourceId/ProductionDatabase",
      "Condition": {
        "StringEquals": {
          "ResourceType": ["AWS::RDS::DBInstance"]
        }
      }
    }
  ]
}
```

**2. 定期检测**

```bash
# 建议：每日/每周定期运行
for stack in $(aws cloudformation list-stacks \
  --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE \
  --query 'StackSummaries[].StackName' --output text); do
  echo "Checking $stack..."
  aws cloudformation detect-stack-drift --stack-name "$stack"
done
```

**3. 自动化监控（AWS Config）**

```yaml
# AWS Config Rule 检测 Drift
Resources:
  CloudFormationDriftRule:
    Type: AWS::Config::ConfigRule
    Properties:
      ConfigRuleName: cloudformation-stack-drift-detection-check
      Source:
        Owner: AWS
        SourceIdentifier: CLOUDFORMATION_STACK_DRIFT_DETECTION_CHECK
      MaximumExecutionFrequency: TwentyFour_Hours
```

---

## 7. 日本 IT 职场相关性

### 7.1 Drift 与障害対応

在日本 IT 运维现场，Drift 最常发生在 **障害対応**（incident response）期间：

```
典型场景：

夜間監視
  └─▶ 異常検知（アラート発報）
       └─▶ 緊急対応（Console 手動変更）
            └─▶ 翌朝 Drift 検出
                 └─▶ 変更管理票で追認
                      └─▶ IaC 反映 or ロールバック
```

**重要**：即使是紧急修复，事后也必须通过 **変更管理** 流程追认，并将变更反映到 IaC。

### 7.2 変更管理（Change Management）

日本企业的变更管理流程通常要求：

| 阶段 | 证据 | CloudFormation 对应 |
|------|------|---------------------|
| 変更申請 | 変更管理票 | ChangeSet 创建 |
| リスク評価 | 影響範囲分析 | ChangeSet 预览（Replacement 确认） |
| 承認 | 承認者署名 | ChangeSet 执行前审批 |
| 実施 | 作業ログ | ChangeSet 执行 + CloudTrail |
| 確認 | 動作確認結果 | Drift Detection = IN_SYNC |
| 証跡 | 保存 | ChangeSet + CloudTrail logs |

### 7.3 監査対応（Audit Compliance）

Drift Detection 记录可作为审计证据：

```bash
# 导出 Drift 历史作为审计证据
aws cloudformation describe-stack-resource-drifts \
  --stack-name production-stack \
  --stack-resource-drift-status-filters MODIFIED DELETED \
  > drift-audit-$(date +%Y%m%d).json
```

**AWS Config 规则**：定期检查所有 Stack 是否有 Drift，不合规时触发告警。

### 7.4 常用日语术语补充

| 日语 | 读音 | 中文 | 场景 |
|------|------|------|------|
| 構成ドリフト | こうせいどりふと | 配置漂移 | Drift 正式名称 |
| 差分検知 | さぶんけんち | 差异检测 | Drift Detection |
| 手戻り | てもどり | 返工 | Drift 修复工作 |
| 是正措置 | ぜせいそち | 纠正措施 | Drift 修复策略 |
| 予防措置 | よぼうそち | 预防措施 | StackPolicy 等 |

---

## 8. 参考资料

### AWS 官方文档

- [Drift Detection Overview](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/using-cfn-stack-drift.html)
- [Drift-Aware Change Sets (Nov 2025)](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/using-cfn-stack-drift-change-sets.html)
- [Resource Import and Drift Support](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/resource-import-supported-resources.html)
- [Update Behaviors of Stack Resources](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/using-cfn-updating-stacks-update-behaviors.html)

### 相关课程内容

- [Lesson 05 - Drift 检测与资源导入](../README.md) - 主课程内容
- [Lesson 02 - ChangeSets 与回滚策略](../../02-safe-operations/) - ChangeSet 详解
- [Terraform Drift Detection](../../../terraform/10-drift/) - Terraform 对比学习

---

## 总结

CloudFormation 的 Drift 行为与大多数人的直觉不同：

1. **Update Stack 不自动修复 Drift** - 因为使用模板对模板比较
2. **使用 REVERT_DRIFT 模式** - 2025 年新功能，实现三向比较
3. **不是所有资源/属性都支持 Drift Detection** - 查阅官方文档确认
4. **显式设置属性** - 默认值不跟踪 Drift
5. **修复前检查 Update 行为** - 避免意外的 Replacement

理解这些机制，才能在日本 IT 职场中正确处理 Drift 相关的 **障害対応** 和 **変更管理**。
