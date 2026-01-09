# 03 - Unit 文件解剖（Unit File Anatomy）

> **目标**：掌握 systemd Unit 文件的结构，学会为应用创建自定义服务  
> **前置**：已完成 [02 - systemctl 实战](../02-systemctl/)  
> **时间**：60-90 分钟  
> **实战场景**：为新应用创建 systemd 服务（アプリケーションのサービス化）  

---

## 将学到的内容

1. 理解 Unit 文件的三段结构（[Unit], [Service], [Install]）
2. 区分 Type=simple/forking/oneshot/notify 的使用场景
3. 正确使用 ExecStart, ExecStartPre, ExecStop
4. 配置重启策略（Restart, RestartSec, StartLimitIntervalSec）
5. 安全处理环境变量和密钥

---

## 先跑起来！（5 分钟）

> 在学习理论之前，先看一个真实的 Unit 文件长什么样。  

```bash
# 查看 sshd 服务的 Unit 文件
systemctl cat sshd

# 查看 Unit 文件的三段结构
systemctl cat sshd | grep -E '^\[|^#'
```

**观察输出中的三个段落**：

```ini
[Unit]
Description=OpenSSH server daemon
...

[Service]
Type=notify
ExecStart=/usr/sbin/sshd -D $OPTIONS
...

[Install]
WantedBy=multi-user.target
```

**你刚刚看到了一个生产级 Unit 文件的结构！**

每个 systemd 服务都由这样的 Unit 文件定义。现在让我们深入理解每个部分。

---

## Step 1 -- Unit 文件的位置与优先级（10 分钟）

### 1.1 三个目录，三种用途

```bash
# 查看 Unit 文件的搜索路径
systemctl show --property=UnitPath
```

![Unit File Locations](images/unit-file-locations.png)

<details>
<summary>View ASCII source</summary>

```
┌─────────────────────────────────────────────────────────────────────┐
│                    Unit 文件位置（优先级从高到低）                    │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  1. /etc/systemd/system/              ← 管理员自定义（最高优先级）   │
│     └── 你创建的服务、Drop-in 覆盖                                   │
│                                                                      │
│  2. /run/systemd/system/              ← 运行时生成（重启后消失）     │
│     └── 系统启动时动态生成                                           │
│                                                                      │
│  3. /usr/lib/systemd/system/          ← 软件包安装（勿直接修改！）   │
│     └── yum/apt 安装的服务文件                                       │
│                                                                      │
├─────────────────────────────────────────────────────────────────────┤
│  规则：高优先级目录的同名文件会覆盖低优先级目录                       │
│  建议：永远不要直接编辑 /usr/lib/...，使用 Drop-in 或复制到 /etc/   │
└─────────────────────────────────────────────────────────────────────┘
```

</details>

### 1.2 查看文件实际位置

```bash
# 查看 nginx 服务的文件位置
systemctl show nginx --property=FragmentPath

# 查看所有相关文件（包括 Drop-in）
systemctl cat nginx
```

### 1.3 为什么不直接修改 /usr/lib/...

| 修改方式 | 后果 |
|----------|------|
| 直接编辑 /usr/lib/systemd/system/nginx.service | 下次 `yum update nginx` 会覆盖你的修改！ |
| 复制到 /etc/systemd/system/ | 安全，但需要手动同步上游更新 |
| 使用 Drop-in（推荐） | 只覆盖需要的部分，保持与上游同步 |

> **最佳实践**：使用 `systemctl edit nginx` 创建 Drop-in 文件（第 09 课会详细讲解）。  

---

## Step 2 -- Unit 文件的三段结构（15 分钟）

### 2.1 结构概览

![Unit File Structure](images/unit-file-structure.png)

<details>
<summary>View ASCII source</summary>

```
┌─────────────────────────────────────────────────────────────────────┐
│                        myapp.service                                 │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  [Unit]                         ← 元信息和依赖关系                   │
│  Description=My Application                                          │
│  Documentation=https://docs.example.com                              │
│  After=network-online.target    ← 启动顺序                           │
│  Wants=network-online.target    ← 依赖关系                           │
│                                                                      │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  [Service]                      ← 服务如何运行                       │
│  Type=notify                                                         │
│  User=appuser                                                        │
│  ExecStart=/opt/myapp/bin/server                                     │
│  Restart=on-failure                                                  │
│  RestartSec=5                                                        │
│                                                                      │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  [Install]                      ← 如何启用服务                       │
│  WantedBy=multi-user.target     ← enable 时创建软链接到这个 target   │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

</details>

### 2.2 [Unit] 段详解

```ini
[Unit]
# 基本信息
Description=My Application Service          # 服务描述，显示在 status 中
Documentation=https://docs.example.com      # 文档链接
Documentation=man:myapp(8)                  # 可以有多个

# 启动顺序（Ordering）- 只控制顺序，不拉入依赖！
After=network-online.target                 # 在网络就绪后启动
After=postgresql.service                    # 在数据库后启动
Before=nginx.service                        # 在 nginx 前启动

# 依赖关系（Requirements）- 拉入依赖！
Wants=network-online.target                 # 弱依赖：失败也继续
Requires=postgresql.service                 # 强依赖：失败则自己也失败

# 冲突
Conflicts=shutdown.target                   # 关机时停止
```

> **重要**：`After=` 只控制顺序，不会自动拉入依赖！  
> 必须同时使用 `Wants=` 或 `Requires=` 才能确保依赖服务被启动。  
> 详见 [04 - 依赖与排序](../04-dependencies/)。  

### 2.3 [Service] 段详解

```ini
[Service]
# 服务类型
Type=notify                                 # 详见下一节

# 运行身份
User=appuser                                # 以指定用户运行
Group=appgroup                              # 以指定组运行
WorkingDirectory=/opt/myapp                 # 工作目录

# 环境变量
Environment=NODE_ENV=production             # 单个变量
EnvironmentFile=/etc/myapp/env              # 从文件加载（推荐用于敏感数据）

# 启动命令
ExecStartPre=/opt/myapp/bin/check-config    # 启动前检查
ExecStart=/opt/myapp/bin/server             # 主启动命令
ExecStartPost=/opt/myapp/bin/notify-ready   # 启动后执行
ExecReload=/bin/kill -HUP $MAINPID          # reload 命令
ExecStop=/opt/myapp/bin/graceful-stop       # 停止命令

# 重启策略
Restart=on-failure                          # 失败时重启
RestartSec=5                                # 重启前等待 5 秒
StartLimitIntervalSec=300                   # 5 分钟内
StartLimitBurst=5                           # 最多重启 5 次
```

### 2.4 [Install] 段详解

```ini
[Install]
# enable 时的目标
WantedBy=multi-user.target                  # 多用户模式自启动（最常用）
# WantedBy=graphical.target                 # 图形界面自启动

# 其他选项
RequiredBy=myapp.target                     # 必需依赖（较少用）
Also=myapp-helper.service                   # 同时 enable 另一个服务
Alias=app.service                           # 创建别名
```

**WantedBy 的工作原理**：

```bash
# enable 时发生了什么？
systemctl enable myapp.service

# 实际上是创建了软链接：
# /etc/systemd/system/multi-user.target.wants/myapp.service
#    -> /etc/systemd/system/myapp.service
```

---

## Step 3 -- Type 类型详解（15 分钟）

### 3.1 五种主要类型

| Type | 说明 | 适用场景 |
|------|------|----------|
| `simple` | ExecStart 进程就是主进程（默认） | 大多数现代应用 |
| `forking` | ExecStart fork 后父进程退出 | 传统 daemon（如旧版 nginx） |
| `oneshot` | 短期任务，执行完就结束 | 初始化脚本、一次性任务 |
| `notify` | 服务通过 sd_notify 报告就绪 | 支持 systemd 通知的应用 |
| `dbus` | 通过 D-Bus 名称报告就绪 | D-Bus 服务 |

### 3.2 Type=simple（默认）

```ini
[Service]
Type=simple
ExecStart=/opt/myapp/bin/server
```

![Type=simple](images/type-simple.png)

<details>
<summary>View ASCII source</summary>

```
Type=simple（默认）

┌─────────────────────────────────────────────────────────────────┐
│                                                                  │
│   systemctl start myapp                                          │
│           │                                                      │
│           ▼                                                      │
│   ┌───────────────┐                                              │
│   │  ExecStart    │ ◄─── systemd 认为这个进程就是主进程          │
│   │  /opt/.../    │      进程启动 = 服务就绪                     │
│   │   server      │                                              │
│   └───────────────┘                                              │
│                                                                  │
│   适用：Node.js, Python Flask, Go 应用等前台运行的程序           │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

</details>

**适用场景**：
- Node.js / Python / Go 应用
- 任何不 fork 的前台进程

### 3.3 Type=forking

```ini
[Service]
Type=forking
PIDFile=/var/run/myapp.pid
ExecStart=/opt/myapp/bin/server --daemon
```

![Type=forking](images/type-forking.png)

<details>
<summary>View ASCII source</summary>

```
Type=forking（传统 daemon）

┌─────────────────────────────────────────────────────────────────┐
│                                                                  │
│   systemctl start myapp                                          │
│           │                                                      │
│           ▼                                                      │
│   ┌───────────────┐                                              │
│   │  ExecStart    │                                              │
│   │  父进程       │ ──► fork() ──► 子进程（真正的服务）          │
│   │  (立即退出)   │              ▲                               │
│   └───────────────┘              │                               │
│                                  │                               │
│           父进程退出 = 服务就绪 ─┘                               │
│                                                                  │
│   必须配置 PIDFile= 让 systemd 知道子进程 PID                    │
│                                                                  │
│   适用：旧版 Apache, 旧版 MySQL, 其他传统 daemon                 │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

</details>

> **注意**：现代应用很少使用 forking 模式。如果应用支持前台运行，优先使用 `Type=simple` 或 `Type=notify`。  

### 3.4 Type=oneshot

```ini
[Service]
Type=oneshot
ExecStart=/opt/scripts/init-database.sh
RemainAfterExit=yes    # 执行完后状态仍显示 active
```

**适用场景**：
- 系统初始化脚本
- 一次性配置任务
- 数据库迁移

### 3.5 Type=notify

```ini
[Service]
Type=notify
ExecStart=/opt/myapp/bin/server
NotifyAccess=main
```

![Type=notify](images/type-notify.png)

<details>
<summary>View ASCII source</summary>

```
Type=notify（推荐用于支持的应用）

┌─────────────────────────────────────────────────────────────────┐
│                                                                  │
│   systemctl start myapp                                          │
│           │                                                      │
│           ▼                                                      │
│   ┌───────────────┐                                              │
│   │  ExecStart    │                                              │
│   │               │ ─── 初始化中... ───┐                         │
│   │               │                    │                         │
│   │               │ ◄── sd_notify ─────┤                         │
│   │               │    "READY=1"       │                         │
│   │               │                    │                         │
│   └───────────────┘                    │                         │
│                                        ▼                         │
│                              systemd 收到通知：服务就绪！        │
│                                                                  │
│   优势：真正知道服务何时准备好接收请求                           │
│                                                                  │
│   支持的应用：nginx (1.15+), PostgreSQL, systemd-aware apps     │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

</details>

**支持 sd_notify 的常见应用**：
- nginx 1.15+
- PostgreSQL
- MariaDB
- Docker
- 任何使用 libsystemd 的应用

---

## Step 4 -- 重启策略配置（10 分钟）

### 4.1 Restart 选项

| 选项 | 说明 | 推荐场景 |
|------|------|----------|
| `no` | 不自动重启（默认） | 一次性任务 |
| `on-failure` | 仅失败时重启（推荐） | 生产服务 |
| `on-abnormal` | 异常信号或超时时重启 | 特殊场景 |
| `on-abort` | 仅异常信号时重启 | 调试场景 |
| `always` | 总是重启 | 必须持续运行的服务 |

### 4.2 重启控制参数

```ini
[Service]
# 重启策略
Restart=on-failure                    # 失败时重启
RestartSec=5                          # 重启前等待 5 秒（避免快速循环）

# 重启限制（防止重启风暴）
StartLimitIntervalSec=300             # 5 分钟窗口期
StartLimitBurst=5                     # 窗口期内最多重启 5 次
# 超过限制后，服务进入 failed 状态，需要手动 reset-failed
```

### 4.3 退出状态判断

```ini
[Service]
# 哪些退出码算成功
SuccessExitStatus=0 1 SIGTERM         # 退出码 0、1 或 SIGTERM 都算成功

# 哪些退出码触发重启
RestartPreventExitStatus=255          # 退出码 255 不重启（表示配置错误）
RestartForceExitStatus=1              # 退出码 1 强制重启（即使 Restart=no）
```

---

## Step 5 -- 环境变量与密钥安全（10 分钟）

### 5.1 两种设置方式

| 方式 | 适用场景 | 安全性 |
|------|----------|--------|
| `Environment=` | 非敏感配置 | 可被 `systemctl show` 看到！ |
| `EnvironmentFile=` | 敏感数据 | 文件权限 0600 保护 |

### 5.2 Environment= 的问题

```ini
# 反模式：密钥直接写在 Unit 文件
[Service]
Environment=DATABASE_URL=postgres://user:password@localhost/db
Environment=API_KEY=sk-1234567890abcdef
```

**问题**：任何人都能看到！

```bash
# 任何用户都能执行这个命令看到密钥
systemctl show myapp --property=Environment
# Environment=DATABASE_URL=postgres://user:password@localhost/db API_KEY=sk-1234567890abcdef
```

### 5.3 EnvironmentFile=（推荐）

```ini
# 正确方式：使用环境文件
[Service]
EnvironmentFile=/etc/myapp/secrets
```

创建密钥文件：

```bash
# 创建文件
sudo touch /etc/myapp/secrets

# 设置严格权限（只有 root 可读）
sudo chmod 0600 /etc/myapp/secrets

# 编辑内容
sudo vim /etc/myapp/secrets
```

文件内容：

```bash
# /etc/myapp/secrets
DATABASE_URL=postgres://user:password@localhost/db
API_KEY=sk-1234567890abcdef
NODE_ENV=production
```

### 5.4 systemd 250+ 的 LoadCredential（高级）

```ini
# systemd 250+ 支持更安全的凭证注入
[Service]
LoadCredential=db-password:/etc/myapp/db-password

# 服务运行时，凭证在 /run/credentials/myapp.service/db-password
# 应用代码读取这个文件获取密码
```

> **适用版本**：systemd 250+（RHEL 9, Ubuntu 22.04+）  

---

## Step 6 -- 动手实验：创建自定义服务（20 分钟）

> **场景**：为一个简单的 Python HTTP 服务器创建 systemd Unit 文件。  

### 6.1 创建应用目录和脚本

```bash
# 创建应用目录
sudo mkdir -p /opt/mywebapp
sudo mkdir -p /var/log/mywebapp

# 创建简单的 Python HTTP 服务器脚本
sudo tee /opt/mywebapp/server.py << 'EOF'
#!/usr/bin/env python3
"""Simple HTTP server for systemd demo."""

import http.server
import socketserver
import os
import signal
import sys

PORT = int(os.environ.get('PORT', 8080))
BIND = os.environ.get('BIND', '0.0.0.0')

class Handler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header('Content-type', 'text/plain')
        self.end_headers()
        message = f"Hello from mywebapp! PORT={PORT}\n"
        self.wfile.write(message.encode())

def graceful_shutdown(signum, frame):
    print("Received shutdown signal, exiting...")
    sys.exit(0)

signal.signal(signal.SIGTERM, graceful_shutdown)

print(f"Starting server on {BIND}:{PORT}")
with socketserver.TCPServer((BIND, PORT), Handler) as httpd:
    httpd.serve_forever()
EOF

# 设置执行权限
sudo chmod +x /opt/mywebapp/server.py
```

### 6.2 创建服务用户

```bash
# 创建专用服务用户（无 home 目录，无登录 shell）
sudo useradd -r -s /sbin/nologin mywebapp

# 设置目录权限
sudo chown -R mywebapp:mywebapp /opt/mywebapp
sudo chown -R mywebapp:mywebapp /var/log/mywebapp
```

### 6.3 创建环境配置文件

```bash
# 创建配置目录
sudo mkdir -p /etc/mywebapp

# 创建环境文件
sudo tee /etc/mywebapp/env << 'EOF'
# mywebapp environment configuration
PORT=8080
BIND=0.0.0.0
EOF

# 设置权限
sudo chmod 0640 /etc/mywebapp/env
sudo chown root:mywebapp /etc/mywebapp/env
```

### 6.4 创建 Unit 文件

```bash
sudo tee /etc/systemd/system/mywebapp.service << 'EOF'
[Unit]
Description=My Web Application
Documentation=https://example.com/docs
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=mywebapp
Group=mywebapp
WorkingDirectory=/opt/mywebapp

# 环境变量（从文件加载）
EnvironmentFile=/etc/mywebapp/env

# 启动命令
ExecStart=/usr/bin/python3 /opt/mywebapp/server.py

# 重启策略
Restart=on-failure
RestartSec=5
StartLimitIntervalSec=300
StartLimitBurst=5

# 日志输出到 journal
StandardOutput=journal
StandardError=journal
SyslogIdentifier=mywebapp

[Install]
WantedBy=multi-user.target
EOF
```

### 6.5 启用并启动服务

```bash
# 重新加载 systemd 配置
sudo systemctl daemon-reload

# 启用服务（开机自启）
sudo systemctl enable mywebapp

# 启动服务
sudo systemctl start mywebapp

# 检查状态
sudo systemctl status mywebapp
```

### 6.6 验证服务

```bash
# 测试 HTTP 响应
curl http://localhost:8080

# 查看日志
sudo journalctl -u mywebapp -f

# 查看服务详情
systemctl show mywebapp --property=Type,User,MainPID,Restart
```

### 6.7 测试重启策略

```bash
# 获取主进程 PID
MAIN_PID=$(systemctl show mywebapp --property=MainPID --value)
echo "Main PID: $MAIN_PID"

# 模拟进程崩溃
sudo kill -9 $MAIN_PID

# 等待几秒，观察自动重启
sleep 6
systemctl status mywebapp
```

### 6.8 清理（可选）

```bash
# 停止并禁用服务
sudo systemctl stop mywebapp
sudo systemctl disable mywebapp

# 删除 Unit 文件
sudo rm /etc/systemd/system/mywebapp.service
sudo systemctl daemon-reload

# 删除应用文件
sudo rm -rf /opt/mywebapp /etc/mywebapp /var/log/mywebapp

# 删除用户
sudo userdel mywebapp
```

---

## 反模式：常见错误

### 错误 1：Type=forking 用于不 fork 的应用

```ini
# 错误：Python/Node 应用不 fork，不应该用 forking
[Service]
Type=forking
ExecStart=/usr/bin/python3 /opt/app/server.py

# 正确：使用 simple（默认）
[Service]
Type=simple
ExecStart=/usr/bin/python3 /opt/app/server.py
```

**后果**：systemd 等待父进程退出，但应用不会 fork，导致启动超时。

### 错误 2：密钥写在 Environment=

```ini
# 错误：任何人都能 systemctl show 看到
[Service]
Environment=API_KEY=sk-secret123
Environment=DB_PASSWORD=mysecret

# 正确：使用 EnvironmentFile
[Service]
EnvironmentFile=/etc/myapp/secrets
# 并设置文件权限 0600
```

**后果**：敏感信息暴露给所有能执行 `systemctl show` 的用户。

### 错误 3：ExecStart 中写复杂 shell

```ini
# 错误：复杂 shell 管道在 ExecStart 中
[Service]
ExecStart=/bin/sh -c 'cd /opt/app && source venv/bin/activate && python server.py 2>&1 | tee /var/log/app.log'

# 正确：封装成脚本
[Service]
ExecStart=/opt/app/start.sh
```

**后果**：调试困难，进程跟踪混乱，信号处理问题。

### 错误 4：没有 RestartSec 的 Restart=always

```ini
# 错误：失败立即重启，可能造成重启风暴
[Service]
Restart=always

# 正确：设置重启间隔和限制
[Service]
Restart=on-failure
RestartSec=5
StartLimitIntervalSec=300
StartLimitBurst=5
```

**后果**：服务快速失败循环，消耗系统资源，日志爆炸。

### 错误 5：Restart=always 没有 StartLimitIntervalSec

```ini
# 错误：无限重启
[Service]
Restart=always
RestartSec=5
# 没有 StartLimitIntervalSec

# 正确：限制重启次数
[Service]
Restart=on-failure
RestartSec=5
StartLimitIntervalSec=300
StartLimitBurst=5
```

**后果**：配置错误或依赖问题导致服务永远无法启动，却一直在尝试。

---

## 完整 Unit 文件模板

```ini
[Unit]
Description=My Application Service
Documentation=https://docs.example.com
After=network-online.target
Wants=network-online.target

[Service]
Type=notify
User=appuser
Group=appgroup
WorkingDirectory=/opt/myapp

# Use EnvironmentFile for secrets (never inline!)
EnvironmentFile=/etc/myapp/secrets

ExecStartPre=/opt/myapp/bin/check-config
ExecStart=/opt/myapp/bin/server
ExecReload=/bin/kill -HUP $MAINPID

Restart=on-failure
RestartSec=5
StartLimitIntervalSec=300
StartLimitBurst=5

[Install]
WantedBy=multi-user.target
```

---

## 职场小贴士（Japan IT Context）

### アプリケーションのサービス化

在日本 IT 企业，将应用程序配置为 systemd 服务是运维工程师的基本技能。

| 日语术语 | 含义 | 典型场景 |
|----------|------|----------|
| サービス化 | 服务化 | 新应用部署时创建 Unit 文件 |
| 自動起動設定 | 自动启动设置 | `systemctl enable` |
| 再起動設定 | 重启设置 | Restart=on-failure 配置 |
| 起動スクリプト | 启动脚本 | ExecStartPre 中的检查脚本 |

### 文档要求

日本企业通常要求运维操作有详细文档。创建服务时，应该记录：

```markdown
# myapp 服务设定書

## 基本情報
- サービス名: myapp.service
- 作成日: 2026-01-04
- 作成者: 田中

## 設定内容
- Type: notify
- User: appuser
- 自動起動: 有効
- 再起動設定: on-failure (5秒間隔、5分で5回まで)

## 確認方法
1. systemctl status myapp
2. curl http://localhost:8080/health

## 障害対応
- ログ確認: journalctl -u myapp -f
- 手動再起動: sudo systemctl restart myapp
```

---

## 检查清单

完成本课后，你应该能够：

- [ ] 解释 Unit 文件的三段结构（[Unit], [Service], [Install]）
- [ ] 说出 /etc/systemd/system/ 和 /usr/lib/systemd/system/ 的区别
- [ ] 区分 Type=simple 和 Type=forking 的使用场景
- [ ] 知道何时使用 Type=notify
- [ ] 使用 EnvironmentFile= 安全处理密钥
- [ ] 配置 Restart=on-failure 和 RestartSec
- [ ] 配置 StartLimitIntervalSec 和 StartLimitBurst 防止重启风暴
- [ ] 为简单应用创建完整的 Unit 文件
- [ ] 使用 `systemctl cat` 查看服务配置
- [ ] 使用 `systemctl show` 查看服务属性

---

## 本课小结

| 概念 | 要点 | 记忆点 |
|------|------|--------|
| Unit 文件位置 | /etc/ > /run/ > /usr/lib/ | 优先级从高到低 |
| [Unit] 段 | Description, After, Wants | 元信息和依赖 |
| [Service] 段 | Type, ExecStart, Restart | 如何运行 |
| [Install] 段 | WantedBy | enable 时的目标 |
| Type=simple | 默认，前台进程 | 大多数现代应用 |
| Type=forking | 传统 daemon | 需要 PIDFile |
| Type=notify | 应用通知就绪 | 最精确 |
| 密钥安全 | EnvironmentFile= | 文件权限 0600 |
| 重启策略 | Restart + RestartSec | 必须配合使用 |
| 重启限制 | StartLimitIntervalSec | 防止重启风暴 |

---

## 面试准备

### Q: Type=simple と Type=forking の違いは？

**A**: `simple` は ExecStart のプロセスがそのまま主プロセスとして扱われます。`forking` は、プロセスが fork して親が終了した時点で起動完了とみなされ、PIDFile の設定が必要です。現代のアプリケーション（Node.js, Python, Go など）は simple で動作するため、forking は主に従来型の daemon に使用します。

### Q: 機密情報を Unit ファイルで扱う方法は？

**A**: `EnvironmentFile=` で別ファイルを参照し、そのファイルのパーミッションを 0600 に設定します。`Environment=` に直接書くと `systemctl show` で誰でも見えてしまうため、機密情報には使用しません。systemd 250+ では `LoadCredential=` も使用可能です。

### Q: サービスの再起動ループを防ぐ方法は？

**A**: `Restart=on-failure` と `RestartSec=5`（間隔）に加え、`StartLimitIntervalSec=300` と `StartLimitBurst=5` を設定します。これにより、5分間で5回を超えて再起動すると、サービスは failed 状態になり、無限ループを防げます。

---

## 延伸阅读

- [systemd.service(5) man page](https://www.freedesktop.org/software/systemd/man/systemd.service.html)
- [systemd.unit(5) man page](https://www.freedesktop.org/software/systemd/man/systemd.unit.html)
- 下一课：[04 - 依赖与排序](../04-dependencies/) -- 学习 After/Wants/Requires 的正确组合
- 相关课程：[09 - Drop-in 与安全加固](../09-customization-security/) -- 安全定制服务配置

---

## 系列导航

[02 - systemctl 实战 <--](../02-systemctl/) | [系列首页](../) | [--> 04 - 依赖与排序](../04-dependencies/)
