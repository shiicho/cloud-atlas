# 01 · 日志分析工具与模式识别（grep/rg/jq/less + 异常发现）

> **目标**：掌握 grep/rg/jq/less 日志分析工具链，学会识别异常模式  
> **前置**：[00 · Linux 日志系统概览](../00-linux-logs/)  
> **区域**：任意（本课在本地/EC2 均可练习）  
> **费用**：无额外费用

## 将完成的内容

1. 掌握 grep/rg 正则搜索技巧
2. 使用 jq 解析 JSON 格式日志
3. less 高效导航大日志文件
4. 学会识别异常模式（暴力破解 vs 正常登录）
5. 实战：区分外部攻击和内部操作

---

## grep/rg 快速搜索 {#grep-rg}

### grep 基础

```bash
# 基本搜索
grep "ERROR" /var/log/messages

# 忽略大小写
grep -i "error" /var/log/messages

# 显示行号
grep -n "ERROR" /var/log/messages

# 显示上下文（前后各 3 行）
grep -C 3 "ERROR" /var/log/messages

# 多模式搜索
grep -E "ERROR|FATAL|CRITICAL" /var/log/messages
```

### ripgrep (rg) - 更快更强

`rg` 是现代版 grep，速度更快，默认递归搜索：

```bash
# 安装（Amazon Linux 2023）
sudo dnf install ripgrep

# 基本搜索（自动递归）
rg "ERROR" /var/log/

# 指定文件类型
rg "ERROR" --type=log

# 只显示匹配文件名
rg -l "ERROR" /var/log/

# 统计匹配数
rg -c "ERROR" /var/log/
```

### 实用搜索模式

```bash
# 搜索 IP 地址
rg '\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}' /var/log/auth.log

# 搜索时间范围（09:00-09:59）
rg '09:[0-5][0-9]:[0-5][0-9]' /var/log/messages

# 排除某些目录
rg "ERROR" --glob '!*.gz' /var/log/
```

---

## 统计分析技巧

### awk + sort + uniq 组合

这是日志分析最常用的组合：

```bash
# 统计每个 IP 出现次数
awk '{print $1}' access.log | sort | uniq -c | sort -nr | head -10

# 统计每个状态码数量
awk '{print $9}' access.log | sort | uniq -c | sort -nr

# 统计每小时请求数
awk '{print substr($4,14,2)}' access.log | sort | uniq -c
```

### 统计失败登录 Top IP

```bash
# 从 auth.log 提取失败登录 IP
grep "Failed password" /var/log/auth.log | \
  awk '{print $(NF-3)}' | \
  sort | uniq -c | sort -nr | head -10
```

输出示例：
```
    523 203.0.113.24
    156 198.51.100.10
     42 192.0.2.5
```

---

## jq 解析 JSON 日志 {#jq}

现代日志越来越多使用 JSON 格式（CloudTrail、Docker、应用日志）：

### 基础用法

```bash
# 格式化 JSON
cat log.json | jq .

# 提取特定字段
jq '.eventName' cloudtrail.json

# 多字段提取
jq '{time: .eventTime, action: .eventName, user: .userIdentity.userName}' cloudtrail.json
```

### 过滤查询

```bash
# 过滤有错误的事件
jq 'select(.errorCode != null)' cloudtrail.json

# 过滤特定事件类型
jq 'select(.eventName == "ConsoleLogin")' cloudtrail.json

# 组合条件
jq 'select(.eventName == "ConsoleLogin" and .errorMessage != null)' cloudtrail.json
```

### 输出格式化

```bash
# 输出为 TSV（便于 Excel）
jq -r '[.eventTime, .eventName, .sourceIPAddress] | @tsv' cloudtrail.json

# 输出为 CSV
jq -r '[.eventTime, .eventName, .sourceIPAddress] | @csv' cloudtrail.json
```

### 处理数组

```bash
# CloudTrail 日志通常是 Records 数组
jq '.Records[] | {time: .eventTime, event: .eventName}' cloudtrail.json

# 统计各事件类型数量
jq '.Records[].eventName' cloudtrail.json | sort | uniq -c | sort -nr
```

---

## less 高效导航 {#less}

`less` 比 `cat` 更适合查看大文件：

### 基本导航

| 按键 | 作用 |
|------|------|
| `Space` / `f` | 下一页 |
| `b` | 上一页 |
| `g` | 跳到开头 |
| `G` | 跳到末尾 |
| `q` | 退出 |

### 搜索功能

| 按键 | 作用 |
|------|------|
| `/pattern` | 向下搜索 |
| `?pattern` | 向上搜索 |
| `n` | 下一个匹配 |
| `N` | 上一个匹配 |
| `&pattern` | 只显示匹配行 |

### 实用技巧

```bash
# 带行号显示
less -N /var/log/messages

# 实时跟踪（类似 tail -f）
less +F /var/log/messages
# 按 Ctrl+C 停止跟踪，继续浏览

# 从特定行开始
less +100 /var/log/messages

# 搜索并高亮
less /var/log/messages
# 输入 /ERROR 然后回车
```

---

## 异常模式识别 {#anomaly}

### 识别异常的关键思路

1. **频率异常**：短时间大量相同事件
2. **来源异常**：外部 IP vs 内网 IP
3. **时间异常**：非工作时间的操作
4. **模式异常**：正常流程中不该出现的事件

### 内网 vs 外网 IP 判断

常见内网 IP 段：
- `10.0.0.0/8` - 10.x.x.x
- `172.16.0.0/12` - 172.16.x.x ~ 172.31.x.x
- `192.168.0.0/16` - 192.168.x.x

```bash
# 过滤外网 IP（非内网）
grep "Failed password" /var/log/auth.log | \
  grep -v -E '(10\.|172\.(1[6-9]|2[0-9]|3[01])\.|192\.168\.)'
```

---

## 实战练习：区分暴力破解 vs 内部操作

### 场景描述

安全团队发现 auth.log 中有大量登录失败，需要判断是外部攻击还是内部误操作。

### 日志样本

```
Jun 21 01:02:11 sshd[3210]: Failed password for invalid user test from 203.0.113.24 port 55422
Jun 21 01:02:12 sshd[3210]: Failed password for invalid user test from 203.0.113.24 port 55422
Jun 21 01:02:15 sshd[6542]: Accepted publickey for ops from 10.0.2.15 port 51234
Jun 21 01:02:20 sudo: ops : TTY=pts/1 ; PWD=/home/ops ; COMMAND=/bin/vi /etc/ssh/sshd_config
```

### 分析步骤

**Step 1: 统计失败登录 Top IP**

```bash
grep "Failed password" /var/log/auth.log | \
  awk '{print $(NF-3)}' | \
  sort | uniq -c | sort -nr | head
```

**Step 2: 区分内外网**

```bash
# 外部攻击（非内网 IP）
grep "Failed password" /var/log/auth.log | \
  grep -v -E '10\.|172\.(1[6-9]|2[0-9]|3[01])\.|192\.168\.' | head

# 内部失败（内网 IP）
grep "Failed password" /var/log/auth.log | \
  grep -E '10\.|172\.(1[6-9]|2[0-9]|3[01])\.|192\.168\.' | head
```

**Step 3: 关联同时间段的其他事件**

```bash
# 查看 01:02 时间段所有事件
grep "Jun 21 01:02" /var/log/auth.log
```

### 发现要点

| 层次 | 发现 |
|------|------|
| **显而易见** | Failed password 来自外部 IP 203.0.113.24 |
| **需要细看** | 同一时间 ops 用户从内网登录并 sudo 编辑 sshd_config |

### 结论

- 外部 IP `203.0.113.24` 是暴力破解尝试
- 内网 `10.0.2.15` 是运维人员正常操作
- 两者时间接近但无关联

---

## 面试常见问题

### Q1: 你如何快速找出 top failed login IP？

**期望回答**：
```bash
rg 'Failed password' /var/log/auth.log | \
  awk '{print $(NF-3)}' | \
  sort | uniq -c | sort -nr | head
```
> 使用 grep/rg 过滤，awk 提取 IP 字段，sort + uniq -c 统计，sort -nr 降序排列。

**红旗回答**：
- 说「手动翻看日志」
- 不知道 uniq -c 的用法

### Q2: less 里如何跳到下一次出现的 ERROR？

**期望回答**：
> 输入 `/ERROR` 回车搜索，然后按 `n` 跳到下一个匹配，`N` 跳到上一个。

**红旗回答**：
- 说「不会」
- 说「重新 cat | grep」

---

## 常见错误

1. **不使用 rg/grep 的正则能力**
   - 正则可以大幅提高搜索效率

2. **手动翻看大日志文件**
   - 应该用工具过滤和统计

3. **不会用 less 的搜索功能**
   - less 比反复 grep 更高效

4. **无法区分内外网 IP 段**
   - 必须记住 10.x、172.16-31.x、192.168.x

---

## 快速参考

| 需求 | 命令 |
|------|------|
| 搜索关键词 | `rg "ERROR" /var/log/` |
| 多模式搜索 | `grep -E "ERROR\|FATAL"` |
| 统计出现次数 | `... \| sort \| uniq -c \| sort -nr` |
| JSON 字段提取 | `jq '.fieldName' file.json` |
| JSON 过滤 | `jq 'select(.error != null)'` |
| less 搜索 | `/pattern` 然后 `n`/`N` |
| 只显示匹配行 | `less` 中按 `&pattern` |

---

## 下一步

- [02 · systemd 服务日志分析](../02-systemd-logs/) - 识别 crash loop 和 timeout 模式

## 系列导航 / Series Nav

| 课程 | 主题 |
|------|------|
| [00 · Linux 日志系统概览](../00-linux-logs/) | journalctl, dmesg, auth.log |
| **01 · 日志分析工具与模式识别** | 当前 |
| [02 · systemd 服务日志分析](../02-systemd-logs/) | crash loop, timeout |
| [03 · Web 服务器日志](../03-web-server-logs/) | Nginx/Apache 5xx |
| [04 · AWS 日志实战](../04-aws-logs/) | CloudTrail, VPC Flow |
| [05 · 故障时间线重建](../05-timeline-report/) | 障害報告書 |
| [06 · RCA 根因分析实战](../06-rca-practice/) | Five Whys |
