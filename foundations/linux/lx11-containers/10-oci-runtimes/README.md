# 10 - OCI 运行时：runc、containerd 与 CRI-O

> **目标**：理解容器运行时层级架构，区分低级运行时（runc）和高级运行时（containerd/CRI-O），掌握 OCI 规范核心概念  
> **前置**：[Lesson 09 - 容器安全](../09-container-security/)；理解 Namespace、cgroups、OverlayFS 基础  
> **时间**：2.5 小时  
> **场景**：コンテナランタイム選定（容器运行时选型），Kubernetes 运维  

---

## 将学到的内容

1. 理解 OCI 规范（Runtime Spec、Image Spec、Distribution Spec）
2. 区分低级运行时（runc、crun）和高级运行时（containerd、CRI-O）
3. 使用 runc 直接运行 OCI 容器
4. 使用 containerd 的 ctr 命令管理容器
5. 理解 Kubernetes CRI 接口及运行时选型

---

## 先跑起来：5 分钟用 runc 直接运行容器

> **不讲原理，先动手！** 你马上就能绕过 Docker，直接使用 OCI 低级运行时运行容器。  

### 准备 OCI Bundle

```bash
# 1. 创建 OCI bundle 目录结构
mkdir -p ~/oci-demo/rootfs

# 2. 使用 Docker 导出 rootfs（最简单的方式）
docker export $(docker create alpine:latest) | tar -C ~/oci-demo/rootfs -xf -

# 3. 进入 bundle 目录
cd ~/oci-demo

# 4. 生成默认 config.json（OCI 运行时规范）
runc spec
```

### 查看生成的 config.json

```bash
# 查看关键配置
cat config.json | head -50
```

输出（部分）：

```json
{
    "ociVersion": "1.0.2-dev",
    "process": {
        "terminal": true,
        "user": { "uid": 0, "gid": 0 },
        "args": ["sh"],
        "env": [
            "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin",
            "TERM=xterm"
        ],
        "cwd": "/"
    },
    "root": {
        "path": "rootfs",
        "readonly": true
    },
    "hostname": "runc",
    "mounts": [
        { "destination": "/proc", "type": "proc", "source": "proc" },
        { "destination": "/dev", "type": "tmpfs", "source": "tmpfs" }
    ],
    "linux": {
        "namespaces": [
            { "type": "pid" },
            { "type": "network" },
            { "type": "ipc" },
            { "type": "uts" },
            { "type": "mount" }
        ]
    }
}
```

### 运行容器

```bash
# 运行 OCI 容器（需要 root 权限）
sudo runc run mycontainer
```

输出：

```
/ # hostname
runc
/ # ps aux
PID   USER     TIME  COMMAND
    1 root      0:00 sh
    2 root      0:00 ps aux
/ # exit
```

**成功！** 你刚刚绕过了 Docker，直接使用 OCI 低级运行时运行了容器。

### 快速清理

```bash
# 删除容器（如果没有自动删除）
sudo runc delete mycontainer 2>/dev/null

# 清理 bundle 目录
rm -rf ~/oci-demo
```

---

**你刚刚做了什么？**

```
OCI 容器运行流程：

┌─────────────────────────────────────────────────────────────────────┐
│  Docker/Kubernetes/Podman  (用户界面层)                              │
│  "docker run alpine"                                                │
└────────────────────────────────────┬────────────────────────────────┘
                                     │
                                     ▼
┌─────────────────────────────────────────────────────────────────────┐
│  containerd / CRI-O  (高级运行时)                                    │
│  - 镜像拉取/存储                                                     │
│  - 容器生命周期管理                                                   │
│  - 快照管理 (snapshotter)                                            │
└────────────────────────────────────┬────────────────────────────────┘
                                     │ OCI Runtime Spec
                                     │ (config.json)
                                     ▼
┌─────────────────────────────────────────────────────────────────────┐
│  runc / crun / youki  (低级运行时)  ← 你刚刚直接使用了这层！          │
│  - 读取 config.json                                                 │
│  - 创建 Namespace                                                    │
│  - 配置 cgroups                                                      │
│  - 执行容器进程                                                       │
└────────────────────────────────────┬────────────────────────────────┘
                                     │
                                     ▼
┌─────────────────────────────────────────────────────────────────────┐
│  Linux Kernel                                                        │
│  namespaces / cgroups / overlayfs / seccomp                          │
└─────────────────────────────────────────────────────────────────────┘
```

你跳过了 Docker 和 containerd，直接操作了最底层的 runc！

---

## 发生了什么？

### OCI 规范的三大组成

**OCI（Open Container Initiative）** 是容器标准化组织，定义了三个核心规范：

| 规范 | 作用 | 关键文件/格式 |
|------|------|---------------|
| **Runtime Spec** | 定义如何运行容器 | `config.json` |
| **Image Spec** | 定义镜像格式 | manifest, layers, config |
| **Distribution Spec** | 定义镜像分发 | Registry API |

**为什么需要 OCI 规范？**

```
没有 OCI 之前（Docker 专有）：

   Docker Client  ──────▶  Docker Daemon  ──────▶  Docker 专有格式
        │                       │
        └───────────────────────┘
              紧密耦合

有了 OCI 之后（标准化）：

   Docker          ─┐
   Podman          ─┼──▶  OCI 标准接口  ──▶  runc/crun
   Kubernetes      ─┤                           │
   任何工具...     ─┘                           ▼
                                          Linux Kernel
              松耦合，可互换
```

### 运行时层级架构

**容器运行时分为两个层级**：

```
┌─────────────────────────────────────────────────────────────────────┐
│                    高级运行时 (High-level Runtime)                   │
│                                                                     │
│  ┌───────────────────────────┐  ┌───────────────────────────────┐   │
│  │      containerd           │  │         CRI-O                 │   │
│  │  - Docker 默认使用         │  │  - Kubernetes 专用            │   │
│  │  - 镜像管理               │  │  - 最小化设计                  │   │
│  │  - 容器生命周期           │  │  - OpenShift 默认             │   │
│  │  - ctr 命令行工具         │  │                               │   │
│  └───────────────────────────┘  └───────────────────────────────┘   │
│                                                                     │
│  职责：镜像拉取、存储、快照、容器生命周期管理                          │
└────────────────────────────────────┬────────────────────────────────┘
                                     │
                                     │ OCI Runtime Spec
                                     │
┌────────────────────────────────────┴────────────────────────────────┐
│                    低级运行时 (Low-level Runtime)                    │
│                                                                     │
│  ┌───────────────┐  ┌───────────────┐  ┌─────────────────────────┐  │
│  │     runc      │  │     crun      │  │        youki            │  │
│  │  Go 语言      │  │  C 语言       │  │     Rust 语言           │  │
│  │  OCI 参考实现 │  │  更快更小     │  │    安全性高             │  │
│  │  最成熟       │  │  高密度场景   │  │    实验性               │  │
│  └───────────────┘  └───────────────┘  └─────────────────────────┘  │
│                                                                     │
│  职责：创建 namespace、配置 cgroups、执行容器进程                     │
└─────────────────────────────────────────────────────────────────────┘
```

---

## 核心概念：OCI Runtime Spec

### config.json 关键字段

OCI Runtime Spec 定义了 `config.json` 的结构，这是低级运行时的「执行合同」：

```json
{
    "ociVersion": "1.0.2-dev",

    "process": {
        "terminal": true,
        "user": { "uid": 0, "gid": 0 },
        "args": ["nginx", "-g", "daemon off;"],
        "env": ["PATH=/usr/bin"],
        "cwd": "/"
    },

    "root": {
        "path": "rootfs",
        "readonly": false
    },

    "hostname": "web-server",

    "mounts": [
        {
            "destination": "/proc",
            "type": "proc",
            "source": "proc"
        }
    ],

    "linux": {
        "namespaces": [
            { "type": "pid" },
            { "type": "network" },
            { "type": "mount" },
            { "type": "ipc" },
            { "type": "uts" }
        ],
        "resources": {
            "memory": { "limit": 536870912 },
            "cpu": { "quota": 50000, "period": 100000 }
        }
    }
}
```

**字段说明**：

| 字段 | 作用 | 对应内核机制 |
|------|------|-------------|
| `process` | 容器内执行的进程 | exec() |
| `root` | 容器根文件系统 | pivot_root() |
| `hostname` | 容器主机名 | UTS namespace |
| `namespaces` | 启用的隔离类型 | clone() flags |
| `resources` | 资源限制 | cgroups |

### OCI Runtime Spec v1.3 更新（2025-2026）

```
OCI Runtime Spec 最近更新:

┌─────────────────────────────────────────────────────────────────────┐
│  v1.2.0 (2024)                                                      │
│  - idmap mounts 支持                                                 │
│  - 改进的 seccomp 配置                                               │
└─────────────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────────────┐
│  v1.3.0 (Nov 2025)                                                  │
│  - 增强的 cgroup v2 支持                                             │
│  - 更好的 rootless 容器支持                                          │
│  - 新的 lifecycle hooks                                              │
└─────────────────────────────────────────────────────────────────────┘
```

---

## 核心概念：runc vs crun

### 对比

| 特性 | runc | crun |
|------|------|------|
| **语言** | Go | C |
| **二进制大小** | ~10MB | ~300KB |
| **启动速度** | 基准 | 快 50% 以上 |
| **内存占用** | 较高（Go runtime） | 极低 |
| **成熟度** | 生产级，OCI 参考实现 | 生产级，Red Hat 支持 |
| **适用场景** | 通用 | 高密度、FaaS、边缘计算 |

### 为什么 crun 更快？

```
runc (Go):
┌──────────────────────────────────────────┐
│  runc 二进制                              │
│  ┌────────────────────────────────────┐  │
│  │  Go Runtime (GC, goroutines, etc.) │  │  ← 启动开销
│  │  ~8MB 额外开销                      │  │
│  └────────────────────────────────────┘  │
│  ┌────────────────────────────────────┐  │
│  │  OCI 实现逻辑                       │  │
│  └────────────────────────────────────┘  │
└──────────────────────────────────────────┘

crun (C):
┌──────────────────────────────────────────┐
│  crun 二进制                              │
│  ┌────────────────────────────────────┐  │
│  │  OCI 实现逻辑                       │  │  ← 直接执行
│  └────────────────────────────────────┘  │
└──────────────────────────────────────────┘

高密度场景（1000+ 容器）：
- runc: 每次启动都加载 Go runtime
- crun: 直接执行，启动时间和内存占用显著降低
```

### crun 在生产环境的采用（2025-2026）

- **Podman**: 支持 crun 作为默认运行时
- **OpenShift**: 高密度工作负载推荐 crun
- **Serverless/FaaS**: 冷启动优化首选

---

## 核心概念：containerd

### containerd 架构

```
┌─────────────────────────────────────────────────────────────────────┐
│                         containerd                                   │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  ┌─────────────────┐  ┌─────────────────┐  ┌────────────────────┐  │
│  │  Content Store  │  │   Snapshotter   │  │  Container Service │  │
│  │  (镜像层存储)   │  │  (快照管理)     │  │  (容器生命周期)     │  │
│  └─────────────────┘  └─────────────────┘  └────────────────────┘  │
│                                                                     │
│  ┌─────────────────────────────────────────────────────────────┐    │
│  │                    gRPC API                                  │    │
│  │  - 镜像拉取/推送    - 容器创建/启动/停止    - 快照操作       │    │
│  └─────────────────────────────────────────────────────────────┘    │
│                                                                     │
│  ┌─────────────────────────────────────────────────────────────┐    │
│  │                    Shim API                                  │    │
│  │                containerd-shim-runc-v2                       │    │
│  └──────────────────────────┬──────────────────────────────────┘    │
│                              │                                      │
└──────────────────────────────┼──────────────────────────────────────┘
                               │
                               ▼
                    ┌──────────────────┐
                    │   runc / crun    │
                    └──────────────────┘
```

### ctr 命令基础操作

`ctr` 是 containerd 的原生命令行工具：

```bash
# 拉取镜像
sudo ctr images pull docker.io/library/alpine:latest

# 列出镜像
sudo ctr images list

# 运行容器（交互式）
sudo ctr run -t --rm docker.io/library/alpine:latest test1 sh

# 创建容器（不启动）
sudo ctr containers create docker.io/library/alpine:latest mycontainer

# 启动容器
sudo ctr tasks start -d mycontainer

# 列出运行中的任务
sudo ctr tasks list

# 进入容器
sudo ctr tasks exec -t --exec-id shell1 mycontainer sh

# 停止并删除
sudo ctr tasks kill mycontainer
sudo ctr containers delete mycontainer
```

### containerd 2.0+ 更新（2025-2026）

```
containerd 2.0 关键变化：

┌─────────────────────────────────────────────────────────────────────┐
│  移除 Kubernetes CRI v1alpha2 支持                                   │
│  - 只保留 CRI v1 API                                                 │
│  - 旧版 Kubernetes (< 1.24) 需要升级                                 │
└─────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────┐
│  改进的 Sandbox API                                                  │
│  - 更好的 Pod 生命周期管理                                           │
│  - 支持新的沙箱隔离技术                                              │
└─────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────┐
│  Transfer Service                                                    │
│  - 统一的镜像传输 API                                                │
│  - 更好的镜像流式传输支持                                            │
└─────────────────────────────────────────────────────────────────────┘
```

---

## 核心概念：CRI-O

### CRI-O 定位

**CRI-O** 是专为 Kubernetes 设计的容器运行时：

```
CRI-O 设计哲学：

┌─────────────────────────────────────────────────────────────────────┐
│                        "Just enough for Kubernetes"                  │
│                                                                     │
│  只实现 Kubernetes 需要的功能，不多不少                               │
│                                                                     │
│  对比 containerd:                                                    │
│  - containerd: 通用容器运行时，功能丰富                              │
│  - CRI-O: Kubernetes 专用，功能精简                                  │
│                                                                     │
│  优势：                                                              │
│  - 更小的攻击面                                                      │
│  - 更简单的升级（与 Kubernetes 版本对齐）                             │
│  - 更少的依赖                                                        │
└─────────────────────────────────────────────────────────────────────┘
```

### CRI-O vs containerd

| 特性 | containerd | CRI-O |
|------|------------|-------|
| **定位** | 通用容器运行时 | Kubernetes 专用 |
| **功能** | 完整（支持独立使用） | 最小化（只支持 K8s） |
| **默认使用者** | Docker, 通用 K8s | OpenShift, RHEL |
| **镜像构建** | 支持 | 不支持（需 buildah） |
| **版本策略** | 独立版本 | 与 K8s 版本对齐 |

---

## 核心概念：Kubernetes CRI

### CRI 架构

**CRI（Container Runtime Interface）** 是 Kubernetes 与容器运行时的标准接口：

```
Kubernetes CRI 架构：

┌─────────────────────────────────────────────────────────────────────┐
│                         Kubernetes Node                              │
│                                                                     │
│  ┌─────────────────────────────────────────────────────────────┐    │
│  │                        kubelet                               │    │
│  │                                                              │    │
│  │  Pod 管理：                                                  │    │
│  │  - 接收 Pod Spec                                             │    │
│  │  - 调用 CRI 创建 Sandbox                                     │    │
│  │  - 调用 CRI 创建 Container                                   │    │
│  └──────────────────────────┬───────────────────────────────────┘    │
│                              │                                      │
│                              │ CRI (gRPC)                           │
│                              │                                      │
│  ┌───────────────────────────┴───────────────────────────────────┐  │
│  │                containerd / CRI-O                             │  │
│  │                                                               │  │
│  │  RuntimeService:              ImageService:                   │  │
│  │  - RunPodSandbox             - PullImage                      │  │
│  │  - CreateContainer           - ListImages                     │  │
│  │  - StartContainer            - RemoveImage                    │  │
│  │  - StopContainer                                              │  │
│  │  - RemoveContainer                                            │  │
│  └───────────────────────────┬───────────────────────────────────┘  │
│                              │                                      │
│                              │ OCI Runtime Spec                     │
│                              │                                      │
│                    ┌─────────┴─────────┐                            │
│                    │   runc / crun     │                            │
│                    └───────────────────┘                            │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

### RuntimeClass

**RuntimeClass** 允许在同一集群中使用不同的运行时：

```yaml
# RuntimeClass 定义
apiVersion: node.k8s.io/v1
kind: RuntimeClass
metadata:
  name: high-performance
handler: crun  # 使用 crun 作为运行时
---
# Pod 使用特定 RuntimeClass
apiVersion: v1
kind: Pod
metadata:
  name: fast-pod
spec:
  runtimeClassName: high-performance  # 指定运行时
  containers:
  - name: app
    image: myapp:latest
```

**典型使用场景**：

| RuntimeClass | 运行时 | 用途 |
|--------------|--------|------|
| `default` | runc | 通用工作负载 |
| `high-performance` | crun | 高密度、低延迟 |
| `gvisor` | runsc | 强隔离、多租户 |
| `kata` | kata-runtime | VM 级隔离 |

---

## 动手练习

### Lab 1：使用 runc 直接运行容器

**目标**：深入理解 OCI bundle 结构和 runc 工作原理。

**运行演示脚本**：

```bash
cd ~/cloud-atlas/foundations/linux/containers/10-oci-runtimes/code
./runc-demo.sh
```

**或手动执行**：

**步骤 1：准备 OCI Bundle**

```bash
# 创建目录结构
mkdir -p ~/runc-lab/mycontainer/rootfs

# 导出 Alpine rootfs
docker export $(docker create alpine:latest) | tar -C ~/runc-lab/mycontainer/rootfs -xf -

# 进入 bundle 目录
cd ~/runc-lab/mycontainer

# 生成 config.json
runc spec
```

**步骤 2：修改 config.json**

```bash
# 修改启动命令为运行 top
sed -i 's/"sh"/"top", "-b"/' config.json

# 修改 hostname
sed -i 's/"runc"/"my-oci-container"/' config.json

# 查看修改结果
grep -A5 '"args"' config.json
grep '"hostname"' config.json
```

**步骤 3：运行容器**

```bash
# 前台运行（Ctrl+C 退出）
sudo runc run mycontainer

# 或后台运行
sudo runc run -d mycontainer

# 列出容器
sudo runc list

# 查看容器状态
sudo runc state mycontainer
```

输出示例：

```json
{
  "ociVersion": "1.0.2-dev",
  "id": "mycontainer",
  "pid": 12345,
  "status": "running",
  "bundle": "/home/user/runc-lab/mycontainer",
  "rootfs": "/home/user/runc-lab/mycontainer/rootfs",
  "created": "2025-01-04T10:00:00.000000000Z"
}
```

**步骤 4：进入容器**

```bash
# exec 进入容器
sudo runc exec -t mycontainer sh

# 在容器内验证
/ # hostname
my-oci-container
/ # ps aux
/ # exit
```

**步骤 5：清理**

```bash
sudo runc kill mycontainer SIGKILL
sudo runc delete mycontainer
rm -rf ~/runc-lab
```

---

### Lab 2：runc vs crun 性能对比

**目标**：比较 runc 和 crun 的启动性能。

**准备工作**：

```bash
# 安装 crun（Ubuntu/Debian）
sudo apt-get install -y crun

# 或（RHEL/CentOS）
sudo dnf install -y crun

# 验证安装
runc --version
crun --version
```

**准备 OCI Bundle**：

```bash
mkdir -p ~/runtime-compare/test/rootfs
docker export $(docker create alpine:latest) | tar -C ~/runtime-compare/test/rootfs -xf -
cd ~/runtime-compare/test
runc spec

# 修改为非交互式命令
sed -i 's/"sh"/"echo", "hello"/' config.json
sed -i 's/"terminal": true/"terminal": false/' config.json
```

**性能对比测试**：

```bash
# runc 启动时间（10 次平均）
echo "Testing runc..."
for i in {1..10}; do
  time sudo runc run --rm test-runc-$i 2>&1 | grep real
done

# crun 启动时间（10 次平均）
echo "Testing crun..."
for i in {1..10}; do
  time sudo crun run --rm test-crun-$i 2>&1 | grep real
done
```

**典型结果**：

```
runc 平均启动时间:  ~100-150ms
crun 平均启动时间:  ~40-60ms
性能提升:          ~50-60%
```

**清理**：

```bash
rm -rf ~/runtime-compare
```

---

### Lab 3：containerd ctr 操作

**目标**：使用 ctr 直接操作 containerd。

**验证 containerd 运行**：

```bash
# 检查 containerd 状态
sudo systemctl status containerd

# 如果使用 Docker，containerd 已经在运行
sudo ctr version
```

**镜像操作**：

```bash
# 拉取镜像（注意完整镜像名）
sudo ctr images pull docker.io/library/nginx:alpine

# 列出镜像
sudo ctr images list

# 查看镜像详情
sudo ctr images info docker.io/library/nginx:alpine
```

**容器操作**：

```bash
# 创建并运行容器
sudo ctr run -d docker.io/library/nginx:alpine nginx-test

# 列出运行中的容器
sudo ctr containers list
sudo ctr tasks list

# 查看容器详情
sudo ctr containers info nginx-test

# 进入容器
sudo ctr tasks exec -t --exec-id exec1 nginx-test sh

# 在容器内
/ # curl localhost
/ # exit

# 停止容器
sudo ctr tasks kill nginx-test

# 删除容器
sudo ctr containers delete nginx-test
```

**Namespace 操作**：

```bash
# 列出所有 namespace
sudo ctr namespaces list

# Docker 使用的 namespace
sudo ctr -n moby containers list  # Docker 的 namespace 是 "moby"

# Kubernetes 使用的 namespace
sudo ctr -n k8s.io containers list  # K8s 的 namespace 是 "k8s.io"
```

---

## 职场小贴士

### 日本 IT 现场常见场景

**场景 1：コンテナランタイム選定（容器运行时选型）**

```
状況：
新規 Kubernetes クラスタの構築で、containerd と CRI-O の選定を求められた。

選定基準：

┌─────────────────────────────────────────────────────────────────────┐
│  考慮事項                                                            │
├─────────────────┬───────────────────────────────────────────────────┤
│ 既存資産        │ Docker 使用中 → containerd が移行しやすい         │
│                 │ OpenShift 経験あり → CRI-O                        │
├─────────────────┼───────────────────────────────────────────────────┤
│ 運用チーム      │ 汎用ツール必要 → containerd（ctr, nerdctl 使用可）│
│                 │ K8s 専用で十分 → CRI-O                            │
├─────────────────┼───────────────────────────────────────────────────┤
│ 高密度ワーク    │ FaaS/Serverless → crun + containerd/CRI-O        │
│ ロード          │ 通常ワークロード → runc で十分                    │
├─────────────────┼───────────────────────────────────────────────────┤
│ セキュリティ    │ 最小攻撃面優先 → CRI-O                            │
│ 要件            │ 機能優先 → containerd                             │
└─────────────────┴───────────────────────────────────────────────────┘

報告例：
「Docker からの移行を考慮し、containerd を推奨します。
 高密度ワークロードには crun を RuntimeClass で設定可能です。」
```

**場景 2：RuntimeClass の設定**

```yaml
# 運用チームへの説明資料

# 1. RuntimeClass 定義
apiVersion: node.k8s.io/v1
kind: RuntimeClass
metadata:
  name: crun-fast
handler: crun
---
# 2. 高パフォーマンス Pod での使用
apiVersion: v1
kind: Pod
metadata:
  name: fast-job
spec:
  runtimeClassName: crun-fast  # crun 使用
  containers:
  - name: worker
    image: worker:latest
    resources:
      limits:
        cpu: "2"
        memory: "4Gi"
```

**場景 3：トラブルシューティング - コンテナ起動失敗**

```bash
# 問題: Pod が ContainerCreating のまま

# 1. kubelet ログ確認
journalctl -u kubelet | grep -i runtime | tail -20

# 2. containerd ログ確認
journalctl -u containerd | grep -i error | tail -20

# 3. ctr で直接確認
sudo ctr -n k8s.io containers list
sudo ctr -n k8s.io tasks list

# 4. runc 状態確認
sudo runc list

# よくある原因：
# - RuntimeClass 設定ミス
# - runc/crun バイナリ不足
# - cgroup v1/v2 不整合
```

### Kubernetes CRI 理解の重要性

```
面接でよく聞かれる質問：

Q: Docker から containerd への移行で注意点は？
A:
1. docker CLI が使えなくなる → crictl または nerdctl 使用
2. イメージビルドは別ツール必要 → buildah, kaniko
3. ログ形式が変わる可能性 → 監視設定の確認

Q: containerd と CRI-O の違いは？
A:
- containerd: 汎用的、Docker でも K8s でも使える
- CRI-O: K8s 専用、機能が絞られている分シンプル
- 選定はチームのスキルと要件次第
```

---

## 检查清单

完成本课后，你应该能够：

- [ ] 説明 OCI 规范的三大组成（Runtime Spec、Image Spec、Distribution Spec）
- [ ] 区分高级运行时（containerd、CRI-O）和低级运行时（runc、crun）
- [ ] 创建 OCI Bundle 并使用 runc 直接运行容器
- [ ] 理解 config.json 的关键字段及其对应的内核机制
- [ ] 比较 runc 和 crun 的差异，说明 crun 的适用场景
- [ ] 使用 ctr 命令管理 containerd 中的镜像和容器
- [ ] 解释 Kubernetes CRI 架构和 RuntimeClass 的作用
- [ ] 在 containerd vs CRI-O 选型时提供技术建议
- [ ] 排查容器运行时相关问题（检查 runc/containerd 日志）

---

## 延伸阅读

### 官方文档

- [OCI Runtime Specification](https://github.com/opencontainers/runtime-spec)
- [OCI Image Specification](https://github.com/opencontainers/image-spec)
- [runc GitHub](https://github.com/opencontainers/runc)
- [crun GitHub](https://github.com/containers/crun)
- [containerd Documentation](https://containerd.io/docs/)
- [CRI-O Documentation](https://cri-o.io/)

### 相关课程

- [Lesson 01 - 容器 vs 虚拟机](../01-containers-vs-vms/) - 容器基础概念
- [Lesson 09 - 容器安全](../09-container-security/) - seccomp、Capabilities
- [Lesson 11 - 容器故障排查](../11-debugging-troubleshooting/) - 完整调试方法论
- [Lesson 12 - Capstone](../12-capstone/) - 从零构建容器

### 推荐阅读

- *Container Security* by Liz Rice - 包含运行时安全章节
- [Kubernetes CRI Plugin](https://kubernetes.io/docs/concepts/architecture/cri/) - K8s 官方 CRI 文档
- [nerdctl](https://github.com/containerd/nerdctl) - containerd 的 Docker 兼容 CLI

---

## 系列导航

[<-- 09 - 容器安全](../09-container-security/) | [Home](../) | [11 - 容器故障排查 -->](../11-debugging-troubleshooting/)
