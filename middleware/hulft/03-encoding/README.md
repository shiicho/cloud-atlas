# 03 · 字符编码处理（SJIS↔UTF-8/EBCDIC）

> **目标**：掌握日本企业环境中常见的字符编码转换  
> **前置**：[02 · HULFT 安装与基本配置](../02-installation/)  
> **适用**：日本 SIer/银行 IT 岗位面试准备  
> **时长**：约 60 分钟

## 为什么编码问题重要？

在日本企业环境中，**字符编码问题是最常见的故障原因之一**：

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                     日本企业典型编码环境                                      │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│   ┌─────────────┐      ┌─────────────┐      ┌─────────────┐               │
│   │  Mainframe  │      │   Windows   │      │   Linux     │               │
│   │   (z/OS)    │      │   Server    │      │   Server    │               │
│   │             │      │             │      │             │               │
│   │   EBCDIC    │ ───→ │   SJIS      │ ───→ │   UTF-8     │               │
│   │   (930)     │      │   (CP932)   │      │             │               │
│   └─────────────┘      └─────────────┘      └─────────────┘               │
│                                                                             │
│   勘定系統              業務サーバー          Web/API サーバー              │
│   (Core Banking)       (Business)           (Modern Apps)                  │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘

⚠️ 编码错误 = 文字化け = 数据损坏 = 严重事故（障害）
```

## 将完成的内容

1. 配置 SJIS 到 UTF-8 的字符编码转换
2. 处理 EBCDIC（IBM 大型机）文件
3. 理解并避免文字化け（mojibake）
4. 正确处理换行符转换

---

## Step 1 — 理解日本常见编码

### 编码对照表

| 编码 | 别名 | 使用场景 | 特点 |
|------|------|----------|------|
| **Shift_JIS** | SJIS, CP932 | Windows, 旧系统 | 日本 Windows 默认 |
| **UTF-8** | - | Linux, 现代应用 | 国际标准 |
| **EBCDIC** | IBM-930, CP930 | IBM 大型机 | 银行核心系统 |
| **EUC-JP** | - | 旧 Unix 系统 | 逐渐淘汰 |

### Shift_JIS (SJIS) 详解

```
Shift_JIS 特点：
• 日本 Windows 默认编码
• 1-2 字节可变长度
• CP932 是 Microsoft 扩展版本

常见场景：
• Windows 生成的 CSV 文件
• 旧业务系统输出
• Excel 导出文件

⚠️ 注意：机种依存文字（vendor-specific characters）
   ①②③ 等在标准 SJIS 中可能不存在
   需使用 CP932（Microsoft 扩展）
```

### 半角/全角假名问题

```
半角カナ (Half-width Kana):
ｱｲｳｴｵ ｶｷｸｹｺ

全角カナ (Full-width Kana):
アイウエオ カキクケコ

⚠️ 转换时确保两种都能正确处理！
```

---

## Step 2 — SJIS → UTF-8 转换配置

### 典型场景

```
Windows Server (SJIS)  ──→  Linux Server (UTF-8)
       │                           │
   CSV 报表文件              Web 应用读取
   批处理输出                API 数据处理
```

### HULFT 转换配置

在传输定义中设置编码转换：

```bash
# 方式 1：在 hlmdef.tbl 中定义
# 传输定义示例
TRANSFER_ID: DAILY_REPORT
  SOURCE_CODE: SJIS        # 源文件编码
  TARGET_CODE: UTF-8       # 目标文件编码
  NEWLINE_CONV: YES        # 换行符转换 (CRLF→LF)
```

### 命令行指定

```bash
# 使用 hulcmd 时指定编码
/opt/hulft8/bin/hulcmd -sendfile \
  -node NODE_B \
  -file /tmp/report_sjis.csv \
  -dest /tmp/report_utf8.csv \
  -srccode SJIS \
  -dstcode UTF-8 \
  -newline YES
```

### 验证转换结果

```bash
# 检查文件编码
file /tmp/report_utf8.csv
# 期望：UTF-8 Unicode text

# 或使用 nkf
nkf --guess /tmp/report_utf8.csv
# 期望：UTF-8

# 查看实际内容（确认无乱码）
head -5 /tmp/report_utf8.csv
```

---

## Step 3 — 什么是文字化け（Mojibake）

### 定义

**文字化け**（もじばけ）= 字符显示为乱码

```
正常显示：株式会社テスト
文字化け：譁�ｭ怜喧莨夊ｪｽ繝�繧ｹ繝�

原因：编码不匹配
• 文件实际是 SJIS
• 但系统按 UTF-8 读取
• 结果：乱码
```

### 常见文字化け场景

| 场景 | 原因 | 表现 |
|------|------|------|
| SJIS 文件在 UTF-8 环境打开 | 编码识别错误 | 日文变乱码 |
| UTF-8 文件在 SJIS 环境打开 | 编码识别错误 | 部分字符显示异常 |
| 机种依存文字转换 | 字符映射缺失 | ①②③ 变成 ? |
| EBCDIC 未正确转换 | 字符表错误 | 全部乱码 |

### 预防措施

```
✅ 预防文字化け的关键步骤：

1. 明确指定源编码
   - 不要依赖自动检测
   - 在 HULFT 配置中显式设置

2. 明确指定目标编码
   - 知道下游系统期望什么编码
   - UTF-8 是现代系统首选

3. 检查服务账户 Locale
   - LANG=ja_JP.UTF-8 或 en_US.UTF-8
   - C locale 会导致问题

4. 测试机种依存文字
   - 包含 ①②③ 等特殊字符
   - 半角カナ ｱｲｳ

5. 启用转换错误检查
   - 无法映射时报错而非静默替换
```

> 💡 **面试要点 #1**
>
> **问题**：「メインフレームからSJISファイルを取得し、UTF-8のLinuxアプリに配信する際、文字化けをどのように防止しますか？」
>
> （中文参考：从大型机拉取 SJIS 文件并发送到 UTF-8 Linux 应用时，如何防止文字化け？）
>
> **期望回答**：
> 1. 在 HULFT 中明确指定源编码（SJIS/CP932）
> 2. 设置目标编码 UTF-8
> 3. 确保 hulft 服务账户 `LANG=ja_JP.UTF-8`
> 4. 启用 error-on-unmappable 捕获机种依存文字
> 5. 测试包含 機種依存文字 的样本数据

---

## Step 4 — EBCDIC 处理（IBM 大型机）

### 什么是 EBCDIC？

```
EBCDIC (Extended Binary Coded Decimal Interchange Code)
• IBM 大型机专用编码
• 与 ASCII/UTF-8 完全不同的字符映射
• 日本银行核心系统（勘定系）常用

常见 CCSID：
• 930 - 日本语 EBCDIC (Katakana)
• 939 - 日本语 EBCDIC (Extended)
• 1047 - Latin (Open Systems)
```

### 典型场景

```
┌─────────────────┐                    ┌─────────────────┐
│   IBM z/OS      │                    │   Linux         │
│                 │                    │                 │
│   EBCDIC-930    │  ──── HULFT ────→  │   UTF-8         │
│                 │                    │                 │
│   固定长度记录   │                    │   可变长度      │
│   80 字节/行    │                    │   换行符分隔    │
└─────────────────┘                    └─────────────────┘
```

### HULFT EBCDIC 转换配置

```bash
# 传输定义
TRANSFER_ID: MAINFRAME_EXTRACT
  SOURCE_CODE: EBCDIC-930    # IBM 日语 EBCDIC
  TARGET_CODE: UTF-8
  RECORD_FORMAT: FIXED       # 固定长度记录
  RECORD_LENGTH: 80          # 每行 80 字节
```

### EBCDIC 转换注意事项

```
⚠️ EBCDIC 转换的特殊问题：

1. 括号/波浪线字符交换
   EBCDIC 的 [ ] ~ 与 ASCII 位置不同
   需要验证转换后的特殊字符

2. Packed Decimal 数据
   不能当文本转换！
   会导致数据损坏

3. 固定长度记录
   转换后长度可能变化（UTF-8 是可变长度）
   需要处理填充字符

4. 空格填充 vs 零填充
   EBCDIC 空格 = 0x40
   ASCII 空格 = 0x20
```

> 💡 **面试要点 #2**
>
> **问题**：「IBMメインフレームからのEBCDICファイルをどのように処理しますか？」
>
> （中文参考：如何处理来自 IBM 大型机的 EBCDIC 文件？）
>
> **期望回答**：
> - 定义正确的 CCSID（如 930 日语 EBCDIC）
> - 映射到 UTF-8，使用适当的字符表
> - 注意固定长度记录 - 填充字符可能变化
> - 用参考数据测试，验证括号/波浪线处理
> - Packed Decimal 数据不能当文本转换

---

## Step 5 — 换行符转换

### 换行符差异

| 系统 | 换行符 | 十六进制 |
|------|--------|----------|
| Windows | CRLF | 0D 0A |
| Linux/Unix | LF | 0A |
| 旧 Mac | CR | 0D |

### 何时启用换行符转换

```
✅ 启用换行符转换 (NEWLINE_CONV: YES)：
   • 文本文件（CSV, TXT, LOG）
   • 配置文件
   • 脚本文件

❌ 禁用换行符转换：
   • 二进制文件（ZIP, PDF, 图片）
   • 已标准化的文件
   • 固定长度记录格式
```

### 配置示例

```bash
# 文本文件：启用转换
TRANSFER_ID: TEXT_FILE
  TRANSFER_MODE: TEXT
  NEWLINE_CONV: YES      # CRLF → LF

# 二进制文件：禁用所有转换
TRANSFER_ID: BINARY_FILE
  TRANSFER_MODE: BINARY  # 禁用编码转换
  NEWLINE_CONV: NO       # 禁用换行转换
```

### 常见错误

```
⚠️ 二进制文件被文本转换的后果：

原始 PDF 文件 (正常)：
%PDF-1.4
...二进制数据...

被转换后 (损坏)：
%PDF-1.4
...数据被破坏，0D 0A 被改成 0A...

结果：PDF 无法打开！
```

> 💡 **面试要点 #3**
>
> **问题**：「HULFTで改行コード変換を無効にするのはどのような場合ですか？」
>
> （中文参考：什么情况下需要在 HULFT 中禁用换行符转换？）
>
> **期望回答**：
> - 二进制文件（ZIP, PDF, 图片, 可执行文件）
> - 已经在上游标准化过的文件
> - 固定长度记录格式（填充字符重要）
> - 使用 BINARY 传输模式禁用所有转换

---

## Step 6 — 实践：编码转换测试

### 准备测试数据

```bash
# 创建包含日语和特殊字符的测试文件
cat > /tmp/test_utf8.txt << 'EOF'
株式会社テスト
ｱｲｳｴｵ（半角カナ）
①②③（機種依存文字）
2024年12月期決算報告
EOF

# 确认是 UTF-8
file /tmp/test_utf8.txt
```

### 转换为 SJIS

```bash
# 使用 iconv 转换为 SJIS
iconv -f UTF-8 -t CP932 /tmp/test_utf8.txt > /tmp/test_sjis.txt

# 验证
file /tmp/test_sjis.txt
# 期望：ISO-8859 text (或 Non-ISO extended-ASCII)

# 查看十六进制确认编码
hexdump -C /tmp/test_sjis.txt | head -10
```

### 通过 HULFT 传输并转换

```bash
# 发送 SJIS 文件，转换为 UTF-8
/opt/hulft8/bin/hulcmd -sendfile \
  -node NODE_B \
  -file /tmp/test_sjis.txt \
  -dest /tmp/received_utf8.txt \
  -srccode SJIS \
  -dstcode UTF-8

# 在 Node B 验证
file /tmp/received_utf8.txt
cat /tmp/received_utf8.txt
```

### 验证关键字符

```bash
# 检查特殊字符是否正确转换
grep "①②③" /tmp/received_utf8.txt
grep "ｱｲｳ" /tmp/received_utf8.txt

# 如果 grep 找不到，说明转换有问题！
```

---

## Step 7 — 服务账户 Locale 配置

### 为什么 Locale 重要？

```
HULFT 进程继承服务账户的 Locale 设置。
如果 Locale 不正确：
• 文件名显示乱码
• 日志中的日语乱码
• 某些转换操作失败
```

### 检查当前 Locale

```bash
# 以 hulft 用户身份检查
sudo -u hulftsvc locale

# 期望输出：
# LANG=ja_JP.UTF-8 或 en_US.UTF-8
```

### 修复 Locale

```bash
# 方法 1：在 hulenv 中设置
echo 'export LANG=en_US.UTF-8' >> /opt/hulft8/hulenv

# 方法 2：在用户 profile 中设置
# 创建 .bash_profile（即使是 nologin 用户）
sudo tee /opt/hulft/.bash_profile << 'EOF'
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8
EOF
sudo chown hulftsvc:hulft /opt/hulft/.bash_profile

# 重启 HULFT 使生效
sudo -u hulftsvc /opt/hulft8/bin/hulstop
sudo -u hulftsvc /opt/hulft8/bin/hulstart
```

### 验证

```bash
# 检查运行中的 HULFT 进程 Locale
cat /proc/$(pgrep -f hulft)/environ | tr '\0' '\n' | grep LANG
```

---

## 实践练习

### 练习 1：故意制造文字化け

**目的**：理解编码错误的表现

```bash
# 1. 创建 UTF-8 文件
echo "日本語テスト" > /tmp/utf8_test.txt

# 2. 错误地按 SJIS 读取
iconv -f SJIS -t UTF-8 /tmp/utf8_test.txt 2>&1

# 观察错误输出
```

### 练习 2：修复文字化け

**场景**：收到一个乱码文件，如何恢复？

<details>
<summary>点击查看解决思路</summary>

```bash
# 1. 猜测原始编码
nkf --guess garbled_file.txt
# 或
file garbled_file.txt

# 2. 尝试不同编码转换
iconv -f SJIS -t UTF-8 garbled_file.txt > recovered.txt
iconv -f EUC-JP -t UTF-8 garbled_file.txt > recovered.txt

# 3. 使用 nkf 自动检测
nkf -w garbled_file.txt > recovered.txt
# -w = 输出 UTF-8
```

</details>

### 练习 3：设计编码转换流程

**场景**：设计从 Windows Server (SJIS) 到 Linux (UTF-8) 的文件传输

```
要求：
1. CSV 文件，包含日语
2. 可能有機種依存文字
3. 需要换行符转换
4. 错误时通知运维
```

<details>
<summary>点击查看参考设计</summary>

```yaml
# 传输定义
TRANSFER_ID: WIN_TO_LINUX_CSV
  SOURCE_NODE: WINDOWS_SRV
  TARGET_NODE: LINUX_SRV

  # 编码设置
  SOURCE_CODE: CP932        # Windows SJIS 扩展
  TARGET_CODE: UTF-8

  # 换行符
  NEWLINE_CONV: YES         # CRLF → LF

  # 错误处理
  ON_UNMAPPABLE: ERROR      # 无法映射时报错（不静默替换）
  ON_ERROR: NOTIFY          # 错误时通知

  # 重试
  RETRY_COUNT: 3
  RETRY_INTERVAL: 60
```

</details>

---

## 常见错误

| 错误 | 后果 | 预防 |
|------|------|------|
| 忘记指定编码 | 文字化け | 显式配置源/目标编码 |
| 二进制文件启用转换 | PDF/图片损坏 | 使用 BINARY 模式 |
| Locale 为 C | 文件名乱码 | 设置 LANG=*.UTF-8 |
| 不测试機種依存文字 | ①②③ 变成 ? | 用真实样本测试 |
| EBCDIC 当普通文本 | 数据全乱 | 指定正确 CCSID |

---

## 小结

| 主题 | 要点 |
|------|------|
| SJIS→UTF-8 | 显式指定编码，注意 CP932 扩展 |
| EBCDIC | 指定 CCSID，注意固定长度记录 |
| 文字化け | 编码不匹配导致，预防胜于修复 |
| 换行符 | 文本启用转换，二进制禁用 |
| Locale | 服务账户设置 LANG=*.UTF-8 |

---

## 下一步

完成本课后，请继续：

- **[04 · 集信/配信实战（送受信 + 重试机制）](../04-operations/)** — 掌握生产环境传输操作

---

## 系列导航 / Series Nav

| 课程 | 主题 |
|------|------|
| 00 · 概念与架构 | Store-and-Forward, 术语 |
| 01 · 网络与安全 | 端口、防火墙、服务账户 |
| 02 · 安装配置 | HULFT8 双节点 Lab |
| **03 · 字符编码** | ← 当前课程 |
| 04 · 集信/配信实战 | 传输组、重试机制 |
| 05 · 作业联动 | JP1 集成、日志分析 |
| 06 · 云迁移 | HULFT Square, AWS VPC |
