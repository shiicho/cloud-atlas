# LX04 - Shell 脚本编程（Shell Scripting）

> **从零开始系统学习 Bash Shell 脚本编程**  

本课程是 Linux World 模块化课程体系的一部分，专注于 Bash 脚本自动化。

## 课程概览

| 属性 | 值 |
|------|-----|
| **课时** | 12 课 |
| **时长** | 25-30 小时 |
| **难度** | 中级 |
| **前置** | LX01 基础入门 + LX03 文本处理 |
| **认证** | LPIC-1, RHCE |

## 课程特色

- **ShellCheck 全程**：从第一课起使用静态检查，养成好习惯
- **引用规则专课**：Shell 脚本 #1 Bug 来源，专门一课深入讲解
- **失败实验室**：故意制造问题，学会调试
- **日本 IT 场景**：運用監視、障害対応、自動化脚本实例

## 课程大纲

### Part 1: 基础 (01-03)

| 课程 | 标题 | 状态 |
|------|------|------|
| 01 | [脚本基础与执行方式](./01-basics/) | draft |
| 02 | 变量与环境 | pending |
| 03 | 引用规则（重点课！） | pending |

### Part 2: 控制流 (04-05)

| 课程 | 标题 | 状态 |
|------|------|------|
| 04 | 条件判断 | pending |
| 05 | 循环结构 | pending |

### Part 3: 函数与数据结构 (06-08)

| 课程 | 标题 | 状态 |
|------|------|------|
| 06 | 函数 | pending |
| 07 | 数组 | pending |
| 08 | 参数展开 | pending |

### Part 4: 生产级质量 (09-11)

| 课程 | 标题 | 状态 |
|------|------|------|
| 09 | 错误处理与 trap（重点课！） | pending |
| 10 | 命令行参数处理 | pending |
| 11 | 调试技巧与最佳实践 | pending |

### Part 5: 综合项目 (12)

| 课程 | 标题 | 状态 |
|------|------|------|
| 12 | 综合项目：自动化工具开发 | pending |

## 快速开始

```bash
# GitHub（海外用户）
git clone --filter=blob:none --sparse https://github.com/shiicho/cloud-atlas ~/cloud-atlas
cd ~/cloud-atlas && git sparse-checkout set foundations/linux/shell-scripting

# Gitee（中国大陆用户）
git clone --filter=blob:none --sparse https://gitee.com/shiicho/cloud-atlas ~/cloud-atlas
cd ~/cloud-atlas && git sparse-checkout set foundations/linux/shell-scripting
```

## 前置课程

- [LX01 - Linux 基础入门](../foundations/)
- [LX03 - 文本处理](../text-processing/)

## 后续路径

完成本课程后，你可以：

- **LX05 - systemd 深入**：在 service unit 中使用脚本
- **LX09 - 性能调优**：编写性能监控脚本
- **Ansible 课程**：从脚本迁移到声明式自动化
