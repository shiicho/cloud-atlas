# MOTD（Message of the Day）

**TL;DR**：Linux 登录后显示的「当天信息/登录横幅」。用于欢迎语、维护公告、合规提示或安全告警。

## 在哪里出现？
- 交互式登录：SSH、控制台 TTY、通常也包括 SSM Session Manager 的登录 Shell。

## 在系统里的位置
- 早期/静态：`/etc/motd`（单个文本）
- 现代/分片：`/etc/motd.d/`（按文件名顺序拼接展示）
- 一些发行版（如 Ubuntu/Debian）还支持 `update-motd`：`/etc/update-motd.d/` 脚本动态生成

## 在 Amazon Linux 2023（本课程环境）
支持 **`/etc/motd.d/`** 分片。把一段文本保存为文件（如 `10-cloud-atlas`），即可与系统默认横幅一起显示，**不覆盖系统文件**，更安全。

## 注意
- MOTD 对所有用户可见，**不要**放密钥等敏感信息
- 建议简短（10 行内），避免慢脚本

## 试一试
```bash
# 查看当前 MOTD
cat /etc/motd 2>/dev/null || true
sudo ls -1 /etc/motd.d || true

# 删除本课程写入的分片（如需还原）
sudo rm -f /etc/motd.d/10-cloud-atlas
```