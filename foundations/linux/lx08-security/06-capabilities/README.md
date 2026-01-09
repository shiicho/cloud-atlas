# 06 - Linux Capabilities：精细权限控制

> **目标**：掌握 Capabilities 实现最小权限，替代 all-or-nothing 的 root  
> **前置**：完成 Lesson 01-05（安全原则、SSH、SELinux）  
> **时间**：2 小时  
> **实战场景**：非 root 服务绑定 80 端口、systemd 服务权限限制  

---

## 将学到的内容

1. 理解 Capabilities 取代 all-or-nothing root 的设计
2. 查看和设置文件 Capabilities（getcap, setcap）
3. 查看进程 Capabilities（/proc/PID/status, capsh）
4. 在 systemd 服务中使用 Capabilities
5. 理解容器安全中的 Capabilities 控制
6. **关键警告**：CAP_SYS_ADMIN 几乎等于 root

---

## 先跑起来！（10 分钟）

> 在学习理论之前，先体验 Capabilities 解决的真实问题。  

### 场景：非 root 用户绑定 80 端口

```bash
# 创建一个简单的测试程序（使用 Python）
cat > /tmp/simple-server.py << 'EOF'
#!/usr/bin/env python3
import socket
import os

print(f"Running as UID: {os.getuid()}")
print(f"Attempting to bind to port 80...")

try:
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sock.bind(('0.0.0.0', 80))
    sock.listen(1)
    print("SUCCESS! Listening on port 80")
    sock.close()
except PermissionError as e:
    print(f"FAILED: {e}")
    print("Hint: Ports below 1024 require special privileges")
EOF

chmod +x /tmp/simple-server.py

# 尝试以普通用户运行
python3 /tmp/simple-server.py
```

**预期输出**：

```
Running as UID: 1000
Attempting to bind to port 80...
FAILED: [Errno 13] Permission denied
Hint: Ports below 1024 require special privileges
```

**问题**：1024 以下的端口（privileged ports）需要 root 权限才能绑定。

**传统解决方案**：
- 以 root 运行服务 → **危险！**
- 使用 iptables 端口转发 → 复杂
- 使用反向代理 → 增加架构复杂度

**现代解决方案**：Capabilities！

```bash
# 使用 setcap 授予绑定低端口的能力
sudo setcap 'cap_net_bind_service=+ep' /usr/bin/python3

# 再次尝试
python3 /tmp/simple-server.py
```

**预期输出**：

```
Running as UID: 1000
Attempting to bind to port 80...
SUCCESS! Listening on port 80
```

**发生了什么？** 我们没有给 Python 完整的 root 权限，只给了它**绑定低端口**这一项能力。这就是 Capabilities 的核心价值。

```bash
# 清理：移除测试用的 capability（重要！）
sudo setcap -r /usr/bin/python3

# 验证已移除
getcap /usr/bin/python3
# 应该没有输出
```

> **注意**：上面只是演示。在生产环境中，不要直接给 Python 解释器加 capability。正确做法是给编译后的二进制程序加，或使用 systemd 的 AmbientCapabilities。  

---

## Step 1 — 为什么需要 Capabilities？（15 分钟）

### 1.1 传统 root 权限的问题

在传统 Unix 模型中，权限是 all-or-nothing：

<!-- DIAGRAM: traditional-root-model -->
```
┌─────────────────────────────────────────────────────────────────┐
│                     传统 Unix 权限模型                           │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│   普通用户                           root                        │
│   ┌─────────────────┐              ┌─────────────────┐          │
│   │ UID != 0        │              │ UID = 0         │          │
│   │                 │              │                 │          │
│   │ 受限于:          │              │ 可以做任何事:   │          │
│   │ - 文件权限       │              │ - 绑定任何端口  │          │
│   │ - 进程权限       │              │ - 读写任何文件  │          │
│   │ - 端口限制       │              │ - 杀死任何进程  │          │
│   │ - 网络限制       │              │ - 加载内核模块  │          │
│   └─────────────────┘              │ - 挂载文件系统  │          │
│                                    │ - 修改时间      │          │
│                                    │ - ...等 30+ 种  │          │
│                                    └─────────────────┘          │
│                                                                 │
│   问题：需要做一件特权操作 → 必须获得全部特权                       │
│   例如：只想绑定 80 端口 → 必须以 root 运行 → 安全隐患             │
└─────────────────────────────────────────────────────────────────┘
```
<!-- /DIAGRAM -->

**真实案例**：

| 需求 | 传统做法 | 风险 |
|------|----------|------|
| nginx 绑定 80 端口 | 以 root 启动 | nginx 漏洞 = root 权限泄露 |
| ping 发送 ICMP | SUID root | SUID 程序漏洞 = 提权 |
| wireshark 抓包 | 以 root 运行 | GUI 程序以 root 运行极度危险 |

### 1.2 Capabilities：细粒度权限分解

Linux Capabilities 将 root 的超级权限分解成 30+ 个独立的能力：

```bash
# 查看系统支持的所有 Capabilities
man capabilities
# 或
cat /usr/include/linux/capability.h | grep "^#define CAP_"
```

**常用 Capabilities 列表**：

| Capability | 作用 | 使用场景 |
|------------|------|----------|
| `CAP_NET_BIND_SERVICE` | 绑定 1024 以下端口 | Web 服务器 |
| `CAP_NET_RAW` | 使用原始套接字 | ping, tcpdump |
| `CAP_NET_ADMIN` | 网络配置（iptables, 路由） | 网络管理工具 |
| `CAP_DAC_OVERRIDE` | 绕过文件权限检查 | 备份工具 |
| `CAP_CHOWN` | 修改文件所有者 | 文件管理 |
| `CAP_SETUID` | 设置进程 UID | login, su |
| `CAP_SYS_PTRACE` | 跟踪进程 | 调试器 |
| `CAP_SYS_TIME` | 修改系统时间 | NTP 客户端 |
| `CAP_SYS_ADMIN` | **危险！见下文** | 内核管理 |

### 1.3 CAP_SYS_ADMIN：最危险的 Capability

> **关键警告**：`CAP_SYS_ADMIN` 几乎等于 root！  

```bash
# CAP_SYS_ADMIN 包含的操作：
# - 挂载/卸载文件系统
# - 设置主机名
# - 配置 cgroups
# - 加载 BPF 程序
# - 访问某些设备
# - ... 以及更多

# 这是一个 "catch-all" capability，违反了最小权限原则
# 在容器安全中，CAP_SYS_ADMIN 是逃逸的主要途径之一
```

| Capability | 风险等级 | 说明 |
|------------|----------|------|
| CAP_NET_BIND_SERVICE | 低 | 只能绑定端口 |
| CAP_NET_RAW | 中 | 可以嗅探网络 |
| CAP_SYS_PTRACE | 高 | 可以调试其他进程 |
| **CAP_SYS_ADMIN** | **极高** | **几乎等于 root** |

---

## Step 2 — 文件 Capabilities（20 分钟）

### 2.1 查看文件 Capabilities

```bash
# 查看单个文件的 capabilities
getcap /usr/bin/ping

# 典型输出（RHEL/CentOS）：
# /usr/bin/ping cap_net_raw=ep

# 递归查看目录下所有有 capabilities 的文件
getcap -r /usr/bin/ 2>/dev/null

# 全系统扫描（审计用途）
sudo getcap -r / 2>/dev/null
```

### 2.2 Capability 标志含义

Capabilities 有三个标志位：

```
cap_net_bind_service=+ep
                      ││
                      │└─ p = Permitted（允许的）
                      └── e = Effective（生效的）
```

| 标志 | 含义 | 说明 |
|------|------|------|
| `e` (Effective) | 生效的 | 进程当前使用的能力 |
| `p` (Permitted) | 允许的 | 进程可以使用的能力上限 |
| `i` (Inheritable) | 可继承的 | 可以传递给子进程的能力 |

**常用组合**：

```bash
# 最常用：ep（允许并生效）
setcap cap_net_bind_service=+ep /path/to/binary

# 完整组合：eip
setcap cap_net_bind_service=+eip /path/to/binary
```

### 2.3 设置文件 Capabilities

```bash
# 设置 capability
sudo setcap 'cap_net_bind_service=+ep' /path/to/binary

# 设置多个 capabilities
sudo setcap 'cap_net_bind_service,cap_net_raw=+ep' /path/to/binary

# 移除所有 capabilities
sudo setcap -r /path/to/binary

# 验证设置
getcap /path/to/binary
```

### 2.4 实战：让 nc 绑定低端口

```bash
# 复制 nc（避免修改系统原件）
sudo cp /usr/bin/nc /tmp/nc-cap

# 尝试以普通用户绑定 80 端口（失败）
/tmp/nc-cap -l 80
# nc: Permission denied

# 添加 capability
sudo setcap 'cap_net_bind_service=+ep' /tmp/nc-cap

# 验证
getcap /tmp/nc-cap
# /tmp/nc-cap cap_net_bind_service=ep

# 再次尝试（成功）
/tmp/nc-cap -l 80 &
ss -tlnp | grep :80
# LISTEN ... 80 ... users:(("nc-cap",...))

# 清理
kill %1
rm /tmp/nc-cap
```

---

## Step 3 — 进程 Capabilities（15 分钟）

### 3.1 查看进程 Capabilities

```bash
# 方法 1：使用 /proc 文件系统
cat /proc/$$/status | grep Cap

# 输出示例：
# CapInh: 0000000000000000    # Inheritable
# CapPrm: 0000000000000000    # Permitted
# CapEff: 0000000000000000    # Effective
# CapBnd: 000001ffffffffff    # Bounding set
# CapAmb: 0000000000000000    # Ambient

# 方法 2：使用 capsh 解码
capsh --decode=000001ffffffffff

# 方法 3：使用 getpcaps（如果安装了 libcap）
getpcaps $$
```

### 3.2 理解 Capability 集合

<!-- DIAGRAM: capability-sets -->
```
┌─────────────────────────────────────────────────────────────────┐
│                     进程 Capability 集合                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│   ┌─────────────────────────────────────────────────────────┐   │
│   │ Bounding Set（边界集）                                   │   │
│   │ 进程可能获得的 capability 的上限                          │   │
│   │ 只能减少，不能增加                                        │   │
│   │ ┌─────────────────────────────────────────────────────┐ │   │
│   │ │ Permitted Set（允许集）                              │ │   │
│   │ │ 进程当前允许使用的 capabilities                       │ │   │
│   │ │ ┌─────────────────────────────────────────────────┐ │ │   │
│   │ │ │ Effective Set（生效集）                          │ │ │   │
│   │ │ │ 进程当前实际使用的 capabilities                   │ │ │   │
│   │ │ └─────────────────────────────────────────────────┘ │ │   │
│   │ └─────────────────────────────────────────────────────┘ │   │
│   └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│   Inheritable Set（可继承集）  ← 可以传递给子进程                  │
│   Ambient Set（环境集）       ← 自动传递给非特权子进程              │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```
<!-- /DIAGRAM -->

### 3.3 使用 capsh 探索 Capabilities

```bash
# 查看当前 shell 的 capabilities
capsh --print

# 输出示例：
# Current: =
# Bounding set =cap_chown,cap_dac_override,cap_dac_read_search,...
# Ambient set =
# ...

# 以受限 capabilities 运行命令
sudo capsh --drop=cap_net_raw -- -c "ping -c 1 localhost"
# ping: socket: Operation not permitted

# 保留特定 capabilities 运行
sudo capsh --keep=1 --user=nobody --caps='cap_net_bind_service+eip' -- -c 'cat /proc/self/status | grep Cap'
```

---

## Step 4 — systemd 集成（30 分钟）

> **最佳实践**：在生产环境中，使用 systemd 管理服务的 Capabilities，而不是给文件设置 setcap。  

### 4.1 systemd Capability 指令

| 指令 | 作用 |
|------|------|
| `CapabilityBoundingSet=` | 设置边界集（上限） |
| `AmbientCapabilities=` | 设置环境 capabilities |
| `NoNewPrivileges=true` | 禁止获得新权限 |

### 4.2 创建使用 Capabilities 的服务

**场景**：创建一个以非 root 用户运行的 web 服务，需要绑定 80 端口。

```bash
# 1. 创建服务用户
sudo useradd -r -s /sbin/nologin webservice

# 2. 创建服务脚本
sudo tee /opt/webservice/server.py << 'EOF'
#!/usr/bin/env python3
"""Simple HTTP server that binds to port 80"""
import http.server
import socketserver
import os

PORT = 80

print(f"Starting server on port {PORT}")
print(f"Running as UID: {os.getuid()}, GID: {os.getgid()}")

Handler = http.server.SimpleHTTPRequestHandler

with socketserver.TCPServer(("", PORT), Handler) as httpd:
    print(f"Serving at port {PORT}")
    httpd.serve_forever()
EOF

sudo chmod +x /opt/webservice/server.py
sudo chown -R webservice:webservice /opt/webservice

# 3. 创建 systemd unit 文件
sudo tee /etc/systemd/system/webservice.service << 'EOF'
[Unit]
Description=Web Service with Capabilities
After=network.target

[Service]
Type=simple
User=webservice
Group=webservice
WorkingDirectory=/opt/webservice

# 安全设置：Capabilities
# AmbientCapabilities 允许非 root 用户获得指定的 capability
AmbientCapabilities=CAP_NET_BIND_SERVICE

# CapabilityBoundingSet 限制可以获得的 capabilities 上限
CapabilityBoundingSet=CAP_NET_BIND_SERVICE

# 禁止获得新权限（重要安全设置）
NoNewPrivileges=true

# 额外的安全加固
ProtectSystem=strict
ProtectHome=true
PrivateTmp=true
ReadWritePaths=/opt/webservice

ExecStart=/usr/bin/python3 /opt/webservice/server.py

[Install]
WantedBy=multi-user.target
EOF

# 4. 启动服务
sudo systemctl daemon-reload
sudo systemctl start webservice

# 5. 验证
sudo systemctl status webservice
ss -tlnp | grep :80
# LISTEN ... :80 ... users:(("python3",...))

# 检查进程的 capabilities
ps aux | grep server.py
PID=$(pgrep -f "server.py")
sudo cat /proc/$PID/status | grep Cap

# 清理（测试后）
sudo systemctl stop webservice
sudo systemctl disable webservice
sudo rm /etc/systemd/system/webservice.service
sudo userdel webservice
sudo rm -rf /opt/webservice
```

### 4.3 systemd 安全指令详解

```ini
[Service]
# ==========================================
# Capabilities 控制
# ==========================================

# AmbientCapabilities: 服务启动时自动获得的 capabilities
# 这是让非 root 服务获得特定权限的标准方式
AmbientCapabilities=CAP_NET_BIND_SERVICE

# CapabilityBoundingSet: 服务可以拥有的 capabilities 上限
# 这是一个安全边界，即使代码尝试也无法超越
CapabilityBoundingSet=CAP_NET_BIND_SERVICE CAP_NET_RAW

# NoNewPrivileges: 禁止通过 execve 获得新权限
# 这防止了利用 SUID 程序提权
NoNewPrivileges=true

# ==========================================
# 其他安全加固（推荐配合使用）
# ==========================================

# 保护系统目录
ProtectSystem=strict      # /usr, /boot 只读
ProtectHome=true          # 无法访问 /home
PrivateTmp=true           # 隔离的 /tmp

# 网络限制（如果不需要出站）
# RestrictAddressFamilies=AF_INET AF_INET6

# 系统调用过滤
# SystemCallFilter=@system-service
```

### 4.4 实际服务示例：Node.js 应用

```ini
# /etc/systemd/system/nodejs-app.service
[Unit]
Description=Node.js Application
After=network.target

[Service]
Type=simple
User=nodejs
Group=nodejs
WorkingDirectory=/app

# Capabilities：只允许绑定低端口
AmbientCapabilities=CAP_NET_BIND_SERVICE
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
NoNewPrivileges=true

# 环境变量
Environment=NODE_ENV=production
Environment=PORT=80

# 安全加固
ProtectSystem=strict
ProtectHome=true
PrivateTmp=true
ReadWritePaths=/app/logs

ExecStart=/usr/bin/node /app/server.js

[Install]
WantedBy=multi-user.target
```

---

## Step 5 — 容器安全中的 Capabilities（20 分钟）

### 5.1 容器默认 Capabilities

Docker/Podman 默认给容器分配一组有限的 capabilities：

```bash
# 查看 Docker 默认授予的 capabilities
docker run --rm alpine cat /proc/self/status | grep Cap

# 对比完整 root 的 capabilities
sudo cat /proc/1/status | grep Cap
```

**Docker 默认 Capabilities**：

| Capability | 默认 | 说明 |
|------------|------|------|
| CAP_CHOWN | Yes | 修改文件所有者 |
| CAP_DAC_OVERRIDE | Yes | 绕过文件权限 |
| CAP_FSETID | Yes | 保留 setuid/setgid |
| CAP_FOWNER | Yes | 绕过所有者检查 |
| CAP_MKNOD | Yes | 创建设备文件 |
| CAP_NET_RAW | Yes | 原始套接字 |
| CAP_SETGID | Yes | 设置 GID |
| CAP_SETUID | Yes | 设置 UID |
| CAP_SETFCAP | Yes | 设置文件 capabilities |
| CAP_SETPCAP | Yes | 修改进程 capabilities |
| CAP_NET_BIND_SERVICE | Yes | 绑定低端口 |
| CAP_SYS_CHROOT | Yes | 使用 chroot |
| CAP_KILL | Yes | 发送信号 |
| CAP_AUDIT_WRITE | Yes | 写入审计日志 |

### 5.2 --cap-drop 和 --cap-add

```bash
# 最安全：丢弃所有 capabilities，只添加需要的
docker run --rm \
    --cap-drop=ALL \
    --cap-add=NET_BIND_SERVICE \
    nginx

# Podman 同样支持
podman run --rm \
    --cap-drop=ALL \
    --cap-add=NET_BIND_SERVICE \
    nginx

# 查看容器的 capabilities
docker run --rm \
    --cap-drop=ALL \
    --cap-add=NET_BIND_SERVICE \
    alpine cat /proc/self/status | grep Cap
```

### 5.3 --privileged：最大安全隐患

> **严重警告**：`--privileged` 模式几乎禁用所有安全限制！  

```bash
# 极其危险！不要在生产环境使用
docker run --privileged alpine

# --privileged 做了什么：
# 1. 授予所有 capabilities
# 2. 禁用 seccomp
# 3. 禁用 AppArmor/SELinux
# 4. 可以访问主机设备
# 5. 可以挂载主机文件系统
# 6. 容器逃逸变得非常容易
```

**--privileged 的正当使用场景**：

| 场景 | 是否正当 | 替代方案 |
|------|----------|----------|
| Docker-in-Docker | 有时 | 使用 Docker socket 挂载 |
| 需要访问 GPU | 不需要 | 使用 `--device` |
| 需要修改网络 | 不需要 | `--cap-add=NET_ADMIN` |
| 调试容器问题 | 临时可以 | 调试后移除 |

### 5.4 CAP_SYS_ADMIN 与容器逃逸

<!-- DIAGRAM: container-escape-risk -->
```
┌─────────────────────────────────────────────────────────────────┐
│                     CAP_SYS_ADMIN 容器逃逸风险                   │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│   正常容器（无 CAP_SYS_ADMIN）        危险容器（有 CAP_SYS_ADMIN） │
│   ┌─────────────────────┐            ┌─────────────────────┐    │
│   │     容器进程         │            │     容器进程         │    │
│   │        │             │            │        │             │    │
│   │        ↓             │            │        ↓             │    │
│   │   命名空间隔离        │            │   可以：              │    │
│   │   - mount namespace  │            │   - 挂载 /proc        │    │
│   │   - cgroup 限制      │            │   - 访问主机 cgroup   │    │
│   │   - 无法访问主机      │            │   - 创建设备节点      │    │
│   │                      │            │   - 可能逃逸到主机    │    │
│   └──────────┬───────────┘            └──────────┬───────────┘    │
│              │                                    │                │
│              │ 隔离                               │ 逃逸风险       │
│              ▼                                    ▼                │
│   ┌─────────────────────────────────────────────────────────┐    │
│   │                    主机内核                               │    │
│   └─────────────────────────────────────────────────────────┘    │
│                                                                 │
│   安全原则：给容器的 capabilities 越少越好                        │
└─────────────────────────────────────────────────────────────────┘
```
<!-- /DIAGRAM -->

### 5.5 容器安全最佳实践

```bash
# 1. 基础安全：丢弃所有，只加需要的
docker run \
    --cap-drop=ALL \
    --cap-add=NET_BIND_SERVICE \
    myapp

# 2. 中级安全：加上只读根文件系统
docker run \
    --cap-drop=ALL \
    --cap-add=NET_BIND_SERVICE \
    --read-only \
    --tmpfs /tmp \
    myapp

# 3. 高级安全：加上 seccomp 和用户映射
docker run \
    --cap-drop=ALL \
    --cap-add=NET_BIND_SERVICE \
    --read-only \
    --security-opt=no-new-privileges:true \
    --security-opt seccomp=default \
    --user 1000:1000 \
    myapp
```

**Kubernetes 中的 Capabilities**：

```yaml
# Pod 安全上下文示例
apiVersion: v1
kind: Pod
metadata:
  name: secure-pod
spec:
  securityContext:
    runAsNonRoot: true
    runAsUser: 1000
  containers:
  - name: app
    image: myapp
    securityContext:
      allowPrivilegeEscalation: false
      capabilities:
        drop:
          - ALL
        add:
          - NET_BIND_SERVICE
```

---

## 反模式：常见错误

### 错误 1：给脚本解释器设置 Capabilities

```bash
# 危险！给 Python/Bash 解释器设置 capabilities
sudo setcap 'cap_net_bind_service=+ep' /usr/bin/python3

# 后果：所有 Python 脚本都获得这个 capability
# 包括恶意脚本！

# 正确做法：
# - 使用 systemd AmbientCapabilities（只影响特定服务）
# - 或给编译后的二进制程序设置 capabilities
```

### 错误 2：使用 CAP_SYS_ADMIN "方便"

```bash
# 错误：懒得分析需要什么，直接给 SYS_ADMIN
docker run --cap-add=SYS_ADMIN myapp

# CAP_SYS_ADMIN 几乎等于 root
# 正确做法：分析具体需要什么 capability
strace -c myapp 2>&1 | head -20
# 根据系统调用确定需要的 capability
```

### 错误 3：容器使用 --privileged

```bash
# 错误：开发时用 --privileged "方便"
docker run --privileged myapp

# 后果：
# - 所有安全边界失效
# - 容器可以访问主机设备
# - 容器可以修改主机内核参数
# - 容器逃逸非常容易

# 正确做法：识别具体需求
# 需要访问 GPU？ → --device=/dev/nvidia0
# 需要网络管理？ → --cap-add=NET_ADMIN
# 需要调试？ → 临时添加 SYS_PTRACE，用完移除
```

### 错误 4：忘记 NoNewPrivileges

```bash
# 不完整的 systemd 配置
[Service]
User=myuser
AmbientCapabilities=CAP_NET_BIND_SERVICE
# 缺少 NoNewPrivileges=true

# 风险：服务进程可能通过 SUID 程序提权

# 完整配置
[Service]
User=myuser
AmbientCapabilities=CAP_NET_BIND_SERVICE
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
NoNewPrivileges=true
```

---

## 职场小贴士（Japan IT Context）

### Capabilities 相关术语

| 日语术语 | 含义 | 应用 |
|----------|------|------|
| 権限最小化（けんげんさいしょうか） | 最小权限原则 | Capabilities 的核心理念 |
| 特権分離（とっけんぶんり） | 权限分离 | 用 Capabilities 替代 root |
| コンテナセキュリティ | 容器安全 | --cap-drop, --privileged |
| セキュリティ境界（きょうかい） | 安全边界 | Bounding Set |

### 日本企业安全审计关注点

在日本企业的安全审计（セキュリティ監査）中，Capabilities 相关的检查点：

1. **SUID 程序审计**
   ```bash
   # 找出所有 SUID 程序
   find / -perm /6000 -type f 2>/dev/null
   # 问题：是否可以用 Capabilities 替代？
   ```

2. **容器权限审计**
   ```bash
   # 检查是否有 --privileged 容器
   docker ps --format '{{.Names}}' | while read name; do
       docker inspect "$name" --format '{{.HostConfig.Privileged}}'
   done
   ```

3. **服务权限审计**
   ```bash
   # 检查以 root 运行的服务
   ps aux | grep -E "^root" | grep -v "kernel"
   # 问题：是否可以用非 root 用户 + Capabilities？
   ```

### 安全报告模板

```markdown
## 権限最小化 監査結果

### 確認日: 20XX年XX月XX日
### 対象: production-server-01

| 項目 | 現状 | 推奨 | 判定 |
|------|------|------|------|
| root 運行サービス数 | 5 | 最小化 | 要改善 |
| --privileged コンテナ | 2 | 0 | NG |
| CAP_SYS_ADMIN 使用 | 3 | 最小化 | 要改善 |
| systemd Capabilities 使用 | 1 | 増加推奨 | 要改善 |

### 改善提案
1. nginx を Capabilities 使用方式に移行
2. --privileged コンテナを --cap-add 方式に移行
3. NoNewPrivileges=true を全サービスに適用
```

---

## 动手实验：完整实践（30 分钟）

### 实验 1：分析系统 Capabilities 现状

```bash
# 运行分析脚本
bash code/cap-demo.sh

# 脚本会：
# 1. 列出所有有 capabilities 的文件
# 2. 显示当前 shell 的 capabilities
# 3. 演示 capability 设置和使用
```

### 实验 2：创建安全的 systemd 服务

```bash
# 使用提供的模板
ls code/systemd-cap-service/

# 1. 安装服务
sudo cp code/systemd-cap-service/cap-demo.service /etc/systemd/system/
sudo systemctl daemon-reload

# 2. 启动并验证
sudo systemctl start cap-demo
sudo systemctl status cap-demo

# 3. 检查服务的 capabilities
PID=$(systemctl show cap-demo -p MainPID --value)
sudo cat /proc/$PID/status | grep Cap
sudo capsh --decode=$(sudo cat /proc/$PID/status | grep CapEff | awk '{print $2}')

# 4. 清理
sudo systemctl stop cap-demo
sudo rm /etc/systemd/system/cap-demo.service
```

### 实验 3：容器 Capabilities 对比

```bash
# 需要 Docker 或 Podman

# 1. 默认 capabilities
docker run --rm alpine cat /proc/self/status | grep Cap

# 2. 最小 capabilities
docker run --rm --cap-drop=ALL alpine cat /proc/self/status | grep Cap

# 3. 添加特定 capability
docker run --rm --cap-drop=ALL --cap-add=NET_BIND_SERVICE \
    alpine cat /proc/self/status | grep Cap

# 对比结果，理解 capabilities 的变化
```

---

## 检查清单

完成本课后，你应该能够：

- [ ] 解释为什么 Capabilities 比传统 root 权限更安全
- [ ] 使用 `getcap` 查看文件的 capabilities
- [ ] 使用 `setcap` 设置文件的 capabilities
- [ ] 使用 `capsh` 解码进程的 capabilities
- [ ] 解释 Effective、Permitted、Bounding 集合的区别
- [ ] 配置 systemd 服务使用 `AmbientCapabilities`
- [ ] 解释 `NoNewPrivileges=true` 的重要性
- [ ] 使用 `--cap-drop` 和 `--cap-add` 控制容器权限
- [ ] 解释为什么 `CAP_SYS_ADMIN` 和 `--privileged` 是危险的
- [ ] 在安全审计中检查 Capabilities 使用情况

---

## 本课小结

| 概念 | 命令/配置 | 记忆点 |
|------|-----------|--------|
| 查看文件能力 | `getcap /path` | 检查二进制权限 |
| 设置文件能力 | `setcap cap_xxx=+ep /path` | 替代 SUID |
| 查看进程能力 | `cat /proc/PID/status \| grep Cap` | 运行时检查 |
| 解码能力 | `capsh --decode=<hex>` | 理解 hex 值 |
| systemd 配置 | `AmbientCapabilities=` | 生产环境首选 |
| 禁止提权 | `NoNewPrivileges=true` | 安全加固必备 |
| 容器丢弃能力 | `--cap-drop=ALL` | 最小权限 |
| 容器添加能力 | `--cap-add=NET_BIND_SERVICE` | 按需添加 |

**核心理念**：

```
传统模式：需要特权 → 给 root → 获得所有权限 → 风险巨大
Capabilities：需要特权 → 分析需求 → 只给需要的能力 → 风险最小
```

**危险警告**：

```
CAP_SYS_ADMIN ≈ root
--privileged = 禁用所有安全边界
永远不要因为"方便"使用它们！
```

---

## 延伸阅读

- [man capabilities](https://man7.org/linux/man-pages/man7/capabilities.7.html) - 官方文档
- [Docker Security: Capabilities](https://docs.docker.com/engine/security/#linux-kernel-capabilities) - Docker 安全指南
- [systemd Security Options](https://www.freedesktop.org/software/systemd/man/systemd.exec.html#Capabilities) - systemd 文档
- [RHEL Security Guide: Capabilities](https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/9/html/security_hardening/index) - Red Hat 安全加固
- 相关课程：[LX11 - 容器基础](../../containers/) - 深入容器安全
- 上一课：[05 - SELinux 进阶](../05-selinux-advanced/) - Booleans 与自定义策略

---

## 系列导航

[上一课：05 - SELinux 进阶](../05-selinux-advanced/) | [系列首页](../) | [下一课：07 - auditd 审计系统 -->](../07-auditd/)
