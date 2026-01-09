# 04 - 条件判断 示例代码

本目录包含 Lesson 04（条件判断）的示例代码。

## 文件说明

| 文件 | 说明 |
|------|------|
| `file_detector.sh` | Mini Project - 文件类型检测器 |
| `test_comparison.sh` | 演示 `[ ]` vs `[[ ]]` 的区别 |
| `case_demo.sh` | case 语句多种用法演示 |

## 使用方法

```bash
# 给所有脚本添加执行权限
chmod +x *.sh

# 运行文件检测器
./file_detector.sh /etc/passwd
./file_detector.sh /etc
./file_detector.sh /bin/bash

# 运行 [ ] vs [[ ]] 对比演示
./test_comparison.sh

# 运行 case 语句演示
./case_demo.sh
./case_demo.sh start
./case_demo.sh stop
```

## ShellCheck 检查

所有脚本都应通过 ShellCheck 检查：

```bash
shellcheck *.sh
```

## 相关课程

- [Lesson 04 - 条件判断](../README.md)
