# 10 - CIS Benchmarks 合规实战（CIS Benchmarks Compliance）

> **目标**：掌握 CIS Benchmark 合规扫描、结果分析和例外管理  
> **前置**：完成 Lesson 01-09（安全原则、SSH、SELinux、auditd、PAM）  
> **时间**：⚡ 40 分钟（速读）/ 🔬 150 分钟（完整实操）  
> **关键理念**：扫描是起点，不是终点；例外必须文档化；一键修复有风险  

---

## 将学到的内容

1. 理解 CIS Benchmark 结构（Level 1 vs Level 2）
2. 使用 OpenSCAP 进行合规扫描
3. 分析扫描结果和修复建议
4. **核心技能**：例外管理和文档化
5. 理解自动修复的风险（一键修复的危险）

---

## 先跑起来！（15 分钟）

> 在学习理论之前，先对你的服务器进行一次真实的合规扫描。  

```bash
# 1. 安装 OpenSCAP 和安全指南
# RHEL/CentOS/Rocky
sudo dnf install openscap-scanner scap-security-guide -y

# Debian/Ubuntu（内容位置不同）
# sudo apt install libopenscap8 ssg-debian ssg-base -y

# 2. 查看可用的安全配置文件
oscap info /usr/share/xml/scap/ssg/content/ssg-rhel9-ds.xml 2>/dev/null | grep -A 50 "Profiles:" | head -30

# 3. 执行 CIS Level 1 快速扫描（约 2-5 分钟）
sudo oscap xccdf eval \
  --profile xccdf_org.ssgproject.content_profile_cis_server_l1 \
  --results /tmp/cis-scan-results.xml \
  --report /tmp/cis-scan-report.html \
  /usr/share/xml/scap/ssg/content/ssg-rhel9-ds.xml 2>/dev/null

# 4. 查看扫描摘要
echo "=== 扫描结果摘要 ==="
grep -E "rule result|pass|fail|notapplicable" /tmp/cis-scan-results.xml | \
  sed -n 's/.*result="\([^"]*\)".*/\1/p' | sort | uniq -c | sort -rn

# 5. 在浏览器中查看详细报告（如果有图形界面）
# firefox /tmp/cis-scan-report.html
# 或者复制到本地查看
ls -la /tmp/cis-scan-report.html
```

**你刚刚：**

- 对系统进行了 CIS Level 1 合规扫描
- 生成了 XML 结果文件和 HTML 报告
- 看到了 Pass/Fail/Not Applicable 的统计

**现实检查**：

- 大多数未加固的系统首次扫描 Pass 率约为 **50-70%**
- 不要惊慌！这正是扫描的意义——发现需要改进的地方
- 重要的是**理解**每个 Fail 项，而不是盲目修复

---

## Step 1 - CIS Benchmarks 概述（20 分钟）

### 1.1 什么是 CIS？

**CIS**（Center for Internet Security）是一个非营利组织，发布行业公认的安全配置基准。

```
CIS 生态系统：

┌─────────────────────────────────────────────────────────────────┐
│                    CIS (Center for Internet Security)            │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│   ┌─────────────────┐   ┌─────────────────┐   ┌──────────────┐  │
│   │  CIS Benchmarks │   │   CIS Controls  │   │  CIS-CAT     │  │
│   │   (配置基准)     │   │   (安全控制框架)  │   │  (评估工具)  │  │
│   └────────┬────────┘   └─────────────────┘   └──────────────┘  │
│            │                                                     │
│            ▼                                                     │
│   ┌─────────────────────────────────────────────────────────┐   │
│   │              CIS Benchmark 文档                          │   │
│   │  - CIS Red Hat Enterprise Linux 9 Benchmark             │   │
│   │  - CIS Ubuntu Linux 22.04 LTS Benchmark                 │   │
│   │  - CIS Amazon Linux 2023 Benchmark                      │   │
│   │  - CIS Windows Server 2022 Benchmark                    │   │
│   │  - CIS Docker Benchmark                                 │   │
│   │  - CIS Kubernetes Benchmark                             │   │
│   └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

<details>
<summary>View ASCII source</summary>

```
CIS 生态系统：

┌─────────────────────────────────────────────────────────────────┐
│                    CIS (Center for Internet Security)            │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│   ┌─────────────────┐   ┌─────────────────┐   ┌──────────────┐  │
│   │  CIS Benchmarks │   │   CIS Controls  │   │  CIS-CAT     │  │
│   │   (配置基准)     │   │   (安全控制框架)  │   │  (评估工具)  │  │
│   └────────┬────────┘   └─────────────────┘   └──────────────┘  │
│            │                                                     │
│            ▼                                                     │
│   ┌─────────────────────────────────────────────────────────────┐   │
│   │              CIS Benchmark 文档                          │   │
│   │  - CIS Red Hat Enterprise Linux 9 Benchmark             │   │
│   │  - CIS Ubuntu Linux 22.04 LTS Benchmark                 │   │
│   │  - CIS Amazon Linux 2023 Benchmark                      │   │
│   │  - CIS Windows Server 2022 Benchmark                    │   │
│   │  - CIS Docker Benchmark                                 │   │
│   │  - CIS Kubernetes Benchmark                             │   │
│   └─────────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

</details>

### 1.2 Benchmark vs Hardening

| 概念 | 含义 | 类比 |
|------|------|------|
| **Benchmark** | 安全配置标准/检查清单 | 考试大纲 |
| **Hardening** | 实施安全配置的过程 | 备考过程 |
| **Compliance** | 符合 Benchmark 要求 | 考试通过 |
| **Audit** | 验证合规状态 | 参加考试 |

### 1.3 Level 1 vs Level 2

CIS Benchmark 分为两个级别：

| 级别 | 目标 | 对业务影响 | 适用场景 |
|------|------|-----------|----------|
| **Level 1** | 基础安全 | 最小 | 所有服务器 |
| **Level 2** | 深度防御 | 可能影响功能 | 高安全环境 |

```
Level 1 示例（低影响）：
- 禁用不必要的服务
- 设置文件权限
- 配置密码策略

Level 2 示例（可能影响业务）：
- 禁用 USB 存储（可能影响运维）
- 更严格的审计规则（性能开销）
- 限制内核模块加载（可能影响驱动）
```

### 1.4 Scored vs Not Scored

| 类型 | 含义 | 处理方式 |
|------|------|----------|
| **Scored** | 计入合规评分 | 必须处理或申请例外 |
| **Not Scored** | 不计入评分 | 建议实施，但不强制 |

```bash
# 查看 Benchmark 文档中的标记示例
# [Scored] 5.2.1 Ensure permissions on /etc/ssh/sshd_config are configured
# [Not Scored] 5.2.1.1 Ensure SSH access is limited (site-specific)
```

---

## Step 2 - OpenSCAP 深入使用（30 分钟）

### 2.1 OpenSCAP 工具链

```
OpenSCAP 工作流：

┌─────────────┐     ┌─────────────────┐     ┌─────────────────┐
│  SCAP 内容   │────▶│    oscap CLI    │────▶│  扫描结果/报告   │
│ (SSG 指南)   │     │   (扫描引擎)     │     │  (XML/HTML)     │
└─────────────┘     └─────────────────┘     └─────────────────┘
       │                    │                        │
       │                    │                        ▼
       │                    │              ┌─────────────────┐
       │                    │              │    分析/修复     │
       │                    ▼              │  - 理解失败原因   │
       │           ┌─────────────────┐     │  - 评估业务影响   │
       │           │   remediation   │     │  - 实施或例外    │
       │           │    (修复脚本)    │     └─────────────────┘
       │           └─────────────────┘
       │
       ▼
┌─────────────────────────────────────────────┐
│  SCAP Security Guide (SSG) 内容结构         │
│                                             │
│  /usr/share/xml/scap/ssg/content/           │
│  ├── ssg-rhel9-ds.xml      # RHEL 9 数据流  │
│  ├── ssg-rhel8-ds.xml      # RHEL 8 数据流  │
│  ├── ssg-fedora-ds.xml     # Fedora         │
│  └── ssg-ubuntu2204-ds.xml # Ubuntu 22.04   │
│                                             │
│  Profile 示例：                              │
│  - cis_server_l1    (CIS Level 1 Server)   │
│  - cis_server_l2    (CIS Level 2 Server)   │
│  - cis_workstation_l1                       │
│  - stig             (DISA STIG)            │
│  - pci-dss          (PCI DSS)              │
└─────────────────────────────────────────────┘
```

<details>
<summary>View ASCII source</summary>

```
OpenSCAP 工作流：

┌─────────────┐     ┌─────────────────┐     ┌─────────────────┐
│  SCAP 内容   │────▶│    oscap CLI    │────▶│  扫描结果/报告   │
│ (SSG 指南)   │     │   (扫描引擎)     │     │  (XML/HTML)     │
└─────────────┘     └─────────────────┘     └─────────────────┘
       │                    │                        │
       │                    │                        ▼
       │                    │              ┌─────────────────┐
       │                    │              │    分析/修复     │
       │                    ▼              │  - 理解失败原因   │
       │           ┌─────────────────┐     │  - 评估业务影响   │
       │           │   remediation   │     │  - 实施或例外    │
       │           │    (修复脚本)    │     └─────────────────┘
       │           └─────────────────┘
       │
       ▼
┌─────────────────────────────────────────────┐
│  SCAP Security Guide (SSG) 内容结构         │
│                                             │
│  /usr/share/xml/scap/ssg/content/           │
│  ├── ssg-rhel9-ds.xml      # RHEL 9 数据流  │
│  ├── ssg-rhel8-ds.xml      # RHEL 8 数据流  │
│  ├── ssg-fedora-ds.xml     # Fedora         │
│  └── ssg-ubuntu2204-ds.xml # Ubuntu 22.04   │
│                                             │
│  Profile 示例：                              │
│  - cis_server_l1    (CIS Level 1 Server)   │
│  - cis_server_l2    (CIS Level 2 Server)   │
│  - cis_workstation_l1                       │
│  - stig             (DISA STIG)            │
│  - pci-dss          (PCI DSS)              │
└─────────────────────────────────────────────┘
```

</details>

### 2.2 oscap 常用命令

```bash
# 查看 SCAP 内容信息
oscap info /usr/share/xml/scap/ssg/content/ssg-rhel9-ds.xml

# 列出所有可用 profile
oscap info /usr/share/xml/scap/ssg/content/ssg-rhel9-ds.xml | grep -E "Id:|Title:"

# 执行扫描（完整命令）
sudo oscap xccdf eval \
  --profile xccdf_org.ssgproject.content_profile_cis_server_l1 \
  --results /var/log/openscap/cis-results-$(date +%Y%m%d).xml \
  --report /var/log/openscap/cis-report-$(date +%Y%m%d).html \
  /usr/share/xml/scap/ssg/content/ssg-rhel9-ds.xml

# 只检查特定规则
sudo oscap xccdf eval \
  --profile xccdf_org.ssgproject.content_profile_cis_server_l1 \
  --rule xccdf_org.ssgproject.content_rule_sshd_disable_root_login \
  /usr/share/xml/scap/ssg/content/ssg-rhel9-ds.xml

# 生成修复脚本（谨慎使用！）
sudo oscap xccdf generate fix \
  --profile xccdf_org.ssgproject.content_profile_cis_server_l1 \
  --fix-type bash \
  /usr/share/xml/scap/ssg/content/ssg-rhel9-ds.xml > /tmp/remediation.sh
```

### 2.3 使用扫描脚本

我们提供了一个封装好的扫描脚本：

```bash
# 查看脚本内容
cat code/openscap-scan.sh

# 执行扫描
sudo bash code/openscap-scan.sh

# 脚本会：
# 1. 自动检测操作系统和 SCAP 内容位置
# 2. 执行 CIS Level 1 扫描
# 3. 生成带时间戳的报告
# 4. 输出摘要统计
```

### 2.4 报告格式

| 格式 | 用途 | 命令参数 |
|------|------|----------|
| **HTML** | 人工审阅，浏览器查看 | `--report file.html` |
| **XML** | 程序处理，工具集成 | `--results file.xml` |
| **ARF** | 完整结果归档 | `--results-arf file.xml` |

---

## Step 3 - 结果分析（30 分钟）

### 3.1 理解扫描结果状态

| 状态 | 含义 | 处理方式 |
|------|------|----------|
| **Pass** | 符合要求 | 无需操作 |
| **Fail** | 不符合要求 | 修复或申请例外 |
| **Not Applicable** | 不适用（如检查 httpd，但系统未安装） | 无需操作 |
| **Not Checked** | 无法自动检查，需人工验证 | 人工审核 |
| **Error** | 检查过程出错 | 排查原因 |

### 3.2 分析 Fail 项

```bash
# 从 XML 结果中提取 Fail 项
grep -B 5 'result="fail"' /tmp/cis-scan-results.xml | grep "rule id" | head -20

# 更友好的方式：使用 oscap 生成报告
sudo oscap xccdf generate report /tmp/cis-scan-results.xml > /tmp/fail-summary.html

# 或者使用 xmllint 提取（需要安装 libxml2-utils）
xmllint --xpath "//*[local-name()='rule-result'][@result='fail']/@idref" /tmp/cis-scan-results.xml 2>/dev/null
```

### 3.3 常见 Fail 项分类

```
CIS Level 1 常见 Fail 分类：

┌───────────────────────────────────────────────────────────────┐
│ 1. 服务配置                                                    │
│    - SSH 设置（PermitRootLogin, PasswordAuth）                 │
│    - 不必要服务未禁用                                           │
├───────────────────────────────────────────────────────────────┤
│ 2. 文件权限                                                    │
│    - 敏感文件权限过宽（/etc/passwd, /etc/shadow）               │
│    - SUID/SGID 文件过多                                        │
│    - 无主文件（没有有效 owner）                                 │
├───────────────────────────────────────────────────────────────┤
│ 3. 认证策略                                                    │
│    - 密码复杂度不足（pam_pwquality）                           │
│    - 账户锁定未配置（pam_faillock）                            │
│    - root 账户无限制                                           │
├───────────────────────────────────────────────────────────────┤
│ 4. 审计配置                                                    │
│    - auditd 未运行或规则不足                                   │
│    - 日志保留期不够                                            │
├───────────────────────────────────────────────────────────────┤
│ 5. 网络配置                                                    │
│    - 防火墙规则不足                                            │
│    - 不安全的网络参数（IP forwarding 等）                       │
└───────────────────────────────────────────────────────────────┘
```

### 3.4 评估修复影响

在修复之前，问自己三个问题：

```
修复前检查清单：

1. 业务影响？
   └─ 这个改动会影响正在运行的服务吗？
   └─ 需要停机维护吗？
   └─ 是否需要提前通知用户？

2. 回滚方案？
   └─ 如何恢复原来的配置？
   └─ 有备份吗？
   └─ 能快速回滚吗？

3. 测试验证？
   └─ 如何验证修复有效？
   └─ 如何确认没有破坏功能？
   └─ 谁来验收？
```

---

## Step 4 - 实战场景：Pre-Audit SUID Cleanup（40 分钟）

> **场景**：金融客户要求服务器上线前通过 CIS Benchmark 扫描。  
> 扫描标记多个非必需 SUID 二进制文件，存在提权风险。  
> 你需要找到所有 SUID 文件，评估必要性，安全移除权限。  

### 4.1 什么是 SUID/SGID？

```
SUID/SGID 权限说明：

┌─────────────────────────────────────────────────────────────────┐
│                    特殊权限位                                     │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│   SUID (Set User ID)                                           │
│   - 文件权限: -rwsr-xr-x (注意 's')                             │
│   - 效果: 执行时以文件所有者身份运行                              │
│   - 常见例子: /usr/bin/passwd (需要写 /etc/shadow)              │
│                                                                 │
│   SGID (Set Group ID)                                          │
│   - 文件权限: -rwxr-sr-x                                        │
│   - 效果: 执行时以文件所属组身份运行                              │
│   - 常见例子: /usr/bin/wall (需要写终端)                         │
│                                                                 │
│   安全风险：                                                     │
│   ┌─────────────────────────────────────────────────────────┐   │
│   │  普通用户 ──▶ SUID root 程序漏洞 ──▶ root 权限提升       │   │
│   └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│   历史案例：                                                     │
│   - CVE-2021-4034: polkit pkexec 本地提权                       │
│   - CVE-2019-14287: sudo 配置绕过                               │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

<details>
<summary>View ASCII source</summary>

```
SUID/SGID 权限说明：

┌─────────────────────────────────────────────────────────────────┐
│                    特殊权限位                                     │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│   SUID (Set User ID)                                           │
│   - 文件权限: -rwsr-xr-x (注意 's')                             │
│   - 效果: 执行时以文件所有者身份运行                              │
│   - 常见例子: /usr/bin/passwd (需要写 /etc/shadow)              │
│                                                                 │
│   SGID (Set Group ID)                                          │
│   - 文件权限: -rwxr-sr-x                                        │
│   - 效果: 执行时以文件所属组身份运行                              │
│   - 常见例子: /usr/bin/wall (需要写终端)                         │
│                                                                 │
│   安全风险：                                                     │
│   ┌─────────────────────────────────────────────────────────┐   │
│   │  普通用户 ──▶ SUID root 程序漏洞 ──▶ root 权限提升       │   │
│   └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│   历史案例：                                                     │
│   - CVE-2021-4034: polkit pkexec 本地提权                       │
│   - CVE-2019-14287: sudo 配置绕过                               │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

</details>

### 4.2 执行 SUID 清理场景

```bash
# 进入场景目录
cd code/suid-cleanup-scenario/

# Step 1: 发现所有 SUID/SGID 文件
sudo bash discover-suid.sh

# Step 2: 分析评估（脚本会生成评估报告）
sudo bash analyze-suid.sh

# Step 3: 清理不必要的 SUID（谨慎！先理解每个文件）
# 查看清理脚本内容
cat cleanup-suid.sh

# 确认理解后执行
# sudo bash cleanup-suid.sh
```

### 4.3 手动 SUID 分析流程

```bash
# 1. 查找所有 SUID 文件
sudo find / -perm /4000 -type f 2>/dev/null | tee /tmp/suid-files.txt

# 2. 查找所有 SGID 文件
sudo find / -perm /2000 -type f 2>/dev/null | tee /tmp/sgid-files.txt

# 3. 合并查找 SUID 或 SGID
sudo find / -perm /6000 -type f 2>/dev/null | tee /tmp/suid-sgid-files.txt

# 4. 分析每个文件
# 对于每个文件，检查：
# - 属于哪个包？
# - 这个功能是否需要？
# - 有没有替代方案？

for file in $(cat /tmp/suid-files.txt | head -10); do
    echo "=== $file ==="
    rpm -qf "$file" 2>/dev/null || dpkg -S "$file" 2>/dev/null || echo "不属于任何包"
    ls -la "$file"
    echo ""
done
```

### 4.4 常见 SUID 文件评估

| 文件 | 必要性 | 说明 |
|------|--------|------|
| `/usr/bin/passwd` | **必须保留** | 用户修改密码 |
| `/usr/bin/sudo` | **必须保留** | 权限提升 |
| `/usr/bin/su` | **必须保留** | 切换用户 |
| `/usr/bin/mount` | **视情况** | 普通用户挂载（可禁用） |
| `/usr/bin/umount` | **视情况** | 普通用户卸载（可禁用） |
| `/usr/bin/pkexec` | **高风险** | polkit，如果不用 GUI 可移除 |
| `/usr/bin/chage` | **低风险** | 密码过期设置（一般 root 用） |
| `/usr/bin/gpasswd` | **低风险** | 组管理（一般 root 用） |
| `/usr/bin/newgrp` | **低风险** | 切换主组（一般不需要） |

### 4.5 安全移除 SUID

```bash
# 移除 SUID 位（保留其他权限）
sudo chmod u-s /usr/bin/newgrp

# 验证
ls -la /usr/bin/newgrp
# 从 -rwsr-xr-x 变为 -rwxr-xr-x

# 如果需要恢复
sudo chmod u+s /usr/bin/newgrp
```

---

## Step 5 - 例外管理（20 分钟）

### 5.1 何时需要例外？

```
例外申请场景：

┌─────────────────────────────────────────────────────────────────┐
│ 业务需求优先于安全建议时：                                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│ 1. 应用兼容性                                                    │
│    └─ 老应用需要特定配置，无法修改                                │
│    └─ 示例：遗留 Java 应用需要特定 SELinux 设置                  │
│                                                                 │
│ 2. 运维需求                                                      │
│    └─ SSH MaxSessions 需要超过推荐值                             │
│    └─ 示例：多窗口开发环境需要 10+ 会话                           │
│                                                                 │
│ 3. 性能考虑                                                      │
│    └─ 某些审计规则影响性能                                        │
│    └─ 示例：高频交易系统不能承受完整审计开销                      │
│                                                                 │
│ 4. 功能需求                                                      │
│    └─ 需要被标记为"风险"的功能                                    │
│    └─ 示例：开发服务器需要 X11 转发                               │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 5.2 例外文档模板

我们提供了标准的例外申请模板：

```bash
# 查看模板
cat code/exception-template.md

# 使用模板
cp code/exception-template.md /path/to/your-exception.md
# 编辑填写具体内容
```

### 5.3 例外管理最佳实践

```
例外管理生命周期：

┌──────────┐    ┌──────────┐    ┌──────────┐    ┌──────────┐
│  申请    │───▶│  评估    │───▶│  审批    │───▶│  记录    │
│          │    │          │    │          │    │          │
│ - 业务原因│    │ - 风险评估│    │ - 管理层 │    │ - 文档化 │
│ - 技术原因│    │ - 补偿控制│    │ - 安全团队│    │ - 存档   │
└──────────┘    └──────────┘    └──────────┘    └──────────┘
                                                     │
                                                     ▼
                                              ┌──────────┐
                                              │  复审    │
                                              │          │
                                              │ - 季度   │
                                              │ - 年度   │
                                              └──────────┘
```

<details>
<summary>View ASCII source</summary>

```
例外管理生命周期：

┌──────────┐    ┌──────────┐    ┌──────────┐    ┌──────────┐
│  申请    │───▶│  评估    │───▶│  审批    │───▶│  记录    │
│          │    │          │    │          │    │          │
│ - 业务原因│    │ - 风险评估│    │ - 管理层 │    │ - 文档化 │
│ - 技术原因│    │ - 补偿控制│    │ - 安全团队│    │ - 存档   │
└──────────┘    └──────────┘    └──────────┘    └──────────┘
                                                     │
                                                     ▼
                                              ┌──────────┐
                                              │  复审    │
                                              │          │
                                              │ - 季度   │
                                              │ - 年度   │
                                              └──────────┘
```

</details>

### 5.4 补偿控制示例

当无法满足某个控制项时，需要提供补偿控制：

| 无法满足的控制项 | 补偿控制 |
|------------------|----------|
| 无法禁用 root SSH 登录 | 限制 root 登录来源 IP + 强制密钥 + auditd 监控 |
| 无法启用 SELinux | 强化 DAC 权限 + auditd + 应用级隔离 |
| 无法配置 CIS 推荐的密码策略 | 多因素认证 + 账户锁定 + 异常登录监控 |
| SUID 文件无法移除 | 限制可执行用户 + auditd 监控执行 |

---

## Step 6 - 自动修复（15 分钟）

### 6.1 OpenSCAP 自动修复

```bash
# 生成 Bash 修复脚本
sudo oscap xccdf generate fix \
  --profile xccdf_org.ssgproject.content_profile_cis_server_l1 \
  --fix-type bash \
  /usr/share/xml/scap/ssg/content/ssg-rhel9-ds.xml > /tmp/remediation.sh

# 生成 Ansible 修复 playbook
sudo oscap xccdf generate fix \
  --profile xccdf_org.ssgproject.content_profile_cis_server_l1 \
  --fix-type ansible \
  /usr/share/xml/scap/ssg/content/ssg-rhel9-ds.xml > /tmp/remediation.yml
```

### 6.2 Ansible Hardening Roles

> **详细内容**：请参考 [Lesson 11 - 安全加固自动化](../11-hardening-automation/)  

```bash
# 查看 Ansible 集成说明
cat code/remediation-ansible/README.md
```

常用的 Ansible hardening roles：

| Role | 来源 | 说明 |
|------|------|------|
| `geerlingguy.security` | Ansible Galaxy | 通用安全加固 |
| `devsec.os_hardening` | dev-sec | CIS 对标 |
| `RHEL-STIG` | Red Hat | STIG 合规 |

### 6.3 一键修复的风险

> **关键信息**：自动修复脚本可能导致业务中断！  

```
一键修复的风险：

┌─────────────────────────────────────────────────────────────────┐
│                    ⚠️  危险操作示例                              │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│ 场景 1：SSH 配置修复                                             │
│ ┌─────────────────────────────────────────────────────────────┐ │
│ │ 脚本操作：PasswordAuthentication no                         │ │
│ │ 潜在问题：如果密钥未配置，立即被锁在外面                       │ │
│ └─────────────────────────────────────────────────────────────┘ │
│                                                                 │
│ 场景 2：服务禁用                                                 │
│ ┌─────────────────────────────────────────────────────────────┐ │
│ │ 脚本操作：systemctl disable --now rpcbind                   │ │
│ │ 潜在问题：NFS 客户端立即无法工作                              │ │
│ └─────────────────────────────────────────────────────────────┘ │
│                                                                 │
│ 场景 3：内核参数修改                                             │
│ ┌─────────────────────────────────────────────────────────────┐ │
│ │ 脚本操作：net.ipv4.ip_forward = 0                           │ │
│ │ 潜在问题：容器网络、VPN 立即中断                              │ │
│ └─────────────────────────────────────────────────────────────┘ │
│                                                                 │
│ 场景 4：防火墙加固                                               │
│ ┌─────────────────────────────────────────────────────────────┐ │
│ │ 脚本操作：nftables 规则应用                                  │ │
│ │ 潜在问题：应用端口未开放，服务不可用                          │ │
│ └─────────────────────────────────────────────────────────────┘ │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘

安全的修复流程：

1. 测试环境先行
   └─ 在非生产环境验证每个修复项

2. 分批实施
   └─ 一次修复 3-5 个控制项
   └─ 每批次验证后再继续

3. 保留回滚能力
   └─ 配置备份
   └─ 变更窗口
   └─ 回滚脚本准备

4. 业务验收
   └─ 应用团队确认功能正常
   └─ 监控无异常告警
```

<details>
<summary>View ASCII source</summary>

```
一键修复的风险：

┌─────────────────────────────────────────────────────────────────┐
│                    ⚠️  危险操作示例                              │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│ 场景 1：SSH 配置修复                                             │
│ ┌─────────────────────────────────────────────────────────────┐ │
│ │ 脚本操作：PasswordAuthentication no                         │ │
│ │ 潜在问题：如果密钥未配置，立即被锁在外面                       │ │
│ └─────────────────────────────────────────────────────────────┘ │
│                                                                 │
│ 场景 2：服务禁用                                                 │
│ ┌─────────────────────────────────────────────────────────────┐ │
│ │ 脚本操作：systemctl disable --now rpcbind                   │ │
│ │ 潜在问题：NFS 客户端立即无法工作                              │ │
│ └─────────────────────────────────────────────────────────────┘ │
│                                                                 │
│ 场景 3：内核参数修改                                             │
│ ┌─────────────────────────────────────────────────────────────┐ │
│ │ 脚本操作：net.ipv4.ip_forward = 0                           │ │
│ │ 潜在问题：容器网络、VPN 立即中断                              │ │
│ └─────────────────────────────────────────────────────────────┘ │
│                                                                 │
│ 场景 4：防火墙加固                                               │
│ ┌─────────────────────────────────────────────────────────────┐ │
│ │ 脚本操作：nftables 规则应用                                  │ │
│ │ 潜在问题：应用端口未开放，服务不可用                          │ │
│ └─────────────────────────────────────────────────────────────┘ │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘

安全的修复流程：

1. 测试环境先行
   └─ 在非生产环境验证每个修复项

2. 分批实施
   └─ 一次修复 3-5 个控制项
   └─ 每批次验证后再继续

3. 保留回滚能力
   └─ 配置备份
   └─ 变更窗口
   └─ 回滚脚本准备

4. 业务验收
   └─ 应用团队确认功能正常
   └─ 监控无异常告警
```

</details>

---

## 反模式：常见错误

### 错误 1：盲目一键修复

```bash
# 危险！可能导致业务中断
sudo oscap xccdf generate fix ... > remediation.sh
sudo bash remediation.sh    # ← 没有审核就执行

# 正确做法
# 1. 先查看脚本内容
cat remediation.sh | less

# 2. 分批执行，每次几个控制项
head -50 remediation.sh > batch-1.sh
cat batch-1.sh  # 审核
sudo bash batch-1.sh
# 验证...

# 3. 测试环境先验证
```

### 错误 2：未文档化的例外

```bash
# 危险！未记录的例外
# 审计时："为什么这个控制项 Fail？"
# 回答："不知道，可能有原因..."

# 正确做法
# 每个例外都要：
# 1. 记录业务原因
# 2. 记录风险评估
# 3. 记录补偿控制
# 4. 定期复审
```

### 错误 3：只看 Pass 率

```bash
# 错误思维
# "Pass 率 95%，安全了！"

# 正确思维
# 那 5% 的 Fail 是什么？
# - 是关键控制项吗？
# - 有例外文档吗？
# - 有补偿控制吗？
```

### 错误 4：扫描后不跟进

```bash
# 错误做法
# 扫描 → 看报告 → 归档 → 忘记

# 正确做法
# 扫描 → 分析 → 制定计划 → 实施 → 验证 → 复扫
#          ↑                              │
#          └──────────── 持续循环 ─────────┘
```

---

## 职场小贴士（Japan IT Context）

### 合规在日本企业

| 日语术语 | 含义 | 技术实现 |
|----------|------|----------|
| セキュリティ基線 | 安全基线 | CIS Benchmark |
| 脆弱性診断 | 漏洞扫描 | OpenSCAP, Nessus |
| 監査対応 | 审计应对 | 合规报告、例外文档 |
| 例外申請 | 例外申请 | Exception Template |
| 是正措置 | 纠正措施 | Remediation Plan |
| 補償統制 | 补偿控制 | Compensating Control |

### 日本企业合规要求

```
日本企业常见合规框架：

┌─────────────────────────────────────────────────────────────────┐
│ 1. ISMS (ISO 27001)                                             │
│    - 日本企業で最も普及                                          │
│    - 技术控制 + 管理控制                                         │
│    - CIS Benchmark 可作为技术实施参考                            │
├─────────────────────────────────────────────────────────────────┤
│ 2. PCI DSS (クレジットカード業界)                                │
│    - 支付卡行业数据安全标准                                       │
│    - 严格的访问控制、日志要求                                     │
│    - 对应 CIS 的 SSH、auditd、防火墙控制                         │
├─────────────────────────────────────────────────────────────────┤
│ 3. 金融庁ガイドライン                                            │
│    - 金融机构安全指南                                            │
│    - 强调风险管理和监控                                          │
├─────────────────────────────────────────────────────────────────┤
│ 4. 個人情報保護法 (APPI)                                         │
│    - 个人信息保护                                                │
│    - 访问控制、加密、审计轨迹                                     │
└─────────────────────────────────────────────────────────────────┘
```

### 审计报告模板

```markdown
## セキュリティ監査報告書

### 監査日: 20XX年XX月XX日
### 対象サーバー: production-app-01
### 監査基準: CIS RHEL 9 Benchmark v1.0.0 Level 1

### 結果サマリー

| 項目 | 件数 |
|------|------|
| Pass | 185 |
| Fail | 23 |
| Not Applicable | 12 |
| **合格率** | **88.9%** |

### Fail 項目一覧

| ID | 内容 | 対応状況 |
|----|------|----------|
| 5.2.4 | SSH MaxAuthTries | 対応予定 |
| 5.2.16 | SSH MaxSessions | 例外申請済 |
| ... | ... | ... |

### 例外事項

| 控制項目 | 例外理由 | 補償統制 | 承認者 |
|----------|----------|----------|--------|
| 5.2.16 | 開発環境要件 | Fail2Ban + auditd | 山田部長 |

### 是正計画

| 優先度 | 項目 | 担当 | 期限 |
|--------|------|------|------|
| 高 | SSH MaxAuthTries | 田中 | 12/15 |
| 中 | auditd 規則追加 | 佐藤 | 12/20 |
```

---

## 检查清单

完成本课后，你应该能够：

- [ ] 解释 CIS Benchmark Level 1 和 Level 2 的区别
- [ ] 使用 OpenSCAP 执行 CIS 合规扫描
- [ ] 解读 Pass/Fail/Not Applicable 结果
- [ ] 分析 Fail 项并评估修复影响
- [ ] 使用 `find / -perm /6000` 查找 SUID/SGID 文件
- [ ] 安全移除不必要的 SUID 权限
- [ ] 撰写例外申请文档
- [ ] 解释为什么一键修复是危险的
- [ ] 描述补偿控制的概念

---

## 本课小结

| 概念 | 命令/方法 | 记忆点 |
|------|-----------|--------|
| 合规扫描 | `oscap xccdf eval` | 起点，不是终点 |
| 结果分析 | HTML 报告 + XML 结果 | 理解每个 Fail 项 |
| SUID 查找 | `find / -perm /6000` | 提权风险评估 |
| SUID 移除 | `chmod u-s` | 谨慎评估必要性 |
| 例外管理 | Exception Template | **必须文档化** |
| 自动修复 | `oscap generate fix` | **高风险，谨慎使用** |

**核心理念**：

```
┌─────────────────────────────────────────────────────────────────┐
│                                                                 │
│   扫描是起点，不是终点                                           │
│   Scanning is the beginning, not the end                        │
│                                                                 │
│   例外必须文档化                                                 │
│   Exceptions MUST be documented                                 │
│                                                                 │
│   一键修复有风险                                                 │
│   One-click remediation is risky                                │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 延伸阅读

- [CIS Benchmarks Download](https://www.cisecurity.org/cis-benchmarks/) - 官方 Benchmark 文档（需注册）
- [OpenSCAP Documentation](https://www.open-scap.org/documentation/) - OpenSCAP 官方文档
- [SCAP Security Guide](https://www.open-scap.org/security-policies/scap-security-guide/) - SSG 项目
- [NIST 800-53](https://csrc.nist.gov/publications/detail/sp/800-53/rev-5/final) - 美国联邦安全控制框架
- 相关课程：[Lesson 11 - 安全加固自动化](../11-hardening-automation/) - Ansible 自动化加固

---

## 系列导航

[上一课：09 - PAM 高级配置](../09-pam-advanced/) | [系列首页](../) | [下一课：11 - 安全加固自动化 ->](../11-hardening-automation/)
