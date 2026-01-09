# 11 - 容器故障排查：观测与定位

> **目标**：建立容器故障排查系统方法论，整合前 10 课知识，掌握 OOM/网络/存储/进程四大问题的定位技巧  
> **前置**：[Lesson 10 - OCI 运行时](../10-oci-runtimes/)；建议完成 Lesson 03 (nsenter)、06 (cgroups)、08 (网络)  
> **时间**：2.5 小时  
> **场景**：障害対応スキル（故障对应技能）—— 日本 IT 运维现场最重要的能力  

---

## 将学到的内容

1. 建立容器故障排查系统方法论（4 步定位法）
2. 调查「静默 OOM Kill」—— 夜间批处理消失的真相
3. 使用 nsenter 调试 Distroless 黑箱容器（无 shell/curl/ping）
4. 定位「磁盘空间之谜」—— Zabbix 告警但容器内看不到
5. 绕过 docker exec 调试卡死容器

**本课是「技能整合课」**：你将运用前 10 课所有知识解决真实生产问题。

---

## 先跑起来：5 分钟调查「消失的进程」

> **不讲原理，先动手！** 模拟一个进程「神秘消失」的场景，然后找到证据。  

### 创建受限 cgroup

```bash
# 创建 cgroup，限制内存 30MB
sudo mkdir /sys/fs/cgroup/mystery-gone
echo "30M" | sudo tee /sys/fs/cgroup/mystery-gone/memory.max

# 启动一个「会消失」的进程
sudo bash -c 'echo $$ > /sys/fs/cgroup/mystery-gone/cgroup.procs && stress --vm 1 --vm-bytes 50M --timeout 60s'
```

输出：

```
stress: info: [12345] dispatching hogs: 0 cpu, 0 io, 1 vm, 0 hdd
stress: FAIL: [12345] (415) <-- worker 12346 got signal 9
stress: WARN: [12345] (417) now reaping child worker processes
stress: FAIL: [12345] (451) failed run completed in 0s
```

进程「消失」了！没有任何应用日志。这就是运维现场的典型问题。

### 找到证据

**证据 1：内核日志**

```bash
dmesg | grep -i oom | tail -5
```

输出：

```
[xxxxx.xxxxxx] oom-kill:constraint=CONSTRAINT_MEMCG...
[xxxxx.xxxxxx] Memory cgroup out of memory: Killed process 12346 (stress)
```

**证据 2：cgroup 事件统计**

```bash
cat /sys/fs/cgroup/mystery-gone/memory.events
```

输出：

```
low 0
high 0
max 1
oom 1
oom_kill 1
```

**oom_kill 1** —— 铁证！内核因内存限制杀死了进程。

### 清理

```bash
sudo rmdir /sys/fs/cgroup/mystery-gone
```

---

**你刚刚做了什么？**

```
┌─────────────────────────────────────────────────────────────────────┐
│                     故障排查黄金法则                                 │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  应用日志：空                                                        │
│       │                                                             │
│       ▼                                                             │
│  「进程消失了，但我不知道为什么」                                     │
│       │                                                             │
│       ▼                                                             │
│  容器日志不够！需要检查宿主机：                                        │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │ dmesg           →  内核杀死进程的记录                        │   │
│  │ memory.events   →  cgroup OOM 事件统计                       │   │
│  │ audit.log       →  seccomp/SELinux 拒绝                      │   │
│  └─────────────────────────────────────────────────────────────┘   │
│                                                                     │
│  反模式：「只看容器日志，不看宿主机 dmesg」                            │
│  → OOM Kill 和 seccomp 拒绝只在宿主机可见！                          │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

这就是本课的核心思想：**容器问题往往需要从宿主机视角诊断**。

---

## 核心概念：故障排查方法论

### 4 步定位法

```
┌─────────────────────────────────────────────────────────────────────┐
│                    容器故障排查 4 步定位法                            │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  Step 1: 确定问题类型                                                │
│  ┌──────────────┬──────────────┬──────────────┬──────────────┐      │
│  │   启动失败   │   运行时消失  │   网络不通   │   资源问题   │      │
│  │  (Startup)   │  (Runtime)   │  (Network)   │  (Resource)  │      │
│  └──────────────┴──────────────┴──────────────┴──────────────┘      │
│                                                                     │
│  Step 2: 收集证据                                                   │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │ 容器层: docker logs, docker inspect                          │   │
│  │ 宿主机: dmesg, journalctl, /var/log/audit/audit.log          │   │
│  │ cgroup: memory.events, cpu.stat, pids.current                │   │
│  │ Namespace: nsenter 进入检查                                   │   │
│  └──────────────────────────────────────────────────────────────┘   │
│                                                                     │
│  Step 3: 隔离问题层                                                 │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │         应用层 (App)                                          │   │
│  │              ↓                                                │   │
│  │         容器层 (Container Runtime)                            │   │
│  │              ↓                                                │   │
│  │         宿主机层 (Host OS)                                    │   │
│  │              ↓                                                │   │
│  │         内核层 (Kernel: cgroups, namespaces, seccomp)         │   │
│  └──────────────────────────────────────────────────────────────┘   │
│                                                                     │
│  Step 4: 验证修复                                                   │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │ 复现问题 → 应用修复 → 验证修复 → 监控防止复发                  │   │
│  └──────────────────────────────────────────────────────────────┘   │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

### 日志层级：从哪里找证据？

| 问题类型 | 应用日志 | 容器日志 | 宿主机日志 | cgroup 文件 |
|----------|----------|----------|------------|-------------|
| OOM Kill | 无 | 无/突然停止 | **dmesg 有记录** | **memory.events** |
| seccomp 拒绝 | 可能有 | 可能有 | **dmesg/audit.log** | - |
| 网络不通 | 超时错误 | - | - | - |
| CPU 限流 | 变慢 | - | - | **cpu.stat** |
| 磁盘满 | 写入失败 | - | df -h | - |

**关键认识**：容器日志是「应用视角」，宿主机日志是「内核视角」。很多问题只有内核知道！

---

## 场景 1：Silent OOM Kill（静默 OOM Kill）

### 问题描述

```
状況：
每天凌晨 3 点，夜间批处理容器突然消失。
检查应用日志：空。
检查 docker logs：什么都没有。
工程师需要证明是内核杀死了进程，而非应用 bug。

日本语：
夜間バッチが 03:00 に異常終了。アプリケーションログに記録なし。
```

### 动手排查

**运行演示脚本**：

```bash
cd ~/cloud-atlas/foundations/linux/containers/11-debugging-troubleshooting/code
sudo ./silent-oom-scenario.sh
```

**或手动执行**：

**步骤 1：模拟夜间批处理（受 cgroup 限制）**

```bash
# 创建 cgroup 模拟 Kubernetes Pod 资源限制
sudo mkdir -p /sys/fs/cgroup/batch-job
echo "100M" | sudo tee /sys/fs/cgroup/batch-job/memory.max

# 运行「批处理」（会被 OOM Kill）
sudo bash -c 'echo $$ > /sys/fs/cgroup/batch-job/cgroup.procs && stress --vm 1 --vm-bytes 200M --timeout 60s'
```

进程立即消失，无任何应用输出。

**步骤 2：收集证据**

```bash
# 证据 1：内核日志（最关键！）
dmesg | grep -i oom | tail -10
```

输出：

```
[xxxxx.xxxxxx] oom-kill:constraint=CONSTRAINT_MEMCG,nodemask=...
[xxxxx.xxxxxx] Memory cgroup out of memory: Killed process XXXX (stress) ...
[xxxxx.xxxxxx] oom_reaper: reaped process XXXX (stress), now anon-rss:0kB ...
```

```bash
# 证据 2：cgroup OOM 事件统计
cat /sys/fs/cgroup/batch-job/memory.events
```

输出：

```
low 0
high 0
max 1
oom 1
oom_kill 1
oom_group_kill 0
```

```bash
# 证据 3：journalctl 内核消息
journalctl -k --since "5 minutes ago" | grep -i oom
```

**步骤 3：生成障害報告書（事故报告）**

```markdown
## 障害報告書

### 事象
夜間バッチ処理が 03:00 に異常終了。アプリケーションログに記録なし。

### 原因
cgroup メモリ制限 (100MB) による OOM Kill。
バッチ処理が 200MB 以上のメモリを使用しようとした。

### 証拠
1. dmesg 出力：
   `Memory cgroup out of memory: Killed process XXXX (stress)`

2. memory.events：
   `oom_kill 1`

3. memory.max 設定：
   `100M`

### 対策
1. 短期：メモリ制限を 256M に引き上げ
2. 長期：バッチ処理のメモリ使用量を最適化
3. 監視：memory.events の oom_kill を Zabbix で監視
```

**步骤 4：清理**

```bash
sudo rmdir /sys/fs/cgroup/batch-job 2>/dev/null
```

---

## 场景 2：Distroless Black Box（Distroless 黑箱调试）

### 问题描述

```
状況：
Go 应用部署在 distroless 镜像中（gcr.io/distroless/static）。
应用无法连接 RDS 数据库，但容器内没有 shell、curl、ping！
无法使用 docker exec 调试。

日本语：
本番環境では debug ツールを含まない軽量イメージが推奨される。
nsenter はこのような環境でのトラブルシューティング必須スキル。
```

### 动手排查

**运行演示脚本**：

```bash
cd ~/cloud-atlas/foundations/linux/containers/11-debugging-troubleshooting/code
sudo ./distroless-debug-scenario.sh
```

**或手动执行**：

**步骤 1：启动「无法调试」的容器**

```bash
# 使用 alpine 模拟 distroless（删除 shell 来模拟）
docker run -d --name distroless-app alpine sleep infinity

# 尝试 exec 进入（会失败，因为我们将模拟无 shell）
# docker exec -it distroless-app /bin/sh  # 假设失败
```

**步骤 2：获取容器 PID**

```bash
# 获取容器在宿主机上的 PID
PID=$(docker inspect --format '{{.State.Pid}}' distroless-app)
echo "Container PID: $PID"
```

**步骤 3：使用 nsenter 进入 Network Namespace**

```bash
# 只进入网络命名空间（不需要容器内有 shell）
sudo nsenter -t $PID -n ip addr
```

输出：

```
1: lo: <LOOPBACK,UP,LOWER_UP> ...
    inet 127.0.0.1/8 scope host lo
       valid_lft forever preferred_lft forever
42: eth0@if43: <BROADCAST,MULTICAST,UP,LOWER_UP> ...
    inet 172.17.0.2/16 brd 172.17.255.255 scope global eth0
       valid_lft forever preferred_lft forever
```

**步骤 4：在容器网络空间执行调试命令**

```bash
# 测试网络连通性（使用宿主机的 ping）
sudo nsenter -t $PID -n ping -c 3 8.8.8.8

# 检查路由
sudo nsenter -t $PID -n ip route

# 检查 DNS 解析（如果宿主机有 nslookup）
sudo nsenter -t $PID -n nslookup google.com

# 抓包分析（强大！）
sudo nsenter -t $PID -n tcpdump -i eth0 -c 10
```

**步骤 5：模拟 RDS 连接问题排查**

```bash
# 测试特定端口连通性（模拟 RDS 3306）
sudo nsenter -t $PID -n nc -zv 8.8.8.8 443

# 如果是 DNS 问题，检查 /etc/resolv.conf
sudo nsenter -t $PID -m cat /etc/resolv.conf
```

**关键技巧**：

```
┌─────────────────────────────────────────────────────────────────────┐
│                   nsenter 选择性进入 Namespace                       │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  nsenter -t <PID> -n               # 只进入 Network NS              │
│  nsenter -t <PID> -m               # 只进入 Mount NS                │
│  nsenter -t <PID> -p               # 只进入 PID NS                  │
│  nsenter -t <PID> -n -m            # 进入 Network + Mount           │
│  nsenter -t <PID> -a               # 进入所有 NS                    │
│                                                                     │
│  技巧：                                                              │
│  - 网络问题：只进 -n，用宿主机工具（ping, tcpdump, nc）              │
│  - 文件问题：只进 -m，查看容器文件系统                               │
│  - 进程问题：进 -m -p，查看 /proc/1/...                             │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

**步骤 6：清理**

```bash
docker rm -f distroless-app
```

---

## 场景 3：Disk Space Mystery（磁盘空间之谜）

### 问题描述

```
状況：
Zabbix 告警：宿主机磁盘 100% 满。
但容器内 du -sh / 只显示 500MB。
「隐藏」的磁盘空间去哪了？

日本语：
運用監視でディスク容量アラートはよくある。
コンテナ環境では「見えない」消費が問題になりやすい。
```

### 可能原因

1. **已删除但仍被打开的文件**：进程持有文件句柄，文件虽删除但空间未释放
2. **OverlayFS upper 层膨胀**：容器内写入大量数据到 overlay 而非 volume
3. **Docker 日志膨胀**：JSON 日志文件无限增长
4. **未清理的悬空镜像**：dangling images 占用空间

### 动手排查

**运行演示脚本**：

```bash
cd ~/cloud-atlas/foundations/linux/containers/11-debugging-troubleshooting/code
sudo ./disk-mystery-scenario.sh
```

**或手动执行**：

**步骤 1：检查宿主机磁盘使用**

```bash
# 宿主机视角
df -h /var/lib/docker
```

**步骤 2：检查已删除但打开的文件**

```bash
# 查找被删除但仍被打开的文件（空间未释放）
sudo lsof +L1 | head -20

# 按大小排序
sudo lsof +L1 2>/dev/null | awk 'NR>1 {print $7, $1, $9}' | sort -rn | head -10
```

输出示例：

```
SIZE      COMMAND    NAME
104857600 java       /var/log/app.log (deleted)
52428800  nginx      /var/log/access.log (deleted)
```

**问题**：文件已删除（deleted），但进程仍持有句柄，空间未释放！

**解决方案**：

```bash
# 方法 1：重启持有句柄的进程
docker restart <container>

# 方法 2：清空文件内容（不删除句柄）
# 找到进程 PID 和 FD
PID=<from lsof output>
FD=<from lsof output>
# 清空
: > /proc/$PID/fd/$FD
```

**步骤 3：检查 OverlayFS upper 层**

```bash
# 查看容器的 overlay 存储
docker inspect <container> | jq '.[0].GraphDriver.Data'
```

输出：

```json
{
  "LowerDir": "/var/lib/docker/overlay2/.../diff:...",
  "MergedDir": "/var/lib/docker/overlay2/.../merged",
  "UpperDir": "/var/lib/docker/overlay2/.../diff",
  "WorkDir": "/var/lib/docker/overlay2/.../work"
}
```

```bash
# 检查 UpperDir 大小（容器运行时写入的数据）
sudo du -sh /var/lib/docker/overlay2/<id>/diff
```

**问题**：如果 UpperDir 很大，说明容器内写入了大量数据到 overlay 而非 volume。

**步骤 4：检查 Docker 空间使用**

```bash
# Docker 磁盘使用概览
docker system df

# 详细信息
docker system df -v
```

输出：

```
TYPE            TOTAL     ACTIVE    SIZE      RECLAIMABLE
Images          10        5         5.2GB     2.1GB (40%)
Containers      8         3         500MB     200MB (40%)
Local Volumes   5         3         10GB      5GB (50%)
Build Cache     0         0         0B        0B
```

**步骤 5：清理悬空资源**

```bash
# 清理未使用的资源
docker system prune

# 更激进的清理（包括未使用的 volume）
docker system prune -a --volumes
```

**步骤 6：使用 nsenter 进入 Mount Namespace 检查**

```bash
PID=$(docker inspect --format '{{.State.Pid}}' <container>)

# 进入 mount namespace 查看容器视角的磁盘使用
sudo nsenter -t $PID -m df -h

# 查找容器内大文件
sudo nsenter -t $PID -m find / -type f -size +100M 2>/dev/null
```

---

## 场景 4：Stuck Container Process（卡死的容器进程）

### 问题描述

```
状況：
Java 容器僵死，docker exec -it <container> /bin/bash 挂起无响应。
docker logs 没有新输出。
需要不依赖 docker exec 的调试方法。
```

### 动手排查

**步骤 1：确认容器状态**

```bash
docker ps | grep <container>
docker inspect --format '{{.State.Status}}' <container>
```

**步骤 2：获取容器 PID**

```bash
PID=$(docker inspect --format '{{.State.Pid}}' <container>)
echo "Container PID: $PID"

# 检查进程是否存在
ps -p $PID -o pid,stat,wchan,comm
```

输出示例：

```
  PID STAT WCHAN         COMMAND
12345 Ds   io_schedule   java
```

**STAT = Ds** 表示进程在不可中断睡眠状态（等待 I/O）。

**步骤 3：使用 nsenter 绕过 Docker daemon**

```bash
# 进入 mount + pid namespace
sudo nsenter -t $PID -m -p /bin/bash

# 或者使用宿主机的 shell 直接检查
sudo nsenter -t $PID -m cat /proc/1/status
```

**步骤 4：检查进程打开的文件描述符**

```bash
# 查看进程打开的所有文件
sudo ls -la /proc/$PID/fd

# 查看在等待什么
sudo cat /proc/$PID/wchan
```

**步骤 5：检查进程堆栈**

```bash
# 内核态堆栈
sudo cat /proc/$PID/stack
```

输出示例：

```
[<ffffffff...>] io_schedule+0x...
[<ffffffff...>] wait_on_page_bit+0x...
[<ffffffff...>] __filemap_fdatawait_range+0x...
```

等待 I/O 完成 —— 可能是磁盘或网络问题。

**步骤 6：直接读取容器内日志**

```bash
# 获取容器根目录
MERGED=$(docker inspect --format '{{.GraphDriver.Data.MergedDir}}' <container>)

# 直接读取日志（绕过 docker exec）
sudo tail -100 $MERGED/var/log/app.log
```

**步骤 7：生成 Thread dump（Java 容器）**

```bash
# 发送 SIGQUIT 生成 thread dump
sudo kill -3 $PID

# 查看 thread dump（通常输出到 stdout）
docker logs <container> --tail 1000
```

---

## 故障排查清单

```markdown
# 容器故障排查清单

## 启动失败

- [ ] `docker logs <container>` - 查看容器日志
- [ ] `docker inspect <container>` - 检查容器状态和配置
- [ ] `dmesg | grep -i seccomp` - 检查 seccomp 是否阻止系统调用
- [ ] `docker inspect <container> | jq '.[0].HostConfig.CapDrop'` - 检查 capability 配置
- [ ] 检查镜像是否正确：`docker image inspect <image>`

## 运行时消失（Silent Death）

- [ ] `dmesg | grep -i oom` - 检查 OOM Kill（**最重要！**）
- [ ] `cat /sys/fs/cgroup/<path>/memory.events` - 检查 cgroup OOM 统计
- [ ] `cat /sys/fs/cgroup/<path>/pids.current` vs `pids.max` - 检查进程数限制
- [ ] `docker logs <container>` - 检查最后日志
- [ ] `journalctl -k | grep -i oom` - 内核日志备用方法

## 网络问题

- [ ] 获取 PID：`docker inspect --format '{{.State.Pid}}' <container>`
- [ ] 检查 IP 配置：`nsenter -t <PID> -n ip addr`
- [ ] 检查路由：`nsenter -t <PID> -n ip route`
- [ ] 测试连通性：`nsenter -t <PID> -n ping <target>`
- [ ] 检查 DNS：`nsenter -t <PID> -n cat /etc/resolv.conf`
- [ ] 抓包：`nsenter -t <PID> -n tcpdump -i eth0 -c 20`
- [ ] 检查 veth pair：`ip link | grep veth`
- [ ] 检查 bridge：`ip link show type bridge`
- [ ] 检查 NAT 规则：`nft list ruleset | grep -A5 postrouting`

## 存储问题

- [ ] 宿主机磁盘：`df -h /var/lib/docker`
- [ ] Docker 空间使用：`docker system df -v`
- [ ] 已删除但打开的文件：`lsof +L1`
- [ ] OverlayFS upper 层：`du -sh $(docker inspect --format '{{.GraphDriver.Data.UpperDir}}' <container>)`
- [ ] 进入 mount namespace 检查：`nsenter -t <PID> -m du -sh /`
- [ ] 清理悬空资源：`docker system prune`

## 进程卡死

- [ ] 进程状态：`ps -p <PID> -o pid,stat,wchan,comm`
- [ ] 打开的文件：`ls -la /proc/<PID>/fd`
- [ ] 等待什么：`cat /proc/<PID>/wchan`
- [ ] 内核态堆栈：`cat /proc/<PID>/stack`
- [ ] 使用 nsenter 绕过 docker exec：`nsenter -t <PID> -m -p /bin/bash`
- [ ] 直接读取日志：`cat <MergedDir>/var/log/app.log`

## 安全问题（seccomp/capabilities）

- [ ] seccomp 拒绝：`dmesg | grep -i seccomp`
- [ ] audit 日志：`cat /var/log/audit/audit.log | grep denied`
- [ ] 解码 syscall：`ausyscall <number>`
- [ ] 检查 capabilities：`docker inspect <container> | jq '.[0].HostConfig.CapAdd'`
```

---

## 动手练习

### Lab 1：OOM Kill 调查

**目标**：完整调查一次 OOM Kill 事件。

```bash
cd ~/cloud-atlas/foundations/linux/containers/11-debugging-troubleshooting/code
sudo ./lab-oom-investigation.sh
```

**手动步骤**：

1. 创建 cgroup 限制内存为 64MB
2. 运行 stress 分配 128MB
3. 收集 dmesg、memory.events 证据
4. 编写障害報告書

### Lab 2：Distroless 网络调试

**目标**：使用 nsenter 调试无 shell 容器的网络问题。

```bash
cd ~/cloud-atlas/foundations/linux/containers/11-debugging-troubleshooting/code
sudo ./lab-distroless-debug.sh
```

**手动步骤**：

1. 启动一个容器
2. 获取 PID
3. 使用 `nsenter -t <PID> -n` 进入网络空间
4. 执行 `ip addr`、`ping`、`tcpdump`

### Lab 3：磁盘空间排查

**目标**：找到「隐藏」的磁盘空间消耗。

```bash
cd ~/cloud-atlas/foundations/linux/containers/11-debugging-troubleshooting/code
sudo ./lab-disk-mystery.sh
```

**手动步骤**：

1. 运行 `docker system df`
2. 检查 `lsof +L1`
3. 检查 OverlayFS upper 层
4. 使用 nsenter 进入 mount namespace 检查

### Lab 4：卡死进程调试

**目标**：绕过 docker exec 调试卡死容器。

```bash
cd ~/cloud-atlas/foundations/linux/containers/11-debugging-troubleshooting/code
sudo ./lab-stuck-process.sh
```

**手动步骤**：

1. 获取容器 PID
2. 检查 `/proc/<PID>/status`
3. 检查 `/proc/<PID>/stack`
4. 使用 nsenter 进入检查

---

## 职场小贴士

### 日本 IT 现场常见场景

**场景 1：夜間バッチ障害対応**

```
状況：
朝出社すると、夜間バッチが失敗していた。
アプリログには何も記録されていない。

確認手順：
1. dmesg | grep -i oom
2. cat /sys/fs/cgroup/<container>/memory.events
3. journalctl -k | grep -i oom

報告書に添付すべきもの：
- dmesg の出力（タイムスタンプ付き）
- memory.events の内容
- memory.max の設定値
- 推奨対策（メモリ増加 or アプリ最適化）
```

**场景 2：本番環境の distroless コンテナデバッグ**

```
状況：
本番環境の Go アプリケーションが RDS に接続できない。
コンテナは distroless で shell がない。

対応：
1. docker inspect でコンテナ PID 取得
2. nsenter -t <PID> -n で Network NS に入る
3. 宿主機の ping, nc, tcpdump を使用
4. DNS 設定確認：nsenter -t <PID> -m cat /etc/resolv.conf

報告：
「nsenter を使用してコンテナ Network Namespace でデバッグしました。
 DNS 設定に問題があることを確認しました。」
```

**场景 3：監視アラート：ディスク 100%**

```
状況：
Zabbix から disk full アラート。
コンテナ内で du -sh / しても小さい。

確認手順：
1. df -h /var/lib/docker
2. docker system df -v
3. lsof +L1（削除済みだがオープンされているファイル）
4. overlay2 の upper dir サイズ確認

よくある原因：
- ログファイルの無限成長
- 削除されたがオープンされているファイル
- overlay 層への書き込み（volume を使うべき）
```

### 障害対応スキルの重要性

```
日本 IT 運用現場での評価ポイント：

1. 障害の切り分け能力
   - 問題がどの層にあるか素早く特定できる
   - 適切な証拠を収集できる

2. 報告書の品質
   - 技術的証拠を添付する
   - 原因と対策を明確に記載
   - 再発防止策を提案

3. ツールの習熟度
   - nsenter, dmesg, lsof などを使いこなせる
   - Docker/Kubernetes の内部構造を理解

障害対応ができるエンジニアは、
日本 IT 業界で高く評価されます。
```

---

## 检查清单

完成本课后，你应该能够：

- [ ] 使用 4 步定位法（確定問題類型 → 収集証拠 → 隔離問題層 → 驗証修復）
- [ ] 從 `dmesg` 和 `memory.events` 找到 OOM Kill 证据
- [ ] 使用 `nsenter -t <PID> -n` 调试无 shell 容器的网络
- [ ] 使用 `lsof +L1` 找到已删除但仍占用空间的文件
- [ ] 检查 OverlayFS upper 层找到容器磁盘消耗
- [ ] 绕过 docker exec 使用 `nsenter` 调试卡死容器
- [ ] 检查 `/proc/<PID>/stack` 了解进程阻塞原因
- [ ] 理解「只看容器日志，不看宿主机 dmesg」这个反模式
- [ ] 编写日本 IT 现场的障害報告書
- [ ] 整合运用前 10 课知识解决复杂问题

---

## 延伸阅读

### 官方文档

- [Docker Troubleshooting](https://docs.docker.com/config/daemon/)
- [Linux cgroups v2 - Memory Controller](https://docs.kernel.org/admin-guide/cgroup-v2.html#memory)
- [nsenter(1) - Linux manual page](https://man7.org/linux/man-pages/man1/nsenter.1.html)

### 相关课程

- [Lesson 03 - Namespace 深入](../03-namespace-deep-dive/) - nsenter 基础
- [Lesson 06 - cgroups v2 资源控制](../06-cgroups-v2-resource-control/) - OOM 调查基础
- [Lesson 07 - OverlayFS](../07-overlay-filesystems/) - 存储层原理
- [Lesson 08 - 容器网络](../08-container-networking/) - 网络调试基础
- [Lesson 12 - Capstone](../12-capstone/) - 综合运用所有知识

### 推荐阅读

- *Container Security* by Liz Rice - 容器安全与调试
- *Systems Performance* by Brendan Gregg - 系统性能分析
- [BPF Performance Tools](https://github.com/iovisor/bcc) - 高级调试工具

---

## 系列导航

[<-- 10 - OCI 运行时](../10-oci-runtimes/) | [Home](../) | [12 - Capstone -->](../12-capstone/)
