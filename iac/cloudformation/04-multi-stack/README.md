# 04 - 多栈架构与跨栈引用

> **目标**：掌握 CloudFormation 多栈架构设计，实现模块化和跨栈通信
> **时间**：50 分钟
> **费用**：VPC + Subnets（免费层）
> **区域**：ap-northeast-1（Tokyo）推荐，或 us-east-1
> **前置**：[03 - 现代工具](../03-modern-tools/)

---

## 将学到的内容

1. 理解单体模板（Monolithic Template）的问题
2. 使用 Nested Stacks 实现模块化
3. 使用 Exports/ImportValue 实现跨栈引用
4. 设计 Layer 化架构：Network → Foundations → Application
5. 选择 Nested Stacks vs Cross-Stack References

---

## Step 1 — 先跑起来！跨栈引用（10 分钟）

> 先"尝到"跨栈引用的便利，再理解背后原理。

### 1.1 准备 Network Stack 模板

创建 `network-stack.yaml`，定义 VPC 和子网：

```yaml
AWSTemplateFormatVersion: '2010-09-09'
Description: Network Layer - VPC and Subnets (exports for cross-stack reference)

Parameters:
  Environment:
    Type: String
    Default: dev
    AllowedValues: [dev, staging, prod]

Resources:
  VPC:
    Type: AWS::EC2::VPC
    Properties:
      CidrBlock: 10.0.0.0/16
      EnableDnsHostnames: true
      EnableDnsSupport: true
      Tags:
        - Key: Name
          Value: !Sub '${Environment}-vpc'

  PublicSubnet1:
    Type: AWS::EC2::Subnet
    Properties:
      VpcId: !Ref VPC
      CidrBlock: 10.0.1.0/24
      AvailabilityZone: !Select [0, !GetAZs '']
      MapPublicIpOnLaunch: true
      Tags:
        - Key: Name
          Value: !Sub '${Environment}-public-1'

  PublicSubnet2:
    Type: AWS::EC2::Subnet
    Properties:
      VpcId: !Ref VPC
      CidrBlock: 10.0.2.0/24
      AvailabilityZone: !Select [1, !GetAZs '']
      MapPublicIpOnLaunch: true
      Tags:
        - Key: Name
          Value: !Sub '${Environment}-public-2'

Outputs:
  VpcId:
    Description: VPC ID
    Value: !Ref VPC
    Export:
      Name: !Sub '${Environment}-VpcId'

  PublicSubnet1Id:
    Description: Public Subnet 1 ID
    Value: !Ref PublicSubnet1
    Export:
      Name: !Sub '${Environment}-PublicSubnet1Id'

  PublicSubnet2Id:
    Description: Public Subnet 2 ID
    Value: !Ref PublicSubnet2
    Export:
      Name: !Sub '${Environment}-PublicSubnet2Id'
```

> 你也可以直接使用课程代码：`code/network-stack.yaml`

### 1.2 部署 Network Stack

1. 登录 AWS Console，进入 **CloudFormation**
2. 点击 **Create stack** → **With new resources (standard)**
3. 选择 **Upload a template file**，上传 `network-stack.yaml`
4. **Stack name**：`dev-network-stack`
5. **Environment**：保持默认 `dev`
6. 点击 **Next** → **Next** → **Submit**

<!-- SCREENSHOT: network-stack-create -->

等待 Stack 状态变为 `CREATE_COMPLETE`。

### 1.3 验证 Exports

1. 在 CloudFormation Console，点击左侧导航栏的 **Exports**
2. 你会看到三个导出值：
   - `dev-VpcId`
   - `dev-PublicSubnet1Id`
   - `dev-PublicSubnet2Id`

<!-- SCREENSHOT: cloudformation-exports -->

### 1.4 准备 App Stack 模板

创建 `app-stack.yaml`，引用 Network Stack 的输出：

```yaml
AWSTemplateFormatVersion: '2010-09-09'
Description: Application Layer - imports VPC from network stack

Parameters:
  Environment:
    Type: String
    Default: dev
    AllowedValues: [dev, staging, prod]

Resources:
  AppSecurityGroup:
    Type: AWS::EC2::SecurityGroup
    Properties:
      GroupDescription: Application Security Group
      VpcId: !ImportValue
        Fn::Sub: '${Environment}-VpcId'
      SecurityGroupIngress:
        - IpProtocol: tcp
          FromPort: 80
          ToPort: 80
          CidrIp: 0.0.0.0/0
      Tags:
        - Key: Name
          Value: !Sub '${Environment}-app-sg'

Outputs:
  SecurityGroupId:
    Description: Application Security Group ID
    Value: !Ref AppSecurityGroup
```

> 你也可以直接使用课程代码：`code/app-stack.yaml`

### 1.5 部署 App Stack

1. 创建新 Stack，上传 `app-stack.yaml`
2. **Stack name**：`dev-app-stack`
3. **Environment**：`dev`
4. 点击 **Next** → **Next** → **Submit**

<!-- SCREENSHOT: app-stack-create -->

### 1.6 验证跨栈引用

1. 进入 **EC2 Console** → **Security Groups**
2. 找到 `dev-app-sg`
3. 确认它创建在正确的 VPC 中

恭喜！你刚刚实现了 CloudFormation 跨栈引用！

---

## Step 2 — 发生了什么？（5 分钟）

### 2.1 跨栈引用原理

![Cross-Stack Reference 原理](images/cross-stack-reference.png)

<details>
<summary>View ASCII source</summary>

```
┌─────────────────────────────────────────────────────────────────────┐
│                     Cross-Stack Reference 原理                        │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│   Network Stack                          App Stack                  │
│   ┌─────────────────┐                   ┌─────────────────┐        │
│   │  Resources:     │                   │  Resources:     │        │
│   │    VPC          │                   │    SG           │        │
│   │    Subnets      │                   │                 │        │
│   ├─────────────────┤                   ├─────────────────┤        │
│   │  Outputs:       │                   │  !ImportValue   │        │
│   │    Export:      │ ────引用────▶    │   dev-VpcId     │        │
│   │    dev-VpcId    │                   │                 │        │
│   └─────────────────┘                   └─────────────────┘        │
│                                                                     │
│   ┌─────────────────────────────────────────────────────────┐      │
│   │                AWS CloudFormation Exports                │      │
│   │   dev-VpcId: vpc-0123456789                              │      │
│   │   dev-PublicSubnet1Id: subnet-aaa                        │      │
│   │   dev-PublicSubnet2Id: subnet-bbb                        │      │
│   └─────────────────────────────────────────────────────────┘      │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

</details>

### 2.2 Export 与 ImportValue

**导出（Export）**：在 Outputs 中使用 `Export.Name`

```yaml
Outputs:
  VpcId:
    Value: !Ref VPC
    Export:
      Name: dev-VpcId    # 全局唯一的导出名称
```

**导入（ImportValue）**：在其他 Stack 中引用

```yaml
Resources:
  MyResource:
    Properties:
      VpcId: !ImportValue dev-VpcId
```

### 2.3 依赖关系

当 Stack B 导入 Stack A 的 Export 时：

| 操作 | 允许？ | 说明 |
|------|--------|------|
| 更新 Stack A 的其他资源 | Yes | 不影响导出值 |
| 删除 Stack A 的 Export | **No** | 被依赖时无法删除 |
| 删除 Stack A | **No** | 必须先删除 Stack B |

这种保护机制防止意外破坏跨栈依赖！

---

## Step 3 — 为什么需要多栈？（5 分钟）

### 3.1 单体模板的问题

![单体模板问题](images/monolithic-problems.png)

<details>
<summary>View ASCII source</summary>

```
┌─────────────────────────────────────────────────────────────────────┐
│                     单体模板 (Monolithic Template) 问题               │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│   单体模板 (5000+ 行)                                                │
│   ┌─────────────────────────────────────────────────────────┐      │
│   │  VPC                                                     │      │
│   │  Subnets (6)                                             │      │
│   │  Route Tables (3)                                        │      │
│   │  NAT Gateway                                             │      │
│   │  Security Groups (10)                                    │      │
│   │  ALB + Target Groups                                     │      │
│   │  EC2 Instances (5)                                       │      │
│   │  RDS Cluster                                             │      │
│   │  ElastiCache                                             │      │
│   │  S3 Buckets (3)                                          │      │
│   │  IAM Roles (8)                                           │      │
│   │  CloudWatch Alarms (20)                                  │      │
│   │  ...                                                     │      │
│   └─────────────────────────────────────────────────────────┘      │
│                                                                     │
│   问题:                                                              │
│   ┌──────────────┐ ┌──────────────┐ ┌──────────────┐              │
│   │ 1. 部署慢     │ │ 2. 难维护    │ │ 3. 爆炸半径大 │              │
│   │ 30+ 分钟     │ │ 100+ 资源    │ │ 一错全停     │              │
│   └──────────────┘ └──────────────┘ └──────────────┘              │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

</details>

| 问题 | 说明 | 影响 |
|------|------|------|
| **部署慢** | 所有资源串行/并行处理 | 一次部署 30+ 分钟 |
| **难维护** | 5000+ 行 YAML | 找一个参数要翻很久 |
| **爆炸半径大** | 任何错误影响全部 | 应用改坏网络也回滚 |
| **权限难分** | 网络/应用同模板 | 开发者能动网络配置 |
| **复用困难** | 逻辑耦合严重 | 无法只用 VPC 部分 |

### 3.2 分层解决方案

![Layer 化架构设计](images/layered-solution.png)

<details>
<summary>View ASCII source</summary>

```
┌─────────────────────────────────────────────────────────────────────┐
│                        Layer 化架构设计                               │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│   Layer 3: Application                    变更频率: 高              │
│   ┌─────────────────────────────────┐                              │
│   │  EC2, ECS, Lambda               │    独立部署、快速迭代         │
│   │  Application Security Groups    │                              │
│   └────────────────┬────────────────┘                              │
│                    │ ImportValue                                    │
│                    ▼                                                │
│   Layer 2: Foundations                    变更频率: 中              │
│   ┌─────────────────────────────────┐                              │
│   │  ALB, RDS, ElastiCache          │    基础服务、稳定运行         │
│   │  S3, Secrets Manager            │                              │
│   └────────────────┬────────────────┘                              │
│                    │ ImportValue                                    │
│                    ▼                                                │
│   Layer 1: Network                        变更频率: 低              │
│   ┌─────────────────────────────────┐                              │
│   │  VPC, Subnets, Route Tables     │    网络基础、很少变更         │
│   │  NAT Gateway, VPN               │                              │
│   └─────────────────────────────────┘                              │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

</details>

**按生命周期分层**：

| Layer | 内容 | 变更频率 | 管理者 |
|-------|------|----------|--------|
| **Network** | VPC, Subnets, NAT | 极低 | 网络团队 |
| **Foundations** | RDS, ALB, S3 | 低 | 平台团队 |
| **Application** | EC2, Lambda, ECS | 高 | 应用团队 |

---

## Step 4 — Nested Stacks（10 分钟）

> Nested Stacks 是另一种模块化方式，适合紧密耦合的组件。

### 4.1 Nested Stacks vs Cross-Stack References

![Nested Stacks vs Cross-Stack References](images/nested-vs-cross-stack.png)

<details>
<summary>View ASCII source</summary>

```
┌─────────────────────────────────────────────────────────────────────┐
│              Nested Stacks vs Cross-Stack References                 │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│   Nested Stacks (父子关系)              Cross-Stack (兄弟关系)       │
│   ┌─────────────────────┐              ┌─────────────────────┐     │
│   │   Parent Stack      │              │   Stack A           │     │
│   │   ┌───────────────┐ │              │   Export: VpcId     │     │
│   │   │  Child: VPC   │ │              └──────────┬──────────┘     │
│   │   └───────────────┘ │                         │                │
│   │   ┌───────────────┐ │              ┌──────────▼──────────┐     │
│   │   │  Child: App   │ │              │   Stack B           │     │
│   │   └───────────────┘ │              │   ImportValue       │     │
│   └─────────────────────┘              └─────────────────────┘     │
│                                                                     │
│   特点:                                 特点:                        │
│   • 一起创建/删除                        • 独立生命周期               │
│   • 一起回滚                             • 独立部署                   │
│   • 父 Stack 控制所有                    • 松耦合                     │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

</details>

| 特性 | Nested Stacks | Cross-Stack References |
|------|---------------|------------------------|
| **关系** | 父子 | 兄弟 |
| **生命周期** | 一起创建/删除 | 独立 |
| **回滚** | 一起回滚 | 独立回滚 |
| **部署顺序** | 自动处理 | 需手动考虑 |
| **适用场景** | 紧密耦合组件 | 松耦合层 |

### 4.2 创建 Nested Stack 子模板

创建 `nested-stacks/child-vpc.yaml`：

```yaml
AWSTemplateFormatVersion: '2010-09-09'
Description: Child Stack - VPC (used by parent stack)

Parameters:
  Environment:
    Type: String
  VpcCidr:
    Type: String
    Default: 10.0.0.0/16

Resources:
  VPC:
    Type: AWS::EC2::VPC
    Properties:
      CidrBlock: !Ref VpcCidr
      EnableDnsHostnames: true
      EnableDnsSupport: true
      Tags:
        - Key: Name
          Value: !Sub '${Environment}-vpc'

  PublicSubnet:
    Type: AWS::EC2::Subnet
    Properties:
      VpcId: !Ref VPC
      CidrBlock: 10.0.1.0/24
      AvailabilityZone: !Select [0, !GetAZs '']
      Tags:
        - Key: Name
          Value: !Sub '${Environment}-public'

Outputs:
  VpcId:
    Value: !Ref VPC
  SubnetId:
    Value: !Ref PublicSubnet
```

### 4.3 创建 Parent Stack

创建 `nested-stacks/parent.yaml`：

```yaml
AWSTemplateFormatVersion: '2010-09-09'
Description: Parent Stack - orchestrates nested stacks

Parameters:
  Environment:
    Type: String
    Default: dev
  TemplatesBucket:
    Type: String
    Description: S3 bucket containing nested stack templates

Resources:
  # 调用 VPC 子栈
  VpcStack:
    Type: AWS::CloudFormation::Stack
    Properties:
      TemplateURL: !Sub 'https://${TemplatesBucket}.s3.amazonaws.com/child-vpc.yaml'
      Parameters:
        Environment: !Ref Environment

  # 使用子栈输出创建资源
  AppSecurityGroup:
    Type: AWS::EC2::SecurityGroup
    Properties:
      GroupDescription: App SG in nested VPC
      VpcId: !GetAtt VpcStack.Outputs.VpcId
      Tags:
        - Key: Name
          Value: !Sub '${Environment}-app-sg'

Outputs:
  VpcId:
    Description: VPC ID from nested stack
    Value: !GetAtt VpcStack.Outputs.VpcId
  SubnetId:
    Description: Subnet ID from nested stack
    Value: !GetAtt VpcStack.Outputs.SubnetId
```

### 4.4 Nested Stack 关键语法

**调用子栈**：

```yaml
Type: AWS::CloudFormation::Stack
Properties:
  TemplateURL: https://bucket.s3.amazonaws.com/template.yaml
  Parameters:
    ParamName: ParamValue
```

**获取子栈输出**：

```yaml
!GetAtt StackLogicalId.Outputs.OutputKey
```

### 4.5 Nested Stack 注意事项

| 注意点 | 说明 |
|--------|------|
| **模板存储** | 子模板必须在 S3 上 |
| **URL 格式** | 使用 HTTPS URL |
| **更新传播** | 更新父栈会检查所有子栈 |
| **删除顺序** | 删除父栈会自动删除所有子栈 |

> **S3 Bucket 准备**：在使用 Nested Stacks 前，需要先创建 S3 Bucket 存储子模板：
> ```bash
> # 创建存储模板的 S3 Bucket
> aws s3 mb s3://cfn-templates-${AWS_ACCOUNT_ID}-${AWS_REGION}
>
> # 上传子模板
> aws s3 cp nested-stacks/child-vpc.yaml s3://cfn-templates-xxx/
> ```

---

## Step 5 — 选择哪种方式？（5 分钟）

### 5.1 决策流程

![架构选择决策流程](images/decision-flow.png)

<details>
<summary>View ASCII source</summary>

```
┌─────────────────────────────────────────────────────────────────────┐
│                         架构选择决策流程                              │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│   组件需要独立部署吗？                                                │
│          │                                                          │
│     Yes  │   No                                                     │
│          │                                                          │
│          ▼                                                          │
│   ┌──────┴──────┐                                                   │
│   │             │                                                   │
│   ▼             ▼                                                   │
│   Cross-Stack   组件生命周期相同吗？                                  │
│   References           │                                            │
│                   Yes  │   No                                       │
│                        │                                            │
│                        ▼                                            │
│                 ┌──────┴──────┐                                     │
│                 │             │                                     │
│                 ▼             ▼                                     │
│             Nested        Cross-Stack                               │
│             Stacks        References                                │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

</details>

### 5.2 场景推荐

| 场景 | 推荐方式 | 理由 |
|------|----------|------|
| VPC + App 分离 | **Cross-Stack** | 不同生命周期、不同团队 |
| ALB + EC2 组合 | **Nested** | 紧密耦合、一起部署 |
| 多环境 VPC 复用 | **Cross-Stack** | 同一 VPC 多个应用引用 |
| 一次性完整环境 | **Nested** | 环境整体管理 |

### 5.3 日本企业常见模式

在日本的 SIer 项目中，常见的分层模式：

```
本番環境 (Production)
├── 01-network-stack       ← 网络团队管理、変更管理厳格
├── 02-security-stack      ← 安全团队管理
├── 03-database-stack      ← DBA 管理
└── 04-application-stack   ← 应用团队管理、頻繁更新
```

> 日本的运维现场，这种分层叫做「レイヤー分離」。
> 每个层有不同的変更管理流程和承認者。

---

## Step 6 — Service Catalog 简介（3 分钟）

> 企业级模板分发工具。

### 6.1 什么是 Service Catalog？

Service Catalog 让你：
- 预定义合规的 CloudFormation 模板
- 控制谁可以使用哪些模板
- 开发者自助申请资源

![Service Catalog 概念](images/service-catalog.png)

<details>
<summary>View ASCII source</summary>

```
┌─────────────────────────────────────────────────────────────────────┐
│                        Service Catalog 概念                          │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│   Platform Team                         Developers                  │
│   ┌─────────────────┐                   ┌─────────────────┐        │
│   │  创建 Product   │                   │  浏览 Catalog   │        │
│   │  (CFn Template) │                   │  选择 Product   │        │
│   │  设置权限       │ ──────────────▶  │  Launch Stack   │        │
│   │  版本管理       │                   │  自动合规!      │        │
│   └─────────────────┘                   └─────────────────┘        │
│                                                                     │
│   适用场景:                                                          │
│   • 大型企业标准化                                                    │
│   • 合规要求严格（金融/政府）                                          │
│   • 开发者自助服务                                                    │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

</details>

### 6.2 与多栈架构的关系

| 方式 | 用途 |
|------|------|
| **Cross-Stack** | 运维团队内部分层 |
| **Nested Stacks** | 模块化复用 |
| **Service Catalog** | 企业级模板分发 |

Service Catalog 的 Product 内部可以使用 Nested Stacks！

---

## Step 7 — 反模式警告（3 分钟）

### 7.1 避免这些问题

| 反模式 | 问题 | 解决方案 |
|--------|------|----------|
| **5000+ 行单体模板** | 难维护、部署慢 | 按生命周期分层 |
| **循环依赖** | Stack A → B → A | 重新设计依赖关系 |
| **忽略删除顺序** | 删除失败 | 先删应用、后删网络 |
| **硬编码 Export 名称** | 环境冲突 | 使用 `${Environment}-` 前缀 |

### 7.2 循环依赖示例

```yaml
# 错误示例 - 循环依赖！

# Stack A
Resources:
  ResourceA:
    Type: AWS::EC2::SecurityGroup
    Properties:
      GroupDescription: SG A
      VpcId: !ImportValue StackB-VpcId   # 引用 Stack B 的输出

Outputs:
  SecurityGroupA:
    Value: !Ref ResourceA
    Export:
      Name: StackA-SecurityGroupId

# Stack B
Resources:
  ResourceB:
    Type: AWS::EC2::SecurityGroup
    Properties:
      GroupDescription: SG B
      # 如果这里又引用 Stack A 的输出，就形成循环！
      SecurityGroupIngress:
        - SourceSecurityGroupId: !ImportValue StackA-SecurityGroupId  # 循环!

Outputs:
  VpcId:
    Value: !Ref VPC
    Export:
      Name: StackB-VpcId
```

**解决方案**：重新设计，让依赖单向流动（Network → App，不反向）。

---

## Step 8 — 动手练习：三层架构（10 分钟）

> 运用所学，部署一个完整的三层架构。

### 8.1 架构图

```
┌────────────────────────────────────────────┐
│              dev-app-stack                 │
│  ┌────────────────────────────────────┐   │
│  │  Security Group (App)              │   │
│  │  → ImportValue: dev-VpcId          │   │
│  │  → ImportValue: dev-ALBSecurityGroupId │
│  └────────────────────────────────────┘   │
└────────────────────────────────────────────┘
                    │
                    ▼
┌────────────────────────────────────────────┐
│              dev-alb-stack                 │
│  ┌────────────────────────────────────┐   │
│  │  ALB Security Group                │   │
│  │  → ImportValue: dev-VpcId          │   │
│  │  → ImportValue: dev-PublicSubnetIds│   │
│  │  Export: dev-ALBSecurityGroupId    │   │
│  └────────────────────────────────────┘   │
└────────────────────────────────────────────┘
                    │
                    ▼
┌────────────────────────────────────────────┐
│              dev-network-stack             │
│  ┌────────────────────────────────────┐   │
│  │  VPC, Subnets, IGW                 │   │
│  │  Export: dev-VpcId                 │   │
│  │  Export: dev-PublicSubnetIds       │   │
│  └────────────────────────────────────┘   │
└────────────────────────────────────────────┘
```

### 8.2 部署顺序

1. **Network Stack** → 导出 VPC、Subnet
2. **ALB Stack** → 导入 VPC，导出 SG
3. **App Stack** → 导入所有依赖

### 8.3 验证方法

在 CloudFormation Console 的 **Exports** 页面：
- 确认所有 Export 都存在
- 点击 Export 可以看到哪些 Stack 在使用它

---

## Step 9 — 清理资源（5 分钟）

> **重要**：按正确顺序删除！

### 9.1 删除顺序

**必须按依赖关系的反向删除**：

1. 先删除 `dev-app-stack`（依赖最多）
2. 再删除 `dev-alb-stack`（如果有）
3. 最后删除 `dev-network-stack`（被依赖最多）

### 9.2 删除步骤

1. 选择 `dev-app-stack` → **Delete**
2. 等待 `DELETE_COMPLETE`
3. 选择 `dev-network-stack` → **Delete**
4. 等待 `DELETE_COMPLETE`

### 9.3 如果删除失败

如果看到错误：

```
Export dev-VpcId cannot be deleted as it is in use by dev-app-stack
```

说明还有 Stack 在引用这个 Export，先删除依赖的 Stack。

---

## 职场小贴士

### 日本企业的多栈管理

在日本的 IT 现场，多栈架构通常涉及：

**1. 変更管理分離**

```
Network Stack → 変更管理委員会の承認必須（月1回）
App Stack    → チームリーダー承認で可（日次）
```

**2. 権限分離**

| 层 | 権限者 | IAM 设置 |
|---|--------|----------|
| Network | インフラチーム | 全权限 |
| App | 開発チーム | 只能操作 App Stack |

**3. 证迹管理**

每次 Stack 操作都需要记录：
- ChangeSet 截图
- 実行前/実行後の状態
- 承認者署名

### 常见日语术语

| 日语 | 读音 | 中文 | 英文 |
|------|------|------|------|
| 親スタック | おやすたっく | 父栈 | Parent Stack |
| 子スタック | こすたっく | 子栈 | Child Stack |
| 依存関係 | いぞんかんけい | 依赖关系 | Dependencies |
| レイヤー分離 | れいやーぶんり | 层分离 | Layer Separation |

---

## 检查清单

完成本课后，你应该能够：

- [ ] 解释单体模板的 3 个主要问题
- [ ] 使用 Export 和 ImportValue 实现跨栈引用
- [ ] 区分 Nested Stacks 和 Cross-Stack References 的适用场景
- [ ] 设计 Layer 化架构（Network → Foundations → App）
- [ ] 按正确顺序删除有依赖关系的 Stacks

---

## 面试准备

### よくある質問（常见面试题）

**Q: Nested Stacks と Cross-Stack References の違いは？**

A: Nested は親子関係で一緒に管理。親 Stack を削除すると子も全て削除される。Cross-Stack は独立したスタック間で値を共有。ライフサイクルが同じなら Nested、違うなら Cross-Stack を使う。

（Nested 是父子关系，一起管理。删除父 Stack 会删除所有子栈。Cross-Stack 是独立栈之间共享值。生命周期相同用 Nested，不同用 Cross-Stack。）

**Q: Export を削除できない場合はどうしますか？**

A: その Export を ImportValue している Stack を先に削除する必要がある。CloudFormation Console の Exports 画面で、どの Stack が使用しているか確認できる。

（需要先删除引用该 Export 的 Stack。可以在 CloudFormation Console 的 Exports 页面确认哪些 Stack 在使用。）

**Q: 大規模な CloudFormation 環境をどう設計しますか？**

A: ライフサイクル別にレイヤー分離（Network / Foundations / Application）。各レイヤーは Cross-Stack References で連携。変更頻度の高い Application 層は独立してデプロイ可能にする。

（按生命周期分层（Network / Foundations / Application）。各层通过 Cross-Stack References 连接。变更频率高的 Application 层可独立部署。）

---

## 延伸阅读

- [AWS CloudFormation - Nested Stacks](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/using-cfn-nested-stacks.html)
- [Cross-Stack References](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/walkthrough-crossstackref.html)
- [AWS Service Catalog](https://docs.aws.amazon.com/servicecatalog/latest/adminguide/introduction.html)
- 对比学习：[Terraform 08 - 项目布局](../../terraform/08-layout/)

---

## 下一步

你已经掌握了多栈架构设计。下一课我们将学习：

- Drift 检测（配置与现实不匹配）
- 资源导入（将现有资源纳入 CloudFormation 管理）
- Stack Refactoring（2025 新功能）

-> [05 - Drift 检测与资源导入](../05-drift-import/)

---

## 系列导航

[<- 03 - 现代工具](../03-modern-tools/) | [Home](../) | [05 - Drift 检测 ->](../05-drift-import/)
