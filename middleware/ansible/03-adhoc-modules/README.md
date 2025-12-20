# 03 · Ad-hoc 命令与模块入门（Ad-hoc Commands & Modules）

> **目标**：掌握 Ad-hoc 命令和核心模块  
> **前置**：[02 · Inventory 管理](../02-inventory/)  
> **时间**：30 分钟  
> **实战项目**：運用巡検 - 使用 Ad-hoc 进行系统检查

---

## 将学到的内容

1. Ad-hoc 命令语法
2. 核心模块：ping, command, shell, copy, file, dnf, service, user
3. 理解幂等性（Idempotency）
4. Check mode (-C) 和 Diff mode (-D)

---

## 实战练习 (Hands-on Exercises)

> 本课提供 6 个实战脚本，帮助你掌握核心模块和幂等性概念。

**目录**: `exercises/`

| 脚本 | 学习目标 | 关键模块 |
|------|----------|----------|
| `01-setup-facts.sh` | 收集系统信息 | setup (filter) |
| `02-file-module.sh` | 文件操作与幂等性 | file (touch, mode, absent) |
| `03-copy-module.sh` | 文件复制 | copy (content, backup) |
| `04-command-idempotent.sh` | 让 command 模块幂等 | command (creates, removes) |
| `05-fetch-module.sh` | 从远程下载文件 | fetch (flat) |
| `06-ansible-doc.sh` | 查看模块文档 | ansible-doc |

```bash
# 快速开始
cd ~/03-adhoc-modules/exercises
bash 01-setup-facts.sh
```

**输出颜色说明**:
- **GREEN** = 成功，无变化（幂等性生效）
- **YELLOW** = 成功，有变化
- **RED** = 执行失败
- **PURPLE** = 条件不满足，跳过

详细说明请参阅 [`exercises/README.md`](exercises/README.md)。

---

## Step 1 — Ad-hoc 命令语法

```bash
ansible <pattern> -m <module> -a "<arguments>" [options]
```

| 参数 | 说明 |
|------|------|
| `<pattern>` | 目标主机模式（all, webservers, node1） |
| `-m <module>` | 使用的模块 |
| `-a "<args>"` | 模块参数 |
| `-i <inventory>` | 指定 inventory |
| `-b` / `--become` | 使用 sudo |
| `-C` / `--check` | 检查模式（不执行） |
| `-v/-vv/-vvv` | 详细输出 |

---

## Step 2 — 核心模块

### 2.1 ping - 连通性测试

```bash
ansible all -m ping
```

> 注意：这不是 ICMP ping，而是测试 Ansible 连接。

### 2.2 command - 执行命令

```bash
# 执行简单命令
ansible all -m command -a "uptime"

# 默认模块就是 command
ansible all -a "uptime"
```

### 2.3 shell - Shell 命令（支持管道）

```bash
# 使用管道和重定向
ansible all -m shell -a "cat /etc/passwd | grep root"

# 环境变量
ansible all -m shell -a "echo $HOME"
```

### 2.4 copy - 复制文件

```bash
# 复制文件到远程
ansible all -m copy -a "src=/tmp/test.txt dest=/tmp/test.txt"

# 直接写入内容
ansible all -m copy -a "content='Hello World' dest=/tmp/hello.txt"
```

### 2.5 file - 文件/目录管理

```bash
# 创建目录
ansible all -m file -a "path=/opt/app state=directory mode=0755" -b

# 创建符号链接
ansible all -m file -a "src=/opt/app dest=/app state=link" -b

# 删除文件
ansible all -m file -a "path=/tmp/test.txt state=absent"
```

### 2.6 dnf/yum - 包管理

```bash
# 安装软件包
ansible all -m dnf -a "name=httpd state=present" -b

# 安装多个包
ansible all -m dnf -a "name=httpd,vim,htop state=present" -b

# 删除软件包
ansible all -m dnf -a "name=httpd state=absent" -b

# 更新指定包到最新版
ansible all -m dnf -a "name=httpd state=latest" -b
```

> ⚠️ **危险操作警告**
>
> ```bash
> # ❌ 禁止在生产环境执行！
> ansible all -m dnf -a "name=* state=latest" -b
> ```
>
> 这会更新**所有**软件包，可能导致：
> - 服务中断（内核更新需要重启）
> - 兼容性问题（依赖版本变化）
> - 无法回滚
>
> 正确做法：使用 `--limit` 限定范围，在维护窗口执行，提前备份。

### 2.7 service - 服务管理

```bash
# 启动服务
ansible webservers -m service -a "name=httpd state=started" -b

# 重启服务
ansible webservers -m service -a "name=httpd state=restarted" -b

# 设置开机启动
ansible webservers -m service -a "name=httpd enabled=yes" -b
```

### 2.8 user - 用户管理

```bash
# 创建用户
ansible all -m user -a "name=deploy state=present" -b

# 创建用户并设置组
ansible all -m user -a "name=deploy groups=wheel append=yes" -b

# 删除用户
ansible all -m user -a "name=deploy state=absent remove=yes" -b
```

---

## Step 3 — 幂等性（Idempotency）

幂等性意味着：**多次执行结果一致**。

```bash
# 第一次执行 - changed
ansible all -m dnf -a "name=htop state=present" -b
# node1 | CHANGED

# 第二次执行 - ok（无变更）
ansible all -m dnf -a "name=htop state=present" -b
# node1 | SUCCESS (changed=false)
```

> 💡 **面试要点**
>
> **問題**：べき等性（Idempotency）とは何ですか？
>
> **回答**：同じ操作を何度実行しても同じ結果になる性質。
> Ansible は状態管理により、既に目的の状態であれば変更を行わない。

---

## Step 4 — Check Mode 和 Diff Mode

### Check Mode (-C)

```bash
# 模拟执行，不实际变更
ansible all -m dnf -a "name=nginx state=present" -b -C
```

### Diff Mode (-D)

```bash
# 显示文件变更内容
ansible all -m copy -a "content='new content' dest=/tmp/test.txt" -D
```

### 组合使用

```bash
# 最安全的预览方式
ansible all -m copy -a "content='new' dest=/tmp/test.txt" -C -D
```

---

## Step 5 — Mini-Project：運用巡検

> **场景**：每日系统巡检，检查磁盘、服务状态、用户等。

### 巡检脚本

```bash
#!/bin/bash
# daily-check.sh

echo "=== 磁盘使用率 ==="
ansible all -m shell -a "df -h | grep -E '^/dev'" -o

echo "=== 内存使用 ==="
ansible all -m shell -a "free -m" -o

echo "=== httpd 服务状态 ==="
ansible webservers -m command -a "systemctl is-active httpd" -b

echo "=== 系统负载 ==="
ansible all -m shell -a "uptime" -o

echo "=== 最近登录 ==="
ansible all -m shell -a "last -n 5" -o
```

### 创建运维用户

```bash
# 在所有节点创建 ops 用户
ansible all -m user -a "name=ops_user groups=wheel state=present" -b

# 验证
ansible all -m shell -a "id ops_user"
```

---

## 常见错误

| 错误 | 原因 | 解决 |
|------|------|------|
| `MODULE FAILURE` | 模块参数错误 | 检查参数语法 |
| `Missing sudo password` | 需要 sudo 密码 | 配置 NOPASSWD |
| `No such file or directory` | 文件路径不存在 | 检查路径 |

---

## 动手前检查清单

| # | 检查项 | 验证命令 |
|---|--------|----------|
| 1 | 连接正常 | `ansible all -m ping` |
| 2 | Inventory 正确 | `ansible-inventory --graph` |
| 3 | 权限验证 | `ansible all -m command -a "whoami" -b` |

---

## 日本企業現場ノート

> 💼 **Ad-hoc 命令的企业使用规范**

| 要点 | 说明 |
|------|------|
| **禁止直接执行** | 生产环境禁止直接使用 ad-hoc，必须使用 Playbook + 审批 |
| **日志记录** | 开启 `ANSIBLE_LOG_PATH` 记录所有操作 |
| **限定范围** | 始终使用 `--limit` 限定目标主机 |
| **変更管理** | 任何变更需提前申请変更チケット |

```bash
# 正确做法：限定范围 + 记录日志
export ANSIBLE_LOG_PATH=~/ansible-$(date +%Y%m%d).log
ansible webservers --limit node1 -m dnf -a "name=httpd state=present" -b
```

> 📋 **面试/入场时可能被问**：「アドホックコマンドはいつ使いますか？」
> → 調査・確認用途のみ。変更操作は Playbook + 承認フロー経由。

---

## command vs shell 对比

| 模块 | 特点 | 使用场景 |
|------|------|----------|
| `command` | 不经过 shell，更安全 | 简单命令（推荐默认） |
| `shell` | 经过 /bin/sh，支持管道/重定向 | 需要 shell 特性时 |

> 💡 优先使用 `command`，只有需要管道 (`|`)、重定向 (`>`) 或环境变量时才用 `shell`。

---

## 本课小结

| 模块 | 用途 | 示例 |
|------|------|------|
| ping | 连通性测试 | `ansible all -m ping` |
| command/shell | 执行命令 | `-m command -a "cmd"`（优先） |
| copy | 复制文件 | `-m copy -a "src=.. dest=.."` |
| file | 文件管理 | `-m file -a "path=.. state=.."` |
| dnf | 包管理 | `-m dnf -a "name=.. state=.."` |
| service | 服务管理 | `-m service -a "name=.. state=.."` |
| user | 用户管理 | `-m user -a "name=.. state=.."`  |

---

## 系列导航

← [02 · Inventory](../02-inventory/) | [Home](../) | [Next →](../04-playbook-basics/)
