# 08 - 镜像加固与供应链安全（Image Hardening & Supply Chain Security）

> **目标**：应用 CIS Benchmark 加固镜像，理解供应链安全基础，建立补丁管理流程  
> **前置**：[07 - 金色镜像策略](../07-golden-image/)、[LX08 - Linux 安全基础](../../security/)  
> **时间**：2 小时  
> **实战场景**：CIS 合规扫描、漏洞检测、加固自动化  

---

## 将学到的内容

1. 应用 CIS Benchmark 到 Linux 镜像（Level 1 vs Level 2）
2. 使用 OpenSCAP 进行合规性扫描
3. 理解供应链安全基础（SBOM、包签名验证）
4. 使用 Trivy 进行漏洞扫描
5. 建立补丁管理流程
6. 将加固集成到镜像构建管道

---

## 先跑起来！（10 分钟）

> 在学习加固理论之前，先对你的系统做一次安全扫描。  

在任意 Amazon Linux 2023 或 RHEL/CentOS 实例上运行：

### 快速安全体检

```bash
# 安装 OpenSCAP 扫描工具
sudo dnf install -y openscap-scanner scap-security-guide

# 查看可用的安全配置文件
oscap info /usr/share/xml/scap/ssg/content/ssg-al2023-ds.xml 2>/dev/null | grep -A 50 "Profiles:" | head -30

# 运行快速 CIS 扫描（仅评估，不修改系统）
sudo oscap xccdf eval \
  --profile xccdf_org.ssgproject.content_profile_cis \
  --results /tmp/scan-results.xml \
  --report /tmp/scan-report.html \
  /usr/share/xml/scap/ssg/content/ssg-al2023-ds.xml 2>/dev/null

# 查看扫描摘要
echo ""
echo "=== 扫描结果摘要 ==="
grep -E "(pass|fail|notapplicable)" /tmp/scan-results.xml | \
  sed 's/.*result="\([^"]*\)".*/\1/' | sort | uniq -c
```

**你应该看到类似这样的输出**：

```
=== 扫描结果摘要 ===
     45 fail
     12 notapplicable
     89 pass
```

**关键发现**：
- 即使是标准 AWS AMI，也有很多项目不符合 CIS 基准
- `fail` 的项目需要手动修复或自动化加固
- `notapplicable` 表示该检查项不适用于当前系统配置
- 扫描报告 `/tmp/scan-report.html` 包含详细的修复建议

### 查看具体失败项

```bash
# 提取失败的规则 ID 和描述
oscap xccdf eval \
  --profile xccdf_org.ssgproject.content_profile_cis \
  /usr/share/xml/scap/ssg/content/ssg-al2023-ds.xml 2>&1 | \
  grep -E "^(Title|Rule|fail)" | head -30
```

---

**你刚刚完成了第一次合规性扫描。** 这就是在日本企业的「監査要件」中经常需要做的事情：证明系统符合安全基准。

---

## Step 1 - CIS Benchmark 概述（25 分钟）

### 1.1 什么是 CIS Benchmark？

**CIS（Center for Internet Security）Benchmark** 是全球公认的系统安全配置标准：

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    CIS Benchmark 层级结构                                     │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│   ┌───────────────────────────────────────────────────────────────────────┐ │
│   │                        Level 1 (基础级)                                │ │
│   │                                                                       │ │
│   │   目标：所有系统都应该达到的基本安全配置                               │ │
│   │   影响：对系统功能影响最小                                             │ │
│   │                                                                       │ │
│   │   示例检查项：                                                         │ │
│   │   ● 禁用不必要的服务                                                  │ │
│   │   ● 配置密码策略                                                      │ │
│   │   ● 设置文件权限                                                      │ │
│   │   ● 启用审计日志                                                      │ │
│   │   ● 配置 SSH 安全选项                                                 │ │
│   └───────────────────────────────────────────────────────────────────────┘ │
│                                                                             │
│   ┌───────────────────────────────────────────────────────────────────────┐ │
│   │                        Level 2 (高安全级)                              │ │
│   │                                                                       │ │
│   │   目标：高安全要求环境（金融、政府、医疗）                              │ │
│   │   影响：可能影响系统功能或性能                                          │ │
│   │                                                                       │ │
│   │   示例检查项：                                                         │ │
│   │   ● SELinux 强制模式                                                  │ │
│   │   ● 更严格的内核参数                                                  │ │
│   │   ● 高级审计配置                                                      │ │
│   │   ● 磁盘加密要求                                                      │ │
│   │   ● 高级网络隔离                                                      │ │
│   └───────────────────────────────────────────────────────────────────────┘ │
│                                                                             │
│   选择建议：                                                                │
│   ● 大多数云工作负载：Level 1 即可                                         │
│   ● 金融/政府/医疗：Level 2 + 行业特定要求                                 │
│   ● 生产环境：至少 Level 1                                                 │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 1.2 CIS Benchmark 主要分类

CIS Benchmark 通常按以下类别组织：

| 类别 | 说明 | 示例检查项 |
|------|------|-----------|
| **Initial Setup** | 系统初始配置 | 文件系统分区、禁用不用的文件系统类型 |
| **Services** | 服务配置 | 禁用不必要服务、配置 cron、SSH |
| **Network Configuration** | 网络配置 | 禁用 IPv6（如不用）、防火墙规则 |
| **Logging and Auditing** | 日志和审计 | auditd 配置、日志轮转、时间同步 |
| **Access, Authentication, Authorization** | 访问控制 | 密码策略、sudo 配置、PAM 模块 |
| **System Maintenance** | 系统维护 | 文件权限、SUID/SGID 文件 |

### 1.3 AWS 特定考虑

在 AWS 环境中应用 CIS Benchmark 需要考虑：

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    AWS 环境的 CIS 适配                                        │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│   可直接应用的检查项：                                                       │
│   ├─ 密码策略配置                                                           │
│   ├─ SSH 配置加固                                                           │
│   ├─ 文件权限设置                                                           │
│   ├─ auditd 配置                                                            │
│   └─ 服务禁用                                                               │
│                                                                             │
│   需要调整的检查项：                                                         │
│   ├─ 引导加载器密码 → EC2 没有 GRUB 交互                                   │
│   ├─ 物理端口禁用 → 不适用（虚拟化环境）                                   │
│   ├─ 磁盘分区要求 → AMI 通常单分区，需要自定义                             │
│   └─ 防火墙规则 → 与安全组协调                                             │
│                                                                             │
│   AWS 替代方案：                                                             │
│   ├─ 本地防火墙 → 安全组 + nftables 双层                                   │
│   ├─ 本地用户管理 → IAM + SSM Session Manager                              │
│   └─ 本地日志 → CloudWatch Logs 导出                                       │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 1.4 例外管理

不是所有 CIS 检查项都必须通过。**例外管理（Exception Management）** 是关键：

```bash
# 记录例外的格式示例
cat > /tmp/cis-exceptions.md << 'EOF'
# CIS Benchmark 例外记录

## 例外 1: 分区要求
- **规则**: 1.1.2 - Ensure /tmp is a separate partition
- **状态**: 例外
- **原因**: AWS AMI 标准设计，使用根分区
- **补偿控制**: tmp 目录通过 noexec,nosuid 挂载选项限制
- **审批人**: Security Team
- **审批日期**: 2025-01-10

## 例外 2: GRUB 密码
- **规则**: 1.4.1 - Ensure bootloader password is set
- **状态**: 不适用
- **原因**: EC2 没有 GRUB 交互访问
- **补偿控制**: 实例通过安全组和 IAM 保护
EOF

cat /tmp/cis-exceptions.md
```

---

## Step 2 - OpenSCAP 扫描详解（25 分钟）

### 2.1 OpenSCAP 工具链

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    OpenSCAP 工具链                                           │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│   ┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐      │
│   │  SCAP Content   │────►│    oscap        │────►│  扫描报告        │      │
│   │  (SSG)          │     │  (扫描引擎)      │     │  HTML/XML       │      │
│   └─────────────────┘     └─────────────────┘     └─────────────────┘      │
│                                                                             │
│   组件说明：                                                                │
│                                                                             │
│   SCAP Security Guide (SSG)：                                              │
│   ├─ 包含各发行版的安全配置文件                                             │
│   ├─ CIS、STIG、PCI-DSS 等多种标准                                         │
│   └─ 路径: /usr/share/xml/scap/ssg/content/                                │
│                                                                             │
│   oscap 命令：                                                              │
│   ├─ xccdf eval: 执行合规性检查                                            │
│   ├─ oval eval: 执行漏洞检查                                               │
│   ├─ xccdf generate fix: 生成修复脚本                                      │
│   └─ info: 查看 SCAP 内容信息                                              │
│                                                                             │
│   报告格式：                                                                │
│   ├─ HTML: 人类可读，适合审计                                              │
│   ├─ XML: 机器可读，适合自动化处理                                         │
│   └─ ARF: Asset Reporting Format，标准格式                                 │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 2.2 查看可用配置文件

```bash
# 查看 Amazon Linux 2023 的安全配置文件
oscap info /usr/share/xml/scap/ssg/content/ssg-al2023-ds.xml

# 列出所有可用的 profile
oscap info /usr/share/xml/scap/ssg/content/ssg-al2023-ds.xml 2>/dev/null | \
  grep -A 100 "Profiles:" | grep "Id:" | head -20

# 常见的 profile：
# - cis (CIS Benchmark)
# - cis_workstation_l1 (CIS Level 1 - Workstation)
# - cis_server_l1 (CIS Level 1 - Server)
# - stig (DISA STIG)
# - pci-dss (PCI DSS)
```

### 2.3 执行详细扫描

```bash
# 完整的 CIS 扫描命令
sudo oscap xccdf eval \
  --profile xccdf_org.ssgproject.content_profile_cis \
  --results /tmp/cis-results.xml \
  --report /tmp/cis-report.html \
  --oval-results \
  /usr/share/xml/scap/ssg/content/ssg-al2023-ds.xml

# 查看 HTML 报告（如果有图形界面或 Web 服务器）
# 或者解析 XML 结果
echo "=== 失败的规则 ==="
xmllint --xpath "//*[local-name()='rule-result'][@result='fail']/*[local-name()='idref']/text()" \
  /tmp/cis-results.xml 2>/dev/null | tr ' ' '\n' | head -20

# 统计结果
echo ""
echo "=== 结果统计 ==="
for result in pass fail error unknown notapplicable notchecked; do
  count=$(grep -c "result=\"$result\"" /tmp/cis-results.xml 2>/dev/null || echo 0)
  echo "$result: $count"
done
```

### 2.4 生成修复脚本

```bash
# 生成 Bash 修复脚本
sudo oscap xccdf generate fix \
  --profile xccdf_org.ssgproject.content_profile_cis \
  --fix-type bash \
  --output /tmp/cis-remediation.sh \
  /usr/share/xml/scap/ssg/content/ssg-al2023-ds.xml

# 查看修复脚本（不要直接运行！先审查）
head -100 /tmp/cis-remediation.sh

# 生成 Ansible 修复 playbook
sudo oscap xccdf generate fix \
  --profile xccdf_org.ssgproject.content_profile_cis \
  --fix-type ansible \
  --output /tmp/cis-remediation.yml \
  /usr/share/xml/scap/ssg/content/ssg-al2023-ds.xml

# 查看 Ansible playbook
head -50 /tmp/cis-remediation.yml
```

> **警告**：自动生成的修复脚本需要仔细审查后才能应用。某些修复可能影响系统功能。  

### 2.5 扫描特定规则

```bash
# 只扫描 SSH 相关规则
sudo oscap xccdf eval \
  --profile xccdf_org.ssgproject.content_profile_cis \
  --rule xccdf_org.ssgproject.content_rule_sshd_disable_root_login \
  --rule xccdf_org.ssgproject.content_rule_sshd_set_idle_timeout \
  /usr/share/xml/scap/ssg/content/ssg-al2023-ds.xml 2>&1 | tail -20
```

---

## Step 3 - 供应链安全基础（20 分钟）

### 3.1 什么是软件供应链安全？

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    软件供应链攻击向量                                          │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│   传统攻击：直接攻击目标系统                                                  │
│   ─────────────────────────────────────                                     │
│   攻击者 ────────────────────────────────► 目标系统                          │
│                                                                             │
│   供应链攻击：通过依赖项间接攻击                                              │
│   ─────────────────────────────────────                                     │
│                                                                             │
│   攻击者 ───┐                                                               │
│             │                                                               │
│             ▼                                                               │
│   ┌─────────────────┐                                                       │
│   │  上游软件包      │  ← 攻击者在这里植入恶意代码                            │
│   │  (npm, PyPI,    │                                                       │
│   │   RPM, etc.)    │                                                       │
│   └────────┬────────┘                                                       │
│            │ 正常依赖                                                        │
│            ▼                                                                │
│   ┌─────────────────┐                                                       │
│   │  开发者/运维     │  ← 不知情地引入恶意代码                                │
│   └────────┬────────┘                                                       │
│            │ 部署                                                            │
│            ▼                                                                │
│   ┌─────────────────┐                                                       │
│   │  生产系统        │  ← 被攻陷                                             │
│   └─────────────────┘                                                       │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 3.2 重大供应链安全事件

> **供应链安全入门：为什么重要？**  

| 事件 | 时间 | 影响 | 教训 |
|------|------|------|------|
| **SolarWinds** | 2020 | 18,000+ 组织，含美国政府 | 构建系统也需要保护 |
| **Log4Shell** | 2021 | 数百万 Java 应用 | 需要知道使用了哪些组件 |
| **Codecov** | 2021 | 数千家公司 CI/CD 泄露 | CI/CD 管道是高价值目标 |
| **ua-parser-js** | 2021 | 数百万 npm 下载 | 自动更新有风险 |

**共同点**：受害者不是直接被攻击，而是通过信任的软件被攻击。

### 3.3 SBOM（软件物料清单）

**SBOM（Software Bill of Materials）** 是软件组件的清单：

```bash
# 生成简单的软件清单
echo "=== 系统软件清单 (SBOM) ==="

# 已安装的 RPM 包
echo "# 已安装 RPM 包清单" > /tmp/sbom.txt
echo "# 生成时间: $(date -Iseconds)" >> /tmp/sbom.txt
echo "# 系统: $(cat /etc/os-release | grep PRETTY_NAME | cut -d= -f2 | tr -d '"')" >> /tmp/sbom.txt
echo "" >> /tmp/sbom.txt

rpm -qa --qf '%{NAME}|%{VERSION}|%{RELEASE}|%{VENDOR}\n' | sort >> /tmp/sbom.txt

# 显示前 20 行
head -25 /tmp/sbom.txt

# 统计
echo ""
echo "总包数: $(rpm -qa | wc -l)"
```

**标准 SBOM 格式**：

| 格式 | 说明 | 使用场景 |
|------|------|----------|
| **SPDX** | Linux Foundation 标准 | 开源合规、法律 |
| **CycloneDX** | OWASP 标准 | 安全漏洞追踪 |
| **SWID** | ISO 标准 | 软件资产管理 |

```bash
# 使用 syft 生成标准 SBOM（如果已安装）
# syft / -o spdx-json > sbom.spdx.json
# syft / -o cyclonedx-json > sbom.cdx.json
```

### 3.4 包签名验证

```bash
# 检查 RPM 包签名
echo "=== RPM 签名验证 ==="

# 检查 GPG 密钥
rpm -qa gpg-pubkey* --qf '%{NAME}-%{VERSION}-%{RELEASE}\t%{SUMMARY}\n'

# 验证已安装包的签名
echo ""
echo "验证 Amazon Linux 核心包签名..."
rpm -V amazon-linux-release 2>&1 || echo "验证通过"

# 检查所有包签名状态
echo ""
echo "未签名的包（可能有风险）:"
rpm -qa --qf '%{NAME}\t%{SIGPGP:pgpsig}\n' | grep -v "Key ID" | head -10
```

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    包签名验证流程                                             │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│   1. 软件发布者签名                                                          │
│   ┌──────────────┐    私钥签名    ┌──────────────┐                          │
│   │   软件包      │───────────────►│  签名的软件包  │                          │
│   │   (.rpm)     │                │  (.rpm + sig) │                          │
│   └──────────────┘                └──────────────┘                          │
│                                                                             │
│   2. 用户验证                                                                │
│   ┌──────────────┐    公钥验证    ┌──────────────┐                          │
│   │  签名的软件包  │───────────────►│   验证结果     │                          │
│   │              │                │  ✓ 签名有效   │                          │
│   └──────────────┘                │  ✗ 签名无效   │                          │
│         │                         └──────────────┘                          │
│         │                                                                   │
│   ┌─────▼────────┐                                                          │
│   │   信任的      │  GPG 公钥来自官方源                                       │
│   │   GPG 公钥    │  /etc/pki/rpm-gpg/                                       │
│   └──────────────┘                                                          │
│                                                                             │
│   验证命令：                                                                 │
│   rpm -K package.rpm      # 验证单个包                                       │
│   rpm -Va                 # 验证所有已安装包                                 │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Step 4 - 漏洞扫描（20 分钟）

### 4.1 Trivy 漏洞扫描

**Trivy** 是一个全面的漏洞扫描器，支持多种目标：

```bash
# 安装 Trivy
sudo rpm -ivh https://github.com/aquasecurity/trivy/releases/download/v0.50.0/trivy_0.50.0_Linux-64bit.rpm 2>/dev/null || \
  echo "如果上面失败，请访问 https://github.com/aquasecurity/trivy/releases 下载"

# 或者使用 dnf（如果已配置源）
# sudo dnf install -y trivy
```

### 4.2 扫描文件系统

```bash
# 扫描当前系统的漏洞
sudo trivy rootfs / --scanners vuln --severity HIGH,CRITICAL

# 更详细的输出
sudo trivy rootfs / \
  --scanners vuln \
  --severity HIGH,CRITICAL \
  --format table \
  --output /tmp/trivy-report.txt

# 查看报告
cat /tmp/trivy-report.txt
```

### 4.3 扫描 AMI

```bash
# 扫描 AMI（需要 AWS 凭证）
# trivy vm --scanners vuln ami:ami-0123456789abcdef0

# 扫描 EBS 快照
# trivy vm --scanners vuln ebs:snap-0123456789abcdef0
```

### 4.4 AWS Inspector

AWS 原生的漏洞扫描服务：

```bash
# 检查 Inspector 扫描状态
aws inspector2 list-findings \
  --filter-criteria '{"findingStatus":[{"comparison":"EQUALS","value":"ACTIVE"}]}' \
  --max-results 10 \
  --query 'findings[].{Title:title,Severity:severity,Resource:resources[0].id}' \
  --output table 2>/dev/null || echo "需要启用 Inspector 服务"
```

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    漏洞扫描工具对比                                           │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│   工具           费用      云原生    容器支持    CI/CD 集成    实时监控       │
│   ─────────────────────────────────────────────────────────────────────    │
│   Trivy          免费      ✓        ✓          ✓            ✗             │
│   AWS Inspector  按量付费  ✓✓       ✓          ✓            ✓             │
│   Grype          免费      △        ✓          ✓            ✗             │
│   Clair          免费      ✗        ✓          ✓            ✗             │
│                                                                             │
│   推荐组合：                                                                │
│   ● 开发/CI: Trivy（快速、免费、本地运行）                                   │
│   ● 生产监控: AWS Inspector（持续扫描、告警集成）                            │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Step 5 - 补丁管理（15 分钟）

### 5.1 补丁管理策略

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    补丁管理策略对比                                           │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│   策略 1: 在线补丁 (Patch in Place)                                         │
│   ─────────────────────────────────                                         │
│   ┌──────────┐    dnf update    ┌──────────┐                               │
│   │ 运行实例  │─────────────────►│ 更新后实例 │                               │
│   │ v1.0     │                  │ v1.1     │                               │
│   └──────────┘                  └──────────┘                               │
│                                                                             │
│   优点: 快速、简单                                                          │
│   缺点: 可能引入不一致、需要重启、难以回滚                                    │
│   适用: 紧急安全补丁、开发环境                                               │
│                                                                             │
│   ─────────────────────────────────────────────────────────────────────    │
│                                                                             │
│   策略 2: 镜像更新 (Immutable Infrastructure)                               │
│   ───────────────────────────────────────────                               │
│   ┌──────────┐              ┌──────────┐              ┌──────────┐         │
│   │ AMI v1.0 │──► 更新构建 ─►│ AMI v1.1 │──► 部署新 ──►│ 新实例    │         │
│   │          │              │          │    实例      │ v1.1     │         │
│   └──────────┘              └──────────┘              └──────────┘         │
│        │                                                    │              │
│        └───────────── 保留用于回滚 ─────────────────────────┘              │
│                                                                             │
│   优点: 一致性、可回滚、可审计                                               │
│   缺点: 需要更多时间、更复杂的流程                                           │
│   适用: 生产环境、合规要求                                                   │
│                                                                             │
│   ─────────────────────────────────────────────────────────────────────    │
│                                                                             │
│   推荐: 混合策略                                                             │
│   ● 紧急安全补丁: 在线补丁 + 后续镜像更新                                    │
│   ● 常规更新: 镜像更新                                                      │
│   ● 所有变更: 记录在变更管理系统                                             │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 5.2 补丁更新流程

```bash
# 检查可用更新
sudo dnf check-update

# 只查看安全更新
sudo dnf updateinfo list security

# 查看更新详情
sudo dnf updateinfo info

# 应用安全更新
sudo dnf update --security -y

# 应用所有更新
sudo dnf update -y

# 检查是否需要重启
needs-restarting -r || echo "需要重启以完成更新"

# 查看需要重启的服务
needs-restarting -s
```

### 5.3 自动化补丁更新

```bash
# 安装自动更新工具
sudo dnf install -y dnf-automatic

# 配置自动更新
sudo cat > /etc/dnf/automatic.conf << 'EOF'
[commands]
upgrade_type = security
random_sleep = 360
download_updates = yes
apply_updates = yes

[emitters]
emit_via = stdio

[email]
email_from = root@localhost
email_to = admin@example.com
EOF

# 启用定时任务
sudo systemctl enable --now dnf-automatic.timer

# 检查状态
systemctl status dnf-automatic.timer
```

---

## Step 6 - 加固自动化（15 分钟）

### 6.1 Packer + 加固脚本

```bash
# 加固脚本示例
cat > /tmp/harden-cis.sh << 'EOF'
#!/bin/bash
# CIS Level 1 加固脚本（示例）
# 警告：请在测试环境验证后再用于生产

set -e

echo "=== CIS Level 1 加固开始 ==="

# 1. SSH 加固
echo "配置 SSH..."
cat >> /etc/ssh/sshd_config << 'SSHEOF'
# CIS SSH 加固
PermitRootLogin no
MaxAuthTries 4
PermitEmptyPasswords no
ClientAliveInterval 300
ClientAliveCountMax 0
LoginGraceTime 60
SSHEOF

# 2. 禁用不必要的服务
echo "禁用不必要的服务..."
for svc in rpcbind avahi-daemon cups; do
    systemctl disable $svc 2>/dev/null || true
    systemctl stop $svc 2>/dev/null || true
done

# 3. 文件权限
echo "设置文件权限..."
chmod 644 /etc/passwd
chmod 644 /etc/group
chmod 600 /etc/shadow
chmod 600 /etc/gshadow

# 4. 配置审计
echo "配置 auditd..."
systemctl enable auditd
systemctl start auditd

# 5. 内核参数
echo "配置内核参数..."
cat > /etc/sysctl.d/99-cis.conf << 'SYSCTL'
# CIS 内核加固
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.secure_redirects = 0
net.ipv4.conf.default.secure_redirects = 0
net.ipv4.icmp_echo_ignore_broadcasts = 1
SYSCTL

sysctl --system > /dev/null

echo "=== CIS Level 1 加固完成 ==="
EOF

chmod +x /tmp/harden-cis.sh
cat /tmp/harden-cis.sh
```

### 6.2 EC2 Image Builder

AWS 原生的镜像构建服务，内置 CIS 加固组件：

```bash
# 列出可用的 CIS 加固组件
aws imagebuilder list-components \
  --owner Amazon \
  --filters "name=name,values=*cis*" \
  --query 'componentVersionList[].{Name:name,Version:version}' \
  --output table 2>/dev/null || echo "需要 Image Builder 权限"

# 常用组件：
# - cis-benchmark-level-1 (Amazon Linux 2023)
# - stig-build-linux-high (DISA STIG)
```

### 6.3 加固管道集成

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    镜像加固 CI/CD 管道                                        │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│   ┌─────────┐    ┌─────────┐    ┌─────────┐    ┌─────────┐    ┌─────────┐  │
│   │  代码   │───►│  构建   │───►│  加固   │───►│  扫描   │───►│  发布   │  │
│   │ 提交   │    │ 镜像   │    │ 脚本   │    │ 验证   │    │ AMI    │  │
│   └─────────┘    └─────────┘    └─────────┘    └─────────┘    └─────────┘  │
│                                                                             │
│   工具链示例：                                                               │
│                                                                             │
│   GitHub Actions / Jenkins / CodePipeline                                   │
│        │                                                                    │
│        ▼                                                                    │
│   ┌─────────────────────────────────────────────────────────────────────┐  │
│   │ Packer 构建:                                                        │  │
│   │   1. 从基础 AMI 启动                                                │  │
│   │   2. 运行 provisioner 脚本                                          │  │
│   │      - 系统更新                                                     │  │
│   │      - 安装应用                                                     │  │
│   │      - CIS 加固                                                     │  │
│   │      - 清理 (seal)                                                  │  │
│   │   3. 创建 AMI                                                       │  │
│   └─────────────────────────────────────────────────────────────────────┘  │
│        │                                                                    │
│        ▼                                                                    │
│   ┌─────────────────────────────────────────────────────────────────────┐  │
│   │ 验证阶段:                                                           │  │
│   │   1. 从新 AMI 启动测试实例                                          │  │
│   │   2. OpenSCAP 扫描验证 CIS 合规                                     │  │
│   │   3. Trivy 漏洞扫描                                                 │  │
│   │   4. 功能测试                                                       │  │
│   │   5. 通过率 > 85% 才发布                                            │  │
│   └─────────────────────────────────────────────────────────────────────┘  │
│        │                                                                    │
│        ▼                                                                    │
│   ┌─────────────────────────────────────────────────────────────────────┐  │
│   │ 发布:                                                               │  │
│   │   1. 标记 AMI (版本、日期、CIS 级别)                                │  │
│   │   2. 更新 Launch Template                                           │  │
│   │   3. 生成合规报告                                                   │  │
│   │   4. 通知相关团队                                                   │  │
│   └─────────────────────────────────────────────────────────────────────┘  │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Lab 1 - CIS 扫描实验（30 分钟）

### 实验目标

使用 OpenSCAP 对系统进行 CIS 合规性扫描，分析结果并手动修复部分问题。

### Step 1 - 安装工具

```bash
# 安装 OpenSCAP 和安全指南
sudo dnf install -y openscap-scanner scap-security-guide

# 验证安装
oscap --version
ls /usr/share/xml/scap/ssg/content/
```

### Step 2 - 执行扫描

```bash
# 创建报告目录
mkdir -p /tmp/cis-scan

# 执行 CIS 扫描
sudo oscap xccdf eval \
  --profile xccdf_org.ssgproject.content_profile_cis \
  --results /tmp/cis-scan/results.xml \
  --report /tmp/cis-scan/report.html \
  /usr/share/xml/scap/ssg/content/ssg-al2023-ds.xml

# 查看结果摘要
echo "=== 扫描结果摘要 ==="
for result in pass fail error notapplicable; do
  count=$(grep -c "result=\"$result\"" /tmp/cis-scan/results.xml 2>/dev/null || echo 0)
  printf "%-15s: %s\n" "$result" "$count"
done
```

### Step 3 - 分析失败项

```bash
# 提取失败项详情
echo "=== 失败的检查项 (前 10 个) ==="
grep -B 2 'result="fail"' /tmp/cis-scan/results.xml | \
  grep 'idref=' | \
  sed 's/.*idref="\([^"]*\)".*/\1/' | \
  head -10

# 查看特定规则的详情
RULE_ID="xccdf_org.ssgproject.content_rule_sshd_disable_root_login"
oscap info --profile xccdf_org.ssgproject.content_profile_cis \
  /usr/share/xml/scap/ssg/content/ssg-al2023-ds.xml 2>&1 | \
  grep -A 5 "$RULE_ID" || echo "规则信息查看方式：查看 HTML 报告"
```

### Step 4 - 手动修复示例

```bash
# 示例：修复 SSH root 登录
echo "=== 修复 SSH root 登录 ==="
sudo grep -E "^PermitRootLogin" /etc/ssh/sshd_config || \
  echo "当前未设置 PermitRootLogin"

# 添加配置
sudo sed -i 's/^#PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
sudo sed -i 's/^PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config

# 如果配置文件中没有这行，添加它
grep -q "^PermitRootLogin" /etc/ssh/sshd_config || \
  echo "PermitRootLogin no" | sudo tee -a /etc/ssh/sshd_config

# 验证配置
sudo sshd -t && echo "SSH 配置语法正确"
sudo grep "^PermitRootLogin" /etc/ssh/sshd_config

# 重启 SSH 服务
sudo systemctl reload sshd
```

### Step 5 - 重新扫描验证

```bash
# 重新扫描
sudo oscap xccdf eval \
  --profile xccdf_org.ssgproject.content_profile_cis \
  --results /tmp/cis-scan/results-after.xml \
  /usr/share/xml/scap/ssg/content/ssg-al2023-ds.xml 2>&1 | \
  grep -E "(pass|fail)" | tail -20

# 比较前后结果
echo "=== 修复前后对比 ==="
echo "修复前:"
grep -c 'result="pass"' /tmp/cis-scan/results.xml
echo "修复后:"
grep -c 'result="pass"' /tmp/cis-scan/results-after.xml
```

### 检查清单

- [ ] 能安装和使用 OpenSCAP
- [ ] 能执行 CIS 合规性扫描
- [ ] 能解读扫描结果
- [ ] 能手动修复特定检查项
- [ ] 理解不同严重级别的含义

---

## Lab 2 - Trivy 漏洞扫描实验（20 分钟）

### 实验目标

使用 Trivy 扫描系统漏洞，理解漏洞报告格式。

### Step 1 - 安装 Trivy

```bash
# 添加 Trivy 仓库并安装
sudo tee /etc/yum.repos.d/trivy.repo << 'EOF'
[trivy]
name=Trivy repository
baseurl=https://aquasecurity.github.io/trivy-repo/rpm/releases/$basearch/
gpgcheck=0
enabled=1
EOF

sudo dnf install -y trivy || {
  echo "如果安装失败，使用二进制安装"
  curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | sudo sh -s -- -b /usr/local/bin
}

# 验证安装
trivy --version
```

### Step 2 - 扫描文件系统

```bash
# 更新漏洞数据库
trivy image --download-db-only

# 扫描根文件系统
sudo trivy rootfs / \
  --scanners vuln \
  --severity HIGH,CRITICAL \
  --format table \
  2>&1 | head -50

# 生成 JSON 报告
sudo trivy rootfs / \
  --scanners vuln \
  --severity HIGH,CRITICAL \
  --format json \
  --output /tmp/trivy-vulns.json

# 查看漏洞统计
echo "=== 漏洞统计 ==="
cat /tmp/trivy-vulns.json | python3 -c "
import sys, json
data = json.load(sys.stdin)
vulns = {}
for result in data.get('Results', []):
    for v in result.get('Vulnerabilities', []):
        sev = v.get('Severity', 'UNKNOWN')
        vulns[sev] = vulns.get(sev, 0) + 1
for sev, count in sorted(vulns.items()):
    print(f'{sev}: {count}')
"
```

### Step 3 - 分析特定漏洞

```bash
# 查看 CRITICAL 漏洞详情
cat /tmp/trivy-vulns.json | python3 -c "
import sys, json
data = json.load(sys.stdin)
for result in data.get('Results', []):
    for v in result.get('Vulnerabilities', []):
        if v.get('Severity') == 'CRITICAL':
            print(f\"CVE: {v.get('VulnerabilityID')}\"
            print(f\"Package: {v.get('PkgName')} {v.get('InstalledVersion')}\")
            print(f\"Fixed in: {v.get('FixedVersion', 'Not fixed')}\")
            print(f\"Title: {v.get('Title', 'N/A')}\")
            print('---')
" | head -30
```

### Step 4 - 修复漏洞

```bash
# 查看可更新的包
sudo dnf check-update

# 更新有漏洞的包
sudo dnf update -y

# 重新扫描验证
sudo trivy rootfs / \
  --scanners vuln \
  --severity CRITICAL \
  2>&1 | tail -20
```

### 检查清单

- [ ] 能安装和使用 Trivy
- [ ] 能扫描文件系统漏洞
- [ ] 能解读漏洞报告
- [ ] 理解 CVSS 评分和严重级别
- [ ] 能通过更新修复漏洞

---

## 供应链安全侧边栏（Supply Chain Security Sidebar）

### 为什么供应链安全如此重要？

**SolarWinds 事件（2020）**：

```
攻击者入侵 SolarWinds 构建系统
            │
            ▼
在 Orion 软件更新中植入后门
            │
            ▼
18,000+ 组织安装了恶意更新
包括：美国财政部、商务部、国土安全部
            │
            ▼
攻击者获得对这些组织网络的访问权限
```

**Log4Shell（CVE-2021-44228）**：

```
Log4j 是 Java 的日志库
            │
            ▼
存在远程代码执行漏洞
            │
            ▼
数百万 Java 应用受影响
大多数组织不知道自己使用了 Log4j
            │
            ▼
需要紧急排查和修复
```

### 基础防护措施

| 措施 | 说明 | 实现方法 |
|------|------|----------|
| **验证包签名** | 确保软件来自官方 | GPG 签名验证 |
| **使用官方源** | 只从可信源安装 | 配置 /etc/yum.repos.d/ |
| **定期更新** | 及时应用安全补丁 | dnf-automatic |
| **生成 SBOM** | 知道用了什么组件 | syft, trivy |
| **漏洞扫描** | 发现已知漏洞 | Trivy, Inspector |
| **锁定版本** | 避免自动更新引入问题 | package lock files |

### 深入学习路径

供应链安全是一个深入的话题，本课仅介绍基础概念。更多内容参见：

- **LX11-CONTAINERS**: 容器镜像安全、镜像签名
- **DevOps 课程**: CI/CD 管道安全
- **SLSA (Supply chain Levels for Software Artifacts)**: Google 提出的供应链安全框架

---

## 职场小贴士（Japan IT Context）

### 監査要件とセキュリティ基線

在日本企业，**安全基准（セキュリティ基線）** 和 **审计要求（監査要件）** 是合规的核心：

| 日语术语 | 读音 | 含义 | CIS 实践 |
|----------|------|------|----------|
| セキュリティ基準 | セキュリティきじゅん | 安全标准 | CIS Benchmark 作为基准 |
| 脆弱性管理 | ぜいじゃくせいかんり | 漏洞管理 | Trivy/Inspector 扫描 |
| パッチ管理 | パッチかんり | 补丁管理 | 定期更新流程 |
| 監査証跡 | かんさしょうせき | 审计追踪 | 保存扫描报告 |
| コンプライアンス | コンプライアンス | 合规性 | 达到 CIS Level 1/2 |

### FISC 金融系统安全指南

日本金融行业由 **FISC（金融情報システムセンター）** 制定安全要求：

```
┌─────────────────────────────────────────────────────────────────────────────┐
│            FISC 安全管理基準との対応                                          │
│            (FISC Security Guidelines Mapping)                               │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│   FISC 要求              CIS Benchmark 对应项                                │
│   ─────────────────────────────────────────────────────────────────────    │
│                                                                             │
│   アクセス制御            SSH 加固、sudo 配置、文件权限                      │
│   (Access Control)       CIS 5.x - Access, Authentication                  │
│                                                                             │
│   ログ管理               auditd 配置、日志保留                               │
│   (Log Management)       CIS 4.x - Logging and Auditing                    │
│                                                                             │
│   脆弱性対策             漏洞扫描、补丁管理                                  │
│   (Vulnerability Mgmt)   Trivy + 定期更新                                   │
│                                                                             │
│   設定管理               镜像加固、配置审计                                  │
│   (Config Management)    OpenSCAP 扫描验证                                  │
│                                                                             │
│   証跡保全               扫描报告保存、变更记录                              │
│   (Evidence Retention)   HTML/XML 报告存档                                  │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 合规报告模板

```bash
# 生成审计用合规报告
cat > /tmp/compliance-report.md << EOF
# セキュリティコンプライアンスレポート
# Security Compliance Report

## 基本情報
- 対象システム: $(hostname)
- スキャン日時: $(date -Iseconds)
- スキャンツール: OpenSCAP $(oscap --version | head -1)
- 適用基準: CIS Benchmark Level 1

## スキャン結果サマリ
- Pass: $(grep -c 'result="pass"' /tmp/cis-scan/results.xml 2>/dev/null || echo "N/A")
- Fail: $(grep -c 'result="fail"' /tmp/cis-scan/results.xml 2>/dev/null || echo "N/A")
- 適用外: $(grep -c 'result="notapplicable"' /tmp/cis-scan/results.xml 2>/dev/null || echo "N/A")

## 例外事項
[別紙「CIS例外記録」参照]

## 対応計画
- 緊急対応（Critical）: 24時間以内
- 高優先度（High）: 1週間以内
- 中優先度（Medium）: 1ヶ月以内

## 承認
- 作成者: ____________
- 確認者: ____________
- 承認日: ____________
EOF

cat /tmp/compliance-report.md
```

---

## 检查清单

完成本课后，你应该能够：

- [ ] 解释 CIS Benchmark 的 Level 1 和 Level 2 区别
- [ ] 使用 OpenSCAP 执行合规性扫描
- [ ] 解读扫描报告并识别关键问题
- [ ] 手动修复常见的 CIS 检查项失败
- [ ] 理解软件供应链安全的基本概念
- [ ] 使用 Trivy 进行漏洞扫描
- [ ] 建立基本的补丁管理流程
- [ ] 将加固脚本集成到镜像构建流程
- [ ] 管理 CIS 例外并记录文档
- [ ] 生成符合日本企业审计要求的合规报告

---

## 本课小结

| 概念 | 要点 |
|------|------|
| CIS Benchmark | 系统安全配置的行业标准，Level 1 适合大多数场景 |
| OpenSCAP | 开源合规扫描工具，支持 CIS、STIG 等多种标准 |
| 供应链安全 | 通过依赖项的攻击向量，需要 SBOM 和签名验证 |
| 漏洞扫描 | Trivy（本地）+ Inspector（云端）组合使用 |
| 补丁管理 | 镜像更新优于在线补丁，保持不可变基础设施 |
| 例外管理 | 记录无法修复的项目，提供补偿控制 |

---

## 延伸阅读

- [CIS Benchmarks](https://www.cisecurity.org/cis-benchmarks) - CIS 官方基准文档
- [OpenSCAP Documentation](https://www.open-scap.org/documentation/) - OpenSCAP 官方文档
- [Trivy Documentation](https://aquasecurity.github.io/trivy/) - Trivy 漏洞扫描器
- [AWS Inspector](https://docs.aws.amazon.com/inspector/) - AWS 原生漏洞扫描
- [SLSA Framework](https://slsa.dev/) - 供应链安全框架
- 前一课：[07 - 金色镜像策略](../07-golden-image/) - Bake vs Bootstrap 决策
- 下一课：[09 - 可观测性集成](../09-observability/) - CloudWatch Agent 配置

---

## 清理资源

```bash
# 删除临时文件
rm -rf /tmp/cis-scan
rm -f /tmp/scan-results.xml /tmp/scan-report.html
rm -f /tmp/cis-exceptions.md
rm -f /tmp/cis-remediation.sh /tmp/cis-remediation.yml
rm -f /tmp/sbom.txt
rm -f /tmp/trivy-report.txt /tmp/trivy-vulns.json
rm -f /tmp/harden-cis.sh
rm -f /tmp/compliance-report.md

# 如果修改了 SSH 配置，确保没有锁定自己
sudo sshd -t && echo "SSH 配置正确"
```

---

## 系列导航

[<- 07 - 金色镜像策略](../07-golden-image/) | [系列首页](../) | [09 - 可观测性集成 ->](../09-observability/)
