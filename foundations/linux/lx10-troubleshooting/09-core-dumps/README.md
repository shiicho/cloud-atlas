# 09 - Core Dump 与崩溃分析（Core Dumps and Crash Analysis）

> **目标**：掌握 core dump 配置和基础崩溃分析，学会使用 coredumpctl 和 GDB  
> **前置**：LX10-08 strace 基础，理解进程和信号  
> **时间**：2 小时  
> **核心理念**：Core dump 是程序崩溃时的"现场快照"，是定位崩溃原因的关键证据  

---

## 将学到的内容

1. 配置系统生成 core dump
2. 使用 coredumpctl 管理和查看 core dump
3. 使用 GDB 进行基础崩溃分析
4. 理解常见崩溃信号（SIGSEGV, SIGBUS, SIGABRT, SIGFPE）
5. 配置 debuginfod 自动获取调试符号

---

## 先跑起来！（5 分钟）

> 在深入理论之前，先看看你的系统有没有 core dump 记录。  
> 这些命令立即告诉你系统最近是否有程序崩溃。  

```bash
# 列出所有 core dump 记录
coredumpctl list

# 查看最近一次 core dump 的详细信息（含 backtrace）
coredumpctl info -1
```

**示例输出**：

```
TIME                           PID  UID  GID SIG     COREFILE EXE                          SIZE
Fri 2026-01-10 10:23:45 JST   1234 1000 1000 SIGSEGV present  /usr/local/bin/myapp         2.1M
Thu 2026-01-09 15:30:12 JST   5678 0    0    SIGABRT present  /usr/sbin/some-daemon        4.5M
```

**你刚刚找到了系统上的崩溃记录！**

如果输出为空，说明最近没有程序崩溃（好事！）。现在让我们学习如何配置和分析 core dump。

---

## Step 1 -- 什么是 Core Dump？（10 分钟）

### 1.1 Core Dump 定义

**Core dump** 是程序异常终止时，操作系统将进程内存状态保存到磁盘的文件。

它包含：
- 程序崩溃时的内存内容
- 寄存器状态
- 调用栈信息
- 打开的文件描述符

**类比**：Core dump 就像飞机的"黑匣子"，记录了崩溃瞬间的所有状态。

### 1.2 Core Dump 工作流程

<!-- DIAGRAM: core-dump-workflow -->
```
┌──────────────────────────────────────────────────────────────────────┐
│                    Core Dump 生成和分析流程                           │
├──────────────────────────────────────────────────────────────────────┤
│                                                                      │
│   ┌─────────────┐     ┌─────────────┐     ┌─────────────────────┐   │
│   │  程序运行   │     │  发生异常   │     │  内核捕获信号       │   │
│   │  (Process)  │ ──▶ │  (Crash)    │ ──▶ │  (SIGSEGV etc.)     │   │
│   └─────────────┘     └─────────────┘     └──────────┬──────────┘   │
│                                                       │              │
│                                                       ▼              │
│                       ┌───────────────────────────────────────────┐ │
│                       │  core_pattern 决定如何处理                 │ │
│                       │                                           │ │
│                       │  ┌─────────────────┐  ┌────────────────┐  │ │
│                       │  │ 传统方式        │  │ systemd 方式   │  │ │
│                       │  │ /tmp/core.%p    │  │ systemd-coredump│ │ │
│                       │  │ (文件路径)      │  │ (推荐)         │  │ │
│                       │  └────────┬────────┘  └───────┬────────┘  │ │
│                       │           │                    │           │ │
│                       └───────────┼────────────────────┼───────────┘ │
│                                   │                    │              │
│                                   ▼                    ▼              │
│                       ┌─────────────────┐  ┌─────────────────────┐   │
│                       │  core 文件      │  │  coredumpctl        │   │
│                       │  (手动管理)     │  │  (统一管理+元数据)  │   │
│                       └─────────────────┘  └──────────┬──────────┘   │
│                                                       │              │
│                                                       ▼              │
│                                            ┌─────────────────────┐   │
│                                            │  GDB 分析           │   │
│                                            │  • bt (backtrace)   │   │
│                                            │  • info registers   │   │
│                                            │  • thread apply all │   │
│                                            └─────────────────────┘   │
│                                                                      │
└──────────────────────────────────────────────────────────────────────┘
```
<!-- /DIAGRAM -->

### 1.3 为什么需要 Core Dump？

| 场景 | 没有 Core Dump | 有 Core Dump |
|------|----------------|--------------|
| 程序崩溃 | 只知道"挂了" | 知道在哪行代码崩溃 |
| 间歇性崩溃 | 难以复现 | 有证据可分析 |
| 生产环境问题 | 无法调试 | 可以离线分析 |
| 与开发沟通 | "程序挂了，不知道为什么" | "在 foo.c:123 行空指针" |

---

## Step 2 -- Core Dump 配置（20 分钟）

### 2.1 检查当前配置

```bash
# 检查 ulimit（用户级限制）
ulimit -c
# 输出：0 = 禁用，unlimited = 无限制

# 检查 core_pattern（内核级配置）
cat /proc/sys/kernel/core_pattern
# 输出可能是：
# |/usr/lib/systemd/systemd-coredump ...  (systemd 方式)
# core                                     (传统方式)
# /tmp/core.%p                             (自定义路径)
```

### 2.2 为什么 Core Dump 可能缺失？

<!-- DIAGRAM: why-no-coredump -->
```
┌──────────────────────────────────────────────────────────────────────┐
│                 为什么 Core Dump 可能"消失"？                         │
├──────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  检查点 1: ulimit -c                                                 │
│  ┌────────────────────────────────────────────────────────────────┐ │
│  │  ulimit -c 0        →  禁用 core dump（最常见原因）            │ │
│  │  ulimit -c 1024     →  限制 1024 字节（文件太小被截断）        │ │
│  │  ulimit -c unlimited →  无限制（推荐）                         │ │
│  └────────────────────────────────────────────────────────────────┘ │
│                                                                      │
│  检查点 2: core_pattern                                              │
│  ┌────────────────────────────────────────────────────────────────┐ │
│  │  路径不存在         →  core 无法写入                           │ │
│  │  目录权限不足       →  没有写入权限                            │ │
│  │  磁盘空间不足       →  写入失败                                │ │
│  └────────────────────────────────────────────────────────────────┘ │
│                                                                      │
│  检查点 3: 进程配置                                                  │
│  ┌────────────────────────────────────────────────────────────────┐ │
│  │  setuid 程序        →  默认禁用 core dump（安全考虑）          │ │
│  │  fs.suid_dumpable   →  需要设为 1 或 2 才能 dump               │ │
│  │  prctl(PR_SET_DUMPABLE, 0)  →  程序自己禁用了                  │ │
│  └────────────────────────────────────────────────────────────────┘ │
│                                                                      │
│  检查点 4: systemd-coredump                                          │
│  ┌────────────────────────────────────────────────────────────────┐ │
│  │  Storage=none       →  /etc/systemd/coredump.conf 禁用存储     │ │
│  │  ProcessSizeMax=0   →  进程太大被跳过                          │ │
│  │  ExternalSizeMax=0  →  外部程序 core 被跳过                    │ │
│  └────────────────────────────────────────────────────────────────┘ │
│                                                                      │
└──────────────────────────────────────────────────────────────────────┘
```
<!-- /DIAGRAM -->

### 2.3 启用 Core Dump（传统方式）

```bash
# 1. 设置 ulimit（当前 shell）
ulimit -c unlimited

# 2. 永久设置（系统级）
sudo bash -c 'echo "* soft core unlimited" >> /etc/security/limits.conf'
sudo bash -c 'echo "* hard core unlimited" >> /etc/security/limits.conf'

# 3. 设置 core_pattern（指定保存位置）
# 创建目录
sudo mkdir -p /var/coredumps
sudo chmod 1777 /var/coredumps

# 设置模式（%p=PID, %e=程序名, %t=时间戳）
echo '/var/coredumps/core.%e.%p.%t' | sudo tee /proc/sys/kernel/core_pattern

# 永久生效
echo 'kernel.core_pattern = /var/coredumps/core.%e.%p.%t' | sudo tee -a /etc/sysctl.conf
sudo sysctl -p
```

### 2.4 启用 Core Dump（systemd-coredump 方式，推荐）

现代 Linux 发行版（RHEL 8+, Ubuntu 20.04+, Fedora）默认使用 systemd-coredump。

```bash
# 检查是否使用 systemd-coredump
cat /proc/sys/kernel/core_pattern
# 输出应该是：|/usr/lib/systemd/systemd-coredump ...

# 检查配置
cat /etc/systemd/coredump.conf
```

**配置文件 `/etc/systemd/coredump.conf`**：

```ini
[Coredump]
# Storage=external  # external=保存，none=不保存，journal=只记录到日志
# Compress=yes      # 压缩 core 文件
# ProcessSizeMax=2G # 最大进程大小
# ExternalSizeMax=2G # 最大 core 文件大小
# MaxUse=           # core 文件总大小限制
# KeepFree=         # 保留磁盘空间
```

**推荐配置**（启用并设置合理限制）：

```bash
sudo tee /etc/systemd/coredump.conf << 'EOF'
[Coredump]
Storage=external
Compress=yes
ProcessSizeMax=2G
ExternalSizeMax=2G
MaxUse=10G
KeepFree=1G
EOF

# 重启 systemd-coredump
sudo systemctl daemon-reload
```

### 2.5 为什么 systemd-coredump 更好？

| 特性 | 传统方式 | systemd-coredump |
|------|----------|------------------|
| 元数据 | 无 | PID, 信号, 时间戳, 命令行 |
| 管理 | 手动清理 | 自动轮转 |
| 查询 | 手动找文件 | `coredumpctl list` |
| 压缩 | 无 | 自动压缩 |
| 磁盘管理 | 可能填满磁盘 | 配额限制 |

---

## Step 3 -- coredumpctl 使用（20 分钟）

### 3.1 基础命令

```bash
# 列出所有 core dump
coredumpctl list

# 列出指定程序的 core dump
coredumpctl list nginx

# 列出指定 PID 的 core dump
coredumpctl list 12345

# 列出今天的 core dump
coredumpctl list --since today

# 列出最近 1 小时的 core dump
coredumpctl list --since "1 hour ago"
```

### 3.2 查看 Core Dump 信息

```bash
# 查看最近一次 core dump 的详细信息
coredumpctl info -1

# 查看指定 PID 的 core dump
coredumpctl info 12345

# 查看指定程序的最近 core dump
coredumpctl info myapp
```

**示例输出**：

```
           PID: 12345 (myapp)
           UID: 1000 (user)
           GID: 1000 (user)
        Signal: 11 (SEGV)
     Timestamp: Fri 2026-01-10 10:23:45 JST
  Command Line: /usr/local/bin/myapp --config /etc/myapp.conf
    Executable: /usr/local/bin/myapp
 Control Group: /user.slice/user-1000.slice/session-1.scope
          Unit: session-1.scope
        Coredump: /var/lib/systemd/coredump/core.myapp.1000.abc123.lz4

Message: Process 12345 (myapp) of user 1000 dumped core.

Stack trace of thread 12345:
#0  0x00007f1234567890 crash_function (myapp + 0x1234)
#1  0x00007f1234567abc main_loop (myapp + 0x5678)
#2  0x00007f1234567def main (myapp + 0x9abc)
#3  0x00007f12345678ab __libc_start_main (libc.so.6 + 0x21ab)
#4  0x00007f12345678cd _start (myapp + 0x1cd)
```

**关键信息解读**：

| 字段 | 含义 |
|------|------|
| Signal: 11 (SEGV) | 段错误（非法内存访问） |
| Stack trace | 崩溃时的调用栈 |
| #0 | 崩溃发生的位置 |
| myapp + 0x1234 | 程序内的偏移地址 |

### 3.3 调试和导出

```bash
# 启动 GDB 调试最近的 core dump
coredumpctl debug -1

# 调试指定程序的最近 core dump
coredumpctl debug myapp

# 导出 core 文件（用于离线分析或发送给开发）
coredumpctl dump -1 -o /tmp/core.myapp

# 导出并压缩
coredumpctl dump -1 | gzip > /tmp/core.myapp.gz
```

### 3.4 coredumpctl Cheatsheet

```bash
# ============================================
# coredumpctl 速查表
# ============================================

# 列出所有 core dump
coredumpctl list

# 列出指定程序
coredumpctl list <program>

# 查看最近 core dump 详情（含 backtrace）
coredumpctl info -1

# 启动 GDB 调试最近 core
coredumpctl debug -1

# 导出 core 文件
coredumpctl dump -1 > /tmp/core

# 按时间过滤
coredumpctl list --since "2026-01-10"
coredumpctl list --since "1 hour ago"

# 按 PID 查询
coredumpctl info <PID>
coredumpctl debug <PID>
```

---

## Step 4 -- GDB 基础崩溃分析（25 分钟）

### 4.1 GDB 简介

**GDB (GNU Debugger)** 是 Linux 上最强大的调试器。对于 core dump 分析，我们只需要掌握几个基础命令。

### 4.2 启动 GDB 分析 Core Dump

```bash
# 方式 1：通过 coredumpctl（推荐）
coredumpctl debug -1

# 方式 2：直接使用 gdb
gdb /path/to/program /path/to/core

# 方式 3：附加 core 文件
gdb /path/to/program
(gdb) core /path/to/core
```

### 4.3 GDB 核心命令

**获取调用栈（最重要）**：

```gdb
# 基础 backtrace
(gdb) bt
#0  0x00007f1234567890 in crash_function () at crash.c:42
#1  0x00007f1234567abc in process_data () at process.c:156
#2  0x00007f1234567def in main () at main.c:89

# 完整 backtrace（含局部变量）
(gdb) bt full
#0  0x00007f1234567890 in crash_function () at crash.c:42
        ptr = 0x0
        len = 1024
#1  0x00007f1234567abc in process_data () at process.c:156
        buffer = 0x7ffc12345678 "input data..."

# 所有线程的 backtrace
(gdb) thread apply all bt
```

**查看源代码位置**：

```gdb
# 显示崩溃位置的源代码
(gdb) list
37      void crash_function(char *ptr) {
38          int len = strlen(ptr);  // ptr 是 NULL！
39          // ...
40      }

# 显示指定行
(gdb) list crash.c:42
```

**查看寄存器和内存**：

```gdb
# 查看寄存器
(gdb) info registers
rax            0x0                 0
rbx            0x7ffc12345678      140721234567800
rsp            0x7ffc12345600      0x7ffc12345600

# 查看指定地址的内存
(gdb) x/10x 0x7ffc12345678
```

**查看变量值**：

```gdb
# 打印变量
(gdb) print ptr
$1 = 0x0

# 打印数组
(gdb) print buffer
$2 = "input data..."

# 打印结构体
(gdb) print *config
$3 = {port = 8080, host = 0x55555555a0 "localhost"}
```

### 4.4 GDB Cheatsheet

```gdb
# ============================================
# GDB Core Dump 分析速查表
# ============================================

# 调用栈分析
bt                      # 基础 backtrace
bt full                 # 含局部变量
bt 10                   # 只显示 10 帧
thread apply all bt     # 所有线程

# 源代码
list                    # 显示当前位置
list file.c:42          # 显示指定行

# 变量
print var               # 打印变量
print *ptr              # 解引用指针
print array[0]          # 数组元素

# 寄存器和内存
info registers          # 所有寄存器
info reg rax            # 指定寄存器
x/10x addr              # 查看内存

# 线程
info threads            # 线程列表
thread 2                # 切换到线程 2

# 帧切换
frame 0                 # 切换到帧 0
up                      # 上一帧
down                    # 下一帧

# 退出
quit                    # 退出 GDB
```

### 4.5 实战示例：分析空指针崩溃

**场景**：程序崩溃，coredumpctl info 显示 SIGSEGV。

```bash
# 1. 查看 core dump 信息
coredumpctl info -1

# 输出显示：
# Signal: 11 (SEGV)
# Stack trace:
# #0  strlen () at strlen.S:42
# #1  process_input () at input.c:28
# #2  main () at main.c:15

# 2. 启动 GDB 详细分析
coredumpctl debug -1
```

**GDB 分析过程**：

```gdb
# 进入 GDB 后
(gdb) bt
#0  0x00007f123456 in strlen () from /lib64/libc.so.6
#1  0x00000040089a in process_input (data=0x0) at input.c:28
#2  0x000000400756 in main () at main.c:15

# 看到 #1 帧的 data=0x0（空指针！）

# 切换到 #1 帧查看详情
(gdb) frame 1
#1  0x00000040089a in process_input (data=0x0) at input.c:28
28          len = strlen(data);

# 确认是空指针传入
(gdb) print data
$1 = 0x0

# 查看调用者
(gdb) frame 2
#2  0x000000400756 in main () at main.c:15
15          process_input(user_data);

(gdb) print user_data
$2 = 0x0

# 结论：main() 传入了空指针 user_data 到 process_input()
```

---

## Step 5 -- 常见崩溃信号（15 分钟）

### 5.1 信号概览

<!-- DIAGRAM: crash-signals -->
```
┌──────────────────────────────────────────────────────────────────────┐
│                      常见崩溃信号速查                                 │
├──────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  信号       编号    含义                  常见原因                    │
│  ─────────────────────────────────────────────────────────────────   │
│                                                                      │
│  SIGSEGV    11     段错误               • 空指针解引用               │
│                    (Segmentation       • 访问已释放内存              │
│                     Fault)             • 数组越界                    │
│                                        • 栈溢出                      │
│                                                                      │
│  SIGBUS      7     总线错误            • 未对齐内存访问              │
│                    (Bus Error)         • 映射文件被截断              │
│                                        • 硬件问题                    │
│                                                                      │
│  SIGABRT     6     程序自我终止        • assert() 失败               │
│                    (Abort)             • abort() 调用                │
│                                        • 内存分配失败                │
│                                        • C++ 异常未捕获              │
│                                                                      │
│  SIGFPE      8     浮点异常            • 除零                        │
│                    (Floating Point     • 整数溢出                    │
│                     Exception)         • 无效浮点操作                │
│                                                                      │
│  SIGILL      4     非法指令            • 损坏的二进制                │
│                    (Illegal           • CPU 不支持的指令             │
│                     Instruction)       • 内存损坏                    │
│                                                                      │
└──────────────────────────────────────────────────────────────────────┘
```
<!-- /DIAGRAM -->

### 5.2 信号详解

#### SIGSEGV (Signal 11) - 段错误

**最常见的崩溃信号**。表示程序试图访问无效内存。

**常见原因**：
```c
// 1. 空指针解引用
char *ptr = NULL;
printf("%s", ptr);  // SIGSEGV!

// 2. 访问已释放内存
free(buffer);
printf("%s", buffer);  // SIGSEGV!

// 3. 数组越界
int arr[10];
arr[100] = 42;  // SIGSEGV!

// 4. 栈溢出（无限递归）
void recurse() { recurse(); }  // SIGSEGV!
```

**GDB 分析要点**：
```gdb
(gdb) bt
# 查看崩溃位置，通常是某个指针操作
(gdb) print ptr
# 检查相关指针是否为 0x0 或异常地址
```

#### SIGBUS (Signal 7) - 总线错误

**访问物理上不存在或未对齐的内存地址**。

**常见原因**：
```c
// 1. 未对齐访问（某些架构）
char buf[10];
int *ptr = (int*)(buf + 1);  // 未对齐
*ptr = 42;  // SIGBUS!

// 2. mmap 文件被截断
int fd = open("file", O_RDWR);
char *map = mmap(..., fd, ...);
// 另一个进程 truncate 了文件
map[1000] = 'x';  // SIGBUS!
```

#### SIGABRT (Signal 6) - 中止信号

**程序主动请求终止**。通常是检测到内部错误。

**常见原因**：
```c
// 1. assert 失败
assert(ptr != NULL);  // 如果 ptr 为 NULL，SIGABRT

// 2. 显式调用 abort()
if (critical_error) {
    abort();  // SIGABRT
}

// 3. C++ 未捕获异常
throw std::runtime_error("error");  // 未 catch，SIGABRT

// 4. glibc 检测到内存损坏
// 双重 free、堆溢出等
free(ptr);
free(ptr);  // double free，SIGABRT
```

**GDB 分析要点**：
```gdb
(gdb) bt
# 查找 __GI_abort, __assert_fail 等
# 向上追溯找到真正的错误检查点
```

#### SIGFPE (Signal 8) - 浮点异常

**算术错误**。不仅限于浮点，整数除零也会触发。

**常见原因**：
```c
// 1. 整数除零
int a = 10;
int b = 0;
int c = a / b;  // SIGFPE!

// 2. 浮点溢出/下溢（需要启用 FPE 陷阱）
```

### 5.3 信号与 Core Dump 的关系

```bash
# 查看哪些信号会生成 core dump
# 默认：SIGQUIT, SIGILL, SIGTRAP, SIGABRT, SIGFPE, SIGSEGV, SIGBUS, SIGSYS, SIGXCPU, SIGXFSZ

# 手动发送信号（测试用）
kill -SIGSEGV <pid>   # 强制 SIGSEGV（模拟崩溃）
kill -SIGABRT <pid>   # 强制 SIGABRT
```

---

## Step 6 -- debuginfod 自动符号获取（10 分钟）

### 6.1 什么是 debuginfod？

**问题**：生产环境的程序通常没有调试符号（stripped），GDB 只能显示地址，不显示函数名和行号。

**传统解决方案**：手动下载 debuginfo 包。

**现代方案**：debuginfod 自动从网络获取调试符号。

### 6.2 debuginfod 工作原理

<!-- DIAGRAM: debuginfod-flow -->
```
┌──────────────────────────────────────────────────────────────────────┐
│                    debuginfod 工作流程                                │
├──────────────────────────────────────────────────────────────────────┤
│                                                                      │
│   ┌─────────────┐     ┌─────────────┐     ┌─────────────────────┐   │
│   │  GDB 分析   │     │  检查 ELF   │     │  查询 debuginfod    │   │
│   │  core dump  │ ──▶ │  build-id   │ ──▶ │  服务器             │   │
│   └─────────────┘     └─────────────┘     └──────────┬──────────┘   │
│                                                       │              │
│                                                       ▼              │
│                       ┌───────────────────────────────────────────┐ │
│                       │  debuginfod 服务器                         │ │
│                       │  • Fedora: https://debuginfod.fedoraproject.org │
│                       │  • Ubuntu: https://debuginfod.ubuntu.com   │ │
│                       │  • Debian: https://debuginfod.debian.net   │ │
│                       └───────────────────────────────────────────┘ │
│                                                       │              │
│                                                       ▼              │
│                                            ┌─────────────────────┐   │
│                                            │  下载调试符号       │   │
│                                            │  缓存到本地         │   │
│                                            │  ~/.cache/debuginfod│   │
│                                            └─────────────────────┘   │
│                                                                      │
└──────────────────────────────────────────────────────────────────────┘
```
<!-- /DIAGRAM -->

### 6.3 配置 debuginfod

```bash
# 检查是否已配置
echo $DEBUGINFOD_URLS

# 设置 debuginfod 服务器（根据发行版选择）

# Fedora / RHEL
export DEBUGINFOD_URLS="https://debuginfod.fedoraproject.org/"

# Ubuntu
export DEBUGINFOD_URLS="https://debuginfod.ubuntu.com/"

# Debian
export DEBUGINFOD_URLS="https://debuginfod.debian.net/"

# 永久配置（添加到 ~/.bashrc 或 /etc/profile.d/）
echo 'export DEBUGINFOD_URLS="https://debuginfod.fedoraproject.org/"' >> ~/.bashrc
```

### 6.4 验证 debuginfod

```bash
# 安装 debuginfod-find 工具（如果没有）
# RHEL/Fedora
sudo dnf install elfutils-debuginfod-client

# Ubuntu/Debian
sudo apt install debuginfod

# 测试：查找 libc 的调试符号
debuginfod-find debuginfo /lib64/libc.so.6
# 应该下载并显示路径
```

### 6.5 2025-2026 debuginfod 采用状态

| 发行版 | 官方服务器 | 状态 |
|--------|------------|------|
| Fedora | debuginfod.fedoraproject.org | 完全支持 |
| Ubuntu 22.04+ | debuginfod.ubuntu.com | 完全支持 |
| Debian 12+ | debuginfod.debian.net | 完全支持 |
| RHEL 8/9 | 使用 Fedora 服务器 | 支持 |
| Amazon Linux 2023 | 无官方服务器 | 需手动下载 |

**生产环境建议**：
- 如果公司有安全限制，可以搭建内部 debuginfod 服务器
- 或预先下载 debuginfo 包到本地

---

## Step 7 -- 事故场景："消失的 Core Dump"（15 分钟）

### 7.1 场景描述

**背景**：
- 生产环境的 Java 应用每天崩溃 1-2 次
- 开发要求提供 core dump 分析
- 但是 `/var/coredumps` 目录是空的
- coredumpctl list 也没有记录

**症状**：
```bash
# 检查 core dump 记录
$ coredumpctl list
No coredumps found.

# 检查目录
$ ls /var/coredumps/
(empty)

# 但进程确实崩溃了
$ journalctl -u myapp --since "1 hour ago"
Jan 10 10:23:45 server systemd[1]: myapp.service: Main process exited, code=killed, status=11/SEGV
Jan 10 10:23:45 server systemd[1]: myapp.service: Failed with result 'signal'.
```

### 7.2 排查步骤

**Step 1：检查 ulimit**

```bash
# 检查服务的 ulimit
$ systemctl show myapp | grep LimitCORE
LimitCORE=0
LimitCORESoft=0

# 问题找到！服务的 core 限制是 0
```

**Step 2：检查 systemd service 配置**

```bash
$ cat /etc/systemd/system/myapp.service
[Service]
# 没有设置 LimitCORE，默认可能是 0
```

**Step 3：修复配置**

```bash
# 编辑 service 文件
sudo systemctl edit myapp.service

# 添加以下内容
[Service]
LimitCORE=infinity

# 或者系统级设置
sudo mkdir -p /etc/systemd/system.conf.d
sudo tee /etc/systemd/system.conf.d/core.conf << 'EOF'
[Manager]
DefaultLimitCORE=infinity
EOF

# 重新加载
sudo systemctl daemon-reload
sudo systemctl restart myapp
```

**Step 4：验证配置生效**

```bash
# 检查服务的 ulimit
$ systemctl show myapp | grep LimitCORE
LimitCORE=infinity
LimitCORESoft=infinity

# 检查 core_pattern
$ cat /proc/sys/kernel/core_pattern
|/usr/lib/systemd/systemd-coredump %P %u %g %s %t %c %h
```

**Step 5：测试 core dump 生成**

```bash
# 手动触发崩溃（测试用）
$ kill -SIGSEGV $(pgrep myapp)

# 检查是否生成
$ coredumpctl list
TIME                           PID  UID  GID SIG     COREFILE EXE
Fri 2026-01-10 10:45:00 JST  12345 1000 1000 SIGSEGV present  /usr/local/bin/myapp

# 成功！
```

### 7.3 常见原因清单

| 原因 | 检查方法 | 修复方法 |
|------|----------|----------|
| ulimit -c 0 | `ulimit -c` | `ulimit -c unlimited` |
| service LimitCORE=0 | `systemctl show <svc>` | 添加 `LimitCORE=infinity` |
| core_pattern 路径不存在 | `cat /proc/sys/kernel/core_pattern` | 创建目录或改路径 |
| systemd-coredump Storage=none | `/etc/systemd/coredump.conf` | 改为 `Storage=external` |
| setuid 程序 | `ls -l <binary>` | 设置 `fs.suid_dumpable=2` |
| 磁盘空间不足 | `df -h` | 清理空间 |
| ProcessSizeMax 太小 | `/etc/systemd/coredump.conf` | 增大限制 |

---

## 动手实验（20 分钟）

### 实验 1：配置 Core Dump 收集

**目标**：确保系统能正确收集 core dump。

```bash
# 1. 检查当前配置
ulimit -c
cat /proc/sys/kernel/core_pattern
coredumpctl list

# 2. 确保 systemd-coredump 正确配置
sudo cat /etc/systemd/coredump.conf

# 3. 创建测试程序
cat > /tmp/crash.c << 'EOF'
#include <stdio.h>
#include <string.h>

int main() {
    char *ptr = NULL;
    printf("About to crash...\n");
    printf("%s\n", ptr);  // NULL pointer dereference
    return 0;
}
EOF

# 4. 编译（保留调试符号）
gcc -g -o /tmp/crash /tmp/crash.c

# 5. 运行崩溃程序
/tmp/crash

# 6. 检查 core dump
coredumpctl list
coredumpctl info -1
```

### 实验 2：使用 GDB 分析崩溃

**目标**：使用 GDB 定位崩溃原因。

```bash
# 1. 启动 GDB 分析
coredumpctl debug -1

# 2. 在 GDB 中执行
(gdb) bt
# 应该看到类似：
# #0  __strlen_sse2 () at strlen.S:xx
# #1  printf () at ...
# #2  main () at /tmp/crash.c:7

(gdb) bt full
# 查看局部变量

(gdb) frame 2
# 切换到 main 帧

(gdb) print ptr
# 应该显示 $1 = 0x0

(gdb) list
# 显示源代码

(gdb) quit
```

### 实验 3：模拟"消失的 Core Dump"并修复

**目标**：体验排查 core dump 不生成的问题。

```bash
# 1. 临时禁用 core dump
ulimit -c 0

# 2. 尝试生成崩溃
/tmp/crash

# 3. 检查 - 应该没有新记录
coredumpctl list

# 4. 修复
ulimit -c unlimited

# 5. 再次崩溃
/tmp/crash

# 6. 验证
coredumpctl list
# 现在应该有记录了
```

---

## 日本 IT 职场：Core Dump 实践

### 8.1 核心日语术语

| 日语 | 读音 | 含义 | 使用场景 |
|------|------|------|----------|
| **コアダンプ** | koa danpu | Core dump | "コアダンプを取得してください" |
| **クラッシュ** | kurasshu | Crash | "アプリがクラッシュした" |
| **スタックトレース** | sutakku toreesu | Stack trace | "スタックトレースを確認" |
| **デバッグ情報** | debaggu jouhou | Debug info | "デバッグ情報付きでビルド" |
| **セグフォ** | segufo | Segfault (俗语) | "セグフォで落ちた" |

### 8.2 与开发团队协作

```
运维发现崩溃
     │
     ▼
収集（core dump, ログ, 環境情報）
     │
     ▼
報告（開発チームへエスカレーション）
     │
     ▼
分析（開発と運維で協力）
     │
     ▼
修正（開発がパッチ作成）
     │
     ▼
デプロイ（運維が本番適用）
```

**报告模板**：

```markdown
# クラッシュレポート

## 概要
- 発生日時: 2026-01-10 10:23:45 JST
- 対象サーバー: prod-web-01
- アプリケーション: myapp v2.3.1
- シグナル: SIGSEGV (11)

## 環境情報
- OS: Rocky Linux 9.3
- カーネル: 5.14.0-362.el9.x86_64
- メモリ: 16GB (使用率 65%)

## スタックトレース
(coredumpctl info からコピー)

## Core Dump
- 場所: /var/lib/systemd/coredump/core.myapp.xxx
- サイズ: 2.1MB
- ※必要であれば転送可能

## 再現手順
1. XXX
2. XXX

## 備考
- 同様のクラッシュは今週 3 回発生
- 直前にメモリ使用率が急増していた
```

### 8.3 职场提示

> **クラッシュ分析は開発との連携が多い**  
> (崩溃分析需要频繁与开发团队协作)  

- Core dump 是与开发沟通的重要证据
- 运维负责收集和初步分析，开发负责深入修复
- 保存 core dump 作为证据（不要立即删除）
- 记录崩溃时的环境状态（内存、CPU、日志）

> **証拠として core dump を保存**  
> (作为证据保存 core dump)  

- 默认 systemd-coredump 会自动轮转删除旧的 core dump
- 重要的 core dump 应该导出并归档
- 使用 `coredumpctl dump -o /path/to/archive/` 导出

---

## 检查清单

完成本课后，你应该能够：

- [ ] 解释什么是 core dump 以及它的作用
- [ ] 检查系统的 core dump 配置（ulimit, core_pattern）
- [ ] 使用 `coredumpctl list` 列出系统上的 core dump
- [ ] 使用 `coredumpctl info` 查看 core dump 详情
- [ ] 使用 `coredumpctl debug` 启动 GDB 分析
- [ ] 在 GDB 中使用 `bt`, `bt full`, `print` 命令
- [ ] 解释 SIGSEGV, SIGBUS, SIGABRT, SIGFPE 的含义
- [ ] 配置 debuginfod 自动获取调试符号
- [ ] 排查 core dump 不生成的问题
- [ ] 导出 core dump 文件用于归档或发送给开发

---

## 本课小结

| 概念 | 要点 |
|------|------|
| Core Dump | 程序崩溃时的内存快照，是分析崩溃的关键证据 |
| systemd-coredump | 现代 Linux 推荐的 core dump 管理方式 |
| coredumpctl | 统一管理 core dump 的命令行工具 |
| GDB 基础 | bt (backtrace), bt full, print, list |
| SIGSEGV | 段错误，最常见的崩溃信号，通常是空指针或越界 |
| SIGABRT | 程序主动中止，assert 失败或 double free |
| debuginfod | 2025+ 自动获取调试符号的现代方案 |
| 消失的 Core | 检查 ulimit, LimitCORE, core_pattern |

**核心理念**：

> Core dump 是程序崩溃的"黑匣子"。  
> systemd-coredump + coredumpctl 是现代最佳实践。  
> coredumpctl info 已包含基础 backtrace。  
> 保存 core dump 作为证据，与开发协作分析。  

---

## 面试准备

### よくある質問（常见问题）

**Q: Core dump とは何ですか？**

A: プログラムが異常終了した時に、その時点のメモリ状態をファイルに保存したものです。これにより、クラッシュの原因を後から分析できます。「飛行機のブラックボックス」のようなものです。

**Q: Core dump が生成されない場合、どうやって調査しますか？**

A: 以下の順序で確認します：
1. `ulimit -c` でシェルの制限を確認
2. `systemctl show <service>` で LimitCORE を確認
3. `/proc/sys/kernel/core_pattern` でパスを確認
4. `/etc/systemd/coredump.conf` で Storage 設定を確認
5. ディスク空き容量を確認

**Q: SIGSEGV と SIGABRT の違いは？**

A:
- **SIGSEGV (11)**: カーネルが検出した不正メモリアクセス。NULL ポインタや配列越境が主な原因
- **SIGABRT (6)**: プログラムが自ら終了を要求。assert 失敗や double free で glibc が検出

**Q: coredumpctl の基本的な使い方を教えてください**

A:
```bash
coredumpctl list          # 一覧表示
coredumpctl info -1       # 最新の詳細（スタックトレース含む）
coredumpctl debug -1      # GDB で分析
coredumpctl dump -1 > file  # エクスポート
```

**Q: debuginfod とは何ですか？**

A: デバッグシンボルを自動的にネットワークから取得する仕組みです。2025 年現在、主要な Linux ディストリビューション（Fedora, Ubuntu, Debian）が公式サーバーを提供しており、GDB 分析時にシンボル情報を自動取得できます。

---

## トラブルシューティング（本課自体の問題解決）

### coredumpctl コマンドが見つからない

```bash
# RHEL/Fedora
sudo dnf install systemd-coredump

# Ubuntu/Debian
sudo apt install systemd-coredump
```

### GDB でシンボルが表示されない

```bash
# debuginfo パッケージをインストール

# RHEL/Fedora
sudo dnf debuginfo-install <package>

# Ubuntu/Debian
# -dbgsym パッケージを有効化してインストール
sudo apt install <package>-dbgsym

# または debuginfod を設定
export DEBUGINFOD_URLS="https://debuginfod.fedoraproject.org/"
```

### core dump がすぐに消える

```bash
# systemd-coredump の保持設定を確認
cat /etc/systemd/coredump.conf

# MaxUse や KeepFree を調整
sudo vim /etc/systemd/coredump.conf
# MaxUse=10G  # 保持する最大サイズ
```

---

## 延伸阅读

- [systemd-coredump 官方文档](https://www.freedesktop.org/software/systemd/man/systemd-coredump.html)
- [GDB 官方文档](https://sourceware.org/gdb/current/onlinedocs/gdb/)
- [debuginfod 项目](https://sourceware.org/elfutils/Debuginfod.html)
- [Brendan Gregg - Core Dump 分析](https://www.brendangregg.com/)
- 上一课：[08 - strace 系统调用追踪](../08-strace/)
- 下一课：[10 - Capstone: 根因分析与障害報告書](../10-rca-capstone/)

---

## 系列导航

[<-- 08 - strace](../08-strace/) | [系列首页](../) | [10 - RCA Capstone -->](../10-rca-capstone/)
