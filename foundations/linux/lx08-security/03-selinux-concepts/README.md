# 03 · SELinux 核心概念（SELinux Core Concepts）

> **目标**：理解 SELinux 的保护作用，掌握三种模式和安全上下文  
> **前置**：完成 Lesson 01-02（安全原则与 SSH 加固）  
> **时间**：⚡ 35 分钟（速读）/ 🔬 130 分钟（完整实操）  
> **实战场景**：生产服务器安全加固、合规审计准备  

---

## 将学到的内容

1. 理解 SELinux 的目的和价值（保护你，不是阻碍你）
2. 掌握三种模式（Enforcing, Permissive, Disabled）及其适用场景
3. 理解安全上下文格式（user:role:type:level）
4. 学会查看文件、进程和用户的 SELinux 上下文
5. **关键心态**：SELinux 是你的安全网，不是敌人

---

## 先跑起来！（5 分钟）

> 在学习理论之前，先体验 SELinux 的存在。  
> 运行这些命令，观察输出 — 这就是你将要掌握的技能。  

```bash
# 检查 SELinux 状态
getenforce
# 输出: Enforcing  (或 Permissive/Disabled)

# 查看详细状态
sestatus

# 查看你自己的 SELinux 上下文
id -Z

# 查看文件的 SELinux 上下文
ls -Z /etc/passwd /var/www/html/ /home/ 2>/dev/null | head -5

# 查看进程的 SELinux 上下文
ps auxZ | grep -E 'sshd|httpd|nginx' | head -5
```

**你刚刚查看了系统的 SELinux 安全状态！**

看到那些 `system_u:object_r:passwd_file_t:s0` 格式的标签了吗？这就是 SELinux 用来保护你的系统的「安全上下文」。

现在让我们理解这一切意味着什么。

---

## Step 1 — SELinux 是什么：安全网，不是障碍（15 分钟）

### 1.1 传统权限的局限

还记得 [Lesson 01](../01-security-principles/) 中提到的 DAC 和 MAC 吗？

传统的 Linux 权限（DAC）有一个根本问题：**root 用户可以做任何事**。

```bash
# DAC 世界：root 无所不能
sudo cat /etc/shadow          # 读取密码哈希 - OK
sudo rm -rf /var/www/         # 删除 Web 目录 - OK
sudo chmod 777 /               # 破坏系统权限 - OK
```

这意味着：**一旦攻击者获得 root 权限，游戏结束**。

### 1.2 SELinux：最后一道防线

SELinux（Security-Enhanced Linux）是 MAC（强制访问控制）的实现：

```
DAC (传统权限)  →  "你是谁？你有权限吗？"
MAC (SELinux)  →  "这个进程类型，允许访问这个文件类型吗？"
```

**SELinux 不关心你是 root** — 它关心的是：

- 这个**进程**（httpd_t）是否被允许访问这个**文件类型**（user_home_t）？
- 即使 root 运行的进程，也受 SELinux 策略约束

<!-- DIAGRAM: selinux-protection-layers -->
```
SELinux 保护层级
═══════════════════════════════════════════════════════════════════════════

攻击者 → 网络层防护 → 应用层防护 → DAC 权限 → SELinux → 内核
          │             │            │           │
          │             │            │           └── 最后一道防线！
          │             │            └── 传统权限（owner/group/others）
          │             └── 应用程序自身的认证/授权
          └── 防火墙、SSH 加固等

场景：攻击者获得了 Web 服务器 root 权限

没有 SELinux:
┌─────────────────────────────────────────────────────────────────────┐
│  攻击者 (root) → 读取 /etc/shadow → 获取密码哈希 → 破解 → 完全控制   │
│  攻击者 (root) → 修改 /var/www → 植入后门 → 持久化                  │
│  攻击者 (root) → 访问 /home → 窃取用户数据                          │
└─────────────────────────────────────────────────────────────────────┘

有 SELinux (Enforcing):
┌─────────────────────────────────────────────────────────────────────┐
│  httpd_t 进程 → 尝试读取 /etc/shadow (shadow_t)                      │
│      ↓                                                              │
│  SELinux 策略检查: httpd_t 可以访问 shadow_t 吗？                    │
│      ↓                                                              │
│  策略: 拒绝! → AVC denial 日志 → 攻击失败！                          │
│                                                                     │
│  即使是 root 运行的 httpd，也无法越权访问                            │
└─────────────────────────────────────────────────────────────────────┘
```
<!-- /DIAGRAM -->

### 1.3 思维转变：保护 vs 限制

很多人第一次遇到 SELinux 时的想法：

> "SELinux 阻止我的应用运行！关掉它！"  

正确的思维应该是：

> "SELinux 发现了我的配置问题。让我看看哪里需要调整。"  

**类比**：

| 错误思维 | 正确思维 |
|----------|----------|
| 安全带勒着我不舒服，解掉 | 安全带保护我，调整到合适位置 |
| 杀毒软件误报，关掉 | 杀毒软件提醒我检查这个文件 |
| SELinux 阻止我，禁用 | SELinux 保护我，学会正确配置 |

### 1.4 谁在使用 SELinux？

| 发行版 | 默认 MAC 系统 | 备注 |
|--------|--------------|------|
| RHEL/CentOS/Rocky/Alma | **SELinux** | Enforcing 模式 |
| Fedora | **SELinux** | Enforcing 模式 |
| Amazon Linux | **SELinux** | Permissive 模式 |
| Ubuntu/Debian | AppArmor | 不同的 MAC 实现 |
| SUSE | AppArmor | 不同的 MAC 实现 |

> **日本 IT 市场**：RHEL 是企业标准，SELinux 是必备知识。  
> 安全审计时，`getenforce` 输出 `Enforcing` 是基本要求。  

---

## Step 2 — 三种模式：Enforcing, Permissive, Disabled（20 分钟）

### 2.1 模式概览

SELinux 有三种运行模式：

<!-- DIAGRAM: selinux-three-modes -->
```
SELinux 三种模式
═══════════════════════════════════════════════════════════════════════════

┌────────────────────────────────────────────────────────────────────────┐
│                          Enforcing (强制)                               │
│                                                                        │
│  ✓ 策略生效，违规操作被阻止                                              │
│  ✓ 拒绝记录到 audit 日志                                                │
│  ✓ 生产环境唯一正确选择                                                  │
│                                                                        │
│  进程 (httpd_t) → 访问 shadow_t → SELinux 检查 → 拒绝！操作失败          │
└────────────────────────────────────────────────────────────────────────┘
                                    │
                                    │ setenforce 0 (临时调试)
                                    ▼
┌────────────────────────────────────────────────────────────────────────┐
│                          Permissive (宽容)                              │
│                                                                        │
│  ✓ 策略不强制执行，但仍然记录                                            │
│  ✓ 违规操作被允许但写入日志                                              │
│  ✓ 调试排错的正确选择                                                   │
│                                                                        │
│  进程 (httpd_t) → 访问 shadow_t → SELinux 检查 → 记录！操作成功          │
│                                                                        │
│  ⚠️ 临时使用！排错完成后必须回到 Enforcing                               │
└────────────────────────────────────────────────────────────────────────┘
                                    │
                                    │ SELINUX=disabled (永久禁用)
                                    ▼
┌────────────────────────────────────────────────────────────────────────┐
│                          Disabled (禁用)                                │
│                                                                        │
│  ✗ SELinux 完全关闭                                                     │
│  ✗ 没有保护，没有日志                                                   │
│  ✗ 重新启用需要完整 relabel（耗时！）                                    │
│                                                                        │
│  ❌ 永远不要选择这个！                                                   │
└────────────────────────────────────────────────────────────────────────┘
```
<!-- /DIAGRAM -->

### 2.2 查看当前模式

```bash
# 简单查看
getenforce
# 输出: Enforcing / Permissive / Disabled

# 详细状态
sestatus
```

**sestatus 输出解读**：

```
SELinux status:                 enabled
SELinuxfs mount:                /sys/fs/selinux
SELinux root directory:         /etc/selinux
Loaded policy name:             targeted
Current mode:                   enforcing    ← 当前运行模式
Mode from config file:          enforcing    ← 配置文件设置
Policy MLS status:              enabled
Policy deny_unknown status:     allowed
Memory protection checking:     actual (secure)
Max kernel policy version:      33
```

### 2.3 临时切换模式（setenforce）

```bash
# 切换到 Permissive（临时，调试用）
sudo setenforce 0
getenforce
# 输出: Permissive

# 切换回 Enforcing
sudo setenforce 1
getenforce
# 输出: Enforcing
```

**注意**：

- `setenforce` 是**临时**的，重启后恢复配置文件设置
- 只能在 Enforcing ↔ Permissive 之间切换
- 如果当前是 Disabled，`setenforce` 不起作用（需要重启）

### 2.4 永久配置（/etc/selinux/config）

```bash
# 查看配置文件
cat /etc/selinux/config
```

```ini
# This file controls the state of SELinux on the system.
# SELINUX= can take one of these three values:
#     enforcing - SELinux security policy is enforced.
#     permissive - SELinux prints warnings instead of enforcing.
#     disabled - No SELinux policy is loaded.
SELINUX=enforcing

# SELINUXTYPE= can take one of these three values:
#     targeted - Targeted processes are protected,
#     minimum - Modification of targeted policy. Only selected processes are protected.
#     mls - Multi Level Security protection.
SELINUXTYPE=targeted
```

**修改配置后需要重启才生效**。

### 2.5 为什么永远不要 Disabled？

| 问题 | Permissive | Disabled |
|------|------------|----------|
| 有日志记录 | 有（可以分析问题） | 无 |
| 重新启用 | setenforce 1 立即生效 | 需要重启 + relabel |
| relabel 耗时 | 不需要 | 大系统可能需要 30+ 分钟 |
| 安全审计 | 可以接受（临时调试） | 立即 FAIL |

**Disabled 的隐藏代价**：

```bash
# 如果从 Disabled 恢复到 Enforcing
# 1. 修改 /etc/selinux/config
# 2. 创建 /.autorelabel 触发文件
touch /.autorelabel

# 3. 重启 — 系统会花很长时间 relabel 所有文件
# 大型文件系统可能需要 30 分钟到数小时！
```

**结论**：调试用 Permissive，生产用 Enforcing，永远不要 Disabled。

---

## Step 3 — 安全上下文：user:role:type:level（25 分钟）

### 3.1 上下文格式

SELinux 给每个进程、文件、用户打上「安全上下文」标签：

```
system_u:object_r:httpd_sys_content_t:s0
   │        │           │             │
   │        │           │             └── Level (MLS/MCS 级别)
   │        │           └── Type (类型) ← 最重要！
   │        └── Role (角色)
   └── User (SELinux 用户)
```

**日常工作中，只需关注 Type（类型）**。

### 3.2 Type：最重要的部分

Type 决定了「谁能访问什么」：

```
进程类型 (httpd_t)  ─── 策略规则 ───▶  文件类型 (httpd_sys_content_t)
                           │
                           └── "httpd_t 可以读取 httpd_sys_content_t"
```

**常见类型示例**：

| 类型 | 说明 | 典型文件 |
|------|------|----------|
| `httpd_sys_content_t` | Web 服务器内容 | /var/www/html/ |
| `httpd_t` | Apache/Nginx 进程 | httpd, nginx 进程 |
| `sshd_t` | SSH 守护进程 | sshd 进程 |
| `user_home_t` | 用户主目录 | /home/user/ |
| `passwd_file_t` | 密码文件 | /etc/passwd |
| `shadow_t` | 影子密码文件 | /etc/shadow |
| `container_t` | 容器进程 | Docker/Podman 容器 |

### 3.3 查看上下文的命令

**查看文件上下文**：

```bash
# ls -Z 查看文件上下文
ls -Z /etc/passwd
# -rw-r--r--. root root system_u:object_r:passwd_file_t:s0 /etc/passwd

ls -Z /var/www/html/
# drwxr-xr-x. root root system_u:object_r:httpd_sys_content_t:s0 .

ls -Z /home/
# drwx------. alice alice unconfined_u:object_r:user_home_dir_t:s0 alice
```

**查看进程上下文**：

```bash
# ps auxZ 查看进程上下文
ps auxZ | grep sshd
# system_u:system_r:sshd_t:s0-s0:c0.c1023 root 1234 ... /usr/sbin/sshd -D

ps auxZ | grep httpd
# system_u:system_r:httpd_t:s0    root 5678 ... /usr/sbin/httpd -DFOREGROUND
```

**查看用户上下文**：

```bash
# id -Z 查看当前用户上下文
id -Z
# unconfined_u:unconfined_r:unconfined_t:s0-s0:c0.c1023
```

### 3.4 上下文解读实战

```bash
# 创建实验目录
mkdir -p ~/selinux-lab && cd ~/selinux-lab

# 创建一个文件，查看默认上下文
touch myfile.txt
ls -Z myfile.txt
# 输出类似: unconfined_u:object_r:user_home_t:s0 myfile.txt

# 创建到 /tmp 的文件
touch /tmp/tempfile.txt
ls -Z /tmp/tempfile.txt
# 输出类似: unconfined_u:object_r:user_tmp_t:s0 /tmp/tempfile.txt

# 不同目录，不同类型！
#   ~/          → user_home_t
#   /tmp        → user_tmp_t
#   /var/www    → httpd_sys_content_t
```

### 3.5 为什么类型很重要？

考虑这个场景：

```bash
# Web 服务器配置指向 /home/alice/website
# 文件权限完美：755 目录，644 文件
# 但是 Nginx 返回 403 Forbidden！

ls -Z /home/alice/website/
# -rw-r--r--. alice alice unconfined_u:object_r:user_home_t:s0 index.html
#                                                    ↑
#                                         类型是 user_home_t，不是 httpd_sys_content_t！
```

**SELinux 策略**：`httpd_t` 进程**不允许**读取 `user_home_t` 类型的文件。

即使 DAC 权限（755/644）允许，SELinux 也会阻止。这就是 MAC 的威力。

> 修复方法见 [Lesson 04: SELinux 排错实战](../04-selinux-troubleshooting/)  

---

## Step 4 — 动手实验（30 分钟）

### 4.1 实验 A：上下文探索

```bash
# 切换到实验目录
cd ~/selinux-lab

# 查看系统各处的 SELinux 上下文
echo "=== 系统目录 ==="
ls -Z /etc/passwd /etc/shadow /etc/ssh/sshd_config

echo "=== Web 目录 ==="
ls -Zd /var/www/html/ 2>/dev/null || echo "Web 目录不存在"

echo "=== 用户目录 ==="
ls -Zd ~ /tmp/

echo "=== 进程上下文 ==="
ps auxZ | grep -E 'sshd|httpd|nginx|systemd' | head -5

echo "=== 当前用户上下文 ==="
id -Z
```

**观察要点**：

- 不同目录有不同的类型（`passwd_file_t`, `shadow_t`, `sshd_key_t` 等）
- 进程类型与其服务相关（`sshd_t`, `httpd_t`）
- 普通用户通常是 `unconfined_t`（不受限制的类型）

### 4.2 实验 B：模式切换（需要 root）

> **警告**：在生产环境，只有在排错时才临时切换到 Permissive！  

```bash
# 查看当前模式
getenforce

# 记录当前模式
ORIGINAL_MODE=$(getenforce)
echo "原始模式: $ORIGINAL_MODE"

# 如果是 Enforcing，临时切换到 Permissive
if [ "$ORIGINAL_MODE" = "Enforcing" ]; then
    sudo setenforce 0
    echo "已切换到 Permissive"
    getenforce

    # 模拟调试完成，切换回来
    echo "调试完成，恢复 Enforcing..."
    sudo setenforce 1
    getenforce
fi

# 验证恢复
echo "最终模式: $(getenforce)"
```

### 4.3 实验 C：运行上下文查看脚本

使用我们准备的脚本快速查看系统上下文：

```bash
# 进入代码目录
cd ~/cloud-atlas/foundations/linux/lx08-security/03-selinux-concepts/code

# 运行上下文查看脚本
bash context-viewer.sh

# 运行模式演示脚本（展示但不实际切换）
bash mode-demo.sh
```

---

## 反模式：致命的 SELinux 错误

### 反模式 1：setenforce 0 作为解决方案

```bash
# 看到 SELinux 错误，直接禁用
sudo setenforce 0
# "问题解决了！" — 错！问题只是被隐藏了

# 这相当于：
# - 发现汽车仪表盘亮红灯
# - 用胶带把灯贴住
# - "问题解决了！"
```

**正确做法**：

```bash
# 1. 切换到 Permissive 调试
sudo setenforce 0

# 2. 查看拒绝日志
sudo ausearch -m avc -ts recent

# 3. 理解拒绝原因
sudo audit2why < /var/log/audit/audit.log

# 4. 应用正确修复（Boolean 或 fcontext）
# ...

# 5. 切换回 Enforcing 验证
sudo setenforce 1
```

### 反模式 2：SELINUX=disabled 永久禁用

```bash
# /etc/selinux/config
SELINUX=disabled   # 永远不要这样做！
```

**为什么是灾难**：

1. **失去所有保护** — MAC 防线完全消失
2. **重新启用代价高** — 需要 relabel 全部文件
3. **合规立即失败** — 任何安全审计都会标红
4. **习惯形成** — 一旦禁用，再也不会学习正确用法

### 反模式 3：不看日志就放弃

```bash
# "SELinux 阻止了，但我不知道原因"
# "算了，关掉 SELinux 吧"
```

**正确做法**：

```bash
# SELinux 总是告诉你原因！
# 日志在 /var/log/audit/audit.log

# 最近的拒绝
sudo ausearch -m avc -ts recent

# 人类可读的建议
sudo sealert -a /var/log/audit/audit.log 2>/dev/null || \
sudo audit2why < /var/log/audit/audit.log
```

---

## 职场小贴士（Japan IT Context）

### SELinux 在日本 IT 职场

日本企业运维中，SELinux 是标准要求：

| 日语术语 | 含义 | 实践要点 |
|----------|------|----------|
| セキュリティ強化（きょうか） | 安全加固 | SELinux Enforcing 是基线 |
| コンプライアンス対応 | 合规应对 | 审计要求 SELinux 启用 |
| 変更履歴（へんこうりれき） | 变更记录 | 记录 setenforce、semanage 操作 |
| 障害対応（しょうがいたいおう） | 故障处理 | 先看 AVC 日志再判断 |

### 安全审计检查项

日本企业的安全审计（セキュリティ監査）经常检查：

```bash
# 审计员会运行这些命令
getenforce
# 期望输出: Enforcing

sestatus
# 检查 Current mode 和 Mode from config file 都是 enforcing

# 查看是否有未解决的 AVC 拒绝
ausearch -m avc -ts today | head
```

**审计要求**：

| 检查项 | 期望状态 | 不合格后果 |
|--------|----------|------------|
| getenforce | Enforcing | 审计失败，需要整改报告 |
| SELINUX=enforcing | 配置文件一致 | 安全例外申请 |
| 无未解决 AVC | 已知问题有文档 | 需要说明理由 |

### 实际场景：新服务器交付

在日本 IT 现场，服务器交付时的标准检查：

```bash
#!/bin/bash
# 服务器安全基线检查（サーバーセキュリティ基線チェック）

echo "=== SELinux 状态检查 ==="
MODE=$(getenforce)
echo "当前模式: $MODE"

if [ "$MODE" != "Enforcing" ]; then
    echo "警告: SELinux 不在 Enforcing 模式！"
    echo "这在生产环境是不可接受的。"
    exit 1
fi

echo "OK: SELinux Enforcing"

# 检查是否有未解决的拒绝
AVC_COUNT=$(ausearch -m avc -ts today 2>/dev/null | grep -c "avc:" || echo 0)
echo "今日 AVC 拒绝数: $AVC_COUNT"
```

---

<details>
<summary>AppArmor 概览（Ubuntu/SUSE 用户点击展开）</summary>

## AppArmor：另一种 MAC 实现

如果你使用 Ubuntu 或 SUSE，默认的 MAC 系统是 AppArmor，不是 SELinux。

### SELinux vs AppArmor

| 特性 | SELinux | AppArmor |
|------|---------|----------|
| 标签方式 | 基于标签（给每个对象打标签） | 基于路径（规则绑定到路径） |
| 默认发行版 | RHEL, Fedora, CentOS | Ubuntu, SUSE, Debian |
| 学习曲线 | 较陡（但更强大） | 较平缓 |
| 策略粒度 | 更细（type, role, user, level） | 中等（主要是 profile） |

### AppArmor 基础命令

```bash
# 查看状态
sudo aa-status

# 查看所有 profile
sudo aa-status --complaining   # 类似 SELinux Permissive
sudo aa-status --enforcing     # 类似 SELinux Enforcing

# 切换 profile 模式
sudo aa-complain /usr/sbin/nginx   # 切换到警告模式
sudo aa-enforce /usr/sbin/nginx    # 切换到强制模式

# 禁用/启用 profile
sudo aa-disable /etc/apparmor.d/usr.sbin.nginx
sudo aa-enable /etc/apparmor.d/usr.sbin.nginx
```

### 原则相通

无论 SELinux 还是 AppArmor：

1. **不要禁用** — 学会正确配置
2. **调试用宽容模式** — SELinux Permissive / AppArmor complain
3. **生产用强制模式** — SELinux Enforcing / AppArmor enforce
4. **查看日志排错** — 两者都有详细日志

本课程聚焦 SELinux（因为 RHEL 在日本企业主流），但原则可以迁移到 AppArmor。

</details>

---

## 检查清单

完成本课后，你应该能够：

- [ ] 解释 SELinux 为什么是「安全网」而不是「障碍」
- [ ] 说明 DAC 和 MAC 的区别和互补关系
- [ ] 使用 `getenforce` 和 `sestatus` 查看 SELinux 状态
- [ ] 描述 Enforcing、Permissive、Disabled 三种模式的区别
- [ ] 使用 `setenforce` 临时切换模式（仅用于调试）
- [ ] 解释为什么永远不应该使用 Disabled 模式
- [ ] 理解安全上下文格式 `user:role:type:level`
- [ ] 使用 `ls -Z` 查看文件上下文
- [ ] 使用 `ps auxZ` 查看进程上下文
- [ ] 使用 `id -Z` 查看用户上下文
- [ ] 识别常见类型（httpd_t, sshd_t, user_home_t 等）

---

## 本课小结

| 概念 | 命令/配置 | 记忆点 |
|------|-----------|--------|
| MAC 保护 | SELinux | 即使 root 也受限制 |
| 查看模式 | `getenforce` | Enforcing = 生产环境 |
| 详细状态 | `sestatus` | 查看配置和运行状态 |
| 临时切换 | `setenforce 0/1` | 调试用，重启后失效 |
| 永久配置 | `/etc/selinux/config` | 修改后需重启 |
| 文件上下文 | `ls -Z` | 看 Type（类型） |
| 进程上下文 | `ps auxZ` | 进程类型决定能做什么 |
| 用户上下文 | `id -Z` | 普通用户通常 unconfined |
| **永远不要** | `SELINUX=disabled` | Permissive 调试，Enforcing 生产 |

---

## 延伸阅读

- [Red Hat SELinux Guide](https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/9/html/using_selinux/index)
- [SELinux Project Wiki](https://selinuxproject.org/page/Main_Page)
- 下一课：[04 · SELinux 排错实战](../04-selinux-troubleshooting/) — 学习 ausearch、audit2why、semanage fcontext
- 相关课程：[05 · SELinux 进阶](../05-selinux-advanced/) — Booleans 与自定义策略

---

## 系列导航

[02 · SSH 现代化加固 ←](../02-ssh-hardening/) | [系列首页](../) | [04 · SELinux 排错实战 →](../04-selinux-troubleshooting/)
