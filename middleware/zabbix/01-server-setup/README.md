# 01 · Zabbix Server 初始化（Server Setup）

> **目标**：完成 Zabbix Server 数据库初始化和 Web UI 配置  
> **前置**：[00 · 环境与架构导入](../00-architecture-lab/)  
> **费用**：实验环境持续产生费用（约 $0.03/小时）；完成系列后请删除堆栈  
> **时间**：20-30 分钟  
> **实战项目**：配置 Housekeeping，创建运维账户

## 将学到的内容

1. 初始化 MariaDB 数据库
2. 配置 Zabbix Server
3. 完成 Web UI 安装向导
4. 配置 Housekeeping（History vs Trends）
5. 创建运维账户，禁用默认 Admin

---

## Step 1 — 初始化数据库

通过 SSM 连接到 Zabbix Server：

```bash
# 切换到 root
sudo -i

# 验证 Zabbix 包已安装（CloudFormation 应已完成）
rpm -qa | grep zabbix-server
# 预期输出：zabbix-server-mysql-7.0.x

# 确认时间同步正常（重要：时间不同步会导致触发器和图表异常）
timedatectl
# 确认 NTP service: active
# 如果未同步，启用 chronyd：
# systemctl enable --now chronyd
```

> ⚠️ **验证失败？** 如果没有看到 `zabbix-server-mysql` 包，请确认 CloudFormation 堆栈已成功完成（状态为 `CREATE_COMPLETE`）。

### 1.1 安全配置 MariaDB

```bash
# 确认 MariaDB 正在运行（CloudFormation 已启动，这里确认一下）
systemctl status mariadb
# 如果未运行：systemctl start mariadb && systemctl enable mariadb

# 运行安全配置向导
mysql_secure_installation
```

按以下提示逐步操作：

```
Enter current password for root (enter for none):
→ 直接按 Enter（新安装无密码）

Switch to unix_socket authentication [Y/n]
→ 输入 n，然后 Enter

Change the root password? [Y/n]
→ 输入 Y，然后 Enter
New password:
→ 输入你的 root 密码（如：MySecurePass123!）
Re-enter new password:
→ 再次输入相同密码

Remove anonymous users? [Y/n]
→ 输入 Y，然后 Enter

Disallow root login remotely? [Y/n]
→ 输入 Y，然后 Enter

Remove test database and access to it? [Y/n]
→ 输入 Y，然后 Enter

Reload privilege tables now? [Y/n]
→ 输入 Y，然后 Enter
```

完成后显示 `All done!` 表示配置成功。

> **密码要求**：建议 12+ 字符，包含大小写字母、数字和符号。请记录此密码，后续配置需要。

### 1.2 创建 Zabbix 数据库

> 💡 **SQL 简要说明**：不需要记住语法，理解目的即可  
> - `CREATE DATABASE` = 创建一个空的"文件夹"存放 Zabbix 数据  
> - `CREATE USER` = 创建一个专用账户（不用 root 更安全）  
> - `GRANT` = 给这个账户"钥匙"，只能访问 zabbix 数据库

```bash
# 登录 MariaDB
mysql -uroot -p
```

输入 MariaDB root 密码（刚才 `mysql_secure_installation` 设置的）。

在 MariaDB 提示符下执行：

```sql
CREATE DATABASE zabbix CHARACTER SET utf8mb4 COLLATE utf8mb4_bin;
CREATE USER 'zabbix'@'localhost' IDENTIFIED BY 'YourZabbixDBPassword';
-- 替换为你的密码                              ^^^^^^^^^^^^^^^^^^^^
GRANT ALL PRIVILEGES ON zabbix.* TO 'zabbix'@'localhost';
SET GLOBAL log_bin_trust_function_creators = 1;
FLUSH PRIVILEGES;
EXIT;
```

> ⚠️ **记住这个密码**：后续配置 Zabbix Server 和导入 Schema 时需要。

### 1.3 导入初始 Schema

> 💡 **这一步在做什么？**  
>
> 刚才创建的 `zabbix` 数据库是空的，就像一个空文件夹。  
> Zabbix 需要预定义的「表格结构」来存放数据，比如：  
> - `hosts` 表 → 存放被监控的主机信息  
> - `items` 表 → 存放监控项配置  
> - `triggers` 表 → 存放告警规则  
> - `events` 表 → 存放告警事件历史  
>
> 这条命令把 Zabbix 官方提供的表格结构导入数据库。

```bash
# 解压并导入 Zabbix 表结构（约 1-2 分钟）
zcat /usr/share/zabbix-sql-scripts/mysql/server.sql.gz | mysql --default-character-set=utf8mb4 -uzabbix -p zabbix
```

系统会提示输入密码，输入刚才创建 zabbix 用户时设置的密码。

<details>
<summary>🔍 好奇 SQL 内容？点击展开查看方法</summary>

```bash
# 查看前 100 行（表结构定义）
zcat /usr/share/zabbix-sql-scripts/mysql/server.sql.gz | head -100

# 查看有哪些 CREATE TABLE 语句
zcat /usr/share/zabbix-sql-scripts/mysql/server.sql.gz | grep "CREATE TABLE"

# 查看 hosts 表的结构
zcat /usr/share/zabbix-sql-scripts/mysql/server.sql.gz | grep -A 30 "CREATE TABLE \`hosts\`"
```

完整 SQL 约 5MB、17 万行，包含 170+ 张表的定义和初始数据。

</details>

```bash
# 恢复安全设置
mysql -uroot -p -e "SET GLOBAL log_bin_trust_function_creators = 0;"
```

验证导入：

```bash
mysql -uzabbix -p -e "USE zabbix; SHOW TABLES;" | head -20
```

输入 zabbix 用户密码，应看到大量表（hosts, items, triggers 等）。

---

## Step 2 — 配置 Zabbix Server

### 2.1 编辑配置文件

```bash
# 编辑 Zabbix Server 配置
vim /etc/zabbix/zabbix_server.conf
```

找到并修改以下配置：

```ini
# 数据库配置
DBHost=localhost
DBName=zabbix
DBUser=zabbix
DBPassword=YourZabbixDBPassword    # ← 改成 Step 1.2 设置的密码
```

> 💡 **提示**：在 vim 中按 `/DBPassword` 然后 Enter 可快速定位

<details>
<summary>🔍 想了解这些配置？点击展开</summary>

**数据库配置**：告诉 Zabbix Server 如何连接数据库
| 参数 | 说明 |
|------|------|
| `DBHost` | 数据库服务器地址（localhost = 本机） |
| `DBName` | 数据库名称（Step 1.2 创建的 `zabbix`） |
| `DBUser` | 数据库用户名 |
| `DBPassword` | 数据库密码 |

> 📚 **性能调优**是进阶话题，详见 → [06 · 扩展与运维实践](../06-ops-advanced/#性能调优)

</details>

### 2.2 配置 PHP 时区

```bash
# 编辑 PHP-FPM 配置
vim /etc/php-fpm.d/zabbix.conf
```

在文件末尾添加以下行：

```ini
php_value[date.timezone] = Asia/Tokyo
```

> 💡 **提示**：在 vim 中按 `G` 跳到文件末尾，按 `o` 新建一行，输入上述配置后 `:wq` 保存退出

### 2.3 启动服务

> 💡 **SELinux 说明**：CloudFormation 模板已安装 `zabbix-selinux-policy` 包，自动配置 SELinux 规则。  
> 如果遇到 403 错误且日志显示 SELinux 相关信息，可临时禁用测试：`sudo setenforce 0`（仅限实验环境）。

```bash
# 启动 Zabbix Server
systemctl start zabbix-server

# 启动 Web 服务（Apache + PHP-FPM）
systemctl start httpd php-fpm

# 设置开机自启
systemctl enable zabbix-server httpd php-fpm

# 检查状态
systemctl status zabbix-server
```

预期输出：`Active: active (running)`

> 💡 **重新尝试时**：如果之前已启动过服务但修改了配置，使用 `systemctl restart` 而非 `start`

如果启动失败，检查日志：

```bash
tail -50 /var/log/zabbix/zabbix_server.log
```

---

## Step 3 — 完成 Web UI 安装向导

### 3.1 访问 Web UI

打开浏览器，访问：

```
http://<ZabbixServerPublicIP>/zabbix
```

> 💡 从 CloudFormation 输出获取 `ZabbixServerPublicIP`

### 3.2 安装向导

**Step 1: Welcome**
- 点击「Next step」

**Step 2: Check of pre-requisites**
- 所有项目应显示 `OK`
- 如果有 `Fail`，返回终端修复

**Step 3: Configure DB connection**

| 字段 | 值 |
|------|-----|
| Database type | MySQL |
| Database host | localhost |
| Database port | 0 (default) |
| Database name | zabbix |
| User | zabbix |
| Password | （Step 1.2 设置的 zabbix 用户密码） |

**Step 4: Settings**

| 字段 | 值 |
|------|-----|
| Zabbix server name | Zabbix Lab |
| Default time zone | (UTC+09:00) Asia/Tokyo |
| Default theme | Blue (或 Dark) |

**Step 5: Pre-installation summary**
- 确认配置，点击「Next step」

**Step 6: Install**
- 显示「Congratulations!」
- 点击「Finish」

### 3.3 首次登录

默认凭据：

| 字段 | 值 |
|------|-----|
| Username | Admin |
| Password | zabbix |

> ⚠️ **重要**：登录后立即修改 Admin 密码！

---

## Step 4 — 基础安全配置

### 4.1 修改 Admin 密码

1. 点击左侧菜单「Users」→「Users」
2. 点击「Admin」用户
3. 点击「Change password」
4. 输入新密码（建议 12+ 字符，含大小写、数字、符号）
5. 点击「Update」

### 4.2 创建个人运维账户

> 最佳实践：创建个人账户，避免共用 Admin

1. 「Users」→「Users」→「Create user」

2. **User 标签页**：

   | 字段 | 值 |
   |------|-----|
   | Username | your-name |
   | Name | Your Name |
   | Groups | 点击「Select」→ 选择「Zabbix administrators」 |
   | Password | 设置强密码 |

3. **Permissions 标签页**：
   - Role: `Super admin role`

4. 点击「Add」

### 4.3 测试新账户

1. 登出 Admin
2. 使用新账户登录
3. 确认可以正常访问所有功能

---

## Step 5 — 配置 Housekeeping

> 🎯 **面试高频问题**：History と Trends の違いは？

### History vs Trends

| 特性 | History | Trends |
|------|---------|--------|
| **数据类型** | 原始采集值 | 每小时聚合（min/max/avg） |
| **精度** | 高（秒级） | 低（小时级） |
| **存储空间** | 大 | 小（约 1/100） |
| **默认保留** | 7-14 天 | 365 天 |
| **用途** | 实时监控、告警 | 长期趋势分析 |

### 配置 Housekeeping

1. 「Administration」→「Housekeeping」

2. 配置建议：

   | 数据类型 | 保留期间 | 说明 |
   |----------|----------|------|
   | Events and alerts | 365 days | 事件历史 |
   | Services | 365 days | SLA 数据 |
   | Audit | 365 days | 审计日志 |
   | User sessions | 365 days | 会话历史 |
   | History | 14 days | 原始数据（根据存储调整） |
   | Trends | 365 days | 趋势数据 |

3. 点击「Update」

> 💡 **存储估算**：t3.small 20GB EBS，History 14d + Trends 365d 约占用 5-10GB（视监控项数量）

---

## Step 6 — 验证 Server 状态

### 6.1 检查 Dashboard

登录后，默认 Dashboard 应显示：
- System information widget
- Problems widget（暂无数据）

### 6.2 检查 Server 信息

「Reports」→「System information」

确认：
- Zabbix server is running: `Yes`
- Number of hosts: 1 (Zabbix server 自身)

### 6.3 检查队列

「Monitoring」→「Queue」

- 所有项目应为 0 或很小的数字
- 如果大量排队，表示有性能问题

---

## Mini-Project：Housekeeping 设计

> 场景：你负责一个有 100 台服务器的监控系统，每台 50 个监控项，采集间隔 1 分钟。

计算并设计 Housekeeping 策略：

1. **计算每日数据量**
   - 100 服务器 × 50 项 × 60 分钟 × 24 小时 = 720 万条/天

2. **设计保留策略**

   | 数据类型 | 保留期间 | 理由 |
   |----------|----------|------|
   | History | ? | |
   | Trends | ? | |

3. **考虑因素**
   - 故障分析需要多长时间的详细数据？
   - 容量规划需要多长时间的趋势？
   - 存储预算是多少？

---

## 面试问答

### Q: History と Trends の違い、保存期間の設計は？

**A**:
- **History**: 生データを秒単位で保存。リアルタイム監視やアラート判定に使用。通常 7-14 日間保存。
- **Trends**: 1 時間ごとの集計値（min/max/avg）。キャパシティ計画や長期分析に使用。通常 365 日以上保存。
- **設計ポイント**: History は DB 容量を消費するため、必要最小限に。Trends は圧縮されているため長期保存可能。

### Q: Housekeeping の役割は？

**A**:
- 古いデータを自動削除し、データベースサイズを管理
- デフォルトでは毎時実行
- パフォーマンスに影響する場合、HousekeepingFrequency や MaxHousekeeperDelete を調整

---

## 常见错误

| 错误 | 原因 | 解决方案 |
|------|------|----------|
| Web UI 403 | Apache 配置问题 | 检查 `/etc/httpd/conf.d/zabbix.conf` |
| DB connection failed | 密码错误 | 确认 `zabbix_server.conf` 中密码 |
| Server not running | 配置语法错误 | 检查日志 `/var/log/zabbix/zabbix_server.log` |
| 时区显示错误 | PHP 时区未设置 | 编辑 `/etc/php-fpm.d/zabbix.conf` |

---

## 本课小结

| 配置项 | 位置 |
|--------|------|
| Server 配置 | `/etc/zabbix/zabbix_server.conf` |
| PHP 时区 | `/etc/php-fpm.d/zabbix.conf` |
| Server 日志 | `/var/log/zabbix/zabbix_server.log` |
| Housekeeping | Web UI → Administration → Housekeeping |

---

## 清理提醒

> ⚠️ **费用提醒**：实验环境持续产生费用。完成整个系列后，请删除 CloudFormation 堆栈。  
> 详见 → [00 · 清理资源](../00-architecture-lab/#清理资源)

---

## 下一步

Server 已就绪！下一课我们将在被监控主机上安装 Agent，并在 Web UI 中注册。

→ [02 · Agent 与主机管理](../02-agent-host/)

## 系列导航

← [00 · 环境与架构](../00-architecture-lab/) | [系列首页](../) | [02 · Agent 与主机管理](../02-agent-host/) →
