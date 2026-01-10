# LX02 - Linux 系统管理（System Administration）

> **掌握日常 Linux 运维的核心技能**

本课程是 Linux World 模块化课程体系的一部分，专注于系统管理基础。

## 课程概览

| 属性 | 值 |
|------|-----|
| **课时** | 12 课 |
| **时长** | 25-30 小时 |
| **难度** | 中级 |
| **前置** | LX01 基础入门 |
| **认证** | LPIC-1, RHCSA |

## 课程特色

- **权限重点**：chmod 777 的危害，最小权限原则
- **SUID 安全审计**：理解特殊权限的攻击面
- **sudo 最佳实践**：visudo、最小权限配置
- **日本 IT 场景**：アカウント管理、権限管理台帳

## 版本兼容性

本课程基于 RHEL 8/9 和 Ubuntu 22.04/24.04 编写。用户/权限管理命令跨版本稳定。

> 📌 详细版本信息请参考 [Linux 系列发行版生命周期](../)

## 课程大纲

### Unit 1: 用户和组管理 (01-02)

| 课程 | 标题 | 描述 |
|------|------|------|
| 01 | [用户与用户组](./01-users-and-groups/) | useradd、groupadd、/etc/passwd |
| 02 | [密码与账户管理](./02-password-account-management/) | /etc/shadow、chage、PAM 基础 |

### Unit 2: 文件权限 (03-05)

| 课程 | 标题 | 描述 |
|------|------|------|
| 03 | [文件权限基础](./03-file-permissions-fundamentals/) | chmod、chown、umask |
| 04 | [特殊权限](./04-special-permissions/) | SUID、SGID、Sticky Bit |
| 05 | [ACL 与文件属性](./05-acls-file-attributes/) | setfacl、chattr |

### Unit 3: Sudo 配置 (06)

| 课程 | 标题 | 描述 |
|------|------|------|
| 06 | [sudo 配置](./06-sudo-configuration/) | visudo、sudoers.d、最小权限 |

### Unit 4: 进程管理 (07-08)

| 课程 | 标题 | 描述 |
|------|------|------|
| 07 | [进程基础](./07-process-fundamentals/) | ps、top、/proc |
| 08 | [信号与作业控制](./08-signals-job-control/) | kill、fg、bg、nohup |

### Unit 5: 包管理 (09-11)

| 课程 | 标题 | 描述 |
|------|------|------|
| 09 | [软件包管理 (RPM/DNF)](./09-package-management-rpm-dnf/) | rpm、dnf、RHEL 系 |
| 10 | [软件包管理 (DEB/APT)](./10-package-management-deb-apt/) | dpkg、apt、Debian 系 |
| 11 | [软件源与 GPG](./11-repository-gpg/) | 仓库配置、GPG 验证 |

### Unit 6: 综合项目 (12)

| 课程 | 标题 | 描述 |
|------|------|------|
| 12 | [综合实战：多用户环境](./12-capstone-multiuser-environment/) | 团队环境搭建 |

## 快速开始

```bash
# GitHub（海外用户）
git clone --filter=blob:none --sparse https://github.com/shiicho/cloud-atlas ~/cloud-atlas
cd ~/cloud-atlas && git sparse-checkout set foundations/linux/lx02-sysadmin

# Gitee（中国大陆用户）
git clone --filter=blob:none --sparse https://gitee.com/shiicho/cloud-atlas ~/cloud-atlas
cd ~/cloud-atlas && git sparse-checkout set foundations/linux/lx02-sysadmin
```

## 前置课程

- [LX01 - Linux 基础入门](../lx01-foundations/)

## 后续路径

完成本课程后，你可以：

- **LX05 - systemd 深入**：服务管理、启动流程
- **LX06 - 网络**：网络配置与排障
- **LX07 - 存储管理**：LVM、RAID、备份
