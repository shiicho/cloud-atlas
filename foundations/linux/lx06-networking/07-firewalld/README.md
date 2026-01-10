# 07 - firewalld 区域

> **目标**：使用 firewalld 的 zone 概念管理防火墙，实现基于信任级别的访问控制  
> **前置**：了解 nftables 基础（06 课）  
> **时间**：⚡ 12 分钟（速读）/ 🔬 50 分钟（完整实操）  
> **环境**：RHEL/CentOS/AlmaLinux/Fedora（Ubuntu 需额外安装 firewalld）  

---

## 将学到的内容

1. 理解 firewalld 架构（zones、services、rich rules）
2. 使用 firewall-cmd 管理防火墙
3. 配置区域和服务
4. 使用 rich rules 实现复杂规则
5. 理解 firewalld 与 nftables 的关系

---

## Step 1 - 先跑起来：快速防火墙配置（5 分钟）

> **目标**：先"尝到" firewalld 的便捷，再理解原理。  

打开终端，运行这几条命令：

### 1.1 查看当前防火墙状态

```bash
# 查看 firewalld 是否运行
sudo systemctl status firewalld

# 查看当前区域和规则
sudo firewall-cmd --list-all
```

```
public (active)
  target: default
  icmp-block-inversion: no
  interfaces: eth0
  sources:
  services: cockpit dhcpv6-client ssh
  ports:
  protocols:
  forward: yes
  masquerade: no
  forward-ports:
  source-ports:
  icmp-blocks:
  rich rules:
```

**你看到了**：当前活动的 zone（public）、绑定的接口（eth0）、允许的服务（ssh 等）。

### 1.2 开放 HTTP 服务

```bash
# 临时添加 HTTP 服务（重启后失效）
sudo firewall-cmd --add-service=http

# 验证
sudo firewall-cmd --list-services
```

```
cockpit dhcpv6-client http ssh
```

### 1.3 开放自定义端口

```bash
# 临时添加端口 8080/tcp
sudo firewall-cmd --add-port=8080/tcp

# 验证
sudo firewall-cmd --list-ports
```

```
8080/tcp
```

---

**3 条命令，完成防火墙配置！**

| 命令 | 用途 |
|------|------|
| `firewall-cmd --list-all` | 查看当前配置 |
| `firewall-cmd --add-service=http` | 开放服务 |
| `firewall-cmd --add-port=8080/tcp` | 开放端口 |

比直接写 nftables 规则简单得多，对吧？接下来让我们理解背后的原理。

---

## Step 2 - 安全第一：防止锁定自己（必读）

> **警告**：防火墙配置错误可能导致你被锁在服务器外面！  

在修改任何防火墙规则前，请牢记以下安全措施：

### 2.1 方法一：使用 --timeout 参数（推荐）

```bash
# 添加规则，5 分钟后自动删除
sudo firewall-cmd --add-port=22/tcp --timeout=300

# 规则会在 300 秒后自动消失
# 如果新规则把你锁在外面，等 5 分钟就恢复了
```

**这是 firewalld 的安全网**：`--timeout` 让规则在指定秒数后自动删除。

### 2.2 方法二：先测试临时规则

```bash
# 步骤 1：不加 --permanent，规则临时生效
sudo firewall-cmd --remove-service=ssh

# 步骤 2：测试是否还能连接（从另一个终端）
ssh user@server

# 步骤 3：如果还能连接，再加 --permanent
sudo firewall-cmd --permanent --remove-service=ssh
sudo firewall-cmd --reload
```

### 2.3 永远不要做的事

```bash
# 危险！永远不要在唯一的 SSH 连接上执行：
sudo firewall-cmd --permanent --remove-service=ssh
sudo firewall-cmd --reload
# 如果执行了，你将立即被断开，无法再连回来
```

<!-- DIAGRAM: firewalld-safety-protocol -->
```
防火墙修改安全协议
════════════════════════════════════════════════════════════════════

场景：你正在通过 SSH 远程配置防火墙

安全做法                                   危险做法
─────────────────────────────────────────────────────────────────────

┌─────────────────────────────┐           ┌─────────────────────────┐
│ 1. 先不加 --permanent       │           │ 直接加 --permanent      │
│    firewall-cmd --add-xxx   │           │ 然后 --reload           │
└──────────────┬──────────────┘           └──────────────┬──────────┘
               │                                         │
               ▼                                         ▼
┌─────────────────────────────┐           ┌─────────────────────────┐
│ 2. 测试是否正常工作         │           │ 如果规则有误...         │
│    - 从另一终端连接测试     │           │                         │
│    - 确认服务可访问         │           │   ╔═══════════════════╗ │
└──────────────┬──────────────┘           │   ║  立即被锁在外面   ║ │
               │                           │   ║  无法恢复连接     ║ │
               ▼                           │   ╚═══════════════════╝ │
┌─────────────────────────────┐           └─────────────────────────┘
│ 3. 确认无误后再 --permanent │
│    然后 --reload            │
└──────────────┬──────────────┘
               │
               ▼
┌─────────────────────────────┐
│ 4. 如果临时规则有问题       │
│    重启 firewalld 即可恢复  │
│    systemctl restart        │
│    firewalld                │
└─────────────────────────────┘

记住：临时规则 = 安全网
     --timeout = 自动恢复
```
<!-- /DIAGRAM -->

---

## Step 3 - 发生了什么？firewalld 架构（10 分钟）

### 3.1 firewalld 是什么

firewalld 是一个**防火墙管理前端**，底层使用 nftables（或 iptables）。

<!-- DIAGRAM: firewalld-architecture -->
```
firewalld 架构图
════════════════════════════════════════════════════════════════════

                    你的操作
                        │
                        ▼
              ┌─────────────────────┐
              │    firewall-cmd     │  ← 命令行工具
              │    (用户接口)        │
              └──────────┬──────────┘
                        │
                        ▼
              ┌─────────────────────┐
              │     firewalld       │  ← 守护进程
              │    (D-Bus 服务)      │     管理区域、服务、规则
              └──────────┬──────────┘
                        │
                        ▼
              ┌─────────────────────┐
              │     nftables        │  ← 实际的包过滤
              │   (Linux 内核)       │     firewalld 自动生成规则
              └─────────────────────┘

你不需要手写 nftables 规则，firewalld 帮你生成！
但如果需要高级功能，可以绕过 firewalld 直接用 nftables。
```
<!-- /DIAGRAM -->

### 3.2 核心概念：Zones（区域）

Zone 是 firewalld 的核心概念——**基于信任级别的网络分类**。

| Zone | 信任级别 | 默认行为 | 典型用途 |
|------|----------|----------|----------|
| **drop** | 最低 | 丢弃所有入站，不响应 | 完全隔离 |
| **block** | 很低 | 拒绝所有入站，返回 ICMP reject | 明确拒绝 |
| **public** | 低 | 仅允许选定服务 | **默认区域**，公网服务器 |
| **external** | 低 | 用于 NAT 路由器外部接口 | 网关设备 |
| **dmz** | 中低 | 允许有限访问 | DMZ 区服务器 |
| **work** | 中 | 信任同事 | 办公网络 |
| **home** | 中高 | 信任家庭设备 | 家庭网络 |
| **internal** | 高 | 信任内部网络 | 内网服务器 |
| **trusted** | 最高 | 允许所有流量 | 完全信任的网络 |

### 3.3 查看所有区域

```bash
# 列出所有可用区域
firewall-cmd --get-zones

# 查看所有区域的详细配置
firewall-cmd --list-all-zones
```

### 3.4 Services（服务）

firewalld 预定义了常用服务，你不需要记端口号：

```bash
# 查看所有预定义服务
firewall-cmd --get-services

# 查看某个服务的详情
firewall-cmd --info-service=http
```

```
http
  ports: 80/tcp
  protocols:
  source-ports:
  modules:
  destination:
  includes:
  helpers:
```

常用服务映射：

| 服务名 | 端口 | 说明 |
|--------|------|------|
| ssh | 22/tcp | SSH 远程连接 |
| http | 80/tcp | Web 服务 |
| https | 443/tcp | 加密 Web |
| mysql | 3306/tcp | MySQL 数据库 |
| postgresql | 5432/tcp | PostgreSQL |
| dns | 53/tcp, 53/udp | DNS 服务 |

---

## Step 4 - 动手实验：基本操作（15 分钟）

### Lab 1：--permanent vs 即时生效

```bash
# 临时添加（立即生效，重启丢失）
sudo firewall-cmd --add-service=http
sudo firewall-cmd --list-services   # 显示 http

# 重启 firewalld
sudo systemctl restart firewalld
sudo firewall-cmd --list-services   # http 消失了！

# 永久添加（需要 --reload 才生效）
sudo firewall-cmd --permanent --add-service=http
sudo firewall-cmd --list-services   # 还没有 http！

# 重新加载配置
sudo firewall-cmd --reload
sudo firewall-cmd --list-services   # 现在有 http 了
```

**记忆口诀**：
- `--permanent` = 写入配置文件，但不立即生效
- `--reload` = 让永久配置生效
- 不加 `--permanent` = 临时规则，重启丢失

### Lab 2：添加和删除服务

```bash
# 添加服务（临时 + 永久，一步完成）
sudo firewall-cmd --add-service=https
sudo firewall-cmd --permanent --add-service=https

# 删除服务
sudo firewall-cmd --remove-service=https
sudo firewall-cmd --permanent --remove-service=https
```

### Lab 3：添加和删除端口

```bash
# 添加端口
sudo firewall-cmd --add-port=3000/tcp
sudo firewall-cmd --permanent --add-port=3000/tcp

# 添加端口范围
sudo firewall-cmd --add-port=8000-8100/tcp

# 删除端口
sudo firewall-cmd --remove-port=3000/tcp
sudo firewall-cmd --permanent --remove-port=3000/tcp
```

### Lab 4：切换区域

```bash
# 查看默认区域
firewall-cmd --get-default-zone

# 查看接口所属区域
firewall-cmd --get-zone-of-interface=eth0

# 将接口移到其他区域
sudo firewall-cmd --zone=internal --change-interface=eth0

# 修改默认区域
sudo firewall-cmd --set-default-zone=internal
```

---

## Step 5 - Rich Rules：复杂规则（10 分钟）

当简单的服务/端口规则不够用时，使用 Rich Rules。

### 5.1 Rich Rules 语法

```bash
# 基本格式
rule family="ipv4" source address="IP" service name="xxx" accept/reject/drop
```

### 5.2 常用场景

**场景 1：只允许特定 IP 访问 SSH**

```bash
# 拒绝所有 SSH
sudo firewall-cmd --remove-service=ssh

# 只允许特定 IP
sudo firewall-cmd --add-rich-rule='rule family="ipv4" source address="192.168.1.100" service name="ssh" accept'

# 永久保存
sudo firewall-cmd --permanent --add-rich-rule='rule family="ipv4" source address="192.168.1.100" service name="ssh" accept'
```

**场景 2：限制特定网段访问某端口**

```bash
# 允许 10.0.0.0/8 访问 MySQL
sudo firewall-cmd --add-rich-rule='rule family="ipv4" source address="10.0.0.0/8" port port="3306" protocol="tcp" accept'
```

**场景 3：添加日志记录**

```bash
# 记录被拒绝的连接
sudo firewall-cmd --add-rich-rule='rule family="ipv4" source address="0.0.0.0/0" service name="ssh" log prefix="SSH-ATTEMPT: " level="notice" limit value="3/m" reject'
```

### 5.3 查看和删除 Rich Rules

```bash
# 查看所有 rich rules
sudo firewall-cmd --list-rich-rules

# 删除 rich rule（需要完整匹配）
sudo firewall-cmd --remove-rich-rule='rule family="ipv4" source address="192.168.1.100" service name="ssh" accept'
```

---

## Step 6 - 故障实验室：沉默丢弃（10 分钟）

> **场景**：AWS EC2 上的服务，Security Group 已开放，但还是连不上。  

这是云环境中最常见的问题之一——**双层防火墙**。

### 6.1 理解双层防火墙

<!-- DIAGRAM: dual-layer-firewall -->
```
云环境双层防火墙
════════════════════════════════════════════════════════════════════

                    互联网用户
                        │
                        ▼
        ╔═══════════════════════════════════════════╗
        ║           云服务商防火墙                    ║
        ║   (AWS Security Group / Azure NSG)        ║
        ║                                           ║
        ║   规则：允许 TCP 80 ← 你配置了这个        ║
        ╚═══════════════════════════════════════════╝
                        │
                        │ 通过 ✓
                        ▼
        ╔═══════════════════════════════════════════╗
        ║           操作系统防火墙                    ║
        ║        (firewalld / nftables)             ║
        ║                                           ║
        ║   规则：只允许 SSH ← 忘记开放 HTTP！       ║
        ╚═══════════════════════════════════════════╝
                        │
                        │ 被阻止 ✗
                        ▼
                    ┌─────────┐
                    │  Nginx  │  ← 服务正常运行
                    │ (HTTP)  │     但请求到不了
                    └─────────┘

两层都要开放，流量才能到达服务！
```
<!-- /DIAGRAM -->

### 6.2 模拟问题

假设你在 EC2 上部署了 Nginx：

```bash
# Nginx 正在运行
sudo systemctl status nginx
# Active: active (running)

# 监听端口正常
ss -tuln | grep 80
# tcp  LISTEN  0  511  0.0.0.0:80  0.0.0.0:*

# 本地测试成功
curl http://localhost
# Welcome to nginx!

# 但远程测试失败（假设 Security Group 已开放）
curl http://<EC2-PUBLIC-IP>
# 超时...
```

### 6.3 排查步骤

```bash
# 步骤 1：确认服务运行且监听正确地址
ss -tuln | grep 80
# 确认是 0.0.0.0:80 不是 127.0.0.1:80

# 步骤 2：检查 OS 防火墙
sudo firewall-cmd --list-all
```

```
public (active)
  target: default
  interfaces: eth0
  services: cockpit dhcpv6-client ssh    ← 没有 http！
  ports:
```

**根因找到**：OS 防火墙没有开放 HTTP。

### 6.4 修复

```bash
# 开放 HTTP 服务
sudo firewall-cmd --add-service=http
sudo firewall-cmd --permanent --add-service=http

# 验证
sudo firewall-cmd --list-services
# cockpit dhcpv6-client http ssh

# 远程测试
curl http://<EC2-PUBLIC-IP>
# Welcome to nginx!
```

### 6.5 云环境检查清单

```bash
# 完整的云服务连通性检查
echo "=== 1. 服务状态 ==="
systemctl status nginx

echo "=== 2. 监听地址 ==="
ss -tuln | grep -E ':(80|443) '

echo "=== 3. OS 防火墙 ==="
sudo firewall-cmd --list-all

echo "=== 4. 云防火墙 ==="
echo "请在云控制台检查 Security Group / NSG 规则"
```

---

## Mini Project：多区域防火墙配置

### 项目说明

配置一个服务器，使用两个不同的 zone：
- **public zone**：面向互联网，只开放 HTTP/HTTPS
- **internal zone**：面向内网，开放更多服务

### 场景设定

```
服务器有两个网卡：
- eth0 (10.0.1.10) - 连接互联网，分配到 public zone
- eth1 (192.168.100.10) - 连接内网，分配到 internal zone

安全需求：
- 互联网只能访问 Web 服务 (80, 443)
- 内网可以访问 Web + SSH + 监控 (80, 443, 22, 9090)
```

### 配置步骤

```bash
# 1. 查看当前接口分配
firewall-cmd --get-active-zones

# 2. 将 eth0 分配到 public zone
sudo firewall-cmd --zone=public --change-interface=eth0
sudo firewall-cmd --permanent --zone=public --change-interface=eth0

# 3. 将 eth1 分配到 internal zone
sudo firewall-cmd --zone=internal --change-interface=eth1
sudo firewall-cmd --permanent --zone=internal --change-interface=eth1

# 4. 配置 public zone（面向互联网）
sudo firewall-cmd --zone=public --add-service=http
sudo firewall-cmd --zone=public --add-service=https
sudo firewall-cmd --permanent --zone=public --add-service=http
sudo firewall-cmd --permanent --zone=public --add-service=https

# 5. 配置 internal zone（面向内网）
sudo firewall-cmd --zone=internal --add-service=http
sudo firewall-cmd --zone=internal --add-service=https
sudo firewall-cmd --zone=internal --add-service=ssh
sudo firewall-cmd --zone=internal --add-service=cockpit
sudo firewall-cmd --permanent --zone=internal --add-service=http
sudo firewall-cmd --permanent --zone=internal --add-service=https
sudo firewall-cmd --permanent --zone=internal --add-service=ssh
sudo firewall-cmd --permanent --zone=internal --add-service=cockpit

# 6. 验证配置
firewall-cmd --zone=public --list-all
firewall-cmd --zone=internal --list-all
```

### 验证结果

```bash
# Public zone 输出
public (active)
  interfaces: eth0
  services: http https

# Internal zone 输出
internal (active)
  interfaces: eth1
  services: cockpit http https ssh
```

### 测试验证

```bash
# 从互联网测试（应该成功）
curl http://10.0.1.10        # HTTP 成功
ssh user@10.0.1.10           # SSH 失败（被阻止）

# 从内网测试（应该成功）
curl http://192.168.100.10   # HTTP 成功
ssh user@192.168.100.10      # SSH 成功
```

---

## firewalld vs 直接 nftables：何时用哪个

| 场景 | 推荐工具 | 原因 |
|------|----------|------|
| 简单的服务/端口开放 | firewalld | 命令简单，不需要记语法 |
| 基于 zone 的网络隔离 | firewalld | zone 概念直观 |
| 需要动态修改（运行时） | firewalld | D-Bus 接口，不中断连接 |
| 复杂的包过滤逻辑 | nftables | 更灵活的语法 |
| 高性能要求（万级规则） | nftables | sets 和 maps 更高效 |
| 容器/K8s 网络 | nftables | CNI 插件通常直接用 nftables |
| 混合使用 | **不推荐** | 会造成规则冲突 |

### 查看 firewalld 生成的 nftables 规则

```bash
# firewalld 在后台生成的 nftables 规则
sudo nft list ruleset | head -50
```

你会看到 firewalld 自动生成的复杂规则集，这就是为什么对于简单场景，用 firewalld 更省心。

---

## 职场小贴士

### 日本 IT 常用术语

| 日本語 | 中文 | 场景 |
|--------|------|------|
| ファイアウォール | 防火墙 | 安全配置 |
| ゾーン | 区域 | firewalld zone |
| ポート開放 | 端口开放 | 防火墙配置 |
| 許可ルール | 允许规则 | accept rule |
| 拒否ルール | 拒绝规则 | reject/drop rule |
| セキュリティグループ | 安全组 | AWS Security Group |
| 二重ファイアウォール | 双层防火墙 | OS + Cloud |

### 面试常见问题

**Q: firewalld のゾーンとは？**

A: 信頼レベルによるネットワーク分類です。public は低信頼（インターネット向け）、trusted は高信頼（すべて許可）、internal は内部ネットワーク用です。インターフェースや IP アドレスをゾーンに割り当てて、ゾーンごとに異なるルールを適用できます。

**Q: firewalld と直接 nftables 設定の使い分けは？**

A: サービスやポートベースの簡単なルールなら firewalld が便利です。--add-service=http のように直感的に設定でき、ゾーン概念でネットワーク分離も簡単です。複雑なパケットフィルタリングや高パフォーマンス要件（数万ルール）がある場合は直接 nftables を使います。両方を混在させると競合するので避けるべきです。

**Q: --permanent と --reload の関係は？**

A: --permanent は設定ファイルに書き込みますが、すぐには反映されません。--reload で設定ファイルを読み込んで適用します。運用では、まず --permanent なしでテストし、問題なければ --permanent + --reload という手順が安全です。

---

## 本课小结

| 你学到的 | 命令/概念 |
|----------|-----------|
| 查看当前配置 | `firewall-cmd --list-all` |
| 添加服务 | `firewall-cmd --add-service=http` |
| 添加端口 | `firewall-cmd --add-port=8080/tcp` |
| 永久保存 | `--permanent` + `--reload` |
| 切换区域 | `--zone=internal --change-interface=eth0` |
| Rich rules | `--add-rich-rule='rule ...'` |
| 安全测试 | 先不加 `--permanent`，确认后再永久保存 |

**核心理念**：

```
firewalld = nftables 的友好前端

Zone 思维：
- public = 不信任（互联网）
- internal = 信任（内网）
- trusted = 完全信任

安全原则：
1. 先临时，后永久
2. 用 --timeout 做安全网
3. 云环境检查双层防火墙
```

---

## 反模式警示

| 错误做法 | 正确做法 |
|----------|----------|
| 直接 `--permanent` 然后 `--reload` | 先测试临时规则，确认后再永久保存 |
| 忘记 `--permanent` 以为永久生效 | 记住临时规则重启会丢失 |
| 忘记 `--reload` 以为永久规则已生效 | `--permanent` 后必须 `--reload` |
| 云环境只配 Security Group | 记得也要配置 OS 防火墙 |
| 在唯一 SSH 连接上删除 ssh 服务 | 使用 `--timeout` 或先测试临时规则 |
| 混用 firewalld 和直接 nftables | 选择一个工具，不要混用 |

---

## 检查清单

在继续下一课之前，确认你能：

- [ ] 使用 `firewall-cmd --list-all` 查看当前配置
- [ ] 使用 `--add-service` 和 `--add-port` 开放服务和端口
- [ ] 解释 `--permanent` 和 `--reload` 的关系
- [ ] 说明 public、internal、trusted 等 zone 的区别
- [ ] 使用 `--timeout` 安全地测试规则
- [ ] 将接口分配到不同的 zone
- [ ] 编写简单的 rich rule
- [ ] 排查云环境的"双层防火墙"问题
- [ ] 说明何时用 firewalld，何时直接用 nftables

---

## 延伸阅读

- [firewalld 官方文档](https://firewalld.org/documentation/)
- [Red Hat - Using firewalld](https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/9/html/configuring_firewalls_and_packet_filters/using-and-configuring-firewalld_firewall-packet-filters)
- [firewall-cmd man page](https://man7.org/linux/man-pages/man1/firewall-cmd.1.html)

---

## 下一步

你已经学会了使用 firewalld 管理防火墙。接下来，让我们学习 tcpdump 抓包分析，深入网络故障排查。

[08 - tcpdump 与抓包分析 ->](../08-tcpdump/)

---

## 系列导航

[<- 06 - nftables 基础](../06-nftables/) | [Home](/) | [08 - tcpdump 与抓包分析 ->](../08-tcpdump/)
