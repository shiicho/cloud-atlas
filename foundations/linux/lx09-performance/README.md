# Linux 性能分析（Linux Performance Analysis）

> **系列目标**：掌握系统性能分析方法论与工具链  
> **适合人群**：中高级运维工程师、SRE、想提升障害対応能力的日本 IT 从业者  
> **预计时长**：20-25 小时  

---

## 课程特色

- **方法论先行**：USE Method 作为思维框架，避免"工具购物"
- **问题导向**：先问"什么慢？"再选工具
- **基线第一**：永远先测量，再调优
- **真实场景**：7 个日本 IT 场景（夜间バッチ、障害対応、性能監視）
- **层层深入**：System -> Process -> Syscall -> Kernel

---

## 版本兼容性

| 工具 | 课程版本 | 当前最新 | 说明 |
|------|----------|----------|------|
| **sysstat** | 12.5+ | 12.7.6 (2024) | iostat、mpstat、pidstat |
| **perf** | 5.4+ | 6.x (2025) | 内核自带性能分析器 |
| **BCC tools** | 0.24+ | 0.31.0 (2025) | eBPF 工具集 |
| **bpftrace** | 0.17+ | 0.22.0 (2025) | eBPF 追踪语言 |
| **FlameGraph** | v1.0 | v1.0 (stable) | Brendan Gregg 火焰图脚本 |
| **Kernel** | 4.20+ | 6.12 | PSI 需要 4.20+，eBPF 推荐 5.x+ |
| **RHEL** | 8/9 | 9.5 | RHEL 8 支持至 2029 |
| **Ubuntu** | 20.04+ | 24.04 LTS | 22.04/24.04 推荐 |

**注意事项：**
- PSI (Pressure Stall Information) 需要 Linux 4.20+ 内核
- eBPF/BCC 工具在 RHEL 8.1+ 完整支持，推荐 RHEL 9
- `net.ipv4.tcp_tw_recycle` 在 Linux 4.12+ 已移除

---

## 课程大纲

| 课号 | 标题 | 核心内容 | 状态 |
|------|------|----------|------|
| 01 | [性能方法论（USE Method）](./01-use-methodology/) | USE 框架、四大资源、基线建立 | draft |
| 02 | CPU 分析 | top、mpstat、pidstat、PSI、Load Average | pending |
| 03 | 内存分析 | free、smem、pmap、slab、OOM Killer | pending |
| 04 | I/O 分析 | iostat、iotop、pidstat -d、I/O 调度器 | pending |
| 05 | 网络性能 | ss、iperf3、tcpdump、TCP 缓冲区 | pending |
| 06 | strace 系统调用追踪 | syscall 分析、性能模式识别 | pending |
| 07 | perf 性能分析器 | perf top/record/report、采样技术 | pending |
| 08 | Flamegraph 火焰图 | 生成与解读、On-CPU vs Off-CPU | pending |
| 09 | 内核调优（sysctl） | 安全调优、工作负载配置 | pending |
| 10 | eBPF 入门（BCC 工具） | 生产环境追踪、核心 BCC 工具 | pending |

---

## 学习路径

```
01 USE Method (方法论)
       │
       ▼
┌──────┴──────┐
│  资源分析    │
├─────────────┤
│ 02 CPU      │
│ 03 Memory   │
│ 04 Disk I/O │
│ 05 Network  │
└──────┬──────┘
       │
       ▼
┌──────┴──────┐
│  深度分析    │
├─────────────┤
│ 06 strace   │
│ 07 perf     │
│ 08 Flamegraph│
└──────┬──────┘
       │
       ▼
┌──────┴──────┐
│ 调优与追踪   │
├─────────────┤
│ 09 sysctl   │
│ 10 eBPF     │
└─────────────┘
```

---

## 前置课程

- **必须**：LX05-SYSTEMD（理解 cgroup v2、journalctl）
- **必须**：LX07-STORAGE（理解文件系统、I/O 调度器）
- **推荐**：LX06-NETWORK（TCP/IP 基础、ss 使用）
- **推荐**：LX03-TEXT（日志分析技能）

---

## 后续课程

- LX10-TROUBLESHOOTING（故障排查综合实战）
- LX11-CONTAINERS（容器性能分析）

---

## 职场关联

| 日语术语 | 读音 | 含义 |
|----------|------|------|
| 性能監視 | せいのうかんし | Performance monitoring |
| 性能劣化 | せいのうれっか | Performance degradation |
| ボトルネック | ボトルネック | Bottleneck |
| エビデンス | エビデンス | Evidence |
| チューニング | チューニング | Tuning |
| 負荷試験 | ふかしけん | Load testing |
| OOM Killer | OOMキラー | Out of Memory Killer |

---

## 认证对标

- **LPIC-3**：Capacity planning, Resource measurement, Kernel debugging
- **RHCE**：Performance Co-Pilot (PCP), cgroups resource limits
