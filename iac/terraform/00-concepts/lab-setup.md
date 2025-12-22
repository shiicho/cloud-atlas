# 环境准备 - Terraform 学习实验室

> **目标**：部署一个预装 Terraform 的 EC2 实例，通过 SSM 或 VS Code Remote 连接
> **时间**：15-20 分钟
> **费用**：t3.small 约 $0.02/小时（用完即删）

---

## 前置要求

- [ ] AWS 账户（有管理员权限或足够的 IAM 权限）
- [ ] 本地已安装 AWS CLI 并配置凭证
- [ ] （可选）VS Code + Remote-SSH 插件

验证 AWS CLI：

```bash
aws sts get-caller-identity
```

看到你的 Account ID 和 ARN？继续下一步！

---

## 方式一：CloudFormation 一键部署（推荐）

### Step 1 — 下载模板

模板位置：[terraform-lab.yaml](./cfn/terraform-lab.yaml)

或者直接使用 AWS CLI：

```bash
# 克隆课程代码（如果尚未克隆）
git clone --filter=blob:none --sparse https://github.com/shiicho/cloud-atlas ~/cloud-atlas
cd ~/cloud-atlas
git sparse-checkout set iac/terraform
cd iac/terraform/00-concepts/cfn
```

### Step 2 — 部署 Stack

```bash
aws cloudformation create-stack \
  --stack-name terraform-lab \
  --template-body file://terraform-lab.yaml \
  --capabilities CAPABILITY_NAMED_IAM \
  --region ap-northeast-1
```

等待部署完成（约 3-5 分钟）：

```bash
aws cloudformation wait stack-create-complete \
  --stack-name terraform-lab \
  --region ap-northeast-1

echo "✅ 部署完成！"
```

### Step 3 — 获取实例 ID

```bash
aws cloudformation describe-stacks \
  --stack-name terraform-lab \
  --region ap-northeast-1 \
  --query 'Stacks[0].Outputs[?OutputKey==`InstanceId`].OutputValue' \
  --output text
```

记下这个 Instance ID（形如 `i-0abc123def456`）。

---

## 连接到实验环境

### 方式 A：SSM Session Manager（最简单）

```bash
aws ssm start-session \
  --target i-你的实例ID \
  --region ap-northeast-1
```

连接成功后，切换到 ec2-user：

```bash
sudo su - ec2-user
```

### 方式 B：VS Code Remote-SSH（推荐日常开发）

> 📖 **详细指南**: 完整的 VS Code 远程开发设置请参考 [VS Code 远程开发指南](../../../references/vscode-remote-dev/)

#### 快速设置

**1. 安装 Session Manager 插件**

| 平台 | 命令 |
|------|------|
| **Windows** | `winget install Amazon.SessionManagerPlugin` 或 [下载 MSI](https://s3.amazonaws.com/session-manager-downloads/plugin/latest/windows/SessionManagerPluginSetup.exe) |
| **macOS** | `brew install --cask session-manager-plugin` |
| **Linux** | `sudo dpkg -i session-manager-plugin.deb` ([下载](https://s3.amazonaws.com/session-manager-downloads/plugin/latest/ubuntu_64bit/session-manager-plugin.deb)) |

**2. 配置 SSH Config**

编辑 `~/.ssh/config`（Windows: `C:\Users\你的用户名\.ssh\config`）

> ⚠️ **Windows 用户注意**: Windows 和 macOS/Linux 配置不同！详见 [故障排除](../../../references/vscode-remote-dev/troubleshooting.md#windows-专属问题)

**Windows 配置（无引号）:**
```ssh-config
Host terraform-lab
    HostName i-你的实例ID
    User ec2-user
    ProxyCommand aws ssm start-session --target %h --document-name AWS-StartSSHSession --parameters portNumber=%p --region ap-northeast-1
```

**macOS/Linux 配置（带引号）:**
```ssh-config
Host terraform-lab
    HostName i-你的实例ID
    User ec2-user
    ProxyCommand aws ssm start-session --target %h --document-name AWS-StartSSHSession --parameters "portNumber=%p" --region ap-northeast-1
```

**3. 生成 SSH Key（如果没有）**

```bash
ssh-keygen -t ed25519 -C "terraform-lab"
```

**4. 上传公钥到实例**

```bash
# 通过 SSM 连接
aws ssm start-session --target i-你的实例ID --region ap-northeast-1

# 在实例内执行
sudo su - ec2-user
mkdir -p ~/.ssh && chmod 700 ~/.ssh
echo "你的公钥内容" >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
exit
exit
```

**5. VS Code 连接**

1. 打开 VS Code
2. `Ctrl+Shift+P` → "Remote-SSH: Connect to Host"
3. 选择 `terraform-lab`
4. 如果出现登录提示，可以选择 GitHub 登录或按 Esc 跳过
5. 等待连接完成（首次需要几分钟安装 VS Code Server）

> 💡 **遇到问题？** 查看 [故障排除指南](../../../references/vscode-remote-dev/troubleshooting.md)

---

## 验证环境

连接后，验证工具已安装：

```bash
terraform version
aws --version
git --version
```

应该看到：

```
Terraform v1.14.x
aws-cli/2.x.x
git version 2.x.x
```

---

## 克隆课程示例代码

```bash
git clone --filter=blob:none --sparse https://github.com/shiicho/cloud-atlas ~/cloud-atlas
cd ~/cloud-atlas && git sparse-checkout set iac/terraform
ls ~/cloud-atlas/iac/terraform/
```

```
00-concepts/
01-first-resource/
02-state/
03-hcl/
...
```

每个课程直接进入对应目录即可：

```bash
cd ~/cloud-atlas/iac/terraform/01-first-resource/code
```

---

## 清理环境

完成学习后，删除 Stack 以节省费用：

```bash
aws cloudformation delete-stack \
  --stack-name terraform-lab \
  --region ap-northeast-1

aws cloudformation wait stack-delete-complete \
  --stack-name terraform-lab \
  --region ap-northeast-1

echo "✅ 环境已清理！"
```

---

## 常见问题

<details>
<summary>❓ SSM 连接失败：TargetNotConnected</summary>

实例可能还在启动中。等待 2-3 分钟后重试。

检查实例状态：
```bash
aws ec2 describe-instances \
  --instance-ids i-你的实例ID \
  --query 'Reservations[0].Instances[0].State.Name' \
  --output text
```

应该显示 `running`。

</details>

<details>
<summary>❓ VS Code 连接超时 / Error parsing parameter</summary>

**Windows 常见问题:** 如果看到 `Error parsing parameter '--parameters'` 错误，是因为 SSH 配置中的引号问题。

**解决方案:** Windows 用户使用**无引号**的配置：
```ssh-config
ProxyCommand aws ssm start-session --target %h --document-name AWS-StartSSHSession --parameters portNumber=%p --region ap-northeast-1
```

**其他检查:**
1. Session Manager 插件已安装：`session-manager-plugin --version`
2. SSH Config 中的 Instance ID 正确
3. 公钥已上传到实例

> 更多问题请参考 [故障排除指南](../../../references/vscode-remote-dev/troubleshooting.md)

</details>

<details>
<summary>❓ terraform 命令未找到</summary>

UserData 脚本可能还在执行。等待 3-5 分钟后重试。

检查脚本是否完成：
```bash
cat /var/log/userdata-complete.log
```

</details>

---

## 下一步

环境准备好了！开始第一课：

→ [01 · 安装配置与第一个资源](../01-first-resource/)

---

## 系列导航

[Home](../) | [01 · 第一个资源 →](../01-first-resource/)
