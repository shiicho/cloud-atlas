# 05 · sed 文本转换（sed Text Transformation）

> **目标**：掌握 sed 流编辑器，实现文本替换、删除和匿名化处理  
> **前置**：[04 · 用于 grep 和 sed 的正则表达式](../04-regular-expressions/)  
> **时间**：⚡ 20 分钟（速读）/ 🔬 75 分钟（完整实操）  
> **实战项目**：日志匿名化（为外部厂商准备合规数据）  

---

## 先跑起来

> 不需要理解，先体验 sed 的威力。  

```bash
# 创建练习目录
mkdir -p ~/sed-lab && cd ~/sed-lab

# 创建测试文件
cat > sample.log << 'EOF'
2026-01-04 10:23:45 [INFO] User admin logged in from 192.168.1.100
2026-01-04 10:24:01 [ERROR] Connection failed from 10.0.2.50
2026-01-04 10:24:15 [INFO] User tanaka logged in from 172.16.0.25
2026-01-04 10:25:00 [WARNING] Password attempt for root from 203.0.113.42
2026-01-04 10:25:30 [INFO] Config path: /etc/app/config.yaml
EOF

# 魔法 1: 把所有 ERROR 改成 CRITICAL
sed 's/ERROR/CRITICAL/' sample.log

# 魔法 2: 隐藏所有 IP 地址
sed -E 's/[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/xxx.xxx.xxx.xxx/g' sample.log

# 魔法 3: 只显示包含 ERROR 或 WARNING 的行
sed -n '/ERROR\|WARNING/p' sample.log

# 魔法 4: 删除所有包含 password 的行（不区分大小写）
sed '/[Pp]assword/d' sample.log
```

你刚刚用 sed 完成了：
- 文本替换（置換）
- 数据脱敏（マスキング）
- 行过滤和删除

这些都是日志处理和运维监控的核心技能。现在让我们系统学习！

---

## 核心概念

### sed 是什么？

sed（Stream Editor）是一个流编辑器。它逐行读取输入，对每行应用编辑命令，然后输出结果。

![sed Processing Flow](images/sed-processing-flow.png)

<details>
<summary>View ASCII source</summary>

```
┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│  输入文件     │────▶│    sed       │────▶│   stdout     │
│  (stdin)     │     │  (逐行处理)   │     │  (输出结果)   │
└──────────────┘     └──────────────┘     └──────────────┘
                            │
                            │ 不修改原文件
                            │ （除非使用 -i）
                            ▼
                     ┌──────────────┐
                     │  原文件不变   │
                     └──────────────┘
```

</details>

**关键特性**：
- 默认输出到 stdout，原文件不变
- 支持正则表达式
- 可以组合多个编辑命令

---

## 基础替换 s/old/new/

### 基本语法

```bash
sed 's/old/new/' file       # 替换每行第一个匹配
sed 's/old/new/g' file      # 替换每行所有匹配（global）
sed 's/old/new/i' file      # 不区分大小写（case insensitive）
sed 's/old/new/gi' file     # 全局 + 不区分大小写
```

### 实际演示

```bash
cd ~/sed-lab

# 创建测试文件
echo "hello world, hello universe" > test.txt

# 只替换第一个 hello
sed 's/hello/HELLO/' test.txt
# 输出: HELLO world, hello universe

# 替换所有 hello（g = global）
sed 's/hello/HELLO/g' test.txt
# 输出: HELLO world, HELLO universe

# 不区分大小写替换
echo "Hello HELLO hello" | sed 's/hello/hi/gi'
# 输出: hi hi hi
```

### 常用标志

| 标志 | 含义 | 示例 |
|------|------|------|
| `g` | 全局替换（每行所有匹配） | `s/a/b/g` |
| `i` | 不区分大小写 | `s/error/ERROR/i` |
| `p` | 打印匹配行（配合 -n） | `s/error/ERROR/p` |
| `2` | 只替换第 2 个匹配 | `s/a/b/2` |

---

## 替代分隔符

当模式中包含 `/` 时，用其他分隔符更清晰：

```bash
# 问题：路径中有很多 /，需要转义
sed 's/\/etc\/app\/config/\/opt\/app\/config/' file

# 解决：使用 # 或 | 作为分隔符
sed 's#/etc/app/config#/opt/app/config#' file
sed 's|/etc/app/config|/opt/app/config|' file
```

**实际演示**：

```bash
# 修改配置文件路径
echo "config_path=/etc/app/config.yaml" > config.txt

# 使用 # 分隔符（更清晰）
sed 's#/etc/app#/opt/myapp#g' config.txt
# 输出: config_path=/opt/myapp/config.yaml

# 使用 | 分隔符
sed 's|/etc/app|/opt/myapp|g' config.txt
# 输出: config_path=/opt/myapp/config.yaml
```

> **最佳实践**：当模式包含 `/` 时，始终使用替代分隔符。`#` 和 `|` 最常用。  

---

## 地址范围（Address Ranges）

sed 可以只对特定行进行操作：

### 按行号

```bash
sed '5s/old/new/'           # 只处理第 5 行
sed '5,10s/old/new/'        # 处理第 5-10 行
sed '5,$s/old/new/'         # 从第 5 行到文件末尾
```

### 按模式匹配

```bash
sed '/ERROR/s/old/new/'     # 只处理包含 ERROR 的行
sed '/start/,/end/s/a/b/'   # 从匹配 start 到匹配 end 之间的行
```

### 实际演示

```bash
cd ~/sed-lab

# 创建测试文件
cat > server.log << 'EOF'
[SERVER1] status: running
[SERVER1] load: 0.5
[SERVER2] status: stopped
[SERVER2] load: 0.0
[SERVER3] status: running
[SERVER3] load: 1.2
EOF

# 只修改第 3 行
sed '3s/stopped/STOPPED/' server.log

# 修改第 3-4 行
sed '3,4s/SERVER2/BACKUP/' server.log

# 只修改包含 running 的行
sed '/running/s/status/STATE/' server.log

# 从 SERVER2 到 SERVER3 之间的行
sed '/SERVER2/,/SERVER3/s/load/LOAD/' server.log
```

---

## 行操作命令

### d - 删除行

```bash
sed '5d' file               # 删除第 5 行
sed '5,10d' file            # 删除第 5-10 行
sed '/pattern/d' file       # 删除匹配行
sed '/^$/d' file            # 删除空行
sed '/^#/d' file            # 删除注释行
```

### p - 打印行（配合 -n）

```bash
sed -n '5p' file            # 只打印第 5 行
sed -n '5,10p' file         # 只打印第 5-10 行
sed -n '/ERROR/p' file      # 只打印匹配行（等同于 grep）
```

### i\ 和 a\ - 插入和追加

```bash
sed '1i\# Header line' file        # 在第 1 行前插入
sed '$a\# Footer line' file        # 在最后一行后追加
sed '/ERROR/a\# 需要检查!' file    # 在匹配行后追加
```

### 实际演示

```bash
cd ~/sed-lab

# 删除空行和注释
cat > config.txt << 'EOF'
# Database settings
db_host=localhost

# Port configuration
db_port=5432

# Empty line above
EOF

# 删除注释行
sed '/^#/d' config.txt

# 删除空行
sed '/^$/d' config.txt

# 同时删除注释和空行
sed '/^#/d; /^$/d' config.txt

# 只显示非注释、非空行（等同于上面）
sed -n '/^[^#]/p' config.txt | sed '/^$/d'
```

---

## 安全的就地编辑（In-Place Editing）

### 危险操作：sed -i

```bash
# 直接修改原文件（危险！无备份！）
sed -i 's/old/new/g' file

# 如果命令写错，数据就丢了！
```

### 安全操作：sed -i.bak

```bash
# 创建备份后再修改（推荐！）
sed -i.bak 's/old/new/g' file

# 结果：
# - file      → 修改后的文件
# - file.bak  → 原始文件备份
```

### macOS 注意事项

```bash
# macOS 的 sed -i 需要显式指定备份扩展名
sed -i '' 's/old/new/g' file      # 无备份（危险）
sed -i '.bak' 's/old/new/g' file  # 有备份（安全）

# Linux 的 sed
sed -i 's/old/new/g' file         # 无备份
sed -i.bak 's/old/new/g' file     # 有备份
```

### 实际演示

```bash
cd ~/sed-lab

# 创建测试文件
echo "original content" > important.txt
cat important.txt

# 安全修改（带备份）
sed -i.bak 's/original/modified/' important.txt

# 检查结果
echo "=== 修改后 ==="
cat important.txt
echo "=== 备份文件 ==="
cat important.txt.bak

# 如果出错，可以恢复
# cp important.txt.bak important.txt
```

> **黄金法则**：永远使用 `sed -i.bak`，不要使用裸 `sed -i`！  

---

## 实战项目：日志匿名化

### 场景

> 你的公司需要将日志文件发送给外部厂商（外部ベンダー）进行分析，但日志中包含敏感信息（IP 地址、用户名、服务器名）。需要进行数据脱敏（マスキング）处理。  

### 准备测试数据

```bash
cd ~/sed-lab

# 创建模拟的生产日志
cat > production.log << 'EOF'
2026-01-04 09:00:01 [INFO] server-web-01 User tanaka logged in from 192.168.1.100
2026-01-04 09:00:15 [INFO] server-web-01 User suzuki logged in from 10.0.2.50
2026-01-04 09:01:00 [ERROR] server-db-01 Connection timeout from 172.16.0.25
2026-01-04 09:01:30 [WARNING] server-web-02 Password attempt for admin from 203.0.113.42
2026-01-04 09:02:00 [INFO] server-api-01 API key ak_live_12345 used by tanaka
2026-01-04 09:02:15 [ERROR] server-db-01 Query failed: SELECT * FROM users WHERE name='yamada'
2026-01-04 09:03:00 [INFO] server-web-01 Session token: eyJhbGciOiJIUzI1NiJ9.eyJ1c2VyIjoidGFuYWthIn0
2026-01-04 09:03:30 [INFO] server-web-02 Email notification sent to tanaka@company.co.jp
EOF

echo "原始日志已创建: production.log"
```

### Step 1：IP 地址匿名化

```bash
# 将所有 IP 地址替换为 x.x.x.x
sed -E 's/[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/x.x.x.x/g' production.log
```

### Step 2：用户名匿名化

```bash
# 替换已知用户名
sed -e 's/tanaka/USER_A/g' \
    -e 's/suzuki/USER_B/g' \
    -e 's/yamada/USER_C/g' \
    production.log
```

### Step 3：服务器名匿名化

```bash
# 替换服务器名
sed -E 's/server-[a-z]+-[0-9]+/SERVER_XX/g' production.log
```

### Step 4：敏感数据删除

```bash
# 删除包含密码、API key、token 的行
sed -E '/[Pp]assword|api_key|token|API key/d' production.log
```

### Step 5：邮箱地址匿名化

```bash
# 替换邮箱地址
sed -E 's/[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}/EMAIL_REDACTED/g' production.log
```

### 完整匿名化脚本

```bash
cat > ~/sed-lab/anonymize.sh << 'EOF'
#!/bin/bash
# 日志匿名化脚本 - Log Anonymization Script
# 用于准备发送给外部厂商的日志（外部ベンダー共有用）

set -euo pipefail

# 输入验证
input_file="${1:-}"
if [[ -z "$input_file" || ! -f "$input_file" ]]; then
    echo "Usage: $0 <log_file>"
    exit 1
fi

# 输出文件名
output_file="${input_file%.log}_anonymized.log"

# 匿名化处理
sed -E \
    -e 's/[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/x.x.x.x/g' \
    -e 's/server-[a-z]+-[0-9]+/SERVER_XX/g' \
    -e 's/[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}/EMAIL_REDACTED/g' \
    -e 's/ak_live_[a-zA-Z0-9]+/API_KEY_REDACTED/g' \
    -e 's/eyJ[a-zA-Z0-9._-]+/TOKEN_REDACTED/g' \
    -e '/[Pp]assword/d' \
    "$input_file" > "$output_file"

echo "匿名化完成: $output_file"
echo ""
echo "=== 处理统计 ==="
echo "原始行数: $(wc -l < "$input_file")"
echo "处理后行数: $(wc -l < "$output_file")"
echo ""
echo "=== 匿名化结果预览 ==="
head -10 "$output_file"
EOF

chmod +x ~/sed-lab/anonymize.sh
```

### 运行脚本

```bash
cd ~/sed-lab
./anonymize.sh production.log
```

**预期输出**：

```
匿名化完成: production_anonymized.log

=== 处理统计 ===
原始行数: 8
处理后行数: 7

=== 匿名化结果预览 ===
2026-01-04 09:00:01 [INFO] SERVER_XX User tanaka logged in from x.x.x.x
2026-01-04 09:00:15 [INFO] SERVER_XX User suzuki logged in from x.x.x.x
2026-01-04 09:01:00 [ERROR] SERVER_XX Connection timeout from x.x.x.x
2026-01-04 09:02:00 [INFO] SERVER_XX API key API_KEY_REDACTED used by tanaka
2026-01-04 09:02:15 [ERROR] SERVER_XX Query failed: SELECT * FROM users WHERE name='yamada'
2026-01-04 09:03:00 [INFO] SERVER_XX Session token: TOKEN_REDACTED
2026-01-04 09:03:30 [INFO] SERVER_XX Email notification sent to EMAIL_REDACTED
```

> **注意**：用户名替换取决于你是否有完整的用户名列表。实际场景中可能需要更复杂的处理。  

---

## 职场小贴士

### 日本 IT 公司常见场景

| 日语术语 | 含义 | sed 应用 |
|----------|------|----------|
| 置換（ちかん） | 替换 | `s/old/new/g` |
| マスキング | 数据脱敏 | IP、用户名匿名化 |
| 外部ベンダー共有 | 发送给外部厂商 | 日志匿名化处理 |
| 個人情報保護 | 个人信息保护 | 删除/替换敏感数据 |

### 运维中的 sed 使用场景

1. **配置文件批量修改**
   ```bash
   # 修改所有服务器的配置
   sed -i.bak 's/old_server/new_server/g' /etc/app/*.conf
   ```

2. **日志清理**
   ```bash
   # 删除调试日志行
   sed -i.bak '/\[DEBUG\]/d' app.log
   ```

3. **数据格式转换**
   ```bash
   # CSV 分隔符转换
   sed 's/,/\t/g' data.csv > data.tsv
   ```

4. **紧急修复**
   ```bash
   # 快速修复配置错误
   sed -i.bak 's/wrong_value/correct_value/' /etc/app/config
   systemctl restart app
   ```

---

## 现代替代工具：sd

`sd` 是 sed 的现代替代品，语法更简单：

```bash
# 安装
# macOS: brew install sd
# Linux: cargo install sd

# 基本替换（不需要复杂的转义）
sd 'old' 'new' file

# 正则替换（默认使用 Rust regex）
sd '\d+\.\d+\.\d+\.\d+' 'x.x.x.x' file

# 就地修改（自动创建备份）
sd -i 'old' 'new' file
```

**sed vs sd 对比**：

| 操作 | sed | sd |
|------|-----|-----|
| 简单替换 | `sed 's/old/new/g'` | `sd 'old' 'new'` |
| 路径替换 | `sed 's#/a/b#/c/d#g'` | `sd '/a/b' '/c/d'` |
| 正则 | 需要考虑 BRE/ERE | 默认现代 regex |
| 就地修改 | `-i.bak`（需显式备份） | `-i`（更安全默认） |

> **建议**：sed 是标准工具，必须掌握。sd 可以作为日常使用的快捷方式。  

---

## 反面模式（Anti-Patterns）

### 1. sed -i 不带备份

```bash
# 危险！
sed -i 's/old/new/g' important_file

# 正确做法
sed -i.bak 's/old/new/g' important_file
```

### 2. 过于复杂的 sed 脚本

```bash
# 难以阅读和维护
sed -e 's/a/b/g' -e 's/c/d/g' -e '/pattern/d' -e '1,10s/x/y/' file

# 如果逻辑复杂，改用 awk 或 Python
awk '
    /pattern/ { next }
    NR <= 10 { gsub(/x/, "y") }
    { gsub(/a/, "b"); gsub(/c/, "d"); print }
' file
```

### 3. 用 sed 处理结构化数据

```bash
# 不推荐：用 sed 解析 JSON
sed 's/.*"name":"\([^"]*\)".*/\1/' data.json

# 正确做法：用 jq
jq -r '.name' data.json
```

### 4. 忘记转义特殊字符

```bash
# 错误：. 是正则的任意字符
sed 's/192.168.1.1/x.x.x.x/' file    # 会匹配 192a168b1c1

# 正确：转义点号
sed 's/192\.168\.1\.1/x.x.x.x/' file
```

---

## 动手练习

### 练习 1：基础替换

```bash
# 创建测试文件
cat > ~/sed-lab/exercise1.txt << 'EOF'
The quick brown fox jumps over the lazy dog.
The fox is quick and brown.
EOF

# 任务：
# 1. 把所有 fox 替换成 cat
# 2. 把所有 the 替换成 THE（不区分大小写）
# 3. 只替换第一行的 quick

# 你的答案：
# sed 's/fox/cat/g' ~/sed-lab/exercise1.txt
# sed 's/the/THE/gi' ~/sed-lab/exercise1.txt
# sed '1s/quick/QUICK/' ~/sed-lab/exercise1.txt
```

### 练习 2：删除和过滤

```bash
# 创建测试文件
cat > ~/sed-lab/exercise2.txt << 'EOF'
# Configuration file
# Created: 2026-01-04

server_name=web01
server_port=8080

# Database settings
db_host=localhost
db_port=5432
EOF

# 任务：
# 1. 删除所有注释行（以 # 开头）
# 2. 删除所有空行
# 3. 只显示包含 server 的行

# 你的答案：
# sed '/^#/d' ~/sed-lab/exercise2.txt
# sed '/^$/d' ~/sed-lab/exercise2.txt
# sed -n '/server/p' ~/sed-lab/exercise2.txt
```

### 练习 3：安全就地编辑

```bash
# 创建测试文件
echo "environment=development" > ~/sed-lab/exercise3.txt

# 任务：
# 1. 用 sed -i.bak 将 development 改为 production
# 2. 验证修改成功
# 3. 验证备份文件存在

# 你的答案：
# sed -i.bak 's/development/production/' ~/sed-lab/exercise3.txt
# cat ~/sed-lab/exercise3.txt
# cat ~/sed-lab/exercise3.txt.bak
```

---

## 检查清单

完成本课后，你应该能够：

- [ ] 使用 `s/old/new/` 进行基本替换
- [ ] 理解 `g`、`i` 标志的含义
- [ ] 使用替代分隔符处理包含 `/` 的模式
- [ ] 使用行号和模式指定地址范围
- [ ] 使用 `d` 删除行、`p` 打印行
- [ ] **始终使用 `sed -i.bak` 而不是裸 `sed -i`**
- [ ] 完成日志匿名化脚本
- [ ] 理解 sed 的局限性（何时应该用 awk）

---

## 快速参考

```bash
# 替换
sed 's/old/new/'          # 替换每行第一个
sed 's/old/new/g'         # 替换所有
sed 's/old/new/gi'        # 全局 + 不区分大小写

# 替代分隔符
sed 's#/old/path#/new/path#g'

# 地址范围
sed '5s/old/new/'         # 第 5 行
sed '5,10s/old/new/'      # 第 5-10 行
sed '/ERROR/s/old/new/'   # 包含 ERROR 的行

# 行操作
sed '/pattern/d'          # 删除匹配行
sed -n '/pattern/p'       # 只打印匹配行
sed '/^$/d'               # 删除空行
sed '/^#/d'               # 删除注释行

# 安全就地编辑
sed -i.bak 's/old/new/g' file
```

---

## 延伸阅读

- **官方文档**: [GNU sed Manual](https://www.gnu.org/software/sed/manual/sed.html)
- **现代替代**: [sd - Intuitive find & replace](https://github.com/chmln/sd)
- **下一课**: [06 · awk 字段处理](../06-awk-fields/) - 处理结构化数据

---

## 系列导航

| 课程 | 主题 |
|------|------|
| [01 · 管道和重定向](../01-pipes-redirection/) | stdin/stdout/stderr |
| [02 · 查看和流式处理文件](../02-viewing-files/) | cat/less/head/tail |
| [03 · grep 基础](../03-grep-fundamentals/) | 模式搜索 |
| [04 · 正则表达式](../04-regular-expressions/) | BRE/ERE |
| **05 · sed 文本转换** | 当前课程 |
| [06 · awk 字段处理](../06-awk-fields/) | 字段提取 |
| [07 · awk 程序和聚合](../07-awk-programs/) | 数据分析 |
| [08 · 排序、去重和字段提取](../08-sorting-uniqueness/) | sort/uniq/cut |
| [09 · 使用 find 和 xargs 查找文件](../09-find-xargs/) | 文件查找 |
| [10 · 综合项目：日志分析管道](../10-capstone-pipeline/) | 实战项目 |
