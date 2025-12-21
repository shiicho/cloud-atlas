# 04 - 多栈架构代码

本目录包含 CloudFormation 多栈架构示例模板。

## 文件结构

```
code/
├── network-stack.yaml       # 网络层模板 (VPC, Subnets)
├── app-stack.yaml           # 应用层模板 (Security Groups)
└── nested-stacks/
    ├── parent.yaml          # 父栈模板
    └── child-vpc.yaml       # 子栈模板 (VPC Module)
```

## 使用方式

### Cross-Stack Reference (推荐)

按顺序部署独立栈：

```bash
# 1. 部署网络层（先部署，导出 VpcId 等）
aws cloudformation create-stack \
  --stack-name dev-network-stack \
  --template-body file://network-stack.yaml \
  --parameters ParameterKey=Environment,ParameterValue=dev

# 等待完成
aws cloudformation wait stack-create-complete --stack-name dev-network-stack

# 2. 部署应用层（引用网络层的 Exports）
aws cloudformation create-stack \
  --stack-name dev-app-stack \
  --template-body file://app-stack.yaml \
  --parameters ParameterKey=Environment,ParameterValue=dev

# 3. 清理（按反向顺序）
aws cloudformation delete-stack --stack-name dev-app-stack
aws cloudformation wait stack-delete-complete --stack-name dev-app-stack
aws cloudformation delete-stack --stack-name dev-network-stack
```

### Nested Stacks

```bash
# 1. 上传子栈模板到 S3
aws s3 cp nested-stacks/child-vpc.yaml s3://your-bucket/nested-stacks/

# 2. 部署父栈
aws cloudformation create-stack \
  --stack-name dev-nested-stack \
  --template-body file://nested-stacks/parent.yaml \
  --parameters \
    ParameterKey=Environment,ParameterValue=dev \
    ParameterKey=TemplatesBucket,ParameterValue=your-bucket

# 3. 清理（删除父栈会自动删除所有子栈）
aws cloudformation delete-stack --stack-name dev-nested-stack
```

## 主要区别

| 特性 | Cross-Stack | Nested Stacks |
|------|-------------|---------------|
| 关系 | 兄弟 | 父子 |
| 部署 | 独立 | 一起 |
| 删除 | 按顺序 | 自动级联 |
| 适用 | 不同生命周期 | 相同生命周期 |
