# 05 - 存储故障：容量、inode、I/O 错误

> **目标**：掌握存储问题的系统性诊断，区分空间满、inode 耗尽、I/O 错误三类问题  
> **前置**：LX07 存储基础（LVM、文件系统、挂载）  
> **时间**：2 小时  
> **核心挑战**：df 显示磁盘满，但 du 统计却不符  

---

## 将学到的内容

1. 区分磁盘空间、inode、I/O 错误三类存储问题
2. 诊断 "已删除但未释放" 的幽灵磁盘占用
3. 处理只读文件系统（Read-only remount）
4. 检查磁盘健康状态（SMART、dmesg）
5. 安全地执行文件系统修复（fsck 的正确使用）

---

## 先跑起来！（5 分钟）

> 存储问题是深夜告警的常客。这 3 条命令立即告诉你存储出了什么问题。  

```bash
# 查看磁盘空间使用（含文件系统类型）
df -hT

# 查看 inode 使用（小文件过多会耗尽 inode）
df -i

# 查看被删除但仍被进程持有的文件（幽灵占用）
lsof +D /var 2>/dev/null | grep deleted | head -10
```

**运行结果示例**：

```
# df -hT
Filesystem     Type      Size  Used Avail Use% Mounted on
/dev/sda1      ext4       50G   48G  2.0G  96% /
/dev/sdb1      xfs       100G   80G   20G  80% /data

# df -i
Filesystem      Inodes   IUsed   IFree IUse% Mounted on
/dev/sda1      3276800 3276700     100  100% /

# lsof +D /var | grep deleted
java      1234  app   10w  REG  8,1  5368709120  12345 /var/log/app.log (deleted)
```

**发现了什么？**

- `df -hT`：显示各分区使用率和文件系统类型
- `df -i`：inode 100% = 无法创建新文件（即使有空间）
- `lsof | grep deleted`：5GB 的日志文件被删除，但 Java 进程仍持有句柄！

这就是存储排查的第一步。现在让我们深入学习每类问题的诊断方法。

---

## Step 1 -- 存储问题分类（10 分钟）

### 1.1 三类存储问题

存储问题主要分为三类，诊断方法各不相同：

<!-- DIAGRAM: storage-problem-types -->
```
+------------------------------------------------------------------------+
|                       存储问题分类                                      |
+------------------------------------------------------------------------+
|                                                                        |
|    问题类型           症状                      关键命令               |
|    +--------------+  +---------------------+  +---------------------+  |
|    | 空间满       |  | "No space left"     |  | df -hT              |  |
|    | (Space Full) |  | 写入失败            |  | du -sh /path/*      |  |
|    |              |  | 服务无法启动        |  | lsof | grep deleted |  |
|    +--------------+  +---------------------+  +---------------------+  |
|                                                                        |
|    +--------------+  +---------------------+  +---------------------+  |
|    | inode 耗尽   |  | "No space left"     |  | df -i               |  |
|    | (inode      |  | 但 df -h 有空间     |  | find -type f | wc   |  |
|    |  Exhaustion)|  | 小文件极多          |  |                     |  |
|    +--------------+  +---------------------+  +---------------------+  |
|                                                                        |
|    +--------------+  +---------------------+  +---------------------+  |
|    | I/O 错误     |  | 文件系统只读        |  | dmesg | grep error  |  |
|    | (I/O Errors) |  | 读写极慢            |  | smartctl -a         |  |
|    |              |  | 内核报错            |  | fsck (unmounted!)   |  |
|    +--------------+  +---------------------+  +---------------------+  |
|                                                                        |
+------------------------------------------------------------------------+
```
<!-- /DIAGRAM -->

### 1.2 快速诊断流程

当收到 "No space left on device" 错误时：

```bash
# Step 1: 检查磁盘空间
df -hT

# Step 2: 如果空间有剩余，检查 inode
df -i

# Step 3: 如果 df 显示满但 du 不符，检查已删除文件
lsof +L1 | head -20
```

---

## Step 2 -- 磁盘空间问题（25 分钟）

### 2.1 df vs du：为什么会不一致？

**df** 统计的是文件系统块的使用情况（来自 superblock）。
**du** 统计的是目录树中文件的大小总和。

两者不一致的原因：
1. **已删除文件仍被进程持有**（最常见！）
2. 挂载点下隐藏了文件
3. 稀疏文件
4. 保留给 root 的空间

### 2.2 找到大文件和大目录

```bash
# 找到最大的 10 个目录
du -sh /* 2>/dev/null | sort -rh | head -10

# 进入可疑目录继续深入
du -sh /var/* 2>/dev/null | sort -rh | head -10

# 找到大于 100MB 的文件
find / -type f -size +100M -exec ls -lh {} \; 2>/dev/null | sort -k5 -rh | head -20

# 找到最近 24 小时修改的大文件（可能是日志疯狂增长）
find / -type f -size +50M -mtime -1 2>/dev/null
```

### 2.3 幽灵磁盘占用：已删除但未释放

**这是最容易被误诊的问题！**

场景：运维删除了大日志文件，但磁盘使用率不下降。

```bash
# 检查被删除但仍被进程持有的文件
lsof +L1
# +L1 = 显示 link count < 1 的文件（已删除但仍打开）

# 或者更直接
lsof | grep deleted

# 示例输出
java    1234  app  10w  REG  8,1  5368709120  12345 /var/log/app.log (deleted)
#                                 ^^^^^^^^^^ 5GB 仍被占用！
```

**为什么会这样？**

<!-- DIAGRAM: deleted-file-mechanism -->
```
+------------------------------------------------------------------------+
|                    文件删除 vs 空间释放                                  |
+------------------------------------------------------------------------+
|                                                                        |
|   正常情况（文件关闭后删除）                                            |
|   +------------+      rm file      +------------+                      |
|   |   file     | -----------------> |   空间    |                      |
|   | (inode+数据)|                   |   释放    |                      |
|   +------------+                   +------------+                      |
|                                                                        |
|   异常情况（文件被进程持有时删除）                                      |
|   +------------+      rm file      +------------+                      |
|   |   file     | -----------------> | 目录条目  |                      |
|   | (inode+数据)|                   |   删除    |                      |
|   +------+-----+                   +------------+                      |
|          |                                                             |
|          | 进程仍持有 fd                                               |
|          v                                                             |
|   +------------+                                                       |
|   | inode+数据 | <--- 空间仍被占用！                                   |
|   | (deleted)  |      直到进程关闭 fd                                  |
|   +------------+                                                       |
|                                                                        |
|   Linux 文件系统行为：                                                  |
|   - rm 删除的是目录条目（文件名到 inode 的链接）                        |
|   - inode 和数据块直到所有 fd 关闭才释放                               |
|   - 进程打开的文件通过 /proc/<PID>/fd 可见                             |
|                                                                        |
+------------------------------------------------------------------------+
```
<!-- /DIAGRAM -->

### 2.4 解决幽灵磁盘占用

**方法 1：重启持有文件的进程（推荐）**

```bash
# 找到持有已删除文件的进程
lsof +L1 | grep deleted

# 优雅重启该服务
sudo systemctl restart tomcat
# 或
sudo systemctl restart java-app
```

**方法 2：截断文件（不重启进程）**

如果不能重启进程，可以通过 `/proc/<PID>/fd` 截断文件：

```bash
# 找到进程 PID 和文件描述符
lsof +L1 | grep deleted
# 假设输出显示 PID=1234, FD=10

# 截断文件（清空但保持文件描述符有效）
: > /proc/1234/fd/10

# 验证空间释放
df -hT
```

**方法 3：使用正确的方式"清理"日志**

```bash
# 错误方式（会导致幽灵占用）
rm /var/log/app.log

# 正确方式（清空文件内容，保持文件存在）
: > /var/log/app.log
# 或
truncate -s 0 /var/log/app.log
# 或
cat /dev/null > /var/log/app.log
```

### 2.5 挂载点下的隐藏文件

另一个 df 和 du 不符的原因：

```bash
# 假设 /data 是一个挂载点
# 如果有人在挂载前写入了文件...

# 临时卸载挂载点
sudo umount /data

# 检查隐藏的文件
ls -la /data

# 如果有文件，这些会占用根分区空间！
# 清理后重新挂载
sudo mount /data
```

---

## Step 3 -- inode 耗尽（15 分钟）

### 3.1 什么是 inode？

**inode**（Index Node）存储文件的元数据：
- 文件大小、权限、属主
- 时间戳（atime, mtime, ctime）
- 数据块位置

**每个文件需要一个 inode**，即使是空文件！

```bash
# 查看 inode 使用情况
df -i

# 示例输出
Filesystem      Inodes   IUsed   IFree IUse% Mounted on
/dev/sda1      3276800 3276700     100  100% /
#                       ^^^^^^^ 几乎用完！
```

### 3.2 inode 耗尽的症状

```bash
# 尝试创建文件
touch /tmp/test
# 错误：No space left on device

# 但磁盘空间充足
df -h
# /dev/sda1       50G   30G   20G   60% /

# 检查 inode
df -i
# /dev/sda1      3276800 3276800      0  100% /
#                                     ^ inode 用完了！
```

### 3.3 找到小文件大户

```bash
# 统计每个目录下的文件数量
find / -xdev -type f -print 2>/dev/null | cut -d'/' -f2-3 | sort | uniq -c | sort -rn | head -20

# 找到文件数量最多的目录
for i in /*; do echo -n "$i: "; find "$i" -xdev -type f 2>/dev/null | wc -l; done | sort -t: -k2 -rn | head -10

# 常见罪魁祸首
ls /var/spool/postfix/maildrop/ | wc -l  # 邮件队列
ls /tmp/ | wc -l                          # 临时文件
ls /var/cache/apt/archives/ | wc -l       # APT 缓存
```

### 3.4 清理策略

```bash
# 清理旧的内核和包缓存
sudo apt autoremove  # Debian/Ubuntu
sudo yum autoremove  # RHEL/CentOS

# 清理邮件队列
sudo postsuper -d ALL  # 删除所有邮件

# 清理临时文件
sudo find /tmp -type f -atime +7 -delete

# 清理旧日志
sudo journalctl --vacuum-time=7d
sudo find /var/log -name "*.gz" -mtime +30 -delete
```

---

## Step 4 -- I/O 错误与只读文件系统（20 分钟）

### 4.1 文件系统变成只读的原因

当 Linux 检测到存储故障时，会自动将文件系统重新挂载为只读（Read-only），以防止数据损坏。

常见原因：
1. **磁盘物理故障**（坏扇区、控制器故障）
2. **文件系统损坏**（断电、非正常关机）
3. **存储后端问题**（SAN、NFS、云存储）
4. **RAID 降级**

### 4.2 检查 I/O 错误

```bash
# 检查内核日志中的存储错误
dmesg | grep -iE 'error|fail|ata|scsi|sda|sdb|i/o' | tail -30

# 常见错误消息
# ata1.00: status: { DRDY ERR }
# ata1.00: error: { UNC }        ← 不可恢复读取错误
# EXT4-fs error (device sda1): ext4_lookup:1604: inode #262145: comm bash: deleted inode referenced
# Remounting filesystem read-only  ← 自动重挂载为只读
```

### 4.3 检查磁盘 SMART 状态

**SMART**（Self-Monitoring, Analysis and Reporting Technology）是硬盘自检系统。

```bash
# 安装 smartmontools
sudo apt install smartmontools  # Debian/Ubuntu
sudo yum install smartmontools  # RHEL/CentOS

# 检查 SMART 状态
sudo smartctl -a /dev/sda

# 关键指标
sudo smartctl -a /dev/sda | grep -E 'Reallocated_Sector|Current_Pending|Offline_Uncorrectable'
# Reallocated_Sector_Ct  > 0 = 有坏扇区被重映射
# Current_Pending_Sector > 0 = 等待重映射的扇区
# Offline_Uncorrectable  > 0 = 无法修复的坏扇区

# 运行短测试
sudo smartctl -t short /dev/sda
# 等待几分钟后查看结果
sudo smartctl -l selftest /dev/sda
```

### 4.4 处理只读文件系统

**Step 1：确认只读状态**

```bash
# 检查挂载状态
mount | grep ' / '
# /dev/sda1 on / type ext4 (ro,relatime)
#                          ^^ ro = read-only

# 尝试写入测试
touch /tmp/test
# touch: cannot touch '/tmp/test': Read-only file system
```

**Step 2：查找原因**

```bash
# 检查内核日志
dmesg | tail -50

# 检查 SMART
sudo smartctl -a /dev/sda

# 检查文件系统日志
journalctl -k | grep -iE 'ext4|xfs|error'
```

**Step 3：尝试重新挂载为读写**

```bash
# 尝试 remount 为 rw
sudo mount -o remount,rw /

# 如果失败，说明有未修复的文件系统错误
# 需要进入单用户模式或使用 Live CD 运行 fsck
```

### 4.5 fsck：文件系统检查与修复

**危险操作警告！**

> **fsck 只能对未挂载的文件系统运行！**  
> 对已挂载的分区运行 fsck 会导致严重数据损坏！  

```bash
# 错误！危险！
sudo fsck /dev/sda1  # 如果 sda1 是根分区且已挂载

# 正确做法
# 1. 重启进入救援模式/单用户模式
# 2. 或使用 Live CD
# 3. 确保分区未挂载后再运行 fsck
```

**安全的 fsck 流程**：

```bash
# 方法 1：重启时强制 fsck（适用于根分区）
sudo touch /forcefsck
sudo reboot

# 方法 2：对非根分区
sudo umount /dev/sdb1
sudo fsck -y /dev/sdb1
sudo mount /dev/sdb1

# 方法 3：进入 Emergency Mode
# 重启后在 GRUB 界面编辑内核参数
# 添加 systemd.unit=emergency.target
# 然后运行 fsck
```

---

## Step 5 -- 存储问题决策树（10 分钟）

### 5.1 完整决策树

当遇到存储相关问题时，使用此决策树：

<!-- DIAGRAM: storage-decision-tree -->
```
+------------------------------------------------------------------------+
|                       存储问题诊断决策树                                 |
+------------------------------------------------------------------------+
|                                                                        |
|                           存储问题                                      |
|                              |                                         |
|                              v                                         |
|                  +------------------------+                            |
|                  | df -hT 显示磁盘满?     |                            |
|                  +------------------------+                            |
|                     |              |                                   |
|                    Yes             No                                  |
|                     |              |                                   |
|                     v              v                                   |
|        +------------------+   +------------------------+               |
|        | du 统计相符?     |   | df -i inode 满?        |               |
|        +------------------+   +------------------------+               |
|           |          |           |              |                      |
|          Yes         No         Yes             No                     |
|           |          |           |              |                      |
|           v          v           v              v                      |
|     +---------+ +---------+ +---------+  +------------------+          |
|     | 清理    | | 检查    | | 小文件  |  | I/O 错误?        |          |
|     | 大文件  | | 已删除  | | 过多    |  | (dmesg 检查)     |          |
|     |         | | 文件    | | 清理    |  +------------------+          |
|     +---------+ +---------+ +---------+     |          |               |
|                     |                      Yes         No              |
|                     v                       |          |               |
|              +-------------+                v          v               |
|              | lsof +L1    |         +----------+ +----------+         |
|              | grep deleted|         | smartctl | | 检查挂载 |         |
|              | 找到进程    |         | 检查磁盘 | | 是否只读 |         |
|              | 重启或截断  |         | 考虑 fsck| |          |         |
|              +-------------+         | (卸载后!)| +----------+         |
|                                      +----------+                      |
|                                                                        |
|   关键命令速查：                                                        |
|   - df -hT          : 检查空间使用                                     |
|   - df -i           : 检查 inode 使用                                  |
|   - du -sh /path/*  : 统计目录大小                                     |
|   - lsof +L1        : 找已删除但占用的文件                             |
|   - dmesg | grep -i error : 检查 I/O 错误                              |
|   - smartctl -a     : 检查磁盘健康                                     |
|                                                                        |
+------------------------------------------------------------------------+
```
<!-- /DIAGRAM -->

---

## Step 6 -- 真实案例：幽灵磁盘占用（15 分钟）

### 6.1 场景描述

凌晨 3 点，监控告警：

```
CRITICAL: /var 磁盘使用率 98%
主机: app-server-01
```

### 6.2 初步诊断

```bash
# 登录服务器
ssh admin@app-server-01

# 检查磁盘使用
df -hT /var
# Filesystem     Type  Size  Used Avail Use% Mounted on
# /dev/sda2      ext4  100G   98G  2.0G  98% /var

# 统计 /var 下各目录大小
du -sh /var/* | sort -rh | head -10
# 20G    /var/lib
# 10G    /var/cache
# 8G     /var/log
# ...
# 总计约 40G，但 df 显示 98G！
```

### 6.3 发现幽灵占用

```bash
# 检查已删除但仍被持有的文件
lsof +L1 | grep deleted

# 输出
# java   12345  app  10w  REG  8,1  53687091200  112233 /var/log/app/catalina.out (deleted)
#                                  ^^^^^^^^^^^ 50GB！

# 确认进程信息
ps aux | grep 12345
# app  12345 ... /opt/tomcat/bin/java ...
```

### 6.4 根因分析

运维团队在白天执行了日志清理：

```bash
# 他们执行的命令
rm /var/log/app/catalina.out
```

但 Tomcat 进程仍持有该文件的文件描述符，导致：
- 目录条目被删除（`ls` 看不到文件）
- inode 和数据块未释放（进程仍在写入）
- `df` 统计的是 inode 块使用，所以显示 98%
- `du` 统计的是目录树，所以只有 40G

### 6.5 解决方案

**方案 A：重启 Tomcat（推荐）**

```bash
# 检查是否可以重启
# 确认业务影响

# 优雅重启
sudo systemctl restart tomcat

# 验证空间释放
df -hT /var
# 使用率下降到约 42%
```

**方案 B：不重启，截断文件**

```bash
# 找到 fd 路径
ls -l /proc/12345/fd/ | grep deleted
# lrwx------ 1 app app 64 Jan 10 03:15 10 -> /var/log/app/catalina.out (deleted)

# 截断文件（立即释放空间，不影响进程）
: > /proc/12345/fd/10

# 验证
df -hT /var
```

### 6.6 预防措施

```bash
# 正确的日志清理方式
: > /var/log/app/catalina.out

# 配置 logrotate
cat > /etc/logrotate.d/tomcat << 'EOF'
/var/log/app/catalina.out {
    daily
    rotate 7
    compress
    missingok
    notifempty
    copytruncate  # 关键！截断而非删除
}
EOF
```

---

## Step 7 -- 反模式：fsck 挂载的文件系统（10 分钟）

### 7.1 为什么这是灾难

```bash
# 绝对不要这样做！
sudo fsck /dev/sda1  # 如果 sda1 已挂载

# 后果：
# - 文件系统元数据损坏
# - 数据丢失
# - 可能需要从备份恢复
```

### 7.2 fsck 安全检查清单

在运行 fsck 之前：

- [ ] 确认目标分区**未挂载**
- [ ] 如果是根分区，需要进入救援模式
- [ ] 有最近的备份
- [ ] 理解 `-y` 参数会自动修复（可能删除损坏文件）

```bash
# 检查分区是否挂载
mount | grep sda1

# 如果需要 fsck 根分区
# 方法 1：设置下次启动时 fsck
sudo touch /forcefsck
sudo reboot

# 方法 2：Live CD 启动后
# （从 Live CD 启动）
sudo fsck -y /dev/sda1
```

---

## 动手实验（20 分钟）

### 实验 1：模拟幽灵磁盘占用

```bash
# 创建测试环境
mkdir -p /tmp/storage-lab
cd /tmp/storage-lab

# 创建一个大文件
dd if=/dev/zero of=bigfile.log bs=1M count=100

# 检查磁盘使用
df -h /tmp

# 用 tail -f 持有这个文件
tail -f bigfile.log &
TAIL_PID=$!

# 删除文件
rm bigfile.log

# 检查 - 文件消失了
ls -la bigfile.log
# ls: cannot access 'bigfile.log': No such file or directory

# 但 df 显示空间未释放！
df -h /tmp

# 找到幽灵文件
lsof +L1 | grep bigfile

# 解决方案 1：杀死进程
kill $TAIL_PID

# 验证空间释放
df -h /tmp
```

### 实验 2：检查系统 SMART 状态

```bash
# 安装 smartmontools（如果未安装）
sudo apt install smartmontools -y 2>/dev/null || sudo yum install smartmontools -y

# 列出所有磁盘
lsblk

# 检查第一块磁盘的 SMART 状态（需要真实磁盘）
sudo smartctl -a /dev/sda 2>/dev/null || echo "SMART not supported or virtual disk"

# 查看关键健康指标
sudo smartctl -H /dev/sda 2>/dev/null

# 如果是虚拟机，SMART 可能不可用
# 这是正常的，云服务器通常不暴露 SMART 数据
```

### 实验 3：inode 使用分析

```bash
# 检查 inode 使用
df -i

# 找出文件数量最多的目录
echo "=== Top 10 directories by file count ==="
for dir in /var /tmp /home; do
    if [ -d "$dir" ]; then
        count=$(find "$dir" -xdev -type f 2>/dev/null | wc -l)
        echo "$dir: $count files"
    fi
done

# 清理测试文件
rm -rf /tmp/storage-lab
```

---

## 检查清单

完成本课后，你应该能够：

- [ ] 使用 `df -hT` 和 `df -i` 检查空间和 inode 使用
- [ ] 使用 `du -sh` 定位大目录
- [ ] 解释为什么 `df` 和 `du` 会不一致
- [ ] 使用 `lsof +L1` 找到已删除但仍占用空间的文件
- [ ] 使用截断（truncate）而非删除（rm）来清理活跃日志
- [ ] 检查 `dmesg` 中的 I/O 错误
- [ ] 使用 `smartctl` 检查磁盘健康状态
- [ ] 解释为什么不能对挂载的文件系统运行 `fsck`
- [ ] 处理只读文件系统（remount rw 或 fsck）

---

## 本课小结

| 问题类型 | 诊断命令 | 解决方案 |
|----------|----------|----------|
| 空间满（df 和 du 一致） | `du -sh /path/*` | 删除/清理大文件 |
| 空间满（df 和 du 不符） | `lsof +L1 \| grep deleted` | 重启进程或截断 fd |
| inode 耗尽 | `df -i` | 清理小文件，清理缓存 |
| I/O 错误 | `dmesg`, `smartctl -a` | 更换磁盘，fsck 修复 |
| 只读文件系统 | `mount`, `dmesg` | 找原因，remount 或 fsck |

**核心经验**：

> df 满但 du 不符 → 99% 是已删除文件仍被进程持有。  
> 使用 `lsof +L1` 而非盲目清理。  
> 清理日志用截断（`: >`）而非删除（`rm`）。  
> fsck 只能对**未挂载**的分区运行！  

---

## 面试准备

### 常见日语面试问题

**Q: ディスク障害の切り分けについて説明してください。**

A: ディスク障害の切り分けは3つの観点で行います：

1. **容量問題**（df -hT で確認）
   - df と du の差異がある場合、削除済みファイルが開いたままの可能性（lsof +L1 で確認）

2. **inode 枯渇**（df -i で確認）
   - 小さいファイルが大量にある場合に発生

3. **I/O エラー**（dmesg で確認）
   - smartctl でディスク健康状態を確認
   - 読み取り専用になった場合は fsck が必要（アンマウント後！）

**Q: df と du の結果が一致しない場合、何を疑いますか？**

A: 最も多いのは「削除されたファイルがプロセスに保持されている」ケースです。

```bash
# 確認コマンド
lsof +L1 | grep deleted
```

解決策は：
- プロセスを再起動する
- または `/proc/<PID>/fd` 経由でファイルを truncate する

**Q: 本番環境で fsck を実行する際の注意点は？**

A: 最も重要なのは「**マウント中のファイルシステムには絶対に実行しない**」ことです。

- マウント中の fsck はデータ破壊を引き起こします
- ルートパーティションの場合は rescue mode や Live CD から実行
- 実行前にバックアップ確認が必須

---

## 日本 IT 职场：ディスク障害

### よく使う表現

| 日语 | 读音 | 场景 |
|------|------|------|
| ディスクフル | disuku furu | 磁盘满 |
| 容量不足 | youryou fusoku | 空间不足 |
| 容量監視 | youryou kanshi | 容量监控 |
| 深夜アラート | shinya araato | 深夜告警 |
| 一次対応 | ichiji taiou | 初步处理 |

### 职场提示

**ディスク障害は深夜アラートでよくある**

存储问题是日本企业夜班告警的常客。几个要点：

1. **容量監視は運用監視の基本**
   - 80% 警告、90% 告警是标准配置
   - 不要等到 100% 才处理

2. **清理前先确认**
   - 不要直接删除，先确认文件用途
   - 日志文件用 truncate 而非 rm

3. **记录处理过程**
   - 深夜处理也要留下记录
   - 第二天早上要能解释做了什么

---

## トラブルシューティング（本課自体の問題解決）

### lsof 命令很慢

```bash
# lsof 扫描所有进程的 fd，在大系统上可能很慢

# 限制搜索范围
lsof +D /var/log  # 只搜索特定目录

# 或使用 find 通过 /proc 直接查找
find /proc/*/fd -ls 2>/dev/null | grep deleted
```

### smartctl 显示 "Not Available"

```bash
# 虚拟机或云服务器通常不暴露 SMART
# 这是正常的

# 在这些环境中，关注：
# - 云厂商的磁盘健康 API
# - dmesg 中的 I/O 错误
# - 应用层的超时和错误日志
```

### df 和 mount 显示不同

```bash
# 可能有 bind mount 或 overlay
findmnt --list

# 查看所有挂载（包括隐藏的）
cat /proc/mounts
```

---

## 延伸阅读

- [Red Hat - Managing Disk Space](https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/9/html/managing_storage_devices/)
- [smartmontools Documentation](https://www.smartmontools.org/wiki/TocDoc)
- [Linux Filesystem Hierarchy](https://refspecs.linuxfoundation.org/FHS_3.0/fhs/index.html)
- 上一课：[04 - 网络问题](../04-network-problems/) -- 分层诊断
- 下一课：[06 - 性能问题](../06-performance/) -- USE 方法论实战

---

## 系列导航

[<-- 04 - 网络问题](../04-network-problems/) | [系列首页](../) | [06 - 性能问题 -->](../06-performance/)
