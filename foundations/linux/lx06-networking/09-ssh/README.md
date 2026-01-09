# 09 - SSH 深入

> **目标**：掌握 SSH 高级配置，包括密钥管理、跳板机、端口转发和安全加固  
> **前置**：了解基础网络和抓包分析（01-08 课）  
> **时间**：60 分钟  
> **环境**：任意 Linux 发行版（Ubuntu, AlmaLinux, Amazon Linux 均可）  

---

## 将学到的内容

1. 理解 SSH 密钥认证机制
2. 配置 ~/.ssh/config 简化连接
3. 使用 ProxyJump 穿越跳板机
4. 配置端口转发（Local、Remote、Dynamic）
5. 使用 ControlMaster 复用连接
6. SSH 安全加固

---

## Step 1 - 先跑起来：10 秒连接服务器（5 分钟）

> **目标**：体验 SSH config 的威力 - 从输入一长串命令到只敲一个单词。  

### 1.1 传统方式（麻烦）

```bash
# 每次都要输入一堆参数
ssh -i ~/.ssh/my-key.pem -p 2222 ec2-user@ec2-13-115-xxx-xxx.ap-northeast-1.compute.amazonaws.com
```

### 1.2 配置后（优雅）

先创建配置文件：

```bash
mkdir -p ~/.ssh
chmod 700 ~/.ssh
cat >> ~/.ssh/config << 'EOF'
Host dev
    HostName ec2-13-115-xxx-xxx.ap-northeast-1.compute.amazonaws.com
    User ec2-user
    Port 2222
    IdentityFile ~/.ssh/my-key.pem
EOF
chmod 600 ~/.ssh/config
```

现在只需：

```bash
ssh dev
```

**一个单词，搞定连接！** 这就是 SSH config 的魅力。

### 1.3 更进一步：跳板机穿透

日本企业常见架构：外部只能访问跳板机（踏み台），内部服务器需要"跳"进去。

```bash
# 传统方式：先登录跳板机，再登录目标
ssh jump-host
ssh internal-server  # 在跳板机上再 ssh

# 配置后：一步到位
ssh internal
```

配置：

```bash
cat >> ~/.ssh/config << 'EOF'
Host jump
    HostName jump.example.com
    User admin

Host internal
    HostName 10.0.1.50
    User ec2-user
    ProxyJump jump
EOF
```

**两跳变一跳！** 接下来让我们深入理解这些配置。

---

## Step 2 - 发生了什么？SSH 密钥认证机制（10 分钟）

### 2.1 密钥对的本质

SSH 密钥认证基于非对称加密：

<!-- DIAGRAM: ssh-key-authentication -->
```
SSH 密钥认证流程
════════════════════════════════════════════════════════════════════

你的电脑                                           服务器
────────                                           ──────

  ┌─────────────────┐                        ┌─────────────────┐
  │   私钥 (Private) │                        │ authorized_keys │
  │   id_ed25519     │                        │ 存放公钥列表     │
  │   绝对不能泄露！  │                        │                 │
  └────────┬────────┘                        └────────┬────────┘
           │                                          │
           │  1. 客户端发起连接请求                    │
           │ ──────────────────────────────────────▶ │
           │                                          │
           │  2. 服务器发送随机挑战（challenge）        │
           │ ◀────────────────────────────────────── │
           │                                          │
           │  3. 客户端用私钥签名                      │
           │ ──────────────────────────────────────▶ │
           │     "我有配对的私钥"                      │
           │                                          │
           │  4. 服务器用公钥验证签名                  │
           │     匹配！允许登录                        │
           │ ◀────────────────────────────────────── │
           │                                          │
           ▼                                          ▼
        认证成功                                   会话建立

关键点：
• 私钥永远不离开你的电脑
• 公钥可以放在任何你想登录的服务器
• 即使公钥泄露，没有私钥也无法登录
```
<!-- /DIAGRAM -->

### 2.2 密钥生成最佳实践

```bash
# 推荐：Ed25519 算法（更快、更安全）
ssh-keygen -t ed25519 -C "your-email@example.com"

# 如果需要兼容旧系统：RSA 4096 位
ssh-keygen -t rsa -b 4096 -C "your-email@example.com"
```

生成过程：

```
Generating public/private ed25519 key pair.
Enter file in which to save the key (/home/user/.ssh/id_ed25519):
Enter passphrase (empty for no passphrase): [输入密码短语]
Enter same passphrase again:
Your identification has been saved in /home/user/.ssh/id_ed25519
Your public key has been saved in /home/user/.ssh/id_ed25519.pub
```

**密码短语（passphrase）**：
- 强烈建议设置！即使私钥被盗，没有密码短语也无法使用
- 使用 ssh-agent 可以避免每次都输入

### 2.3 密钥分发

```bash
# 方法 1：ssh-copy-id（推荐）
ssh-copy-id -i ~/.ssh/id_ed25519.pub user@server

# 方法 2：手动复制
cat ~/.ssh/id_ed25519.pub | ssh user@server 'mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys'

# 方法 3：直接编辑（云服务器初始化时）
# 在 authorized_keys 中添加公钥内容
```

### 2.4 权限要求（关键！）

SSH 对权限非常严格，权限不对会直接拒绝：

```bash
# 正确的权限设置
chmod 700 ~/.ssh              # 目录：仅所有者可访问
chmod 600 ~/.ssh/id_ed25519   # 私钥：仅所有者可读写
chmod 644 ~/.ssh/id_ed25519.pub  # 公钥：可被其他人读取
chmod 600 ~/.ssh/authorized_keys  # 授权密钥：仅所有者可读写
chmod 600 ~/.ssh/config       # 配置文件：仅所有者可读写
```

---

## Step 3 - ~/.ssh/config 完全指南（10 分钟）

### 3.1 基本结构

```bash
# ~/.ssh/config

# 全局默认设置（对所有 Host 生效）
Host *
    ServerAliveInterval 60
    ServerAliveCountMax 3
    AddKeysToAgent yes

# 特定主机配置
Host dev
    HostName dev.example.com
    User developer
    Port 22
    IdentityFile ~/.ssh/dev-key
```

### 3.2 常用配置项

| 配置项 | 说明 | 示例 |
|--------|------|------|
| `HostName` | 真实主机名/IP | `10.0.1.50` |
| `User` | 登录用户名 | `ec2-user` |
| `Port` | SSH 端口 | `2222` |
| `IdentityFile` | 私钥路径 | `~/.ssh/my-key.pem` |
| `ProxyJump` | 跳板机 | `jump-host` |
| `LocalForward` | 本地端口转发 | `8080 localhost:80` |
| `RemoteForward` | 远程端口转发 | `9090 localhost:3000` |
| `DynamicForward` | SOCKS 代理 | `1080` |
| `ServerAliveInterval` | 保活间隔（秒） | `60` |

### 3.3 Host 别名的威力

```bash
# 一个主机多个别名
Host dev development dev-server
    HostName dev.example.com
    User developer

# 通配符匹配
Host *.prod
    User admin
    IdentityFile ~/.ssh/prod-key

Host web.prod
    HostName 10.0.1.10

Host db.prod
    HostName 10.0.1.20
```

使用：

```bash
ssh dev          # 或 ssh development，或 ssh dev-server
ssh web.prod     # 使用 admin 用户和 prod-key
ssh db.prod
```

### 3.4 实用配置模板

```bash
# ~/.ssh/config - 生产环境推荐配置

# 全局设置
Host *
    # 保持连接活跃（防止超时断开）
    ServerAliveInterval 60
    ServerAliveCountMax 3
    # 连接复用（加速多次连接）
    ControlMaster auto
    ControlPath ~/.ssh/sockets/%r@%h-%p
    ControlPersist 600
    # 自动添加密钥到 agent
    AddKeysToAgent yes
    # 压缩传输（慢网络有帮助）
    Compression yes

# 跳板机
Host jump
    HostName jump.company.com
    User admin
    IdentityFile ~/.ssh/jump-key
    # 跳板机不需要转发 agent
    ForwardAgent no

# 内部服务器（通过跳板机访问）
Host internal-*
    User ec2-user
    ProxyJump jump
    IdentityFile ~/.ssh/internal-key

Host internal-web
    HostName 10.0.1.10

Host internal-db
    HostName 10.0.1.20

# AWS 服务器
Host aws-*
    User ec2-user
    IdentityFile ~/.ssh/aws-key.pem

Host aws-tokyo
    HostName ec2-xxx.ap-northeast-1.compute.amazonaws.com
```

创建 socket 目录：

```bash
mkdir -p ~/.ssh/sockets
chmod 700 ~/.ssh/sockets
```

---

## Step 4 - ProxyJump：跳板机穿透（10 分钟）

### 4.1 为什么需要跳板机？

日本企业网络架构的标准做法：

<!-- DIAGRAM: bastion-architecture -->
```
跳板机（踏み台サーバ）架构
════════════════════════════════════════════════════════════════════

    互联网                    DMZ 区域                 内部网络
    ────────                  ─────────                ────────────

                          ┌─────────────┐
    你的电脑               │   跳板机    │          ┌─────────────┐
   ┌─────────┐    SSH     │  (Bastion)  │   SSH    │  Web 服务器 │
   │         │ ──────────▶│ 10.0.0.10   │─────────▶│  10.0.1.10  │
   │         │    :22     │             │          └─────────────┘
   │         │            │  唯一对外    │
   │         │            │  开放 SSH    │          ┌─────────────┐
   └─────────┘            │             │   SSH    │  DB 服务器  │
                          │             │─────────▶│  10.0.1.20  │
                          └─────────────┘          └─────────────┘

   安全策略：
   • 跳板机是唯一入口（攻击面最小化）
   • 内部服务器没有公网 IP
   • 所有 SSH 会话都经过跳板机（审计日志）
   • 跳板机可以设置 MFA（多因素认证）
```
<!-- /DIAGRAM -->

### 4.2 传统方式 vs ProxyJump

**传统方式**（麻烦、不安全）：

```bash
# 方法 1：两步登录
ssh jump-host
# 在跳板机上再执行
ssh internal-server

# 方法 2：ProxyCommand（旧写法）
ssh -o ProxyCommand="ssh -W %h:%p jump-host" internal-server
```

**现代方式**（推荐）：

```bash
# 命令行方式
ssh -J jump-host internal-server

# 多跳穿透
ssh -J jump1,jump2 target-server
```

### 4.3 配置文件方式

```bash
# ~/.ssh/config

Host jump
    HostName jump.company.com
    User admin

Host internal
    HostName 10.0.1.50
    User ec2-user
    ProxyJump jump

# 多跳场景
Host deep-internal
    HostName 192.168.1.100
    User app
    ProxyJump jump,internal
```

使用：

```bash
ssh internal       # 自动通过 jump 跳转
ssh deep-internal  # 自动通过 jump -> internal 跳转
```

### 4.4 文件传输（通过跳板机）

```bash
# scp 通过跳板机
scp -J jump local-file.txt internal:/tmp/

# rsync 通过跳板机
rsync -avz -e "ssh -J jump" local-dir/ internal:/remote-dir/
```

---

## Step 5 - 端口转发三剑客（15 分钟）

### 5.1 Local Port Forwarding（-L）

**场景**：访问内网服务（如数据库、Web 管理界面）

<!-- DIAGRAM: local-port-forwarding -->
```
Local Port Forwarding（本地端口转发）
════════════════════════════════════════════════════════════════════

命令：ssh -L 3306:db-server:3306 jump-host

你的电脑                    跳板机                    数据库服务器
─────────                   ──────                    ────────────

┌─────────────┐         ┌─────────────┐         ┌─────────────┐
│             │         │             │         │             │
│  localhost  │ ──SSH───▶  jump-host  │────────▶│  db-server  │
│  :3306      │ tunnel  │             │         │  :3306      │
│             │         │             │         │             │
└──────┬──────┘         └─────────────┘         └─────────────┘
       │
       │ mysql -h 127.0.0.1 -P 3306
       │
┌──────┴──────┐
│  MySQL      │
│  客户端     │
└─────────────┘

工作原理：
1. 本机监听 3306 端口
2. 连接 localhost:3306 的流量被转发到 SSH 隧道
3. 跳板机将流量转发到 db-server:3306
4. 就像直接连接数据库一样！
```
<!-- /DIAGRAM -->

**使用示例**：

```bash
# 建立隧道（-N 不执行命令，-f 后台运行）
ssh -L 3306:db-server:3306 -N -f jump-host

# 现在可以用本地工具连接
mysql -h 127.0.0.1 -P 3306 -u dbuser -p

# 或者连接远程的 Web 管理界面
ssh -L 8080:internal-web:80 jump-host
# 浏览器访问 http://localhost:8080
```

**配置文件方式**：

```bash
Host db-tunnel
    HostName jump.company.com
    User admin
    LocalForward 3306 db-server:3306
    LocalForward 6379 redis-server:6379
```

### 5.2 Remote Port Forwarding（-R）

**场景**：让外部访问你的本地服务（如展示开发中的网站）

<!-- DIAGRAM: remote-port-forwarding -->
```
Remote Port Forwarding（远程端口转发）
════════════════════════════════════════════════════════════════════

命令：ssh -R 8080:localhost:3000 remote-server

你的电脑                    远程服务器                  同事
─────────                   ──────────                  ────

┌─────────────┐         ┌─────────────┐         ┌─────────────┐
│             │         │             │         │             │
│  localhost  │ ◀──SSH───  remote     │ ◀───────│   同事      │
│  :3000      │ tunnel  │  :8080      │ 访问    │   浏览器    │
│  开发服务器 │         │             │         │             │
└─────────────┘         └─────────────┘         └─────────────┘

工作原理：
1. 远程服务器监听 8080 端口
2. 同事访问 remote-server:8080
3. 流量通过 SSH 隧道转发到你的电脑
4. 你的本地开发服务器响应请求

用途：
• 展示本地开发的网站给同事看
• 临时对外暴露本地服务
• 调试 Webhook 回调
```
<!-- /DIAGRAM -->

**使用示例**：

```bash
# 本地运行开发服务器
npm run dev  # 监听 localhost:3000

# 建立反向隧道
ssh -R 8080:localhost:3000 remote-server

# 同事访问 http://remote-server:8080 就能看到你的开发页面
```

**注意**：默认情况下，-R 绑定到远程服务器的 127.0.0.1。要绑定到 0.0.0.0（允许外部访问），需要：

```bash
# 1. 修改远程服务器的 sshd_config
# GatewayPorts yes

# 2. 使用绑定地址
ssh -R 0.0.0.0:8080:localhost:3000 remote-server
```

### 5.3 Dynamic Port Forwarding（-D）

**场景**：SOCKS 代理，通过服务器访问任意网站

<!-- DIAGRAM: dynamic-port-forwarding -->
```
Dynamic Port Forwarding（动态端口转发 / SOCKS 代理）
════════════════════════════════════════════════════════════════════

命令：ssh -D 1080 jump-host

你的电脑                    跳板机                    目标网站
─────────                   ──────                    ────────

┌─────────────┐         ┌─────────────┐         ┌─────────────┐
│             │         │             │         │  internal   │
│  浏览器     │ ──SOCKS5──▶ jump-host │────────▶│  .company   │
│  代理设置:  │ tunnel  │             │         │  .com       │
│  127.0.0.1  │         │             │         └─────────────┘
│  :1080      │         │             │
└─────────────┘         │             │         ┌─────────────┐
                        │             │────────▶│  google.com │
                        └─────────────┘         └─────────────┘

工作原理：
1. 本机监听 1080 端口作为 SOCKS5 代理
2. 配置浏览器使用这个代理
3. 所有 HTTP/HTTPS 请求通过 SSH 隧道
4. 从跳板机发出请求（用跳板机的 IP）

用途：
• 访问内网网站（无需知道具体 IP）
• 翻墙（如果远程服务器在海外）
• 匿名浏览（隐藏真实 IP）
```
<!-- /DIAGRAM -->

**使用示例**：

```bash
# 建立 SOCKS 代理
ssh -D 1080 -N -f jump-host

# 配置浏览器代理
# Firefox: Settings > Network Settings > Manual proxy > SOCKS Host: 127.0.0.1, Port: 1080

# 或使用 curl 测试
curl --socks5 127.0.0.1:1080 http://internal.company.com
```

### 5.4 端口转发对比总结

| 类型 | 参数 | 方向 | 典型场景 |
|------|------|------|----------|
| **Local** | `-L` | 本地 -> 远程 | 访问内网数据库、Web 管理界面 |
| **Remote** | `-R` | 远程 -> 本地 | 展示本地开发站点、Webhook 调试 |
| **Dynamic** | `-D` | 本地 SOCKS 代理 | 访问内网任意服务、翻墙 |

---

## Step 6 - ControlMaster：连接复用（5 分钟）

### 6.1 问题：频繁连接很慢

每次 SSH 连接都需要：
1. TCP 三次握手
2. SSH 密钥交换
3. 用户认证

如果频繁连接同一台服务器（如使用 scp、rsync），这些开销会累积。

### 6.2 解决方案：ControlMaster

```bash
# ~/.ssh/config

Host *
    ControlMaster auto
    ControlPath ~/.ssh/sockets/%r@%h-%p
    ControlPersist 600
```

配置说明：

| 配置项 | 说明 |
|--------|------|
| `ControlMaster auto` | 自动复用已有连接 |
| `ControlPath` | 控制套接字路径（%r=用户, %h=主机, %p=端口） |
| `ControlPersist 600` | 断开后保持 600 秒（10 分钟） |

### 6.3 效果对比

```bash
# 创建 socket 目录
mkdir -p ~/.ssh/sockets
chmod 700 ~/.ssh/sockets

# 第一次连接（正常速度）
time ssh dev 'echo hello'  # 约 1-2 秒

# 第二次连接（瞬间完成）
time ssh dev 'echo hello'  # 约 0.1 秒
```

### 6.4 手动管理连接

```bash
# 检查控制连接状态
ssh -O check dev

# 手动关闭控制连接
ssh -O stop dev

# 列出所有控制套接字
ls -la ~/.ssh/sockets/
```

---

## Step 7 - 连接调试：ssh -vvv（5 分钟）

当 SSH 连接失败时，调试信息是你的救命稻草。

### 7.1 调试级别

```bash
# 一级调试（基本信息）
ssh -v user@host

# 二级调试（更详细）
ssh -vv user@host

# 三级调试（最详细）
ssh -vvv user@host
```

### 7.2 常见问题定位

**问题 1：密钥认证失败**

```bash
ssh -vvv user@host 2>&1 | grep -E "(Trying|Offering|Authentications)"
```

```
debug1: Trying private key: /home/user/.ssh/id_ed25519
debug1: Offering public key: /home/user/.ssh/id_ed25519
debug1: Authentications that can continue: publickey
debug1: No more authentication methods to try.
```

**可能原因**：
- 服务器上没有对应的公钥
- authorized_keys 权限不对

**问题 2：连接超时**

```bash
ssh -vvv user@host 2>&1 | grep -E "(Connecting|Connection)"
```

```
debug1: Connecting to host [10.0.1.50] port 22.
debug1: Connection timed out
```

**可能原因**：
- 防火墙阻断
- 主机不可达
- 端口不对

---

## Step 8 - 故障实验室：SSH 权限拒绝（10 分钟）

> **场景**：新同事配置 SSH 密钥后仍然无法登录，报错 "Permission denied (publickey)"  

### 8.1 模拟问题

```bash
# 在服务器上，故意设置错误权限
chmod 777 ~/.ssh/authorized_keys
```

### 8.2 症状

```bash
# 尝试连接
ssh user@server
```

```
user@server: Permission denied (publickey).
```

### 8.3 定位根因

**Step 1：客户端调试**

```bash
ssh -vvv user@server 2>&1 | tail -20
```

```
debug1: Offering public key: /home/user/.ssh/id_ed25519
debug3: send packet: type 50
debug2: we sent a publickey packet, wait for reply
debug3: receive packet: type 51
debug1: Authentications that can continue: publickey
debug1: No more authentication methods to try.
```

密钥发送成功，但服务器拒绝了。问题在服务器端。

**Step 2：服务器日志**

```bash
# 查看 SSH 认证日志
sudo tail -20 /var/log/secure  # RHEL/CentOS/Amazon Linux
# 或
sudo tail -20 /var/log/auth.log  # Ubuntu/Debian
```

```
Jan 05 10:30:45 server sshd[12345]: Authentication refused: bad ownership or modes for file /home/user/.ssh/authorized_keys
```

**根因找到了！** authorized_keys 权限太松。

### 8.4 修复

```bash
# 修复权限
chmod 600 ~/.ssh/authorized_keys
chmod 700 ~/.ssh
```

### 8.5 预防检查脚本

```bash
#!/bin/bash
# ssh-permission-check.sh

echo "SSH 权限检查"
echo "============"

# 检查 .ssh 目录
SSH_DIR="$HOME/.ssh"
DIR_PERM=$(stat -c %a "$SSH_DIR" 2>/dev/null)

if [ "$DIR_PERM" != "700" ]; then
    echo "[错误] ~/.ssh 权限是 $DIR_PERM，应该是 700"
else
    echo "[正常] ~/.ssh 权限 700"
fi

# 检查 authorized_keys
AUTH_KEYS="$SSH_DIR/authorized_keys"
if [ -f "$AUTH_KEYS" ]; then
    KEY_PERM=$(stat -c %a "$AUTH_KEYS" 2>/dev/null)
    if [ "$KEY_PERM" != "600" ]; then
        echo "[错误] authorized_keys 权限是 $KEY_PERM，应该是 600"
    else
        echo "[正常] authorized_keys 权限 600"
    fi
fi

# 检查私钥
for key in "$SSH_DIR"/id_*; do
    if [[ "$key" != *.pub && -f "$key" ]]; then
        KEY_PERM=$(stat -c %a "$key" 2>/dev/null)
        if [ "$KEY_PERM" != "600" ]; then
            echo "[错误] $key 权限是 $KEY_PERM，应该是 600"
        else
            echo "[正常] $key 权限 600"
        fi
    fi
done
```

---

## Step 9 - SSH 安全加固（5 分钟）

### 9.1 服务端加固（/etc/ssh/sshd_config）

```bash
# 推荐的安全配置

# 禁用 root 直接登录
PermitRootLogin no

# 只允许密钥认证
PasswordAuthentication no
PubkeyAuthentication yes

# 禁用空密码
PermitEmptyPasswords no

# 限制允许登录的用户
AllowUsers admin ec2-user

# 限制最大认证尝试次数
MaxAuthTries 3

# 设置登录超时
LoginGraceTime 60

# 禁用 X11 转发（如果不需要）
X11Forwarding no

# 使用更安全的算法
KexAlgorithms curve25519-sha256@libssh.org,diffie-hellman-group16-sha512
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com
MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com
```

修改后重启 SSH：

```bash
sudo sshd -t  # 检查配置语法
sudo systemctl restart sshd
```

### 9.2 Match Blocks：条件配置

```bash
# 对特定用户/IP 应用不同规则

# 默认配置
PasswordAuthentication no

# 来自内网的连接允许密码认证
Match Address 10.0.0.0/8,192.168.0.0/16
    PasswordAuthentication yes

# 特定用户强制使用密钥
Match User admin
    PasswordAuthentication no
    PubkeyAuthentication yes
```

### 9.3 Agent Forwarding 的安全风险

```bash
# 危险！不要在不信任的跳板机上使用 Agent Forwarding
ssh -A untrusted-jump-host  # 跳板机管理员可以使用你的密钥！
```

**安全替代方案**：使用 ProxyJump

```bash
# 安全：私钥始终在你的电脑上
ssh -J jump-host target-server
```

---

## Mini Project：跳板机与隧道配置

### 项目说明

配置一个完整的企业级 SSH 环境：
1. 通过跳板机访问内部服务器
2. 建立到内部数据库的端口转发
3. 使用 ControlMaster 优化连接速度

### 完整配置文件

```bash
# ~/.ssh/config - 企业级配置模板

# =============================================================================
# 全局设置
# =============================================================================
Host *
    # 连接保活
    ServerAliveInterval 60
    ServerAliveCountMax 3

    # 连接复用（大幅提升多次连接速度）
    ControlMaster auto
    ControlPath ~/.ssh/sockets/%r@%h-%p
    ControlPersist 600

    # 自动添加密钥到 agent
    AddKeysToAgent yes

    # 首次连接自动添加主机指纹
    StrictHostKeyChecking accept-new

    # 压缩传输
    Compression yes

# =============================================================================
# 跳板机（踏み台サーバ）
# =============================================================================
Host jump bastion
    HostName jump.company.com
    User admin
    IdentityFile ~/.ssh/jump-key
    # 跳板机不转发 agent（安全考虑）
    ForwardAgent no

# =============================================================================
# 内部服务器（通过跳板机访问）
# =============================================================================
Host web
    HostName 10.0.1.10
    User ec2-user
    ProxyJump jump
    IdentityFile ~/.ssh/internal-key

Host app
    HostName 10.0.1.20
    User ec2-user
    ProxyJump jump
    IdentityFile ~/.ssh/internal-key

Host db
    HostName 10.0.1.30
    User ec2-user
    ProxyJump jump
    IdentityFile ~/.ssh/internal-key

# =============================================================================
# 数据库隧道（快捷方式）
# =============================================================================
Host db-tunnel
    HostName 10.0.1.30
    User ec2-user
    ProxyJump jump
    IdentityFile ~/.ssh/internal-key
    # MySQL 端口转发
    LocalForward 3306 localhost:3306
    # 不执行命令，仅建立隧道
    RequestTTY no

Host redis-tunnel
    HostName 10.0.1.30
    User ec2-user
    ProxyJump jump
    IdentityFile ~/.ssh/internal-key
    LocalForward 6379 localhost:6379
    RequestTTY no

# =============================================================================
# 开发环境 SOCKS 代理
# =============================================================================
Host socks-proxy
    HostName jump.company.com
    User admin
    IdentityFile ~/.ssh/jump-key
    DynamicForward 1080
    RequestTTY no
```

### 使用方法

```bash
# 1. 创建 socket 目录
mkdir -p ~/.ssh/sockets
chmod 700 ~/.ssh/sockets

# 2. 日常登录
ssh web     # 一步登录内部 Web 服务器
ssh db      # 一步登录数据库服务器

# 3. 建立数据库隧道
ssh -N -f db-tunnel
mysql -h 127.0.0.1 -P 3306 -u dbuser -p

# 4. 建立 SOCKS 代理
ssh -N -f socks-proxy
curl --socks5 127.0.0.1:1080 http://internal.company.com

# 5. 文件传输
scp local-file.txt web:/tmp/
rsync -avz local-dir/ app:/var/www/html/
```

### 验证配置

```bash
# 测试连接（不实际登录）
ssh -o BatchMode=yes -o ConnectTimeout=5 web echo "OK"

# 检查隧道状态
ss -tuln | grep -E "3306|6379|1080"

# 检查控制连接
ssh -O check web
```

---

## 职场小贴士

### 日本 IT 常用术语

| 日本語 | 中文 | 场景 |
|--------|------|------|
| 踏み台サーバ | 跳板机/堡垒机 | SSH 架构设计 |
| ポートフォワーディング | 端口转发 | 访问内网服务 |
| 公開鍵認証 | 公钥认证 | SSH 密钥登录 |
| 接続の多重化 | 连接复用 | ControlMaster |
| セキュリティ強化 | 安全加固 | sshd_config 配置 |

### 面试常见问题

**Q: SSH のポートフォワーディングの種類は？**

A: 3 種類あります。Local (-L) はローカルポートから接続先サーバ経由でリモートサービスに接続。Remote (-R) はリモートサーバのポートから SSH クライアント経由でローカルサービスに接続。Dynamic (-D) は SOCKS プロキシとして動作し、任意の宛先に接続できます。

**Q: ProxyJump とは？**

A: 踏み台サーバ経由の接続を簡潔に設定する機能です。`ssh -J jump target` または config で `ProxyJump jump` を指定します。従来の ProxyCommand より設定が簡単で、多段ジャンプも容易です。秘密鍵はローカルに残るため、AgentForwarding より安全です。

**Q: SSH 認証に失敗した場合のトラブルシューティング手順は？**

A: まず `ssh -vvv` で詳細ログを確認。クライアント側で鍵が送信されているか確認し、サーバ側の `/var/log/secure` または `/var/log/auth.log` でエラーメッセージを確認します。よくある原因は `~/.ssh` のパーミッション（700）や `authorized_keys` のパーミッション（600）が正しくない場合です。

---

## 本课小结

| 你学到的 | 命令/配置 |
|----------|-----------|
| 密钥生成 | `ssh-keygen -t ed25519` |
| SSH 配置 | `~/.ssh/config` |
| Host 别名 | `Host dev` + `HostName xxx` |
| 跳板机穿透 | `ProxyJump` 或 `-J` |
| 本地端口转发 | `-L 3306:db:3306` |
| 远程端口转发 | `-R 8080:localhost:3000` |
| SOCKS 代理 | `-D 1080` |
| 连接复用 | `ControlMaster auto` |
| 连接调试 | `ssh -vvv` |

**核心理念**：

```
SSH 不只是远程登录工具，而是安全隧道的瑞士军刀

记住：
• ~/.ssh/config 是你的效率倍增器
• ProxyJump 比 Agent Forwarding 更安全
• 权限问题查 /var/log/secure
• 连接问题用 ssh -vvv
```

---

## 反模式警示

| 错误做法 | 正确做法 |
|----------|----------|
| 直接 SSH 而不使用跳板机 | 通过跳板机访问内部服务器（安全审计） |
| .ssh 目录权限不是 700 | `chmod 700 ~/.ssh` |
| authorized_keys 权限不是 600 | `chmod 600 ~/.ssh/authorized_keys` |
| 使用 Agent Forwarding 到不信任的跳板机 | 使用 ProxyJump（私钥不离开本机） |
| 每次输入一长串 SSH 命令 | 配置 ~/.ssh/config 使用别名 |
| 允许 root 密码登录 | `PermitRootLogin no` + 密钥认证 |

---

## 检查清单

在继续下一课之前，确认你能：

- [ ] 生成 Ed25519 密钥对并分发公钥
- [ ] 配置 ~/.ssh/config 使用 Host 别名
- [ ] 使用 ProxyJump 通过跳板机连接内部服务器
- [ ] 建立 Local Port Forwarding 访问内网数据库
- [ ] 建立 Dynamic Port Forwarding (SOCKS) 代理
- [ ] 配置 ControlMaster 实现连接复用
- [ ] 使用 ssh -vvv 调试连接问题
- [ ] 检查并修复 SSH 权限问题
- [ ] 解释三种端口转发的区别和使用场景

---

## 延伸阅读

- [OpenSSH 官方文档](https://www.openssh.com/manual.html)
- [SSH Config 完整参考](https://man.openbsd.org/ssh_config)
- [SSHD Config 完整参考](https://man.openbsd.org/sshd_config)
- [SSH Tunneling 详解 - DigitalOcean](https://www.digitalocean.com/community/tutorials/how-to-set-up-ssh-tunneling-on-a-vps)

---

## 下一步

你已经掌握了 SSH 的高级配置和端口转发技巧。接下来，让我们深入 Linux 网络命名空间，理解容器网络的底层原理。

[10 - 网络命名空间 ->](../10-namespaces/)

---

## 系列导航

[<- 08 - tcpdump 与抓包分析](../08-tcpdump/) | [Home](/) | [10 - 网络命名空间 ->](../10-namespaces/)
