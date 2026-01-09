#!/bin/bash
# =============================================================================
# 脚本名称: while_read.sh
# 功能说明: 正确读取文件的方法演示
# 课程: LX04-SHELL Lesson 05 - 循环结构
# =============================================================================
#
# 关键点:
#   IFS=    保留行首尾空白
#   -r      不解释反斜杠
#   < file  从文件重定向输入（避免子 shell 问题）
#
# =============================================================================

# 创建测试数据
TESTFILE=$(mktemp)
cat > "$TESTFILE" << 'EOF'
  Line with leading spaces
Line with \n escape
Normal line
	Line with tab
EOF

echo "测试文件内容："
cat -A "$TESTFILE"
echo ""

echo "=== 错误方法：不用 IFS= 和 -r ==="
while read line; do
    echo "[$line]"
done < "$TESTFILE"

echo ""
echo "=== 正确方法：使用 IFS= 和 -r ==="
while IFS= read -r line; do
    echo "[$line]"
done < "$TESTFILE"

echo ""
echo "=== 读取带分隔符的数据（CSV）==="
CSV_DATA="alice,alice@example.com,admin
bob,bob@example.com,user
charlie,charlie@example.com,user"

while IFS=, read -r username email role; do
    echo "用户: $username, 邮箱: $email, 角色: $role"
done <<< "$CSV_DATA"

echo ""
echo "=== 从命令输出读取（进程替换）==="
count=0
while IFS= read -r line; do
    ((count++))
done < <(echo -e "line1\nline2\nline3")
echo "行数: $count"

# 清理
rm -f "$TESTFILE"
