# 00 · 环境与架构导入（Architecture & Lab Setup）

> **目标**：理解 Zabbix 架构，部署实验环境  
> **推荐**：[AWS SSM 01 · CloudFormation 部署](../../../aws/ssm/01-cfn-deploy/)（了解 AWS 控制台部署堆栈即可，本课也有详细步骤）  
> **时间**：20-30 分钟  
> **费用**：约 $0.03/小时（t3.small + t3.micro）；完成后请删除堆栈

## 将学到的内容

1. Zabbix 三层架构（Server / Agent / Proxy）
2. Active vs Passive Agent 模式（面试重点）
3. 端口与协议（10050, 10051, 80/443）
4. 使用 CloudFormation 部署实验环境

---

## Step 1 — 理解 Zabbix 架构

> 在安装任何软件之前，先理解其架构。这是日本 IT 面试中常被问到的基础问题。

### 三层架构

```
┌─────────────────────────────────────────────────────────────────┐
│                         Zabbix 架构                              │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌──────────────┐                                                │
│  │   Browser    │◄────── HTTP/HTTPS (80/443)                     │
│  └──────────────┘                                                │
│         │                                                        │
│         ▼                                                        │
│  ┌──────────────────────────────────────┐                        │
│  │         Zabbix Server                │                        │
│  │  ┌─────────┐  ┌─────────┐           │                        │
│  │  │ Web UI  │  │ Backend │           │                        │
│  │  │ (Apache)│  │ Process │           │                        │
│  │  └─────────┘  └─────────┘           │                        │
│  │         │                            │                        │
│  │  ┌──────────────────────┐           │                        │
│  │  │    Database          │           │                        │
│  │  │   (MariaDB)          │           │                        │
│  │  └──────────────────────┘           │                        │
│  └──────────────────────────────────────┘                        │
│         │                    ▲                                   │
│         │ Passive (10050)    │ Active (10051)                    │
│         ▼                    │                                   │
│  ┌──────────────┐     ┌──────────────┐                          │
│  │ Zabbix Agent │     │ Zabbix Agent │                          │
│  │  (Passive)   │     │  (Active)    │                          │
│  │              │     │              │                          │
│  │ Server polls │     │ Agent pushes │                          │
│  └──────────────┘     └──────────────┘                          │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 组件说明

| 组件 | 作用 | 端口 |
|------|------|------|
| **Zabbix Server** | 接收数据、处理触发器、发送告警 | 10051 (trapper) |
| **Zabbix Web UI** | 配置界面、图表展示、问题管理 | 80/443 |
| **Zabbix Agent** | 安装在被监控主机，采集数据 | 10050 (passive) |
| **Zabbix Proxy** | 分布式架构中的数据中转站 | 10051 |
| **Database** | 存储配置、历史数据、趋势 | 3306 (MariaDB) |

---

## Step 2 — Active vs Passive Agent（面试重点）

> 🎯 **面试高频问题**：Active Agent と Passive Agent の違いは？

### 对比表

| 特性 | Passive Agent | Active Agent |
|------|---------------|--------------|
| **通信方向** | Server → Agent（轮询） | Agent → Server（推送） |
| **端口** | 10050（Agent 监听） | 10051（Server 监听） |
| **防火墙** | 需开放 Agent 入站 10050 | 只需 Agent 出站 10051 |
| **NAT 友好** | ❌ 需要端口映射 | ✅ 可穿透 NAT |
| **负载** | Server 承担轮询压力 | Agent 分担数据收集 |
| **配置** | Server 填写 Agent IP | Agent 填写 Server IP |

> 💡 **概念补充**：不熟悉「轮询/推送」或「NAT」？
> - [轮询与推送](../../../glossary/networking/polling-pushing.md)
> - [NAT 与穿透](../../../glossary/networking/nat-traversal.md)

### 通信流程图

```
Passive Mode（被动模式）:
┌────────┐    1. 请求数据    ┌────────┐
│ Server │ ──────────────► │ Agent  │
│        │                  │ :10050 │
│        │ ◄────────────── │        │
└────────┘    2. 返回数据    └────────┘

Active Mode（主动模式）:
┌────────┐    1. 获取配置    ┌────────┐
│ Server │ ◄────────────── │ Agent  │
│ :10051 │                  │        │
│        │ ◄────────────── │        │
└────────┘    2. 推送数据    └────────┘
```

### 推荐使用 Active Mode

日本企业环境中，推荐使用 **Active Agent**：

1. **NAT 穿透**：Agent 在私有网络内，无需开放入站端口
2. **负载分散**：Agent 主动收集并推送，减轻 Server 轮询压力
3. **更好的可靠性**：Agent 缓存数据，网络中断后自动重传

---

## Step 3 — 部署实验环境

### 架构图

```
┌─────────────────────────────────────────────────────────────┐
│                 VPC (10.0.0.0/16)                            │
│                                                              │
│  ┌─────────────────────┐    ┌─────────────────────┐         │
│  │   Zabbix Server     │    │   Monitored Host    │         │
│  │   (t3.small)        │    │   (t3.micro)        │         │
│  │                     │    │                     │         │
│  │ - Zabbix 7.0 LTS    │    │ - Zabbix Agent 2    │         │
│  │ - MariaDB           │    │ - httpd             │         │
│  │ - Apache + php      │    │ - net-snmp          │         │
│  │                     │    │                     │         │
│  │ Ports:              │    │ Ports:              │         │
│  │ - 80/443 (Web UI)   │    │ - 10050 (Passive)   │         │
│  │ - 10051 (Active)    │    │ - 161/UDP (SNMP)    │         │
│  └─────────────────────┘    └─────────────────────┘         │
│           │                           │                      │
│           └───────── SSM ─────────────┘                      │
│                  (Session Manager)                           │
└─────────────────────────────────────────────────────────────┘
```

### 3.1 下载模板

模板文件位于：[cfn/zabbix-lab.yaml](../cfn/zabbix-lab.yaml)

或直接从终端下载：

```bash
# 创建工作目录
mkdir -p ~/zabbix-course && cd ~/zabbix-course

# 下载模板（如果未 clone 仓库）
curl -O https://raw.githubusercontent.com/shiicho/cloud-atlas/main/middleware/zabbix/cfn/zabbix-lab.yaml
```

### 3.2 通过 AWS 控制台部署

1. **打开 CloudFormation 控制台**
   - 登录 AWS Console
   - 搜索 "CloudFormation" 并打开

2. **创建堆栈**
   - 点击「创建堆栈」→「使用新资源（标准）」
   - 选择「上传模板文件」
   - 上传 `zabbix-lab.yaml`

3. **配置参数**

   | 参数 | 建议值 | 说明 |
   |------|--------|------|
   | StackName | `zabbix-lab` | 堆栈名称 |
   | EnvironmentName | `zabbix-lab` | 资源前缀 |
   | AllowedCIDR | `你的IP/32` | 限制 Web UI 访问（推荐） |
   | ZabbixServerInstanceType | `t3.small` | 2GB 内存，足够实验用 |

   > 💡 **安全提示**：将 AllowedCIDR 设置为你的 IP 地址（如 `203.0.113.50/32`），而非默认的 `0.0.0.0/0`
>
> 查询你的公网 IP：浏览器访问 [checkip.amazonaws.com](https://checkip.amazonaws.com) 或终端执行 `curl checkip.amazonaws.com`

4. **权限配置**
   - 勾选「我确认，AWS CloudFormation 可能创建 IAM 资源」
   - 点击「创建堆栈」

5. **等待完成**
   - 约 5-8 分钟
   - 状态变为 `CREATE_COMPLETE`

### 3.3 获取输出信息

堆栈创建完成后，在「输出」标签页找到：

| 输出键 | 用途 |
|--------|------|
| `ZabbixServerPublicIP` | Web UI 访问地址 |
| `ZabbixServerPrivateIP` | Agent 配置用 |
| `MonitoredHostPrivateIP` | 主机注册用 |
| `CleanupCommand` | 删除堆栈命令 |

### 3.4 验证实例连接

通过 SSM Session Manager 连接（无需 SSH 密钥）：

**方法 1：控制台**
- 打开 EC2 控制台
- 选择 `zabbix-lab-zabbix-server`
- 点击「连接」→「Session Manager」→「连接」

**方法 2：CLI**
```bash
# 连接 Zabbix Server
aws ssm start-session --target <ZabbixServerInstanceId>

# 连接 Monitored Host
aws ssm start-session --target <MonitoredHostInstanceId>
```

### 3.5 验证预安装

连接到 Zabbix Server 后，验证软件已安装：

```bash
# 切换到 root
sudo -i

# 检查安装状态
cat /root/zabbix-install-status.txt

# 验证 Zabbix 包
rpm -qa | grep zabbix

# 验证 MariaDB
systemctl status mariadb

# 验证 Apache
systemctl status httpd
```

预期输出：
```
zabbix-server-mysql-7.0.x
zabbix-web-mysql-7.0.x
zabbix-apache-conf-7.0.x
zabbix-sql-scripts-7.0.x
zabbix-agent2-7.0.x
```

---

## Step 4 — 理解安全组规则

查看 CloudFormation 创建的安全组规则，理解与架构的对应关系：

### Zabbix Server 安全组

| 端口 | 协议 | 来源 | 用途 |
|------|------|------|------|
| 80 | TCP | AllowedCIDR | Web UI (HTTP) |
| 10051 | TCP | VPC (10.0.0.0/16) | Active Agent 连接 |

### Monitored Host 安全组

| 端口 | 协议 | 来源 | 用途 |
|------|------|------|------|
| 10050 | TCP | ZabbixServerSG | Passive Agent 轮询 |
| 161 | UDP | ZabbixServerSG | SNMP 轮询 |

---

## Mini-Project：绘制架构图

> 动手练习：用你喜欢的工具（draw.io、Miro、纸笔）绘制实验环境架构图

要求：
1. 标注两台 EC2 实例及其角色
2. 标注端口号和通信方向
3. 区分 Active 和 Passive 数据流
4. 标注安全组规则

---

## 面试问答

### Q: Active Agent と Passive Agent の違いは？

**A**:
- **Passive Agent**: サーバーがエージェントに接続してデータを取得（ポーリング）。エージェント側で 10050 ポートを開放する必要がある。
- **Active Agent**: エージェントがサーバーに接続してデータを送信（プッシュ）。サーバー側で 10051 ポートを開放。NAT 越しでも動作するため、推奨される構成。

### Q: Zabbix Proxy はどんな場面で使う？

**A**:
- 多拠点監視（本社と支社など）
- DMZ 内サーバーの監視
- WAN 越しの負荷軽減（Proxy がローカルで収集、バッチ送信）
- ネットワーク分離環境（Proxy だけが Server と通信）

---

## 常见错误

| 错误 | 原因 | 解决方案 |
|------|------|----------|
| Stack creation timeout | IAM 权限不足 | 确认有创建 IAM Role 权限 |
| SSM 连接失败 | Instance Profile 未附加 | 检查 IAM Role 是否正确关联 |
| 实例无法启动 | AMI ID 过期 | 更新 CloudFormation 中的 AMI ID |

---

## 清理资源

完成学习后，删除堆栈避免持续扣费：

```bash
aws cloudformation delete-stack --stack-name zabbix-lab
```

或通过控制台：CloudFormation → 选择堆栈 → 删除

---

## 本课小结

| 概念 | 要点 |
|------|------|
| Zabbix 架构 | Server + Agent + (Proxy) + Database |
| Active Agent | Agent → Server，NAT 友好，推荐使用 |
| Passive Agent | Server → Agent，需开放 Agent 端口 |
| 端口 | 10050 (Passive), 10051 (Active), 80/443 (Web UI) |

---

## 下一步

环境已就绪！下一课我们将初始化 Zabbix Server，完成 Web UI 配置。

→ [01 · Zabbix Server 初始化](../01-server-setup/)

## 系列导航

[系列首页](../) | [01 · Server 初始化](../01-server-setup/) →
