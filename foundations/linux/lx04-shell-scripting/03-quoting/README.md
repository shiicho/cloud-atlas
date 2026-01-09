# 03 · 引用规则（重点课！）

> **目标**：掌握 Shell 引用规则，避免 90% 的脚本 Bug  
> **前置**：已完成 [02 · 变量与环境](../02-variables/)  
> **时间**：75-90 分钟  
> **环境**：任意 Linux 发行版（Bash 4.0+）  

---

> **WARNING** - 这是 Shell 脚本中最容易出错的主题！  
>
> 引用规则决定了变量是否展开、空格如何处理、通配符是否生效。  
> 掌握引用规则能避免 90% 的脚本 Bug。  
>
> **黄金法则：除非你明确知道为什么不需要，否则始终使用双引号包裹变量。**  
>
> `"$variable"` 而不是 `$variable`  

---

## 将学到的内容

1. 理解 Word Splitting（词分割）机制
2. 理解 Glob Expansion（通配符展开）机制
3. 掌握单引号 vs 双引号 vs 无引号的区别
4. 养成"总是引用变量"的习惯
5. 处理文件名中的空格、特殊字符
6. 理解 SSH 远程命令的引用嵌套

---

## Step 1 — 先跑起来：感受引用的威力（5 分钟）

> 先看一个 Bug，再学怎么避免。  

```bash
# 创建练习目录
mkdir -p ~/quote-lab && cd ~/quote-lab

# 创建一些测试文件
touch "important file.txt" "my photo.jpg" "report 2026.pdf"
ls -la
```

现在运行下面两个版本的脚本：

```bash
# 版本 A：不加引号（危险！）
for file in $(ls); do
    echo "处理: $file"
done
```

```bash
# 版本 B：正确的写法
for file in *; do
    echo "处理: $file"
done
```

**观察输出的区别！**

版本 A 输出（错误）：
```
处理: important
处理: file.txt
处理: my
处理: photo.jpg
处理: report
处理: 2026.pdf
```

版本 B 输出（正确）：
```
处理: important file.txt
处理: my photo.jpg
处理: report 2026.pdf
```

**版本 A 把文件名按空格拆分了！** 这就是"词分割"（Word Splitting）带来的问题。

---

## Step 2 — 发生了什么？Shell 的展开机制（10 分钟）

当 Shell 执行命令时，会进行多个阶段的处理：

<!-- DIAGRAM: shell-expansion-order -->
```
┌─────────────────────────────────────────────────────────────────────────────┐
│  Shell 展开顺序（从上到下）                                                   │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   1. 大括号展开       {a,b,c} → a b c                                        │
│         │                                                                    │
│         ▼                                                                    │
│   2. 波浪号展开       ~ → /home/user                                         │
│         │                                                                    │
│         ▼                                                                    │
│   3. 参数/变量展开    $VAR → value                                           │
│         │                                                                    │
│         ▼                                                                    │
│   4. 命令替换         $(cmd) → output                                        │
│         │                                                                    │
│         ▼                                                                    │
│   5. 算术展开         $((1+2)) → 3                                           │
│         │                                                                    │
│         ▼                                                                    │
│  ═══════════════════════════════════════════════════════════════════════    │
│   6. 词分割 ★         "a b c" → [a] [b] [c]  ← 空格拆分成多个词！             │
│         │                                                                    │
│         ▼                                                                    │
│   7. 通配符展开 ★     *.txt → file1.txt file2.txt  ← 模式匹配文件！          │
│  ═══════════════════════════════════════════════════════════════════════    │
│                                                                              │
│   ★ 标记的两步是引用规则控制的重点！                                          │
│   双引号可以阻止词分割和通配符展开                                            │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```
<!-- /DIAGRAM -->

### 核心概念

| 术语 | 英文 | 说明 |
|------|------|------|
| 词分割 | Word Splitting | 按 IFS（默认空格/Tab/换行）拆分字符串 |
| 通配符展开 | Glob Expansion | `*`、`?`、`[...]` 匹配文件名 |
| 引用 | Quoting | 使用引号保护字符串不被拆分/展开 |

**问题的根源：** 未引用的变量会经历词分割和通配符展开！

---

## Step 3 — 三种引用方式详解（20 分钟）

### 3.1 无引号：全部展开（危险！）

```bash
cd ~/quote-lab

# 设置变量
msg="hello world"
pattern="*.txt"

# 无引号：词分割 + 通配符展开
echo $msg       # echo 收到两个参数: "hello" "world"
echo $pattern   # echo 收到展开后的文件列表
```

```bash
# 使用 set -x 查看实际展开结果
set -x
echo $msg
echo $pattern
set +x
```

输出：
```
+ echo hello world
hello world
+ echo 'important file.txt'
important file.txt
```

### 3.2 双引号：变量展开，但阻止词分割和通配符

```bash
# 双引号：变量展开，但保持为一个整体
echo "$msg"      # echo 收到一个参数: "hello world"
echo "$pattern"  # 原样输出 "*.txt"
```

```bash
# 验证
set -x
echo "$msg"
echo "$pattern"
set +x
```

输出：
```
+ echo 'hello world'
hello world
+ echo '*.txt'
*.txt
```

### 3.3 单引号：完全原样输出

```bash
# 单引号：所有字符原样输出，没有任何展开
echo '$msg'      # 输出字面字符串 $msg
echo '$pattern'  # 输出字面字符串 $pattern
echo '$((1+2))'  # 输出 $((1+2))，不会计算
```

### 3.4 对比总结

| 引用方式 | 变量展开 | 命令替换 | 词分割 | 通配符展开 | 使用场景 |
|----------|----------|----------|--------|------------|----------|
| 无引号 | Yes | Yes | Yes | Yes | 极少使用（故意拆分时） |
| 双引号 `"..."` | Yes | Yes | **No** | **No** | **最常用**，保护变量 |
| 单引号 `'...'` | **No** | **No** | **No** | **No** | 完全原样输出 |

### 3.5 交互式演示脚本

```bash
cat > ~/quote-lab/quoting-demo.sh << 'EOF'
#!/bin/bash
# quoting-demo.sh - 引用方式演示

msg="hello world"
files="*.txt"
var='$USER'

echo "=== 无引号 ==="
echo $msg
echo $files

echo ""
echo "=== 双引号 ==="
echo "$msg"
echo "$files"

echo ""
echo "=== 单引号 ==="
echo '$msg'
echo '$files'
echo '$var 的值是:' "$var"
EOF

chmod +x ~/quote-lab/quoting-demo.sh
cd ~/quote-lab && ./quoting-demo.sh
```

---

## Step 4 — 特殊引用：$'...' 和转义字符（10 分钟）

### 4.1 $'...' ANSI-C 引用

当你需要在字符串中包含特殊字符（换行、Tab 等）时：

```bash
# $'...' 语法：支持转义字符
echo $'第一行\n第二行\n第三行'
echo $'列1\t列2\t列3'
```

输出：
```
第一行
第二行
第三行
列1    列2    列3
```

常用转义序列：

| 转义序列 | 含义 | 示例 |
|----------|------|------|
| `\n` | 换行 | `$'line1\nline2'` |
| `\t` | Tab | `$'col1\tcol2'` |
| `\\` | 反斜杠 | `$'path\\to\\file'` |
| `\'` | 单引号 | `$'it\'s'` |
| `\"` | 双引号 | `$'say \"hi\"'` |

### 4.2 转义字符 `\`

在双引号内，反斜杠可以转义特殊字符：

```bash
# 转义双引号
echo "他说: \"你好\""

# 转义美元符号
price=100
echo "价格是 \$${price}"

# 转义反斜杠
echo "路径是 C:\\Users\\name"
```

### 4.3 在单引号中包含单引号

这是个常见难题！

```bash
# 方法 1：用双引号
echo "It's a test"

# 方法 2：拼接字符串
echo 'It'\''s a test'
#    ^^^  ^^  ^^^^^^^^
#    单引 转义 单引号字符串继续
#    号结 的单
#    束   引号

# 方法 3：使用 $'...'
echo $'It\'s a test'
```

---

## Step 5 — 失败实验室：引用错误的灾难（15 分钟）

> **学习目标**：亲眼见证不加引号会导致什么问题。  

### 实验 1：文件名空格灾难

```bash
cd ~/quote-lab

# 创建带空格的文件
touch "my important data.txt"
echo "珍贵数据" > "my important data.txt"

# 不加引号处理文件
file="my important data.txt"
cat $file
```

输出：
```
cat: my: No such file or directory
cat: important: No such file or directory
cat: data.txt: No such file or directory
```

**修复：**

```bash
cat "$file"  # 正确！
```

### 实验 2：rm 的恐怖故事

```bash
# 警告：这是演示，我们用 echo 代替 rm

# 假设变量意外为空
file=""

# 不加引号的危险
echo rm -rf /home/user/$file/
# 输出: rm -rf /home/user//
# 如果 file 为空，会删除 /home/user/ 下所有内容！

# 加引号的保护
echo rm -rf "/home/user/$file/"
# 输出: rm -rf /home/user//
# 效果一样危险，但至少 ShellCheck 会警告
```

**最佳实践：使用 set -u 防止空变量**

```bash
set -u  # 未定义变量报错
echo $undefined_var
# bash: undefined_var: unbound variable
```

### 实验 3：通配符意外展开

```bash
cd ~/quote-lab

# 设置一个包含 * 的消息
msg="Warning: *.txt files found!"

# 不加引号
echo $msg
# 输出: Warning: important file.txt my photo.jpg ... files found!
# * 被展开成了文件列表！

# 加引号
echo "$msg"
# 输出: Warning: *.txt files found!
```

### 实验 4：[ ] 中的未引用变量

```bash
# 创建测试变量
name=""

# 不加引号会导致语法错误
if [ $name = "John" ]; then
    echo "Hello John"
fi
# bash: [: =: unary operator expected

# 加引号正确
if [ "$name" = "John" ]; then
    echo "Hello John"
fi
# 正常执行，条件为 false
```

### 实验 5：SSH 远程命令的引用陷阱

```bash
# 本地变量
LOCAL_HOST=$(hostname)

# 错误：变量在本地展开
ssh localhost "echo 主机名是 $LOCAL_HOST"
# 输出: 主机名是 your-local-hostname（本地的主机名）

# 正确：用单引号防止本地展开
ssh localhost 'echo 主机名是 $HOSTNAME'
# 输出: 主机名是 remote-hostname（远程的主机名）

# 混合使用：部分本地展开，部分远程展开
local_user="admin"
ssh localhost "echo 用户 $local_user 在 "'$HOSTNAME'" 上登录"
```

---

## Step 6 — 调试技巧：使用 set -x 查看展开结果（5 分钟）

当你不确定变量如何展开时，使用 `set -x`：

```bash
#!/bin/bash
# debug-expansion.sh

msg="hello world"
files="*.txt"

echo "=== 开启调试模式 ==="
set -x

echo $msg
echo "$msg"
echo $files
echo "$files"

set +x
echo "=== 调试模式关闭 ==="
```

运行结果：
```
=== 开启调试模式 ===
+ echo hello world
hello world
+ echo 'hello world'
hello world
+ echo important file.txt
important file.txt
+ echo '*.txt'
*.txt
+ set +x
=== 调试模式关闭 ===
```

**看 `+` 后面的内容**，那是 Shell 实际执行的命令！

---

## Step 7 — Mini Project：安全的文件处理器（15 分钟）

> **项目目标**：写一个脚本正确处理包含空格和特殊字符的文件名。  

### 需求

创建脚本 `safe-file-processor.sh`：
1. 接受一个目录作为参数
2. 遍历目录中的所有文件
3. 显示每个文件的名称和大小
4. 能正确处理包含空格、特殊字符的文件名
5. 通过 ShellCheck 零警告

### 参考实现

```bash
cat > ~/quote-lab/safe-file-processor.sh << 'EOF'
#!/bin/bash
# =============================================================================
# 脚本名称: safe-file-processor.sh
# 功能说明: 安全地处理包含特殊字符的文件名
# 关键点: 正确使用引号，避免词分割和通配符展开
# =============================================================================

# 检查参数
if [ $# -eq 0 ]; then
    echo "用法: $0 <目录>"
    exit 1
fi

target_dir="$1"

# 检查目录是否存在
if [ ! -d "$target_dir" ]; then
    echo "错误: 目录 '$target_dir' 不存在"
    exit 1
fi

echo "========================================"
echo "  文件处理报告"
echo "  目录: $target_dir"
echo "========================================"
echo ""

# 计数器
count=0

# 正确的文件遍历方式：使用 for + glob
# 注意：不要用 for file in $(ls)
for file in "$target_dir"/*; do
    # 检查是否真的有文件（处理空目录情况）
    if [ ! -e "$file" ]; then
        echo "目录为空或无匹配文件"
        break
    fi

    # 只处理普通文件
    if [ -f "$file" ]; then
        # 获取文件名（不含路径）
        filename=$(basename "$file")

        # 获取文件大小
        # 注意：stat 命令在不同系统语法不同
        if stat --version &>/dev/null; then
            # GNU stat (Linux)
            size=$(stat --printf="%s" "$file")
        else
            # BSD stat (macOS)
            size=$(stat -f%z "$file")
        fi

        # 格式化输出
        printf "%-40s %10s bytes\n" "$filename" "$size"
        ((count++))
    fi
done

echo ""
echo "========================================"
echo "共处理 $count 个文件"
echo "========================================"
EOF

chmod +x ~/quote-lab/safe-file-processor.sh
```

### 测试脚本

```bash
cd ~/quote-lab

# 创建测试文件（包含各种特殊情况）
mkdir -p test-files
cd test-files
touch "normal.txt"
touch "file with spaces.txt"
touch "file-with-dashes.txt"
touch "file_with_underscores.txt"
touch "report [2026].pdf"
touch "data*.bak"              # 文件名包含 * 号
echo "测试内容" > "中文文件名.txt"

# 运行脚本
cd ~/quote-lab
./safe-file-processor.sh test-files
```

### ShellCheck 检查

```bash
shellcheck ~/quote-lab/safe-file-processor.sh
```

应该没有错误！

---

## Step 8 — 常见反模式与修复（10 分钟）

### 反模式 1：未引用的变量删除文件

```bash
# ❌ 错误：文件名有空格会出问题
file="my document.txt"
rm $file
# 会尝试删除 "my" 和 "document.txt" 两个文件！

# ✅ 正确
rm "$file"
```

### 反模式 2：通配符变量意外展开

```bash
# ❌ 错误：* 会被展开
msg="*"
echo $msg
# 输出当前目录所有文件！

# ✅ 正确
echo "$msg"
```

### 反模式 3：for 循环解析 ls 输出

```bash
# ❌ 错误：空格文件名被拆分
for f in $(ls); do
    echo "$f"
done

# ✅ 正确：使用 glob
for f in *; do
    echo "$f"
done

# ✅ 正确：处理带路径的情况
for f in /path/to/dir/*; do
    [ -e "$f" ] || continue  # 处理空目录
    echo "$f"
done
```

### 反模式 4：while read 循环问题

```bash
# ❌ 错误：管道创建子 shell，变量改变不会保留
count=0
cat file.txt | while read line; do
    ((count++))
done
echo "$count"  # 输出 0！

# ✅ 正确：使用重定向
count=0
while read -r line; do
    ((count++))
done < file.txt
echo "$count"  # 正确的计数
```

### 反模式 5：SSH 远程命令变量混淆

```bash
# ❌ 错误：$HOSTNAME 在本地展开
ssh server "echo 服务器是 $HOSTNAME"

# ✅ 正确：用单引号让变量在远程展开
ssh server 'echo 服务器是 $HOSTNAME'

# ✅ 正确：混合使用（部分本地，部分远程）
local_var="value"
ssh server "echo 本地值: $local_var, 远程主机: "'$HOSTNAME'
```

### 反模式 6：数组展开不加引号

```bash
# ❌ 错误：元素边界丢失
files=("file one.txt" "file two.txt")
for f in ${files[@]}; do
    echo "$f"
done
# 输出 4 行：file, one.txt, file, two.txt

# ✅ 正确
for f in "${files[@]}"; do
    echo "$f"
done
# 输出 2 行：file one.txt, file two.txt
```

---

## 引用规则速查表

<!-- DIAGRAM: quoting-cheatsheet -->
```
┌─────────────────────────────────────────────────────────────────────────────┐
│  引用规则速查表                                                              │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  场景                           推荐写法                   避免写法          │
│  ─────────────────────────────────────────────────────────────────────────  │
│  普通变量                       "$var"                    $var              │
│  命令替换                       "$(command)"              $(command)        │
│  数组全部元素                   "${array[@]}"             ${array[@]}       │
│  路径拼接                       "${dir}/${file}"          $dir/$file        │
│  条件判断                       [ "$var" = "value" ]      [ $var = "value ] │
│  for 循环遍历文件               for f in *                for f in $(ls)    │
│  读取文件行                     while read -r line        for line in $(cat)│
│  原样输出（无展开）             'literal $string'         -                 │
│  包含特殊字符                   $'line1\nline2'           -                 │
│                                                                              │
│  ─────────────────────────────────────────────────────────────────────────  │
│                                                                              │
│  黄金法则：双引号是你的朋友！                                                │
│  "$variable" - 始终安全                                                      │
│  $variable   - 可能有问题                                                    │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```
<!-- /DIAGRAM -->

---

## 职场小贴士（Japan IT Context）

### 运维脚本中的引用问题

在日本 IT 企业的运维现场（運用現場），引用问题是脚本 Bug 的主要来源：

| 日语术语 | 含义 | 与引用的关系 |
|----------|------|--------------|
| 障害 (shougai) | 故障 | 文件名空格导致的脚本失败 |
| 誤操作 (gosousa) | 误操作 | 变量为空时 rm 删错文件 |
| 文字化け (mojibake) | 乱码 | 特殊字符未正确引用 |

### 典型的日本企业脚本问题

```bash
# 实际案例：日志备份脚本
# 日志文件名包含日期和时间，格式如：access_2026-01-10 15:30:00.log

# ❌ 问题代码
for log in /var/log/app/access_*.log; do
    cp $log /backup/  # 空格导致复制失败
done

# ✅ 修复
for log in /var/log/app/access_*.log; do
    cp "$log" /backup/
done
```

### ShellCheck 是标配

越来越多的日本 IT 企业要求运维脚本必须通过 ShellCheck 检查：

```bash
# CI/CD パイプライン（Pipeline）中的检查
shellcheck --severity=warning *.sh
```

---

## 本课小结

| 引用类型 | 语法 | 变量展开 | 词分割 | 通配符 | 使用场景 |
|----------|------|----------|--------|--------|----------|
| 无引号 | `$var` | Yes | Yes | Yes | 故意拆分 |
| 双引号 | `"$var"` | Yes | **No** | **No** | **默认选择** |
| 单引号 | `'$var'` | **No** | **No** | **No** | 原样输出 |
| ANSI-C | `$'...'` | **No** | **No** | **No** | 特殊字符 |

**黄金法则三连：**

1. **变量用双引号**: `"$variable"`
2. **命令替换用双引号**: `"$(command)"`
3. **数组用双引号**: `"${array[@]}"`

---

## 常见错误总结

### 错误 1：变量不加引号

```bash
# ❌ 错误
file="my file.txt"
cat $file

# ✅ 正确
cat "$file"
```

### 错误 2：用 for 遍历 ls 输出

```bash
# ❌ 错误
for f in $(ls); do echo "$f"; done

# ✅ 正确
for f in *; do echo "$f"; done
```

### 错误 3：[ ] 中变量不加引号

```bash
# ❌ 错误（空变量会语法错误）
[ $name = "John" ]

# ✅ 正确
[ "$name" = "John" ]

# ✅ 更好（[[ ]] 更安全）
[[ $name = "John" ]]
```

### 错误 4：SSH 命令引用混乱

```bash
# ❌ 变量在本地展开
ssh host "echo $HOSTNAME"

# ✅ 变量在远程展开
ssh host 'echo $HOSTNAME'
```

---

## 检查清单

完成本课后，你应该能够：

- [ ] 解释词分割（Word Splitting）和通配符展开（Glob Expansion）的机制
- [ ] 区分单引号、双引号、无引号的行为差异
- [ ] 正确使用双引号保护变量 `"$var"`
- [ ] 使用 `$'...'` 语法处理特殊字符
- [ ] 正确遍历文件（`for f in *` 而不是 `for f in $(ls)`）
- [ ] 使用 `set -x` 调试变量展开问题
- [ ] 写出能正确处理特殊文件名的脚本
- [ ] 通过 ShellCheck 检查脚本引用问题

---

## 面试准备

### **シェルスクリプトでダブルクォートが必要な理由は？**
（Shell 脚本中为什么需要双引号？）

ダブルクォートは Word Splitting と Glob Expansion を防ぎます。変数に空白やワイルドカード文字が含まれる場合、クォートなしでは予期しない動作になります。例えば `file="my doc.txt"` で `cat $file` とすると、`cat` は `my` と `doc.txt` という2つの引数を受け取ります。`cat "$file"` とすれば正しく動作します。

### **シングルクォートとダブルクォートの違いは？**
（单引号和双引号的区别？）

シングルクォートは全ての文字をリテラルとして扱い、変数展開もコマンド置換も行いません。`'$USER'` は文字通り `$USER` と出力されます。ダブルクォートは変数展開とコマンド置換を許可しますが、Word Splitting と Glob Expansion を防ぎます。`"$USER"` は実際のユーザー名に展開されます。

### **ファイル名にスペースが含まれる場合の正しい処理方法は？**
（文件名包含空格时的正确处理方法？）

3つのポイントがあります：
1. 変数は常にダブルクォートで囲む: `"$file"`
2. `for f in $(ls)` ではなく `for f in *` を使用
3. `while read` でファイルを読む場合は `-r` オプションを使用し、`IFS=` でリーディングスペースを保持

---

## トラブルシューティング

### **変数が意図せず分割される**

```bash
# 問題
path="my documents/file.txt"
ls $path  # エラー: my: No such file or directory

# 解決
ls "$path"
```

### **ワイルドカードが展開されてしまう**

```bash
# 問題
pattern="*.log"
echo $pattern  # 実際のファイル名が表示される

# 解決
echo "$pattern"  # *.log と表示される
```

### **SSH で変数が展開されるタイミングが違う**

```bash
# 問題：ローカルで展開される
ssh server "echo $HOME"  # ローカルの HOME

# 解決：シングルクォートでリモートで展開
ssh server 'echo $HOME'  # リモートの HOME
```

---

## 延伸阅读

- [Bash Pitfalls - Word Splitting](https://mywiki.wooledge.org/WordSplitting)
- [BashFAQ/050 - I'm trying to put a command in a variable](https://mywiki.wooledge.org/BashFAQ/050)
- [ShellCheck Wiki - SC2086](https://github.com/koalaman/shellcheck/wiki/SC2086)
- 相关课程：[02 · 变量与环境](../02-variables/) - 变量基础
- 下一课：[04 · 条件判断](../04-conditionals/) - if 语句和 test 命令

---

## 系列导航

<- [02 · 变量与环境](../02-variables/) | [Home](../) | [04 · 条件判断 ->](../04-conditionals/)
