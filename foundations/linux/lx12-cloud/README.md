# LX12 - 云端 Linux（Linux in Cloud）

> **从 Linux 管理员视角学习云端 Linux - 不是云服务，而是 Linux 在云中的差异**

本课程是 Linux World 模块化课程体系的一部分，专注于云环境中的 Linux 管理。

## 课程概览

| 属性 | 值 |
|------|-----|
| **课时** | 10 课 |
| **时长** | 20-25 小时 |
| **难度** | 高级 |
| **前置** | LX06 网络 + LX08 安全 |
| **认证** | AWS SAA 相关 |

## 课程特色

- **Linux-first 视角**：从 Linux 内部理解云行为
- **故障驱动学习**：6 个真实生产场景作为实验
- **跨云概念**：AWS 为主，GCP/Azure 侧边栏
- **不讲控制台点击**：全程 CLI + 代码

## 版本兼容性

| 工具 | 课程版本 | 当前最新 | 说明 |
|------|----------|----------|------|
| **cloud-init** | 23.x+ | 25.3 (2025) | 启动流程配置 |
| **AWS CLI** | 2.15+ | 2.32 (2025) | AWS 命令行工具 |
| **CloudWatch Agent** | 1.300+ | 1.300063 (2025) | 指标/日志收集 |
| **IMDSv2** | - | 推荐 | 元数据安全访问 |
| **RHEL** | 8/9 | 9.5 | RHEL 8 支持至 2029 |
| **Ubuntu** | 20.04+ | 24.04 LTS | 22.04/24.04 推荐 |
| **Amazon Linux** | 2023 | 2023.6 | 推荐用于 AWS |

**注意事项：**
- IMDSv2 强制启用是 AWS 安全最佳实践
- EBS NVMe 设备名需要使用 ebsnvme-id 解析
- cloud-init 日志在 /var/log/cloud-init*.log

## 课程大纲

### Part 1: 基础 (01-03)

| 课程 | 标题 | 描述 |
|------|------|------|
| 01 | [云端上下文](./01-cloud-context/) | 云与裸金属的差异 |
| 02 | [cloud-init](./02-cloud-init/) | 启动流程与调试 |
| 03 | [元数据服务](./03-metadata/) | 169.254.169.254、IMDSv2 |

### Part 2: 网络与存储 (04-05)

| 课程 | 标题 | 描述 |
|------|------|------|
| 04 | [云网络](./04-cloud-networking/) | 安全组 vs nftables |
| 05 | [云存储](./05-cloud-storage/) | EBS 扩容、设备名变化 |

### Part 3: 安全与镜像 (06-08)

| 课程 | 标题 | 描述 |
|------|------|------|
| 06 | [IAM 与实例配置文件](./06-iam-instance-profiles/) | 告别硬编码凭证 |
| 07 | [金色镜像策略](./07-golden-image/) | Bake vs Bootstrap |
| 08 | [镜像加固](./08-image-hardening/) | CIS 基线、供应链安全 |

### Part 4: 可观测性与综合 (09-10)

| 课程 | 标题 | 描述 |
|------|------|------|
| 09 | [可观测性集成](./09-observability/) | CloudWatch Agent |
| 10 | [综合实战](./10-capstone/) | 生产级云 Linux 部署 |

## 快速开始

```bash
# GitHub（海外用户）
git clone --filter=blob:none --sparse https://github.com/shiicho/cloud-atlas ~/cloud-atlas
cd ~/cloud-atlas && git sparse-checkout set foundations/linux/lx12-cloud

# Gitee（中国大陆用户）
git clone --filter=blob:none --sparse https://gitee.com/shiicho/cloud-atlas ~/cloud-atlas
cd ~/cloud-atlas && git sparse-checkout set foundations/linux/lx12-cloud
```

## 前置课程

- [LX06 - 网络](../lx06-networking/)
- [LX08 - 安全加固](../lx08-security/)

## 后续路径

完成本课程后，你可以：

- **AWS SSM 课程**：深入 AWS 运维管理
- **Terraform 课程**：基础设施即代码
- **AWS SAA 认证**：有 Linux 视角的云架构理解
