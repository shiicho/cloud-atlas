# 03 - 文件系统选择与创建

> **目标**：理解 ext4 与 XFS 的差异，掌握文件系统创建与磁盘加密基础  
> **前置**：完成 [02 - 分区管理](../02-partitioning/)  
> **时间**：45 分钟  
> **环境**：任意 Linux（Ubuntu/RHEL/AlmaLinux），需要 root 权限  

---

## 将学到的内容

1. 理解 ext4 和 XFS 的特性差异
2. 使用 `mkfs.ext4`、`mkfs.xfs` 创建文件系统
3. 掌握文件系统选择决策标准
4. 了解 LUKS 磁盘加密基本工作流程
5. 了解 io_uring 现代异步 I/O（概念）

---

## Step 1 - ext4 vs XFS：核心差异

在上一课中，你已经在磁盘上创建了分区。但分区只是"画出地盘"，要存放文件还需要**文件系统**（Filesystem）。

Linux 世界最常用的两个文件系统：

| 特性 | ext4 | XFS |
|------|------|-----|
| **起源** | ext 家族演进（1992-2008） | SGI IRIX（1993），2001 进入 Linux |
| **设计理念** | 稳定成熟，功能全面 | 高性能，大规模存储 |
| **默认发行版** | Ubuntu、Debian | RHEL 7+、CentOS、AlmaLinux |
| **最大文件系统** | 1 EiB | 8 EiB |
| **在线扩展** | 支持 | 支持 |
| **在线收缩** | 支持（需卸载） | **不支持** |
| **fsck 速度** | 快（小分区） | 依赖日志回放 |
| **大文件性能** | 良好 | **优秀**（Allocation Groups） |
| **并行 I/O** | 一般 | **优秀** |
| **reflink（CoW）** | 不支持 | 支持 |

### 关键决策点

**选择 ext4 的场景：**
- 系统盘（`/`、`/boot`）
- 需要收缩分区的可能性
- 通用用途服务器
- 小文件密集型工作负载

**选择 XFS 的场景：**
- 大文件存储（数据库、媒体文件）
- 高吞吐量需求
- RHEL/CentOS/AlmaLinux 默认
- 容器存储（需 `ftype=1`）

> **核心记忆点**：XFS 不能收缩！选择 XFS 就要做好"只增不减"的准备。  

---

## Step 2 - 创建文件系统

### 2.1 创建 ext4 文件系统

```bash
# 在分区上创建 ext4
sudo mkfs.ext4 /dev/sdb1

# 带标签创建（推荐）
sudo mkfs.ext4 -L data_ext4 /dev/sdb1
```

输出示例：

```
mke2fs 1.46.5 (30-Dec-2021)
Creating filesystem with 2621440 4k blocks and 655360 inodes
Filesystem UUID: a1b2c3d4-e5f6-7890-abcd-ef1234567890
Superblock backups stored on blocks:
        32768, 98304, 163840, 229376, 294912, 819200, 884736, 1605632

Allocating group tables: done
Writing inode tables: done
Creating journal (16384 blocks): done
Writing superblocks and filesystem accounting information: done
```

### 2.2 创建 XFS 文件系统

```bash
# 在分区上创建 XFS
sudo mkfs.xfs /dev/sdb2

# 带标签创建
sudo mkfs.xfs -L data_xfs /dev/sdb2

# Docker/容器环境（确保 ftype=1）
sudo mkfs.xfs -n ftype=1 /dev/sdb2
```

输出示例：

```
meta-data=/dev/sdb2              isize=512    agcount=4, agsize=655360 blks
         =                       sectsz=512   attr=2, projid32bit=1
         =                       crc=1        finobt=1, sparse=1, rmapbt=0
         =                       reflink=1    bigtime=1 inobtcount=1 nrext64=0
data     =                       bsize=4096   blocks=2621440, imaxpct=25
         =                       sunit=0      swidth=0 blks
naming   =version 2              bsize=4096   ascii-ci=0, ftype=1
log      =internal log           bsize=4096   blocks=16384, version=2
         =                       sectsz=512   sunit=0 blks, lazy-count=1
realtime =none                   extsz=4096   blocks=0, rtextents=0
```

> **注意 `ftype=1`**：Docker overlay2 需要此选项，现代 xfsprogs 默认启用。  

---

## Step 3 - 查看文件系统参数

创建完成后，如何确认和查看参数？

### 3.1 ext4 参数查看

```bash
# 查看 ext4 详细信息
sudo tune2fs -l /dev/sdb1
```

关键输出字段：

```
Filesystem volume name:   data_ext4
Filesystem UUID:          a1b2c3d4-e5f6-7890-abcd-ef1234567890
Filesystem features:      has_journal ext_attr resize_inode dir_index
Inode count:              655360
Block count:              2621440
Reserved block count:     131072    # 5% 保留给 root
Block size:               4096
```

```bash
# 修改保留块比例（默认 5%，数据盘可设 0）
sudo tune2fs -m 1 /dev/sdb1    # 改为 1%
```

### 3.2 XFS 参数查看

```bash
# 查看 XFS 信息（需要挂载后执行）
sudo mount /dev/sdb2 /mnt
xfs_info /mnt
```

关键输出字段：

```
meta-data=/dev/sdb2              isize=512    agcount=4, agsize=655360 blks
data     =                       bsize=4096   blocks=2621440
naming   =version 2              bsize=4096   ascii-ci=0, ftype=1
log      =internal               bsize=4096   blocks=16384
```

```bash
# 检查 reflink 支持
xfs_info /mnt | grep reflink
# reflink=1 表示支持
```

---

## Step 4 - LUKS 磁盘加密

### 4.1 什么是 LUKS？

**LUKS**（Linux Unified Key Setup）是 Linux 标准的磁盘加密方案：

```
┌─────────────────────────────────────────────────────────────┐
│                     存储架构对比                              │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  普通分区:                                                   │
│  ┌─────────────┐     ┌─────────────┐                        │
│  │ /dev/sdb1   │────▶│ 文件系统     │────▶ 挂载点            │
│  │ (分区)      │     │ (ext4/XFS)  │      (/data)           │
│  └─────────────┘     └─────────────┘                        │
│                                                             │
│  LUKS 加密分区:                                              │
│  ┌─────────────┐     ┌─────────────┐     ┌─────────────┐    │
│  │ /dev/sdb1   │────▶│    LUKS     │────▶│ /dev/mapper │    │
│  │ (分区)      │     │  (加密层)    │     │ /data_crypt │    │
│  └─────────────┘     └─────────────┘     └──────┬──────┘    │
│                                                  │          │
│                                          ┌──────▼──────┐    │
│                                          │ 文件系统     │    │
│                                          │ (ext4/XFS)  │    │
│                                          └──────┬──────┘    │
│                                                  │          │
│                                              挂载点          │
│                                              (/data)        │
└─────────────────────────────────────────────────────────────┘
```

### 4.2 LUKS 基本工作流程

```bash
# 1. 初始化 LUKS 加密（会销毁分区数据！）
sudo cryptsetup luksFormat /dev/sdb1

# 输入 YES（大写）确认，然后设置密码

# 2. 打开（解锁）加密分区
sudo cryptsetup luksOpen /dev/sdb1 data_crypt

# 3. 在解密后的设备上创建文件系统
sudo mkfs.ext4 /dev/mapper/data_crypt

# 4. 挂载使用
sudo mount /dev/mapper/data_crypt /data

# 5. 使用完毕后关闭
sudo umount /data
sudo cryptsetup luksClose data_crypt
```

### 4.3 架构选择：LVM on LUKS vs LUKS on LVM

| 架构 | 描述 | 优点 | 缺点 |
|------|------|------|------|
| **LVM on LUKS** | 先加密，再 LVM | 一个密码解锁所有 LV | 全加密或全不加密 |
| **LUKS on LVM** | 先 LVM，再加密 | 可选择性加密 LV | 多密码管理 |

**生产推荐**：LVM on LUKS（管理简单，安全性一致）

### 4.4 开机自动解锁（crypttab）

```bash
# /etc/crypttab 配置示例
# <name>         <device>                      <keyfile>      <options>
data_crypt      UUID=xxxxx-xxxxx-xxxxx-xxxxx   /root/keyfile  luks
```

> **安全提示**：密钥文件需要严格保护权限（`chmod 400`），并且只有 root 可读。  

---

## 动手实验：创建加密分区

使用 loop 设备安全练习 LUKS：

```bash
# 创建 100MB 虚拟磁盘
fallocate -l 100M /tmp/luks_test.img
sudo losetup /dev/loop10 /tmp/luks_test.img

# 初始化 LUKS
sudo cryptsetup luksFormat /dev/loop10
# 输入 YES，设置密码

# 打开加密设备
sudo cryptsetup luksOpen /dev/loop10 test_crypt

# 创建文件系统并挂载
sudo mkfs.ext4 /dev/mapper/test_crypt
sudo mkdir -p /mnt/encrypted
sudo mount /dev/mapper/test_crypt /mnt/encrypted

# 写入测试文件
echo "Secret data" | sudo tee /mnt/encrypted/secret.txt

# 清理
sudo umount /mnt/encrypted
sudo cryptsetup luksClose test_crypt
sudo losetup -d /dev/loop10
rm /tmp/luks_test.img
```

---

## Sidebar: io_uring 现代异步 I/O

> **覆盖级别**：了解即可（Awareness Only）  

**io_uring** 是 Linux 5.1+ 引入的新异步 I/O 接口：

- 传统 I/O（read/write/epoll）每次操作需要系统调用
- io_uring 通过共享内存 ring buffer 减少内核切换
- 高 IOPS 场景性能提升显著

**作为存储管理员需要知道：**

| 场景 | 相关性 |
|------|--------|
| 高性能数据库 | PostgreSQL 16+ 可能启用 io_uring |
| 性能测试 | fio 支持 io_uring 引擎 |
| 内核版本 | 某些功能需要 5.x 以上内核 |

```bash
# 检查 io_uring 是否被禁用（某些安全加固会禁用）
cat /proc/sys/kernel/io_uring_disabled
# 0 = 启用, 1 = 禁用
```

> **深入学习**：io_uring 的详细内容将在 LX09-PERFORMANCE 课程中讨论。  

---

## 决策指南

```
                     ┌─────────────────────────────────────────┐
                     │        选择哪个文件系统？                 │
                     └───────────────────┬─────────────────────┘
                                         │
                     ┌───────────────────▼───────────────────┐
                     │      可能需要收缩分区吗？               │
                     └───────────────────┬───────────────────┘
                              │                    │
                            是                    否
                              │                    │
                              ▼                    ▼
                          ┌───────┐     ┌──────────────────────┐
                          │ ext4  │     │ 大文件（>100MB）为主？│
                          └───────┘     └──────────┬───────────┘
                                              │         │
                                            是         否
                                              │         │
                                              ▼         ▼
                                          ┌─────┐   ┌──────────────────┐
                                          │ XFS │   │ 需要并行 I/O？    │
                                          └─────┘   └────────┬─────────┘
                                                        │         │
                                                      是         否
                                                        │         │
                                                        ▼         ▼
                                                    ┌─────┐   ┌───────┐
                                                    │ XFS │   │ 都可以│
                                                    └─────┘   └───────┘
```

### 快速选择表

| 使用场景 | 推荐 | 理由 |
|----------|------|------|
| 系统根分区 | ext4 | 稳定、可收缩 |
| 数据库存储 | XFS | 大文件、并行 I/O |
| Web 服务器 | ext4 | 小文件多 |
| 日志服务器 | ext4 | 日志轮转、小文件 |
| 媒体存储 | XFS | 大文件性能 |
| RHEL 默认 | XFS | 发行版标准 |
| 需要加密 | 任意 + LUKS | 块设备级加密 |

---

## 本课小结

| 你学到的 | 命令/概念 |
|----------|-----------|
| 创建 ext4 | `mkfs.ext4 -L label /dev/sdX` |
| 创建 XFS | `mkfs.xfs -L label /dev/sdX` |
| 查看 ext4 参数 | `tune2fs -l /dev/sdX` |
| 查看 XFS 参数 | `xfs_info /mount/point` |
| LUKS 初始化 | `cryptsetup luksFormat /dev/sdX` |
| LUKS 解锁 | `cryptsetup luksOpen /dev/sdX name` |
| LUKS 锁定 | `cryptsetup luksClose name` |
| 核心差异 | XFS 不能收缩，ext4 可以 |

---

## 下一步

文件系统创建好了，但还没有"挂载"到系统目录树。下一课我们将学习挂载操作和 fstab 配置——这是最容易导致服务器无法启动的配置文件。

-> [04 - 挂载与 fstab](../04-mounting-fstab/)

---

## 职场小贴士

### 日本 IT 运维场景

**个人情報保護法と暗号化**

日本的《个人信息保护法》（個人情報保護法）对数据保护有严格要求。在以下场景，磁盘加密是必要或推荐的：

- **ノート PC**（笔记本电脑）：必须加密
- **リムーバブルメディア**（移动存储）：USB 驱动器、外接硬盘
- **クラウドボリューム**：敏感数据所在的云存储卷

> 面试时提到 LUKS 经验会是加分项，表明你理解日本企业的合规需求。  

---

## 面试准备

**Q: ext4 と XFS の違いは何ですか？**

A: 主な違いは：
- ext4 は縮小可能、XFS は拡張のみ
- XFS は大きなファイルと並列 I/O に優れる
- RHEL 系は XFS がデフォルト、Ubuntu 系は ext4 がデフォルト

**Q: なぜ RHEL は XFS をデフォルトにしていますか？**

A: エンタープライズ環境では大容量ストレージと高スループットが求められるため。XFS の Allocation Group アーキテクチャがマルチコア環境で有利です。

**Q: LUKS について説明してください。**

A: LUKS は Linux 標準のディスク暗号化方式です。dm-crypt の上に鍵管理層を提供し、ブロックデバイスレベルで暗号化します。個人情報保護法対応でノート PC やリムーバブルメディアの暗号化に使われます。

---

## 检查清单

在继续下一课之前，确认你能：

- [ ] 解释 ext4 和 XFS 的主要差异
- [ ] 使用 `mkfs.ext4` 和 `mkfs.xfs` 创建文件系统
- [ ] 使用 `tune2fs` 查看/修改 ext4 参数
- [ ] 使用 `xfs_info` 查看 XFS 参数
- [ ] 描述 LUKS 加密的基本工作流程
- [ ] 根据使用场景选择合适的文件系统

---

## 延伸阅读

- [Red Hat - Managing File Systems (RHEL 9)](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/9/html/managing_file_systems/)
- [Arch Wiki - ext4](https://wiki.archlinux.org/title/Ext4)
- [Arch Wiki - XFS](https://wiki.archlinux.org/title/XFS)
- [Arch Wiki - LUKS](https://wiki.archlinux.org/title/dm-crypt/Encrypting_an_entire_system)

---

## 系列导航

<- [02 - 分区管理](../02-partitioning/) | [课程首页](../) | [04 - 挂载与 fstab ->](../04-mounting-fstab/)
