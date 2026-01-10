# 10 - 网络命名空间 (Network Namespaces)

> **目标**：理解 Linux 网络命名空间，手动构建容器网络，揭开 Docker/K8s 网络的底层原理  
> **前置**：了解基础网络配置、SSH 深入（01-09 课）  
> **时间**：⚡ 15 分钟（速读）/ 🔬 60 分钟（完整实操）  
> **环境**：任意 Linux 发行版（Ubuntu, AlmaLinux, Amazon Linux 均可），需要 root 权限  

---

## 将学到的内容

1. 理解网络命名空间的概念（隔离的网络栈）
2. 使用 ip netns 创建和管理命名空间
3. 使用 veth pair 连接命名空间
4. 配置 Bridge + veth 实现多命名空间互联
5. 配置 NAT 让命名空间访问外网
6. 理解这就是容器网络的底层原理

---

## Step 1 - 先跑起来：5 分钟创建"迷你容器网络"

> **目标**：先体验网络命名空间的魔力，再理解原理。  

### 1.1 创建两个隔离的网络环境

```bash
# 创建两个网络命名空间（类似两个"容器"）
sudo ip netns add container1
sudo ip netns add container2

# 验证创建成功
ip netns list
```

```
container2
container1
```

### 1.2 体验隔离性

```bash
# 在 container1 中查看网络接口
sudo ip netns exec container1 ip addr
```

```
1: lo: <LOOPBACK> mtu 65536 qdisc noop state DOWN group default qlen 1000
    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
```

**只有一个未启用的 lo 接口！** 这就是隔离——命名空间内看不到主机的 eth0、docker0 等任何网络接口。

### 1.3 用"虚拟网线"连接两个容器

```bash
# 创建一对 veth（虚拟以太网）设备
sudo ip link add veth1 type veth peer name veth2

# 把 veth1 放入 container1
sudo ip link set veth1 netns container1

# 把 veth2 放入 container2
sudo ip link set veth2 netns container2

# 配置 IP 地址
sudo ip netns exec container1 ip addr add 10.0.0.1/24 dev veth1
sudo ip netns exec container2 ip addr add 10.0.0.2/24 dev veth2

# 启动接口
sudo ip netns exec container1 ip link set veth1 up
sudo ip netns exec container2 ip link set veth2 up
sudo ip netns exec container1 ip link set lo up
sudo ip netns exec container2 ip link set lo up
```

### 1.4 见证奇迹：两个"容器"通信

```bash
# 从 container1 ping container2
sudo ip netns exec container1 ping -c 3 10.0.0.2
```

```
PING 10.0.0.2 (10.0.0.2) 56(84) bytes of data.
64 bytes from 10.0.0.2: icmp_seq=1 ttl=64 time=0.050 ms
64 bytes from 10.0.0.2: icmp_seq=2 ttl=64 time=0.038 ms
64 bytes from 10.0.0.2: icmp_seq=3 ttl=64 time=0.042 ms
```

**成功！两个完全隔离的网络环境通过 veth pair 连接起来了。**

---

**恭喜！你刚刚手动实现了 Docker 容器网络的核心机制！**

| 你做的 | Docker 自动做的 |
|--------|----------------|
| `ip netns add` | 每个容器创建一个 netns |
| `ip link add veth` | 创建 veth pair |
| `ip addr add` | 分配容器 IP |

接下来，让我们深入理解这些概念。

---

## Step 2 - 发生了什么？命名空间的本质（10 分钟）

### 2.1 什么是网络命名空间？

<!-- DIAGRAM: network-namespace-concept -->
```
网络命名空间 - 隔离的网络栈
================================================================================

默认命名空间（主机）                    container1 命名空间
─────────────────────────               ─────────────────────────
┌─────────────────────────────┐         ┌─────────────────────────────┐
│  网络接口                   │         │  网络接口                   │
│  ├── lo (127.0.0.1)         │         │  ├── lo (127.0.0.1)         │
│  ├── eth0 (192.168.1.10)    │         │  └── veth1 (10.0.0.1)       │
│  ├── docker0 (172.17.0.1)   │         │                             │
│  └── ...                    │         │  路由表                     │
│                             │         │  └── 10.0.0.0/24 dev veth1  │
│  路由表                     │         │                             │
│  ├── default via 192.168.1.1│         │  防火墙规则                 │
│  └── 10.0.0.0/8 dev docker0 │         │  └── (独立的 nftables)      │
│                             │         │                             │
│  防火墙规则                 │         │  套接字                     │
│  └── (nftables/iptables)    │         │  └── 监听端口独立           │
│                             │         │                             │
│  /proc/net/*                │         │  /proc/net/*                │
│  └── 网络统计信息           │         │  └── 独立的统计信息         │
└─────────────────────────────┘         └─────────────────────────────┘
        │                                       │
        │  完全隔离！                           │
        │  • 看不到对方的接口                   │
        │  • 独立的路由表                       │
        │  • 独立的防火墙规则                   │
        │  • 独立的端口空间                     │
        │                                       │
        └───────── 除非用 veth 连接 ────────────┘
```
<!-- /DIAGRAM -->

**命名空间提供的隔离**：

| 隔离项 | 说明 |
|--------|------|
| 网络接口 | 每个命名空间有独立的接口列表 |
| IP 地址 | 同一个 IP 可以在不同命名空间中使用 |
| 路由表 | 独立的路由决策 |
| 防火墙规则 | 独立的 nftables/iptables |
| 端口空间 | 不同命名空间可以监听相同端口 |
| /proc/net | 独立的网络统计信息 |

### 2.2 Linux 的 7 种命名空间

网络命名空间只是 Linux 命名空间家族的一员：

| 命名空间 | 隔离的内容 | 容器用途 |
|----------|-----------|----------|
| **Network (net)** | 网络栈 | 容器独立网络 |
| **PID** | 进程 ID | 容器只看到自己的进程 |
| **Mount (mnt)** | 文件系统挂载点 | 容器独立的文件系统视图 |
| **UTS** | 主机名 | 容器独立主机名 |
| **IPC** | 进程间通信 | 隔离共享内存、信号量 |
| **User** | 用户 ID | 容器内的 root 不是真 root |
| **Cgroup** | cgroup 根目录 | 资源限制隔离 |

**Docker/容器 = 所有命名空间的组合 + cgroups 资源限制**

---

## Step 3 - ip netns 命令详解（10 分钟）

### 3.1 基本操作

```bash
# 创建命名空间
sudo ip netns add myns

# 列出所有命名空间
ip netns list

# 在命名空间中执行命令
sudo ip netns exec myns <command>

# 删除命名空间
sudo ip netns delete myns
```

### 3.2 命名空间内常用检查

```bash
# 查看接口
sudo ip netns exec container1 ip addr

# 查看路由表
sudo ip netns exec container1 ip route

# 查看连接状态
sudo ip netns exec container1 ss -tuln

# 启动 shell（交互式）
sudo ip netns exec container1 bash
# 现在你"进入"了命名空间
ip addr  # 只能看到命名空间内的接口
exit     # 退出
```

### 3.3 命名空间文件

```bash
# 命名空间实际是 /var/run/netns/ 下的文件
ls -la /var/run/netns/
```

```
total 0
drwxr-xr-x  2 root root   80 Jan  5 10:00 .
drwxr-xr-x 41 root root 1180 Jan  5 09:00 ..
-r--r--r--  1 root root    0 Jan  5 10:00 container1
-r--r--r--  1 root root    0 Jan  5 10:00 container2
```

这些文件是指向 `/proc/<pid>/ns/net` 的绑定挂载。

---

## Step 4 - veth pair：虚拟网线（10 分钟）

### 4.1 veth 是什么？

veth（Virtual Ethernet）是成对出现的虚拟网络设备，就像一根虚拟网线：
- 从一端发送的数据包会从另一端出来
- 两端可以分别放在不同的命名空间

<!-- DIAGRAM: veth-pair-concept -->
```
veth pair - 虚拟以太网电缆
================================================================================

创建前：

    ip link add veth1 type veth peer name veth2

创建后：
    ┌──────────────────────────────────────────────────────────────┐
    │                      默认命名空间                             │
    │                                                              │
    │         ┌──────┐                      ┌──────┐               │
    │         │veth1 │══════════════════════│veth2 │               │
    │         └──────┘     虚拟网线         └──────┘               │
    │                                                              │
    └──────────────────────────────────────────────────────────────┘

移动 veth1 到 container1：

    ip link set veth1 netns container1

    ┌────────────────────────┐              ┌────────────────────────┐
    │   container1 命名空间   │              │      默认命名空间       │
    │                        │              │                        │
    │      ┌──────┐          │              │          ┌──────┐      │
    │      │veth1 │══════════════════════════════════════│veth2 │      │
    │      └──────┘          │   穿越边界   │          └──────┘      │
    │      10.0.0.1          │              │                        │
    │                        │              │                        │
    └────────────────────────┘              └────────────────────────┘

两端都移动后：

    ┌────────────────────────┐              ┌────────────────────────┐
    │   container1 命名空间   │              │   container2 命名空间   │
    │                        │              │                        │
    │      ┌──────┐          │              │          ┌──────┐      │
    │      │veth1 │══════════════════════════════════════│veth2 │      │
    │      └──────┘          │              │          └──────┘      │
    │      10.0.0.1          │              │          10.0.0.2      │
    │                        │              │                        │
    └────────────────────────┘              └────────────────────────┘

    两个隔离的网络空间现在可以通信了！
```
<!-- /DIAGRAM -->

### 4.2 veth pair 操作

```bash
# 创建 veth pair
sudo ip link add veth-host type veth peer name veth-ns

# 查看创建的设备（两个一起出现）
ip link show type veth
```

```
5: veth-ns@veth-host: <BROADCAST,MULTICAST,M-DOWN> mtu 1500 qdisc noop state DOWN mode DEFAULT group default qlen 1000
6: veth-host@veth-ns: <BROADCAST,MULTICAST,M-DOWN> mtu 1500 qdisc noop state DOWN mode DEFAULT group default qlen 1000
```

注意 `veth-ns@veth-host` 表示 veth-ns 的对端是 veth-host。

### 4.3 常见陷阱：忘记 up

```bash
# 创建 veth 后，默认是 DOWN 状态
ip link show veth-host
```

```
6: veth-host@veth-ns: <BROADCAST,MULTICAST> mtu 1500 qdisc noop state DOWN ...
```

**必须手动启动**：

```bash
sudo ip link set veth-host up
sudo ip link set veth-ns up
```

---

## Step 5 - Bridge + veth：多命名空间互联（15 分钟）

两个命名空间可以用 veth pair 直连。但如果有多个命名空间呢？

### 5.1 问题：多容器互联

<!-- DIAGRAM: bridge-necessity -->
```
问题：多命名空间如何互联？
================================================================================

方案 A：全连接（不可扩展）

    ┌─────┐      ┌─────┐      ┌─────┐
    │ NS1 │──────│ NS2 │──────│ NS3 │
    └──┬──┘      └─────┘      └──┬──┘
       │                         │
       └─────────────────────────┘

    3 个命名空间需要 3 对 veth
    4 个命名空间需要 6 对 veth
    N 个命名空间需要 N*(N-1)/2 对 veth

    ❌ 不可扩展！

方案 B：使用 Bridge（Docker 的做法）

                   ┌─────────────────────────────────────┐
                   │            Bridge (br0)              │
                   │          172.17.0.1/16               │
                   └───┬──────────┬──────────┬───────────┘
                       │          │          │
                    ┌──┴──┐    ┌──┴──┐    ┌──┴──┐
                    │veth │    │veth │    │veth │
                    └──┬──┘    └──┬──┘    └──┬──┘
    ┌─────────────────┐│┌─────────────────┐│┌─────────────────┐
    │   container1    │││   container2    │││   container3    │
    │   172.17.0.2    │││   172.17.0.3    │││   172.17.0.4    │
    └─────────────────┘│└─────────────────┘│└─────────────────┘

    N 个命名空间只需要 N 对 veth + 1 个 bridge

    ✓ 可扩展！
```
<!-- /DIAGRAM -->

### 5.2 动手实验：构建 Bridge 网络

先清理之前的实验：

```bash
sudo ip netns delete container1 2>/dev/null
sudo ip netns delete container2 2>/dev/null
```

创建完整的 Bridge 网络：

```bash
# Step 1: 创建 Bridge
sudo ip link add br0 type bridge
sudo ip addr add 172.20.0.1/24 dev br0
sudo ip link set br0 up

# Step 2: 创建两个命名空间
sudo ip netns add ns1
sudo ip netns add ns2

# Step 3: 为 ns1 创建 veth pair 并连接到 bridge
sudo ip link add veth-ns1 type veth peer name veth-br1
sudo ip link set veth-ns1 netns ns1
sudo ip link set veth-br1 master br0
sudo ip link set veth-br1 up
sudo ip netns exec ns1 ip addr add 172.20.0.10/24 dev veth-ns1
sudo ip netns exec ns1 ip link set veth-ns1 up
sudo ip netns exec ns1 ip link set lo up

# Step 4: 为 ns2 创建 veth pair 并连接到 bridge
sudo ip link add veth-ns2 type veth peer name veth-br2
sudo ip link set veth-ns2 netns ns2
sudo ip link set veth-br2 master br0
sudo ip link set veth-br2 up
sudo ip netns exec ns2 ip addr add 172.20.0.20/24 dev veth-ns2
sudo ip netns exec ns2 ip link set veth-ns2 up
sudo ip netns exec ns2 ip link set lo up

# Step 5: 在命名空间内添加默认路由
sudo ip netns exec ns1 ip route add default via 172.20.0.1
sudo ip netns exec ns2 ip route add default via 172.20.0.1
```

### 5.3 验证连通性

```bash
# ns1 ping ns2
sudo ip netns exec ns1 ping -c 2 172.20.0.20
```

```
PING 172.20.0.20 (172.20.0.20) 56(84) bytes of data.
64 bytes from 172.20.0.20: icmp_seq=1 ttl=64 time=0.062 ms
64 bytes from 172.20.0.20: icmp_seq=2 ttl=64 time=0.048 ms
```

```bash
# ns1 ping bridge（主机）
sudo ip netns exec ns1 ping -c 2 172.20.0.1
```

```
PING 172.20.0.1 (172.20.0.1) 56(84) bytes of data.
64 bytes from 172.20.0.1: icmp_seq=1 ttl=64 time=0.035 ms
64 bytes from 172.20.0.1: icmp_seq=2 ttl=64 time=0.041 ms
```

### 5.4 查看 Bridge 状态

```bash
# 查看 bridge 接口
bridge link show
```

```
3: veth-br1@if4: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 master br0 state forwarding
5: veth-br2@if6: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 master br0 state forwarding
```

```bash
# 或使用 brctl（需要安装 bridge-utils）
brctl show br0
```

---

## Step 6 - NAT：让命名空间访问外网（10 分钟）

现在 ns1 和 ns2 可以互相通信，也能访问主机。但能访问外网吗？

### 6.1 测试外网访问

```bash
# 尝试从 ns1 ping 外网
sudo ip netns exec ns1 ping -c 2 8.8.8.8
```

```
PING 8.8.8.8 (8.8.8.8) 56(84) bytes of data.
--- 8.8.8.8 ping statistics ---
2 packets transmitted, 0 received, 100% packet loss, time 1001ms
```

**失败！** 因为外网不知道如何回复 172.20.0.10（私有 IP）。

### 6.2 解决方案：NAT（网络地址转换）

<!-- DIAGRAM: nat-for-namespaces -->
```
NAT 让私有 IP 访问外网
================================================================================

问题：外网不认识 172.20.0.10

    ns1 (172.20.0.10)                               8.8.8.8
    ┌─────────────────┐                        ┌─────────────────┐
    │                 │  src: 172.20.0.10      │                 │
    │  ping 8.8.8.8   │ ────────────────────▶  │  Google DNS     │
    │                 │                        │                 │
    │                 │  ??? 172.20.0.10 是谁？│                 │
    │                 │ ◀──────── ✗ ──────────│  无法回复       │
    └─────────────────┘                        └─────────────────┘

解决：MASQUERADE（伪装）

    ns1 (172.20.0.10)         主机 (eth0)              8.8.8.8
    ┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
    │                 │    │                 │    │                 │
    │  ping 8.8.8.8   │───▶│  NAT 转换       │───▶│  Google DNS     │
    │                 │    │  src: 172.20... │    │                 │
    │                 │    │   → 主机公网 IP  │    │                 │
    │                 │    │                 │    │                 │
    │                 │◀───│  NAT 还原       │◀───│  回复到主机 IP   │
    │  收到回复       │    │  dst: 主机 IP   │    │                 │
    │                 │    │   → 172.20.0.10 │    │                 │
    └─────────────────┘    └─────────────────┘    └─────────────────┘

    外网只看到主机的 IP，不知道 172.20.0.10 的存在
```
<!-- /DIAGRAM -->

### 6.3 配置 NAT

```bash
# Step 1: 启用 IP 转发
sudo sysctl -w net.ipv4.ip_forward=1

# Step 2: 添加 MASQUERADE 规则（使用 nftables）
# 首先检查是否有现有的 nat 表
sudo nft list tables | grep nat

# 创建 NAT 规则
sudo nft add table ip nat 2>/dev/null || true
sudo nft add chain ip nat postrouting '{ type nat hook postrouting priority 100; }' 2>/dev/null || true
sudo nft add rule ip nat postrouting ip saddr 172.20.0.0/24 oif != "br0" masquerade
```

如果系统使用 iptables：

```bash
# iptables 版本（二选一）
sudo iptables -t nat -A POSTROUTING -s 172.20.0.0/24 ! -o br0 -j MASQUERADE
```

### 6.4 验证外网访问

```bash
# 再次测试
sudo ip netns exec ns1 ping -c 2 8.8.8.8
```

```
PING 8.8.8.8 (8.8.8.8) 56(84) bytes of data.
64 bytes from 8.8.8.8: icmp_seq=1 ttl=116 time=5.12 ms
64 bytes from 8.8.8.8: icmp_seq=2 ttl=116 time=4.89 ms
```

**成功！** 命名空间现在可以访问外网了。

### 6.5 测试 DNS 解析

```bash
# 测试 DNS（需要配置 resolv.conf）
sudo mkdir -p /etc/netns/ns1
echo "nameserver 8.8.8.8" | sudo tee /etc/netns/ns1/resolv.conf

# 测试解析
sudo ip netns exec ns1 ping -c 2 google.com
```

---

## Step 7 - 这就是容器网络！（5 分钟）

### 7.1 对比 Docker 网络

你刚才手动做的，Docker 自动帮你做：

| 你做的 | Docker 做的 |
|--------|-------------|
| `ip netns add ns1` | `docker run` 创建容器时自动创建 netns |
| `ip link add br0 type bridge` | 创建 `docker0` bridge |
| `ip link add veth... peer name veth...` | 创建 veth pair |
| `ip link set veth-ns1 netns ns1` | 把 veth 一端放入容器 netns |
| `ip addr add 172.20.0.10/24` | 从 IPAM 分配 IP 给容器 |
| NAT masquerade | 配置 iptables NAT 规则 |

### 7.2 查看 Docker 的网络命名空间

```bash
# 运行一个容器
docker run -d --name test-nginx nginx

# 找到容器的 PID
CONTAINER_PID=$(docker inspect -f '{{.State.Pid}}' test-nginx)
echo $CONTAINER_PID

# 创建指向容器 netns 的符号链接（让 ip netns 能看到）
sudo ln -sf /proc/$CONTAINER_PID/ns/net /var/run/netns/docker-test

# 现在可以用 ip netns 查看容器网络
sudo ip netns exec docker-test ip addr
```

```
1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN group default qlen 1000
    inet 127.0.0.1/8 scope host lo
17: eth0@if18: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue state UP group default
    inet 172.17.0.2/16 brd 172.17.255.255 scope global eth0
```

清理：

```bash
docker stop test-nginx && docker rm test-nginx
sudo rm /var/run/netns/docker-test
```

### 7.3 Kubernetes 网络

K8s 使用 CNI（Container Network Interface）插件，但底层原理相同：

```
K8s Pod 网络（以 Calico 为例）
================================================================================

    ┌─────────────────────────────────────────────────────────────────────┐
    │                          Node 1                                     │
    │  ┌────────────────────┐      ┌────────────────────┐                 │
    │  │      Pod A          │      │      Pod B          │                 │
    │  │  ┌──────────────┐  │      │  ┌──────────────┐  │                 │
    │  │  │  Container   │  │      │  │  Container   │  │                 │
    │  │  │  10.0.1.2    │  │      │  │  10.0.1.3    │  │                 │
    │  │  └──────┬───────┘  │      │  └──────┬───────┘  │                 │
    │  │         │ veth     │      │         │ veth     │                 │
    │  └─────────┼──────────┘      └─────────┼──────────┘                 │
    │            │                           │                            │
    │  ──────────┴───────────────────────────┴────────────────            │
    │                     CNI 网络（路由/隧道）                            │
    └─────────────────────────────────────────────────────────────────────┘

    Pod = netns + veth + CNI 配置
```

---

## Mini Project：手动构建容器网络

### 项目说明

完整构建一个包含两个"容器"的网络环境：
1. 两个命名空间通过 bridge 连接
2. 命名空间可以互相通信
3. 命名空间可以访问外网
4. 包含完整的清理脚本

### 完整脚本

创建文件 `container-network-setup.sh`：

```bash
#!/bin/bash
# container-network-setup.sh
# 手动构建容器网络演示脚本

set -e  # 出错即退出

# 配置
BRIDGE_NAME="demo-br0"
BRIDGE_IP="192.168.100.1/24"
BRIDGE_SUBNET="192.168.100.0/24"
NS1_NAME="demo-ns1"
NS1_IP="192.168.100.10/24"
NS2_NAME="demo-ns2"
NS2_IP="192.168.100.20/24"

# 颜色
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}======================================${NC}"
echo -e "${GREEN}手动构建容器网络${NC}"
echo -e "${GREEN}======================================${NC}"
echo ""

# 检查 root
if [ "$EUID" -ne 0 ]; then
    echo "请使用 sudo 运行此脚本"
    exit 1
fi

# Step 1: 创建 Bridge
echo -e "${YELLOW}[Step 1] 创建 Bridge: $BRIDGE_NAME${NC}"
ip link add $BRIDGE_NAME type bridge
ip addr add $BRIDGE_IP dev $BRIDGE_NAME
ip link set $BRIDGE_NAME up
echo "  Bridge IP: $BRIDGE_IP"

# Step 2: 创建命名空间
echo -e "${YELLOW}[Step 2] 创建命名空间${NC}"
ip netns add $NS1_NAME
ip netns add $NS2_NAME
echo "  创建: $NS1_NAME, $NS2_NAME"

# Step 3: 为 NS1 创建 veth 并连接
echo -e "${YELLOW}[Step 3] 配置 $NS1_NAME${NC}"
ip link add veth-$NS1_NAME type veth peer name veth-br-$NS1_NAME
ip link set veth-$NS1_NAME netns $NS1_NAME
ip link set veth-br-$NS1_NAME master $BRIDGE_NAME
ip link set veth-br-$NS1_NAME up
ip netns exec $NS1_NAME ip addr add $NS1_IP dev veth-$NS1_NAME
ip netns exec $NS1_NAME ip link set veth-$NS1_NAME up
ip netns exec $NS1_NAME ip link set lo up
ip netns exec $NS1_NAME ip route add default via 192.168.100.1
echo "  $NS1_NAME IP: $NS1_IP"

# Step 4: 为 NS2 创建 veth 并连接
echo -e "${YELLOW}[Step 4] 配置 $NS2_NAME${NC}"
ip link add veth-$NS2_NAME type veth peer name veth-br-$NS2_NAME
ip link set veth-$NS2_NAME netns $NS2_NAME
ip link set veth-br-$NS2_NAME master $BRIDGE_NAME
ip link set veth-br-$NS2_NAME up
ip netns exec $NS2_NAME ip addr add $NS2_IP dev veth-$NS2_NAME
ip netns exec $NS2_NAME ip link set veth-$NS2_NAME up
ip netns exec $NS2_NAME ip link set lo up
ip netns exec $NS2_NAME ip route add default via 192.168.100.1
echo "  $NS2_NAME IP: $NS2_IP"

# Step 5: 配置 NAT
echo -e "${YELLOW}[Step 5] 配置 NAT（外网访问）${NC}"
sysctl -w net.ipv4.ip_forward=1 > /dev/null
# 获取默认出口接口
DEFAULT_IF=$(ip route | grep default | awk '{print $5}' | head -1)
# 使用 iptables（兼容性更好）
iptables -t nat -A POSTROUTING -s $BRIDGE_SUBNET -o $DEFAULT_IF -j MASQUERADE
echo "  IP 转发已启用"
echo "  NAT 规则已添加（出口: $DEFAULT_IF）"

# Step 6: 配置 DNS
echo -e "${YELLOW}[Step 6] 配置 DNS${NC}"
mkdir -p /etc/netns/$NS1_NAME /etc/netns/$NS2_NAME
echo "nameserver 8.8.8.8" > /etc/netns/$NS1_NAME/resolv.conf
echo "nameserver 8.8.8.8" > /etc/netns/$NS2_NAME/resolv.conf
echo "  DNS 已配置 (8.8.8.8)"

echo ""
echo -e "${GREEN}======================================${NC}"
echo -e "${GREEN}配置完成！${NC}"
echo -e "${GREEN}======================================${NC}"
echo ""
echo "测试命令："
echo "  # NS1 ping NS2"
echo "  sudo ip netns exec $NS1_NAME ping -c 2 192.168.100.20"
echo ""
echo "  # NS1 ping 外网"
echo "  sudo ip netns exec $NS1_NAME ping -c 2 8.8.8.8"
echo ""
echo "  # NS1 访问网站"
echo "  sudo ip netns exec $NS1_NAME curl -s http://example.com | head -5"
echo ""
echo "  # 进入 NS1 shell"
echo "  sudo ip netns exec $NS1_NAME bash"
echo ""
echo "清理命令："
echo "  sudo ./container-network-cleanup.sh"
```

创建清理脚本 `container-network-cleanup.sh`：

```bash
#!/bin/bash
# container-network-cleanup.sh
# 清理手动创建的容器网络

set -e

# 配置（与 setup 脚本一致）
BRIDGE_NAME="demo-br0"
BRIDGE_SUBNET="192.168.100.0/24"
NS1_NAME="demo-ns1"
NS2_NAME="demo-ns2"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}======================================${NC}"
echo -e "${GREEN}清理容器网络${NC}"
echo -e "${GREEN}======================================${NC}"
echo ""

if [ "$EUID" -ne 0 ]; then
    echo "请使用 sudo 运行此脚本"
    exit 1
fi

# 删除命名空间（会自动清理其中的 veth）
echo -e "${YELLOW}[Step 1] 删除命名空间${NC}"
ip netns delete $NS1_NAME 2>/dev/null && echo "  删除: $NS1_NAME" || echo "  $NS1_NAME 不存在"
ip netns delete $NS2_NAME 2>/dev/null && echo "  删除: $NS2_NAME" || echo "  $NS2_NAME 不存在"

# 删除 Bridge（会自动删除连接的 veth 端）
echo -e "${YELLOW}[Step 2] 删除 Bridge${NC}"
ip link delete $BRIDGE_NAME 2>/dev/null && echo "  删除: $BRIDGE_NAME" || echo "  $BRIDGE_NAME 不存在"

# 删除 NAT 规则
echo -e "${YELLOW}[Step 3] 清理 NAT 规则${NC}"
DEFAULT_IF=$(ip route | grep default | awk '{print $5}' | head -1)
iptables -t nat -D POSTROUTING -s $BRIDGE_SUBNET -o $DEFAULT_IF -j MASQUERADE 2>/dev/null && echo "  NAT 规则已删除" || echo "  NAT 规则不存在"

# 清理 DNS 配置
echo -e "${YELLOW}[Step 4] 清理 DNS 配置${NC}"
rm -rf /etc/netns/$NS1_NAME /etc/netns/$NS2_NAME 2>/dev/null && echo "  DNS 配置已清理" || echo "  DNS 配置不存在"

echo ""
echo -e "${GREEN}======================================${NC}"
echo -e "${GREEN}清理完成！${NC}"
echo -e "${GREEN}======================================${NC}"
```

### 使用方法

```bash
# 添加执行权限
chmod +x container-network-setup.sh
chmod +x container-network-cleanup.sh

# 运行设置
sudo ./container-network-setup.sh

# 测试
sudo ip netns exec demo-ns1 ping -c 2 192.168.100.20
sudo ip netns exec demo-ns1 ping -c 2 8.8.8.8
sudo ip netns exec demo-ns1 curl -s http://example.com | head -5

# 清理
sudo ./container-network-cleanup.sh
```

---

## 清理本课所有实验

```bash
# 清理 Step 1-4 的实验
sudo ip netns delete container1 2>/dev/null
sudo ip netns delete container2 2>/dev/null

# 清理 Step 5-6 的实验
sudo ip netns delete ns1 2>/dev/null
sudo ip netns delete ns2 2>/dev/null
sudo ip link delete br0 2>/dev/null

# 清理 NAT 规则
sudo nft delete rule ip nat postrouting handle $(sudo nft -a list chain ip nat postrouting | grep "192.168.100.0/24\|172.20.0.0/24" | awk '{print $NF}') 2>/dev/null
# 或 iptables
sudo iptables -t nat -D POSTROUTING -s 172.20.0.0/24 ! -o br0 -j MASQUERADE 2>/dev/null

# 清理 Mini Project
sudo ./container-network-cleanup.sh 2>/dev/null

# 验证清理
ip netns list  # 应该为空（或只有系统原有的）
bridge link show  # 应该不显示我们创建的 bridge
```

---

## 职场小贴士

### 日本 IT 常用术语

| 日本语 | 中文 | 场景 |
|--------|------|------|
| 名前空間 | 命名空间 | ネットワーク名前空間 |
| コンテナネットワーク | 容器网络 | Docker/K8s 网络讨论 |
| ブリッジネットワーク | Bridge 网络 | docker0 类型 |
| NAT | NAT | 私有 IP 访问外网 |
| 仮想インターフェース | 虚拟接口 | veth 设备 |
| ネットワーク分離 | 网络隔离 | 安全架构讨论 |

### 面试常见问题

**Q: ネットワーク名前空間とは？**

A: Linux カーネルの機能で、隔離されたネットワークスタックを提供します。各名前空間は独自のネットワークインターフェース、ルーティングテーブル、ファイアウォールルール、ポート空間を持ちます。これがコンテナのネットワーク分離の基盤です。

**Q: Docker のブリッジネットワークの仕組みは？**

A: Docker は各コンテナに netns を作成し、veth ペアを使って docker0 ブリッジに接続します。コンテナ側に IP を割り当て、NAT（MASQUERADE）で外部通信を可能にします。同じブリッジに接続されたコンテナ同士は直接通信できます。

**Q: veth ペアとは？**

A: 仮想イーサネットデバイスで、必ずペアで作成されます。一端から入ったパケットはもう一端から出てきます。異なる名前空間を接続するために使用され、コンテナネットワークの基本要素です。

---

## 本课小结

| 你学到的 | 命令/概念 |
|----------|-----------|
| 创建命名空间 | `ip netns add <name>` |
| 在命名空间中执行命令 | `ip netns exec <ns> <cmd>` |
| 创建 veth pair | `ip link add veth1 type veth peer name veth2` |
| 移动接口到命名空间 | `ip link set <dev> netns <ns>` |
| 创建 Bridge | `ip link add br0 type bridge` |
| 连接到 Bridge | `ip link set <dev> master <bridge>` |
| 配置 NAT | `nft add rule ip nat postrouting masquerade` |

**核心理念**：

```
网络命名空间 = 隔离的网络栈

容器网络 = netns + veth + bridge + NAT

排障要点：
• 命名空间内有独立的路由表，需要配置默认路由
• veth 创建后默认是 DOWN，必须手动 up
• 访问外网需要 NAT + IP 转发
• 不理解命名空间 → Docker 网络排障困难
```

---

## 反模式警示

| 错误做法 | 正确做法 |
|----------|----------|
| 不理解命名空间就排查 Docker 网络 | 先理解底层原理，再排查上层问题 |
| 忘记在命名空间内配置默认路由 | `ip route add default via <gateway>` |
| 创建 veth 后忘记 up | `ip link set <dev> up` |
| 忘记启用 IP 转发 | `sysctl -w net.ipv4.ip_forward=1` |
| 清理时只删命名空间 | 同时清理 bridge、NAT 规则、DNS 配置 |

---

## 检查清单

在继续下一课之前，确认你能：

- [ ] 使用 `ip netns add/delete` 创建和删除命名空间
- [ ] 使用 `ip netns exec` 在命名空间中执行命令
- [ ] 创建 veth pair 并移动到命名空间
- [ ] 配置 Bridge 连接多个命名空间
- [ ] 配置 NAT 让命名空间访问外网
- [ ] 解释命名空间提供了哪些隔离
- [ ] 解释 Docker bridge 网络的工作原理
- [ ] 完整清理实验环境

---

## 延伸阅读

- [Linux Network Namespaces - man page](https://man7.org/linux/man-pages/man8/ip-netns.8.html)
- [Docker Networking Overview](https://docs.docker.com/network/)
- [Kubernetes Networking Model](https://kubernetes.io/docs/concepts/cluster-administration/networking/)
- [Linux Bridge - Kernel Documentation](https://wiki.linuxfoundation.org/networking/bridge)
- [Container Networking From Scratch - nullday](https://github.com/lizrice/containers-from-scratch)

---

## 下一步

你已经理解了容器网络的底层原理——网络命名空间。接下来，让我们学习系统性的网络故障排查方法论，将所有知识整合成实战工作流。

[11 - 故障排查工作流 ->](../11-troubleshooting/)

---

## 系列导航

[<- 09 - SSH 深入](../09-ssh/) | [Home](/) | [11 - 故障排查工作流 ->](../11-troubleshooting/)
