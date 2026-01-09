# 02 - 网络接口配置（Interface Configuration）

> **目标**：掌握 Linux 网络接口的查看、配置与持久化方法  
> **前置**：完成 [01-网络基础](../01-fundamentals/)，理解 TCP/IP 分层模型  
> **时间**：60 分钟  
> **实战场景**：服务器上线前的静态 IP 配置  

---

## 将学到的内容

1. 理解现代 Linux 接口命名规范（Predictable Network Interface Names）
2. 使用 `ip` 命令查看和临时配置接口
3. 区分 `ip link`、`ip addr`、`ip route` 的用途
4. 使用 `nmcli` 进行持久化网络配置
5. 理解 NetworkManager vs systemd-networkd 的适用场景
6. Bridge 和 VLAN 基础概念（虚拟化和容器网络基础）

---

## 先跑起来！（5 分钟）

> 在学习理论之前，先用 3 条命令看看你的网络接口。  
> 这就是运维工程师每天都在用的技能。  

```bash
# 1. 查看所有网络接口
ip link show

# 2. 查看接口的 IP 地址
ip addr show

# 3. 查看接口详细信息（网卡型号、速度、双工模式）
# 注意：ethtool 可能需要 sudo
sudo ethtool eth0 2>/dev/null || sudo ethtool ens5 2>/dev/null || echo "尝试你实际的接口名"
```

**你刚刚查看了系统的网络接口配置！**

注意到接口名称了吗？是 `eth0` 还是 `ens5`、`enp0s3`？

这个命名差异正是我们第一个要理解的概念。

---

## Step 1 -- 接口命名演进（10 分钟）

### 1.1 从 ethX 到 Predictable Names

```
传统命名（~2009）                现代命名（2009+）
────────────────────────────────────────────────────────
eth0                   →        ens5, enp0s3, eno1
eth1                   →        enp0s8, ens33
wlan0                  →        wlp2s0
```

**为什么改变？**

传统的 `eth0`、`eth1` 命名有一个致命问题：**重启后顺序可能变化**。

想象这个场景：
- 服务器有两张网卡：管理网（eth0）和业务网（eth1）
- 某次重启后，内核以不同顺序识别网卡
- eth0 和 eth1 互换了
- **结果**：管理流量进入业务网，业务中断

### 1.2 Predictable Network Interface Names

```
┌─────────────────────────────────────────────────────────────────┐
│                    接口命名规则                                  │
├──────────┬──────────────────────────────────────────────────────┤
│ 前缀     │ 含义                                                 │
├──────────┼──────────────────────────────────────────────────────┤
│ en       │ Ethernet（以太网）                                   │
│ wl       │ Wireless LAN（无线网）                               │
│ ww       │ Wireless WAN（移动网络）                             │
│ lo       │ Loopback（环回接口）                                 │
├──────────┼──────────────────────────────────────────────────────┤
│ 后缀类型 │ 含义                               │ 示例            │
├──────────┼────────────────────────────────────┼─────────────────┤
│ oN       │ 主板集成网卡（on-board）           │ eno1, eno2      │
│ sN       │ PCI 热插拔槽位（slot）             │ ens5            │
│ pXsY     │ PCI 总线位置（bus X slot Y）       │ enp0s3          │
│ pXsYfZ   │ 多功能设备（function Z）           │ enp0s3f0        │
└──────────┴────────────────────────────────────┴─────────────────┘
```

### 1.3 动手查看

```bash
# 查看接口名称来源
udevadm info /sys/class/net/$(ls /sys/class/net | grep -E '^en|^eth' | head -1) 2>/dev/null | grep ID_NET_NAME

# 查看网卡驱动信息（哪个硬件对应哪个接口）
dmesg | grep -i eth | head -10

# 列出所有网络接口
ls /sys/class/net/
```

---

## Step 2 -- ip 命令家族（15 分钟）

### 2.1 iproute2 包

`ip` 命令是 **iproute2** 包的核心工具，2009 年起取代了传统的 `ifconfig`、`route`、`arp` 等命令。

```
┌─────────────────────────────────────────────────────────────────┐
│                    ip 命令家族                                   │
├──────────────┬──────────────────────────────────────────────────┤
│ 子命令       │ 功能                         │ 替代的旧命令      │
├──────────────┼──────────────────────────────┼───────────────────┤
│ ip link      │ 接口状态（up/down）          │ ifconfig          │
│ ip addr      │ IP 地址管理                  │ ifconfig          │
│ ip route     │ 路由表管理                   │ route             │
│ ip neigh     │ ARP/邻居表                   │ arp               │
│ ip tunnel    │ 隧道配置                     │ iptunnel          │
│ ip maddr     │ 组播地址                     │ ipmaddr           │
└──────────────┴──────────────────────────────┴───────────────────┘
```

### 2.2 ip link -- 接口状态

```bash
# 查看所有接口
ip link show

# 查看特定接口
ip link show ens5

# 输出解读
# 2: ens5: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 9001 qdisc mq state UP mode DEFAULT group default qlen 1000
#    │      │                                   │           │
#    │      │                                   │           └─ 接口状态（UP/DOWN）
#    │      │                                   └─ MTU 值
#    │      └─ 接口标志（BROADCAST=支持广播，UP=管理启用，LOWER_UP=物理连接）
#    └─ 接口索引

# 启用/禁用接口（需要 sudo）
sudo ip link set ens5 down
sudo ip link set ens5 up
```

### 2.3 ip addr -- IP 地址管理

```bash
# 查看所有接口的 IP 地址
ip addr show
ip a                # 简写

# 只看 IPv4 地址
ip -4 addr show

# 只看 IPv6 地址
ip -6 addr show

# 查看特定接口
ip addr show dev ens5

# 输出解读
# 2: ens5: <BROADCAST,MULTICAST,UP,LOWER_UP> ...
#     inet 192.168.1.10/24 brd 192.168.1.255 scope global ens5
#          │              │   │               │
#          │              │   │               └─ 地址作用域
#          │              │   └─ 广播地址
#          │              └─ 子网掩码（CIDR 表示）
#          └─ IP 地址
```

### 2.4 ip neigh -- 邻居表（ARP）

```bash
# 查看 ARP 表（IP 到 MAC 地址的映射）
ip neigh show

# 输出示例
# 192.168.1.1 dev ens5 lladdr 00:11:22:33:44:55 REACHABLE
#                       │                       │
#                       │                       └─ 状态（REACHABLE/STALE/FAILED）
#                       └─ MAC 地址
```

---

## Step 3 -- 临时 IP 配置（Lab 2）（15 分钟）

> **重要**：`ip` 命令的配置是**临时的**，重启后丢失。  
> 这在测试和排障时很有用，但不适合生产环境的永久配置。  

### 3.1 添加 IP 地址

```bash
# 添加 IP 地址
sudo ip addr add 192.168.100.10/24 dev ens5

# 验证
ip addr show dev ens5

# 一个接口可以有多个 IP 地址（IP 别名）
sudo ip addr add 192.168.100.11/24 dev ens5

# 查看所有地址
ip addr show dev ens5
```

### 3.2 删除 IP 地址

```bash
# 删除特定 IP
sudo ip addr del 192.168.100.11/24 dev ens5

# 删除接口上的所有 IP
sudo ip addr flush dev ens5
```

### 3.3 启用/禁用接口

```bash
# 禁用接口
sudo ip link set ens5 down

# 启用接口
sudo ip link set ens5 up

# 查看状态
ip link show ens5
```

### 3.4 临时配置的用途

| 场景 | 说明 |
|------|------|
| **排障** | 快速测试不同的 IP 配置 |
| **测试** | 验证网络连通性后再持久化 |
| **紧急恢复** | 网络配置损坏时的临时修复 |

---

## Step 4 -- NetworkManager 持久化配置（Lab 3）（20 分钟）

### 4.1 NetworkManager vs systemd-networkd

```
┌────────────────────────────────────────────────────────────────────┐
│                    网络配置管理器对比                               │
├────────────────────┬───────────────────────────────────────────────┤
│ NetworkManager     │ systemd-networkd                              │
├────────────────────┼───────────────────────────────────────────────┤
│ 桌面和服务器通用   │ 专注服务器/容器                               │
│ 支持 WiFi、VPN     │ 不支持 WiFi                                   │
│ 丰富的 GUI/TUI     │ 纯配置文件                                    │
│ nmcli/nmtui        │ networkctl                                    │
│ RHEL/CentOS 默认   │ Ubuntu Server 18.04+ 可选                    │
│ Fedora/Ubuntu 默认 │ 容器/嵌入式常用                               │
└────────────────────┴───────────────────────────────────────────────┘
```

**选择建议**：
- 大多数情况下用 **NetworkManager**（本课重点）
- 极简服务器/容器环境可考虑 **systemd-networkd**

### 4.2 nmcli 基础

```bash
# 检查 NetworkManager 状态
systemctl status NetworkManager

# 查看设备状态
nmcli device status

# 输出示例
# DEVICE  TYPE      STATE      CONNECTION
# ens5    ethernet  connected  Wired connection 1
# lo      loopback  unmanaged  --

# 查看连接配置
nmcli connection show

# 输出示例
# NAME                UUID                                  TYPE      DEVICE
# Wired connection 1  a1b2c3d4-e5f6-7890-abcd-ef1234567890  ethernet  ens5
```

**关键概念**：device（设备） vs connection（连接配置）

```
┌─────────────────────────────────────────────────────────────────┐
│                    device vs connection                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  Device（设备）              Connection（连接配置）              │
│  ────────────────            ──────────────────────              │
│  物理网卡                    配置文件                            │
│  只能有一个活动连接          可以有多个配置                      │
│                                                                  │
│     ens5   ◄─────────────┐                                       │
│     (设备)               │                                       │
│                          │ 活动连接                              │
│                          │                                       │
│            ┌─────────────┴─────────────┐                        │
│            │                           │                        │
│       office-lan               home-wifi                        │
│       (连接配置1)              (连接配置2)                       │
│       静态 IP                  DHCP                              │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 4.3 配置静态 IP

```bash
# 方法 1：修改现有连接
nmcli connection modify "Wired connection 1" \
    ipv4.method manual \
    ipv4.addresses 192.168.1.100/24 \
    ipv4.gateway 192.168.1.1 \
    ipv4.dns "8.8.8.8 8.8.4.4"

# 应用更改
nmcli connection up "Wired connection 1"

# 方法 2：创建新连接
nmcli connection add \
    type ethernet \
    con-name "static-lan" \
    ifname ens5 \
    ipv4.method manual \
    ipv4.addresses 192.168.1.100/24 \
    ipv4.gateway 192.168.1.1 \
    ipv4.dns "8.8.8.8"

# 激活新连接
nmcli connection up "static-lan"
```

### 4.4 配置 DHCP

```bash
# 切换回 DHCP
nmcli connection modify "Wired connection 1" \
    ipv4.method auto \
    ipv4.addresses "" \
    ipv4.gateway "" \
    ipv4.dns ""

# 应用更改
nmcli connection up "Wired connection 1"
```

### 4.5 nmtui -- 文本界面

```bash
# 启动文本界面（更直观）
nmtui
```

这会打开一个交互式菜单，适合不熟悉 nmcli 语法的用户。

### 4.6 验证配置

```bash
# 查看连接详情
nmcli connection show "Wired connection 1"

# 检查实际生效的 IP
ip addr show ens5

# 测试网络连通性
ping -c 3 192.168.1.1
```

---

## Step 5 -- Bridge 和 VLAN 基础（可选，10 分钟）

### 5.1 Bridge（网桥）

网桥将多个网络接口连接在一起，像交换机一样工作。

**常见用途**：
- 虚拟机网络（KVM、VirtualBox）
- 容器网络（Docker bridge）

```bash
# 创建网桥
sudo nmcli connection add type bridge con-name br0 ifname br0

# 将物理接口加入网桥
sudo nmcli connection add type bridge-slave con-name br0-slave ifname ens5 master br0

# 配置网桥 IP
sudo nmcli connection modify br0 \
    ipv4.method manual \
    ipv4.addresses 192.168.1.100/24 \
    ipv4.gateway 192.168.1.1

# 启用网桥
sudo nmcli connection up br0
```

### 5.2 VLAN

VLAN 在同一物理接口上创建多个虚拟接口，每个对应不同的 VLAN ID。

```bash
# 创建 VLAN 接口（VLAN ID 100）
sudo nmcli connection add type vlan \
    con-name vlan100 \
    ifname ens5.100 \
    dev ens5 \
    id 100

# 配置 VLAN IP
sudo nmcli connection modify vlan100 \
    ipv4.method manual \
    ipv4.addresses 10.100.0.10/24

# 启用 VLAN
sudo nmcli connection up vlan100
```

---

## IPv6 快速入门（可选边栏）

> 大多数日本企业环境仍以 IPv4 为主，但了解 IPv6 基础越来越重要，  
> 尤其是云环境和新部署越来越多启用 IPv6。  

### 查看 IPv6 地址

```bash
# 查看 IPv6 地址
ip -6 addr show

# 查看 IPv6 路由
ip -6 route show
```

### 常见地址类型

| 前缀 | 类型 | 说明 |
|------|------|------|
| `fe80::` | 链路本地（Link-Local） | 自动生成，仅本地链路通信 |
| `2001::` | 全局单播（Global Unicast） | 公网可路由地址 |
| `::1` | 环回（Loopback） | 等同于 IPv4 的 127.0.0.1 |
| `fd00::`| 唯一本地（ULA） | 类似 IPv4 私有地址 |

### IPv6 连通性测试

```bash
# 测试环回地址
ping -6 ::1

# 测试链路本地地址（需要指定接口）
ping -6 fe80::1%ens5

# 测试公网 IPv6
ping -6 2001:4860:4860::8888    # Google DNS
```

### 禁用 IPv6（如果不需要）

```bash
# 临时禁用
sudo sysctl -w net.ipv6.conf.all.disable_ipv6=1
sudo sysctl -w net.ipv6.conf.default.disable_ipv6=1

# 永久禁用（写入 /etc/sysctl.conf）
echo "net.ipv6.conf.all.disable_ipv6 = 1" | sudo tee -a /etc/sysctl.conf
echo "net.ipv6.conf.default.disable_ipv6 = 1" | sudo tee -a /etc/sysctl.conf
sudo sysctl -p
```

> **警告**：禁用前确认应用不依赖 IPv6。某些服务默认监听 IPv6 地址。  

---

## 反模式：常见错误

### 错误 1：用 ip 命令以为是永久的

```bash
# 错误：以为这样配置就永久了
sudo ip addr add 192.168.1.10/24 dev ens5
# 重启后配置丢失！

# 正确：使用 nmcli 持久化
nmcli connection modify "Wired connection 1" \
    ipv4.method manual \
    ipv4.addresses 192.168.1.10/24
nmcli connection up "Wired connection 1"
```

**后果**：服务器重启后失去 IP 地址，无法远程连接。

### 错误 2：使用 ifconfig 而不是 ip

```bash
# 过时：ifconfig 从 2009 年起已弃用
ifconfig eth0 192.168.1.10 netmask 255.255.255.0

# 现代：使用 ip 命令
ip addr add 192.168.1.10/24 dev ens5
```

**问题**：
- `ifconfig` 不支持某些现代功能（多个 IP 地址、CIDR 表示法）
- 很多新系统默认不安装 `net-tools` 包
- 日本 IT 现场也在逐步淘汰

### 错误 3：不理解 connection profile vs device

```bash
# 错误理解：以为接口名就是连接名
nmcli connection modify ens5 ipv4.method manual
# Error: Connection 'ens5' not found.

# 正确：先查看连接名
nmcli connection show
# NAME                UUID                                  TYPE      DEVICE
# Wired connection 1  a1b2c3d4-...                          ethernet  ens5

# 使用正确的连接名
nmcli connection modify "Wired connection 1" ipv4.method manual
```

### 错误 4：修改后不重新激活连接

```bash
# 错误：修改后不应用
nmcli connection modify "Wired connection 1" ipv4.addresses 192.168.1.10/24
# 配置已保存但未生效

# 正确：修改后重新激活
nmcli connection modify "Wired connection 1" ipv4.addresses 192.168.1.10/24
nmcli connection up "Wired connection 1"
```

---

## 职场小贴士（Japan IT Context）

### 网络配置变更（ネットワーク設定変更）

在日本 IT 企业，网络配置变更是需要谨慎处理的运维操作。

| 日语术语 | 含义 | 典型场景 |
|----------|------|----------|
| 設定変更 | 配置变更 | 修改 IP 地址、网关 |
| 疎通確認 | 连通性确认 | ping 测试确认网络通 |
| 切り戻し | 回滚 | 变更失败时恢复原配置 |
| エビデンス | 证据/截图 | 变更前后的状态记录 |

### 变更流程

```bash
# 1. 变更前 - 记录当前状态（エビデンス）
ip addr show > /tmp/before-change.txt
nmcli connection show "Wired connection 1" > /tmp/conn-before.txt

# 2. 执行变更
nmcli connection modify "Wired connection 1" ipv4.addresses 192.168.1.100/24

# 3. 应用变更
nmcli connection up "Wired connection 1"

# 4. 疎通確認
ping -c 3 192.168.1.1

# 5. 变更后 - 记录新状态
ip addr show > /tmp/after-change.txt

# 6. 如果失败 - 切り戻し
nmcli connection modify "Wired connection 1" ipv4.addresses 192.168.1.50/24
nmcli connection up "Wired connection 1"
```

### 远程变更的安全网

```bash
# 如果通过 SSH 远程修改 IP，设置自动恢复
# 避免改错 IP 后失去连接

# 方法：使用 at 命令设置定时恢复
echo "nmcli connection up 'Wired connection 1'" | at now + 5 minutes

# 如果变更成功，取消定时任务
atrm $(atq | awk '{print $1}')
```

---

## 面试问题（Interview Prep）

### Q1: ip コマンドと ifconfig の違いは？

**A**: `ip` は iproute2 パッケージの現代ツールで、2009 年から推奨されています。
`ifconfig` は net-tools パッケージで非推奨です。

違い：
- `ip` は CIDR 表記（/24）をサポート、`ifconfig` はサブネットマスク表記
- `ip` は複数 IP アドレスを簡単に管理できる
- `ip` はより詳細な情報を表示（例：state UP/DOWN）
- 多くの新しいディストリビューションで net-tools はデフォルトでインストールされていない

### Q2: NetworkManager で静的 IP を設定する方法は？

**A**: nmcli コマンドを使用：

```bash
nmcli connection modify <conn-name> \
    ipv4.method manual \
    ipv4.addresses x.x.x.x/24 \
    ipv4.gateway y.y.y.y \
    ipv4.dns z.z.z.z
nmcli connection up <conn-name>
```

ポイント：
- `modify` で設定変更、`up` で適用
- 接続名は `nmcli connection show` で確認
- `--permanent` は不要（デフォルトで永続化）

---

## 检查清单

完成本课后，你应该能够：

- [ ] 解释 Predictable Network Interface Names 的命名规则
- [ ] 区分 `ip link`、`ip addr`、`ip route` 的用途
- [ ] 使用 `ip addr add/del` 临时配置 IP 地址
- [ ] 使用 `ip link set up/down` 控制接口状态
- [ ] 使用 `nmcli device status` 查看设备状态
- [ ] 使用 `nmcli connection show` 查看连接配置
- [ ] 使用 `nmcli connection modify` 配置静态 IP
- [ ] 理解 NetworkManager 的 device vs connection 概念
- [ ] 知道 `ifconfig` 已弃用及原因
- [ ] 了解 Bridge 和 VLAN 的基本概念

---

## 本课小结

| 概念 | 命令 | 记忆点 |
|------|------|--------|
| 查看接口 | `ip link show` | 接口状态（UP/DOWN） |
| 查看 IP | `ip addr show` | 地址和子网掩码 |
| 临时添加 IP | `ip addr add` | 重启丢失！ |
| 临时删除 IP | `ip addr del` | 用于测试 |
| 查看设备 | `nmcli device status` | 物理设备状态 |
| 查看连接 | `nmcli connection show` | 配置文件列表 |
| 修改连接 | `nmcli connection modify` | 持久化配置 |
| 应用变更 | `nmcli connection up` | 激活配置 |
| 文本界面 | `nmtui` | 交互式配置 |

---

## 延伸阅读

- [Linux man page: ip](https://man7.org/linux/man-pages/man8/ip.8.html)
- [NetworkManager nmcli examples](https://networkmanager.dev/docs/api/latest/nmcli-examples.html)
- [Predictable Network Interface Names](https://www.freedesktop.org/wiki/Software/systemd/PredictableNetworkInterfaceNames/)
- 下一课：[03 - IP 路由](../03-routing/) -- 理解路由表和静态路由配置
- 相关课程：[systemd 课程](../../systemd/) -- systemd-networkd 详解

---

## 系列导航

[← 01-网络基础](../01-fundamentals/) | [系列首页](../) | [03-IP 路由 →](../03-routing/)
