#!/bin/bash
# =============================================================================
# setup.sh - Nginx 403 SELinux 场景设置脚本
# =============================================================================
#
# 用途：制造一个 SELinux 导致的 Nginx 403 Forbidden 问题
# 前提：
#   - RHEL/Rocky/Alma Linux 9
#   - SELinux Enforcing 模式
#   - 以 root 运行
#
# 这个脚本会：
#   1. 安装 Nginx（如果没有）
#   2. 创建 /data/www 目录和测试页面
#   3. 修改 Nginx 配置指向新目录
#   4. 重启 Nginx
#   5. 演示 403 错误
#
# 目的：让学员体验 SELinux 文件上下文导致的访问问题
#
# =============================================================================

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== SELinux Nginx 403 场景设置 ===${NC}"
echo ""

# 检查 root 权限
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}错误：请以 root 用户运行此脚本${NC}"
   echo "使用: sudo bash setup.sh"
   exit 1
fi

# 检查 SELinux 模式
SELINUX_MODE=$(getenforce)
echo -e "${YELLOW}当前 SELinux 模式: ${SELINUX_MODE}${NC}"

if [[ "$SELINUX_MODE" == "Disabled" ]]; then
    echo -e "${RED}错误：SELinux 已禁用，无法进行此实验${NC}"
    echo "请在 /etc/selinux/config 中设置 SELINUX=enforcing 并重启"
    exit 1
fi

if [[ "$SELINUX_MODE" == "Permissive" ]]; then
    echo -e "${YELLOW}警告：SELinux 是 Permissive 模式${NC}"
    echo "切换到 Enforcing 模式..."
    setenforce 1
    echo -e "${GREEN}已切换到 Enforcing 模式${NC}"
fi

# 安装 Nginx
echo ""
echo -e "${BLUE}Step 1: 安装 Nginx...${NC}"
if ! command -v nginx &> /dev/null; then
    dnf install -y nginx
    echo -e "${GREEN}Nginx 安装完成${NC}"
else
    echo -e "${GREEN}Nginx 已安装${NC}"
fi

# 安装 setroubleshoot（用于 sealert）
echo ""
echo -e "${BLUE}Step 2: 安装 SELinux 排错工具...${NC}"
dnf install -y setroubleshoot-server policycoreutils-python-utils &> /dev/null || true
echo -e "${GREEN}排错工具就绪${NC}"

# 创建测试目录和文件
echo ""
echo -e "${BLUE}Step 3: 创建测试目录 /data/www...${NC}"
mkdir -p /data/www
cat > /data/www/index.html << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>SELinux Test Page</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; }
        h1 { color: #2e7d32; }
        .info { background: #e8f5e9; padding: 20px; border-radius: 8px; }
    </style>
</head>
<body>
    <h1>Welcome from /data/www!</h1>
    <div class="info">
        <p>If you can see this page, you have successfully fixed the SELinux file context issue.</p>
        <p>Congratulations on completing the SELinux troubleshooting exercise!</p>
    </div>
</body>
</html>
EOF

# 设置 DAC 权限（这些是正确的）
chmod 755 /data
chmod 755 /data/www
chmod 644 /data/www/index.html

echo -e "${GREEN}测试目录创建完成${NC}"

# 备份并修改 Nginx 配置
echo ""
echo -e "${BLUE}Step 4: 修改 Nginx 配置...${NC}"
if [[ ! -f /etc/nginx/nginx.conf.bak ]]; then
    cp /etc/nginx/nginx.conf /etc/nginx/nginx.conf.bak
    echo -e "${GREEN}已备份原配置到 nginx.conf.bak${NC}"
fi

# 替换 root 目录
sed -i 's|root         /usr/share/nginx/html;|root         /data/www;|g' /etc/nginx/nginx.conf
echo -e "${GREEN}Nginx 配置已修改，root 指向 /data/www${NC}"

# 检查配置语法
echo ""
echo -e "${BLUE}Step 5: 检查 Nginx 配置语法...${NC}"
nginx -t
echo -e "${GREEN}Nginx 配置语法正确${NC}"

# 重启 Nginx
echo ""
echo -e "${BLUE}Step 6: 重启 Nginx...${NC}"
systemctl restart nginx
systemctl enable nginx &> /dev/null
echo -e "${GREEN}Nginx 已重启${NC}"

# 展示问题
echo ""
echo -e "${BLUE}=== 场景设置完成 ===${NC}"
echo ""
echo -e "${YELLOW}现在测试访问:${NC}"
echo ""
curl -s http://localhost/ | head -5
echo ""
echo -e "${RED}如果看到 403 Forbidden，说明场景设置成功！${NC}"
echo ""
echo -e "${BLUE}=== 排错提示 ===${NC}"
echo ""
echo "你的任务是找出并修复 SELinux 问题。"
echo ""
echo "提示命令："
echo "  1. ausearch -m avc -ts recent"
echo "  2. ls -Z /data/www/"
echo "  3. ls -Z /usr/share/nginx/html/"
echo "  4. semanage fcontext -a -t ... \"/data/www(/.*)?\" "
echo "  5. restorecon -Rv /data/www"
echo ""
echo "解决方案在 solution.sh 文件中（尽量先自己尝试！）"
echo ""
