# AWS Systems Manager 入门（GUI 版）

> 目标：用 **CloudFormation（控制台）** 一键搭好最小 SSM 实验环境，然后用 **Session Manager / Run Command / Parameter Store / 会话日志落地** 完成常见场景演练。
> 区域：建议 `ap-northeast-1`（东京）。
> 成本：t3.micro + 基础网络，费用很低；**完成请删除堆栈**。

## 课程目录

- [01 · CloudFormation 部署最小实验环境](./01-cfn-deploy/)
- [02 · Session Manager 免密登录 EC2（浏览器 Shell）](./02-session-manager/)
- [03 · Run Command 批量执行脚本（示例：安装 htop）](./03-run-command/)
- [04 · Parameter Store（创建/读取/在脚本中使用）](./04-parameter-store/)
- [05 · 会话日志落地（CloudWatch Logs / S3）](./05-session-logging/)
- [06 · State Manager 状态管理器（Ensure + Check）](./06-state-manager/)
- [07 · Hybrid 托管 On-Prem / Docker 主机](./07-hybrid/) *(placeholder)*

## CloudFormation 模板

- [ssm-lab-minimal.yaml](./01-cfn-deploy/cfn/ssm-lab-minimal.yaml) → 第 01 ~ 04 课用
- [ssm-lab-minimal-v2.yaml](./01-cfn-deploy/cfn/ssm-lab-minimal-v2.yaml) → 第 05 课用

> 注：AWS 中文控制台与英文控制台按钮文字略有差异；文档以**中文控制台**为准，并在必要处给出（英文）对照。
