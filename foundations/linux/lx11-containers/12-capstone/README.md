# 12 - Capstone：从零构建容器

> **目标**：综合运用所有容器原语，从零构建一个完整的容器环境  
> **前置**：[Lesson 01-11](../) 全部内容  
> **时间**：3 小时  
> **环境**：Linux 系统（需要 root 权限，建议 Ubuntu 22.04+ / RHEL 9+）  

---

## 将学到的内容

1. 综合运用 Namespace、cgroups、OverlayFS、网络配置
2. 从第一行命令开始，构建可运行的隔离容器
3. 理解每个组件如何协同工作
4. 验证「容器 = 进程 + 约束」心智模型

---

## 先跑起来：15 分钟构建你的第一个容器

> **不讲原理，先动手！** 使用我们提供的脚手架脚本，快速构建一个完整容器。  

### 准备工作

```bash
# 获取课程代码
git clone --filter=blob:none --sparse https://github.com/shiicho/cloud-atlas ~/cloud-atlas
cd ~/cloud-atlas && git sparse-checkout set foundations/linux/containers

# 进入 capstone 目录
cd ~/cloud-atlas/foundations/linux/containers/12-capstone/code
```

### 下载根文件系统

```bash
# 下载 Alpine Linux 作为容器根文件系统
mkdir -p ~/container-lab/rootfs
cd ~/container-lab
curl -o alpine-minirootfs.tar.gz \
  https://dl-cdn.alpinelinux.org/alpine/v3.19/releases/x86_64/alpine-minirootfs-3.19.0-x86_64.tar.gz
tar -xzf alpine-minirootfs.tar.gz -C rootfs
```

### 使用脚手架构建容器

```bash
# 复制脚手架脚本
cp ~/cloud-atlas/foundations/linux/containers/12-capstone/code/*.sh ~/container-lab/

# 执行完整构建脚本
cd ~/container-lab
sudo ./build-container.sh
```

脚本会：
1. 设置 OverlayFS 根文件系统
2. 创建 Namespace 隔离
3. 配置 cgroups 资源限制
4. 建立网络连接
5. 启动容器 shell

### 在容器内验证

```bash
# 你现在在容器内！

# 验证 1：进程隔离
ps aux
# 应该只看到 /bin/sh 和 ps

# 验证 2：主机名隔离
hostname
# 应该是 my-container

# 验证 3：网络隔离
ip addr
# 应该只有 lo 和 eth0

# 验证 4：外网连通性
ping -c 3 8.8.8.8
# 应该成功

# 验证 5：根文件系统
cat /etc/os-release
# 应该显示 Alpine Linux

# 退出容器
exit
```

---

**你刚刚做了什么？**

```
                        从零构建容器完整流程
┌──────────────────────────────────────────────────────────────────────┐
│                                                                      │
│  Phase 1: Filesystem                                                 │
│  ┌────────────────────────────────────────────────────────────────┐  │
│  │  alpine-rootfs (lower)  +  empty (upper)  =  merged (容器看到)  │  │
│  │                    OverlayFS                                    │  │
│  └────────────────────────────────────────────────────────────────┘  │
│                              │                                       │
│                              ▼                                       │
│  Phase 2: Namespaces                                                 │
│  ┌────────────────────────────────────────────────────────────────┐  │
│  │  unshare --pid --mount --uts --net --ipc                       │  │
│  │  ┌──────────┬──────────┬──────────┬──────────┬──────────┐      │  │
│  │  │   PID    │  Mount   │   UTS    │   Net    │   IPC    │      │  │
│  │  │  隔离    │  隔离    │  隔离    │  隔离    │  隔离    │      │  │
│  │  └──────────┴──────────┴──────────┴──────────┴──────────┘      │  │
│  └────────────────────────────────────────────────────────────────┘  │
│                              │                                       │
│                              ▼                                       │
│  Phase 3: Network                                                    │
│  ┌────────────────────────────────────────────────────────────────┐  │
│  │      veth pair         bridge           NAT                     │  │
│  │  container ─────────── br0 ─────────── nftables ──────▶ 外网   │  │
│  └────────────────────────────────────────────────────────────────┘  │
│                              │                                       │
│                              ▼                                       │
│  Phase 4: Resource Limits                                            │
│  ┌────────────────────────────────────────────────────────────────┐  │
│  │  cgroup v2: memory.max=256M, cpu.max=50000/100000              │  │
│  └────────────────────────────────────────────────────────────────┘  │
│                              │                                       │
│                              ▼                                       │
│  Phase 5: Run                                                        │
│  ┌────────────────────────────────────────────────────────────────┐  │
│  │  pivot_root → mount /proc → exec /bin/sh                       │  │
│  └────────────────────────────────────────────────────────────────┘  │
│                                                                      │
└──────────────────────────────────────────────────────────────────────┘

这就是 Docker/runc 背后的核心原理！
```

---

## 发生了什么？

### 容器 = 进程 + 约束

回顾整个课程的核心心智模型：

| 组件 | 作用 | 对应约束 |
|------|------|----------|
| **Namespace** | 限制进程「能看到」什么 | 隔离视图 |
| **cgroups** | 限制进程「能用」多少资源 | 资源限制 |
| **OverlayFS** | 提供文件系统视图 | 镜像层 |
| **seccomp** | 限制进程「能调用」哪些系统调用 | 系统调用过滤 |

Docker、containerd、Podman 都是在这些 Linux 原语之上构建的抽象层。

### 没有魔法，只有 Linux

```bash
# Docker run 背后发生的事情：
docker run -it --memory=256m --cpus=0.5 alpine sh

# 等价于我们手动做的：
# 1. 准备 rootfs (OverlayFS)
# 2. unshare --pid --mount --uts --net --ipc
# 3. 创建 cgroup，设置 memory.max=256M, cpu.max=50000/100000
# 4. 创建 veth pair + bridge + NAT
# 5. pivot_root 切换根目录
# 6. exec /bin/sh
```

---

## 核心概念：构建步骤详解

### Phase 1: Filesystem（文件系统）

使用 OverlayFS 创建容器根文件系统：

```bash
# 目录结构
mkdir -p /tmp/container/{lower,upper,work,merged}

# lower = Alpine rootfs（只读层）
# upper = 可写层（容器运行时的修改）
# work = OverlayFS 工作目录
# merged = 容器看到的合并视图

mount -t overlay overlay \
  -o lowerdir=/tmp/container/lower,upperdir=/tmp/container/upper,workdir=/tmp/container/work \
  /tmp/container/merged
```

**为什么用 OverlayFS？**

- 镜像只读，多容器共享
- 写时复制，节省空间
- 删除文件创建 whiteout，不影响底层

### Phase 2: Namespaces（命名空间）

使用 `unshare` 创建隔离环境：

```bash
# 创建新的 PID、Mount、UTS、Network、IPC Namespace
unshare --pid --fork --mount --uts --net --ipc /bin/sh
```

各 Namespace 作用：

| Namespace | 隔离内容 | 效果 |
|-----------|----------|------|
| **PID** | 进程 ID | 容器内 PID 从 1 开始 |
| **Mount** | 挂载点 | 独立的文件系统视图 |
| **UTS** | 主机名 | 独立的 hostname |
| **Network** | 网络栈 | 独立的 IP、路由、端口 |
| **IPC** | 进程间通信 | 独立的共享内存、信号量 |

### Phase 3: Network（网络）

为容器建立网络连接：

```bash
# 1. 在宿主机创建 veth pair
ip link add veth-host type veth peer name veth-container

# 2. 把一端移到容器 namespace
ip link set veth-container netns <container-pid>

# 3. 创建 bridge（如果需要多容器）
ip link add br0 type bridge
ip link set veth-host master br0

# 4. 配置 NAT（使用 nftables）
nft add table ip nat
nft add chain ip nat postrouting { type nat hook postrouting priority 100 \; }
nft add rule ip nat postrouting ip saddr 172.20.0.0/24 masquerade
```

### Phase 4: Resource Limits（资源限制）

使用 cgroups v2 限制资源：

```bash
# 创建 cgroup
mkdir /sys/fs/cgroup/my-container

# 设置内存限制（256MB）
echo "256M" > /sys/fs/cgroup/my-container/memory.max

# 设置 CPU 限制（50%）
echo "50000 100000" > /sys/fs/cgroup/my-container/cpu.max

# 将容器进程加入 cgroup
echo <container-pid> > /sys/fs/cgroup/my-container/cgroup.procs
```

### Phase 5: Run（运行）

切换根目录并启动进程：

```bash
# pivot_root 切换根目录（比 chroot 更安全）
cd /tmp/container/merged
mkdir -p oldroot
pivot_root . oldroot

# 挂载必要的伪文件系统
mount -t proc proc /proc
mount -t sysfs sysfs /sys

# 卸载旧根
umount -l /oldroot
rmdir /oldroot

# 执行容器进程
exec /bin/sh
```

---

## 动手练习

### Lab 1：理解 scaffold 脚本

在开始自己实现之前，先理解脚手架脚本的作用。

**查看 scaffold-namespace.sh**：

```bash
cat ~/container-lab/scaffold-namespace.sh
```

核心功能：
- 处理 `--fork --pid` 组合的正确顺序
- 正确挂载 `/proc`
- 处理 `pivot_root` 参数陷阱

**查看 scaffold-cgroup.sh**：

```bash
cat ~/container-lab/scaffold-cgroup.sh
```

核心功能：
- 检测 cgroup v2 挂载点
- 创建 cgroup 目录
- 正确写入 `memory.max` 和 `cpu.max`

**查看 scaffold-network.sh**：

```bash
cat ~/container-lab/scaffold-network.sh
```

核心功能：
- 创建 veth pair
- 配置 bridge
- 使用 nftables 配置 NAT（不是 iptables）

---

### Lab 2：手动构建容器（不使用脚本）

**目标**：完全手动执行每一步，加深理解

**Terminal 1（宿主机）**：

```bash
# === Phase 1: Filesystem ===
cd ~/container-lab
mkdir -p container/{lower,upper,work,merged}

# 复制 rootfs 到 lower
cp -a rootfs/* container/lower/

# 挂载 OverlayFS
sudo mount -t overlay overlay \
  -o lowerdir=container/lower,upperdir=container/upper,workdir=container/work \
  container/merged

# 验证
ls container/merged/
```

**Terminal 1（继续）**：

```bash
# === Phase 2: Namespaces ===
# 创建隔离环境（但先不进入）
sudo unshare --pid --fork --mount --uts --net --ipc \
  /bin/bash -c '
    # 设置主机名
    hostname my-container

    # 挂载 /proc（PID namespace 需要）
    mount -t proc proc /proc

    # 等待网络配置
    echo "Container PID: $$"
    echo "等待网络配置...按任意键继续"
    read

    # 切换根目录
    cd /home/$SUDO_USER/container-lab/container/merged
    mkdir -p oldroot
    pivot_root . oldroot
    cd /

    # 挂载伪文件系统
    mount -t proc proc /proc
    mount -t sysfs sysfs /sys

    # 清理旧根
    umount -l /oldroot 2>/dev/null
    rmdir /oldroot 2>/dev/null

    exec /bin/sh
  '
```

**Terminal 2（宿主机，配置网络）**：

```bash
# === Phase 3: Network ===
# 获取容器进程 PID（从 Terminal 1 的输出）
CONTAINER_PID=<从Terminal1获取>

# 创建 bridge
sudo ip link add br0 type bridge
sudo ip addr add 172.20.0.1/24 dev br0
sudo ip link set br0 up

# 创建 veth pair
sudo ip link add veth-host type veth peer name veth-ct

# 将 veth-ct 移到容器 namespace
sudo ip link set veth-ct netns $CONTAINER_PID

# 连接 veth-host 到 bridge
sudo ip link set veth-host master br0
sudo ip link set veth-host up

# 在容器内配置网络（通过 nsenter）
sudo nsenter -t $CONTAINER_PID -n ip addr add 172.20.0.2/24 dev veth-ct
sudo nsenter -t $CONTAINER_PID -n ip link set veth-ct up
sudo nsenter -t $CONTAINER_PID -n ip link set lo up
sudo nsenter -t $CONTAINER_PID -n ip route add default via 172.20.0.1

# 启用 IP 转发
echo 1 | sudo tee /proc/sys/net/ipv4/ip_forward

# 配置 NAT
sudo nft add table ip nat
sudo nft add chain ip nat postrouting { type nat hook postrouting priority 100 \; }
sudo nft add rule ip nat postrouting ip saddr 172.20.0.0/24 masquerade

echo "网络配置完成！回到 Terminal 1 按回车键继续"
```

**Terminal 2（继续，配置 cgroups）**：

```bash
# === Phase 4: Resource Limits ===
# 创建 cgroup
sudo mkdir /sys/fs/cgroup/my-container

# 设置内存限制
echo "256M" | sudo tee /sys/fs/cgroup/my-container/memory.max

# 设置 CPU 限制（50%）
echo "50000 100000" | sudo tee /sys/fs/cgroup/my-container/cpu.max

# 将容器进程加入 cgroup
echo $CONTAINER_PID | sudo tee /sys/fs/cgroup/my-container/cgroup.procs
```

**Terminal 1（回到容器内验证）**：

```bash
# 按回车后，你应该在容器 shell 中

# 验证隔离
ps aux
hostname
ip addr
ping -c 3 8.8.8.8
```

---

### Lab 3：在容器中运行 Web 服务器

**目标**：验证容器可以运行实际应用

在容器内：

```bash
# 安装 busybox httpd（Alpine 已包含）
mkdir -p /www
echo "<h1>Hello from my container!</h1>" > /www/index.html

# 启动简单 Web 服务器
httpd -p 8080 -h /www &

# 验证
wget -O - http://localhost:8080
```

在宿主机（Terminal 2）：

```bash
# 访问容器 Web 服务
curl http://172.20.0.2:8080
```

输出：

```html
<h1>Hello from my container!</h1>
```

---

### Lab 4：资源限制验证

**目标**：验证 cgroups 限制是否生效

在容器内：

```bash
# 安装 stress（如果没有）
apk add --no-cache stress

# 尝试分配超过限制的内存
stress --vm 1 --vm-bytes 512M --timeout 10s
```

预期结果：进程被 OOM Kill

在宿主机查看证据：

```bash
# 检查 OOM 事件
cat /sys/fs/cgroup/my-container/memory.events

# 检查 dmesg
dmesg | grep -i oom | tail -5
```

---

## 清理

```bash
# 停止容器（在容器内执行 exit）

# 清理网络
sudo ip link del br0
sudo nft delete table ip nat

# 清理 cgroup
sudo rmdir /sys/fs/cgroup/my-container

# 卸载 OverlayFS
sudo umount ~/container-lab/container/merged

# 清理目录
rm -rf ~/container-lab/container
```

---

## 职场小贴士

### 日本 IT 现场：コンテナの仕組み

**この Capstone は深い理解の証明になる**

面接で「コンテナの仕組みを説明してください」と聞かれたとき：

```
悪い回答：
「Docker を使えばコンテナが動きます」

良い回答：
「コンテナは本質的に制約付きプロセスです。
 Linux Namespace でプロセスが見えるものを制限し、
 cgroups で使えるリソースを制限します。
 実際に unshare と cgroups で手動コンテナを構築した経験があります。」
```

**理解の深さを示す具体例**：

| 質問 | 表面的回答 | 深い理解を示す回答 |
|------|-----------|-------------------|
| OOM Kill の調査方法 | ログを見る | `dmesg` と `memory.events` で証拠を収集 |
| ネットワーク問題 | docker logs | `nsenter -t <PID> -n` でコンテナネットワークを直接調査 |
| セキュリティ | `--privileged` | 必要な capability だけを付与 |

### 障害対応での活用

```bash
# 本番コンテナのデバッグ

# 1. PID 取得
PID=$(docker inspect --format '{{.State.Pid}}' <container>)

# 2. 直接 namespace に入る
nsenter -t $PID -n  # ネットワーク調査
nsenter -t $PID -m  # ファイルシステム調査
nsenter -t $PID -p  # プロセス調査

# 3. cgroup 状態確認
cat /sys/fs/cgroup/system.slice/docker-<id>.scope/memory.events
cat /sys/fs/cgroup/system.slice/docker-<id>.scope/cpu.stat
```

---

## 評価基準（Grading Criteria）

このCapstoneの評価基準：

| 基準 | 配点 | 内容 |
|------|------|------|
| **隔離検証** | 30% | Namespace 隔離が正しく機能している |
| **リソース制限** | 20% | cgroup 制限が有効 |
| **ネットワーク接続** | 25% | コンテナが外部ネットワークにアクセス可能 |
| **ドキュメント品質** | 15% | 各ステップの目的を明確に説明 |
| **コード品質** | 10% | スクリプトが読みやすく再利用可能 |

### 検証コマンド

```bash
# 1. PID Namespace 検証
ps aux  # コンテナプロセスのみ表示されること

# 2. UTS Namespace 検証
hostname  # コンテナのホスト名が表示されること

# 3. Network Namespace 検証
ip addr  # コンテナの IP が表示されること

# 4. 外部接続検証
ping -c 3 8.8.8.8  # 成功すること

# 5. リソース制限検証
cat /sys/fs/cgroup/.../memory.max  # 制限値が設定されていること
```

---

## 检查清单

完成本课后，你应该能够：

- [ ] 从零手动构建完整容器（不依赖 Docker/runc）
- [ ] 解释 OverlayFS 在容器中的作用
- [ ] 使用 `unshare` 创建多种 Namespace
- [ ] 使用 `pivot_root` 切换容器根目录
- [ ] 手动配置 veth pair + bridge + NAT 网络
- [ ] 配置 cgroups v2 资源限制
- [ ] 验证容器隔离（ps、hostname、ip addr）
- [ ] 验证外网连通性（ping 8.8.8.8）
- [ ] 验证资源限制（触发 OOM Kill）
- [ ] 解释「容器 = 进程 + 约束」心智模型
- [ ] 向非技术人员解释容器和 VM 的区别

---

## 回顾：课程总结

### 你学到了什么

```
LX11-CONTAINERS 课程回顾

Lesson 01-02: 心智模型
  └─ Container = Process + Constraints
  └─ 公寓楼比喻：7 种 Namespace

Lesson 03-04: Namespace 深入
  └─ unshare / nsenter 实战
  └─ User Namespace 与 Rootless

Lesson 05-06: cgroups v2
  └─ 统一层级架构
  └─ memory.high vs memory.max

Lesson 07: OverlayFS
  └─ 写时复制
  └─ whiteout 机制

Lesson 08: 容器网络
  └─ veth pair + bridge + NAT

Lesson 09: 容器安全
  └─ seccomp + capabilities

Lesson 10: OCI 运行时
  └─ runc / containerd / CRI

Lesson 11: 故障排查
  └─ OOM 调查
  └─ 网络问题定位

Lesson 12: Capstone（本课）
  └─ 综合所有知识
  └─ 从零构建容器
```

### 下一步学习

- **Kubernetes**：容器编排，Pod/Deployment/Service
- **LX12-CLOUD**：云端容器（EKS, ECS, Fargate）
- **容器安全深入**：AppArmor, SELinux, Falco

---

## 延伸阅读

### 官方文档

- [namespaces(7) man page](https://man7.org/linux/man-pages/man7/namespaces.7.html)
- [cgroups(7) man page](https://man7.org/linux/man-pages/man7/cgroups.7.html)
- [pivot_root(2) man page](https://man7.org/linux/man-pages/man2/pivot_root.2.html)

### 相关课程

- [Lesson 03 - Namespace 深入](../03-namespace-deep-dive/) - unshare/nsenter 详解
- [Lesson 06 - cgroups v2 资源控制](../06-cgroups-v2-resource-control/) - OOM Kill 调查
- [Lesson 08 - 容器网络](../08-container-networking/) - veth/bridge/NAT

### 推荐阅读

- *Container Security* by Liz Rice
- *Linux Containers and Virtualization* by Shashank Mohan Jain
- [Containers from Scratch](https://ericchiang.github.io/post/containers-from-scratch/) - Eric Chiang 的经典文章

---

## 系列导航

[<-- 11 - 容器故障排查](../11-debugging-troubleshooting/) | [Home](../) | [课程完结]
