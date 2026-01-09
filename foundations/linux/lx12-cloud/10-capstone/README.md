# 10 - Capstone：不可变金色镜像管道（Immutable Golden Image Pipeline）

> **目标**：综合应用 LX12-CLOUD 全课程知识，构建生产级加固镜像管道  
> **前置**：本课程前 9 课全部完成  
> **时间**：3 小时  
> **成果**：可重复构建、CIS 加固、可审计的金色镜像  

---

## 将学到的内容

1. 综合应用所有课程知识构建完整的镜像管道
2. 实现生产级的镜像加固流程
3. 生成可审计的配置报告（manifest）
4. 验证镜像符合 CIS Level 1 安全基准
5. 理解日本企业的本番要件（本番環境要求）和監査対応（审计对应）

---

## Capstone 概述

### 项目背景

你是一家日本 IT 企业的基础设施工程师。团队需要为生产环境构建一个标准化的 Web 服务器金色镜像。这个镜像将成为所有 Web 服务器的基础，需要满足以下要求：

- **安全合规**：符合 CIS Level 1 基准
- **可观测**：集成 CloudWatch Agent 进行监控
- **可审计**：生成完整的配置清单（manifest）
- **可重复**：使用 Packer 或脚本实现自动化构建
- **零信任**：禁用 SSH，仅允许 SSM Session Manager 访问

### 交付物清单

完成本 Capstone 后，你将提交以下内容：

| 交付物 | 说明 | 必需 |
|--------|------|------|
| Packer 模板或构建脚本 | 自动化镜像构建配置 | Yes |
| 加固配置文件 | CIS 加固脚本或 Ansible playbook | Yes |
| Seal 脚本 | 清理 machine-id、SSH keys 等 | Yes |
| OpenSCAP 扫描报告 | CIS 合规性验证结果 | Yes |
| manifest.txt | 软件清单（已安装包列表） | Yes |
| README.md | 构建说明文档 | Yes |

---

## 项目需求

### 功能需求

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    金色镜像功能需求                                            │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│   1. 基础镜像                                                                │
│   ┌─────────────────────────────────────────────────────────────────────┐  │
│   │  从标准 OS 镜像开始：                                                │  │
│   │  ● Amazon Linux 2023 (推荐)                                         │  │
│   │  ● 或 Ubuntu 24.04 LTS                                              │  │
│   │  ● 使用官方 AMI，验证 owner ID                                       │  │
│   └─────────────────────────────────────────────────────────────────────┘  │
│                                                                             │
│   2. 应用安装                                                                │
│   ┌─────────────────────────────────────────────────────────────────────┐  │
│   │  安装并配置 Nginx Web 服务器：                                        │  │
│   │  ● 安装 Nginx 最新稳定版                                             │  │
│   │  ● 配置为开机自启动                                                  │  │
│   │  ● 配置默认欢迎页面                                                  │  │
│   │  ● 禁用版本显示（server_tokens off）                                 │  │
│   └─────────────────────────────────────────────────────────────────────┘  │
│                                                                             │
│   3. 安全加固                                                                │
│   ┌─────────────────────────────────────────────────────────────────────┐  │
│   │  应用 CIS Level 1 加固：                                             │  │
│   │  ● SSH 加固（禁用 root 登录、设置超时）                               │  │
│   │  ● 文件权限设置                                                      │  │
│   │  ● 禁用不必要的服务                                                  │  │
│   │  ● 配置 auditd 审计                                                  │  │
│   │  ● 内核参数加固                                                      │  │
│   └─────────────────────────────────────────────────────────────────────┘  │
│                                                                             │
│   4. 可观测性                                                                │
│   ┌─────────────────────────────────────────────────────────────────────┐  │
│   │  配置 CloudWatch Agent：                                             │  │
│   │  ● 安装 CloudWatch Agent                                             │  │
│   │  ● 配置内存和磁盘指标收集                                             │  │
│   │  ● 配置 /var/log/messages 日志收集                                   │  │
│   │  ● 配置 Nginx 访问日志收集                                            │  │
│   │  ● 设置为开机自启动                                                  │  │
│   └─────────────────────────────────────────────────────────────────────┘  │
│                                                                             │
│   5. 访问控制                                                                │
│   ┌─────────────────────────────────────────────────────────────────────┐  │
│   │  零信任访问配置：                                                     │  │
│   │  ● 禁用 SSH 端口（或配置为仅内网访问）                                │  │
│   │  ● 安装并配置 SSM Agent                                              │  │
│   │  ● 仅允许通过 SSM Session Manager 访问                               │  │
│   └─────────────────────────────────────────────────────────────────────┘  │
│                                                                             │
│   6. 镜像清理                                                                │
│   ┌─────────────────────────────────────────────────────────────────────┐  │
│   │  正确清理镜像状态：                                                   │  │
│   │  ● 清除 /etc/machine-id                                              │  │
│   │  ● 删除 SSH host keys                                                │  │
│   │  ● 清除 cloud-init 状态                                              │  │
│   │  ● 清除命令历史                                                      │  │
│   │  ● 清除临时文件和缓存                                                │  │
│   └─────────────────────────────────────────────────────────────────────┘  │
│                                                                             │
│   7. 验证与报告                                                              │
│   ┌─────────────────────────────────────────────────────────────────────┐  │
│   │  合规性验证：                                                         │  │
│   │  ● 通过 OpenSCAP 扫描验证 CIS 合规                                   │  │
│   │  ● CIS 通过率 > 85%                                                  │  │
│   │  ● 生成软件清单 (manifest.txt)                                       │  │
│   │  ● 记录例外项目及原因                                                │  │
│   └─────────────────────────────────────────────────────────────────────┘  │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 项目目录结构

按以下结构组织你的 Capstone 项目：

```
capstone/
├── packer/                          # Packer 构建配置
│   ├── image.pkr.hcl               # 主 Packer 模板
│   └── provisioners/               # 构建脚本目录
│       ├── 01-update.sh            # 系统更新
│       ├── 02-install-nginx.sh     # 安装 Nginx
│       ├── 03-install-cloudwatch.sh # 安装 CloudWatch Agent
│       ├── 04-harden-cis.sh        # CIS 加固
│       └── 99-seal.sh              # 镜像清理
│
├── configs/                         # 配置文件
│   ├── nginx.conf                  # Nginx 配置
│   ├── cloudwatch-config.json      # CloudWatch Agent 配置
│   └── sshd_config.d/              # SSH 加固配置
│       └── 99-cis-hardening.conf
│
├── validation/                      # 验证脚本
│   ├── scan.sh                     # OpenSCAP 扫描脚本
│   ├── verify-image.sh             # 镜像验证脚本
│   └── expected-pass-rate.txt      # 期望通过率
│
├── reports/                         # 生成的报告（构建后）
│   ├── cis-scan-report.html        # CIS 扫描报告
│   └── cis-scan-results.xml        # 扫描结果数据
│
├── manifest.txt                     # 软件清单
├── exceptions.md                    # CIS 例外记录
└── README.md                        # 项目说明文档
```

---

## 实现指南

### Step 1 - 创建项目结构（10 分钟）

```bash
# 创建工作目录
mkdir -p ~/capstone/{packer/provisioners,configs/sshd_config.d,validation,reports}
cd ~/capstone

# 创建 README
cat > README.md << 'EOF'
# Golden Image Capstone

## Overview
Production-ready hardened web server golden image.

## Requirements
- AWS Account with EC2 and AMI permissions
- Packer installed (>= 1.9.0)
- AWS CLI configured

## Build Instructions
```bash
cd packer
packer init image.pkr.hcl
packer build image.pkr.hcl
```

## Validation
```bash
cd validation
./scan.sh
```

## Deliverables
- [ ] Packer template
- [ ] CIS hardening scripts
- [ ] CloudWatch Agent configuration
- [ ] OpenSCAP scan report (>85% pass rate)
- [ ] Software manifest

## Author
[Your Name]

## Date
[Build Date]
EOF
```

### Step 2 - Packer 模板（15 分钟）

创建 Packer 模板 `packer/image.pkr.hcl`：

```hcl
# packer/image.pkr.hcl
# Golden Image Capstone - Production Web Server

packer {
  required_plugins {
    amazon = {
      version = ">= 1.2.0"
      source  = "github.com/hashicorp/amazon"
    }
  }
}

# ===== Variables =====
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
  default = "golden-web-server"
}

variable "ami_version" {
  type    = string
  default = "1.0.0"
}

# ===== Data Source: Find Latest Amazon Linux 2023 =====
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

# ===== Source =====
source "amazon-ebs" "golden" {
  ami_name        = "${var.ami_name_prefix}-${var.ami_version}-{{timestamp}}"
  ami_description = "CIS Level 1 hardened web server golden image"
  instance_type   = var.instance_type
  region          = var.aws_region
  source_ami      = data.amazon-ami.al2023.id
  ssh_username    = "ec2-user"

  # Tags for AMI
  tags = {
    Name          = "${var.ami_name_prefix}-${var.ami_version}-{{timestamp}}"
    Version       = var.ami_version
    BaseAMI       = data.amazon-ami.al2023.id
    Builder       = "packer"
    CIS_Level     = "1"
    Environment   = "production"
    BuildTime     = "{{timestamp}}"
  }

  # Snapshot tags
  snapshot_tags = {
    Name = "${var.ami_name_prefix}-${var.ami_version}-{{timestamp}}-snapshot"
  }
}

# ===== Build =====
build {
  sources = ["source.amazon-ebs.golden"]

  # Step 1: System update
  provisioner "shell" {
    script = "provisioners/01-update.sh"
  }

  # Step 2: Install Nginx
  provisioner "shell" {
    script = "provisioners/02-install-nginx.sh"
  }

  # Step 3: Install CloudWatch Agent
  provisioner "shell" {
    script = "provisioners/03-install-cloudwatch.sh"
  }

  # Step 4: Upload configuration files
  provisioner "file" {
    source      = "../configs/cloudwatch-config.json"
    destination = "/tmp/cloudwatch-config.json"
  }

  provisioner "shell" {
    inline = [
      "sudo mkdir -p /opt/aws/amazon-cloudwatch-agent/etc",
      "sudo mv /tmp/cloudwatch-config.json /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json"
    ]
  }

  # Step 5: CIS hardening
  provisioner "shell" {
    script = "provisioners/04-harden-cis.sh"
  }

  # Step 6: Final seal (cleanup)
  provisioner "shell" {
    script = "provisioners/99-seal.sh"
  }

  # Post-processor: Generate manifest
  post-processor "manifest" {
    output     = "../manifest.json"
    strip_path = true
  }
}
```

### Step 3 - 系统更新脚本（5 分钟）

创建 `packer/provisioners/01-update.sh`：

```bash
#!/bin/bash
# 01-update.sh - System update
set -e

echo "=== Step 1: System Update ==="

# Update all packages
sudo dnf update -y

# Install essential tools
sudo dnf install -y \
    vim \
    curl \
    wget \
    unzip \
    jq \
    openscap-scanner \
    scap-security-guide

echo "=== System update completed ==="
```

### Step 4 - Nginx 安装脚本（5 分钟）

创建 `packer/provisioners/02-install-nginx.sh`：

```bash
#!/bin/bash
# 02-install-nginx.sh - Install and configure Nginx
set -e

echo "=== Step 2: Install Nginx ==="

# Install Nginx
sudo dnf install -y nginx

# Create hardened nginx.conf
sudo tee /etc/nginx/nginx.conf > /dev/null << 'NGINX_CONF'
# Nginx configuration - CIS hardened
user nginx;
worker_processes auto;
error_log /var/log/nginx/error.log;
pid /run/nginx.pid;

events {
    worker_connections 1024;
}

http {
    # Security headers
    server_tokens off;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;

    # Logging
    log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                    '$status $body_bytes_sent "$http_referer" '
                    '"$http_user_agent" "$http_x_forwarded_for"';
    access_log /var/log/nginx/access.log main;

    # Basic settings
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    types_hash_max_size 4096;

    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    # Default server
    server {
        listen 80 default_server;
        listen [::]:80 default_server;
        server_name _;
        root /usr/share/nginx/html;

        location / {
            index index.html;
        }

        # Health check endpoint
        location /health {
            access_log off;
            return 200 "healthy\n";
            add_header Content-Type text/plain;
        }
    }
}
NGINX_CONF

# Create custom welcome page
sudo tee /usr/share/nginx/html/index.html > /dev/null << 'HTML'
<!DOCTYPE html>
<html>
<head>
    <title>Golden Image Web Server</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; background: #f5f5f5; }
        .container { background: white; padding: 30px; border-radius: 5px; max-width: 600px; margin: auto; }
        h1 { color: #333; }
        .status { color: #28a745; font-weight: bold; }
        .info { background: #e9ecef; padding: 15px; border-radius: 3px; margin-top: 20px; }
    </style>
</head>
<body>
    <div class="container">
        <h1>Golden Image Web Server</h1>
        <p class="status">Server is running</p>
        <div class="info">
            <p><strong>CIS Level:</strong> 1 (Hardened)</p>
            <p><strong>Monitoring:</strong> CloudWatch Agent</p>
            <p><strong>Access:</strong> SSM Session Manager</p>
        </div>
    </div>
</body>
</html>
HTML

# Enable and start Nginx
sudo systemctl enable nginx

# Verify configuration
sudo nginx -t

echo "=== Nginx installation completed ==="
```

### Step 5 - CloudWatch Agent 脚本（10 分钟）

创建 `packer/provisioners/03-install-cloudwatch.sh`：

```bash
#!/bin/bash
# 03-install-cloudwatch.sh - Install CloudWatch Agent
set -e

echo "=== Step 3: Install CloudWatch Agent ==="

# Download and install CloudWatch Agent
sudo dnf install -y amazon-cloudwatch-agent

# Verify installation
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -h > /dev/null

# Enable service (will start with IAM role on actual instance)
sudo systemctl enable amazon-cloudwatch-agent

echo "=== CloudWatch Agent installation completed ==="
```

创建 CloudWatch 配置 `configs/cloudwatch-config.json`：

```json
{
  "agent": {
    "metrics_collection_interval": 60,
    "run_as_user": "root"
  },
  "metrics": {
    "namespace": "GoldenImage/WebServer",
    "metrics_collected": {
      "cpu": {
        "measurement": ["cpu_usage_idle", "cpu_usage_user", "cpu_usage_system"],
        "metrics_collection_interval": 60
      },
      "mem": {
        "measurement": ["mem_used_percent", "mem_available"],
        "metrics_collection_interval": 60
      },
      "disk": {
        "measurement": ["disk_used_percent", "disk_free"],
        "resources": ["/"],
        "metrics_collection_interval": 60
      }
    }
  },
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/messages",
            "log_group_name": "/golden-image/system",
            "log_stream_name": "{instance_id}/messages",
            "retention_in_days": 30
          },
          {
            "file_path": "/var/log/nginx/access.log",
            "log_group_name": "/golden-image/nginx",
            "log_stream_name": "{instance_id}/access",
            "retention_in_days": 30
          },
          {
            "file_path": "/var/log/nginx/error.log",
            "log_group_name": "/golden-image/nginx",
            "log_stream_name": "{instance_id}/error",
            "retention_in_days": 30
          }
        ]
      }
    }
  }
}
```

### Step 6 - CIS 加固脚本（15 分钟）

创建 `packer/provisioners/04-harden-cis.sh`：

```bash
#!/bin/bash
# 04-harden-cis.sh - CIS Level 1 Hardening
set -e

echo "=== Step 4: CIS Level 1 Hardening ==="

# ===== 1. SSH Hardening =====
echo "Configuring SSH hardening..."
sudo tee /etc/ssh/sshd_config.d/99-cis-hardening.conf > /dev/null << 'SSHD_CONFIG'
# CIS Level 1 SSH Hardening
# Applied by golden image build process

# Disable root login
PermitRootLogin no

# Disable empty passwords
PermitEmptyPasswords no

# Set maximum authentication attempts
MaxAuthTries 4

# Set login grace time
LoginGraceTime 60

# Set client alive settings (idle timeout)
ClientAliveInterval 300
ClientAliveCountMax 0

# Disable X11 forwarding
X11Forwarding no

# Use strong ciphers only
Ciphers aes256-gcm@openssh.com,aes128-gcm@openssh.com,aes256-ctr,aes192-ctr,aes128-ctr

# Use strong MACs only
MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com,hmac-sha2-512,hmac-sha2-256

# Use strong key exchange algorithms
KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org,ecdh-sha2-nistp256,ecdh-sha2-nistp384,ecdh-sha2-nistp521,diffie-hellman-group-exchange-sha256
SSHD_CONFIG

# Verify SSH configuration
sudo sshd -t

# ===== 2. File Permissions =====
echo "Setting file permissions..."
sudo chmod 644 /etc/passwd
sudo chmod 644 /etc/group
sudo chmod 600 /etc/shadow
sudo chmod 600 /etc/gshadow
sudo chmod 600 /etc/ssh/sshd_config
sudo chmod 700 /root
sudo chmod 600 /boot/grub2/grub.cfg 2>/dev/null || true

# ===== 3. Disable Unnecessary Services =====
echo "Disabling unnecessary services..."
for svc in rpcbind avahi-daemon cups bluetooth postfix; do
    if systemctl list-unit-files | grep -q "^$svc"; then
        sudo systemctl disable $svc 2>/dev/null || true
        sudo systemctl stop $svc 2>/dev/null || true
        echo "  Disabled: $svc"
    fi
done

# ===== 4. Configure Auditd =====
echo "Configuring auditd..."
sudo dnf install -y audit
sudo systemctl enable auditd

# Basic audit rules
sudo tee /etc/audit/rules.d/99-cis.rules > /dev/null << 'AUDIT_RULES'
# CIS Level 1 Audit Rules

# Ensure events that modify date and time information are collected
-a always,exit -F arch=b64 -S adjtimex -S settimeofday -k time-change
-a always,exit -F arch=b32 -S adjtimex -S settimeofday -S stime -k time-change

# Ensure events that modify user/group information are collected
-w /etc/group -p wa -k identity
-w /etc/passwd -p wa -k identity
-w /etc/shadow -p wa -k identity
-w /etc/gshadow -p wa -k identity
-w /etc/security/opasswd -p wa -k identity

# Ensure login and logout events are collected
-w /var/log/lastlog -p wa -k logins
-w /var/run/faillock/ -p wa -k logins

# Ensure session initiation information is collected
-w /var/run/utmp -p wa -k session
-w /var/log/wtmp -p wa -k logins
-w /var/log/btmp -p wa -k logins

# Ensure successful file system mounts are collected
-a always,exit -F arch=b64 -S mount -F auid>=1000 -F auid!=4294967295 -k mounts
-a always,exit -F arch=b32 -S mount -F auid>=1000 -F auid!=4294967295 -k mounts

# Ensure the audit configuration is immutable
-e 2
AUDIT_RULES

# ===== 5. Kernel Hardening =====
echo "Applying kernel hardening..."
sudo tee /etc/sysctl.d/99-cis-hardening.conf > /dev/null << 'SYSCTL'
# CIS Level 1 Kernel Hardening

# Network security
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.secure_redirects = 0
net.ipv4.conf.default.secure_redirects = 0
net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.default.log_martians = 1
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.tcp_syncookies = 1

# IPv6 (disable if not used)
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0

# Core dumps
fs.suid_dumpable = 0

# ASLR
kernel.randomize_va_space = 2
SYSCTL

# Apply sysctl settings
sudo sysctl --system > /dev/null

# ===== 6. Password Policy =====
echo "Configuring password policy..."
# This is a basic example - full implementation depends on PAM configuration
sudo tee /etc/security/pwquality.conf > /dev/null << 'PWQUALITY'
# CIS Password Quality Requirements
minlen = 14
dcredit = -1
ucredit = -1
ocredit = -1
lcredit = -1
PWQUALITY

# ===== 7. Remove Unnecessary Packages =====
echo "Removing unnecessary packages..."
for pkg in telnet ftp tftp-server; do
    sudo dnf remove -y $pkg 2>/dev/null || true
done

echo "=== CIS Level 1 hardening completed ==="
```

### Step 7 - Seal 脚本（10 分钟）

创建 `packer/provisioners/99-seal.sh`：

```bash
#!/bin/bash
# 99-seal.sh - Final image cleanup (seal)
set -e

echo "=== Step 99: Image Seal (Cleanup) ==="

# ===== 1. Clear machine-id =====
echo "Clearing machine-id..."
sudo truncate -s 0 /etc/machine-id
if [ -f /var/lib/dbus/machine-id ]; then
    sudo rm /var/lib/dbus/machine-id
    sudo ln -s /etc/machine-id /var/lib/dbus/machine-id
fi

# ===== 2. Remove SSH host keys =====
echo "Removing SSH host keys..."
sudo rm -f /etc/ssh/ssh_host_*

# ===== 3. Clear cloud-init state =====
echo "Clearing cloud-init state..."
if command -v cloud-init &> /dev/null; then
    sudo cloud-init clean --logs
fi

# ===== 4. Clear command history =====
echo "Clearing command history..."
cat /dev/null > ~/.bash_history
sudo cat /dev/null > /root/.bash_history 2>/dev/null || true
history -c

# ===== 5. Clear log files =====
echo "Clearing log files..."
sudo find /var/log -type f -name "*.log" -exec truncate -s 0 {} \;
sudo find /var/log -type f -name "*.gz" -delete
sudo find /var/log -type f -name "*.[0-9]" -delete
sudo journalctl --vacuum-time=1s 2>/dev/null || true

# ===== 6. Clear temporary files =====
echo "Clearing temporary files..."
sudo rm -rf /tmp/*
sudo rm -rf /var/tmp/*

# ===== 7. Clear package cache =====
echo "Clearing package cache..."
sudo dnf clean all

# ===== 8. Generate software manifest =====
echo "Generating software manifest..."
rpm -qa --qf '%{NAME}|%{VERSION}|%{RELEASE}|%{ARCH}\n' | sort > /tmp/manifest.txt
echo "# Software Manifest" | sudo tee ~/manifest.txt
echo "# Generated: $(date -Iseconds)" | sudo tee -a ~/manifest.txt
echo "# System: $(cat /etc/os-release | grep PRETTY_NAME | cut -d= -f2 | tr -d '"')" | sudo tee -a ~/manifest.txt
echo "" | sudo tee -a ~/manifest.txt
echo "# Format: NAME|VERSION|RELEASE|ARCH" | sudo tee -a ~/manifest.txt
cat /tmp/manifest.txt | sudo tee -a ~/manifest.txt
rm /tmp/manifest.txt

# ===== 9. Verify seal status =====
echo ""
echo "=== Seal Verification ==="
echo -n "machine-id: "
if [ -s /etc/machine-id ]; then
    echo "WARNING - not empty"
else
    echo "OK - cleared"
fi

echo -n "SSH host keys: "
SSH_KEYS=$(ls /etc/ssh/ssh_host_* 2>/dev/null | wc -l)
if [ "$SSH_KEYS" -gt 0 ]; then
    echo "WARNING - $SSH_KEYS files exist"
else
    echo "OK - cleared"
fi

echo -n "cloud-init state: "
if [ -f /var/lib/cloud/instance/boot-finished ]; then
    echo "WARNING - state exists"
else
    echo "OK - cleared"
fi

echo ""
echo "=== Image seal completed ==="
```

### Step 8 - 验证脚本（10 分钟）

创建 `validation/scan.sh`：

```bash
#!/bin/bash
# scan.sh - OpenSCAP CIS compliance scan
set -e

echo "=========================================="
echo "CIS Compliance Scan"
echo "=========================================="
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "Please run as root (sudo ./scan.sh)"
    exit 1
fi

# Create reports directory
REPORT_DIR="../reports"
mkdir -p $REPORT_DIR

# Determine OS and set SCAP content path
if [ -f /usr/share/xml/scap/ssg/content/ssg-al2023-ds.xml ]; then
    SCAP_CONTENT="/usr/share/xml/scap/ssg/content/ssg-al2023-ds.xml"
    PROFILE="xccdf_org.ssgproject.content_profile_cis"
elif [ -f /usr/share/xml/scap/ssg/content/ssg-ubuntu2404-ds.xml ]; then
    SCAP_CONTENT="/usr/share/xml/scap/ssg/content/ssg-ubuntu2404-ds.xml"
    PROFILE="xccdf_org.ssgproject.content_profile_cis_level1_server"
else
    echo "ERROR: SCAP content not found. Install scap-security-guide package."
    exit 1
fi

echo "Using SCAP content: $SCAP_CONTENT"
echo "Profile: $PROFILE"
echo ""

# Run scan
echo "Running OpenSCAP scan..."
oscap xccdf eval \
    --profile $PROFILE \
    --results $REPORT_DIR/cis-scan-results.xml \
    --report $REPORT_DIR/cis-scan-report.html \
    $SCAP_CONTENT || true

# Calculate pass rate
echo ""
echo "=========================================="
echo "Scan Results Summary"
echo "=========================================="

PASS=$(grep -c 'result="pass"' $REPORT_DIR/cis-scan-results.xml 2>/dev/null || echo 0)
FAIL=$(grep -c 'result="fail"' $REPORT_DIR/cis-scan-results.xml 2>/dev/null || echo 0)
NA=$(grep -c 'result="notapplicable"' $REPORT_DIR/cis-scan-results.xml 2>/dev/null || echo 0)

TOTAL=$((PASS + FAIL))
if [ $TOTAL -gt 0 ]; then
    PASS_RATE=$(echo "scale=1; $PASS * 100 / $TOTAL" | bc)
else
    PASS_RATE=0
fi

echo "Pass:           $PASS"
echo "Fail:           $FAIL"
echo "Not Applicable: $NA"
echo ""
echo "Pass Rate:      ${PASS_RATE}%"
echo ""

# Check against threshold
THRESHOLD=85
if (( $(echo "$PASS_RATE >= $THRESHOLD" | bc -l) )); then
    echo "STATUS: PASS (>= ${THRESHOLD}% required)"
    exit 0
else
    echo "STATUS: FAIL (< ${THRESHOLD}% required)"
    echo ""
    echo "Review the HTML report for details:"
    echo "  $REPORT_DIR/cis-scan-report.html"
    exit 1
fi
```

创建 `validation/verify-image.sh`：

```bash
#!/bin/bash
# verify-image.sh - Verify golden image readiness
set -e

echo "=========================================="
echo "Golden Image Verification"
echo "=========================================="
echo ""

ISSUES=0

# 1. Check machine-id
echo "1. machine-id check"
if [ -s /etc/machine-id ]; then
    echo "   [FAIL] machine-id is not empty"
    ISSUES=$((ISSUES + 1))
else
    echo "   [PASS] machine-id is cleared"
fi

# 2. Check SSH host keys
echo "2. SSH host keys check"
SSH_KEYS=$(ls /etc/ssh/ssh_host_* 2>/dev/null | wc -l)
if [ "$SSH_KEYS" -gt 0 ]; then
    echo "   [FAIL] $SSH_KEYS SSH host key files exist"
    ISSUES=$((ISSUES + 1))
else
    echo "   [PASS] SSH host keys are cleared"
fi

# 3. Check cloud-init state
echo "3. cloud-init state check"
if [ -f /var/lib/cloud/instance/boot-finished ]; then
    echo "   [FAIL] cloud-init state exists"
    ISSUES=$((ISSUES + 1))
else
    echo "   [PASS] cloud-init state is cleared"
fi

# 4. Check Nginx service
echo "4. Nginx service check"
if systemctl is-enabled nginx &>/dev/null; then
    echo "   [PASS] Nginx is enabled"
else
    echo "   [FAIL] Nginx is not enabled"
    ISSUES=$((ISSUES + 1))
fi

# 5. Check CloudWatch Agent
echo "5. CloudWatch Agent check"
if systemctl is-enabled amazon-cloudwatch-agent &>/dev/null; then
    echo "   [PASS] CloudWatch Agent is enabled"
else
    echo "   [FAIL] CloudWatch Agent is not enabled"
    ISSUES=$((ISSUES + 1))
fi

# 6. Check SSH hardening
echo "6. SSH hardening check"
if grep -q "PermitRootLogin no" /etc/ssh/sshd_config.d/*.conf 2>/dev/null; then
    echo "   [PASS] SSH root login is disabled"
else
    echo "   [FAIL] SSH root login is not properly configured"
    ISSUES=$((ISSUES + 1))
fi

# 7. Check auditd
echo "7. Auditd check"
if systemctl is-enabled auditd &>/dev/null; then
    echo "   [PASS] Auditd is enabled"
else
    echo "   [FAIL] Auditd is not enabled"
    ISSUES=$((ISSUES + 1))
fi

# 8. Check manifest
echo "8. Manifest check"
if [ -f ~/manifest.txt ] || [ -f /tmp/manifest.txt ]; then
    echo "   [PASS] Software manifest exists"
else
    echo "   [WARN] Software manifest not found"
fi

# Summary
echo ""
echo "=========================================="
if [ "$ISSUES" -eq 0 ]; then
    echo "RESULT: PASS - Image is ready for capture"
    exit 0
else
    echo "RESULT: FAIL - $ISSUES issue(s) found"
    exit 1
fi
```

创建 `validation/expected-pass-rate.txt`：

```
# CIS Compliance Pass Rate Threshold
# Golden images must achieve at least this pass rate

MINIMUM_PASS_RATE=85

# Notes:
# - Some CIS rules may be marked as exceptions
# - See exceptions.md for documented exceptions
# - Pass rate is calculated as: pass / (pass + fail) * 100
```

---

## 验证检查清单

完成 Capstone 后，使用以下检查清单验证你的工作：

### 启动测试

- [ ] 从镜像成功启动新实例
- [ ] Nginx 服务自动启动
- [ ] 访问 http://<instance-ip> 显示欢迎页面
- [ ] 访问 http://<instance-ip>/health 返回 "healthy"

### 安全验证

- [ ] SSH 端口不允许 root 登录
- [ ] SSM Session Manager 可以访问实例
- [ ] CloudWatch Agent 服务正在运行
- [ ] CIS 扫描通过率 >= 85%
- [ ] auditd 服务正在运行

### 清理验证

- [ ] `/etc/machine-id` 为空或不存在
- [ ] SSH host keys 已清除（新实例会自动生成）
- [ ] cloud-init 状态已清除
- [ ] 命令历史已清除

### 文档验证

- [ ] `manifest.txt` 列出所有已安装的包及版本
- [ ] `README.md` 说明构建和验证过程
- [ ] `exceptions.md` 记录任何 CIS 例外项目

---

## 评分标准

| 评分项 | 权重 | 说明 |
|--------|------|------|
| **功能正确性** | 30% | 实例能正常启动，Nginx 运行，健康检查通过 |
| **安全合规** | 30% | CIS 通过率 >= 85%，SSH 加固，SSM 配置正确 |
| **可复现性** | 20% | Packer 模板能重复构建相同结果 |
| **文档质量** | 20% | manifest 完整，README 清晰，例外有记录 |

### 评分细则

**功能正确性（30 分）**
- 实例启动成功：10 分
- Nginx 服务运行：10 分
- CloudWatch Agent 配置正确：10 分

**安全合规（30 分）**
- CIS 通过率 >= 85%：15 分
- SSH 加固配置正确：5 分
- auditd 配置正确：5 分
- 镜像清理完成：5 分

**可复现性（20 分）**
- Packer 模板语法正确：10 分
- 能多次构建相同结果：10 分

**文档质量（20 分）**
- manifest.txt 完整：5 分
- README.md 清晰：5 分
- 例外记录完整：5 分
- 代码注释充分：5 分

---

## 职场小贴士（Japan IT Context）

### 本番要件（Production Requirements）

在日本企业，金色镜像需要满足严格的本番環境要求：

```
┌─────────────────────────────────────────────────────────────────────────────┐
│            本番環境向けゴールデンイメージ要件                                   │
│            (Production Golden Image Requirements)                           │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│   1. セキュリティ要件 (Security Requirements)                                │
│   ┌─────────────────────────────────────────────────────────────────────┐  │
│   │  □ CIS Benchmark Level 1 準拠                                       │  │
│   │  □ 脆弱性スキャン実施済み（Trivy, Inspector）                        │  │
│   │  □ SSH ルートログイン禁止                                            │  │
│   │  □ 不要なサービス無効化                                              │  │
│   │  □ 監査ログ設定済み (auditd)                                         │  │
│   └─────────────────────────────────────────────────────────────────────┘  │
│                                                                             │
│   2. 運用要件 (Operational Requirements)                                    │
│   ┌─────────────────────────────────────────────────────────────────────┐  │
│   │  □ CloudWatch Agent によるメトリクス収集                             │  │
│   │  □ ログの CloudWatch Logs への転送                                   │  │
│   │  □ SSM Session Manager によるアクセス                                │  │
│   │  □ 自動起動設定（サービス有効化）                                     │  │
│   └─────────────────────────────────────────────────────────────────────┘  │
│                                                                             │
│   3. 構成管理要件 (Configuration Management)                                │
│   ┌─────────────────────────────────────────────────────────────────────┐  │
│   │  □ ソフトウェア一覧（manifest.txt）                                  │  │
│   │  □ 設計書との整合性確認                                              │  │
│   │  □ 変更履歴の記録                                                    │  │
│   │  □ バージョン管理                                                    │  │
│   └─────────────────────────────────────────────────────────────────────┘  │
│                                                                             │
│   4. 監査要件 (Audit Requirements)                                          │
│   ┌─────────────────────────────────────────────────────────────────────┐  │
│   │  □ CIS スキャンレポート保存                                          │  │
│   │  □ 例外事項の文書化                                                  │  │
│   │  □ 承認フローの証跡                                                  │  │
│   │  □ ビルドログの保存                                                  │  │
│   └─────────────────────────────────────────────────────────────────────┘  │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 監査対応（Audit Response）

本 Capstone で生成するドキュメントは、監査時に以下の証跡として活用できます：

| ドキュメント | 監査対応用途 |
|-------------|-------------|
| manifest.txt | ソフトウェア構成の証明 |
| cis-scan-report.html | セキュリティ基準準拠の証明 |
| exceptions.md | 例外事項の正当性説明 |
| README.md | 構築手順の再現性証明 |
| Packer template | 構成の自動化・標準化証明 |

### 日本企業での報告フォーマット

```markdown
# ゴールデンイメージ構築完了報告書

## 基本情報
- イメージ名: golden-web-server-1.0.0-20250110
- AMI ID: ami-0123456789abcdef0
- ベース AMI: Amazon Linux 2023
- 構築日時: 2025-01-10 14:30:00 JST
- 構築者: [担当者名]

## セキュリティ準拠状況
- CIS Benchmark Level 1 準拠率: 87.5%
- 例外項目数: 3件（詳細は exceptions.md 参照）
- 脆弱性スキャン結果: Critical 0件、High 0件

## 構成情報
- Nginx: 1.24.0
- CloudWatch Agent: 1.300xxx.x
- SSM Agent: 3.2.xxxx.0
- 合計パッケージ数: 245

## 承認
- 作成者確認: ____________ (日付: ______)
- レビュー者確認: ____________ (日付: ______)
- 本番リリース承認: ____________ (日付: ______)
```

---

## 提出方法

### 方法 1：Git リポジトリ

```bash
# プロジェクトを Git リポジトリとして初期化
cd ~/capstone
git init
git add .
git commit -m "feat: Golden Image Capstone - CIS Level 1 hardened web server"

# リモートリポジトリにプッシュ（オプション）
# git remote add origin <your-repo-url>
# git push -u origin main
```

### 方法 2：ZIP アーカイブ

```bash
cd ~
zip -r capstone-$(date +%Y%m%d).zip capstone/
```

### 提出物チェックリスト

提出前に以下を確認してください：

- [ ] packer/image.pkr.hcl が存在する
- [ ] packer/provisioners/ に全スクリプトが存在する
- [ ] configs/ に設定ファイルが存在する
- [ ] validation/scan.sh が実行可能
- [ ] manifest.txt が生成されている
- [ ] reports/cis-scan-report.html が生成されている
- [ ] README.md が完成している
- [ ] exceptions.md が作成されている（例外がある場合）

---

## 延伸学習

本 Capstone を完了した後、以下のトピックで更に深く学べます：

### 発展課題

1. **マルチアーキテクチャ対応**
   - ARM64 (Graviton) 版の golden image を構築
   - x86_64 と ARM64 のデュアルビルド

2. **CI/CD 統合**
   - GitHub Actions で自動ビルド
   - AMI の自動テストパイプライン

3. **STIG 準拠**
   - CIS Level 2 または DISA STIG 準拠
   - より厳格なセキュリティ要件対応

4. **コンテナイメージ版**
   - 同等の加固を適用したコンテナイメージ
   - ECR へのプッシュ自動化

### 関連コース

- [LX11-CONTAINERS](../../containers/) - コンテナセキュリティ
- [Terraform Course](../../../automation/terraform/) - IaC による AMI 管理
- [CloudFormation Course](../../../automation/cloudformation/) - Launch Template 管理

---

## 本課小結

| 項目 | 内容 |
|------|------|
| **目的** | 生産級金色鏡像構築能力の実証 |
| **成果物** | Packer テンプレート、加固スクリプト、検証レポート |
| **評価基準** | 機能 30%、セキュリティ 30%、再現性 20%、文書 20% |
| **合格基準** | CIS 通過率 >= 85%、全検証項目パス |

---

## 清理资源

Capstone 完成後、以下のリソースを清理してください：

```bash
# 作成した AMI を削除（必要な場合）
# aws ec2 deregister-image --image-id ami-xxxxx

# 関連するスナップショットを削除
# aws ec2 delete-snapshot --snapshot-id snap-xxxxx

# テストインスタンスを終了
# aws ec2 terminate-instances --instance-ids i-xxxxx

# ローカルファイルの清理
rm -rf ~/capstone
```

---

## 系列导航

[<- 09 - 可观测性集成](../09-observability/) | [系列首页](../) | [课程完成]

---

**恭喜完成 LX12-CLOUD 课程！**

你现在具备了在云环境中管理 Linux 系统的核心技能：
- cloud-init 启动流程调试
- 元数据服务与 IMDSv2
- 云网络与存储管理
- IAM 与实例配置文件
- 金色镜像构建与加固
- 可观测性集成
- 生产级镜像管道构建

这些技能是日本 IT 企业云基础设施工程师的必备能力。祝你在职场上取得成功！
