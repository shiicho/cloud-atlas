#!/bin/bash
#
# env-vs-local.sh - 环境变量 vs Shell 变量演示
#
# 演示 export 对变量可见性的影响
#

echo "=== 环境变量 vs Shell 变量 ==="
echo ""

# 1. 设置 Shell 变量（不 export）
LOCAL_VAR="I am a local shell variable"

# 2. 设置环境变量（export）
export ENV_VAR="I am an exported environment variable"

echo "--- 在当前 Shell 中 ---"
echo "LOCAL_VAR: $LOCAL_VAR"
echo "ENV_VAR: $ENV_VAR"

echo ""
echo "--- 在子 Shell 中（bash -c）---"
echo "LOCAL_VAR 在子 Shell: $(bash -c 'echo $LOCAL_VAR')"
echo "ENV_VAR 在子 Shell: $(bash -c 'echo $ENV_VAR')"

echo ""
echo "--- 解释 ---"
echo "LOCAL_VAR 没有 export，所以子进程看不到"
echo "ENV_VAR 用 export 导出，所以子进程可以继承"

echo ""
echo "=== export 的两种写法 ==="

# 写法 1：声明时 export
export METHOD1="declared with export"

# 写法 2：先声明后 export
METHOD2="declared first"
export METHOD2

echo "METHOD1: $METHOD1"
echo "METHOD2: $METHOD2"

echo ""
echo "=== 查看所有环境变量 ==="
echo "使用 env 命令可以查看所有环境变量"
echo "常见环境变量："
echo "  USER=$USER"
echo "  HOME=$HOME"
echo "  PATH=$PATH"
echo "  SHELL=$SHELL"
echo "  PWD=$PWD"

echo ""
echo "=== 删除变量 ==="
MY_TEMP="temporary"
echo "删除前: MY_TEMP=$MY_TEMP"
unset MY_TEMP
echo "删除后: MY_TEMP=$MY_TEMP (空)"

echo ""
echo "=== 脚本执行完成 ==="
