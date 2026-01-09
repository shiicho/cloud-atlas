# SELinux 排错工作流速查表

## 六步排错法

```
问题发生
    │
    ▼
┌───────────────────────────────────────────────────────────────────────────┐
│  Step 1: 确认是 SELinux 问题                                               │
│                                                                           │
│  ausearch -m avc -ts recent                                               │
│                                                                           │
│  有 AVC 拒绝？ → 继续排错                                                  │
│  无 AVC 拒绝？ → 检查 DAC 权限 (ls -l) 或服务配置                           │
└───────────────────────────────────────────────────────────────────────────┘
    │
    ▼
┌───────────────────────────────────────────────────────────────────────────┐
│  Step 2: 理解拒绝原因                                                      │
│                                                                           │
│  ausearch -m avc -ts recent | audit2why                                   │
│                                                                           │
│  输出告诉你：                                                              │
│  - "Missing type enforcement (TE) allow rule" → 需要修改上下文或策略       │
│  - "One of the following booleans was set incorrectly" → 需要设置 Boolean  │
└───────────────────────────────────────────────────────────────────────────┘
    │
    ▼
┌───────────────────────────────────────────────────────────────────────────┐
│  Step 3: 获取修复建议                                                      │
│                                                                           │
│  sealert -a /var/log/audit/audit.log                                      │
│                                                                           │
│  提供人类可读的建议，包括：                                                 │
│  - 推荐的修复命令                                                          │
│  - 置信度评分                                                              │
│  - 可能的原因分析                                                          │
└───────────────────────────────────────────────────────────────────────────┘
    │
    ▼
┌───────────────────────────────────────────────────────────────────────────┐
│  Step 4: 选择修复方法                                                      │
│                                                                           │
│  ┌─────────────────────────────────────────────────────────────────────┐  │
│  │ Boolean 问题？                                                       │  │
│  │                                                                     │  │
│  │ getsebool -a | grep <service>                                       │  │
│  │ setsebool -P <boolean> on                                           │  │
│  │                                                                     │  │
│  │ 例：setsebool -P httpd_can_network_connect_db on                    │  │
│  └─────────────────────────────────────────────────────────────────────┘  │
│                                                                           │
│  ┌─────────────────────────────────────────────────────────────────────┐  │
│  │ 文件上下文问题？                                                     │  │
│  │                                                                     │  │
│  │ semanage fcontext -a -t <type> "/path/regex"                        │  │
│  │ restorecon -Rv /path                                                │  │
│  │                                                                     │  │
│  │ 例：semanage fcontext -a -t httpd_sys_content_t "/data/www(/.*)?"   │  │
│  │     restorecon -Rv /data/www                                        │  │
│  └─────────────────────────────────────────────────────────────────────┘  │
│                                                                           │
│  ┌─────────────────────────────────────────────────────────────────────┐  │
│  │ 端口问题？                                                           │  │
│  │                                                                     │  │
│  │ semanage port -l | grep <type>                                      │  │
│  │ semanage port -a -t <type> -p <proto> <port>                        │  │
│  │                                                                     │  │
│  │ 例：semanage port -a -t http_port_t -p tcp 8888                     │  │
│  └─────────────────────────────────────────────────────────────────────┘  │
└───────────────────────────────────────────────────────────────────────────┘
    │
    ▼
┌───────────────────────────────────────────────────────────────────────────┐
│  Step 5: 验证修复                                                          │
│                                                                           │
│  # 重启服务                                                                │
│  systemctl restart <service>                                              │
│                                                                           │
│  # 测试功能                                                                │
│  curl http://localhost/                                                   │
│                                                                           │
│  # 确认无新拒绝                                                            │
│  ausearch -m avc -ts recent                                               │
└───────────────────────────────────────────────────────────────────────────┘
    │
    ▼
┌───────────────────────────────────────────────────────────────────────────┐
│  Step 6: 记录变更                                                          │
│                                                                           │
│  echo "$(date) - semanage fcontext -a -t httpd_sys_content_t '/data/www'" │
│       >> /var/log/selinux-changes.log                                     │
│                                                                           │
│  # 日本 IT 现场：写入変更履歴 / 障害報告書                                   │
└───────────────────────────────────────────────────────────────────────────┘
```

---

## 常用命令速查

### 诊断命令

| 命令 | 用途 | 示例 |
|------|------|------|
| `getenforce` | 查看当前模式 | `getenforce` |
| `sestatus` | 详细状态 | `sestatus` |
| `ausearch -m avc` | 搜索 AVC 拒绝 | `ausearch -m avc -ts recent` |
| `audit2why` | 解释拒绝原因 | `ausearch -m avc \| audit2why` |
| `sealert -a` | 获取建议 | `sealert -a /var/log/audit/audit.log` |
| `ls -Z` | 查看文件上下文 | `ls -Z /data/www/` |
| `ps auxZ` | 查看进程上下文 | `ps auxZ \| grep nginx` |

### 修复命令

| 命令 | 用途 | 持久性 |
|------|------|--------|
| `chcon -t type path` | 临时修改上下文 | 临时 |
| `semanage fcontext -a` | 添加永久上下文规则 | **永久** |
| `restorecon -Rv path` | 应用策略规则 | - |
| `setsebool -P bool on` | 设置 Boolean（永久） | **永久** |
| `semanage port -a` | 添加端口规则 | **永久** |

### Boolean 操作

```bash
# 列出所有 Boolean
getsebool -a

# 搜索特定服务的 Boolean
getsebool -a | grep httpd

# 设置 Boolean（临时）
setsebool httpd_can_network_connect on

# 设置 Boolean（永久）
setsebool -P httpd_can_network_connect on
```

### 文件上下文操作

```bash
# 查看系统默认规则
semanage fcontext -l | grep /var/www

# 添加自定义规则
semanage fcontext -a -t httpd_sys_content_t "/data/www(/.*)?"

# 删除自定义规则
semanage fcontext -d "/data/www(/.*)?"

# 应用规则到文件系统
restorecon -Rv /data/www
```

### 端口操作

```bash
# 查看端口类型
semanage port -l | grep http

# 添加端口
semanage port -a -t http_port_t -p tcp 8888

# 删除端口
semanage port -d -t http_port_t -p tcp 8888
```

---

## 常见问题类型

### 问题 1：Web 服务器访问非标准目录

**症状**：Nginx/Apache 返回 403 Forbidden

**诊断**：
```bash
ls -Z /custom/webroot/
# 输出：... default_t ...  ← 类型错误！
```

**修复**：
```bash
semanage fcontext -a -t httpd_sys_content_t "/custom/webroot(/.*)?"
restorecon -Rv /custom/webroot
```

### 问题 2：服务无法绑定自定义端口

**症状**：服务启动失败，`systemctl status` 显示 bind 错误

**诊断**：
```bash
ausearch -m avc -ts recent | grep name_bind
# 输出：denied { name_bind } ... tclass=tcp_socket
```

**修复**：
```bash
semanage port -a -t http_port_t -p tcp 8888
```

### 问题 3：应用无法连接远程数据库

**症状**：应用日志显示 "Connection refused"，但 telnet 正常

**诊断**：
```bash
getsebool httpd_can_network_connect_db
# 输出：httpd_can_network_connect_db --> off
```

**修复**：
```bash
setsebool -P httpd_can_network_connect_db on
```

---

## 记忆口诀

```
排错六步走，日志先开头
ausearch 找拒绝，audit2why 看原因
sealert 给建议，semanage 改规则
restorecon 来应用，记录变更别忘记

chcon 改标签，重启就没了
semanage 改规则，永远都有效
生产用 semanage，测试用 chcon
```

---

## 日本 IT 现场术语

| 日语 | 中文 | 场景 |
|------|------|------|
| 障害対応（しょうがいたいおう） | 故障处理 | 遇到 SELinux 问题时 |
| 原因調査（げんいんちょうさ） | 根因分析 | 使用 ausearch/audit2why |
| 恒久対策（こうきゅうたいさく） | 永久修复 | semanage fcontext |
| 暫定対策（ざんていたいさく） | 临时修复 | chcon（应急用） |
| 変更履歴（へんこうりれき） | 变更记录 | 记录 semanage 命令 |
| セキュリティ監査 | 安全审计 | 检查 SELinux enforcing |
