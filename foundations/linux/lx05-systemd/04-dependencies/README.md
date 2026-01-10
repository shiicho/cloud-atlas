# 04 - 依赖与排序（Dependencies and Ordering）

> **目标**：掌握 systemd 最容易混淆的概念 -- 排序与依赖是独立的！  
> **前置**：已完成 [03 - Unit 文件解剖](../03-unit-files/)  
> **时间**：⚡ 20 分钟（速读）/ 🔬 75 分钟（完整实操）  
> **实战场景**：起動順序（Boot Order）-- DB 準備完了前に Web アプリが起動する問題  

---

## 将学到的内容

1. 理解排序（Ordering）与依赖（Requirements）的根本区别
2. 正确组合 After= 与 Wants=/Requires=
3. 区分 Wants, Requires, BindsTo, PartOf, Requisite, Conflicts
4. 使用 Conflicts= 处理互斥服务
5. 创建等待脚本处理复杂依赖

---

## 核心概念（必须先理解！）

> **这是 systemd 最容易混淆的主题！**  
>
> 在继续学习之前，请记住这个黄金法则：  
>
> **排序（Ordering）≠ 依赖（Requirements）**  
>
> 这两个概念是**完全独立**的！必须**同时使用**才能达到预期效果。  

![Ordering vs Requirements](images/ordering-vs-requirements.png)

<details>
<summary>View ASCII source</summary>

```
┌─────────────────────────────────────────────────────────────────────────┐
│                   排序（Ordering）vs 依赖（Requirements）                │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  排序 After=/Before=                   依赖 Wants=/Requires=             │
│  ─────────────────────                 ─────────────────────             │
│                                                                          │
│  "如果两者都要启动，                   "请帮我也启动另一个服务"          │
│   我在它之后/之前"                                                       │
│                                                                          │
│  ┌───────────┐                         ┌───────────┐                     │
│  │ Service A │                         │ Service A │                     │
│  │ After=B   │                         │ Wants=B   │                     │
│  └─────┬─────┘                         └─────┬─────┘                     │
│        │                                     │                           │
│        │ "如果 B 也在                        │ "请启动 B"                │
│        │  启动，我等它"                      ▼                           │
│        │                               ┌───────────┐                     │
│        ▼                               │ Service B │                     │
│  ┌───────────┐                         │ (被拉入)  │                     │
│  │ Service B │                         └───────────┘                     │
│  │ (可能没有 │                                                           │
│  │  被启动!) │                                                           │
│  └───────────┘                                                           │
│                                                                          │
│  ⚠️  After= 不会启动 B！              ⚠️  Wants= 不控制顺序！            │
│     只是说"如果 B 也启动，               只是说"请也启动 B"             │
│     我在它后面"                                                          │
│                                                                          │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  ✅ 正确做法：两者结合！                                                 │
│                                                                          │
│  [Unit]                                                                  │
│  After=postgresql.service      ← 顺序：在 PostgreSQL 后启动             │
│  Wants=postgresql.service      ← 依赖：请启动 PostgreSQL                │
│                                                                          │
│  效果：PostgreSQL 被启动，然后我再启动                                   │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

</details>

---

## 先跑起来！（10 分钟）

> 在深入理论之前，让我们亲眼看看"After= 不拉入依赖"这个问题。  

### Failure Lab: After 没有 Wants

这个实验将展示最常见的配置错误：只写了 `After=` 却没有 `Wants=`。

```bash
# 创建实验目录
sudo mkdir -p /opt/dependency-lab

# 创建一个模拟的"数据库"服务
sudo tee /etc/systemd/system/fake-db.service << 'EOF'
[Unit]
Description=Fake Database (for dependency demo)

[Service]
Type=oneshot
ExecStart=/bin/echo "Fake DB started at $(date)"
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

# 创建一个"Web 应用"服务 -- 错误配置！
sudo tee /etc/systemd/system/webapp-bad.service << 'EOF'
[Unit]
Description=Web App (BAD config - After without Wants)
# 错误！只有 After，没有 Wants
After=fake-db.service

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'echo "Web app checking DB..."; systemctl is-active fake-db.service'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

# 重新加载
sudo systemctl daemon-reload
```

现在，让我们测试这个错误配置：

```bash
# 确保 fake-db 没有在运行
sudo systemctl stop fake-db.service 2>/dev/null

# 启动 webapp-bad
sudo systemctl start webapp-bad.service

# 检查状态 -- 会失败！
systemctl status webapp-bad.service
```

**预期输出**：

```
● webapp-bad.service - Web App (BAD config - After without Wants)
     Loaded: loaded (/etc/systemd/system/webapp-bad.service; disabled)
     Active: failed (Result: exit-code)
    ...
    fake-db.service is inactive
```

**问题**：`After=fake-db.service` 只是说"如果 fake-db 也要启动，我在它之后"。
但它**不会**自动启动 fake-db！

### 修复：添加 Wants=

```bash
# 创建正确配置的 Web 应用服务
sudo tee /etc/systemd/system/webapp-good.service << 'EOF'
[Unit]
Description=Web App (GOOD config - After + Wants)
# 正确！After + Wants 组合
After=fake-db.service
Wants=fake-db.service

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'echo "Web app checking DB..."; systemctl is-active fake-db.service'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

# 重新加载
sudo systemctl daemon-reload

# 确保 fake-db 没有在运行
sudo systemctl stop fake-db.service 2>/dev/null

# 启动 webapp-good
sudo systemctl start webapp-good.service

# 检查状态 -- 成功！
systemctl status webapp-good.service
```

**预期输出**：

```
● webapp-good.service - Web App (GOOD config - After + Wants)
     Loaded: loaded (/etc/systemd/system/webapp-good.service; disabled)
     Active: active (exited)
    ...
    fake-db.service is active
```

**你刚刚亲眼看到了 systemd 依赖配置最常见的错误！**

这个错误如此常见，以至于它有一个名字：**"After without Wants"** 反模式。

---

## Step 1 -- 排序指令详解（15 分钟）

### 1.1 After= 和 Before=

排序指令**只控制启动顺序**，不会拉入依赖。

| 指令 | 含义 | 说明 |
|------|------|------|
| `After=X` | 在 X 之后启动 | 如果 X 也要启动，等 X 完成后再启动我 |
| `Before=X` | 在 X 之前启动 | 如果 X 也要启动，先启动我再启动 X |

```ini
[Unit]
Description=My Web Application
After=network-online.target    # 在网络就绪后启动
After=postgresql.service       # 在数据库后启动
Before=nginx.service           # 在 nginx 前启动（如果需要预热）
```

### 1.2 排序的条件性

```bash
# 查看 sshd 的排序依赖
systemctl show sshd --property=After

# 查看某个服务的完整依赖链
systemctl list-dependencies sshd
```

![After Conditional](images/after-conditional.png)

<details>
<summary>View ASCII source</summary>

```
After= 是条件性的

┌─────────────────────────────────────────────────────────────────────────┐
│                                                                          │
│  场景 1: A 和 B 都要启动                                                 │
│  ───────────────────────                                                 │
│                                                                          │
│  A [After=B]          B                                                  │
│  ─────────────       ────                                                │
│                                                                          │
│       等待...   ◄───  B 先启动                                           │
│         ↓             ↓                                                  │
│       A 启动    ◄───  B 完成                                             │
│                                                                          │
│  结果：B 先，A 后 ✓                                                      │
│                                                                          │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  场景 2: 只有 A 要启动，B 没有被拉入                                     │
│  ─────────────────────────────────                                       │
│                                                                          │
│  A [After=B]          B                                                  │
│  ─────────────       ────                                                │
│                                                                          │
│       A 直接启动      (没有启动)                                         │
│                                                                          │
│  结果：A 启动，B 没启动                                                  │
│  After= 不会启动 B！只是说"如果 B 也启动，我在它后面"                   │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

</details>

### 1.3 停止时的顺序反转

启动顺序和停止顺序是**相反**的：

```
启动：B → A（A 在 B 之后启动）
停止：A → B（A 先停止，然后 B 停止）
```

这确保了依赖关系在停止时也被正确处理。

---

## Step 2 -- 依赖指令详解（20 分钟）

### 2.1 依赖指令总览

| Directive | 强度 | 行为 |
|-----------|------|------|
| `Wants=` | 弱 | 尽力启动依赖，依赖失败也继续 |
| `Requires=` | 强 | 依赖失败则自己也失败（需配合 After=） |
| `BindsTo=` | 最强 | 依赖停止/失败，自己也停止 |
| `PartOf=` | 传播 | 依赖的 stop/restart 传播给自己 |
| `Requisite=` | 即时 | 依赖必须已经在运行，否则立即失败 |
| `Conflicts=` | 负向 | 互斥，启动一个停止另一个 |

### 2.2 Wants= -- 弱依赖

```ini
[Unit]
Description=My Application
After=optional-service.service
Wants=optional-service.service
```

**行为**：
- 尝试启动 optional-service
- 如果 optional-service 启动失败，**自己仍然继续启动**
- 适用于：可选功能、增强服务、非关键依赖

**使用场景**：
- 日志收集服务（没有也能运行）
- 监控 Agent（没有也能工作）
- 可选的缓存服务

### 2.3 Requires= -- 强依赖

```ini
[Unit]
Description=My Application
After=postgresql.service
Requires=postgresql.service
```

**行为**：
- 启动 postgresql.service
- 如果 postgresql.service 启动失败，**自己也失败**
- **注意**：必须配合 `After=` 使用！

**重要警告**：

```ini
# 错误：Requires 没有 After
[Unit]
Requires=postgresql.service
# PostgreSQL 和 App 可能同时启动，App 可能在 DB 准备好之前就尝试连接！

# 正确：Requires + After
[Unit]
After=postgresql.service
Requires=postgresql.service
```

**使用场景**：
- 数据库服务（没有就无法工作）
- 认证服务（必须可用）
- 核心基础设施

### 2.4 BindsTo= -- 最强绑定

```ini
[Unit]
Description=Device-dependent Service
After=dev-sda1.device
BindsTo=dev-sda1.device
```

**行为**：
- 比 Requires= 更强
- 依赖停止 → 自己也停止
- 依赖失败 → 自己也失败
- 适用于：设备依赖、紧密耦合的服务

**使用场景**：
- 挂载点依赖的服务
- 设备绑定的服务
- 必须与另一个服务同生共死的情况

### 2.5 PartOf= -- 传播 stop/restart

```ini
[Unit]
Description=Application Worker
PartOf=myapp.service
```

**行为**：
- myapp.service stop → 我也 stop
- myapp.service restart → 我也 restart
- **不会**自动启动依赖！
- 适用于：主从服务、多进程应用

**使用场景**：
- 主服务 + 工作进程
- 多个紧密相关的服务
- 需要一起重启的服务组

### 2.6 Requisite= -- 即时检查

```ini
[Unit]
Description=Service requiring DB already running
Requisite=postgresql.service
After=postgresql.service
```

**行为**：
- 检查 postgresql.service **是否已经在运行**
- 如果没有在运行，**立即失败**（不尝试启动它）
- 适用于：已知依赖应该已经在运行的情况

**与 Requires= 的区别**：

| 指令 | 依赖不在运行时 |
|------|----------------|
| `Requires=` | 尝试启动依赖 |
| `Requisite=` | 立即失败，不尝试启动 |

### 2.7 Conflicts= -- 互斥

```ini
[Unit]
Description=Production Mode
Conflicts=development.service
```

**行为**：
- 启动 production → 停止 development
- 启动 development → 停止 production
- 两者不能同时运行

**使用场景**：
- 生产/开发模式切换
- 互斥的服务版本
- 同端口服务（如 nginx 和 apache）

---

## Step 3 -- 依赖强度对比图（5 分钟）

![Dependency Strength](images/dependency-strength.png)

<details>
<summary>View ASCII source</summary>

```
┌──────────────┬──────────┬─────────────────────────────────────────────────┐
│ Directive    │ Strength │ Behavior                                        │
├──────────────┼──────────┼─────────────────────────────────────────────────┤
│ Wants=       │ Weak     │ Best effort, continues if dep fails             │
│              │   ○      │ "请帮我启动，失败了也没关系"                    │
├──────────────┼──────────┼─────────────────────────────────────────────────┤
│ Requires=    │ Strong   │ Fails if dependency fails (with After=)         │
│              │   ●      │ "必须启动成功，否则我也失败"                    │
├──────────────┼──────────┼─────────────────────────────────────────────────┤
│ BindsTo=     │ Strongest│ Stops if dependency stops/fails                 │
│              │   ●●     │ "同生共死，你停我也停"                          │
├──────────────┼──────────┼─────────────────────────────────────────────────┤
│ PartOf=      │ Propagate│ Stop/restart propagates from parent             │
│              │   ↓      │ "传播 stop/restart 给我"                        │
├──────────────┼──────────┼─────────────────────────────────────────────────┤
│ Requisite=   │ Immediate│ Fails if dependency not already active          │
│              │   ⚡     │ "必须已经在运行，不然立即失败"                  │
├──────────────┼──────────┼─────────────────────────────────────────────────┤
│ Conflicts=   │ Negative │ Starting one stops the other                    │
│              │   ✕      │ "互斥，不能共存"                                │
└──────────────┴──────────┴─────────────────────────────────────────────────┘

选择指南：
─────────────────────────────────────────────────────────────────────────────

可选依赖？ ────────► Wants=
    │
    ▼ 不是
    │
必须成功？ ────────► Requires= + After=
    │
    ▼ 还不够
    │
同生共死？ ────────► BindsTo= + After=
    │
    ▼ 需要传播
    │
传播重启？ ────────► PartOf=
    │
    ▼ 必须已在运行
    │
不启动依赖？ ───────► Requisite= + After=
    │
    ▼ 互斥
    │
两者冲突？ ────────► Conflicts=
```

</details>

---

## Step 4 -- 常见模式与反模式（15 分钟）

### 4.1 正确模式：After= + Wants=/Requires=

```ini
# 标准 Web 应用配置
[Unit]
Description=Web Application
Documentation=https://docs.example.com

# 正确：排序 + 依赖
After=network-online.target
Wants=network-online.target

After=postgresql.service
Requires=postgresql.service

[Service]
Type=notify
ExecStart=/opt/webapp/bin/server
```

### 4.2 反模式 1：After= without Wants=

```ini
# 错误配置！
[Unit]
After=postgresql.service
# 没有 Wants= 或 Requires=
# PostgreSQL 不会被启动！

[Service]
ExecStart=/opt/webapp/bin/server
```

**后果**：如果单独启动此服务，PostgreSQL 不会被自动启动，应用可能无法连接数据库。

**修复**：

```ini
# 正确配置
[Unit]
After=postgresql.service
Wants=postgresql.service    # 添加这一行！

[Service]
ExecStart=/opt/webapp/bin/server
```

### 4.3 反模式 2：network.target vs network-online.target

```ini
# 错误配置！
[Unit]
After=network.target    # 网络可能还没真正准备好！

[Service]
ExecStart=/opt/webapp/bin/server --connect-to-remote-db
```

**问题**：
- `network.target` 只表示"网络栈已初始化"
- **不保证**网络连接已经建立
- 远程连接可能失败

**修复**：

```ini
# 正确配置
[Unit]
After=network-online.target       # 网络真正可用
Wants=network-online.target       # 并拉入依赖

[Service]
ExecStart=/opt/webapp/bin/server --connect-to-remote-db
```

### 4.4 network.target vs network-online.target 详解

| Target | 含义 | 保证 |
|--------|------|------|
| `network.target` | 网络栈已初始化 | 本地接口可能已配置，但**不保证连接** |
| `network-online.target` | 网络已可用 | 可以进行网络通信 |

```bash
# 查看 network-online.target 的依赖
systemctl list-dependencies network-online.target

# 检查网络等待服务
systemctl status NetworkManager-wait-online.service
# 或
systemctl status systemd-networkd-wait-online.service
```

**何时使用哪个**：

| 场景 | 使用 |
|------|------|
| 只需要本地网络接口 | `network.target` |
| 需要连接远程服务 | `network-online.target` |
| 需要 DNS 解析 | `network-online.target` |
| 需要访问 NFS/远程存储 | `network-online.target` |

### 4.5 反模式 3：Requires= without After=

```ini
# 有问题的配置
[Unit]
Requires=postgresql.service
# 没有 After=！
# PostgreSQL 和 Web 应用可能同时启动！

[Service]
ExecStart=/opt/webapp/bin/server
```

**后果**：两个服务可能并行启动，Web 应用可能在 PostgreSQL 准备好接受连接之前就尝试连接。

**修复**：

```ini
# 正确配置
[Unit]
After=postgresql.service      # 添加排序！
Requires=postgresql.service

[Service]
ExecStart=/opt/webapp/bin/server
```

---

## Step 5 -- 自定义等待服务（10 分钟）

有时候，`After=` 不够用 -- 依赖的服务"启动"了，但还没真正"就绪"。

### 5.1 问题场景

PostgreSQL 服务可能显示 `active (running)`，但数据库还在执行恢复，
无法接受连接。这时候 Web 应用启动就会失败。

### 5.2 解决方案：Type=oneshot 等待服务

```bash
# 创建 PostgreSQL 就绪检测服务
sudo tee /etc/systemd/system/wait-for-postgresql.service << 'EOF'
[Unit]
Description=Wait for PostgreSQL to be ready
After=postgresql.service
Requires=postgresql.service

[Service]
Type=oneshot
# 最多等待 60 秒，每 2 秒检查一次
ExecStart=/bin/bash -c '\
    for i in $(seq 1 30); do \
        if pg_isready -q; then \
            echo "PostgreSQL is ready"; \
            exit 0; \
        fi; \
        echo "Waiting for PostgreSQL... ($i/30)"; \
        sleep 2; \
    done; \
    echo "PostgreSQL not ready after 60s"; \
    exit 1'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
```

然后在 Web 应用中依赖这个等待服务：

```ini
[Unit]
Description=Web Application
After=wait-for-postgresql.service
Requires=wait-for-postgresql.service

[Service]
Type=notify
ExecStart=/opt/webapp/bin/server
```

### 5.3 等待服务的模式

![Wait Service Pattern](images/wait-service-pattern.png)

<details>
<summary>View ASCII source</summary>

```
┌─────────────────────────────────────────────────────────────────────────┐
│                     等待服务模式（Wait Service Pattern）                 │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  ┌───────────────┐                                                       │
│  │  postgresql   │  ← 服务"启动"了                                      │
│  │   .service    │     但可能还在初始化                                  │
│  └───────┬───────┘                                                       │
│          │                                                               │
│          │ After=, Requires=                                             │
│          ▼                                                               │
│  ┌───────────────┐                                                       │
│  │   wait-for-   │  ← Type=oneshot                                      │
│  │  postgresql   │     循环检测直到真正就绪                              │
│  │   .service    │     pg_isready / curl / nc                           │
│  └───────┬───────┘                                                       │
│          │                                                               │
│          │ After=, Requires=                                             │
│          ▼                                                               │
│  ┌───────────────┐                                                       │
│  │   webapp      │  ← 现在可以安全连接数据库                            │
│  │   .service    │                                                       │
│  └───────────────┘                                                       │
│                                                                          │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  常用检测命令：                                                          │
│                                                                          │
│  PostgreSQL:  pg_isready -q                                              │
│  MySQL:       mysqladmin ping -h localhost                               │
│  Redis:       redis-cli ping                                             │
│  HTTP:        curl -sf http://localhost:8080/health                      │
│  TCP Port:    nc -z localhost 5432                                       │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

</details>

---

## Step 6 -- 动手实验：数据库依赖的 Web 应用（20 分钟）

> **Mini-Project**：创建 Web 应用服务，正确依赖 PostgreSQL，包含就绪检测。  

### 6.1 模拟场景

我们将创建：
1. 模拟数据库服务（fake-postgresql）
2. 等待服务（wait-for-db）
3. Web 应用服务（webapp）

### 6.2 创建模拟数据库服务

```bash
# 创建模拟 PostgreSQL 服务（启动需要 5 秒才"就绪"）
sudo tee /etc/systemd/system/fake-postgresql.service << 'EOF'
[Unit]
Description=Fake PostgreSQL (simulates slow startup)

[Service]
Type=oneshot
# 模拟数据库启动需要 5 秒
ExecStart=/bin/bash -c '\
    echo "PostgreSQL starting..."; \
    sleep 5; \
    touch /tmp/fake-pg-ready; \
    echo "PostgreSQL ready"'
ExecStop=/bin/rm -f /tmp/fake-pg-ready
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
```

### 6.3 创建等待服务

```bash
# 创建等待服务
sudo tee /etc/systemd/system/wait-for-fake-pg.service << 'EOF'
[Unit]
Description=Wait for Fake PostgreSQL to be ready
After=fake-postgresql.service
Requires=fake-postgresql.service

[Service]
Type=oneshot
ExecStart=/bin/bash -c '\
    for i in $(seq 1 20); do \
        if [ -f /tmp/fake-pg-ready ]; then \
            echo "Database is ready!"; \
            exit 0; \
        fi; \
        echo "Waiting for database... ($i/20)"; \
        sleep 1; \
    done; \
    echo "Database not ready!"; \
    exit 1'
RemainAfterExit=yes
EOF
```

### 6.4 创建 Web 应用服务

```bash
# 创建 Web 应用服务
sudo tee /etc/systemd/system/webapp-demo.service << 'EOF'
[Unit]
Description=Demo Web Application
Documentation=https://example.com/docs

# 正确的依赖配置！
After=network-online.target
Wants=network-online.target

After=wait-for-fake-pg.service
Requires=wait-for-fake-pg.service

[Service]
Type=simple
ExecStart=/bin/bash -c '\
    echo "Web application starting..."; \
    echo "Connected to database!"; \
    while true; do \
        sleep 60; \
    done'
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
```

### 6.5 测试完整依赖链

```bash
# 重新加载
sudo systemctl daemon-reload

# 确保服务都已停止
sudo systemctl stop webapp-demo.service wait-for-fake-pg.service fake-postgresql.service 2>/dev/null

# 清理状态文件
sudo rm -f /tmp/fake-pg-ready

# 启动 Web 应用（应该自动拉入整个依赖链）
sudo systemctl start webapp-demo.service

# 查看启动顺序
sudo journalctl -u fake-postgresql -u wait-for-fake-pg -u webapp-demo --since "1 minute ago" --no-pager
```

**预期输出**：

```
fake-postgresql.service: PostgreSQL starting...
fake-postgresql.service: PostgreSQL ready
wait-for-fake-pg.service: Waiting for database... (1/20)
wait-for-fake-pg.service: Database is ready!
webapp-demo.service: Web application starting...
webapp-demo.service: Connected to database!
```

### 6.6 查看依赖关系

```bash
# 查看 webapp-demo 的依赖树
systemctl list-dependencies webapp-demo.service

# 查看反向依赖（谁依赖这个服务）
systemctl list-dependencies --reverse fake-postgresql.service
```

### 6.7 测试失败场景

```bash
# 停止所有服务
sudo systemctl stop webapp-demo.service wait-for-fake-pg.service fake-postgresql.service

# 如果数据库不启动会怎样？
# 修改 fake-postgresql 让它失败
sudo systemctl mask fake-postgresql.service

# 尝试启动 webapp
sudo systemctl start webapp-demo.service

# 查看结果
systemctl status webapp-demo.service

# 恢复
sudo systemctl unmask fake-postgresql.service
```

### 6.8 清理

```bash
# 停止并删除实验服务
sudo systemctl stop webapp-demo.service wait-for-fake-pg.service fake-postgresql.service 2>/dev/null
sudo systemctl disable webapp-demo.service wait-for-fake-pg.service fake-postgresql.service 2>/dev/null
sudo rm /etc/systemd/system/webapp-demo.service
sudo rm /etc/systemd/system/wait-for-fake-pg.service
sudo rm /etc/systemd/system/fake-postgresql.service
sudo rm /etc/systemd/system/fake-db.service
sudo rm /etc/systemd/system/webapp-bad.service
sudo rm /etc/systemd/system/webapp-good.service
sudo rm -f /tmp/fake-pg-ready
sudo systemctl daemon-reload
```

---

## 反模式总结

### 错误 1：After= without Wants=

```ini
# 错误
[Unit]
After=postgresql.service
# 依赖不会被启动！

# 正确
[Unit]
After=postgresql.service
Wants=postgresql.service
```

### 错误 2：network.target instead of network-online.target

```ini
# 错误 -- 网络可能还没准备好
[Unit]
After=network.target

# 正确 -- 网络确实可用
[Unit]
After=network-online.target
Wants=network-online.target
```

### 错误 3：Requires= without After=

```ini
# 错误 -- 可能并行启动
[Unit]
Requires=postgresql.service

# 正确 -- 确保顺序
[Unit]
After=postgresql.service
Requires=postgresql.service
```

### 错误 4：忽略 BindsTo= 用于设备依赖

```ini
# 错误 -- 设备拔出后服务继续运行
[Unit]
After=dev-sda1.device
Requires=dev-sda1.device

# 正确 -- 设备拔出后服务停止
[Unit]
After=dev-sda1.device
BindsTo=dev-sda1.device
```

---

## 职场小贴士（Japan IT Context）

### 起動順序（Boot Order）

在日本 IT 企业，服务启动顺序问题是常见的运维障害：

| 日语术语 | 含义 | 典型场景 |
|----------|------|----------|
| 起動順序 | 启动顺序 | DB 準備完了前に Web アプリが起動 |
| 依存関係 | 依赖关系 | After= と Wants= の正しい設定 |
| 起動失敗 | 启动失败 | データベース接続エラー |
| 順序制御 | 顺序控制 | 正確なブート順序の保証 |

### 障害対応チェックリスト

当服务启动失败时，检查依赖关系：

```bash
# 1. 检查服务状态
systemctl status myapp.service

# 2. 检查依赖链
systemctl list-dependencies myapp.service

# 3. 检查依赖服务状态
systemctl status postgresql.service

# 4. 查看启动顺序日志
journalctl -b -u postgresql -u myapp --no-pager

# 5. 确认配置中的依赖指令
systemctl cat myapp.service | grep -E 'After|Before|Wants|Requires'
```

### 運用手順書の記載例

日本企业通常要求详细的运维文档：

```markdown
# myapp 依存関係設定

## 依存サービス
- postgresql.service（必須）
- redis.service（推奨）

## 起動順序
1. network-online.target
2. postgresql.service
3. redis.service
4. myapp.service

## 設定内容
After=network-online.target postgresql.service redis.service
Wants=network-online.target redis.service
Requires=postgresql.service

## 確認コマンド
systemctl list-dependencies myapp.service
```

---

## 检查清单

完成本课后，你应该能够：

- [ ] 解释 After= 和 Wants= 的区别
- [ ] 说明为什么 After= 不会启动依赖服务
- [ ] 正确使用 After= + Wants=/Requires= 组合
- [ ] 区分 Wants=（弱）和 Requires=（强）的使用场景
- [ ] 理解 BindsTo= 用于设备依赖的场景
- [ ] 知道何时使用 network-online.target 而非 network.target
- [ ] 创建 Type=oneshot 等待服务处理复杂依赖
- [ ] 使用 `systemctl list-dependencies` 查看依赖树
- [ ] 识别并修复 "After without Wants" 反模式
- [ ] 使用 Conflicts= 处理互斥服务

---

## 本课小结

| 概念 | 要点 | 记忆点 |
|------|------|--------|
| Ordering vs Requirements | 两者独立，必须同时使用 | After + Wants/Requires |
| After= | 只控制顺序，不拉入依赖 | "如果也启动，我在后面" |
| Wants= | 弱依赖，失败继续 | "尽力启动" |
| Requires= | 强依赖，失败也失败 | "必须成功" |
| BindsTo= | 最强，同生共死 | "你停我也停" |
| PartOf= | 传播 stop/restart | "跟着一起" |
| Requisite= | 必须已在运行 | "不帮你启动" |
| Conflicts= | 互斥 | "不能共存" |
| network-online.target | 网络真正可用 | 远程连接用这个 |
| 等待服务 | Type=oneshot 循环检测 | 处理慢启动依赖 |

---

## 面试准备

### Q: After= と Requires= の違いは？

**A**: `After=` は起動順序のみを制御します。「もし両方起動するなら、自分は後」という意味です。依存サービスを起動しません。`Requires=` は依存関係を定義し、依存サービスを起動しますが、順序は制御しません。通常は `After=` と `Requires=` を両方使用する必要があります。

例：
```ini
After=postgresql.service      # 順序：後に起動
Requires=postgresql.service   # 依存：起動を要求
```

### Q: network.target と network-online.target の違いは？

**A**: `network.target` はネットワークスタックの初期化を示しますが、実際の接続は保証しません。`network-online.target` は、ネットワークが実際に使用可能な状態を示します。リモートデータベースや API に接続するサービスは、必ず `network-online.target` を使用すべきです。

### Q: Wants= と Requires= の使い分けは？

**A**: `Wants=` は依存サービスが失敗しても自分は起動を続けます。ログ収集や監視など、なくても動作するサービスに使用します。`Requires=` は依存サービスが失敗したら自分も失敗します。データベースなど、必須の依存関係に使用します。

### Q: BindsTo= はどのような場合に使いますか？

**A**: `BindsTo=` は `Requires=` より強い依存関係です。依存サービスが停止または失敗した場合、自分も停止します。デバイス依存のサービス（マウントポイントなど）や、別のサービスと完全に連動する必要がある場合に使用します。

---

## 延伸阅读

- [systemd.unit(5) - 依赖关系部分](https://www.freedesktop.org/software/systemd/man/systemd.unit.html#Mapping%20of%20unit%20properties%20to%20their%20inverses)
- [Understanding systemd Dependencies](https://www.freedesktop.org/wiki/Software/systemd/NetworkTarget/)
- 下一课：[05 - Target 与启动流程](../05-targets/) -- 学习 Target 如何组织服务
- 相关课程：[03 - Unit 文件解剖](../03-unit-files/) -- Unit 文件基础结构

---

## 系列导航

[03 - Unit 文件解剖 <--](../03-unit-files/) | [系列首页](../) | [--> 05 - Target 与启动流程](../05-targets/)
