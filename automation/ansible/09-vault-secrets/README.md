# 09 · Vault 与机密管理（Vault & Secrets Management）

> **目标**：掌握 Ansible Vault 加密和机密管理
> **前置**：[08 · 错误处理](../08-error-handling/)
> **时间**：30 分钟
> **版本**：ansible-core 2.15+，amazon.aws >= 8.0.0
> **实战项目**：加密数据库密码

---

## 将学到的内容

1. 使用 ansible-vault 加密
2. 加密变量 vs 加密文件
3. Vault 密码管理
4. 集成 AWS Secrets Manager

---

## 准备环境

```bash
# 1. 切换到 ansible 用户（如果当前不是 ansible 用户）
[ "$(whoami)" != "ansible" ] && sudo su - ansible

# 2. 更新课程仓库（获取最新内容）
cd ~/repo && git pull

# 3. 进入本课目录
cd ~/09-vault-secrets

# 4. 确认 Managed Nodes 可连接
ansible all -m ping
```

---

## Step 1 — Ansible Vault 基础

### 1.1 加密文件

```bash
# 创建加密文件
ansible-vault create secrets.yaml

# 加密现有文件
ansible-vault encrypt vars/passwords.yaml

# 编辑加密文件
ansible-vault edit secrets.yaml

# 解密文件
ansible-vault decrypt secrets.yaml

# 查看加密文件
ansible-vault view secrets.yaml

# 修改密码
ansible-vault rekey secrets.yaml
```

### 1.2 加密字符串

```bash
# 加密单个字符串
ansible-vault encrypt_string 'my_secret_password' --name 'db_password'
```

输出：

```yaml
db_password: !vault |
          $ANSIBLE_VAULT;1.1;AES256
          61626364656667686970...
```

---

## Step 2 — 在 Playbook 中使用

### 2.1 加密变量文件

```yaml
# vars/secrets.yaml (加密后)
db_password: supersecret
api_key: abc123xyz
```

### 2.2 使用加密变量

```yaml
---
- name: Use vault secrets
  hosts: all
  vars_files:
    - vars/secrets.yaml

  tasks:
    - name: Configure database
      ansible.builtin.template:
        src: db.conf.j2
        dest: /etc/myapp/db.conf
      vars:
        password: "{{ db_password }}"
```

### 2.3 运行时解密

```bash
# 交互式输入密码
ansible-playbook site.yaml --ask-vault-pass

# 使用密码文件
ansible-playbook site.yaml --vault-password-file ~/.vault_pass

# 使用环境变量
export ANSIBLE_VAULT_PASSWORD_FILE=~/.vault_pass
ansible-playbook site.yaml
```

---

## Step 3 — Vault 密码管理

### 3.1 密码文件

```bash
# 创建密码文件
echo "my_vault_password" > ~/.vault_pass
chmod 600 ~/.vault_pass
```

> ⚠️ **安全警告**：
> - 密码文件**绝对不能**提交到 Git
> - 使用后应尽快删除（CI/CD 场景）
> - 生产环境考虑使用密码管理器脚本（如 `pass`、`gopass`）

### 3.2 ansible.cfg 配置

```ini
[defaults]
vault_password_file = ~/.vault_pass
```

### 3.3 多 Vault ID（多环境）

```bash
# 创建带 ID 的加密文件
ansible-vault create --vault-id dev@~/.vault_pass_dev secrets_dev.yaml
ansible-vault create --vault-id prod@~/.vault_pass_prod secrets_prod.yaml

# 使用多个 vault ID
ansible-playbook site.yaml \
  --vault-id dev@~/.vault_pass_dev \
  --vault-id prod@~/.vault_pass_prod
```

---

## Step 4 — CI/CD 中使用 Vault

### 4.1 GitHub Actions

```yaml
# .github/workflows/deploy.yaml
name: Deploy
on: push

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Create vault password file
        run: |
          printf '%s' "${{ secrets.ANSIBLE_VAULT_PASSWORD }}" > .vault_pass
          chmod 600 .vault_pass

      - name: Run Ansible
        run: |
          ansible-playbook -i inventory site.yaml \
            --vault-password-file .vault_pass

      - name: Cleanup vault password
        if: always()
        run: rm -f .vault_pass
```

> 💡 使用 `printf '%s'` 而非 `echo` 避免末尾换行符问题。`if: always()` 确保即使失败也会清理。

### 4.2 Jenkins

```groovy
pipeline {
    agent any
    environment {
        ANSIBLE_VAULT_PASSWORD_FILE = credentials('vault-password')
    }
    stages {
        stage('Deploy') {
            steps {
                sh 'ansible-playbook site.yaml'
            }
        }
    }
}
```

---

## Step 5 — 集成 AWS Secrets Manager

### 5.1 安装依赖

```bash
pip3 install boto3
ansible-galaxy collection install amazon.aws
```

### 5.2 lookup 插件

> ⚠️ **费用警告**：AWS Secrets Manager 按 API 调用和存储收费。
> 每个 Secret 约 $0.40/月，每 10,000 次 API 调用 $0.05。

```yaml
---
- name: Use AWS Secrets Manager
  hosts: all
  vars:
    # 使用 secretsmanager_secret（旧版 aws_secret 已重定向）
    db_secret: "{{ lookup('amazon.aws.secretsmanager_secret', 'myapp/database') }}"

  tasks:
    - name: Configure with secret
      ansible.builtin.template:
        src: db.conf.j2
        dest: /etc/myapp/db.conf
        mode: '0600'
      vars:
        db_user: "{{ (db_secret | from_json).username }}"
        db_pass: "{{ (db_secret | from_json).password }}"
      no_log: true   # 防止密码出现在日志中
```

> ⚠️ **绝对禁止**：不要用 `debug` 模块打印密码！
> ```yaml
> # ❌ 永远不要这样做！
> - debug:
>     msg: "Password: {{ db_password }}"
> ```
>
> 正确做法是使用 `no_log: true` 隐藏敏感任务输出。

### 5.3 动态获取密码

```yaml
- name: Configure database
  ansible.builtin.template:
    src: db.conf.j2
    dest: /etc/myapp/db.conf
  vars:
    db_config: "{{ lookup('amazon.aws.secretsmanager_secret', 'myapp/db-credentials') | from_json }}"
    db_host: "{{ db_config.host }}"
    db_user: "{{ db_config.username }}"
    db_pass: "{{ db_config.password }}"
```

---

## Step 6 — 最佳实践

### 6.1 目录结构

```
project/
├── ansible.cfg
├── site.yaml
├── inventory/
├── group_vars/
│   ├── all.yaml           # 非敏感变量
│   └── all/
│       ├── vars.yaml      # 非敏感
│       └── vault.yaml     # 加密的敏感变量
└── .vault_pass            # Git 忽略
```

### 6.2 .gitignore

```
# 忽略密码文件
.vault_pass
*vault_pass*
*.key
*.pem
```

### 6.3 变量命名约定

```yaml
# vault.yaml (加密)
vault_db_password: "secret123"
vault_api_key: "abc123"

# vars.yaml (引用加密变量)
db_password: "{{ vault_db_password }}"
api_key: "{{ vault_api_key }}"
```

---

## Mini-Project：安全的密码管理

1. 创建加密的 `vault.yaml` 包含：
   - 数据库密码
   - API 密钥
   - SSH 私钥

2. 创建 Playbook 使用这些密码配置应用

3. 配置 CI/CD 密码注入

---

## 动手前检查清单

| # | 检查项 | 验证命令 |
|---|--------|----------|
| 1 | Vault 文件可解密 | `ansible-vault view secrets.yaml` |
| 2 | 密码文件权限正确 | `ls -la ~/.vault_pass` (应为 600) |
| 3 | 密码文件已忽略 | `git check-ignore .vault_pass` |
| 4 | AWS 凭证配置（如使用） | `aws sts get-caller-identity` |

---

## 日本企業現場ノート

> 💼 **机密管理的企业实践**

| 要点 | 说明 |
|------|------|
| **密钥轮换** | 定期 rekey，记录轮换时间和操作人 |
| **権限分離** | Vault 密码管理员 ≠ Playbook 执行者 |
| **監査ログ** | 记录谁在何时解密/修改了什么 |
| **変更管理** | Vault 文件变更需提交审批 |
| **バックアップ** | 加密文件需备份，密码需安全存储 |

```bash
# 验证 vault 文件是否真的加密
head -1 secrets.yaml
# 应该看到: $ANSIBLE_VAULT;1.1;AES256
```

> 📋 **面试/入场时可能被问**：
> - 「Vault パスワードの管理方法は？」→ 外部シークレットマネージャー or CI ツールの Secrets
> - 「平文でパスワードを保存していませんか？」→ 絶対 NG、Vault 必須

---

## 面试要点

> **問題**：Vault パスワードを CI/CD で管理する方法は？
>
> **回答**：
> - 環境変数 ANSIBLE_VAULT_PASSWORD_FILE
> - CI ツールの Secret 機能（GitHub Secrets, Jenkins Credentials）
> - 外部シークレットマネージャー（AWS Secrets Manager, HashiCorp Vault）

---

## 本课小结

| 概念 | 要点 |
|------|------|
| ansible-vault | 加密/解密工具 |
| --vault-password-file | 密码文件参数 |
| encrypt_string | 加密单个变量 |
| Vault ID | 多环境密码管理 |
| AWS Secrets Manager | 外部密码集成 |

---

## 清理资源

> **保留 Managed Nodes** - 后续课程都需要使用。
>
> 学完所有课程后，请参考 [课程首页的清理资源](../#清理资源) 删除所有节点。

---

## 系列导航

← [08 · 错误处理](../08-error-handling/) | [Home](../) | [Next →](../10-awx-tower/)
