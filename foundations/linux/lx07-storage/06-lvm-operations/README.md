# 06 - LVM 日常操作（LVM Operations）

> **目标**：掌握 LVM 扩展和管理的核心操作，避免最常见的新手陷阱  
> **前置**：完成 [05 - LVM 架构](../05-lvm-architecture/) 课程  
> **时间**：60-90 分钟  
> **实战场景**：磁盘扩容后 df -h 显示空间没变，用户投诉"扩容没生效"  

---

## 将学到的内容

1. 使用 pvcreate、vgcreate、lvcreate 创建 LVM 组件
2. 使用 lvextend 扩展逻辑卷（配合文件系统扩展）
3. 理解 lvreduce 的限制和风险（仅 ext4）
4. 掌握 VG 扩展（添加 PV 到现有 VG）

---

## LVM 扩展的 #1 陷阱

在深入学习之前，先看这个最常见的新手错误：

```bash
# 运维人员执行了 LVM 扩展
lvextend -L +10G /dev/vg_data/lv_app

# 检查结果
lvs
# 显示 LV 已经是 20G 了

# 但是用户报告...
df -h /app
# 还是显示 10G！"扩容没生效！"
```

**问题在哪？** LV（逻辑卷）扩展了，但文件系统没有扩展！

这是 LVM 操作的 **#1 新手陷阱**，本课将教你正确的做法。

---

## Step 1 -- LVM 创建流程回顾（10 分钟）

### 1.1 完整创建流程

上一课我们学习了 LVM 架构。先快速回顾创建流程：

```bash
# 准备：创建 loop 设备模拟磁盘
fallocate -l 2G /tmp/disk1.img
sudo losetup /dev/loop1 /tmp/disk1.img

# Step 1: 创建 Physical Volume (PV)
sudo pvcreate /dev/loop1

# Step 2: 创建 Volume Group (VG)
sudo vgcreate vg_lab /dev/loop1

# Step 3: 创建 Logical Volume (LV) - 使用 1G
sudo lvcreate -L 1G -n lv_data vg_lab

# Step 4: 创建文件系统
sudo mkfs.ext4 /dev/vg_lab/lv_data

# Step 5: 挂载
sudo mkdir -p /mnt/data
sudo mount /dev/vg_lab/lv_data /mnt/data

# 验证
df -h /mnt/data
```

### 1.2 查看 LVM 状态

```bash
# 三个查看命令
pvs    # Physical Volume 状态
vgs    # Volume Group 状态
lvs    # Logical Volume 状态

# 详细信息
pvdisplay /dev/loop1
vgdisplay vg_lab
lvdisplay /dev/vg_lab/lv_data
```

---

## Step 2 -- 正确的 LV 扩展方法（15 分钟）

### 2.1 推荐方法：lvextend -r

`-r` 参数（`--resizefs`）会自动调整文件系统大小：

```bash
# 推荐！一条命令完成 LV 和文件系统扩展
sudo lvextend -r -L +500M /dev/vg_lab/lv_data

# 验证：LV 和文件系统都扩展了
lvs
df -h /mnt/data
```

`-r` 参数会自动检测文件系统类型并调用相应的扩展命令：
- ext4 -> `resize2fs`
- XFS -> `xfs_growfs`

### 2.2 扩展选项

```bash
# 增加指定大小
lvextend -r -L +500M /dev/vg_lab/lv_data

# 扩展到指定大小
lvextend -r -L 2G /dev/vg_lab/lv_data

# 使用 VG 剩余空间的百分比
lvextend -r -l +50%FREE /dev/vg_lab/lv_data

# 使用 VG 全部剩余空间
lvextend -r -l +100%FREE /dev/vg_lab/lv_data
```

### 2.3 手动扩展文件系统（了解原理）

如果你需要分步操作：

```bash
# Step 1: 扩展 LV
sudo lvextend -L +500M /dev/vg_lab/lv_data

# Step 2: 扩展文件系统（根据类型选择）

# ext4 文件系统
sudo resize2fs /dev/vg_lab/lv_data

# XFS 文件系统（注意：使用挂载点！）
sudo xfs_growfs /mnt/data
```

> **关键区别**：  
> - `resize2fs` 使用设备路径：`/dev/vg_lab/lv_data`  
> - `xfs_growfs` 使用挂载点：`/mnt/data`  

---

## Step 3 -- 灾难实验：忘记扩展文件系统（20 分钟）

这是本课最重要的实验。我们故意重现这个错误，理解问题的本质。

### 3.1 场景设置

```bash
# 确认当前状态
lvs /dev/vg_lab/lv_data
df -h /mnt/data
```

记录当前 LV 大小和文件系统大小。

### 3.2 制造问题

```bash
# 只扩展 LV，不扩展文件系统（错误示范）
sudo lvextend -L +200M /dev/vg_lab/lv_data

# 检查 LV - 已经扩展了！
lvs /dev/vg_lab/lv_data
# LSize 增加了 200M

# 检查文件系统 - 没有变化！
df -h /mnt/data
# Size 还是原来的大小！
```

### 3.3 诊断问题

这就是用户报告"扩容没生效"的原因：

```
┌─────────────────────────────────────────────────────────────┐
│                     Logical Volume                          │
│  ┌────────────────────────────┐ ┌─────────────────────────┐│
│  │      Filesystem            │ │    Unused Space         ││
│  │      (原大小)              │ │    (新增 200M)          ││
│  │      df -h 能看到          │ │    df -h 看不到！       ││
│  └────────────────────────────┘ └─────────────────────────┘│
└─────────────────────────────────────────────────────────────┘
```

LV 是容器，文件系统是内容。扩大了容器，内容没有填满新空间。

### 3.4 修复问题

```bash
# ext4 文件系统
sudo resize2fs /dev/vg_lab/lv_data

# 再次检查
df -h /mnt/data
# 现在大小正确了！
```

### 3.5 实验心得

| lvs 显示 | df -h 显示 | 状态 | 修复 |
|----------|------------|------|------|
| 新大小 | 新大小 | 正常 | - |
| 新大小 | 旧大小 | 忘记扩展 FS | resize2fs / xfs_growfs |
| 旧大小 | 旧大小 | LV 扩展失败 | 检查 VG 空间 |

---

## Step 4 -- 扩展 VG：添加新磁盘（15 分钟）

当 VG 空间不足时，需要添加新的 PV。

### 4.1 场景：VG 空间不足

```bash
# 查看 VG 剩余空间
vgs vg_lab
# VFree 列显示剩余空间

# 如果 VFree 接近 0，需要扩展 VG
```

### 4.2 添加新 PV 到 VG

```bash
# 创建新的模拟磁盘
fallocate -l 1G /tmp/disk2.img
sudo losetup /dev/loop2 /tmp/disk2.img

# 将新磁盘初始化为 PV
sudo pvcreate /dev/loop2

# 将 PV 添加到现有 VG
sudo vgextend vg_lab /dev/loop2

# 验证
vgs vg_lab
# VFree 增加了！

pvs
# 可以看到两个 PV 都属于 vg_lab
```

### 4.3 真实场景：云服务器扩容

在 AWS、Azure 等云环境中：

```bash
# 1. 在云控制台扩展 EBS/Disk 大小（例如从 20G 到 50G）

# 2. 让系统识别新大小
sudo growpart /dev/xvda 2    # 扩展分区

# 3. 扩展 PV
sudo pvresize /dev/xvda2

# 4. 扩展 LV + 文件系统
sudo lvextend -r -l +100%FREE /dev/vg/lv_root
```

---

## Step 5 -- LV 收缩：危险操作（10 分钟）

### 5.1 关键限制

| 文件系统 | 支持收缩 | 说明 |
|----------|----------|------|
| ext4 | 是 | 需要先收缩 FS，再收缩 LV |
| XFS | **否** | XFS 设计上不支持收缩 |
| Btrfs | 是 | 原生支持 |

### 5.2 ext4 收缩流程（高风险）

```bash
# 警告：收缩操作有数据丢失风险！务必先备份！

# 1. 卸载文件系统
sudo umount /mnt/data

# 2. 检查文件系统
sudo e2fsck -f /dev/vg_lab/lv_data

# 3. 收缩文件系统到目标大小
sudo resize2fs /dev/vg_lab/lv_data 500M

# 4. 收缩 LV
sudo lvreduce -L 500M /dev/vg_lab/lv_data

# 5. 重新挂载
sudo mount /dev/vg_lab/lv_data /mnt/data
```

> **警告**：如果收缩 LV 比文件系统更小，会导致数据损坏！  

### 5.3 为什么 XFS 不支持收缩？

XFS 的设计哲学是"只增不减"。如果需要减小 XFS 卷：
1. 备份数据
2. 删除 LV
3. 创建更小的 LV
4. 恢复数据

> **日本 IT 运维实践**：生产环境中很少执行收缩操作。通常是在容量规划阶段避免过度分配，或者接受现有大小。  

---

## 职场小贴士（Japan IT Context）

### 变更管理术语

| 日语术语 | 含义 | 场景 |
|----------|------|------|
| ストレージ拡張 | 存储扩展 | LVM extend 操作 |
| 容量拡張申請 | 容量扩展申请 | 变更管理流程 |
| 作業手順書 | 操作手顺书 | 执行步骤文档 |
| 変更管理 | 变更管理 | 生产环境变更审批 |

### 面试常见问题

**Q: LVM の拡張で、df コマンドの表示が変わらない場合の原因は？**

A: LV（論理ボリューム）は拡張されましたが、ファイルシステムの拡張が漏れている可能性があります。ext4 なら `resize2fs`、XFS なら `xfs_growfs` でファイルシステムを拡張する必要があります。`lvextend -r` オプションを使えば、両方を同時に実行できます。

**Q: XFS で LV を縮小できますか？**

A: いいえ、XFS はファイルシステムの縮小をサポートしていません。縮小が必要な場合は、データのバックアップ、LV の再作成、データの復元が必要です。

### 作業手順書の重要ポイント

1. **事前確認**：現在の LV/FS サイズを記録
2. **拡張実行**：`lvextend -r` を使用（FS 拡張も同時に）
3. **事後確認**：`lvs` と `df -h` 両方で確認
4. **ロールバック手順**：縮小は非推奨、事前に容量計画を

---

## 本課小結

| 操作 | コマンド | 注意点 |
|------|----------|--------|
| LV 扩展（推荐） | `lvextend -r -L +SIZE` | -r 自动扩展文件系统 |
| 手动扩展 ext4 | `resize2fs /dev/path` | 需要设备路径 |
| 手动扩展 XFS | `xfs_growfs /mount` | 需要挂载点 |
| VG 扩展 | `vgextend vg pv` | 先 pvcreate 新 PV |
| LV 收缩 | `lvreduce -L SIZE` | ext4 only, 高风险 |

**核心要点**：永远使用 `lvextend -r`，避免忘记扩展文件系统的陷阱。

---

## 检查清单

完成本课后，确认你能够：

- [ ] 使用 `lvextend -r` 扩展 LV 和文件系统
- [ ] 解释为什么 `lvs` 和 `df -h` 显示不同大小
- [ ] 使用 `resize2fs` 或 `xfs_growfs` 手动扩展文件系统
- [ ] 使用 `vgextend` 向 VG 添加新 PV
- [ ] 说明 XFS 不支持收缩的原因
- [ ] 重现并修复"LVM 扩展顺序错误"问题

---

## 实验清理

```bash
# 卸载文件系统
sudo umount /mnt/data

# 删除 LV
sudo lvremove -f /dev/vg_lab/lv_data

# 删除 VG
sudo vgremove vg_lab

# 删除 PV
sudo pvremove /dev/loop1 /dev/loop2

# 释放 loop 设备
sudo losetup -d /dev/loop1 /dev/loop2 2>/dev/null

# 删除模拟磁盘文件
rm -f /tmp/disk1.img /tmp/disk2.img
```

---

## 延伸阅读

- [Red Hat: Extending Logical Volumes](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/8/html/configuring_and_managing_logical_volumes/modifying-the-size-of-a-logical-volume_configuring-and-managing-logical-volumes)
- [lvextend man page](https://man7.org/linux/man-pages/man8/lvextend.8.html)
- [resize2fs man page](https://man7.org/linux/man-pages/man8/resize2fs.8.html)
- 上一课：[05 - LVM 架构](../05-lvm-architecture/) -- 理解 PV/VG/LV 三层架构
- 下一课：[07 - LVM 快照](../07-lvm-snapshots/) -- Copy-on-Write 原理与应用

---

## 系列导航

[<-- 05 - LVM 架构](../05-lvm-architecture/) | [系列首页](../) | [07 - LVM 快照 -->](../07-lvm-snapshots/)
