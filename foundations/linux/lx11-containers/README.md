# LX11 - 容器内部原理（Container Internals）

> **深入 Linux 容器底层原理，理解 Docker/Kubernetes 背后的内核技术**

本课程是 Linux World 模块化课程体系的一部分，专注于容器底层原理。

## 课程概览

| 属性 | 值 |
|------|-----|
| **课时** | 12 课 |
| **时长** | 25-30 小时 |
| **难度** | 高级 |
| **前置** | LX05 systemd + LX06 网络 + LX08 安全 |
| **认证** | CKA 容器运行时 |

## 课程特色

- **"容器 = 进程 + 约束"**：建立正确心智模型
- **"公寓楼比喻"**：7 种 Namespace 类比记忆
- **Shell 工具优先**：unshare/nsenter/ip 手把手实操
- **从零构建容器**：Capstone 彻底理解原理

## 课程大纲

### Part 1: 概念 (01-02)

| 课程 | 标题 | 描述 |
|------|------|------|
| 01 | [容器 vs 虚拟机](./01-containers-vs-vms/) | 进程视角 |
| 02 | [Namespace 概览](./02-namespace-overview/) | 7 种隔离类型 |

### Part 2: Namespace 深入 (03-04)

| 课程 | 标题 | 描述 |
|------|------|------|
| 03 | [Namespace 深入](./03-namespace-deep-dive/) | unshare、nsenter |
| 04 | [User Namespace](./04-user-namespace-rootless/) | Rootless 容器 |

### Part 3: cgroups (05-06)

| 课程 | 标题 | 描述 |
|------|------|------|
| 05 | [cgroups v2 架构](./05-cgroups-v2-architecture/) | 统一层级 |
| 06 | [cgroups v2 资源控制](./06-cgroups-v2-resource-control/) | CPU、内存限制 |

### Part 4: 镜像与网络 (07-08)

| 课程 | 标题 | 描述 |
|------|------|------|
| 07 | [OverlayFS](./07-overlay-filesystems/) | 镜像层、写时复制 |
| 08 | [容器网络](./08-container-networking/) | veth、bridge、NAT |

### Part 5: 安全与运行时 (09-10)

| 课程 | 标题 | 描述 |
|------|------|------|
| 09 | [容器安全](./09-container-security/) | seccomp、capabilities |
| 10 | [OCI 运行时](./10-oci-runtimes/) | runc、containerd |

### Part 6: 排障与综合 (11-12)

| 课程 | 标题 | 描述 |
|------|------|------|
| 11 | [调试与排障](./11-debugging-troubleshooting/) | nsenter 调试 |
| 12 | [综合实战：从零构建容器](./12-capstone/) | 手写容器运行时 |

## 快速开始

```bash
# GitHub（海外用户）
git clone --filter=blob:none --sparse https://github.com/shiicho/cloud-atlas ~/cloud-atlas
cd ~/cloud-atlas && git sparse-checkout set foundations/linux/lx11-containers

# Gitee（中国大陆用户）
git clone --filter=blob:none --sparse https://gitee.com/shiicho/cloud-atlas ~/cloud-atlas
cd ~/cloud-atlas && git sparse-checkout set foundations/linux/lx11-containers
```

## 前置课程

- [LX05 - systemd 深入](../lx05-systemd/)
- [LX06 - 网络](../lx06-networking/)
- [LX08 - 安全加固](../lx08-security/)

## 后续路径

完成本课程后，你可以：

- **Docker/Kubernetes 课程**：有底层基础，学习更扎实
- **CKA 认证**：容器运行时选型、故障排查
