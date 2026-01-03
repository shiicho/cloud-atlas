# Bash 脚本入门系列 | Bash Scripting for Beginners

从零开始学习 Bash 脚本编程，6 节课带你掌握 Linux 自动化必备技能。

> **面向日本 IT 运维场景**：每课配实战项目，聚焦运用巡检、日志分析、自动化报警等实际工作需求。

## 系列概览 / Series Overview

| # | 课程 | 主题 | 实战项目 |
|---|------|------|----------|
| 00 | [环境准备](./00-setup/) | 一键部署练习环境 | CloudFormation 部署 EC2 |
| 01 | [第一个脚本](./01-first-script/) | shebang、执行权限、变量 | 系统概要报告 |
| 02 | [变量与文件系统](./02-filesystem/) | 路径、重定向、磁盘操作 | 磁盘空间快照 |
| 03 | [管道与文本](./03-pipes/) | 管道、排序、日志基础 | Web 日志 Top 分析 |
| 04 | [条件与循环](./04-loops/) | if/for/while、数组 | 批量服务器检查 |
| 05 | [函数与参数](./05-functions/) | 函数封装、getopts | 健康检查脚本 |
| 06 | [文本进阶与自动化](./06-automation/) | grep/sed/awk、cron | 日志报警雏形 |

## 适合谁 / Who Is This For

- Linux 新手，想学自动化
- 在日本 IT 行业工作或求职的运维/SRE
- 开发者，想提升命令行效率
- 任何对 Shell 脚本感兴趣的人

## 环境要求 / Prerequisites

- AWS 账号（免费套餐即可）
- 无需本地安装任何软件
- 使用 AWS Session Manager 浏览器终端
- **推荐先学**：[SSM 系列 02 · Session Manager 免密登录](../../aws/ssm/02-session-manager/)

## 快速开始 / Quick Start

```bash
# 1. 部署练习环境（见 00-setup）
#    Deploy the lab environment (see 00-setup)

# 2. 通过 Session Manager 连接 EC2
#    Connect to EC2 via Session Manager

# 3. 开始第一课！
#    Start lesson 01!
```

## 完成后你能 / After This Series

- 编写运维巡检脚本（系统报告、磁盘快照）
- 分析 Web 日志定位问题（Top IP、Top 路径）
- 批量检查服务器健康状态
- 实现简单的日志报警自动化
- 为 SRE/运维岗位面试加分

## 系列导航 / Related Series

- [AWS SSM 系列](../../aws/ssm/) - 深入学习 Session Manager
- [Linux 基础](../) - 更多 Linux 概念

---

*预计学习时间：每课 20-30 分钟，全系列约 3 小时*
