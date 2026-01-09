#!/bin/bash
# =============================================================================
# simulate_app.sh - 模拟产生 stdout 和 stderr 的应用程序
# =============================================================================
#
# 用途：
#   演示重定向和管道如何处理不同的输出流
#
# 运行方式：
#   ./simulate_app.sh                    # 正常运行
#   ./simulate_app.sh > out.log 2> err.log  # 分离输出
#   ./simulate_app.sh 2>&1 | tee all.log    # 合并并保存
#
# =============================================================================

echo "[INFO] Application starting..."

for i in {1..10}; do
    # 每隔 3 次产生一个错误（输出到 stderr）
    if [ $((i % 3)) -eq 0 ]; then
        echo "[ERROR] Something went wrong at iteration $i" >&2
    else
        echo "[INFO] Processing iteration $i"
    fi
    sleep 0.5
done

echo "[INFO] Application finished successfully"
exit 0
