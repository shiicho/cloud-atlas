# 08 - 排序、去重和字段提取

> **目标**：掌握 sort、uniq、cut 命令，实现日志频率分析和趋势识别  
> **前置**：已完成 [07 - awk 程序和聚合](../07-awk-programs/)  
> **时间**：90 分钟  
> **实战项目**：频率分析 - 找出 Top 错误、最活跃 IP、重复问题  

---

## 先跑起来（5 分钟）

> 在学习理论之前，先体验这些工具组合的威力！  

### 创建练习环境

```bash
# 创建练习目录
mkdir -p ~/sort-lab && cd ~/sort-lab

# 创建模拟访问日志
cat > access.log << 'EOF'
192.168.1.100 GET /api/users 200 45ms
10.0.0.50 POST /api/login 200 120ms
192.168.1.100 GET /api/orders 500 2300ms
172.16.0.25 GET /api/products 200 89ms
10.0.0.50 GET /api/users 200 52ms
192.168.1.100 GET /api/orders 504 30000ms
192.168.1.101 GET /health 200 5ms
10.0.0.50 POST /api/login 401 35ms
192.168.1.100 GET /api/users 200 48ms
172.16.0.25 GET /api/products 200 91ms
10.0.0.50 GET /api/orders 200 156ms
192.168.1.100 GET /api/orders 200 145ms
10.0.0.50 POST /api/login 200 118ms
192.168.1.101 GET /health 200 6ms
192.168.1.100 GET /api/users 500 1500ms
EOF

# 创建错误日志
cat > errors.log << 'EOF'
2026-01-04 09:00:01 ERROR Database connection timeout
2026-01-04 09:01:15 ERROR Authentication failed
2026-01-04 09:02:30 ERROR Database connection timeout
2026-01-04 09:03:45 ERROR File not found: /tmp/cache
2026-01-04 09:05:00 ERROR Database connection timeout
2026-01-04 09:06:22 ERROR Authentication failed
2026-01-04 09:07:33 ERROR Memory allocation failed
2026-01-04 09:08:10 ERROR Database connection timeout
2026-01-04 09:09:55 ERROR File not found: /tmp/cache
2026-01-04 09:10:30 ERROR Database connection timeout
EOF
```

### 立即体验

```bash
cd ~/sort-lab

# 魔法 1: 找出最活跃的 IP（请求最多的前 3 个）
cut -d' ' -f1 access.log | sort | uniq -c | sort -rn | head -3

# 魔法 2: 找出最常见的错误类型
cut -d' ' -f5- errors.log | sort | uniq -c | sort -rn

# 魔法 3: 找出有多少个不同的 IP 访问过
cut -d' ' -f1 access.log | sort -u | wc -l

# 魔法 4: 按响应时间排序，找出最慢的请求
sort -t' ' -k5 -h access.log | tail -3
```

**观察输出**：

```
# 最活跃 IP:
      6 192.168.1.100
      5 10.0.0.50
      2 172.16.0.25

# 最常见错误:
      5 Database connection timeout
      2 Authentication failed
      2 File not found: /tmp/cache
      1 Memory allocation failed

# 不同 IP 数量:
4

# 最慢请求:
192.168.1.100 GET /api/users 500 1500ms
192.168.1.100 GET /api/orders 500 2300ms
192.168.1.100 GET /api/orders 504 30000ms
```

你刚刚完成了日志频率分析！这是运维监控（運用監視）和故障趋势分析（障害傾向分析）的核心技能。

---

## 核心概念

### 为什么需要这些工具？

在日志分析中，最常见的问题是：

- 哪个 IP 请求最多？（可能是攻击或异常）
- 哪种错误出现最频繁？（需要优先修复）
- 有多少不同的用户/IP/错误类型？

这些问题都需要 **排序** 和 **去重** 操作。

![sort-uniq-pipeline](images/sort-uniq-pipeline.png)

<details>
<summary>View ASCII source</summary>

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│  原始数据    │────▶│    sort     │────▶│    uniq     │
│  (未排序)    │     │  (排序)     │     │  (去重计数)  │
└─────────────┘     └─────────────┘     └─────────────┘
                                               │
                                               ▼
                    ┌─────────────┐     ┌─────────────┐
                    │   head/tail │◀────│  sort -rn   │
                    │  (取 Top N) │     │  (按数量排序)│
                    └─────────────┘     └─────────────┘
```

</details>

---

## sort 命令详解

### 基本用法

```bash
sort file           # 按字母顺序排序
sort -n file        # 按数字排序
sort -r file        # 逆序
sort -u file        # 排序并去重（等于 sort | uniq）
```

### 常用选项

| 选项 | 含义 | 示例 |
|------|------|------|
| `-n` | 数字排序 | `sort -n numbers.txt` |
| `-r` | 逆序（从大到小） | `sort -rn numbers.txt` |
| `-k N` | 按第 N 个字段排序 | `sort -k2 data.txt` |
| `-t 'X'` | 指定分隔符为 X | `sort -t',' -k2 data.csv` |
| `-u` | 去重（unique） | `sort -u file` |
| `-h` | 人类可读数字（1K, 2M） | `sort -h sizes.txt` |

### 实际演示

```bash
cd ~/sort-lab

# 创建测试数据
cat > numbers.txt << 'EOF'
10
2
100
25
5
EOF

# 字母排序 vs 数字排序
echo "=== 字母排序（错误！）==="
sort numbers.txt
# 输出: 10, 100, 2, 25, 5  (按字符比较：'1' < '2')

echo "=== 数字排序（正确！）==="
sort -n numbers.txt
# 输出: 2, 5, 10, 25, 100
```

> **重要**：处理数字时一定要加 `-n`，否则 "10" 会排在 "2" 前面！  

### 按字段排序

```bash
cd ~/sort-lab

# 按第 5 列（响应时间）排序
sort -k5 access.log

# 按第 4 列（状态码）数字排序
sort -t' ' -k4 -n access.log

# 只按状态码排序（不包含后续字段）
sort -t' ' -k4,4 -n access.log
```

### sort -k 的陷阱

```bash
# 创建测试数据
cat > scores.txt << 'EOF'
Alice 85 90
Bob 90 75
Carol 85 95
EOF

# 错误用法：sort -k2 会从第 2 字段排到行尾
sort -k2 scores.txt
# Alice 和 Carol 都是 85，但后面的数字也参与比较

# 正确用法：sort -k2,2 只按第 2 字段
sort -k2,2 -n scores.txt
```

> **关键**：`-k2` 意思是「从第 2 字段到行尾」，`-k2,2` 才是「只按第 2 字段」。  

### 人类可读数字排序

```bash
# 创建文件大小数据
cat > sizes.txt << 'EOF'
512K
2M
100K
1G
50M
EOF

# 普通数字排序（错误！）
sort -n sizes.txt
# 不能正确处理 K, M, G

# 人类可读排序（正确！）
sort -h sizes.txt
# 输出: 100K, 512K, 2M, 50M, 1G
```

---

## uniq 命令详解

### 核心原则（最重要！）

> **uniq 只能去除相邻的重复行！** 这是最常见的错误。  

```bash
cd ~/sort-lab

# 创建测试数据
cat > colors.txt << 'EOF'
red
blue
red
green
blue
red
EOF

# 错误用法：直接 uniq
echo "=== 直接 uniq（错误！）==="
uniq colors.txt
# 输出: red, blue, red, green, blue, red
# 没有去重！因为重复的行不相邻

# 正确用法：先 sort 再 uniq
echo "=== sort | uniq（正确！）==="
sort colors.txt | uniq
# 输出: blue, green, red
```

![uniq-adjacent-only](images/uniq-adjacent-only.png)

<details>
<summary>View ASCII source</summary>

```
原始文件:           直接 uniq:          sort | uniq:
┌─────────┐        ┌─────────┐         ┌─────────┐
│  red    │        │  red    │  ─────▶ │  blue   │
│  blue   │  ────▶ │  blue   │         │  green  │
│  red    │        │  red    │ 相邻    │  red    │
│  green  │        │  green  │ 才去重   └─────────┘
│  blue   │        │  blue   │
│  red    │        │  red    │
└─────────┘        └─────────┘
                   没有效果！
```

</details>

### 常用选项

| 选项 | 含义 | 用途 |
|------|------|------|
| `-c` | 统计每行出现次数 | 频率分析 |
| `-d` | 只显示重复的行 | 找重复项 |
| `-u` | 只显示不重复的行 | 找唯一项 |

### 频率分析标准模式

```bash
# 统计频率的标准管道
sort file | uniq -c | sort -rn | head -10
```

这个模式的含义：
1. `sort` - 把相同的行排在一起
2. `uniq -c` - 统计每行出现次数
3. `sort -rn` - 按数量从大到小排序
4. `head -10` - 取前 10 个

```bash
cd ~/sort-lab

# 统计 IP 出现频率
cut -d' ' -f1 access.log | sort | uniq -c | sort -rn

# 输出:
#       6 192.168.1.100
#       5 10.0.0.50
#       2 172.16.0.25
#       2 192.168.1.101
```

### uniq -d 和 uniq -u

```bash
# 准备数据
cat > users.txt << 'EOF'
alice
bob
alice
carol
bob
bob
EOF

# 找出重复的用户（出现 2 次以上）
sort users.txt | uniq -d
# 输出: alice, bob

# 找出只出现一次的用户
sort users.txt | uniq -u
# 输出: carol

# 统计重复用户的出现次数
sort users.txt | uniq -dc
# 输出:
#       2 alice
#       3 bob
```

---

## cut 命令详解

### 基本用法

```bash
cut -d'分隔符' -f字段号 file
cut -c字符位置 file
```

### 常用选项

| 选项 | 含义 | 示例 |
|------|------|------|
| `-d ','` | 指定分隔符为逗号 | `cut -d',' -f1 data.csv` |
| `-f1` | 取第 1 个字段 | `cut -d' ' -f1 file` |
| `-f1,3` | 取第 1 和第 3 个字段 | `cut -d' ' -f1,3 file` |
| `-f1-3` | 取第 1 到第 3 个字段 | `cut -d' ' -f1-3 file` |
| `-c1-10` | 取第 1-10 个字符 | `cut -c1-10 file` |

### 实际演示

```bash
cd ~/sort-lab

# 从访问日志提取 IP
cut -d' ' -f1 access.log

# 提取 IP 和状态码
cut -d' ' -f1,4 access.log

# 从 /etc/passwd 提取用户名
cut -d':' -f1 /etc/passwd | head -5

# 提取用户名和 shell
cut -d':' -f1,7 /etc/passwd | head -5
```

### cut 的局限性

> **cut 不能处理可变宽度的空白分隔符！**  

```bash
# 创建有多个空格的数据
cat > spaces.txt << 'EOF'
Alice    85
Bob      90
Carol    95
EOF

# cut 把每个空格都当作分隔符（错误！）
cut -d' ' -f2 spaces.txt
# 输出: 空（因为第 2 个"字段"是空格）

# 正确做法：使用 awk
awk '{print $2}' spaces.txt
# 输出: 85, 90, 95
```

> **规则**：固定分隔符（如 `:`, `,`, `|`）用 cut，可变空白用 awk。  

---

## paste 和 join：文件合并

### paste - 并列合并

```bash
cd ~/sort-lab

# 创建两个文件
cat > names.txt << 'EOF'
Alice
Bob
Carol
EOF

cat > scores.txt << 'EOF'
85
90
95
EOF

# 并列合并（默认用 Tab 分隔）
paste names.txt scores.txt
# 输出:
# Alice   85
# Bob     90
# Carol   95

# 使用自定义分隔符
paste -d',' names.txt scores.txt
# 输出:
# Alice,85
# Bob,90
# Carol,95
```

### join - SQL 风格的连接

```bash
cd ~/sort-lab

# 创建两个有关联键的文件（必须已排序！）
cat > users.txt << 'EOF'
001 Alice
002 Bob
003 Carol
EOF

cat > orders.txt << 'EOF'
001 Order-A
001 Order-B
002 Order-C
EOF

# join 默认按第一个字段连接
join users.txt orders.txt
# 输出:
# 001 Alice Order-A
# 001 Alice Order-B
# 002 Bob Order-C
```

> **注意**：join 要求两个文件都按连接字段排序！  

---

## 实战项目：日志频率分析

### 场景

> 你是运维工程师，需要从一周的日志中分析：  
> 1. 最活跃的 IP（可能是爬虫或攻击）  
> 2. 最常见的错误类型（需要优先修复）  
> 3. 高峰时段（按小时统计请求量）  

### 准备数据

```bash
cd ~/sort-lab

# 创建更大的测试日志
cat > week.log << 'EOF'
2026-01-04 08:15:22 192.168.1.100 GET /api/users 200
2026-01-04 08:15:25 10.0.0.50 GET /api/products 200
2026-01-04 08:16:01 192.168.1.100 POST /api/orders 500
2026-01-04 08:16:15 192.168.1.100 GET /api/users 200
2026-01-04 09:00:01 172.16.0.25 GET /health 200
2026-01-04 09:00:05 192.168.1.100 GET /api/orders 200
2026-01-04 09:15:30 10.0.0.50 POST /api/login 401
2026-01-04 09:20:45 192.168.1.101 GET /api/products 200
2026-01-04 10:00:01 192.168.1.100 GET /api/users 504
2026-01-04 10:05:22 10.0.0.50 GET /api/orders 200
2026-01-04 10:10:33 192.168.1.100 GET /api/users 500
2026-01-04 10:15:44 172.16.0.25 GET /api/products 200
2026-01-04 11:00:01 192.168.1.100 POST /api/orders 200
2026-01-04 11:05:15 10.0.0.50 GET /api/users 200
2026-01-04 11:10:30 192.168.1.101 GET /health 200
EOF
```

### 任务 1：找出最活跃的 IP

```bash
# 提取 IP（第 3 字段）→ 排序 → 统计 → 按数量排序
cut -d' ' -f3 week.log | sort | uniq -c | sort -rn | head -5

# 输出:
#       7 192.168.1.100
#       4 10.0.0.50
#       2 172.16.0.25
#       2 192.168.1.101
```

**分析**：192.168.1.100 请求量最大，需要确认是否正常。

### 任务 2：找出最常见的 HTTP 错误

```bash
# 先筛选出错误（4xx, 5xx），再统计
grep -E ' [45][0-9]{2}$' week.log | cut -d' ' -f6 | sort | uniq -c | sort -rn

# 输出:
#       2 500
#       1 504
#       1 401
```

**分析**：500 错误最多，需要检查服务端问题。

### 任务 3：按小时统计请求量

```bash
# 提取小时部分（第 2 字段的前 2 个字符）
cut -d' ' -f2 week.log | cut -c1-2 | sort | uniq -c | sort -k2 -n

# 输出:
#       4 08
#       3 09
#       4 10
#       4 11
```

或者使用 awk 更灵活：

```bash
awk '{split($2,t,":"); print t[1]}' week.log | sort | uniq -c | sort -k2 -n
```

### 任务 4：找出有错误的 IP

```bash
# 先筛选错误请求，再统计 IP
grep -E ' [45][0-9]{2}$' week.log | cut -d' ' -f3 | sort | uniq -c | sort -rn

# 输出:
#       3 192.168.1.100
#       1 10.0.0.50
```

**分析**：192.168.1.100 产生了最多的错误，需要调查。

### 综合分析脚本

```bash
cat > ~/sort-lab/analyze.sh << 'EOF'
#!/bin/bash
# 日志频率分析脚本 - Log Frequency Analyzer

LOG_FILE="${1:-week.log}"

if [[ ! -f "$LOG_FILE" ]]; then
    echo "Error: File $LOG_FILE not found"
    exit 1
fi

echo "========================================"
echo "日志频率分析报告"
echo "Log Frequency Analysis Report"
echo "文件: $LOG_FILE"
echo "========================================"
echo ""

echo "【最活跃 IP Top 5】"
echo "Top 5 Most Active IPs:"
cut -d' ' -f3 "$LOG_FILE" | sort | uniq -c | sort -rn | head -5
echo ""

echo "【HTTP 状态码分布】"
echo "HTTP Status Code Distribution:"
cut -d' ' -f6 "$LOG_FILE" | sort | uniq -c | sort -rn
echo ""

echo "【产生错误的 IP】"
echo "IPs with Errors (4xx/5xx):"
grep -E ' [45][0-9]{2}$' "$LOG_FILE" | cut -d' ' -f3 | sort | uniq -c | sort -rn
echo ""

echo "【访问最多的接口】"
echo "Most Accessed Endpoints:"
cut -d' ' -f5 "$LOG_FILE" | sort | uniq -c | sort -rn | head -5
echo ""

echo "【不同 IP 总数】"
echo "Total Unique IPs:"
cut -d' ' -f3 "$LOG_FILE" | sort -u | wc -l
EOF

chmod +x ~/sort-lab/analyze.sh
```

运行分析：

```bash
cd ~/sort-lab
./analyze.sh week.log
```

---

## 职场小贴士

### 日本 IT 现场术语

| 日本語 | 中文 | 场景 |
|--------|------|------|
| ソート | 排序 | データをソートする |
| 重複排除（ちょうふくはいじょ） | 去重 | 重複データを排除する |
| 頻度分析（ひんどぶんせき） | 频率分析 | エラーの頻度を分析 |
| 障害傾向分析 | 故障趋势分析 | 週次レポート |
| 集計（しゅうけい） | 统计/汇总 | ログ集計 |

### 运维中的典型场景

**1. 每日错误统计报告**

```bash
# 在日本 IT 公司，每日/每周报告（日次レポート/週次レポート）是常见任务
grep 'ERROR' /var/log/app/app.log | \
  awk '{print $4}' | \         # 提取错误类型
  sort | uniq -c | sort -rn | \
  head -10 > /tmp/daily_errors.txt
```

**2. 异常访问检测**

```bash
# 找出请求量超过 1000 的 IP（可能是爬虫或攻击）
cut -d' ' -f1 /var/log/nginx/access.log | \
  sort | uniq -c | sort -rn | \
  awk '$1 > 1000 {print}'
```

**3. 故障时间线分析**

```bash
# 障害発生時：找出故障前后的请求模式
grep '2026-01-04 09:' /var/log/app/app.log | \
  cut -d' ' -f1-2 | \
  sort | uniq -c
```

---

## 反面模式（Anti-Patterns）

### 1. uniq 不加 sort（最常见错误！）

```bash
# 错误！uniq 只去除相邻重复
uniq file.txt

# 正确
sort file.txt | uniq
```

### 2. sort -k 不指定结束字段

```bash
# 错误！从第 2 字段排到行尾
sort -k2 file.txt

# 正确！只按第 2 字段
sort -k2,2 file.txt
```

### 3. 用 cut 处理可变空白

```bash
# 错误！cut 不能处理多个空格
cut -d' ' -f2 file.txt

# 正确！用 awk
awk '{print $2}' file.txt
```

### 4. 数字排序忘加 -n

```bash
# 错误！10 排在 2 前面
echo -e "10\n2\n5" | sort

# 正确
echo -e "10\n2\n5" | sort -n
```

### 5. 忘记 uniq -c 输出的格式

```bash
# uniq -c 输出格式是：计数 + 空格 + 内容
# 如果要进一步处理，注意字段位置

# 取 Top 10 的内容（不含计数）
sort file | uniq -c | sort -rn | head -10 | awk '{print $2}'
```

---

## 动手练习

### 练习 1：验证 uniq 的行为

```bash
cd ~/sort-lab

# 创建测试文件
cat > test_uniq.txt << 'EOF'
apple
banana
apple
cherry
banana
apple
EOF

# 任务：
# 1. 直接用 uniq，观察结果（为什么没去重？）
uniq test_uniq.txt

# 2. 用 sort | uniq，观察结果
sort test_uniq.txt | uniq

# 3. 统计每种水果的出现次数
sort test_uniq.txt | uniq -c

# 4. 找出出现超过 1 次的水果
sort test_uniq.txt | uniq -d

# 5. 找出只出现 1 次的水果
sort test_uniq.txt | uniq -u
```

### 练习 2：多字段排序

```bash
cd ~/sort-lab

# 创建成绩单
cat > grades.txt << 'EOF'
Alice Math 85
Bob Math 90
Carol Math 85
Alice Science 92
Bob Science 88
Carol Science 90
EOF

# 任务：
# 1. 按科目排序（第 2 字段）
sort -k2,2 grades.txt

# 2. 按分数数字排序（第 3 字段）
sort -k3,3 -n grades.txt

# 3. 先按科目，再按分数从高到低
sort -k2,2 -k3,3 -rn grades.txt

# 4. 找出每个科目的最高分
sort -k2,2 -k3,3 -rn grades.txt | \
  awk '!seen[$2]++ {print}'
```

### 练习 3：实战日志分析

```bash
cd ~/sort-lab

# 使用之前创建的 week.log
# 完成以下任务：

# 1. 统计每个 HTTP 方法（GET/POST）的请求数
cut -d' ' -f4 week.log | sort | uniq -c

# 2. 找出响应 500 错误最多的 3 个 IP
grep ' 500$' week.log | cut -d' ' -f3 | sort | uniq -c | sort -rn | head -3

# 3. 按日期+小时统计请求量
cut -d' ' -f1-2 week.log | cut -d':' -f1 | sort | uniq -c

# 4. 找出只出现过一次的 IP（可能是临时访客）
cut -d' ' -f3 week.log | sort | uniq -u
```

---

## 检查清单

完成本课后，你应该能够：

- [ ] 理解 `sort -n` 和 `sort` 的区别（数字 vs 字母排序）
- [ ] 使用 `sort -k` 按指定字段排序
- [ ] **记住 uniq 只去除相邻重复，必须先 sort**
- [ ] 使用 `uniq -c` 统计频率
- [ ] 使用 `cut -d -f` 提取字段
- [ ] 知道 cut 不能处理可变空白（用 awk 代替）
- [ ] 掌握标准频率分析管道：`sort | uniq -c | sort -rn | head`
- [ ] 使用 `paste` 并列合并文件
- [ ] 理解 `sort -k2` 和 `sort -k2,2` 的区别

**验证命令**：

```bash
cd ~/sort-lab

# 测试 1: 统计 IP 频率
cut -d' ' -f1 access.log | sort | uniq -c | sort -rn | head -1
# 预期: 6 192.168.1.100

# 测试 2: 人类可读排序
echo -e "1K\n2M\n500K" | sort -h | tail -1
# 预期: 2M

# 测试 3: 验证 uniq 相邻原则
echo -e "a\nb\na" | uniq | wc -l
# 预期: 3（因为两个 a 不相邻）

echo -e "a\nb\na" | sort | uniq | wc -l
# 预期: 2（排序后相邻，能去重）
```

---

## 快速参考

```bash
# sort 常用选项
sort file           # 字母排序
sort -n file        # 数字排序
sort -r file        # 逆序
sort -k2,2 file     # 按第 2 字段
sort -t',' file     # 指定分隔符
sort -u file        # 排序并去重
sort -h file        # 人类可读数字

# uniq 常用选项（必须先 sort！）
sort file | uniq       # 去重
sort file | uniq -c    # 统计频率
sort file | uniq -d    # 只显示重复的
sort file | uniq -u    # 只显示不重复的

# cut 常用选项
cut -d':' -f1 file     # 按 : 分隔，取第 1 字段
cut -d',' -f1,3 file   # 取第 1 和第 3 字段
cut -c1-10 file        # 取前 10 个字符

# 标准频率分析管道
sort file | uniq -c | sort -rn | head -10

# paste 和 join
paste file1 file2      # 并列合并
join file1 file2       # SQL 风格连接（需要先排序）
```

---

## 延伸阅读

### 官方文档

- [GNU coreutils: sort](https://www.gnu.org/software/coreutils/manual/html_node/sort-invocation.html)
- [GNU coreutils: uniq](https://www.gnu.org/software/coreutils/manual/html_node/uniq-invocation.html)
- [GNU coreutils: cut](https://www.gnu.org/software/coreutils/manual/html_node/cut-invocation.html)

### 相关课程

- [07 - awk 程序和聚合](../07-awk-programs/) - 更复杂的聚合分析
- [09 - 使用 find 和 xargs 查找文件](../09-find-xargs/) - 批量处理文件
- [10 - 综合项目：日志分析管道](../10-capstone-pipeline/) - 整合所有技能

---

## 清理

```bash
cd ~
rm -rf ~/sort-lab
```

---

## 系列导航

| 课程 | 主题 |
|------|------|
| [01 - 管道和重定向](../01-pipes-redirection/) | stdin/stdout/stderr |
| [02 - 查看和流式处理文件](../02-viewing-files/) | cat/less/head/tail |
| [03 - grep 基础](../03-grep-fundamentals/) | 模式搜索 |
| [04 - 正则表达式](../04-regular-expressions/) | BRE/ERE |
| [05 - sed 文本转换](../05-sed-transformation/) | 文本替换 |
| [06 - awk 字段处理](../06-awk-fields/) | 字段提取 |
| [07 - awk 程序和聚合](../07-awk-programs/) | 数据分析 |
| **08 - 排序、去重和字段提取** | 当前课程 |
| [09 - 使用 find 和 xargs 查找文件](../09-find-xargs/) | 文件查找 |
| [10 - 综合项目：日志分析管道](../10-capstone-pipeline/) | 实战项目 |
