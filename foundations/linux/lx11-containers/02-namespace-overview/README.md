# 02 - Linux Namespace（Namespace Overview）

> **目标**：理解 Namespace 如何控制进程"能看到什么"，掌握 7 种 Namespace 类型  
> **前置**：已完成 [01 · 容器 vs 虚拟机](../01-containers-vs-vms/)  
> **时间**：⚡ 35 分钟（速读）/ 🔬 130 分钟（完整实操）  
> **费用**：无（本地 Linux 或 EC2 实例）  

---

## 将学到的内容

1. 理解 Namespace 是容器隔离的核心机制
2. 使用"公寓楼比喻"记忆 7 种 Namespace 类型
3. 使用 `lsns` 和 `/proc/<PID>/ns/` 探索系统 Namespace
4. 区分 Namespace（能看到什么）和 cgroups（能用多少）

---

## 🚀 先跑起来：5 分钟体验 Namespace 隔离

> 先"尝到"Namespace 的味道，再理解原理。  

### 快速体验：网络隔离

```bash
# 创建一个隔离的网络环境
sudo unshare --net bash

# 查看网络接口 - 注意：只有 lo！
ip addr

# 尝试 ping 外网 - 网络不通！
ping -c 1 8.8.8.8

# 退出隔离环境
exit

# 回到宿主机 - 所有网络接口都回来了
ip addr
```

**刚才发生了什么？**

你刚刚创建了一个 Network Namespace（网络命名空间）。在这个隔离环境中，进程只能看到一个空的网络栈 —— 没有 eth0，没有网络连接，完全与宿主机网络隔离。

**这就是容器网络隔离的基础原理。** 每个 Docker 容器都运行在自己的 Network Namespace 中。

---

## 🔍 发生了什么？核心概念

### Namespace vs cgroups：隔离的两个维度

容器隔离需要两种机制配合：

| 机制 | 控制 | 比喻 |
|------|------|------|
| **Namespace** | 进程能"看到"什么 | 视野范围 |
| **cgroups** | 进程能"使用"多少 | 资源配额 |

```
容器 = Namespace (隔离可见性) + cgroups (限制资源)
```

**关键理解**：
- Namespace 让容器"看不到"宿主机的其他进程、网络、文件系统
- cgroups 让容器"用不了"超过配额的 CPU、内存、磁盘 IO
- 两者组合才能实现完整的容器隔离

---

## 📖 公寓楼比喻：记住 7 种 Namespace

想象普通 Linux 是一个"共享大房子" —— 所有人都能看到所有人。

我们要建造"私人公寓楼" —— 每个容器是一个独立单元。

<!-- DIAGRAM: apartment-building -->
```
┌─────────────────────────────────────────────────────────────────────────┐
│                          公寓楼（宿主机）                                 │
│                                                                         │
│  ┌─────────────────────┐  ┌─────────────────────┐  ┌─────────────────┐  │
│  │      房间 A         │  │      房间 B         │  │     房间 C      │  │
│  │     (容器 1)        │  │     (容器 2)        │  │    (容器 3)     │  │
│  │                     │  │                     │  │                 │  │
│  │  ┌───────────────┐  │  │  ┌───────────────┐  │  │  ┌───────────┐  │  │
│  │  │  门牌: web-01 │  │  │  │  门牌: db-01  │  │  │  │门牌:cache │  │  │
│  │  │   (UTS NS)    │  │  │  │   (UTS NS)    │  │  │  │ (UTS NS)  │  │  │
│  │  └───────────────┘  │  │  └───────────────┘  │  │  └───────────┘  │  │
│  │                     │  │                     │  │                 │  │
│  │  PID 1: nginx       │  │  PID 1: mysql       │  │  PID 1: redis   │  │
│  │  (PID Namespace)    │  │  (PID Namespace)    │  │  (PID NS)       │  │
│  │                     │  │                     │  │                 │  │
│  │  eth0: 172.17.0.2   │  │  eth0: 172.17.0.3   │  │  eth0: 172.17.4 │  │
│  │  (Network NS)       │  │  (Network NS)       │  │  (Network NS)   │  │
│  │                     │  │                     │  │                 │  │
│  │  / (独立文件系统)    │  │  / (独立文件系统)    │  │  / (独立文件)   │  │
│  │  (Mount NS)         │  │  (Mount NS)         │  │  (Mount NS)     │  │
│  │                     │  │                     │  │                 │  │
│  │  水电表: 2CPU/512M  │  │  水电表: 4CPU/2G    │  │  水电表: 1CPU/1G│  │
│  │  (cgroup 限制)      │  │  (cgroup 限制)      │  │  (cgroup)       │  │
│  └─────────────────────┘  └─────────────────────┘  └─────────────────┘  │
│                                    │                                    │
│                          ┌─────────┴─────────┐                          │
│                          │     共享内核       │                          │
│                          │   (所有容器共用)   │                          │
│                          └───────────────────┘                          │
└─────────────────────────────────────────────────────────────────────────┘
```
<!-- /DIAGRAM -->

### 7 种 Namespace 对照表

| Namespace | 公寓比喻 | 隔离内容 | 引入版本 |
|-----------|----------|----------|----------|
| **Mount** | 墙壁 | 文件系统挂载点 | 2.4.19 (2002) |
| **UTS** | 门牌 | 主机名和域名 | 2.6.19 (2006) |
| **PID** | 家庭 | 进程 ID 树 | 2.6.24 (2008) |
| **Network** | 对讲机 | 网络栈、IP、路由 | 2.6.29 (2009) |
| **IPC** | 隔音 | 进程间通信 | 2.6.19 (2006) |
| **User** | 角色扮演 | 用户和组 ID | 3.8 (2013) |
| **Cgroup** | 资源视图 | cgroup 层级视图 | 4.6 (2016) |

---

## 📚 7 种 Namespace 详解

### 1. Mount Namespace（墙壁）

**作用**：隔离文件系统挂载点

**公寓比喻**：每个房间有自己的墙壁，你看不到邻居房间里的东西。

```bash
# 容器内的 / 是独立的文件系统视图
# 容器看不到宿主机的 /home, /root 等目录
```

**实际效果**：
- 容器有自己的根目录 `/`
- 容器挂载的目录不影响宿主机
- OverlayFS 镜像层基于此实现

> 参考：[Lesson 03](../03-namespace-deep-dive/) 将深入讲解 Mount Namespace 和 `pivot_root`  

---

### 2. UTS Namespace（门牌）

**作用**：隔离主机名和域名

**公寓比喻**：每个房间有自己的门牌号（主机名），大楼有大楼的名字（域名）。

```bash
# 创建独立主机名的环境
sudo unshare --uts bash

# 修改主机名 - 只影响这个 namespace
hostname container-01
hostname

# 退出后查看 - 宿主机主机名不变
exit
hostname
```

**实际效果**：
- 每个容器可以有自己的 hostname
- `docker run --hostname myapp` 就是使用 UTS Namespace

---

### 3. PID Namespace（家庭）

**作用**：隔离进程 ID 树

**公寓比喻**：每个房间里有自己的"户主"（PID 1）。在房间里你是户主，但在走廊里只是普通居民。

```bash
# 宿主机：容器进程是普通进程 (PID 12345)
ps aux | grep nginx

# 容器内：同一个进程是 PID 1
docker exec container ps aux
# PID 1 是 nginx
```

**关键概念**：
- 容器内第一个进程是 PID 1（init 进程）
- 宿主机能看到容器内所有进程（不同 PID）
- 容器看不到宿主机或其他容器的进程

```
宿主机视角:                容器内视角:
PID 1    = systemd         PID 1    = nginx
PID 12345 = nginx (容器)    PID 10   = nginx worker
PID 12346 = nginx worker    PID 11   = nginx worker
```

---

### 4. Network Namespace（对讲机）

**作用**：隔离网络栈

**公寓比喻**：每个房间有自己的电话分机（网络接口），需要电缆（veth pair）连接到大堂（bridge）才能打外线。

```bash
# 查看宿主机网络
ip addr
# eth0, docker0, ...

# 查看容器网络
docker exec container ip addr
# 只有 lo 和 eth0 (不同的 eth0！)
```

**实际效果**：
- 独立的网卡、IP 地址、路由表、iptables 规则
- 容器间网络隔离
- 需要 veth pair + bridge 才能通信

> 参考：如果你学过 [LX06 网络课程](../../lx06-networking/)，Network Namespace 应该不陌生。  
> [Lesson 08](../08-container-networking/) 将详细讲解容器网络架构。  

---

### 5. IPC Namespace（隔音）

**作用**：隔离进程间通信

**公寓比喻**：房间之间有隔音墙，你不能隔墙喊话（共享内存被隔离）。

```bash
# IPC 资源包括：
# - 共享内存 (shm)
# - 信号量 (semaphores)
# - 消息队列 (message queues)

# 查看 IPC 资源
ipcs

# 容器内的 IPC 资源与宿主机隔离
docker exec container ipcs
```

**实际效果**：
- 容器间无法通过 IPC 机制通信
- 防止容器间信息泄露
- 某些数据库使用共享内存，需要注意 IPC 配置

---

### 6. User Namespace（角色扮演）

**作用**：隔离用户和组 ID

**公寓比喻**：你在房间里可以扮演国王（root），但出门就是普通公民。

```bash
# 容器内
id
# uid=0(root) gid=0(root)

# 宿主机上看同一个进程
ps -eo pid,uid,gid,comm | grep <container-process>
# uid=100000 (非 root！)
```

**UID 映射示例**：

```
容器内 UID    宿主机 UID
─────────    ──────────
0 (root)  →  100000
1         →  100001
...
65535     →  165535
```

**安全价值**：
- 即使容器内是 root，逃逸后也是普通用户
- 实现 Rootless 容器的核心机制
- 满足"禁止 root 进程"的安全策略

> 参考：[Lesson 04](../04-user-namespace-rootless/) 将深入讲解 User Namespace 和 Rootless 容器  

---

### 7. Cgroup Namespace（水电表视图）

**作用**：隔离 cgroup 层级视图

**公寓比喻**：你只能看到自己房间的水电表，看不到整栋楼的表。

```bash
# 宿主机看到完整 cgroup 层级
ls /sys/fs/cgroup/

# 容器内只看到自己的 cgroup 子树
docker exec container cat /proc/1/cgroup
# 0::/
# (容器认为自己在 cgroup 根)
```

**注意**：这是最新的 Namespace 类型（Linux 4.6, 2016），主要用于：
- 让容器以为自己在 cgroup 根
- 防止容器看到宿主机 cgroup 信息
- 安全隔离考虑

---

## 🛠️ 动手实验：探索系统 Namespace

### 实验 1：使用 lsns 查看 Namespace

```bash
# 查看系统中所有 Namespace
sudo lsns

# 输出示例：
#         NS TYPE   NPROCS   PID USER  COMMAND
# 4026531834 time       89     1 root  /sbin/init
# 4026531835 cgroup     89     1 root  /sbin/init
# 4026531836 pid        89     1 root  /sbin/init
# 4026531837 user       89     1 root  /sbin/init
# 4026531838 uts        89     1 root  /sbin/init
# 4026531839 ipc        89     1 root  /sbin/init
# 4026531840 net        89     1 root  /sbin/init
# 4026531841 mnt        87     1 root  /sbin/init
```

**字段解释**：
- `NS`：Namespace inode 编号（唯一标识）
- `TYPE`：Namespace 类型
- `NPROCS`：使用此 Namespace 的进程数
- `PID`：创建此 Namespace 的进程
- `COMMAND`：进程命令

### 实验 2：查看进程的 Namespace

```bash
# 查看 init 进程 (PID 1) 的 Namespace
ls -la /proc/1/ns/

# 输出示例：
# lrwxrwxrwx 1 root root 0 Jan  4 10:00 cgroup -> 'cgroup:[4026531835]'
# lrwxrwxrwx 1 root root 0 Jan  4 10:00 ipc -> 'ipc:[4026531839]'
# lrwxrwxrwx 1 root root 0 Jan  4 10:00 mnt -> 'mnt:[4026531841]'
# lrwxrwxrwx 1 root root 0 Jan  4 10:00 net -> 'net:[4026531840]'
# lrwxrwxrwx 1 root root 0 Jan  4 10:00 pid -> 'pid:[4026531836]'
# lrwxrwxrwx 1 root root 0 Jan  4 10:00 user -> 'user:[4026531837]'
# lrwxrwxrwx 1 root root 0 Jan  4 10:00 uts -> 'uts:[4026531838]'
```

### 实验 3：比较宿主机进程和容器进程

```bash
# 启动一个容器
docker run -d --name test-nginx nginx

# 获取容器内 PID 1 在宿主机的 PID
CONTAINER_PID=$(docker inspect --format '{{.State.Pid}}' test-nginx)
echo "Container PID on host: $CONTAINER_PID"

# 比较 Namespace
echo "=== Host init (PID 1) Namespace ==="
ls -la /proc/1/ns/

echo "=== Container process Namespace ==="
ls -la /proc/$CONTAINER_PID/ns/

# 关键观察：inode 编号不同 = 不同的 Namespace！
```

### 实验 4：验证 Namespace 隔离效果

```bash
# 容器内的进程树
docker exec test-nginx ps aux
# 只能看到容器内的进程

# 容器内的网络
docker exec test-nginx ip addr
# 只有 lo 和容器的 eth0

# 容器内的主机名
docker exec test-nginx hostname
# 输出容器 ID 前 12 位

# 清理
docker rm -f test-nginx
```

---

## 💡 职场小贴士

### Linux Namespace vs Kubernetes Namespace

在日本 IT 职场，你会经常听到"名前空間"这个词。但要注意区分两个完全不同的概念：

| 术语 | 含义 | 层级 |
|------|------|------|
| Linux Namespace | 内核级进程隔离机制 | OS 层 |
| Kubernetes Namespace | 资源分组和访问控制 | 应用层 |

```
⚠️ 日本語での注意点：
「Namespace」と言われたら、文脈を確認：
- OS/Container の話 → Linux Namespace (今回の内容)
- K8s の話 → Kubernetes Namespace (別概念)
```

### 面试常见问题

**Q: コンテナの隔離はどのように実現されていますか？**

A: Linux Namespace と cgroups の組み合わせです。Namespace は「見えるもの」を制限（PID, Network, Mount など 7 種類）、cgroups は「使えるリソース」を制限（CPU, メモリ, IO）。

**Q: 7 種類の Namespace を説明できますか？**

A: Mount（ファイルシステム）、UTS（ホスト名）、PID（プロセス ID）、Network（ネットワーク）、IPC（プロセス間通信）、User（UID/GID）、Cgroup（cgroup ビュー）です。

---

## 🎯 检查清单

完成本课后，你应该能够：

- [ ] 解释 Namespace 和 cgroups 的区别（"能看到什么" vs "能用多少"）
- [ ] 说出 7 种 Namespace 类型及其作用
- [ ] 使用"公寓楼比喻"向他人解释 Namespace
- [ ] 使用 `lsns` 查看系统 Namespace
- [ ] 查看 `/proc/<PID>/ns/` 确定进程的 Namespace
- [ ] 比较宿主机进程和容器进程的 Namespace 差异
- [ ] 区分 Linux Namespace 和 Kubernetes Namespace

---

## 📖 核心概念总结

### Namespace 总览

```
┌─────────────────────────────────────────────────────────────┐
│                    7 种 Linux Namespace                      │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  Mount NS    UTS NS     PID NS     Network NS               │
│  (文件系统)   (主机名)    (进程 ID)   (网络栈)                  │
│      │          │          │           │                    │
│      ▼          ▼          ▼           ▼                    │
│   墙壁        门牌       家庭        对讲机                   │
│                                                             │
│  IPC NS      User NS    Cgroup NS                           │
│  (进程通信)   (UID/GID)   (cgroup 视图)                       │
│      │          │          │                                │
│      ▼          ▼          ▼                                │
│   隔音       角色扮演    水电表                               │
│                                                             │
└─────────────────────────────────────────────────────────────┘

关键理解：
- Namespace 控制进程能"看到"什么（隔离可见性）
- cgroups 控制进程能"使用"多少（限制资源）
- 容器 = Namespace + cgroups + OverlayFS + seccomp + ...
```

---

## 🔧 常用命令速查

```bash
# 查看所有 Namespace
sudo lsns

# 查看特定类型的 Namespace
sudo lsns -t net
sudo lsns -t pid

# 查看进程的 Namespace
ls -la /proc/<PID>/ns/

# 查看当前 shell 的 Namespace
ls -la /proc/$$/ns/

# 比较两个进程是否在同一 Namespace
readlink /proc/1/ns/net
readlink /proc/$$/ns/net
# inode 相同 = 同一 Namespace
```

---

## 📚 延伸阅读

- [Lesson 03: Namespace 深入 - unshare 与 nsenter](../03-namespace-deep-dive/)
- [Lesson 04: User Namespace 与 Rootless 容器](../04-user-namespace-rootless/)
- [Lesson 08: 容器网络架构](../08-container-networking/)
- [man 7 namespaces](https://man7.org/linux/man-pages/man7/namespaces.7.html) - Linux 手册
- [man 1 lsns](https://man7.org/linux/man-pages/man1/lsns.1.html) - lsns 命令

---

## 系列导航

[01 · 容器 vs 虚拟机](../01-containers-vs-vms/) | [Home](../) | [03 · Namespace 深入 →](../03-namespace-deep-dive/)
