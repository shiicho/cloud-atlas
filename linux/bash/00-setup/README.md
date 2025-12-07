# 00 · 环境准备（Environment Setup）

> **目标**：一键部署 Bash 练习环境
> **前置**：了解 Session Manager 基本操作（参考 [SSM 02 · 免密登录](../../../aws/ssm/02-session-manager/)）
> **时间**：5 分钟
> **费用**：t3.micro 免费套餐；用完记得删除 Stack

## 概述

本课程使用 AWS EC2 作为练习环境。通过 CloudFormation 一键部署：
- Amazon Linux 2023（Bash 5.2+）
- Session Manager 浏览器终端（无需 SSH 密钥）

> 💡 **已完成 SSM 系列？** 如果你已经有运行中的 EC2 实例，可以直接使用，跳过 Step 1。

## Step 1 — 部署 CloudFormation Stack

**操作**：打开 AWS Console → CloudFormation → Create stack

1. 选择 **Upload a template file**
2. 上传 [`cfn/bash-lab.yaml`](./cfn/bash-lab.yaml)
3. Stack name: `bash-lab`
4. 保持默认参数，点击 **Next** → **Next**
5. 勾选 **I acknowledge that AWS CloudFormation might create IAM resources**
6. 点击 **Submit**

等待 3-5 分钟，状态变为 `CREATE_COMPLETE`。

## Step 2 — 连接 EC2

使用 Session Manager 连接实例（无需 SSH 密钥）：

1. 打开 EC2 Console → Instances
2. 选择 `bash-lab-ec2` → 点击 **Connect**
3. 选择 **Session Manager** 标签 → 点击 **Connect**

浏览器会打开一个终端窗口。

> 📖 **详细步骤**：参考 [SSM 02 · Session Manager 免密登录](../../../aws/ssm/02-session-manager/)

## Step 3 — 验证环境

在终端中执行：

```bash
# 查看 Bash 版本
bash --version
# 输出: GNU bash, version 5.2.x ...

# 查看当前用户
whoami
# 输出: ssm-user

# 切换到 home 目录
cd ~
pwd
# 输出: /home/ssm-user
```

## Step 4 — 创建练习目录

```bash
# 创建课程练习目录
mkdir -p ~/bash-course
cd ~/bash-course

# 确认位置
pwd
# 输出: /home/ssm-user/bash-course
```

从现在开始，所有练习都在 `~/bash-course` 目录进行。

## 环境说明

| 项目 | 值 |
|------|-----|
| OS | Amazon Linux 2023 |
| Bash | 5.2+ |
| 用户 | ssm-user |
| 练习目录 | ~/bash-course |
| 编辑器 | nano, vim |

## 清理资源

**练习结束后务必删除，避免产生费用：**

1. CloudFormation Console → Stacks
2. 选择 `bash-lab`
3. 点击 **Delete**
4. 确认删除

约 5 分钟后，所有资源自动清理完成。

## 常见问题

### Session Manager 连接失败？

- 等待 EC2 完全启动（2-3 分钟）
- 确认 Stack 状态为 `CREATE_COMPLETE`
- 检查 EC2 状态为 `running`
- 更多排查：参考 [SSM 02 · Session Manager 免密登录](../../../aws/ssm/02-session-manager/)

### 想用自己的 Linux 环境？

可以！只需确保：
- Bash 4.0+ (推荐 5.0+)
- 有 root 或 sudo 权限（部分课程需要）

查看版本：`bash --version`

## 下一步

环境准备好了！开始 [01 · 第一个脚本](../01-first-script/)

## 系列导航

← [系列首页](../) | [01 · 第一个脚本](../01-first-script/) →
