# 09 - Drop-in 与安全加固（Drop-ins and Security Hardening）

> **目标**：掌握 Drop-in 文件安全定制服务，使用 systemd-analyze security 进行安全审计  
> **前置**：已完成 [03 - Unit 文件解剖](../03-unit-files/) 和 [08 - 资源控制](../08-resource-control/)  
> **时间**：⚡ 20 分钟（速读）/ 🔬 75 分钟（完整实操）  
> **实战场景**：セキュリティ監査（Security Audit）- 使用标准 OS 工具进行安全加固  

---

## 将学到的内容

1. 使用 Drop-in 文件安全定制服务（不修改原始 Unit 文件）
2. 理解 override vs accumulate 指令的区别
3. 使用 systemd-analyze security 进行安全审计
4. 应用常见安全加固指令
5. 创建完全加固的服务模板

---

## 先跑起来！（5 分钟）

> 在学习理论之前，先对系统上的服务进行一次安全审计。  

```bash
# 查看系统所有服务的安全评分
systemd-analyze security

# 查看特定服务的详细安全评分
systemd-analyze security sshd.service

# 查看 nginx（如果安装了）
systemd-analyze security nginx.service 2>/dev/null || echo "nginx not installed"
```

**观察输出**：

```
UNIT                      EXPOSURE PREDICATE HAPPY
sshd.service                   9.6 UNSAFE
nginx.service                  9.2 UNSAFE
systemd-journald.service       4.4 OK
systemd-logind.service         2.6 OK
```

**你刚刚看到了每个服务的安全暴露评分！**

- **0-2 分**：安全配置优秀（绿色 OK）
- **2-5 分**：配置良好
- **5-8 分**：需要改进
- **8-10 分**：高度暴露（红色 UNSAFE）

大多数服务默认评分都很高（不安全）。本课将教你如何使用 Drop-in 文件将评分降低到安全水平。

---

## Step 1 -- Drop-in 文件基础（15 分钟）

### 1.1 为什么需要 Drop-in？

在 [03 - Unit 文件解剖](../03-unit-files/) 中，我们学到了不要直接修改 `/usr/lib/systemd/system/` 下的文件。

| 修改方式 | 问题 |
|----------|------|
| 直接编辑 /usr/lib/... | `yum update` 会覆盖你的修改！ |
| 复制到 /etc/... | 安全，但需要手动同步上游更新 |
| **Drop-in（推荐）** | 只覆盖需要的部分，保持与上游同步 |

### 1.2 Drop-in 目录结构

```bash
# 查看 nginx 服务的 Drop-in 目录
ls -la /etc/systemd/system/nginx.service.d/ 2>/dev/null || echo "No drop-ins yet"

# 查看 systemd 如何合并配置
systemctl cat nginx
```

![Drop-in Structure](images/drop-in-structure.png)

<details>
<summary>View ASCII source</summary>

```
Drop-in 文件结构

/etc/systemd/system/nginx.service.d/
├── 10-limits.conf        ← 资源限制配置
├── 20-hardening.conf     ← 安全加固配置
└── 30-logging.conf       ← 日志配置

加载顺序：按文件名字母序
  10-*.conf → 20-*.conf → 30-*.conf

命名规范：
  数字前缀 + 描述性名称 + .conf
  例：10-limits.conf, 20-security.conf

文件合并规则：
┌─────────────────────────────────────────────────────────────┐
│  /usr/lib/systemd/system/nginx.service     ← 原始文件      │
│            +                                                │
│  /etc/systemd/system/nginx.service.d/*.conf ← Drop-in 覆盖 │
│            =                                                │
│  最终配置（systemctl cat nginx 查看）                        │
└─────────────────────────────────────────────────────────────┘
```

</details>

### 1.3 创建 Drop-in 文件的两种方法

**方法 1：systemctl edit（推荐）**

```bash
# 自动创建 Drop-in 目录和文件
sudo systemctl edit nginx.service

# 这会打开编辑器，保存后自动：
# 1. 创建 /etc/systemd/system/nginx.service.d/override.conf
# 2. 执行 daemon-reload
```

**方法 2：手动创建**

```bash
# 创建 Drop-in 目录
sudo mkdir -p /etc/systemd/system/nginx.service.d/

# 创建配置文件
sudo vim /etc/systemd/system/nginx.service.d/20-hardening.conf

# 重新加载配置
sudo systemctl daemon-reload
```

### 1.4 查看 Drop-in 差异

```bash
# 查看所有 Unit 文件的差异（Drop-in 覆盖情况）
systemd-delta

# 只看扩展的文件
systemd-delta --type=extended

# 输出示例：
# [EXTENDED]   /usr/lib/systemd/system/nginx.service
#              → /etc/systemd/system/nginx.service.d/override.conf
```

---

## Step 2 -- Override vs Accumulate（10 分钟）

### 2.1 关键区别

并非所有指令的行为都相同！有些指令会**覆盖**，有些会**累加**。

![Override vs Accumulate](images/override-accumulate.png)

<details>
<summary>View ASCII source</summary>

```
Override vs Accumulate 指令行为

┌─────────────────────────────────────────────────────────────────┐
│                    Override（覆盖型）指令                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ExecStart= 特殊规则：必须先清空再设置！                          │
│                                                                  │
│  原始文件：                                                      │
│    [Service]                                                     │
│    ExecStart=/usr/sbin/nginx -g 'daemon off;'                   │
│                                                                  │
│  错误的 Drop-in：                                                │
│    [Service]                                                     │
│    ExecStart=/usr/sbin/nginx -c /custom/nginx.conf              │
│    # 结果：启动失败！两个 ExecStart 冲突                          │
│                                                                  │
│  正确的 Drop-in：                                                │
│    [Service]                                                     │
│    ExecStart=                      ← 先清空！                    │
│    ExecStart=/usr/sbin/nginx -c /custom/nginx.conf              │
│                                                                  │
├─────────────────────────────────────────────────────────────────┤
│                   Accumulate（累加型）指令                       │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  Environment= 会累加：                                           │
│                                                                  │
│  原始文件：                                                      │
│    [Service]                                                     │
│    Environment=FOO=bar                                           │
│                                                                  │
│  Drop-in：                                                       │
│    [Service]                                                     │
│    Environment=BAZ=qux                                           │
│                                                                  │
│  结果：FOO=bar BAZ=qux  ← 两个都生效！                           │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

</details>

### 2.2 指令行为速查表

| 指令类型 | 行为 | 清空语法 |
|----------|------|----------|
| `ExecStart=` | Override | `ExecStart=`（空值清空） |
| `ExecStartPre=` | Accumulate | `ExecStartPre=`（空值清空） |
| `ExecStartPost=` | Accumulate | `ExecStartPost=`（空值清空） |
| `Environment=` | Accumulate | 无法清空，使用 `UnsetEnvironment=` |
| `EnvironmentFile=` | Accumulate | 无法清空 |
| `User=`, `Group=` | Override | 直接覆盖 |
| `MemoryMax=`, `CPUQuota=` | Override | 直接覆盖 |

### 2.3 实战示例：修改 ExecStart

```bash
# 查看原始 nginx 配置
systemctl cat nginx | grep ExecStart

# 创建 Drop-in 修改启动命令
sudo systemctl edit nginx.service
```

在编辑器中输入：

```ini
[Service]
# 必须先清空原有的 ExecStart！
ExecStart=
ExecStart=/usr/sbin/nginx -c /etc/nginx/custom.conf -g 'daemon off;'
```

```bash
# 验证配置
systemctl cat nginx | grep ExecStart

# 应该看到：
# ExecStart=
# ExecStart=/usr/sbin/nginx -c /etc/nginx/custom.conf -g 'daemon off;'
```

---

## Step 3 -- Ghost Config 陷阱（重要！）（10 分钟）

### 3.1 什么是 Ghost Config？

**Ghost Config** 是最常见的 systemd 配置错误之一：

> 编辑 Unit 文件后直接 restart，不执行 daemon-reload。  
> 结果：服务运行的是**旧配置**，但文件显示的是**新配置**！  

![Ghost Config](images/ghost-config.png)

<details>
<summary>View ASCII source</summary>

```
Ghost Config（幽灵配置）陷阱

┌─────────────────────────────────────────────────────────────────┐
│                                                                  │
│   错误操作流程：                                                 │
│                                                                  │
│   1. vim /etc/systemd/system/myapp.service   ← 编辑配置         │
│   2. systemctl restart myapp                 ← 直接重启！       │
│                                                                  │
│   ┌─────────────────┐          ┌─────────────────┐              │
│   │   文件系统      │          │   systemd 内存  │              │
│   │  (新配置)       │    ≠     │   (旧配置)      │              │
│   └─────────────────┘          └─────────────────┘              │
│                                                                  │
│   后果：                                                         │
│   - cat 文件看到的是新配置                                       │
│   - systemctl show 看到的是旧配置                                │
│   - 服务运行的是旧配置！                                         │
│   - 调试时你会非常困惑...                                        │
│                                                                  │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│   正确操作流程：                                                 │
│                                                                  │
│   1. vim /etc/systemd/system/myapp.service   ← 编辑配置         │
│   2. systemctl daemon-reload                 ← 重新加载！       │
│   3. systemctl restart myapp                 ← 然后重启         │
│                                                                  │
│   或者使用 systemctl edit（自动 daemon-reload）                  │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

</details>

### 3.2 检测 Ghost Config

```bash
# 查看 systemd 内存中的配置
systemctl show nginx --property=ExecStart

# 对比文件中的配置
grep ExecStart /etc/systemd/system/nginx.service

# 如果两者不一致，说明有 Ghost Config！
```

### 3.3 正确的配置修改流程

```bash
# 方法 1：使用 systemctl edit（自动 daemon-reload）
sudo systemctl edit nginx.service
# 编辑 → 保存 → 自动执行 daemon-reload

# 方法 2：手动编辑
sudo vim /etc/systemd/system/nginx.service.d/override.conf
sudo systemctl daemon-reload   # 不要忘记！
sudo systemctl restart nginx
```

### 3.4 配置验证最佳实践

```bash
# 对于服务配置，先验证再重载
nginx -t && sudo systemctl reload nginx

# 对于 SSH，先验证再重启
sudo sshd -t && sudo systemctl restart sshd

# 对于 Unit 文件，使用 systemd-analyze verify
sudo systemd-analyze verify /etc/systemd/system/myapp.service
```

---

## Step 4 -- systemd-analyze security 详解（15 分钟）

### 4.1 全面安全审计

```bash
# 查看所有服务的安全评分
systemd-analyze security

# 按暴露程度排序（最不安全的在前）
systemd-analyze security --no-pager | sort -t $'\t' -k2 -rn | head -20
```

### 4.2 单服务详细审计

```bash
# 查看 nginx 的详细安全评分
systemd-analyze security nginx.service
```

**输出示例**（摘录）：

```
  NAME                            DESCRIPTION                           EXPOSURE
✓ PrivateNetwork=                 Service has access to the host's n...    0.5
✗ User=/DynamicUser=              Service runs as root                     0.4
✓ CapabilityBoundingSet=~...      Service may be able to acquire cap...    0.3
✗ NoNewPrivileges=                Service processes may acquire new ...    0.2
✗ ProtectHome=                    Service has full access to home di...    0.2
✗ PrivateTmp=                     Service has access to other users'...    0.1
...

→ Overall exposure level for nginx.service: 9.2 UNSAFE
```

### 4.3 评分解读

| 分数范围 | 评级 | 含义 |
|----------|------|------|
| 0.0 - 2.0 | SAFE | 配置优秀，符合最佳实践 |
| 2.0 - 5.0 | OK | 配置良好，可接受 |
| 5.0 - 8.0 | MEDIUM | 需要改进 |
| 8.0 - 10.0 | UNSAFE | 高度暴露，建议加固 |

### 4.4 每项检查的含义

| 检查项 | 说明 | 降分方法 |
|--------|------|----------|
| `User=/DynamicUser=` | 以 root 运行 | 设置 `User=` 或 `DynamicUser=yes` |
| `NoNewPrivileges=` | 可获取新权限 | 设置 `NoNewPrivileges=yes` |
| `PrivateTmp=` | 共享 /tmp | 设置 `PrivateTmp=yes` |
| `ProtectHome=` | 可访问 /home | 设置 `ProtectHome=yes` |
| `ProtectSystem=` | 可写系统目录 | 设置 `ProtectSystem=strict` |
| `RestrictAddressFamilies=` | 无网络限制 | 限制允许的协议族 |
| `SystemCallFilter=` | 无系统调用限制 | 使用 `@system-service` 过滤 |

---

## Step 5 -- 核心安全加固指令（15 分钟）

### 5.1 入门级加固（影响小，收益高）

这些指令对大多数服务都安全，建议首先应用：

```ini
[Service]
# 1. 禁止获取新权限（最重要！）
NoNewPrivileges=yes

# 2. 私有 /tmp 目录
PrivateTmp=yes

# 3. 保护 /home 目录
ProtectHome=yes

# 4. 限制 SUID/SGID
RestrictSUIDSGID=yes
```

### 5.2 中级加固（推荐）

```ini
[Service]
# 文件系统保护
ProtectSystem=strict           # /usr, /boot, /etc 只读
ReadWritePaths=/var/lib/myapp  # 允许写入的目录（例外）
ProtectHome=yes                # /home, /root 不可访问

# 内核保护
ProtectKernelTunables=yes      # 禁止修改 /proc/sys
ProtectKernelModules=yes       # 禁止加载内核模块
ProtectControlGroups=yes       # 禁止修改 cgroup
```

### 5.3 高级加固（完整模板）

```ini
[Service]
# ==========================================
# 运行身份
# ==========================================
User=appuser
Group=appgroup
# DynamicUser=yes  # 替代方案：临时用户

# ==========================================
# 文件系统保护
# ==========================================
ProtectSystem=strict           # /usr, /boot, /etc 只读
ProtectHome=yes                # /home, /root 不可访问
PrivateTmp=yes                 # 私有 /tmp
ReadWritePaths=/var/lib/myapp  # 例外：允许写入

# ==========================================
# 内核保护
# ==========================================
ProtectKernelTunables=yes
ProtectKernelModules=yes
ProtectControlGroups=yes

# ==========================================
# 权限限制
# ==========================================
NoNewPrivileges=yes
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
RestrictSUIDSGID=yes

# ==========================================
# 网络隔离（如需要）
# ==========================================
RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX

# ==========================================
# 系统调用过滤
# ==========================================
SystemCallFilter=@system-service
SystemCallArchitectures=native
```

### 5.4 各指令详解

| 指令 | 作用 | 何时使用 |
|------|------|----------|
| `ProtectSystem=strict` | /usr, /boot, /etc 只读 | 几乎所有服务 |
| `ProtectSystem=full` | 只有 /etc 只读 | 需要写 /usr 的服务 |
| `ProtectHome=yes` | 无法访问 /home, /root | 不需要用户数据的服务 |
| `ProtectHome=read-only` | 只读访问 /home | 需要读取用户数据的服务 |
| `PrivateTmp=yes` | 独立的 /tmp | 几乎所有服务 |
| `NoNewPrivileges=yes` | 禁止 setuid 等 | 几乎所有服务 |
| `DynamicUser=yes` | 临时用户/组 | 无状态服务（容器化风格） |
| `MemoryDenyWriteExecute=yes` | 禁止 W+X 内存 | 非 JIT 编译的服务 |

---

## Step 6 -- 动手实验：安全加固审计（20 分钟）

> **场景**：对 nginx 服务进行安全加固，将评分从 9+ 降到 5 以下。  

### 6.1 确认初始评分

```bash
# 安装 nginx（如未安装）
sudo dnf install -y nginx   # RHEL/Rocky
# sudo apt install -y nginx # Ubuntu

# 查看初始安全评分
systemd-analyze security nginx.service
```

记录初始分数：`9.2 UNSAFE`

### 6.2 创建加固 Drop-in

```bash
# 使用 systemctl edit 创建 Drop-in
sudo systemctl edit nginx.service
```

输入以下内容：

```ini
[Service]
# ==========================================
# 安全加固配置 - nginx
# 目标：将安全评分从 9+ 降到 5 以下
# ==========================================

# 权限限制
NoNewPrivileges=yes
RestrictSUIDSGID=yes

# 文件系统保护
ProtectSystem=full
ProtectHome=yes
PrivateTmp=yes
PrivateDevices=yes

# 内核保护
ProtectKernelTunables=yes
ProtectKernelModules=yes
ProtectKernelLogs=yes
ProtectControlGroups=yes

# 系统调用过滤
SystemCallArchitectures=native
SystemCallFilter=@system-service
SystemCallFilter=~@privileged @resources

# 网络限制
RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX

# 其他
LockPersonality=yes
RestrictRealtime=yes
RestrictNamespaces=yes
```

### 6.3 验证配置

```bash
# 验证 Unit 文件语法
sudo systemd-analyze verify /etc/systemd/system/nginx.service.d/override.conf

# 测试 nginx 配置
sudo nginx -t

# 重启服务
sudo systemctl restart nginx

# 确认服务正常运行
systemctl status nginx
curl -I http://localhost
```

### 6.4 检查新评分

```bash
# 查看新的安全评分
systemd-analyze security nginx.service
```

**预期结果**：评分从 `9.2 UNSAFE` 降到 `4.x OK` 左右。

### 6.5 渐进式调试

如果服务无法启动，采用渐进式方法：

```bash
# 1. 先只添加基础加固
[Service]
NoNewPrivileges=yes
PrivateTmp=yes
ProtectHome=yes

# 2. 测试服务是否正常
sudo systemctl restart nginx && curl -I http://localhost

# 3. 逐步添加更多指令，每次测试
# 4. 如果某个指令导致问题，暂时注释掉
```

### 6.6 查看 Drop-in 文件

```bash
# 查看创建的 Drop-in
cat /etc/systemd/system/nginx.service.d/override.conf

# 查看完整合并后的配置
systemctl cat nginx

# 查看 systemd-delta 显示的差异
systemd-delta --type=extended | grep nginx
```

---

## 反模式：常见错误

### 错误 1：直接编辑 /usr/lib/systemd/system/

```bash
# 错误：直接编辑包管理器安装的文件
sudo vim /usr/lib/systemd/system/nginx.service

# 问题：yum/apt update 会覆盖你的修改！

# 正确：使用 Drop-in
sudo systemctl edit nginx.service
```

### 错误 2：忘记 daemon-reload（Ghost Config）

```bash
# 错误：修改文件后直接重启
sudo vim /etc/systemd/system/myapp.service
sudo systemctl restart myapp
# 服务运行的仍然是旧配置！

# 正确：先 daemon-reload
sudo vim /etc/systemd/system/myapp.service
sudo systemctl daemon-reload
sudo systemctl restart myapp
```

### 错误 3：过度加固导致服务无法运行

```ini
# 错误：一次性添加所有加固指令
[Service]
PrivateNetwork=yes      # nginx 需要网络！
ProtectSystem=strict    # nginx 需要写 /var/log/nginx！
```

```ini
# 正确：渐进式添加，并设置例外
[Service]
ProtectSystem=strict
ReadWritePaths=/var/log/nginx /var/cache/nginx
# PrivateNetwork=no  # 保持默认，nginx 需要网络
```

### 错误 4：ExecStart 不清空就覆盖

```ini
# 错误：直接覆盖（会导致启动失败）
[Service]
ExecStart=/usr/sbin/nginx -c /custom/nginx.conf

# 正确：先清空再设置
[Service]
ExecStart=
ExecStart=/usr/sbin/nginx -c /custom/nginx.conf
```

### 错误 5：配置验证遗漏

```bash
# 错误：不验证就重载
sudo systemctl reload nginx

# 正确：先验证配置
nginx -t && sudo systemctl reload nginx

# 对于 sshd
sshd -t && sudo systemctl restart sshd

# 对于 Unit 文件
systemd-analyze verify /etc/systemd/system/myapp.service
```

---

## 完整加固模板

### Web 应用服务模板

```ini
[Service]
# ==========================================
# 运行身份
# ==========================================
User=appuser
Group=appgroup
# DynamicUser=yes  # 替代方案：临时用户

# ==========================================
# 文件系统保护
# ==========================================
ProtectSystem=strict           # /usr, /boot, /etc 只读
ProtectHome=yes                # /home, /root 不可访问
PrivateTmp=yes                 # 私有 /tmp
ReadWritePaths=/var/lib/myapp  # 例外：允许写入

# ==========================================
# 内核保护
# ==========================================
ProtectKernelTunables=yes
ProtectKernelModules=yes
ProtectControlGroups=yes

# ==========================================
# 权限限制
# ==========================================
NoNewPrivileges=yes
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
RestrictSUIDSGID=yes

# ==========================================
# 网络隔离（如需要）
# ==========================================
RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX

# ==========================================
# 系统调用过滤
# ==========================================
SystemCallFilter=@system-service
SystemCallArchitectures=native
```

### 批处理任务模板

```ini
[Service]
# ==========================================
# 运行身份
# ==========================================
User=batchuser
Group=batchuser

# ==========================================
# 文件系统保护（更严格）
# ==========================================
ProtectSystem=strict
ProtectHome=yes
PrivateTmp=yes
PrivateDevices=yes
ReadWritePaths=/var/lib/batch /var/log/batch

# ==========================================
# 全面加固
# ==========================================
NoNewPrivileges=yes
ProtectKernelTunables=yes
ProtectKernelModules=yes
ProtectControlGroups=yes

# ==========================================
# 网络隔离（批处理通常不需要网络）
# ==========================================
PrivateNetwork=yes
# 或者限制为本地：RestrictAddressFamilies=AF_UNIX

# ==========================================
# 系统调用过滤
# ==========================================
SystemCallFilter=@system-service
SystemCallArchitectures=native
MemoryDenyWriteExecute=yes
```

---

## 职场小贴士（Japan IT Context）

### セキュリティ監査（Security Audit）

在日本 IT 企业，安全监查是常规工作。`systemd-analyze security` 是快速评估服务安全性的标准工具。

| 日语术语 | 含义 | 典型场景 |
|----------|------|----------|
| セキュリティ監査 | Security Audit | 定期或项目上线前的安全评估 |
| 脆弱性対応 | Vulnerability Response | 发现问题后的加固措施 |
| 変更管理 | Change Management | 使用 Drop-in 安全修改配置 |
| 権限最小化 | Principle of Least Privilege | NoNewPrivileges, User= 等配置 |

### 变更管理文档

日本企业通常要求配置变更有详细文档：

```markdown
# nginx セキュリティ加固 手順書

## 変更概要
- 対象: nginx.service
- 目的: セキュリティ評価を 9.2 から 5.0 以下に改善
- 方法: Drop-in ファイルによる設定追加

## 事前確認
1. systemd-analyze security nginx.service で現状確認
2. nginx -t で設定検証

## 変更手順
1. sudo systemctl edit nginx.service
2. 加固設定を追加（別紙参照）
3. nginx -t && sudo systemctl restart nginx
4. systemd-analyze security nginx.service で改善確認

## 切り戻し手順
1. sudo rm /etc/systemd/system/nginx.service.d/override.conf
2. sudo systemctl daemon-reload
3. sudo systemctl restart nginx
```

---

## 检查清单

完成本课后，你应该能够：

- [ ] 解释为什么使用 Drop-in 而不是直接修改 Unit 文件
- [ ] 使用 `systemctl edit` 创建 Drop-in 文件
- [ ] 使用 `systemd-delta` 查看配置差异
- [ ] 区分 Override 和 Accumulate 指令的行为
- [ ] 正确覆盖 ExecStart=（先清空再设置）
- [ ] 避免 Ghost Config 陷阱（记住 daemon-reload）
- [ ] 使用 `systemd-analyze security` 审计服务安全性
- [ ] 解读安全评分（0-2 优秀，8-10 危险）
- [ ] 应用基础加固指令：NoNewPrivileges, PrivateTmp, ProtectHome
- [ ] 应用中级加固指令：ProtectSystem, ProtectKernel*
- [ ] 渐进式测试加固配置，避免过度加固
- [ ] 在加固时设置必要的例外（如 ReadWritePaths）

---

## 本课小结

| 概念 | 要点 | 记忆点 |
|------|------|--------|
| Drop-in 目录 | /etc/systemd/system/xxx.service.d/ | 按字母序加载 |
| systemctl edit | 创建 Drop-in 并自动 daemon-reload | 推荐方式 |
| Override | ExecStart= 需要先清空 | `ExecStart=` + `ExecStart=/new/cmd` |
| Accumulate | Environment= 会累加 | 无需清空 |
| Ghost Config | 改文件不 reload | 先 daemon-reload 再 restart |
| 安全审计 | systemd-analyze security | 0-2 安全，8-10 危险 |
| 入门加固 | NoNewPrivileges, PrivateTmp | 影响小，收益高 |
| 中级加固 | ProtectSystem, ProtectHome | 需要设置例外 |
| 渐进式加固 | 逐步添加，每次测试 | 避免过度加固 |

---

## 面试准备

### Q: systemd のハードニングで最初に設定すべきは？

**A**: `NoNewPrivileges=yes` と `PrivateTmp=yes` です。この二つは影響が少なく効果が高いため、最初に設定すべきです。`NoNewPrivileges` はプロセスが setuid/setgid で権限昇格することを防ぎ、`PrivateTmp` は他のプロセスの /tmp を見えなくします。

### Q: ベンダーの Unit ファイルをカスタマイズする正しい方法は？

**A**: `systemctl edit nginx.service` で drop-in ファイルを作成します。`/usr/lib/systemd/system/` を直接編集すると、`yum update` や `apt upgrade` で上書きされてしまいます。drop-in は `/etc/systemd/system/nginx.service.d/override.conf` に保存され、パッケージ更新後も保持されます。

### Q: systemd-analyze security の評価スコアの意味は？

**A**: 0-2 は優秀（セキュリティ設定が適切）、2-5 は良好、5-8 は改善が必要、8-10 は危険です。多くのサービスはデフォルトで 8-10 になるため、drop-in で加固設定を追加して 5 以下を目指すのが推奨です。

### Q: Unit ファイルを編集後、サービスが古い設定で動いている。原因は？

**A**: `systemctl daemon-reload` を実行していないためです。これは Ghost Config と呼ばれる問題で、ファイルは新しい設定を表示しますが、systemd のメモリには古い設定が残っています。正しい手順は：編集 → daemon-reload → restart です。`systemctl edit` を使えば自動的に daemon-reload されます。

---

## 延伸阅读

- [systemd.exec(5) man page](https://www.freedesktop.org/software/systemd/man/systemd.exec.html) -- 安全加固指令详解
- [systemd-analyze(1) man page](https://www.freedesktop.org/software/systemd/man/systemd-analyze.html) -- security 命令详解
- 前置课程：[03 - Unit 文件解剖](../03-unit-files/) -- Unit 文件基础结构
- 前置课程：[08 - 资源控制](../08-resource-control/) -- cgroup 资源限制
- 下一课：[10 - 综合项目](../10-capstone/) -- 创建生产级服务配置

---

## 系列导航

[08 - 资源控制 <--](../08-resource-control/) | [系列首页](../) | [--> 10 - 综合项目](../10-capstone/)
