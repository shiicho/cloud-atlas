# PAM 配置恢复步骤 / PAM Configuration Recovery Steps

> **紧急情况**：如果 PAM 配置错误导致无法登录，使用以下步骤恢复。  

---

## 场景 1：有另一个 root 终端打开

这是最简单的情况。在备用 root 终端执行：

```bash
# 恢复 PAM 配置备份
sudo cp -r /etc/pam.d.bak.*/* /etc/pam.d/

# 恢复 faillock 配置
sudo cp /etc/security/faillock.conf.bak.* /etc/security/faillock.conf

# 验证可以登录
su - testuser  # 测试普通用户
su -           # 测试 root

# 如果使用 authselect (RHEL 8+)，重置到默认
sudo authselect select sssd --force
# 或
sudo authselect select minimal --force
```

---

## 场景 2：有控制台访问（VNC/IPMI/Cloud Console）

如果 SSH 无法登录，但有控制台访问：

```bash
# 1. 通过控制台登录为 root

# 2. 检查问题
cat /etc/pam.d/system-auth
journalctl -u sshd --since "5 minutes ago"

# 3. 恢复备份
cp -r /etc/pam.d.bak.*/* /etc/pam.d/

# 4. 或者重置到默认 (RHEL 8+)
authselect select sssd --force

# 5. 验证 SSH 正常
systemctl restart sshd
ssh localhost
```

---

## 场景 3：无法登录（需要救援模式）

完全锁死时，使用救援模式：

### RHEL/CentOS/Rocky

```bash
# 1. 重启服务器，在 GRUB 菜单按 e 编辑

# 2. 找到以 linux 开头的行，在行尾添加：
rd.break

# 3. 按 Ctrl+X 启动

# 4. 进入救援模式后：
mount -o remount,rw /sysroot
chroot /sysroot

# 5. 恢复配置
cp -r /etc/pam.d.bak.*/* /etc/pam.d/

# 6. 或重置到默认
authselect select sssd --force

# 7. 如果修改了 SELinux 相关文件
touch /.autorelabel

# 8. 退出并重启
exit
exit
reboot
```

### Debian/Ubuntu

```bash
# 1. 重启，在 GRUB 按住 Shift

# 2. 选择 Advanced options -> Recovery mode

# 3. 选择 root shell

# 4. 挂载文件系统可写
mount -o remount,rw /

# 5. 恢复配置
cp -r /etc/pam.d.bak.*/* /etc/pam.d/

# 6. 重启
reboot
```

---

## 场景 4：AWS EC2 恢复

```bash
# 方法 1：使用 EC2 Serial Console（需要预先启用）
# AWS Console -> EC2 -> 选择实例 -> Actions -> Connect -> EC2 Serial Console

# 方法 2：使用 SSM Session Manager（需要预先配置 SSM Agent）
aws ssm start-session --target i-xxxxxxxxx

# 方法 3：挂载 EBS 卷到另一个实例
# 1. 停止问题实例
# 2. 分离根卷
# 3. 挂载到正常实例
# 4. 修复配置
mount /dev/xvdf1 /mnt
cp -r /mnt/etc/pam.d.bak.*/* /mnt/etc/pam.d/
# 5. 分离并重新挂载到原实例
```

---

## 场景 5：账户被 faillock 锁定

如果只是账户被锁定（不是 PAM 配置错误）：

```bash
# 使用 root 解锁
sudo faillock --user USERNAME --reset

# 验证
sudo faillock --user USERNAME
# 应该显示空输出

# 如果 root 也被锁定，需要救援模式，然后：
# 删除 faillock 数据
rm -f /var/run/faillock/*
```

---

## 预防措施

### 修改前的检查清单

- [ ] 有备用 root 终端打开
- [ ] 有控制台访问权限
- [ ] 已备份所有配置
- [ ] 在测试环境验证过
- [ ] 知道如何进入救援模式

### 备份命令

```bash
# 完整备份
sudo cp -r /etc/pam.d /etc/pam.d.bak.$(date +%Y%m%d-%H%M%S)
sudo cp -r /etc/security /etc/security.bak.$(date +%Y%m%d-%H%M%S)

# 单独备份特定文件
sudo cp /etc/pam.d/system-auth /etc/pam.d/system-auth.bak
sudo cp /etc/security/faillock.conf /etc/security/faillock.conf.bak
```

### 自动恢复 cron（测试环境用）

```bash
# 每 5 分钟自动恢复 PAM 配置（只在测试环境使用！）
*/5 * * * * /bin/cp -r /etc/pam.d.bak.YYYYMMDD/* /etc/pam.d/ 2>/dev/null
```

---

## 联系信息

如果以上方法都不行：

1. 联系数据中心/云提供商请求控制台访问
2. 联系同事使用共享的救援账户
3. 考虑从备份恢复整个系统
