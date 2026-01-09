# 02 - cloud-init 启动流程（cloud-init Fundamentals）

> **目标**：理解 cloud-init 四阶段启动，学会调试"沉默启动"故障  
> **前置**：[01 - 云中 Linux 有何不同](../01-cloud-context/)、基础 systemd 概念  
> **时间**：2.5 小时  
> **实战场景**：诊断 user-data 执行失败的障害対応  

---

## 将学到的内容

1. 理解 cloud-init 四个启动阶段及其执行顺序
2. 编写 shell 脚本和 cloud-config YAML 两种 user-data
3. 调试 cloud-init 失败的启动（The Silent Boot 场景）
4. 编写幂等的初始化脚本，避免 ASG 扩容失败

---

## 先跑起来！（10 分钟）

> 在学习 cloud-init 理论之前，先观察它在你的实例上做了什么。  

在任意 EC2 实例上运行以下命令：

```bash
# cloud-init 执行完了吗？
cloud-init status

# 查看实例的 user-data（你启动时传入的脚本）
sudo cat /var/lib/cloud/instance/user-data.txt

# 查看 cloud-init 执行了什么
sudo cat /var/log/cloud-init-output.log | tail -30

# 查看四个阶段的执行状态
cloud-init analyze show
```

**你刚刚看到了什么？**

```
status: done
```

这表示 cloud-init 已完成所有四个阶段的执行。如果你看到 `status: running`，说明还在执行中。

**重要发现**：
- `/var/lib/cloud/instance/user-data.txt` 保存了你传入的 user-data
- `/var/log/cloud-init-output.log` 记录了脚本的标准输出
- `cloud-init analyze show` 展示了各阶段的耗时

现在让我们理解 cloud-init 是如何工作的。

---

## Step 1 - cloud-init 是什么？（10 分钟）

### 1.1 跨云初始化框架

cloud-init 是一个**跨云平台**的实例初始化工具，由 Canonical（Ubuntu 的母公司）开发：

```
┌─────────────────────────────────────────────────────────────┐
│                    cloud-init 架构                          │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│   ┌───────────┐    ┌───────────┐    ┌───────────┐         │
│   │    AWS    │    │    GCP    │    │   Azure   │         │
│   │  EC2 IMDS │    │  Metadata │    │  Wireserver│        │
│   └─────┬─────┘    └─────┬─────┘    └─────┬─────┘         │
│         │                │                │                │
│         └────────────────┼────────────────┘                │
│                          ▼                                  │
│                  ┌───────────────┐                         │
│                  │   Datasource  │  ← 数据源抽象层          │
│                  └───────┬───────┘                         │
│                          ▼                                  │
│                  ┌───────────────┐                         │
│                  │  cloud-init   │  ← 核心引擎              │
│                  └───────┬───────┘                         │
│                          │                                  │
│         ┌────────────────┼────────────────┐                │
│         ▼                ▼                ▼                │
│   ┌──────────┐    ┌──────────┐    ┌──────────┐            │
│   │ 配置网络  │    │ 创建用户  │    │ 执行脚本  │            │
│   └──────────┘    └──────────┘    └──────────┘            │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### 1.2 Datasource：数据从哪来？

cloud-init 通过 **Datasource** 获取配置数据：

| 云平台 | Datasource | 元数据地址 |
|--------|------------|------------|
| AWS EC2 | `Ec2` | `169.254.169.254` |
| GCP | `GCE` | `169.254.169.254` |
| Azure | `Azure` | `169.254.169.254` |
| OpenStack | `OpenStack` | `169.254.169.254` |
| 本地测试 | `NoCloud` | ISO/seed 目录 |

```bash
# 查看当前 datasource
cloud-init query ds
```

### 1.3 首次启动检测：Instance-ID

cloud-init 通过比对 **Instance-ID** 判断是否首次启动：

```bash
# 当前实例 ID
cloud-init query instance_id

# 保存的实例 ID
cat /var/lib/cloud/data/instance-id
```

**重要**：如果两者不同，cloud-init 会重新执行配置（这就是为什么 AMI 需要清理 `/var/lib/cloud/`）。

---

## Step 2 - 四个启动阶段（20 分钟）

### 2.1 阶段全景图

cloud-init 在 systemd 启动流程中被调用四次，每次执行不同的任务：

<!-- DIAGRAM: cloud-init-four-stages -->
```
┌─────────────────────────────────────────────────────────────────────────┐
│                    cloud-init 四阶段启动流程                             │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  Linux Kernel Boot                                                      │
│       │                                                                 │
│       ▼                                                                 │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │ Stage 1: init-local (cloud-init-local.service)                  │   │
│  │ ┌─────────────────────────────────────────────────────────────┐ │   │
│  │ │ ● 无网络阶段                                                 │ │   │
│  │ │ ● 从本地数据源读取配置                                       │ │   │
│  │ │ ● 执行 bootcmd（网络配置前）                                 │ │   │
│  │ │ ● 写入网络配置文件                                           │ │   │
│  │ └─────────────────────────────────────────────────────────────┘ │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│       │                                                                 │
│       ▼                                                                 │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │ Stage 2: init (cloud-init.service)                              │   │
│  │ ┌─────────────────────────────────────────────────────────────┐ │   │
│  │ │ ● 网络已就绪                                                 │ │   │
│  │ │ ● 从元数据服务获取 user-data                                 │ │   │
│  │ │ ● 设置主机名、SSH 密钥                                       │ │   │
│  │ │ ● 扩展根文件系统                                             │ │   │
│  │ └─────────────────────────────────────────────────────────────┘ │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│       │                                                                 │
│       ▼                                                                 │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │ Stage 3: config (cloud-config.service)                          │   │
│  │ ┌─────────────────────────────────────────────────────────────┐ │   │
│  │ │ ● 执行配置模块                                               │ │   │
│  │ │ ● write_files、packages、users                              │ │   │
│  │ │ ● 挂载磁盘、配置 NTP                                         │ │   │
│  │ └─────────────────────────────────────────────────────────────┘ │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│       │                                                                 │
│       ▼                                                                 │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │ Stage 4: final (cloud-final.service)                            │   │
│  │ ┌─────────────────────────────────────────────────────────────┐ │   │
│  │ │ ● 所有系统服务已启动                                         │ │   │
│  │ │ ● 执行 runcmd                                                │ │   │
│  │ │ ● 执行用户脚本（#!/bin/bash）                                │ │   │
│  │ │ ● 执行 final_message                                         │ │   │
│  │ └─────────────────────────────────────────────────────────────┘ │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│       │                                                                 │
│       ▼                                                                 │
│  System Ready (login prompt)                                            │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```
<!-- /DIAGRAM -->

### 2.2 各阶段详解

| 阶段 | systemd 服务 | 网络状态 | 主要任务 |
|------|--------------|----------|----------|
| **init-local** | `cloud-init-local.service` | 无网络 | bootcmd、网络配置 |
| **init** | `cloud-init.service` | 网络就绪 | 获取 user-data、SSH 密钥 |
| **config** | `cloud-config.service` | 网络就绪 | write_files、packages、users |
| **final** | `cloud-final.service` | 系统就绪 | runcmd、用户脚本 |

### 2.3 动手验证：观察四阶段

```bash
# 查看四个 systemd 服务的状态
systemctl status cloud-init-local cloud-init cloud-config cloud-final

# 查看启动顺序和耗时
cloud-init analyze show

# 查看各阶段日志
journalctl -u cloud-init-local --no-pager | tail -20
journalctl -u cloud-init --no-pager | tail -20
journalctl -u cloud-config --no-pager | tail -20
journalctl -u cloud-final --no-pager | tail -20
```

### 2.4 bootcmd vs runcmd：执行时机不同

```yaml
#cloud-config
bootcmd:
  - echo "bootcmd: $(date)" >> /var/log/cloud-init-stages.log
  # 在 init-local 阶段执行（无网络）
  # 每次启动都执行

runcmd:
  - echo "runcmd: $(date)" >> /var/log/cloud-init-stages.log
  # 在 final 阶段执行（系统就绪）
  # 仅首次启动执行
```

**关键区别**：
- `bootcmd`：每次启动都执行，适合网络配置前的操作
- `runcmd`：仅首次启动执行，适合一次性初始化

---

## Step 3 - User-data 类型（15 分钟）

### 3.1 三种 User-data 格式

cloud-init 支持三种 user-data 格式：

<!-- DIAGRAM: user-data-types -->
```
┌─────────────────────────────────────────────────────────────────────────┐
│                      User-data 类型对比                                  │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  ┌───────────────────────────────────────────────────────────────────┐ │
│  │ Type 1: Shell Script                                              │ │
│  ├───────────────────────────────────────────────────────────────────┤ │
│  │ 识别标志: #!/bin/bash (或其他 shebang)                            │ │
│  │ 执行阶段: final                                                   │ │
│  │ 适用场景: 简单的一次性配置                                         │ │
│  │                                                                   │ │
│  │ #!/bin/bash                                                       │ │
│  │ yum install -y nginx                                              │ │
│  │ systemctl start nginx                                             │ │
│  └───────────────────────────────────────────────────────────────────┘ │
│                                                                         │
│  ┌───────────────────────────────────────────────────────────────────┐ │
│  │ Type 2: cloud-config YAML                                         │ │
│  ├───────────────────────────────────────────────────────────────────┤ │
│  │ 识别标志: #cloud-config (必须在第一行)                            │ │
│  │ 执行阶段: 多阶段（取决于模块）                                    │ │
│  │ 适用场景: 声明式配置、复杂场景                                     │ │
│  │                                                                   │ │
│  │ #cloud-config                                                     │ │
│  │ packages:                                                         │ │
│  │   - nginx                                                         │ │
│  │ runcmd:                                                           │ │
│  │   - systemctl start nginx                                         │ │
│  └───────────────────────────────────────────────────────────────────┘ │
│                                                                         │
│  ┌───────────────────────────────────────────────────────────────────┐ │
│  │ Type 3: Multi-part MIME                                           │ │
│  ├───────────────────────────────────────────────────────────────────┤ │
│  │ 识别标志: Content-Type: multipart/mixed                           │ │
│  │ 执行阶段: 取决于各部分类型                                        │ │
│  │ 适用场景: 组合多种配置类型                                         │ │
│  │                                                                   │ │
│  │ MIME-Version: 1.0                                                 │ │
│  │ Content-Type: multipart/mixed; boundary="==BOUNDARY=="            │ │
│  │                                                                   │ │
│  │ --==BOUNDARY==                                                    │ │
│  │ Content-Type: text/cloud-config                                   │ │
│  │ packages: [nginx]                                                 │ │
│  │                                                                   │ │
│  │ --==BOUNDARY==                                                    │ │
│  │ Content-Type: text/x-shellscript                                  │ │
│  │ #!/bin/bash                                                       │ │
│  │ echo "Hello from script"                                          │ │
│  └───────────────────────────────────────────────────────────────────┘ │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```
<!-- /DIAGRAM -->

### 3.2 什么时候用哪种？

| 场景 | 推荐格式 | 原因 |
|------|----------|------|
| 简单脚本（< 20 行） | Shell Script | 直接、易读 |
| 安装包、创建用户 | cloud-config | 声明式、幂等 |
| 复杂配置 + 脚本 | Multi-part MIME | 组合两者优点 |
| 生产环境 | cloud-config | 更易维护、有验证 |

### 3.3 cloud-config 示例

```yaml
#cloud-config
# 注意：#cloud-config 必须在第一行！

# 安装软件包
packages:
  - nginx
  - htop
  - vim

# 写入文件
write_files:
  - path: /etc/motd
    content: |
      Welcome to Web Server
      Managed by cloud-init
    permissions: '0644'
    owner: root:root

# 创建用户
users:
  - name: webadmin
    groups: wheel
    sudo: ALL=(ALL) NOPASSWD:ALL
    ssh_authorized_keys:
      - ssh-rsa AAAAB3... your-key-here

# 执行命令（final 阶段）
runcmd:
  - systemctl enable nginx
  - systemctl start nginx
  - echo "cloud-init completed at $(date)" >> /var/log/cloud-init-done.log
```

---

## Step 4 - 常用模块详解（15 分钟）

### 4.1 核心模块一览

| 模块 | 用途 | 执行阶段 |
|------|------|----------|
| `bootcmd` | 网络配置前执行命令 | init-local |
| `write_files` | 写入文件 | config |
| `packages` | 安装软件包 | config |
| `users` | 创建用户和 SSH 密钥 | config |
| `runcmd` | 执行命令 | final |
| `final_message` | 启动完成消息 | final |

### 4.2 write_files 详解

```yaml
#cloud-config
write_files:
  # 基本用法
  - path: /etc/myapp/config.yml
    content: |
      server:
        port: 8080
        host: 0.0.0.0
    permissions: '0644'
    owner: root:root

  # 追加模式（不覆盖原文件）
  - path: /etc/profile.d/custom.sh
    content: |
      export JAVA_HOME=/usr/lib/jvm/java-11
    append: true

  # Base64 编码（用于二进制文件）
  - path: /usr/local/bin/tool
    encoding: base64
    content: <base64-encoded-content>
    permissions: '0755'
```

### 4.3 packages 模块

```yaml
#cloud-config
# 更新包索引
package_update: true

# 升级已安装的包
package_upgrade: true

# 安装软件包
packages:
  - nginx
  - postgresql
  - python3-pip
  # 指定版本
  - docker-ce=5:24.0.0-1~ubuntu

# 安装后重启（如果需要）
package_reboot_if_required: true
```

### 4.4 users 模块

```yaml
#cloud-config
users:
  # 保留默认用户（重要！）
  - default

  # 创建新用户
  - name: deployer
    gecos: Deployment User
    groups: docker, wheel
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    ssh_authorized_keys:
      - ssh-rsa AAAAB3...
    lock_passwd: true  # 禁止密码登录
```

> **警告**：如果忘记 `- default`，可能会覆盖默认用户（如 ec2-user），导致无法 SSH 登录！  

---

## Step 5 - 调试 cloud-init（20 分钟）

### 5.1 日志文件位置

| 日志文件 | 内容 |
|----------|------|
| `/var/log/cloud-init.log` | 详细执行日志（DEBUG 级别） |
| `/var/log/cloud-init-output.log` | 脚本的标准输出/错误 |
| `/run/cloud-init/result.json` | 执行结果 JSON |
| `/var/lib/cloud/instance/` | 实例数据缓存 |

### 5.2 常用调试命令

```bash
# 查看当前状态
cloud-init status
cloud-init status --long  # 详细状态

# 查看执行分析
cloud-init analyze show
cloud-init analyze blame  # 类似 systemd-analyze blame

# 查询实例数据
cloud-init query --all
cloud-init query instance_id
cloud-init query userdata  # 查看 user-data

# 验证 cloud-config 语法
cloud-init schema --config-file /path/to/config.yaml

# 查看最近的错误
grep -i error /var/log/cloud-init.log | tail -20
grep -i error /var/log/cloud-init-output.log | tail -20
```

### 5.3 result.json 解读

```bash
cat /run/cloud-init/result.json
```

```json
{
  "v1": {
    "datasource": "DataSourceEc2Local",
    "errors": [],
    "recoverable_errors": {},
    "boot_id": "abc123...",
    "status": "done",
    "exception": null
  }
}
```

- `status: done` = 成功完成
- `status: error` = 有错误发生
- `errors: [...]` = 具体错误信息

---

## Lab 1 - cloud-init 阶段观察实验（25 分钟）

### 实验目标

在四个阶段分别写入文件，观察执行顺序。

### Step 1 - 准备 user-data

创建以下 cloud-config：

```yaml
#cloud-config

# Stage 1: bootcmd (init-local 阶段)
bootcmd:
  - echo "Stage 1 - bootcmd executed at $(date '+%H:%M:%S.%N')" >> /var/log/cloud-init-stages.log

# Stage 3: write_files (config 阶段)
write_files:
  - path: /var/log/cloud-init-stages.log
    content: |
      === cloud-init Stage Observation ===
    append: true
    permissions: '0644'

# Stage 3: packages (config 阶段)
packages:
  - htop

# Stage 4: runcmd (final 阶段)
runcmd:
  - echo "Stage 4 - runcmd executed at $(date '+%H:%M:%S.%N')" >> /var/log/cloud-init-stages.log
  - echo "--- Packages installed ---" >> /var/log/cloud-init-stages.log
  - rpm -q htop >> /var/log/cloud-init-stages.log || dpkg -l htop >> /var/log/cloud-init-stages.log

final_message: |
  cloud-init completed!
  Version: $version
  Datasource: $datasource
  Uptime: $uptime seconds
```

### Step 2 - 启动实例

使用 AWS CLI 启动：

```bash
# 将 user-data 保存为文件
cat > stage-test-userdata.yaml << 'EOF'
#cloud-config
bootcmd:
  - echo "Stage 1 - bootcmd executed at $(date '+%H:%M:%S.%N')" >> /var/log/cloud-init-stages.log
write_files:
  - path: /var/log/cloud-init-stages.log
    content: |
      === cloud-init Stage Observation ===
    append: true
    permissions: '0644'
packages:
  - htop
runcmd:
  - echo "Stage 4 - runcmd executed at $(date '+%H:%M:%S.%N')" >> /var/log/cloud-init-stages.log
  - echo "--- Packages installed ---" >> /var/log/cloud-init-stages.log
  - rpm -q htop >> /var/log/cloud-init-stages.log 2>/dev/null || dpkg -l htop >> /var/log/cloud-init-stages.log 2>/dev/null
final_message: |
  cloud-init completed!
  Uptime: $uptime seconds
EOF

# 启动实例（替换 subnet-id、security-group-id、key-name）
aws ec2 run-instances \
  --image-id resolve:ssm:/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64 \
  --instance-type t3.micro \
  --key-name YOUR_KEY_NAME \
  --subnet-id subnet-xxxxxxxx \
  --security-group-ids sg-xxxxxxxx \
  --user-data file://stage-test-userdata.yaml \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=cloud-init-stage-test}]'
```

### Step 3 - 验证结果

SSH 进入实例后：

```bash
# 查看阶段执行日志
cat /var/log/cloud-init-stages.log

# 查看执行时间分析
cloud-init analyze show

# 验证 htop 已安装
which htop
```

**预期输出**：

```
=== cloud-init Stage Observation ===
Stage 1 - bootcmd executed at 10:15:23.456789
Stage 4 - runcmd executed at 10:15:45.123456
--- Packages installed ---
htop-3.2.1-1.amzn2023.x86_64
```

### 检查清单

- [ ] 观察到 bootcmd 先于 runcmd 执行
- [ ] 理解 write_files 在 config 阶段执行
- [ ] htop 已成功安装
- [ ] 能解释四个阶段的顺序

---

## Lab 2 - The Silent Boot（沉默启动）场景（30 分钟）

### 场景描述

> 实例状态显示 "Running"，但 Web 服务器没有启动，SSH 无法连接。  
> 控制台系统日志被截断。工程师需要诊断 user-data 失败原因。  

这是日本 IT 现场最常见的**障害対応**场景之一。

### 实验目标

故意制造 user-data 失败，学习诊断方法。

### Step 1 - 制造问题

创建一个有问题的 user-data：

```yaml
#cloud-config
packages:
  - nginx

runcmd:
  # 问题 1: apt-get 没有 -y 参数，会等待用户输入
  - apt-get install vim

  # 问题 2: YAML 缩进错误（下面的行缩进不一致）
  -  echo "This has wrong indentation"

  # 问题 3: 假设的网络服务不存在
  - systemctl start nonexistent-service
```

### Step 2 - 启动实例并观察

```bash
# 使用有问题的 user-data 启动实例
aws ec2 run-instances \
  --image-id resolve:ssm:/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64 \
  --instance-type t3.micro \
  --key-name YOUR_KEY_NAME \
  --subnet-id subnet-xxxxxxxx \
  --security-group-ids sg-xxxxxxxx \
  --user-data file://broken-userdata.yaml \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=silent-boot-test}]'
```

等待实例状态变为 "Running"，然后：

```bash
# 获取系统日志（控制台输出）
aws ec2 get-console-output --instance-id i-xxxxxxxxx --output text
```

### Step 3 - 诊断流程

SSH 进入实例后（如果能连接）：

```bash
# 1. 检查 cloud-init 状态
cloud-init status --long

# 2. 查看执行结果
cat /run/cloud-init/result.json | python3 -m json.tool

# 3. 查找错误
grep -i -E "(error|failed|warning)" /var/log/cloud-init.log | tail -30

# 4. 查看脚本输出
cat /var/log/cloud-init-output.log | tail -50

# 5. 验证 user-data 是否正确解析
cloud-init query userdata
```

### Step 4 - 常见错误及解决方案

| 错误类型 | 症状 | 解决方案 |
|----------|------|----------|
| YAML 语法错误 | cloud-init 完全不执行 | 用 `cloud-init schema --config-file` 验证 |
| 交互式命令 | 脚本挂起，实例卡住 | 使用 `-y` 参数，设置 `DEBIAN_FRONTEND=noninteractive` |
| 服务不存在 | 脚本部分执行 | 添加错误处理，使用 `|| true` |
| 网络依赖 | 在网络就绪前执行失败 | 使用 runcmd 而非 bootcmd |

### Step 5 - 修复后的 user-data

```yaml
#cloud-config

# 防止交互式提示
package_update: true

packages:
  - nginx
  - vim

runcmd:
  # 正确：使用 -y 参数
  - DEBIAN_FRONTEND=noninteractive apt-get install -y htop || yum install -y htop

  # 正确：一致的缩进
  - echo "This has correct indentation"

  # 正确：添加错误处理
  - systemctl start nginx || echo "nginx start failed but continuing"

  # 记录完成状态
  - echo "cloud-init user-data completed successfully at $(date)" >> /var/log/cloud-init-done.log
```

### 检查清单

- [ ] 能够从控制台日志识别 cloud-init 失败
- [ ] 知道如何使用 `cloud-init status --long` 检查状态
- [ ] 理解 `/var/log/cloud-init.log` 和 `/var/log/cloud-init-output.log` 的区别
- [ ] 能修复交互式命令和 YAML 语法错误

---

## Lab 3 - 幂等脚本练习（20 分钟）

### 为什么幂等性重要？

在 Auto Scaling Group (ASG) 环境中，实例可能随时被替换：

```
┌─────────────────────────────────────────────────────────────┐
│                    ASG 扩容场景                              │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  流量增加 → ASG 启动新实例 → cloud-init 执行 user-data      │
│                                                             │
│  问题：如果 user-data 不幂等                                 │
│  ┌─────────┐     ┌─────────┐     ┌─────────┐              │
│  │ 实例 1   │     │ 实例 2   │     │ 实例 3   │              │
│  │ 配置 OK  │     │ 配置失败  │     │ 配置 OK  │              │
│  └─────────┘     └─────────┘     └─────────┘              │
│       ✓              ✗              ✓                      │
│                      │                                      │
│                      ▼                                      │
│                 健康检查失败                                 │
│                 实例被替换                                   │
│                 无限循环...                                  │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### 幂等脚本设计原则

```bash
#!/bin/bash
# 幂等脚本模板

# 原则 1: 检查后再执行
if [ ! -f /etc/myapp/config.yml ]; then
    echo "Creating config file..."
    mkdir -p /etc/myapp
    cat > /etc/myapp/config.yml << 'CONFIG'
server:
  port: 8080
CONFIG
else
    echo "Config file already exists, skipping..."
fi

# 原则 2: 使用幂等命令
# 不好：append 每次都追加
# echo "export PATH=..." >> /etc/profile

# 好：使用 grep 检查
if ! grep -q 'JAVA_HOME' /etc/profile; then
    echo 'export JAVA_HOME=/usr/lib/jvm/java-11' >> /etc/profile
fi

# 原则 3: 使用守卫文件（guard file）
GUARD_FILE=/var/lib/cloud/scripts/init-done

if [ -f "$GUARD_FILE" ]; then
    echo "Initialization already completed, skipping..."
    exit 0
fi

# ... 执行初始化任务 ...

# 标记完成
touch "$GUARD_FILE"
echo "Initialization completed successfully"
```

### 实验：对比幂等与非幂等脚本

创建两个测试脚本：

**非幂等脚本（问题版本）**:

```bash
#!/bin/bash
# BAD: 非幂等脚本

# 每次执行都会追加
echo "127.0.0.1 myapp.local" >> /etc/hosts

# 每次执行都会创建用户（第二次会报错）
useradd appuser

# 没有检查就启动（可能已经运行）
systemctl start nginx
```

**幂等脚本（正确版本）**:

```bash
#!/bin/bash
# GOOD: 幂等脚本

# 检查后再追加
if ! grep -q 'myapp.local' /etc/hosts; then
    echo "127.0.0.1 myapp.local" >> /etc/hosts
fi

# 检查用户是否存在
if ! id appuser &>/dev/null; then
    useradd appuser
fi

# 使用幂等命令
systemctl enable nginx  # enable 是幂等的
systemctl start nginx   # start 对已运行的服务是安全的
```

### 检查清单

- [ ] 理解为什么 ASG 场景需要幂等脚本
- [ ] 掌握三种幂等技术：条件检查、grep 守卫、守卫文件
- [ ] 能将非幂等脚本改写为幂等版本

---

## 反模式演示

### 反模式 1：非幂等脚本

```bash
# 错误：每次启动都追加，/etc/hosts 会越来越长
echo "10.0.0.1 db.internal" >> /etc/hosts
echo "10.0.0.2 cache.internal" >> /etc/hosts
```

**后果**：重启多次后，/etc/hosts 充满重复条目。

**修复**：

```bash
# 使用 grep 检查
grep -q 'db.internal' /etc/hosts || echo "10.0.0.1 db.internal" >> /etc/hosts
```

### 反模式 2：交互式命令阻塞启动

```bash
# 错误：apt-get 可能提示确认
apt-get install nginx

# 错误：yum 在某些情况下也会提示
yum install httpd
```

**后果**：实例启动后卡在 cloud-init，看起来"沉默"，SSH 可能无法连接。

**修复**：

```bash
# Debian/Ubuntu
export DEBIAN_FRONTEND=noninteractive
apt-get install -y nginx

# RHEL/Amazon Linux
yum install -y nginx

# 或者使用 cloud-config 的 packages 模块（自动非交互）
```

### 反模式 3：过长启动脚本导致超时

```bash
# 错误：在 user-data 中编译软件
#!/bin/bash
yum install -y gcc make
wget https://example.com/large-source.tar.gz
tar xzf large-source.tar.gz
cd large-source
./configure && make && make install  # 可能需要 30+ 分钟
```

**后果**：
- ASG 健康检查超时
- 实例被标记为不健康并替换
- 无限循环

**修复**：将耗时操作移到 AMI 构建阶段（Bake vs Bootstrap）：

```
┌─────────────────────────────────────────────────────────────┐
│                  Bake vs Bootstrap 策略                      │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  Bake (烘焙到 AMI)          Bootstrap (启动时安装)           │
│  ┌─────────────────┐        ┌─────────────────┐            │
│  │ ● 操作系统        │        │ ● 配置文件        │            │
│  │ ● 依赖包          │        │ ● 环境变量        │            │
│  │ ● 编译好的软件    │        │ ● 密钥/证书       │            │
│  │ ● 基础配置        │        │ ● 动态参数        │            │
│  └─────────────────┘        └─────────────────┘            │
│         │                          │                        │
│         ▼                          ▼                        │
│    启动时间：30 秒             启动时间：5 分钟              │
│    ASG 友好 ✓                  可能超时 ✗                   │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

## 职场小贴士（Japan IT Context）

### 障害対応：启动失败的根因分析

在日本 IT 企业，当实例启动失败时，工程师需要提供**原因究明**（根因分析）报告：

```
┌─────────────────────────────────────────────────────────────┐
│              cloud-init 障害対応チェックリスト                │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  1. 初期確認 (Initial Check)                                │
│     □ EC2 インスタンス状態: Running?                         │
│     □ cloud-init status: done / error / running?           │
│     □ /run/cloud-init/result.json にエラーあり?            │
│                                                             │
│  2. ログ分析 (Log Analysis)                                  │
│     □ /var/log/cloud-init.log でエラー検索                  │
│     □ /var/log/cloud-init-output.log で出力確認             │
│     □ dmesg でカーネルエラー確認                            │
│                                                             │
│  3. user-data 確認                                          │
│     □ cloud-init query userdata で内容確認                  │
│     □ YAML 構文エラー?                                       │
│     □ 対話式コマンド (-y オプション忘れ)?                   │
│                                                             │
│  4. 報告書作成                                               │
│     □ 発生時刻                                               │
│     □ 影響範囲                                               │
│     □ 原因                                                   │
│     □ 対策                                                   │
│     □ 再発防止策                                             │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### 日本 IT 术语对照

| 日语术语 | 读音 | 含义 | cloud-init 相关 |
|----------|------|------|-----------------|
| 障害対応 | しょうがいたいおう | 故障处理 | 诊断 cloud-init 失败 |
| 原因究明 | げんいんきゅうめい | 根因分析 | 分析日志、user-data |
| 初期構築 | しょきこうちく | 初始配置 | user-data 设计 |
| 自動化 | じどうか | 自动化 | 幂等脚本 |
| 冪等性 | べきとうせい | 幂等性 | 可重复执行的脚本 |

### 变更管理：user-data 版本控制

日本企业通常要求**変更管理**（变更管理）：

```bash
# 在 user-data 中记录版本
#cloud-config

# 版本标识（便于审计）
# Version: 1.2.3
# Author: yamada@example.com
# Date: 2025-01-10
# Change: Added nginx configuration

write_files:
  - path: /etc/cloud-init-version
    content: |
      version: 1.2.3
      deployed: $(date -Iseconds)
```

---

## 检查清单

完成本课后，你应该能够：

- [ ] 解释 cloud-init 四个启动阶段的顺序和职责
- [ ] 区分 bootcmd 和 runcmd 的执行时机
- [ ] 编写 shell 脚本和 cloud-config YAML 两种 user-data
- [ ] 使用 `cloud-init status`、`cloud-init analyze show` 诊断问题
- [ ] 解读 `/var/log/cloud-init.log` 和 `/var/log/cloud-init-output.log`
- [ ] 编写幂等的初始化脚本
- [ ] 识别并修复常见的 cloud-init 反模式
- [ ] 解释 Bake vs Bootstrap 策略的权衡

---

## 本课小结

| 概念 | 要点 |
|------|------|
| 四阶段 | init-local → init → config → final |
| User-data 类型 | Shell 脚本、cloud-config YAML、Multi-part MIME |
| 关键模块 | bootcmd（每次）、runcmd（首次）、write_files、packages |
| 调试工具 | `cloud-init status`、`cloud-init analyze`、日志文件 |
| 幂等性 | 条件检查、grep 守卫、守卫文件 |
| Bake vs Bootstrap | 耗时操作放 AMI，配置放 user-data |

---

## 延伸阅读

- [cloud-init 官方文档](https://cloudinit.readthedocs.io/)
- [AWS EC2 User Data 最佳实践](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/user-data.html)
- 下一课：[03 - 元数据服务与 IMDSv2](../03-metadata/) - 学习安全访问实例元数据
- 相关课程：[LX05 - systemd 服务管理](../../systemd/) - 理解 cloud-init 如何与 systemd 集成

---

## 清理资源

实验完成后，记得清理创建的资源：

```bash
# 终止测试实例
aws ec2 terminate-instances --instance-ids i-xxxxxxxxx

# 确认实例已终止
aws ec2 describe-instances --instance-ids i-xxxxxxxxx \
  --query 'Reservations[].Instances[].State.Name'
```

> **费用提醒**：t3.micro 实例每小时约 $0.0104（us-east-1）。及时清理避免不必要的费用。  

---

## 系列导航

[← 01 - 云中 Linux 有何不同](../01-cloud-context/) | [系列首页](../) | [03 - 元数据服务与 IMDSv2 →](../03-metadata/)
