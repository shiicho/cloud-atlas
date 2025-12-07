# cloud-atlas｜云上地图

A mapped guide to **Cloud & Infrastructure** — reproducible labs by **shiicho**.
面向中文读者的云基础设施实战教程，每个课堂都提供「可复现」的代码与步骤。

## 仓库定位 / What this repo is
- 以 **小而快的课程**（bite-size lessons）讲解云/基础设施知识
- 侧重 **GUI 步骤 + 必要代码**，适合入门与复盘
- 每个课程目录内含：IaC 模板 / GUI 图文教程 /（可选）脚本

## 目录结构｜Repository Structure
```
cloud-atlas/
├── aws/
│   └── ssm/                # Systems Manager 系列
│       ├── 01-cfn-deploy/
│       ├── 02-session-manager/
│       └── ...
├── glossary/               # 术语词典
└── README.md
```

## 课程目录 / Course Index

### AWS
- **[Systems Manager 入门（GUI 版）](./aws/ssm/)**
  - [01 · CloudFormation 部署最小 SSM 实验环境](./aws/ssm/01-cfn-deploy/)
  - [02 · Session Manager 免密登录 EC2](./aws/ssm/02-session-manager/)
  - [03 · Run Command 批量执行脚本](./aws/ssm/03-run-command/)
  - [04 · Parameter Store 参数存储](./aws/ssm/04-parameter-store/)
  - [05 · 会话日志落地（CloudWatch）](./aws/ssm/05-session-logging/)
  - [06 · State Manager 状态管理器](./aws/ssm/06-state-manager/)
  - [07 · Hybrid 托管 On-Prem](./aws/ssm/07-hybrid/) *(planned)*

## 前置条件 / Prerequisites
- 可用的 **AWS 账号**（建议区域 `ap-northeast-1` 东京）
- 学习环境可使用 **AdministratorAccess**（正式环境请最小权限）
- 若仅按 GUI 操作，可暂不安装 CLI

## 镜像仓库 / Mirrors
- GitHub：**[shiicho/cloud-atlas](https://github.com/shiicho/cloud-atlas)**
- 中国大陆镜像：**[shiicho/cloud-atlas（Gitee）](https://gitee.com/shiicho/cloud-atlas)**

> 如果你也在大陆网络环境，建议同时拉取镜像仓库以获得更稳定的访问。

## 许可证 / License
**[MIT License](./LICENSE)** © 2025 shiicho
