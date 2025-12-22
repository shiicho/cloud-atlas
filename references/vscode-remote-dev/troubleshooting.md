# VS Code 远程开发 - 故障排除

> 本文档收集常见问题及解决方案。按问题类型分类，方便快速定位。

---

## 目录

- [Windows 专属问题](#windows-专属问题)
- [连接问题](#连接问题)
- [认证问题](#认证问题)
- [性能问题](#性能问题)
- [VS Code Server 问题](#vs-code-server-问题)
- [AWS SSM 专属问题](#aws-ssm-专属问题)
- [平台特定问题](#平台特定问题)

---

## Windows 专属问题

### 问题 #1：ProxyCommand 引号解析错误（最常见！）

**症状**：
```
Error parsing parameter '--parameters': Expected: '=', received: '"' for input: "portNumber=22"
```

**原因**：Windows OpenSSH 客户端对引号处理方式不同

**解决方案**：

```ssh-config
# Windows: 不使用引号
Host i-* mi-*
    ProxyCommand aws ssm start-session --target %h --document-name AWS-StartSSHSession --parameters portNumber=%p --region ap-northeast-1

# macOS/Linux: 使用引号
Host i-* mi-*
    ProxyCommand aws ssm start-session --target %h --document-name AWS-StartSSHSession --parameters "portNumber=%p" --region ap-northeast-1
```

**快速验证**：
```powershell
# Windows PowerShell 测试
ssh -v i-your-instance-id
```

### 问题 #2：SSH Config 文件路径

**症状**：VS Code 找不到 SSH 配置

**解决方案**：

| 位置 | 路径 |
|------|------|
| 用户配置（推荐） | `C:\Users\你的用户名\.ssh\config` |
| 系统配置 | `C:\ProgramData\ssh\ssh_config` |

确保：
1. 文件名是 `config`（没有扩展名）
2. 使用正斜杠 `/` 或双反斜杠 `\\`

```ssh-config
# 正确的 Windows 路径格式
IdentityFile C:/Users/username/.ssh/my-key.pem
# 或
IdentityFile C:\\Users\\username\\.ssh\\my-key.pem
```

### 问题 #3：AWS CLI 路径未识别

**症状**：
```
'aws' is not recognized as an internal or external command
```

**解决方案**：

1. 确认 AWS CLI 安装：
   ```powershell
   where aws
   ```

2. 如果已安装但未识别，重启 VS Code 或终端

3. 使用完整路径：
   ```ssh-config
   ProxyCommand "C:\Program Files\Amazon\AWSCLIV2\aws.exe" ssm start-session ...
   ```

### 问题 #4：Session Manager Plugin 路径

**症状**：
```
SessionManagerPlugin is not found.
```

**解决方案**：

1. 确认安装：
   ```powershell
   session-manager-plugin --version
   ```

2. 如果未识别，添加到 PATH 或重装：
   ```powershell
   # 使用 winget 安装/重装
   winget install Amazon.SessionManagerPlugin
   ```

3. 重启终端/VS Code

---

## 连接问题

### 问题：Connection timed out

**可能原因及排查**：

| 原因 | 排查命令 | 解决方案 |
|------|----------|----------|
| 实例未运行 | `aws ec2 describe-instance-status --instance-ids i-xxx` | 启动实例 |
| SSM Agent 未运行 | `aws ssm describe-instance-information` | 重启 SSM Agent |
| IAM 权限不足 | `aws sts get-caller-identity` | 检查 IAM Policy |
| 网络不通 | `aws ssm start-session --target i-xxx` | 检查 VPC 配置 |
| 区域不匹配 | 检查 SSH Config 中的 `--region` | 修正区域 |

**完整排查流程**：

```bash
# Step 1: 检查实例状态
aws ec2 describe-instance-status \
    --instance-ids i-0123456789abcdef0 \
    --query 'InstanceStatuses[*].[InstanceId,InstanceState.Name,InstanceStatus.Status]'

# Step 2: 检查 SSM Agent 在线状态
aws ssm describe-instance-information \
    --filters "Key=InstanceIds,Values=i-0123456789abcdef0" \
    --query 'InstanceInformationList[*].[InstanceId,PingStatus,AgentVersion]'

# Step 3: 尝试直接 SSM 连接
aws ssm start-session --target i-0123456789abcdef0 --region ap-northeast-1

# Step 4: 如果 Step 3 成功但 VS Code 失败，问题在 SSH 层
ssh -vvv i-0123456789abcdef0  # 详细日志
```

### 问题：Connection refused

**可能原因**：

1. **SSH 服务未运行**：
   ```bash
   # 通过 SSM 登录检查
   aws ssm start-session --target i-xxx
   sudo systemctl status sshd
   sudo systemctl start sshd
   ```

2. **安全组阻止**（直接 SSH 时）：
   - SSM 不需要 22 端口
   - 直接 SSH 需要入站规则

### 问题：Connection reset by peer

**可能原因**：

1. **服务器过载**：检查实例 CPU/内存
2. **SSH 配置问题**：检查 `/etc/ssh/sshd_config`
3. **防火墙规则**：检查 iptables/firewalld

---

## 认证问题

### 问题：Permission denied (publickey)

**症状**：
```
Permission denied (publickey,gssapi-keyex,gssapi-with-mic).
```

**排查步骤**：

```bash
# 1. 检查密钥文件存在且权限正确
ls -la ~/.ssh/your-key.pem
# 应该是 -rw------- (600)

# 2. 检查公钥是否在服务器上
aws ssm start-session --target i-xxx
cat ~/.ssh/authorized_keys

# 3. 检查用户名是否正确
# Amazon Linux: ec2-user
# Ubuntu: ubuntu
# RHEL: ec2-user 或 root
```

**解决方案**：

**方法 1：添加公钥到服务器**
```bash
# 登录服务器
aws ssm start-session --target i-xxx

# 添加公钥
echo "ssh-ed25519 AAAA... your-email" >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
chmod 700 ~/.ssh
```

**方法 2：使用 EC2 Instance Connect**
```bash
# 推送临时公钥（60 秒有效）
aws ec2-instance-connect send-ssh-public-key \
    --instance-id i-xxx \
    --instance-os-user ec2-user \
    --ssh-public-key file://~/.ssh/id_ed25519.pub \
    --region ap-northeast-1

# 立即连接
ssh ec2-user@i-xxx
```

### 问题：密钥格式不正确

**症状**：
```
Load key "xxx.pem": invalid format
```

**解决方案**：

```bash
# 检查密钥格式
head -1 ~/.ssh/your-key.pem

# 正确的 RSA 格式
# -----BEGIN RSA PRIVATE KEY-----

# 正确的 OpenSSH 格式
# -----BEGIN OPENSSH PRIVATE KEY-----

# 如果是 PPK 格式（PuTTY），需要转换
# Windows: 使用 PuTTYgen 转换
# Linux: puttygen key.ppk -O private-openssh -o key.pem
```

### 问题：IAM 权限不足

**症状**：
```
An error occurred (AccessDeniedException) when calling the StartSession operation
```

**最小 IAM Policy**：

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ssm:StartSession",
        "ssm:TerminateSession",
        "ssm:ResumeSession"
      ],
      "Resource": [
        "arn:aws:ec2:*:*:instance/*",
        "arn:aws:ssm:*:*:document/AWS-StartSSHSession"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "ssm:DescribeSessions",
        "ssm:GetConnectionStatus",
        "ssm:DescribeInstanceInformation"
      ],
      "Resource": "*"
    }
  ]
}
```

---

## 性能问题

### 问题：ENOSPC - no space left on device

**症状**：
```
Error: ENOSPC: no space left on device, watch
```

**原因**：inotify 监控数量达到限制

**解决方案**：

```bash
# 查看当前限制
cat /proc/sys/fs/inotify/max_user_watches

# 临时增加（立即生效）
sudo sysctl fs.inotify.max_user_watches=524288

# 永久增加
echo "fs.inotify.max_user_watches=524288" | sudo tee -a /etc/sysctl.conf
sudo sysctl -p
```

### 问题：编辑器响应缓慢

**可能原因及解决**：

| 原因 | 解决方案 |
|------|----------|
| 网络延迟高 | 选择更近的区域 |
| 服务器资源不足 | 升级实例类型 |
| 扩展过多 | 只安装必要扩展 |
| 大文件监控 | 配置 `files.watcherExclude` |

**优化配置**：

```json
// .vscode/settings.json
{
  "files.watcherExclude": {
    "**/node_modules/**": true,
    "**/.terraform/**": true,
    "**/.git/objects/**": true,
    "**/vendor/**": true
  },
  "search.exclude": {
    "**/node_modules": true,
    "**/.terraform": true
  }
}
```

### 问题：打开大文件后永久卡顿

**症状**：打开大文件（>10MB）后，编辑器无响应

**原因**：VS Code 已知 bug (#185413)

**解决方案**：
1. 重启 VS Code
2. 避免直接打开大文件
3. 使用命令行查看大文件：`less`, `tail -f`

### 问题：频繁断开

**解决方案**：

```ssh-config
# SSH Config 添加心跳
Host *
    ServerAliveInterval 60
    ServerAliveCountMax 3
```

---

## VS Code Server 问题

### 问题：VS Code Server 安装失败

**症状**：
```
Failed to install VS Code Server
```

**排查步骤**：

```bash
# 1. 检查服务器架构
uname -m
# x86_64 或 aarch64

# 2. 检查磁盘空间
df -h /home

# 3. 检查网络（需要下载 VS Code Server）
curl -I https://update.code.visualstudio.com

# 4. 手动清理旧版本
rm -rf ~/.vscode-server
```

### 问题：glibc 版本不足

**症状**：
```
/lib64/libc.so.6: version 'GLIBC_2.28' not found
```

**原因**：VS Code 1.99+ 需要 glibc 2.28+

**检查版本**：
```bash
ldd --version
# ldd (GNU libc) 2.xx
```

**解决方案**：

| 情况 | 方案 |
|------|------|
| Amazon Linux 2 | 升级到 Amazon Linux 2023 |
| CentOS 7 | 升级到 CentOS 8+ 或使用旧版 VS Code |
| 无法升级 | 使用 VS Code 1.98 或更早版本 |

**使用旧版 VS Code**：
1. 下载特定版本：https://code.visualstudio.com/updates
2. 或设置 `remote.SSH.serverDownloadUrlTemplate`

### 问题：VS Code Server 占用过多内存

**解决方案**：

```bash
# 查看占用
ps aux | grep vscode-server

# 限制内存（通过 cgroups）
# 或减少打开的项目和扩展
```

---

## AWS SSM 专属问题

### 问题：SSM Agent 离线

**症状**：
```
Instance i-xxx is not connected
```

**排查**：

```bash
# 检查 SSM Agent 状态
aws ssm describe-instance-information \
    --filters "Key=InstanceIds,Values=i-xxx"
```

**常见原因及解决**：

| 原因 | 解决方案 |
|------|----------|
| Agent 未安装 | 安装 SSM Agent |
| Agent 未运行 | 重启 Agent |
| IAM Role 缺失 | 附加 `AmazonSSMManagedInstanceCore` |
| 无法访问 SSM 端点 | 配置 VPC Endpoint 或 NAT |

**重启 SSM Agent**：
```bash
# Amazon Linux 2/2023
sudo systemctl restart amazon-ssm-agent

# Ubuntu
sudo systemctl restart snap.amazon-ssm-agent.amazon-ssm-agent
```

### 问题：VPC Endpoint 配置

私有子网需要 VPC Endpoint 才能访问 SSM：

```
需要的 Endpoints:
- com.amazonaws.{region}.ssm
- com.amazonaws.{region}.ssmmessages
- com.amazonaws.{region}.ec2messages
```

**验证 Endpoint**：
```bash
aws ec2 describe-vpc-endpoints \
    --filters "Name=service-name,Values=com.amazonaws.ap-northeast-1.ssm"
```

### 问题：Session 文档权限

**症状**：
```
User is not authorized to access document AWS-StartSSHSession
```

**解决方案**：

确保 IAM Policy 包含：
```json
{
  "Effect": "Allow",
  "Action": "ssm:StartSession",
  "Resource": "arn:aws:ssm:*:*:document/AWS-StartSSHSession"
}
```

---

## 平台特定问题

### macOS：Keychain 密码提示

**症状**：每次连接都要输入 Keychain 密码

**解决方案**：

```bash
# 添加密钥到 SSH Agent
ssh-add --apple-use-keychain ~/.ssh/id_ed25519

# SSH Config 配置
Host *
    AddKeysToAgent yes
    UseKeychain yes
```

### Linux：Agent 未运行

**症状**：
```
Could not open a connection to your authentication agent
```

**解决方案**：

```bash
# 启动 SSH Agent
eval $(ssh-agent -s)
ssh-add ~/.ssh/your-key
```

### WSL：路径转换问题

**症状**：Windows 和 WSL 路径混淆

**解决方案**：

```ssh-config
# WSL 内的 SSH Config 使用 Linux 路径
Host my-server
    IdentityFile /home/username/.ssh/id_ed25519

# 不要用 /mnt/c/Users/... 除非密钥真的在那里
```

---

## 诊断工具

### SSH 详细日志

```bash
# 最详细的日志（三个 v）
ssh -vvv i-xxx

# 输出重定向到文件
ssh -vvv i-xxx 2>&1 | tee ssh-debug.log
```

### AWS CLI Debug

```bash
# 启用 AWS CLI 调试
aws ssm start-session --target i-xxx --debug 2>&1 | tee ssm-debug.log
```

### VS Code 日志

1. `Ctrl+Shift+P` → `Remote-SSH: Show Log`
2. 查看 Output 面板 → 选择 `Remote - SSH`

### 网络诊断

```bash
# 测试 AWS API 可达性
curl -I https://ssm.ap-northeast-1.amazonaws.com

# 测试 VPC Endpoint（如果使用）
nslookup ssm.ap-northeast-1.amazonaws.com
```

---

## 快速参考卡

### Windows SSH Config 模板

```ssh-config
# Windows 专用 - 不使用引号！
Host terraform-lab
    HostName i-0123456789abcdef0
    User ec2-user
    IdentityFile C:/Users/YourName/.ssh/terraform-lab.pem
    ProxyCommand aws ssm start-session --target %h --document-name AWS-StartSSHSession --parameters portNumber=%p --region ap-northeast-1
```

### macOS/Linux SSH Config 模板

```ssh-config
# macOS/Linux - 使用引号
Host terraform-lab
    HostName i-0123456789abcdef0
    User ec2-user
    IdentityFile ~/.ssh/terraform-lab.pem
    ProxyCommand aws ssm start-session --target %h --document-name AWS-StartSSHSession --parameters "portNumber=%p" --region ap-northeast-1
```

### 常用命令速查

| 操作 | 命令 |
|------|------|
| 测试 SSM 连接 | `aws ssm start-session --target i-xxx` |
| 检查实例状态 | `aws ec2 describe-instance-status --instance-ids i-xxx` |
| 检查 SSM Agent | `aws ssm describe-instance-information` |
| 检查身份 | `aws sts get-caller-identity` |
| SSH 详细日志 | `ssh -vvv hostname` |

---

> 返回主文档：[README.md](./README.md)
