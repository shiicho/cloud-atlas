# 安全交接清单 / Security Handover Checklist

## 文档概要 / Document Overview

| 项目 | 内容 |
|------|------|
| 文档标题 | セキュリティハードニング完了報告書 |
| 文档版本 | 1.0 |
| 作成日 | __________________ |
| 作成者 | __________________ |
| 承認者 | __________________ |

---

## 1. 服务器信息 / Server Information

### 1.1 基本信息

| 项目 | 内容 |
|------|------|
| 主机名 (ホスト名) | __________________ |
| IP 地址 | __________________ |
| 操作系统 | RHEL / Rocky / AlmaLinux ____ |
| 内核版本 | __________________ |
| 用途 | __________________ |
| 所属部门 | __________________ |
| 负责人 | __________________ |

### 1.2 网络信息

| 项目 | 内容 |
|------|------|
| VLAN | __________________ |
| 网关 | __________________ |
| DNS | __________________ |
| NTP | __________________ |

---

## 2. 加固状态汇总 / Hardening Status Summary

### 2.1 总体状态

| 项目 | 状态 | 备注 |
|------|------|------|
| 加固完成日期 | __________________ | |
| OpenSCAP 通过率 | ____% | CIS Level 1 Server |
| 例外项数量 | ____ 项 | 详见例外文档 |
| 验证完成 | [ ] 是 / [ ] 否 | |

### 2.2 各项加固状态

| 加固项目 | 状态 | 验证命令 |
|----------|------|----------|
| SSH 加固 | [ ] 完成 | `sshd -T \| grep -E 'permitrootlogin\|passwordauthentication'` |
| SELinux | [ ] 完成 | `getenforce && ausearch -m avc -ts recent` |
| auditd | [ ] 完成 | `systemctl is-active auditd && auditctl -l \| wc -l` |
| nftables | [ ] 完成 | `nft list ruleset \| grep -E 'dport\|accept'` |
| PAM | [ ] 完成 | `grep pam_faillock /etc/pam.d/system-auth` |
| 文件权限 | [ ] 完成 | `stat -c %a /etc/passwd /etc/shadow` |

---

## 3. SSH 加固详情 / SSH Hardening Details

### 3.1 配置状态

| 配置项 | 当前值 | CIS 要求 | 状态 |
|--------|--------|----------|------|
| PermitRootLogin | ________ | no | [ ] |
| PasswordAuthentication | ________ | no | [ ] |
| MaxAuthTries | ________ | <= 4 | [ ] |
| MaxSessions | ________ | <= 10 | [ ] |
| X11Forwarding | ________ | no | [ ] |
| Banner | ________ | 已设置 | [ ] |

### 3.2 验证命令

```bash
sshd -T | grep -E 'permitrootlogin|passwordauthentication|maxauthtries|maxsessions'
```

### 3.3 配置文件位置

- 主配置: `/etc/ssh/sshd_config`
- 加固配置: `/etc/ssh/sshd_config.d/99-hardening.conf`
- 备份: `/etc/ssh/sshd_config.bak.YYYYMMDD`

---

## 4. SELinux 状态 / SELinux Status

### 4.1 配置状态

| 项目 | 当前值 | 要求 | 状态 |
|------|--------|------|------|
| 运行时模式 | ________ | Enforcing | [ ] |
| 配置文件模式 | ________ | enforcing | [ ] |
| 策略类型 | ________ | targeted | [ ] |

### 4.2 验证命令

```bash
getenforce
sestatus
ausearch -m avc -ts recent
```

### 4.3 注意事项

- [ ] 无未解决的 AVC 拒绝
- [ ] 自定义策略已记录（如有）
- [ ] 布尔值变更已记录（如有）

---

## 5. 防火墙状态 / Firewall Status

### 5.1 配置状态

| 项目 | 当前值 | 状态 |
|------|--------|------|
| 后端 | nftables / firewalld | [ ] |
| 默认策略 | ________ | [ ] |
| 服务状态 | ________ | [ ] |

### 5.2 开放端口

| 端口 | 协议 | 服务 | 源限制 |
|------|------|------|--------|
| 22 | TCP | SSH | __________________ |
| | | | |
| | | | |

### 5.3 验证命令

```bash
nft list ruleset
# 或
firewall-cmd --list-all
```

---

## 6. 审计配置 / Audit Configuration

### 6.1 服务状态

| 项目 | 当前值 | 状态 |
|------|--------|------|
| auditd 状态 | ________ | [ ] |
| 规则数量 | ________ 条 | [ ] |

### 6.2 监控的关键文件

| 文件/目录 | 规则 Key | 状态 |
|-----------|----------|------|
| /etc/passwd | identity | [ ] |
| /etc/shadow | identity | [ ] |
| /etc/ssh/sshd_config | sshd_config | [ ] |
| /etc/sudoers | sudoers | [ ] |
| /etc/sudoers.d | sudoers | [ ] |

### 6.3 验证命令

```bash
systemctl is-active auditd
auditctl -l | head -20
```

---

## 7. PAM 配置 / PAM Configuration

### 7.1 账户锁定策略

| 项目 | 当前值 | 要求 | 状态 |
|------|--------|------|------|
| 锁定阈值 | ________ 次 | 5 | [ ] |
| 锁定时间 | ________ 秒 | 600 | [ ] |
| 失败窗口 | ________ 秒 | 900 | [ ] |

### 7.2 密码策略

| 项目 | 当前值 | 要求 | 状态 |
|------|--------|------|------|
| 最小长度 | ________ | 14 | [ ] |
| 数字要求 | ________ | -1 | [ ] |
| 大写要求 | ________ | -1 | [ ] |
| 小写要求 | ________ | -1 | [ ] |
| 特殊字符 | ________ | -1 | [ ] |

### 7.3 验证命令

```bash
grep -v "^#" /etc/security/faillock.conf | grep -v "^$"
grep -v "^#" /etc/security/pwquality.conf | grep -v "^$"
```

---

## 8. CIS 合规状态 / CIS Compliance Status

### 8.1 扫描结果

| 项目 | 数值 |
|------|------|
| 扫描日期 | __________________ |
| Profile | CIS Level 1 Server |
| 总检查项 | ________ |
| Pass | ________ |
| Fail | ________ |
| Not Applicable | ________ |
| **通过率** | **______%** |

### 8.2 报告位置

- HTML 报告: `__________________.html`
- XML 结果: `__________________.xml`

### 8.3 例外项汇总

| 控制项 ID | 说明 | 原因 | 补偿控制 |
|-----------|------|------|----------|
| | | | |
| | | | |

详细例外说明请参考: `exceptions.md`

---

## 9. 文档清单 / Document List

| 文档 | 文件名 | 位置 |
|------|--------|------|
| 加固检查清单 | checklist.md | |
| 例外文档 | exceptions.md | |
| OpenSCAP 报告 | openscap-report.html | |
| 验证命令 | verification-commands.md | |
| 自动化脚本 | hardening.yaml / .sh | |

---

## 10. 紧急联系 / Emergency Contacts

| 角色 | 姓名 | 电话 | 邮箱 |
|------|------|------|------|
| 服务器管理员 | __________________ | __________________ | __________________ |
| 安全负责人 | __________________ | __________________ | __________________ |
| 运维值班 | __________________ | __________________ | __________________ |

---

## 11. 常见问题处理 / Troubleshooting

### 11.1 SSH 无法登录

```bash
# 检查 SSH 服务状态
systemctl status sshd

# 检查配置语法
sshd -t

# 检查 faillock 锁定
faillock --user <username>

# 解锁用户
faillock --user <username> --reset
```

### 11.2 SELinux 阻止服务

```bash
# 查看 AVC 拒绝
ausearch -m avc -ts recent

# 分析原因
audit2why < /var/log/audit/audit.log

# 临时切换到 Permissive（调试用）
setenforce 0
# 调试完成后立即恢复
setenforce 1
```

### 11.3 防火墙规则问题

```bash
# 查看当前规则
nft list ruleset

# 临时清空规则（紧急情况）
nft flush ruleset

# 恢复规则
nft -f /etc/nftables.conf
```

---

## 12. 变更记录 / Change History

| 日期 | 版本 | 变更内容 | 变更人 | 审批人 |
|------|------|----------|--------|--------|
| | 1.0 | 初始加固 | | |
| | | | | |

---

## 签名确认 / Signatures

### 交接方（引継ぎ側）

| 角色 | 姓名 | 签名 | 日期 |
|------|------|------|------|
| 加固实施人 | __________________ | __________________ | ________ |

### 接收方（受入れ側）

| 角色 | 姓名 | 签名 | 日期 |
|------|------|------|------|
| 运维负责人 | __________________ | __________________ | ________ |
| 安全负责人 | __________________ | __________________ | ________ |

---

## 附录 / Appendix

### A. 快速验证脚本

```bash
#!/bin/bash
# security-status-check.sh
# 快速检查服务器安全状态

echo "=== SSH Status ==="
sshd -T | grep -E 'permitrootlogin|passwordauthentication'

echo ""
echo "=== SELinux Status ==="
getenforce

echo ""
echo "=== Firewall Status ==="
nft list chain inet filter input 2>/dev/null | head -5 || firewall-cmd --list-all

echo ""
echo "=== auditd Status ==="
systemctl is-active auditd
echo "Rules: $(auditctl -l | wc -l)"

echo ""
echo "=== PAM Faillock ==="
grep -E "^deny|^unlock_time" /etc/security/faillock.conf
```

### B. 重要配置文件列表

- `/etc/ssh/sshd_config.d/99-hardening.conf`
- `/etc/selinux/config`
- `/etc/audit/rules.d/90-hardening.rules`
- `/etc/nftables.conf` 或 `/etc/nftables/hardened.nft`
- `/etc/security/faillock.conf`
- `/etc/security/pwquality.conf`
