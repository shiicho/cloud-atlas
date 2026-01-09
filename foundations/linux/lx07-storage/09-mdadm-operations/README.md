# 09 - mdadm 实战（Software RAID with mdadm）

> **目标**：掌握软件 RAID 的创建、监控和故障恢复，能够独立处理 RAID 降级状态  
> **前置**：完成 [08 - RAID 概念](../08-raid-concepts/) 课程  
> **时间**：90-120 分钟  
> **实战场景**：凌晨 3 点收到告警，/proc/mdstat 显示 [U_]，需要紧急处理 RAID 降级  

---

## 将学到的内容

1. 使用 mdadm 创建软件 RAID 阵列
2. 监控 RAID 状态（/proc/mdstat、mdadm --detail）
3. 处理 RAID 降级状态和磁盘更换
4. 配置 RAID 持久化（mdadm.conf）

---

## 实验环境准备

本课使用 loop 设备模拟多磁盘环境。在任何 Linux 系统上都可以完成：

```bash
# 创建 3 个虚拟磁盘（1GB 每个）
for i in 1 2 3; do
  fallocate -l 1G /tmp/disk$i.img
  sudo losetup /dev/loop$i /tmp/disk$i.img
done

# 验证
lsblk /dev/loop1 /dev/loop2 /dev/loop3
```

> **说明**：loop3 将作为 hot spare（热备盘）使用。  

---

## Step 1 -- 创建 RAID 1 阵列（20 分钟）

### 1.1 使用 mdadm 创建 RAID 1

RAID 1（镜像）是最简单、最可靠的冗余方案：

```bash
# 创建 RAID 1 阵列，使用 loop1 和 loop2
sudo mdadm --create /dev/md0 \
  --level=1 \
  --raid-devices=2 \
  /dev/loop1 /dev/loop2

# 确认创建
# 系统会提示: Continue creating array? 输入 y
```

**参数解释**：

| 参数 | 含义 |
|------|------|
| `--create /dev/md0` | 创建名为 md0 的 RAID 设备 |
| `--level=1` | RAID 级别 1（镜像） |
| `--raid-devices=2` | 使用 2 个设备 |

### 1.2 验证 RAID 状态

```bash
# 查看 RAID 状态（最常用）
cat /proc/mdstat
```

输出示例：

```
Personalities : [raid1]
md0 : active raid1 loop2[1] loop1[0]
      1046528 blocks super 1.2 [2/2] [UU]
      [========>............]  resync = 42.0% (439296/1046528)
```

**关键指标解读**：

| 指标 | 含义 |
|------|------|
| `[2/2]` | 期望 2 个设备 / 实际 2 个正常 |
| `[UU]` | 两个设备都 Up（正常） |
| `[U_]` | 第二个设备故障（降级） |
| `resync` | 初始同步进度 |

### 1.3 等待同步完成

```bash
# 监控同步进度
watch -n 1 cat /proc/mdstat
```

同步完成后显示：

```
md0 : active raid1 loop2[1] loop1[0]
      1046528 blocks super 1.2 [2/2] [UU]
```

### 1.4 格式化和挂载

```bash
# 创建文件系统
sudo mkfs.ext4 /dev/md0

# 创建挂载点并挂载
sudo mkdir -p /mnt/raid
sudo mount /dev/md0 /mnt/raid

# 验证
df -h /mnt/raid
```

---

## Step 2 -- RAID 状态监控（15 分钟）

### 2.1 /proc/mdstat 详解

`/proc/mdstat` 是 RAID 状态的实时快照：

```bash
cat /proc/mdstat
```

```
Personalities : [raid1]
md0 : active raid1 loop2[1] loop1[0]
      1046528 blocks super 1.2 [2/2] [UU]

unused devices: <none>
```

**状态标记详解**：

| 标记 | 状态 | 含义 |
|------|------|------|
| `[UU]` | 正常 | 所有设备健康 |
| `[U_]` | 降级 | 第 2 个设备故障 |
| `[_U]` | 降级 | 第 1 个设备故障 |
| `[__]` | 危险 | 所有设备故障 |

### 2.2 mdadm --detail 详细信息

```bash
sudo mdadm --detail /dev/md0
```

输出示例：

```
/dev/md0:
           Version : 1.2
     Creation Time : Sat Jan  4 10:30:00 2026
        Raid Level : raid1
        Array Size : 1046528 (1022.00 MiB 1071.64 MB)
     Used Dev Size : 1046528 (1022.00 MiB 1071.64 MB)
      Raid Devices : 2
     Total Devices : 2
       Persistence : Superblock is persistent

             State : clean
    Active Devices : 2
   Working Devices : 2
    Failed Devices : 0
     Spare Devices : 0

    Number   Major   Minor   RaidDevice State
       0       7        1        0      active sync   /dev/loop1
       1       7        2        1      active sync   /dev/loop2
```

**重点关注**：

| 字段 | 正常值 | 告警值 |
|------|--------|--------|
| State | clean | degraded, recovering |
| Active Devices | = Raid Devices | < Raid Devices |
| Failed Devices | 0 | > 0 |

### 2.3 监控脚本示例

```bash
#!/bin/bash
# raid-check.sh - RAID 状态检查脚本

if grep -q '\[U_\]\|\_U\]' /proc/mdstat; then
  echo "警告: RAID 处于降级状态!"
  cat /proc/mdstat
  exit 1
fi

echo "RAID 状态正常"
cat /proc/mdstat
```

---

## Step 3 -- mdadm.conf 持久化配置（15 分钟）

### 3.1 为什么需要 mdadm.conf？

系统重启后，RAID 阵列需要重新组装。mdadm.conf 告诉系统：
- 有哪些 RAID 阵列
- 每个阵列由哪些设备组成
- 阵列应该自动组装

### 3.2 生成配置

```bash
# 扫描现有 RAID 阵列
sudo mdadm --detail --scan

# 输出示例：
# ARRAY /dev/md0 metadata=1.2 name=hostname:0 UUID=xxxxxxxx:xxxxxxxx:xxxxxxxx:xxxxxxxx

# 追加到 mdadm.conf
sudo mdadm --detail --scan >> /etc/mdadm/mdadm.conf
# 或者（取决于发行版）
sudo mdadm --detail --scan >> /etc/mdadm.conf
```

### 3.3 mdadm.conf 格式

```bash
# /etc/mdadm/mdadm.conf (Debian/Ubuntu)
# /etc/mdadm.conf (RHEL/CentOS)

# 邮件通知地址
MAILADDR root@localhost

# RAID 阵列定义
ARRAY /dev/md0 metadata=1.2 UUID=xxxxxxxx:xxxxxxxx:xxxxxxxx:xxxxxxxx
```

### 3.4 更新 initramfs

配置更改后需要更新启动镜像：

```bash
# Debian/Ubuntu
sudo update-initramfs -u

# RHEL/CentOS
sudo dracut -f
```

> **重要**：不更新 initramfs，重启后 RAID 可能无法自动组装！  

---

## Step 4 -- 灾难实验：RAID 降级恢复（30 分钟）

这是本课最重要的实验。我们将模拟真实的磁盘故障场景。

### 4.1 场景描述

**凌晨 3 点告警**：
```
[ALERT] RAID degraded on server-prod-01
/proc/mdstat shows [U_]
```

在日本 IT 运维中，这属于 P1（最高优先级）障害。

### 4.2 模拟磁盘故障

```bash
# 先确认当前状态正常
cat /proc/mdstat
# 应该显示 [UU]

# 模拟 loop2 故障
sudo mdadm --manage /dev/md0 --fail /dev/loop2

# 检查状态
cat /proc/mdstat
```

**你会看到**：

```
md0 : active raid1 loop2[1](F) loop1[0]
      1046528 blocks super 1.2 [2/1] [U_]
```

关键变化：
- `[2/1]` - 期望 2 个，只有 1 个正常
- `[U_]` - 第二个设备故障
- `(F)` - Failed 标记

### 4.3 确认故障详情

```bash
sudo mdadm --detail /dev/md0
```

```
             State : clean, degraded
    Active Devices : 1
   Working Devices : 1
    Failed Devices : 1
     Spare Devices : 0

    Number   Major   Minor   RaidDevice State
       0       7        1        0      active sync   /dev/loop1
       -       0        0        1      removed
       1       7        2        -      faulty   /dev/loop2
```

### 4.4 移除故障磁盘

```bash
# 从阵列移除故障磁盘
sudo mdadm --manage /dev/md0 --remove /dev/loop2

# 确认移除
cat /proc/mdstat
sudo mdadm --detail /dev/md0
```

### 4.5 添加新磁盘

在生产环境中，这一步是更换物理磁盘后执行。我们用 loop3 模拟新磁盘：

```bash
# 添加新磁盘到阵列
sudo mdadm --manage /dev/md0 --add /dev/loop3

# 立即检查状态
cat /proc/mdstat
```

你会看到重建过程：

```
md0 : active raid1 loop3[2] loop1[0]
      1046528 blocks super 1.2 [2/1] [U_]
      [======>.............]  recovery = 35.2% (368640/1046528) finish=0.2min speed=46080K/sec
```

### 4.6 监控重建进度

```bash
# 实时监控
watch -n 1 cat /proc/mdstat
```

重建完成后：

```
md0 : active raid1 loop3[2] loop1[0]
      1046528 blocks super 1.2 [2/2] [UU]
```

### 4.7 完整恢复流程总结

```
故障发现
    │
    ▼
┌─────────────────────────────────────┐
│ cat /proc/mdstat                    │
│ 确认 [U_] 降级状态                  │
└──────────────┬──────────────────────┘
               │
               ▼
┌─────────────────────────────────────┐
│ mdadm --detail /dev/mdX             │
│ 识别故障磁盘                        │
└──────────────┬──────────────────────┘
               │
               ▼
┌─────────────────────────────────────┐
│ mdadm --manage --fail --remove      │
│ 标记并移除故障盘                    │
└──────────────┬──────────────────────┘
               │
               ▼
┌─────────────────────────────────────┐
│ （物理更换磁盘）                    │
│ 分区与旧盘一致                      │
└──────────────┬──────────────────────┘
               │
               ▼
┌─────────────────────────────────────┐
│ mdadm --manage --add /dev/newdisk   │
│ 添加新盘，触发重建                  │
└──────────────┬──────────────────────┘
               │
               ▼
┌─────────────────────────────────────┐
│ watch cat /proc/mdstat              │
│ 监控重建进度至 [UU]                 │
└─────────────────────────────────────┘
```

---

## Step 5 -- Hot Spare 配置（15 分钟）

### 5.1 什么是 Hot Spare？

Hot Spare（热备盘）是阵列中的备用磁盘：
- 平时不存储数据
- 当成员盘故障时自动接替
- 大幅缩短恢复时间

### 5.2 添加 Hot Spare

```bash
# 先创建一个新的 loop 设备作为热备
fallocate -l 1G /tmp/disk4.img
sudo losetup /dev/loop4 /tmp/disk4.img

# 添加为 spare
sudo mdadm --manage /dev/md0 --add-spare /dev/loop4

# 或者直接 --add，系统会自动判断角色
sudo mdadm --manage /dev/md0 --add /dev/loop4
```

### 5.3 验证 Hot Spare

```bash
sudo mdadm --detail /dev/md0
```

```
             State : clean
     Spare Devices : 1

    Number   Major   Minor   RaidDevice State
       0       7        1        0      active sync   /dev/loop1
       2       7        3        1      active sync   /dev/loop3
       3       7        4        -      spare   /dev/loop4
```

### 5.4 测试自动重建

```bash
# 模拟 loop1 故障
sudo mdadm --manage /dev/md0 --fail /dev/loop1

# 立即检查
cat /proc/mdstat
```

你会看到 Hot Spare 自动开始重建：

```
md0 : active raid1 loop4[3] loop3[2] loop1[0](F)
      1046528 blocks super 1.2 [2/1] [_U]
      [=>...................]  recovery =  8.0% (83968/1046528) finish=0.4min
```

loop4（热备盘）自动加入重建！

---

## 反模式：没有配置热备盘

### 问题场景

```
时间线：
00:00  磁盘 A 故障，RAID 降级 [U_]
00:15  收到告警
02:00  运维人员到场
02:30  新磁盘到货
03:00  更换完成，开始重建
06:00  重建完成

风险窗口：6 小时处于降级状态
如果此期间第二块盘故障 = 数据全部丢失
```

### 正确做法

```
时间线：
00:00  磁盘 A 故障，RAID 降级 [U_]
00:01  Hot Spare 自动接替，开始重建
03:00  重建完成，恢复 [UU]

次日：补充新的热备盘
```

> **日本 IT 运维实践**：生产环境的 RAID 5/6/10 阵列通常配置至少 1 个热备盘。  
> 这是 SLA（服务等级协议）的要求。  

---

## 职场小贴士（Japan IT Context）

### 障害対応術語

| 日语术语 | 含义 | 场景 |
|----------|------|------|
| RAID 縮退 | RAID degraded | [U_] 状态 |
| ディスク障害 | 磁盘故障 | 需要更换硬件 |
| ホットスペア | Hot spare | 热备盘 |
| リビルド | Rebuild | 重建过程 |
| 障害一次対応 | 初步故障响应 | 确认状态、上报 |

### 面试常见问题

**Q: RAID が縮退状態になった場合、どう対応しますか？**

A: まず `/proc/mdstat` と `mdadm --detail` で状態を確認します。障害ディスクを特定し、`mdadm --fail --remove` で安全に取り外します。新しいディスクを同じパーティション構成で準備し、`mdadm --add` で追加します。`/proc/mdstat` でリビルド進捗を監視し、完了後に `mdadm.conf` を更新して `update-initramfs` を実行します。

**Q: ホットスペアの重要性を説明してください。**

A: ホットスペアはダウンタイムを大幅に削減します。ディスク障害発生時、人間が対応する前に自動でリビルドを開始するため、二次障害のリスク窓口を最小化できます。特に深夜や休日の障害対応では、ホットスペアが SLA 維持の鍵となります。

---

## 本课小结

| 操作 | コマンド | 用途 |
|------|----------|------|
| 创建 RAID | `mdadm --create` | 初始化阵列 |
| 查看状态 | `cat /proc/mdstat` | 快速状态检查 |
| 详细信息 | `mdadm --detail` | 故障诊断 |
| 标记故障 | `mdadm --fail` | 故障处理第一步 |
| 移除磁盘 | `mdadm --remove` | 安全移除故障盘 |
| 添加磁盘 | `mdadm --add` | 添加新盘/热备 |
| 持久化 | `mdadm --detail --scan` | 更新 mdadm.conf |

**核心要点**：

1. `[UU]` = 正常，`[U_]` = 降级，需要立即处理
2. 恢复流程：fail -> remove -> add -> 监控重建
3. 生产环境务必配置 hot spare
4. 每次变更后更新 mdadm.conf 和 initramfs

---

## 检查清单

完成本课后，确认你能够：

- [ ] 使用 `mdadm --create` 创建 RAID 1 阵列
- [ ] 读懂 `/proc/mdstat` 的状态标记（[UU] vs [U_]）
- [ ] 使用 `mdadm --detail` 诊断 RAID 问题
- [ ] 完成 RAID 降级恢复全流程（fail, remove, add）
- [ ] 配置 mdadm.conf 实现持久化
- [ ] 解释 hot spare 的作用和配置方法
- [ ] 监控 RAID 重建进度

---

## 实验清理

```bash
# 卸载文件系统
sudo umount /mnt/raid

# 停止 RAID 阵列
sudo mdadm --stop /dev/md0

# 清除 RAID 超级块
sudo mdadm --zero-superblock /dev/loop1 /dev/loop2 /dev/loop3 /dev/loop4 2>/dev/null

# 释放 loop 设备
for i in 1 2 3 4; do
  sudo losetup -d /dev/loop$i 2>/dev/null
done

# 删除模拟磁盘文件
rm -f /tmp/disk{1,2,3,4}.img
```

---

## 延伸阅读

- [mdadm man page](https://man7.org/linux/man-pages/man8/mdadm.8.html)
- [Linux RAID Wiki](https://raid.wiki.kernel.org/)
- [Red Hat: Managing RAID](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/8/html/managing_storage_devices/managing-raid_managing-storage-devices)
- 上一课：[08 - RAID 概念](../08-raid-concepts/) -- RAID 级别选择与原理
- 下一课：[10 - 备份策略](../10-backup-strategies/) -- tar, rsync 与 3-2-1 规则

---

## 系列导航

[<-- 08 - RAID 概念](../08-raid-concepts/) | [系列首页](../) | [10 - 备份策略 -->](../10-backup-strategies/)
