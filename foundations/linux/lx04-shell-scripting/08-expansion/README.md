# 08 - 参数展开（Parameter Expansion）

> **目标**：掌握 Bash 参数展开的强大功能，无需外部命令处理字符串  
> **前置**：[07 - 数组](../07-arrays/)  
> **时间**：⚡ 25 分钟（速读）/ 🔬 90 分钟（完整实操）  
> **环境**：Bash 4.x+（RHEL 7/8/9, Ubuntu 18.04+ 均可）  

---

## 将学到的内容

1. 掌握默认值语法（`:-`、`:=`、`:+`、`:?`）
2. 掌握字符串截取（`#`、`##`、`%`、`%%`）
3. 使用大小写转换（`^`、`,`）
4. 理解间接引用（`!`）
5. 结合实际场景应用

---

## 先跑起来！（5 分钟）

> 在理解原理之前，先体验参数展开的魔力。  
> 不用 `sed`、`awk`、`cut`，纯 Bash 就能处理字符串！  

```bash
# 创建练习目录
mkdir -p ~/expansion-lab && cd ~/expansion-lab

# 创建第一个参数展开脚本
cat > first-expansion.sh << 'EOF'
#!/bin/bash
# 参数展开的威力演示

# 文件路径处理（不用 dirname/basename！）
filepath="/var/log/nginx/access.log"
echo "完整路径: $filepath"
echo "目录部分: ${filepath%/*}"          # /var/log/nginx
echo "文件名:   ${filepath##*/}"         # access.log
echo "去扩展名: ${filepath%.*}"          # /var/log/nginx/access
echo "扩展名:   ${filepath##*.}"         # log

echo ""

# 默认值（安全处理未定义变量）
echo "USER 变量: ${USER:-unknown}"       # 使用环境变量
echo "未定义的: ${UNDEFINED:-默认值}"     # 使用默认值

echo ""

# 大小写转换
name="hello world"
echo "首字母大写: ${name^}"              # Hello world
echo "全部大写:   ${name^^}"             # HELLO WORLD
EOF

bash first-expansion.sh
```

**你应该看到类似的输出：**

```
完整路径: /var/log/nginx/access.log
目录部分: /var/log/nginx
文件名:   access.log
去扩展名: /var/log/nginx/access
扩展名:   log

USER 变量: yourname
未定义的: 默认值

首字母大写: Hello world
全部大写:   HELLO WORLD
```

**惊喜吗？** 这些操作通常需要 `dirname`、`basename`、`tr` 等外部命令，但参数展开让你在 Bash 内部就能完成——**更快、更简洁、无需 fork 子进程**。

现在让我们深入理解每种参数展开语法。

---

## Step 1 — 默认值与错误处理（20 分钟）

### 1.1 四种默认值语法

参数展开提供四种处理未定义或空变量的方式：

![Default Value Syntax](images/default-value-syntax.png)

<details>
<summary>View ASCII source</summary>

<!-- DIAGRAM: default-value-syntax -->
```
┌─────────────────────────────────────────────────────────────────────────┐
│  参数展开：默认值语法                                                     │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  ${var:-default}    使用默认值（var 未设置或为空时）                      │
│  ┌─────────────────────────────────────────────────────────────┐        │
│  │  var 有值  → 返回 $var                                       │        │
│  │  var 为空  → 返回 default                                    │        │
│  │  var 未设置 → 返回 default                                   │        │
│  │  注意：var 本身不被修改                                       │        │
│  └─────────────────────────────────────────────────────────────┘        │
│                                                                          │
│  ${var:=default}    设置默认值（var 未设置或为空时赋值）                  │
│  ┌─────────────────────────────────────────────────────────────┐        │
│  │  var 有值  → 返回 $var                                       │        │
│  │  var 为空  → var=default，返回 default                       │        │
│  │  var 未设置 → var=default，返回 default                      │        │
│  │  注意：var 被修改了！                                         │        │
│  └─────────────────────────────────────────────────────────────┘        │
│                                                                          │
│  ${var:+alternate}  替代值（var 有值时使用替代）                          │
│  ┌─────────────────────────────────────────────────────────────┐        │
│  │  var 有值  → 返回 alternate                                  │        │
│  │  var 为空  → 返回空                                          │        │
│  │  var 未设置 → 返回空                                         │        │
│  │  用途：条件性添加参数                                         │        │
│  └─────────────────────────────────────────────────────────────┘        │
│                                                                          │
│  ${var:?error}      错误提示（var 未设置或为空时报错退出）                │
│  ┌─────────────────────────────────────────────────────────────┐        │
│  │  var 有值  → 返回 $var                                       │        │
│  │  var 为空  → 打印 error 到 stderr，脚本退出（exit 1）        │        │
│  │  var 未设置 → 打印 error 到 stderr，脚本退出（exit 1）       │        │
│  │  用途：强制要求变量必须有值                                   │        │
│  └─────────────────────────────────────────────────────────────┘        │
│                                                                          │
│  冒号的作用：                                                             │
│  - 有冒号 (:-)：同时检查「未设置」和「空值」                              │
│  - 无冒号 (-)：只检查「未设置」，空值被视为有效值                          │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```
<!-- /DIAGRAM -->

</details>

### 1.2 默认值使用示例

```bash
cd ~/expansion-lab

cat > default-values.sh << 'EOF'
#!/bin/bash
# 默认值语法演示

echo "=== ${var:-default} 使用默认值 ==="
unset name
echo "未设置: ${name:-Guest}"         # Guest
name=""
echo "空值:   ${name:-Guest}"         # Guest
name="Alice"
echo "有值:   ${name:-Guest}"         # Alice

echo ""
echo "=== ${var:=default} 设置默认值 ==="
unset config_dir
echo "设置前: config_dir = '${config_dir:-未定义}'"
: "${config_dir:=/etc/myapp}"         # : 是空命令，仅触发展开
echo "设置后: config_dir = '$config_dir'"

echo ""
echo "=== ${var:+alternate} 替代值 ==="
unset debug
echo "debug 未设置: '${debug:+--verbose}'"    # 空
debug="yes"
echo "debug=yes:    '${debug:+--verbose}'"    # --verbose

# 实际应用：条件性添加命令参数
verbose=""
# verbose="true"  # 取消注释启用 verbose
echo "rsync ${verbose:+-v} source/ dest/"

echo ""
echo "=== ${var:?error} 错误提示 ==="
# 必需的环境变量检查
export DB_HOST="localhost"
export DB_PORT="5432"
# unset DB_USER  # 取消注释会导致脚本退出

echo "DB_HOST: ${DB_HOST:?需要设置 DB_HOST}"
echo "DB_PORT: ${DB_PORT:?需要设置 DB_PORT}"
# echo "DB_USER: ${DB_USER:?需要设置 DB_USER}"  # 会报错退出
EOF

bash default-values.sh
```

### 1.3 有冒号 vs 无冒号

```bash
cd ~/expansion-lab

cat > colon-difference.sh << 'EOF'
#!/bin/bash
# 冒号的区别演示

echo "=== 有冒号 vs 无冒号 ==="

# 情况 1：变量未设置
unset var
echo "未设置:"
echo "  \${var:-default} = '${var:-default}'"   # default
echo "  \${var-default}  = '${var-default}'"    # default

# 情况 2：变量为空
var=""
echo "空值:"
echo "  \${var:-default} = '${var:-default}'"   # default（空被视为需要默认值）
echo "  \${var-default}  = '${var-default}'"    # 空（空被视为有效值！）

# 情况 3：变量有值
var="value"
echo "有值:"
echo "  \${var:-default} = '${var:-default}'"   # value
echo "  \${var-default}  = '${var-default}'"    # value
EOF

bash colon-difference.sh
```

**输出：**

```
=== 有冒号 vs 无冒号 ===
未设置:
  ${var:-default} = 'default'
  ${var-default}  = 'default'
空值:
  ${var:-default} = 'default'
  ${var-default}  = ''
有值:
  ${var:-default} = 'value'
  ${var-default}  = 'value'
```

> **记住**：大多数情况下使用带冒号的版本（`:-`），因为空值通常也应该使用默认值。  

### 1.4 实际应用：配置文件加载

```bash
cd ~/expansion-lab

cat > config-loader.sh << 'EOF'
#!/bin/bash
# 使用默认值的配置加载模式

# 设置默认配置
: "${APP_NAME:=myapp}"
: "${APP_ENV:=development}"
: "${APP_PORT:=8080}"
: "${LOG_LEVEL:=info}"
: "${CONFIG_FILE:=/etc/${APP_NAME}/config.conf}"

echo "应用配置："
echo "  APP_NAME:    $APP_NAME"
echo "  APP_ENV:     $APP_ENV"
echo "  APP_PORT:    $APP_PORT"
echo "  LOG_LEVEL:   $LOG_LEVEL"
echo "  CONFIG_FILE: $CONFIG_FILE"

# 环境特定配置
case "${APP_ENV}" in
    production)
        : "${DB_HOST:=db.prod.example.com}"
        : "${LOG_LEVEL:=warn}"
        ;;
    staging)
        : "${DB_HOST:=db.staging.example.com}"
        ;;
    *)
        : "${DB_HOST:=localhost}"
        ;;
esac

echo ""
echo "数据库配置："
echo "  DB_HOST: $DB_HOST"
EOF

# 使用默认值运行
echo "=== 使用默认值 ==="
bash config-loader.sh

echo ""
echo "=== 覆盖部分配置 ==="
APP_ENV=production APP_PORT=3000 bash config-loader.sh
```

---

## Step 2 — 字符串长度与子串提取（15 分钟）

### 2.1 字符串长度

```bash
cd ~/expansion-lab

cat > string-length.sh << 'EOF'
#!/bin/bash
# 字符串长度

str="Hello, World!"
echo "字符串: '$str'"
echo "长度:   ${#str}"    # 13

# 数组元素个数
arr=(apple banana cherry)
echo ""
echo "数组:   ${arr[*]}"
echo "元素数: ${#arr[@]}"  # 3

# 特定元素长度
echo "第一个元素 '${arr[0]}' 的长度: ${#arr[0]}"  # 5
EOF

bash string-length.sh
```

### 2.2 子串提取

![Substring Extraction](images/substring-extraction.png)

<details>
<summary>View ASCII source</summary>

<!-- DIAGRAM: substring-extraction -->
```
┌─────────────────────────────────────────────────────────────────────────┐
│  子串提取语法：${var:offset:length}                                       │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  字符串: "Hello, World!"                                                 │
│  索引:    0123456789...                                                  │
│                                                                          │
│  ${var:offset}          从 offset 开始到末尾                             │
│  ${var:offset:length}   从 offset 开始，取 length 个字符                 │
│                                                                          │
│  示例：                                                                   │
│  ┌─────────────────────────────────────────────────────────────┐        │
│  │  str="Hello, World!"                                         │        │
│  │                                                              │        │
│  │  ${str:0}      → "Hello, World!"   # 从 0 开始到末尾        │        │
│  │  ${str:7}      → "World!"          # 从 7 开始到末尾        │        │
│  │  ${str:0:5}    → "Hello"           # 从 0 开始取 5 个       │        │
│  │  ${str:7:5}    → "World"           # 从 7 开始取 5 个       │        │
│  │  ${str: -6}    → "World!"          # 从倒数第 6 个到末尾    │        │
│  │  ${str: -6:5}  → "World"           # 从倒数第 6 个取 5 个   │        │
│  └─────────────────────────────────────────────────────────────┘        │
│                                                                          │
│  注意：负数 offset 前需要空格或括号，避免与 :- 混淆                        │
│    ${str: -6}  ✓  正确                                                   │
│    ${str:(-6)} ✓  正确                                                   │
│    ${str:-6}   ✗  被解释为默认值语法！                                    │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```
<!-- /DIAGRAM -->

</details>

```bash
cd ~/expansion-lab

cat > substring.sh << 'EOF'
#!/bin/bash
# 子串提取演示

str="Hello, World!"
echo "原字符串: '$str'"
echo ""

# 从指定位置到末尾
echo "=== 从 offset 到末尾 ==="
echo "\${str:7}  = '${str:7}'"       # World!

# 指定长度
echo ""
echo "=== 指定长度 ==="
echo "\${str:0:5} = '${str:0:5}'"    # Hello
echo "\${str:7:5} = '${str:7:5}'"    # World

# 负数索引（从末尾计数）
echo ""
echo "=== 负数索引 ==="
echo "\${str: -6}   = '${str: -6}'"      # World!  (注意空格！)
echo "\${str: -6:5} = '${str: -6:5}'"    # World
echo "\${str:(-6)}  = '${str:(-6)}'"     # 用括号也可以

# 实际应用：提取日期组件
echo ""
echo "=== 实际应用 ==="
date_str="2026-01-10"
year="${date_str:0:4}"
month="${date_str:5:2}"
day="${date_str:8:2}"
echo "日期: $date_str"
echo "年: $year, 月: $month, 日: $day"

# 提取文件名的固定部分
filename="log_20260110_server01.txt"
date_part="${filename:4:8}"
server="${filename:13:8}"
echo ""
echo "文件名: $filename"
echo "日期部分: $date_part"
echo "服务器: $server"
EOF

bash substring.sh
```

---

## Step 3 — 前缀与后缀删除（25 分钟）

这是参数展开中**最实用**的功能，用于路径处理、扩展名提取等场景。

### 3.1 四种模式删除语法

![Pattern Removal](images/pattern-removal.png)

<details>
<summary>View ASCII source</summary>

<!-- DIAGRAM: pattern-removal -->
```
┌─────────────────────────────────────────────────────────────────────────┐
│  模式删除语法                                                             │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  # - 从开头删除（前缀）     % - 从末尾删除（后缀）                         │
│                                                                          │
│  ${var#pattern}   删除最短匹配前缀                                        │
│  ${var##pattern}  删除最长匹配前缀（贪婪）                                 │
│  ${var%pattern}   删除最短匹配后缀                                        │
│  ${var%%pattern}  删除最长匹配后缀（贪婪）                                 │
│                                                                          │
│  记忆技巧：                                                               │
│  ┌───────────────────────────────────────────────────────────┐          │
│  │  # 在键盘上在 $ 左边 → 从左（开头）删除                    │          │
│  │  % 在键盘上在 $ 右边 → 从右（末尾）删除                    │          │
│  │                                                            │          │
│  │  单符号 (#, %) → 最短匹配（非贪婪）                        │          │
│  │  双符号 (##, %%) → 最长匹配（贪婪）                        │          │
│  └───────────────────────────────────────────────────────────┘          │
│                                                                          │
│  路径示例：path="/var/log/nginx/access.log"                              │
│  ┌───────────────────────────────────────────────────────────┐          │
│  │  ${path#*/}   → var/log/nginx/access.log  # 删除第一个 /  │          │
│  │  ${path##*/}  → access.log                # 删除到最后 /  │          │
│  │  ${path%/*}   → /var/log/nginx            # 删除最后 /后  │          │
│  │  ${path%%/*}  → (空)                      # 删除第一个 /后│          │
│  └───────────────────────────────────────────────────────────┘          │
│                                                                          │
│  扩展名示例：file="archive.tar.gz"                                       │
│  ┌───────────────────────────────────────────────────────────┐          │
│  │  ${file%.*}   → archive.tar   # 删除最后一个 .xxx         │          │
│  │  ${file%%.*}  → archive       # 删除第一个 .xxx 及之后    │          │
│  │  ${file#*.}   → tar.gz        # 删除第一个 xxx.          │          │
│  │  ${file##*.}  → gz            # 删除到最后一个 .          │          │
│  └───────────────────────────────────────────────────────────┘          │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```
<!-- /DIAGRAM -->

</details>

### 3.2 基础示例

```bash
cd ~/expansion-lab

cat > pattern-removal.sh << 'EOF'
#!/bin/bash
# 模式删除演示

echo "=== 前缀删除 (#, ##) ==="
str="hello-world-hello-bash"

echo "原字符串: $str"
echo "\${str#*-}   = ${str#*-}"     # world-hello-bash（最短匹配）
echo "\${str##*-}  = ${str##*-}"    # bash（最长匹配）

echo ""
echo "=== 后缀删除 (%, %%) ==="
echo "\${str%-*}   = ${str%-*}"     # hello-world-hello（最短匹配）
echo "\${str%%-*}  = ${str%%-*}"    # hello（最长匹配）

echo ""
echo "=== 路径处理 ==="
path="/var/log/nginx/access.log"
echo "完整路径:   $path"
echo "目录名:     ${path%/*}"       # /var/log/nginx（等同 dirname）
echo "文件名:     ${path##*/}"      # access.log（等同 basename）

echo ""
echo "=== 扩展名处理 ==="
file="document.backup.tar.gz"
echo "文件名:     $file"
echo "去最后扩展: ${file%.*}"       # document.backup.tar
echo "去所有扩展: ${file%%.*}"      # document
echo "最后扩展名: ${file##*.}"      # gz
echo "所有扩展名: ${file#*.}"       # backup.tar.gz
EOF

bash pattern-removal.sh
```

### 3.3 实际应用：批量重命名

```bash
cd ~/expansion-lab

cat > batch-rename.sh << 'EOF'
#!/bin/bash
# 使用参数展开批量重命名文件

# 创建测试文件
mkdir -p test_files
touch test_files/photo_001.JPG
touch test_files/photo_002.JPG
touch test_files/photo_003.JPG

echo "=== 原始文件 ==="
ls test_files/

echo ""
echo "=== 重命名预览（.JPG → .jpg）==="
for file in test_files/*.JPG; do
    if [[ -f "$file" ]]; then
        newname="${file%.JPG}.jpg"
        echo "mv '$file' → '$newname'"
    fi
done

echo ""
echo "=== 执行重命名 ==="
for file in test_files/*.JPG; do
    if [[ -f "$file" ]]; then
        mv "$file" "${file%.JPG}.jpg"
    fi
done
ls test_files/

echo ""
echo "=== 添加前缀预览 ==="
for file in test_files/*.jpg; do
    if [[ -f "$file" ]]; then
        dir="${file%/*}"
        name="${file##*/}"
        newname="$dir/2026_$name"
        echo "mv '$file' → '$newname'"
    fi
done
EOF

bash batch-rename.sh
```

### 3.4 路径处理对比

```bash
cd ~/expansion-lab

cat > path-comparison.sh << 'EOF'
#!/bin/bash
# 参数展开 vs 外部命令

path="/var/log/nginx/access.log"
echo "路径: $path"
echo ""

echo "=== 获取目录名 ==="
echo "dirname:       $(dirname "$path")"
echo "\${path%/*}:   ${path%/*}"

echo ""
echo "=== 获取文件名 ==="
echo "basename:      $(basename "$path")"
echo "\${path##*/}:  ${path##*/}"

echo ""
echo "=== 去扩展名 ==="
echo "basename .log: $(basename "$path" .log)"
echo "\${path%.*}:   ${path%.*}"
# 注意：上面保留了路径，只去扩展名
# 如果只要文件名不要扩展名：
name="${path##*/}"
echo "仅文件名:      ${name%.*}"

echo ""
echo "=== 性能对比 ==="
# 参数展开的性能优势
iterations=1000

start=$(date +%s.%N)
for ((i=0; i<iterations; i++)); do
    dir="${path%/*}"
    name="${path##*/}"
done
end=$(date +%s.%N)
echo "参数展开 $iterations 次: $(echo "$end - $start" | bc) 秒"

start=$(date +%s.%N)
for ((i=0; i<iterations; i++)); do
    dir=$(dirname "$path")
    name=$(basename "$path")
done
end=$(date +%s.%N)
echo "外部命令 $iterations 次: $(echo "$end - $start" | bc) 秒"
EOF

bash path-comparison.sh
```

---

## Step 4 — 查找替换（15 分钟）

### 4.1 替换语法

```bash
cd ~/expansion-lab

cat > search-replace.sh << 'EOF'
#!/bin/bash
# 查找替换语法

str="hello world, hello bash"

echo "原字符串: $str"
echo ""

echo "=== 替换第一个匹配 ==="
echo "\${str/hello/hi}:  ${str/hello/hi}"     # hi world, hello bash

echo ""
echo "=== 替换所有匹配 ==="
echo "\${str//hello/hi}: ${str//hello/hi}"    # hi world, hi bash

echo ""
echo "=== 删除（替换为空）==="
echo "删除第一个 hello: ${str/hello/}"
echo "删除所有 hello:   ${str//hello/}"

echo ""
echo "=== 锚定替换 ==="
# # 锚定开头
# % 锚定结尾
echo "开头匹配: \${str/#hello/hi}: ${str/#hello/hi}"   # hi world, hello bash
echo "结尾匹配: \${str/%bash/shell}: ${str/%bash/shell}" # hello world, hello shell

echo ""
echo "=== 实际应用 ==="
# 路径分隔符转换
win_path="C:\\Users\\Admin\\Documents"
unix_path="${win_path//\\//}"
echo "Windows: $win_path"
echo "Unix:    $unix_path"

# 去除空格
text="  hello   world  "
cleaned="${text// /}"
echo ""
echo "原始: '$text'"
echo "去空格: '$cleaned'"

# 替换多个字符（需要多次替换）
version="v1.2.3-beta"
clean_version="${version//./}"
clean_version="${clean_version//-/}"
clean_version="${clean_version//v/}"
echo ""
echo "版本: $version → $clean_version"
EOF

bash search-replace.sh
```

### 4.2 大小写转换

```bash
cd ~/expansion-lab

cat > case-conversion.sh << 'EOF'
#!/bin/bash
# 大小写转换（Bash 4.0+）

str="Hello World"

echo "原字符串: $str"
echo ""

echo "=== 转大写 ==="
echo "首字母大写: \${str^}:  ${str^}"     # Hello World（首字母已大写）
echo "全部大写:   \${str^^}: ${str^^}"    # HELLO WORLD

echo ""
echo "=== 转小写 ==="
echo "首字母小写: \${str,}:  ${str,}"     # hello World
echo "全部小写:   \${str,,}: ${str,,}"    # hello world

echo ""
echo "=== 混合应用 ==="
name="john DOE"
# 规范化：首字母大写，其余小写
normalized="${name,,}"        # 先全小写: john doe
normalized="${normalized^}"   # 首字母大写: John doe
echo "原始:   $name"
echo "规范化: $normalized"

# 更好的方式：分别处理姓和名
first="john"
last="DOE"
echo ""
echo "姓: ${first^}  名: ${last,,}"
echo "姓: ${first^^} 名: ${last^^}"

echo ""
echo "=== 用户输入规范化 ==="
read -p "请输入 yes 或 no: " answer
answer="${answer,,}"  # 转小写
case "$answer" in
    yes|y) echo "你选择了 Yes" ;;
    no|n)  echo "你选择了 No" ;;
    *)     echo "无效输入" ;;
esac
EOF

# 交互式运行
echo "YES" | bash case-conversion.sh
```

---

## Step 5 — 间接引用与高级技巧（15 分钟）

### 5.1 间接引用

```bash
cd ~/expansion-lab

cat > indirect-reference.sh << 'EOF'
#!/bin/bash
# 间接引用：${!var}

echo "=== 基本间接引用 ==="
name="greeting"
greeting="Hello, World!"

echo "name 的值:   $name"           # greeting
echo "直接引用:    $greeting"       # Hello, World!
echo "间接引用:    ${!name}"        # Hello, World!（通过 name 的值引用）

echo ""
echo "=== 动态变量名 ==="
# 根据环境选择配置
env="prod"
db_host_dev="localhost"
db_host_staging="staging.db.local"
db_host_prod="prod.db.example.com"

var_name="db_host_${env}"
echo "环境: $env"
echo "变量名: $var_name"
echo "数据库主机: ${!var_name}"

echo ""
echo "=== 列出匹配的变量名 ==="
# ${!prefix*} 或 ${!prefix@} 列出以 prefix 开头的变量名
echo "以 BASH_ 开头的变量："
echo "${!BASH_*}"

echo ""
echo "=== 数组间接引用 ==="
arr=(apple banana cherry)
idx=1
echo "arr[$idx] = ${arr[$idx]}"     # banana

# 间接获取数组元素
ref="arr[$idx]"
echo "\${!ref} = ${!ref}"           # banana
EOF

bash indirect-reference.sh
```

### 5.2 实际应用：配置映射

```bash
cd ~/expansion-lab

cat > config-mapping.sh << 'EOF'
#!/bin/bash
# 使用间接引用实现配置映射

# 定义多环境配置
config_dev_host="localhost"
config_dev_port="3000"
config_dev_debug="true"

config_staging_host="staging.example.com"
config_staging_port="8080"
config_staging_debug="true"

config_prod_host="prod.example.com"
config_prod_port="80"
config_prod_debug="false"

# 获取配置的函数
get_config() {
    local env="$1"
    local key="$2"
    local var_name="config_${env}_${key}"
    echo "${!var_name}"
}

# 显示指定环境的所有配置
show_env_config() {
    local env="$1"
    echo "=== $env 环境配置 ==="
    echo "  host:  $(get_config "$env" host)"
    echo "  port:  $(get_config "$env" port)"
    echo "  debug: $(get_config "$env" debug)"
}

# 使用
show_env_config dev
echo ""
show_env_config prod
EOF

bash config-mapping.sh
```

---

## Step 6 — [Bash 5+] 新特性（可选）

> 以下特性需要 Bash 5.0+，在 RHEL 8（4.4）上不可用，但 RHEL 9、Ubuntu 20.04+ 可用。  

```bash
cd ~/expansion-lab

cat > bash5-features.sh << 'EOF'
#!/bin/bash
# Bash 5.x 新特性

# 检查 Bash 版本
if ((BASH_VERSINFO[0] < 5)); then
    echo "这些特性需要 Bash 5.0+，当前版本: $BASH_VERSION"
    echo "（以下内容仅作参考）"
    echo ""
fi

echo "Bash 版本: $BASH_VERSION"
echo ""

echo "=== [Bash 5+] \$EPOCHSECONDS ==="
# 替代 $(date +%s)，无需 fork
if [[ -v EPOCHSECONDS ]]; then
    echo "EPOCHSECONDS: $EPOCHSECONDS"
    echo "date +%s:     $(date +%s)"
else
    echo "EPOCHSECONDS 不可用（需要 Bash 5.0+）"
    echo "替代方案: \$(date +%s)"
fi

echo ""
echo "=== [Bash 5+] \$EPOCHREALTIME ==="
# 微秒精度时间戳
if [[ -v EPOCHREALTIME ]]; then
    echo "EPOCHREALTIME: $EPOCHREALTIME"
else
    echo "EPOCHREALTIME 不可用（需要 Bash 5.0+）"
    echo "替代方案: \$(date +%s.%N)"
fi

echo ""
echo "=== [Bash 5+] \$SRANDOM ==="
# 32-bit 加密安全随机数
if [[ -v SRANDOM ]]; then
    echo "SRANDOM: $SRANDOM"
    echo "RANDOM:  $RANDOM (15-bit)"
else
    echo "SRANDOM 不可用（需要 Bash 5.1+）"
    echo "替代方案: \$(od -An -tu4 -N4 /dev/urandom | tr -d ' ')"
fi
EOF

bash bash5-features.sh
```

**各发行版 Bash 版本：**

| 发行版 | Bash 版本 |
|--------|-----------|
| RHEL 7 | 4.2 |
| RHEL 8 | 4.4 |
| RHEL 9 | 5.1 |
| Ubuntu 20.04 | 5.0 |
| Ubuntu 22.04 | 5.1 |
| Ubuntu 24.04 | 5.2 |

---

## Step 7 — Mini Project：文件路径处理器（20 分钟）

> **项目目标**：创建一个使用纯参数展开处理文件路径的工具。  

### 7.1 项目要求

创建 `pathutil.sh`：
1. 接受文件路径作为参数
2. 输出：目录、文件名、基础名、扩展名
3. 支持多扩展名（如 `.tar.gz`）
4. 不使用 `dirname`、`basename`、`cut` 等外部命令
5. 通过 ShellCheck 检查

### 7.2 完整实现

```bash
cd ~/expansion-lab

cat > pathutil.sh << 'EOF'
#!/bin/bash
# =============================================================================
# 文件名：pathutil.sh
# 功能：纯参数展开的路径处理工具
# 用法：./pathutil.sh <路径>
# =============================================================================

set -euo pipefail

# 颜色定义
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[0;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# 帮助信息
usage() {
    cat << HELP
用法: $(basename "$0") <路径>

使用纯 Bash 参数展开解析文件路径。

示例:
  $(basename "$0") /var/log/nginx/access.log
  $(basename "$0") archive.tar.gz
  $(basename "$0") ~/Documents/report.pdf

特性:
  - 提取目录名、文件名、基础名、扩展名
  - 支持多扩展名（如 .tar.gz）
  - 不依赖外部命令（dirname、basename、cut 等）
HELP
}

# 解析路径的函数
parse_path() {
    local path="$1"

    # 处理空路径
    if [[ -z "$path" ]]; then
        echo "错误: 路径不能为空" >&2
        return 1
    fi

    # 目录部分
    local dir
    if [[ "$path" == */* ]]; then
        dir="${path%/*}"
        # 处理根目录的情况
        [[ -z "$dir" ]] && dir="/"
    else
        dir="."
    fi

    # 文件名（带扩展名）
    local filename="${path##*/}"

    # 基础名和扩展名
    local basename
    local extension
    local full_extension

    if [[ "$filename" == .* && "${filename#.}" != *"."* ]]; then
        # 隐藏文件没有扩展名（如 .bashrc）
        basename="$filename"
        extension=""
        full_extension=""
    elif [[ "$filename" == *"."* ]]; then
        # 有扩展名
        basename="${filename%.*}"      # 去最后一个扩展名
        extension="${filename##*.}"    # 最后一个扩展名
        full_extension="${filename#*.}" # 所有扩展名

        # 处理多扩展名（如 archive.tar.gz → tar.gz）
        if [[ "$basename" == *"."* ]]; then
            # 检查是否是已知的双扩展名
            case "$extension" in
                gz|bz2|xz|lz|zst)
                    local prev_ext="${basename##*.}"
                    case "$prev_ext" in
                        tar)
                            # 是 .tar.gz 类型
                            full_extension="$prev_ext.$extension"
                            basename="${basename%.*}"
                            ;;
                    esac
                    ;;
            esac
        fi
    else
        # 没有扩展名
        basename="$filename"
        extension=""
        full_extension=""
    fi

    # 输出结果
    echo -e "${BLUE}路径解析结果：${NC}"
    echo -e "  ${GREEN}原始路径:${NC}   $path"
    echo -e "  ${GREEN}目录:${NC}       $dir"
    echo -e "  ${GREEN}文件名:${NC}     $filename"
    echo -e "  ${GREEN}基础名:${NC}     $basename"
    echo -e "  ${GREEN}扩展名:${NC}     ${extension:-（无）}"

    if [[ -n "$full_extension" && "$full_extension" != "$extension" ]]; then
        echo -e "  ${YELLOW}完整扩展:${NC}   $full_extension"
    fi

    # 如果是实际存在的文件，显示更多信息
    if [[ -e "$path" ]]; then
        echo ""
        echo -e "${BLUE}文件信息：${NC}"
        if [[ -f "$path" ]]; then
            echo -e "  类型: 普通文件"
            echo -e "  大小: $(stat -f%z "$path" 2>/dev/null || stat -c%s "$path" 2>/dev/null) 字节"
        elif [[ -d "$path" ]]; then
            echo -e "  类型: 目录"
        elif [[ -L "$path" ]]; then
            echo -e "  类型: 符号链接 → $(readlink "$path")"
        fi
    fi
}

# 批量处理函数
batch_parse() {
    for path in "$@"; do
        parse_path "$path"
        echo ""
    done
}

# 主程序
main() {
    # 检查参数
    if [[ $# -eq 0 ]]; then
        usage
        exit 1
    fi

    case "$1" in
        -h|--help)
            usage
            exit 0
            ;;
        *)
            if [[ $# -eq 1 ]]; then
                parse_path "$1"
            else
                batch_parse "$@"
            fi
            ;;
    esac
}

main "$@"
EOF

chmod +x pathutil.sh

# 测试
echo "=== 测试 1: 标准路径 ==="
./pathutil.sh /var/log/nginx/access.log

echo ""
echo "=== 测试 2: 多扩展名 ==="
./pathutil.sh backup.tar.gz

echo ""
echo "=== 测试 3: 隐藏文件 ==="
./pathutil.sh ~/.bashrc

echo ""
echo "=== 测试 4: 无扩展名 ==="
./pathutil.sh /usr/bin/bash

echo ""
echo "=== 测试 5: 批量处理 ==="
./pathutil.sh /etc/passwd /var/log/messages README.md
```

---

## 速查表（Cheatsheet）

```bash
# ============================================================================
# 参数展开速查表
# ============================================================================

# --- 默认值 ---
"${var:-default}"   # 如果 var 未设置或空，使用 default
"${var:=default}"   # 如果 var 未设置或空，设置为 default
"${var:+alternate}" # 如果 var 有值，使用 alternate
"${var:?error msg}" # 如果 var 未设置或空，打印错误并退出

# --- 字符串长度 ---
"${#var}"           # 字符串长度
"${#arr[@]}"        # 数组元素个数

# --- 子串提取 ---
"${var:offset}"     # 从 offset 到末尾
"${var:offset:len}" # 从 offset 开始取 len 个字符
"${var: -n}"        # 最后 n 个字符（注意空格！）

# --- 前缀删除 ---
"${var#pattern}"    # 删除最短前缀匹配
"${var##pattern}"   # 删除最长前缀匹配（取文件名）

# --- 后缀删除 ---
"${var%pattern}"    # 删除最短后缀匹配（去扩展名）
"${var%%pattern}"   # 删除最长后缀匹配

# --- 查找替换 ---
"${var/old/new}"    # 替换第一个匹配
"${var//old/new}"   # 替换所有匹配
"${var/#old/new}"   # 替换开头匹配
"${var/%old/new}"   # 替换结尾匹配

# --- 大小写转换 (Bash 4+) ---
"${var^}"           # 首字母大写
"${var^^}"          # 全部大写
"${var,}"           # 首字母小写
"${var,,}"          # 全部小写

# --- 间接引用 ---
"${!var}"           # 通过 var 的值作为变量名引用
"${!prefix*}"       # 列出以 prefix 开头的变量名

# ============================================================================
# 常用路径处理
# ============================================================================

path="/var/log/nginx/access.log"
"${path%/*}"        # /var/log/nginx      （目录，等同 dirname）
"${path##*/}"       # access.log          （文件名，等同 basename）
"${path%.*}"        # /var/log/nginx/access（去扩展名）
"${path##*.}"       # log                 （扩展名）
```

---

## 反模式：常见错误

### 错误 1：负数索引忘记空格

```bash
# 错误：被解释为默认值语法
str="hello"
echo "${str:-3}"    # 输出 hello（把 -3 当成默认值！）

# 正确：空格或括号
echo "${str: -3}"   # 输出 llo
echo "${str:(-3)}"  # 输出 llo
```

### 错误 2：混淆 # 和 % 的方向

```bash
path="/var/log/app.log"

# 错误：用 # 删除后缀
echo "${path#.log}"   # 不起作用，# 从开头匹配

# 正确：用 % 删除后缀
echo "${path%.log}"   # /var/log/app
```

### 错误 3：忘记模式中的通配符

```bash
path="/var/log/nginx/access.log"

# 错误：只匹配字面量
echo "${path#/}"      # var/log/nginx/access.log（只删除一个 /）

# 正确：使用通配符
echo "${path##*/}"    # access.log（删除到最后一个 /）
```

### 错误 4：在需要外部命令时坚持用参数展开

```bash
# 参数展开不支持正则表达式
# 错误想法：用参数展开做复杂匹配
str="abc123def456"

# 这种情况用 sed 更合适
echo "$str" | sed 's/[0-9]//g'  # abcdef
```

---

## 职场小贴士（Japan IT Context）

### 运维脚本中的参数展开

在日本 IT 企业的运维场景中，参数展开常用于：

| 日语术语 | 含义 | 参数展开应用 |
|----------|------|--------------|
| ログローテーション | 日志轮转 | `${log%.log}.$(date +%Y%m%d).log` |
| バックアップ | 备份 | `${file%.*}_backup.${file##*.}` |
| 設定ファイル | 配置文件 | `${CONFIG_DIR:-/etc/myapp}` |
| 環境変数 | 环境变量 | `${APP_ENV:?環境変数が必要です}` |

### 日志文件处理示例

```bash
#!/bin/bash
# ログファイル処理スクリプト

# 必須環境変数チェック
: "${LOG_DIR:?LOG_DIR 環境変数が設定されていません}"

# 古いログのアーカイブ
for logfile in "$LOG_DIR"/*.log; do
    [[ -f "$logfile" ]] || continue

    # ファイル名からベース名を取得
    basename="${logfile##*/}"
    basename="${basename%.log}"

    # アーカイブ先
    archive="${LOG_DIR}/archive/${basename}_$(date +%Y%m%d).log.gz"

    gzip -c "$logfile" > "$archive"
    echo "アーカイブ完了: $archive"
done
```

### 监控脚本配置模板

```bash
#!/bin/bash
# 監視スクリプト設定

# デフォルト値設定
: "${MONITOR_INTERVAL:=60}"
: "${ALERT_THRESHOLD:=90}"
: "${ALERT_EMAIL:=admin@example.com}"
: "${LOG_LEVEL:=INFO}"

# 設定確認
echo "監視設定:"
echo "  間隔:     ${MONITOR_INTERVAL}秒"
echo "  閾値:     ${ALERT_THRESHOLD}%"
echo "  通知先:   $ALERT_EMAIL"
echo "  ログ:     $LOG_LEVEL"
```

---

## 检查清单

完成本课后，你应该能够：

- [ ] 使用 `${var:-default}` 设置默认值
- [ ] 使用 `${var:?error}` 强制要求变量
- [ ] 使用 `${#var}` 获取字符串长度
- [ ] 使用 `${var:offset:length}` 提取子串
- [ ] 使用 `${var#pattern}` 删除前缀
- [ ] 使用 `${var%pattern}` 删除后缀
- [ ] 区分 `#`/`##` 和 `%`/`%%` 的贪婪与非贪婪
- [ ] 使用 `${var/old/new}` 进行替换
- [ ] 使用 `${var^^}` 和 `${var,,}` 转换大小写
- [ ] 理解 `${!var}` 间接引用

**验证命令：**

```bash
cd ~/expansion-lab

# 测试 1: 默认值
bash -c 'echo "${UNDEFINED:-default}"'
# 预期: default

# 测试 2: 路径处理
bash -c 'p="/var/log/app.log"; echo "${p%/*} ${p##*/}"'
# 预期: /var/log app.log

# 测试 3: 扩展名
bash -c 'f="archive.tar.gz"; echo "${f%.*} ${f##*.}"'
# 预期: archive.tar gz

# 测试 4: 大小写
bash -c 'echo "${name^^}" name="hello"'
# 运行: name="hello"; echo "${name^^}"
# 预期: HELLO

# 测试 5: ShellCheck
shellcheck pathutil.sh
# 预期: 无错误
```

---

## 本课小结

| 语法 | 功能 | 示例 |
|------|------|------|
| `${var:-default}` | 默认值 | `${PORT:-8080}` |
| `${var:=default}` | 设置默认值 | `${CONFIG:=/etc/app.conf}` |
| `${var:?error}` | 必需变量 | `${DB_HOST:?需要数据库}` |
| `${#var}` | 字符串长度 | `${#filename}` |
| `${var:n:m}` | 子串提取 | `${date:0:4}` |
| `${var#pattern}` | 删除最短前缀 | `${path#*/}` |
| `${var##pattern}` | 删除最长前缀 | `${path##*/}` → 文件名 |
| `${var%pattern}` | 删除最短后缀 | `${file%.*}` → 去扩展名 |
| `${var%%pattern}` | 删除最长后缀 | `${file%%.*}` |
| `${var/old/new}` | 替换一次 | `${str/foo/bar}` |
| `${var//old/new}` | 替换全部 | `${str//foo/bar}` |
| `${var^^}` | 全大写 | `${input^^}` |
| `${var,,}` | 全小写 | `${input,,}` |
| `${!var}` | 间接引用 | `${!var_name}` |

---

## 面试准备

### **変数のデフォルト値を設定する方法は？**

`${var:-default}` で未設定時にデフォルト値を使用し、`${var:=default}` で同時に変数に代入します。

```bash
# 使用のみ（変数は変更されない）
port="${PORT:-8080}"

# 代入も行う
: "${CONFIG_DIR:=/etc/myapp}"

# 必須変数チェック
: "${DB_HOST:?DB_HOST が必要です}"
```

### **ファイルパスから拡張子を取り除くには？**

`${filename%.*}` を使います。`%` は最短後方マッチを削除します。

```bash
file="document.pdf"
base="${file%.*}"     # document

# ディレクトリとファイル名の分離
path="/var/log/app.log"
dir="${path%/*}"      # /var/log（dirname と同等）
name="${path##*/}"    # app.log（basename と同等）
```

---

## 延伸阅读

- [Bash Parameter Expansion](https://www.gnu.org/software/bash/manual/html_node/Shell-Parameter-Expansion.html) - GNU Bash 官方文档
- [Advanced Bash-Scripting Guide - Manipulating Strings](https://tldp.org/LDP/abs/html/string-manipulation.html) - 高级 Bash 脚本指南
- 上一课：[07 - 数组](../07-arrays/) — 索引数组与关联数组
- 下一课：[09 - 错误处理与 trap](../09-error-handling/) — 生产级脚本必备

---

## 清理

```bash
# 清理练习文件
cd ~
rm -rf ~/expansion-lab
```

---

## 系列导航

[<-- 07 - 数组](../07-arrays/) | [课程首页](../) | [09 - 错误处理与 trap -->](../09-error-handling/)
