#!/bin/bash
# =============================================================================
# 脚本名称: for_ls.sh
# 功能说明: 反模式演示 - for in $(ls) 的问题
# 课程: LX04-SHELL Lesson 05 - 循环结构
# =============================================================================
#
# !! 警告 !!
# 这是一个反模式演示，展示常见错误
# 不要在生产环境使用 for in $(ls)
#
# =============================================================================

# 创建测试环境
TESTDIR=$(mktemp -d)
touch "$TESTDIR/normal.txt"
touch "$TESTDIR/with space.txt"
touch "$TESTDIR/multi  spaces.txt"

echo "实际文件列表："
ls -la "$TESTDIR/"
echo ""

echo "=== 错误方法：for in \$(ls) ==="
echo "（注意：带空格的文件名会被分割！）"
cd "$TESTDIR" || exit 1
for file in $(ls); do
    echo "  遍历到: [$file]"
    if [[ -e "$file" ]]; then
        echo "    -> 文件存在"
    else
        echo "    -> 文件不存在！（被错误分割）"
    fi
done
cd - > /dev/null || exit 1

echo ""
echo "=== 正确方法：for in 通配符 ==="
for file in "$TESTDIR"/*; do
    filename=$(basename "$file")
    echo "  遍历到: [$filename]"
    [[ -e "$file" ]] && echo "    -> 文件存在"
done

# 清理
rm -rf "$TESTDIR"

echo ""
echo "结论：永远不要使用 for in \$(ls)，使用通配符 for in * 代替"
