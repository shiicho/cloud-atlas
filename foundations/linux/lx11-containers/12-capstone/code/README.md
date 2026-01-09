# Capstone 代码文件

从零构建容器的脚手架脚本和完整构建脚本。

## 文件说明

| 文件 | 用途 |
|------|------|
| `build-container.sh` | 完整构建脚本，组合所有步骤 |
| `scaffold-namespace.sh` | Namespace 创建脚手架 |
| `scaffold-cgroup.sh` | cgroups v2 配置脚手架 |
| `scaffold-network.sh` | 容器网络配置脚手架 |

## 快速开始

```bash
# 1. 准备 rootfs
mkdir -p ~/container-lab/rootfs
cd ~/container-lab
curl -o alpine.tar.gz \
  https://dl-cdn.alpinelinux.org/alpine/v3.19/releases/x86_64/alpine-minirootfs-3.19.0-x86_64.tar.gz
tar -xzf alpine.tar.gz -C rootfs

# 2. 复制脚本
cp /path/to/code/*.sh ~/container-lab/

# 3. 运行完整构建
cd ~/container-lab
sudo ./build-container.sh
```

## 脚手架脚本用法

### scaffold-namespace.sh

处理 Namespace 创建的常见陷阱：

```bash
sudo ./scaffold-namespace.sh <rootfs-path> [container-name] [command]

# 示例
sudo ./scaffold-namespace.sh /tmp/container/merged my-container /bin/sh
```

**处理的陷阱**：
- `--fork --pid` 组合的正确顺序
- `/proc` 挂载时机
- `pivot_root` 参数顺序

### scaffold-cgroup.sh

处理 cgroups v2 配置：

```bash
sudo ./scaffold-cgroup.sh <cgroup-name> [memory-limit] [cpu-percent] [pid]

# 示例
sudo ./scaffold-cgroup.sh my-container 256M 50 12345
```

**处理的陷阱**：
- 检测 cgroup v2 挂载点
- 正确写入 `memory.max` 和 `cpu.max`
- 将进程加入 cgroup

### scaffold-network.sh

处理容器网络配置：

```bash
sudo ./scaffold-network.sh <action> [options]

# 设置网络
sudo ./scaffold-network.sh setup --pid 12345 --name my-container

# 清理网络
sudo ./scaffold-network.sh cleanup --name my-container

# 查看状态
sudo ./scaffold-network.sh status
```

**处理的陷阱**：
- veth pair 创建和命名
- bridge 设置
- nftables NAT 规则（不是 iptables）
- IP 转发启用

## 手动构建步骤

如果想完全手动构建，参考以下步骤：

```bash
# Phase 1: Filesystem (OverlayFS)
mkdir -p /tmp/container/{lower,upper,work,merged}
cp -a rootfs/* /tmp/container/lower/
mount -t overlay overlay \
  -o lowerdir=/tmp/container/lower,upperdir=/tmp/container/upper,workdir=/tmp/container/work \
  /tmp/container/merged

# Phase 2: Namespaces
unshare --pid --fork --mount --uts --net --ipc /bin/sh

# Phase 3: Network (在宿主机执行)
ip link add br0 type bridge
ip addr add 172.20.0.1/24 dev br0
ip link set br0 up
# ... 更多网络配置

# Phase 4: Resource Limits
mkdir /sys/fs/cgroup/my-container
echo "256M" > /sys/fs/cgroup/my-container/memory.max
echo "50000 100000" > /sys/fs/cgroup/my-container/cpu.max

# Phase 5: Run
pivot_root . oldroot
mount -t proc proc /proc
exec /bin/sh
```

## 清理

```bash
# 使用构建脚本清理
sudo ./build-container.sh --cleanup

# 或手动清理
sudo ip link del br-container
sudo nft delete table ip container-nat
sudo rmdir /sys/fs/cgroup/container-my-container
sudo umount /tmp/container-*/merged
sudo rm -rf /tmp/container-*
```

## 学习建议

1. **先运行 `build-container.sh`**，验证容器可以工作
2. **阅读脚手架脚本**，理解每个步骤的作用
3. **手动执行每一步**，加深理解
4. **故意制造错误**，学习排查技巧

## 常见问题

### Q: unshare 后 ps 显示宿主机进程

**原因**：忘记挂载 `/proc`

**解决**：在新 PID namespace 中执行 `mount -t proc proc /proc`

### Q: pivot_root 报错 "invalid argument"

**原因**：`oldroot` 目录不在新根目录内

**解决**：在执行 `pivot_root` 前 `cd` 到新根目录，然后 `mkdir oldroot`

### Q: 容器无法访问外网

**检查清单**：
1. IP 转发是否启用？`cat /proc/sys/net/ipv4/ip_forward`
2. NAT 规则是否存在？`nft list table ip container-nat`
3. 容器路由是否正确？`ip route`

### Q: cgroup 限制不生效

**检查**：
1. 确认是 cgroup v2：`mount | grep cgroup2`
2. 检查进程是否在 cgroup 中：`cat /sys/fs/cgroup/<name>/cgroup.procs`
