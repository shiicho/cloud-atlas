# 07 - 金色镜像策略（Golden Image Strategy）

> **目标**：理解 Bake vs Bootstrap 决策框架，掌握 Packer 基础和镜像清理规范  
> **前置**：[06 - IAM 与实例配置文件](../06-iam-instance-profiles/)、[02 - cloud-init 启动流程](../02-cloud-init/)  
> **时间**：2.5 小时  
> **实战场景**：Ghost Identity 身份冲突、Configuration Audit 配置审计  

---

## 将学到的内容

1. 理解 Bake vs Bootstrap 决策框架（何时预装，何时动态配置）
2. 掌握 Packer 基础构建金色镜像
3. 正确清理镜像前的状态（machine-id、SSH keys 等）
4. 建立镜像生命周期管理（版本、测试、发布、弃用）
5. 了解 2025 年镜像构建趋势（EC2 Image Builder、ARM64/Graviton）

---

## 先跑起来！（10 分钟）

> 在学习金色镜像理论之前，先检查你当前实例的"镜像准备度"。  

在任意 EC2 实例上运行：

### 检查实例的唯一标识符

```bash
# machine-id：系统唯一标识符
cat /etc/machine-id

# 这个 ID 对你的实例唯一吗？
# 如果从这个实例创建 AMI，所有新实例都会继承这个 ID！
```

```
a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6
```

### 检查 SSH Host Keys

```bash
# SSH 服务器的"指纹"
ls -la /etc/ssh/ssh_host_*

# 这些密钥用于验证服务器身份
# 如果多个实例有相同的密钥 = 安全风险！
```

```
-rw-r----- 1 root ssh_keys  480 Jan  1 12:00 /etc/ssh/ssh_host_ecdsa_key
-rw-r--r-- 1 root root      162 Jan  1 12:00 /etc/ssh/ssh_host_ecdsa_key.pub
-rw-r----- 1 root ssh_keys  387 Jan  1 12:00 /etc/ssh/ssh_host_ed25519_key
-rw-r--r-- 1 root root       82 Jan  1 12:00 /etc/ssh/ssh_host_ed25519_key.pub
-rw-r----- 1 root ssh_keys 2590 Jan  1 12:00 /etc/ssh/ssh_host_rsa_key
-rw-r--r-- 1 root root      554 Jan  1 12:00 /etc/ssh/ssh_host_rsa_key.pub
```

### 检查命令历史

```bash
# 你的操作记录
wc -l ~/.bash_history 2>/dev/null || echo "No history file"

# 历史记录可能包含敏感信息（密码、token 等）
# 镜像前必须清除！
```

### 快速镜像准备度检查

```bash
# 一键检查镜像准备状态
echo "=== 镜像准备度检查 ==="

echo -n "machine-id: "
if [ -s /etc/machine-id ]; then
    echo "警告 - 需要清除 ($(cat /etc/machine-id | head -c 8)...)"
else
    echo "OK - 已清除或为空"
fi

echo -n "SSH host keys: "
if ls /etc/ssh/ssh_host_* 2>/dev/null | head -1 > /dev/null; then
    echo "警告 - $(ls /etc/ssh/ssh_host_* 2>/dev/null | wc -l) 个密钥文件存在"
else
    echo "OK - 已清除"
fi

echo -n "bash_history: "
if [ -s ~/.bash_history ]; then
    echo "警告 - $(wc -l < ~/.bash_history) 行历史记录"
else
    echo "OK - 无历史记录"
fi

echo -n "cloud-init: "
if [ -f /var/lib/cloud/instance/boot-finished ]; then
    echo "警告 - cloud-init 状态存在，新实例可能跳过初始化"
else
    echo "OK - 无 cloud-init 状态"
fi
```

---

**你刚刚看到了创建金色镜像前需要注意的关键状态。** 如果不清理这些状态，从这个实例创建的所有新实例都会有相同的 machine-id、相同的 SSH 密钥、相同的历史记录。这就是"Ghost Identity"问题的根源。

---

## Step 1 - Bake vs Bootstrap 决策框架（25 分钟）

### 1.1 两种极端模式

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    Bake vs Bootstrap 对比                                    │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│   ┌─────────────────────────────────────────────────────────────────────┐  │
│   │                    Pure Bake（纯预装模式）                            │  │
│   │                                                                     │  │
│   │   AMI 包含一切：OS + 软件 + 配置 + 应用代码                          │  │
│   │                                                                     │  │
│   │   启动时间：秒级 ─────────────────────────────────────────►         │  │
│   │   灵活性：  低 ───────────────────────────────────────────►         │  │
│   │   镜像大小：大（包含所有依赖）                                       │  │
│   │   更新频率：高（每次代码变更都要重建镜像）                            │  │
│   │                                                                     │  │
│   │   适用场景：                                                        │  │
│   │   ● 启动速度关键（ASG 快速扩容）                                     │  │
│   │   ● 环境一致性要求高                                                │  │
│   │   ● 应用更新频率低                                                  │  │
│   └─────────────────────────────────────────────────────────────────────┘  │
│                                                                             │
│   ┌─────────────────────────────────────────────────────────────────────┐  │
│   │                    Pure Bootstrap（纯动态模式）                       │  │
│   │                                                                     │  │
│   │   AMI 只有基础 OS，启动时通过 user-data 安装一切                     │  │
│   │                                                                     │  │
│   │   启动时间：分钟级 ──────────────────────────────────────►          │  │
│   │   灵活性：  高 ──────────────────────────────────────────►          │  │
│   │   镜像大小：小（只有 OS）                                            │  │
│   │   更新频率：低（修改 user-data 即可）                                │  │
│   │                                                                     │  │
│   │   适用场景：                                                        │  │
│   │   ● 开发/测试环境                                                   │  │
│   │   ● 快速迭代阶段                                                    │  │
│   │   ● 启动时间不敏感                                                  │  │
│   └─────────────────────────────────────────────────────────────────────┘  │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 1.2 推荐：混合模式（Hybrid）

实践中，最佳方案是 **Bake 基础 + Bootstrap 配置**：

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    混合模式：Bake 基础 + Bootstrap 配置                       │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│   AMI（Bake 部分）                                                          │
│   ┌─────────────────────────────────────────────────────────────────────┐  │
│   │  操作系统                                                            │  │
│   │  安全补丁                                                            │  │
│   │  基础软件包（nginx, java, python...）                                │  │
│   │  监控 Agent（CloudWatch Agent）                                      │  │
│   │  安全加固（CIS Baseline）                                            │  │
│   │  日志配置                                                            │  │
│   └─────────────────────────────────────────────────────────────────────┘  │
│                           │                                                │
│                           │ 启动（秒级）                                   │
│                           ▼                                                │
│   cloud-init / user-data（Bootstrap 部分）                                 │
│   ┌─────────────────────────────────────────────────────────────────────┐  │
│   │  环境变量配置                                                        │  │
│   │  从 Secrets Manager 获取密钥                                         │  │
│   │  从 S3 下载配置文件                                                  │  │
│   │  注册到服务发现                                                      │  │
│   │  启动应用服务                                                        │  │
│   └─────────────────────────────────────────────────────────────────────┘  │
│                                                                             │
│   优势：                                                                    │
│   ✓ 启动速度快（大部分已预装）                                             │
│   ✓ 配置灵活（环境变量/密钥动态获取）                                      │
│   ✓ 镜像更新频率可控（基础软件更新才重建）                                 │
│   ✓ 安全性好（密钥不在镜像中）                                             │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 1.3 决策流程图

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    Bake vs Bootstrap 决策流程                                │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│                          需要在镜像中包含吗？                                 │
│                                 │                                           │
│                                 ▼                                           │
│                    ┌─────────────────────────┐                             │
│                    │  启动后需要更新吗？        │                             │
│                    │  （配置、密钥、代码）      │                             │
│                    └─────────────────────────┘                             │
│                         │              │                                   │
│                        YES            NO                                   │
│                         │              │                                   │
│                         ▼              ▼                                   │
│               ┌──────────────┐  ┌──────────────┐                          │
│               │  Bootstrap   │  │    Bake      │                          │
│               │  (user-data) │  │   (AMI)      │                          │
│               └──────────────┘  └──────────────┘                          │
│                                                                             │
│   Bake（预装到 AMI）:                Bootstrap（启动时配置）:               │
│   ─────────────────                   ──────────────────                   │
│   ● 操作系统                          ● 环境变量                            │
│   ● 安全补丁                          ● 密钥/凭证                           │
│   ● 运行时（Java, Python...）         ● 配置文件                            │
│   ● 基础软件包                        ● 应用代码（频繁更新时）              │
│   ● 监控 Agent                        ● 服务发现注册                        │
│   ● 安全加固配置                      ● 动态主机名                          │
│   ● 日志轮转配置                                                           │
│                                                                             │
│   经验法则：                                                                │
│   "如果更新频率 < 镜像构建频率，就 Bake；否则 Bootstrap"                   │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 1.4 实际例子

**场景：Web 服务器**

| 组件 | 更新频率 | 决策 | 原因 |
|------|----------|------|------|
| Nginx | 月级 | Bake | 安全补丁随镜像更新 |
| SSL 证书 | 90 天 | Bootstrap | 证书轮换不需要重建镜像 |
| 应用配置 | 周级 | Bootstrap | 配置从 S3/SSM 动态获取 |
| 应用代码 | 日级 | Bootstrap* | 从 S3/CodeDeploy 部署 |
| CloudWatch Agent | 月级 | Bake | 监控基础设施 |
| 数据库密码 | 动态 | Bootstrap | 从 Secrets Manager 获取 |

*注：如果应用代码更新频率降低（月级），可以考虑 Bake。

---

## Step 2 - Packer 基础（30 分钟）

### 2.1 什么是 Packer？

**Packer** 是 HashiCorp 的开源镜像构建工具，支持多云平台：

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    Packer 工作流程                                           │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│   ┌───────────────┐                                                         │
│   │  Packer 模板  │  定义构建配置（HCL2 格式）                              │
│   │  (.pkr.hcl)   │                                                         │
│   └───────┬───────┘                                                         │
│           │                                                                 │
│           ▼                                                                 │
│   ┌───────────────┐                                                         │
│   │    Source     │  选择基础 AMI（Amazon Linux, Ubuntu...）                │
│   │   (基础镜像)  │                                                         │
│   └───────┬───────┘                                                         │
│           │                                                                 │
│           ▼                                                                 │
│   ┌───────────────┐     ┌───────────────┐     ┌───────────────┐            │
│   │ Provisioner 1 │────▶│ Provisioner 2 │────▶│ Provisioner N │            │
│   │ (系统更新)    │     │ (安装软件)    │     │ (清理状态)    │            │
│   └───────────────┘     └───────────────┘     └───────────────┘            │
│           │                                                                 │
│           ▼                                                                 │
│   ┌───────────────┐                                                         │
│   │Post-Processor │  生成 manifest、打标签、复制到其他区域                  │
│   └───────┬───────┘                                                         │
│           │                                                                 │
│           ▼                                                                 │
│   ┌───────────────┐                                                         │
│   │   输出 AMI    │  ami-0abc123def456789                                   │
│   │               │  web-server-2025-01-10-1234                              │
│   └───────────────┘                                                         │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 2.2 Packer 模板结构（HCL2）

```hcl
# web-server.pkr.hcl

# ===== Packer 设置 =====
packer {
  required_plugins {
    amazon = {
      version = ">= 1.2.0"
      source  = "github.com/hashicorp/amazon"
    }
  }
}

# ===== 变量定义 =====
variable "aws_region" {
  type    = string
  default = "ap-northeast-1"
}

variable "instance_type" {
  type    = string
  default = "t3.micro"
}

variable "ami_name_prefix" {
  type    = string
  default = "web-server"
}

# ===== 数据源：查找最新的基础 AMI =====
data "amazon-ami" "amazon-linux-2023" {
  filters = {
    name                = "al2023-ami-*-x86_64"
    root-device-type    = "ebs"
    virtualization-type = "hvm"
  }
  most_recent = true
  owners      = ["amazon"]
  region      = var.aws_region
}

# ===== Source：定义构建源 =====
source "amazon-ebs" "web" {
  ami_name        = "${var.ami_name_prefix}-{{timestamp}}"
  ami_description = "Web server golden image"
  instance_type   = var.instance_type
  region          = var.aws_region
  source_ami      = data.amazon-ami.amazon-linux-2023.id
  ssh_username    = "ec2-user"

  # 标签
  tags = {
    Name        = "${var.ami_name_prefix}-{{timestamp}}"
    Environment = "production"
    Builder     = "packer"
    BuildTime   = "{{timestamp}}"
  }

  # 快照标签
  snapshot_tags = {
    Name = "${var.ami_name_prefix}-{{timestamp}}-snapshot"
  }
}

# ===== Build：构建步骤 =====
build {
  sources = ["source.amazon-ebs.web"]

  # Step 1: 系统更新
  provisioner "shell" {
    inline = [
      "sudo dnf update -y",
      "sudo dnf install -y nginx"
    ]
  }

  # Step 2: 安装 CloudWatch Agent
  provisioner "shell" {
    script = "scripts/install-cloudwatch-agent.sh"
  }

  # Step 3: 上传配置文件
  provisioner "file" {
    source      = "configs/nginx.conf"
    destination = "/tmp/nginx.conf"
  }

  provisioner "shell" {
    inline = [
      "sudo mv /tmp/nginx.conf /etc/nginx/nginx.conf",
      "sudo systemctl enable nginx"
    ]
  }

  # Step 4: 清理（Seal）- 关键！
  provisioner "shell" {
    script = "scripts/seal.sh"
  }

  # Post-processor: 生成 manifest
  post-processor "manifest" {
    output     = "manifest.json"
    strip_path = true
  }
}
```

### 2.3 Provisioner 类型

| Provisioner | 用途 | 示例 |
|-------------|------|------|
| `shell` | 执行 shell 命令/脚本 | 安装软件、配置系统 |
| `file` | 上传文件 | 配置文件、脚本 |
| `ansible` | 运行 Ansible playbook | 复杂配置管理 |
| `powershell` | Windows PowerShell | Windows 镜像 |

### 2.4 基本 Packer 命令

```bash
# 初始化（下载插件）
packer init web-server.pkr.hcl

# 验证模板
packer validate web-server.pkr.hcl

# 格式化模板
packer fmt web-server.pkr.hcl

# 构建镜像
packer build web-server.pkr.hcl

# 构建并指定变量
packer build -var "aws_region=us-east-1" web-server.pkr.hcl

# 调试模式（暂停在每一步）
packer build -debug web-server.pkr.hcl
```

---

## Step 3 - 镜像清理（Seal）（25 分钟）

### 3.1 为什么需要清理？

从运行中的实例创建 AMI 时，实例的**唯一状态**会被"烘烤"进镜像。如果不清理，所有新实例都会继承这些状态：

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    镜像状态污染问题                                           │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│   原始实例                                                                   │
│   ┌─────────────────────────────────────────────────────────────────────┐  │
│   │  machine-id: a1b2c3d4...                                            │  │
│   │  SSH keys: /etc/ssh/ssh_host_*                                      │  │
│   │  history: 500 行命令历史                                             │  │
│   │  logs: /var/log/* 充满日志                                          │  │
│   │  cloud-init: 已完成首次启动                                          │  │
│   └─────────────────────────────────────────────────────────────────────┘  │
│                           │                                                │
│                           │ 直接创建 AMI（不清理）                          │
│                           ▼                                                │
│   ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐           │
│   │   实例 A        │  │   实例 B        │  │   实例 C        │           │
│   │ machine-id:     │  │ machine-id:     │  │ machine-id:     │           │
│   │ a1b2c3d4...     │  │ a1b2c3d4...     │  │ a1b2c3d4...     │           │
│   │ (相同!)         │  │ (相同!)         │  │ (相同!)         │           │
│   └─────────────────┘  └─────────────────┘  └─────────────────┘           │
│                                                                             │
│   问题：                                                                    │
│   ● DHCP 客户端 ID 冲突                                                    │
│   ● 监控工具无法区分实例                                                   │
│   ● 日志聚合混乱                                                           │
│   ● SSH 主机密钥相同 = 安全风险                                            │
│   ● cloud-init 可能跳过初始化                                              │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 3.2 必须清理的项目

| 项目 | 位置 | 原因 | 清理命令 |
|------|------|------|----------|
| **machine-id** | `/etc/machine-id` | 系统唯一标识符，用于 DHCP、journald | `truncate -s 0 /etc/machine-id` |
| **SSH host keys** | `/etc/ssh/ssh_host_*` | 服务器身份验证，应每实例唯一 | `rm /etc/ssh/ssh_host_*` |
| **cloud-init 状态** | `/var/lib/cloud/` | 防止 cloud-init 跳过首次启动 | `cloud-init clean` |
| **命令历史** | `~/.bash_history` | 可能包含敏感信息 | `rm ~/.bash_history` |
| **日志文件** | `/var/log/*` | 减小镜像体积，避免旧日志混淆 | `find /var/log -type f -delete` |
| **临时文件** | `/tmp/*`, `/var/tmp/*` | 清除构建残留 | `rm -rf /tmp/* /var/tmp/*` |
| **DNF/APT 缓存** | `/var/cache/dnf/` | 减小镜像体积 | `dnf clean all` |

### 3.3 标准 Seal 脚本

```bash
#!/bin/bash
# seal.sh - 镜像捕获前的清理脚本
# 用法: 在 Packer provisioner 最后阶段执行

set -e

echo "=== 开始镜像清理 (Seal) ==="

# 1. 清除 machine-id（关键！）
echo "清除 machine-id..."
sudo truncate -s 0 /etc/machine-id
# 某些发行版还有 /var/lib/dbus/machine-id
if [ -f /var/lib/dbus/machine-id ]; then
    sudo rm /var/lib/dbus/machine-id
    sudo ln -s /etc/machine-id /var/lib/dbus/machine-id
fi

# 2. 清除 SSH host keys（启动时会自动重新生成）
echo "清除 SSH host keys..."
sudo rm -f /etc/ssh/ssh_host_*

# 3. 清除 cloud-init 状态
echo "清除 cloud-init 状态..."
if command -v cloud-init &> /dev/null; then
    sudo cloud-init clean --logs
fi

# 4. 清除命令历史
echo "清除命令历史..."
cat /dev/null > ~/.bash_history
history -c

# 5. 清除日志文件
echo "清除日志文件..."
sudo find /var/log -type f -name "*.log" -delete
sudo find /var/log -type f -name "*.gz" -delete
sudo find /var/log -type f -name "*.[0-9]" -delete
# 清除 journal 日志
sudo journalctl --vacuum-time=1s 2>/dev/null || true

# 6. 清除临时文件
echo "清除临时文件..."
sudo rm -rf /tmp/*
sudo rm -rf /var/tmp/*

# 7. 清除包管理缓存
echo "清除包管理缓存..."
if command -v dnf &> /dev/null; then
    sudo dnf clean all
elif command -v apt-get &> /dev/null; then
    sudo apt-get clean
    sudo rm -rf /var/lib/apt/lists/*
fi

# 8. 清除 root 用户历史
echo "清除 root 用户历史..."
sudo cat /dev/null > /root/.bash_history

# 9. 确保 SSH 目录权限正确
echo "验证 SSH 配置..."
sudo chmod 700 /root/.ssh 2>/dev/null || true
sudo chmod 600 /root/.ssh/authorized_keys 2>/dev/null || true

echo "=== 镜像清理完成 ==="
echo "machine-id: $(cat /etc/machine-id || echo '(已清除)')"
echo "SSH keys: $(ls /etc/ssh/ssh_host_* 2>/dev/null | wc -l) 个文件"
```

### 3.4 清理验证脚本

```bash
#!/bin/bash
# verify-seal.sh - 验证镜像清理是否完成

echo "=== 镜像清理验证 ==="

ISSUES=0

# 检查 machine-id
if [ -s /etc/machine-id ]; then
    echo "[FAIL] machine-id 不为空: $(cat /etc/machine-id)"
    ISSUES=$((ISSUES + 1))
else
    echo "[PASS] machine-id 已清除"
fi

# 检查 SSH host keys
SSH_KEYS=$(ls /etc/ssh/ssh_host_* 2>/dev/null | wc -l)
if [ "$SSH_KEYS" -gt 0 ]; then
    echo "[FAIL] SSH host keys 存在: $SSH_KEYS 个文件"
    ISSUES=$((ISSUES + 1))
else
    echo "[PASS] SSH host keys 已清除"
fi

# 检查 cloud-init 状态
if [ -f /var/lib/cloud/instance/boot-finished ]; then
    echo "[FAIL] cloud-init 状态存在"
    ISSUES=$((ISSUES + 1))
else
    echo "[PASS] cloud-init 状态已清除"
fi

# 检查命令历史
if [ -s ~/.bash_history ]; then
    echo "[WARN] bash_history 存在: $(wc -l < ~/.bash_history) 行"
else
    echo "[PASS] bash_history 已清除"
fi

# 总结
echo ""
if [ "$ISSUES" -eq 0 ]; then
    echo "=== 验证通过：镜像可以安全捕获 ==="
else
    echo "=== 验证失败：发现 $ISSUES 个问题 ==="
    exit 1
fi
```

### 3.5 virt-sysprep 工具（可选）

对于 Linux 镜像，`virt-sysprep` 是一个自动化清理工具：

```bash
# 安装（在构建机器上）
sudo dnf install -y libguestfs-tools

# 使用 virt-sysprep 清理镜像（离线模式）
# 注意：这需要镜像文件，不是运行中的实例
sudo virt-sysprep -a disk-image.raw \
    --operations defaults,-lvm-uuids \
    --hostname '' \
    --root-password disabled

# 查看会执行的操作
virt-sysprep --list-operations
```

**virt-sysprep 常用操作**：

| 操作 | 说明 |
|------|------|
| `machine-id` | 清除 /etc/machine-id |
| `ssh-hostkeys` | 删除 SSH host keys |
| `logfiles` | 清除日志文件 |
| `bash-history` | 清除 bash 历史 |
| `tmp-files` | 清除临时文件 |

---

## Step 4 - 镜像生命周期管理（20 分钟）

### 4.1 镜像生命周期

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    镜像生命周期管理                                           │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│   构建 (Build)                                                              │
│   ┌─────────────────────────────────────────────────────────────────────┐  │
│   │  ● Packer/Image Builder 构建                                        │  │
│   │  ● 自动命名：web-server-2025-01-10-143022                           │  │
│   │  ● 打标签：Environment=dev, Version=1.0.0                           │  │
│   └─────────────────────────────────────────────────────────────────────┘  │
│                           │                                                │
│                           ▼                                                │
│   测试 (Test)                                                               │
│   ┌─────────────────────────────────────────────────────────────────────┐  │
│   │  ● 从镜像启动测试实例                                                │  │
│   │  ● 运行验证脚本（服务启动、端口监听、健康检查）                       │  │
│   │  ● 安全扫描（Inspector, Trivy）                                      │  │
│   │  ● CIS 合规检查                                                      │  │
│   └─────────────────────────────────────────────────────────────────────┘  │
│                           │                                                │
│                           ▼                                                │
│   发布 (Release)                                                            │
│   ┌─────────────────────────────────────────────────────────────────────┐  │
│   │  ● 更新标签：Status=approved                                        │  │
│   │  ● 复制到生产账户/区域                                               │  │
│   │  ● 更新 Launch Template                                              │  │
│   │  ● 通知相关团队                                                      │  │
│   └─────────────────────────────────────────────────────────────────────┘  │
│                           │                                                │
│                           ▼                                                │
│   运行 (Active)                                                             │
│   ┌─────────────────────────────────────────────────────────────────────┐  │
│   │  ● 生产环境使用中                                                    │  │
│   │  ● 监控镜像使用量                                                    │  │
│   │  ● 定期检查是否有新版本                                              │  │
│   └─────────────────────────────────────────────────────────────────────┘  │
│                           │                                                │
│                           ▼                                                │
│   弃用 (Deprecate)                                                          │
│   ┌─────────────────────────────────────────────────────────────────────┐  │
│   │  ● 更新标签：Status=deprecated                                      │  │
│   │  ● 通知用户迁移到新版本                                              │  │
│   │  ● 设置弃用时间                                                      │  │
│   │  ● 保留一定时间（回滚需要）                                          │  │
│   └─────────────────────────────────────────────────────────────────────┘  │
│                           │                                                │
│                           ▼                                                │
│   删除 (Delete)                                                             │
│   ┌─────────────────────────────────────────────────────────────────────┐  │
│   │  ● 确认无活跃使用                                                    │  │
│   │  ● 删除 AMI 和关联快照                                               │  │
│   │  ● 保留审计记录                                                      │  │
│   └─────────────────────────────────────────────────────────────────────┘  │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 4.2 版本命名约定

推荐的镜像命名格式：

```
{app}-{version}-{date}-{build-number}

示例：
web-server-1.0.0-20250110-001
nginx-2.3.1-20250110-002
base-cis-al2023-20250110-001
```

**标签规范**：

| 标签 | 值 | 用途 |
|------|-----|------|
| `Name` | `web-server-1.0.0-20250110-001` | AMI 显示名称 |
| `Application` | `web-server` | 应用标识 |
| `Version` | `1.0.0` | 应用版本 |
| `BaseAMI` | `ami-0abc123...` | 基础镜像 ID |
| `BuildDate` | `2025-01-10` | 构建日期 |
| `BuildNumber` | `001` | 构建序号 |
| `Builder` | `packer` | 构建工具 |
| `Status` | `testing/approved/deprecated` | 生命周期状态 |
| `Environment` | `dev/staging/prod` | 目标环境 |

### 4.3 镜像管理脚本

```bash
#!/bin/bash
# manage-ami.sh - AMI 生命周期管理

# 列出所有自建镜像
list_amis() {
    aws ec2 describe-images \
        --owners self \
        --query 'Images[*].[ImageId,Name,CreationDate,Tags[?Key==`Status`].Value|[0]]' \
        --output table
}

# 标记镜像为 approved
approve_ami() {
    local ami_id=$1
    aws ec2 create-tags \
        --resources "$ami_id" \
        --tags Key=Status,Value=approved
    echo "AMI $ami_id 已标记为 approved"
}

# 标记镜像为 deprecated
deprecate_ami() {
    local ami_id=$1
    aws ec2 create-tags \
        --resources "$ami_id" \
        --tags Key=Status,Value=deprecated Key=DeprecationDate,Value="$(date +%Y-%m-%d)"
    echo "AMI $ami_id 已标记为 deprecated"
}

# 查找使用特定 AMI 的实例
find_instances_using_ami() {
    local ami_id=$1
    aws ec2 describe-instances \
        --filters "Name=image-id,Values=$ami_id" \
        --query 'Reservations[*].Instances[*].[InstanceId,State.Name]' \
        --output table
}

# 删除旧的 deprecated AMI（保留最近 N 个）
cleanup_old_amis() {
    local keep_count=${1:-3}
    local app_name=${2:-"web-server"}

    # 获取 deprecated 的 AMI，按日期排序
    aws ec2 describe-images \
        --owners self \
        --filters "Name=tag:Application,Values=$app_name" "Name=tag:Status,Values=deprecated" \
        --query 'sort_by(Images, &CreationDate)[*].[ImageId,Name,CreationDate]' \
        --output text | head -n -$keep_count | while read ami_id name date; do

        echo "准备删除: $ami_id ($name, $date)"
        # 实际删除需要取消注释
        # aws ec2 deregister-image --image-id "$ami_id"
    done
}

# 使用示例
case "$1" in
    list) list_amis ;;
    approve) approve_ami "$2" ;;
    deprecate) deprecate_ami "$2" ;;
    find-usage) find_instances_using_ami "$2" ;;
    cleanup) cleanup_old_amis "$2" "$3" ;;
    *) echo "Usage: $0 {list|approve|deprecate|find-usage|cleanup} [args]" ;;
esac
```

---

## Step 5 - 2025 更新（15 分钟）

### 5.1 EC2 Image Builder vs Packer

| 特性 | Packer | EC2 Image Builder |
|------|--------|-------------------|
| **学习曲线** | 中等 | 低（AWS Console） |
| **多云支持** | 是（AWS, GCP, Azure...） | 仅 AWS |
| **Pipeline 集成** | 需要额外配置 | 内置 Pipeline |
| **STIG 合规** | 手动配置 | 内置 STIG 组件 |
| **成本** | 只收实例费用 | 只收实例费用 |
| **灵活性** | 高 | 中 |
| **社区支持** | 广泛 | AWS 官方 |

**选择建议**：
- **纯 AWS 环境** + 合规要求高 → EC2 Image Builder
- **多云环境** + 需要最大灵活性 → Packer
- **团队熟悉 HashiCorp 工具** → Packer

### 5.2 ARM64 / Graviton 镜像

2025 年趋势：**Graviton 实例性价比显著**（比 x86 便宜约 20%，性能相当或更好）

```hcl
# Packer 构建 ARM64 镜像

data "amazon-ami" "amazon-linux-2023-arm" {
  filters = {
    name                = "al2023-ami-*-arm64"  # 注意：arm64
    root-device-type    = "ebs"
    virtualization-type = "hvm"
  }
  most_recent = true
  owners      = ["amazon"]
}

source "amazon-ebs" "web-arm64" {
  ami_name      = "web-server-arm64-{{timestamp}}"
  instance_type = "t4g.micro"  # Graviton 实例类型
  source_ami    = data.amazon-ami.amazon-linux-2023-arm.id
  ssh_username  = "ec2-user"
  # ...
}
```

**架构兼容性检查**：

```bash
# 检查当前实例架构
uname -m
# aarch64 = ARM64
# x86_64 = x86

# 检查软件包是否支持 ARM64
dnf repoquery --arch=aarch64 nginx
```

### 5.3 供应链安全趋势

| 趋势 | 说明 | 实践 |
|------|------|------|
| **SBOM** | Software Bill of Materials | 生成软件清单 |
| **镜像签名** | 验证镜像来源 | AWS Signer |
| **持续扫描** | Inspector v2 | 运行中实例也扫描 |
| **基础镜像信任** | 只使用官方镜像 | 验证 AMI owner |

```bash
# 生成 SBOM（软件物料清单）
# Amazon Linux 2023
sudo dnf repoquery --installed --qf '%{name}-%{version}-%{release}.%{arch}' > sbom.txt

# 使用 syft（开源 SBOM 工具）
syft dir:/ -o cyclonedx-json > sbom.json
```

---

## Lab 1 - Packer 金色镜像（40 分钟）

### 实验目标

使用 Packer 构建一个包含 Nginx 的金色镜像。

### Step 1 - 准备 Packer 环境

```bash
# 检查 Packer 是否安装
packer version

# 如果未安装（Amazon Linux 2023）
sudo dnf install -y dnf-plugins-core
sudo dnf config-manager --add-repo https://rpm.releases.hashicorp.com/AmazonLinux/hashicorp.repo
sudo dnf -y install packer

# 创建工作目录
mkdir -p ~/packer-lab && cd ~/packer-lab
```

### Step 2 - 创建 Packer 模板

```bash
# 创建主模板文件
cat > web-server.pkr.hcl << 'EOF'
packer {
  required_plugins {
    amazon = {
      version = ">= 1.2.0"
      source  = "github.com/hashicorp/amazon"
    }
  }
}

variable "aws_region" {
  type    = string
  default = "ap-northeast-1"
}

data "amazon-ami" "al2023" {
  filters = {
    name                = "al2023-ami-*-x86_64"
    root-device-type    = "ebs"
    virtualization-type = "hvm"
  }
  most_recent = true
  owners      = ["amazon"]
  region      = var.aws_region
}

source "amazon-ebs" "web" {
  ami_name        = "web-server-lab-{{timestamp}}"
  ami_description = "Packer Lab - Web server golden image"
  instance_type   = "t3.micro"
  region          = var.aws_region
  source_ami      = data.amazon-ami.al2023.id
  ssh_username    = "ec2-user"

  tags = {
    Name        = "web-server-lab-{{timestamp}}"
    Builder     = "packer"
    Environment = "lab"
  }
}

build {
  sources = ["source.amazon-ebs.web"]

  # 系统更新和软件安装
  provisioner "shell" {
    inline = [
      "sudo dnf update -y",
      "sudo dnf install -y nginx",
      "sudo systemctl enable nginx"
    ]
  }

  # 清理脚本
  provisioner "shell" {
    inline = [
      "# 清除 machine-id",
      "sudo truncate -s 0 /etc/machine-id",
      "",
      "# 清除 SSH host keys",
      "sudo rm -f /etc/ssh/ssh_host_*",
      "",
      "# 清除 cloud-init 状态",
      "sudo cloud-init clean --logs || true",
      "",
      "# 清除历史和缓存",
      "sudo dnf clean all",
      "cat /dev/null > ~/.bash_history",
      "history -c"
    ]
  }

  post-processor "manifest" {
    output     = "manifest.json"
    strip_path = true
  }
}
EOF
```

### Step 3 - 构建镜像

```bash
# 初始化 Packer
packer init web-server.pkr.hcl

# 验证模板
packer validate web-server.pkr.hcl

# 构建镜像（需要 AWS 凭证）
packer build web-server.pkr.hcl
```

构建过程会：
1. 启动一个临时 EC2 实例
2. SSH 连接并执行 provisioner
3. 停止实例并创建 AMI
4. 清理临时资源

### Step 4 - 验证镜像

```bash
# 查看 manifest
cat manifest.json | jq '.'

# 获取新建的 AMI ID
AMI_ID=$(cat manifest.json | jq -r '.builds[0].artifact_id' | cut -d: -f2)
echo "New AMI: $AMI_ID"

# 查看 AMI 详情
aws ec2 describe-images --image-ids $AMI_ID

# 从镜像启动测试实例（可选）
# aws ec2 run-instances \
#   --image-id $AMI_ID \
#   --instance-type t3.micro \
#   --key-name your-key \
#   --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=test-golden-image}]'
```

### Step 5 - 清理

```bash
# 如果是实验，清理创建的 AMI
# aws ec2 deregister-image --image-id $AMI_ID

# 找到关联的快照
# SNAPSHOT_ID=$(aws ec2 describe-images --image-ids $AMI_ID --query 'Images[0].BlockDeviceMappings[0].Ebs.SnapshotId' --output text)
# aws ec2 delete-snapshot --snapshot-id $SNAPSHOT_ID

# 清理本地文件
rm -rf ~/packer-lab
```

### 检查清单

- [ ] 成功安装和配置 Packer
- [ ] 理解 Packer 模板结构（source, build, provisioner）
- [ ] 能够构建基本的 AMI
- [ ] 理解 seal 脚本的作用

---

## Lab 2 - Ghost Identity 场景（30 分钟）

### 场景描述

> 你从运行中的服务器创建了金色镜像 (AMI)。从该镜像启动 3 个实例后，它们在监控工具中争用同一 IP，日志聚合混乱。  

**根因**：`/etc/machine-id` 在镜像捕获前未清除

### Step 1 - 模拟问题

```bash
# 查看当前实例的 machine-id
MACHINE_ID=$(cat /etc/machine-id)
echo "当前 machine-id: $MACHINE_ID"

# 模拟：如果从这个实例创建 AMI（不清理），所有新实例都会有这个 ID
echo "问题：所有新实例都会有相同的 machine-id: $MACHINE_ID"
```

### Step 2 - 理解 machine-id 的影响

```bash
# machine-id 用于什么？
echo "=== machine-id 的用途 ==="

# 1. systemd-journald 使用 machine-id 标识日志
echo "1. Journal 日志标识:"
journalctl --header 2>/dev/null | grep "Machine ID" || echo "   (需要查看 journal 头部)"

# 2. DHCP 客户端 ID
echo -e "\n2. DHCP 客户端标识:"
echo "   某些 DHCP 服务器使用 machine-id 分配租约"

# 3. D-Bus 系统标识
echo -e "\n3. D-Bus 系统标识:"
ls -la /var/lib/dbus/machine-id 2>/dev/null || echo "   /var/lib/dbus/machine-id"

# 4. 监控工具
echo -e "\n4. 监控工具标识:"
echo "   CloudWatch Agent、Datadog 等可能使用 machine-id 区分主机"
```

### Step 3 - 演示正确的清理流程

```bash
# 正确的清理方式（在创建 AMI 前执行）

echo "=== 正确的 machine-id 清理流程 ==="

# 方法 1：清空文件（systemd 会在下次启动时重新生成）
echo "方法 1: truncate -s 0 /etc/machine-id"

# 方法 2：删除文件（某些发行版）
echo "方法 2: rm /etc/machine-id"

# cloud-init 会在首次启动时生成新的 machine-id
echo -e "\ncloud-init 会在首次启动时生成新的唯一 machine-id"

# 验证命令
echo -e "\n=== 验证 machine-id 已清除 ==="
cat > /tmp/check-machine-id.sh << 'SCRIPT'
if [ -s /etc/machine-id ]; then
    echo "[FAIL] machine-id 不为空"
    cat /etc/machine-id
else
    echo "[PASS] machine-id 已清除或为空"
fi
SCRIPT

bash /tmp/check-machine-id.sh
```

### Step 4 - 完整的清理检查

```bash
# 创建完整的镜像准备检查脚本
cat > /tmp/ami-readiness-check.sh << 'EOF'
#!/bin/bash
echo "=========================================="
echo "AMI 准备度检查报告"
echo "=========================================="
echo ""

ISSUES=0

# 1. machine-id
echo "1. machine-id 检查"
if [ -s /etc/machine-id ]; then
    echo "   [FAIL] machine-id 存在: $(cat /etc/machine-id | head -c 16)..."
    ISSUES=$((ISSUES + 1))
else
    echo "   [PASS] machine-id 已清除"
fi

# 2. SSH host keys
echo -e "\n2. SSH Host Keys 检查"
SSH_KEYS=$(ls /etc/ssh/ssh_host_* 2>/dev/null | wc -l)
if [ "$SSH_KEYS" -gt 0 ]; then
    echo "   [FAIL] 存在 $SSH_KEYS 个 SSH host key 文件"
    ISSUES=$((ISSUES + 1))
else
    echo "   [PASS] SSH host keys 已清除"
fi

# 3. cloud-init 状态
echo -e "\n3. cloud-init 状态检查"
if [ -f /var/lib/cloud/instance/boot-finished ]; then
    echo "   [FAIL] cloud-init 已完成标记存在"
    ISSUES=$((ISSUES + 1))
else
    echo "   [PASS] cloud-init 状态已清除"
fi

# 4. 命令历史
echo -e "\n4. 命令历史检查"
HISTORY_LINES=$(wc -l < ~/.bash_history 2>/dev/null || echo "0")
if [ "$HISTORY_LINES" -gt 0 ]; then
    echo "   [WARN] bash_history 包含 $HISTORY_LINES 行"
else
    echo "   [PASS] bash_history 已清除"
fi

# 5. 临时文件
echo -e "\n5. 临时文件检查"
TMP_FILES=$(find /tmp -type f 2>/dev/null | wc -l)
if [ "$TMP_FILES" -gt 10 ]; then
    echo "   [WARN] /tmp 包含 $TMP_FILES 个文件"
else
    echo "   [PASS] 临时文件数量合理"
fi

# 总结
echo ""
echo "=========================================="
if [ "$ISSUES" -eq 0 ]; then
    echo "结果: 通过 - 镜像可以安全捕获"
else
    echo "结果: 失败 - 发现 $ISSUES 个必须修复的问题"
fi
echo "=========================================="
EOF

chmod +x /tmp/ami-readiness-check.sh
bash /tmp/ami-readiness-check.sh
```

### 检查清单

- [ ] 理解 machine-id 的作用和影响
- [ ] 理解未清理 machine-id 导致的问题
- [ ] 能够正确清除 machine-id
- [ ] 能够验证镜像清理状态

---

## Lab 3 - Configuration Audit 场景（25 分钟）

### 场景描述

> 将金色镜像交接给运维团队。需要证明镜像与设计文档（設計書）完全匹配。  

**目标**：生成可审计的配置报告

### Step 1 - 生成软件清单

```bash
# 生成已安装包清单
echo "=== 生成软件清单 ==="

# Amazon Linux / RHEL / CentOS
rpm -qa --qf '%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}\n' | sort > /tmp/installed-packages.txt

# 或者使用 dnf
# dnf list installed --quiet | tail -n +2 | awk '{print $1}' | sort > /tmp/installed-packages.txt

echo "已安装包数量: $(wc -l < /tmp/installed-packages.txt)"
echo "前 10 个包:"
head -10 /tmp/installed-packages.txt
```

### Step 2 - 创建批准列表并比较

```bash
# 创建一个模拟的"批准包列表"（实际场景从设计文档获取）
cat > /tmp/approved-packages.txt << 'EOF'
nginx-1.24.0-1.amzn2023.0.2.x86_64
amazon-cloudwatch-agent-1.300033.0-1.amzn2023.x86_64
amazon-ssm-agent-3.2.2222.0-1.amzn2023.x86_64
EOF

echo "=== 批准列表 ==="
cat /tmp/approved-packages.txt

echo -e "\n=== 差异分析 ==="

# 检查批准列表中的包是否都已安装
echo "检查必需包是否已安装:"
while read pkg; do
    if grep -q "^${pkg%%\-[0-9]*}" /tmp/installed-packages.txt; then
        echo "  [OK] $pkg"
    else
        echo "  [MISSING] $pkg"
    fi
done < /tmp/approved-packages.txt
```

### Step 3 - 生成配置审计报告

```bash
cat > /tmp/generate-audit-report.sh << 'EOF'
#!/bin/bash
# 生成配置审计报告

REPORT_FILE="/tmp/audit-report-$(date +%Y%m%d-%H%M%S).txt"

echo "=========================================="  > $REPORT_FILE
echo "      镜像配置审计报告"                     >> $REPORT_FILE
echo "      Image Configuration Audit Report"   >> $REPORT_FILE
echo "=========================================="  >> $REPORT_FILE
echo ""                                          >> $REPORT_FILE
echo "生成时间: $(date)"                         >> $REPORT_FILE
echo "主机名: $(hostname)"                       >> $REPORT_FILE
echo "AMI ID: $(curl -s http://169.254.169.254/latest/meta-data/ami-id 2>/dev/null || echo 'N/A')" >> $REPORT_FILE
echo ""                                          >> $REPORT_FILE

# 1. 系统信息
echo "=== 1. 系统信息 ===" >> $REPORT_FILE
echo "OS: $(cat /etc/os-release | grep PRETTY_NAME | cut -d= -f2 | tr -d '"')" >> $REPORT_FILE
echo "Kernel: $(uname -r)" >> $REPORT_FILE
echo "Architecture: $(uname -m)" >> $REPORT_FILE
echo "" >> $REPORT_FILE

# 2. 安装的包
echo "=== 2. 安装的包 (前50个) ===" >> $REPORT_FILE
rpm -qa --qf '%{NAME}-%{VERSION}\n' 2>/dev/null | sort | head -50 >> $REPORT_FILE
echo "... (共 $(rpm -qa | wc -l) 个包)" >> $REPORT_FILE
echo "" >> $REPORT_FILE

# 3. 启用的服务
echo "=== 3. 启用的服务 ===" >> $REPORT_FILE
systemctl list-unit-files --state=enabled --type=service --no-pager 2>/dev/null | head -20 >> $REPORT_FILE
echo "" >> $REPORT_FILE

# 4. 监听端口
echo "=== 4. 监听端口 ===" >> $REPORT_FILE
ss -tulpn 2>/dev/null | grep LISTEN >> $REPORT_FILE
echo "" >> $REPORT_FILE

# 5. 用户账户
echo "=== 5. 系统用户 (UID < 1000) ===" >> $REPORT_FILE
awk -F: '$3 < 1000 {print $1":"$3}' /etc/passwd | head -20 >> $REPORT_FILE
echo "" >> $REPORT_FILE

# 6. 镜像清理状态
echo "=== 6. 镜像清理状态 ===" >> $REPORT_FILE
if [ -s /etc/machine-id ]; then
    echo "machine-id: 存在 (警告)" >> $REPORT_FILE
else
    echo "machine-id: 已清除 (正常)" >> $REPORT_FILE
fi

SSH_KEYS=$(ls /etc/ssh/ssh_host_* 2>/dev/null | wc -l)
if [ "$SSH_KEYS" -gt 0 ]; then
    echo "SSH host keys: $SSH_KEYS 个文件存在 (警告)" >> $REPORT_FILE
else
    echo "SSH host keys: 已清除 (正常)" >> $REPORT_FILE
fi

# 7. 安全配置
echo "" >> $REPORT_FILE
echo "=== 7. 安全配置检查 ===" >> $REPORT_FILE
echo "SELinux: $(getenforce 2>/dev/null || echo 'Not installed')" >> $REPORT_FILE
echo "Firewalld: $(systemctl is-active firewalld 2>/dev/null || echo 'Not running')" >> $REPORT_FILE
echo "SSHd PermitRootLogin: $(grep -E '^PermitRootLogin' /etc/ssh/sshd_config 2>/dev/null || echo 'Not set')" >> $REPORT_FILE

echo "" >> $REPORT_FILE
echo "===========================================" >> $REPORT_FILE
echo "报告生成完成" >> $REPORT_FILE
echo "===========================================" >> $REPORT_FILE

echo "审计报告已生成: $REPORT_FILE"
cat $REPORT_FILE
EOF

chmod +x /tmp/generate-audit-report.sh
bash /tmp/generate-audit-report.sh
```

### Step 4 - 导出报告

```bash
# 查看生成的报告
ls -la /tmp/audit-report-*.txt

# 在实际场景中，可以上传到 S3
# REPORT_FILE=$(ls /tmp/audit-report-*.txt | tail -1)
# aws s3 cp $REPORT_FILE s3://your-audit-bucket/golden-images/
```

### 检查清单

- [ ] 能够生成软件包清单
- [ ] 能够与批准列表比较差异
- [ ] 能够生成综合审计报告
- [ ] 理解日本企业对配置审计的要求

---

## 不可变基础设施（Immutable Infrastructure Sidebar）

### 传统模式 vs 不可变模式

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    传统模式 vs 不可变基础设施                                 │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│   传统模式（Mutable）                                                        │
│   ─────────────────────                                                    │
│                                                                             │
│   服务器 ─► 补丁 ─► 配置更新 ─► 代码部署 ─► 更多补丁 ─► ...                │
│                                                                             │
│   问题：                                                                    │
│   ● 配置漂移（drift）：服务器之间不一致                                     │
│   ● "在我机器上能跑"：环境差异                                              │
│   ● 难以回滚：更新历史复杂                                                  │
│   ● 审计困难：谁改了什么？                                                  │
│                                                                             │
│   ─────────────────────────────────────────────────────────────────────    │
│                                                                             │
│   不可变模式（Immutable）                                                    │
│   ─────────────────────                                                    │
│                                                                             │
│   AMI v1 ─► 实例群 A                                                        │
│                     ↓ 更新 = 替换                                          │
│   AMI v2 ─► 实例群 B ─► 删除实例群 A                                        │
│                     ↓ 回滚 = 再次替换                                       │
│   AMI v1 ─► 实例群 C ─► 删除实例群 B                                        │
│                                                                             │
│   优势：                                                                    │
│   ✓ 一致性：所有实例来自同一镜像                                            │
│   ✓ 可预测：知道每个实例的确切状态                                          │
│   ✓ 快速回滚：切换到旧镜像即可                                              │
│   ✓ 易审计：镜像版本 = 配置版本                                             │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 实现不可变基础设施

```
更新流程：

1. 代码/配置变更
       │
       ▼
2. CI/CD Pipeline 触发 Packer 构建
       │
       ▼
3. 新 AMI 创建（ami-new-123）
       │
       ▼
4. 更新 Launch Template 版本
       │
       ▼
5. ASG Instance Refresh
       │
       ▼
6. 新实例启动，旧实例终止
       │
       ▼
7. 验证成功 → 标记旧 AMI 为 deprecated
   验证失败 → 回滚到旧 Launch Template 版本
```

### 与 cloud-init 的配合

```bash
# 不可变基础设施中 cloud-init 的角色

# AMI 包含：
# - 操作系统 + 所有软件
# - 所有配置（静态部分）
# - 监控 Agent

# cloud-init 只负责：
# - 设置主机名
# - 注册到服务发现
# - 从 Secrets Manager 获取密钥
# - 启动应用服务

# 示例 user-data（最小化）
cat << 'EOF'
#cloud-config
hostname: web-${INSTANCE_ID}

runcmd:
  # 从 Secrets Manager 获取配置
  - aws secretsmanager get-secret-value --secret-id app/config | jq -r '.SecretString' > /etc/app/config.json

  # 注册到服务发现
  - /opt/scripts/register-service.sh

  # 启动应用
  - systemctl start myapp
EOF
```

---

## 反模式演示（Anti-Patterns Demo）

### 反模式 1：不清理 machine-id

```bash
# 危险！创建 AMI 前不清理 machine-id
# 所有新实例都会有相同的 ID

# 后果：
# - DHCP 客户端 ID 冲突
# - 监控工具无法区分实例
# - 日志聚合混乱
# - systemd-journald 可能覆盖日志

# 修复：
sudo truncate -s 0 /etc/machine-id
```

### 反模式 2：配置漂移

```bash
# 危险！在运行中的实例上手动修改配置，然后创建 AMI

# 场景：
ssh ec2-user@instance
sudo vim /etc/nginx/nginx.conf  # 手动修改
sudo systemctl restart nginx
# ...几周后...
sudo create-ami  # 忘记了修改了什么

# 后果：
# - AMI 包含未记录的配置
# - 无法复现环境
# - 审计失败："这个配置是谁加的？"

# 修复：
# 所有配置变更都通过 Packer provisioner 或 Ansible
# 配置 = 代码，提交到 Git
```

### 反模式 3：未经测试的镜像

```bash
# 危险！构建完直接发布到生产环境

# 后果：
# - 服务启动失败
# - 依赖缺失
# - 配置错误
# - 生产事故

# 修复：
# 建立测试流程
packer build ...
# 自动测试：
# 1. 从新 AMI 启动测试实例
# 2. 运行健康检查
# 3. 运行集成测试
# 4. CIS 扫描
# 5. 通过后才标记为 approved
```

### 反模式 4：凭证烘烤进 AMI

```bash
# 危险！把凭证写入 AMI

# 错误示例（Packer provisioner）：
provisioner "shell" {
  inline = [
    "echo 'AWS_ACCESS_KEY_ID=AKIAXXXXXX' >> /etc/profile.d/aws.sh",
    "echo 'DB_PASSWORD=secret123' >> /etc/app/config"
  ]
}

# 后果：
# - 所有实例共享相同凭证
# - 凭证无法轮换
# - 安全审计失败
# - 泄露风险极高

# 修复：
# 凭证通过 Secrets Manager / Parameter Store 获取
# 在 cloud-init 中动态获取
runcmd:
  - aws secretsmanager get-secret-value --secret-id db/password | jq -r '.SecretString' > /etc/app/db-password
```

---

## 职场小贴士（Japan IT Context）

### ゴールデンイメージは変更管理の基本

在日本企业，**金色镜像（ゴールデンイメージ）** 是变更管理（変更管理）的核心：

| 日语术语 | 读音 | 含义 | 镜像实践 |
|----------|------|------|----------|
| ゴールデンイメージ | ゴールデンイメージ | Golden Image | 标准化基础镜像 |
| 変更管理 | へんこうかんり | Change Management | AMI 版本控制 |
| 設計書 | せっけいしょ | Design Document | 镜像规格文档 |
| 手順書 | てじゅんしょ | Procedure Document | 镜像构建步骤 |
| 構成管理 | こうせいかんり | Configuration Management | 镜像配置追踪 |

### 日本企业的镜像管理要求

```
┌─────────────────────────────────────────────────────────────────────────────┐
│            ゴールデンイメージ管理チェックリスト                               │
│            (Golden Image Management Checklist)                              │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  1. 構成管理 (Configuration Management)                                     │
│     □ 全てのソフトウェアが設計書と一致しているか                             │
│     □ バージョン番号が正しく付与されているか                                 │
│     □ 変更履歴が記録されているか                                            │
│                                                                             │
│  2. セキュリティ (Security)                                                 │
│     □ セキュリティパッチが適用されているか                                   │
│     □ CIS ベースラインに準拠しているか                                      │
│     □ 脆弱性スキャンをパスしているか                                        │
│                                                                             │
│  3. テスト (Testing)                                                        │
│     □ 機能テストをパスしているか                                            │
│     □ 性能テストをパスしているか                                            │
│     □ 本番環境との互換性が確認されているか                                   │
│                                                                             │
│  4. 承認 (Approval)                                                         │
│     □ 変更管理委員会の承認を得ているか                                      │
│     □ リリース責任者の承認を得ているか                                      │
│     □ 監査証跡が保存されているか                                            │
│                                                                             │
│  確認日: ____________  確認者: ____________                                  │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 設計書との一致を証明

日本企业通常要求"设计文档与实际配置的一致性证明"：

```bash
# 生成与设计文档比较的报告

# 1. 从设计文档获取期望的软件列表
# （实际中从内部系统或文档获取）
cat > /tmp/design-spec.txt << 'EOF'
# 設計書: SYS-2025-001
# 対象: Web Server Golden Image
# 必須ソフトウェア:
nginx >= 1.24.0
amazon-cloudwatch-agent >= 1.300000
amazon-ssm-agent >= 3.2.0
EOF

# 2. 生成实际安装清单
rpm -qa --qf '%{NAME} %{VERSION}\n' | sort > /tmp/actual-packages.txt

# 3. 生成比较报告
echo "=== 設計書との差分レポート ==="
echo "Date: $(date)"
echo ""
echo "期待: $(grep -c '>=' /tmp/design-spec.txt) 個のパッケージ"
echo "実際: $(wc -l < /tmp/actual-packages.txt) 個のパッケージがインストール済み"
echo ""
echo "必須パッケージの確認:"
grep '>=' /tmp/design-spec.txt | while read pkg ver; do
    if grep -q "^$pkg " /tmp/actual-packages.txt; then
        actual_ver=$(grep "^$pkg " /tmp/actual-packages.txt | awk '{print $2}')
        echo "  [OK] $pkg: $actual_ver"
    else
        echo "  [NG] $pkg: 未インストール"
    fi
done
```

---

## 检查清单

完成本课后，你应该能够：

- [ ] 解释 Bake vs Bootstrap 的决策框架
- [ ] 描述混合模式（Bake 基础 + Bootstrap 配置）的优势
- [ ] 使用 Packer 创建基本的金色镜像
- [ ] 编写镜像清理（seal）脚本
- [ ] 正确处理 machine-id、SSH keys、cloud-init 状态
- [ ] 理解镜像生命周期管理（构建、测试、发布、弃用）
- [ ] 生成配置审计报告
- [ ] 避免常见的镜像反模式（未清理、配置漂移、凭证烘烤）
- [ ] 理解日本企业对金色镜像的管理要求

---

## 本课小结

| 概念 | 要点 |
|------|------|
| Bake vs Bootstrap | 混合模式最佳：Bake 基础软件 + Bootstrap 动态配置 |
| Packer | HashiCorp 镜像构建工具，支持多云 |
| 镜像清理 | 必须清除 machine-id、SSH keys、cloud-init 状态 |
| 生命周期 | 构建 → 测试 → 发布 → 运行 → 弃用 → 删除 |
| 不可变基础设施 | 更新 = 替换，无配置漂移 |
| 反模式 | 不清理、配置漂移、未测试、凭证烘烤 |

---

## 延伸阅读

- [Packer Documentation](https://developer.hashicorp.com/packer/docs) - 官方文档
- [EC2 Image Builder](https://docs.aws.amazon.com/imagebuilder/) - AWS 原生镜像构建
- [AMI Lifecycle](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ami-lifecycle.html) - AMI 生命周期管理
- [Immutable Infrastructure](https://www.hashicorp.com/resources/what-is-mutable-vs-immutable-infrastructure) - 不可变基础设施概念
- 前一课：[06 - IAM 与实例配置文件](../06-iam-instance-profiles/) - IAM 凭证管理
- 下一课：[08 - 镜像加固与供应链安全](../08-image-hardening/) - CIS 基线与安全加固

---

## 清理资源

```bash
# 删除实验中创建的 AMI（如果有）
# aws ec2 deregister-image --image-id ami-xxxx
# aws ec2 delete-snapshot --snapshot-id snap-xxxx

# 清理本地临时文件
rm -f /tmp/installed-packages.txt
rm -f /tmp/approved-packages.txt
rm -f /tmp/audit-report-*.txt
rm -f /tmp/check-machine-id.sh
rm -f /tmp/ami-readiness-check.sh
rm -f /tmp/generate-audit-report.sh
rm -rf ~/packer-lab

echo "清理完成"
```

---

## 系列导航

[<- 06 - IAM 与实例配置文件](../06-iam-instance-profiles/) | [系列首页](../) | [08 - 镜像加固与供应链安全 ->](../08-image-hardening/)
