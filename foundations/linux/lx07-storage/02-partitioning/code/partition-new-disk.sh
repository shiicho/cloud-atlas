#!/bin/bash
# =============================================================================
# partition-new-disk.sh - 标准化新磁盘分区脚本
# =============================================================================
#
# 使用 sgdisk 自动创建标准 GPT 分区布局：
#   - 分区 1: EFI System (512MB)
#   - 分区 2: Boot (1GB)
#   - 分区 3: LVM (剩余空间)
#
# Usage: ./partition-new-disk.sh /dev/sdX
#
# WARNING: 此脚本会销毁目标磁盘上的所有数据！
#
# =============================================================================

set -e

DISK=$1

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 检查参数
if [ -z "$DISK" ]; then
    echo -e "${RED}Error: No disk specified${NC}"
    echo "Usage: $0 /dev/sdX"
    echo ""
    echo "Example:"
    echo "  $0 /dev/sdb      # Partition /dev/sdb"
    echo "  $0 /dev/loop1    # Partition loop device (for testing)"
    exit 1
fi

# 检查设备是否存在
if [ ! -b "$DISK" ]; then
    echo -e "${RED}Error: $DISK is not a block device${NC}"
    exit 1
fi

# 检查是否为 root
if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}Error: This script must be run as root${NC}"
    exit 1
fi

# 检查 sgdisk 是否可用
if ! command -v sgdisk &> /dev/null; then
    echo -e "${RED}Error: sgdisk not found. Please install gdisk package.${NC}"
    echo "  Ubuntu/Debian: apt install gdisk"
    echo "  RHEL/CentOS:   yum install gdisk"
    exit 1
fi

# 安全确认
echo -e "${YELLOW}========================================${NC}"
echo -e "${YELLOW}WARNING: This will DESTROY all data on $DISK${NC}"
echo -e "${YELLOW}========================================${NC}"
echo ""
echo "Current partition table:"
sgdisk -p "$DISK" 2>/dev/null || echo "(No partition table found)"
echo ""
echo -e "${RED}Are you sure you want to continue? (type 'yes' to confirm)${NC}"
read -r confirm

if [ "$confirm" != "yes" ]; then
    echo "Aborted."
    exit 0
fi

echo ""
echo -e "${GREEN}Partitioning $DISK with standard GPT layout...${NC}"

# 执行分区
# -Z: Zap (destroy) the GPT and MBR data structures
# -n: New partition (number:start:end)
# -t: Set partition type
# -c: Set partition name
sgdisk -Z \
    -n 1:0:+512M -t 1:ef00 -c 1:"EFI System" \
    -n 2:0:+1G   -t 2:8300 -c 2:"Boot" \
    -n 3:0:0     -t 3:8e00 -c 3:"LVM" \
    "$DISK"

# 通知内核重新读取分区表
partprobe "$DISK" 2>/dev/null || true

echo ""
echo -e "${GREEN}Partition table created successfully:${NC}"
sgdisk -p "$DISK"

echo ""
echo -e "${GREEN}Next steps:${NC}"
echo "  1. Create filesystems:"
echo "     mkfs.vfat -F32 ${DISK}1        # EFI"
echo "     mkfs.ext4 ${DISK}2             # Boot"
echo "     pvcreate ${DISK}3              # LVM PV"
echo ""
echo "  2. Or view with:"
echo "     lsblk $DISK"
echo "     blkid | grep $DISK"
