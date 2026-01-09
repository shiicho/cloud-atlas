# Ghost Configuration Change Scenario

## Scenario Description (Chinese)

**场景：幽灵配置变更**

周一早晨检查发现堡垒机 SSH root 登录被启用，违反安全策略。
团队无人承认修改。工程师必须使用 auditd 日志确定：

- 哪个用户做了修改
- 何时修改
- 使用什么命令

最终生成事故报告（報告書）。

## Scenario Description (Japanese)

**シナリオ：ゴースト設定変更**

月曜朝の確認で、踏み台サーバーの SSH root ログインが有効化されていることが発覚。
セキュリティポリシー違反である。チーム内で誰も変更を認めていない。
エンジニアは auditd ログを使用して以下を特定する必要がある：

- 誰が変更したか
- いつ変更したか
- どのコマンドを使用したか

最終的にインシデント報告書を作成する。

## Files

| File | Purpose |
|------|---------|
| `setup-audit.sh` | Set up audit rules for SSH config monitoring |
| `simulate-change.sh` | Simulate the unauthorized configuration change |
| `investigate.sh` | Investigate the change using ausearch |
| `cleanup.sh` | Clean up after the scenario |

## Usage

```bash
# Step 1: Set up audit rules
sudo bash setup-audit.sh

# Step 2: Simulate the change (run as different user or in different terminal)
sudo bash simulate-change.sh

# Step 3: Investigate
sudo bash investigate.sh

# Step 4: Clean up
sudo bash cleanup.sh
```

## Learning Objectives

1. Configure audit rules for critical file monitoring
2. Use `auditctl -w` to watch files
3. Use `ausearch -k` to find events by key
4. Understand `auid` (audit user ID) vs `uid`
5. Generate an incident report based on findings
