# Ansible Ad-Hoc Commands - Practice Exercises

本目录包含 6 个实战练习脚本，帮助你掌握 Ansible ad-hoc 命令和常用模块。

## 练习清单

### 01-setup-facts.sh - 收集系统信息
**学习目标**: 使用 setup 模块收集主机的系统信息（facts）

**执行方法**:
```bash
bash 01-setup-facts.sh
```

**知识点**:
- `ansible -m setup` 收集所有系统信息
- 使用 `filter=` 参数筛选特定信息
- 常用筛选：发行版、内存、网络等

**预期输出**: 全部为 GREEN（成功，setup 模块只读取信息，不修改系统）

---

### 02-file-module.sh - 文件操作与幂等性
**学习目标**: 理解 file 模块的幂等性（idempotence）

**执行方法**:
```bash
bash 02-file-module.sh
```

**知识点**:
- 创建文件/目录：`state=touch` / `state=directory`
- 设置权限：`mode=0600`
- 幂等性：重复执行相同命令不会产生变化
- 删除文件：`state=absent`

**预期输出**:
- 第 1 次创建文件 → YELLOW（有变化）
- 第 1 次设置权限 → YELLOW（有变化）
- 第 2 次设置权限 → GREEN（无变化，幂等性！）
- 删除操作 → YELLOW（有变化）

---

### 03-copy-module.sh - 文件复制
**学习目标**: 使用 copy 模块传输内容到远程主机

**执行方法**:
```bash
bash 03-copy-module.sh
```

**知识点**:
- `content=` 直接写入内容（无需本地文件）
- `src=` 复制本地文件（此例未演示）
- `backup=yes` 覆盖前备份旧文件
- 结合 command 模块验证文件内容

**预期输出**:
- 首次复制 → YELLOW（创建新文件）
- 更新内容 → YELLOW（内容变化）
- 验证内容 → YELLOW（command 模块总是标记为 CHANGED）

---

### 04-command-idempotent.sh - 让 command 模块具有幂等性
**学习目标**: 使用 `creates=` 和 `removes=` 参数控制命令执行条件

**执行方法**:
```bash
bash 04-command-idempotent.sh
```

**知识点**:
- `creates=/path` - 仅当文件不存在时执行
- `removes=/path` - 仅当文件存在时执行
- command 模块本身不幂等，但可通过参数实现

**预期输出**:
- 第 1 次 `creates` → YELLOW（文件不存在，执行命令）
- 第 2 次 `creates` → GREEN + "skipped"（文件已存在，跳过）
- 第 1 次 `removes` → YELLOW（文件存在，执行删除）
- 第 2 次 `removes` → GREEN + "skipped"（文件不存在，跳过）

---

### 05-fetch-module.sh - 从远程主机下载文件
**学习目标**: 使用 fetch 模块将远程文件拉取到控制节点

**执行方法**:
```bash
bash 05-fetch-module.sh
```

**知识点**:
- fetch vs copy：fetch 是反向操作（远程 → 本地）
- `flat=no` 保留主机名目录结构
- `flat=yes` 平铺到目标目录（多主机会冲突）

**预期输出**:
- 创建远程文件 → YELLOW
- fetch 文件 → YELLOW
- 本地查看 `./fetched/` 目录，包含子目录（主机名/路径）

---

### 06-ansible-doc.sh - 查看模块文档
**学习目标**: 使用 ansible-doc 命令查看模块用法

**执行方法**:
```bash
bash 06-ansible-doc.sh
```

**知识点**:
- `ansible-doc -l` 列出所有可用模块
- `ansible-doc <module>` 查看模块完整文档
- `ansible-doc -s <module>` 查看模块参数速查

**预期输出**: 命令行文档输出（无颜色标记）

---

## Ansible 输出颜色说明

| 颜色 | 状态 | 含义 |
|------|------|------|
| GREEN | SUCCESS | 成功，但无变化（幂等性） |
| YELLOW | CHANGED | 成功，且系统状态发生变化 |
| RED | FAILED | 执行失败 |
| PURPLE | SKIPPED | 条件不满足，跳过执行 |

## 练习顺序建议

1. 先执行 **06-ansible-doc.sh**，学会查文档
2. 再执行 **01-setup-facts.sh**，了解系统信息
3. 按顺序执行 **02 → 03 → 04 → 05**，体验幂等性和常用模块

## 清理环境

所有脚本都包含 cleanup 步骤，执行完自动清理。如需手动清理：

```bash
# 清理远程主机临时文件
ansible all -m shell -a "rm -rf /tmp/ansible_* /tmp/hello.txt /tmp/marker /tmp/remote_info.txt"

# 清理本地目录
rm -rf ./fetched
```

## 故障排查

**Q: 执行脚本提示 "permission denied"**
```bash
chmod +x *.sh
```

**Q: 连接主机失败**
```bash
# 检查 inventory 配置
ansible-inventory --list

# 测试连接
ansible all -m ping
```

**Q: 想看更详细的执行过程**
```bash
# 在任意 ansible 命令后加 -v / -vv / -vvv
ansible all -m ping -vv
```

## 参考资源

- [Ansible 模块索引](https://docs.ansible.com/ansible/latest/collections/index_module.html)
- [Ad-Hoc 命令官方文档](https://docs.ansible.com/ansible/latest/user_guide/intro_adhoc.html)
- 课程主 README: `../README.md`
