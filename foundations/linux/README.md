# Linux 系列 | Linux Series

Linux 是云计算和 DevOps 的基石。本系列从零开始，带你系统掌握 Linux 运维技能。

> **面向日本 IT 运维场景**：每课配实战项目，聚焦运维巡检、日志分析、自动化报警等实际工作需求。  

## 课程模块 / Course Modules

### Tier 1: Survivor（生存必备）

| 模块 | 课程 | 内容 |
|------|------|------|
| LX01 | [Linux 基础](./lx01-foundations/) | CLI 导航、文件操作、权限管理 |
| LX02 | [系统管理](./lx02-sysadmin/) | 用户、权限、进程、包管理 |
| LX03 | [文本处理](./lx03-text-processing/) | grep/sed/awk、日志分析 |
| LX04 | [Shell 脚本](./lx04-shell-scripting/) | Bash 编程、自动化脚本 |

### Tier 2: Operator（日常运维）

| 模块 | 课程 | 内容 |
|------|------|------|
| LX05 | [Systemd](./lx05-systemd/) | 服务管理、日志查看 |
| LX06 | [网络基础](./lx06-networking/) | 配置、诊断、防火墙 |
| LX07 | [存储管理](./lx07-storage/) | LVM、文件系统、备份 |
| LX08 | [安全加固](./lx08-security/) | SSH、SELinux、审计 |

### Tier 3: Troubleshooter（问题诊断）

| 模块 | 课程 | 内容 |
|------|------|------|
| LX09 | [性能分析](./lx09-performance/) | CPU/内存/IO 分析、eBPF |
| LX10 | [故障排查](./lx10-troubleshooting/) | 问题诊断、RCA 方法论 |

### Tier 4: Specialist（专业进阶）

| 模块 | 课程 | 内容 |
|------|------|------|
| LX11 | [容器基础](./lx11-containers/) | Namespace、cgroups、OCI |
| LX12 | [云端 Linux](./lx12-cloud/) | cloud-init、Golden Image |

## 快速开始 / Quick Start

```bash
# 1. 部署练习环境
git clone --filter=blob:none --sparse https://github.com/shiicho/cloud-atlas ~/cloud-atlas
cd ~/cloud-atlas && git sparse-checkout set foundations/linux

# 2. 从 LX01 开始
cd foundations/linux/lx01-foundations
```

## 旧版课程 / Legacy Course

Looking for the original 7-lesson Bash course? It's archived here:
- [Bash 脚本入门 v1](./_archived/linux-bash-v1/) - 原 6+1 课快速入门

## 系列导航 / Related Series

- [AWS SSM 系列](../../cloud/aws-ssm/) - 深入学习 Session Manager
- [Terraform 系列](../../automation/terraform/) - 基础设施即代码
- [Ansible 系列](../../automation/ansible/) - 配置管理自动化

---

*12 模块 · 132 节课 · 对标 LPIC-1/RHCSA/RHCE*
