# LX10 - Linux 故障排查大师（Linux Troubleshooting Mastery）

> **系统性故障排查方法论，从启动问题到根因分析**

本课程是 Linux World 模块化课程体系的一部分，专注于生产级故障排查。

## 课程概览

| 属性 | 值 |
|------|-----|
| **课时** | 10 课 |
| **时长** | 20-25 小时 |
| **难度** | 高级 |
| **前置** | LX05 systemd + LX07 存储 + LX09 性能 |
| **认证** | RHCE |

## 课程特色

- **框架先行**：USE/RED 方法论驱动，工具只是验证手段
- **证据优先**：采集证据再行动，不盲目重启
- **真实混沌**：多系统级联故障，模拟真实生产环境
- **障害報告書**：每次故障排查产出正式报告

## 课程大纲

### Part 1: 方法论 (01)

| 课程 | 标题 | 描述 |
|------|------|------|
| 01 | [排查方法论](./01-methodology/) | USE/RED 框架、决策树 |

### Part 2: 系统故障 (02-05)

| 课程 | 标题 | 描述 |
|------|------|------|
| 02 | [启动问题](./02-boot-issues/) | GRUB、initramfs、紧急模式 |
| 03 | [服务故障](./03-service-failures/) | systemd 依赖分析 |
| 04 | [网络问题](./04-network-problems/) | L3→L4→L7 分层诊断 |
| 05 | [存储问题](./05-storage-issues/) | 容量、inode、I/O 错误 |

### Part 3: 性能与日志 (06-07)

| 课程 | 标题 | 描述 |
|------|------|------|
| 06 | [性能分析](./06-performance/) | CPU、内存、I/O wait |
| 07 | [日志分析](./07-log-analysis/) | journalctl、时间线重建 |

### Part 4: 调试 (08-09)

| 课程 | 标题 | 描述 |
|------|------|------|
| 08 | [strace 应用调试](./08-strace/) | 系统调用追踪 |
| 09 | [Core Dump 分析](./09-core-dumps/) | coredumpctl、GDB |

### Part 5: 根因分析 (10)

| 课程 | 标题 | 描述 |
|------|------|------|
| 10 | [RCA 实战](./10-rca-capstone/) | 5 Whys、障害報告書 |

## 快速开始

```bash
# GitHub（海外用户）
git clone --filter=blob:none --sparse https://github.com/shiicho/cloud-atlas ~/cloud-atlas
cd ~/cloud-atlas && git sparse-checkout set foundations/linux/lx10-troubleshooting

# Gitee（中国大陆用户）
git clone --filter=blob:none --sparse https://gitee.com/shiicho/cloud-atlas ~/cloud-atlas
cd ~/cloud-atlas && git sparse-checkout set foundations/linux/lx10-troubleshooting
```

## 前置课程

- [LX05 - systemd 深入](../lx05-systemd/)
- [LX07 - 存储管理](../lx07-storage/)
- [LX09 - 性能调优](../lx09-performance/)

## 后续路径

完成本课程后，你已具备：

- 生产级故障排查能力
- RHCE 故障排除模块覆盖
- 日本 IT 障害対応实战经验
