# 02 - 启动故障：GRUB、initramfs、紧急模式

> **目标**：系统性诊断和恢复 Linux 启动故障  
> **前置**：LX05-SYSTEMD 服务管理基础，LX07-STORAGE 存储基础  
> **时间**：2-2.5 小时  
> **实战场景**：服务器维护重启后无法启动  

---

## 将学到的内容

1. 理解 Linux 完整启动流程（BIOS/UEFI -> GRUB -> Kernel -> initramfs -> systemd）
2. 区分不同启动阶段的故障症状
3. 使用 GRUB 命令行手动引导系统
4. 重建损坏的 initramfs
5. 使用 Emergency Mode 和 Rescue Mode 修复系统
6. 解决 /etc/fstab 导致的启动失败

---

## 先跑起来！（10 分钟）

> 服务器昨天还好好的，今天重启后进不去了。  
> 先不管理论，用这几条命令快速定位启动阶段：  

```bash
# 查看上次启动的日志（从当前系统）
journalctl -b -1 -p err

# 如果已经进入系统，查看启动耗时
systemd-analyze

# 查看启动关键链
systemd-analyze critical-chain

# 检查是否有失败的服务阻塞启动
systemctl --failed

# 查看 fstab 挂载状态
systemctl list-units --type=mount --state=failed
```

**你刚刚定位了启动可能卡住的阶段！**

启动故障不可怕，可怕的是盲目乱试。理解启动流程后，你能准确定位问题出在哪个阶段。

现在让我们系统学习 Linux 启动流程和故障排查方法。

---

## Step 1 -- Linux 启动流程全景图（15 分钟）

### 1.1 启动五阶段

理解启动流程是诊断的前提。Linux 启动分为五个阶段：

<!-- DIAGRAM: boot-process-flow -->
```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        Linux 启动流程（Boot Process）                        │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐    ┌─────────────┐  │
│  │   Stage 1   │───▶│   Stage 2   │───▶│   Stage 3   │───▶│   Stage 4   │  │
│  │ BIOS/UEFI   │    │    GRUB2    │    │   Kernel    │    │  initramfs  │  │
│  │             │    │             │    │             │    │             │  │
│  │ 硬件初始化  │    │  引导加载器  │    │  内核加载   │    │  临时根文件 │  │
│  │ 查找启动盘  │    │  选择内核   │    │  硬件探测   │    │  系统挂载   │  │
│  └─────────────┘    └─────────────┘    └─────────────┘    └──────┬──────┘  │
│                                                                  │         │
│                                                                  ▼         │
│                           ┌─────────────────────────────────────────────┐  │
│                           │              Stage 5: systemd               │  │
│                           │                                             │  │
│                           │  ┌─────────┐  ┌─────────┐  ┌─────────────┐  │  │
│                           │  │ basic   │─▶│ multi-  │─▶│ graphical/  │  │  │
│                           │  │ .target │  │ user    │  │ multi-user  │  │  │
│                           │  │         │  │ .target │  │ .target     │  │  │
│                           │  └─────────┘  └─────────┘  └─────────────┘  │  │
│                           └─────────────────────────────────────────────┘  │
│                                                                             │
│  故障定位：哪个阶段？                                                        │
│  ───────────────────                                                        │
│  Stage 1 失败 → 无任何显示，检查 BIOS/硬盘                                   │
│  Stage 2 失败 → grub> 或 grub rescue> 提示符                                │
│  Stage 3 失败 → Kernel panic, root device not found                         │
│  Stage 4 失败 → dracut 错误，进入 dracut shell                              │
│  Stage 5 失败 → Emergency Mode 或 Rescue Mode                               │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```
<!-- /DIAGRAM -->

### 1.2 各阶段的职责

| 阶段 | 组件 | 职责 | 故障表现 |
|------|------|------|----------|
| 1 | BIOS/UEFI | 硬件自检，查找启动设备 | 无显示，蜂鸣，硬件错误 |
| 2 | GRUB2 | 加载内核和 initramfs | grub>/grub rescue> 提示符 |
| 3 | Kernel | 初始化 CPU、内存、设备驱动 | Kernel panic |
| 4 | initramfs | 临时根，加载真正的 root 分区 | dracut shell，找不到 root |
| 5 | systemd | 启动服务，挂载文件系统 | Emergency/Rescue Mode |

### 1.3 BIOS vs UEFI

现代服务器多使用 UEFI，但传统 BIOS 仍有使用：

| 对比项 | Legacy BIOS | UEFI |
|--------|-------------|------|
| 启动分区 | MBR（主引导记录） | ESP（EFI 系统分区） |
| 分区表 | MBR（最大 2TB） | GPT（支持大磁盘） |
| GRUB 位置 | MBR + /boot/grub2/ | ESP + /boot/efi/ |
| 安全启动 | 不支持 | Secure Boot |

```bash
# 检查当前启动模式
[ -d /sys/firmware/efi ] && echo "UEFI" || echo "BIOS"

# UEFI 模式下查看 ESP 分区
ls -la /boot/efi/EFI/
```

---

## Step 2 -- 启动故障决策树（10 分钟）

### 2.1 核心决策树

遇到启动故障，按此决策树定位阶段：

<!-- DIAGRAM: boot-decision-tree -->
```
┌──────────────────────────────────────────────────────────────────────────┐
│                         启动故障决策树                                    │
├──────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  启动失败                                                                │
│      │                                                                   │
│      ▼                                                                   │
│  ┌─────────────────────┐                                                 │
│  │ 屏幕有任何显示吗？  │                                                 │
│  └──────────┬──────────┘                                                 │
│             │                                                            │
│     ┌───────┴───────┐                                                    │
│     │ No            │ Yes                                                │
│     ▼               ▼                                                    │
│  ┌──────────┐  ┌─────────────────────┐                                   │
│  │ Stage 1  │  │ 是 grub> 或         │                                   │
│  │ 硬件问题 │  │ grub rescue> 吗？   │                                   │
│  │          │  └──────────┬──────────┘                                   │
│  │ ・检查电源│            │                                              │
│  │ ・检查硬盘│     ┌──────┴──────┐                                       │
│  │ ・BIOS设置│     │ Yes         │ No                                    │
│  └──────────┘     ▼             ▼                                        │
│              ┌──────────┐  ┌─────────────────────┐                       │
│              │ Stage 2  │  │ 显示 Kernel panic   │                       │
│              │ GRUB故障 │  │ 或 dracut shell？   │                       │
│              │          │  └──────────┬──────────┘                       │
│              │ 见 Step 3│            │                                   │
│              └──────────┘     ┌──────┴──────┐                            │
│                               │ Yes         │ No                         │
│                               ▼             ▼                            │
│                          ┌──────────┐  ┌─────────────────────┐           │
│                          │ Stage 3-4│  │ Emergency Mode 或   │           │
│                          │ 内核/    │  │ Rescue Mode？       │           │
│                          │ initramfs│  └──────────┬──────────┘           │
│                          │          │            │                       │
│                          │ 见 Step 4│     ┌──────┴──────┐                │
│                          └──────────┘     │ Yes         │ No             │
│                                           ▼             ▼                │
│                                      ┌──────────┐  ┌──────────┐          │
│                                      │ Stage 5  │  │ 正常启动 │          │
│                                      │ systemd  │  │ 但有问题 │          │
│                                      │          │  │          │          │
│                                      │ 见 Step 5│  │ 见 Step 6│          │
│                                      └──────────┘  └──────────┘          │
│                                                                          │
└──────────────────────────────────────────────────────────────────────────┘
```
<!-- /DIAGRAM -->

### 2.2 收集启动信息

在能进入系统的情况下，先收集信息：

```bash
# 启动日志
journalctl -b                    # 本次启动
journalctl -b -1                 # 上次启动
journalctl -b -1 -p err          # 上次启动的错误

# 启动时间分析
systemd-analyze                  # 总耗时
systemd-analyze blame            # 各服务耗时
systemd-analyze critical-chain   # 关键路径

# 失败的单元
systemctl --failed
systemctl list-units --state=failed

# fstab 检查
cat /etc/fstab
mount | grep -v "^cgroup"        # 当前挂载
```

---

## Step 3 -- GRUB 故障诊断与恢复（25 分钟）

### 3.1 GRUB 故障的两种模式

GRUB 故障有两种表现，处理方法不同：

| 提示符 | 含义 | 原因 | 恢复方法 |
|--------|------|------|----------|
| `grub>` | GRUB 加载成功，但找不到配置 | grub.cfg 缺失或损坏 | 手动引导 + 重建配置 |
| `grub rescue>` | GRUB 核心加载，但模块损坏 | /boot/grub2/ 损坏 | 需要救援介质 |

### 3.2 从 grub> 提示符手动引导

如果看到 `grub>` 提示符，可以手动引导：

```bash
# 1. 列出可用磁盘和分区
grub> ls
# 输出：(hd0) (hd0,gpt2) (hd0,gpt1)

# 2. 查找包含 Linux 内核的分区
grub> ls (hd0,gpt2)/
# 找到 vmlinuz-* 和 initramfs-* 文件

# 3. 设置根分区
grub> set root=(hd0,gpt2)

# 4. 加载内核（根据实际版本调整）
grub> linux /vmlinuz-5.14.0-427.el9.x86_64 root=/dev/sda3 ro

# 5. 加载 initramfs
grub> initrd /initramfs-5.14.0-427.el9.x86_64.img

# 6. 启动
grub> boot
```

**常见内核参数**：

| 参数 | 用途 |
|------|------|
| `root=/dev/sda3` | 指定根分区 |
| `root=UUID=xxxxx` | 使用 UUID 指定根分区 |
| `ro` | 只读挂载 root |
| `rd.break` | 在 initramfs 阶段中断（用于密码重置） |
| `systemd.unit=rescue.target` | 进入单用户模式 |
| `init=/bin/bash` | 直接进入 bash（绕过 systemd） |

### 3.3 从救援介质恢复 GRUB

如果 `grub rescue>` 或完全无法引导，需要救援介质：

```bash
# 1. 从救援 ISO/USB 启动
# 选择 "Rescue a system" 或 "Troubleshooting"

# 2. 挂载系统分区（救援模式通常会帮你挂载到 /mnt/sysroot）
mount /dev/sda3 /mnt/sysroot
mount /dev/sda2 /mnt/sysroot/boot    # 如果 /boot 是独立分区
mount /dev/sda1 /mnt/sysroot/boot/efi  # UEFI 的 ESP 分区

# 3. 挂载必要的虚拟文件系统
mount --bind /dev /mnt/sysroot/dev
mount --bind /proc /mnt/sysroot/proc
mount --bind /sys /mnt/sysroot/sys

# 4. chroot 进入系统
chroot /mnt/sysroot

# 5. 重建 GRUB 配置
# RHEL/CentOS/Rocky:
grub2-mkconfig -o /boot/grub2/grub.cfg

# Debian/Ubuntu:
grub-mkconfig -o /boot/grub/grub.cfg

# 6. 重新安装 GRUB（BIOS 模式）
# RHEL/CentOS:
grub2-install /dev/sda

# Debian/Ubuntu:
grub-install /dev/sda

# 7. 重新安装 GRUB（UEFI 模式）
# RHEL/CentOS:
grub2-install --target=x86_64-efi --efi-directory=/boot/efi

# 8. 退出并重启
exit
reboot
```

### 3.4 GRUB 配置备份（预防措施）

日常维护中，养成备份 GRUB 配置的习惯：

```bash
# 备份 GRUB 配置
cp /boot/grub2/grub.cfg /boot/grub2/grub.cfg.backup

# 备份 GRUB 环境
cp /boot/grub2/grubenv /boot/grub2/grubenv.backup

# 查看当前默认内核
grubby --default-kernel

# 查看所有可用内核
grubby --info=ALL
```

---

## Step 4 -- initramfs 故障诊断与修复（20 分钟）

### 4.1 initramfs 的作用

initramfs（Initial RAM Filesystem）是启动时的临时根文件系统：

<!-- DIAGRAM: initramfs-role -->
```
┌──────────────────────────────────────────────────────────────────────────┐
│                         initramfs 的作用                                  │
├──────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  问题：内核需要挂载根文件系统 (/)                                          │
│        但根文件系统在 LVM/RAID/加密磁盘上，需要特殊驱动                     │
│        这些驱动在根文件系统里，形成先有鸡还是先有蛋的问题                    │
│                                                                          │
│  ┌─────────────┐                      ┌─────────────┐                    │
│  │   Kernel    │                      │  真正的 /   │                    │
│  │             │    ?如何到达?         │             │                    │
│  │  内存中加载  │ ────────────────────▶│ /dev/sda3   │                    │
│  │  没有驱动   │                      │ (LVM/XFS)   │                    │
│  └─────────────┘                      └─────────────┘                    │
│                                                                          │
│  解决方案：initramfs                                                      │
│                                                                          │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐                   │
│  │   Kernel    │───▶│  initramfs  │───▶│  真正的 /   │                   │
│  │             │    │             │    │             │                   │
│  │  加载到内存  │    │ ・临时根文件 │    │ 挂载并切换  │                   │
│  │             │    │ ・必要驱动   │    │ (pivot_root)│                   │
│  │             │    │ ・LVM工具   │    │             │                   │
│  │             │    │ ・加密工具   │    │             │                   │
│  └─────────────┘    └─────────────┘    └─────────────┘                   │
│                                                                          │
│  initramfs 包含：                                                         │
│  ・必要的内核模块（存储驱动、文件系统）                                     │
│  ・设备管理工具（udev 规则）                                               │
│  ・LVM/RAID/加密工具                                                      │
│  ・启动脚本                                                               │
│                                                                          │
└──────────────────────────────────────────────────────────────────────────┘
```
<!-- /DIAGRAM -->

### 4.2 initramfs 故障症状

常见错误信息：

```
dracut: FATAL: No or empty root= argument
dracut: FATAL: Unable to access root device
dracut Warning: Could not boot.
Dropping to debug shell.

dracut:/#
```

### 4.3 dracut shell 紧急排查

如果进入了 `dracut:/#` shell：

```bash
# 查看可用的块设备
lsblk

# 查看设备 UUID
blkid

# 检查 LVM 卷组
vgs
lvs
lvscan

# 手动激活 LVM
vgchange -ay

# 检查 root 设备是否存在
ls /dev/mapper/

# 查看启动参数
cat /proc/cmdline
```

### 4.4 重建 initramfs

从救援模式或正常系统重建 initramfs：

```bash
# RHEL/CentOS/Fedora/Rocky Linux（使用 dracut）
# -------------------------------------------

# 重建当前内核的 initramfs
dracut -f

# 重建指定内核的 initramfs
dracut -f /boot/initramfs-5.14.0-427.el9.x86_64.img 5.14.0-427.el9.x86_64

# 添加特定驱动模块
dracut -f --add-drivers "nvme xfs"

# 详细输出（调试用）
dracut -fv


# Debian/Ubuntu（使用 update-initramfs）
# --------------------------------------

# 更新当前内核的 initramfs
update-initramfs -u

# 更新指定内核
update-initramfs -u -k 5.15.0-91-generic

# 重建所有内核的 initramfs
update-initramfs -u -k all

# 详细输出
update-initramfs -u -v
```

### 4.5 rd.break 调试模式

`rd.break` 在 initramfs 阶段中断，常用于密码重置：

```bash
# 1. 在 GRUB 菜单按 'e' 编辑启动项
# 2. 找到 linux 行，在末尾添加 rd.break
# 3. 按 Ctrl+X 启动

# 进入 initramfs shell 后：
# 根文件系统在 /sysroot 且为只读

# 重新挂载为读写
mount -o remount,rw /sysroot

# chroot 进入
chroot /sysroot

# 修改 root 密码（如果需要）
passwd root

# 如果是 RHEL/CentOS（SELinux），标记重新打标签
touch /.autorelabel

# 退出并重启
exit
exit
# 或 reboot -f
```

---

## Step 5 -- systemd 启动故障：Emergency 与 Rescue（20 分钟）

### 5.1 Emergency vs Rescue Mode

如果内核和 initramfs 都正常，但系统进入了 Emergency Mode 或 Rescue Mode：

| 模式 | target | 特点 | 常见原因 |
|------|--------|------|----------|
| Emergency Mode | emergency.target | 最小环境，root 只读 | fstab 错误、fsck 失败 |
| Rescue Mode | rescue.target | 单用户，可读写 | 手动请求、依赖失败 |

### 5.2 Emergency Mode 诊断

```bash
# Emergency Mode 下的诊断步骤

# 1. 查看启动日志
journalctl -xb

# 2. 查看具体错误
journalctl -xb -p err

# 3. 检查失败的挂载
systemctl --failed
systemctl list-units --type=mount --state=failed

# 4. 检查 fstab
cat /etc/fstab

# 5. 验证设备存在
lsblk
blkid

# 6. 检查文件系统
# 注意：只能对未挂载的分区运行 fsck！
fsck /dev/sda2
```

### 5.3 常见 systemd 启动阻塞

**问题 1：服务启动超时**

```bash
# 查找超时的服务
journalctl -b -p err | grep -i timeout

# 查看服务状态
systemctl status <service>

# 临时禁用问题服务
systemctl mask <service>
reboot

# 修复后恢复
systemctl unmask <service>
```

**问题 2：依赖服务失败**

```bash
# 查看服务依赖
systemctl list-dependencies <service>

# 查看反向依赖（谁依赖这个服务）
systemctl list-dependencies --reverse <service>

# 查看启动关键链
systemd-analyze critical-chain <service>
```

### 5.4 手动进入救援模式

有时需要主动进入救援模式进行维护：

```bash
# 方法 1：GRUB 启动参数
# 在 linux 行末尾添加：
systemd.unit=rescue.target    # Rescue Mode
systemd.unit=emergency.target  # Emergency Mode

# 方法 2：从运行中的系统
systemctl isolate rescue.target
systemctl isolate emergency.target

# 方法 3：设置默认目标（谨慎使用）
systemctl set-default rescue.target
# 恢复：
systemctl set-default multi-user.target
```

---

## Step 6 -- fstab 问题排查（25 分钟）

### 6.1 场景："昨天还好好的"

> **场景**：计划维护重启后，服务器进入 Emergency Mode。  
> 原因：一个非关键数据盘被加入 /etc/fstab，但没有 nofail 选项，而该磁盘当前离线。  

这是最常见的启动故障之一。

### 6.2 fstab 字段复习

```bash
# /etc/fstab 格式
# <设备>       <挂载点>   <类型>   <选项>        <dump> <fsck>
UUID=xxx-xxx   /          xfs      defaults      0      1
UUID=yyy-yyy   /boot      ext4     defaults      0      2
UUID=zzz-zzz   /data      xfs      defaults      0      2    # 危险！
```

### 6.3 关键选项：nofail 和 noauto

| 选项 | 作用 | 使用场景 |
|------|------|----------|
| `nofail` | 设备不存在时不阻塞启动 | 可选磁盘、外接存储 |
| `noauto` | 启动时不自动挂载 | 手动挂载的设备 |
| `x-systemd.device-timeout=10` | 设备等待超时 | 网络存储、慢速设备 |

**安全的 fstab 配置**：

```bash
# 非关键数据盘：添加 nofail
UUID=zzz-zzz   /data      xfs      defaults,nofail      0      2

# 网络存储：添加超时和 nofail
UUID=aaa-aaa   /nfs       nfs      defaults,nofail,x-systemd.device-timeout=30   0 0

# 可移动设备：noauto
UUID=bbb-bbb   /usb       ext4     defaults,noauto,nofail   0 0
```

### 6.4 Emergency Mode 下修复 fstab

```bash
# 1. Emergency Mode 下 root 是只读的
# 先重新挂载为读写
mount -o remount,rw /

# 2. 编辑 fstab
vim /etc/fstab

# 3. 方法 A：注释掉问题行
# UUID=zzz-zzz   /data      xfs      defaults      0      2

# 4. 方法 B：添加 nofail 选项
UUID=zzz-zzz   /data      xfs      defaults,nofail      0      2

# 5. 方法 C：确认 UUID 是否正确
blkid
# 对比 fstab 中的 UUID

# 6. 验证 fstab 语法
mount -a
# 如果有错误会提示

# 7. 重启
reboot
```

### 6.5 UUID vs 设备路径

**为什么推荐 UUID？**

| 方式 | 示例 | 稳定性 | 问题 |
|------|------|--------|------|
| 设备路径 | `/dev/sda1` | 不稳定 | 添加磁盘后可能变化 |
| UUID | `UUID=xxxx-xxxx` | 稳定 | 格式化后会变 |
| LABEL | `LABEL=data` | 稳定 | 需要设置标签 |
| LVM | `/dev/mapper/vg-lv` | 稳定 | 仅限 LVM |

```bash
# 查看设备 UUID
blkid

# 使用 UUID 添加到 fstab
echo "UUID=$(blkid -s UUID -o value /dev/sdb1)  /data  xfs  defaults,nofail  0  2" >> /etc/fstab

# 设置卷标
xfs_admin -L data /dev/sdb1    # XFS
e2label /dev/sdb1 data         # ext4
```

### 6.6 测试 fstab 修改

**修改 fstab 后，不要直接重启！先测试！**

```bash
# 方法 1：mount -a（最常用）
mount -a
# 如果没有错误输出，说明语法正确

# 方法 2：systemd 重新加载
systemctl daemon-reload
systemctl list-units --type=mount --state=failed

# 方法 3：模拟挂载（不实际挂载）
mount -fav
# -f: fake，不实际挂载
# -a: all，所有条目
# -v: verbose，详细输出
```

---

## Step 7 -- 动手实验（30 分钟）

### 实验 1：模拟 fstab 故障（建议在虚拟机中进行）

> **警告**：此实验会导致系统无法正常启动，请在虚拟机中进行！  

```bash
# 1. 创建一个测试分区或 loop 设备
dd if=/dev/zero of=/tmp/testdisk.img bs=1M count=100
losetup /dev/loop0 /tmp/testdisk.img
mkfs.xfs /dev/loop0

# 2. 获取 UUID
blkid /dev/loop0

# 3. 创建挂载点
mkdir /testmount

# 4. 添加到 fstab（故意不加 nofail，错误示范）
echo "UUID=<上一步的UUID>  /testmount  xfs  defaults  0  2" >> /etc/fstab

# 5. 测试挂载
mount -a
# 应该成功

# 6. 移除 loop 设备（模拟磁盘故障）
umount /testmount
losetup -d /dev/loop0
rm /tmp/testdisk.img

# 7. 尝试重启（在虚拟机中！）
# 系统会进入 Emergency Mode

# 8. 修复：在 Emergency Mode 中
mount -o remount,rw /
vim /etc/fstab
# 注释掉或删除问题行
reboot
```

### 实验 2：GRUB 手动引导练习

在 GRUB 菜单中练习手动引导：

```bash
# 1. 重启系统，在 GRUB 菜单按 'c' 进入命令行

# 2. 列出设备
grub> ls

# 3. 查看分区内容
grub> ls (hd0,gpt2)/

# 4. 记录内核和 initramfs 文件名
# vmlinuz-xxx
# initramfs-xxx.img

# 5. 按 ESC 返回菜单正常启动

# 6. 记录这些信息，以备真正需要手动引导时使用
```

### 实验 3：initramfs 重建

```bash
# 查看当前 initramfs 内容
lsinitrd /boot/initramfs-$(uname -r).img | head -50

# 备份当前 initramfs
cp /boot/initramfs-$(uname -r).img /boot/initramfs-$(uname -r).img.backup

# 重建 initramfs（RHEL/CentOS）
dracut -fv

# 或指定添加驱动
dracut -fv --add-drivers "nvme virtio_blk"

# 验证新的 initramfs
lsinitrd /boot/initramfs-$(uname -r).img | head -50
```

---

## 反模式：常见错误

### 错误 1：不测试就重启

```bash
# 错误：修改 fstab 后直接重启
vim /etc/fstab
# 添加新挂载点
reboot    # 危险！

# 正确：先测试
vim /etc/fstab
mount -a    # 测试语法
systemctl daemon-reload
systemctl list-units --type=mount --state=failed
# 确认无错误后再重启
```

### 错误 2：非关键磁盘不加 nofail

```bash
# 错误：数据盘使用默认选项
UUID=xxx  /data  xfs  defaults  0  2

# 正确：非 root 分区添加 nofail
UUID=xxx  /data  xfs  defaults,nofail  0  2
```

### 错误 3：对挂载的文件系统运行 fsck

```bash
# 错误：这会损坏数据！
fsck /dev/sda3    # 如果 sda3 已挂载

# 正确：先卸载或从救援模式运行
umount /dev/sda3
fsck /dev/sda3

# 或者对 root 分区，必须从救援模式运行
```

### 错误 4：Emergency Mode 下不 remount rw

```bash
# 错误：直接编辑
vim /etc/fstab
# E45: 'readonly' option is set

# 正确：先 remount
mount -o remount,rw /
vim /etc/fstab
```

---

## 职场小贴士（Japan IT Context）

### 启动故障处理（起動障害対応）

在日本 IT 现场，启动故障通常发生在维护窗口后：

| 日语术语 | 含义 | 场景 |
|----------|------|------|
| 起動障害 | 启动故障 | 服务器无法启动 |
| 緊急対応 | 紧急处理 | 深夜 On-call |
| 変更管理 | 变更管理 | 追溯最近的变更 |
| 切り戻し | 回滚 | 恢复到变更前状态 |
| 障害報告書 | 故障报告 | 事后文档 |

### 典型场景：夜间批处理后的启动故障

```
时间线（典型）：
2:00 AM - 夜间批处理结束，系统重启
2:05 AM - 监控告警：サーバー起動失敗
2:10 AM - On-call エンジニア 接到电话
2:15 AM - 确认症状：Emergency Mode
2:30 AM - 定位原因：fstab 中新增数据盘 UUID 错误
2:35 AM - 修复并重启
2:40 AM - 服务恢复
3:00 AM - 报告上级（一次報告）
翌日   - 提交 障害報告書
```

### 变更管理的重要性

日本企业非常重视变更管理（変更管理）。启动故障的排查第一步：

```bash
# 检查最近的变更
# 1. 配置变更
ls -lt /etc/ | head -20
stat /etc/fstab

# 2. 软件更新
rpm -qa --last | head -10    # RHEL/CentOS
apt list --installed 2>/dev/null | head -10    # Debian/Ubuntu

# 3. 内核更新
ls -lt /boot/

# 4. 向团队确认
# 「昨日何か変更しましたか？」
# (昨天有做什么变更吗？)
```

### 面试常见问题

**Q1: サーバーが起動しない場合、どのように対応しますか？**
（服务器无法启动时，你会如何处理？）

参考答案：
1. 首先确认故障阶段（GRUB？initramfs？systemd？）
2. 查看屏幕错误信息，确定是 grub 提示符、kernel panic 还是 Emergency Mode
3. 如果是 Emergency Mode，先检查 journalctl -xb 和 /etc/fstab
4. 记录所有诊断步骤和发现，用于后续的障害報告書

**Q2: /etc/fstab の nofail オプションは何のためですか？**
（/etc/fstab 的 nofail 选项有什么用？）

参考答案：
- nofail 选项表示设备不存在时不阻塞启动
- 非关键数据盘应该添加此选项
- 防止因可选磁盘离线导致系统进入 Emergency Mode

---

## 检查清单

完成本课后，你应该能够：

- [ ] 描述 Linux 5 个启动阶段及其职责
- [ ] 区分 BIOS 和 UEFI 启动模式
- [ ] 使用启动决策树定位故障阶段
- [ ] 从 grub> 提示符手动引导系统
- [ ] 使用救援介质 chroot 修复 GRUB
- [ ] 使用 dracut -f 或 update-initramfs -u 重建 initramfs
- [ ] 使用 rd.break 进入 initramfs shell
- [ ] 区分 Emergency Mode 和 Rescue Mode
- [ ] 在 Emergency Mode 下 remount rw 并编辑 fstab
- [ ] 正确使用 nofail 和 noauto 选项
- [ ] 修改 fstab 后使用 mount -a 测试
- [ ] 理解 UUID vs 设备路径的优劣

---

## 本课小结

| 概念 | 关键命令/配置 | 记忆点 |
|------|---------------|--------|
| 启动流程 | BIOS->GRUB->Kernel->initramfs->systemd | 5 个阶段 |
| GRUB 恢复 | grub> 手动引导，chroot 重建 | ls, set root, linux, initrd, boot |
| initramfs | dracut -f / update-initramfs -u | 包含根挂载必需的驱动 |
| rd.break | 在 initramfs 阶段中断 | 密码重置常用 |
| Emergency Mode | fstab 错误常见原因 | mount -o remount,rw / |
| nofail | 设备不存在时不阻塞 | 非关键磁盘必加 |
| 测试 fstab | mount -a | 重启前必测 |

---

## 延伸阅读

- [Red Hat: Boot Process and Troubleshooting](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/9/html/managing_monitoring_and_updating_the_kernel/assembly_boot-process-and-troubleshooting_managing-monitoring-and-updating-the-kernel)
- [Arch Wiki: GRUB](https://wiki.archlinux.org/title/GRUB)
- [dracut man page](https://man7.org/linux/man-pages/man8/dracut.8.html)
- 下一课：[03 - 服务故障：systemd 深度诊断](../03-service-failures/) -- 学习 systemd 依赖分析和服务故障排查
- 相关课程：[LX05-SYSTEMD](../../systemd/) -- systemd 基础知识

---

## 系列导航

[<-- 01 - 故障排查方法论](../01-methodology/) | [系列首页](../) | [03 - 服务故障 -->](../03-service-failures/)
