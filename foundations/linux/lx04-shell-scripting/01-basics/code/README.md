# Lesson 01 代码示例

本目录包含脚本基础与执行方式课程的所有示例代码。

## 文件列表

| 文件 | 说明 |
|------|------|
| `hello.sh` | 第一个 Hello World 脚本 |
| `shebang-demo.sh` | Shebang 两种写法对比演示 |
| `system-info.sh` | Mini Project 参考实现 |
| `template.sh` | 推荐的脚本模板 |
| `fixed.sh` | 修复后的正确示例 |
| `bad/buggy.sh` | 反模式演示（故意包含错误） |
| `bad/no-shebang.sh` | 缺少 shebang 的反模式 |

## 快速开始

```bash
# 克隆仓库（使用 sparse checkout）
git clone --filter=blob:none --sparse https://github.com/shiicho/cloud-atlas ~/cloud-atlas
cd ~/cloud-atlas && git sparse-checkout set foundations/linux/shell-scripting

# 进入代码目录
cd foundations/linux/shell-scripting/01-basics/code

# 运行第一个脚本
chmod +x hello.sh
./hello.sh

# 使用 ShellCheck 检查脚本
shellcheck hello.sh
shellcheck bad/buggy.sh  # 会显示错误
```

## ShellCheck 练习

```bash
# 查看反模式的问题
shellcheck bad/buggy.sh

# 验证修复后的版本
shellcheck fixed.sh
```
