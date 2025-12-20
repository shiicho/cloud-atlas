# 03 · Ad-hoc 命令与模块（Ad-hoc Commands & Modules）

> **目标**：掌握 Ad-hoc 命令和核心模块
> **前置**：[02 · Inventory 管理](../02-inventory/)（需要已部署 Managed Nodes）
> **时间**：25 分钟

---

## 将学到的内容

1. Ad-hoc 命令语法
2. 核心模块：setup, file, copy, command, shell, dnf, service, user
3. 幂等性（Idempotency）
4. Check mode (-C) 和 Diff mode (-D)

---

## 前置确认

确保已完成 Lesson 02，Managed Nodes 正在运行：

```bash
cd ~/03-adhoc-modules
ansible all -m ping
```

如果失败，请先完成 [02 · Inventory 管理](../02-inventory/)。

---

## Step 1 — Ad-hoc 命令语法

```
ansible <目标> -m <模块> -a "<参数>" [选项]
```

| 部分 | 说明 | 示例 |
|------|------|------|
| `<目标>` | 主机或组 | `all`, `webservers`, `al2023-1.ans.local` |
| `-m <模块>` | 使用的模块 | `-m ping`, `-m shell`, `-m copy` |
| `-a "<参数>"` | 模块参数 | `-a "name=httpd state=present"` |
| `-b` | 使用 sudo | `ansible all -b -m dnf ...` |
| `-C` | 检查模式（不执行） | 预览变更 |
| `-D` | Diff 模式 | 显示文件差异 |
| `-v/-vv/-vvv` | 详细输出 | 调试时使用 |

---

## Step 2 — 核心模块

### 2.1 setup - 收集系统信息

```bash
# 查看所有 Facts
ansible all -m setup | head -50

# 过滤特定信息
ansible all -m setup -a "filter=ansible_distribution*"
ansible all -m setup -a "filter=ansible_memory_mb"
```

> 💡 `setup` 模块收集的信息称为 **Facts**，可在 Playbook 中使用。

### 2.2 command - 执行命令（默认模块）

```bash
# 执行简单命令
ansible all -m command -a "uptime"

# command 是默认模块，可省略 -m
ansible all -a "hostname"
ansible all -a "df -h /"
```

### 2.3 shell - Shell 命令（支持管道）

```bash
# 使用管道
ansible all -m shell -a "cat /etc/passwd | wc -l"

# 使用环境变量
ansible all -m shell -a "echo $HOME"

# 重定向
ansible all -m shell -a "date > /tmp/date.txt"
```

**command vs shell**：

| 模块 | 特点 | 使用场景 |
|------|------|----------|
| `command` | 不经过 shell，更安全 | 简单命令（推荐） |
| `shell` | 经过 /bin/sh | 需要管道/重定向时 |

### 2.4 file - 文件/目录管理

```bash
# 创建目录
ansible all -m file -a "path=/tmp/testdir state=directory mode=0755"

# 创建空文件
ansible all -m file -a "path=/tmp/testfile state=touch"

# 删除文件
ansible all -m file -a "path=/tmp/testfile state=absent"

# 创建符号链接
ansible all -m file -a "src=/tmp/testdir dest=/tmp/link state=link"
```

### 2.5 copy - 复制文件

```bash
# 直接写入内容
ansible all -m copy -a "content='Hello Ansible' dest=/tmp/hello.txt"

# 复制本地文件到远程
echo "Local file" > /tmp/local.txt
ansible all -m copy -a "src=/tmp/local.txt dest=/tmp/remote.txt"

# 带备份
ansible all -m copy -a "content='Updated' dest=/tmp/hello.txt backup=yes"
```

### 2.6 dnf - 包管理

```bash
# 安装软件包
ansible all -m dnf -a "name=htop state=present"

# 安装多个包
ansible all -m dnf -a "name=htop,vim,tree state=present"

# 卸载软件包
ansible all -m dnf -a "name=htop state=absent"

# 更新到最新版
ansible all -m dnf -a "name=htop state=latest"
```

### 2.7 service - 服务管理

```bash
# 启动服务
ansible webservers -m service -a "name=httpd state=started"

# 停止服务
ansible webservers -m service -a "name=httpd state=stopped"

# 重启服务
ansible webservers -m service -a "name=httpd state=restarted"

# 设置开机启动
ansible webservers -m service -a "name=httpd enabled=yes"
```

### 2.8 user - 用户管理

```bash
# 创建用户
ansible all -m user -a "name=testuser state=present"

# 创建用户并加入组
ansible all -m user -a "name=testuser groups=wheel append=yes"

# 删除用户
ansible all -m user -a "name=testuser state=absent remove=yes"
```

---

## Step 3 — 幂等性（Idempotency）

幂等性：**多次执行，结果相同**。

### 3.1 演示

```bash
# 第一次执行 - 安装 htop
ansible all -m dnf -a "name=htop state=present"
# 输出: CHANGED (changed=true)

# 第二次执行 - 已安装，跳过
ansible all -m dnf -a "name=htop state=present"
# 输出: SUCCESS (changed=false)
```

### 3.2 颜色含义

| 颜色 | 含义 |
|------|------|
| **GREEN** | 成功，无变化 |
| **YELLOW** | 成功，有变化 |
| **RED** | 执行失败 |
| **PURPLE** | 跳过 |

### 3.3 让 command 模块幂等

`command` 模块默认不幂等（每次都执行）。使用 `creates` / `removes` 参数：

```bash
# 只有当 /tmp/marker 不存在时才执行
ansible all -m command -a "touch /tmp/created creates=/tmp/marker"

# 只有当 /tmp/marker 存在时才执行
ansible all -m command -a "rm /tmp/marker removes=/tmp/marker"
```

---

## Step 4 — Check Mode 和 Diff Mode

### 4.1 Check Mode (-C)

预览变更，不实际执行：

```bash
ansible all -m dnf -a "name=nginx state=present" -C
```

### 4.2 Diff Mode (-D)

显示文件变更内容：

```bash
ansible all -m copy -a "content='new content' dest=/tmp/test.txt" -D
```

### 4.3 组合使用（最安全）

```bash
ansible all -m copy -a "content='new' dest=/tmp/test.txt" -C -D
```

---

## 实战练习

本课提供 6 个练习脚本，位于 `exercises/`：

| 脚本 | 学习目标 |
|------|----------|
| `01-setup-facts.sh` | 收集系统信息 |
| `02-file-module.sh` | 文件操作与幂等性 |
| `03-copy-module.sh` | 文件复制 |
| `04-command-idempotent.sh` | 让 command 幂等 |
| `05-fetch-module.sh` | 从远程下载文件 |
| `06-ansible-doc.sh` | 查看模块文档 |

```bash
cd ~/03-adhoc-modules/exercises
bash 01-setup-facts.sh
```

---

## 日本企業現場ノート

> 💼 **Ad-hoc 命令的企业使用规范**

| 要点 | 说明 |
|------|------|
| **禁止直接变更** | 生产环境禁止用 ad-hoc 做变更，必须使用 Playbook |
| **日志记录** | 开启 `ANSIBLE_LOG_PATH` |
| **限定范围** | 始终使用 `--limit` |

```bash
# 正确做法
export ANSIBLE_LOG_PATH=~/ansible-$(date +%Y%m%d).log
ansible webservers --limit al2023-1.ans.local -m shell -a "uptime"
```

> 📋 **面试题**：「アドホックコマンドはいつ使いますか？」
> → 調査・確認用途のみ。変更操作は Playbook 経由。

---

## 本课小结

| 模块 | 用途 | 示例 |
|------|------|------|
| setup | 收集系统信息 | `-m setup -a "filter=..."` |
| command | 执行命令（默认） | `-a "hostname"` |
| shell | Shell 命令 | `-m shell -a "cmd \| grep"` |
| file | 文件/目录管理 | `-m file -a "path=.. state=.."` |
| copy | 复制文件 | `-m copy -a "src=.. dest=.."` |
| dnf | 包管理 | `-m dnf -a "name=.. state=.."` |
| service | 服务管理 | `-m service -a "name=.. state=.."` |
| user | 用户管理 | `-m user -a "name=.. state=.."` |

---

## 下一步

掌握了 Ad-hoc 命令，开始学习 Playbook。

→ [04 · Playbook 基础](../04-playbook-basics/)

---

## 系列导航

← [02 · Inventory](../02-inventory/) | [Home](../) | [Next →](../04-playbook-basics/)
