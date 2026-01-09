# LX06 - Linux 网络（Linux Networking）

> **从接口配置到防火墙，从 DNS 到网络排障**

本课程是 Linux World 模块化课程体系的一部分，专注于网络配置与排障。

## 课程概览

| 属性 | 值 |
|------|-----|
| **课时** | 12 课 |
| **时长** | 25-30 小时 |
| **难度** | 中级 |
| **前置** | LX02 系统管理 |
| **认证** | LPIC-2, RHCSA |

## 课程特色

- **现代工具优先**：nftables > iptables，ss > netstat
- **故障排查思维**：L3→L4→L7 分层诊断
- **证据先行**：采集证据再变更
- **日本 IT 场景**：運用監視、障害対応、ネットワーク障害

## 课程大纲

### Part 1: 基础 (01-04)

| 课程 | 标题 | 描述 |
|------|------|------|
| 01 | [网络基础](./01-fundamentals/) | TCP/IP 快速回顾 |
| 02 | [接口配置](./02-interfaces/) | ip、nmcli |
| 03 | [路由](./03-routing/) | ip route、静态路由 |
| 04 | [DNS](./04-dns/) | systemd-resolved、/etc/resolv.conf |

### Part 2: 套接字与防火墙 (05-07)

| 课程 | 标题 | 描述 |
|------|------|------|
| 05 | [套接字检查](./05-sockets/) | ss、netstat |
| 06 | [nftables](./06-nftables/) | 现代防火墙 |
| 07 | [firewalld](./07-firewalld/) | 区域、服务、富规则 |

### Part 3: 诊断与高级 (08-10)

| 课程 | 标题 | 描述 |
|------|------|------|
| 08 | [tcpdump 抓包](./08-tcpdump/) | 抓包分析 |
| 09 | [SSH 深入](./09-ssh/) | 密钥、配置、隧道 |
| 10 | [网络命名空间](./10-namespaces/) | 容器网络基础 |

### Part 4: 故障排查 (11-12)

| 课程 | 标题 | 描述 |
|------|------|------|
| 11 | [网络故障排查](./11-troubleshooting/) | L3→L4→L7 工作流 |
| 12 | [综合实战](./12-capstone/) | 完整网络诊断场景 |

## 快速开始

```bash
# GitHub（海外用户）
git clone --filter=blob:none --sparse https://github.com/shiicho/cloud-atlas ~/cloud-atlas
cd ~/cloud-atlas && git sparse-checkout set foundations/linux/lx06-networking

# Gitee（中国大陆用户）
git clone --filter=blob:none --sparse https://gitee.com/shiicho/cloud-atlas ~/cloud-atlas
cd ~/cloud-atlas && git sparse-checkout set foundations/linux/lx06-networking
```

## 前置课程

- [LX02 - 系统管理](../lx02-sysadmin/)

## 后续路径

完成本课程后，你可以：

- **LX08 - 安全加固**：防火墙深入、SSH 加固
- **LX11 - 容器**：网络命名空间是容器网络基础
- **LX12 - 云端 Linux**：云网络配置
