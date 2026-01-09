#!/bin/bash
# =============================================================================
# 脚本名称: for_glob.sh
# 功能说明: 正确遍历文件的方法（最佳实践）
# 课程: LX04-SHELL Lesson 05 - 循环结构
# =============================================================================
#
# 最佳实践:
#   1. 使用通配符而不是 $(ls)
#   2. 检查文件存在性
#   3. 引用变量
#   4. 使用 nullglob 处理无匹配情况
#
# =============================================================================

# 创建测试环境
TESTDIR=$(mktemp -d)
touch "$TESTDIR/normal.txt"
touch "$TESTDIR/with space.txt"
touch "$TESTDIR/report_2025.log"

echo "测试目录: $TESTDIR"
echo ""

echo "=== 方法 1：基本通配符遍历 ==="
for file in "$TESTDIR"/*.txt; do
    # 检查文件是否存在（处理无匹配的情况）
    [[ -e "$file" ]] || continue
    echo "TXT 文件: $(basename "$file")"
done

echo ""
echo "=== 方法 2：使用 nullglob ==="
shopt -s nullglob  # 无匹配时返回空列表
for file in "$TESTDIR"/*.xyz; do
    echo "XYZ 文件: $(basename "$file")"
done
echo "(没有 .xyz 文件，循环不执行)"
shopt -u nullglob

echo ""
echo "=== 方法 3：多类型文件 ==="
for file in "$TESTDIR"/*.txt "$TESTDIR"/*.log; do
    [[ -e "$file" ]] || continue
    echo "文件: $(basename "$file")"
done

echo ""
echo "=== 方法 4：递归遍历（使用 globstar）==="
# 创建子目录结构
mkdir -p "$TESTDIR/subdir"
touch "$TESTDIR/subdir/nested.txt"

shopt -s globstar nullglob
for file in "$TESTDIR"/**/*.txt; do
    echo "递归找到: ${file#$TESTDIR/}"
done
shopt -u globstar nullglob

echo ""
echo "=== 方法 5：find + while read（复杂场景）==="
find "$TESTDIR" -type f -name "*.txt" -print0 | while IFS= read -r -d '' file; do
    echo "Find 找到: ${file#$TESTDIR/}"
done

# 清理
rm -rf "$TESTDIR"
