# Lesson 01 - 容器 vs 虚拟机：代码文件

本目录包含 Lesson 01 的演示脚本。

## 文件列表

| 文件 | 用途 | 权限要求 |
|------|------|----------|
| `isolation-demo.sh` | 综合隔离演示（Network/PID/UTS/Mount） | sudo |
| `kernel-verify.sh` | 验证容器与宿主机共享内核 | sudo |
| `process-visibility.sh` | 演示容器进程在宿主机可见 | sudo |

## 使用方法

### 综合演示

```bash
# 运行所有自动演示
sudo ./isolation-demo.sh --all

# 进入交互式隔离环境
sudo ./isolation-demo.sh --interactive
```

### 内核验证

```bash
sudo ./kernel-verify.sh
```

### 进程可见性

```bash
sudo ./process-visibility.sh
```

## 环境要求

- Linux 系统（推荐 Ubuntu 22.04+ / RHEL 9+）
- root 权限（使用 sudo）
- 内核版本 5.x+（支持完整 Namespace 功能）

## 核心命令速查

```bash
# 创建网络隔离环境
sudo unshare --net bash

# 创建 PID 隔离环境
sudo unshare --pid --fork --mount-proc bash

# 创建完整隔离环境
sudo unshare --pid --net --uts --mount --fork --mount-proc bash

# 查看进程的 namespace
ls -la /proc/$$/ns/

# 验证内核版本
uname -r
```

## 清理

所有演示脚本会自动清理创建的资源。如需手动清理：

```bash
# 查找并终止残留的隔离进程
pgrep -f "unshare" | xargs -r sudo kill
```
