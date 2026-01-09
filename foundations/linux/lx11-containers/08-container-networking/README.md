# 08 - 容器网络：veth、Bridge 与 NAT

> **目标**：深入理解容器网络原理 —— 手动配置 veth pair、bridge、NAT，掌握 nsenter 网络调试  
> **前置**：[Lesson 07 - OverlayFS](../07-overlay-filesystems/)、[LX06 - 网络基础](../../network/)  
> **时间**：2.5 小时  
> **环境**：Linux 系统（建议 Ubuntu 22.04+ / RHEL 9+，需要 root 权限）  

---

## 将学到的内容

1. 理解容器网络的 veth pair 机制
2. 手动配置 network namespace + veth + bridge 网络
3. 使用 nftables 配置容器 NAT（现代方案，不用 iptables）
4. 使用 nsenter 调试 Distroless 容器网络
5. 排查「容器网络不通」的常见问题

---

## 先跑起来：5 分钟创建容器网络

> **不讲原理，先动手！** 你马上就能让隔离的 network namespace 访问外网。  

### 创建隔离网络环境

```bash
# 1. 创建 network namespace（模拟容器网络隔离）
sudo ip netns add mycontainer

# 2. 验证隔离效果——没有任何网络接口（除了 lo）
sudo ip netns exec mycontainer ip addr
```

输出：

```
1: lo: <LOOPBACK> mtu 65536 qdisc noop state DOWN group default qlen 1000
    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
```

**注意**：只有 lo（loopback），没有 eth0！这就是网络隔离。

### 连接到宿主机网络

```bash
# 3. 创建 veth pair（虚拟网线）
sudo ip link add veth-host type veth peer name veth-container

# 4. 把一端放进 namespace
sudo ip link set veth-container netns mycontainer

# 5. 配置 IP 地址
sudo ip addr add 172.18.0.1/24 dev veth-host
sudo ip netns exec mycontainer ip addr add 172.18.0.2/24 dev veth-container

# 6. 启动接口
sudo ip link set veth-host up
sudo ip netns exec mycontainer ip link set veth-container up
sudo ip netns exec mycontainer ip link set lo up

# 7. 设置默认路由
sudo ip netns exec mycontainer ip route add default via 172.18.0.1
```

### 测试连通性

```bash
# 从 namespace ping 宿主机
sudo ip netns exec mycontainer ping -c 3 172.18.0.1
```

输出：

```
PING 172.18.0.1 (172.18.0.1) 56(84) bytes of data.
64 bytes from 172.18.0.1: icmp_seq=1 ttl=64 time=0.055 ms
64 bytes from 172.18.0.1: icmp_seq=2 ttl=64 time=0.044 ms
64 bytes from 172.18.0.1: icmp_seq=3 ttl=64 time=0.042 ms
```

**成功！** 隔离的 namespace 可以和宿主机通信了。

### 配置 NAT 访问外网

```bash
# 8. 启用 IP 转发
echo 1 | sudo tee /proc/sys/net/ipv4/ip_forward

# 9. 使用 nftables 配置 NAT（现代方案）
sudo nft add table ip nat
sudo nft add chain ip nat postrouting { type nat hook postrouting priority 100 \; }
sudo nft add rule ip nat postrouting ip saddr 172.18.0.0/24 masquerade

# 10. 测试访问外网
sudo ip netns exec mycontainer ping -c 3 8.8.8.8
```

输出：

```
PING 8.8.8.8 (8.8.8.8) 56(84) bytes of data.
64 bytes from 8.8.8.8: icmp_seq=1 ttl=116 time=5.32 ms
64 bytes from 8.8.8.8: icmp_seq=2 ttl=116 time=5.28 ms
64 bytes from 8.8.8.8: icmp_seq=3 ttl=116 time=5.25 ms
```

**成功！** 隔离的 namespace 可以访问外网了。

### 清理

```bash
# 删除 namespace（自动清理 veth）
sudo ip netns del mycontainer

# 删除 NAT 规则
sudo nft delete table ip nat
```

---

**你刚刚做了什么？**

```
容器网络架构：

┌─────────────────────────────────────────────────────────────────┐
│                           宿主机                                 │
│                                                                 │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │              Network Namespace: mycontainer                │  │
│  │                                                            │  │
│  │     ┌──────────────────┐                                   │  │
│  │     │  veth-container  │                                   │  │
│  │     │  172.18.0.2/24   │                                   │  │
│  │     └────────┬─────────┘                                   │  │
│  └──────────────┼─────────────────────────────────────────────┘  │
│                 │                                                 │
│                 │ veth pair（虚拟网线）                           │
│                 │                                                 │
│        ┌────────┴─────────┐                                      │
│        │    veth-host     │                                      │
│        │   172.18.0.1/24  │                                      │
│        └────────┬─────────┘                                      │
│                 │                                                 │
│        ┌────────┴─────────┐                                      │
│        │   NAT (MASQ)     │  ← nftables masquerade               │
│        └────────┬─────────┘                                      │
│                 │                                                 │
│        ┌────────┴─────────┐                                      │
│        │      eth0        │  宿主机物理网卡                       │
│        │  192.168.1.x     │                                      │
│        └──────────────────┘                                      │
└─────────────────────────────────────────────────────────────────┘
```

这就是 Docker/Kubernetes 容器网络的核心原理。Docker 的 `docker0` 桥接就是这个模式的扩展版本。

---

## 发生了什么？

### 容器网络核心组件

| 组件 | 作用 | 类比 |
|------|------|------|
| **Network Namespace** | 网络栈隔离 | 每个容器有独立的网络环境 |
| **veth pair** | 连接两个 namespace | 虚拟网线，一端在容器，一端在宿主机 |
| **bridge** | 连接多个容器 | 虚拟交换机 |
| **NAT** | 容器访问外网 | 地址转换，隐藏内部 IP |

### veth pair 详解

veth（Virtual Ethernet）是成对出现的虚拟网络设备：

```
veth pair 工作原理：

┌─────────────────┐     ┌─────────────────┐
│   veth-host     │────│  veth-container │
│   (宿主机端)    │    │   (容器端)       │
└─────────────────┘     └─────────────────┘
        │                       │
        │    数据包双向传输      │
        └───────────────────────┘

特点：
1. 成对创建，成对删除
2. 一端收到的包会立即从另一端发出
3. 可以放在不同的 network namespace 中
```

### 为什么需要 NAT？

容器使用私有 IP（如 172.18.0.2），外网不认识这个地址。NAT 将容器的私有 IP 转换为宿主机的公网 IP：

```
NAT 工作流程（容器访问 8.8.8.8）：

1. 容器发送包:
   src: 172.18.0.2  →  dst: 8.8.8.8

2. 经过 NAT (masquerade):
   src: 192.168.1.x  →  dst: 8.8.8.8  (宿主机 IP)

3. 响应返回:
   src: 8.8.8.8  →  dst: 192.168.1.x

4. NAT 反向转换:
   src: 8.8.8.8  →  dst: 172.18.0.2  (送回容器)
```

---

## 核心概念：容器网络架构

### Docker 默认网络模式

Docker 的 bridge 网络就是「先跑起来」实验的扩展版本：

```
Docker bridge 网络架构：

┌─────────────────────────────────────────────────────────────────┐
│                           宿主机                                 │
│                                                                 │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────────────┐  │
│  │ Container A │    │ Container B │    │ Container C         │  │
│  │  eth0       │    │  eth0       │    │  eth0               │  │
│  │ 172.17.0.2  │    │ 172.17.0.3  │    │ 172.17.0.4          │  │
│  └──────┬──────┘    └──────┬──────┘    └──────┬──────────────┘  │
│         │                  │                  │                  │
│      veth_a             veth_b             veth_c               │
│         │                  │                  │                  │
│         └──────────────────┼──────────────────┘                  │
│                            │                                     │
│                    ┌───────┴───────┐                             │
│                    │    docker0    │ 172.17.0.1                  │
│                    │   (bridge)    │                             │
│                    └───────┬───────┘                             │
│                            │                                     │
│                    ┌───────┴───────┐                             │
│                    │   NAT (MASQ)  │                             │
│                    └───────┬───────┘                             │
│                            │                                     │
│                    ┌───────┴───────┐                             │
│                    │     eth0      │  宿主机 IP                   │
│                    └───────────────┘                             │
└─────────────────────────────────────────────────────────────────┘

关键点：
1. 每个容器有独立的 network namespace
2. 每个容器通过 veth pair 连接到 docker0 bridge
3. bridge 充当二层交换机，容器间可互通
4. NAT 允许容器访问外网
```

### 三种常见容器网络模式

| 模式 | 特点 | 使用场景 |
|------|------|----------|
| **bridge** | 默认模式，veth + bridge + NAT | 大多数应用 |
| **host** | 共享宿主机网络栈 | 高性能需求（绕过 NAT） |
| **none** | 无网络 | 安全隔离、自定义网络 |

---

## 动手练习

### Lab 1：手动配置完整容器网络

**目标**：使用 ip netns、veth、bridge 构建多容器网络

运行演示脚本：

```bash
cd ~/cloud-atlas/foundations/linux/containers/08-container-networking/code
sudo ./veth-bridge-demo.sh
```

或手动执行：

**步骤 1**：创建 bridge（虚拟交换机）

```bash
# 创建 bridge
sudo ip link add br0 type bridge
sudo ip addr add 172.18.0.1/24 dev br0
sudo ip link set br0 up
```

**步骤 2**：创建两个 network namespace

```bash
# 创建两个「容器」
sudo ip netns add container1
sudo ip netns add container2
```

**步骤 3**：为每个容器创建 veth pair 并连接到 bridge

```bash
# 容器 1
sudo ip link add veth1-br type veth peer name veth1-ct
sudo ip link set veth1-ct netns container1
sudo ip link set veth1-br master br0
sudo ip link set veth1-br up
sudo ip netns exec container1 ip addr add 172.18.0.2/24 dev veth1-ct
sudo ip netns exec container1 ip link set veth1-ct up
sudo ip netns exec container1 ip link set lo up
sudo ip netns exec container1 ip route add default via 172.18.0.1

# 容器 2
sudo ip link add veth2-br type veth peer name veth2-ct
sudo ip link set veth2-ct netns container2
sudo ip link set veth2-br master br0
sudo ip link set veth2-br up
sudo ip netns exec container2 ip addr add 172.18.0.3/24 dev veth2-ct
sudo ip netns exec container2 ip link set veth2-ct up
sudo ip netns exec container2 ip link set lo up
sudo ip netns exec container2 ip route add default via 172.18.0.1
```

**步骤 4**：测试容器间通信

```bash
# 容器 1 ping 容器 2
sudo ip netns exec container1 ping -c 3 172.18.0.3
```

输出：

```
PING 172.18.0.3 (172.18.0.3) 56(84) bytes of data.
64 bytes from 172.18.0.3: icmp_seq=1 ttl=64 time=0.055 ms
```

**步骤 5**：查看 bridge 状态

```bash
# 查看 bridge 成员
bridge link show

# 或者
ip link show master br0
```

输出：

```
5: veth1-br@if4: <BROADCAST,MULTICAST,UP,LOWER_UP> ... master br0
7: veth2-br@if6: <BROADCAST,MULTICAST,UP,LOWER_UP> ... master br0
```

**清理**：

```bash
sudo ip netns del container1
sudo ip netns del container2
sudo ip link del br0
```

---

### Lab 2：nftables NAT 配置

**目标**：使用 nftables 配置容器 NAT（现代方案）

运行演示脚本：

```bash
cd ~/cloud-atlas/foundations/linux/containers/08-container-networking/code
sudo ./nat-setup.sh
```

或手动执行：

**步骤 1**：准备网络环境

```bash
# 创建 namespace 和 veth（简化版）
sudo ip netns add nattest
sudo ip link add veth-host type veth peer name veth-ct
sudo ip link set veth-ct netns nattest
sudo ip addr add 172.19.0.1/24 dev veth-host
sudo ip netns exec nattest ip addr add 172.19.0.2/24 dev veth-ct
sudo ip link set veth-host up
sudo ip netns exec nattest ip link set veth-ct up
sudo ip netns exec nattest ip link set lo up
sudo ip netns exec nattest ip route add default via 172.19.0.1
```

**步骤 2**：启用 IP 转发

```bash
# 临时启用
echo 1 | sudo tee /proc/sys/net/ipv4/ip_forward

# 永久启用（需要重启生效）
# echo "net.ipv4.ip_forward = 1" | sudo tee /etc/sysctl.d/99-ip-forward.conf
# sudo sysctl --system
```

**步骤 3**：使用 nftables 配置 NAT

```bash
# 创建 NAT 表
sudo nft add table ip nat

# 创建 postrouting 链（SNAT/MASQUERADE）
sudo nft add chain ip nat postrouting { type nat hook postrouting priority 100 \; }

# 添加 masquerade 规则
sudo nft add rule ip nat postrouting ip saddr 172.19.0.0/24 masquerade

# 查看规则
sudo nft list table ip nat
```

输出：

```
table ip nat {
    chain postrouting {
        type nat hook postrouting priority srcnat; policy accept;
        ip saddr 172.19.0.0/24 masquerade
    }
}
```

**步骤 4**：测试外网访问

```bash
# 测试 ping 外网
sudo ip netns exec nattest ping -c 3 8.8.8.8

# 测试 DNS（如果有 curl）
sudo ip netns exec nattest curl -I https://www.google.com 2>/dev/null | head -3
```

**步骤 5**：端口映射（DNAT）

```bash
# 假设容器运行 web 服务在 80 端口
# 将宿主机 8080 端口转发到容器 80 端口

# 创建 prerouting 链
sudo nft add chain ip nat prerouting { type nat hook prerouting priority -100 \; }

# 添加 DNAT 规则
sudo nft add rule ip nat prerouting tcp dport 8080 dnat to 172.19.0.2:80

# 查看完整规则
sudo nft list ruleset
```

**清理**：

```bash
sudo ip netns del nattest
sudo nft delete table ip nat
```

---

### Lab 3：Distroless 容器网络调试

**场景**：Go 应用部署在 distroless 镜像中（无 shell、curl、ping），无法连接数据库。

**问题**：Distroless 镜像没有调试工具，如何排查网络问题？

**解决方案**：使用 nsenter 从宿主机进入容器网络 namespace

**模拟场景**（使用 Docker）：

```bash
# 启动一个 distroless 容器（使用 static 镜像模拟）
docker run -d --name distroless-app gcr.io/distroless/static-debian11 sleep infinity

# 尝试 docker exec —— 失败！
docker exec -it distroless-app sh
# Error: executable file not found in $PATH

docker exec -it distroless-app ping 8.8.8.8
# Error: executable file not found in $PATH
```

**使用 nsenter 调试**：

```bash
# 1. 获取容器 PID
PID=$(docker inspect --format '{{.State.Pid}}' distroless-app)
echo "容器 PID: $PID"

# 2. 只进入 Network Namespace，使用宿主机工具
# 查看容器网络接口
sudo nsenter -t $PID -n ip addr

# 3. 测试网络连通性
sudo nsenter -t $PID -n ping -c 3 8.8.8.8

# 4. 查看路由表
sudo nsenter -t $PID -n ip route

# 5. 查看 DNS 配置
sudo nsenter -t $PID -n cat /etc/resolv.conf

# 6. 测试端口连通性
sudo nsenter -t $PID -n nc -zv database.internal 5432

# 7. 抓包分析
sudo nsenter -t $PID -n tcpdump -i eth0 -n port 5432 -c 10
```

**调试模板**：

```bash
#!/bin/bash
# distroless-debug.sh - Distroless 容器网络调试脚本

CONTAINER=$1
if [ -z "$CONTAINER" ]; then
    echo "用法: $0 <container-name>"
    exit 1
fi

PID=$(docker inspect --format '{{.State.Pid}}' "$CONTAINER" 2>/dev/null)
if [ -z "$PID" ]; then
    echo "错误: 无法获取容器 PID"
    exit 1
fi

echo "=========================================="
echo "  Distroless 容器网络调试"
echo "  容器: $CONTAINER"
echo "  PID: $PID"
echo "=========================================="

echo ""
echo "【1. 网络接口】"
sudo nsenter -t $PID -n ip addr

echo ""
echo "【2. 路由表】"
sudo nsenter -t $PID -n ip route

echo ""
echo "【3. DNS 配置】"
sudo nsenter -t $PID -n cat /etc/resolv.conf

echo ""
echo "【4. 监听端口】"
sudo nsenter -t $PID -n ss -tuln

echo ""
echo "【5. 外网连通性】"
sudo nsenter -t $PID -n ping -c 1 8.8.8.8 && echo "外网: OK" || echo "外网: FAILED"
```

**清理**：

```bash
docker stop distroless-app && docker rm distroless-app
```

---

### Lab 4：容器网络不通排查

**场景**：新建容器无法访问外网，ping 8.8.8.8 超时，但同一宿主机其他容器正常。

**排查步骤**：

```bash
# 1. 获取问题容器 PID
PID=$(docker inspect --format '{{.State.Pid}}' <problem-container>)

# 2. 检查容器网络接口
sudo nsenter -t $PID -n ip addr
# 确认 eth0 存在且有 IP 地址

# 3. 检查容器路由
sudo nsenter -t $PID -n ip route
# 确认有默认路由指向网关

# 4. 检查 veth pair 状态
ip link | grep veth
# 确认 veth 接口状态是 UP

# 5. 检查 bridge 成员
bridge link show
# 或
ip link show master docker0
# 确认 veth 连接到 bridge

# 6. 检查 NAT 规则
sudo nft list table ip nat
# 或（如果使用 iptables）
# sudo iptables -t nat -L -n -v

# 7. 检查 IP 转发
cat /proc/sys/net/ipv4/ip_forward
# 应该是 1

# 8. 抓包分析
sudo nsenter -t $PID -n tcpdump -i eth0 -n icmp
# 在另一个终端：
# sudo nsenter -t $PID -n ping 8.8.8.8
```

**常见问题及解决方案**：

| 症状 | 原因 | 解决方案 |
|------|------|----------|
| eth0 无 IP | DHCP 失败或静态 IP 未配置 | 检查容器网络配置 |
| 无默认路由 | 网关配置缺失 | 添加默认路由 |
| veth 状态 DOWN | 接口未启动 | `ip link set <veth> up` |
| veth 不在 bridge | 未连接到 bridge | `ip link set <veth> master <bridge>` |
| NAT 规则缺失 | nftables/iptables 未配置 | 添加 masquerade 规则 |
| IP 转发禁用 | 内核参数未启用 | `echo 1 > /proc/sys/net/ipv4/ip_forward` |

---

## 职场小贴士

### 日本 IT 现场：ネットワーク障害対応

**场景 1：本番コンテナのネットワーク調査**

```
状況：
本番環境の Go アプリが RDS に接続できない。
コンテナは distroless イメージで shell が入っていない。

調査手順：

1. PID 取得
   PID=$(docker inspect --format '{{.State.Pid}}' <container>)

2. ネットワーク確認
   nsenter -t $PID -n ip addr
   nsenter -t $PID -n ip route

3. DNS 確認
   nsenter -t $PID -n nslookup rds.internal

4. ポート確認
   nsenter -t $PID -n nc -zv rds.internal 5432

5. パケットキャプチャ
   nsenter -t $PID -n tcpdump -i eth0 port 5432

報告書に添付：
- ネットワーク設定（ip addr 出力）
- tcpdump キャプチャ結果
```

**场景 2：セキュリティグループ/NAT 問題**

```
よくある原因：
1. Security Group で outbound が制限されている
2. NAT Gateway の設定ミス
3. VPC ルーティング問題

コンテナ側で確認できること：
- ping 外部IP → 通信可否
- nslookup ドメイン → DNS 解決可否
- tcpdump → パケットが出ているか

AWS 側で確認すること：
- Security Group outbound ルール
- NAT Gateway 状態
- Route Table 設定
```

### 运维监控ポイント

**ネットワーク障害は本番トラブルの主要原因**

| 監視項目 | ツール | アラート条件 |
|----------|--------|-------------|
| コンテナネットワーク | tcpdump, ss | 接続タイムアウト |
| veth 状態 | ip link | state DOWN |
| bridge 状態 | bridge link | 切断 |
| NAT テーブル | nft list | ルール欠落 |

**nsenter でのデバッグは必須スキル**

Distroless イメージの普及により、`docker exec` に頼らない調査能力が求められる。

---

## 反模式：常见错误

### 错误 1：在容器内配置 iptables/nftables

```bash
# 错误：在容器内配置防火墙规则
docker exec <container> iptables -A INPUT -p tcp --dport 80 -j ACCEPT

# 问题：
# 1. 规则在容器重启后丢失
# 2. 可能与宿主机规则冲突
# 3. 权限问题（需要 CAP_NET_ADMIN）

# 正确：在宿主机或 CNI 层面配置网络策略
```

### 错误 2：使用 host 网络模式作为默认

```bash
# 错误：所有容器都用 host 网络
docker run --network=host myapp

# 问题：
# 1. 端口冲突（多个容器无法监听同一端口）
# 2. 安全隔离丧失（容器共享宿主机网络栈）
# 3. 无法使用容器网络功能（如 service discovery）

# 正确：只在性能关键场景使用 host 网络
# - 需要极低延迟的应用
# - 需要访问宿主机网络的监控工具
```

---

## 检查清单

完成本课后，你应该能够：

- [ ] 使用 `ip netns` 创建和管理 network namespace
- [ ] 使用 `ip link add ... type veth` 创建 veth pair
- [ ] 使用 `ip link add ... type bridge` 创建 bridge
- [ ] 使用 `ip link set ... master ...` 将 veth 连接到 bridge
- [ ] 使用 `nft add rule ... masquerade` 配置 NAT
- [ ] 使用 `nsenter -t <PID> -n` 进入容器网络调试
- [ ] 排查容器网络不通问题（veth/bridge/NAT 检查）
- [ ] 解释 Docker bridge 网络架构
- [ ] 避免「在容器内配置 iptables」反模式
- [ ] 避免「默认使用 host 网络」反模式

---

## 延伸阅读

### 官方文档

- [ip-netns(8) man page](https://man7.org/linux/man-pages/man8/ip-netns.8.html)
- [veth(4) man page](https://man7.org/linux/man-pages/man4/veth.4.html)
- [nftables wiki](https://wiki.nftables.org/)
- [Docker Networking](https://docs.docker.com/network/)

### 相关课程

- [Lesson 03 - Namespace 深入](../03-namespace-deep-dive/) - nsenter 调试技巧
- [Lesson 11 - 容器故障排查](../11-debugging-troubleshooting/) - 完整排查方法论
- [LX06 - Linux 网络基础](../../network/) - 网络基础、nftables

### 推荐阅读

- *Container Networking* by Michael Hausenblas
- Kubernetes CNI 网络插件原理

---

## 系列导航

[<-- 07 - OverlayFS](../07-overlay-filesystems/) | [Home](../) | [09 - 容器安全 -->](../09-container-security/)
