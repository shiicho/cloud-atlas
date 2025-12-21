# 中间人攻击（Man-in-the-Middle Attack / MITM）

> **一句话**：攻击者在通信双方之间偷偷插入自己，窃听或篡改数据。

---

## 日常类比

想象你和朋友用纸条传话，中间有个"热心人"帮你们传递：

```
你 ──── "热心人" ──── 朋友
   └── 实际上偷看并修改了内容
```

这个"热心人"就是中间人（Man-in-the-Middle）。

---

## 技术场景

### 场景 1：公共 WiFi

```
你的手机                    攻击者                    银行网站
    │                         │                         │
    │  "连接银行网站"          │                         │
    ├────────────────────────▶│                         │
    │                         │  "代替你连接银行"        │
    │                         ├────────────────────────▶│
    │                         │                         │
    │  看起来正常的银行页面    │◀────────────────────────┤
    │◀────────────────────────┤                         │
    │                         │                         │
    │  输入账号密码            │                         │
    ├────────────────────────▶│  偷走你的密码！          │
```

### 场景 2：SSH（Ansible 使用场景）

```
Control Node                   攻击者                  Managed Node
    │                            │                        │
    │  ssh node1                 │                        │
    ├───────────────────────────▶│                        │
    │                            │  假装是 node1          │
    │  "连接成功"                 │◀───────────────────────┤
    │◀───────────────────────────┤                        │
    │                            │                        │
    │  执行 ansible playbook     │                        │
    ├───────────────────────────▶│  截获你的命令和密钥！   │
```

这就是为什么 **`host_key_checking=False` 在生产环境很危险**。

---

## 防护措施

| 攻击场景 | 防护方式 |
|----------|----------|
| **HTTPS** | 验证 SSL 证书（浏览器会警告） |
| **SSH** | `host_key_checking=True` + `known_hosts` |
| **公共 WiFi** | 使用 VPN |
| **DNS 劫持** | 使用 DNSSEC 或可信 DNS |

### SSH 防护示例

```bash
# 首次连接时验证指纹
ssh ansible@node1
# The authenticity of host 'node1' can't be established.
# ED25519 key fingerprint is SHA256:xxxxx
# Are you sure you want to continue connecting (yes/no)?

# 正确做法：确认指纹后输入 yes，之后会记录到 known_hosts
# 危险做法：设置 host_key_checking=False 跳过验证
```

---

## 为什么叫"中间人"？

| 术语 | 英文 | 说明 |
|------|------|------|
| **Man-in-the-Middle** | MITM | 攻击者位于通信"中间" |
| **端到端加密** | E2E Encryption | 只有通信双方能解密，中间人看不到内容 |
| **证书/密钥验证** | Certificate/Key Verification | 确认对方身份，防止冒充 |

---

## 面试要点

> **問題**：MITM 攻撃とは何ですか？どう防ぎますか？
>
> **期望回答**：
> - 通信の中間に攻撃者が入り、データを盗聴・改ざんする攻撃
> - 防御策：HTTPS の証明書検証、SSH の known_hosts、VPN の使用
> - Ansible では `host_key_checking=True` を本番環境で必ず有効にする

---

## 相关概念

- [Agent vs Agentless](./agent-agentless.md) — SSH 连接是 Agentless 的基础
- [幂等性](./idempotency.md) — 安全执行的另一个重要原则

---

[返回 Glossary 首页](../)
