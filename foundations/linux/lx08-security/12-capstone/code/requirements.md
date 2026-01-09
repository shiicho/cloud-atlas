# Capstone 验收标准 / Acceptance Criteria

## 概述

本文档定义了 LX08-SECURITY Capstone 项目的验收标准。学习者必须满足以下所有"必须"项目，并尽可能完成"推荐"项目。

---

## 必须完成（Required）

### 1. OpenSCAP 合规扫描

| 要求 | 验证方法 | 通过标准 |
|------|----------|----------|
| 执行 CIS Level 1 扫描 | `oscap xccdf eval --profile cis_server_l1` | 命令成功执行 |
| 通过率达标 | 查看报告中的 Pass 百分比 | >= 90% |
| 生成 HTML 报告 | 文件存在且可读 | `openscap-report.html` 存在 |

**验证命令**：

```bash
# 检查报告文件
ls -la openscap-report.html

# 计算通过率
TOTAL=$(grep -c "<result>" final-scan-results.xml)
PASS=$(grep -c "<result>pass</result>" final-scan-results.xml)
echo "Pass Rate: $(echo "scale=1; $PASS * 100 / $TOTAL" | bc)%"
```

### 2. SSH 加固

| 配置项 | 要求值 | 验证命令 |
|--------|--------|----------|
| PermitRootLogin | no | `sshd -T \| grep permitrootlogin` |
| PasswordAuthentication | no | `sshd -T \| grep passwordauthentication` |
| MaxAuthTries | <= 4 | `sshd -T \| grep maxauthtries` |
| 配置语法 | 无错误 | `sshd -t` 返回 0 |

### 3. SELinux

| 要求 | 验证命令 | 通过标准 |
|------|----------|----------|
| Enforcing 模式 | `getenforce` | 输出 "Enforcing" |
| 配置持久化 | `grep SELINUX= /etc/selinux/config` | SELINUX=enforcing |
| 无严重 AVC | `ausearch -m avc -ts today \| wc -l` | 0 或仅已知可接受 |

### 4. auditd 审计

| 要求 | 验证命令 | 通过标准 |
|------|----------|----------|
| 服务运行 | `systemctl is-active auditd` | active |
| 规则已加载 | `auditctl -l \| wc -l` | >= 20 条规则 |
| 关键文件监控 | `auditctl -l \| grep sshd_config` | 有输出 |

### 5. nftables 防火墙

| 要求 | 验证命令 | 通过标准 |
|------|----------|----------|
| 服务启用 | `systemctl is-enabled nftables` | enabled |
| 默认策略 | `nft list chain inet filter input` | policy drop |
| SSH 允许 | `nft list ruleset \| grep "dport 22"` | 有 accept 规则 |

### 6. PAM 配置

| 要求 | 验证命令 | 通过标准 |
|------|----------|----------|
| Faillock 配置 | `grep deny /etc/security/faillock.conf` | deny = 5 |
| 密码长度 | `grep minlen /etc/security/pwquality.conf` | minlen = 14 |
| 密码复杂度 | `grep dcredit /etc/security/pwquality.conf` | dcredit = -1 |

### 7. 文档交付

| 文档 | 必须包含内容 |
|------|-------------|
| `openscap-report.html` | 完整的 CIS Level 1 扫描报告 |
| `exceptions.md` | 每个例外项的原因和补偿控制 |
| `checklist.md` | 所有检查项已勾选或注明状态 |
| `handover.md` | 服务器信息、加固状态、验证命令、紧急联系 |
| `verification-commands.md` | 每个加固项的验证命令 |

---

## 推荐完成（Recommended）

### 自动化配置

| 要求 | 文件 | 说明 |
|------|------|------|
| Ansible playbook | `hardening.yaml` | 可重复执行，幂等 |
| Shell 脚本 | `hardening.sh` | 包含错误处理 |

**验证**：

```bash
# Ansible playbook 语法检查
ansible-playbook --syntax-check hardening.yaml

# 或 Shell 脚本语法检查
bash -n hardening.sh
```

### 高级配置

| 配置 | 说明 |
|------|------|
| Fail2Ban | SSH 暴力破解防护 |
| 限制 core dump | 安全性增强 |
| 禁用不必要文件系统 | cramfs, squashfs, udf |
| sysctl 加固 | 网络安全参数 |

---

## 评分细则

### OpenSCAP 通过率（40%）

| 通过率 | 得分 |
|--------|------|
| >= 95% | 40 分 |
| 90-94% | 35 分 |
| 85-89% | 30 分 |
| 80-84% | 25 分 |
| < 80% | 不及格 |

### 例外文档质量（20%）

| 质量 | 得分 | 标准 |
|------|------|------|
| 优秀 | 20 分 | 每项有业务原因、风险评估、补偿控制、审批签名 |
| 良好 | 15 分 | 有业务原因和补偿控制 |
| 及格 | 10 分 | 只有业务原因 |
| 不及格 | 0 分 | 无文档或只是列表 |

### 自动化程度（20%）

| 方式 | 得分 | 标准 |
|------|------|------|
| Ansible playbook | 20 分 | 完整、幂等、有变量 |
| Shell 脚本 | 15 分 | 有错误处理、可重复执行 |
| 手动记录 | 10 分 | 步骤清晰、可重现 |
| 无自动化 | 5 分 | 只有零散命令 |

### 报告质量（20%）

| 质量 | 得分 | 标准 |
|------|------|------|
| 专业 | 20 分 | 清晰、完整、可追溯、格式规范 |
| 良好 | 15 分 | 基本完整，格式良好 |
| 及格 | 10 分 | 信息完整但格式混乱 |
| 不及格 | 0 分 | 缺少关键信息 |

---

## 提交清单

提交前请确认以下文件都已准备：

```
capstone/
├── reports/
│   ├── openscap-report.html      # [必须] OpenSCAP 扫描报告
│   └── final-scan-results.xml    # [必须] 扫描原始结果
├── docs/
│   ├── exceptions.md             # [必须] 例外文档
│   ├── checklist.md              # [必须] 加固检查清单
│   ├── handover.md               # [必须] 安全交接清单
│   └── verification-commands.md  # [必须] 验证命令文档
└── config/
    ├── hardening.yaml            # [推荐] Ansible playbook
    └── hardening.sh              # [推荐] Shell 脚本
```

---

## 常见失败原因

1. **通过率不达标** - 没有完成所有加固步骤
2. **锁死服务器** - SSH 配置错误导致无法登录（确保有备用访问）
3. **例外文档缺失** - 有失败项但没有文档说明
4. **文档不完整** - 缺少关键信息如服务器名、日期、签名
5. **配置不可重复** - 手动步骤无法在新服务器上重现

---

## 参考资源

- `code/checklist.md` - 完整加固检查清单
- `code/handover-template.md` - 安全交接清单模板
- `code/openscap-pass-criteria.md` - OpenSCAP 评分说明
