# LX03 - 文本处理精通（Text Processing Mastery）

> **掌握 Unix 文本处理哲学：管道、过滤器、grep、sed、awk**

本课程是 Linux World 模块化课程体系的一部分，专注于文本处理与日志分析。

## 课程概览

| 属性 | 值 |
|------|-----|
| **课时** | 10 课 |
| **时长** | 20-25 小时 |
| **难度** | 中级 |
| **前置** | LX01 基础入门 |
| **认证** | LPIC-1 (101.3, 103.2, 103.7) |

## 课程特色

- **日志分析主线**：以 運用監視 场景贯穿全课程
- **Unix 哲学**：小工具、大组合
- **grep → sed → awk**：渐进式复杂度
- **日本 IT 场景**：障害対応、ログ分析

## 课程大纲

### Part 1: 基础 (01-02)

| 课程 | 标题 | 描述 |
|------|------|------|
| 01 | [管道与重定向](./01-pipes-redirection/) | >、>>、\|、tee |
| 02 | [查看文件](./02-viewing-files/) | cat、less、head、tail |

### Part 2: 搜索 (03-04)

| 课程 | 标题 | 描述 |
|------|------|------|
| 03 | [grep 基础](./03-grep-fundamentals/) | grep 选项、-E、-v、-c |
| 04 | [正则表达式](./04-regular-expressions/) | BRE、ERE、常用模式 |

### Part 3: 转换 (05-07)

| 课程 | 标题 | 描述 |
|------|------|------|
| 05 | [sed 转换](./05-sed-transformation/) | s/old/new/、-i、地址范围 |
| 06 | [awk 字段处理](./06-awk-fields/) | $1、$NF、FS、OFS |
| 07 | [awk 程序](./07-awk-programs/) | BEGIN/END、变量、条件 |

### Part 4: 工具集 (08-09)

| 课程 | 标题 | 描述 |
|------|------|------|
| 08 | [排序与去重](./08-sorting-uniqueness/) | sort、uniq、wc |
| 09 | [find 与 xargs](./09-find-xargs/) | find、xargs -0 |

### Part 5: 综合项目 (10)

| 课程 | 标题 | 描述 |
|------|------|------|
| 10 | [实战：日志分析管道](./10-capstone-pipeline/) | 完整日志分析工具 |

## 快速开始

```bash
# GitHub（海外用户）
git clone --filter=blob:none --sparse https://github.com/shiicho/cloud-atlas ~/cloud-atlas
cd ~/cloud-atlas && git sparse-checkout set foundations/linux/lx03-text-processing

# Gitee（中国大陆用户）
git clone --filter=blob:none --sparse https://gitee.com/shiicho/cloud-atlas ~/cloud-atlas
cd ~/cloud-atlas && git sparse-checkout set foundations/linux/lx03-text-processing
```

## 前置课程

- [LX01 - Linux 基础入门](../lx01-foundations/)

## 后续路径

完成本课程后，你可以：

- **LX04 - Shell 脚本**：将文本处理融入自动化脚本
- **LX08 - 安全加固**：日志分析用于安全审计
