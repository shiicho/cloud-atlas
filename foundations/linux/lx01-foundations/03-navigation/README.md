# 03 · 文件系统导航

> **目标**：像本地人一样在 Linux 文件系统中自由移动  
> **前置**：已完成 [02 · 第一步](../02-first-steps/)  
> **时间**：90 分钟  
> **环境**：任意 Linux 发行版  

---

## 将学到的内容

1. 用 `cd` 命令自信地导航
2. 理解绝对路径和相对路径的区别
3. 掌握导航快捷符号（`~`, `..`, `-`, `/`）
4. 建立文件系统的心智模型

---

## Step 1 — 先跑起来：瞬间移动（2 分钟）

> 🎯 **目标**：体验在文件系统中"瞬移"的感觉。  

```bash
cd /var/log && ls -lh | head
```

**看到了什么？**

```
total 2.5M
-rw-r--r-- 1 root root  12K Jan  4 10:30 alternatives.log
-rw-r--r-- 1 root root 8.9K Jan  4 09:00 apt
-rw-r----- 1 root adm   45K Jan  4 10:35 auth.log
-rw-r--r-- 1 root root  68K Jan  4 10:00 bootstrap.log
-rw-rw---- 1 root utmp    0 Jan  1 00:00 btmp
-rw-r----- 1 root adm  450K Jan  4 10:35 kern.log
```

🎉 **你刚刚"瞬移"到了系统日志目录！**

这就是 `cd` 的力量——你可以去文件系统中的任何地方。

---

## Step 2 — cd 命令详解（15 分钟）

### 2.1 基本语法

```bash
cd [目录路径]
```

- `cd` = **C**hange **D**irectory = 改变目录 = "瞬移"

### 2.2 常用用法

```bash
# 去特定目录
cd /etc

# 回到家目录（三种等价方式）
cd ~
cd $HOME
cd        # 不带参数也回家

# 回到上一个目录（来回切换）
cd -
```

### 2.3 验证位置

每次移动后，养成验证的习惯：

```bash
cd /var/log
pwd
```

```
/var/log
```

---

## Step 3 — 绝对路径 vs 相对路径（20 分钟）

### 3.1 两种路径类型

![Path Types](images/path-types.png)

<details>
<summary>View ASCII source</summary>

```
                    /（根目录）
                       │
          ┌────────────┼────────────┐
          │            │            │
         home         var         etc
          │            │
       terraform      log
          │
       playground
          │
        project1

绝对路径：从根目录开始
/home/terraform/playground/project1

相对路径：从当前位置开始
假设你在 /home/terraform：
./playground/project1  或  playground/project1
```

</details>

| 类型 | 特征 | 例子 |
|------|------|------|
| **绝对路径** | 以 `/` 开头 | `/var/log/syslog` |
| **相对路径** | 不以 `/` 开头 | `../Documents` |

### 3.2 什么时候用哪种？

| 场景 | 推荐 | 原因 |
|------|------|------|
| 脚本中指定路径 | 绝对路径 | 确保不管在哪执行都能找到 |
| 在项目内移动 | 相对路径 | 简短、灵活 |
| 临时导航 | 都可以 | 方便即可 |

### 3.3 实践练习

```bash
# 从家目录开始
cd ~
pwd  # /home/terraform

# 绝对路径：直接到目标
cd /var/log
pwd  # /var/log

# 相对路径：向上再向下
cd ~
cd playground/project1  # 假设存在
pwd  # /home/terraform/playground/project1
```

---

## Step 4 — 导航快捷符号（20 分钟）

### 4.1 符号速查表

| 符号 | 含义 | 例子 |
|------|------|------|
| `/` | 根目录（一切的起点） | `cd /` |
| `~` | 家目录（你的安全港） | `cd ~` |
| `.` | 当前目录 | `./script.sh` |
| `..` | 上级目录（父目录） | `cd ..` |
| `-` | 上一个目录（切换回去） | `cd -` |

### 4.2 上级目录导航

```bash
# 当前在 /home/terraform/playground/project1
pwd
# /home/terraform/playground/project1

# 上一级
cd ..
pwd
# /home/terraform/playground

# 再上一级
cd ..
pwd
# /home/terraform

# 一次上两级
cd ../..
pwd
# /home
```

### 4.3 神奇的 cd -

```bash
# 这是个超级实用的技巧
cd /etc
cd /var/log

# 来回切换
cd -  # 回到 /etc
cd -  # 回到 /var/log
cd -  # 再回到 /etc
```

> 💡 **专业提示**：`cd -` 非常适合在两个目录之间来回工作。  

---

## Step 5 — 文件系统地图（FHS）（20 分钟）

### 5.1 城市比喻

把 Linux 文件系统想象成一座城市：

![FHS City Map](images/fhs-city.png)

<details>
<summary>View ASCII source</summary>

```
                            / (城市中心)
                               │
     ┌──────────┬──────────┬───┴───┬──────────┬──────────┐
     │          │          │       │          │          │
   /bin       /etc      /home    /var       /tmp       /usr
  警察局    市政厅    住宅区    仓库区    公共广场    商业区
  基础命令   配置文件  用户目录   日志/数据  临时文件   程序文件

  🚔 /bin      → 必需的基础命令 (ls, cp, mv)
  🏛️ /etc      → 系统配置文件 (城市规章制度)
  🏠 /home     → 用户个人目录 (你的家)
  📦 /var      → 可变数据 (日志、邮件、数据库)
  🏖️ /tmp      → 临时文件 (重启后消失)
  🏬 /usr      → 用户程序和库 (商店和服务)
```

</details>

### 5.2 重要目录详解

| 目录 | 用途 | 你会在这做什么 |
|------|------|----------------|
| `/` | 根目录 | 一切的起点 |
| `/home` | 用户家目录 | 存放个人文件 |
| `/etc` | 配置文件 | 修改系统设置 |
| `/var/log` | 日志文件 | 故障排查 |
| `/tmp` | 临时文件 | 存放临时数据（重启后丢失） |
| `/opt` | 可选软件 | 安装第三方程序 |
| `/usr/bin` | 用户程序 | 大多数命令在这 |

### 5.3 探索之旅

```bash
# 去根目录
cd /
ls

# 去配置目录
cd /etc
ls | head

# 去日志目录
cd /var/log
ls -lh

# 回家
cd ~
```

---

## Step 6 — 动手练习：文件系统探险（10 分钟）

### 6.1 探索挑战

完成以下任务：

```bash
# 1. 确认起始位置
pwd

# 2. 去配置目录，查看 hostname
cd /etc
cat hostname

# 3. 去日志目录，查看最新日志
cd /var/log
ls -lt | head

# 4. 回到家目录
cd ~
pwd

# 5. 创建探索记录
mkdir -p ~/playground/exploration
cd ~/playground/exploration
echo "我探索过 /etc 和 /var/log" > notes.txt

# 6. 验证
cat notes.txt
```

### 6.2 导航竞速

尝试用最少的命令完成：

1. 从家目录去 `/var/log`
2. 回到家目录
3. 去 `/etc`
4. 回到 `/var/log`（用 `cd -`）

```bash
cd ~                # 起点
cd /var/log         # 第一站
cd ~                # 回家
cd /etc             # 第二站
cd -                # 回到 /var/log！
```

---

## 本课小结

| 你学到的 | 命令/概念 |
|----------|-----------|
| 目录切换 | `cd` |
| 回家 | `cd`, `cd ~`, `cd $HOME` |
| 上级目录 | `cd ..`, `cd ../..` |
| 来回切换 | `cd -` |
| 绝对路径 | 以 `/` 开头 |
| 相对路径 | 不以 `/` 开头 |
| FHS 基础 | `/home`, `/etc`, `/var/log`, `/tmp` |

**核心理念**：把文件系统想象成城市，`cd` 是你的交通工具，路径是地址。

---

## 下一步

你现在可以自由移动了。接下来学习如何"创造"——创建文件和目录。

→ [04 · 文件和目录](../04-files-directories/)

---

## 面试准备

💼 **よくある質問**

**Q: / と ~ の違いは？**

A: `/` はルートディレクトリ（ファイルシステムの最上位）、`~` は現在のユーザーのホームディレクトリ（例：`/home/username`）です。

**Q: /usr は "user" の略ですか？**

A: よくある誤解です。歴史的には「Unix System Resources」の略です。ユーザーファイルは `/home` に保存します。

**Q: /etc の名前の由来は？**

A: 「etcetera」（その他）が由来。初期 UNIX で「分類しにくいもの」を置いた場所でした。今は設定ファイルの標準場所です。

---

## トラブルシューティング

🔧 **よくある問題**

**`cd: no such file or directory`**

```bash
# パスを確認
ls -la /path/to/directory

# スペルミスがないか確認
# Tab 補完を使う
cd /var/lo<Tab>
```

**どこにいるかわからない**

```bash
# 現在位置確認
pwd

# 迷ったらホームに戻る
cd ~
```

**権限がなくて入れない**

```bash
# エラー例
cd /root
# bash: cd: /root: Permission denied

# 解決：sudo が必要な場合
sudo ls /root
```

---

## 检查清单

在继续下一课之前，确认你能：

- [ ] 使用 `cd` 在目录间移动
- [ ] 解释绝对路径和相对路径的区别
- [ ] 使用 `~`, `..`, `-` 快捷导航
- [ ] 说出至少 5 个 FHS 标准目录的用途
- [ ] 用 `cd -` 在两个目录间快速切换

---

## 系列导航

← [02 · 第一步](../02-first-steps/) | [Home](../) | [04 · 文件和目录 →](../04-files-directories/)
