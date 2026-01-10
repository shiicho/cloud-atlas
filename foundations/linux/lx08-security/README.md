# LX08 - Linux 安全加固（Linux Security Hardening）

> **从 SSH 加固到 CIS 合规，系统学习 Linux 安全硬化**

本课程是 Linux World 模块化课程体系的一部分，专注于生产级安全加固。

## 课程概览

| 属性 | 值 |
|------|-----|
| **课时** | 12 课 |
| **时长** | 25-30 小时 |
| **难度** | 中高级 |
| **前置** | LX02 系统管理 + LX06 网络 |
| **认证** | RHCSA, RHCE |

## 课程特色

- **SSH 起步**：实用技能建立信心
- **SELinux 安全网思维**：保护你，不是阻碍你
- **场景驱动**：真实日本 IT 安全事件作为学习载体
- **合规实战**：CIS Benchmarks、OpenSCAP 扫描

## 版本兼容性

| 工具 | 课程版本 | 当前最新 | 说明 |
|------|----------|----------|------|
| **OpenSSH** | 8.0+ | 9.9 (2024) | ed25519、FIDO2 支持 |
| **SELinux** | targeted 3.5+ | 3.7 (2025) | RHEL 8/9 默认策略 |
| **auditd** | 3.0+ | 3.1.6 (2025) | 审计规则、ausearch |
| **nftables** | 0.9+ | 1.1.1 (2025) | RHEL 9+ 默认防火墙 |
| **OpenSCAP** | 1.3+ | 1.4.1 (2025) | CIS Benchmark 扫描 |
| **PAM** | 1.3+ | 1.7.0 (2025) | faillock 替代 pam_tally2 |
| **RHEL** | 8/9 | 9.5 | RHEL 8 支持至 2029 |
| **Ubuntu** | 20.04+ | 24.04 LTS | 22.04/24.04 推荐 |

**注意事项：**
- SELinux 默认在 RHEL/CentOS 启用，Ubuntu 需手动安装配置
- RHEL 9 使用 nftables 替代 iptables，firewalld 后端已切换
- pam_tally2 在 RHEL 8+ 已弃用，使用 faillock 模块

## 课程大纲

### Part 1: 基础与 SSH (01-02)

| 课程 | 标题 | 描述 |
|------|------|------|
| 01 | [安全原则](./01-security-principles/) | 纵深防御、最小权限 |
| 02 | [SSH 加固](./02-ssh-hardening/) | 密钥认证、FIDO2 |

### Part 2: SELinux (03-05)

| 课程 | 标题 | 描述 |
|------|------|------|
| 03 | [SELinux 概念](./03-selinux-concepts/) | MAC、上下文、布尔值 |
| 04 | [SELinux 排错](./04-selinux-troubleshooting/) | audit2why、sealert |
| 05 | [SELinux 高级](./05-selinux-advanced/) | 策略模块、自定义 |

### Part 3: 审计与防火墙 (06-08)

| 课程 | 标题 | 描述 |
|------|------|------|
| 06 | [Capabilities](./06-capabilities/) | 细粒度权限 |
| 07 | [auditd 审计](./07-auditd/) | 规则、日志、溯源 |
| 08 | [nftables 深入](./08-nftables/) | 企业级防火墙规则 |

### Part 4: 认证与合规 (09-11)

| 课程 | 标题 | 描述 |
|------|------|------|
| 09 | [PAM 高级配置](./09-pam-advanced/) | 认证链路、MFA |
| 10 | [CIS Benchmarks](./10-cis-benchmarks/) | OpenSCAP、合规自动化 |
| 11 | [加固自动化](./11-hardening-automation/) | Ansible 加固剧本 |

### Part 5: 综合项目 (12)

| 课程 | 标题 | 描述 |
|------|------|------|
| 12 | [综合实战](./12-capstone/) | 完整安全加固项目 |

## 快速开始

```bash
# GitHub（海外用户）
git clone --filter=blob:none --sparse https://github.com/shiicho/cloud-atlas ~/cloud-atlas
cd ~/cloud-atlas && git sparse-checkout set foundations/linux/lx08-security

# Gitee（中国大陆用户）
git clone --filter=blob:none --sparse https://gitee.com/shiicho/cloud-atlas ~/cloud-atlas
cd ~/cloud-atlas && git sparse-checkout set foundations/linux/lx08-security
```

## 前置课程

- [LX02 - 系统管理](../lx02-sysadmin/)
- [LX06 - 网络](../lx06-networking/)

## 后续路径

完成本课程后，你可以：

- **LX11 - 容器**：容器安全边界
- **LX12 - 云端 Linux**：云安全最佳实践
