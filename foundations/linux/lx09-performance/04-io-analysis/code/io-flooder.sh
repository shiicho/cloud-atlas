#!/bin/bash
# ============================================================
# io-flooder.sh - I/O 负载模拟脚本（坏演员）
# ============================================================
#
# 用途: 模拟 I/O 问题，供学员练习诊断技能
#
# 模式:
#   random  - 随机小块 I/O（模拟数据库负载）
#   sequential - 顺序大块写入（模拟备份/日志）
#   sync - 同步写入风暴（模拟数据库 fsync）
#
# 用法:
#   ./io-flooder.sh random 60      # 随机 I/O，60 秒
#   ./io-flooder.sh sequential 30  # 顺序写入，30 秒
#   ./io-flooder.sh sync 30        # 同步写入，30 秒
#
# 警告: 此脚本会产生大量 I/O，仅用于测试环境！
#
# ============================================================

MODE=${1:-random}
DURATION=${2:-30}
TEMP_DIR="${3:-/tmp/io-flooder-$$}"

# 清理函数
cleanup() {
    echo ""
    echo "清理临时文件..."
    rm -rf "$TEMP_DIR"
    echo "已停止"
    exit 0
}

trap cleanup SIGINT SIGTERM

echo "============================================"
echo "  I/O Flooder - 负载模拟器"
echo "============================================"
echo "模式: $MODE"
echo "时长: $DURATION 秒"
echo "临时目录: $TEMP_DIR"
echo ""
echo "按 Ctrl+C 停止"
echo "============================================"
echo ""

mkdir -p "$TEMP_DIR"

case $MODE in
    random)
        # 模拟数据库随机 I/O
        echo "模式: 随机小块 I/O（模拟数据库查询）"
        echo "特征: 高 IOPS，低 throughput，高 await"
        echo ""

        START_TIME=$(date +%s)
        COUNT=0

        while [ $(($(date +%s) - START_TIME)) -lt $DURATION ]; do
            # 随机位置写入小块数据
            dd if=/dev/urandom of="$TEMP_DIR/random_$RANDOM" bs=4K count=1 2>/dev/null
            COUNT=$((COUNT + 1))

            # 随机延迟
            usleep $((RANDOM % 1000)) 2>/dev/null || sleep 0.001
        done

        echo "完成: 写入 $COUNT 个 4KB 随机块"
        ;;

    sequential)
        # 模拟备份/日志顺序写入
        echo "模式: 顺序大块写入（模拟备份任务）"
        echo "特征: 低 IOPS，高 throughput"
        echo ""

        START_TIME=$(date +%s)
        TOTAL_MB=0

        while [ $(($(date +%s) - START_TIME)) -lt $DURATION ]; do
            # 顺序写入 10MB 块
            dd if=/dev/zero of="$TEMP_DIR/sequential_$(date +%s)" bs=1M count=10 2>/dev/null
            TOTAL_MB=$((TOTAL_MB + 10))

            # 删除旧文件避免磁盘满
            find "$TEMP_DIR" -name "sequential_*" -mmin +1 -delete 2>/dev/null
        done

        echo "完成: 写入约 ${TOTAL_MB} MB 顺序数据"
        ;;

    sync)
        # 模拟数据库 fsync 风暴
        echo "模式: 同步写入（模拟数据库事务提交）"
        echo "特征: 低 IOPS（受 fsync 限制），高 await"
        echo "警告: 这会显著影响系统 I/O 性能！"
        echo ""

        START_TIME=$(date +%s)
        COUNT=0
        FILE="$TEMP_DIR/sync_test"

        while [ $(($(date +%s) - START_TIME)) -lt $DURATION ]; do
            # 写入并强制刷盘
            echo "Transaction $COUNT at $(date +%T)" >> "$FILE"
            sync "$FILE" 2>/dev/null || sync

            COUNT=$((COUNT + 1))
        done

        echo "完成: $COUNT 次同步写入"
        ;;

    mixed)
        # 混合负载
        echo "模式: 混合负载（随机读 + 顺序写）"
        echo ""

        START_TIME=$(date +%s)

        # 先创建读取源文件
        dd if=/dev/urandom of="$TEMP_DIR/read_source" bs=1M count=100 2>/dev/null

        while [ $(($(date +%s) - START_TIME)) -lt $DURATION ]; do
            # 随机读取
            dd if="$TEMP_DIR/read_source" of=/dev/null bs=4K count=1 skip=$((RANDOM % 25600)) 2>/dev/null &

            # 顺序写入
            dd if=/dev/zero of="$TEMP_DIR/write_seq" bs=64K count=10 conv=notrunc 2>/dev/null &

            wait
        done

        echo "完成: 混合负载测试"
        ;;

    *)
        echo "未知模式: $MODE"
        echo ""
        echo "可用模式:"
        echo "  random     - 随机小块 I/O（数据库场景）"
        echo "  sequential - 顺序大块写入（备份场景）"
        echo "  sync       - 同步写入风暴（事务场景）"
        echo "  mixed      - 混合负载"
        exit 1
        ;;
esac

cleanup
