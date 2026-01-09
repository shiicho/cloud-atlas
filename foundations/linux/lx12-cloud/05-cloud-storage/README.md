# 05 - 云存储：EBS 与持久化（Cloud Storage: EBS & Persistence）

> **目标**：掌握云存储的三层扩容（卷→分区→文件系统），学会使用救援实例恢复"砖化"的云服务器  
> **前置**：[01 - 云中 Linux 有何不同](../01-cloud-context/)、[LX07 存储管理](../../storage/)（lsblk、mount、fstab 基础）  
> **时间**：2.5 小时  
> **实战场景**：诊断 "EBS 扩容了但磁盘还是满" 的幻影存储问题  

---

## 将学到的内容

1. 理解云存储与本地存储的差异（Instance Store vs EBS）
2. 正确扩展 EBS 卷（包括分区和文件系统——**三步缺一不可**）
3. 使用 by-uuid 实现稳定挂载（告别设备名变化的噩梦）
4. 掌握云环境的救援实例模式（当无法 SSH 时的救命稻草）
5. 理解云环境独特的恢复手段（没有物理控制台怎么办？）

---

## 先跑起来！（10 分钟）

> 在学习云存储理论之前，先用 Linux 命令探索你的云实例存储环境。  

在任意 EC2 实例上运行以下命令：

### 探索存储设备

```bash
# 查看块设备拓扑（你会发现云存储的层次结构）
lsblk

# 注意设备名和大小！
```

```
NAME          MAJ:MIN RM SIZE RO TYPE MOUNTPOINTS
nvme0n1       259:0    0  20G  0 disk
├─nvme0n1p1   259:1    0  20G  0 part /
└─nvme0n1p128 259:2    0   1M  0 part
```

**发现 1**：设备名是 `nvme0n1` 而非传统的 `/dev/sda`——这是 NVMe 存储的命名方式。

### 探索文件系统使用情况

```bash
# 查看文件系统使用情况
df -h

# 查看根分区类型
df -T /
```

```
Filesystem      Type  Size  Used Avail Use% Mounted on
/dev/nvme0n1p1  xfs    20G  2.1G   18G  11% /
```

**发现 2**：Amazon Linux 2023 默认使用 XFS 文件系统。

### 探索设备 UUID

```bash
# 查看设备 UUID（稳定的标识符）
blkid

# 注意！设备名可能变化，但 UUID 不会
```

```
/dev/nvme0n1p1: UUID="a1b2c3d4-e5f6-7890-abcd-ef1234567890" TYPE="xfs" PARTLABEL="Linux" PARTUUID="..."
```

**发现 3**：每个设备有唯一的 UUID——这是 fstab 中应该使用的标识符。

### 查看当前 fstab

```bash
# 查看挂载配置
cat /etc/fstab

# 注意使用的是 UUID 还是设备名
```

**你刚刚用标准 Linux 命令探索了云存储。** 接下来让我们理解为什么云存储需要特别对待。

---

## Step 1 - 云存储概念（20 分钟）

### 1.1 Instance Store vs EBS

云存储有两种根本不同的类型：

<!-- DIAGRAM: instance-store-vs-ebs -->
```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    Instance Store vs EBS 对比                                │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│   Instance Store（实例存储）                EBS（弹性块存储）                 │
│   ─────────────────────────                ─────────────────                │
│                                                                             │
│   ┌─────────────────────┐                  ┌─────────────────────┐         │
│   │     EC2 实例        │                  │     EC2 实例        │         │
│   │   ┌───────────┐     │                  │                     │         │
│   │   │ Instance  │     │                  │                     │         │
│   │   │  Store    │     │                  └──────────┬──────────┘         │
│   │   │  (本地)   │     │                             │                    │
│   │   └───────────┘     │                             │ 网络连接            │
│   └─────────────────────┘                             │                    │
│                                                        ▼                    │
│   位置：物理主机本地                        ┌─────────────────────┐         │
│   持久性：实例终止即丢失！                  │    EBS 卷           │         │
│   用途：临时数据、缓存                      │  （独立存储）        │         │
│   性能：极高（本地 NVMe）                   └─────────────────────┘         │
│   成本：包含在实例价格中                                                     │
│                                             位置：独立存储系统               │
│   ⚠️ Stop/Start 后数据丢失！               持久性：独立于实例生命周期        │
│   ⚠️ 重启后数据保留                        用途：系统盘、数据盘             │
│                                             性能：取决于卷类型               │
│                                             成本：按容量和 IOPS 计费         │
│                                                                             │
│                                             ✓ Stop/Start 数据保留           │
│                                             ✓ 可分离重新附加                 │
│                                             ✓ 可创建快照                     │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```
<!-- /DIAGRAM -->

### 1.2 EBS 卷类型

| 类型 | 用途 | IOPS | 价格 |
|------|------|------|------|
| **gp3** | 通用（推荐默认） | 3000-16000 | $0.08/GB/月 |
| **gp2** | 通用（旧版） | 随容量变化 | $0.10/GB/月 |
| **io2** | 高性能数据库 | 最高 256000 | $0.125/GB + IOPS |
| **st1** | 大数据、日志 | 吞吐量优化 | $0.045/GB/月 |
| **sc1** | 冷存储 | 最低成本 | $0.015/GB/月 |

**2025 推荐**：新项目使用 gp3，可独立配置 IOPS 和吞吐量。

### 1.3 根卷 vs 数据卷

```bash
# 查看当前挂载的所有 EBS 卷
lsblk -o NAME,SIZE,TYPE,MOUNTPOINT

# 从元数据服务获取块设备映射
TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/block-device-mapping/
```

| 类型 | 说明 | 生命周期 |
|------|------|----------|
| **根卷** | 操作系统所在卷 | 默认随实例终止删除 |
| **数据卷** | 附加的 EBS 卷 | 独立于实例生命周期 |

**最佳实践**：
- 根卷：保持较小，只放 OS 和基础软件
- 数据卷：应用数据、日志、数据库文件

### 1.4 快照与备份

```bash
# 创建 EBS 快照（需要 AWS CLI）
aws ec2 create-snapshot \
  --volume-id vol-xxxxxxxx \
  --description "Pre-upgrade backup $(date +%Y%m%d)"

# 查看快照进度
aws ec2 describe-snapshots \
  --snapshot-ids snap-xxxxxxxx \
  --query 'Snapshots[0].Progress'
```

**快照特点**：
- 增量存储（只存变化部分）
- 可跨 AZ/Region 复制
- 可从快照创建新卷
- 是云环境备份的基础

---

## Step 2 - 设备命名（15 分钟）

### 2.1 设备命名的混乱

云环境中设备命名是一个常见痛点：

<!-- DIAGRAM: device-naming -->
```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        云存储设备命名对照                                     │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│   AWS 控制台指定          Linux 实际看到              说明                   │
│   ────────────────        ────────────────           ────────               │
│                                                                             │
│   /dev/sda1              /dev/nvme0n1p1             Nitro 实例              │
│   /dev/sdf               /dev/nvme1n1               附加卷                  │
│   /dev/sdg               /dev/nvme2n1               第三个卷                │
│   /dev/xvda              /dev/xvda                  旧实例类型              │
│   /dev/xvdf              /dev/xvdf                  旧实例类型              │
│                                                                             │
│   ⚠️ 问题：重启后 NVMe 设备顺序可能变化！                                    │
│                                                                             │
│   ┌────────────────────────────────────────────────────────────────────┐   │
│   │  重启前                           重启后                            │   │
│   │  /dev/nvme1n1 → 数据卷A          /dev/nvme1n1 → 数据卷B ❌          │   │
│   │  /dev/nvme2n1 → 数据卷B          /dev/nvme2n1 → 数据卷A ❌          │   │
│   └────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
│   解决方案：使用稳定标识符                                                   │
│   ─────────────────────────                                                 │
│   /dev/disk/by-uuid/xxxx-xxxx         ✓ 文件系统 UUID（推荐）              │
│   /dev/disk/by-id/nvme-xxx            ✓ NVMe 序列号                        │
│   /dev/disk/by-label/DATA             ✓ 文件系统标签                       │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```
<!-- /DIAGRAM -->

### 2.2 查看稳定标识符

```bash
# 查看所有稳定标识符
ls -la /dev/disk/by-uuid/
ls -la /dev/disk/by-id/
ls -la /dev/disk/by-label/

# 使用 blkid 查看 UUID
blkid

# 输出示例：
/dev/nvme0n1p1: UUID="a1b2c3d4-e5f6-7890-abcd-ef1234567890" TYPE="xfs"
/dev/nvme1n1: UUID="11112222-3333-4444-5555-666677778888" TYPE="ext4"
```

### 2.3 NVMe 设备识别

对于 Nitro 实例（新型实例），可以通过 NVMe 工具识别：

```bash
# 安装 NVMe 工具（如果没有）
sudo yum install -y nvme-cli

# 查看 NVMe 设备详情
sudo nvme list

# 获取设备的卷 ID
sudo nvme id-ctrl -v /dev/nvme1n1 | grep -i "sn\|mn"

# 或者使用这个命令查看 EBS 卷 ID
lsblk -o +SERIAL
```

### 2.4 为什么设备名会变化？

```
┌────────────────────────────────────────────────────────────────────────────┐
│                       设备名变化的原因                                       │
├────────────────────────────────────────────────────────────────────────────┤
│                                                                            │
│  1. Stop/Start（停止/启动）                                                │
│     - 实例可能迁移到不同物理主机                                           │
│     - NVMe 控制器重新枚举设备                                              │
│                                                                            │
│  2. 添加/移除 EBS 卷                                                       │
│     - 新卷可能插入到现有设备号之前                                         │
│                                                                            │
│  3. 实例类型变更                                                           │
│     - 从 xen 虚拟化 → Nitro 虚拟化                                        │
│     - /dev/xvdf → /dev/nvme1n1                                            │
│                                                                            │
│  结论：永远不要在 fstab 中硬编码设备名！                                    │
│                                                                            │
└────────────────────────────────────────────────────────────────────────────┘
```

---

## Step 3 - EBS 扩容三步曲（30 分钟）

### 3.1 为什么控制台扩容 ≠ 完成扩容？

**这是云存储最重要的概念**：EBS 扩容是三层操作，控制台只完成第一层！

<!-- DIAGRAM: ebs-resize-three-layers -->
```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    EBS 扩容三层架构（都要扩！）                                │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│   Layer 1: 块设备（Block Device）                                           │
│   ─────────────────────────────────                                         │
│   AWS 控制台 / CLI：修改卷大小                                               │
│   aws ec2 modify-volume --size 100                                          │
│   ✓ AWS 自动完成                                                            │
│                                                                             │
│          ▼                                                                  │
│                                                                             │
│   Layer 2: 分区（Partition）                                                 │
│   ─────────────────────────────                                             │
│   Linux 命令：扩展分区以使用新空间                                           │
│   sudo growpart /dev/nvme0n1 1                                              │
│   ⚠️ 需要手动执行！                                                          │
│                                                                             │
│          ▼                                                                  │
│                                                                             │
│   Layer 3: 文件系统（Filesystem）                                            │
│   ────────────────────────────────                                          │
│   Linux 命令：扩展文件系统以填充分区                                         │
│   sudo xfs_growfs /         # XFS                                           │
│   sudo resize2fs /dev/xxx   # ext4                                          │
│   ⚠️ 需要手动执行！                                                          │
│                                                                             │
│   ┌─────────────────────────────────────────────────────────────────────┐  │
│   │                                                                     │  │
│   │     ┌───────────────────────────────────────────────────────────┐  │  │
│   │     │  Block Device (100GB)    ← Layer 1: 控制台扩容             │  │  │
│   │     │  ┌───────────────────────────────────────────────────┐    │  │  │
│   │     │  │  Partition (20GB → 100GB)  ← Layer 2: growpart    │    │  │  │
│   │     │  │  ┌───────────────────────────────────────────┐    │    │  │  │
│   │     │  │  │  Filesystem (20GB → 100GB)                │    │    │  │  │
│   │     │  │  │  ↑ Layer 3: xfs_growfs / resize2fs        │    │    │  │  │
│   │     │  │  └───────────────────────────────────────────┘    │    │  │  │
│   │     │  └───────────────────────────────────────────────────┘    │  │  │
│   │     └───────────────────────────────────────────────────────────┘  │  │
│   │                                                                     │  │
│   │  如果只做 Layer 1，df -h 仍然显示 20GB！                            │  │
│   │                                                                     │  │
│   └─────────────────────────────────────────────────────────────────────┘  │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```
<!-- /DIAGRAM -->

### 3.2 扩容完整流程

**场景**：根卷从 20GB 扩展到 100GB

**Step 1 - 查看当前状态**

```bash
# 查看块设备大小
lsblk

# 查看文件系统使用情况
df -h /

# 记录当前状态（重要！）
lsblk > /tmp/before-resize.txt
df -h > /tmp/before-df.txt
```

**Step 2 - 在 AWS 控制台/CLI 扩展卷**

```bash
# 使用 AWS CLI 扩展卷（或在控制台操作）
aws ec2 modify-volume \
  --volume-id vol-xxxxxxxx \
  --size 100

# 等待卷状态变为 "optimizing" 或 "completed"
aws ec2 describe-volumes-modifications \
  --volume-ids vol-xxxxxxxx \
  --query 'VolumesModifications[0].ModificationState'
```

**Step 3 - 扩展分区（Layer 2）**

```bash
# 查看：块设备已经是 100GB，但分区还是 20GB
lsblk

# 输出：
# NAME          SIZE  TYPE MOUNTPOINTS
# nvme0n1       100G  disk            <- 100GB 了！
# ├─nvme0n1p1    20G  part /          <- 还是 20GB！
# └─nvme0n1p128   1M  part

# 扩展分区
sudo growpart /dev/nvme0n1 1

# 验证分区已扩展
lsblk
```

**Step 4 - 扩展文件系统（Layer 3）**

```bash
# 查看文件系统类型
df -T /

# 如果是 XFS：
sudo xfs_growfs /

# 如果是 ext4：
# sudo resize2fs /dev/nvme0n1p1

# 验证文件系统已扩展
df -h /
```

**完整状态变化**：

```
┌────────────────────────────────────────────────────────────────────────────┐
│  操作步骤                    lsblk 显示                 df -h /            │
├────────────────────────────────────────────────────────────────────────────┤
│  初始状态                    nvme0n1: 20G               20G                │
│                              nvme0n1p1: 20G                                │
│                                                                            │
│  控制台扩容后                nvme0n1: 100G ✓            20G ← 没变！       │
│                              nvme0n1p1: 20G ✗                              │
│                                                                            │
│  growpart 后                 nvme0n1: 100G ✓            20G ← 还没变！     │
│                              nvme0n1p1: 100G ✓                             │
│                                                                            │
│  xfs_growfs 后               nvme0n1: 100G ✓            100G ✓ 完成！      │
│                              nvme0n1p1: 100G ✓                             │
└────────────────────────────────────────────────────────────────────────────┘
```

### 3.3 XFS vs ext4 扩容命令

| 文件系统 | 查看命令 | 扩容命令 | 是否需要卸载 |
|----------|----------|----------|--------------|
| **XFS** | `xfs_info /` | `xfs_growfs /` | 否（在线扩容） |
| **ext4** | `tune2fs -l /dev/xxx` | `resize2fs /dev/xxx` | 否（在线扩容） |

**注意**：XFS 只能扩容，不能缩容！ext4 可以缩容（需要卸载）。

---

## Step 4 - fstab 最佳实践（15 分钟）

### 4.1 fstab 格式回顾

```bash
# /etc/fstab 格式：
# <设备>  <挂载点>  <类型>  <选项>  <dump>  <fsck>
```

### 4.2 错误示例：硬编码设备名

```bash
# ❌ 错误：使用设备名
/dev/xvdf  /data  xfs  defaults  0  2
/dev/nvme1n1  /data  xfs  defaults  0  2

# 问题：重启后设备名可能变化！
```

### 4.3 正确示例：使用 UUID

```bash
# ✓ 正确：使用 UUID
UUID=11112222-3333-4444-5555-666677778888  /data  xfs  defaults,nofail  0  2
```

**获取 UUID**：

```bash
# 方法 1：blkid
blkid /dev/nvme1n1

# 方法 2：lsblk
lsblk -o NAME,UUID

# 方法 3：ls
ls -la /dev/disk/by-uuid/
```

### 4.4 nofail 选项：启动容错

```bash
# 关键选项：nofail
UUID=xxxx-xxxx  /data  xfs  defaults,nofail  0  2
                                    ^^^^^^
                                    关键！
```

**nofail 的作用**：

```
┌────────────────────────────────────────────────────────────────────────────┐
│                        nofail 选项的重要性                                  │
├────────────────────────────────────────────────────────────────────────────┤
│                                                                            │
│   没有 nofail：                                                            │
│   ─────────────                                                            │
│   如果 EBS 卷无法挂载（卷不存在、损坏等）                                  │
│   → 系统进入 emergency mode                                                │
│   → 无法启动！无法 SSH！                                                   │
│   → 需要救援实例恢复                                                       │
│                                                                            │
│   有 nofail：                                                              │
│   ───────────                                                              │
│   如果 EBS 卷无法挂载                                                      │
│   → 系统记录警告但继续启动                                                 │
│   → 可以 SSH 进去排查问题                                                  │
│   → 生产环境必备！                                                         │
│                                                                            │
│   最佳实践 fstab 条目：                                                    │
│   UUID=xxxx  /data  xfs  defaults,nofail,x-systemd.device-timeout=10  0 2  │
│                                                                            │
└────────────────────────────────────────────────────────────────────────────┘
```

### 4.5 验证 fstab 语法

**修改 fstab 前必做**：

```bash
# 1. 备份
sudo cp /etc/fstab /etc/fstab.bak

# 2. 编辑
sudo vim /etc/fstab

# 3. 验证语法（关键步骤！）
sudo mount -a

# 如果有错误，会显示在这里
# 4. 如果验证通过，重启测试（可选）
```

---

## Step 5 - 救援实例模式（25 分钟）

### 5.1 什么时候需要救援实例？

当实例"砖化"（无法启动或无法 SSH）时：

| 症状 | 可能原因 | 解决方案 |
|------|----------|----------|
| 无法启动，卡在启动 | fstab 错误 | 救援实例 |
| SSH 连不上（端口无响应） | sshd 配置错误 | 救援实例 |
| 能连但无法 sudo | sudoers 错误 | 救援实例 |
| 启动但无网络 | 网络配置错误 | Serial Console / 救援实例 |

### 5.2 救援实例工作流程

<!-- DIAGRAM: rescue-instance-workflow -->
```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        救援实例恢复流程                                       │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│   问题实例                        救援实例                                    │
│   ─────────                       ─────────                                  │
│                                                                             │
│   Step 1: 停止问题实例                                                       │
│   ┌─────────────┐                                                           │
│   │   问题实例   │ ◄── aws ec2 stop-instances                               │
│   │  (Stopped)  │                                                           │
│   └──────┬──────┘                                                           │
│          │                                                                  │
│   Step 2: 分离根卷                                                           │
│          │                                                                  │
│          ▼                                                                  │
│   ┌─────────────┐     aws ec2 detach-volume                                 │
│   │  根卷 (EBS) │ ─────────────────────────────────┐                        │
│   │  vol-xxx    │                                   │                       │
│   └─────────────┘                                   │                       │
│                                                      │                       │
│   Step 3: 启动救援实例                               │                       │
│                                     ┌───────────────┼───────────────┐       │
│                                     │               │               │       │
│                                     │   救援实例    ▼               │       │
│                                     │   (Running)                   │       │
│                                     │   ┌───────────────────┐       │       │
│                                     │   │ 附加问题卷为      │       │       │
│                                     │   │ /dev/sdf          │       │       │
│                                     │   │ (显示为 nvme1n1)  │       │       │
│                                     │   └───────────────────┘       │       │
│                                     │                               │       │
│                                     └───────────────────────────────┘       │
│                                                                             │
│   Step 4: 在救援实例中修复                                                   │
│   sudo mkdir /rescue                                                        │
│   sudo mount /dev/nvme1n1p1 /rescue                                         │
│   sudo vim /rescue/etc/fstab  # 修复错误                                    │
│   sudo umount /rescue                                                       │
│                                                                             │
│   Step 5: 分离卷，重新附加到原实例                                           │
│   aws ec2 detach-volume --volume-id vol-xxx                                 │
│   aws ec2 attach-volume --volume-id vol-xxx --instance-id i-problem \       │
│     --device /dev/sda1                                                      │
│                                                                             │
│   Step 6: 启动原实例                                                         │
│   aws ec2 start-instances --instance-ids i-problem                          │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```
<!-- /DIAGRAM -->

### 5.3 救援实例详细步骤

**准备工作**：记录问题实例信息

```bash
# 记录实例 ID 和根卷信息
INSTANCE_ID="i-0123456789abcdef0"  # 问题实例 ID
VOLUME_ID="vol-0123456789abcdef0"  # 根卷 ID（从控制台或 describe-instances 获取）
AZ="ap-northeast-1a"               # 可用区（必须在同一 AZ）
```

**Step 1 - 停止问题实例**

```bash
# 停止实例
aws ec2 stop-instances --instance-ids $INSTANCE_ID

# 等待停止完成
aws ec2 wait instance-stopped --instance-ids $INSTANCE_ID
echo "Instance stopped"
```

**Step 2 - 分离根卷**

```bash
# 分离根卷
aws ec2 detach-volume --volume-id $VOLUME_ID

# 等待分离完成
aws ec2 wait volume-available --volume-ids $VOLUME_ID
echo "Volume detached"
```

**Step 3 - 启动救援实例**

```bash
# 启动救援实例（使用相同 AMI 和 AZ）
RESCUE_ID=$(aws ec2 run-instances \
  --image-id ami-xxxxxxxxx \
  --instance-type t3.micro \
  --placement AvailabilityZone=$AZ \
  --key-name your-key \
  --query 'Instances[0].InstanceId' \
  --output text)

# 等待启动完成
aws ec2 wait instance-running --instance-ids $RESCUE_ID
echo "Rescue instance running: $RESCUE_ID"
```

**Step 4 - 附加问题卷到救援实例**

```bash
# 附加卷（作为数据卷，不是根卷）
aws ec2 attach-volume \
  --volume-id $VOLUME_ID \
  --instance-id $RESCUE_ID \
  --device /dev/sdf

# 等待附加完成
aws ec2 wait volume-in-use --volume-ids $VOLUME_ID
echo "Volume attached"
```

**Step 5 - SSH 到救援实例并修复**

```bash
# SSH 到救援实例
ssh -i your-key.pem ec2-user@<救援实例公有IP>

# 在救援实例中：
# 查看附加的卷
lsblk

# 挂载问题卷
sudo mkdir /rescue
sudo mount /dev/nvme1n1p1 /rescue

# 修复问题（例如 fstab）
sudo vim /rescue/etc/fstab

# 验证修复
cat /rescue/etc/fstab

# 卸载
sudo umount /rescue
```

**Step 6 - 恢复原实例**

```bash
# 从救援实例分离卷
aws ec2 detach-volume --volume-id $VOLUME_ID
aws ec2 wait volume-available --volume-ids $VOLUME_ID

# 重新附加到原实例（作为根卷）
aws ec2 attach-volume \
  --volume-id $VOLUME_ID \
  --instance-id $INSTANCE_ID \
  --device /dev/sda1

# 启动原实例
aws ec2 start-instances --instance-ids $INSTANCE_ID
aws ec2 wait instance-running --instance-ids $INSTANCE_ID
echo "Instance recovered!"

# 清理：终止救援实例
aws ec2 terminate-instances --instance-ids $RESCUE_ID
```

---

## 云环境恢复手段

> **关键理解**：物理服务器可以插 USB、进 BIOS、启动到单用户模式。云实例没有这些选项！  

### 为什么云恢复不同？

```
┌────────────────────────────────────────────────────────────────────────────┐
│                    物理服务器 vs 云实例恢复对比                              │
├────────────────────────────────────────────────────────────────────────────┤
│                                                                            │
│   物理服务器恢复选项：                    云实例恢复选项：                   │
│   ─────────────────────                  ──────────────────                 │
│   ✓ 插入 USB 启动盘                      ✗ 没有物理访问                     │
│   ✓ 进入 BIOS/UEFI                       ✗ 没有 BIOS 控制                   │
│   ✓ 单用户模式 (init=/bin/sh)            ✗ 无法传递内核参数                 │
│   ✓ 本地 KVM/IPMI 控制台                 △ Serial Console (有限)           │
│   ✓ 直接操作磁盘                         ✓ 分离/附加 EBS 卷                 │
│                                                                            │
│   结论：云环境需要不同的恢复策略！                                          │
│                                                                            │
└────────────────────────────────────────────────────────────────────────────┘
```

### 恢复方法优先级

| 方法 | 适用场景 | 前提条件 | 推荐指数 |
|------|----------|----------|----------|
| **SSM Session Manager** | SSH 不可用但系统运行 | 预先配置 SSM Agent + IAM | ★★★★★ |
| **EC2 Serial Console** | 网络完全不通 | 预先设置密码/密钥 | ★★★★☆ |
| **救援实例** | 系统无法启动 | 同 AZ 内操作 | ★★★★★ |
| **User Data 恢复脚本** | 知道问题原因 | 系统能启动到 cloud-init | ★★★☆☆ |

### 方法 1：EC2 Serial Console

```bash
# 检查实例类型是否支持 Serial Console
# 支持：Nitro 系统实例（大多数新实例类型）

# 前提：需要预先在实例内设置密码
sudo passwd ec2-user

# 访问方式：AWS Console → EC2 → 选择实例 → Connect → EC2 Serial Console
```

**限制**：
- 不是所有实例类型都支持
- 需要预先设置访问凭证
- 体验类似于物理服务器的串口

### 方法 2：SSM Session Manager

```bash
# 检查 SSM Agent 状态（在实例正常时配置）
sudo systemctl status amazon-ssm-agent

# 通过 SSM 连接（无需开放 SSH 端口）
aws ssm start-session --target i-0123456789abcdef0

# 优势：
# - 无需开放入站端口
# - 自动记录会话日志
# - 可通过 IAM 控制访问
```

**前提**：
- SSM Agent 已安装并运行
- 实例有 IAM 角色（允许 SSM 操作）
- 实例有到 SSM 端点的网络连接（公网或 VPC Endpoint）

### 方法 3：User Data 恢复脚本

```bash
# 停止实例
aws ec2 stop-instances --instance-ids i-xxx

# 修改 user-data（添加修复命令）
aws ec2 modify-instance-attribute \
  --instance-id i-xxx \
  --user-data file://recovery-script.txt

# recovery-script.txt 内容示例：
#!/bin/bash
# 修复 fstab（移除问题行）
sed -i '/UUID=broken-uuid/d' /etc/fstab

# 启动实例
aws ec2 start-instances --instance-ids i-xxx
```

**限制**：
- 仅在实例能启动到 cloud-init 阶段时有效
- 需要知道确切的问题原因

### 方法 4：救援实例（最可靠）

见上一节详细流程。这是**最通用、最可靠**的恢复方法。

### 预防措施：避免需要恢复

```
┌────────────────────────────────────────────────────────────────────────────┐
│                       修改关键配置前的检查清单                               │
├────────────────────────────────────────────────────────────────────────────┤
│                                                                            │
│  ✓ 创建快照                                                                │
│    aws ec2 create-snapshot --volume-id vol-xxx --description "Before edit" │
│                                                                            │
│  ✓ 验证语法                                                                │
│    - fstab:    sudo mount -a                                               │
│    - sudoers:  sudo visudo -c                                              │
│    - sshd:     sudo sshd -t                                                │
│    - systemd:  sudo systemd-analyze verify xxx.service                     │
│                                                                            │
│  ✓ 保持备用访问通道                                                        │
│    - SSM Session Manager 配置完成                                          │
│    - Serial Console 密码已设置                                             │
│                                                                            │
│  ✓ 使用 drop-in 目录而非直接编辑                                           │
│    - /etc/sudoers.d/xxx 替代编辑 /etc/sudoers                             │
│    - /etc/ssh/sshd_config.d/xxx 替代编辑主配置                            │
│                                                                            │
│  ⚠️ 在没有恢复计划的情况下修改关键配置 = 高风险操作！                       │
│                                                                            │
└────────────────────────────────────────────────────────────────────────────┘
```

---

## Lab 1 - EBS 扩容完整流程（30 分钟）

### 实验目标

完成 EBS 扩容的完整三步流程，理解每一步的作用。

### Step 1 - 准备环境

```bash
# 确认当前状态
lsblk
df -h

# 记录初始状态
echo "=== Before Resize ===" > /tmp/resize-lab.log
lsblk >> /tmp/resize-lab.log
df -h >> /tmp/resize-lab.log
```

### Step 2 - 在控制台扩展 EBS 卷

1. 打开 AWS Console → EC2 → Elastic Block Store → Volumes
2. 选择根卷
3. Actions → Modify Volume
4. 将 Size 从 8GB 改为 20GB
5. 点击 Modify → Yes

或使用 CLI：

```bash
# 获取实例的根卷 ID
VOLUME_ID=$(aws ec2 describe-instances \
  --instance-ids $(curl -s http://169.254.169.254/latest/meta-data/instance-id) \
  --query 'Reservations[0].Instances[0].BlockDeviceMappings[?DeviceName==`/dev/xvda`].Ebs.VolumeId' \
  --output text)

# 扩展卷
aws ec2 modify-volume --volume-id $VOLUME_ID --size 20

# 等待修改完成
watch -n 5 "aws ec2 describe-volumes-modifications --volume-ids $VOLUME_ID --query 'VolumesModifications[0].ModificationState'"
```

### Step 3 - 验证块设备已扩展

```bash
# 查看块设备
lsblk

# 预期输出：
# nvme0n1       20G  ← 已经是 20GB
# ├─nvme0n1p1    8G  ← 分区还是 8GB！
```

### Step 4 - 扩展分区

```bash
# 扩展分区 1
sudo growpart /dev/nvme0n1 1

# 验证
lsblk

# 预期输出：
# nvme0n1       20G
# ├─nvme0n1p1   20G  ← 分区现在是 20GB
```

### Step 5 - 扩展文件系统

```bash
# 检查文件系统类型
df -T /

# 如果是 XFS（Amazon Linux 2023 默认）
sudo xfs_growfs /

# 如果是 ext4
# sudo resize2fs /dev/nvme0n1p1

# 验证
df -h
```

### Step 6 - 记录最终状态

```bash
echo "=== After Resize ===" >> /tmp/resize-lab.log
lsblk >> /tmp/resize-lab.log
df -h >> /tmp/resize-lab.log

# 对比前后变化
cat /tmp/resize-lab.log
```

### 检查清单

- [ ] 理解 EBS 扩容的三层架构
- [ ] 能使用 `lsblk` 查看块设备和分区大小
- [ ] 能使用 `growpart` 扩展分区
- [ ] 能使用 `xfs_growfs` 或 `resize2fs` 扩展文件系统
- [ ] 理解为什么控制台扩容后 `df -h` 没有变化

---

## Lab 2 - Phantom Storage 场景（20 分钟）

### 场景描述

> **"幻影存储"**：在 AWS 控制台将 EBS 卷从 20GB 扩容到 100GB。  
> 但监控仍然告警 "Disk Full" (99%)。  

这是生产环境最常见的 EBS 相关问题。

### 实验目标

诊断并解决"EBS 扩容了但磁盘还是满"的问题。

### Step 1 - 模拟场景

```bash
# 假设你收到告警，磁盘使用率 99%
df -h /
# 输出：99% used

# 你检查了 AWS 控制台，发现卷已经扩容到 100GB
# 但为什么 df -h 还是显示原来的大小？
```

### Step 2 - 诊断

```bash
# 关键诊断命令：比较块设备 vs 分区 vs 文件系统

# 1. 查看块设备大小
lsblk
# nvme0n1      100G  ← 块设备确实是 100GB

# 2. 查看分区大小
lsblk -o NAME,SIZE,TYPE
# nvme0n1       100G  disk
# nvme0n1p1      20G  part  ← 分区还是 20GB！

# 3. 查看文件系统大小
df -h /
# 20G total  ← 文件系统也是 20GB

# 结论：Layer 1（块设备）扩容了，但 Layer 2、3 没有
```

### Step 3 - 修复

```bash
# 扩展分区
sudo growpart /dev/nvme0n1 1

# 扩展文件系统
sudo xfs_growfs /  # 或 resize2fs

# 验证
df -h /
# 100G total  ← 问题解决！
```

### Step 4 - 总结经验

```
┌────────────────────────────────────────────────────────────────────────────┐
│                    Phantom Storage 排查速查                                 │
├────────────────────────────────────────────────────────────────────────────┤
│                                                                            │
│   症状：控制台显示卷已扩容，但 df -h 没变化                                │
│                                                                            │
│   诊断命令：                                                               │
│   lsblk                    # 对比块设备 vs 分区大小                        │
│                                                                            │
│   修复命令：                                                               │
│   sudo growpart /dev/xxx N  # 扩展分区 N                                  │
│   sudo xfs_growfs /         # 扩展 XFS                                    │
│   sudo resize2fs /dev/xxx   # 扩展 ext4                                   │
│                                                                            │
│   预防：创建扩容自动化脚本或使用 Systems Manager Automation                │
│                                                                            │
└────────────────────────────────────────────────────────────────────────────┘
```

### 检查清单

- [ ] 能识别 "Phantom Storage" 症状
- [ ] 能使用 `lsblk` 定位问题层级
- [ ] 能执行完整的三步扩容流程
- [ ] 理解为什么这是常见问题（控制台只做 Layer 1）

---

## Lab 3 - Locked Door 场景（30 分钟）

### 场景描述

> **"被锁的门"**：编辑 `/etc/fstab` 后，实例拒绝启动或接受 SSH。  
> 没有物理访问权限，需要恢复系统。  

### 实验目标

使用救援实例恢复损坏的 fstab（模拟生产事故）。

### 警告

> **本实验会让实例无法启动！** 请在测试实例上进行，或确保有恢复能力。  

### Step 1 - 准备环境

```bash
# 1. 记录实例 ID（用于后续恢复）
INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
echo "Instance ID: $INSTANCE_ID"

# 2. 创建快照（安全网）
VOLUME_ID=$(aws ec2 describe-instances \
  --instance-ids $INSTANCE_ID \
  --query 'Reservations[0].Instances[0].BlockDeviceMappings[0].Ebs.VolumeId' \
  --output text)
aws ec2 create-snapshot --volume-id $VOLUME_ID --description "Before fstab break"
```

### Step 2 - 故意破坏 fstab

```bash
# 备份原始 fstab
sudo cp /etc/fstab /etc/fstab.backup

# 添加错误条目（不存在的 UUID）
echo "UUID=00000000-0000-0000-0000-000000000000 /broken xfs defaults 0 2" | sudo tee -a /etc/fstab

# 验证 mount -a 会失败
sudo mount -a
# 应该报错：mount: /broken: can't find UUID=...
```

### Step 3 - 重启触发问题

```bash
# 重启实例
sudo reboot

# 等待... 实例将无法启动或进入 emergency mode
```

### Step 4 - 从外部观察

```bash
# 在本地或另一个实例上
# 实例状态检查会失败
aws ec2 describe-instance-status --instance-ids $INSTANCE_ID

# 系统日志可能显示 mount 失败
aws ec2 get-console-output --instance-ids $INSTANCE_ID --output text | tail -50
```

### Step 5 - 执行救援恢复

按照前面的"救援实例详细步骤"执行：

1. 停止问题实例
2. 分离根卷
3. 启动救援实例
4. 附加问题卷
5. 挂载并修复 fstab
6. 恢复

```bash
# 在救援实例中修复
sudo mkdir /rescue
sudo mount /dev/nvme1n1p1 /rescue

# 查看破损的 fstab
cat /rescue/etc/fstab

# 修复：删除错误行
sudo sed -i '/00000000-0000-0000-0000-000000000000/d' /rescue/etc/fstab

# 或恢复备份
sudo cp /rescue/etc/fstab.backup /rescue/etc/fstab

# 卸载
sudo umount /rescue
```

### Step 6 - 验证恢复

```bash
# 启动原实例后验证
ssh ec2-user@<实例IP>

# 检查 fstab 已修复
cat /etc/fstab
```

### 检查清单

- [ ] 理解 fstab 错误会导致启动失败
- [ ] 能执行完整的救援实例恢复流程
- [ ] 理解 `nofail` 选项的重要性
- [ ] 建立"修改前备份"的习惯

---

## Lab 4 - by-uuid 挂载（15 分钟）

### 实验目标

配置使用 UUID 的稳定 fstab 条目。

### Step 1 - 创建测试卷和文件系统

```bash
# 如果有额外的 EBS 卷（/dev/nvme1n1）
# 创建文件系统
sudo mkfs.xfs /dev/nvme1n1

# 创建挂载点
sudo mkdir /data
```

### Step 2 - 获取 UUID

```bash
# 获取 UUID
blkid /dev/nvme1n1

# 输出示例：
# /dev/nvme1n1: UUID="a1b2c3d4-e5f6-7890-1234-567890abcdef" TYPE="xfs"

# 保存 UUID
UUID=$(blkid -s UUID -o value /dev/nvme1n1)
echo "UUID: $UUID"
```

### Step 3 - 配置 fstab

```bash
# 添加正确的 fstab 条目
echo "UUID=$UUID /data xfs defaults,nofail 0 2" | sudo tee -a /etc/fstab

# 验证
cat /etc/fstab

# 测试挂载
sudo mount -a

# 验证挂载成功
df -h /data
mount | grep /data
```

### Step 4 - 验证稳定性

```bash
# 重启测试
sudo reboot

# 重启后验证
df -h /data
# 应该正常挂载
```

### 最佳实践 fstab 模板

```bash
# /etc/fstab - 云环境最佳实践示例

# 根分区（通常由 AMI 自动配置）
UUID=root-uuid /                xfs  defaults,noatime       0 1

# 数据卷（使用 UUID + nofail）
UUID=data-uuid /data            xfs  defaults,nofail        0 2

# 日志卷（使用 UUID + nofail + noatime）
UUID=logs-uuid /var/log/app     xfs  defaults,nofail,noatime 0 2

# 临时卷（如果使用 Instance Store）
# 注意：Instance Store 每次启动 UUID 可能变化，需要特殊处理
```

### 检查清单

- [ ] 能使用 `blkid` 获取设备 UUID
- [ ] 能配置使用 UUID 的 fstab 条目
- [ ] 理解 `nofail` 选项的作用
- [ ] 能使用 `mount -a` 验证 fstab 语法

---

## 跨云视角（Cross-Cloud Sidebar）

块存储和设备管理是所有云平台的通用概念：

| 概念 | AWS | GCP | Azure |
|------|-----|-----|-------|
| 块存储 | EBS | Persistent Disk | Managed Disks |
| 临时存储 | Instance Store | Local SSD | Temp Disk |
| 文件存储 | EFS | Filestore | Azure Files |
| 对象存储 | S3 | GCS | Blob Storage |
| 快照 | EBS Snapshot | Disk Snapshot | Disk Snapshot |
| 扩容流程 | 控制台+growpart+xfs_growfs | 控制台+resize2fs | 控制台+xfs_growfs |

**核心原则相同**：

```
块设备扩容 → 分区扩容 → 文件系统扩容
三步都要做！
```

**GCP 特点**：
- Persistent Disk 可以在线 resize（无需停止实例）
- 自动挂载通常使用 `/dev/disk/by-id/google-*`

**Azure 特点**：
- Managed Disks 同样需要 OS 内扩展分区和文件系统
- Premium SSD 可以在线扩容

---

## 反模式演示（Anti-Patterns Demo）

### 反模式 1：硬编码设备名

```bash
# ❌ 错误：
# /etc/fstab 中使用：
/dev/nvme1n1  /data  xfs  defaults  0  2

# 后果：
# 1. 重启后设备名变为 nvme2n1
# 2. 挂载失败，系统进入 emergency mode
# 3. 需要救援实例恢复
```

**修复**：始终使用 UUID

```bash
# ✓ 正确：
UUID=a1b2c3d4-xxxx  /data  xfs  defaults,nofail  0  2
```

### 反模式 2：假设控制台扩容已完成

```bash
# ❌ 错误思维：
# "我在控制台把卷从 20GB 扩容到 100GB 了，应该 OK 了"

# 后果：
# 1. df -h 仍显示 20GB
# 2. 磁盘告警持续
# 3. 应用因磁盘满而崩溃
```

**修复**：记住三步流程

```bash
# 1. 控制台扩容（自动）
# 2. growpart 扩展分区（手动）
# 3. xfs_growfs/resize2fs 扩展文件系统（手动）
```

### 反模式 3：不使用 nofail

```bash
# ❌ 错误：
UUID=xxxx  /data  xfs  defaults  0  2
#                       ^^^^^^^^
#                       缺少 nofail！

# 后果：
# 如果卷无法挂载，系统无法启动
```

**修复**：始终添加 nofail

```bash
# ✓ 正确：
UUID=xxxx  /data  xfs  defaults,nofail  0  2
```

### 反模式 4：在没有恢复计划的情况下修改关键配置

```bash
# ❌ 错误：
sudo vim /etc/fstab  # 直接编辑，没有备份
sudo visudo  # 直接编辑，没有 -c 检查
sudo vim /etc/ssh/sshd_config  # 没有 sshd -t 验证

# 后果：
# 语法错误导致实例"砖化"
# 需要救援实例恢复
```

**修复**：修改前必做

```bash
# 1. 创建快照
aws ec2 create-snapshot --volume-id vol-xxx

# 2. 备份文件
sudo cp /etc/fstab /etc/fstab.bak

# 3. 验证语法
sudo mount -a  # fstab
sudo visudo -c  # sudoers
sudo sshd -t  # sshd
```

---

## 职场小贴士（Japan IT Context）

### ディスク障害とストレージ拡張は運用基本

在日本 IT 现场，存储管理是基础设施运维的日常工作：

| 日语术语 | 读音 | 含义 | 使用场景 |
|----------|------|------|----------|
| ディスク容量 | ディスクようりょう | 磁盘容量 | "ディスク容量が不足しています" |
| ストレージ拡張 | ストレージかくちょう | 存储扩展 | "EBS の拡張作業を行います" |
| スナップショット | - | 快照 | "作業前にスナップショットを取得" |
| バックアップ | - | 备份 | "バックアップから復元" |
| 障害復旧 | しょうがいふっきゅう | 故障恢复 | "障害復旧手順を確認" |
| 証跡保全 | しょうせきほぜん | 证据保全 | "作業前に証跡を保全" |

### 証跡保全：扩容前快照

日本企业对**証跡保全**（证据保全）非常重视：

```
┌────────────────────────────────────────────────────────────────────────────┐
│                     EBS 扩容作業前のチェックリスト                           │
├────────────────────────────────────────────────────────────────────────────┤
│                                                                            │
│  1. 事前確認                                                               │
│     □ 現在のディスク使用量を記録（df -h の出力を保存）                     │
│     □ 拡張対象の EBS ボリューム ID を確認                                   │
│     □ 作業時間帯が変更管理で承認されていることを確認                       │
│                                                                            │
│  2. 証跡保全                                                               │
│     □ 作業前スナップショットを取得                                         │
│     □ スナップショット ID を作業記録に記載                                  │
│     □ 現在の lsblk 出力をキャプチャ                                        │
│                                                                            │
│  3. 作業実施                                                               │
│     □ AWS Console/CLI で EBS ボリュームを拡張                              │
│     □ growpart でパーティションを拡張                                      │
│     □ xfs_growfs/resize2fs でファイルシステムを拡張                        │
│                                                                            │
│  4. 事後確認                                                               │
│     □ df -h で拡張後の容量を確認                                           │
│     □ アプリケーションの動作確認                                           │
│     □ 作業完了報告を作成                                                   │
│                                                                            │
│  5. 作業記録                                                               │
│     □ 作業日時                                                             │
│     □ 作業者                                                               │
│     □ 変更内容（拡張前後のサイズ）                                         │
│     □ スナップショット ID                                                  │
│                                                                            │
└────────────────────────────────────────────────────────────────────────────┘
```

### 障害報告の書き方

存储相关故障报告示例：

```
【障害報告】
■ 発生日時：2025-01-10 09:30 JST
■ 影響範囲：アプリケーションサーバー停止
■ 原因：/etc/fstab の設定誤りにより起動失敗
■ 根本原因：UUID ではなくデバイス名を使用していたため、
           再起動時にデバイス名が変更され mount 失敗
■ 対応内容：
  1. 救援インスタンスを起動
  2. 問題のルートボリュームをアタッチ
  3. /etc/fstab を修正（デバイス名 → UUID）
  4. 元インスタンスを復旧
■ 復旧日時：2025-01-10 10:45 JST
■ 再発防止策：
  - fstab 変更時のレビュープロセス追加
  - UUID 使用を標準化
  - nofail オプションの必須化
```

---

## 检查清单

完成本课后，你应该能够：

- [ ] 解释 Instance Store 和 EBS 的区别
- [ ] 识别为什么 EBS 设备名会变化
- [ ] 执行完整的 EBS 扩容三步流程（卷→分区→文件系统）
- [ ] 使用 `lsblk` 诊断 "Phantom Storage" 问题
- [ ] 配置使用 UUID 和 nofail 的 fstab 条目
- [ ] 执行救援实例恢复流程
- [ ] 理解云环境独特的恢复手段（Serial Console、SSM、救援实例）
- [ ] 建立"修改关键配置前必须有恢复计划"的意识
- [ ] 掌握日本 IT 现场的存储运维术语

---

## 本课小结

| 概念 | 要点 |
|------|------|
| Instance Store vs EBS | Instance Store 临时、EBS 持久 |
| 设备命名 | NVMe 名可能变化，使用 UUID |
| EBS 扩容 | 三步：卷→分区→文件系统 |
| fstab | 使用 UUID + nofail |
| 救援实例 | 云环境的"单用户模式"替代 |
| 恢复手段 | Serial Console、SSM、救援实例、User Data |
| 预防措施 | 快照、语法验证、备用访问通道 |

---

## 延伸阅读

- [Amazon EBS 用户指南](https://docs.aws.amazon.com/ebs/latest/userguide/) - 官方 EBS 文档
- [Extend a Linux file system](https://docs.aws.amazon.com/ebs/latest/userguide/recognize-expanded-volume-linux.html) - EBS 扩容官方指南
- [EC2 Serial Console](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-serial-console.html) - Serial Console 配置
- 下一课：[06 - IAM 与实例配置文件](../06-iam-instance-profiles/) - 学习云凭证管理
- 前置课程：[LX07 - 存储管理](../../storage/) - Linux 存储基础

---

## 清理资源

本课实验可能创建了额外资源：

```bash
# 1. 删除测试快照
aws ec2 delete-snapshot --snapshot-id snap-xxx

# 2. 终止救援实例（如果创建了）
aws ec2 terminate-instances --instance-ids i-rescue-xxx

# 3. 清理测试挂载点
sudo umount /data
sudo rmdir /data

# 4. 清理 fstab 测试条目
sudo vim /etc/fstab
# 删除测试添加的条目

# 5. 验证清理完成
lsblk
df -h
cat /etc/fstab
```

---

## 系列导航

[← 04 - 云网络：Linux 视角](../04-cloud-networking/) | [系列首页](../) | [06 - IAM 与实例配置文件 →](../06-iam-instance-profiles/)
