# 08 · Shell 配置

> **目标**：理解并定制你的 Shell 环境  
> **前置**：已完成 [07 · 文本编辑基础](../07-text-editing/)  
> **时间**：90 分钟  
> **环境**：任意 Linux 发行版（使用 bash）  

---

## 将学到的内容

1. 理解 login shell 和 non-login shell 的区别
2. 知道该编辑哪个配置文件
3. 创建实用的 alias
4. 定制 Shell 提示符（PS1）

---

## Step 1 — 先跑起来：即时改变提示符（2 分钟）

> 🎯 **目标**：体验 Shell 可定制的魔力。  

```bash
export PS1='[\u@\h \W]\$ '
pwd
```

**看到了什么？**

```
[terraform@linux-lab ~]$
```

你的提示符变了！

> 💡 这只是临时的。关闭终端后会恢复。稍后我们会学习如何永久保存。  

---

## Step 2 — Login vs Non-Login Shell（20 分钟）

### 2.1 两种 Shell

| 类型 | 触发方式 | 读取的配置文件 |
|------|----------|----------------|
| **Login Shell** | SSH 登录、`su -` | `.bash_profile` / `.profile` |
| **Non-Login Shell** | 新开终端标签、`bash` | `.bashrc` |

### 2.2 如何判断？

```bash
echo $0
```

| 输出 | 含义 |
|------|------|
| `-bash` | Login shell（注意前面的 `-`） |
| `bash` | Non-login shell |

### 2.3 办公室比喻

![Shell Types](images/shell-types.png)

<details>
<summary>View ASCII source</summary>

```
┌─────────────────────────────────────────────────────────────┐
│                     Shell 类型比喻                           │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  Login Shell = 进入办公大楼                                  │
│  ┌─────────────────────────┐                                │
│  │  🏢 办公大楼            │                                │
│  │  ┌───────────────────┐  │                                │
│  │  │ 刷卡进入          │ ←── SSH 登录、开机登录            │
│  │  │ 读取 .bash_profile │  │                                │
│  │  └───────────────────┘  │                                │
│  └─────────────────────────┘                                │
│                                                             │
│  Non-Login Shell = 在办公桌上新开一个文件夹                  │
│  ┌─────────────────────────┐                                │
│  │  🖥️ 你的办公桌          │                                │
│  │  ┌───────────────────┐  │                                │
│  │  │ 已经在楼里了      │ ←── 新开终端标签                  │
│  │  │ 只读取 .bashrc    │  │                                │
│  │  └───────────────────┘  │                                │
│  └─────────────────────────┘                                │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

</details>

### 2.4 配置文件加载顺序

**Login Shell：**
```
/etc/profile → ~/.bash_profile (或 ~/.profile) → ~/.bashrc (如果被 source)
```

**Non-Login Shell：**
```
~/.bashrc
```

### 2.5 最佳实践

将所有配置放在 `.bashrc`，在 `.bash_profile` 中 source 它：

```bash
# ~/.bash_profile 内容
if [ -f ~/.bashrc ]; then
    source ~/.bashrc
fi
```

这样无论是哪种 shell，配置都会加载。

---

## Step 3 — Alias：命令快捷方式（25 分钟）

### 3.1 什么是 Alias？

Alias = 别名 = 命令快捷方式

```bash
# 创建一个临时 alias
alias ll='ls -la'

# 使用它
ll
```

### 3.2 查看现有 Alias

```bash
alias
```

### 3.3 常用 Alias

```bash
# 导航类
alias ..='cd ..'
alias ...='cd ../..'
alias ~='cd ~'

# 列表类
alias ll='ls -la'
alias la='ls -A'
alias l='ls -CF'

# 安全类
alias rm='rm -i'
alias cp='cp -i'
alias mv='mv -i'

# 实用类
alias h='history'
alias c='clear'
alias ports='ss -tulanp'  # ss 是 netstat 的现代替代
```

### 3.4 永久保存 Alias

```bash
# 编辑 .bashrc
nano ~/.bashrc

# 添加你的 alias（在文件末尾）
alias ll='ls -la'
alias rm='rm -i'

# 保存退出后，使其生效
source ~/.bashrc

# 验证
alias ll
```

### 3.5 动手练习

```bash
# 1. 添加 alias 到 .bashrc
echo "alias ll='ls -la'" >> ~/.bashrc
echo "alias cls='clear'" >> ~/.bashrc

# 2. 重新加载
source ~/.bashrc

# 3. 测试
ll
cls
```

---

## Step 4 — PS1：定制提示符（25 分钟）

### 4.1 PS1 转义序列

| 转义符 | 含义 |
|--------|------|
| `\u` | 用户名 |
| `\h` | 主机名（短） |
| `\H` | 主机名（完整） |
| `\w` | 当前目录（完整路径） |
| `\W` | 当前目录（仅目录名） |
| `\$` | `$`（普通用户）或 `#`（root） |
| `\t` | 24小时制时间 |
| `\d` | 日期 |
| `\n` | 换行 |

### 4.2 常见提示符样式

**默认风格：**
```bash
export PS1='\u@\h:\w\$ '
# terraform@linux-lab:~/playground$
```

**简洁风格：**
```bash
export PS1='[\W]\$ '
# [playground]$
```

**信息丰富风格：**
```bash
export PS1='[\u@\h \W]\$ '
# [terraform@linux-lab playground]$
```

**带时间：**
```bash
export PS1='[\t \W]\$ '
# [14:30:45 playground]$
```

### 4.3 添加颜色

```bash
# 绿色用户名，蓝色目录
export PS1='\[\033[32m\]\u@\h\[\033[0m\]:\[\033[34m\]\w\[\033[0m\]\$ '
```

颜色代码：

| 代码 | 颜色 |
|------|------|
| `\033[30m` | 黑色 |
| `\033[31m` | 红色 |
| `\033[32m` | 绿色 |
| `\033[33m` | 黄色 |
| `\033[34m` | 蓝色 |
| `\033[0m` | 重置 |

### 4.4 永久保存 PS1

```bash
# 编辑 .bashrc
nano ~/.bashrc

# 添加到文件末尾
export PS1='[\u@\h \W]\$ '

# 保存退出，重新加载
source ~/.bashrc
```

---

## Step 5 — 实用配置技巧（10 分钟）

### 5.1 历史记录增强

```bash
# 添加到 .bashrc

# 增加历史记录大小
export HISTSIZE=10000
export HISTFILESIZE=20000

# 避免重复记录
export HISTCONTROL=ignoredups:erasedups

# 时间戳
export HISTTIMEFORMAT="%F %T "
```

### 5.2 安全别名

```bash
# 防止误删
alias rm='rm -i'
alias cp='cp -i'
alias mv='mv -i'
```

### 5.3 自动补全增强

```bash
# 忽略大小写补全
bind "set completion-ignore-case on"
```

---

## Step 6 — 综合练习（5 分钟）

### 6.1 创建你的配置

```bash
# 1. 备份现有配置
cp ~/.bashrc ~/.bashrc.backup

# 2. 编辑配置
nano ~/.bashrc

# 3. 添加以下内容到文件末尾：
# ========================================
# My Custom Settings
# ========================================

# Aliases
alias ll='ls -la'
alias ..='cd ..'
alias rm='rm -i'
alias h='history'
alias c='clear'

# PS1 Prompt
export PS1='[\u@\h \W]\$ '

# History settings
export HISTSIZE=10000
export HISTCONTROL=ignoredups

# 4. 保存退出

# 5. 重新加载
source ~/.bashrc

# 6. 测试
ll
..
```

---

## 本课小结

| 概念 | 说明 |
|------|------|
| Login Shell | SSH/`su -` 触发，读取 `.bash_profile` |
| Non-Login Shell | 新终端标签触发，读取 `.bashrc` |
| Alias | 命令快捷方式，`alias name='command'` |
| PS1 | Shell 提示符，用 `\u`, `\h`, `\W` 等定制 |
| source | 重新加载配置文件 |

**核心理念**：配置放 `.bashrc`，从 `.bash_profile` source 它。

---

## 下一步

你的 Shell 现在是定制的了！接下来学习环境变量和 PATH，理解系统如何找到命令。

→ [09 · 环境变量和 PATH](../09-environment-path/)

---

## 面试准备

💼 **よくある質問**

**Q: .bashrc と .bash_profile の違いは？**

A: `.bash_profile` はログインシェル（SSH 等）で読まれ、`.bashrc` は非ログインシェル（新しいターミナルタブ等）で読まれます。`.bash_profile` から `.bashrc` を source するのがベストプラクティス。

**Q: alias はどこに書くべき？**

A: `.bashrc` に書きます。環境変数は `.bash_profile` に、対話的設定（alias, PS1）は `.bashrc` に書くのが一般的。

**Q: source と . (dot) の違いは？**

A: 同じです。`source ~/.bashrc` と `. ~/.bashrc` は同等。`. ` は POSIX 標準、`source` は bash 拡張。

---

## トラブルシューティング

🔧 **よくある問題**

**設定が反映されない**

```bash
# 再読み込み
source ~/.bashrc

# それでもダメなら
echo $0  # Login/Non-login 確認
cat ~/.bashrc  # 設定内容確認
```

**PS1 を変更したら表示がおかしい**

```bash
# デフォルトに戻す
export PS1='\u@\h:\w\$ '

# .bashrc から問題の行を削除
nano ~/.bashrc
```

**alias が効かない**

```bash
# alias が定義されているか確認
alias

# シェルスクリプト内では alias は効かない
# 関数を使うか、コマンド自体を書く
```

---

## 检查清单

在继续下一课之前，确认你能：

- [ ] 区分 Login Shell 和 Non-Login Shell
- [ ] 知道配置应该写在 `.bashrc` 还是 `.bash_profile`
- [ ] 创建和使用 alias
- [ ] 定制 PS1 提示符
- [ ] 用 `source` 重新加载配置

---

## 系列导航

← [07 · 文本编辑基础](../07-text-editing/) | [Home](../) | [09 · 环境变量和 PATH →](../09-environment-path/)
