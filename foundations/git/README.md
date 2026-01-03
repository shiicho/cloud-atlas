# Git 版本控制：从入门到协作

> **Git Version Control: From Basics to Collaboration**
> 掌握现代团队协作的核心工具，为 DevOps 和 IaC 工作流打下坚实基础

---

## 课程简介

从零开始系统学习 Git 版本控制。本课程专为 DevOps 和基础设施工程师设计，使用 IaC 文件（Terraform、Ansible）作为示例，而非应用代码。

**学完本课程，你将能够：**
- 理解 Git 的设计哲学和核心概念
- 熟练使用 Git 进行本地和远程仓库操作
- 掌握分支、合并、冲突解决
- 参与 Pull Request 协作流程
- 在日本 IT 职场中应用 Git 最佳实践

---

## 课程信息

| 项目 | 详情 |
|------|------|
| **难度** | 入门 (Beginner) |
| **时长** | 8-10 小时 |
| **前置条件** | 无（推荐：基本命令行经验） |
| **环境要求** | Git 2.40+，GitHub 账号 |
| **费用** | 免费（GitHub 免费版即可） |

---

## 课程大纲

| # | 课程 | 时长 | 类型 |
|---|------|------|------|
| 00 | [概念导入：Git 的设计哲学](00-concepts/) | 15 min | 概念 |
| 01 | [第一个提交：本地仓库](01-first-commit/) | 30 min | 实操 |
| 02 | [远程仓库：连接世界](02-remote/) | 35 min | 实操 |
| 03 | [分支：Git 的杀手锏](03-branches/) | 40 min | 实操 |
| 04 | [冲突解决与历史探索](04-conflicts/) | 45 min | 实操 |
| 05 | [Pull Request 协作流程](05-pull-requests/) | 50 min | 实操 |
| 06 | [日本 IT 应用指南](06-japan-it/) | 45 min | 实操 (可选) |

---

## 学习路径

```
00 概念导入        理解 Git 设计哲学
      │
      ▼
01 第一个提交      本地仓库操作
      │
      ▼
02 远程仓库        连接 GitHub
      │
      ▼
03 分支            并行开发
      │
      ▼
04 冲突解决        团队协作必备
      │
      ▼
05 Pull Request    现代协作流程
      │
      ▼
06 日本 IT 指南    职场应用 (可选)
```

---

## 前置条件

**必须：**
- 无（真正的零基础课程）

**推荐：**
- 基本命令行经验（`cd`、`ls`、`mkdir`）
- 已安装 Git（[安装指南](https://git-scm.com/downloads)）

**可选：**
- GitHub 账号（Lesson 02 开始需要）
- VS Code 或其他代码编辑器

---

## 环境准备

### 方式一：本地环境（推荐）

```bash
# 检查 Git 是否已安装
git --version

# 如未安装：
# macOS
brew install git

# Ubuntu/Debian
sudo apt install git

# Windows
# 下载 https://git-scm.com/download/win
```

### Windows 用户注意

推荐使用 **Git Bash**（安装 Git for Windows 时自带）运行本课程的所有命令。

安装后，打开 Git Bash 运行一次：

```bash
git config --global core.autocrlf true
```

> 这能避免 Windows 与 Linux/macOS 协作时的换行符问题。

### 方式二：云端环境

如果你已部署其他课程的 Lab EC2（如 Terraform Lab），Git 已预装，可直接使用。

### 练习目录说明

本课程使用多个练习目录，设计目的如下：

| 目录 | 课程 | 说明 |
|------|------|------|
| `~/system-check` | 01, 02, 03, 05 | 主项目，贯穿多课 |
| `~/git-practice/` | 04 | 冲突练习（隔离环境） |
| `~/my-infrastructure` | 06 | 日本 IT 风格项目 |

> **提示**：每课开头都有路径说明。如果中途休息，记得回到正确的目录。

---

## 目标学员

- **基础设施工程师**：需要版本控制 IaC 代码
- **DevOps 工程师**：团队协作和 CI/CD 基础
- **运维工程师**：管理配置文件和脚本
- **转职者**：从 GUI 工具转向 CLI Git
- **日本 IT 就职者**：需要了解日本企业的 Git 工作流

---

## 技能树定位

```
本课程填补的技能缺口：

[git-basics] ─────► [terraform-basics]
     │
     ├──────────► [docker-basics]
     │
     └──────────► [cicd-github-actions]
```

完成本课程后，你将满足 Terraform、Docker、CI/CD 课程的 Git 前置条件。

---

## 课程特色

| 特色 | 说明 |
|------|------|
| **理念先行** | 先理解 Git 为什么这样设计，再学命令 |
| **IaC 视角** | 示例使用 `.tf`、`.yaml`、`.sh` 文件 |
| **动手优先** | 每课先运行，再解释（Taste-First） |
| **日本 IT** | 最后一课专门讲日本职场应用 |
| **本地学习** | 无需云资源，本机即可完成 |

---

## 进阶路线

完成本课程后，推荐学习：

1. **[Terraform 基础设施即代码](../../automation/terraform/)** — 使用 Git 管理 IaC
2. **CI/CD with GitHub Actions**（规划中）— Git 触发自动化流水线
3. **Git Advanced**（规划中）— Rebase、Hooks、Internals

---

## 相关资源

- [Git 官方文档](https://git-scm.com/doc)
- [GitHub 文档](https://docs.github.com/)
- [Conventional Commits](https://conventionalcommits.org/)

---

## 反馈与问题

如果发现内容问题或有改进建议，欢迎：
- 在 [GitHub Issues](https://github.com/shiicho/cloud-atlas/issues) 提交反馈
- 通过 Pull Request 贡献修正

---

*本课程是 [Cloud Atlas](https://github.com/shiicho/cloud-atlas) 系列的一部分。*
