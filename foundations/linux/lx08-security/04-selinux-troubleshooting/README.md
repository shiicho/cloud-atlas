# 04 · SELinux 排错实战（SELinux Troubleshooting）

> **目标**：掌握 SELinux 问题诊断流程，学会永久修复文件上下文  
> **前置**：完成 [Lesson 03 · SELinux 核心概念](../03-selinux-concepts/)  
> **时间**：2.5-3 小时  
> **实战场景**：Web 服务器迁移后 403 错误、自定义端口服务无法启动  

---

## 将学到的内容

1. 使用 `ausearch` 搜索 AVC 拒绝日志
2. 使用 `audit2why` 理解拒绝原因
3. 使用 `sealert` 获取人类可读的修复建议
4. **关键技能**：`semanage fcontext` 永久修复 vs `chcon` 临时修复
5. 掌握完整的 SELinux 排错工作流

---

## 先跑起来！制造一个 SELinux 问题（10 分钟）

> 在学习排错之前，先亲手制造一个 SELinux 问题。  
> 这就是日本 IT 现场常见的「障害対応」场景。  

### 场景：Nginx 迁移后 403 Forbidden

你接到任务：将 Web 内容从 `/usr/share/nginx/html` 迁移到独立分区 `/data/www`。

```bash
# 切换到 root（需要权限操作）
sudo -i

# 确认 SELinux 是 Enforcing（这是前提！）
getenforce
# 输出应该是: Enforcing

# 安装 Nginx（如果没有）
dnf install -y nginx

# 创建新目录并放置网页
mkdir -p /data/www
echo "<h1>Welcome from /data/www!</h1>" > /data/www/index.html

# 设置 DAC 权限（这些是正确的！）
chmod 755 /data
chmod 755 /data/www
chmod 644 /data/www/index.html

# 备份并修改 Nginx 配置
cp /etc/nginx/nginx.conf /etc/nginx/nginx.conf.bak
sed -i 's|/usr/share/nginx/html|/data/www|g' /etc/nginx/nginx.conf

# 重启 Nginx
systemctl restart nginx

# 测试访问
curl http://localhost/
```

**你会看到：**

```html
<html>
<head><title>403 Forbidden</title></head>
<body>
<center><h1>403 Forbidden</h1></center>
<hr><center>nginx/1.x.x</center>
</body>
</html>
```

**403 Forbidden？！** 但是：

- 文件权限是 `644`，目录是 `755`
- Nginx 配置语法检查通过 (`nginx -t`)
- 文件确实存在

**这就是 SELinux 在保护你的系统。** 现在让我们学习如何诊断和修复。

---

## Step 1 — SELinux 排错工作流（15 分钟）

### 1.1 排错六步法

遇到 SELinux 问题，按这个流程走：

<!-- DIAGRAM: selinux-troubleshooting-flowchart -->
```
SELinux 排错工作流
================================================================================

     问题发生（应用报错、403、Permission denied）
                    │
                    ▼
    ┌───────────────────────────────────────┐
    │  Step 1: 确认是 SELinux 问题           │
    │  ausearch -m avc -ts recent           │
    └───────────────────────────────────────┘
                    │
          有 AVC 拒绝？
           /          \
         Yes           No
          │             │
          ▼             ▼
    ┌─────────────┐   ┌─────────────────────────┐
    │  继续排错    │   │  检查 DAC 权限           │
    │             │   │  ls -l /path/to/file    │
    └─────────────┘   │  检查服务配置            │
          │           └─────────────────────────┘
          ▼
    ┌───────────────────────────────────────┐
    │  Step 2: 理解拒绝原因                   │
    │  audit2why < /var/log/audit/audit.log │
    └───────────────────────────────────────┘
                    │
                    ▼
    ┌───────────────────────────────────────┐
    │  Step 3: 获取修复建议                   │
    │  sealert -a /var/log/audit/audit.log  │
    └───────────────────────────────────────┘
                    │
                    ▼
           修复类型判断
        /       │        \
   Boolean   文件上下文   端口
       │        │          │
       ▼        ▼          ▼
    ┌────────┐ ┌──────────┐ ┌─────────────────┐
    │setsebool│ │semanage  │ │semanage port -a │
    │ -P xxx │ │fcontext  │ │-t type -p proto │
    └────────┘ └──────────┘ └─────────────────┘
                    │
                    ▼
    ┌───────────────────────────────────────┐
    │  Step 4: 应用修复                       │
    │  restorecon -Rv /path                 │
    └───────────────────────────────────────┘
                    │
                    ▼
    ┌───────────────────────────────────────┐
    │  Step 5: 验证修复                       │
    │  测试应用功能                           │
    └───────────────────────────────────────┘
                    │
                    ▼
    ┌───────────────────────────────────────┐
    │  Step 6: 记录变更                       │
    │  写入运维文档 / 变更記録               │
    └───────────────────────────────────────┘
```
<!-- /DIAGRAM -->

### 1.2 核心工具一览

| 工具 | 作用 | 常用命令 |
|------|------|----------|
| `ausearch` | 搜索审计日志 | `ausearch -m avc -ts recent` |
| `audit2why` | 解释拒绝原因 | `audit2why < audit.log` |
| `sealert` | 人类可读建议 | `sealert -a audit.log` |
| `semanage fcontext` | **永久**修改上下文 | `semanage fcontext -a -t type path` |
| `restorecon` | 应用策略规则 | `restorecon -Rv /path` |
| `chcon` | **临时**修改上下文 | `chcon -t type /path` |

---

## Step 2 — 诊断：找到 SELinux 拒绝（20 分钟）

### 2.1 ausearch — 搜索 AVC 拒绝

AVC（Access Vector Cache）是 SELinux 的访问决策缓存。拒绝会记录在审计日志中。

```bash
# 搜索最近的 AVC 拒绝
ausearch -m avc -ts recent
```

**输出示例：**

```
----
time->Sat Jan  4 10:23:45 2026
type=AVC msg=audit(1735986225.123:456): avc:  denied  { read } for  pid=12345 comm="nginx" name="index.html" dev="sda1" ino=67890 scontext=system_u:system_r:httpd_t:s0 tcontext=unconfined_u:object_r:default_t:s0 tclass=file permissive=0
```

**解读这条日志：**

| 字段 | 值 | 含义 |
|------|-----|------|
| `denied { read }` | 拒绝读取 | 操作类型被拒绝 |
| `comm="nginx"` | nginx | 进程名 |
| `name="index.html"` | 文件名 | 被访问的对象 |
| `scontext=...httpd_t:s0` | 进程上下文 | Nginx 进程的类型是 `httpd_t` |
| `tcontext=...default_t:s0` | 目标上下文 | 文件类型是 `default_t` |
| `tclass=file` | 文件 | 对象类别 |

**问题定位**：`httpd_t` 进程尝试读取 `default_t` 类型的文件，被 SELinux 策略拒绝。

### 2.2 查看文件上下文

```bash
# 查看 /data/www 的上下文
ls -Z /data/www/
```

**输出：**

```
unconfined_u:object_r:default_t:s0 index.html
```

**问题找到了！** 文件类型是 `default_t`（默认类型），而不是 `httpd_sys_content_t`（Web 内容类型）。

对比正常的 Web 目录：

```bash
ls -Z /usr/share/nginx/html/
```

```
system_u:object_r:httpd_sys_content_t:s0 index.html
```

### 2.3 audit2why — 理解拒绝原因

```bash
# 分析最近的拒绝原因
ausearch -m avc -ts recent | audit2why
```

**输出示例：**

```
type=AVC msg=audit(1735986225.123:456): avc:  denied  { read } for  pid=12345 comm="nginx" name="index.html" ...

    Was caused by:
        Missing type enforcement (TE) allow rule.

        You can use audit2allow to generate a loadable module to allow this access.
```

这告诉我们：策略没有允许这个访问。但 **不要急着用 audit2allow**！这不是最佳解决方案。

### 2.4 sealert — 获取人类可读建议

`sealert` 提供更详细的分析和建议（需要 `setroubleshoot-server` 包）：

```bash
# 安装 setroubleshoot（如果没有）
dnf install -y setroubleshoot-server

# 分析审计日志
sealert -a /var/log/audit/audit.log | head -50
```

**输出示例：**

```
SELinux is preventing nginx from read access on the file index.html.

*****  Plugin restorecon (99.5 confidence) suggests   ************************

If you want to fix the label.
/data/www/index.html default label should be httpd_sys_content_t.
Then you can run restorecon. The access attempt may have been stopped due to
insufficient permissions to access a parent directory in which case try to
change the following command accordingly.
Do
# /sbin/restorecon -v /data/www/index.html
```

**sealert 告诉我们**：应该把文件类型改成 `httpd_sys_content_t`！

---

## Step 3 — 修复：永久 vs 临时（25 分钟）

### 3.1 chcon — 临时修复（不推荐作为最终方案）

`chcon` 直接修改文件的安全上下文：

```bash
# 临时修改上下文
chcon -t httpd_sys_content_t /data/www/index.html
chcon -t httpd_sys_content_t /data/www

# 验证
ls -Z /data/www/
```

**测试：**

```bash
curl http://localhost/
```

```html
<h1>Welcome from /data/www!</h1>
```

**成功了！** 但是...

### 3.2 chcon 的致命缺陷

```bash
# 模拟系统维护：运行 restorecon
restorecon -Rv /data/www

# 再次查看上下文
ls -Z /data/www/
```

**输出：**

```
unconfined_u:object_r:default_t:s0 index.html
```

**上下文又变回 `default_t` 了！**

```bash
curl http://localhost/
# 又是 403 Forbidden！
```

**原因**：`chcon` 修改的是文件的实际标签，但 SELinux 策略数据库中 `/data/www` 的**默认上下文**仍是 `default_t`。

当系统运行 `restorecon`（文件系统 relabel、安全修复等场景），标签会被"恢复"为默认值。

### 3.3 semanage fcontext — 永久修复（正确做法）

`semanage fcontext` 修改 SELinux **策略数据库**中的规则：

```bash
# 添加永久上下文规则
semanage fcontext -a -t httpd_sys_content_t "/data/www(/.*)?"
```

**命令解释：**

| 部分 | 含义 |
|------|------|
| `semanage fcontext` | 管理文件上下文 |
| `-a` | 添加规则（add） |
| `-t httpd_sys_content_t` | 目标类型 |
| `"/data/www(/.*)?"` | 路径正则（包含子目录和文件） |

**应用规则：**

```bash
# 应用策略数据库中的规则到文件系统
restorecon -Rv /data/www
```

**输出：**

```
Relabeled /data/www from unconfined_u:object_r:default_t:s0 to unconfined_u:object_r:httpd_sys_content_t:s0
Relabeled /data/www/index.html from unconfined_u:object_r:default_t:s0 to unconfined_u:object_r:httpd_sys_content_t:s0
```

### 3.4 验证永久修复

```bash
# 测试访问
curl http://localhost/
```

```html
<h1>Welcome from /data/www!</h1>
```

**现在模拟系统维护：**

```bash
# 运行 restorecon 不会破坏设置
restorecon -Rv /data/www

# 查看上下文 — 仍然正确！
ls -Z /data/www/

# 仍然能访问
curl http://localhost/
```

**永久修复成功！** 即使系统重新标记文件，上下文也会保持正确。

### 3.5 查看现有规则

```bash
# 查看自定义的 fcontext 规则
semanage fcontext -l | grep /data/www
```

```
/data/www(/.*)?    all files    system_u:object_r:httpd_sys_content_t:s0
```

---

## Step 4 — 常见场景：自定义端口（15 分钟）

### 4.1 场景：httpd 监听 8888 端口

```bash
# 修改 Nginx 配置监听 8888
sed -i 's/listen       80;/listen       8888;/' /etc/nginx/nginx.conf
sed -i 's/listen       \[::\]:80;/listen       [::]:8888;/' /etc/nginx/nginx.conf

# 重启 Nginx
systemctl restart nginx
```

**报错：**

```
Job for nginx.service failed because the control process exited with error code.
```

### 4.2 诊断

```bash
# 查看服务状态
systemctl status nginx

# 查看 AVC 拒绝
ausearch -m avc -ts recent | tail -10
```

**AVC 日志：**

```
type=AVC msg=audit(...): avc:  denied  { name_bind } for  pid=... comm="nginx" src=8888 scontext=system_u:system_r:httpd_t:s0 tcontext=system_u:object_r:unreserved_port_t:s0 tclass=tcp_socket permissive=0
```

**问题**：`httpd_t` 不允许绑定 `unreserved_port_t` 类型的端口。

### 4.3 查看允许的 HTTP 端口

```bash
semanage port -l | grep http
```

```
http_port_t                    tcp      80, 81, 443, 488, 8008, 8009, 8443, 9000
```

端口 8888 不在列表中！

### 4.4 添加端口到 SELinux 策略

```bash
# 添加 8888 端口到 http_port_t
semanage port -a -t http_port_t -p tcp 8888

# 验证
semanage port -l | grep http
```

```
http_port_t                    tcp      8888, 80, 81, 443, 488, 8008, 8009, 8443, 9000
```

### 4.5 重启并测试

```bash
# 重启 Nginx
systemctl restart nginx

# 测试
curl http://localhost:8888/
```

```html
<h1>Welcome from /data/www!</h1>
```

**成功！**

---

## Step 5 — 动手实验（30 分钟）

### 5.1 实验 A：完整 Nginx 403 场景

使用我们准备的脚本来练习：

```bash
# 进入代码目录
cd ~/cloud-atlas/foundations/linux/security/04-selinux-troubleshooting/code/nginx-403-scenario

# 设置场景（制造问题）
sudo bash setup.sh

# 验证问题存在
curl http://localhost/
# 应该看到 403

# 现在自己动手排错！
# 提示：
# 1. ausearch -m avc -ts recent
# 2. ls -Z /data/www/
# 3. semanage fcontext -a -t ...
# 4. restorecon -Rv ...

# 完成后验证
curl http://localhost/

# 如果卡住了，查看解决方案
cat solution.sh
```

### 5.2 实验 B：自定义端口场景

```bash
# 尝试让 httpd 监听 9999 端口
# 1. 修改配置
# 2. 诊断 SELinux 问题
# 3. 添加端口规则
# 4. 验证
```

### 5.3 思考题

1. 如果运维同事说「SELinux 太麻烦，直接 `setenforce 0` 吧」，你如何反驳？
2. 什么情况下用 `chcon`？什么情况下必须用 `semanage fcontext`？
3. 如果 `sealert` 建议用 `audit2allow` 生成策略，你应该怎么做？

---

## 反模式：致命的 SELinux 排错错误

### 反模式 1：setenforce 0 "解决"问题

```bash
# 看到 403，直接禁用 SELinux
sudo setenforce 0
# "问题解决了！"

# 这相当于：
# - 汽车防盗器响了
# - 拔掉喇叭
# - "问题解决了！"
```

**正确做法**：按照排错流程诊断和修复。

### 反模式 2：只用 chcon，不用 semanage

```bash
# 快速修复
chcon -t httpd_sys_content_t /data/www/*

# 三个月后，系统升级自动运行 restorecon
# 网站又 403 了
# "为什么又坏了？"
```

**正确做法**：`semanage fcontext` 添加永久规则。

### 反模式 3：盲目使用 audit2allow

```bash
# 看到拒绝就生成策略
ausearch -m avc -ts recent | audit2allow -M myfix
semodule -i myfix.pp
# "问题解决了！"

# 但你可能授予了过多权限！
```

**正确做法**：

1. 先检查是否有适用的 Boolean
2. 再检查是否是文件上下文问题
3. 最后才考虑自定义策略（[Lesson 05](../05-selinux-advanced/) 会详细讲）

---

## 职场小贴士（Japan IT Context）

### SELinux 排错在日本 IT 现场

日本企业运维中，SELinux 问题是常见的「障害」：

| 日语术语 | 含义 | 实践要点 |
|----------|------|----------|
| 障害対応（しょうがいたいおう） | 故障处理 | 先看 AVC 日志再判断原因 |
| 原因調査（げんいんちょうさ） | 根因分析 | `ausearch` + `audit2why` 是标配 |
| 恒久対策（こうきゅうたいさく） | 永久修复 | 必须用 `semanage fcontext` |
| 暫定対策（ざんていたいさく） | 临时修复 | `chcon` 只能作为应急 |
| 変更履歴（へんこうりれき） | 变更记录 | 记录每条 semanage 命令 |

### 报告书模板

日本企业通常需要提交障害報告書（Incident Report）：

```markdown
## 障害報告書

### 発生日時
2026-01-04 10:23 JST

### 事象
Web サーバー (nginx) が /data/www のコンテンツに対して 403 Forbidden を返す

### 原因
SELinux のファイルコンテキストが default_t のままで、httpd_t プロセスからの読み取りが拒否された

### 調査ログ
```
ausearch -m avc -ts recent
type=AVC msg=audit(...): avc: denied { read } for pid=12345 ...
```

### 対策
#### 暫定対策
N/A（恒久対策を即時実施）

#### 恒久対策
semanage fcontext -a -t httpd_sys_content_t "/data/www(/.*)?"
restorecon -Rv /data/www

### 再発防止
- Web コンテンツ移行時は SELinux コンテキスト設定を手順書に含める
- 移行後チェックリストに `ls -Z` による確認を追加
```

### 变更管理

在日本 IT 现场，SELinux 配置变更需要记录：

```bash
# 记录变更（写入运维日志）
echo "$(date '+%Y-%m-%d %H:%M:%S') - semanage fcontext -a -t httpd_sys_content_t '/data/www(/.*)?'" >> /var/log/selinux-changes.log
```

---

## chcon vs semanage fcontext 对比

| 特性 | chcon | semanage fcontext |
|------|-------|-------------------|
| **持久性** | 临时（restorecon 会覆盖） | 永久（写入策略数据库） |
| **使用场景** | 快速测试、应急 | 生产环境正式修复 |
| **语法** | `chcon -t type /path` | `semanage fcontext -a -t type "regex"` + `restorecon` |
| **系统升级** | 可能丢失 | 保持 |
| **文件 relabel** | 丢失 | 保持 |
| **RHCSA 考试** | 需要了解 | **必须掌握** |

### 记忆口诀

```
chcon 改标签，restorecon 会清掉
semanage 改规则，永远都有效
生产用 semanage，测试用 chcon
```

---

## 清理实验环境

```bash
# 恢复 Nginx 默认配置
sudo cp /etc/nginx/nginx.conf.bak /etc/nginx/nginx.conf
sudo systemctl restart nginx

# 删除自定义 fcontext 规则（如果需要）
sudo semanage fcontext -d "/data/www(/.*)?"

# 删除自定义端口规则（如果添加了）
sudo semanage port -d -t http_port_t -p tcp 8888 2>/dev/null
sudo semanage port -d -t http_port_t -p tcp 9999 2>/dev/null

# 删除测试目录
sudo rm -rf /data/www

# 验证 Nginx 默认工作
curl http://localhost/
```

---

## 检查清单

完成本课后，你应该能够：

- [ ] 使用 `ausearch -m avc -ts recent` 搜索 AVC 拒绝
- [ ] 解读 AVC 日志中的 `scontext`（进程上下文）和 `tcontext`（目标上下文）
- [ ] 使用 `audit2why` 理解拒绝原因
- [ ] 使用 `sealert -a` 获取修复建议
- [ ] 使用 `ls -Z` 对比文件的实际上下文和期望上下文
- [ ] 使用 `semanage fcontext -a -t type "path"` 添加永久上下文规则
- [ ] 使用 `restorecon -Rv` 应用策略规则
- [ ] 解释为什么 `chcon` 不能作为永久修复
- [ ] 使用 `semanage port -a` 添加自定义端口
- [ ] 描述 SELinux 排错六步法

---

## 本课小结

| 概念 | 命令 | 记忆点 |
|------|------|--------|
| 搜索拒绝 | `ausearch -m avc -ts recent` | 第一步永远是看日志 |
| 理解原因 | `audit2why < audit.log` | 为什么被拒绝 |
| 获取建议 | `sealert -a audit.log` | 人类可读的修复建议 |
| **永久修复** | `semanage fcontext -a -t type "path"` | 生产环境唯一选择 |
| 应用规则 | `restorecon -Rv /path` | 把规则应用到文件 |
| 临时修复 | `chcon -t type /path` | 只用于测试 |
| 端口规则 | `semanage port -a -t type -p proto port` | 自定义端口 |

**核心理念**：

```
问题 → ausearch → audit2why/sealert → semanage fcontext → restorecon → 验证
         │                 │                   │              │
         │                 │                   │              └── 应用规则
         │                 │                   └── 永久修复
         │                 └── 理解原因
         └── 找到拒绝
```

---

## 延伸阅读

- [Red Hat SELinux Troubleshooting Guide](https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/9/html/using_selinux/troubleshooting-problems-related-to-selinux_using-selinux)
- [semanage-fcontext man page](https://man7.org/linux/man-pages/man8/semanage-fcontext.8.html)
- 上一课：[03 · SELinux 核心概念](../03-selinux-concepts/) — 理解上下文和模式
- 下一课：[05 · SELinux 进阶](../05-selinux-advanced/) — Booleans 与自定义策略

---

## 系列导航

[03 · SELinux 核心概念 ←](../03-selinux-concepts/) | [系列首页](../) | [05 · SELinux 进阶 →](../05-selinux-advanced/)
