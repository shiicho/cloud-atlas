# 04 · 文件和目录

> **目标**：安全地创建、复制、移动和删除文件  
> **前置**：已完成 [03 · 文件系统导航](../03-navigation/)  
> **时间**：90 分钟  
> **环境**：任意 Linux 发行版  

---

## 将学到的内容

1. 创建文件和目录（`touch`, `mkdir`）
2. 复制和移动文件（`cp`, `mv`）
3. 安全删除文件（`rm` 和注意事项）
4. 理解基本文件类型

---

## Step 1 — 先跑起来：创造东西（2 分钟）

> 🎯 **目标**：体验"创造"的感觉。  

```bash
mkdir -p ~/playground/test && touch ~/playground/test/hello.txt && ls -la ~/playground/test/
```

**看到了什么？**

```
total 8
drwxr-xr-x 2 terraform terraform 4096 Jan  4 11:00 .
drwxr-xr-x 3 terraform terraform 4096 Jan  4 11:00 ..
-rw-r--r-- 1 terraform terraform    0 Jan  4 11:00 hello.txt
```

🎉 **你刚刚创建了一个目录和一个文件！**

- `mkdir -p` = 创建目录（包括父目录）
- `touch` = 创建空文件

---

## Step 2 — 创建文件和目录（20 分钟）

### 2.1 mkdir - 创建目录

```bash
# 基本用法
mkdir myproject

# 创建多级目录（推荐加 -p）
mkdir -p project/src/main

# 一次创建多个
mkdir dir1 dir2 dir3
```

**关于 -p 选项：**

```bash
# 没有 -p：如果父目录不存在会报错
mkdir a/b/c
# mkdir: cannot create directory 'a/b/c': No such file or directory

# 有 -p：自动创建缺失的父目录
mkdir -p a/b/c  # 成功！
```

### 2.2 touch - 创建文件

```bash
# 创建空文件
touch newfile.txt

# 创建多个文件
touch file1.txt file2.txt file3.txt

# 如果文件已存在，更新时间戳
touch existingfile.txt
```

### 2.3 动手练习

```bash
# 创建项目结构
cd ~/playground
mkdir -p myproject/src myproject/docs myproject/tests

# 创建文件
touch myproject/README.md
touch myproject/src/main.py
touch myproject/tests/test_main.py

# 查看结构
ls -R myproject
```

---

## Step 3 — 复制和移动（25 分钟）

### 3.1 cp - 复制文件

```bash
# 基本复制
cp source.txt destination.txt

# 复制到目录
cp file.txt ~/backup/

# 复制目录（必须加 -r）
cp -r myproject myproject-backup

# 安全复制（覆盖前询问）
cp -i important.txt backup/important.txt
```

**常用选项：**

| 选项 | 含义 |
|------|------|
| `-r` | 递归（复制目录必需） |
| `-i` | 交互式（覆盖前询问） |
| `-v` | 详细输出 |
| `-p` | 保留权限和时间戳 |

### 3.2 mv - 移动/重命名

```bash
# 移动文件
mv file.txt ~/Documents/

# 重命名文件
mv oldname.txt newname.txt

# 移动并重命名
mv file.txt ~/Documents/renamed.txt

# 移动目录
mv myproject ~/Documents/

# 安全移动（覆盖前询问）
mv -i file.txt destination/
```

**mv 的双重身份：**

```bash
# 同一目录内 = 重命名
mv a.txt b.txt

# 不同目录 = 移动
mv a.txt ~/Documents/
```

### 3.3 动手练习

```bash
cd ~/playground

# 创建测试文件
echo "Hello World" > original.txt

# 复制
cp original.txt copy.txt
ls -la

# 复制到新目录
mkdir backups
cp original.txt backups/

# 重命名
mv copy.txt renamed.txt
ls -la

# 移动
mv renamed.txt backups/
ls backups/
```

---

## Step 4 — 删除文件：小心操作！（20 分钟）

### 4.1 一个真实的恐怖故事

> ⚠️ **皮克斯差点失去《玩具总动员2》**  
>
> 1998年，有人在皮克斯的服务器上运行了 `rm -rf *`，  
> 删除了《玩具总动员2》90% 的文件。备份也失败了。  
> 幸运的是，一位技术总监在家中有一份副本，拯救了这部电影。  
>
> **教训**：`rm` 没有回收站！删除就是删除！  

### 4.2 rm - 删除文件

```bash
# 基本删除（危险！）
rm file.txt

# 安全删除（推荐！）
rm -i file.txt
# rm: remove regular file 'file.txt'? y

# 删除多个文件
rm -i file1.txt file2.txt

# 强制删除（更危险！谨慎使用）
rm -f file.txt
```

### 4.3 rmdir - 删除空目录

```bash
# 只能删除空目录（更安全）
rmdir emptydir

# 如果目录不为空，会报错
rmdir nonemptydir
# rmdir: failed to remove 'nonemptydir': Directory not empty
```

### 4.4 rm -r - 删除目录

```bash
# 删除目录及其内容
rm -ri myproject
# rm: descend into directory 'myproject'? y
# rm: remove regular file 'myproject/file.txt'? y
# ...

# 危险区域：rm -rf
# 递归删除，不询问
# rm -rf directory  # ⚠️ 极其危险！
```

### 4.5 安全删除习惯

**黄金法则**：删除前先看！

```bash
# ❌ 错误做法
rm -rf *.log

# ✅ 正确做法
ls *.log          # 先看看有什么
rm -i *.log       # 加 -i 逐个确认
```

**更安全的别名**：

```bash
# 添加到 ~/.bashrc
alias rm='rm -i'
```

---

## Step 5 — 文件类型（10 分钟）

### 5.1 ls -l 的第一个字符

```bash
ls -l /
```

```
drwxr-xr-x   2 root root  4096 Jan  1 00:00 bin
-rw-r--r--   1 root root   220 Jan  1 00:00 .profile
lrwxrwxrwx   1 root root     7 Jan  1 00:00 lib -> usr/lib
```

| 字符 | 类型 |
|------|------|
| `-` | 普通文件 |
| `d` | 目录 |
| `l` | 符号链接（快捷方式） |
| `c` | 字符设备 |
| `b` | 块设备 |

### 5.2 file 命令

```bash
file /bin/ls
# /bin/ls: ELF 64-bit LSB executable...

file /etc/passwd
# /etc/passwd: ASCII text

file /dev/null
# /dev/null: character special
```

---

## Step 6 — 综合练习（10 分钟）

### 6.1 项目管理练习

```bash
cd ~/playground

# 1. 创建项目结构
mkdir -p webapp/{frontend,backend,docs}
touch webapp/README.md
touch webapp/frontend/index.html
touch webapp/backend/app.py

# 2. 查看结构
ls -R webapp

# 3. 备份项目
cp -r webapp webapp-backup

# 4. 重命名备份
mv webapp-backup webapp-v1

# 5. 验证
ls -la

# 6. 清理（小心！）
rm -ri webapp-v1
```

### 6.2 安全操作流程

每次删除操作，遵循这个流程：

```bash
# 1. 确认位置
pwd

# 2. 查看目标
ls -la target_file_or_dir

# 3. 执行删除（带 -i）
rm -ri target_file_or_dir

# 4. 验证
ls -la
```

---

## 本课小结

| 操作 | 命令 | 安全选项 |
|------|------|----------|
| 创建目录 | `mkdir -p` | - |
| 创建文件 | `touch` | - |
| 复制 | `cp` | `-i`（询问覆盖） |
| 移动/重命名 | `mv` | `-i`（询问覆盖） |
| 删除文件 | `rm` | `-i`（逐个确认） |
| 删除空目录 | `rmdir` | 本身就安全 |
| 删除目录 | `rm -r` | `-i`（必须加！） |

**核心理念**：Linux 没有回收站！删除前三思，备份重要文件。

---

## 下一步

你现在可以创建和管理文件了。接下来学习如何"阅读"——查看文件内容。

→ [05 · 查看文件内容](../05-viewing-files/)

---

## 面试准备

💼 **よくある質問**

**Q: cp と mv の違いは？**

A: `cp` はコピー（元ファイルが残る）、`mv` は移動（元ファイルが消える）。同じディレクトリ内での `mv` はリネームになります。

**Q: rm -rf の危険性は？**

A: 確認なしで再帰的に全て削除します。Linux にはゴミ箱がないため、削除したファイルは基本的に復元できません。

**Q: なぜ mkdir -p を使うべき？**

A: 親ディレクトリが存在しない場合に自動作成してくれます。スクリプトで特に有用です。

**Q: touch の本来の用途は？**

A: ファイルのタイムスタンプを更新すること。ファイルが存在しない場合に空ファイルを作成するのは副作用です。

---

## トラブルシューティング

🔧 **よくある問題**

**`rm: cannot remove 'file': Permission denied`**

```bash
# ファイルの所有者確認
ls -la file

# 自分のファイルなら権限を変更
chmod u+w file
rm file

# システムファイルなら sudo（要注意！）
sudo rm file
```

**`cp: omitting directory`**

```bash
# ディレクトリをコピーするには -r が必要
cp -r sourcedir destdir
```

**誤削除からの復旧**

```bash
# 悲しいニュース：基本的に復元できません
# 対策：
# 1. 重要ファイルは事前にバックアップ
# 2. alias rm='rm -i' を設定
# 3. git などのバージョン管理を使う
```

---

## 检查清单

在继续下一课之前，确认你能：

- [ ] 使用 `mkdir -p` 创建多级目录
- [ ] 使用 `touch` 创建空文件
- [ ] 使用 `cp -r` 复制目录
- [ ] 使用 `mv` 移动和重命名文件
- [ ] 理解 `rm` 的危险性并使用 `-i` 选项
- [ ] 解释 ls -l 输出中的文件类型字符

---

## 系列导航

← [03 · 文件系统导航](../03-navigation/) | [Home](../) | [05 · 查看文件内容 →](../05-viewing-files/)
