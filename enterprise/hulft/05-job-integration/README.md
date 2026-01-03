# 05 · 作业连携与错误处理（JP1 联动 + 日志分析）

> **目标**：掌握 HULFT 与作业调度器集成及故障排查
> **前置**：[04 · 集信/配信实战](../04-operations/)
> **适用**：日本 SIer/银行 IT 岗位面试准备
> **时长**：约 90 分钟
> **费用**：使用 Lesson 02 部署的环境；完成后请参考 [02 · 安装配置](../02-installation/) 清理资源

---

> **版本说明**：
> - 本教程基于 **HULFT8**
> - **HULFT10** 已于 2024年12月发布
> - HULFT8 标准支持结束：2030年6月
> - JP1 示例基于 **V13.x**（V9 支持至 2026年3月）
> - 新项目建议评估 HULFT10

## 为什么 JP1 集成重要？

```
在日本银行/企业 IT 环境中：

• JP1 AJS (Automatic Job Scheduler) 是主流作业调度器
• 日本银行/大型企业广泛使用 JP1（日立制作所产品）
• HULFT 传输通常由 JP1 触发和监控
• 面试必考：「JP1とHULFTの連携経験はありますか？」
```

## 将完成的内容

1. 配置 JP1 触发 HULFT 作业
2. 理解 HULFT RC（Return Code）代码
3. 设计作业分支逻辑（成功/警告/失败）
4. 掌握日志分析和故障排查方法
5. 设计幂等（Idempotent）文件处理

---

## Step 1 — JP1 与 HULFT 集成概述

### JP1 AJS 简介

```
JP1 AJS (Automatic Job Scheduler)
├── 日立制作所开发
├── 日本企业标准作业调度器
├── 功能类似：
│   ├── cron（基础定时）
│   ├── Autosys（企业调度）
│   └── Control-M（企业调度）
└── 特点：
    ├── 可视化作业网络（Jobnet）
    ├── 依赖管理
    ├── 日历调度
    └── 集中监控
```

### 典型集成架构

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                      JP1 + HULFT 集成架构                                    │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│   ┌─────────────────────────────────────────────────────────────────────┐   │
│   │                        JP1 AJS Manager                               │   │
│   │                                                                     │   │
│   │   Jobnet: DAILY_BATCH_001                                           │   │
│   │   ┌─────────┐    ┌─────────┐    ┌─────────┐    ┌─────────┐        │   │
│   │   │ Job A   │───→│ Job B   │───→│ Job C   │───→│ Job D   │        │   │
│   │   │ ETL処理 │    │ HULFT   │    │ 後処理  │    │ 通知    │        │   │
│   │   └─────────┘    └────┬────┘    └─────────┘    └─────────┘        │   │
│   │                       │                                             │   │
│   └───────────────────────┼─────────────────────────────────────────────┘   │
│                           │                                                 │
│                           │ hulcmd -flowsend                                │
│                           ▼                                                 │
│   ┌─────────────────────────────────────────────────────────────────────┐   │
│   │                        HULFT Engine                                  │   │
│   │                                                                     │   │
│   │   RC=0 ──→ 成功，继续 Job C                                         │   │
│   │   RC=4 ──→ 警告，根据策略决定                                        │   │
│   │   RC≥8 ──→ 失败，跳转到错误处理                                      │   │
│   │                                                                     │   │
│   └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### JP1 作业定义示例

> **注意**：以下为**概念示例**（伪代码格式），展示 JP1 配置的逻辑结构。
> 实际 JP1 配置通过 **JP1/AJS3 - View** GUI 或专用定义文件完成，语法与此不同。

```
# JP1 Jobnet 定义（概念示例）

Jobnet: DAILY_SETTLEMENT
  Schedule: 23:00 daily
  Calendar: BANK_BUSINESS_DAYS

  Jobs:
    - Name: ETL_EXTRACT
      Type: UNIX_JOB
      Script: /opt/scripts/etl_extract.sh
      On_Success: HULFT_SEND
      On_Failure: ALERT_OPS

    - Name: HULFT_SEND
      Type: UNIX_JOB
      Script: /opt/scripts/hulft_wrapper.sh
      Args: DAILY_REPORT_001
      On_Success: POST_PROCESS
      On_Failure: HULFT_RETRY
      On_Warning: POST_PROCESS  # RC=4 时继续

    - Name: HULFT_RETRY
      Type: UNIX_JOB
      Script: /opt/scripts/hulft_wrapper.sh
      Args: DAILY_REPORT_001
      Retry_Count: 3
      Retry_Interval: 300
      On_Success: POST_PROCESS
      On_Failure: ALERT_OPS

    - Name: POST_PROCESS
      Type: UNIX_JOB
      Script: /opt/scripts/post_process.sh

    - Name: ALERT_OPS
      Type: MAIL
      To: ops-team@bank.co.jp
      Subject: "HULFT Transfer Failed"
```

---

## Step 2 — HULFT Return Code (RC) 详解

### RC 代码分类

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                      HULFT Return Code 体系                                  │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│   RC = 0        成功（Success）                                              │
│   ─────────────────────────────────────────────────────────                 │
│   传输完成，无错误                                                           │
│   JP1: 继续下一个 Job                                                       │
│                                                                             │
│   RC = 4        警告（Warning）                                              │
│   ─────────────────────────────────────────────────────────                 │
│   传输完成，但有警告                                                         │
│   例：可选文件不存在、部分记录跳过                                           │
│   JP1: 根据业务策略决定（继续或停止）                                        │
│                                                                             │
│   RC ≥ 8        错误（Error）                                               │
│   ─────────────────────────────────────────────────────────                 │
│   传输失败                                                                   │
│   JP1: 分支到错误处理或重试                                                  │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 常见 RC 代码

| RC | 类别 | 含义 | 典型原因 |
|----|------|------|----------|
| **0** | 成功 | 传输完成 | - |
| **4** | 警告 | 完成但有警告 | 可选文件缺失 |
| **8** | 错误 | 一般性失败 | 配置错误 |
| **1002** | 错误 | 连接失败 | 网络问题、对端未启动 |
| **2001** | 错误 | 认证失败 | 凭证错误 |
| **300x** | 错误 | 文件错误 | 文件不存在、权限不足 |
| **4xxx** | 错误 | 编码错误 | 转换失败、无法映射字符 |

### RC 处理策略

```bash
# 不同 RC 的处理策略示例

RC=0:
  → 正常继续
  → 记录成功日志

RC=4:
  → 检查具体警告原因
  → 业务关键文件：停止并告警
  → 可选文件：继续处理

RC=8:
  → 立即告警
  → 检查是否可重试
  → 记录详细错误信息

RC=1002 (连接失败):
  → 检查网络连通性
  → 检查对端 HULFT 状态
  → 等待后重试

RC=300x (文件错误):
  → 检查源文件是否存在
  → 检查文件权限
  → 检查磁盘空间
```

---

## Step 3 — Shell Wrapper 脚本

### 为什么需要 Wrapper？

```
直接在 JP1 中调用 hulcmd 的问题：
• RC 处理不够灵活
• 无法添加自定义日志
• 难以实现复杂的重试逻辑
• 无法进行预检查

使用 Shell Wrapper：
✅ 灵活的 RC 处理
✅ 自定义日志记录
✅ 预检查（文件存在、磁盘空间等）
✅ 复杂重试逻辑
✅ 审计追踪
```

### Wrapper 脚本模板

```bash
#!/bin/bash
#==============================================================================
# hulft_wrapper.sh - HULFT Transfer Wrapper for JP1
#==============================================================================
# Usage: hulft_wrapper.sh <TRANSFER_ID>
# Returns: 0=Success, 4=Warning, 8+=Error
#==============================================================================

set -o pipefail

# 配置
HULFT_HOME=/opt/hulft8
LOG_DIR=/var/log/hulft_jobs
TRANSFER_ID=$1
TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
LOG_FILE="${LOG_DIR}/${TRANSFER_ID}_${TIMESTAMP}.log"

#------------------------------------------------------------------------------
# 日志函数
#------------------------------------------------------------------------------
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1" | tee -a "$LOG_FILE" >&2
}

#------------------------------------------------------------------------------
# 预检查
#------------------------------------------------------------------------------
pre_check() {
    log "Starting pre-check for transfer: $TRANSFER_ID"

    # 检查 HULFT 是否运行
    if ! ${HULFT_HOME}/bin/hulstat > /dev/null 2>&1; then
        log_error "HULFT is not running"
        return 8
    fi

    # 检查磁盘空间（Spool 目录）
    SPOOL_USAGE=$(df ${HULFT_HOME}/spool | tail -1 | awk '{print $5}' | tr -d '%')
    if [ "$SPOOL_USAGE" -gt 90 ]; then
        log_error "Spool disk usage is ${SPOOL_USAGE}% (>90%)"
        return 8
    fi

    log "Pre-check passed"
    return 0
}

#------------------------------------------------------------------------------
# 主处理
#------------------------------------------------------------------------------
main() {
    log "=========================================="
    log "HULFT Transfer Started"
    log "Transfer ID: $TRANSFER_ID"
    log "=========================================="

    # 预检查
    pre_check
    PRE_RC=$?
    if [ $PRE_RC -ne 0 ]; then
        log_error "Pre-check failed with RC=$PRE_RC"
        return $PRE_RC
    fi

    # 执行传输
    log "Executing: hulcmd -flowsend $TRANSFER_ID"
    ${HULFT_HOME}/bin/hulcmd -flowsend "$TRANSFER_ID" >> "$LOG_FILE" 2>&1
    HULFT_RC=$?

    # RC 处理
    case $HULFT_RC in
        0)
            log "Transfer completed successfully (RC=0)"
            ;;
        4)
            log "Transfer completed with warning (RC=4)"
            # 记录警告详情
            grep -i "warning" ${HULFT_HOME}/log/hulft.log | tail -5 >> "$LOG_FILE"
            ;;
        *)
            log_error "Transfer failed (RC=$HULFT_RC)"
            # 记录错误详情
            grep -E "ERROR|RC=" ${HULFT_HOME}/log/hulft.log | tail -20 >> "$LOG_FILE"
            ;;
    esac

    log "=========================================="
    log "HULFT Transfer Ended with RC=$HULFT_RC"
    log "=========================================="

    return $HULFT_RC
}

#------------------------------------------------------------------------------
# 入口
#------------------------------------------------------------------------------
if [ -z "$TRANSFER_ID" ]; then
    echo "Usage: $0 <TRANSFER_ID>" >&2
    exit 8
fi

mkdir -p "$LOG_DIR"
main
exit $?
```

### 使用示例

```bash
# JP1 Job 配置
Job: HULFT_DAILY_REPORT
  Script: /opt/scripts/hulft_wrapper.sh
  Args: DAILY_REPORT_001

  # RC 分支
  RC=0: → NEXT_JOB
  RC=4: → NEXT_JOB  (或 WARNING_HANDLER)
  RC≥8: → ERROR_HANDLER
```

> 💡 **面试要点 #1**
>
> **问题**：「HULFTのRCをJP1の分岐処理（リトライ/中止）にどのようにマッピングしますか？」
>
> （中文参考：如何将 HULFT 的 RC 映射到 JP1 的分支处理（重试/中止）？）
>
> **期望回答**：
> - RC=0：继续下一个 Job
> - RC=4：根据策略决定（警告可能继续或停止）
> - RC≥8：分支到重试 Job 或中止 Jobnet
> - 用 Shell Wrapper 包装 hulcmd 进行精细控制
> - 记录所有 RC 到日志供审计

---

## Step 4 — 日志分析与故障排查

### 日志文件位置

```
/opt/hulft8/log/
├── hulft.log      # 主日志（传输记录、错误）
├── hulevt.log     # 事件日志（系统事件）
└── hulft_YYYYMMDD.log  # 按日期归档（如配置）

/opt/hulft8/spool/
└── <TRANSFER_ID>/
    └── transfer.log  # 单次传输详细日志
```

### 常用日志分析命令

```bash
#==============================================================================
# HULFT 日志分析常用命令
#==============================================================================

# 1. 查看最近的错误
grep -E "RC=[^0]|ERROR|FAIL" /opt/hulft8/log/hulft.log | tail -20

# 2. 查看特定传输的日志
grep "DAILY_REPORT_001" /opt/hulft8/log/hulft.log | tail -50

# 3. 查看特定时间段的日志
awk '/2024-12-08 23:/ {print}' /opt/hulft8/log/hulft.log

# 4. 统计各 RC 出现次数
grep -oE "RC=[0-9]+" /opt/hulft8/log/hulft.log | sort | uniq -c | sort -rn

# 5. 查看重试记录
grep -E "RETRY|retry" /opt/hulft8/log/hulft.log | tail -20

# 6. 查看编码转换错误
grep -E "code.?conv|encoding|mojibake|unmappable" /opt/hulft8/log/hulft.log

# 7. 实时监控日志
tail -f /opt/hulft8/log/hulft.log | grep --line-buffered -E "RC=|ERROR"
```

### 常见故障模式

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                      常见故障模式与排查                                      │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│   模式 1: 连接超时 (timeout)                                                │
│   ─────────────────────────────────────────────────────────────────────     │
│   日志: "connection timeout" / "no response"                                │
│   原因: 网络问题、对端未启动、防火墙                                        │
│   排查:                                                                     │
│     nc -zv <peer_ip> 8594    # 测试端口                                    │
│     ping <peer_ip>            # 测试网络                                    │
│     ssh peer "hulstat"        # 检查对端状态                                │
│                                                                             │
│   模式 2: 序列错误 (sequence error)                                         │
│   ─────────────────────────────────────────────────────────────────────     │
│   日志: "sequence error" / "duplicate detected"                             │
│   原因: NAT 问题、重复发送、时钟不同步                                      │
│   排查:                                                                     │
│     检查 NAT 配置                                                           │
│     比较两端时钟: date                                                      │
│     检查 管理情報 中的序列号                                                │
│                                                                             │
│   模式 3: Spool 空间不足                                                    │
│   ─────────────────────────────────────────────────────────────────────     │
│   日志: "cannot open spool" / "disk full"                                   │
│   原因: 磁盘满、权限问题                                                    │
│   排查:                                                                     │
│     df -h /opt/hulft8/spool                                                │
│     ls -la /opt/hulft8/spool                                               │
│                                                                             │
│   模式 4: 编码转换错误                                                      │
│   ─────────────────────────────────────────────────────────────────────     │
│   日志: "code conversion error" / "unmappable character"                    │
│   原因: 编码配置错误、無法映射的字符                                        │
│   排查:                                                                     │
│     检查源/目标编码配置                                                     │
│     检查服务账户 locale                                                     │
│     用 iconv 手动测试转换                                                   │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

> 💡 **面试要点 #2**
>
> **问题**：「受信時の文字コード変換エラーを確認するには、ログのどこを見ますか？」
>
> （中文参考：接收时发生编码转换错误，应该查看日志的哪里？）
>
> **期望回答**：
> - 主日志：`/opt/hulft8/log/hulft.log`
> - 搜索："code conversion error" 或 "unmappable character"
> - 检查 spool 目录下的单次传输日志
> - 验证服务账户的 locale 设置

---

## Step 5 — 幂等性设计（Idempotent Processing）

### 什么是幂等性？

```
幂等性 (Idempotence)：
同一操作执行多次，结果与执行一次相同。

为什么 HULFT 场景需要幂等性？
• 网络抖动导致重试
• JP1 作业重新执行
• 手动恢复操作
• ACK 丢失后的重发

非幂等的后果：
⚠️ 银行转账执行两次 = 资金错误
⚠️ 订单处理重复 = 客户投诉
⚠️ 报表重复统计 = 数据错误
```

### 幂等性设计模式

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                      幂等性设计模式                                          │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│   模式 1: 临时文件 + 原子移动                                               │
│   ─────────────────────────────────────────────────────────────────────     │
│                                                                             │
│   HULFT 接收 → /data/incoming/file.tmp                                     │
│                      │                                                      │
│                      ▼ 验证完成后                                           │
│                mv file.tmp file.csv  (原子操作)                             │
│                      │                                                      │
│                      ▼                                                      │
│                下游应用读取 file.csv                                        │
│                                                                             │
│   优点: 下游永远看不到不完整的文件                                          │
│                                                                             │
│   模式 2: 序列号检查                                                        │
│   ─────────────────────────────────────────────────────────────────────     │
│                                                                             │
│   接收文件 → 检查 管理情報 序列号                                           │
│                      │                                                      │
│            ┌────────┴────────┐                                              │
│            │                 │                                              │
│      新序列号            已处理序列号                                        │
│            │                 │                                              │
│            ▼                 ▼                                              │
│        正常处理          跳过（返回成功）                                    │
│                                                                             │
│   模式 3: Checksum 验证                                                     │
│   ─────────────────────────────────────────────────────────────────────     │
│                                                                             │
│   接收文件 → 计算 MD5/SHA256                                                │
│                      │                                                      │
│            ┌────────┴────────┐                                              │
│            │                 │                                              │
│      与记录不同           与记录相同                                         │
│      (新文件)            (重复文件)                                          │
│            │                 │                                              │
│            ▼                 ▼                                              │
│        正常处理          跳过处理                                            │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 实现示例

```bash
#!/bin/bash
#==============================================================================
# idempotent_receiver.sh - 幂等文件接收处理
#==============================================================================

INCOMING_DIR=/data/incoming
PROCESSED_DIR=/data/processed
CHECKSUM_DB=/data/.checksums

# 确保目录和文件存在
mkdir -p "$INCOMING_DIR" "$PROCESSED_DIR"
touch "$CHECKSUM_DB"

process_file() {
    local FILE=$1
    local CHECKSUM=$(md5sum "$FILE" | awk '{print $1}')
    local BASENAME=$(basename "$FILE")

    # 检查是否已处理
    if grep -q "$CHECKSUM" "$CHECKSUM_DB" 2>/dev/null; then
        echo "File already processed (duplicate): $BASENAME"
        rm -f "$FILE"  # 删除重复文件
        return 0  # 返回成功（幂等）
    fi

    # 处理文件（你的业务逻辑）
    echo "Processing new file: $BASENAME"
    # ... 业务处理 ...

    # 记录已处理
    echo "$CHECKSUM $BASENAME $(date '+%Y-%m-%d %H:%M:%S')" >> "$CHECKSUM_DB"

    # 移动到已处理目录
    mv "$FILE" "$PROCESSED_DIR/"

    return 0
}

# 处理所有新文件
for FILE in "$INCOMING_DIR"/*.csv; do
    [ -f "$FILE" ] && process_file "$FILE"
done
```

### JP1 重试的幂等考虑

```bash
# JP1 Jobnet 设计考虑

Jobnet: SETTLEMENT_PROCESS

  # 如果 Job 失败，JP1 可能重新执行整个 Jobnet
  # 设计时确保：

  Job: HULFT_RECEIVE
    # HULFT 本身有序列号去重
    # 重复接收同一文件 → 自动跳过

  Job: FILE_PROCESS
    # 应用层必须实现幂等
    # 方案：检查 checksum 或 处理标记

  Job: DB_UPDATE
    # 数据库操作必须幂等
    # 方案：使用 UPSERT / ON CONFLICT
    # 或：先检查是否已存在
```

> 💡 **面试要点 #3**
>
> **问题**：「HULFTを使用した冪等（べきとう）なファイル処理をどのように設計しますか？」
>
> （中文参考：如何设计使用 HULFT 的幂等文件处理？）
>
> **期望回答**：
> 1. 写入临时文件，完成后原子移动
> 2. 检查序列号跳过已处理的
> 3. Checksum 验证检测重复
> 4. JP1 只重试失败的步骤（不重跑全部）
> 5. 下游应用必须能优雅处理重复输入

---

## Step 6 — 实践：构建完整作业流程

### 场景：日次報表处理

```
需求：
1. 每天 23:00 从对端接收报表
2. 编码转换（SJIS → UTF-8）
3. 加载到数据库
4. 失败时通知运维
5. 所有步骤必须有日志
```

### 目录结构

> **参考脚本**：本课程提供可复用的脚本模板，位于
> `cloud-atlas/enterprise/hulft/05-job-integration/scripts/` 目录：
> - `common.sh` - 日志和通用函数
> - `load_to_db.sh` - 数据库加载 stub
> - `notify_ops.sh` - 通知脚本模板

```bash
/opt/batch/daily_report/
├── scripts/
│   ├── common.sh             # 通用函数（日志、检查）
│   ├── hulft_receive.sh      # HULFT 接收 wrapper
│   ├── convert_encoding.sh   # 编码转换
│   ├── load_to_db.sh         # 数据库加载
│   └── notify_ops.sh         # 通知脚本
├── logs/
│   └── YYYYMMDD/             # 按日期存放日志
├── incoming/                  # HULFT 接收目录
├── processed/                 # 处理完成目录
└── failed/                    # 失败文件目录
```

### 脚本实现

**hulft_receive.sh**
```bash
#!/bin/bash
source /opt/batch/daily_report/scripts/common.sh

TRANSFER_ID="DAILY_REPORT_RECEIVE"

log "Starting HULFT receive: $TRANSFER_ID"

# 执行接收（集信）
# 注意：集信（Pull）操作也使用 flowsend 命令，传输方向由 Transfer Definition 决定
# 官方文档中对应命令为 utlsend
/opt/hulft8/bin/hulcmd -flowsend "$TRANSFER_ID"
RC=$?

case $RC in
    0) log "Receive successful"; exit 0 ;;
    4) log "Receive completed with warning"; exit 4 ;;
    *) log_error "Receive failed RC=$RC"; exit 8 ;;
esac
```

**convert_encoding.sh**
```bash
#!/bin/bash
source /opt/batch/daily_report/scripts/common.sh

INCOMING=/opt/batch/daily_report/incoming
PROCESSED=/opt/batch/daily_report/processed

for FILE in "$INCOMING"/*.csv; do
    [ -f "$FILE" ] || continue

    BASENAME=$(basename "$FILE")
    log "Converting: $BASENAME"

    # SJIS → UTF-8
    iconv -f CP932 -t UTF-8 "$FILE" > "${PROCESSED}/${BASENAME}"

    if [ $? -eq 0 ]; then
        log "Conversion successful: $BASENAME"
        rm -f "$FILE"
    else
        log_error "Conversion failed: $BASENAME"
        mv "$FILE" /opt/batch/daily_report/failed/
        exit 8
    fi
done

exit 0
```

### cron/JP1 配置

```bash
# 如果没有 JP1，可用 cron 模拟

# crontab -e
# 每天 23:00 执行
0 23 * * * /opt/batch/daily_report/scripts/run_daily_batch.sh >> /var/log/daily_batch.log 2>&1
```

**run_daily_batch.sh**
```bash
#!/bin/bash
#==============================================================================
# 日次報表处理主脚本
#==============================================================================

SCRIPT_DIR=/opt/batch/daily_report/scripts
LOG_DIR=/opt/batch/daily_report/logs/$(date '+%Y%m%d')
mkdir -p "$LOG_DIR"

run_step() {
    local STEP_NAME=$1
    local SCRIPT=$2

    echo "[$(date)] Starting: $STEP_NAME"
    "$SCRIPT" >> "$LOG_DIR/${STEP_NAME}.log" 2>&1
    local RC=$?

    if [ $RC -ge 8 ]; then
        echo "[$(date)] FAILED: $STEP_NAME (RC=$RC)"
        "$SCRIPT_DIR/notify_ops.sh" "$STEP_NAME" "$RC"
        exit $RC
    fi

    echo "[$(date)] Completed: $STEP_NAME (RC=$RC)"
    return $RC
}

# 执行各步骤
run_step "hulft_receive" "$SCRIPT_DIR/hulft_receive.sh"
run_step "convert_encoding" "$SCRIPT_DIR/convert_encoding.sh"
run_step "load_to_db" "$SCRIPT_DIR/load_to_db.sh"

echo "[$(date)] Daily batch completed successfully"
exit 0
```

---

## 实践练习

### 练习 1：分析日志找出故障原因

**场景**：以下日志片段，找出故障原因：

```
2024-12-08 23:05:12 [HULFT] Transfer started: DAILY_REPORT_001
2024-12-08 23:05:13 [HULFT] Connecting to NODE_B (10.0.1.20:8594)
2024-12-08 23:05:43 [HULFT] Connection timeout
2024-12-08 23:05:43 [HULFT] Retry attempt 1/3
2024-12-08 23:06:43 [HULFT] Connection timeout
2024-12-08 23:06:43 [HULFT] Retry attempt 2/3
2024-12-08 23:07:43 [HULFT] Connection timeout
2024-12-08 23:07:43 [HULFT] Retry attempt 3/3
2024-12-08 23:08:43 [HULFT] Connection timeout
2024-12-08 23:08:43 [HULFT] Transfer failed RC=1002
```

<details>
<summary>点击查看答案</summary>

**故障原因**：连接超时 (RC=1002)

**排查步骤**：
1. 检查 NODE_B (10.0.1.20) 是否可达：`ping 10.0.1.20`
2. 检查端口是否开放：`nc -zv 10.0.1.20 8594`
3. 检查 NODE_B 上 HULFT 是否运行：`hulstat`
4. 检查防火墙规则

**可能原因**：
- NODE_B 的 HULFT 未启动
- 防火墙阻断了 8594 端口
- 网络故障

</details>

### 练习 2：设计重试策略

**场景**：设计一个适合银行日次批处理的重试策略

```
要求：
- 必须在 06:00 前完成
- 23:00 开始
- 每次重试间隔合理
- 多次失败后通知值班
```

<details>
<summary>点击查看参考设计</summary>

```
时间窗口：23:00 ~ 06:00 = 7 小时

重试策略设计：
- 第 1 轮：RETRY_COUNT=3, RETRY_INTERVAL=60 (3分钟)
- 等待 30 分钟
- 第 2 轮：RETRY_COUNT=3, RETRY_INTERVAL=120 (6分钟)
- 等待 1 小时
- 第 3 轮：RETRY_COUNT=3, RETRY_INTERVAL=300 (15分钟)
- 失败 → 通知夜间值班

总时间估算：
第 1 轮最大：3 分钟
等待：30 分钟
第 2 轮最大：6 分钟
等待：60 分钟
第 3 轮最大：15 分钟
通知/处理：30 分钟

总计 < 3 小时，在 06:00 前有足够处理时间
```

</details>

---

## 常见错误

| 错误 | 后果 | 预防 |
|------|------|------|
| 忽略 RC=4 警告 | 数据可能不完整 | 明确定义 RC=4 处理策略 |
| 不用 Wrapper 包装 | 无法精细控制 RC | 所有 HULFT 调用用 Wrapper |
| 日志轮转删除证据 | 无法事后分析 | 保留足够天数的日志 |
| 非幂等处理 | 重试导致重复处理 | 实现幂等设计模式 |

---

## 小结

| 主题 | 要点 |
|------|------|
| JP1 集成 | 用 Jobnet 编排，RC 分支控制流程 |
| RC 代码 | 0=成功, 4=警告, ≥8=错误 |
| Shell Wrapper | 包装 hulcmd，精细控制 |
| 日志分析 | 熟悉日志位置和常见故障模式 |
| 幂等性 | 临时文件+原子移动，序列号检查 |

---

## 下一步

完成本课后，请继续：

- **[06 · 云迁移：HULFT Square / AWS VPC 设计](../06-cloud-migration/)** — 现代云环境中的 HULFT 部署

---

## 系列导航 / Series Nav

| 课程 | 主题 |
|------|------|
| 00 · 概念与架构 | Store-and-Forward, 术语 |
| 01 · 网络与安全 | 端口、防火墙、服务账户 |
| 02 · 安装配置 | HULFT8 双节点 Lab |
| 03 · 字符编码 | SJIS↔UTF-8, EBCDIC |
| 04 · 集信/配信实战 | 传输组、重试机制 |
| **05 · 作业联动** | ← 当前课程 |
| 06 · 云迁移 | HULFT Square, AWS VPC |
