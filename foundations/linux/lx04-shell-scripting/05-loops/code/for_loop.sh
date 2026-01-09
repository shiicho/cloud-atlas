#!/bin/bash
# =============================================================================
# 脚本名称: for_loop.sh
# 功能说明: for 循环的各种用法演示
# 课程: LX04-SHELL Lesson 05 - 循环结构
# =============================================================================

echo "=== 1. 列表迭代 ==="
for fruit in apple banana orange; do
    echo "水果: $fruit"
done

echo ""
echo "=== 2. 花括号展开 ==="
for num in {1..5}; do
    echo "数字: $num"
done

echo ""
echo "=== 3. 带步长展开 ==="
for even in {0..10..2}; do
    echo "偶数: $even"
done

echo ""
echo "=== 4. C 风格循环 ==="
for ((i = 0; i < 5; i++)); do
    echo "i = $i"
done

echo ""
echo "=== 5. 数组遍历 ==="
servers=("web01" "web02" "db01")
for server in "${servers[@]}"; do
    echo "服务器: $server"
done

echo ""
echo "=== 6. 通配符遍历文件（正确方式）==="
# 遍历当前目录的 .sh 文件
for file in *.sh; do
    [[ -e "$file" ]] || continue
    echo "脚本: $file"
done
