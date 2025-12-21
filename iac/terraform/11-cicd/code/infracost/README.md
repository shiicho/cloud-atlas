# Infracost Configuration

本目录包含 Infracost 配置文件，用于在 PR 中显示基础设施成本变化。

## 什么是 Infracost？

Infracost 是一个开源工具，可以在代码变更前估算云基础设施成本。它支持：
- AWS、Azure、GCP
- Terraform、Terragrunt、Pulumi
- GitHub、GitLab、Azure DevOps

## 安装

```bash
# macOS
brew install infracost

# Linux
curl -fsSL https://raw.githubusercontent.com/infracost/infracost/master/scripts/install.sh | sh

# Windows (使用 Chocolatey)
choco install infracost
```

## 配置

### 1. 获取 API Key

```bash
infracost auth login
```

### 2. 添加到 GitHub Secrets

1. 进入 GitHub 仓库 > Settings > Secrets and variables > Actions
2. 添加 Secret: `INFRACOST_API_KEY`
3. 值为上一步获取的 API Key

## 本地使用

```bash
# 查看成本明细
infracost breakdown --path .

# 比较两个版本的成本差异
infracost diff --path . --compare-to baseline.json
```

## 文件说明

| 文件 | 说明 |
|------|------|
| `infracost.yml` | Infracost 配置文件，定义项目路径和设置 |

## 定价数据

Infracost 使用 AWS 公开定价 API 获取价格数据。对于以下资源，它可能需要额外配置：

- Reserved Instances / Savings Plans（需要配置 usage 文件）
- Spot Instances（价格波动）
- Free Tier（默认不考虑免费额度）

## 参考链接

- [Infracost 官方文档](https://www.infracost.io/docs/)
- [Supported Resources](https://www.infracost.io/docs/supported_resources/overview/)
- [Usage-Based Resources](https://www.infracost.io/docs/features/usage_based_resources/)
