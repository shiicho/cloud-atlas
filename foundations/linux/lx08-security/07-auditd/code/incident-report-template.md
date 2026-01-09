# セキュリティインシデント報告書 / Security Incident Report

> 本テンプレートは日本IT企業で使用される標準的なインシデント報告書形式に基づいています。  
> This template follows the standard incident report format used in Japan IT enterprises.  

---

## 基本情報 / Basic Information

| 項目 | 内容 |
|------|------|
| **報告日 / Report Date** | YYYY年MM月DD日 |
| **報告者 / Reporter** | 氏名 / Name |
| **インシデント番号 / Incident ID** | INC-YYYYMMDD-XXX |
| **インシデント発生日時 / Occurred At** | YYYY年MM月DD日 HH:MM JST |
| **発見日時 / Discovered At** | YYYY年MM月DD日 HH:MM JST |
| **影響システム / Affected System** | hostname / IP address |
| **深刻度 / Severity** | 高 / 中 / 低 (High / Medium / Low) |

---

## インシデント概要 / Incident Summary

### 何が起きたか / What Happened

[一段落で概要を記述 / One paragraph summary]

例 / Example:
> 堡垒机 SSH 配置文件 `/etc/ssh/sshd_config` 被未经授权修改，  
> `PermitRootLogin` 设置从 `no` 变更为 `yes`。违反安全策略。  
>
> Bastion host SSH configuration file was modified without authorization.  
> PermitRootLogin was changed from 'no' to 'yes', violating security policy.  

### 発見経緯 / How It Was Discovered

[発見に至った経緯を記述 / Describe how the incident was discovered]

例 / Example:
> 週明け月曜日の定期セキュリティ監査で設定ファイルの差分チェック時に発覚。  
>
> Discovered during regular Monday security audit while checking configuration drift.  

---

## 調査結果 / Investigation Findings

### 証拠収集コマンド / Evidence Collection Commands

```bash
# ausearch による調査 / Investigation using ausearch
ausearch -k ssh_config -ts "YYYY/MM/DD HH:MM:SS" -te "YYYY/MM/DD HH:MM:SS" --format text

# 特定ユーザーの行動追跡 / Tracking specific user's actions
ausearch -ua <AUID> -ts "1 day ago" --format text

# ログイン記録 / Login records
ausearch -m USER_LOGIN,USER_AUTH -ts "YYYY/MM/DD" --format text
```

### 証拠ログ / Evidence Logs

```
[ausearch 出力をここに貼り付け / Paste ausearch output here]

例 / Example:
type=SYSCALL msg=audit(1704369600.123:456): arch=c000003e syscall=257
success=yes exit=3 auid=1000 uid=0 gid=0 euid=0 comm="vim"
exe="/usr/bin/vim" key="ssh_config"
```

### 時系列 / Timeline

| 時刻 / Time | 事象 / Event | 証拠 / Evidence |
|-------------|--------------|-----------------|
| YYYY/MM/DD HH:MM | ユーザーログイン / User login | ausearch -m USER_LOGIN |
| YYYY/MM/DD HH:MM | sudo 実行 / sudo execution | ausearch -k sudo_usage |
| YYYY/MM/DD HH:MM | 設定変更 / Config change | ausearch -k ssh_config |
| YYYY/MM/DD HH:MM | サービス再起動 / Service restart | journalctl -u sshd |

### 責任者特定 / User Identification

| 項目 / Field | 値 / Value |
|--------------|------------|
| **auid (Audit UID)** | |
| **ユーザー名 / Username** | |
| **UID (Effective)** | |
| **所属 / Department** | |
| **本人証言 / User Statement** | |

---

## 影響範囲 / Impact Assessment

### チェックリスト / Checklist

- [ ] 設定変更あり / Configuration changed
- [ ] データ漏洩あり / Data breach occurred
- [ ] 不正アクセスの兆候あり / Signs of unauthorized access
- [ ] サービス停止あり / Service outage occurred
- [ ] 外部への影響あり / External impact
- [ ] 顧客データへの影響あり / Customer data affected
- [ ] 規制違反あり / Regulatory violation

### 影響詳細 / Impact Details

[具体的な影響を記述 / Describe specific impacts]

---

## 対応状況 / Response Actions

### 実施済み対応 / Completed Actions

| 対応項目 / Action | 状態 / Status | 担当 / Owner | 完了日 / Date |
|-------------------|---------------|--------------|---------------|
| 設定復旧 / Config restore | 完了 / Done | | |
| 証拠保全 / Evidence preserve | 完了 / Done | | |
| 本人ヒアリング / User interview | 完了 / Done | | |
| サービス再起動 / Service restart | 完了 / Done | | |

### 未完了対応 / Pending Actions

| 対応項目 / Action | 状態 / Status | 担当 / Owner | 期限 / Deadline |
|-------------------|---------------|--------------|-----------------|
| 再発防止策検討 / Prevention plan | 進行中 / In progress | | |
| 監視強化 / Enhanced monitoring | 予定 / Planned | | |

---

## 再発防止策 / Prevention Measures

### 技術的対策 / Technical Measures

1. **監視強化 / Enhanced Monitoring**
   - sshd_config 変更に対するリアルタイムアラート設定
   - Real-time alerting for sshd_config changes

2. **変更管理 / Change Management**
   - 本番環境変更の承認フロー導入
   - Approval workflow for production changes

3. **環境識別 / Environment Identification**
   - 環境別プロンプト色分け（本番=赤）
   - Color-coded prompts by environment (production = red)

### 運用的対策 / Operational Measures

1. **教育 / Training**
   - 変更管理プロセスの再教育
   - Refresher training on change management

2. **権限見直し / Access Review**
   - 本番アクセス権限の見直し
   - Review of production access permissions

3. **監査強化 / Audit Enhancement**
   - 定期監査頻度の見直し
   - Review of audit frequency

---

## 根本原因分析 / Root Cause Analysis

### 直接原因 / Direct Cause

[直接的な原因を記述 / Describe the direct cause]

### 根本原因 / Root Cause

[根本的な原因を記述 / Describe the root cause]

### 寄与要因 / Contributing Factors

1. [要因1 / Factor 1]
2. [要因2 / Factor 2]
3. [要因3 / Factor 3]

---

## 添付資料 / Attachments

- [ ] 証拠ログ全文 / Full evidence logs
- [ ] スクリーンショット / Screenshots
- [ ] 設定ファイル差分 / Configuration diff
- [ ] aureport 出力 / aureport output

---

## 承認 / Approval

| 役職 / Role | 氏名 / Name | 日付 / Date | 署名 / Signature |
|-------------|-------------|-------------|------------------|
| 担当者 / Assignee | | | |
| セキュリティ担当 / Security | | | |
| 部門長 / Manager | | | |
| CISO | | | |

---

## 改訂履歴 / Revision History

| バージョン / Version | 日付 / Date | 変更者 / Author | 変更内容 / Changes |
|----------------------|-------------|-----------------|---------------------|
| 1.0 | YYYY/MM/DD | | 初版作成 / Initial draft |

---

## 備考 / Notes

[その他特記事項 / Additional notes]

---

*このテンプレートは LX08-SECURITY Lesson 07 - auditd の学習用に作成されました。*
*This template was created for LX08-SECURITY Lesson 07 - auditd training.*
