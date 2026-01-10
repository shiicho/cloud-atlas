# 07 - OverlayFS（Overlay Filesystems）

> **目标**：理解 OverlayFS 分层架构与写时复制机制 —— Docker/Podman 镜像层的底层原理  
> **前置**：[Lesson 06 - cgroups v2 资源限制](../06-cgroups-v2-resource-control/)；了解 [LX07-STORAGE](../../lx07-storage/) 中的文件系统基础  
> **时间**：⚡ 30 分钟（速读）/ 🔬 120 分钟（完整实操）  
> **环境**：Linux 系统（建议 Ubuntu 22.04+ / RHEL 9+）  

---

## 将学到的内容

1. 理解 OverlayFS 的四个核心目录：lowerdir、upperdir、workdir、merged
2. 手动挂载 overlay 文件系统，直观感受容器镜像层工作原理
3. 理解写时复制（Copy-on-Write, CoW）机制
4. 理解 whiteout 文件如何实现「删除」操作
5. 观察 Docker 容器的真实镜像层结构

---

## 先跑起来：5 分钟创建你的「容器镜像层」

> **不讲原理，先动手！** 你马上就会理解 Docker 镜像为什么可以「分层」、「共享」。  

### 准备 overlay 目录结构

```bash
# 创建 overlay 实验目录
sudo mkdir -p /tmp/overlay-lab/{lower,upper,work,merged}

# 在 lower（只读层）中创建文件
echo "这是镜像层的文件" | sudo tee /tmp/overlay-lab/lower/image-file.txt
echo "配置文件原始内容" | sudo tee /tmp/overlay-lab/lower/config.txt
sudo mkdir -p /tmp/overlay-lab/lower/app
echo "应用程序代码" | sudo tee /tmp/overlay-lab/lower/app/main.py
```

### 挂载 OverlayFS

```bash
# 挂载 overlay 文件系统
sudo mount -t overlay overlay \
    -o lowerdir=/tmp/overlay-lab/lower,upperdir=/tmp/overlay-lab/upper,workdir=/tmp/overlay-lab/work \
    /tmp/overlay-lab/merged
```

### 体验「容器视图」

```bash
# 进入 merged 目录 —— 这就是「容器看到的文件系统」
ls /tmp/overlay-lab/merged
```

输出：

```
app  config.txt  image-file.txt
```

**容器看到的是 lower + upper 的合并视图！**

### 体验「写时复制」

```bash
# 修改「镜像层」的文件
echo "容器运行时修改的内容" | sudo tee /tmp/overlay-lab/merged/config.txt

# 检查：lower（镜像层）没有变化
cat /tmp/overlay-lab/lower/config.txt
```

输出：

```
配置文件原始内容
```

```bash
# 检查：修改后的文件出现在 upper（容器层）
cat /tmp/overlay-lab/upper/config.txt
```

输出：

```
容器运行时修改的内容
```

### 体验「删除」操作

```bash
# 删除「镜像层」的文件
sudo rm /tmp/overlay-lab/merged/image-file.txt

# 检查：lower（镜像层）文件还在！
ls /tmp/overlay-lab/lower/image-file.txt
```

输出：

```
/tmp/overlay-lab/lower/image-file.txt
```

```bash
# 检查：upper 出现了 whiteout 文件（字符设备 c 0 0）
ls -la /tmp/overlay-lab/upper/
```

输出：

```
c--------- 1 root root 0, 0 Jan  4 12:00 image-file.txt
```

**whiteout 文件（c 0 0）告诉内核「隐藏这个文件」！**

### 清理

```bash
# 卸载 overlay
sudo umount /tmp/overlay-lab/merged

# 删除实验目录
sudo rm -rf /tmp/overlay-lab
```

---

**你刚刚做了什么？**

```
┌──────────────────────────────────────────────────────────────────┐
│                    merged（容器看到的视图）                       │
│                                                                  │
│    /app/main.py  /config.txt  [image-file.txt 被隐藏]            │
│                                                                  │
└───────────────────────────┬──────────────────────────────────────┘
                            │ overlay mount
                            │
    ┌───────────────────────┴───────────────────────┐
    │                                               │
┌───┴──────────────┐                    ┌───────────┴────────────┐
│    upperdir      │                    │      lowerdir          │
│   （容器层）      │                    │     （镜像层）          │
│                  │                    │                        │
│  config.txt      │                    │  image-file.txt        │
│  (修改后的内容)   │                    │  config.txt            │
│                  │                    │  app/main.py           │
│  image-file.txt  │                    │                        │
│  (whiteout: c 0 0)                    │                        │
└──────────────────┘                    └────────────────────────┘
     可写                                       只读

写时复制规则：
1. 读取文件 → 优先从 upper 读，没有则从 lower 读
2. 修改文件 → 复制到 upper，然后修改
3. 删除文件 → 在 upper 创建 whiteout 文件（c 0 0）
```

这就是 Docker/Podman 镜像层的核心原理！多个容器可以共享同一个 lower（镜像层），每个容器有自己的 upper（容器层）。

---

## 发生了什么？

### OverlayFS 四大目录

| 目录 | 作用 | 容器场景对应 |
|------|------|-------------|
| **lowerdir** | 只读底层，可以有多个 | 镜像层（base image + layers） |
| **upperdir** | 可写上层 | 容器层（运行时修改） |
| **workdir** | 工作目录（内核使用） | 临时工作空间 |
| **merged** | 合并视图 | 容器看到的根文件系统 |

### 挂载命令详解

```bash
mount -t overlay overlay \
    -o lowerdir=/path/to/lower,upperdir=/path/to/upper,workdir=/path/to/work \
    /path/to/merged
```

| 参数 | 说明 |
|------|------|
| `-t overlay` | 文件系统类型为 overlay |
| `-o lowerdir=...` | 只读底层目录（可用 `:` 分隔多个） |
| `-o upperdir=...` | 可写上层目录 |
| `-o workdir=...` | 工作目录（必须与 upper 在同一文件系统） |
| 最后一个参数 | 合并后的挂载点 |

### 多层 lowerdir

Docker 镜像通常有多个层。OverlayFS 支持多个 lowerdir：

```bash
# 多层 lower（用冒号分隔，左边优先级高）
mount -t overlay overlay \
    -o lowerdir=/layer3:/layer2:/layer1,upperdir=/upper,workdir=/work \
    /merged
```

对应 Docker 镜像层：

```
┌────────────────────────────────┐
│          merged               │ ← 容器视图
├────────────────────────────────┤
│          upperdir             │ ← 容器层（可写）
├────────────────────────────────┤
│          layer3               │ ← 应用层 (RUN npm install)
├────────────────────────────────┤
│          layer2               │ ← 依赖层 (COPY package.json)
├────────────────────────────────┤
│          layer1               │ ← 基础镜像 (FROM ubuntu:22.04)
└────────────────────────────────┘
```

---

## 核心概念：写时复制（Copy-on-Write）

### 读取操作

```
读取 /etc/config.txt
    │
    ▼
检查 upperdir 是否有这个文件
    │
    ├── 有 → 返回 upperdir 中的文件
    │
    └── 没有 → 检查 lowerdir
                │
                └── 返回 lowerdir 中的文件
```

**读取是「零成本」的** —— 直接读取 lower 层文件，不需要复制。

### 写入操作（Copy-on-Write）

```
写入 /etc/config.txt
    │
    ▼
检查 upperdir 是否已有这个文件
    │
    ├── 有 → 直接修改 upperdir 中的文件
    │
    └── 没有 → 从 lowerdir 复制到 upperdir
                │
                └── 修改 upperdir 中的副本
```

**写入触发「复制」** —— 这就是 Copy-on-Write。

### 删除操作（Whiteout）

```
删除 /etc/config.txt
    │
    ▼
文件只在 lowerdir 中存在？
    │
    ├── 是 → 在 upperdir 创建 whiteout 文件
    │        （字符设备 c 0 0）
    │        这个文件「遮盖」lowerdir 的文件
    │
    └── 否（在 upper 中）→ 直接删除 upper 中的文件
```

**Whiteout 文件** —— 特殊的字符设备（major=0, minor=0），告诉内核「这个文件不存在」。

### 为什么需要 Whiteout？

问题：lower 层是只读的，无法真正删除文件。

解决：在 upper 层创建一个「标记文件」，告诉内核「假装这个文件不存在」。

```bash
# 查看 whiteout 文件
ls -la /path/to/upper/deleted-file
# c--------- 1 root root 0, 0 ... deleted-file
```

- `c` = 字符设备
- `0, 0` = major:minor 都是 0

---

## 动手练习

### Lab 1：手动挂载 OverlayFS

**目标**：深入理解 overlay 挂载和 CoW 机制。

运行演示脚本：

```bash
cd ~/cloud-atlas/foundations/linux/lx11-containers/07-overlay-filesystems/code
sudo ./overlay-mount-demo.sh
```

或手动执行：

**步骤 1**：准备目录

```bash
# 创建目录结构
sudo mkdir -p /tmp/overlay-demo/{lower,upper,work,merged}

# 创建 lower 层内容
sudo mkdir -p /tmp/overlay-demo/lower/etc
echo "original content" | sudo tee /tmp/overlay-demo/lower/etc/app.conf
echo "log data" | sudo tee /tmp/overlay-demo/lower/var-log.txt
```

**步骤 2**：挂载 overlay

```bash
sudo mount -t overlay overlay \
    -o lowerdir=/tmp/overlay-demo/lower,upperdir=/tmp/overlay-demo/upper,workdir=/tmp/overlay-demo/work \
    /tmp/overlay-demo/merged
```

**步骤 3**：验证合并视图

```bash
# 容器视图
ls -la /tmp/overlay-demo/merged/

# 读取文件（来自 lower）
cat /tmp/overlay-demo/merged/etc/app.conf
```

**步骤 4**：观察写时复制

```bash
# 修改文件
echo "modified by container" | sudo tee /tmp/overlay-demo/merged/etc/app.conf

# 验证 lower 未变
cat /tmp/overlay-demo/lower/etc/app.conf
# 输出: original content

# 验证 upper 有副本
cat /tmp/overlay-demo/upper/etc/app.conf
# 输出: modified by container
```

**步骤 5**：观察 whiteout

```bash
# 删除文件
sudo rm /tmp/overlay-demo/merged/var-log.txt

# 验证容器视图看不到
ls /tmp/overlay-demo/merged/var-log.txt 2>&1
# 输出: No such file or directory

# 验证 lower 文件还在
cat /tmp/overlay-demo/lower/var-log.txt
# 输出: log data

# 验证 whiteout 文件
ls -la /tmp/overlay-demo/upper/var-log.txt
# 输出: c--------- 1 root root 0, 0 ... var-log.txt
```

**清理**：

```bash
sudo umount /tmp/overlay-demo/merged
sudo rm -rf /tmp/overlay-demo
```

---

### Lab 2：观察 Docker 容器层

**目标**：查看真实 Docker/Podman 容器的 OverlayFS 结构。

**前提**：已安装 Docker 或 Podman。

**步骤 1**：运行容器

```bash
docker run -d --name overlay-lab nginx:alpine
```

**步骤 2**：查看镜像层信息

```bash
# 查看镜像的 GraphDriver 信息
docker inspect nginx:alpine | jq '.[0].GraphDriver'
```

输出示例：

```json
{
  "Data": {
    "LowerDir": "/var/lib/docker/overlay2/abc123.../diff:/var/lib/docker/overlay2/def456.../diff",
    "MergedDir": "/var/lib/docker/overlay2/xyz789.../merged",
    "UpperDir": "/var/lib/docker/overlay2/xyz789.../diff",
    "WorkDir": "/var/lib/docker/overlay2/xyz789.../work"
  },
  "Name": "overlay2"
}
```

**步骤 3**：查看容器层信息

```bash
# 查看容器的挂载信息
docker inspect overlay-lab | jq '.[0].GraphDriver'
```

**步骤 4**：探索 lower 层

```bash
# 获取 LowerDir 路径
LOWER=$(docker inspect nginx:alpine | jq -r '.[0].GraphDriver.Data.LowerDir' | cut -d: -f1)

# 查看内容
sudo ls $LOWER
```

**步骤 5**：在容器中创建文件并观察 upper 层

```bash
# 在容器中创建文件
docker exec overlay-lab touch /tmp/container-file.txt
docker exec overlay-lab sh -c 'echo "hello" > /tmp/container-file.txt'

# 获取容器的 UpperDir
UPPER=$(docker inspect overlay-lab | jq -r '.[0].GraphDriver.Data.UpperDir')

# 查看 upper 层变化
sudo ls -la $UPPER/
sudo cat $UPPER/tmp/container-file.txt
```

**清理**：

```bash
docker stop overlay-lab && docker rm overlay-lab
```

---

### Lab 3：写时复制演示

**目标**：直观观察 CoW 对大文件的影响。

运行演示脚本：

```bash
cd ~/cloud-atlas/foundations/linux/lx11-containers/07-overlay-filesystems/code
sudo ./cow-demo.sh
```

或手动执行：

**步骤 1**：创建包含大文件的 lower 层

```bash
sudo mkdir -p /tmp/cow-demo/{lower,upper,work,merged}

# 创建 50MB 大文件
sudo dd if=/dev/zero of=/tmp/cow-demo/lower/bigfile.bin bs=1M count=50 status=progress

# 查看大小
ls -lh /tmp/cow-demo/lower/bigfile.bin
# 输出: -rw-r--r-- 1 root root 50M ... bigfile.bin
```

**步骤 2**：挂载 overlay

```bash
sudo mount -t overlay overlay \
    -o lowerdir=/tmp/cow-demo/lower,upperdir=/tmp/cow-demo/upper,workdir=/tmp/cow-demo/work \
    /tmp/cow-demo/merged
```

**步骤 3**：读取大文件（不触发复制）

```bash
# upper 层为空
ls -la /tmp/cow-demo/upper/
# 输出: total 0

# 读取文件（不复制）
md5sum /tmp/cow-demo/merged/bigfile.bin

# upper 层仍为空
ls -la /tmp/cow-demo/upper/
# 输出: total 0
```

**步骤 4**：修改大文件（触发复制）

```bash
# 修改文件（即使只改一个字节，也要复制整个文件！）
echo "x" | sudo tee -a /tmp/cow-demo/merged/bigfile.bin

# 检查 upper 层
ls -lh /tmp/cow-demo/upper/
# 输出: -rw-r--r-- 1 root root 50M ... bigfile.bin
```

**关键发现**：修改 50MB 文件的一个字节，导致整个 50MB 文件被复制到 upper 层！

**清理**：

```bash
sudo umount /tmp/cow-demo/merged
sudo rm -rf /tmp/cow-demo
```

---

## 性能考虑

### 反模式：容器内写大量数据到 overlay

**问题**：

```dockerfile
# 反模式：写数据到容器层
FROM python:3.11
WORKDIR /app
COPY . .
RUN python process_data.py  # 生成大量数据到容器层
```

```bash
# 运行时不断写日志到容器层
docker run myapp python app.py >> /var/log/app.log
```

**后果**：

1. 数据写入 overlay upper 层
2. upper 层文件不断增长
3. 磁盘空间消耗在 `/var/lib/docker/overlay2/`
4. 性能下降（overlay 写入比直接 ext4 慢）

**解决方案**：数据写入 volume

```bash
# 正确：使用 volume
docker run -v /data:/app/data myapp python app.py
```

### 反模式：OverlayFS 放在不支持 d_type 的 XFS

**问题**：旧版 XFS 或使用 `ftype=0` 创建的 XFS 不支持 d_type。

**后果**：

```
overlay: upper fs does not support RENAME_WHITEOUT
overlay: d_type not supported
```

- 奇怪的 inode 错误
- 性能严重下降
- 容器启动失败

**检查方法**：

```bash
# 检查 XFS 是否支持 d_type
xfs_info /var/lib/docker | grep ftype
# 输出应该是: ftype=1
```

如果 `ftype=0`，需要重新创建文件系统。

### 反模式：使用 :latest 标签

**问题**：

```bash
docker pull myapp:latest  # 今天的 latest
# 一周后
docker pull myapp:latest  # 不同的镜像！
```

**后果**：

- 无法追溯镜像版本
- 无法复现问题
- 安全漏洞难以追踪

**解决方案**：使用具体 tag 或 digest

```bash
# 使用具体 tag
docker pull nginx:1.25.3

# 使用 digest（完全确定）
docker pull nginx@sha256:abc123...
```

---

## 职场小贴士

### 日本 IT 现场常见场景

**场景 1：イメージレイヤー理解は Dockerfile 最適化に必須**

```
問題：Docker イメージが 2GB もある

原因分析：
1. docker history <image> でレイヤー確認
2. 不要な中間ファイルがレイヤーに残っている

最適化パターン：
# 悪い例（2つのレイヤー）
RUN apt-get update
RUN apt-get install -y curl && apt-get clean

# 良い例（1つのレイヤー、クリーンアップ含む）
RUN apt-get update && \
    apt-get install -y curl && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*
```

**场景 2：本番でのディスク容量問題の原因究明**

```
アラート：/var/lib/docker が 95% 使用

調査手順：
1. docker system df  # 全体のディスク使用量
2. docker system df -v  # 詳細表示
3. 大きなイメージやコンテナを特定

容器層の確認：
# 各コンテナの overlay 使用量
for c in $(docker ps -q); do
  echo "=== $c ==="
  UPPER=$(docker inspect $c | jq -r '.[0].GraphDriver.Data.UpperDir')
  sudo du -sh $UPPER
done

対策：
- 不要なコンテナ削除: docker container prune
- 不要なイメージ削除: docker image prune
- ログを volume に出力
```

**场景 3：コンテナ内で削除したはずのファイルが容量を消費**

```
症状：
コンテナ内で rm -rf /tmp/* を実行したのに、
ディスク使用量が減らない。

原因：
ファイルが lower（イメージ層）にある場合、
削除しても whiteout ファイルが作られるだけで、
実際の容量は解放されない。

確認方法：
# upper 層を確認
ls -la $UPPER/tmp/
# c--------- ... (whiteout ファイルがある)

対策：
イメージ層に大きなファイルを入れない。
データは volume に保存。
```

### 常见日语术语

| 日语 | 读音 | 含义 |
|------|------|------|
| イメージレイヤー | イメージレイヤー | Image layer |
| 書き込み時コピー | かきこみじコピー | Copy-on-Write |
| オーバーレイ | オーバーレイ | Overlay |
| ストレージドライバ | ストレージドライバ | Storage driver |
| 容量削減 | ようりょうさくげん | Capacity reduction |

---

## 检查清单

完成本课后，你应该能够：

- [ ] 说出 OverlayFS 的四个核心目录（lowerdir, upperdir, workdir, merged）
- [ ] 手动执行 `mount -t overlay` 命令挂载 overlay 文件系统
- [ ] 解释写时复制（Copy-on-Write）的工作原理
- [ ] 解释 whiteout 文件（c 0 0）的作用
- [ ] 使用 `docker inspect` 查看容器的 GraphDriver 信息
- [ ] 找到容器的 LowerDir、UpperDir、MergedDir 路径
- [ ] 解释为什么数据应该写入 volume 而不是容器层
- [ ] 使用 `xfs_info` 检查 XFS 是否支持 d_type

---

## OverlayFS 分层结构图（完整）

```
OverlayFS 分层结构:

┌─────────────────────────────────────┐
│            merged (合并视图)         │  ← 容器看到的文件系统
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

写时复制 (CoW):
1. 读取 /etc/nginx/nginx.conf → 从 lowerdir 读取
2. 写入 /etc/nginx/nginx.conf → 复制到 upperdir，然后修改
3. 删除 /var/log/file.log → 在 upperdir 创建 whiteout 文件
```

Docker 镜像层对应：

```
┌────────────────────────────────────────────────────────────┐
│                       容器                                  │
│  ┌──────────────────────────────────────────────────────┐  │
│  │              upperdir（容器可写层）                   │  │
│  │              /var/lib/docker/overlay2/xxx/diff       │  │
│  └──────────────────────────────────────────────────────┘  │
│                            │                                │
│  ┌──────────────────────────────────────────────────────┐  │
│  │              lowerdir（镜像只读层）                   │  │
│  │                                                      │  │
│  │   ┌────────────────────────────────────────────┐     │  │
│  │   │  Layer 3: RUN npm install                  │     │  │
│  │   └────────────────────────────────────────────┘     │  │
│  │   ┌────────────────────────────────────────────┐     │  │
│  │   │  Layer 2: COPY package.json                │     │  │
│  │   └────────────────────────────────────────────┘     │  │
│  │   ┌────────────────────────────────────────────┐     │  │
│  │   │  Layer 1: FROM node:18-alpine              │     │  │
│  │   └────────────────────────────────────────────┘     │  │
│  │                                                      │  │
│  └──────────────────────────────────────────────────────┘  │
└────────────────────────────────────────────────────────────┘

多个容器可以共享相同的 lowerdir（镜像层）！
每个容器有自己独立的 upperdir（容器层）。
```

---

## 延伸阅读

### 官方文档

- [OverlayFS - Kernel Documentation](https://www.kernel.org/doc/html/latest/filesystems/overlayfs.html)
- [Docker Storage Drivers](https://docs.docker.com/storage/storagedriver/)
- [Docker overlay2 Storage Driver](https://docs.docker.com/storage/storagedriver/overlayfs-driver/)

### 相关课程

- [Lesson 06 - cgroups v2 资源限制](../06-cgroups-v2-resource-control/) - 资源控制实战
- [Lesson 08 - 容器网络](../08-container-networking/) - veth、Bridge 与 NAT
- [Lesson 11 - 容器故障排查](../11-debugging-troubleshooting/) - 包含存储问题排查
- [LX07 - Linux 存储](../../lx07-storage/) - 文件系统和挂载基础

### 推荐阅读

- *Container Security* by Liz Rice - Chapter on Container Storage
- Docker Official Blog: Understanding Docker Storage

---

## 面试准备（Interview Prep）

### Q1: OverlayFS の仕組みを説明してください（解释 OverlayFS 的工作原理）

**回答要点**：

```
OverlayFS は 4 つのディレクトリで構成：
1. lowerdir（下層）：読み取り専用、イメージレイヤー
2. upperdir（上層）：書き込み可能、コンテナレイヤー
3. workdir：カーネルが使用する作業ディレクトリ
4. merged：統合ビュー、コンテナが見るファイルシステム

動作原理：
- 読み取り：upper → lower の順で検索
- 書き込み：lower のファイルを upper にコピーしてから変更（CoW）
- 削除：upper に whiteout ファイル（c 0 0）を作成
```

### Q2: Copy-on-Write のメリットとデメリットは？（CoW 的优缺点？）

**回答要点**：

```
メリット：
1. ディスク節約：複数コンテナがイメージ層を共有
2. 起動高速化：イメージをコピーする必要がない
3. 効率的：読み取りはコピー不要

デメリット：
1. 書き込みオーバーヘッド：最初の書き込み時にファイル全体をコピー
2. 大きなファイルの編集が遅い：1バイト変更でも全ファイルコピー
3. ストレージ見積もりが難しい：実際の使用量が分かりにくい

対策：
- データは volume に保存
- 頻繁に変更するファイルはコンテナ層に置かない
```

### Q3: コンテナのディスク使用量が増え続ける問題の調査方法は？

**回答要点**：

```bash
# 1. 全体の使用量確認
docker system df -v

# 2. 各コンテナの upper 層サイズ確認
for c in $(docker ps -q); do
  UPPER=$(docker inspect $c | jq -r '.[0].GraphDriver.Data.UpperDir')
  echo "$c: $(sudo du -sh $UPPER)"
done

# 3. 大きなファイルを特定
sudo find $UPPER -type f -size +100M

# 対策
# - ログを volume に出力
# - 不要なファイルは volume に移動
# - docker container prune で不要コンテナ削除
```

---

## 系列导航

[<-- 06 - cgroups v2 资源限制](../06-cgroups-v2-resource-control/) | [Home](../) | [08 - 容器网络 -->](../08-container-networking/)
