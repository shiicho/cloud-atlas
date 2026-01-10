# Lesson 07 - OverlayFS 容器镜像层原理：代码文件

本目录包含 Lesson 07 的演示脚本。

## 文件列表

| 文件 | 说明 | 用法 |
|------|------|------|
| `overlay-mount-demo.sh` | OverlayFS 手动挂载演示（lowerdir/upperdir/whiteout） | `sudo ./overlay-mount-demo.sh` |
| `cow-demo.sh` | 写时复制（Copy-on-Write）性能演示 | `sudo ./cow-demo.sh` |

## 前置要求

1. **Linux 系统**
   - 内核 3.18+ 支持 OverlayFS（现代发行版都满足）
   - Ubuntu 22.04+, RHEL 9+, Fedora 31+ 都支持

2. **root 权限**
   - 挂载 OverlayFS 需要 root 权限
   - 使用 `sudo` 运行脚本

3. **基础工具**
   - `mount`, `umount` (通常已预装)
   - `bc` (用于时间计算，可选)
   - `tree` (用于目录展示，可选)

## 使用方法

```bash
# 克隆仓库（如果还没有）
git clone --filter=blob:none --sparse https://github.com/shiicho/cloud-atlas ~/cloud-atlas
cd ~/cloud-atlas && git sparse-checkout set foundations/linux/containers

# 进入代码目录
cd ~/cloud-atlas/foundations/linux/lx11-containers/07-overlay-filesystems/code

# 添加执行权限
chmod +x *.sh

# 运行 OverlayFS 挂载演示
sudo ./overlay-mount-demo.sh

# 运行写时复制演示
sudo ./cow-demo.sh
```

## 演示内容

### overlay-mount-demo.sh

**学习目标**：理解 OverlayFS 四大目录和基本操作。

1. **创建目录结构**
   - lowerdir: 只读底层（镜像层）
   - upperdir: 可写上层（容器层）
   - workdir: 内核工作目录
   - merged: 合并视图

2. **挂载 OverlayFS**
   - 使用 `mount -t overlay` 命令
   - 验证挂载成功

3. **读取操作**
   - 读取 lower 层文件
   - 验证不触发复制

4. **写入操作（Copy-on-Write）**
   - 修改 lower 层文件
   - 观察文件被复制到 upper 层

5. **删除操作（Whiteout）**
   - 删除 lower 层文件
   - 观察 whiteout 文件（c 0 0）

### cow-demo.sh

**学习目标**：理解 Copy-on-Write 对大文件的性能影响。

1. **创建大文件**
   - 在 lower 层创建 50MB 文件
   - 模拟镜像中的大型库文件

2. **读取大文件**
   - 验证读取不触发复制
   - upper 层保持为空

3. **修改大文件**
   - 追加 1 字节
   - 观察整个文件被复制到 upper 层
   - 测量复制耗时

4. **磁盘空间分析**
   - 展示 CoW 导致的磁盘膨胀
   - 解释为什么数据应该用 volume

5. **性能对比**
   - 直接写入 vs Overlay 写入
   - 量化 Overlay 的性能开销

## 安全说明

- 所有脚本在退出时自动清理创建的 overlay 挂载和临时目录
- 如果脚本异常中断，可能需要手动清理：
  ```bash
  # 卸载 overlay
  sudo umount /tmp/overlay-mount-demo/merged 2>/dev/null
  sudo umount /tmp/cow-demo/merged 2>/dev/null

  # 删除目录
  sudo rm -rf /tmp/overlay-mount-demo
  sudo rm -rf /tmp/cow-demo
  ```

## 故障排查

**问题**：`mount: unknown filesystem type 'overlay'`

**解决**：加载 overlay 内核模块
```bash
sudo modprobe overlay
```

**问题**：`mount: /tmp/.../merged: wrong fs type, bad option`

**解决**：检查目录权限和路径
```bash
# 确保目录存在且有正确权限
sudo mkdir -p /tmp/overlay-demo/{lower,upper,work,merged}
sudo chmod 755 /tmp/overlay-demo/*
```

**问题**：`Device or resource busy` 卸载失败

**解决**：确保没有进程在使用挂载点
```bash
# 查看使用挂载点的进程
sudo lsof +D /tmp/overlay-demo/merged

# 强制卸载
sudo umount -l /tmp/overlay-demo/merged
```

## 关键概念回顾

```
OverlayFS 分层结构:

┌─────────────────────────────────────┐
│            merged (合并视图)         │  ← 容器看到的
└────────────────┬────────────────────┘
                 │ overlay mount
┌────────────────┴────────────────────┐
│                                      │
┌─────────────────┐  ┌─────────────────┐
│   upperdir      │  │   lowerdir      │
│   (可写层)      │  │   (只读层)      │
│                 │  │                 │
│  容器运行时     │  │  镜像层         │
│  的修改存这里   │  │  (可多个)       │
└─────────────────┘  └─────────────────┘

Copy-on-Write 规则:
1. 读取 → 从 lower 读（不复制）
2. 写入 → 复制到 upper 后修改
3. 删除 → 在 upper 创建 whiteout (c 0 0)
```

## 相关课程

- [Lesson 06 - cgroups v2 资源限制](../06-cgroups-v2-resource-control/)
- [Lesson 08 - 容器网络](../08-container-networking/)
- [LX07 - Linux 存储](../../lx07-storage/)
