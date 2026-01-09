# 09 - 容器安全：seccomp 与 Capabilities

> **目标**：理解容器安全边界，掌握 seccomp 和 Capabilities 配置，识别并避免常见安全反模式  
> **前置**：[Lesson 08 - 容器网络](../08-container-networking/)；了解 [LX08-SECURITY 第 6 课 Capabilities 基础](../../security/)  
> **时间**：2.5 小时  
> **场景**：セキュリティ監査対応（安全审计应对）  

---

## 将学到的内容

1. 理解容器安全边界的多层防御体系
2. 配置和调试 seccomp profile（系统调用过滤）
3. 管理容器 Capabilities（精细权限控制）
4. 识别危险的安全反模式（--privileged, docker.sock 等）
5. 使用 dmesg、audit.log、strace 调试安全问题

---

## 先跑起来：5 分钟体验 Capabilities 限制

> **不讲原理，先动手！** 你马上会看到容器权限被精确控制的效果。  

### 准备工作

确保 Docker 已安装（或使用 Podman）：

```bash
docker --version || podman --version
```

### 实验：Drop 所有 Capabilities

```bash
# 默认容器：可以执行 chown
docker run --rm alpine chown nobody /etc/passwd
echo "Exit code: $?"  # 0（成功）

# Drop 所有 capabilities：chown 失败！
docker run --rm --cap-drop=ALL alpine chown nobody /etc/passwd
echo "Exit code: $?"  # 1（失败）
```

输出：

```
chown: /etc/passwd: Operation not permitted
Exit code: 1
```

### 实验：只添加必需的 Capability

```bash
# Drop ALL + 只添加 CHOWN capability
docker run --rm --cap-drop=ALL --cap-add=CHOWN alpine chown nobody /etc/passwd
echo "Exit code: $?"  # 0（成功）
```

**你刚刚做了什么？**

```
默认容器                 --cap-drop=ALL            --cap-drop=ALL --cap-add=CHOWN
┌─────────────────┐     ┌─────────────────┐       ┌─────────────────┐
│ CAP_CHOWN       │     │                 │       │ CAP_CHOWN       │
│ CAP_DAC_OVERRIDE│     │ (无 Capability) │       │                 │
│ CAP_FOWNER      │     │                 │       │ (只有 CHOWN)    │
│ CAP_SETUID      │     │  chown 失败!    │       │  chown 成功!    │
│ ...14 more...   │     │                 │       │                 │
└─────────────────┘     └─────────────────┘       └─────────────────┘
      ↓                        ↓                         ↓
   权限太多              权限不足                    刚刚好!
```

这就是**最小权限原则**在容器中的应用。

---

## 发生了什么？

### 容器安全边界的多层防御

容器安全不是单一机制，而是多层防御的组合：

```
┌─────────────────────────────────────────────────────────────────────┐
│                        容器安全边界                                  │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  Layer 1: Namespace (可见性隔离)                                    │
│  ┌────────────────────────────────────────────────────────────┐     │
│  │ PID / Mount / Network / UTS / IPC / User / Cgroup          │     │
│  │ 控制进程「能看到什么」                                      │     │
│  └────────────────────────────────────────────────────────────┘     │
│                                                                     │
│  Layer 2: cgroups (资源限制)                                        │
│  ┌────────────────────────────────────────────────────────────┐     │
│  │ CPU / Memory / IO / PIDs                                    │     │
│  │ 控制进程「能用多少」                                        │     │
│  └────────────────────────────────────────────────────────────┘     │
│                                                                     │
│  Layer 3: Capabilities (特权分解)                                   │
│  ┌────────────────────────────────────────────────────────────┐     │
│  │ CAP_NET_BIND_SERVICE / CAP_CHOWN / CAP_SYS_ADMIN / ...      │     │
│  │ 控制进程「能做什么操作」                                    │     │
│  └────────────────────────────────────────────────────────────┘     │
│                                                                     │
│  Layer 4: seccomp (系统调用过滤)                                    │
│  ┌────────────────────────────────────────────────────────────┐     │
│  │ 允许/禁止特定系统调用                                       │     │
│  │ 控制进程「能调用什么内核接口」                              │     │
│  └────────────────────────────────────────────────────────────┘     │
│                                                                     │
│  Layer 5: AppArmor/SELinux (MAC 强制访问控制)                       │
│  ┌────────────────────────────────────────────────────────────┐     │
│  │ 基于策略的访问控制                                          │     │
│  │ 控制进程「能访问什么资源」                                  │     │
│  └────────────────────────────────────────────────────────────┘     │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

本课重点：**Layer 3 (Capabilities)** 和 **Layer 4 (seccomp)**。

---

## 核心概念：Capabilities

### 回顾：从 LX08-SECURITY 到容器

在 [LX08-SECURITY 第 6 课](../../security/) 中，你学习了 Linux Capabilities 的基础：

- 传统 Unix：root (UID 0) 拥有所有权限，普通用户几乎没有
- Capabilities：将 root 权限分解为 40+ 个细粒度能力
- 文件 Capabilities：使用 `getcap`/`setcap` 给可执行文件赋予特定能力

**LX11 在此基础上添加**：

- 容器如何继承和限制 Capabilities
- `--cap-drop` 和 `--cap-add` 的使用
- 安全审计时如何解释 Capabilities 配置

### Docker 默认 Capabilities

Docker 默认保留 14 个 Capabilities（出于兼容性考虑）：

```bash
# 查看容器的 Capabilities
docker run --rm alpine cat /proc/1/status | grep Cap
```

输出：

```
CapInh: 0000000000000000
CapPrm: 00000000a80425fb
CapEff: 00000000a80425fb
CapBnd: 00000000a80425fb
CapAmb: 0000000000000000
```

解码 Capabilities：

```bash
# 将 hex 值解码为可读名称
capsh --decode=00000000a80425fb
```

输出：

```
0x00000000a80425fb=cap_chown,cap_dac_override,cap_fowner,cap_fsetid,
cap_kill,cap_setgid,cap_setuid,cap_setpcap,cap_net_bind_service,
cap_net_raw,cap_sys_chroot,cap_mknod,cap_audit_write,cap_setfcap
```

### 常见 Capabilities 说明

| Capability | 作用 | 容器中的典型用途 |
|------------|------|------------------|
| `CAP_CHOWN` | 改变文件所有者 | 安装软件包 |
| `CAP_NET_BIND_SERVICE` | 绑定 <1024 端口 | Web 服务器 |
| `CAP_NET_RAW` | 使用原始套接字 | ping, tcpdump |
| `CAP_SETUID` | 切换用户 ID | 进程切换用户 |
| `CAP_SYS_ADMIN` | 系统管理（危险！） | **应避免** |
| `CAP_SYS_PTRACE` | 调试其他进程 | 调试工具 |

### 最小权限配置

**安全最佳实践**：Drop ALL，只添加必需的。

```bash
# 示例：运行 Nginx（需要绑定 80 端口）
docker run --rm \
  --cap-drop=ALL \
  --cap-add=NET_BIND_SERVICE \
  --cap-add=CHOWN \
  --cap-add=SETUID \
  --cap-add=SETGID \
  nginx:alpine
```

---

## 核心概念：seccomp

### 什么是 seccomp？

**seccomp (Secure Computing Mode)** 是 Linux 内核的系统调用过滤机制：

- 限制进程可以调用的系统调用（syscall）
- 比 Capabilities 更细粒度
- 在系统调用执行前检查，拒绝危险调用

### Docker 默认 seccomp Profile

Docker 默认启用 seccomp profile，阻止约 44 个危险系统调用：

```
Docker 默认 seccomp 阻止的系统调用（部分）：

┌──────────────────┬──────────────────────────────────────────────┐
│ 系统调用          │ 被阻止原因                                    │
├──────────────────┼──────────────────────────────────────────────┤
│ mount            │ 挂载文件系统 - 可逃逸容器                     │
│ umount           │ 卸载文件系统                                  │
│ ptrace           │ 进程追踪 - 可调试/劫持其他进程                │
│ personality      │ 设置进程执行域 - 可绕过安全限制               │
│ keyctl           │ 内核密钥管理                                  │
│ add_key          │ 添加密钥到内核                                │
│ request_key      │ 请求内核密钥                                  │
│ init_module      │ 加载内核模块 - 可完全控制内核                 │
│ delete_module    │ 删除内核模块                                  │
│ kexec_load       │ 加载新内核 - 可替换运行的内核                 │
│ reboot           │ 重启系统                                      │
│ swapon/swapoff   │ 交换空间控制                                  │
│ ...              │ ...                                           │
└──────────────────┴──────────────────────────────────────────────┘
```

### 验证 seccomp 生效

```bash
# 尝试在容器中执行 mount（默认被阻止）
docker run --rm alpine mount -t proc proc /tmp
```

输出：

```
mount: permission denied (are you root?)
```

即使是 root，seccomp 也阻止了 `mount` 系统调用。

---

## 动手练习

### Lab 1：seccomp Profile 实验

**目标**：理解 seccomp 如何阻止危险系统调用。

**运行演示脚本**：

```bash
cd ~/cloud-atlas/foundations/linux/containers/09-container-security/code
./seccomp-demo.sh
```

**或手动执行**：

**步骤 1：验证默认 seccomp 阻止 unshare**

```bash
# unshare 系统调用被默认 profile 阻止（除非有特定 capability）
docker run --rm alpine unshare --fork --pid --mount-proc /bin/sh -c "echo PID: $$"
```

输出（可能失败或成功，取决于 capability）：

```
unshare: unshare(0x60000000): Operation not permitted
```

**步骤 2：禁用 seccomp 后可以执行**

> **警告**：仅在隔离测试环境中执行！  

```bash
# 禁用 seccomp（危险！）
docker run --rm --security-opt seccomp=unconfined alpine \
  unshare --fork --pid --mount-proc /bin/sh -c "echo PID: \$\$"
```

输出：

```
PID: 1
```

**步骤 3：查看被阻止的证据（在宿主机）**

```bash
# 检查内核日志
dmesg | grep -i seccomp | tail -5
```

输出示例：

```
[12345.678901] audit: type=1326 ... syscall=56 compat=0 ... exe="/bin/unshare" ...
```

syscall=56 是 `clone` 系统调用（unshare 内部使用）。

---

### Lab 2：Capabilities 实验

**目标**：使用 `--cap-drop=ALL --cap-add=...` 最小化权限。

**运行演示脚本**：

```bash
cd ~/cloud-atlas/foundations/linux/containers/09-container-security/code
./capabilities-demo.sh
```

**或手动执行**：

**步骤 1：演示 CAP_NET_RAW（ping 需要）**

```bash
# 默认可以 ping
docker run --rm alpine ping -c 1 8.8.8.8

# Drop CAP_NET_RAW 后不能 ping
docker run --rm --cap-drop=NET_RAW alpine ping -c 1 8.8.8.8
```

输出：

```
PING 8.8.8.8 (8.8.8.8): 56 data bytes
ping: permission denied (are you root?)
```

**步骤 2：演示 CAP_NET_BIND_SERVICE（绑定低端口）**

```bash
# 创建测试脚本
docker run --rm alpine sh -c "nc -l -p 80 &"  # 默认可以

# Drop 后失败
docker run --rm --cap-drop=NET_BIND_SERVICE alpine sh -c "nc -l -p 80"
# 可能需要安装 nc: apk add netcat-openbsd
```

**步骤 3：完整最小权限示例**

```bash
# Nginx 最小权限配置
docker run --rm -d \
  --name nginx-minimal \
  --cap-drop=ALL \
  --cap-add=NET_BIND_SERVICE \
  --cap-add=CHOWN \
  --cap-add=SETUID \
  --cap-add=SETGID \
  --cap-add=DAC_OVERRIDE \
  nginx:alpine

# 验证运行
docker ps | grep nginx-minimal

# 清理
docker rm -f nginx-minimal
```

---

### Lab 3：安全反模式演示

> **警告**：以下演示仅用于教育目的，**必须在隔离的测试环境中执行**！  
> 永远不要在生产环境使用这些危险配置！  

**目标**：理解为什么 `--privileged` 和 `docker.sock` 挂载是危险的。

#### 反模式 1：--privileged 绕过所有隔离

```bash
# 演示 --privileged 可以访问宿主机设备
docker run --rm --privileged alpine ls /dev | head -20
```

输出（可以看到宿主机所有设备）：

```
autofs
bsg
btrfs-control
console
...
sda
sda1
...
```

**危险**：`--privileged` 容器可以：
- 访问所有设备（包括磁盘）
- 挂载宿主机文件系统
- 加载内核模块
- 基本等同于 root 直接在宿主机执行

```bash
# 演示：privileged 容器可以挂载宿主机磁盘！
docker run --rm --privileged alpine sh -c "mkdir /hostroot && mount /dev/sda1 /hostroot && ls /hostroot" 2>/dev/null || echo "（需要实际磁盘设备）"
```

#### 反模式 2：挂载 docker.sock

```bash
# 挂载 docker.sock 的容器可以控制所有容器！
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock alpine sh -c "
  apk add --no-cache docker-cli >/dev/null 2>&1
  docker ps
"
```

输出（可以看到宿主机所有容器）：

```
CONTAINER ID   IMAGE   ...
abc123         nginx   ...
def456         redis   ...
```

**危险**：拥有 docker.sock 访问权的容器可以：
- 查看、启动、停止所有容器
- 启动特权容器
- 访问其他容器的数据
- **等同于宿主机 root 权限**

#### 反模式 3：禁用 seccomp

```bash
# --security-opt seccomp=unconfined 允许所有系统调用
docker run --rm --security-opt seccomp=unconfined alpine whoami
```

虽然看起来无害，但：
- 攻击者可以利用内核漏洞
- mount、ptrace 等危险调用不受限
- 大大增加攻击面

#### 反模式 4：CAP_SYS_ADMIN 授权

```bash
# CAP_SYS_ADMIN 是最危险的 capability
docker run --rm --cap-add=SYS_ADMIN alpine cat /proc/1/status | grep Cap
```

**CAP_SYS_ADMIN 允许**：
- 挂载文件系统
- 配置内核参数
- 使用 perf_event
- 基本接近 root

---

## 安全调试技巧

当容器因安全策略失败时，如何定位问题？

### 方法 1：检查 dmesg（seccomp 拒绝）

```bash
# 在宿主机执行
dmesg | grep -i seccomp | tail -10

# 或使用 journalctl
journalctl -k | grep -i seccomp | tail -10
```

输出示例：

```
[xxxxx.xxxxxx] audit: type=1326 audit(xxx): ... syscall=56 ... exe="/bin/unshare" ...
```

解码 syscall 编号：

```bash
# syscall 56 是什么？
ausyscall 56  # 需要 auditd 包
# 或查表：https://filippo.io/linux-syscall-table/
```

### 方法 2：检查 audit.log（SELinux/AppArmor 拒绝）

```bash
# 检查审计日志
sudo cat /var/log/audit/audit.log | grep -i denied | tail -10

# 使用 ausearch（更易读）
sudo ausearch -m avc -ts recent
```

### 方法 3：使用 strace 追踪系统调用

```bash
# 在容器中追踪系统调用
docker run --rm --cap-add=SYS_PTRACE alpine sh -c "
  apk add --no-cache strace >/dev/null 2>&1
  strace -f ping -c 1 8.8.8.8 2>&1 | head -30
"
```

**注意**：`strace` 需要 `CAP_SYS_PTRACE` capability。

### 调试工作流

```
容器启动/运行失败
        │
        ▼
┌───────────────────┐
│ 1. 检查容器日志   │  docker logs <container>
└────────┬──────────┘
         │ 无有用信息？
         ▼
┌───────────────────┐
│ 2. 检查 dmesg     │  dmesg | grep -i seccomp
└────────┬──────────┘  dmesg | grep -i oom
         │ 发现 seccomp 拒绝？
         ▼
┌───────────────────┐
│ 3. 解码 syscall   │  ausyscall <number>
└────────┬──────────┘
         │ 确认需要的系统调用
         ▼
┌───────────────────┐
│ 4. 调整 profile   │  自定义 seccomp profile
└───────────────────┘  或添加所需 capability
```

---

## 职场小贴士

### 日本 IT 现场常见场景

**场景 1：セキュリティ監査でコンテナ権限確認（安全审计容器权限）**

```
監査員：「このコンテナの権限設定を説明してください」

確認コマンド：
# 1. 容器的 capability 配置
docker inspect <container> | jq '.[0].HostConfig.CapAdd'
docker inspect <container> | jq '.[0].HostConfig.CapDrop'

# 2. seccomp profile 確認
docker inspect <container> | jq '.[0].HostConfig.SecurityOpt'

# 3. 特権モード確認（最重要！）
docker inspect <container> | jq '.[0].HostConfig.Privileged'

回答例：
「このコンテナは --cap-drop=ALL で全 capability を削除し、
 必要最小限の NET_BIND_SERVICE のみ追加しています。
 --privileged は使用していません。」
```

**场景 2：--privileged 使用の説明を求められる**

```
状況：開発者が --privileged を使いたいと言う

対応：
1. なぜ必要か具体的に確認
2. 代替案を提案

代替案例：
- mount が必要 → CAP_SYS_ADMIN より安全な設計を検討
- デバイスアクセス → --device=/dev/xxx で特定デバイスのみ
- ホストネットワーク → --network=host（privileged より狭い）

報告：
「--privileged の代わりに --cap-add=XXX で対応しました。
 セキュリティリスクを最小化しています。」
```

**场景 3：コンテナ起動失敗のトラブルシューティング**

```
問題：アプリがコンテナで起動しない

調査手順：
1. docker logs <container>                    # アプリログ確認
2. dmesg | grep -i seccomp                    # seccomp 拒否確認
3. docker inspect <container> | grep -i cap   # capability 確認

よくある原因：
- CAP_NET_BIND_SERVICE 不足（80番ポートバインド失敗）
- seccomp で必要な syscall が拒否
- CAP_CHOWN 不足（ファイル権限変更失敗）
```

### 安全配置チェックリスト

```markdown
## コンテナセキュリティチェックリスト

### 基本設定
- [ ] --privileged を使用していない
- [ ] /var/run/docker.sock をマウントしていない
- [ ] --security-opt seccomp=unconfined を使用していない

### Capabilities
- [ ] --cap-drop=ALL から始めている
- [ ] 必要最小限の capability のみ追加
- [ ] CAP_SYS_ADMIN を使用していない

### ユーザー
- [ ] USER 指令で非 root ユーザー指定
- [ ] または --user オプションで非 root 実行

### ファイルシステム
- [ ] --read-only で読み取り専用（可能な場合）
- [ ] 機密データは volume でなく secret 使用
```

---

## 检查清单

完成本课后，你应该能够：

- [ ] 説明容器安全边界的多层防御体系（Namespace, cgroups, Capabilities, seccomp）
- [ ] 使用 `--cap-drop=ALL --cap-add=...` 配置最小权限
- [ ] 解释 Docker 默认保留的 14 个 Capabilities 及其作用
- [ ] 理解 seccomp 默认 profile 阻止的危险系统调用
- [ ] 使用 `dmesg` 查看 seccomp 拒绝日志
- [ ] 识别 4 大安全反模式及其危险性：
  - `--privileged`
  - 挂载 `docker.sock`
  - `--security-opt seccomp=unconfined`
  - `CAP_SYS_ADMIN`
- [ ] 向安全审计解释容器权限配置
- [ ] 调试因安全策略导致的容器启动失败

---

## 延伸阅读

### 官方文档

- [Docker Security - Kernel namespaces](https://docs.docker.com/engine/security/)
- [Docker seccomp profiles](https://docs.docker.com/engine/security/seccomp/)
- [Linux Capabilities - man 7 capabilities](https://man7.org/linux/man-pages/man7/capabilities.7.html)
- [seccomp - Kernel Documentation](https://www.kernel.org/doc/Documentation/prctl/seccomp_filter.txt)

### 相关课程

- [LX08-SECURITY 第 6 课 - Linux Capabilities](../../security/) - Capabilities 基础
- [Lesson 04 - User Namespace](../04-user-namespace-rootless/) - 用户隔离和 rootless 容器
- [Lesson 11 - 容器故障排查](../11-debugging-troubleshooting/) - 完整调试方法论

### 推荐阅读

- *Container Security* by Liz Rice - 全面的容器安全指南
- [Falco](https://falco.org/) - 运行时容器安全监控
- [Docker Bench for Security](https://github.com/docker/docker-bench-security) - 自动化安全检查

---

## 系列导航

[<-- 08 - 容器网络](../08-container-networking/) | [Home](../) | [10 - OCI 运行时 -->](../10-oci-runtimes/)
