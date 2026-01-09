# Lesson 04 代码文件

本目录包含 User Namespace 与 Rootless 容器课程的演示脚本。

## 文件说明

| 文件 | 用途 | 权限要求 |
|------|------|----------|
| `uid-mapping-demo.sh` | 演示 User Namespace UID 映射机制 | 普通用户 |
| `rootless-setup.sh` | 配置 rootless 容器环境（subuid/subgid） | sudo |
| `security-audit-demo.sh` | 生成安全审计证据报告 | 普通用户 |

## 使用方法

### 1. UID 映射演示

```bash
chmod +x uid-mapping-demo.sh
./uid-mapping-demo.sh
```

演示内容：
- 创建 User Namespace 并成为 "root"
- 显示 UID 映射
- 证明权限限制

### 2. Rootless 环境配置

```bash
chmod +x rootless-setup.sh
sudo ./rootless-setup.sh [username]
```

配置内容：
- 启用 user namespaces
- 配置 /etc/subuid
- 配置 /etc/subgid
- 验证配置

### 3. 安全审计演示

```bash
chmod +x security-audit-demo.sh

# 分析运行中的容器
./security-audit-demo.sh mycontainer

# 或分析特定 PID
./security-audit-demo.sh 12345
```

输出内容：
- UID/GID 映射分析
- 宿主机进程权限
- 日语/中文格式的审计报告

## 环境要求

- Linux 内核 3.8+（User Namespace 支持）
- `unshare` 命令（util-linux 包）
- （可选）Podman 或 Docker
- （可选）sudo 权限（用于 rootless-setup.sh）

## 注意事项

1. **User Namespace 启用**：某些系统默认禁用 user namespaces
   ```bash
   cat /proc/sys/user/max_user_namespaces
   # 如果是 0，需要启用
   ```

2. **subuid/subgid 配置**：rootless 容器需要配置这些文件
   ```bash
   cat /etc/subuid
   cat /etc/subgid
   ```

3. **安全审计脚本**：需要有运行中的容器才能分析

## 相关课程

- [Lesson 03 - Namespace 深入](../03-namespace-deep-dive/)
- [Lesson 09 - 容器安全](../09-container-security/)
