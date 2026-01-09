# OpenSCAP 评分说明 / OpenSCAP Scoring Guide

## 概述

本文档解释 OpenSCAP CIS Benchmark 扫描的评分机制和结果解读方法。

---

## 1. 扫描命令

### 1.1 基本扫描

```bash
# Rocky Linux 9 / RHEL 9
sudo oscap xccdf eval \
  --profile xccdf_org.ssgproject.content_profile_cis_server_l1 \
  --results results.xml \
  --report report.html \
  /usr/share/xml/scap/ssg/content/ssg-rl9-ds.xml
```

### 1.2 可用 Profile

| Profile ID | 名称 | 适用场景 |
|------------|------|----------|
| `cis_server_l1` | CIS Level 1 Server | 生产服务器基础加固 |
| `cis_server_l2` | CIS Level 2 Server | 高安全性生产服务器 |
| `cis_workstation_l1` | CIS Level 1 Workstation | 工作站基础加固 |
| `cis_workstation_l2` | CIS Level 2 Workstation | 高安全性工作站 |
| `stig` | DISA STIG | 美国政府/军方标准 |
| `pci-dss` | PCI DSS | 支付卡行业标准 |

### 1.3 查看可用 Profile

```bash
oscap info /usr/share/xml/scap/ssg/content/ssg-rl9-ds.xml | grep -A 100 "Profiles:"
```

---

## 2. 结果状态说明

### 2.1 结果类型

| 结果 | 说明 | 计入通过率 |
|------|------|------------|
| **pass** | 检查通过 | 是（分子） |
| **fail** | 检查失败 | 是（分母） |
| **notapplicable** | 不适用（如未安装相关组件） | 否 |
| **notchecked** | 无法检查（缺少工具等） | 否 |
| **informational** | 信息提示 | 否 |
| **error** | 检查出错 | 否 |

### 2.2 通过率计算

```
通过率 = pass / (pass + fail) * 100%
```

**注意**：`notapplicable` 和 `notchecked` 不计入通过率计算。

---

## 3. 结果统计方法

### 3.1 命令行统计

```bash
# 统计各状态数量
grep -E "<result>" results.xml | sort | uniq -c

# 计算通过率
PASS=$(grep -c "<result>pass</result>" results.xml)
FAIL=$(grep -c "<result>fail</result>" results.xml)
TOTAL=$((PASS + FAIL))
RATE=$(echo "scale=1; $PASS * 100 / $TOTAL" | bc)
echo "Pass: $PASS / $TOTAL = $RATE%"
```

### 3.2 使用 oscap 生成报告

```bash
# 生成文本报告
oscap xccdf generate report results.xml > report.txt

# 查看失败项
grep -E "^(Title|Result):" report.txt | paste - - | grep "fail"
```

---

## 4. 本项目评分标准

### 4.1 通过率要求

| 等级 | 通过率 | 评价 |
|------|--------|------|
| 优秀 | >= 95% | 超出预期 |
| 达标 | >= 90% | 满足要求（本项目最低要求） |
| 需改进 | 80-89% | 基本可接受但需要优化 |
| 不达标 | < 80% | 需要重新加固 |

### 4.2 评分公式

本 Capstone 项目的 OpenSCAP 部分评分（40 分满分）：

```
如果 通过率 >= 95%: 得分 = 40
如果 90% <= 通过率 < 95%: 得分 = 35
如果 85% <= 通过率 < 90%: 得分 = 30
如果 80% <= 通过率 < 85%: 得分 = 25
如果 通过率 < 80%: 不及格（需要重做）
```

---

## 5. 常见失败项及修复

### 5.1 SSH 相关

| 控制项 | 修复方法 |
|--------|----------|
| Ensure SSH root login is disabled | `PermitRootLogin no` |
| Ensure SSH PasswordAuthentication is disabled | `PasswordAuthentication no` |
| Ensure SSH MaxAuthTries is set | `MaxAuthTries 4` |
| Ensure SSH warning banner is configured | `Banner /etc/issue.net` |

### 5.2 PAM 相关

| 控制项 | 修复方法 |
|--------|----------|
| Ensure lockout for failed password attempts | 配置 pam_faillock |
| Ensure password complexity requirements | 配置 pwquality.conf |
| Ensure password hashing algorithm is SHA-512 | PAM 默认配置 |

### 5.3 文件权限

| 控制项 | 修复方法 |
|--------|----------|
| Ensure permissions on /etc/passwd | `chmod 644 /etc/passwd` |
| Ensure permissions on /etc/shadow | `chmod 000 /etc/shadow` |
| Ensure permissions on /etc/group | `chmod 644 /etc/group` |

### 5.4 审计相关

| 控制项 | 修复方法 |
|--------|----------|
| Ensure auditd is installed | `dnf install audit` |
| Ensure auditd service is enabled | `systemctl enable auditd` |
| Ensure audit rules for user/group changes | 添加 audit rules |

---

## 6. 例外处理

### 6.1 何时使用例外

- 控制项与业务需求冲突
- 环境不适用某项控制
- 有更好的替代控制措施

### 6.2 例外文档要求

每个例外项必须包含：

1. **控制项标识** - CIS 控制项编号和名称
2. **当前配置** - 实际配置状态
3. **不修改原因** - 业务/技术原因
4. **风险评估** - 低/中/高
5. **补偿控制** - 替代的安全措施
6. **审批** - 签名和日期
7. **复审日期** - 下次审核日期

### 6.3 例外示例

```markdown
### Exception: CIS 5.2.16 - SSH MaxSessions

**控制项**: Ensure SSH MaxSessions is limited to 4 or less

**当前配置**: MaxSessions 10

**不修改原因**:
- 开发团队需要多窗口操作
- 运维人员需要同时打开多个 SSH 会话进行故障排查

**风险评估**: 低
- 已有 Key-only 认证
- 已有 Fail2Ban 防护
- 已有审计日志

**补偿控制**:
1. 仅允许密钥认证（消除密码暴力破解风险）
2. Fail2Ban 监控异常行为
3. auditd 记录所有 SSH 登录
4. 定期审核活跃会话

**审批**: __________ 日期: __________

**复审日期**: __________
```

---

## 7. 报告解读

### 7.1 HTML 报告结构

- **Summary** - 总体通过率和统计
- **Rule Results** - 每条规则的详细结果
- **Remediation** - 失败项的修复建议

### 7.2 关注重点

1. **高优先级失败项** - Severity 为 high 的项目
2. **关键服务相关** - SSH, firewall, audit 相关
3. **可快速修复项** - 配置文件修改即可解决
4. **需要例外项** - 业务冲突，需要文档化

---

## 8. 持续合规

### 8.1 定期扫描建议

| 频率 | 目的 |
|------|------|
| 初始部署 | 基线扫描 |
| 每周 | 配置漂移检测 |
| 变更后 | 验证变更影响 |
| 季度 | 正式合规审计 |

### 8.2 自动化扫描

```bash
# 创建 cron 任务
cat > /etc/cron.weekly/security-scan << 'EOF'
#!/bin/bash
REPORT_DIR=/var/log/security-scans
TIMESTAMP=$(date +%Y%m%d)

mkdir -p $REPORT_DIR

oscap xccdf eval \
  --profile xccdf_org.ssgproject.content_profile_cis_server_l1 \
  --results $REPORT_DIR/scan-$TIMESTAMP.xml \
  --report $REPORT_DIR/scan-$TIMESTAMP.html \
  /usr/share/xml/scap/ssg/content/ssg-rl9-ds.xml

# 发送邮件通知（可选）
# mail -s "Weekly Security Scan Report" admin@example.com < $REPORT_DIR/summary.txt
EOF

chmod +x /etc/cron.weekly/security-scan
```

---

## 参考资源

- [OpenSCAP User Manual](https://www.open-scap.org/tools/openscap-base/)
- [SCAP Security Guide](https://www.open-scap.org/security-policies/scap-security-guide/)
- [CIS Benchmarks](https://www.cisecurity.org/cis-benchmarks)
- [NIST SCAP](https://csrc.nist.gov/projects/security-content-automation-protocol)
