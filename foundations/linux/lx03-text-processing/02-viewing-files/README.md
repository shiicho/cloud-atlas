# 02 - 查看和流式处理文件

> **目标**：掌握文件查看工具，学会实时监控日志  
> **前置**：已完成 [01 - 管道和重定向](../01-pipes-redirection/)  
> **时间**：⚡ 15 分钟（速读）/ 🔬 60 分钟（完整实操）  
> **环境**：任意 Linux 系统（Ubuntu/CentOS/RHEL）  

---

## 将学到的内容

1. 选择正确的文件查看工具（cat、less、head、tail）
2. 使用 `tail -f` 实时监控日志
3. 使用 `less` 高效浏览大文件
4. 提取特定行范围的内容
5. 避免常见的 anti-patterns（无用的 cat）

---

## 先跑起来

> 在学习理论之前，先体验这些工具的实际效果。  

### 准备测试日志

```bash
# 创建练习目录
mkdir -p ~/text-lab && cd ~/text-lab

# 生成模拟日志（2000 行）
for i in $(seq 1 2000); do
  timestamp=$(date -d "-$((2000-i)) seconds" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date '+%Y-%m-%d %H:%M:%S')
  level=$((RANDOM % 10))
  if [ $level -lt 1 ]; then
    echo "$timestamp [ERROR] Connection timeout to database"
  elif [ $level -lt 3 ]; then
    echo "$timestamp [WARN] High memory usage detected"
  else
    echo "$timestamp [INFO] Request processed successfully"
  fi
done > app.log

echo "日志文件已创建：$(wc -l < app.log) 行"
```

### 立即体验

```bash
# 1. 查看前 5 行
head -5 app.log

# 2. 查看最后 5 行
tail -5 app.log

# 3. 在另一个终端实时追加日志，观察 tail -f 效果
tail -f app.log &
sleep 1
echo "$(date '+%Y-%m-%d %H:%M:%S') [ERROR] New error occurred!" >> app.log
sleep 1
kill %1 2>/dev/null

# 4. 用 less 浏览（按 q 退出）
less app.log
```

你刚刚用 4 个工具查看了同一个文件！
每个工具适用于不同场景 -- 接下来我们逐个深入理解。

---

## 发生了什么？

![File Viewing Tools Comparison](images/file-viewing-tools.png)

<details>
<summary>View ASCII source</summary>

<!-- DIAGRAM: file-viewing-tools -->
```
┌─────────────────────────────────────────────────────────────────┐
│                     文件查看工具对比                              │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│   cat                    适用于：小文件、拼接、管道输入           │
│   ┌─────┐                                                       │
│   │ A   │───────────────────────────────────▶ 全部输出          │
│   │ B   │                                                       │
│   │ ... │                                                       │
│   │ Z   │                                                       │
│   └─────┘                                                       │
│                                                                 │
│   head -n 5              适用于：查看文件开头、检查格式           │
│   ┌─────┐                                                       │
│   │ A   │───▶ 输出                                              │
│   │ B   │───▶ 输出                                              │
│   │ C   │───▶ 输出                                              │
│   │ D   │───▶ 输出                                              │
│   │ E   │───▶ 输出                                              │
│   │ ... │    (忽略)                                             │
│   └─────┘                                                       │
│                                                                 │
│   tail -n 5              适用于：查看最新日志、文件结尾           │
│   ┌─────┐                                                       │
│   │ ... │    (忽略)                                             │
│   │ V   │───▶ 输出                                              │
│   │ W   │───▶ 输出                                              │
│   │ X   │───▶ 输出                                              │
│   │ Y   │───▶ 输出                                              │
│   │ Z   │───▶ 输出                                              │
│   └─────┘                                                       │
│                                                                 │
│   tail -f                适用于：实时监控（ログ監視）             │
│   ┌─────┐                                                       │
│   │ ... │                    ┌──────────────┐                   │
│   │ Y   │                    │  等待新内容  │                   │
│   │ Z   │───▶ 输出 ─────────▶│  追加时输出  │───▶ 持续输出      │
│   └─────┘                    └──────────────┘                   │
│                                                                 │
│   less                   适用于：浏览大文件、搜索、导航           │
│   ┌─────┐                    ┌──────────────┐                   │
│   │ A   │                    │   交互模式   │                   │
│   │ B   │───────────────────▶│  ↑↓ 滚动    │                   │
│   │ ... │                    │  / 搜索     │                   │
│   │ Z   │                    │  q 退出     │                   │
│   └─────┘                    └──────────────┘                   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```
<!-- /DIAGRAM -->

</details>

---

## 核心概念

### 1. cat - 连接与输出

`cat`（concatenate）最初设计用于**连接**多个文件：

```bash
# 基本用法：输出整个文件
cat app.log

# 真正用途：连接多个文件
cat header.txt body.txt footer.txt > combined.txt

# 显示行号（调试时有用）
cat -n app.log

# 显示特殊字符（调试格式问题）
cat -A app.log    # 显示 Tab(^I)、行尾($)
```

**适用场景**：
- 小文件（< 100 行）
- 连接多个文件
- 作为管道输入

**不适用场景**：
- 阅读大文件（应该用 `less`）
- `cat file | command`（见 Anti-patterns 章节）

---

### 2. less - 交互式分页器

`less` 是查看大文件的最佳工具：

```bash
less app.log
```

**必背快捷键**：

| 按键 | 功能 | 记忆技巧 |
|------|------|----------|
| `Space` / `f` | 向下翻页 | forward |
| `b` | 向上翻页 | backward |
| `g` | 跳转到文件开头 | go to start |
| `G` | 跳转到文件结尾 | Go to end |
| `/pattern` | 向下搜索 | 类似 vim |
| `?pattern` | 向上搜索 | 反向搜索 |
| `n` | 下一个匹配 | next |
| `N` | 上一个匹配 | Next (反向) |
| `q` | 退出 | quit |

**高级技巧**：

```bash
# 直接跳到第 100 行
less +100 app.log

# 从匹配 ERROR 的位置开始
less +/ERROR app.log

# Follow 模式（类似 tail -f，但可交互）
less +F app.log
# 按 Ctrl+C 暂停 follow，可以搜索/滚动
# 按 F 恢复 follow 模式
```

**`less +F` vs `tail -f`**：

| 特性 | `tail -f` | `less +F` |
|------|-----------|-----------|
| 实时跟踪 | Yes | Yes |
| 暂停后搜索 | No | Yes (Ctrl+C) |
| 向上滚动 | No | Yes |
| 恢复跟踪 | N/A | 按 F |

**推荐**：夜勤监控时使用 `less +F`，可以随时暂停查看历史。

---

### 3. head - 查看开头

```bash
# 默认显示前 10 行
head app.log

# 指定行数
head -n 20 app.log
head -20 app.log      # 简写

# 除了最后 N 行，显示其他所有
head -n -5 app.log    # 跳过最后 5 行
```

**实用场景**：

```bash
# 检查 CSV 文件的表头
head -1 data.csv

# 检查日志格式
head -3 /var/log/syslog

# 结合管道：只看前 10 个结果
ps aux | head -10
```

---

### 4. tail - 查看结尾

```bash
# 默认显示最后 10 行
tail app.log

# 指定行数
tail -n 20 app.log
tail -20 app.log      # 简写

# 从第 N 行开始显示到结尾
tail -n +100 app.log  # 从第 100 行开始

# 实时跟踪（核心功能！）
tail -f app.log

# 跟踪 + 自动重试（日志轮转时使用）
tail -F app.log
```

**`-f` vs `-F`**：

| 选项 | 行为 | 使用场景 |
|------|------|----------|
| `-f` | 跟踪文件描述符 | 文件不会被替换 |
| `-F` | 跟踪文件名 + 重试 | 日志轮转（logrotate） |

**生产环境始终使用 `-F`**：

```bash
# 日志轮转时 -f 会停止，-F 会继续
tail -F /var/log/nginx/access.log
```

---

### 5. 提取特定行范围

**方法一：head + tail 组合**

```bash
# 提取第 10-20 行
head -20 app.log | tail -11

# 计算方法：tail -n (结束行 - 开始行 + 1)
```

**方法二：sed（推荐）**

```bash
# 提取第 10-20 行
sed -n '10,20p' app.log

# 提取从匹配行到另一匹配行
sed -n '/ERROR/,/INFO/p' app.log
```

**方法三：awk**

```bash
# 提取第 10-20 行
awk 'NR>=10 && NR<=20' app.log
```

---

## Anti-patterns：无用的 cat

### Anti-pattern 1: cat | less

```bash
# 错误 - 无用的 cat
cat large-file.log | less

# 正确
less large-file.log
```

**问题**：额外的进程 + 管道开销，没有任何好处。

### Anti-pattern 2: cat | grep

```bash
# 错误 - 无用的 cat
cat app.log | grep ERROR

# 正确
grep ERROR app.log
```

**问题**：`grep` 本身就能读取文件。

### Anti-pattern 3: cat | head

```bash
# 错误
cat app.log | head -10

# 正确
head -10 app.log
```

**记住**：如果命令本身能读取文件，就不需要 `cat`。

**什么时候 cat 是合理的？**

```bash
# 连接多个文件（cat 的本职工作）
cat part1.log part2.log part3.log | grep ERROR

# 需要 cat 的特殊选项（-n, -A）
cat -n script.sh | head -20

# heredoc 输入
cat << 'EOF' > config.txt
line1
line2
EOF
```

---

## 动手练习

### Lab 1：日志监控实战

**场景**：你是夜勤运维，需要监控 Web 服务器日志。

```bash
cd ~/text-lab

# 模拟持续写入的日志
(while true; do
  echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] Request from 192.168.1.$((RANDOM % 255))"
  sleep 1
  if [ $((RANDOM % 5)) -eq 0 ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') [ERROR] Database connection failed"
  fi
done) > live.log &
LOG_PID=$!

# 记录 PID 以便后续停止
echo "日志生成器 PID: $LOG_PID"
```

**任务 1**：使用 `tail -f` 监控日志

```bash
tail -f live.log
# 观察 INFO 和 ERROR 消息
# 按 Ctrl+C 退出
```

**任务 2**：使用 `tail -f` + `grep` 只看错误

```bash
tail -f live.log | grep --line-buffered ERROR
# --line-buffered 确保实时输出
```

**任务 3**：使用 `less +F` 交互式监控

```bash
less +F live.log
# 按 Ctrl+C 暂停，可以向上滚动查看历史
# 按 / 搜索 ERROR
# 按 F 恢复实时跟踪
# 按 q 退出
```

**清理**：

```bash
kill $LOG_PID 2>/dev/null
rm live.log
```

---

### Lab 2：大文件导航

```bash
cd ~/text-lab

# 生成 10000 行日志
for i in $(seq 1 10000); do
  echo "Line $i: $(date '+%H:%M:%S') - Some log content here"
done > big.log

echo "文件大小: $(wc -l < big.log) 行"
```

**任务 1**：快速检查文件结构

```bash
# 查看开头
head -5 big.log

# 查看结尾
tail -5 big.log
```

**任务 2**：使用 less 导航

```bash
less big.log
```

在 less 中练习：
1. 按 `G` 跳到文件末尾
2. 按 `g` 跳回开头
3. 输入 `/Line 5000` 搜索第 5000 行
4. 按 `n` 继续搜索下一个匹配
5. 按 `q` 退出

**任务 3**：提取特定范围

```bash
# 提取第 100-110 行
sed -n '100,110p' big.log

# 验证
awk 'NR>=100 && NR<=110' big.log
```

**清理**：

```bash
rm big.log
```

---

### Lab 3：多文件查看

```bash
cd ~/text-lab

# 创建多个日志文件
echo -e "=== Access Log ===\nGET /index.html 200\nGET /api 500" > access.log
echo -e "=== Error Log ===\nDatabase timeout\nConnection refused" > error.log

# cat 的正确用途：连接文件
cat access.log error.log

# 带行号连接
cat -n access.log error.log
```

---

## 现代替代工具：bat

`bat` 是 `cat` 的现代替代品，提供语法高亮和 Git 集成。

### 安装

```bash
# Ubuntu/Debian
sudo apt install bat
# 注意：在某些发行版中命令是 batcat

# RHEL/CentOS (需要 EPEL)
sudo dnf install bat

# macOS
brew install bat
```

### 基本使用

```bash
# 语法高亮显示
bat script.sh

# 显示行号（默认开启）
bat config.yaml

# 类似 cat 的简洁输出（无行号/边框）
bat --style=plain file.txt
batcat -pp file.txt  # Ubuntu 简写

# 与 less 集成（自动分页）
bat large-file.log
```

### bat vs cat

| 特性 | cat | bat |
|------|-----|-----|
| 语法高亮 | No | Yes |
| 行号 | `-n` 选项 | 默认开启 |
| Git 集成 | No | 显示修改标记 |
| 分页 | No | 自动（大文件） |
| 速度 | 更快 | 稍慢 |

**建议**：
- 脚本中使用 `cat`（更通用、更快）
- 交互式查看代码时使用 `bat`

---

## 职场小贴士

### 日本 IT 运维场景

**ログ監視（log kanshi）** - 日志监控：

```bash
# 标准监控模式
tail -F /var/log/messages | grep -i error

# 监控多个文件
tail -F /var/log/nginx/*.log
```

**リアルタイム監視** - 实时监控：

在日本的运维现场（運用監視センター），夜勤人员经常需要：

1. **一次対応（初动）**：发现异常时快速定位
   ```bash
   # 查看最近 100 行
   tail -100 /var/log/app/error.log

   # 实时跟踪
   tail -F /var/log/app/error.log | grep --line-buffered -E 'ERROR|FATAL'
   ```

2. **二次対応（详细调查）**：使用 less 深入分析
   ```bash
   less +G /var/log/app/error.log   # 从文件末尾开始
   less +/Exception app.log         # 从第一个异常开始
   ```

3. **引継ぎ（交接班）**：提取时间段日志
   ```bash
   # 提取特定时间段（假设时间戳在行首）
   sed -n '/2026-01-04 02:00/,/2026-01-04 03:00/p' app.log > handoff.log
   ```

### 常用日语术语

| 日语 | 读音 | 含义 |
|------|------|------|
| ログ監視 | log kanshi | 日志监控 |
| リアルタイム監視 | realtime kanshi | 实时监控 |
| 夜勤 | yakin | 夜班 |
| 障害対応 | shougai taiou | 故障处理 |
| 運用監視 | unyou kanshi | 运维监控 |

---

## 检查清单

完成本课后，你应该能够：

- [ ] 使用 `head` 和 `tail` 查看文件的开头和结尾
- [ ] 使用 `tail -f` 实时监控日志文件
- [ ] 理解 `tail -f` 和 `tail -F` 的区别（日志轮转）
- [ ] 使用 `less` 浏览大文件并进行搜索
- [ ] 使用 `less +F` 进行交互式日志监控
- [ ] 使用 `sed -n 'start,end p'` 提取特定行范围
- [ ] 识别并避免无用的 cat（cat | less, cat | grep）
- [ ] 了解 `bat` 作为现代替代工具

---

## 延伸阅读

**官方文档**：
- [GNU Coreutils: cat](https://www.gnu.org/software/coreutils/manual/html_node/cat-invocation.html)
- [GNU Coreutils: head](https://www.gnu.org/software/coreutils/manual/html_node/head-invocation.html)
- [GNU Coreutils: tail](https://www.gnu.org/software/coreutils/manual/html_node/tail-invocation.html)
- [less manual](https://man7.org/linux/man-pages/man1/less.1.html)

**现代工具**：
- [bat - A cat clone with wings](https://github.com/sharkdp/bat)

**相关课程**：
- [01 - 管道和重定向](../01-pipes-redirection/) - 输入输出基础
- [03 - grep 基础](../03-grep-fundamentals/) - 模式搜索

---

## 系列导航

[01 - 管道和重定向](../01-pipes-redirection/) | [Home](../) | [03 - grep 基础](../03-grep-fundamentals/) ->
