# Security Exception Request / 安全例外申請書

> **Instructions / 使用说明:**  
> - Fill in all required fields marked with (*)  
> - Keep this document with your compliance records  
> - Review annually or when systems change  
> - 填写所有标记 (*) 的必填字段  
> - 将此文档与合规记录一起保存  
> - 每年或系统变更时复审  

---

## 1. Basic Information / 基本信息

| Field | Value |
|-------|-------|
| **Request Date / 申請日** (*) | YYYY-MM-DD |
| **Requester / 申請者** (*) | Name / 姓名 |
| **Department / 部門** | |
| **Contact Email / 連絡先** | |
| **Target System / 対象システム** (*) | hostname or system group |

---

## 2. Exception Details / 例外詳細

### 2.1 Control Information / 控制項信息 (*)

| Field | Value |
|-------|-------|
| **Control ID** | e.g., CIS 5.2.16 |
| **Control Title** | e.g., Ensure SSH MaxSessions is limited |
| **Benchmark Version** | e.g., CIS RHEL 9 v1.0.0 |
| **Profile** | e.g., Level 1 Server |
| **Scored** | [ ] Yes / [ ] No |

### 2.2 Current Configuration / 現在の設定 (*)

```
# Paste current configuration or command output
# 粘贴当前配置或命令输出

Example:
$ sudo sshd -T | grep maxsessions
maxsessions 10
```

### 2.3 Required Configuration (per Benchmark) / 基準要求

```
# What the benchmark recommends
# 基準推奨設定

Example:
MaxSessions 4 or less
```

---

## 3. Business Justification / 業務上の理由 (*)

### 3.1 Why is exception needed? / 为什么需要例外？

> Explain the business or technical reason why the recommended configuration cannot be implemented.  
> 解释为什么无法实施推荐配置的业务或技术原因。  

```
Example:
Development team requires multiple simultaneous SSH sessions for:
- IDE remote development (3+ sessions)
- Terminal multiplexing
- File transfer operations
- Monitoring sessions

Reducing MaxSessions would significantly impact developer productivity.
```

### 3.2 Impact if exception is NOT granted / 如果不批准例外的影响

```
Example:
- Developer productivity reduced by approximately 30%
- Unable to use remote IDE features
- Increased context switching overhead
```

### 3.3 Affected Users / Teams / 影响的用户/团队

```
Example:
- Development Team: 15 engineers
- DevOps Team: 5 engineers
- SRE Team: 3 engineers
```

---

## 4. Risk Assessment / 風険評価 (*)

### 4.1 Security Risk Level / 安全风险级别

- [ ] **High / 高** - Direct path to privilege escalation or data breach
- [ ] **Medium / 中** - Indirect security impact, requires other vulnerabilities
- [ ] **Low / 低** - Minimal security impact, defense-in-depth measure

### 4.2 Risk Description / 风险描述

```
Example:
MaxSessions controls the number of SSH sessions per connection.
Higher value allows more sessions but:
- Only affects authenticated users
- Does not increase attack surface for unauthenticated access
- Primary risk: resource exhaustion (DoS) if session limit abused

Risk Level: LOW
```

### 4.3 Likelihood of Exploitation / 被利用的可能性

- [ ] **High** - Actively exploited, public exploit available
- [ ] **Medium** - Theoretical risk, requires specific conditions
- [ ] **Low** - Requires authenticated access, low practical risk

---

## 5. Compensating Controls / 補償統制 (*)

> What additional security measures will be implemented to mitigate the risk?  
> 将实施哪些额外的安全措施来降低风险？  

### 5.1 Compensating Control Details / 补偿控制详情

| Control | Implementation | Status |
|---------|---------------|--------|
| **SSH Key-only Authentication** | PasswordAuthentication no | [ ] Implemented |
| **Fail2Ban** | 5 failures = 15min ban | [ ] Implemented |
| **Source IP Restriction** | AllowUsers user@192.168.0.0/16 | [ ] Implemented |
| **auditd Monitoring** | SSH login/logout logging | [ ] Implemented |
| **Session Timeout** | ClientAliveInterval 300 | [ ] Implemented |

### 5.2 Monitoring / 監視措置

```
Example:
- SSH session count monitored via Zabbix
- Alert threshold: >50 total sessions
- Daily review of SSH audit logs
```

### 5.3 Additional Hardening / 追加の堅牢化

```
Example:
- MaxAuthTries set to 3 (stricter than default)
- Root login completely disabled
- SELinux enforcing mode active
```

---

## 6. Approval / 承認

### 6.1 Requester Acknowledgment / 申請者確認 (*)

> I confirm that:  
> - The business justification is accurate  
> - Compensating controls will be implemented as described  
> - This exception will be reviewed annually  

| | |
|---|---|
| **Signature / 署名** | |
| **Date / 日付** | |

### 6.2 Security Team Review / セキュリティチームレビュー

| Field | Value |
|-------|-------|
| **Reviewer** | |
| **Review Date** | |
| **Recommendation** | [ ] Approve / [ ] Approve with conditions / [ ] Reject |
| **Comments** | |

### 6.3 Management Approval / 管理者承認 (*)

| Field | Value |
|-------|-------|
| **Approver Name** | |
| **Title / 役職** | |
| **Approval Date** | |
| **Signature / 署名** | |

---

## 7. Exception Validity / 例外有效期

| Field | Value |
|-------|-------|
| **Effective Date / 開始日** | |
| **Expiration Date / 終了日** | |
| **Review Frequency** | [ ] Quarterly / [ ] Semi-annual / [ ] Annual |
| **Next Review Date** | |

---

## 8. Review History / 審査履歴

| Date | Reviewer | Action | Notes |
|------|----------|--------|-------|
| | | [ ] Renewed / [ ] Modified / [ ] Revoked | |
| | | [ ] Renewed / [ ] Modified / [ ] Revoked | |
| | | [ ] Renewed / [ ] Modified / [ ] Revoked | |

---

## Appendix A: Quick Reference / 附录 A：快速参考

### Common Exception Scenarios / 常见例外场景

| Scenario | Typical Risk | Typical Compensating Controls |
|----------|--------------|-------------------------------|
| SSH MaxSessions exceeded | Low | Key-only auth, Fail2Ban, IP restriction |
| X11 Forwarding enabled | Medium | Restrict to specific users, auditd |
| Certain services enabled | Varies | Firewall rules, SELinux, monitoring |
| SUID binary retained | Medium-High | Restrict execution, audit execve |
| Weak algorithm for legacy | Medium | Isolate system, VPN, migration plan |

### Risk Acceptance Matrix / 风险接受矩阵

| Impact \ Likelihood | Low | Medium | High |
|---------------------|-----|--------|------|
| **Low** | Accept | Accept with controls | Review |
| **Medium** | Accept with controls | Review | Senior approval |
| **High** | Review | Senior approval | Not recommended |

---

## Document Control / 文档管理

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | YYYY-MM-DD | | Initial version |
| | | | |

---

**Template Version:** 1.0
**Last Updated:** 2026-01-04
**Source:** cloud-atlas LX08-SECURITY Lesson 10
