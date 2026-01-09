# 05 · SELinux 进阶：Booleans 与自定义策略（SELinux Advanced: Booleans & Custom Policies）

> **目标**：掌握 SELinux Booleans 的使用，理解何时需要自定义策略，避免 audit2allow 滥用  
> **前置**：完成 Lesson 03-04（SELinux 核心概念与排错实战）  
> **时间**：2-2.5 小时  
> **实战场景**：WordPress 无法连接远程 RDS 数据库  

---

## 将学到的内容

1. 掌握 SELinux Booleans 的查询和设置
2. 理解 Boolean vs fcontext vs port vs 自定义策略的决策流程
3. 能够创建简单的自定义 SELinux 策略模块
4. **关键心态**：Boolean 优先，自定义策略是最后手段
5. **反模式警惕**：避免盲目使用 audit2allow -M

---

## 先跑起来！（10 分钟）

> WordPress 刚部署完成，但连接远程 RDS 数据库失败。  
> 网络测试正常（telnet 3306 成功），但 WordPress 就是连不上。  
> 让我们体验这个典型的「SELinux Boolean 问题」。  

### 场景模拟

```bash
# 检查 httpd 相关的 SELinux Booleans
getsebool -a | grep httpd | head -10

# 特别关注这一个
getsebool httpd_can_network_connect_db
# 输出: httpd_can_network_connect_db --> off

# 这就是问题所在！
# httpd_t 进程默认不允许发起到数据库端口的网络连接
```

**你刚刚发现了问题！**

SELinux 策略默认限制 Web 服务器进程（httpd_t）发起对外网络连接。这是安全设计 — 防止被入侵的 Web 服务器成为跳板。

但我们需要 WordPress 连接 RDS，所以要启用对应的 Boolean：

```bash
# 查看当前状态
getsebool httpd_can_network_connect_db

# 启用（-P 表示永久）
sudo setsebool -P httpd_can_network_connect_db on

# 验证
getsebool httpd_can_network_connect_db
# 输出: httpd_can_network_connect_db --> on
```

**问题解决！** 不需要修改策略，不需要 audit2allow，一行命令搞定。

这就是 Boolean 的威力 — 预定义的开关，一键启用合法功能。

---

## Step 1 — SELinux Booleans 详解（20 分钟）

### 1.1 什么是 Boolean？

Boolean 是 SELinux 策略中的「开关」：

```
Boolean = 预定义的策略规则组
        = 一键启用/禁用某类功能
        = 不需要写自定义策略
```

<!-- DIAGRAM: selinux-boolean-concept -->
```
SELinux Boolean 概念
===============================================================================

传统方式（复杂）:
┌─────────────────────────────────────────────────────────────────────────────┐
│  需求: httpd 连接远程数据库                                                    │
│                                                                             │
│  步骤:                                                                       │
│  1. 收集 AVC 拒绝日志                                                        │
│  2. 分析 audit2why 输出                                                      │
│  3. 编写 .te 策略文件                                                        │
│  4. 编译策略模块                                                             │
│  5. 安装策略模块                                                             │
│  6. 测试验证                                                                 │
│                                                                             │
│  耗时: 30+ 分钟，需要策略知识                                                   │
└─────────────────────────────────────────────────────────────────────────────┘

Boolean 方式（简单）:
┌─────────────────────────────────────────────────────────────────────────────┐
│  需求: httpd 连接远程数据库                                                    │
│                                                                             │
│  命令: setsebool -P httpd_can_network_connect_db on                          │
│                                                                             │
│  耗时: 10 秒                                                                 │
└─────────────────────────────────────────────────────────────────────────────┘

Boolean 本质:
┌─────────────────────────────────────────────────────────────────────────────┐
│                                                                             │
│  httpd_can_network_connect_db = off                                          │
│      │                                                                       │
│      └── 策略规则:                                                           │
│          allow httpd_t port_type:tcp_socket name_connect;  ← 禁用            │
│          allow httpd_t self:tcp_socket { ... };            ← 禁用            │
│                                                                             │
│  httpd_can_network_connect_db = on                                           │
│      │                                                                       │
│      └── 策略规则:                                                           │
│          allow httpd_t port_type:tcp_socket name_connect;  ← 启用 ✓          │
│          allow httpd_t self:tcp_socket { ... };            ← 启用 ✓          │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```
<!-- /DIAGRAM -->

### 1.2 查询 Booleans

```bash
# 查看所有 Booleans
getsebool -a
# 输出几百个 Boolean...

# 按服务过滤
getsebool -a | grep httpd
getsebool -a | grep sshd
getsebool -a | grep nfs
getsebool -a | grep samba

# 查看单个 Boolean
getsebool httpd_can_network_connect_db

# 查看 Boolean 的详细说明
sudo semanage boolean -l | grep httpd_can_network
```

**常用 httpd Booleans**：

| Boolean | 默认 | 说明 |
|---------|------|------|
| `httpd_can_network_connect` | off | 允许 httpd 发起任意网络连接 |
| `httpd_can_network_connect_db` | off | 允许 httpd 连接数据库端口 |
| `httpd_can_sendmail` | off | 允许 httpd 发送邮件 |
| `httpd_use_nfs` | off | 允许 httpd 使用 NFS 挂载 |
| `httpd_use_cifs` | off | 允许 httpd 使用 CIFS/SMB |
| `httpd_enable_homedirs` | off | 允许 httpd 访问用户主目录 |
| `httpd_read_user_content` | off | 允许 httpd 读取用户内容 |

### 1.3 设置 Booleans

```bash
# 临时设置（重启后失效）
sudo setsebool httpd_can_network_connect_db on

# 永久设置（推荐）
sudo setsebool -P httpd_can_network_connect_db on
#             ^^
#             -P = Persistent = 永久

# 同时设置多个
sudo setsebool -P httpd_can_network_connect_db=on httpd_can_sendmail=on
```

**重要**：永远使用 `-P` 除非你只是临时测试。

### 1.4 Boolean vs 其他解决方案

什么时候用什么方法？看这个决策流程：

<!-- DIAGRAM: selinux-fix-decision-tree -->
```
SELinux 拒绝修复决策树
===============================================================================

                          SELinux AVC 拒绝
                                │
                                ▼
                    ┌───────────────────────┐
                    │  ausearch -m avc      │
                    │  audit2why            │
                    └───────────────────────┘
                                │
                                ▼
        ┌───────────────────────────────────────────────────┐
        │           audit2why 输出分析                        │
        └───────────────────────────────────────────────────┘
                                │
        ┌───────────────────────┼───────────────────────┐
        │                       │                       │
        ▼                       ▼                       ▼
┌───────────────┐     ┌─────────────────┐     ┌─────────────────┐
│ "setsebool"   │     │ "需要添加       │     │ "需要修改文件    │
│  建议         │     │  端口类型"       │     │  上下文"         │
└───────────────┘     └─────────────────┘     └─────────────────┘
        │                       │                       │
        ▼                       ▼                       ▼
┌───────────────┐     ┌─────────────────┐     ┌─────────────────┐
│ Boolean 方案   │     │ Port 方案        │     │ Fcontext 方案   │
│               │     │                 │     │                 │
│ getsebool -a  │     │ semanage port   │     │ semanage        │
│ | grep xxx    │     │ -a -t xxx -p    │     │ fcontext -a     │
│               │     │ tcp 8080        │     │ -t xxx '/path'  │
│ setsebool -P  │     │                 │     │                 │
│ xxx on        │     │                 │     │ restorecon -Rv  │
└───────────────┘     └─────────────────┘     └─────────────────┘
        │                       │                       │
        └───────────────────────┴───────────────────────┘
                                │
                                ▼
                    ┌───────────────────────┐
                    │    以上都不行？        │
                    │                       │
                    │    ↓↓↓ 最后手段 ↓↓↓    │
                    │                       │
                    │   自定义策略模块       │
                    │   audit2allow -M      │
                    │                       │
                    │   ⚠️ 必须审核内容！    │
                    └───────────────────────┘

优先级（从高到低）:
  1. Boolean     → 一行命令，最简单
  2. Port        → semanage port，常见场景
  3. Fcontext    → semanage fcontext，文件上下文
  4. Custom      → audit2allow -M，最后手段
```
<!-- /DIAGRAM -->

---

## Step 2 — 实战：WordPress 远程数据库场景（30 分钟）

### 2.1 场景描述

> **场景**：日本企业的 RHEL 9 服务器上部署 WordPress，需要连接 Amazon RDS MySQL。  
>
> - WordPress 安装完成，Apache 正常运行  
> - RDS 安全组已配置，从服务器 telnet 3306 成功  
> - 但 WordPress 显示「Error establishing a database connection」  
> - 运维工程师怀疑是 SELinux 问题  

### 2.2 诊断流程

```bash
# Step 1: 确认 SELinux 状态
getenforce
# 输出: Enforcing

# Step 2: 检查最近的 AVC 拒绝
sudo ausearch -m avc -ts recent | grep httpd
# 输出类似:
# type=AVC msg=audit(...): avc:  denied  { name_connect } for
# pid=12345 comm="httpd" dest=3306 scontext=system_u:system_r:httpd_t:s0
# tcontext=system_u:object_r:mysqld_port_t:s0 tclass=tcp_socket

# Step 3: 分析拒绝原因
sudo ausearch -m avc -ts recent | audit2why | head -20
# 输出类似:
# Was caused by:
# The boolean httpd_can_network_connect_db was set incorrectly.
# Allow httpd to can network connect db
#
# Allow access by executing:
# setsebool -P httpd_can_network_connect_db 1
```

**关键信息**：

```
denied  { name_connect }     ← 尝试建立网络连接被拒绝
comm="httpd"                 ← httpd 进程
dest=3306                    ← 目标端口 3306 (MySQL)
scontext=httpd_t             ← 源上下文是 httpd_t
tcontext=mysqld_port_t       ← 目标是 MySQL 端口类型
boolean httpd_can_network_connect_db  ← 建议启用这个 Boolean
```

### 2.3 修复

```bash
# Step 4: 查看当前 Boolean 状态
getsebool httpd_can_network_connect_db
# 输出: httpd_can_network_connect_db --> off

# Step 5: 启用 Boolean（永久）
sudo setsebool -P httpd_can_network_connect_db on

# Step 6: 验证
getsebool httpd_can_network_connect_db
# 输出: httpd_can_network_connect_db --> on

# Step 7: 测试 WordPress
curl -I http://localhost/wp-admin/
# 应该返回 200 或 302，而不是数据库连接错误
```

### 2.4 变更记录

在日本 IT 职场，所有 SELinux 变更都应该记录：

```bash
# 记录变更（運用履歴）
echo "$(date '+%Y-%m-%d %H:%M:%S') - setsebool -P httpd_can_network_connect_db on - WordPress RDS 接続のため - $(whoami)" | sudo tee -a /var/log/selinux-changes.log
```

---

## Step 3 — Boolean vs 自定义策略：决策指南（15 分钟）

### 3.1 核心原则

**Boolean 优先，自定义策略是最后手段。**

为什么？

| 方法 | 复杂度 | 风险 | 维护成本 | 适用场景 |
|------|--------|------|----------|----------|
| Boolean | 低 | 低 | 几乎无 | 预定义功能开关 |
| semanage port | 低 | 低 | 低 | 非标准端口 |
| semanage fcontext | 中 | 低 | 低 | 非标准路径 |
| 自定义策略 | 高 | **高** | **高** | 以上都不行 |

### 3.2 什么时候用自定义策略？

只有当以下条件**全部满足**时：

1. 没有对应的 Boolean
2. 不是端口问题
3. 不是文件上下文问题
4. 你完全理解 audit2allow 输出的含义

### 3.3 audit2allow 的陷阱

```bash
# 危险操作：盲目生成策略
sudo ausearch -m avc -ts today | audit2allow -M myfix
sudo semodule -i myfix.pp
# "问题解决了！"

# 但是...你看过 myfix.te 的内容吗？
```

**audit2allow 可能生成过于宽松的策略**：

```
# 真实案例：某工程师盲目使用 audit2allow
# 生成的策略内容：

module myfix 1.0;

require {
    type httpd_t;
    type shadow_t;
    class file { read open getattr };
}

# 这条规则允许 httpd 读取 /etc/shadow！
allow httpd_t shadow_t:file { read open getattr };
```

**这比 setenforce 0 更危险** — 因为看起来 SELinux 还是 Enforcing，但实际上 httpd 可以读取密码文件。

---

## Step 4 — 自定义策略基础（30 分钟）

### 4.1 策略模块结构

自定义策略由两个核心文件组成：

```
myapp.te    ← 类型强制（Type Enforcement）规则
myapp.fc    ← 文件上下文（File Context）定义（可选）
```

### 4.2 安全的策略创建流程

```bash
# Step 1: 收集 AVC 拒绝（在 Permissive 模式下运行一段时间）
sudo setenforce 0
# ... 运行应用，产生所有可能的操作 ...
sudo ausearch -m avc -ts today > /tmp/avc-denials.log

# Step 2: 生成策略草案
sudo audit2allow -i /tmp/avc-denials.log -m myapp > myapp.te

# Step 3: ⚠️ 审核策略内容！
cat myapp.te
# 检查每一条 allow 规则是否合理

# Step 4: 编译策略
sudo checkmodule -M -m -o myapp.mod myapp.te
sudo semodule_package -o myapp.pp -m myapp.mod

# Step 5: 恢复 Enforcing 模式
sudo setenforce 1

# Step 6: 安装策略
sudo semodule -i myapp.pp

# Step 7: 测试验证
# ... 测试应用功能 ...
```

### 4.3 策略审核要点

审核 `.te` 文件时，注意这些危险信号：

**危险规则（绝对不要接受）**：

```
# 允许访问密码文件
allow some_t shadow_t:file { read open getattr };

# 允许所有文件操作
allow some_t some_type:file *;

# 允许所有网络操作
allow some_t self:capability { net_raw net_admin };

# 允许执行任意程序
allow some_t bin_t:file { execute execute_no_trans };
```

**需要仔细评估的规则**：

```
# 允许网络连接 - 确认目标端口是否合理
allow httpd_t port_type:tcp_socket name_connect;

# 允许读取特定目录 - 确认路径是否合理
allow myapp_t mydata_t:dir { read open search };
```

### 4.4 实战：自定义应用策略示例

假设我们有一个自定义应用 `/opt/myapp/bin/myapp`，需要：

- 读取 `/opt/myapp/data/` 目录
- 监听 8888 端口
- 写入 `/var/log/myapp/`

**myapp.te**：

```
# 自定义应用 SELinux 策略
# 创建者: [your name]
# 日期: [date]
# 用途: myapp 应用访问控制

policy_module(myapp, 1.0)

# 声明类型
type myapp_t;
type myapp_exec_t;
type myapp_data_t;
type myapp_log_t;

# myapp_t 是域类型（进程类型）
domain_type(myapp_t)

# myapp_exec_t 是可执行文件类型，转换到 myapp_t 域
domain_entry_file(myapp_t, myapp_exec_t)

# 允许 myapp_t 读取 myapp_data_t 类型的文件
allow myapp_t myapp_data_t:dir { read open search };
allow myapp_t myapp_data_t:file { read open getattr };

# 允许 myapp_t 写入 myapp_log_t 类型的文件
allow myapp_t myapp_log_t:dir { read open search add_name };
allow myapp_t myapp_log_t:file { create write open append getattr };

# 允许 myapp_t 监听 8888 端口
# 需要先: semanage port -a -t myapp_port_t -p tcp 8888
type myapp_port_t;
allow myapp_t myapp_port_t:tcp_socket name_bind;
```

**myapp.fc**：

```
# 文件上下文定义

# 可执行文件
/opt/myapp/bin/myapp    --    system_u:object_r:myapp_exec_t:s0

# 数据目录
/opt/myapp/data(/.*)?         system_u:object_r:myapp_data_t:s0

# 日志目录
/var/log/myapp(/.*)?          system_u:object_r:myapp_log_t:s0
```

**build-install.sh**：

```bash
#!/bin/bash
# 编译和安装自定义 SELinux 策略模块
# 使用方法: sudo ./build-install.sh

set -e

MODULE_NAME="myapp"

echo "=== 编译 SELinux 策略模块: ${MODULE_NAME} ==="

# 检查依赖
if ! command -v checkmodule &> /dev/null; then
    echo "错误: 需要安装 policycoreutils-devel"
    echo "运行: sudo dnf install policycoreutils-devel"
    exit 1
fi

# 编译类型强制规则
echo "编译 ${MODULE_NAME}.te ..."
checkmodule -M -m -o ${MODULE_NAME}.mod ${MODULE_NAME}.te

# 打包策略模块
echo "打包 ${MODULE_NAME}.pp ..."
semodule_package -o ${MODULE_NAME}.pp -m ${MODULE_NAME}.mod -f ${MODULE_NAME}.fc

# 安装策略模块
echo "安装策略模块 ..."
semodule -i ${MODULE_NAME}.pp

# 应用文件上下文
echo "应用文件上下文 ..."
restorecon -Rv /opt/myapp/ /var/log/myapp/

# 添加端口类型（如果尚未添加）
if ! semanage port -l | grep -q myapp_port_t; then
    echo "添加端口类型 ..."
    semanage port -a -t myapp_port_t -p tcp 8888
fi

echo "=== 安装完成 ==="
echo "验证: semodule -l | grep ${MODULE_NAME}"
semodule -l | grep ${MODULE_NAME}
```

---

## Step 5 — 动手实验（30 分钟）

### 5.1 实验 A：WordPress 数据库连接场景

使用准备好的模拟脚本：

```bash
# 进入实验目录
cd ~/cloud-atlas/foundations/linux/security/05-selinux-advanced/code/wordpress-db-scenario

# 查看脚本说明
cat README.md

# 运行诊断脚本
sudo bash diagnose-connection.sh

# 运行修复脚本
sudo bash fix-boolean.sh

# 验证修复
sudo bash verify-fix.sh
```

### 5.2 实验 B：探索 Booleans

```bash
# 列出所有 httpd 相关 Boolean
getsebool -a | grep httpd

# 查看每个 Boolean 的说明
sudo semanage boolean -l | grep httpd | head -10

# 检查哪些 Boolean 已启用
getsebool -a | grep httpd | grep " on"

# 练习：假设需要 httpd 发送邮件
# 1. 查找相关 Boolean
getsebool -a | grep -i mail | grep httpd

# 2. 查看说明
sudo semanage boolean -l | grep httpd_can_sendmail

# 3. 启用（如果需要）
# sudo setsebool -P httpd_can_sendmail on
```

### 5.3 实验 C：审核策略（安全意识培养）

```bash
# 进入策略示例目录
cd ~/cloud-atlas/foundations/linux/security/05-selinux-advanced/code/custom-policy-demo

# 查看示例策略
cat myapp.te

# 讨论：这个策略安全吗？
# - 哪些规则是合理的？
# - 哪些规则可能有风险？
# - 如何改进？
```

---

## 反模式：audit2allow 滥用

### 反模式 1：盲目接受 audit2allow 输出

```bash
# 危险！不审核就安装
sudo ausearch -m avc -ts today | audit2allow -M quickfix
sudo semodule -i quickfix.pp
# "问题解决了！" — 但你可能开了很大的安全漏洞
```

**正确做法**：

```bash
# 1. 先生成策略到文件
sudo ausearch -m avc -ts today | audit2allow -m mypolicy > mypolicy.te

# 2. 审核内容
cat mypolicy.te
# 检查每一条 allow 规则！

# 3. 确认无危险规则后，才编译安装
```

### 反模式 2：跳过 Boolean 直接写策略

```bash
# 错误思路
# "SELinux 阻止了，我来写个策略"
sudo audit2allow -M myfix ...

# 正确思路
# "SELinux 阻止了，先检查有没有 Boolean"
getsebool -a | grep <service>
sudo semanage boolean -l | grep <keyword>
```

### 反模式 3：策略堆积

```bash
# 每次遇到问题就加个策略
sudo semodule -l | wc -l
# 输出: 150+ 策略模块...

# 问题：
# - 策略冲突
# - 维护困难
# - 不知道哪个策略做什么
# - 升级系统时可能出问题
```

**正确做法**：

- 定期审查自定义策略
- 合并相关策略
- 删除不再需要的策略
- 文档记录每个策略的用途

---

## 职场小贴士（Japan IT Context）

### SELinux 变更管理

在日本 IT 职场，SELinux 相关变更需要记录和审批：

| 日语术语 | 含义 | 实践要点 |
|----------|------|----------|
| 変更管理（へんこうかんり） | 变更管理 | Boolean 变更需要申请 |
| 影響範囲（えいきょうはんい） | 影响范围 | 评估 Boolean 影响 |
| 切り戻し手順（きりもどし） | 回滚步骤 | setsebool -P xxx off |
| 本番適用（ほんばんてきよう） | 生产应用 | 先测试环境验证 |

### 典型审批流程

```
1. 问题发生 → 确认是 SELinux 问题
2. 分析原因 → audit2why 输出
3. 确定方案 → Boolean / fcontext / 自定义策略
4. 填写变更申请 → 说明影响范围和回滚步骤
5. 审批 → 安全团队确认
6. 测试环境验证 → 先在 staging 测试
7. 本番适用 → 生产环境执行
8. 验证 → 确认功能正常
9. 记录 → 更新运维文档
```

### 变更记录模板

```markdown
## SELinux 変更履歴

### 変更日時: 2026-01-04 14:30 JST
### 変更者: 田中太郎
### チケット番号: INC-2026-0104-001

#### 変更内容
- Boolean 変更: httpd_can_network_connect_db → on

#### 変更理由
WordPress から Amazon RDS への接続に必要

#### 影響範囲
- 対象サーバー: web01.example.com
- 影響サービス: Apache/httpd
- 影響: httpd プロセスがデータベースポートへ接続可能になる

#### 切り戻し手順
```bash
sudo setsebool -P httpd_can_network_connect_db off
sudo systemctl restart httpd
```

#### 検証結果
- テスト環境: OK (2026-01-04 14:00)
- 本番環境: OK (2026-01-04 14:35)
```

---

## 检查清单

完成本课后，你应该能够：

- [ ] 使用 `getsebool -a | grep <service>` 查找相关 Booleans
- [ ] 使用 `semanage boolean -l` 查看 Boolean 说明
- [ ] 使用 `setsebool -P` 永久设置 Boolean
- [ ] 解释 Boolean vs fcontext vs port vs 自定义策略的选择标准
- [ ] 按照「Boolean 优先，自定义策略最后」的原则处理问题
- [ ] 使用 audit2why 分析拒绝原因
- [ ] 理解 audit2allow 生成的策略内容
- [ ] 识别危险的策略规则（如访问 shadow_t）
- [ ] 解释为什么盲目使用 audit2allow -M 是危险的
- [ ] 完成 WordPress 远程数据库连接场景的修复

---

## 本课小结

| 概念 | 命令/方法 | 记忆点 |
|------|-----------|--------|
| 查询 Boolean | `getsebool -a \| grep xxx` | Boolean 是预定义开关 |
| 设置 Boolean | `setsebool -P xxx on` | -P = 永久 |
| Boolean 说明 | `semanage boolean -l` | 查看每个 Boolean 的用途 |
| 决策顺序 | Boolean → Port → Fcontext → Custom | Boolean 优先！ |
| 生成策略 | `audit2allow -m xxx` | 必须审核输出 |
| 编译策略 | `checkmodule` + `semodule_package` | .te → .mod → .pp |
| 安装策略 | `semodule -i xxx.pp` | 自定义策略最后手段 |
| **警告** | audit2allow -M 盲目使用 | 可能产生危险权限 |

---

## 延伸阅读

- [Red Hat SELinux Booleans Guide](https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/9/html/using_selinux/configuring-selinux-for-applications-and-services-with-non-standard-configurations_using-selinux)
- [SELinux Policy Development](https://selinuxproject.org/page/PolicyDevelopment)
- 上一课：[04 · SELinux 排错实战](../04-selinux-troubleshooting/) — ausearch、audit2why、semanage fcontext
- 下一课：[06 · Linux Capabilities](../06-capabilities/) — 精细权限控制

---

## 系列导航

[04 · SELinux 排错实战 <-](../04-selinux-troubleshooting/) | [系列首页](../) | [06 · Linux Capabilities ->](../06-capabilities/)
