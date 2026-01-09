# LX01 - Linux 基础入门（Linux Foundations）

> **踏入 Linux 世界的第一步**

本课程是 Linux World 模块化课程体系的入门课程，零 Linux 经验起步。

## 课程概览

| 属性 | 值 |
|------|-----|
| **课时** | 10 课 |
| **时长** | 20-25 小时 |
| **难度** | 入门 |
| **前置** | 无 |
| **认证** | LPIC-1 (101-500) |

## 课程特色

- **零恐惧起步**：终端是朋友，不是敌人
- **即时成就感**：每课结束都有看得见的成果
- **先动手后理论**：Taste-First 教学法
- **安全探索**：从只读命令开始，~/playground 作为实验区

## 课程大纲

### Part 1: 起步 (01-03)

| 课程 | 标题 | 描述 |
|------|------|------|
| 01 | [欢迎来到 Linux](./01-welcome-linux/) | Linux 简介、发行版、终端与 Shell |
| 02 | [第一步](./02-first-steps/) | Shell 提示符、pwd、ls、Tab 补全 |
| 03 | [文件系统导航](./03-navigation/) | cd、路径类型、FHS 心智模型 |

### Part 2: 文件操作 (04-05)

| 课程 | 标题 | 描述 |
|------|------|------|
| 04 | [文件和目录](./04-files-directories/) | mkdir、touch、cp、mv、rm |
| 05 | [查看文件内容](./05-viewing-files/) | cat、less、head、tail -f |

### Part 3: 自助学习 (06-07)

| 课程 | 标题 | 描述 |
|------|------|------|
| 06 | [获取帮助](./06-getting-help/) | man、--help、apropos |
| 07 | [文本编辑基础](./07-text-editing/) | nano 主修、vim 求生 |

### Part 4: Shell 环境 (08-09)

| 课程 | 标题 | 描述 |
|------|------|------|
| 08 | [Shell 配置](./08-shell-config/) | .bashrc、别名、PS1 |
| 09 | [环境变量和 PATH](./09-environment-path/) | 环境变量、PATH、~/bin |

### Part 5: 综合项目 (10)

| 课程 | 标题 | 描述 |
|------|------|------|
| 10 | [实战：你的第一个脚本](./10-capstone-first-script/) | 系统健康报告脚本 |

## 快速开始

```bash
# GitHub（海外用户）
git clone --filter=blob:none --sparse https://github.com/shiicho/cloud-atlas ~/cloud-atlas
cd ~/cloud-atlas && git sparse-checkout set foundations/linux/lx01-foundations

# Gitee（中国大陆用户）
git clone --filter=blob:none --sparse https://gitee.com/shiicho/cloud-atlas ~/cloud-atlas
cd ~/cloud-atlas && git sparse-checkout set foundations/linux/lx01-foundations
```

## 后续路径

完成本课程后，你可以：

- **LX02 - 系统管理**：用户、权限、进程、包管理
- **LX03 - 文本处理**：grep、sed、awk、管道
- **LX04 - Shell 脚本**：系统学习 Bash 编程
