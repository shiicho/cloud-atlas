# Lesson 06 - cgroups v2 资源限制实战：代码文件

本目录包含 Lesson 06 的演示脚本。

## 文件列表

| 文件 | 说明 | 用法 |
|------|------|------|
| `memory-limit-demo.sh` | 内存限制演示（memory.high vs memory.max） | `sudo ./memory-limit-demo.sh` |
| `cpu-throttle-demo.sh` | CPU 限制演示（cpu.max） | `sudo ./cpu-throttle-demo.sh` |

## 前置要求

1. **cgroups v2 已启用**
   - Ubuntu 22.04+, RHEL 9+, Fedora 31+ 默认启用
   - 检查：`mount | grep cgroup2`

2. **stress 工具已安装**
   ```bash
   # Ubuntu/Debian
   sudo apt-get install -y stress

   # RHEL/CentOS
   sudo dnf install -y stress
   ```

3. **root 权限**
   - 创建 cgroup 需要 root 权限
   - 使用 `sudo` 运行脚本

## 使用方法

```bash
# 克隆仓库（如果还没有）
git clone --filter=blob:none --sparse https://github.com/shiicho/cloud-atlas ~/cloud-atlas
cd ~/cloud-atlas && git sparse-checkout set foundations/linux/containers

# 进入代码目录
cd ~/cloud-atlas/foundations/linux/lx11-containers/06-cgroups-v2-resource-control/code

# 添加执行权限
chmod +x *.sh

# 运行内存限制演示
sudo ./memory-limit-demo.sh

# 运行 CPU 限制演示
sudo ./cpu-throttle-demo.sh
```

## 演示内容

### memory-limit-demo.sh

1. **memory.high（软限制）演示**
   - 设置 memory.high = 50M
   - 运行 stress 分配 80M 内存
   - 观察进程变慢但不被杀死

2. **memory.max（硬限制）演示**
   - 设置 memory.max = 50M
   - 运行 stress 分配 80M 内存
   - 观察 OOM Kill

3. **组合配置推荐**
   - memory.high = 80M（缓冲区）
   - memory.max = 100M（绝对上限）

### cpu-throttle-demo.sh

1. **无限制 CPU 使用**
   - 观察 stress 占用接近 100% CPU

2. **50% CPU 限制**
   - 设置 cpu.max = '50000 100000'
   - 观察 CPU 使用率被限制在 50%

3. **不同限制级别对比**
   - 对比 25%, 50%, 75% 的效果

## 安全说明

- 所有脚本在退出时自动清理创建的 cgroup
- 如果脚本异常中断，可能需要手动清理：
  ```bash
  sudo rmdir /sys/fs/cgroup/demo-* 2>/dev/null
  ```

## 故障排查

**问题**：`mkdir: cannot create directory: No space left on device`

**解决**：cgroup 可能已存在，先清理：
```bash
sudo rmdir /sys/fs/cgroup/demo-memory-high 2>/dev/null
sudo rmdir /sys/fs/cgroup/demo-memory-max 2>/dev/null
sudo rmdir /sys/fs/cgroup/demo-cpu-throttle 2>/dev/null
```

**问题**：`stress: command not found`

**解决**：安装 stress 工具（见前置要求）
