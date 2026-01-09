# 安全加固检查清单 / Security Hardening Checklist

## 文档信息

| 项目 | 内容 |
|------|------|
| 服务器名 | __________________ |
| IP 地址 | __________________ |
| 操作系统 | RHEL / Rocky / AlmaLinux 9 |
| 加固日期 | __________________ |
| 操作人员 | __________________ |

---

## 1. SSH 加固 (Lesson 02)

### 1.1 基础配置

| 检查项 | 目标值 | 验证命令 | 状态 |
|--------|--------|----------|------|
| PermitRootLogin | no | `sshd -T \| grep permitrootlogin` | [ ] |
| PasswordAuthentication | no | `sshd -T \| grep passwordauthentication` | [ ] |
| PermitEmptyPasswords | no | `sshd -T \| grep permitemptypasswords` | [ ] |
| MaxAuthTries | <= 4 | `sshd -T \| grep maxauthtries` | [ ] |
| MaxSessions | <= 10 | `sshd -T \| grep maxsessions` | [ ] |
| LoginGraceTime | <= 60 | `sshd -T \| grep logingracetime` | [ ] |
| X11Forwarding | no | `sshd -T \| grep x11forwarding` | [ ] |
| LogLevel | VERBOSE 或 INFO | `sshd -T \| grep loglevel` | [ ] |

### 1.2 密钥算法

| 检查项 | 验证命令 | 状态 |
|--------|----------|------|
| 使用 ed25519 或 RSA-4096 密钥 | `ls -la ~/.ssh/*.pub` | [ ] |
| 禁用弱算法 (ssh-rsa) | 检查 sshd_config | [ ] |

### 1.3 配置语法

| 检查项 | 验证命令 | 状态 |
|--------|----------|------|
| 配置语法正确 | `sshd -t` 返回 0 | [ ] |
| 服务正常运行 | `systemctl status sshd` | [ ] |

### 1.4 防暴力破解

| 检查项 | 验证命令 | 状态 |
|--------|----------|------|
| Fail2Ban 已安装 | `rpm -q fail2ban` 或 `dpkg -l fail2ban` | [ ] |
| Fail2Ban SSH jail 已启用 | `fail2ban-client status sshd` | [ ] |

---

## 2. SELinux (Lessons 03-05)

### 2.1 模式检查

| 检查项 | 目标值 | 验证命令 | 状态 |
|--------|--------|----------|------|
| 运行时模式 | Enforcing | `getenforce` | [ ] |
| 配置文件模式 | enforcing | `grep ^SELINUX= /etc/selinux/config` | [ ] |
| 策略类型 | targeted | `sestatus \| grep "Loaded policy"` | [ ] |

### 2.2 AVC 拒绝检查

| 检查项 | 验证命令 | 状态 |
|--------|----------|------|
| 无未解决 AVC 拒绝 | `ausearch -m avc -ts today` | [ ] |
| setroubleshoot 日志清洁 | `journalctl -t setroubleshoot -p warning` | [ ] |

### 2.3 布尔值检查

| 检查项 | 验证命令 | 状态 |
|--------|----------|------|
| 关键布尔值已审核 | `getsebool -a \| grep httpd` | [ ] |
| 无非必要的 on 状态布尔值 | 根据业务需求检查 | [ ] |

---

## 3. Capabilities (Lesson 06)

### 3.1 服务权限

| 检查项 | 验证命令 | 状态 |
|--------|----------|------|
| 服务使用最小权限 | `systemctl show <service> \| grep Capability` | [ ] |
| 无不必要 CAP_SYS_ADMIN | `getcap -r / 2>/dev/null \| grep sys_admin` | [ ] |

### 3.2 SUID/SGID 审计

| 检查项 | 验证命令 | 状态 |
|--------|----------|------|
| SUID 文件已审计 | `find / -perm -4000 -type f 2>/dev/null` | [ ] |
| SGID 文件已审计 | `find / -perm -2000 -type f 2>/dev/null` | [ ] |
| 非必要 SUID 已移除 | 根据审计结果 | [ ] |

---

## 4. auditd 审计 (Lesson 07)

### 4.1 服务状态

| 检查项 | 目标值 | 验证命令 | 状态 |
|--------|--------|----------|------|
| auditd 运行中 | active | `systemctl is-active auditd` | [ ] |
| auditd 已启用 | enabled | `systemctl is-enabled auditd` | [ ] |
| 规则已加载 | >= 20 条 | `auditctl -l \| wc -l` | [ ] |

### 4.2 关键规则检查

| 监控目标 | 验证命令 | 状态 |
|----------|----------|------|
| 用户/组变更 | `auditctl -l \| grep identity` | [ ] |
| SSH 配置 | `auditctl -l \| grep sshd_config` | [ ] |
| sudo 配置 | `auditctl -l \| grep sudoers` | [ ] |
| 时间变更 | `auditctl -l \| grep time-change` | [ ] |
| 网络配置 | `auditctl -l \| grep system-locale` | [ ] |
| 登录事件 | `auditctl -l \| grep logins` | [ ] |

### 4.3 日志存储

| 检查项 | 验证命令 | 状态 |
|--------|----------|------|
| 审计日志存在 | `ls -la /var/log/audit/audit.log` | [ ] |
| 日志轮转已配置 | `grep max_log_file /etc/audit/auditd.conf` | [ ] |

---

## 5. nftables 防火墙 (Lesson 08)

### 5.1 服务状态

| 检查项 | 目标值 | 验证命令 | 状态 |
|--------|--------|----------|------|
| nftables 运行中 | active | `systemctl is-active nftables` | [ ] |
| nftables 已启用 | enabled | `systemctl is-enabled nftables` | [ ] |

### 5.2 规则检查

| 检查项 | 验证命令 | 状态 |
|--------|----------|------|
| 默认 input 策略为 drop | `nft list chain inet filter input \| grep policy` | [ ] |
| 已建立连接允许 | `nft list ruleset \| grep established` | [ ] |
| SSH 端口开放 | `nft list ruleset \| grep "dport 22"` | [ ] |
| 仅必要端口开放 | 审核 `nft list ruleset` 输出 | [ ] |
| 有日志规则 | `nft list ruleset \| grep log` | [ ] |

### 5.3 配置持久化

| 检查项 | 验证命令 | 状态 |
|--------|----------|------|
| 配置文件存在 | `ls /etc/nftables.conf` 或 `/etc/nftables/` | [ ] |
| 重启后规则保持 | 重启测试 | [ ] |

---

## 6. PAM 配置 (Lesson 09)

### 6.1 账户锁定 (pam_faillock)

| 检查项 | 目标值 | 验证命令 | 状态 |
|--------|--------|----------|------|
| 失败锁定次数 | 5 | `grep deny /etc/security/faillock.conf` | [ ] |
| 锁定时间 | 600 秒 | `grep unlock_time /etc/security/faillock.conf` | [ ] |
| 审计已启用 | audit | `grep audit /etc/security/faillock.conf` | [ ] |

### 6.2 密码策略 (pam_pwquality)

| 检查项 | 目标值 | 验证命令 | 状态 |
|--------|--------|----------|------|
| 最小长度 | 14 | `grep minlen /etc/security/pwquality.conf` | [ ] |
| 数字要求 | -1 | `grep dcredit /etc/security/pwquality.conf` | [ ] |
| 大写要求 | -1 | `grep ucredit /etc/security/pwquality.conf` | [ ] |
| 小写要求 | -1 | `grep lcredit /etc/security/pwquality.conf` | [ ] |
| 特殊字符要求 | -1 | `grep ocredit /etc/security/pwquality.conf` | [ ] |
| 字典检查 | 1 | `grep dictcheck /etc/security/pwquality.conf` | [ ] |

### 6.3 密码老化

| 检查项 | 目标值 | 验证命令 | 状态 |
|--------|--------|----------|------|
| PASS_MAX_DAYS | 90 | `grep PASS_MAX_DAYS /etc/login.defs` | [ ] |
| PASS_MIN_DAYS | 7 | `grep PASS_MIN_DAYS /etc/login.defs` | [ ] |
| PASS_WARN_AGE | 14 | `grep PASS_WARN_AGE /etc/login.defs` | [ ] |

---

## 7. CIS 合规 (Lesson 10)

### 7.1 OpenSCAP 扫描

| 检查项 | 目标值 | 验证命令 | 状态 |
|--------|--------|----------|------|
| OpenSCAP 已安装 | - | `oscap --version` | [ ] |
| SCAP 内容已安装 | - | `ls /usr/share/xml/scap/ssg/content/` | [ ] |
| CIS Level 1 扫描通过率 | >= 90% | 查看报告 | [ ] |

### 7.2 例外管理

| 检查项 | 验证方法 | 状态 |
|--------|----------|------|
| 失败项已分类 | 查看例外文档 | [ ] |
| 例外有业务原因 | 查看例外文档 | [ ] |
| 例外有补偿控制 | 查看例外文档 | [ ] |

---

## 8. 其他安全配置

### 8.1 文件系统

| 检查项 | 验证命令 | 状态 |
|--------|----------|------|
| /etc/passwd 权限 644 | `stat -c %a /etc/passwd` | [ ] |
| /etc/shadow 权限 000 | `stat -c %a /etc/shadow` | [ ] |
| /etc/group 权限 644 | `stat -c %a /etc/group` | [ ] |
| /etc/gshadow 权限 000 | `stat -c %a /etc/gshadow` | [ ] |
| /boot/grub2 权限限制 | `stat -c %a /boot/grub2/grub.cfg` | [ ] |

### 8.2 内核参数

| 检查项 | 目标值 | 验证命令 | 状态 |
|--------|--------|----------|------|
| IP 转发禁用 | 0 | `sysctl net.ipv4.ip_forward` | [ ] |
| ICMP 重定向禁用 | 0 | `sysctl net.ipv4.conf.all.accept_redirects` | [ ] |
| 源路由禁用 | 0 | `sysctl net.ipv4.conf.all.accept_source_route` | [ ] |
| Core dump 禁用 | 0 | `sysctl fs.suid_dumpable` | [ ] |

### 8.3 不必要服务

| 检查项 | 验证命令 | 状态 |
|--------|----------|------|
| 已审计运行中服务 | `systemctl list-units --type=service --state=running` | [ ] |
| 已禁用不必要服务 | 根据审计结果 | [ ] |

---

## 签名确认

| 角色 | 签名 | 日期 |
|------|------|------|
| 操作人员 | __________________ | ________ |
| 审核人员 | __________________ | ________ |
| 安全负责人 | __________________ | ________ |

---

## 版本历史

| 版本 | 日期 | 修改内容 | 修改人 |
|------|------|----------|--------|
| 1.0 | | 初始版本 | |
