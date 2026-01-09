# 12 - Capstone: CIS 合规加固服务器

> **目标**：独立完成生产级服务器安全加固，通过 OpenSCAP CIS Level 1 扫描 90%+  
> **前置**：完成 Lessons 01-11（安全原则、SSH、SELinux、auditd、nftables、PAM、CIS）  
> **时间**：3 小时  
> **交付**：加固配置 + OpenSCAP 报告 + 例外文档 + 安全交接清单  

---

## 项目背景

你是一名即将入职日本 IT 企业的系统工程师。公司要求你独立完成一台 RHEL/Rocky 9 服务器的安全加固，并通过 CIS Level 1 合规扫描。

这是典型的「セキュリティ加固プロジェクト」（Security Hardening Project），也是日本 IT 职场入职后常见的第一个任务。

### 业务场景

```
项目名称：新服务器上线前安全加固
期限：3 小时
验收标准：
├── OpenSCAP CIS Level 1 Server 扫描通过率 >= 90%
├── 所有加固配置可重复执行（Ansible playbook 或脚本）
├── 未通过项有例外文档（含补偿控制）
└── 完整的安全交接清单（引継ぎ資料）
```

### 你需要应用的课程知识

| 课程 | 加固内容 | 本项目对应 |
|------|----------|------------|
| Lesson 02 | SSH 加固 | PermitRootLogin, Key-only, Fail2Ban |
| Lesson 03-05 | SELinux | Enforcing 模式，无 AVC 拒绝 |
| Lesson 06 | Capabilities | 服务最小权限 |
| Lesson 07 | auditd | 关键文件监控规则 |
| Lesson 08 | nftables | 防火墙规则配置 |
| Lesson 09 | PAM | 账户锁定、密码复杂度 |
| Lesson 10-11 | CIS/自动化 | OpenSCAP 扫描、自动化加固 |

---

## 交付物清单

完成本 Capstone 后，你需要提交以下内容：

| 交付物 | 文件名 | 说明 |
|--------|--------|------|
| 加固配置 | `hardening.yaml` 或 `hardening.sh` | 可重复执行的自动化配置 |
| OpenSCAP 报告 | `openscap-report.html` | CIS Level 1 扫描结果 |
| 例外文档 | `exceptions.md` | 未通过项的业务原因和补偿控制 |
| 加固检查清单 | `checklist.md` | 参考 `code/checklist.md` |
| 安全交接清单 | `handover.md` | 参考 `code/handover-template.md` |
| 验证命令文档 | `verification-commands.md` | 每步加固的验证命令 |

---

## Step 0 - 环境准备

### 0.1 获取基础镜像

你需要一个干净的 RHEL 9 或 Rocky Linux 9 虚拟机。

```bash
# 方法 1：使用 Vagrant（推荐）
mkdir ~/security-capstone && cd ~/security-capstone
cat > Vagrantfile << 'EOF'
Vagrant.configure("2") do |config|
  config.vm.box = "rockylinux/9"
  config.vm.hostname = "hardened-server"
  config.vm.network "private_network", ip: "192.168.56.10"
  config.vm.provider "virtualbox" do |vb|
    vb.memory = "2048"
    vb.cpus = 2
  end
end
EOF
vagrant up
vagrant ssh

# 方法 2：使用 Docker（轻量级测试）
# 注意：Docker 无法测试完整的 SELinux 和 systemd
docker run -it --privileged rockylinux:9 /bin/bash

# 方法 3：EC2 实例
# 使用 Rocky Linux 9 AMI
```

### 0.2 安装必要工具

```bash
# 安装 OpenSCAP 和 SCAP Security Guide
sudo dnf install -y openscap-scanner scap-security-guide

# 验证安装
oscap --version
ls /usr/share/xml/scap/ssg/content/

# 安装其他工具
sudo dnf install -y audit fail2ban vim git
```

### 0.3 获取检查清单和模板

```bash
# GitHub（海外用户）
git clone --filter=blob:none --sparse https://github.com/shiicho/cloud-atlas ~/cloud-atlas
cd ~/cloud-atlas && git sparse-checkout set foundations/linux/security/12-capstone

# Gitee（中国大陆用户）
# git clone --filter=blob:none --sparse https://gitee.com/shiicho/cloud-atlas ~/cloud-atlas
# cd ~/cloud-atlas && git sparse-checkout set foundations/linux/security/12-capstone

# 查看提供的模板
ls ~/cloud-atlas/foundations/linux/security/12-capstone/code/
```

---

## Step 1 - 初始扫描：了解基线（15 分钟）

### 1.1 执行初始 OpenSCAP 扫描

在加固之前，先了解当前系统的合规状态。

```bash
# 查看可用的 profile
oscap info /usr/share/xml/scap/ssg/content/ssg-rl9-ds.xml | grep -A 50 "Profiles:"

# 执行 CIS Level 1 Server 扫描
sudo oscap xccdf eval \
  --profile xccdf_org.ssgproject.content_profile_cis_server_l1 \
  --results /tmp/initial-scan-results.xml \
  --report /tmp/initial-scan-report.html \
  /usr/share/xml/scap/ssg/content/ssg-rl9-ds.xml

# 统计结果
grep -E "pass|fail|notapplicable" /tmp/initial-scan-results.xml | sort | uniq -c
```

### 1.2 分析初始报告

```bash
# 在浏览器中查看报告（如果有 GUI）
# 或复制到本地查看
scp vagrant@192.168.56.10:/tmp/initial-scan-report.html .

# 命令行查看失败项
oscap xccdf generate report /tmp/initial-scan-results.xml 2>/dev/null | \
  grep -E "^(Title|Result):" | paste - - | grep "fail"
```

**记录你的初始通过率：_____%**

> **提示**：一般基础系统的初始通过率在 40-60% 左右。你的目标是达到 90%+。  

---

## Step 2 - 规划加固策略（15 分钟）

### 2.1 分析失败项

查看 `/tmp/initial-scan-report.html`，将失败项分类：

| 类别 | 示例失败项 | 对应课程 |
|------|------------|----------|
| SSH 配置 | PermitRootLogin, PasswordAuthentication | Lesson 02 |
| SELinux | 非 Enforcing 模式 | Lesson 03-05 |
| auditd | 审计规则缺失 | Lesson 07 |
| 防火墙 | 规则未配置 | Lesson 08 |
| PAM | 账户锁定未配置 | Lesson 09 |
| 文件权限 | 敏感文件权限过松 | Lesson 01 |
| 服务配置 | 不必要服务运行 | - |

### 2.2 确定处理策略

对于每个失败项，决定：

1. **修复** - 按 CIS 要求配置
2. **例外** - 有业务原因不修改，记录并提供补偿控制
3. **Not Applicable** - 环境不适用（如无某服务）

```bash
# 创建工作目录
mkdir -p ~/capstone/{config,reports,docs}
cd ~/capstone

# 创建规划文档
cat > docs/hardening-plan.md << 'EOF'
# 加固计划

## 1. 必须修复
- [ ] SSH 加固
- [ ] SELinux Enforcing
- [ ] auditd 规则
- [ ] nftables 防火墙
- [ ] PAM 配置
- [ ] 文件权限

## 2. 需要例外的项
- [ ] （列出需要例外的项和原因）

## 3. 执行顺序
1. SSH（先确保不会锁死自己）
2. SELinux
3. auditd
4. nftables
5. PAM
6. 其他文件权限
EOF
```

---

## Step 3 - 执行加固（90-120 分钟）

### 3.1 SSH 加固

```bash
# 备份原配置
sudo cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak.$(date +%Y%m%d)

# 创建加固配置（使用 drop-in 文件）
sudo tee /etc/ssh/sshd_config.d/99-hardening.conf << 'EOF'
# ============================================================
# SSH Hardening Configuration
# CIS Benchmark 5.2.x compliance
# ============================================================

# 禁止 root 直接登录
PermitRootLogin no

# 禁止密码认证（仅密钥）
PasswordAuthentication no

# 禁止空密码
PermitEmptyPasswords no

# SSH 协议版本（默认已是 2）
# Protocol 2

# 日志级别
LogLevel VERBOSE

# 最大认证尝试
MaxAuthTries 4

# 最大会话数
MaxSessions 10

# 连接超时
LoginGraceTime 60

# ClientAlive 设置
ClientAliveInterval 300
ClientAliveCountMax 3

# X11 转发（根据需要）
X11Forwarding no

# 禁止 TCP 转发（根据需要）
# AllowTcpForwarding no

# 禁止用户环境
PermitUserEnvironment no

# 强制使用强密码算法
# Ciphers aes256-gcm@openssh.com,chacha20-poly1305@openssh.com,aes256-ctr
# MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com
# KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org

# 横幅（警告信息）
Banner /etc/issue.net

EOF

# 创建警告横幅
sudo tee /etc/issue.net << 'EOF'
***************************************************************************
                         AUTHORIZED ACCESS ONLY
This system is for authorized users only. All activities are monitored and
logged. Unauthorized access attempts will be reported to the authorities.
***************************************************************************
EOF

# 验证配置语法
sudo sshd -t
echo "SSH config syntax: $?"

# 重启 SSH（确保有备用访问方式！）
sudo systemctl restart sshd

# 验证
sshd -T | grep -E "permitrootlogin|passwordauthentication|maxauthtries"
```

### 3.2 SELinux 配置

```bash
# 检查当前状态
getenforce
sestatus

# 确保 Enforcing 模式
sudo setenforce 1

# 永久配置
sudo sed -i 's/^SELINUX=.*/SELINUX=enforcing/' /etc/selinux/config

# 检查是否有 AVC 拒绝
sudo ausearch -m avc -ts recent

# 如果有问题，参考 Lesson 04-05 排错
```

### 3.3 auditd 审计规则

```bash
# 创建审计规则文件
sudo tee /etc/audit/rules.d/90-hardening.rules << 'EOF'
# ============================================================
# CIS Benchmark Audit Rules
# ============================================================

# 删除现有规则（加载时）
-D

# 设置缓冲区大小
-b 8192

# 失败时的行为（1=继续记录，2=panic）
-f 1

# ----------------
# 时间更改监控
# ----------------
-a always,exit -F arch=b64 -S adjtimex -S settimeofday -k time-change
-a always,exit -F arch=b32 -S adjtimex -S settimeofday -S stime -k time-change
-a always,exit -F arch=b64 -S clock_settime -k time-change
-a always,exit -F arch=b32 -S clock_settime -k time-change
-w /etc/localtime -p wa -k time-change

# ----------------
# 用户和组变更
# ----------------
-w /etc/group -p wa -k identity
-w /etc/passwd -p wa -k identity
-w /etc/gshadow -p wa -k identity
-w /etc/shadow -p wa -k identity
-w /etc/security/opasswd -p wa -k identity

# ----------------
# 网络配置变更
# ----------------
-a always,exit -F arch=b64 -S sethostname -S setdomainname -k system-locale
-a always,exit -F arch=b32 -S sethostname -S setdomainname -k system-locale
-w /etc/issue -p wa -k system-locale
-w /etc/issue.net -p wa -k system-locale
-w /etc/hosts -p wa -k system-locale
-w /etc/hostname -p wa -k system-locale

# ----------------
# SSH 配置监控
# ----------------
-w /etc/ssh/sshd_config -p wa -k sshd_config
-w /etc/ssh/sshd_config.d -p wa -k sshd_config

# ----------------
# sudo 配置监控
# ----------------
-w /etc/sudoers -p wa -k sudoers
-w /etc/sudoers.d -p wa -k sudoers

# ----------------
# 登录和登出
# ----------------
-w /var/log/lastlog -p wa -k logins
-w /var/run/faillock -p wa -k logins
-w /var/log/tallylog -p wa -k logins

# ----------------
# 权限修改
# ----------------
-a always,exit -F arch=b64 -S chmod -S fchmod -S fchmodat -F auid>=1000 -F auid!=4294967295 -k perm_mod
-a always,exit -F arch=b32 -S chmod -S fchmod -S fchmodat -F auid>=1000 -F auid!=4294967295 -k perm_mod
-a always,exit -F arch=b64 -S chown -S fchown -S fchownat -S lchown -F auid>=1000 -F auid!=4294967295 -k perm_mod
-a always,exit -F arch=b32 -S chown -S fchown -S fchownat -S lchown -F auid>=1000 -F auid!=4294967295 -k perm_mod

# ----------------
# 使规则不可变（生产环境启用）
# ----------------
# -e 2

EOF

# 加载规则
sudo augenrules --load

# 验证规则
sudo auditctl -l | head -20

# 检查 auditd 状态
sudo systemctl status auditd
```

### 3.4 nftables 防火墙

```bash
# 创建防火墙配置
sudo tee /etc/nftables/hardened.nft << 'EOF'
#!/usr/sbin/nft -f
# ============================================================
# nftables Hardened Configuration
# CIS Benchmark compliance
# ============================================================

flush ruleset

table inet filter {
    chain input {
        type filter hook input priority 0; policy drop;

        # 已建立连接
        ct state established,related accept

        # 本地回环
        iif "lo" accept

        # ICMP（可选，根据需要）
        ip protocol icmp accept
        ip6 nexthdr icmpv6 accept

        # SSH（限制源 IP，生产环境修改）
        tcp dport 22 accept

        # 其他服务端口（根据需要添加）
        # tcp dport { 80, 443 } accept

        # 日志并丢弃其他
        log prefix "[nftables DROP] " counter drop
    }

    chain forward {
        type filter hook forward priority 0; policy drop;
    }

    chain output {
        type filter hook output priority 0; policy accept;
    }
}

EOF

# 应用配置
sudo nft -c -f /etc/nftables/hardened.nft  # 语法检查
sudo nft -f /etc/nftables/hardened.nft

# 验证
sudo nft list ruleset

# 持久化
sudo systemctl enable nftables
```

### 3.5 PAM 配置

```bash
# 配置 faillock（账户锁定）
sudo tee /etc/security/faillock.conf << 'EOF'
# ============================================================
# Faillock Configuration
# CIS Benchmark 5.4.2 compliance
# ============================================================

# 5 次失败后锁定
deny = 5

# 锁定 10 分钟
unlock_time = 600

# 15 分钟窗口
fail_interval = 900

# 审计
audit

# 静默模式
silent

# 目录
dir = /var/run/faillock

EOF

# 配置密码策略
sudo tee /etc/security/pwquality.conf << 'EOF'
# ============================================================
# Password Quality Configuration
# CIS Benchmark 5.4.1 compliance
# ============================================================

# 最小长度 14
minlen = 14

# 必须包含各类字符
dcredit = -1
ucredit = -1
lcredit = -1
ocredit = -1
minclass = 4

# 字典和用户名检查
dictcheck = 1
usercheck = 1

# 连续字符限制
maxrepeat = 3
maxclassrepeat = 4

# 重试次数
retry = 3

# Root 也强制
enforce_for_root

EOF

# 验证
grep -v "^#" /etc/security/faillock.conf | grep -v "^$"
grep -v "^#" /etc/security/pwquality.conf | grep -v "^$"
```

### 3.6 其他关键配置

```bash
# 配置 /etc/login.defs
sudo sed -i 's/^PASS_MAX_DAYS.*/PASS_MAX_DAYS   90/' /etc/login.defs
sudo sed -i 's/^PASS_MIN_DAYS.*/PASS_MIN_DAYS   7/' /etc/login.defs
sudo sed -i 's/^PASS_WARN_AGE.*/PASS_WARN_AGE   14/' /etc/login.defs

# 禁用不必要的文件系统
cat > /etc/modprobe.d/CIS.conf << 'EOF'
install cramfs /bin/true
install squashfs /bin/true
install udf /bin/true
install usb-storage /bin/true
EOF

# 设置 umask
echo "umask 027" >> /etc/profile.d/cis.sh

# 限制 core dumps
echo "* hard core 0" >> /etc/security/limits.conf
echo "fs.suid_dumpable = 0" >> /etc/sysctl.d/99-hardening.conf

# 应用 sysctl
sudo sysctl -p /etc/sysctl.d/99-hardening.conf
```

---

## Step 4 - 重新扫描（15 分钟）

### 4.1 执行最终扫描

```bash
# 执行最终扫描
sudo oscap xccdf eval \
  --profile xccdf_org.ssgproject.content_profile_cis_server_l1 \
  --results ~/capstone/reports/final-scan-results.xml \
  --report ~/capstone/reports/openscap-report.html \
  /usr/share/xml/scap/ssg/content/ssg-rl9-ds.xml

# 统计结果
echo "=== Final Scan Results ==="
grep -E "<result>" ~/capstone/reports/final-scan-results.xml | sort | uniq -c

# 计算通过率
TOTAL=$(grep -c "<result>" ~/capstone/reports/final-scan-results.xml)
PASS=$(grep -c "<result>pass</result>" ~/capstone/reports/final-scan-results.xml)
RATE=$(echo "scale=1; $PASS * 100 / $TOTAL" | bc)
echo "Pass Rate: $RATE%"
```

### 4.2 分析剩余失败项

```bash
# 列出仍然失败的项
oscap xccdf generate report ~/capstone/reports/final-scan-results.xml 2>/dev/null | \
  grep -E "^(Title|Result):" | paste - - | grep "fail" > ~/capstone/docs/remaining-failures.txt

cat ~/capstone/docs/remaining-failures.txt
```

---

## Step 5 - 文档编写（30 分钟）

### 5.1 创建例外文档

对于无法或不应该修复的项，创建例外文档：

```bash
cat > ~/capstone/docs/exceptions.md << 'EOF'
# 安全例外文档 / Security Exception Documentation

## 文档信息

| 项目 | 内容 |
|------|------|
| 服务器 | hardened-server |
| 日期 | 2026-01-04 |
| 编写人 | [Your Name] |
| 审批人 | [待审批] |

---

## 例外项目

### Exception 1: [控制项 ID]

**控制项**：[CIS 控制项名称]

**当前配置**：[描述当前状态]

**不修改原因**：
- [业务原因 1]
- [业务原因 2]

**风险评估**：[低/中/高]

**补偿控制**：
1. [补偿措施 1]
2. [补偿措施 2]

**审批签名**：__________ 日期：__________

**复审日期**：__________

---

### Exception 2: [控制项 ID]

...

---

## 例外汇总

| 控制项 | 原因 | 风险等级 | 补偿控制 |
|--------|------|----------|----------|
| | | | |

EOF
```

### 5.2 创建验证命令文档

```bash
cat > ~/capstone/docs/verification-commands.md << 'EOF'
# 加固验证命令 / Verification Commands

## SSH 配置验证

```bash
# 检查 SSH 配置
sshd -T | grep -E "permitrootlogin|passwordauthentication|maxauthtries|maxsessions"

# 预期输出
# permitrootlogin no
# passwordauthentication no
# maxauthtries 4
# maxsessions 10
```

## SELinux 验证

```bash
# 检查模式
getenforce
# 预期: Enforcing

# 检查配置文件
grep "^SELINUX=" /etc/selinux/config
# 预期: SELINUX=enforcing

# 检查 AVC 拒绝
ausearch -m avc -ts recent
# 预期: 无输出或只有已知可接受的拒绝
```

## auditd 验证

```bash
# 检查服务状态
systemctl status auditd
# 预期: active (running)

# 检查规则数量
auditctl -l | wc -l
# 预期: > 20

# 检查关键规则
auditctl -l | grep -E "sshd_config|sudoers|identity"
```

## nftables 验证

```bash
# 检查服务状态
systemctl status nftables
# 预期: active

# 检查规则
nft list ruleset | grep -E "dport|accept|drop"

# 检查默认策略
nft list chain inet filter input | head -5
# 预期: policy drop
```

## PAM 验证

```bash
# 检查 faillock 配置
grep -v "^#" /etc/security/faillock.conf | grep -v "^$"
# 预期: deny = 5, unlock_time = 600

# 检查 pwquality 配置
grep -v "^#" /etc/security/pwquality.conf | grep -v "^$"
# 预期: minlen = 14, dcredit = -1, etc.

# 测试密码强度
echo "WeakPass1" | pwscore
# 预期: 失败或低分
```

## 文件权限验证

```bash
# 关键文件权限
stat -c "%a %U:%G %n" /etc/passwd /etc/shadow /etc/ssh/sshd_config
# 预期:
# 644 root:root /etc/passwd
# 000 root:root /etc/shadow
# 600 root:root /etc/ssh/sshd_config
```

EOF
```

### 5.3 填写安全交接清单

使用提供的模板 `code/handover-template.md` 填写你的服务器信息。

---

## Step 6 - 创建自动化脚本（可选但推荐）

如果你会 Ansible，创建一个可重复执行的 playbook：

```bash
cat > ~/capstone/config/hardening.yaml << 'EOF'
---
# ============================================================
# CIS Level 1 Hardening Playbook
# Target: RHEL/Rocky 9
# ============================================================

- name: CIS Level 1 Server Hardening
  hosts: all
  become: yes

  vars:
    ssh_permit_root_login: "no"
    ssh_password_auth: "no"
    ssh_max_auth_tries: 4
    faillock_deny: 5
    faillock_unlock_time: 600
    password_min_length: 14

  tasks:
    # SSH Hardening
    - name: Configure SSH hardening
      copy:
        dest: /etc/ssh/sshd_config.d/99-hardening.conf
        content: |
          PermitRootLogin {{ ssh_permit_root_login }}
          PasswordAuthentication {{ ssh_password_auth }}
          PermitEmptyPasswords no
          MaxAuthTries {{ ssh_max_auth_tries }}
          MaxSessions 10
          LoginGraceTime 60
          ClientAliveInterval 300
          ClientAliveCountMax 3
          X11Forwarding no
          Banner /etc/issue.net
      notify: restart sshd

    # SELinux
    - name: Ensure SELinux is enforcing
      selinux:
        policy: targeted
        state: enforcing

    # Faillock
    - name: Configure faillock
      copy:
        dest: /etc/security/faillock.conf
        content: |
          deny = {{ faillock_deny }}
          unlock_time = {{ faillock_unlock_time }}
          fail_interval = 900
          audit
          silent

    # Password Quality
    - name: Configure pwquality
      copy:
        dest: /etc/security/pwquality.conf
        content: |
          minlen = {{ password_min_length }}
          dcredit = -1
          ucredit = -1
          lcredit = -1
          ocredit = -1
          minclass = 4
          dictcheck = 1
          usercheck = 1
          maxrepeat = 3
          retry = 3
          enforce_for_root

  handlers:
    - name: restart sshd
      service:
        name: sshd
        state: restarted

EOF
```

---

## 评分标准

| 评估项目 | 权重 | 优秀 | 良好 | 及格 |
|----------|------|------|------|------|
| **OpenSCAP 通过率** | 40% | >= 95% | >= 90% | >= 80% |
| **例外文档质量** | 20% | 完整的补偿控制 | 有理由但控制不完整 | 只列出不修复项 |
| **自动化程度** | 20% | Ansible playbook | Shell 脚本 | 手动步骤记录 |
| **报告质量** | 20% | 清晰、可追溯、专业 | 基本完整 | 缺少关键信息 |

---

## 职场小贴士（Japan IT Context）

### 本项目对应的日本 IT 职场技能

| 技能 | 日语术语 | 对应内容 |
|------|----------|----------|
| 安全加固 | セキュリティハードニング | 全课程内容 |
| 合规审计 | コンプライアンス監査 | OpenSCAP 扫描 |
| 例外管理 | 例外管理 | Exception documentation |
| 引继资料 | 引継ぎ資料 | Handover checklist |
| 变更管理 | 変更管理 | 文档化的加固流程 |

### 面试加分项

**Q: セキュリティハードニングの経験について教えてください。**

A: 实际回答示例：

```
CIS Benchmark Level 1 に基づいて RHEL 9 サーバーのハードニングを
実施しました。具体的には：

1. SSH の強化（鍵認証のみ、root ログイン禁止）
2. SELinux の enforcing モード設定
3. auditd による監査ログの設定
4. nftables によるファイアウォール設定
5. PAM によるアカウントロックポリシー

OpenSCAP を使用してコンプライアンススキャンを行い、90% 以上の
準拠率を達成しました。修正できない項目については、補償コントロール
を含む例外文書を作成しました。

また、作業は Ansible playbook で自動化し、再現可能な形で
ドキュメント化しています。
```

### 项目完成后的真实工作流程

在日本 IT 企业，完成加固后通常需要：

1. **报告提交**（報告書提出）- 向上司报告完成状态
2. **审查会议**（レビュー会議）- 与安全团队 review 例外项
3. **变更管理登记**（変更管理登録）- 在 ITSM 系统登记变更
4. **引继**（引継ぎ）- 将交接清单交给运维团队

---

## 检查清单

完成本 Capstone 后，确认以下内容：

### 技术成果

- [ ] OpenSCAP CIS Level 1 扫描通过率 >= 90%
- [ ] SSH 配置：PermitRootLogin no, PasswordAuthentication no
- [ ] SELinux：Enforcing 模式，无未解决 AVC 拒绝
- [ ] auditd：关键文件监控规则已配置
- [ ] nftables：防火墙规则配置，默认 DROP
- [ ] PAM：账户锁定和密码策略已配置

### 文档成果

- [ ] `openscap-report.html` - 最终扫描报告
- [ ] `exceptions.md` - 例外文档（含补偿控制）
- [ ] `checklist.md` - 加固检查清单（已勾选）
- [ ] `handover.md` - 安全交接清单（已填写）
- [ ] `verification-commands.md` - 验证命令文档
- [ ] `hardening.yaml` 或 `hardening.sh` - 自动化配置

### 技能确认

- [ ] 能够独立执行 OpenSCAP 合规扫描
- [ ] 能够分析扫描结果并制定加固计划
- [ ] 能够编写专业的例外文档
- [ ] 能够创建可重复的自动化加固脚本
- [ ] 能够编写日本 IT 企业风格的交接资料

---

## 常见问题

### Q: 初始扫描通过率很低，正常吗？

A: 是的，基础系统通常只有 40-60% 的通过率。这是正常的，你的任务就是提升它。

### Q: 有些项无论如何都改不了怎么办？

A: 这很正常。记录在例外文档中，说明原因并提供补偿控制。90% 的目标允许有 10% 的例外。

### Q: 如何在不锁死自己的情况下测试 SSH 配置？

A: 始终保持一个已登录的 root 会话，或确保有控制台访问权限。测试时开新终端。

### Q: OpenSCAP 扫描时间很长怎么办？

A: 这是正常的，完整扫描可能需要 5-10 分钟。可以使用 `--profile` 指定特定 profile 加速。

---

## 延伸阅读

- [CIS Benchmarks Download](https://www.cisecurity.org/cis-benchmarks) - 官方 CIS 基准文档
- [OpenSCAP Documentation](https://www.open-scap.org/documentation/) - OpenSCAP 官方文档
- [RHEL 9 Security Hardening](https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/9/html/security_hardening/) - Red Hat 官方指南
- 相关课程：[Lesson 10 - CIS Benchmarks](../10-cis-benchmarks/) - OpenSCAP 详细使用
- 相关课程：[Lesson 11 - Hardening Automation](../11-hardening-automation/) - Ansible 自动化

---

## 课程总结

恭喜！完成这个 Capstone，你已经具备了：

1. **独立加固** Linux 服务器到 CIS Level 1 标准的能力
2. **使用 OpenSCAP** 进行合规扫描和报告生成
3. **编写专业文档** - 例外文档、交接清单
4. **自动化思维** - 将手动步骤转化为可重复的脚本/playbook
5. **日本 IT 职场** 安全加固项目的完整流程经验

这些技能是日本 IT 企业基础设施工程师的核心能力，将帮助你在面试和实际工作中脱颖而出。

**下一步学习建议**：

- **LX09-PERFORMANCE** - 安全加固后的性能影响分析
- **LX11-CONTAINERS** - 容器安全（namespace, cgroup, seccomp）
- **LX12-CLOUD** - 云安全（IAM, 元数据保护）

---

## 系列导航

[上一课：11 - 安全加固自动化](../11-hardening-automation/) | [系列首页](../) | **课程完成！**
