# Vault 练习

## 练习列表

| 练习 | 内容 | 命令 |
|------|------|------|
| 01-vault-basics | Vault 基础操作 | `ansible-playbook 01-vault-basics.yaml` |
| 02-multi-vault-id | 多环境 Vault 管理 | 见文件内说明 |

## 动手练习：创建加密文件

### 步骤 1: 创建密码文件

```bash
# 创建密码文件（实际内容请更换）
echo "my_secret_password" > ~/.vault_pass
chmod 600 ~/.vault_pass
```

### 步骤 2: 加密示例文件

```bash
# 将明文示例文件加密为正式 vault 文件
cp vars/secrets_example.yaml vars/vault.yaml
ansible-vault encrypt vars/vault.yaml --vault-password-file ~/.vault_pass
```

### 步骤 3: 验证加密

```bash
# 查看加密文件内容
head -1 vars/vault.yaml
# 应该看到: $ANSIBLE_VAULT;1.1;AES256

# 查看解密后内容
ansible-vault view vars/vault.yaml --vault-password-file ~/.vault_pass
```

### 步骤 4: 运行 Playbook

```bash
ansible-playbook exercises/01-vault-basics.yaml --vault-password-file ~/.vault_pass
```

## 清理

```bash
rm -f ~/.vault_pass vars/vault.yaml
```
