# 11 - 文件系统维护（Filesystem Maintenance and Repair）

> **目标**：掌握文件系统检查修复工具，能够诊断和解决常见存储故障  
> **前置**：完成 [10 - 备份策略](../10-backup-strategies/) 课程  
> **时间**：⚡ 25 分钟（速读）/ 🔬 90 分钟（完整实操）  
> **实战场景**：三个真实灾难场景——Ghost Capacity、Inode 耗尽、XFS 损坏  

---

## 将学到的内容

1. 使用 fsck 检查修复 ext4 文件系统
2. 使用 xfs_repair 修复 XFS 文件系统
3. 诊断和解决 inode 耗尽问题
4. 处理"删除文件空间不释放"问题

---

## 核心工具速查

| 文件系统 | 检查工具 | 修复工具 | 关键注意 |
|----------|----------|----------|----------|
| ext2/3/4 | `fsck.ext4` | `fsck.ext4 -y` | 必须 unmount |
| XFS | `xfs_repair -n` | `xfs_repair` | 不是 fsck！ |

---

## Step 1 -- fsck：ext4 文件系统检查（20 分钟）

### 1.1 fsck 基础

`fsck`（File System Check）是 ext 系列文件系统的检查修复工具：

```bash
# 检查文件系统类型
lsblk -f

# 示例输出
NAME   FSTYPE  LABEL UUID                                 MOUNTPOINT
loop1  ext4          a1b2c3d4-5678-90ab-cdef-1234567890ab /mnt/data
loop2  xfs           x1y2z3a4-5678-90ab-cdef-0987654321fe /mnt/xfs
```

### 1.2 安全检查（只读模式）

```bash
# 创建实验环境
fallocate -l 500M /tmp/ext4disk.img
sudo losetup /dev/loop10 /tmp/ext4disk.img
sudo mkfs.ext4 /dev/loop10
sudo mkdir -p /mnt/testfs
sudo mount /dev/loop10 /mnt/testfs

# 写入测试数据
sudo touch /mnt/testfs/important_file.txt
```

**重要**：必须先 unmount 再运行 fsck：

```bash
# 卸载文件系统
sudo umount /mnt/testfs

# 安全检查（-n = 只读，不修改）
sudo fsck.ext4 -n /dev/loop10
```

输出示例：

```
e2fsck 1.46.5 (30-Dec-2021)
/dev/loop10: clean, 12/32768 files, 6544/131072 blocks
```

### 1.3 交互式修复

```bash
# 交互式修复（每个问题询问）
sudo fsck.ext4 /dev/loop10

# 自动修复（生产环境常用）
sudo fsck.ext4 -y /dev/loop10
```

**参数说明**：

| 参数 | 含义 |
|------|------|
| `-n` | 只读检查，不修改 |
| `-y` | 对所有问题回答 yes |
| `-f` | 强制检查（即使 clean） |
| `-p` | 自动修复安全问题 |

---

## Step 2 -- xfs_repair：XFS 文件系统修复（20 分钟）

### 2.1 XFS 使用 xfs_repair，不是 fsck

**这是常见错误**：对 XFS 分区运行 fsck 没有效果：

```bash
# 错误做法（无效！）
sudo fsck /dev/xfs_partition
# 输出: fsck.xfs does not exist

# 正确做法
sudo xfs_repair /dev/xfs_partition
```

### 2.2 创建 XFS 实验环境

```bash
# 创建 XFS 文件系统
fallocate -l 500M /tmp/xfsdisk.img
sudo losetup /dev/loop11 /tmp/xfsdisk.img
sudo mkfs.xfs /dev/loop11
sudo mkdir -p /mnt/xfstest
sudo mount /dev/loop11 /mnt/xfstest

# 写入数据
sudo touch /mnt/xfstest/test_file.txt
```

### 2.3 xfs_repair 使用

```bash
# 必须先卸载
sudo umount /mnt/xfstest

# 干运行（不修改）
sudo xfs_repair -n /dev/loop11

# 实际修复
sudo xfs_repair /dev/loop11
```

### 2.4 强制修复（日志损坏时）

当遇到 "log is not empty" 错误：

```bash
# 先尝试挂载让日志回放
sudo mount /dev/loop11 /mnt/xfstest
sudo umount /mnt/xfstest

# 如果挂载失败，强制清除日志（最后手段！）
sudo xfs_repair -L /dev/loop11
```

> **警告**：`-L` 参数会丢弃日志中未完成的事务，可能导致数据丢失。只在无法挂载时使用。  

---

## Step 3 -- 灾难实验 1：Ghost Capacity（25 分钟）

这是日本 IT 运维中经典的"幽灵容量"问题。

### 3.1 场景描述

**凌晨告警**：

```
[ALERT] Disk usage 100% on /var
但是 du -sh /var/* 只显示 40% 使用
```

df 和 du 的结果不一致——这就是 Ghost Capacity。

### 3.2 模拟问题

```bash
# 创建模拟环境
fallocate -l 200M /tmp/ghostdisk.img
sudo losetup /dev/loop12 /tmp/ghostdisk.img
sudo mkfs.ext4 /dev/loop12
sudo mkdir -p /mnt/ghost
sudo mount /dev/loop12 /mnt/ghost

# 创建一个"日志文件"
sudo dd if=/dev/zero of=/mnt/ghost/application.log bs=1M count=50

# 检查使用情况
df -h /mnt/ghost
```

现在模拟应用程序持有文件句柄：

```bash
# 在后台打开文件（模拟应用进程）
sudo tail -f /mnt/ghost/application.log &
TAIL_PID=$!

# 删除文件
sudo rm /mnt/ghost/application.log

# 检查：文件删除了，但空间没释放！
df -h /mnt/ghost
du -sh /mnt/ghost
```

**你会看到**：
- `df -h` 显示仍占用 50MB
- `du -sh` 显示几乎为空

### 3.3 诊断方法

```bash
# 关键命令：查找已删除但未释放的文件
sudo lsof +L1

# 或者更精确地过滤
sudo lsof | grep deleted
```

输出示例：

```
COMMAND   PID USER   FD   TYPE DEVICE SIZE/OFF   NLINK NODE NAME
tail    12345 root    3r   REG  7,12  52428800       0  123 /mnt/ghost/application.log (deleted)
```

关键信息：
- `NLINK=0`：硬链接数为 0（已删除）
- `(deleted)`：文件标记为已删除
- `SIZE/OFF`：仍占用的空间

### 3.4 解决方法

```bash
# 方法 1：重启持有句柄的进程
sudo kill $TAIL_PID

# 验证空间释放
df -h /mnt/ghost
```

**生产环境建议**：

```bash
# 识别进程后，优雅重启
sudo systemctl restart application-service

# 而不是直接 kill
```

### 3.5 预防措施

```bash
# 监控脚本示例
#!/bin/bash
# ghost-capacity-check.sh

DELETED_SIZE=$(sudo lsof +L1 2>/dev/null | awk '{sum+=$7} END {print sum/1024/1024}')
if (( $(echo "$DELETED_SIZE > 1000" | bc -l) )); then
  echo "警告: ${DELETED_SIZE}MB 空间被已删除文件占用"
  sudo lsof +L1
fi
```

---

## Step 4 -- 灾难实验 2：Inode 耗尽（25 分钟）

### 4.1 场景描述

**用户报告**：

```
"磁盘还有 50% 空间，但无法创建新文件"
touch: cannot touch 'test': No space left on device
```

### 4.2 模拟问题

```bash
# 创建小文件系统（inode 数量有限）
fallocate -l 50M /tmp/inodedisk.img
sudo losetup /dev/loop13 /tmp/inodedisk.img
# 创建时指定较少的 inode
sudo mkfs.ext4 -N 100 /dev/loop13
sudo mkdir -p /mnt/inode
sudo mount /dev/loop13 /mnt/inode

# 查看 inode 情况
df -i /mnt/inode
```

```
Filesystem     Inodes IUsed IFree IUse% Mounted on
/dev/loop13       100    11    89   11% /mnt/inode
```

现在耗尽 inode：

```bash
# 创建大量空文件
cd /mnt/inode
sudo mkdir lots_of_files
cd lots_of_files
for i in $(seq 1 100); do sudo touch file_$i 2>/dev/null; done

# 尝试创建新文件
sudo touch /mnt/inode/newfile
```

错误输出：

```
touch: cannot touch '/mnt/inode/newfile': No space left on device
```

### 4.3 诊断方法

```bash
# 关键命令：查看 inode 使用情况
df -i /mnt/inode
```

```
Filesystem     Inodes IUsed IFree IUse% Mounted on
/dev/loop13       100   100     0  100% /mnt/inode
```

- `IUse% = 100%`：inode 耗尽
- 但 `df -h` 可能显示还有大量空间

**找出问题目录**：

```bash
# 统计每个目录的文件数
sudo find /mnt/inode -xdev -type f | cut -d'/' -f4 | sort | uniq -c | sort -rn | head
```

### 4.4 解决方法

```bash
# 方法 1：删除不需要的文件
sudo rm -rf /mnt/inode/lots_of_files

# 验证
df -i /mnt/inode
sudo touch /mnt/inode/newfile
```

**常见 inode 耗尽原因**：

| 原因 | 典型路径 | 解决方案 |
|------|----------|----------|
| Session 文件 | `/var/lib/php/sessions` | 配置定期清理 |
| 缓存文件 | `/tmp`, `/var/cache` | 清理或增大分区 |
| 邮件队列 | `/var/spool/mail` | 处理积压邮件 |
| 小日志文件 | `/var/log` | 配置 logrotate |

---

## Step 5 -- 灾难实验 3：XFS 损坏恢复（20 分钟）

### 5.1 场景描述

**服务器重启后**：

```
mount: /dev/sdb1: mount(2) system call failed: Structure needs cleaning.
```

这通常发生在非正常关机后。

### 5.2 模拟问题

```bash
# 使用之前的 XFS 环境
sudo mount /dev/loop11 /mnt/xfstest

# 写入数据
sudo dd if=/dev/urandom of=/mnt/xfstest/data.bin bs=1M count=10

# 模拟非正常关机（强制断开）
# 警告：这会造成数据不一致
echo 1 | sudo tee /proc/sys/vm/drop_caches
sudo losetup -d /dev/loop11
```

### 5.3 恢复流程

```bash
# 重新关联设备
sudo losetup /dev/loop11 /tmp/xfsdisk.img

# 尝试挂载（可能失败）
sudo mount /dev/loop11 /mnt/xfstest 2>&1 || echo "挂载失败，需要修复"
```

**标准恢复流程**：

```bash
# 1. 首先尝试挂载让日志回放
sudo mount /dev/loop11 /mnt/xfstest

# 2. 如果成功，卸载后检查
sudo umount /mnt/xfstest
sudo xfs_repair -n /dev/loop11

# 3. 如果挂载失败，直接修复
sudo xfs_repair /dev/loop11

# 4. 最后手段：清除日志（可能丢失数据）
sudo xfs_repair -L /dev/loop11
```

### 5.4 修复后验证

```bash
# 挂载并验证
sudo mount /dev/loop11 /mnt/xfstest
ls -la /mnt/xfstest

# 检查文件系统健康
xfs_info /dev/loop11
```

---

## 反模式警告

### 反模式 1：在挂载状态下运行 fsck

```bash
# 危险！可能导致数据损坏
sudo fsck /dev/sda1  # 如果 sda1 已挂载

# 正确做法
sudo umount /dev/sda1
sudo fsck /dev/sda1
```

### 反模式 2：对 XFS 使用 fsck

```bash
# 无效！fsck.xfs 不存在
sudo fsck /dev/xfs_partition

# 正确做法
sudo xfs_repair /dev/xfs_partition
```

### 反模式 3：忽略 df 和 du 不一致

```bash
# 发现不一致时
df -h /var     # 显示 95%
du -sh /var/*  # 总和只有 40%

# 不要忽略！立即检查
sudo lsof +L1
```

---

## 职场小贴士（Japan IT Context）

### 障害対応術語

| 日语术语 | 含义 | 使用场景 |
|----------|------|----------|
| ファイルシステム破損 | 文件系统损坏 | 需要 fsck/xfs_repair |
| inode 枯渇 | inode 耗尽 | df -i 检查 |
| ゴースト容量 | Ghost capacity | lsof 诊断 |
| 復旧作業 | 恢复操作 | 故障修复过程 |

### 面试常见问题

**Q: df と du の結果が異なる場合、どう調査しますか？**

A: まず `lsof +L1` で削除済みだがプロセスが保持しているファイルを確認します。該当プロセスを特定し、安全に再起動することで空間を解放します。根本対策として、ログローテーションの設定や監視の追加を検討します。

**Q: fsck と xfs_repair の違いは？**

A: `fsck` は ext2/3/4 用、`xfs_repair` は XFS 用です。XFS に対して fsck を実行しても効果はありません。また、両方とも必ずアンマウント状態で実行する必要があります。

---

## 本课小结

| 问题 | 诊断命令 | 解决命令 |
|------|----------|----------|
| ext4 损坏 | `fsck.ext4 -n` | `fsck.ext4 -y` |
| XFS 损坏 | `xfs_repair -n` | `xfs_repair` |
| Ghost Capacity | `lsof +L1` | 重启持有进程 |
| Inode 耗尽 | `df -i` | 删除小文件 |

**核心要点**：

1. fsck 用于 ext4，xfs_repair 用于 XFS
2. 修复前必须 unmount
3. df 和 du 不一致时检查 `lsof +L1`
4. inode 耗尽用 `df -i` 诊断

---

## 检查清单

完成本课后，确认你能够：

- [ ] 区分 fsck 和 xfs_repair 的使用场景
- [ ] 在 unmount 状态下安全运行 fsck
- [ ] 使用 `lsof +L1` 诊断 Ghost Capacity 问题
- [ ] 使用 `df -i` 诊断 inode 耗尽
- [ ] 执行 XFS 文件系统修复流程
- [ ] 解释为什么不能对挂载的文件系统运行 fsck

---

## 实验清理

```bash
# 清理所有实验环境
sudo umount /mnt/ghost /mnt/inode /mnt/testfs /mnt/xfstest 2>/dev/null
sudo losetup -d /dev/loop10 /dev/loop11 /dev/loop12 /dev/loop13 2>/dev/null
rm -f /tmp/ext4disk.img /tmp/xfsdisk.img /tmp/ghostdisk.img /tmp/inodedisk.img
sudo rmdir /mnt/ghost /mnt/inode /mnt/testfs /mnt/xfstest 2>/dev/null
```

---

## 延伸阅读

- [fsck man page](https://man7.org/linux/man-pages/man8/fsck.8.html)
- [xfs_repair man page](https://man7.org/linux/man-pages/man8/xfs_repair.8.html)
- [lsof man page](https://man7.org/linux/man-pages/man8/lsof.8.html)
- 上一课：[10 - 备份策略](../10-backup-strategies/) -- tar, rsync 与 3-2-1 规则
- 下一课：[12 - 综合项目](../12-capstone/) -- 弹性存储架构设计

---

## 系列导航

[<-- 10 - 备份策略](../10-backup-strategies/) | [系列首页](../) | [12 - 综合项目 -->](../12-capstone/)
