# LX07 - Linux 存储管理（Linux Storage Management）

> **从块设备到 LVM 到 RAID，全面掌握 Linux 存储管理**

本课程是 Linux World 模块化课程体系的一部分，专注于存储管理。

## 课程概览

| 属性 | 值 |
|------|-----|
| **课时** | 12 课 |
| **时长** | 25-30 小时 |
| **难度** | 中级 |
| **前置** | LX02 系统管理 |
| **认证** | LPIC-2, RHCSA |

## 课程特色

- **持久命名优先**：UUID、by-id 从第一课开始
- **fstab 重点**：一行错误导致无法启动，专门练习恢复
- **LVM 三部曲**：架构理解 → 日常操作 → 快照工作流
- **故障驱动**：7 个真实灾难场景实验

## 版本兼容性

| 工具 | 课程版本 | 当前最新 | 说明 |
|------|----------|----------|------|
| **lvm2** | 2.03+ | 2.03.38 (2025) | PV/VG/LV 管理 |
| **mdadm** | 4.2+ | 4.3 (2025) | Software RAID |
| **e2fsprogs** | 1.46+ | 1.47.3 (2025) | ext4 工具 |
| **xfsprogs** | 5.x+ | 6.18.0 (2025) | XFS 工具 |
| **cryptsetup** | 2.4+ | 2.8.2 (2025) | LUKS 加密 |
| **RHEL** | 8/9 | 9.5 | RHEL 8 支持至 2029 |
| **Ubuntu** | 20.04+ | 24.04 LTS | 22.04/24.04 推荐 |

**注意事项：**
- 所有存储操作建议先在 loop 设备上练习，避免误操作
- XFS 不支持缩小，只能扩展（课程第 3 课重点讲解）
- LUKS2 是推荐的加密格式（RHEL 8+、Ubuntu 20.04+）

## 课程大纲

### Part 1: 基础 (01-04)

| 课程 | 标题 | 描述 |
|------|------|------|
| 01 | [块设备与命名](./01-block-devices-naming/) | UUID、by-id、lsblk |
| 02 | [分区管理](./02-partitioning/) | fdisk、gdisk、GPT vs MBR |
| 03 | [文件系统](./03-filesystems/) | ext4、XFS、mkfs |
| 04 | [挂载与 fstab](./04-mounting-fstab/) | mount、fstab、nofail |

### Part 2: LVM (05-07)

| 课程 | 标题 | 描述 |
|------|------|------|
| 05 | [LVM 架构](./05-lvm-architecture/) | PV、VG、LV 概念 |
| 06 | [LVM 操作](./06-lvm-operations/) | 创建、扩展、缩小 |
| 07 | [LVM 快照](./07-lvm-snapshots/) | 备份前快照、恢复 |

### Part 3: RAID (08-09)

| 课程 | 标题 | 描述 |
|------|------|------|
| 08 | [RAID 概念](./08-raid-concepts/) | RAID 0/1/5/6/10 |
| 09 | [mdadm 操作](./09-mdadm-operations/) | 创建、监控、恢复 |

### Part 4: 维护与备份 (10-12)

| 课程 | 标题 | 描述 |
|------|------|------|
| 10 | [备份策略](./10-backup-strategies/) | rsync + LVM 快照 |
| 11 | [文件系统维护](./11-filesystem-maintenance/) | fsck、xfs_repair |
| 12 | [综合实战](./12-capstone/) | 存储故障恢复场景 |

## 快速开始

```bash
# GitHub（海外用户）
git clone --filter=blob:none --sparse https://github.com/shiicho/cloud-atlas ~/cloud-atlas
cd ~/cloud-atlas && git sparse-checkout set foundations/linux/lx07-storage

# Gitee（中国大陆用户）
git clone --filter=blob:none --sparse https://gitee.com/shiicho/cloud-atlas ~/cloud-atlas
cd ~/cloud-atlas && git sparse-checkout set foundations/linux/lx07-storage
```

## 前置课程

- [LX02 - 系统管理](../lx02-sysadmin/)

## 后续路径

完成本课程后，你可以：

- **LX09 - 性能调优**：I/O 性能分析
- **LX10 - 故障排查**：存储故障排查
