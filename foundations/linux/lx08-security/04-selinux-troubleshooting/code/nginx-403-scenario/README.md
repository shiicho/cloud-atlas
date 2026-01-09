# Nginx 403 SELinux 场景

这是一个 SELinux 排错练习场景。

## 场景描述

你是一名运维工程师，接到任务将 Web 内容从默认目录迁移到独立分区 `/data/www`。

迁移后，Nginx 返回 403 Forbidden，即使：
- 文件权限正确（755/644）
- Nginx 配置语法正确
- 文件确实存在

## 使用方法

### 1. 设置场景

```bash
sudo bash setup.sh
```

这会：
- 安装 Nginx（如果需要）
- 创建 `/data/www` 目录和测试页面
- 修改 Nginx 配置指向新目录
- 制造 SELinux 问题

### 2. 自己动手排错

使用以下工具诊断问题：

```bash
# 搜索 AVC 拒绝
ausearch -m avc -ts recent

# 理解拒绝原因
ausearch -m avc -ts recent | audit2why

# 查看文件上下文
ls -Z /data/www/

# 对比正常目录
ls -Z /usr/share/nginx/html/
```

### 3. 修复问题

提示：需要使用 `semanage fcontext` 和 `restorecon`。

### 4. 查看解决方案

如果卡住了：

```bash
cat solution.sh

# 或者直接运行解决方案
sudo bash solution.sh
```

## 学习目标

完成这个练习后，你应该能够：

1. 使用 `ausearch` 搜索 SELinux 拒绝
2. 使用 `audit2why` 理解拒绝原因
3. 使用 `semanage fcontext` 添加永久上下文规则
4. 使用 `restorecon` 应用规则
5. 解释为什么 `chcon` 不是永久解决方案

## 清理

```bash
# 恢复 Nginx 默认配置
sudo cp /etc/nginx/nginx.conf.bak /etc/nginx/nginx.conf
sudo systemctl restart nginx

# 删除测试目录
sudo rm -rf /data/www

# 删除 fcontext 规则
sudo semanage fcontext -d "/data/www(/.*)?" 2>/dev/null
```
