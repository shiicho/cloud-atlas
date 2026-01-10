# 04 - User Namespace（Rootless Containers）

> **目标**：理解 User Namespace 的 UID 映射机制，配置 Rootless 容器，并能向安全审计解释隔离原理  
> **前置**：完成 [03 - Namespace 深入](../03-namespace-deep-dive/)  
> **时间**：⚡ 40 分钟（速读）/ 🔬 150 分钟（完整实操）  
> **场景**：日本企業のセキュリティ監査対応（安全审计与 root 禁止策略）  

---

## 将学到的内容

1. 理解 User Namespace 的 UID/GID 映射机制
2. 配置 `/etc/subuid` 和 `/etc/subgid` 启用 rootless 模式
3. 使用 Podman 运行 rootless 容器
4. 向安全审计人员解释 User Namespace 的隔离价值
5. 处理 rootless 容器的常见权限问题

---

## 先跑起来！（5 分钟）

> 在学习理论之前，先体验 User Namespace 的"魔法"：你可以在容器内成为 root，但在宿主机上只是普通用户！  

```bash
# 创建一个 User Namespace，你将成为 "root"！
unshare --user --map-root-user /bin/bash

# 检查身份——你是 root！
id
# uid=0(root) gid=0(root) groups=0(root)

# 你真的是 root 吗？尝试做一个只有 root 能做的事
cat /etc/shadow
# 权限拒绝！虽然你 "看起来" 是 root，但实际上不是

# 查看 UID 映射
cat /proc/self/uid_map
#          0       1000          1
# 解读：容器内 UID 0 = 宿主机 UID 1000（你的用户）

# 退出
exit
```

**你刚刚体验了什么？**

- 在 User Namespace 中，你的 `id` 显示 `uid=0(root)`
- 但访问 `/etc/shadow` 仍然被拒绝
- 因为这个 "root" 只在 Namespace 内有效，在宿主机看来你还是普通用户

**这就是 rootless 容器的核心原理。** 现在让我们深入理解。

---

## Step 1 - 理解 User Namespace 原理（25 分钟）

### 1.1 什么是 User Namespace？

User Namespace 是 Linux 内核提供的 UID/GID 隔离机制。它创建一个独立的用户 ID 空间：

- **容器内**：进程看到的 UID 可以是 0（root）
- **宿主机上**：该进程的真实 UID 是一个普通用户（如 100000）

```
User Namespace 的 UID 映射：

┌─────────────────────────────────────────────────────────────┐
│  容器视角                                                    │
│  ┌───────────────────────────────────────────────────────┐  │
│  │                                                        │  │
│  │   我是 root！(UID 0)                                   │  │
│  │   ├── 可以运行需要 root 的应用                         │  │
│  │   ├── 可以 chown, chmod                               │  │
│  │   └── 但无法访问宿主机的特权资源                       │  │
│  │                                                        │  │
│  └───────────────────────────────────────────────────────┘  │
│                            │                                 │
│                            │ UID 映射                        │
│                            ▼                                 │
│  ┌───────────────────────────────────────────────────────┐  │
│  │  宿主机视角                                            │  │
│  │                                                        │  │
│  │   这只是 UID 100000 的普通用户                         │  │
│  │   ├── 无法读取 /etc/shadow                            │  │
│  │   ├── 无法修改系统文件                                 │  │
│  │   └── 即使容器逃逸，也只是普通用户                     │  │
│  │                                                        │  │
│  └───────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

### 1.2 UID 映射文件

每个进程的 UID 映射信息存储在 `/proc/<PID>/uid_map` 和 `/proc/<PID>/gid_map` 中。

**映射格式**：

```
容器内起始UID    宿主机起始UID    映射数量
     0              100000          65536
```

这表示：
- 容器内 UID 0 = 宿主机 UID 100000
- 容器内 UID 1 = 宿主机 UID 100001
- ...
- 容器内 UID 65535 = 宿主机 UID 165535

### 1.3 动手实验：查看 UID 映射

```bash
# 实验 1：简单的 User Namespace（映射当前用户到 root）
unshare --user --map-root-user /bin/bash

# 在 Namespace 内
id                      # uid=0(root)
cat /proc/self/uid_map  # 查看映射
cat /proc/self/gid_map  # 查看 GID 映射

# 这个 "root" 的权限很有限
touch /etc/test         # 权限拒绝！

exit
```

```bash
# 实验 2：从宿主机观察
# 终端 1：创建 User Namespace
unshare --user --map-root-user /bin/bash -c "
echo '我是容器内的 PID:' $$
echo '容器内 id:' && id
sleep 300
"

# 终端 2：在宿主机观察
# 找到刚才的 bash 进程
PID=$(pgrep -f "sleep 300" | tail -1)
echo "宿主机看到的 PID: $PID"

# 查看宿主机上的真实 UID
ps -p $PID -o pid,uid,user,cmd

# 查看 UID 映射
cat /proc/$PID/uid_map

# 你会看到：容器内的 root 在宿主机上是你自己的 UID
```

### 1.4 为什么 User Namespace 如此重要？

| 特性 | 传统容器 | User Namespace 容器 |
|------|----------|---------------------|
| 容器内 UID 0 | = 宿主机 UID 0（真 root） | = 宿主机 UID 100000+（普通用户） |
| 容器逃逸后 | 获得 root 权限 | 只是普通用户 |
| 满足安全策略 | 不满足 "no root" 要求 | 满足 "no root" 要求 |
| 安全边界 | 依赖其他机制（seccomp 等） | 多一层隔离 |

---

## Step 2 - 配置 subuid/subgid（30 分钟）

### 2.1 什么是 subuid/subgid？

当普通用户运行 rootless 容器时，容器内可能有多个用户（UID 0-65535）。这些 UID 需要映射到宿主机的某些 UID。

`/etc/subuid` 和 `/etc/subgid` 定义了每个用户可以使用的额外 UID/GID 范围。

**文件格式**：

```
用户名:起始UID:数量
```

**示例**：

```bash
# /etc/subuid
testuser:100000:65536
```

这表示用户 `testuser` 可以使用宿主机 UID 100000-165535，用于容器内的 UID 0-65535 映射。

### 2.2 为什么需要 65536 个 UID？

```
为什么是 65536？

容器内可能有多个用户/进程：
  UID 0     (root)      → 需要映射到宿主机某个 UID
  UID 1-99  (系统用户)   → 需要映射到宿主机某些 UID
  UID 1000  (普通用户)   → 需要映射到宿主机某个 UID
  ...
  UID 65534 (nobody)    → 需要映射到宿主机某个 UID

65536 = 2^16，覆盖所有 16 位 UID 范围
```

### 2.3 检查和配置 subuid/subgid

```bash
# 检查当前配置
cat /etc/subuid
cat /etc/subgid

# 如果你的用户没有配置，会看到空或不包含你的用户名
```

**手动添加配置**：

```bash
# 方法 1：使用 usermod（推荐）
sudo usermod --add-subuids 100000-165535 --add-subgids 100000-165535 $USER

# 方法 2：直接编辑文件
echo "$USER:100000:65536" | sudo tee -a /etc/subuid
echo "$USER:100000:65536" | sudo tee -a /etc/subgid

# 验证配置
cat /etc/subuid
cat /etc/subgid
```

**多用户环境的配置**：

```bash
# 每个用户需要不重叠的 UID 范围
# /etc/subuid 示例：
# alice:100000:65536
# bob:165536:65536
# charlie:231072:65536
```

### 2.4 常见错误：不配置 subuid/subgid

这是一个**关键反模式**，会导致：

```bash
# 错误示例：没有配置 subuid 就运行 rootless 容器
podman run --rm alpine id

# 报错：
# Error: cannot find UID/GID mappings when running rootless
# Please ensure /etc/subuid and /etc/subgid are configured correctly
```

**问题根源**：

```
没有 subuid/subgid 配置：

容器需要：
  UID 0 (root)     → 需要映射到宿主机的某个 UID
  UID 1-65535      → 需要映射到宿主机的某些 UID

但系统不知道你能使用哪些 UID！
→ 无法创建 UID 映射
→ 容器启动失败
```

**解决方案**：

```bash
# 确保配置了 subuid/subgid
sudo usermod --add-subuids 100000-165535 --add-subgids 100000-165535 $USER

# 如果之前有失败的容器，可能需要重新初始化
podman system migrate
```

---

## Step 3 - Rootless Podman 实战（40 分钟）

### 3.1 什么是 Rootless 容器？

Rootless 容器是指**整个容器运行时都不需要 root 权限**：

- 容器镜像存储在用户目录下
- 容器进程以普通用户身份运行
- 即使容器内是 root，宿主机上也只是普通用户

### 3.2 安装和配置 Podman

```bash
# Ubuntu/Debian
sudo apt-get update
sudo apt-get install -y podman

# RHEL/CentOS/Fedora
sudo dnf install -y podman

# 验证安装
podman --version
```

### 3.3 配置 Rootless Podman

```bash
# 1. 确保 subuid/subgid 已配置
grep $USER /etc/subuid /etc/subgid

# 如果没有，添加配置
sudo usermod --add-subuids 100000-165535 --add-subgids 100000-165535 $USER

# 2. 启用 user namespaces（如果系统没有默认启用）
# 检查是否已启用
cat /proc/sys/user/max_user_namespaces
# 如果是 0，需要启用：
echo "user.max_user_namespaces = 15000" | sudo tee /etc/sysctl.d/userns.conf
sudo sysctl -p /etc/sysctl.d/userns.conf

# 3. 初始化 Podman（如果是第一次使用）
podman system migrate
```

### 3.4 运行第一个 Rootless 容器

```bash
# 以普通用户身份运行（不需要 sudo）
podman run --rm alpine id
# uid=0(root) gid=0(root)

# 等等，这不是 root 吗？让我们验证真相
```

### 3.5 验证 Rootless 隔离

**实验 1：验证容器内外的 UID 差异**

```bash
# 终端 1：启动一个容器
podman run -d --name test-rootless alpine sleep 3600

# 获取容器的 PID
podman inspect --format '{{.State.Pid}}' test-rootless

# 终端 2：在宿主机检查
PID=$(podman inspect --format '{{.State.Pid}}' test-rootless)

# 查看宿主机上的真实 UID
ps -p $PID -o pid,uid,user,cmd
# 你会看到 UID 是 100000（或你的 subuid 起始值），不是 0！

# 查看 UID 映射
cat /proc/$PID/uid_map
# 输出类似：
#          0     100000      65536

# 清理
podman rm -f test-rootless
```

**实验 2：验证安全隔离**

```bash
# 在容器内尝试做"危险"的事情
podman run --rm alpine sh -c "
    echo '容器内身份:' && id
    echo ''
    echo '尝试读取 /etc/shadow...'
    cat /etc/shadow 2>&1 || echo '→ 失败（容器自己的 shadow 文件）'
    echo ''
    echo '尝试挂载 proc...'
    mount -t proc proc /mnt 2>&1 || echo '→ 失败（没有权限）'
"

# 即使容器内是 root，也无法做真正需要特权的操作
```

### 3.6 Rootless 容器的限制

Rootless 容器有一些限制，需要了解：

| 功能 | Root 容器 | Rootless 容器 | 解决方案 |
|------|-----------|---------------|----------|
| 绑定 <1024 端口 | 可以 | 不可以 | 使用高端口或 slirp4netns |
| 修改宿主机文件 | 可以 | 不可以 | 使用 volume 挂载 |
| 运行特权操作 | 可以 | 不可以 | 这正是安全特性！ |
| 网络性能 | 原生 | 略低（slirp4netns） | 可接受的权衡 |

```bash
# 示例：绑定低端口
# 这会失败：
podman run --rm -p 80:80 nginx
# Error: rootlessport cannot expose privileged port 80

# 解决方案：使用高端口
podman run --rm -p 8080:80 nginx
```

---

## Step 4 - 安全审计场景：向安全官解释 User Namespace（30 分钟）

### 4.1 场景背景

在日本企业中，安全策略经常要求：

- **禁止 root 进程**（root 禁止ポリシー）
- **最小权限原则**（最小権限の原則）
- **特权分离**（特権分離）

但是，很多供应商的容器镜像要求以 UID 0（root）运行。这造成了矛盾。

**User Namespace 是解决方案！**

### 4.2 如何向安全审计解释

**场景模拟**：安全官质疑你的容器以 root 运行

```
安全官：「このコンテナは root で動いていますね？
         セキュリティポリシーに違反しています。」
        （这个容器以 root 运行吧？违反了安全策略。）

你：    「見た目は root ですが、実際は違います。
         User Namespace という技術を使っています。」
        （看起来是 root，但实际上不是。我们使用了 User Namespace 技术。）

安全官：「具体的に説明してください。」
        （请具体解释。）
```

**技术解释**：

```bash
# 1. 显示容器内的 "root"
podman exec test-container id
# uid=0(root) gid=0(root)

# 2. 显示宿主机上的真实 UID
PID=$(podman inspect --format '{{.State.Pid}}' test-container)
ps -p $PID -o pid,uid,user,cmd
# 显示 UID 100000（不是 0！）

# 3. 显示 UID 映射
cat /proc/$PID/uid_map
#          0     100000      65536
# 解释：容器内 0-65535 映射到宿主机 100000-165535
```

**用非技术语言解释**：

```
技术事实：
  容器内：进程看到的 UID 是 0（root）
  宿主机：进程的真实 UID 是 100000（普通用户）

安全含义：
  1. 容器内的 "root" 无法访问宿主机的特权资源
  2. 即使容器被攻破（容器逃逸），攻击者只获得 UID 100000
  3. UID 100000 是普通用户，无法：
     - 读取 /etc/shadow
     - 修改系统配置
     - 安装内核模块
     - 做任何需要真正 root 权限的事

结论：
  虽然容器内 "看起来" 是 root，
  但从宿主机安全角度，它只是普通用户。
  这满足 "禁止 root 进程" 的安全要求。
```

### 4.3 提供证据

安全审计需要证据。以下是你可以提供的证明：

```bash
# 证据 1：UID 映射文件
cat /proc/$PID/uid_map
# 输出：
#          0     100000      65536

# 证据 2：宿主机进程列表
ps -ef | grep -E "PID|$PID"
# 显示进程以 UID 100000 运行

# 证据 3：尝试特权操作
# 在容器内
podman exec test-container sh -c "cat /etc/shadow"
# 只能看到容器自己的 shadow 文件

# 在宿主机
sudo cat /etc/shadow  # 需要 sudo
# 容器进程无法访问这个
```

### 4.4 安全审计报告模板

```markdown
# User Namespace セキュリティ報告書

## 概要
コンテナ環境で User Namespace を使用し、
root 禁止ポリシーに準拠していることを報告します。

## 技術詳細

### コンテナ情報
- コンテナ名: ${CONTAINER_NAME}
- ホスト側 PID: ${PID}
- ホスト側 UID: 100000 (非特権ユーザー)

### UID マッピング
容器内 UID 0-65535 → 宿主机 UID 100000-165535

### 証拠
1. /proc/${PID}/uid_map の出力
2. ps コマンドの出力（UID 100000 を確認）
3. 特権操作の失敗ログ

## 結論
User Namespace により、コンテナ内の root は
ホスト上の非特権ユーザーにマッピングされています。
これにより root 禁止ポリシーに準拠しています。
```

---

## Step 5 - 高级实验：深入 User Namespace（20 分钟）

### 5.1 手动创建完整的 UID 映射

```bash
# 创建 User Namespace 但不自动映射
unshare --user /bin/bash &
PID=$!

# 手动设置 UID 映射
# 格式：容器内起始UID 宿主机起始UID 数量
echo "0 $(id -u) 1" > /proc/$PID/uid_map
echo "0 $(id -g) 1" > /proc/$PID/gid_map

# 让进程继续
fg
```

### 5.2 查看 newuidmap 和 newgidmap

当使用 subuid/subgid 时，系统使用 `newuidmap` 和 `newgidmap` 工具来设置映射：

```bash
# 这些是 setuid 程序
ls -la /usr/bin/newuidmap /usr/bin/newgidmap
# -rwsr-xr-x 1 root root ... /usr/bin/newuidmap
# -rwsr-xr-x 1 root root ... /usr/bin/newgidmap

# 查看你可以映射的 UID 范围
cat /etc/subuid | grep $USER
```

### 5.3 调试 rootless 容器问题

```bash
# 常见问题 1：subuid/subgid 未配置
podman run --rm alpine id
# 如果报错，检查：
cat /etc/subuid | grep $USER
cat /etc/subgid | grep $USER

# 常见问题 2：user namespace 未启用
cat /proc/sys/user/max_user_namespaces
# 如果是 0，需要启用

# 常见问题 3：权限问题
# 检查 ~/.local/share/containers 目录
ls -la ~/.local/share/containers/

# 常见问题 4：需要重新初始化
podman system reset  # 警告：会删除所有容器和镜像
podman system migrate
```

---

## 职场小贴士（Japan IT Context）

### セキュリティ監査への対応

在日本企业中，安全审计（セキュリティ監査）是常见的合规要求：

| 审计要点 | 日语术语 | User Namespace 回答 |
|----------|----------|---------------------|
| root 禁止 | root 禁止ポリシー | UID 映射证明容器 root = 宿主机普通用户 |
| 最小权限 | 最小権限の原則 | rootless 容器天然满足 |
| 权限分离 | 特権分離 | User Namespace 提供额外隔离层 |
| 容器逃逸风险 | コンテナエスケープ | 逃逸后只是普通用户，风险大幅降低 |

### 常见日语术语

| 日语 | 读音 | 含义 |
|------|------|------|
| ユーザー名前空間 | ユーザーなまえくうかん | User Namespace |
| ルートレス | ルートレス | Rootless |
| 権限マッピング | けんげんマッピング | 权限映射 |
| 非特権ユーザー | ひとっけんユーザー | 非特权用户 |
| セキュリティ監査 | セキュリティかんさ | 安全审计 |

### 报告书模板

在日本企业中，障害報告書（故障报告）和監査報告書（审计报告）需要正式格式：

```
件名：Rootless コンテナ セキュリティ確認報告

1. 概要
   User Namespace を使用した Rootless コンテナ環境を構築し、
   root 禁止ポリシーへの準拠を確認しました。

2. 確認事項
   ・コンテナ内 UID 0 = ホスト UID 100000
   ・特権操作の制限を確認
   ・/etc/subuid, /etc/subgid 設定完了

3. 結論
   本環境はセキュリティポリシーに準拠しています。
```

---

## 检查清单

完成本课后，你应该能够：

- [ ] 使用 `unshare --user --map-root-user` 创建 User Namespace
- [ ] 解释 `/proc/<PID>/uid_map` 的格式和含义
- [ ] 配置 `/etc/subuid` 和 `/etc/subgid`
- [ ] 使用 `usermod --add-subuids` 添加 UID 范围
- [ ] 运行 rootless Podman 容器
- [ ] 验证容器内 root 在宿主机上是普通用户
- [ ] 向非技术人员解释 User Namespace 的安全价值
- [ ] 处理 rootless 容器的常见错误
- [ ] 生成安全审计所需的证据

---

## 本课小结

| 概念 | 要点 |
|------|------|
| User Namespace | 隔离 UID/GID，容器内 root = 宿主机普通用户 |
| uid_map | `/proc/<PID>/uid_map` 定义 UID 映射关系 |
| subuid/subgid | `/etc/subuid` 定义用户可用的 UID 范围 |
| Rootless 容器 | 整个容器运行时不需要 root 权限 |
| 安全价值 | 即使容器逃逸，攻击者只是普通用户 |

---

## 反模式：常见错误

### 错误 1：不配置 subuid/subgid 就运行 rootless 容器

```bash
# 错误：直接运行 rootless 容器
podman run --rm alpine id
# Error: cannot find UID/GID mappings

# 正确：先配置 subuid/subgid
sudo usermod --add-subuids 100000-165535 --add-subgids 100000-165535 $USER
podman system migrate
podman run --rm alpine id
```

### 错误 2：混淆容器内 root 和宿主机 root

```bash
# 容器内看起来是 root
podman exec mycontainer id
# uid=0(root)

# 但在宿主机上不是 root！
ps -p $(podman inspect --format '{{.State.Pid}}' mycontainer) -o uid
# 100000（不是 0）

# 不要因为看到 uid=0 就认为有安全风险
# User Namespace 保证了这个 "root" 只在容器内有效
```

### 错误 3：忽视 rootless 容器的限制

```bash
# 错误：期望 rootless 容器能绑定特权端口
podman run --rm -p 80:80 nginx
# Error: rootlessport cannot expose privileged port 80

# 正确：使用高端口
podman run --rm -p 8080:80 nginx

# 或者，如果确实需要 80 端口，使用 root 容器
# 但这需要安全评估！
sudo podman run --rm -p 80:80 nginx
```

---

## 延伸阅读

- [Linux User Namespaces man page](https://man7.org/linux/man-pages/man7/user_namespaces.7.html)
- [Podman Rootless Documentation](https://github.com/containers/podman/blob/main/docs/tutorials/rootless_tutorial.md)
- [subuid(5) man page](https://man7.org/linux/man-pages/man5/subuid.5.html)
- 下一课：[05 - cgroups v2 架构](../05-cgroups-v2-architecture/)
- 相关课程：[09 - 容器安全](../09-container-security/) - seccomp 和 capabilities

---

## 面试准备（Interview Prep）

### Q1: User Namespace とは何ですか？なぜ重要ですか？

**回答要点**：

```
User Namespace は Linux カーネルの機能で、
UID/GID を隔離します。

重要な理由：
1. コンテナ内の root ≠ ホストの root
2. コンテナエスケープ時の被害を軽減
3. root 禁止ポリシーへの準拠が可能

技術的には：
  コンテナ内 UID 0 → ホスト UID 100000 (非特権)
  /proc/<PID>/uid_map で確認可能
```

### Q2: Rootless コンテナと通常のコンテナの違いは？

**回答要点**：

```
通常のコンテナ（root モード）：
  - Docker daemon が root で動作
  - コンテナ内 UID 0 = ホスト UID 0
  - 強い権限、セキュリティリスク高い

Rootless コンテナ：
  - 全て非特権ユーザーで動作
  - User Namespace で UID マッピング
  - コンテナ内 UID 0 = ホスト UID 100000+
  - セキュリティリスク低い

制限事項：
  - 特権ポート (<1024) にバインド不可
  - 一部のネットワーク機能に制限
  - パフォーマンスが若干低下
```

### Q3: subuid/subgid を設定しないとどうなりますか？

**回答要点**：

```
問題：
  Rootless コンテナが起動できない
  「cannot find UID/GID mappings」エラー

原因：
  コンテナ内の複数 UID (0-65535) を
  ホストの UID にマッピングする範囲が未定義

解決策：
  1. /etc/subuid, /etc/subgid を設定
     例：testuser:100000:65536

  2. usermod で追加
     sudo usermod --add-subuids 100000-165535 $USER

  3. podman system migrate を実行
```

---

## 系列导航

[<- 03 - Namespace 深入](../03-namespace-deep-dive/) | [系列首页](../) | [05 - cgroups v2 架构 -->](../05-cgroups-v2-architecture/)
