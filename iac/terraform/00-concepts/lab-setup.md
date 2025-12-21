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
cd iac/terraform/01-first-resource/cfn
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

#### 1. 安装 Session Manager 插件

**macOS:**
```bash
curl "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/mac/sessionmanager-bundle.zip" -o "sessionmanager-bundle.zip"
unzip sessionmanager-bundle.zip
sudo ./sessionmanager-bundle/install -i /usr/local/sessionmanagerplugin -b /usr/local/bin/session-manager-plugin
```

**Windows:**
下载并运行：https://s3.amazonaws.com/session-manager-downloads/plugin/latest/windows/SessionManagerPluginSetup.exe

**Linux:**
```bash
curl "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/ubuntu_64bit/session-manager-plugin.deb" -o "session-manager-plugin.deb"
sudo dpkg -i session-manager-plugin.deb
```

#### 2. 配置 SSH Config

编辑 `~/.ssh/config`（Windows: `C:\Users\你的用户名\.ssh\config`）：

```
Host terraform-lab
    HostName i-你的实例ID
    User ec2-user
    ProxyCommand aws ssm start-session --target %h --document-name AWS-StartSSHSession --parameters 'portNumber=%p' --region ap-northeast-1
```

#### 3. 生成 SSH Key（如果没有）

```bash
ssh-keygen -t ed25519 -C "terraform-lab"
```

#### 4. 上传公钥到实例

```bash
# 先通过 SSM 连接
aws ssm start-session --target i-你的实例ID --region ap-northeast-1

# 在实例内执行
sudo su - ec2-user
mkdir -p ~/.ssh
echo "你的公钥内容" >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
exit
exit
```

#### 5. VS Code 连接

1. 打开 VS Code
2. `Ctrl+Shift+P` → "Remote-SSH: Connect to Host"
3. 选择 `terraform-lab`
4. 等待连接完成

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
Terraform v1.9.x
aws-cli/2.x.x
git version 2.x.x
```

---

## 克隆课程示例代码

```bash
cd ~
git clone --filter=blob:none --sparse https://github.com/shiicho/cloud-atlas ~/cloud-atlas
cd ~/cloud-atlas && git sparse-checkout set iac/terraform
ln -s ~/cloud-atlas/iac/terraform ~/terraform-examples
ls terraform-examples/
```

```
lesson-01-first-resource/
lesson-02-state/
lesson-03-variables/
...
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
<summary>❓ VS Code 连接超时</summary>

1. 确认 Session Manager 插件已安装：
   ```bash
   session-manager-plugin --version
   ```

2. 确认 SSH Config 中的 Instance ID 正确

3. 确认公钥已上传到实例

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
