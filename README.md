# cloud-atlas｜云上地图

A mapped guide to **AWS & Infra** — reproducible labs by **shiicho**.  
面向中文读者的云基础设施实战教程，每个课堂都提供「可复现」的代码与步骤。

## 仓库定位 / What this repo is
- 以 **小而快的课程**（bite-size lessons）讲解 AWS/基础设施知识  
- 侧重 **GUI 步骤 + 必要代码**，适合入门与复盘  
- 每个课程目录内含：CloudFormation 模板 / GUI 图文教程 /（可选）脚本

## 目录结构｜Repository Structure
```
<repo-root>/
├─ 20250812_aws_ssm_01/           # 课程目录（YYYYMMDD\_topic\_xx）
│  ├─ cfn/                        # 基础设施模板（CloudFormation 等）
│  │  └─ ssm-lab-minimal.yaml
│  ├─ index.md                    # 该课程的入口与导航
│  ├─ 01\_cfn\_deploy.md          # 子步骤：数字开头便于排序
│  ├─ 02\_ssm\_session.md
│  ├─ 03\_run\_command.md
│  └─ img/                        # 截图素材（按子目录区分）
└─ README.md                      # 本文件
```

命名规则：
- 课程目录：`YYYYMMDD_topic_nn/`（例如 `20250812_aws_ssm_01`）  
- 子文档：`01_xxx.md / 02_xxx.md ...`  
- 截图：`img/<子章节>/序号_简述.png`

## 当前课程 / Current Lessons

- **[20250812_aws_ssm_01 – AWS Systems Manager 入门（GUI）](./20250812_aws_ssm_01/README.md)**
  - [01 · CloudFormation 部署最小 SSM 实验环境](./20250812_aws_ssm_01/01_cfn_deploy.md)
  - [02 · Session Manager 免密登录 EC2（浏览器 Shell）](./20250812_aws_ssm_01/02_ssm_session.md)
  - [03 · Run Command 批量执行脚本（前后对比：安装 htop）](./20250812_aws_ssm_01/03_run_command.md)
  - [04 · Parameter Store 参数存储（写 MOTD 示例）](./20250812_aws_ssm_01/04_parameter_store.md)
  - [05 · 会话日志落地（CloudWatch Logs / S3）](./20250812_aws_ssm_01/05_session_logging.md)
  - 更多小节将陆续补充（会话/命令日志落地、纯私网 VPC Endpoint、托管 on-prem 等）

## 前置条件 / Prerequisites
- 可用的 **AWS 账号**（建议区域 `ap-northeast-1` 东京）  
- 学习环境可使用 **AdministratorAccess**（正式环境请最小权限）  
- 若仅按 GUI 操作，可暂不安装 CLI；后续会提供独立 CLI 课程

## 镜像仓库 / Mirrors
- GitHub：**[shiicho/cloud-atlas](https://github.com/shiicho/cloud-atlas)**  
- 中国大陆镜像：**[shiicho/cloud-atlas（Gitee）](https://gitee.com/shiicho/cloud-atlas)**  

> 如果你也在大陆网络环境，建议同时拉取镜像仓库以获得更稳定的访问。

## 许可证 / License
**[MIT License](./LICENSE)** © 2025 shiicho