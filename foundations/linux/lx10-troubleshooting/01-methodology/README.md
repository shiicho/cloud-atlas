# 01 - 故障排查方法论（Troubleshooting Methodology）

> **目标**：掌握系统性故障排查的思维框架，从"碰运气"升级为"证据驱动"  
> **前置**：LX05 systemd 基础、LX09 性能分析基础  
> **时间**：2.5 小时  
> **核心理念**：本课不教任何工具命令，只教思维框架  

---

## 将学到的内容

1. 掌握 USE 和 RED 方法论
2. 理解系统性故障排查的四步流程
3. 学会使用决策树而非随机尝试
4. 理解日本 障害対応 工作流程
5. 识别并避免常见排查反模式

---

## 先跑起来！（10 分钟）

> 在学习方法论之前，先体验"快速诊断"的威力。  
> 这 4 条命令立即告诉你系统有什么问题。  

```bash
# 最近 1 小时的错误日志
journalctl -p err --since '1 hour ago'

# 最近的内核消息（OOM、磁盘错误等）
dmesg | tail -20

# 失败的服务
systemctl --failed

# 内存压力指标 (PSI - Pressure Stall Information)
cat /proc/pressure/memory
```

**你刚刚用 4 条命令找到了潜在问题！**

这就是系统性排查的第一步。现在让我们学习完整的方法论，理解为什么要这样做，以及如何更深入地诊断。

---

## Step 1 -- 为什么需要方法论？（15 分钟）

### 1.1 随机尝试 vs 系统性排查

当服务器出问题时，新手通常这样做：

```
问题发生 → 感觉像网络问题 → 重启网络 → 没用 → 重启服务 → 没用 → 重启服务器 → 好了！
```

问题：
- 不知道根因是什么
- 下次还会发生
- 重启销毁了诊断证据
- 无法写出有价值的 RCA 报告

系统性排查应该这样做：

```
问题发生 → 采集证据 → 形成假设 → 验证假设 → 修复 → 记录 → 复盘
```

### 1.2 方法论的价值

<!-- DIAGRAM: methodology-value -->
```
┌──────────────────────────────────────────────────────────────────┐
│                 故障排查方法论的价值                               │
├──────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌──────────────┐      ┌──────────────┐      ┌──────────────┐   │
│  │   随机尝试   │      │   方法论     │      │   结果       │   │
│  │              │      │              │      │              │   │
│  │ • 碰运气     │  →   │ • 框架驱动   │  →   │ • 可复现     │   │
│  │ • 浪费时间   │      │ • 证据驱动   │      │ • 可预防     │   │
│  │ • 无法复盘   │      │ • 假设验证   │      │ • 可记录     │   │
│  │ • 问题再发   │      │ • 文档完整   │      │ • 持续改进   │   │
│  └──────────────┘      └──────────────┘      └──────────────┘   │
│                                                                  │
│  关键转变：从"修好了"到"知道为什么修好了"                         │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘
```
<!-- /DIAGRAM -->

---

## Step 2 -- USE 方法论（20 分钟）

### 2.1 什么是 USE？

USE 是 Brendan Gregg（Netflix 性能工程师）提出的系统性能分析方法论。

| 字母 | 含义 | 检查什么 |
|------|------|----------|
| **U** - Utilization | 利用率 | 资源忙碌的时间百分比 |
| **S** - Saturation | 饱和度 | 等待队列的长度 |
| **E** - Errors | 错误数 | 错误事件的数量 |

### 2.2 对每种资源应用 USE

<!-- DIAGRAM: use-methodology -->
```
┌─────────────────────────────────────────────────────────────────────┐
│                    USE 方法论 - 资源检查矩阵                         │
├───────────┬───────────────────┬──────────────────┬─────────────────┤
│ 资源      │ Utilization       │ Saturation       │ Errors          │
│           │ (利用率)          │ (饱和度)         │ (错误)          │
├───────────┼───────────────────┼──────────────────┼─────────────────┤
│           │ top (us+sy)       │ vmstat r column  │ dmesg           │
│ CPU       │ mpstat -P ALL     │ /proc/pressure/  │ MCE 错误        │
│           │                   │   cpu            │                 │
├───────────┼───────────────────┼──────────────────┼─────────────────┤
│           │ free -m           │ vmstat si/so     │ dmesg OOM       │
│ Memory    │ /proc/meminfo     │ /proc/pressure/  │ EDAC 错误       │
│           │                   │   memory         │                 │
├───────────┼───────────────────┼──────────────────┼─────────────────┤
│           │ iostat -xz        │ avgqu-sz         │ dmesg I/O       │
│ Disk I/O  │ sar -d            │ /proc/pressure/  │ smartctl        │
│           │                   │   io             │                 │
├───────────┼───────────────────┼──────────────────┼─────────────────┤
│           │ sar -n DEV        │ ifconfig drops   │ ip -s link      │
│ Network   │ ss -s             │ netstat -s       │ ethtool -S      │
│           │                   │ retransmits      │                 │
└───────────┴───────────────────┴──────────────────┴─────────────────┘
```
<!-- /DIAGRAM -->

### 2.3 USE 实战示例

**场景：服务器响应变慢**

```bash
# Step 1: CPU - Utilization
top -bn1 | head -5
# 看 %Cpu(s): us (user) + sy (system)

# Step 2: CPU - Saturation
vmstat 1 5
# 看 r 列（等待 CPU 的进程数）
# r > CPU 核数 = CPU 饱和

# Step 3: CPU - Errors
dmesg | grep -i 'mce\|error\|fail' | tail -10

# Step 4: Memory - Utilization
free -m
# available 比 total 小多少

# Step 5: Memory - Saturation
vmstat 1 5
# 看 si/so 列（swap in/out），非零 = 内存压力

# Step 6: Memory - Errors
dmesg | grep -i 'oom\|memory'

# 继续 Disk I/O、Network...
```

**USE 的核心价值**：系统地检查每种资源的三个维度，不遗漏任何方向。

---

## Step 3 -- RED 方法论（15 分钟）

### 3.1 什么是 RED？

RED 是 Tom Wilkie（Grafana Labs）提出的服务层面分析方法论。

| 字母 | 含义 | 检查什么 |
|------|------|----------|
| **R** - Rate | 请求速率 | 每秒请求数 (RPS) |
| **E** - Errors | 错误率 | 错误请求的百分比 |
| **D** - Duration | 响应时间 | 请求处理延迟 |

### 3.2 USE vs RED：何时使用哪个？

<!-- DIAGRAM: use-vs-red -->
```
┌──────────────────────────────────────────────────────────────────┐
│                    USE vs RED 适用场景                            │
├──────────────────────────────────────────────────────────────────┤
│                                                                  │
│     基础设施层 (Infrastructure)          服务层 (Services)       │
│     ┌─────────────────────────┐         ┌────────────────────┐  │
│     │                         │         │                    │  │
│     │   CPU, Memory, Disk     │         │   Web Server       │  │
│     │   Network Interface     │         │   API Service      │  │
│     │   Kernel Resources      │         │   Database Query   │  │
│     │                         │         │   Message Queue    │  │
│     └───────────┬─────────────┘         └──────────┬─────────┘  │
│                 │                                   │            │
│                 ▼                                   ▼            │
│         ┌───────────────┐                 ┌───────────────┐     │
│         │  USE 方法论   │                 │  RED 方法论   │     │
│         │               │                 │               │     │
│         │ Utilization   │                 │ Rate          │     │
│         │ Saturation    │                 │ Errors        │     │
│         │ Errors        │                 │ Duration      │     │
│         └───────────────┘                 └───────────────┘     │
│                                                                  │
│  经验法则：                                                       │
│  • 资源问题（CPU/内存/磁盘）→ USE                                 │
│  • 服务问题（API/Web/数据库）→ RED                                │
│  • 两者结合：RED 发现服务慢 → USE 找资源瓶颈                      │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘
```
<!-- /DIAGRAM -->

### 3.3 RED 实战示例

**场景：API 响应变慢**

```bash
# Rate: 查看请求速率
tail -f /var/log/nginx/access.log | pv -l -i 5 > /dev/null
# 或分析日志
awk '{print $4}' /var/log/nginx/access.log | cut -d: -f1-3 | uniq -c | tail -10

# Errors: 查看错误率
grep -E 'HTTP/(1.1|2) (4|5)[0-9]{2}' /var/log/nginx/access.log | wc -l
# 4xx = 客户端错误, 5xx = 服务端错误

# Duration: 如果日志包含响应时间
awk '{print $NF}' /var/log/nginx/access.log | sort -n | tail -20
# 或使用监控工具 (Prometheus, Grafana)
```

---

## Step 4 -- 四步排查流程（20 分钟）

### 4.1 完整流程图

<!-- DIAGRAM: four-step-process -->
```
┌──────────────────────────────────────────────────────────────────┐
│                    四步故障排查流程                               │
├──────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌─────────────┐   ┌─────────────┐   ┌─────────────┐   ┌──────┐ │
│  │ 1. 定义问题 │ → │ 2. 收集信息 │ → │ 3. 验证假设 │ → │4.记录│ │
│  └─────────────┘   └─────────────┘   └─────────────┘   └──────┘ │
│        │                 │                 │               │     │
│        ▼                 ▼                 ▼               ▼     │
│  ┌─────────────┐   ┌─────────────┐   ┌─────────────┐   ┌──────┐ │
│  │ • 什么不工作│   │ • 时间同步? │   │ • 一次改一处│   │• 时间│ │
│  │ • 什么时候  │   │ • 日志检查  │   │ • 记录当前态│   │  线  │ │
│  │ • 影响范围  │   │ • 资源状态  │   │ • 验证效果  │   │• 根因│ │
│  │ • 最近变更? │   │ • 最近变更  │   │ • 无效则回滚│   │• 预防│ │
│  └─────────────┘   └─────────────┘   └─────────────┘   └──────┘ │
│                                                                  │
│                          ↑                                       │
│                          │                                       │
│                    假设不成立时回退                               │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘
```
<!-- /DIAGRAM -->

### 4.2 Step 1: 定义问题

**关键问题清单**：

| 问题 | 为什么重要 |
|------|------------|
| 什么不工作？ | 准确描述症状，避免假设 |
| 什么时候开始的？ | 缩小时间范围，便于日志分析 |
| 影响范围多大？ | 单用户？单服务？全站？ |
| 最近有什么变更？ | 变更是 80% 故障的原因 |
| 能复现吗？ | 复现 = 可调试 |

**反模式**：跳过定义，直接开始修

### 4.3 Step 2: 收集信息

**第一件事：检查时间同步！**

```bash
# 检查系统时间
timedatectl

# 检查 NTP 同步状态
chronyc tracking
# 或
ntpq -p
```

**为什么时间同步这么重要？**

- 时钟漂移导致 TLS/SSL 握手失败（证书"过期"）
- 日志时间戳无法关联（多服务器时间线混乱）
- Kerberos 认证失败
- 分布式系统一致性问题

**收集信息清单**：

```bash
# 1. 时间同步（第一步！）
timedatectl
chronyc tracking

# 2. 日志检查
journalctl -p err --since '1 hour ago'
journalctl -u <问题服务> --since '1 hour ago'
dmesg | tail -50

# 3. 资源状态（USE 方法）
top -bn1 | head -20
free -m
df -hT
iostat -xz 1 3

# 4. 服务状态
systemctl status <服务名>
systemctl --failed

# 5. 网络状态
ss -tulpn
ping <目标>
```

### 4.4 Step 3: 验证假设

**黄金法则：一次只改一处**

```
假设 A → 修改 A → 验证 → 有效？→ 记录，继续 Step 4
                      ↓
                    无效？→ 回滚 A → 假设 B → ...
```

**反模式**：
- 同时改多处配置（无法确定哪个有效）
- 改了不回滚（累积问题）
- 不验证就宣布"修好了"

### 4.5 Step 4: 文档记录

**必须记录的内容**：

| 项目 | 内容 |
|------|------|
| 时间线 | 发现时间、各操作时间、恢复时间 |
| 症状 | 用户看到什么，监控显示什么 |
| 根因 | 真正的原因（不是症状） |
| 修复步骤 | 具体执行了什么命令/操作 |
| 预防措施 | 如何防止再次发生 |

---

## Step 5 -- 证据保存：采集证据再行动（20 分钟）

### 5.1 核心原则

> **采集证据再行动，绝不盲目重启**  
> Collect BEFORE you fix  

重启会销毁：
- 内存中的进程状态
- 网络连接信息
- 临时文件和缓存
- 未持久化的日志
- `/proc` 下的运行时数据

**一旦丢失，RCA 无法进行。**

### 5.2 证据采集清单

| 证据类型 | 命令 | 保存什么 |
|----------|------|----------|
| 错误截图 | 截图/复制 | 错误消息原文 |
| 进程状态 | `ps auxf` | 进程树和资源使用 |
| 网络状态 | `ss -tulpn` | 监听端口和连接 |
| 内存状态 | `free -m`, `vmstat 1 5` | 内存使用和压力 |
| 压力指标 | `cat /proc/pressure/*` | PSI 压力数据 |
| 系统日志 | `journalctl --since '1h'` | 近期日志 |
| 内核日志 | `dmesg` | OOM、磁盘错误等 |

### 5.3 证据采集脚本

将此脚本保存为 `/usr/local/bin/collect-evidence.sh`：

```bash
#!/bin/bash
# Evidence collection script - run BEFORE reboot
# 证据采集脚本 - 重启前运行
# Usage: sudo collect-evidence.sh

set -e

# Create timestamped evidence directory
EVIDENCE_DIR="/tmp/evidence-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$EVIDENCE_DIR"

echo "============================================"
echo "Evidence Collection Script"
echo "Saving to: $EVIDENCE_DIR"
echo "============================================"

# System information
echo "[1/10] Collecting system info..."
uname -a > "$EVIDENCE_DIR/uname.txt"
uptime > "$EVIDENCE_DIR/uptime.txt"

# Time sync status
echo "[2/10] Collecting time sync status..."
timedatectl > "$EVIDENCE_DIR/timedatectl.txt" 2>&1 || true
chronyc tracking > "$EVIDENCE_DIR/chronyc.txt" 2>&1 || true

# Process status
echo "[3/10] Collecting process status..."
ps auxf > "$EVIDENCE_DIR/ps.txt"
top -bn1 > "$EVIDENCE_DIR/top.txt"

# Network status
echo "[4/10] Collecting network status..."
ss -tulpn > "$EVIDENCE_DIR/ss.txt"
ss -s > "$EVIDENCE_DIR/ss-stats.txt"
ip addr > "$EVIDENCE_DIR/ip-addr.txt"
ip route > "$EVIDENCE_DIR/ip-route.txt"

# Open files
echo "[5/10] Collecting open files (may take time)..."
lsof > "$EVIDENCE_DIR/lsof.txt" 2>/dev/null || true

# Memory status
echo "[6/10] Collecting memory status..."
free -m > "$EVIDENCE_DIR/free.txt"
vmstat 1 5 > "$EVIDENCE_DIR/vmstat.txt"
cat /proc/meminfo > "$EVIDENCE_DIR/meminfo.txt"

# Pressure Stall Information (PSI)
echo "[7/10] Collecting pressure info..."
if [ -d /proc/pressure ]; then
    cat /proc/pressure/cpu > "$EVIDENCE_DIR/pressure-cpu.txt"
    cat /proc/pressure/memory > "$EVIDENCE_DIR/pressure-memory.txt"
    cat /proc/pressure/io > "$EVIDENCE_DIR/pressure-io.txt"
fi

# Disk status
echo "[8/10] Collecting disk status..."
df -hT > "$EVIDENCE_DIR/df.txt"
iostat -xz 1 3 > "$EVIDENCE_DIR/iostat.txt" 2>/dev/null || true

# Kernel messages
echo "[9/10] Collecting kernel messages..."
dmesg > "$EVIDENCE_DIR/dmesg.txt"

# Journal logs
echo "[10/10] Collecting journal logs..."
journalctl --since '1 hour ago' > "$EVIDENCE_DIR/journal-1h.txt" 2>/dev/null || true
journalctl -p err --since '1 hour ago' > "$EVIDENCE_DIR/journal-errors.txt" 2>/dev/null || true

# Failed services
systemctl --failed > "$EVIDENCE_DIR/failed-services.txt" 2>/dev/null || true

# Create summary
echo "============================================" > "$EVIDENCE_DIR/SUMMARY.txt"
echo "Evidence collected at: $(date)" >> "$EVIDENCE_DIR/SUMMARY.txt"
echo "Hostname: $(hostname)" >> "$EVIDENCE_DIR/SUMMARY.txt"
echo "============================================" >> "$EVIDENCE_DIR/SUMMARY.txt"
ls -la "$EVIDENCE_DIR" >> "$EVIDENCE_DIR/SUMMARY.txt"

echo ""
echo "============================================"
echo "Evidence collection complete!"
echo "Location: $EVIDENCE_DIR"
echo "============================================"
echo ""
echo "Files collected:"
ls -lh "$EVIDENCE_DIR"
echo ""
echo "Now you can safely reboot if needed."
```

**使用方法**：

```bash
# 保存脚本
sudo vim /usr/local/bin/collect-evidence.sh
# 粘贴上述内容

# 设置执行权限
sudo chmod +x /usr/local/bin/collect-evidence.sh

# 故障时运行
sudo collect-evidence.sh

# 然后再考虑重启
```

---

## Step 6 -- 主决策树（15 分钟）

### 6.1 故障排查入口决策树

当问题发生时，使用此决策树确定排查方向：

<!-- DIAGRAM: main-decision-tree -->
```
┌──────────────────────────────────────────────────────────────────┐
│                    故障排查主决策树                               │
├──────────────────────────────────────────────────────────────────┤
│                                                                  │
│                        问题发生                                   │
│                           │                                      │
│                           ▼                                      │
│           ┌───────────────────────────────┐                      │
│           │ 系统可以 SSH/控制台访问吗？   │                      │
│           └───────────────┬───────────────┘                      │
│                           │                                      │
│              ┌────────────┴────────────┐                         │
│              │ No                      │ Yes                     │
│              ▼                         ▼                         │
│     ┌─────────────────┐      ┌─────────────────────────┐        │
│     │ 启动故障        │      │ 系统可访问              │        │
│     │ → Lesson 02     │      │                         │        │
│     │ (GRUB/initramfs)│      └───────────┬─────────────┘        │
│     └─────────────────┘                  │                       │
│                                          ▼                       │
│                        ┌───────────────────────────────┐        │
│                        │ 是性能问题吗？               │        │
│                        │ (响应慢、CPU高、内存满)      │        │
│                        └───────────────┬───────────────┘        │
│                                        │                         │
│                           ┌────────────┴────────────┐            │
│                           │ Yes                     │ No         │
│                           ▼                         ▼            │
│                  ┌─────────────────┐    ┌─────────────────────┐ │
│                  │ 性能问题        │    │ 是连通性问题吗？    │ │
│                  │ → Lesson 06     │    │ (ping不通、端口不通)│ │
│                  │ (USE 方法)      │    └───────────┬─────────┘ │
│                  └─────────────────┘                │            │
│                                         ┌───────────┴───────┐   │
│                                         │ Yes               │No │
│                                         ▼                   ▼   │
│                               ┌─────────────────┐ ┌──────────┐ │
│                               │ 网络问题        │ │服务故障  │ │
│                               │ → Lesson 04     │ │→Lesson 03│ │
│                               │ (分层诊断)      │ │(systemd) │ │
│                               └─────────────────┘ └──────────┘ │
│                                                                  │
│  关键提醒：                                                       │
│  • 进入任何分支前，先运行证据采集脚本                             │
│  • 检查时间同步（timedatectl, chronyc）                           │
│  • 询问"最近有什么变更？"                                         │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘
```
<!-- /DIAGRAM -->

### 6.2 决策树练习

**练习：根据症状选择诊断路径**

| # | 症状描述 | 诊断路径 |
|---|----------|----------|
| 1 | 重启后服务器进入 Emergency Mode | 启动故障 (Lesson 02) |
| 2 | Web 服务返回 502 Bad Gateway | 服务故障 (Lesson 03) |
| 3 | ping 目标服务器超时 | 网络问题 (Lesson 04) |
| 4 | df 显示磁盘 100%，但 du 只统计到 40% | 存储问题 (Lesson 05) |
| 5 | Load Average 40+，但 CPU 使用率接近 0% | 性能问题 (Lesson 06) |
| 6 | 应用日志显示 "Connection timed out" | 先网络(L4)，再服务(L7) |
| 7 | systemctl status 显示 active，但端口未监听 | 服务故障 (Lesson 03) |
| 8 | dmesg 显示 "Out of memory: Killed process" | 性能问题 (Lesson 06) |

---

## Step 7 -- 反模式识别（15 分钟）

### 7.1 方法论反模式

| 反模式 | 错误做法 | 后果 | 正确做法 |
|--------|----------|------|----------|
| **先重启再分析** | 不采集证据直接重启 | 丢失诊断线索，无法 RCA | 先采集 ps, ss, dmesg, journal |
| **同时改多处** | 一次修改多个配置 | 不知道哪个修复有效 | 一次改一处，验证后再改下一处 |
| **只盯网络** | 直接假设是网络问题 | 浪费时间在错误方向 | 从应用层日志开始排查 |
| **忽略最近变更** | 不问"最近改了什么" | 错过最可能的原因 | 总是问：最近有什么变更？ |
| **忽略时间同步** | 不检查系统时钟 | TLS 失败、日志无法关联 | 第一步检查 timedatectl |

### 7.2 RCA 反模式

| 反模式 | 错误做法 | 正确做法 |
|--------|----------|----------|
| **停在症状** | "根因是 500 错误" | 问 5 次"为什么"直到系统层面 |
| **混淆触发器和根因** | "根因是流量激增" | 流量是触发器，根因是系统无法应对流量 |
| **指责个人** | "根因是小王配错了" | 问"什么流程允许这个错误发生？" |

### 7.3 真实案例分析

**场景**：周一早上，API 服务返回大量 500 错误。

**错误排查路径**：
```
看到 500 错误 → 觉得是数据库问题 → 重启数据库 → 还是报错
→ 觉得是网络问题 → 检查防火墙 → 没发现问题
→ 重启 API 服务器 → 好了！
→ 报告：原因不明，已重启修复
```

**正确排查路径**：
```
看到 500 错误 → 检查时间同步 → 正常
→ 检查 API 日志 → "disk full" 错误
→ 检查磁盘 → df 显示 100%
→ 检查大文件 → /var/log/app.log 50GB
→ 根因：日志轮转配置错误，日志文件无限增长
→ 修复：配置 logrotate，清理旧日志
→ 预防：添加磁盘使用率监控告警
```

---

## Step 8 -- 日本 IT 职场：障害対応（20 分钟）

### 8.1 日本企业的故障响应流程

在日本 IT 企业，故障响应有一套标准化流程：

<!-- DIAGRAM: japan-incident-flow -->
```
┌──────────────────────────────────────────────────────────────────┐
│               日本企业 障害対応 流程                              │
├──────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌──────────┐    ┌──────────┐    ┌──────────┐    ┌──────────┐  │
│  │ 検知     │ →  │ 報告     │ →  │ 対応     │ →  │ 報告書   │  │
│  │ (kenchi) │    │ (houkoku)│    │ (taio)   │    │          │  │
│  │ 发现     │    │ 上报     │    │ 处理     │    │ 文档化   │  │
│  └──────────┘    └──────────┘    └──────────┘    └──────────┘  │
│       │               │               │               │         │
│       ▼               ▼               ▼               ▼         │
│  • 監視アラート     • 報連相       • 一次対応       • 障害報告書│
│  • ユーザー報告     • エスカレ     • 暫定対応       • 時系列    │
│                       ーション     • 恒久対策       • 再発防止  │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘
```
<!-- /DIAGRAM -->

### 8.2 核心日语术语

| 日语 | 读音 | 含义 | 使用场景 |
|------|------|------|----------|
| **障害対応** | shougai taiou | 故障处理 | "障害対応中です" (正在处理故障) |
| **報連相** | hourensou | 报告-联络-相谈 | 沟通的黄金法则 |
| **一次対応** | ichiji taiou | 初步处理 | 恢复服务的临时措施 |
| **暫定対応** | zantei taiou | 临时措施 | workaround |
| **恒久対策** | koukyuu taisaku | 永久修复 | 根本解决方案 |
| **再発防止** | saihatsu boushi | 防止再发 | RCA 中的 action items |
| **エスカレーション** | esukareshon | 升级 | 问题上报给上级 |
| **切り分け** | kiriwake | 问题隔离 | 缩小问题范围 |
| **障害報告書** | shougai houkokusho | 故障报告 | 正式的事后文档 |

### 8.3 報連相（Ho-Ren-So）

**報連相** 是日本职场沟通的核心原则，在故障处理中尤为重要：

| 要素 | 含义 | 故障处理中的应用 |
|------|------|------------------|
| **報**告 (Houkoku) | 报告 | 发现问题立即上报，不要等"搞清楚再说" |
| **連**絡 (Renraku) | 联络 | 定期更新进度，即使没有新进展 |
| **相**談 (Soudan) | 商量 | 不确定时主动请教，不要自己扛 |

**重要**：沉默比失败更糟糕。定期更新状态，即使只是"还在排查中"。

### 8.4 エスカレーション（升级）时机

什么时候应该升级问题？

| 情况 | 是否升级 | 说明 |
|------|----------|------|
| 30 分钟内无法定位问题 | **升级** | 及早求助 |
| 问题影响范围扩大 | **升级** | 需要更多资源 |
| 需要其他团队协助 | **升级** | 跨团队协调 |
| SLA 即将违约 | **升级** | 管理层需要知情 |
| 自己能在 10 分钟内解决 | 继续处理 | 但要报告进度 |

### 8.5 障害報告書（故障报告）模板

日本企业通常要求正式的故障报告。以下是标准模板：

```markdown
# 障害報告書

## 1. 概要
- 発生日時: 2026-01-10 14:30 (JST)
- 復旧日時: 2026-01-10 15:45 (JST)
- 影響範囲: 本番 API サーバー
- 影響程度: Critical（サービス完全停止）

## 2. 時系列 (Timeline)
| 時刻 (JST) | 事象 |
|------------|------|
| 14:30 | 監視アラート発報（API 応答なし）|
| 14:35 | 担当者 A、初動対応開始 |
| 14:40 | ディスク使用率 100% を確認 |
| 14:50 | 大容量ログファイルを特定 |
| 15:00 | ログファイル削除、サービス再起動 |
| 15:15 | 動作確認完了 |
| 15:45 | 正常復旧宣言 |

## 3. 根本原因 (Root Cause)
logrotate 設定漏れにより、アプリケーションログが
無限に肥大化。ディスクフル発生。

## 4. 対応内容
### 暫定対応 (Workaround)
- 大容量ログファイルを手動削除
- API サービス再起動

### 恒久対策 (Permanent Fix)
- logrotate 設定を追加（日次ローテーション、7世代保持）
- ディスク使用率アラートを 80% に設定

## 5. 再発防止策
| 対策 | 担当者 | 期限 |
|------|--------|------|
| logrotate 設定のコードレビュー必須化 | チームリード | 2026-01-17 |
| 全サーバーのディスク監視見直し | インフラ担当 | 2026-01-24 |
| 本番環境チェックリスト更新 | DevOps | 2026-01-31 |
```

---

## 动手实验：决策树练习（20 分钟）

### 实验 1：症状分类练习

对于以下每个症状，确定：
1. 应该使用哪个诊断路径？
2. 首先检查什么？
3. 需要什么证据？

| 症状 | 你的答案 |
|------|----------|
| 服务器重启后挂在 GRUB 提示符 | |
| nginx 返回 504 Gateway Timeout | |
| 用户报告 SSH 连接被拒绝 | |
| top 显示 wa (I/O wait) 90% | |
| 应用启动需要 30 秒（之前只需 2 秒） | |

**参考答案**：

<details>
<summary>点击查看答案</summary>

1. **GRUB 提示符** → 启动故障 (Lesson 02)
   - 首先：检查 GRUB 配置
   - 证据：grub> 输出截图

2. **504 Gateway Timeout** → 服务故障 (Lesson 03)
   - 首先：检查后端服务状态 (`systemctl status`)
   - 证据：nginx error.log, 后端服务日志

3. **SSH 连接被拒绝** → 可能是网络或服务问题
   - 首先：ping 测试 → 通则检查 sshd 服务
   - 证据：`ss -tlnp | grep 22`, `journalctl -u sshd`

4. **I/O wait 90%** → 性能问题 (Lesson 06)
   - 首先：`iostat -xz 1 3` 查看哪个磁盘繁忙
   - 证据：iostat, iotop, dmesg 磁盘错误

5. **应用启动慢** → 需要 strace 追踪 (Lesson 08)
   - 首先：`strace -tt -T <command>` 看阻塞在哪
   - 证据：strace 输出，可能是 DNS 或磁盘 I/O

</details>

### 实验 2：编写证据采集脚本

1. 将本课提供的 `collect-evidence.sh` 脚本保存到你的系统
2. 运行一次，检查输出
3. 添加你认为有用的额外信息收集

```bash
# 保存脚本
sudo vim /usr/local/bin/collect-evidence.sh

# 运行测试
sudo collect-evidence.sh

# 查看收集的证据
ls -la /tmp/evidence-*
```

---

## 检查清单

完成本课后，你应该能够：

- [ ] 解释 USE 方法论的三个维度（Utilization, Saturation, Errors）
- [ ] 解释 RED 方法论的三个指标（Rate, Errors, Duration）
- [ ] 说明何时使用 USE vs RED
- [ ] 描述四步排查流程（定义-收集-验证-记录）
- [ ] 解释为什么要先检查时间同步
- [ ] 运行证据采集脚本并解释每项数据的意义
- [ ] 使用决策树确定问题的诊断方向
- [ ] 识别至少 3 个排查反模式
- [ ] 解释日本 報連相 原则在故障处理中的应用
- [ ] 阅读并理解日语 障害報告書

---

## 本课小结

| 概念 | 要点 |
|------|------|
| USE 方法论 | 资源维度：Utilization, Saturation, Errors |
| RED 方法论 | 服务维度：Rate, Errors, Duration |
| 四步流程 | 定义 → 收集 → 验证 → 记录 |
| 时间同步 | 第一步检查！时钟漂移导致 TLS 失败、日志混乱 |
| 证据保存 | 采集证据再行动，绝不盲目重启 |
| 决策树 | 系统性选择诊断路径，不随机尝试 |
| 報連相 | 报告-联络-商量，沉默比失败更糟 |
| 障害報告書 | 正式故障报告，包含时间线和预防措施 |

**核心理念**：

> 方法论驱动，工具只是手段。  
> 证据先于行动。  
> 一次改一处。  
> 沟通和记录同样重要。  

---

## 面试准备

### よくある質問（常见问题）

**Q: トラブルシューティングの基本的な流れを説明してください。**

A: 基本的な流れは 4 ステップです：
1. **問題定義**：症状を正確に把握し、影響範囲を確認
2. **情報収集**：ログ、リソース状態、最近の変更を確認。まず時刻同期をチェック
3. **仮説検証**：一つずつ変更して効果を確認、無効なら戻す
4. **文書化**：タイムライン、根本原因、再発防止策を記録

**Q: USE 方法論とは何ですか？**

A: Brendan Gregg が提唱したシステムリソース分析手法です。
- **U**tilization（利用率）：リソースがどれだけ使われているか
- **S**aturation（飽和度）：待ち行列の長さ
- **E**rrors（エラー）：エラーの発生数

CPU、メモリ、ディスク I/O、ネットワークそれぞれに適用します。

**Q: 障害発生時、最初に何をしますか？**

A: まず **証拠を保全** します。再起動すると揮発性データ（プロセス状態、メモリ、ネットワーク接続）が消えてしまいます。
証拠収集スクリプトを実行してから、対応を開始します。
また、**時刻同期** もすぐに確認します。時刻ずれは TLS エラーやログ相関の問題を引き起こします。

**Q: エスカレーションのタイミングは？**

A: 以下の場合にエスカレーションします：
- 30 分以内に原因特定できない場合
- 影響範囲が拡大している場合
- 他チームの協力が必要な場合
- SLA 違反が近い場合

沈黙は失敗より悪いです。進捗がなくても定期的に報告します。

---

## トラブルシューティング（本課自体の問題解決）

### /proc/pressure が存在しない

PSI (Pressure Stall Information) は Linux 4.20+ で導入されました。

```bash
# カーネルバージョン確認
uname -r

# 4.20 未満の場合は PSI なし
# 代わりに vmstat の si/so 列を見る
vmstat 1 5
```

### chronyc コマンドが見つからない

```bash
# RHEL/CentOS
sudo yum install chrony
sudo systemctl enable --now chronyd

# Debian/Ubuntu
sudo apt install chrony
sudo systemctl enable --now chrony
```

### journalctl の出力が少ない

```bash
# ジャーナルの保持設定を確認
journalctl --disk-usage

# 保持期間を確認
grep -E 'SystemMaxUse|MaxRetentionSec' /etc/systemd/journald.conf
```

---

## 延伸阅读

- [Brendan Gregg - USE Method](https://www.brendangregg.com/usemethod.html)
- [Tom Wilkie - RED Method](https://grafana.com/blog/2018/08/02/the-red-method-how-to-instrument-your-services/)
- [Google SRE Book - Effective Troubleshooting](https://sre.google/sre-book/effective-troubleshooting/)
- 下一课：[02 - 启动故障](../02-boot-issues/) -- GRUB、initramfs、紧急模式

---

## 系列导航

[系列首页](../) | [02 - 启动故障 -->](../02-boot-issues/)
