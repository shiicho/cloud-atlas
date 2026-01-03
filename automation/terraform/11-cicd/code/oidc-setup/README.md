# OIDC Setup for GitHub Actions

本目录包含配置 AWS OIDC Provider 的 CloudFormation 模板。

## 什么是 OIDC？

OIDC (OpenID Connect) 允许 GitHub Actions 使用临时凭证访问 AWS，无需存储长期 Access Key。

## 部署步骤

### 1. 部署 CloudFormation Stack

```bash
aws cloudformation deploy \
  --template-file github-oidc.yaml \
  --stack-name github-oidc-terraform \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides \
    GitHubOrg=your-org \
    RepoName=your-repo
```

### 2. 获取 Role ARN

```bash
aws cloudformation describe-stacks \
  --stack-name github-oidc-terraform \
  --query 'Stacks[0].Outputs[?OutputKey==`RoleArn`].OutputValue' \
  --output text
```

### 3. 添加到 GitHub Secrets

1. 进入 GitHub 仓库 > Settings > Secrets and variables > Actions
2. 添加 Secret: `AWS_ROLE_ARN`
3. 值为上一步获取的 ARN

## 文件说明

| 文件 | 说明 |
|------|------|
| `github-oidc.yaml` | CloudFormation 模板，创建 OIDC Provider 和 IAM Role |

## 安全注意事项

- 信任策略限制了只有特定仓库可以 Assume Role
- IAM 权限应该遵循最小权限原则
- 定期审计 CloudTrail 日志

## 参考链接

- [GitHub Docs: Configuring OIDC in AWS](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/configuring-openid-connect-in-amazon-web-services)
- [AWS Blog: Use IAM roles with OIDC](https://aws.amazon.com/blogs/security/use-iam-roles-to-connect-github-actions-to-actions-in-aws/)
