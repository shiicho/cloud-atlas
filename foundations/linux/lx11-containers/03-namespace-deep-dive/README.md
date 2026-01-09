# 03 - Namespace 深入：unshare 与 nsenter

> **目标**：掌握 unshare 和 nsenter 命令，学会从宿主机级别调试容器  
> **前置**：完成 [02 - Linux Namespace 基础](../02-namespace-basics/)  
> **时间**：2.5 小时  
> **场景**：本番環境でのコンテナ障害対応（生产环境容器故障处理）  

---

## 将学到的内容

1. 使用 `unshare` 创建各种 Namespace
2. 使用 `nsenter` 进入现有 Namespace
3. 理解 PID/Mount/UTS/IPC Namespace 的具体隔离效果
4. 掌握从宿主机调试容器的关键技巧
5. 学会绕过 `docker exec` 的限制进行故障排查

---

## 先跑起来！（5 分钟）

> 在学习理论之前，先体验 Namespace 隔离的威力。  

```bash
# 创建一个隔离的 PID Namespace
# 在里面，你的 shell 是 PID 1！
sudo unshare --pid --fork --mount-proc /bin/bash

# 查看进程列表——只有你自己！
ps aux

# 你的 PID 是什么？
echo $$

# 退出隔离环境
exit

# 回到宿主机，验证你看到的只是"幻觉"
ps aux | head -5
```

**你刚刚体验了什么？**

- 在 `unshare` 创建的环境中，`ps aux` 只显示两个进程
- 你的 shell 进程 PID 是 1！
- 但在宿主机上，这只是一个普通进程

**这就是容器隔离的核心原理。** 现在让我们深入理解。

---

## Step 1 - 理解 unshare 命令（20 分钟）

### 1.1 什么是 unshare？

`unshare` 是 Linux 创建新 Namespace 的工具。它让进程"脱离"父进程的 Namespace，进入独立的隔离环境。

```bash
# 查看 unshare 帮助
unshare --help
```

**常用选项：**

| 选项 | 含义 | 创建的 Namespace |
|------|------|------------------|
| `--pid` | 进程隔离 | PID Namespace |
| `--mount` | 挂载隔离 | Mount Namespace |
| `--net` | 网络隔离 | Network Namespace |
| `--uts` | 主机名隔离 | UTS Namespace |
| `--ipc` | IPC 隔离 | IPC Namespace |
| `--user` | 用户隔离 | User Namespace |
| `--cgroup` | cgroup 隔离 | Cgroup Namespace |

### 1.2 关键标志：--fork 和 --mount-proc

创建 PID Namespace 时，有两个重要标志：

```
为什么需要 --fork？

没有 --fork:
┌─────────────────────────────────────────────────────────┐
│  宿主机 PID Namespace                                    │
│  ┌─────────────────────────────────────────────────┐    │
│  │  unshare 进程 (PID 12345)                        │    │
│  │     └──▶ 创建新 PID Namespace                    │    │
│  │                                                  │    │
│  │  问题：unshare 自己在旧 Namespace 中！            │    │
│  └─────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────┘

有 --fork:
┌─────────────────────────────────────────────────────────┐
│  宿主机 PID Namespace                                    │
│  ┌─────────────────────────────────────────────────┐    │
│  │  unshare 进程 (PID 12345)                        │    │
│  │     └──▶ fork() 创建子进程                       │    │
│  │              │                                   │    │
│  │              ▼                                   │    │
│  │  ┌───────────────────────────────────┐          │    │
│  │  │  新 PID Namespace                  │          │    │
│  │  │  子进程 (PID 1 在新 NS 中)         │          │    │
│  │  │  └──▶ exec /bin/bash              │          │    │
│  │  └───────────────────────────────────┘          │    │
│  └─────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────┘
```

```
为什么需要 --mount-proc？

/proc 是进程信息的来源：
  /proc/1/   → PID 1 的信息
  /proc/2/   → PID 2 的信息
  ...

没有重新挂载 /proc：
  ps aux 读取宿主机的 /proc
  → 显示宿主机的所有进程

使用 --mount-proc：
  在新 Namespace 中重新挂载 /proc
  → ps aux 只显示新 Namespace 的进程
```

### 1.3 动手实验：PID Namespace

```bash
# 实验 1：没有 --fork 的问题
sudo unshare --pid /bin/bash
echo $$  # 不是 1！
ps aux   # 看到所有进程
exit

# 实验 2：正确使用 --fork
sudo unshare --pid --fork /bin/bash
echo $$  # 还是不是 1，因为 /proc 没更新
ps aux   # 看到所有进程（读的是宿主机 /proc）
exit

# 实验 3：完整的隔离（推荐方式）
sudo unshare --pid --fork --mount-proc /bin/bash
echo $$  # 是 1！
ps aux   # 只看到当前 Namespace 的进程
exit
```

---

## Step 2 - 各种 Namespace 实践（30 分钟）

### 2.1 PID Namespace 深入实验

```bash
# 终端 1：创建隔离环境
sudo unshare --pid --fork --mount-proc /bin/bash

# 在隔离环境中
echo "我是 PID: $$"
sleep 3600 &
ps aux
```

```bash
# 终端 2：从宿主机观察
# 找到刚才的 bash 进程
ps aux | grep "unshare\|sleep 3600"

# 你会看到类似：
# root      12345  ... unshare --pid --fork --mount-proc /bin/bash
# root      12346  ... /bin/bash
# root      12347  ... sleep 3600

# 隔离环境中的 "PID 1" 在宿主机是 PID 12346
# 隔离环境中的 "PID 2" 在宿主机是 PID 12347
```

**关键洞察**：父 Namespace 能看到子 Namespace 的所有进程，但子 Namespace 看不到父 Namespace 的进程。

### 2.2 Mount Namespace 实验

Mount Namespace 让你拥有独立的挂载点视图。

```bash
# 创建 Mount Namespace
sudo unshare --mount /bin/bash

# 创建临时目录并挂载
mkdir -p /tmp/myroot
mount -t tmpfs none /tmp/myroot
echo "secret data" > /tmp/myroot/secret.txt

# 验证挂载存在
mount | grep myroot
cat /tmp/myroot/secret.txt

# 退出
exit

# 在宿主机验证
mount | grep myroot  # 没有！
ls /tmp/myroot/      # 目录存在但是空的
```

**为什么？** Mount Namespace 中的挂载是私有的，退出后自动卸载。

### 2.3 UTS Namespace 实验

UTS Namespace 隔离主机名。

```bash
# 创建 UTS Namespace
sudo unshare --uts /bin/bash

# 查看原主机名
hostname

# 修改主机名
hostname container-001

# 验证修改
hostname

# 退出
exit

# 宿主机主机名未变
hostname
```

**用途**：每个容器可以有自己的主机名，互不影响。

### 2.4 IPC Namespace 实验

IPC Namespace 隔离进程间通信（共享内存、信号量、消息队列）。

```bash
# 查看当前 IPC 资源
ipcs

# 创建 IPC Namespace
sudo unshare --ipc /bin/bash

# 在新 Namespace 中查看 IPC
ipcs  # 应该是空的（没有继承宿主机的 IPC 资源）

# 创建一个共享内存段
ipcmk -M 1024

# 验证创建
ipcs

# 退出
exit

# 宿主机看不到刚才创建的共享内存
ipcs
```

### 2.5 组合多个 Namespace

容器通常同时使用多个 Namespace：

```bash
# 模拟容器环境（多个 Namespace 组合）
sudo unshare --pid --fork --mount-proc --uts --ipc --mount /bin/bash

# 验证隔离
hostname mycontainer    # 修改主机名
hostname                # mycontainer
ps aux                  # 只有 Namespace 内的进程
ipcs                    # 独立的 IPC

exit
```

---

## Step 3 - nsenter：进入现有 Namespace（30 分钟）

### 3.1 什么是 nsenter？

`nsenter` 让你进入一个**已存在**的 Namespace。这是容器调试的核心工具。

```
nsenter 工作原理：

┌───────────────────────────────────────────────────────────┐
│  宿主机                                                    │
│  ┌─────────────────────────────────────────────────────┐  │
│  │  你的 Shell (PID 1234)                               │  │
│  │                                                      │  │
│  │  nsenter -t 5678 -n                                  │  │
│  │       │                                              │  │
│  │       ▼                                              │  │
│  │  ┌──────────────────────────────────────────────┐   │  │
│  │  │  容器进程 (PID 5678)                          │   │  │
│  │  │  Network Namespace: inode 4026532456          │   │  │
│  │  │                                               │   │  │
│  │  │    ← nsenter 进入这个 Network Namespace       │   │  │
│  │  │    ← 执行命令（如 ip addr）                   │   │  │
│  │  └──────────────────────────────────────────────┘   │  │
│  └─────────────────────────────────────────────────────┘  │
└───────────────────────────────────────────────────────────┘
```

### 3.2 nsenter 选项

| 选项 | 含义 | 用途 |
|------|------|------|
| `-t PID` | 目标进程 PID | 指定要进入的 Namespace 所属进程 |
| `-n` | Network | 进入网络 Namespace |
| `-m` | Mount | 进入挂载 Namespace |
| `-p` | PID | 进入 PID Namespace |
| `-u` | UTS | 进入 UTS Namespace |
| `-i` | IPC | 进入 IPC Namespace |
| `-U` | User | 进入用户 Namespace |
| `-a` | All | 进入所有 Namespace |

### 3.3 动手实验：使用 nsenter 调试容器

首先，启动一个容器（如果没有 Docker，跳到 3.4 使用 unshare 替代）：

```bash
# 启动一个 nginx 容器
docker run -d --name test-nginx nginx

# 获取容器的 PID
PID=$(docker inspect --format '{{.State.Pid}}' test-nginx)
echo "容器 PID: $PID"
```

**场景 1：调试容器网络**

```bash
# 只进入 Network Namespace
sudo nsenter -t $PID -n ip addr

# 测试容器网络连通性
sudo nsenter -t $PID -n ping -c 3 8.8.8.8

# 查看容器路由表
sudo nsenter -t $PID -n ip route

# 查看容器 DNS 配置
sudo nsenter -t $PID -n cat /etc/resolv.conf
```

**场景 2：调试容器文件系统**

```bash
# 进入 Mount Namespace
sudo nsenter -t $PID -m ls /

# 查看 nginx 配置
sudo nsenter -t $PID -m cat /etc/nginx/nginx.conf

# 查看容器内进程打开的文件
sudo nsenter -t $PID -m -p ls -la /proc/1/fd
```

**场景 3：完整进入容器**

```bash
# 进入所有 Namespace
sudo nsenter -t $PID -a /bin/bash

# 现在你就像在容器内部一样
hostname
ps aux
ip addr
exit
```

清理：

```bash
docker stop test-nginx && docker rm test-nginx
```

### 3.4 无 Docker 替代实验

如果没有 Docker，可以用 `unshare` 创建目标进程：

```bash
# 终端 1：创建一个长期运行的隔离进程
sudo unshare --pid --fork --mount-proc --net --uts /bin/bash -c "
hostname isolated-container
sleep 3600
"
```

```bash
# 终端 2：找到进程并使用 nsenter
# 找到 sleep 进程的 PID
PID=$(pgrep -f "sleep 3600" | head -1)
echo "目标 PID: $PID"

# 进入 UTS Namespace 查看主机名
sudo nsenter -t $PID -u hostname

# 进入 Network Namespace
sudo nsenter -t $PID -n ip addr

# 进入 PID Namespace（需要同时进入 Mount 才能看到正确的 /proc）
sudo nsenter -t $PID -p -m ps aux
```

---

## Step 4 - nsenter 调试模式：绕过 docker exec（30 分钟）

### 4.1 为什么需要 nsenter？

在生产环境中，`docker exec` 可能不可用：

| 场景 | 问题 | nsenter 优势 |
|------|------|-------------|
| Distroless 镜像 | 无 shell、无工具 | 使用宿主机工具调试容器网络 |
| docker exec 卡死 | daemon 问题 | 绕过 Docker daemon 直接操作 |
| 最小权限策略 | 禁止 docker exec | nsenter 只需 root 权限 |
| CRI-O/containerd | 不同工具集 | nsenter 通用于所有运行时 |

### 4.2 Distroless 容器调试模式

**场景**：Go 应用部署在 distroless 镜像中，无法连接数据库，需要调试网络。

```
Distroless 镜像特点：
- 无 shell（/bin/sh, /bin/bash）
- 无调试工具（curl, ping, nc）
- 只有应用二进制文件

┌────────────────────────────────────────────────────────┐
│  Distroless Container                                   │
│  ┌──────────────────────────────────────────────────┐  │
│  │                                                   │  │
│  │   /app/myapp  ← 只有这个二进制文件               │  │
│  │                                                   │  │
│  │   ❌ 无 /bin/sh                                  │  │
│  │   ❌ 无 curl, ping, nc                           │  │
│  │   ❌ docker exec 无法进入                        │  │
│  │                                                   │  │
│  └──────────────────────────────────────────────────┘  │
│                                                         │
│  nsenter -t <PID> -n ← 使用宿主机工具调试容器网络      │
│                                                         │
└────────────────────────────────────────────────────────┘
```

**调试步骤**：

```bash
# 1. 找到容器 PID
# Docker
PID=$(docker inspect --format '{{.State.Pid}}' <container>)

# containerd (crictl)
# PID=$(crictl inspect <container-id> | jq '.info.pid')

# 2. 只进入 Network Namespace 调试
# 使用宿主机的 ping 测试连通性
sudo nsenter -t $PID -n ping -c 3 database.internal

# 使用宿主机的 curl 测试 HTTP
sudo nsenter -t $PID -n curl -v http://api.internal:8080/health

# 使用宿主机的 dig/nslookup 测试 DNS
sudo nsenter -t $PID -n dig database.internal

# 使用宿主机的 ss 查看连接状态
sudo nsenter -t $PID -n ss -tuln

# 使用宿主机的 tcpdump 抓包
sudo nsenter -t $PID -n tcpdump -i eth0 -n port 5432
```

### 4.3 标准调试模式模板

**nsenter-debug.sh**（参考 code/ 目录）

```bash
#!/bin/bash
# nsenter 调试模式模板

if [ -z "$1" ]; then
    echo "用法: $0 <container-name-or-pid>"
    exit 1
fi

# 自动检测 PID
if [[ "$1" =~ ^[0-9]+$ ]]; then
    PID=$1
elif command -v docker &>/dev/null; then
    PID=$(docker inspect --format '{{.State.Pid}}' "$1" 2>/dev/null)
elif command -v crictl &>/dev/null; then
    PID=$(crictl inspect "$1" 2>/dev/null | jq -r '.info.pid')
fi

if [ -z "$PID" ] || [ "$PID" = "null" ]; then
    echo "错误：无法获取 PID"
    exit 1
fi

echo "========================================"
echo "  nsenter 调试模式"
echo "  目标 PID: $PID"
echo "========================================"
echo ""

echo "【1. 网络调试】"
echo "$ nsenter -t $PID -n ip addr"
sudo nsenter -t "$PID" -n ip addr
echo ""

echo "$ nsenter -t $PID -n ip route"
sudo nsenter -t "$PID" -n ip route
echo ""

echo "$ nsenter -t $PID -n ss -tuln"
sudo nsenter -t "$PID" -n ss -tuln
echo ""

echo "【2. 进程调试】"
echo "$ nsenter -t $PID -p -m ps aux"
sudo nsenter -t "$PID" -p -m ps aux 2>/dev/null || echo "需要 --mount-proc 或无法访问"
echo ""

echo "【3. 文件系统调试】"
echo "$ nsenter -t $PID -m ls /"
sudo nsenter -t "$PID" -m ls /
echo ""

echo "【4. 进入完整调试 shell】"
echo "$ nsenter -t $PID -a /bin/bash"
echo "（运行 'sudo nsenter -t $PID -a /bin/bash' 进入）"
```

### 4.4 选择性进入 Namespace 的场景

| 场景 | 命令 | 说明 |
|------|------|------|
| 网络调试 | `nsenter -t PID -n` | 只进入网络 NS，使用宿主机工具 |
| 文件检查 | `nsenter -t PID -m` | 只进入挂载 NS，查看容器文件 |
| 进程调试 | `nsenter -t PID -m -p` | 进入挂载+PID NS |
| 完整进入 | `nsenter -t PID -a` | 进入所有 NS |

---

## Step 5 - 生产场景实战（20 分钟）

### 5.1 场景：卡死的容器进程

**问题**：Java 容器僵死，`docker exec` 挂起无响应。

```bash
# 1. 找到容器 PID（绕过 Docker daemon）
PID=$(cat /proc/$(pgrep -f "docker-containerd-shim")/task/*/children | head -1)

# 或者直接从 /proc 查找
ps aux | grep java  # 找到 Java 进程 PID

# 2. 进入 Mount + PID Namespace 调试
sudo nsenter -t $PID -m -p /bin/bash

# 3. 检查进程状态
cat /proc/1/status | grep State

# 4. 检查文件描述符（找阻塞点）
ls -la /proc/1/fd

# 5. 检查调用栈
cat /proc/1/stack  # 内核栈
```

### 5.2 场景：检查容器 Namespace 信息

```bash
# 查看进程的所有 Namespace
ls -la /proc/$PID/ns/

# 输出示例：
# lrwxrwxrwx 1 root root 0 Jan  4 12:00 cgroup -> 'cgroup:[4026531835]'
# lrwxrwxrwx 1 root root 0 Jan  4 12:00 ipc -> 'ipc:[4026532456]'
# lrwxrwxrwx 1 root root 0 Jan  4 12:00 mnt -> 'mnt:[4026532454]'
# lrwxrwxrwx 1 root root 0 Jan  4 12:00 net -> 'net:[4026532459]'
# lrwxrwxrwx 1 root root 0 Jan  4 12:00 pid -> 'pid:[4026532457]'
# lrwxrwxrwx 1 root root 0 Jan  4 12:00 user -> 'user:[4026531837]'
# lrwxrwxrwx 1 root root 0 Jan  4 12:00 uts -> 'uts:[4026532455]'

# 比较两个进程是否在同一 Namespace
ls -la /proc/$PID1/ns/net
ls -la /proc/$PID2/ns/net
# inode 相同 = 同一 Namespace
```

### 5.3 场景：使用 lsns 查看系统 Namespace

```bash
# 列出所有 Namespace
sudo lsns

# 按类型过滤
sudo lsns -t net  # 只看 Network Namespace
sudo lsns -t pid  # 只看 PID Namespace

# 查看特定进程的 Namespace
sudo lsns -p $PID
```

---

## 职场小贴士（Japan IT Context）

### 本番環境でのコンテナ障害対応

在日本企业的生产环境中，`docker exec` 经常不可用：

| 场景 | 日语术语 | nsenter 解决方案 |
|------|----------|------------------|
| Distroless 镜像 | 軽量イメージ | `nsenter -n` 用宿主机工具 |
| 禁止 docker exec | セキュリティポリシー | nsenter 绕过 daemon |
| docker daemon 异常 | Docker 障害 | nsenter 直接操作 Namespace |
| Kubernetes CRI-O | K8s 環境 | nsenter 通用于所有运行时 |

### 障害対応の基本フロー

```
コンテナ障害対応の手順：

1. docker inspect で PID 取得
   → 取得できない場合：ps aux | grep <app>

2. nsenter -t <PID> -n で网络调试
   → ping, curl, dig で接続確認

3. nsenter -t <PID> -m で文件系统检查
   → ログファイル、設定ファイル確認

4. nsenter -t <PID> -m -p で进程调试
   → ps aux, /proc/<PID>/fd 確認

5. 証拠を報告書に添付
   → コマンド出力のスクリーンショット
```

### 常见日语术语

| 日语 | 读音 | 含义 |
|------|------|------|
| 名前空間 | なまえくうかん | Namespace |
| 分離 | ぶんり | Isolation |
| デバッグ | デバッグ | Debug |
| コンテナ内 | コンテナない | Inside container |
| ホスト側 | ホストがわ | Host side |

---

## 检查清单

完成本课后，你应该能够：

- [ ] 使用 `unshare --pid --fork --mount-proc` 创建 PID Namespace
- [ ] 解释为什么需要 `--fork` 和 `--mount-proc` 标志
- [ ] 使用 `unshare --mount` 创建独立挂载环境
- [ ] 使用 `unshare --uts` 创建独立主机名环境
- [ ] 使用 `nsenter -t PID -n` 进入容器网络调试
- [ ] 使用 `nsenter -t PID -m` 进入容器文件系统
- [ ] 使用 `nsenter -t PID -a` 完整进入容器
- [ ] 获取容器进程 PID（docker inspect 或 ps aux）
- [ ] 绕过 docker exec 调试 Distroless 容器
- [ ] 使用 lsns 查看系统 Namespace

---

## 本课小结

| 概念 | 要点 |
|------|------|
| unshare | 创建新 Namespace，脱离父进程的隔离边界 |
| --fork | PID Namespace 需要 fork 子进程成为 PID 1 |
| --mount-proc | 重新挂载 /proc 以正确显示隔离后的进程 |
| nsenter | 进入已存在的 Namespace，用于调试 |
| 选择性进入 | -n 网络、-m 挂载、-p PID、-a 所有 |
| 调试模式 | nsenter 绕过 docker exec 限制 |

---

## 反模式：常见错误

### 错误 1：忘记 --fork 导致 PID 不是 1

```bash
# 错误
sudo unshare --pid /bin/bash
echo $$  # 不是 1！

# 正确
sudo unshare --pid --fork /bin/bash
echo $$  # 是 1（如果加了 --mount-proc）
```

### 错误 2：nsenter 只进入 PID Namespace 看不到进程

```bash
# 错误
sudo nsenter -t $PID -p ps aux
# 报错或显示宿主机进程

# 正确（需要同时进入 Mount Namespace）
sudo nsenter -t $PID -p -m ps aux
```

### 错误 3：依赖 docker exec 而非 nsenter

```bash
# docker exec 的局限：
# - 需要 Docker daemon 正常
# - Distroless 镜像无法进入
# - 可能被安全策略禁止

# nsenter 的优势：
# - 直接操作 Namespace，不依赖 daemon
# - 使用宿主机工具
# - 只需 root 权限
```

---

## 延伸阅读

- [Linux Namespaces man page](https://man7.org/linux/man-pages/man7/namespaces.7.html)
- [unshare(1) man page](https://man7.org/linux/man-pages/man1/unshare.1.html)
- [nsenter(1) man page](https://man7.org/linux/man-pages/man1/nsenter.1.html)
- 下一课：[04 - User Namespace 与 Rootless 容器](../04-user-namespace-rootless/)
- 相关课程：[11 - 容器故障排查](../11-debugging-troubleshooting/) - 完整排查方法论

---

## 面试准备（Interview Prep）

### Q1: unshare と nsenter の違いは？

**回答要点**：

```
unshare:
- 新しい Namespace を作成
- 現在のプロセスを新 Namespace に移動
- コンテナ環境の構築に使用

nsenter:
- 既存の Namespace に入る
- 他のプロセスの Namespace を共有
- コンテナのデバッグに使用
```

### Q2: docker exec が使えない時の対処法は？

**回答要点**：

```
1. docker inspect で PID を取得
   PID=$(docker inspect --format '{{.State.Pid}}' <container>)

2. nsenter でNamespace に直接入る
   nsenter -t $PID -n  # ネットワーク
   nsenter -t $PID -m  # ファイルシステム
   nsenter -t $PID -a  # 全部

3. ホストのツールでデバッグ
   nsenter -t $PID -n ping 8.8.8.8
   nsenter -t $PID -n tcpdump
```

### Q3: PID Namespace で --fork が必要な理由は？

**回答要点**：

```
PID Namespace の作成者自身は古い Namespace に残る。
--fork で子プロセスを作り、その子プロセスが新 Namespace の PID 1 になる。
これにより、その子プロセスから見ると自分が init プロセス。
```

---

## 系列导航

[<- 02 - Namespace 基础](../02-namespace-basics/) | [系列首页](../) | [04 - User Namespace -->](../04-user-namespace-rootless/)
