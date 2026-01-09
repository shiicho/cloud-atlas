# 07 - 数组（Arrays）

> **目标**：掌握索引数组和关联数组，构建配置文件解析器  
> **前置**：[06 - 函数](../06-functions/)  
> **时间**：90-120 分钟  
> **环境**：Bash 4.x+（RHEL 7/8/9, Ubuntu 18.04+ 均可）  
> **注意**：关联数组需要 Bash 4.0+，索引数组在 Bash 3.x 也可用  

---

## 将学到的内容

1. 创建和使用索引数组
2. 创建和使用关联数组（Bash 4+）
3. 数组遍历与操作
4. 数组与循环的结合
5. 实际应用：配置解析、参数收集

---

## 先跑起来！（5 分钟）

> 在理解原理之前，先让数组跑起来。  
> 体验数组存储多个值的便利。  

```bash
# 创建练习目录
mkdir -p ~/array-lab && cd ~/array-lab

# 创建你的第一个数组脚本
cat > first-array.sh << 'EOF'
#!/bin/bash
# 我的第一个数组脚本

# 索引数组：存储服务器列表
servers=("web01" "web02" "db01" "cache01")

echo "=== 服务器列表 ==="
echo "第一台: ${servers[0]}"
echo "第二台: ${servers[1]}"
echo "服务器总数: ${#servers[@]}"
echo "所有服务器: ${servers[@]}"

echo ""

# 关联数组：存储配置（需要 Bash 4+）
declare -A config
config[host]="192.168.1.100"
config[port]="8080"
config[user]="admin"

echo "=== 应用配置 ==="
echo "主机: ${config[host]}"
echo "端口: ${config[port]}"
echo "用户: ${config[user]}"
EOF

# 运行它！
bash first-array.sh
```

**你应该看到类似的输出：**

```
=== 服务器列表 ===
第一台: web01
第二台: web02
服务器总数: 4
所有服务器: web01 web02 db01 cache01

=== 应用配置 ===
主机: 192.168.1.100
端口: 8080
用户: admin
```

**恭喜！你刚刚使用了 Shell 的两种数组！**

数组是处理批量数据的利器——服务器列表、配置参数、文件集合都能用数组优雅处理。

现在让我们深入理解数组的各个方面。

---

## Step 1 — 索引数组基础（20 分钟）

### 1.1 什么是索引数组？

索引数组使用数字下标（从 0 开始）来访问元素：

![Indexed Array](images/indexed-array.png)

<details>
<summary>View ASCII source</summary>

<!-- DIAGRAM: indexed-array -->
```
┌─────────────────────────────────────────────────────────────────┐
│  索引数组（Indexed Array）                                       │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  servers=("web01" "web02" "db01" "cache01")                     │
│                                                                  │
│  内存布局：                                                      │
│  ┌────────┬────────┬────────┬────────┐                         │
│  │ web01  │ web02  │  db01  │cache01 │                         │
│  └────────┴────────┴────────┴────────┘                         │
│  索引：0       1        2        3                              │
│                                                                  │
│  访问语法：                                                      │
│  ${servers[0]}    → "web01"     （第一个元素）                   │
│  ${servers[3]}    → "cache01"   （第四个元素）                   │
│  ${servers[@]}    → 所有元素                                    │
│  ${#servers[@]}   → 4           （元素个数）                    │
│                                                                  │
│  注意：索引从 0 开始，不是 1！                                   │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```
<!-- /DIAGRAM -->

</details>

### 1.2 创建索引数组

有多种方式创建索引数组：

```bash
cd ~/array-lab

cat > create-arrays.sh << 'EOF'
#!/bin/bash

# 方式 1：一次性赋值（最常用）
fruits=("apple" "banana" "cherry" "date")

# 方式 2：逐个赋值
colors[0]="red"
colors[1]="green"
colors[2]="blue"

# 方式 3：使用 declare（显式声明）
declare -a numbers=(1 2 3 4 5)

# 方式 4：从命令输出创建
files=($(ls /etc/*.conf 2>/dev/null | head -5))

# 方式 5：带空格的元素
paths=("/home/user/My Documents" "/tmp/test file.txt")

echo "=== 各种创建方式的结果 ==="
echo "fruits: ${fruits[@]}"
echo "colors: ${colors[@]}"
echo "numbers: ${numbers[@]}"
echo "files: ${files[@]}"
echo "paths[0]: ${paths[0]}"
echo "paths[1]: ${paths[1]}"
EOF

bash create-arrays.sh
```

### 1.3 访问数组元素

```bash
cd ~/array-lab

cat > access-arrays.sh << 'EOF'
#!/bin/bash

servers=("web01" "web02" "db01" "cache01" "monitor01")

echo "=== 访问数组元素 ==="

# 单个元素（注意必须用花括号）
echo "第一个: ${servers[0]}"
echo "最后一个: ${servers[-1]}"       # Bash 4.3+
echo "倒数第二个: ${servers[-2]}"     # Bash 4.3+

# 所有元素
echo ""
echo "所有元素 (\${servers[@]}): ${servers[@]}"
echo "所有元素 (\${servers[*]}): ${servers[*]}"

# 数组长度
echo ""
echo "元素个数: ${#servers[@]}"

# 获取所有索引
echo "所有索引: ${!servers[@]}"

# 元素长度
echo "第一个元素的字符数: ${#servers[0]}"
EOF

bash access-arrays.sh
```

**重要**：`$servers` 只会返回第一个元素，必须用 `${servers[@]}` 获取所有元素！

### 1.4 数组切片

```bash
cd ~/array-lab

cat > array-slice.sh << 'EOF'
#!/bin/bash

letters=("a" "b" "c" "d" "e" "f" "g")

echo "原数组: ${letters[@]}"
echo ""

# 切片语法: ${array[@]:start:count}
echo "=== 数组切片 ==="
echo "从索引 2 开始取 3 个: ${letters[@]:2:3}"    # c d e
echo "从索引 0 开始取 2 个: ${letters[@]:0:2}"    # a b
echo "从索引 3 开始到末尾: ${letters[@]:3}"       # d e f g

# 负数索引切片（Bash 4.3+）
echo ""
echo "=== 负数索引切片 ==="
echo "最后 3 个元素: ${letters[@]: -3}"           # 注意空格！
echo "从倒数第 4 个开始取 2 个: ${letters[@]: -4:2}"
EOF

bash array-slice.sh
```

> **注意**：负数索引前必须有空格，如 `${arr[@]: -3}`，否则会被解析为默认值语法。  

---

## Step 2 — 数组修改操作（15 分钟）

### 2.1 添加元素

```bash
cd ~/array-lab

cat > array-modify.sh << 'EOF'
#!/bin/bash

# 初始数组
servers=("web01" "web02")
echo "初始: ${servers[@]} (共 ${#servers[@]} 个)"

# 追加单个元素
servers+=("db01")
echo "追加 db01: ${servers[@]}"

# 追加多个元素
servers+=("cache01" "monitor01")
echo "追加多个: ${servers[@]}"

# 在指定位置插入（通过切片）
# 在索引 2 处插入 "new-server"
temp=("${servers[@]:0:2}" "new-server" "${servers[@]:2}")
servers=("${temp[@]}")
echo "在位置 2 插入: ${servers[@]}"
EOF

bash array-modify.sh
```

### 2.2 删除元素

```bash
cd ~/array-lab

cat > array-delete.sh << 'EOF'
#!/bin/bash

servers=("web01" "web02" "db01" "cache01" "monitor01")
echo "初始: ${servers[@]}"
echo "索引: ${!servers[@]}"

# 删除指定索引的元素
unset 'servers[2]'  # 删除 db01
echo ""
echo "删除索引 2 后: ${servers[@]}"
echo "索引: ${!servers[@]}"  # 注意索引不会重新排列！

# 如果需要重新排列索引
servers=("${servers[@]}")
echo ""
echo "重新排列后: ${servers[@]}"
echo "索引: ${!servers[@]}"

# 删除整个数组
# unset servers
EOF

bash array-delete.sh
```

![Array Delete Behavior](images/array-delete.png)

<details>
<summary>View ASCII source</summary>

<!-- DIAGRAM: array-delete -->
```
┌─────────────────────────────────────────────────────────────────┐
│  数组删除行为                                                    │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  初始状态：                                                      │
│  ┌────────┬────────┬────────┬────────┬──────────┐              │
│  │ web01  │ web02  │  db01  │cache01 │monitor01 │              │
│  └────────┴────────┴────────┴────────┴──────────┘              │
│  索引：0       1        2        3        4                     │
│                                                                  │
│  执行 unset 'arr[2]' 后：                                       │
│  ┌────────┬────────┬────────┬────────┬──────────┐              │
│  │ web01  │ web02  │ (空)   │cache01 │monitor01 │              │
│  └────────┴────────┴────────┴────────┴──────────┘              │
│  索引：0       1      (无)      3        4                      │
│                                                                  │
│  注意：索引不会自动重新排列！                                     │
│  ${!arr[@]} 返回 "0 1 3 4"                                      │
│                                                                  │
│  要重新排列：arr=("${arr[@]}")                                   │
│  ┌────────┬────────┬────────┬──────────┐                       │
│  │ web01  │ web02  │cache01 │monitor01 │                       │
│  └────────┴────────┴────────┴──────────┘                       │
│  索引：0       1        2        3                              │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```
<!-- /DIAGRAM -->

</details>

### 2.3 修改元素

```bash
cd ~/array-lab

cat > array-update.sh << 'EOF'
#!/bin/bash

servers=("web01" "web02" "db01")

echo "修改前: ${servers[@]}"

# 直接通过索引修改
servers[1]="web02-new"
echo "修改索引 1: ${servers[@]}"

# 批量替换（使用参数展开）
# 把所有 web 替换为 nginx
echo ""
echo "=== 批量替换 ==="
echo "原数组: ${servers[@]}"
echo "替换后: ${servers[@]/web/nginx}"

# 注意：这不会修改原数组，只返回替换后的结果
# 要真正修改，需要重新赋值：
# servers=("${servers[@]/web/nginx}")
EOF

bash array-update.sh
```

---

## Step 3 — 关联数组（Bash 4+）（20 分钟）

### 3.1 什么是关联数组？

关联数组使用字符串作为键（key），类似于其他语言的 Hash、Map 或 Dictionary：

![Associative Array](images/associative-array.png)

<details>
<summary>View ASCII source</summary>

<!-- DIAGRAM: associative-array -->
```
┌─────────────────────────────────────────────────────────────────┐
│  关联数组（Associative Array）                                   │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  索引数组 vs 关联数组：                                          │
│                                                                  │
│  索引数组：                                                      │
│  ┌────────┬────────┬────────┐                                   │
│  │  val1  │  val2  │  val3  │                                   │
│  └────────┴────────┴────────┘                                   │
│  键：  0       1       2        （数字）                         │
│                                                                  │
│  关联数组：                                                      │
│  ┌────────┬────────┬────────┐                                   │
│  │  val1  │  val2  │  val3  │                                   │
│  └────────┴────────┴────────┘                                   │
│  键："host"  "port"  "user"    （字符串）                        │
│                                                                  │
│  声明方式（必须！）：                                             │
│  declare -A config     # 必须用 declare -A 声明                  │
│                                                                  │
│  赋值：                                                          │
│  config[host]="192.168.1.1"                                     │
│  config[port]="8080"                                            │
│                                                                  │
│  访问：                                                          │
│  ${config[host]}     → "192.168.1.1"                            │
│  ${config[@]}        → 所有值                                   │
│  ${!config[@]}       → 所有键                                   │
│                                                                  │
│  注意：必须用 declare -A，否则会被当作索引数组处理！              │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```
<!-- /DIAGRAM -->

</details>

### 3.2 创建和使用关联数组

```bash
cd ~/array-lab

cat > assoc-array.sh << 'EOF'
#!/bin/bash

# 检查 Bash 版本
if ((BASH_VERSINFO[0] < 4)); then
    echo "错误：关联数组需要 Bash 4.0+" >&2
    echo "当前版本: $BASH_VERSION" >&2
    exit 1
fi

# 创建关联数组（必须用 declare -A）
declare -A server_info

# 逐个赋值
server_info[hostname]="prod-web-01"
server_info[ip]="10.0.1.100"
server_info[role]="webserver"
server_info[os]="RHEL 8"

echo "=== 服务器信息 ==="
echo "主机名: ${server_info[hostname]}"
echo "IP 地址: ${server_info[ip]}"
echo "角色: ${server_info[role]}"
echo "操作系统: ${server_info[os]}"

# 或者一次性赋值
declare -A db_config=(
    [host]="db.example.com"
    [port]="5432"
    [name]="production"
    [user]="app_user"
)

echo ""
echo "=== 数据库配置 ==="
echo "连接字符串: postgresql://${db_config[user]}@${db_config[host]}:${db_config[port]}/${db_config[name]}"
EOF

bash assoc-array.sh
```

### 3.3 关联数组的遍历

```bash
cd ~/array-lab

cat > assoc-iterate.sh << 'EOF'
#!/bin/bash

declare -A metrics=(
    [cpu_usage]="45%"
    [memory_usage]="78%"
    [disk_usage]="62%"
    [network_in]="1.2 Gbps"
    [network_out]="0.8 Gbps"
)

echo "=== 系统监控指标 ==="

# 获取所有键
echo "所有键: ${!metrics[@]}"

# 获取所有值
echo "所有值: ${metrics[@]}"

# 遍历键值对
echo ""
echo "=== 详细指标 ==="
for key in "${!metrics[@]}"; do
    printf "  %-15s : %s\n" "$key" "${metrics[$key]}"
done

# 检查键是否存在
echo ""
if [[ -v metrics[cpu_usage] ]]; then
    echo "cpu_usage 键存在"
fi

if [[ ! -v metrics[gpu_usage] ]]; then
    echo "gpu_usage 键不存在"
fi
EOF

bash assoc-iterate.sh
```

### 3.4 常见错误：忘记 declare -A

```bash
cd ~/array-lab

cat > assoc-mistake.sh << 'EOF'
#!/bin/bash

echo "=== 错误示范 ==="

# 错误：没有 declare -A
wrong[host]="localhost"
wrong[port]="8080"

echo "wrong 数组内容: ${wrong[@]}"
echo "wrong 数组键: ${!wrong[@]}"
echo "wrong[host]: ${wrong[host]}"
# 结果：只有最后一个值生效，键被当作数字索引 0

echo ""
echo "=== 正确做法 ==="

# 正确：使用 declare -A
declare -A correct
correct[host]="localhost"
correct[port]="8080"

echo "correct 数组内容: ${correct[@]}"
echo "correct 数组键: ${!correct[@]}"
echo "correct[host]: ${correct[host]}"
EOF

bash assoc-mistake.sh
```

---

## Step 4 — 数组遍历最佳实践（15 分钟）

### 4.1 正确遍历数组（重要！）

数组遍历是最容易出错的地方，关键在于正确使用引号：

![Array Iteration](images/array-iteration.png)

<details>
<summary>View ASCII source</summary>

<!-- DIAGRAM: array-iteration -->
```
┌─────────────────────────────────────────────────────────────────┐
│  数组遍历：引号的重要性                                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  arr=("file one.txt" "file two.txt" "file three.txt")           │
│                                                                  │
│  错误：for item in ${arr[@]}                                    │
│  ┌────────┬─────┬────────┬─────┬──────────┬─────┐              │
│  │  file  │ one │  file  │ two │  file    │three│              │
│  └────────┴─────┴────────┴─────┴──────────┴─────┘              │
│  结果：6 次循环！空格导致元素被分割                              │
│                                                                  │
│  正确：for item in "${arr[@]}"                                  │
│  ┌────────────────┬────────────────┬──────────────────┐        │
│  │  file one.txt  │  file two.txt  │  file three.txt  │        │
│  └────────────────┴────────────────┴──────────────────┘        │
│  结果：3 次循环！每个元素保持完整                                │
│                                                                  │
│  黄金法则：                                                      │
│  遍历数组时，永远使用 "${arr[@]}" 而不是 ${arr[@]}              │
│                                                                  │
│  ${arr[@]} vs ${arr[*]} 的区别：                                │
│  "${arr[@]}"  → "elem1" "elem2" "elem3"  （各自独立，推荐）     │
│  "${arr[*]}"  → "elem1 elem2 elem3"      （合并为一个字符串）   │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```
<!-- /DIAGRAM -->

</details>

### 4.2 遍历示例

```bash
cd ~/array-lab

cat > iterate-correct.sh << 'EOF'
#!/bin/bash

# 带空格的文件名数组
files=("My Document.txt" "Project Report.pdf" "2024 Budget.xlsx")

echo "=== 错误的遍历方式 ==="
echo "使用 \${files[@]} 不加引号："
count=0
for file in ${files[@]}; do
    ((count++))
    echo "  $count: $file"
done
echo "循环次数: $count（错误！应该是 3）"

echo ""
echo "=== 正确的遍历方式 ==="
echo "使用 \"\${files[@]}\" 加引号："
count=0
for file in "${files[@]}"; do
    ((count++))
    echo "  $count: $file"
done
echo "循环次数: $count（正确！）"
EOF

bash iterate-correct.sh
```

### 4.3 带索引的遍历

```bash
cd ~/array-lab

cat > iterate-with-index.sh << 'EOF'
#!/bin/bash

servers=("web01" "web02" "db01" "cache01")

echo "=== 带索引的遍历 ==="

# 方式 1：使用 ${!arr[@]} 获取索引
for i in "${!servers[@]}"; do
    echo "servers[$i] = ${servers[$i]}"
done

echo ""

# 方式 2：使用计数器
echo "=== 使用计数器 ==="
i=0
for server in "${servers[@]}"; do
    echo "服务器 $((i+1)): $server"
    ((i++))
done

echo ""

# 方式 3：C 风格循环
echo "=== C 风格循环 ==="
for ((i=0; i<${#servers[@]}; i++)); do
    echo "servers[$i] = ${servers[$i]}"
done
EOF

bash iterate-with-index.sh
```

### 4.4 关联数组的键值遍历

```bash
cd ~/array-lab

cat > iterate-assoc.sh << 'EOF'
#!/bin/bash

declare -A env_vars=(
    [APP_NAME]="my-application"
    [APP_ENV]="production"
    [APP_PORT]="8080"
    [APP_DEBUG]="false"
)

echo "=== 遍历关联数组 ==="

# 遍历键
echo "所有键："
for key in "${!env_vars[@]}"; do
    echo "  - $key"
done

echo ""

# 遍历键值对（最常用）
echo "键值对："
for key in "${!env_vars[@]}"; do
    echo "  export $key=\"${env_vars[$key]}\""
done

echo ""

# 检查并使用
echo "=== 生成环境配置 ==="
for key in "${!env_vars[@]}"; do
    if [[ -n "${env_vars[$key]}" ]]; then
        export "$key=${env_vars[$key]}"
        echo "已设置: $key"
    fi
done
EOF

bash iterate-assoc.sh
```

---

## Step 5 — 数组参数传递（10 分钟）

### 5.1 传递数组给函数

数组参数传递是 Shell 脚本的一个棘手问题：

```bash
cd ~/array-lab

cat > array-params.sh << 'EOF'
#!/bin/bash

# 方式 1：展开为多个参数（推荐）
function print_all() {
    echo "=== 接收到 $# 个参数 ==="
    local i=1
    for arg in "$@"; do
        echo "  参数 $i: $arg"
        ((i++))
    done
}

# 方式 2：传递数组名（使用 nameref，Bash 4.3+）
function process_array() {
    local -n arr_ref="$1"  # nameref 引用
    echo "=== 通过 nameref 访问 ==="
    echo "数组长度: ${#arr_ref[@]}"
    for item in "${arr_ref[@]}"; do
        echo "  - $item"
    done
}

# 测试
servers=("web01" "web02" "db01")

echo "=== 方式 1：展开传递 ==="
print_all "${servers[@]}"

echo ""
echo "=== 方式 2：传递数组名（Bash 4.3+）==="
process_array servers
EOF

bash array-params.sh
```

### 5.2 从函数返回数组

```bash
cd ~/array-lab

cat > array-return.sh << 'EOF'
#!/bin/bash

# 方式 1：通过标准输出返回（用换行分隔）
function get_servers() {
    echo "web01"
    echo "web02"
    echo "db01"
}

# 方式 2：通过 nameref 输出（Bash 4.3+）
function get_servers_v2() {
    local -n result="$1"
    result=("web01" "web02" "db01")
}

echo "=== 方式 1：读取输出 ==="
# 使用 mapfile/readarray 读取
mapfile -t servers1 < <(get_servers)
echo "获取到 ${#servers1[@]} 台服务器: ${servers1[@]}"

echo ""
echo "=== 方式 2：通过 nameref ==="
declare -a servers2
get_servers_v2 servers2
echo "获取到 ${#servers2[@]} 台服务器: ${servers2[@]}"
EOF

bash array-return.sh
```

---

## Step 6 — Mini Project：配置文件解析器（25 分钟）

> **项目目标**：使用关联数组解析 key=value 格式的配置文件。  

### 6.1 项目需求

创建一个配置解析器，能够：

1. 读取 `key=value` 格式的配置文件
2. 支持注释（# 开头）和空行
3. 支持值中包含 `=` 符号
4. 将配置存储在关联数组中
5. 提供查询和验证功能

### 6.2 创建示例配置文件

```bash
cd ~/array-lab

# 创建示例配置文件
cat > app.conf << 'EOF'
# Application Configuration
# 应用程序配置文件

# Server settings
APP_NAME=my-application
APP_VERSION=1.2.3
APP_ENV=production

# Database settings
DB_HOST=db.example.com
DB_PORT=5432
DB_NAME=myapp_production
DB_USER=app_user
# 注意：密码中可能包含 = 号
DB_PASSWORD=p@ss=word123

# Feature flags
FEATURE_NEW_UI=true
FEATURE_DARK_MODE=false

# Empty value example
EMPTY_VALUE=

# Logging
LOG_LEVEL=INFO
LOG_PATH=/var/log/myapp
EOF

echo "配置文件已创建: app.conf"
cat app.conf
```

### 6.3 完整实现

```bash
cd ~/array-lab

cat > config-parser.sh << 'EOF'
#!/bin/bash
# =============================================================================
# 文件名：config-parser.sh
# 功能：配置文件解析器（使用关联数组）
# 用法：./config-parser.sh <配置文件>
# =============================================================================

set -euo pipefail

# 检查 Bash 版本
if ((BASH_VERSINFO[0] < 4)); then
    echo "错误：本脚本需要 Bash 4.0+（当前: $BASH_VERSION）" >&2
    exit 1
fi

# 全局关联数组存储配置
declare -gA CONFIG

# =============================================================================
# 函数定义
# =============================================================================

# 解析配置文件
# 参数: $1 - 配置文件路径
# 返回: 0 成功, 1 失败
function parse_config() {
    local config_file="$1"
    local line_num=0
    local key value

    # 验证文件存在
    if [[ ! -f "$config_file" ]]; then
        echo "错误：配置文件不存在: $config_file" >&2
        return 1
    fi

    # 清空现有配置
    CONFIG=()

    # 逐行读取
    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_num++))

        # 去除首尾空白
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"

        # 跳过空行和注释
        [[ -z "$line" || "$line" == \#* ]] && continue

        # 解析 key=value
        if [[ "$line" =~ ^([a-zA-Z_][a-zA-Z0-9_]*)=(.*)$ ]]; then
            key="${BASH_REMATCH[1]}"
            value="${BASH_REMATCH[2]}"
            CONFIG["$key"]="$value"
        else
            echo "警告：第 $line_num 行格式无效: $line" >&2
        fi
    done < "$config_file"

    echo "已加载 ${#CONFIG[@]} 个配置项" >&2
    return 0
}

# 获取配置值
# 参数: $1 - 键名, $2 - 默认值（可选）
function config_get() {
    local key="$1"
    local default="${2:-}"

    if [[ -v CONFIG[$key] ]]; then
        echo "${CONFIG[$key]}"
    else
        echo "$default"
    fi
}

# 检查配置项是否存在
function config_has() {
    local key="$1"
    [[ -v CONFIG[$key] ]]
}

# 列出所有配置
function config_list() {
    echo "=== 当前配置（共 ${#CONFIG[@]} 项）==="
    for key in $(printf '%s\n' "${!CONFIG[@]}" | sort); do
        local value="${CONFIG[$key]}"
        # 敏感信息脱敏
        if [[ "$key" =~ PASSWORD|SECRET|KEY ]]; then
            value="********"
        fi
        printf "  %-20s = %s\n" "$key" "$value"
    done
}

# 验证必需的配置项
# 参数: $@ - 必需的键名列表
function config_validate() {
    local missing=()
    for key in "$@"; do
        if ! config_has "$key"; then
            missing+=("$key")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "错误：缺少必需的配置项: ${missing[*]}" >&2
        return 1
    fi
    return 0
}

# 导出配置为环境变量
function config_export() {
    for key in "${!CONFIG[@]}"; do
        export "$key=${CONFIG[$key]}"
    done
    echo "已导出 ${#CONFIG[@]} 个环境变量" >&2
}

# =============================================================================
# 主程序
# =============================================================================

function main() {
    local config_file="${1:-}"

    if [[ -z "$config_file" ]]; then
        echo "用法: $0 <配置文件>" >&2
        exit 1
    fi

    echo "=== 配置文件解析器 ==="
    echo ""

    # 解析配置
    parse_config "$config_file" || exit 1

    # 列出所有配置
    echo ""
    config_list

    # 演示获取单个配置
    echo ""
    echo "=== 获取单个配置 ==="
    echo "APP_NAME: $(config_get APP_NAME)"
    echo "DB_HOST: $(config_get DB_HOST)"
    echo "NOT_EXIST: $(config_get NOT_EXIST "默认值")"

    # 验证必需配置
    echo ""
    echo "=== 验证必需配置 ==="
    if config_validate APP_NAME APP_ENV DB_HOST DB_PORT; then
        echo "配置验证通过！"
    else
        echo "配置验证失败！"
    fi

    # 检查布尔配置
    echo ""
    echo "=== 检查功能开关 ==="
    if [[ "$(config_get FEATURE_NEW_UI)" == "true" ]]; then
        echo "新 UI 功能已启用"
    else
        echo "新 UI 功能未启用"
    fi
}

# 如果直接运行（不是被 source）
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
EOF

chmod +x config-parser.sh
./config-parser.sh app.conf
```

### 6.4 作为库使用

```bash
cd ~/array-lab

cat > use-config.sh << 'EOF'
#!/bin/bash
# 演示如何将 config-parser.sh 作为库使用

# 引入配置解析器
source ./config-parser.sh

# 解析配置文件
parse_config "app.conf"

# 使用配置
echo "=== 应用启动 ==="
echo "应用名称: $(config_get APP_NAME)"
echo "环境: $(config_get APP_ENV)"
echo "版本: $(config_get APP_VERSION)"

# 构建数据库连接字符串
db_conn="postgresql://$(config_get DB_USER):$(config_get DB_PASSWORD)@$(config_get DB_HOST):$(config_get DB_PORT)/$(config_get DB_NAME)"
echo ""
echo "数据库连接: postgresql://$(config_get DB_USER):******@$(config_get DB_HOST):$(config_get DB_PORT)/$(config_get DB_NAME)"

# 检查日志配置
echo ""
echo "日志级别: $(config_get LOG_LEVEL INFO)"
echo "日志路径: $(config_get LOG_PATH /tmp)"
EOF

bash use-config.sh
```

---

## 反模式：常见错误

### 错误 1：${arr[*]} 不加引号

```bash
# 错误：元素边界丢失
files=("file one.txt" "file two.txt")
for f in ${files[*]}; do
    echo "$f"    # 输出 4 次，不是 2 次！
done

# 正确：使用 "${arr[@]}"
for f in "${files[@]}"; do
    echo "$f"    # 输出 2 次
done
```

### 错误 2：忘记 declare -A

```bash
# 错误：没有 declare -A，被当作索引数组
config[host]="localhost"
config[port]="8080"
echo "${config[host]}"  # 可能是空或者奇怪的值

# 正确：显式声明关联数组
declare -A config
config[host]="localhost"
config[port]="8080"
echo "${config[host]}"  # localhost
```

### 错误 3：在 sh 中使用数组

```bash
#!/bin/sh
# 错误：sh 不支持数组！
arr=(a b c)    # 语法错误

# 正确：使用 #!/bin/bash 或检查兼容性
#!/bin/bash
arr=(a b c)    # OK
```

### 错误 4：负数索引前忘记空格

```bash
arr=(a b c d e)

# 错误：会被解析为默认值语法
echo "${arr[@]:-3}"    # 错误！

# 正确：负数前加空格
echo "${arr[@]: -3}"   # d e（最后 3 个）
```

---

## 职场小贴士（Japan IT Context）

### 数组在运维中的应用

在日本 IT 企业，数组常用于以下场景：

| 日语术语 | 含义 | 使用场景 |
|----------|------|----------|
| サーバーリスト | 服务器列表 | 批量操作多台服务器 |
| 設定値 | 配置值 | 关联数组存储配置 |
| バッチ処理 | 批处理 | 处理文件列表 |
| パラメータ管理 | 参数管理 | 命令行参数收集 |

### 日本企业的配置管理

```bash
#!/bin/bash
# ==============================================================================
# ファイル名：server_check.sh
# 概要：複数サーバーの一括ヘルスチェック
# 作成者：山田太郎
# ==============================================================================

# サーバーリスト
declare -a SERVERS=(
    "web01.example.jp"
    "web02.example.jp"
    "db01.example.jp"
    "cache01.example.jp"
)

# 各サーバーをチェック
for server in "${SERVERS[@]}"; do
    echo "Checking: $server"
    if ping -c 1 -W 2 "$server" &>/dev/null; then
        echo "  [OK] $server is reachable"
    else
        echo "  [NG] $server is unreachable"
    fi
done
```

### 障害対応での使用例

```bash
#!/bin/bash
# 障害発生時のログ収集スクリプト

# 収集対象サーバー（関連システム）
declare -A SYSTEMS=(
    [web]="web01.example.jp"
    [app]="app01.example.jp"
    [db]="db01.example.jp"
    [cache]="cache01.example.jp"
)

# ログ収集先
LOG_DIR="/var/log/incident/$(date +%Y%m%d_%H%M%S)"
mkdir -p "$LOG_DIR"

# 各システムからログ収集
for system in "${!SYSTEMS[@]}"; do
    host="${SYSTEMS[$system]}"
    echo "Collecting logs from $system ($host)..."
    ssh "$host" "journalctl -n 1000" > "$LOG_DIR/${system}.log" 2>&1 || \
        echo "  [WARN] Failed to collect from $system"
done

echo "Logs collected in: $LOG_DIR"
```

---

## 检查清单

完成本课后，你应该能够：

- [ ] 创建和使用索引数组 `arr=(a b c)`
- [ ] 访问数组元素 `${arr[0]}`, `${arr[@]}`, `${#arr[@]}`
- [ ] 使用数组切片 `${arr[@]:start:count}`
- [ ] 添加、删除、修改数组元素
- [ ] 使用 `declare -A` 创建关联数组
- [ ] 遍历关联数组的键和值
- [ ] 正确使用引号遍历数组 `"${arr[@]}"`
- [ ] 区分 `${arr[@]}` 和 `${arr[*]}`
- [ ] 传递数组给函数
- [ ] 使用关联数组解析配置文件

**验证命令：**

```bash
cd ~/array-lab

# 测试 1: 索引数组
bash -c 'arr=(a b c); echo ${#arr[@]}'
# 预期: 3

# 测试 2: 关联数组
bash -c 'declare -A m; m[k]=v; echo ${m[k]}'
# 预期: v

# 测试 3: 正确遍历
bash -c 'arr=("a b" "c d"); for i in "${arr[@]}"; do echo "[$i]"; done'
# 预期: [a b] 和 [c d] 各一行

# 测试 4: 配置解析器
./config-parser.sh app.conf | grep -q "APP_NAME"
echo "配置解析器: $([[ $? -eq 0 ]] && echo "OK" || echo "FAIL")"
```

---

## 本课小结

| 概念 | 语法/要点 |
|------|-----------|
| 索引数组创建 | `arr=(a b c)` 或 `arr[0]=a` |
| 关联数组创建 | `declare -A map; map[key]=value` |
| 访问单个元素 | `${arr[0]}`, `${map[key]}` |
| 所有元素 | `${arr[@]}`（推荐）或 `${arr[*]}` |
| 元素个数 | `${#arr[@]}` |
| 所有索引/键 | `${!arr[@]}` |
| 数组切片 | `${arr[@]:start:count}` |
| 追加元素 | `arr+=(new)` |
| 删除元素 | `unset 'arr[index]'` |
| 遍历黄金法则 | 永远用 `"${arr[@]}"` 带引号 |

---

## 面试准备

### **配列の全要素を正しく展開する方法は？**

`"${arr[@]}"` を使います。ダブルクォートで囲むことで、スペースを含む要素も正しく個別に処理されます。

```bash
files=("file one.txt" "file two.txt")

# 間違い：スペースで分割される
for f in ${files[@]}; do echo "$f"; done  # 4回ループ

# 正解：各要素が保持される
for f in "${files[@]}"; do echo "$f"; done  # 2回ループ
```

### **連想配列を作成するには？**

`declare -A` で宣言してから、キーと値を設定します。Bash 4.0 以上が必要です。

```bash
declare -A config
config[host]="localhost"
config[port]="8080"

# または一括で
declare -A config=(
    [host]="localhost"
    [port]="8080"
)

echo "${config[host]}"  # localhost
```

---

## 延伸阅读

- [Bash Arrays](https://www.gnu.org/software/bash/manual/html_node/Arrays.html) - GNU Bash 官方文档
- [Associative Arrays](https://wiki.bash-hackers.org/syntax/arrays#associative_arrays) - Bash Hackers Wiki
- 上一课：[06 - 函数](../06-functions/) — 函数定义与复用
- 下一课：[08 - 参数展开](../08-expansion/) — 强大的字符串处理

---

## 清理

```bash
# 清理练习文件
cd ~
rm -rf ~/array-lab
```

---

## 系列导航

[<-- 06 - 函数](../06-functions/) | [课程首页](../) | [08 - 参数展开 -->](../08-expansion/)
