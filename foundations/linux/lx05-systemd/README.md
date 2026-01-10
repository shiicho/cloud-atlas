# LX05 - systemd 深入（systemd Deep Dive）

> **现代 Linux 的核心：systemd 系统与服务管理器**

本课程是 Linux World 模块化课程体系的一部分，专注于 systemd 服务管理。

## 课程概览

| 属性 | 值 |
|------|-----|
| **课时** | 10 课 |
| **时长** | 20-25 小时 |
| **难度** | 中高级 |
| **前置** | LX02 系统管理 |
| **认证** | RHCSA, LPIC-2 |

## 课程特色

- **Taste-First**：先用 systemctl 再理解 Unit 文件
- **依赖关系重点**：Ordering vs Requirements 区分
- **Timer 迁移**：从 cron 到 systemd timer
- **日本 IT 场景**：運用監視、障害対応、変更管理

## 版本兼容性

| 环境 | 课程目标 | 当前最新 | 说明 |
|------|----------|----------|------|
| **systemd** | 240+ | 257 (2025) | 课程内容与最新版本兼容 |
| **RHEL** | 8/9 | 9.5 | RHEL 8 使用 systemd 239+，RHEL 9 使用 252+ |
| **Ubuntu** | 20.04+ | 24.04 LTS | Ubuntu 20.04 (systemd 245)，22.04 (249)，24.04 (255) |
| **cgroup** | v2 | v2 | systemd 258 已弃用 cgroup v1；RHEL 9 默认 v2 |

**注意事项：**
- Lesson 08 资源控制使用 cgroup v2 语法，RHEL 8 用户需确认已切换到 unified 模式
- LoadCredential 等新特性需要 systemd 250+（RHEL 9、Ubuntu 22.04+）
- 所有命令在 RHEL 8/9 和 Ubuntu 20.04+ 上测试通过

> 📌 详细版本信息请参考 [Linux 系列发行版生命周期](../)

## 课程大纲

### Part 1: 基础 (01-03)

| 课程 | 标题 | 描述 |
|------|------|------|
| 01 | [systemd 架构](./01-architecture/) | 设计哲学、PID 1、Unit 类型 |
| 02 | [systemctl 命令](./02-systemctl/) | start/stop、enable/disable、status |
| 03 | [Unit 文件结构](./03-unit-files/) | [Unit]、[Service]、[Install] |

### Part 2: 启动与依赖 (04-05)

| 课程 | 标题 | 描述 |
|------|------|------|
| 04 | [依赖关系](./04-dependencies/) | Wants、Requires、After、Before |
| 05 | [Target 与启动流程](./05-targets/) | multi-user.target、rescue.target |

### Part 3: 日志与定时 (06-07)

| 课程 | 标题 | 描述 |
|------|------|------|
| 06 | [Timer 定时器](./06-timers/) | OnCalendar、cron 替代 |
| 07 | [journalctl 日志](./07-journalctl/) | 过滤、持久化、导出 |

### Part 4: 高级配置 (08-09)

| 课程 | 标题 | 描述 |
|------|------|------|
| 08 | [资源控制](./08-resource-control/) | cgroup v2、CPUQuota、MemoryMax |
| 09 | [定制与安全](./09-customization-security/) | Drop-in、安全加固选项 |

### Part 5: 综合项目 (10)

| 课程 | 标题 | 描述 |
|------|------|------|
| 10 | [综合实战](./10-capstone/) | 完整服务部署与管理 |

## 快速开始

```bash
# GitHub（海外用户）
git clone --filter=blob:none --sparse https://github.com/shiicho/cloud-atlas ~/cloud-atlas
cd ~/cloud-atlas && git sparse-checkout set foundations/linux/lx05-systemd

# Gitee（中国大陆用户）
git clone --filter=blob:none --sparse https://gitee.com/shiicho/cloud-atlas ~/cloud-atlas
cd ~/cloud-atlas && git sparse-checkout set foundations/linux/lx05-systemd
```

## 前置课程

- [LX02 - 系统管理](../lx02-sysadmin/)

## 后续路径

完成本课程后，你可以：

- **LX08 - 安全加固**：systemd 安全特性深入
- **LX09 - 性能调优**：systemd 指标分析
- **LX10 - 故障排查**：启动故障、服务调试
- **LX11 - 容器**：cgroups v2 深入
