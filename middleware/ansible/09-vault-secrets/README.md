# 09 · Vault 与机密管理（Vault & Secrets Management）

> **目标**：掌握 Ansible Vault 加密和机密管理
> **前置**：[08 · 错误处理](../08-error-handling/)
> **时间**：30 分钟
> **实战项目**：加密数据库密码

---

## 将学到的内容

1. 使用 ansible-vault 加密
2. 加密变量 vs 加密文件
3. Vault 密码管理
4. 集成 AWS Secrets Manager

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
        run: echo "${{ secrets.ANSIBLE_VAULT_PASSWORD }}" > .vault_pass

      - name: Run Ansible
        run: |
          ansible-playbook -i inventory site.yaml \
            --vault-password-file .vault_pass
```

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

```yaml
---
- name: Use AWS Secrets Manager
  hosts: all
  vars:
    db_secret: "{{ lookup('amazon.aws.aws_secret', 'myapp/database') }}"

  tasks:
    - name: Display secret (debug only!)
      ansible.builtin.debug:
        msg: "Username: {{ (db_secret | from_json).username }}"
```

### 5.3 动态获取密码

```yaml
- name: Configure database
  ansible.builtin.template:
    src: db.conf.j2
    dest: /etc/myapp/db.conf
  vars:
    db_config: "{{ lookup('amazon.aws.aws_secret', 'myapp/db-credentials') | from_json }}"
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

## 系列导航

← [08 · 错误处理](../08-error-handling/) | [Home](../) | [Next →](../10-awx-tower/)
