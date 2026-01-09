# 11 - 故障排查工作流 (Troubleshooting Workflow)

> **目标**：掌握 L3-L4-L7 分层排查方法，建立系统性的网络故障排查思维  
> **前置**：了解网络基础、套接字、防火墙、SSH（01-10 课）  
> **时间**：90 分钟  
> **环境**：任意 Linux 发行版（Ubuntu, AlmaLinux, Amazon Linux 均可）  

---

## 将学到的内容

1. 掌握 L3-L4-L7 分层排查方法论
2. 在更改配置前收集证据（エビデンス）
3. 诊断 7 种常见网络故障场景
4. 知道何时自己解决，何时升级（エスカレーション）
5. 编写 RCA（根因分析）报告

---

## Step 1 - 先跑起来：30 秒快速诊断（5 分钟）

> **目标**：先体验一套完整的诊断流程，再理解每一步的原理。  

遇到"服务访问不了"时，按这个顺序快速检查：

### 1.1 L3 检查：网络层能通吗？

```bash
# 能 ping 通目标吗？
ping -c 3 <目标IP>

# 路由路径是什么？
tracepath <目标IP>

# 本机路由表正确吗？
ip route get <目标IP>
```

### 1.2 L4 检查：端口能连吗？

```bash
# 服务在监听吗？（目标机器上执行）
ss -tuln | grep <端口>

# TCP 连接能建立吗？
nc -zv <目标IP> <端口>

# 抓包看握手
sudo tcpdump -i any port <端口> -nn -c 10
```

### 1.3 L7 检查：应用正常吗？

```bash
# HTTP 服务能响应吗？
curl -v http://<目标IP>:<端口>/

# 应用日志有报错吗？
sudo journalctl -u <服务名> --since "5 minutes ago"
```

---

**3 层检查，快速定位问题在哪一层！**

| 层级 | 检查命令 | 确认什么 |
|------|----------|----------|
| L3 网络层 | `ping`, `tracepath`, `ip route` | 路由可达、没有丢包 |
| L4 传输层 | `ss -tuln`, `nc -zv`, `tcpdump` | 端口监听、TCP 握手成功 |
| L7 应用层 | `curl -v`, `journalctl` | 应用响应正常、无报错 |

接下来，让我们深入理解这个工作流，并练习 7 个真实故障场景。

---

## Step 2 - 发生了什么？L3-L4-L7 方法论（10 分钟）

### 2.1 为什么要分层排查？

<!-- DIAGRAM: l3-l4-l7-methodology -->
```
L3-L4-L7 分层排查方法论
================================================================================

问题："服务访问不了"

错误做法：随机猜测，改一堆配置，问题依然存在
正确做法：从底层向上，逐层排查，定位问题所在层

                    L7 应用层
                    ┌─────────────────────────────────────────────────────┐
                    │  检查：curl -v, 应用日志                            │
                    │  问题：应用 bug、配置错误、认证失败                  │
                    │  负责：开发团队 / 应用运维                          │
                    └─────────────────────────────────────────────────────┘
                                        ▲
                                        │ L4 正常后才检查
                    L4 传输层           │
                    ┌─────────────────────────────────────────────────────┐
                    │  检查：ss -tuln, nc -zv, tcpdump                    │
                    │  问题：端口未监听、防火墙阻断、绑定地址错误          │
                    │  负责：系统运维 / 安全团队                          │
                    └─────────────────────────────────────────────────────┘
                                        ▲
                                        │ L3 正常后才检查
                    L3 网络层           │
                    ┌─────────────────────────────────────────────────────┐
                    │  检查：ping, tracepath, ip route                    │
                    │  问题：路由错误、网络不通、丢包                      │
                    │  负责：网络团队 (NW チーム)                         │
                    └─────────────────────────────────────────────────────┘
                                        ▲
                                        │ 从这里开始！
                                   开始排查

关键原则：
  1. 自下而上：先确认 L3，再查 L4，最后查 L7
  2. 收集证据：每一步都记录输出，不要只看"成功/失败"
  3. 最小变更：每次只改一个配置，验证效果
  4. 双端视角：同时从客户端和服务端排查
```
<!-- /DIAGRAM -->

### 2.2 日本 IT 职场的排查流程

在日本 IT 企業，网络障害対応有严格的流程：

| 日本語 | 中文 | 说明 |
|--------|------|------|
| 障害検知 | 故障检测 | 监控告警或用户报告 |
| 影響範囲確認 | 影响范围确认 | 哪些用户/服务受影响 |
| 切り分け | 问题切分 | L3-L4-L7 分层定位 |
| エビデンス収集 | 证据收集 | 命令输出、日志截图 |
| 暫定対応 | 临时处置 | 先恢复服务 |
| 恒久対応 | 永久修复 | 根本解决问题 |
| RCA 作成 | 根因分析报告 | 记录原因和改进措施 |

### 2.3 证据收集清单

**改配置之前，先收集这些：**

```bash
# 创建证据目录
EVIDENCE_DIR="/tmp/incident-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$EVIDENCE_DIR"

# 网络配置快照
ip addr > "$EVIDENCE_DIR/ip-addr.txt"
ip route > "$EVIDENCE_DIR/ip-route.txt"
ss -tulpn > "$EVIDENCE_DIR/ss-tulpn.txt"
cat /etc/resolv.conf > "$EVIDENCE_DIR/resolv.conf"

# 防火墙规则
sudo nft list ruleset > "$EVIDENCE_DIR/nftables.txt" 2>/dev/null
sudo firewall-cmd --list-all > "$EVIDENCE_DIR/firewalld.txt" 2>/dev/null

# 系统日志
sudo journalctl --since "1 hour ago" > "$EVIDENCE_DIR/journal.txt"
sudo dmesg | tail -100 > "$EVIDENCE_DIR/dmesg.txt"

echo "证据已保存到: $EVIDENCE_DIR"
ls -la "$EVIDENCE_DIR"
```

**为什么要收集证据？**

1. **可回滚**：改错了能恢复原状
2. **可追溯**：RCA 时能证明根因
3. **可共享**：升级给 NW 团队时有据可查
4. **可审计**：日本企业要求保留变更记录

---

## Step 3 - 故障场景 1：Localhost 陷阱（10 分钟）

> **场景**：`curl localhost` 成功，但从其他机器访问失败  

### 3.1 症状

```bash
# 在服务器本机
curl http://localhost:8080
# 成功！返回网页内容

# 从其他机器
curl http://192.168.1.100:8080
# curl: (7) Failed to connect: Connection refused
```

### 3.2 诊断步骤

**Step 1：检查监听地址**

```bash
ss -tuln | grep 8080
```

```
tcp  LISTEN  0  511  127.0.0.1:8080  0.0.0.0:*
```

**问题发现！** 服务绑定在 `127.0.0.1`，只接受本地连接。

**Step 2：确认服务配置**

```bash
# 查看进程启动参数
ps aux | grep <服务名>

# 或检查配置文件
cat /etc/nginx/nginx.conf | grep listen
# listen 127.0.0.1:8080;  ← 这就是问题
```

### 3.3 修复方法

修改服务配置，绑定到 `0.0.0.0`：

```bash
# Nginx 示例
# 修改前：listen 127.0.0.1:8080;
# 修改后：listen 0.0.0.0:8080;

sudo systemctl restart nginx
```

### 3.4 验证

```bash
ss -tuln | grep 8080
# tcp  LISTEN  0  511  0.0.0.0:8080  0.0.0.0:*  ← 正确！

# 远程测试
curl http://192.168.1.100:8080
# 成功！
```

### 3.5 诊断流程图

<!-- DIAGRAM: localhost-trap-flow -->
```
Localhost 陷阱诊断流程
================================================================================

        ┌─────────────────────────────────────┐
        │  远程访问失败                       │
        │  curl http://<IP>:<port> refused    │
        └─────────────────┬───────────────────┘
                          │
                          ▼
        ┌─────────────────────────────────────┐
        │  本机测试                           │
        │  curl http://localhost:<port>       │
        └─────────────────┬───────────────────┘
                          │
              ┌───────────┴───────────┐
              │                       │
        本机失败                  本机成功
              │                       │
              ▼                       ▼
    ┌─────────────────┐     ┌─────────────────────────────┐
    │ 服务未运行      │     │ 检查监听地址                │
    │ systemctl       │     │ ss -tuln | grep <port>      │
    │ status <服务>   │     └───────────────┬─────────────┘
    └─────────────────┘                     │
                                ┌───────────┴───────────┐
                                │                       │
                          127.0.0.1               0.0.0.0
                                │                       │
                                ▼                       ▼
                    ┌─────────────────────┐   ┌─────────────────┐
                    │  找到问题！         │   │ 检查防火墙      │
                    │  修改配置绑定到     │   │ firewall-cmd    │
                    │  0.0.0.0            │   │ --list-all      │
                    └─────────────────────┘   └─────────────────┘
```
<!-- /DIAGRAM -->

---

## Step 4 - 故障场景 2：沉默丢弃（10 分钟）

> **场景**：连接超时，tcpdump 看到 SYN 发出去但没有响应  

### 4.1 症状

```bash
# 连接超时
curl --connect-timeout 5 http://192.168.1.100:80
# curl: (28) Connection timed out

# 抓包只看到 SYN，没有 SYN-ACK
sudo tcpdump -i eth0 port 80 -nn
# 10:00:01 IP 10.0.1.50.54321 > 192.168.1.100.80: Flags [S], seq 123456
# 10:00:02 IP 10.0.1.50.54321 > 192.168.1.100.80: Flags [S], seq 123456  ← 重传
# 10:00:04 IP 10.0.1.50.54321 > 192.168.1.100.80: Flags [S], seq 123456  ← 又重传
```

### 4.2 诊断步骤

**Step 1：确认 L3 连通性**

```bash
ping -c 3 192.168.1.100
# PING 192.168.1.100: 64 bytes from 192.168.1.100: icmp_seq=0 ttl=64 time=0.5 ms
```

L3 正常，问题在 L4。

**Step 2：检查目标机器的防火墙**

```bash
# 在目标机器上执行
sudo firewall-cmd --list-all
```

```
public (active)
  target: default
  services: ssh
  ports:
  # 没有 80/tcp！
```

**问题发现！** 防火墙没有开放 80 端口。

**云环境特别注意**：可能有两层防火墙！

```
客户端 → [云安全组/Security Group] → [OS 防火墙/firewalld] → 服务
                  ↑                           ↑
              AWS Console 配置            firewall-cmd 配置
```

### 4.3 沉默丢弃 vs 明确拒绝

| 现象 | tcpdump 看到 | 原因 | curl 报错 |
|------|--------------|------|-----------|
| **沉默丢弃** | 只有 SYN | 防火墙 DROP 规则 | Connection timed out |
| **明确拒绝** | SYN + RST | 端口未监听 | Connection refused |

### 4.4 修复方法

```bash
# 开放端口（临时）
sudo firewall-cmd --add-port=80/tcp

# 验证
sudo firewall-cmd --list-all

# 测试成功后，永久保存
sudo firewall-cmd --add-port=80/tcp --permanent
sudo firewall-cmd --reload
```

### 4.5 云环境检查清单

```bash
# 1. 检查 OS 防火墙
sudo firewall-cmd --list-all

# 2. 检查 nftables（如果没用 firewalld）
sudo nft list ruleset | grep -A5 "chain input"

# 3. AWS Security Group（需要在 Console 或 CLI 检查）
aws ec2 describe-security-groups --group-ids sg-xxx

# 4. VPC Network ACL
aws ec2 describe-network-acls --network-acl-ids acl-xxx
```

---

## Step 5 - 故障场景 3：Split Brain DNS（10 分钟）

> **场景**：`ping <IP>` 成功，`ping <域名>` 失败  

### 5.1 症状

```bash
# IP 直接访问正常
ping -c 3 10.0.1.50
# PING 10.0.1.50: 64 bytes from 10.0.1.50

curl http://10.0.1.50
# 成功！

# 域名访问失败
ping -c 3 app.internal.company.com
# ping: app.internal.company.com: Name or service not known

curl http://app.internal.company.com
# curl: (6) Could not resolve host
```

### 5.2 诊断步骤

**Step 1：检查 DNS 配置**

```bash
# 查看当前 DNS 状态
resolvectl status
```

```
Global
       Protocols: +LLMNR +mDNS -DNSOverTLS DNSSEC=no/unsupported
resolv.conf mode: stub

Link 2 (eth0)
    Current Scopes: DNS
         Protocols: +DefaultRoute +LLMNR -mDNS -DNSOverTLS DNSSEC=no/unsupported
Current DNS Server: 8.8.8.8
       DNS Servers: 8.8.8.8
```

**问题可能性 1**：使用了外部 DNS（8.8.8.8），无法解析内部域名。

**Step 2：测试不同 DNS 服务器**

```bash
# 用默认 DNS
dig app.internal.company.com
# ;; status: NXDOMAIN  ← 找不到

# 用内部 DNS 服务器
dig @10.0.0.2 app.internal.company.com
# ;; ANSWER SECTION:
# app.internal.company.com. 300 IN A 10.0.1.50  ← 能解析！
```

**问题发现！** 需要使用内部 DNS 服务器。

### 5.3 常见原因

| 原因 | 症状 | 修复 |
|------|------|------|
| /etc/resolv.conf 被覆盖 | DNS 配置丢失 | 使用 systemd-resolved 管理 |
| DHCP 覆盖了静态配置 | 重启后 DNS 变化 | 配置 NetworkManager/netplan |
| VPN split-DNS 未生效 | 内部域名无法解析 | 配置 per-link DNS |
| DNS 服务器不可达 | 所有域名都无法解析 | 检查 DNS 服务器连通性 |

### 5.4 修复方法

**方法 1：临时添加 DNS（测试用）**

```bash
# 添加内部 DNS 到特定链路
sudo resolvectl dns eth0 10.0.0.2 8.8.8.8
sudo resolvectl domain eth0 internal.company.com
```

**方法 2：永久配置（使用 NetworkManager）**

```bash
# 添加 DNS 服务器
nmcli connection modify "Wired connection 1" ipv4.dns "10.0.0.2 8.8.8.8"
nmcli connection modify "Wired connection 1" ipv4.dns-search "internal.company.com"
nmcli connection up "Wired connection 1"
```

**方法 3：配置 systemd-resolved**

```bash
# 编辑 /etc/systemd/resolved.conf
sudo tee -a /etc/systemd/resolved.conf << 'EOF'
[Resolve]
DNS=10.0.0.2 8.8.8.8
Domains=internal.company.com
EOF

sudo systemctl restart systemd-resolved
```

### 5.5 验证

```bash
# 检查配置生效
resolvectl status

# 测试解析
dig app.internal.company.com

# 测试连接
curl http://app.internal.company.com
```

---

## Step 6 - 故障场景 4：SSH 权限拒绝（10 分钟）

> **场景**：`Permission denied (publickey)`，密钥明明配好了  

### 6.1 症状

```bash
ssh user@server
# user@server: Permission denied (publickey).
```

### 6.2 诊断步骤

**Step 1：客户端调试**

```bash
ssh -vvv user@server 2>&1 | grep -E "(Offering|Trying|Authentication)"
```

```
debug1: Trying private key: /home/user/.ssh/id_ed25519
debug1: Offering public key: /home/user/.ssh/id_ed25519 ED25519
debug2: we sent a publickey packet, wait for reply
debug1: Authentications that can continue: publickey
debug1: No more authentication methods to try.
```

密钥发送了，但服务器拒绝。问题在服务端。

**Step 2：服务端日志**

```bash
# RHEL/CentOS/Amazon Linux
sudo tail -20 /var/log/secure

# Ubuntu/Debian
sudo tail -20 /var/log/auth.log
```

```
Jan 05 10:30:45 server sshd[12345]: Authentication refused: bad ownership or modes for file /home/user/.ssh/authorized_keys
```

**问题发现！** authorized_keys 权限不对。

**Step 3：检查权限**

```bash
ls -la ~/.ssh/
```

```
drwxrwxrwx 2 user user 4096 Jan  5 10:00 .             ← 错误！应该是 700
-rw-rw-rw- 1 user user  400 Jan  5 10:00 authorized_keys  ← 错误！应该是 600
```

### 6.3 SSH 权限要求

| 文件/目录 | 正确权限 | 说明 |
|-----------|----------|------|
| `~/.ssh/` | 700 | 目录仅所有者可访问 |
| `~/.ssh/authorized_keys` | 600 | 仅所有者可读写 |
| `~/.ssh/id_*` (私钥) | 600 | 仅所有者可读写 |
| `~/.ssh/id_*.pub` (公钥) | 644 | 可被他人读取 |
| `~/.ssh/config` | 600 | 仅所有者可读写 |

### 6.4 修复方法

```bash
# 修复目录权限
chmod 700 ~/.ssh

# 修复 authorized_keys 权限
chmod 600 ~/.ssh/authorized_keys

# 修复私钥权限
chmod 600 ~/.ssh/id_*
chmod 644 ~/.ssh/id_*.pub
```

### 6.5 其他常见原因

| 原因 | 症状 | 检查方法 |
|------|------|----------|
| 公钥未添加到 authorized_keys | 密钥不匹配 | 比较公钥指纹 |
| 用户主目录权限过松 | 同上 | `ls -la /home/` |
| SELinux 阻止访问 | 权限正确但仍失败 | `sudo ausearch -m avc -ts recent` |
| sshd_config 限制 | AllowUsers 不包含该用户 | 检查 sshd_config |

**SELinux 修复**（如果适用）：

```bash
# 恢复 SELinux 上下文
restorecon -Rv ~/.ssh/
```

---

## Step 7 - 故障场景 5：MTU 黑洞（10 分钟）

> **场景**：SSH 能用，scp 传大文件卡住  

### 7.1 症状

```bash
# SSH 正常
ssh user@server 'echo hello'
# hello

# 小命令正常
ssh user@server 'ls -la'
# 输出正常

# 传大文件卡住
scp largefile.zip user@server:/tmp/
# 传输开始后卡住，进度条不动
```

### 7.2 MTU 问题原理

<!-- DIAGRAM: mtu-blackhole -->
```
MTU 黑洞问题原理
================================================================================

MTU (Maximum Transmission Unit)：单个网络包的最大尺寸

正常情况（MTU 一致）：
┌────────────────┐                         ┌────────────────┐
│  客户端        │                         │  服务器        │
│  MTU: 1500     │                         │  MTU: 1500     │
└───────┬────────┘                         └───────┬────────┘
        │                                          │
        │  [1500 字节包] ────────────────────────▶ │  ✓ 正常接收
        │                                          │

问题情况（中间设备 MTU 较小）：
┌────────────────┐    ┌────────────────┐    ┌────────────────┐
│  客户端        │    │  VPN/隧道      │    │  服务器        │
│  MTU: 1500     │    │  MTU: 1400     │    │  MTU: 1500     │
└───────┬────────┘    └───────┬────────┘    └───────┬────────┘
        │                     │                     │
        │  [1500 字节包] ────▶│ ✗ 包太大！          │
        │                     │   需要分片          │
        │                     │   但 DF 标志禁止    │
        │                     │   丢弃 + 发 ICMP    │
        │                     │                     │
        │  如果 ICMP 被阻止   │                     │
        │  客户端不知道包被丢 │                     │
        │  一直重传大包       │                     │
        │  = 传输卡住！       │                     │

为什么小包正常，大包卡住？
• SSH 命令输出通常 < 1400 字节 → 正常通过
• 大文件传输包 = 1500 字节 → 被丢弃
```
<!-- /DIAGRAM -->

### 7.3 诊断步骤

**Step 1：测试 MTU**

```bash
# 测试 1472 字节包（1500 - 28 = 1472，28 是 IP+ICMP 头部）
ping -c 3 -M do -s 1472 <目标IP>
# PING: 1480 data bytes
# From <路由器>: icmp_seq=1 Frag needed and DF set (mtu = 1400)

# 找到有效 MTU
ping -c 3 -M do -s 1372 <目标IP>
# 1380 bytes from <目标IP>: icmp_seq=1 ttl=64 time=10.5 ms
```

**Step 2：确认路径 MTU**

```bash
tracepath <目标IP>
```

```
 1?: [LOCALHOST]                      pmtu 1500
 2:  192.168.1.1                       1.5ms
 3:  10.0.0.1                          5.0ms pmtu 1400  ← MTU 下降
 4:  <目标IP>                         10.0ms reached
     Resume: pmtu 1400
```

### 7.4 修复方法

**方法 1：降低本机 MTU（临时）**

```bash
sudo ip link set eth0 mtu 1400
```

**方法 2：使用 NetworkManager 永久配置**

```bash
nmcli connection modify "Wired connection 1" 802-3-ethernet.mtu 1400
nmcli connection up "Wired connection 1"
```

**方法 3：启用 PMTUD（Path MTU Discovery）**

确保 ICMP 没有被阻止：

```bash
# 检查 ICMP 是否被阻止
sudo iptables -L -n | grep icmp
sudo nft list ruleset | grep icmp

# 允许 ICMP "需要分片" 消息
sudo nft add rule inet filter input icmp type destination-unreachable accept
```

### 7.5 验证

```bash
# 确认 MTU 修改生效
ip link show eth0 | grep mtu

# 测试大文件传输
scp largefile.zip user@server:/tmp/
# 传输成功！
```

---

## Step 8 - 故障场景 6：代理缺失（5 分钟）

> **场景**：企业网络中，yum/curl 超时  

### 8.1 症状

```bash
# yum 更新超时
sudo yum update
# Timeout when connecting to remote server

# curl 也超时
curl -v https://www.google.com
# * Trying 142.250.xxx.xxx:443...
# * connect to 142.250.xxx.xxx port 443 failed: Connection timed out
```

### 8.2 诊断步骤

```bash
# 检查代理环境变量
env | grep -i proxy
# （没有输出 = 没有设置代理）

# 检查是否需要代理
# 如果在企业网络，通常需要代理访问外网
```

### 8.3 修复方法

**临时设置代理**：

```bash
export http_proxy="http://proxy.company.com:8080"
export https_proxy="http://proxy.company.com:8080"
export no_proxy="localhost,127.0.0.1,.internal.company.com"

# 测试
curl -v https://www.google.com
```

**永久配置（用户级）**：

```bash
cat >> ~/.bashrc << 'EOF'
export http_proxy="http://proxy.company.com:8080"
export https_proxy="http://proxy.company.com:8080"
export no_proxy="localhost,127.0.0.1,.internal.company.com"
EOF
```

**系统级配置（yum）**：

```bash
# 编辑 /etc/yum.conf
sudo tee -a /etc/yum.conf << 'EOF'
proxy=http://proxy.company.com:8080
EOF
```

### 8.4 代理排查清单

| 检查项 | 命令 |
|--------|------|
| 环境变量 | `env \| grep -i proxy` |
| yum 配置 | `grep proxy /etc/yum.conf` |
| dnf 配置 | `grep proxy /etc/dnf/dnf.conf` |
| apt 配置 | `cat /etc/apt/apt.conf.d/*proxy*` |
| git 配置 | `git config --global --get http.proxy` |

---

## Step 9 - 故障场景 7：非对称路由（10 分钟）

> **场景**：同子网可达，跨子网不通  

### 9.1 症状

```bash
# 同子网正常
ping -c 3 192.168.1.100
# 成功

# 跨子网失败
ping -c 3 10.0.2.50
# 请求发出去了，但没有响应
```

### 9.2 非对称路由原理

<!-- DIAGRAM: asymmetric-routing -->
```
非对称路由问题
================================================================================

正常路由（对称）：
┌────────────┐        ┌────────────┐        ┌────────────┐
│  客户端    │──请求──▶│   路由器   │──请求──▶│  服务器    │
│ 10.0.1.10  │        │           │        │ 10.0.2.50  │
│            │◀─响应──│           │◀─响应──│            │
└────────────┘        └────────────┘        └────────────┘

非对称路由（问题）：
                      ┌────────────┐
                      │  路由器 A  │
                      │ 10.0.1.1   │
                      └─────┬──────┘
                            │ 请求 ↓
┌────────────┐              │              ┌────────────┐
│  客户端    │──请求────────┘              │  服务器    │
│ 10.0.1.10  │                             │ 10.0.2.50  │
│ eth0       │              ┌──────────────│ eth1       │
└────────────┘              │              └────────────┘
      ▲                     │ 响应
      │                     │ ↓（不同路径！）
      ✗ 收不到！       ┌────┴──────┐
                       │  路由器 B  │
                       │ 10.0.2.1   │
                       └────────────┘

问题原因：
1. 服务器有多个网卡，每个网卡有不同的网关
2. 请求从 eth0 进来，响应从 eth1 出去
3. 状态防火墙只看到"响应"没看到"请求"
4. 防火墙丢弃"无状态"的响应包

服务器路由表示例（问题配置）：
$ ip route
default via 10.0.2.1 dev eth1    ← 默认从 eth1 出
10.0.1.0/24 dev eth0             ← 直连网段
10.0.2.0/24 dev eth1
```
<!-- /DIAGRAM -->

### 9.3 诊断步骤

**Step 1：检查服务器路由表**

```bash
ip route
```

```
default via 10.0.2.1 dev eth1   ← 注意：默认网关在 eth1
10.0.1.0/24 dev eth0 proto kernel scope link src 10.0.1.50
10.0.2.0/24 dev eth1 proto kernel scope link src 10.0.2.50
```

**Step 2：检查请求从哪个接口进来**

```bash
# 在服务器上抓包
sudo tcpdump -i eth0 icmp -nn
# 能看到 ICMP 请求进来

sudo tcpdump -i eth1 icmp -nn
# 能看到 ICMP 响应出去（问题！应该从 eth0 出去）
```

**Step 3：验证返回路径**

```bash
# 检查去往客户端的路由
ip route get 10.0.1.10
# 10.0.1.10 via 10.0.2.1 dev eth1  ← 问题！应该走 eth0
```

### 9.4 修复方法

**方法 1：添加明确的返回路由**

```bash
# 让 10.0.1.0/24 的流量从 eth0 出去
sudo ip route add 10.0.1.0/24 via 10.0.1.1 dev eth0
```

**方法 2：策略路由（更完善）**

```bash
# 创建路由表
echo "100 eth0_table" | sudo tee -a /etc/iproute2/rt_tables

# 添加策略：从 eth0 进来的包，响应也从 eth0 出去
sudo ip rule add from 10.0.1.50 table eth0_table
sudo ip route add default via 10.0.1.1 dev eth0 table eth0_table
```

**方法 3：源地址路由（推荐）**

```bash
# 根据源地址选择网关
sudo ip rule add from 10.0.1.50 lookup eth0_table
sudo ip rule add from 10.0.2.50 lookup eth1_table
```

### 9.5 验证

```bash
# 检查路由
ip route get 10.0.1.10 from 10.0.1.50
# 10.0.1.10 from 10.0.1.50 via 10.0.1.1 dev eth0  ← 正确！

# 测试连通性
ping -c 3 10.0.2.50
# 成功！
```

---

## Step 10 - 知道何时升级（5 分钟）

### 10.1 升级判断标准

| 情况 | 自己处理 | 升级给 NW 团队 |
|------|----------|----------------|
| 应用配置问题 | 是 | |
| OS 防火墙问题 | 是 | |
| 单台服务器问题 | 是 | |
| 跨多台服务器 | | 是 |
| 涉及网络设备 | | 是 |
| 涉及安全组/VPC | 视权限 | 是 |
| 影响多个用户 | | 是 |
| 需要抓包分析网络设备 | | 是 |

### 10.2 升级时提供什么信息

```markdown
## 障害報告

### 概要
- 発生時刻: 2025-01-05 10:30 JST
- 影響範囲: Web サーバ (web01, web02) から DB サーバへの接続不可
- 障害レベル: 重大（サービス停止）

### 切り分け結果
1. L3 疎通確認
   - ping 10.0.2.50: OK
   - tracepath 結果: [添付]

2. L4 接続確認
   - nc -zv 10.0.2.50 3306: タイムアウト
   - tcpdump 結果: SYN のみ、SYN-ACK なし [添付]

3. サーバ側確認
   - ss -tuln: 3306 は 0.0.0.0 で LISTEN 中
   - firewalld: 3306/tcp 許可済み

### エビデンス
- web01 tcpdump: [添付]
- db01 ss -tuln: [添付]
- db01 firewall-cmd --list-all: [添付]

### 推測
- サーバ側の設定は問題なし
- 経路上のネットワーク機器でブロックの可能性
- NW チームでの確認をお願いします
```

---

## Step 11 - RCA 报告模板（5 分钟）

### 11.1 什么是 RCA

RCA（Root Cause Analysis）= 根因分析

日本 IT 企業在每次障害対応后都要提交 RCA 报告。

### 11.2 RCA 模板

```markdown
# 障害報告書（RCA）

## 基本情報
| 項目 | 内容 |
|------|------|
| 発生日時 | 2025-01-05 10:30 JST |
| 復旧日時 | 2025-01-05 11:15 JST |
| 影響時間 | 45 分 |
| 障害レベル | 重大 |
| 報告者 | 山田太郎 |

## 影響範囲
- 影響サービス: 本番 Web サービス
- 影響ユーザ数: 約 5000 名
- 影響内容: サービス接続不可

## タイムライン
| 時刻 | イベント |
|------|----------|
| 10:30 | 監視アラート検知 |
| 10:35 | 担当者にエスカレーション |
| 10:40 | 切り分け開始 |
| 10:55 | 根本原因特定（FW ルール誤削除） |
| 11:10 | FW ルール復旧 |
| 11:15 | サービス復旧確認 |

## 根本原因
前日のメンテナンス作業で、誤って本番 DB への 3306 ポートを許可する
firewalld ルールを削除。--permanent フラグ付きで実行されていたため、
本日の再起動後にルールが消失した。

## 暫定対応
firewall-cmd --add-port=3306/tcp --permanent
firewall-cmd --reload

## 恒久対応
1. FW ルール変更手順の見直し（変更前後の diff 取得を必須化）
2. FW 設定の構成管理ツール（Ansible）への移行
3. 定期的な FW 設定バックアップの自動化

## 再発防止策
| 項目 | 担当 | 期限 |
|------|------|------|
| 変更手順書の改訂 | インフラチーム | 2025-01-12 |
| Ansible 化 | DevOps チーム | 2025-01-31 |
| 監視追加（ポート監視） | 運用チーム | 2025-01-10 |

## 添付資料
- 障害発生時の tcpdump ログ
- firewall-cmd --list-all の出力（Before/After）
- 復旧作業のコマンド履歴
```

---

## Mini Project：L3-L4-L7 诊断检查清单

### 项目说明

创建一个可打印的故障诊断检查清单，用于日常运维和障害対応。

### 检查清单内容

创建文件 `troubleshooting-checklist.md`：

```markdown
# 网络故障诊断检查清单 / ネットワーク障害診断チェックリスト

## 0. 证据收集（変更前）

```bash
# 创建证据目录
EVIDENCE="/tmp/incident-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$EVIDENCE"

# 保存当前状态
ip addr > "$EVIDENCE/ip-addr.txt"
ip route > "$EVIDENCE/ip-route.txt"
ss -tulpn > "$EVIDENCE/ss-tulpn.txt"
sudo nft list ruleset > "$EVIDENCE/nftables.txt" 2>/dev/null
sudo firewall-cmd --list-all > "$EVIDENCE/firewalld.txt" 2>/dev/null
```

## 1. L3 网络层检查

| 检查项 | 命令 | 预期结果 |
|--------|------|----------|
| 目标可达 | `ping -c 3 <IP>` | 0% 丢包 |
| 路由路径 | `tracepath <IP>` | 能到达目标 |
| 本机路由 | `ip route get <IP>` | 显示正确网关 |
| 默认网关 | `ip route \| grep default` | 网关可达 |

**L3 不通 → 检查路由配置、网关、物理连接**

## 2. L4 传输层检查

| 检查项 | 命令 | 预期结果 |
|--------|------|----------|
| 端口监听 | `ss -tuln \| grep <port>` | 显示 LISTEN |
| 监听地址 | 同上 | 0.0.0.0 而非 127.0.0.1 |
| TCP 连接 | `nc -zv <IP> <port>` | succeeded |
| 抓包验证 | `sudo tcpdump -i any port <port> -nn -c 10` | SYN + SYN-ACK |

**只有 SYN 无 SYN-ACK → 防火墙 DROP**
**收到 RST → 端口未监听**

## 3. L4 防火墙检查

| 检查项 | 命令 | 预期结果 |
|--------|------|----------|
| firewalld | `sudo firewall-cmd --list-all` | 端口在允许列表 |
| nftables | `sudo nft list ruleset` | 有 accept 规则 |
| 云安全组 | AWS Console / `aws ec2 describe-security-groups` | 入站规则正确 |

## 4. L7 应用层检查

| 检查项 | 命令 | 预期结果 |
|--------|------|----------|
| HTTP 响应 | `curl -v http://<IP>:<port>/` | 200 OK |
| 应用日志 | `sudo journalctl -u <服务> --since "10 min ago"` | 无错误 |
| 服务状态 | `systemctl status <服务>` | active (running) |

## 5. 常见问题快查表

| 症状 | 可能原因 | 首选检查 |
|------|----------|----------|
| Connection refused | 端口未监听 | `ss -tuln` |
| Connection timeout | 防火墙 DROP | `tcpdump` |
| Name not resolved | DNS 问题 | `resolvectl status` |
| Permission denied (SSH) | 权限不对 | `/var/log/secure` |
| 大文件传输卡住 | MTU 问题 | `ping -M do -s 1472` |
```

### 使用方法

```bash
# 保存为 Markdown 文件
cat > ~/troubleshooting-checklist.md << 'EOF'
[上面的内容]
EOF

# 转换为 PDF（可选）
pandoc ~/troubleshooting-checklist.md -o ~/troubleshooting-checklist.pdf
```

---

## 职场小贴士

### 日本 IT 障害対応术语

| 日本語 | 中文 | 使用场景 |
|--------|------|----------|
| 障害検知 | 故障检测 | 监控告警触发 |
| 影響確認 | 影响确认 | 确定受影响范围 |
| 切り分け | 问题切分 | L3-L4-L7 分层排查 |
| エビデンス | 证据 | 命令输出、日志截图 |
| エスカレーション | 升级 | 向上级或专家团队求助 |
| 暫定対応 | 临时处置 | 先恢复服务 |
| 恒久対応 | 永久修复 | 根本解决问题 |
| RCA | 根因分析 | 事后分析报告 |

### 面试常见问题

**Q: ネットワーク障害の切り分け手順は？**

A: L3 から順番に確認します。まず ping/tracepath で経路確認、次に ss/nc でポート確認、tcpdump で通信確認、最後に curl/ログでアプリ確認。各層で問題がないことを確認してから次の層に進みます。変更前には必ずエビデンスを取得します。

**Q: 障害対応でエビデンス収集が重要な理由は？**

A: 3 つの理由があります。1) 変更前の状態を記録して rollback 可能にする。2) RCA で根本原因を証明する。3) チーム間の情報共有と引き継ぎに必要。日本の IT 現場では監査要件もあり、変更履歴の記録は必須です。

**Q: サービスが LISTEN してるのに接続できない場合の確認ポイントは？**

A: 3 つのポイントを確認します。1) ss -tuln で監聴アドレスが 127.0.0.1 ではなく 0.0.0.0 であること。2) firewalld/nftables でポートが許可されていること。3) クラウド環境では Security Group も確認。tcpdump で SYN が届いているか、RST が返っているかを確認すると原因が特定できます。

---

## 本课小结

| 你学到的 | 内容/命令 |
|----------|-----------|
| L3 检查 | `ping`, `tracepath`, `ip route get` |
| L4 检查 | `ss -tuln`, `nc -zv`, `tcpdump` |
| L7 检查 | `curl -v`, `journalctl` |
| 证据收集 | 保存 ip addr, ip route, ss, firewall 配置 |
| Localhost 陷阱 | 检查监听地址是 0.0.0.0 还是 127.0.0.1 |
| 沉默丢弃 | tcpdump 只有 SYN = 防火墙 DROP |
| Split Brain DNS | resolvectl status + dig 测试 |
| SSH 权限 | ~/.ssh 700, authorized_keys 600 |
| MTU 黑洞 | ping -M do -s 1472 测试 |
| 代理缺失 | env \| grep -i proxy |
| 非对称路由 | 检查 ip route get 的出口接口 |

**核心理念**：

```
系统性排查 > 随机猜测

排查原则：
1. 自下而上：L3 → L4 → L7
2. 先证据，后变更
3. 最小变更，逐步验证
4. 双端视角，两边都查
5. 知道何时升级
```

---

## 反模式警示

| 错误做法 | 正确做法 |
|----------|----------|
| 不收集证据就开始改配置 | 先保存当前状态 |
| 只从一端调试 | 客户端 + 服务端双向排查 |
| 跳过 L3 直接查 L7 | 按 L3-L4-L7 顺序 |
| 随机尝试修复 | 系统性分层排查 |
| 改了很多东西不知道哪个生效 | 每次只改一个，验证后再改下一个 |
| 问题解决了就结束 | 写 RCA 报告，防止再发 |

---

## 检查清单

在继续下一课之前，确认你能：

- [ ] 解释 L3-L4-L7 分层排查的顺序和原因
- [ ] 在更改配置前收集证据（ip addr, route, ss, firewall）
- [ ] 诊断 Localhost 陷阱（127.0.0.1 绑定问题）
- [ ] 区分沉默丢弃（timeout）和明确拒绝（refused）
- [ ] 排查 DNS 解析问题（resolvectl, dig）
- [ ] 修复 SSH 权限问题（700/600）
- [ ] 诊断 MTU 黑洞（ping -M do）
- [ ] 判断何时自己处理，何时升级
- [ ] 编写简单的 RCA 报告

---

## 延伸阅读

- [Linux Network Troubleshooting Guide - Red Hat](https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/9/html/configuring_and_managing_networking/index)
- [tcpdump Tutorial - Daniel Miessler](https://danielmiessler.com/study/tcpdump/)
- [MTU and TCP MSS - Cloudflare](https://blog.cloudflare.com/path-mtu-discovery-in-practice/)
- [SSH Troubleshooting - DigitalOcean](https://www.digitalocean.com/community/tutorials/ssh-essentials-working-with-ssh-servers-clients-and-keys)

---

## 下一步

你已经掌握了系统性的网络故障排查方法论。接下来是课程的综合项目，你将构建一个多区域网络架构并进行故障注入测试。

[12 - 综合项目：多区域网络 ->](../12-capstone/)

---

## 系列导航

[<- 10 - 网络命名空间](../10-namespaces/) | [Home](/) | [12 - 综合项目 ->](../12-capstone/)
