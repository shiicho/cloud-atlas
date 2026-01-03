# 06 · 获取帮助

> **目标**：学会自学，掌握 Linux 内置的帮助系统
> **前置**：已完成 [05 · 查看文件内容](../05-viewing-files/)
> **时间**：60 分钟
> **环境**：任意 Linux 发行版

---

## 将学到的内容

1. 使用 man 手册页
2. 使用 --help 快速查看
3. 用 apropos 查找命令
4. 培养自学习惯

---

## Step 1 — 先跑起来：打开说明书（2 分钟）

> 🎯 **目标**：发现每个命令都有内置说明书。

```bash
man ls
```

**看到了什么？**

```
LS(1)                            User Commands                           LS(1)

NAME
       ls - list directory contents

SYNOPSIS
       ls [OPTION]... [FILE]...

DESCRIPTION
       List information about the FILEs (the current directory by default).
       Sort entries alphabetically if none of -cftuvSUX nor --sort is
       specified.
       ...
```

按 `q` 退出。

🎉 **每个 Linux 命令都有一本内置手册！**

---

## Step 2 — man 手册详解（20 分钟）

### 2.1 man 页面结构

```bash
man ls
```

| 区块 | 内容 |
|------|------|
| NAME | 命令名称和一句话描述 |
| SYNOPSIS | 使用格式（语法） |
| DESCRIPTION | 详细说明 |
| OPTIONS | 所有可用选项 |
| EXAMPLES | 使用示例（如果有） |
| SEE ALSO | 相关命令 |

### 2.2 man 页面导航

导航方式和 `less` 一样：

| 按键 | 动作 |
|------|------|
| `Space` | 下一页 |
| `b` | 上一页 |
| `/pattern` | 搜索 |
| `n` | 下一个匹配 |
| `q` | 退出 |

### 2.3 man 章节

```bash
# 查看特定章节
man 5 passwd    # 配置文件格式
man 1 passwd    # 命令用法
```

| 章节 | 内容 |
|------|------|
| 1 | 用户命令 |
| 2 | 系统调用 |
| 3 | 库函数 |
| 4 | 特殊文件（设备） |
| 5 | 文件格式和配置 |
| 6 | 游戏 |
| 7 | 杂项 |
| 8 | 系统管理命令 |

### 2.4 实践练习

```bash
# 查看 ls 手册
man ls
# 搜索 -a 选项: 输入 /-a 然后回车

# 查看 cp 手册
man cp
# 找到 -r 选项的说明

# 查看 passwd 文件格式
man 5 passwd
```

---

## Step 3 — --help 快速参考（10 分钟）

### 3.1 当你只需要快速查看

```bash
ls --help
```

```
Usage: ls [OPTION]... [FILE]...
List information about the FILEs (the current directory by default).

Mandatory arguments to long options are mandatory for short options too.
  -a, --all                  do not ignore entries starting with .
  -A, --almost-all           do not list implied . and ..
  ...
```

### 3.2 man vs --help

| 特点 | `man` | `--help` |
|------|-------|----------|
| 详细程度 | 完整文档 | 简洁摘要 |
| 启动速度 | 较慢 | 即时 |
| 使用场景 | 深入学习 | 快速查阅 |
| 导航 | 可翻页 | 直接输出 |

### 3.3 专业技巧

```bash
# 输出太长？用 less 分页
ls --help | less

# 快速找特定选项
ls --help | grep -i "sort"
```

---

## Step 4 — 查找命令（15 分钟）

### 4.1 apropos - 我想做某事，用什么命令？

```bash
apropos copy
```

```
cp (1)               - copy files and directories
dd (1)               - convert and copy a file
install (1)          - copy files and set attributes
rsync (1)            - a fast, versatile, remote (and local) file-copying tool
...
```

### 4.2 which - 这个命令在哪里？

```bash
which python
```

```
/usr/bin/python
```

### 4.3 type - 这是什么类型的命令？

```bash
type ls
type cd
type ll
```

```
ls is aliased to `ls --color=auto'
cd is a shell builtin
ll is aliased to `ls -la'
```

### 4.4 whatis - 一句话说明

```bash
whatis ls cp mv
```

```
ls (1)               - list directory contents
cp (1)               - copy files and directories
mv (1)               - move (rename) files
```

---

## Step 5 — 自学习惯养成（10 分钟）

### 5.1 错误信息是你的朋友

```bash
# 故意输错
ls --invalid-option
```

```
ls: unrecognized option '--invalid-option'
Try 'ls --help' for more information.
```

**学习**：错误信息告诉你怎么获取帮助！

### 5.2 学习流程图

![Learning Flow](images/learning-flow.png)

<details>
<summary>View ASCII source</summary>

```
┌─────────────────────────────────────────────────────────────┐
│                    自学流程                                  │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│   遇到问题或新命令                                           │
│          │                                                  │
│          ▼                                                  │
│   ┌──────────────┐                                          │
│   │ 快速了解？    │──Yes──► command --help                   │
│   └──────────────┘                                          │
│          │ No                                               │
│          ▼                                                  │
│   ┌──────────────┐                                          │
│   │ 深入学习？    │──Yes──► man command                      │
│   └──────────────┘                                          │
│          │ No                                               │
│          ▼                                                  │
│   ┌──────────────┐                                          │
│   │ 不知道命令？  │──Yes──► apropos keyword                  │
│   └──────────────┘                                          │
│          │ No                                               │
│          ▼                                                  │
│   ┌──────────────┐                                          │
│   │ 复杂问题？    │──Yes──► Web 搜索（官方文档优先）          │
│   └──────────────┘                                          │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

</details>

### 5.3 为什么 man 优于 Google？

| 优势 | 说明 |
|------|------|
| **版本匹配** | man 总是显示你安装的版本的文档 |
| **权威性** | 官方文档，不是博客猜测 |
| **离线可用** | 服务器没网也能查 |
| **一致性** | 格式统一，易于阅读 |

---

## Step 6 — 综合练习（5 分钟）

### 6.1 自学挑战

```bash
# 1. 我想压缩文件，用什么命令？
apropos compress

# 2. tar 怎么用？
tar --help

# 3. 我想深入学习 tar
man tar
# 搜索 "create"

# 4. gzip 在哪？
which gzip
type gzip
```

### 6.2 实用场景

```bash
# 忘记 grep 的选项
grep --help | grep "case"
# 发现 -i 是忽略大小写

# 不知道怎么创建符号链接
apropos link
man ln
```

---

## 本课小结

| 命令/方式 | 用途 | 使用场景 |
|-----------|------|----------|
| `man command` | 完整手册 | 深入学习 |
| `command --help` | 快速参考 | 查找选项 |
| `apropos keyword` | 搜索命令 | 不知道用什么命令 |
| `which command` | 查找位置 | 确认命令路径 |
| `type command` | 查看类型 | 区分别名/内置/外部 |

**核心理念**：man 优先于 Google。错误信息是帮助，不是惩罚。

---

## 下一步

你现在可以自学了！接下来学习如何"编辑"——用文本编辑器修改文件。

→ [07 · 文本编辑基础](../07-text-editing/)

---

## 面试准备

💼 **よくある質問**

**Q: man ページの読み方は？**

A: SYNOPSIS でコマンド構文を確認、DESCRIPTION で詳細を読む、OPTIONS で必要なオプションを探す。`/` で検索可能。

**Q: --help と man の使い分けは？**

A: 速く確認したいなら `--help`、詳しく学びたいなら `man`。スクリプトでは `--help` の出力をパースすることも。

**Q: apropos が空の結果を返す場合は？**

A: `sudo mandb` を実行してデータベースを更新。検索キーワードを変えてみることも有効。

---

## トラブルシューティング

🔧 **よくある問題**

**`No manual entry for xxx`**

```bash
# man ページがインストールされていない
# パッケージを確認
apt-cache search xxx-doc
# または代替
xxx --help
```

**`apropos` で "nothing appropriate" が出る**

```bash
# man データベースを更新
sudo mandb

# 別のキーワードで試す
apropos "file copy"
```

**man ページが英語で読みにくい**

```bash
# 日本語 man ページをインストール
sudo apt install manpages-ja

# 確認
man ls  # 日本語になるはず
```

---

## 检查清单

在继续下一课之前，确认你能：

- [ ] 用 `man` 打开手册并搜索内容
- [ ] 用 `--help` 快速查看命令用法
- [ ] 用 `apropos` 查找不知道名字的命令
- [ ] 用 `which` 和 `type` 查看命令信息
- [ ] 理解为什么 man 优于 Google 搜索

---

## 系列导航

← [05 · 查看文件内容](../05-viewing-files/) | [Home](../) | [07 · 文本编辑基础 →](../07-text-editing/)
