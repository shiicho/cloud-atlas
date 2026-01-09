#!/bin/bash
# =============================================================================
# solution.sh - Nginx 403 SELinux 场景解决方案
# =============================================================================
#
# 这个脚本展示如何正确诊断和修复 SELinux 文件上下文问题
#
# 学习目标：
#   1. 使用 ausearch 查找 AVC 拒绝
#   2. 使用 audit2why 理解拒绝原因
#   3. 使用 semanage fcontext 添加永久规则
#   4. 使用 restorecon 应用规则
#
# =============================================================================

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== SELinux Nginx 403 问题解决方案 ===${NC}"
echo ""

# 检查 root 权限
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}错误：请以 root 用户运行此脚本${NC}"
   echo "使用: sudo bash solution.sh"
   exit 1
fi

# Step 1: 诊断 - 查看 AVC 拒绝
echo -e "${CYAN}Step 1: 诊断 - 查找 AVC 拒绝${NC}"
echo ""
echo -e "${YELLOW}命令: ausearch -m avc -ts recent | head -20${NC}"
echo ""
ausearch -m avc -ts recent 2>/dev/null | head -20 || echo "(可能没有最近的拒绝记录)"
echo ""

# Step 2: 理解原因
echo -e "${CYAN}Step 2: 理解拒绝原因${NC}"
echo ""
echo -e "${YELLOW}命令: ausearch -m avc -ts recent | audit2why | head -20${NC}"
echo ""
ausearch -m avc -ts recent 2>/dev/null | audit2why 2>/dev/null | head -20 || echo "(可能没有最近的拒绝记录)"
echo ""

# Step 3: 对比上下文
echo -e "${CYAN}Step 3: 对比文件上下文${NC}"
echo ""
echo -e "${YELLOW}问题目录 /data/www:${NC}"
ls -Zd /data/www/ 2>/dev/null || echo "/data/www 不存在"
ls -Z /data/www/ 2>/dev/null || echo "/data/www 不存在"
echo ""
echo -e "${YELLOW}正常目录 /usr/share/nginx/html:${NC}"
ls -Zd /usr/share/nginx/html/ 2>/dev/null
ls -Z /usr/share/nginx/html/ 2>/dev/null | head -5
echo ""
echo -e "${GREEN}发现问题：/data/www 的类型是 default_t，应该是 httpd_sys_content_t${NC}"
echo ""

# Step 4: 永久修复
echo -e "${CYAN}Step 4: 永久修复 - 添加 fcontext 规则${NC}"
echo ""
echo -e "${YELLOW}命令: semanage fcontext -a -t httpd_sys_content_t \"/data/www(/.*)?\"${NC}"
echo ""

# 先删除可能存在的规则（避免重复添加错误）
semanage fcontext -d "/data/www(/.*)?" 2>/dev/null || true

# 添加规则
semanage fcontext -a -t httpd_sys_content_t "/data/www(/.*)?"
echo -e "${GREEN}fcontext 规则已添加${NC}"
echo ""

# Step 5: 应用规则
echo -e "${CYAN}Step 5: 应用规则 - restorecon${NC}"
echo ""
echo -e "${YELLOW}命令: restorecon -Rv /data/www${NC}"
echo ""
restorecon -Rv /data/www
echo ""

# Step 6: 验证上下文
echo -e "${CYAN}Step 6: 验证文件上下文${NC}"
echo ""
echo -e "${YELLOW}修复后 /data/www:${NC}"
ls -Z /data/www/
echo ""
echo -e "${GREEN}文件类型已变为 httpd_sys_content_t${NC}"
echo ""

# Step 7: 测试访问
echo -e "${CYAN}Step 7: 测试 Web 访问${NC}"
echo ""
echo -e "${YELLOW}命令: curl http://localhost/${NC}"
echo ""
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost/)
if [[ "$HTTP_CODE" == "200" ]]; then
    echo -e "${GREEN}HTTP 响应码: $HTTP_CODE - 成功！${NC}"
    echo ""
    echo "页面内容:"
    curl -s http://localhost/ | grep -E "<h1>|<p>" | sed 's/<[^>]*>//g' | head -5
else
    echo -e "${RED}HTTP 响应码: $HTTP_CODE - 仍有问题${NC}"
    echo "请检查 Nginx 日志: journalctl -u nginx"
fi
echo ""

# Step 8: 验证永久性
echo -e "${CYAN}Step 8: 验证修复是永久的${NC}"
echo ""
echo -e "${YELLOW}模拟 restorecon（系统维护时会运行）:${NC}"
restorecon -Rv /data/www
echo ""
echo -e "${YELLOW}再次检查上下文:${NC}"
ls -Z /data/www/
echo ""
echo -e "${GREEN}上下文仍然正确！修复是永久的。${NC}"
echo ""

# 展示规则
echo -e "${CYAN}=== 查看添加的规则 ===${NC}"
echo ""
echo -e "${YELLOW}命令: semanage fcontext -l | grep /data/www${NC}"
semanage fcontext -l | grep /data/www
echo ""

# 总结
echo -e "${BLUE}=== 解决方案总结 ===${NC}"
echo ""
echo "关键命令序列:"
echo ""
echo "  # 1. 诊断"
echo "  ausearch -m avc -ts recent"
echo "  ausearch -m avc -ts recent | audit2why"
echo ""
echo "  # 2. 永久修复"
echo "  semanage fcontext -a -t httpd_sys_content_t \"/data/www(/.*)?\""
echo "  restorecon -Rv /data/www"
echo ""
echo "  # 3. 验证"
echo "  ls -Z /data/www/"
echo "  curl http://localhost/"
echo ""
echo -e "${YELLOW}记住：semanage fcontext 是永久修复，chcon 是临时修复！${NC}"
echo ""
