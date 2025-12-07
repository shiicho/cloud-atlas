# 06 · State Manager 状态管理器（Ensure + Check 双关联）

> **目标**：用 **状态管理器（State Manager）+ AWS-RunShellScript（内联脚本）** 完成一次完整闭环：**创建关联 → 目标选择 → 调度 → 合规与执行日志**。
> **前置**：已完成 [01](../01-cfn-deploy/)、[02](../02-session-manager/)、[03](../03-run-command/)；实例为受管实例。
> **区域**：ap-northeast-1（或任意已启用 SSM 的区域）
> **费用**：State Manager 关联免费；EC2 按实例类型计费。课后可删除关联，保留或清理堆栈参考 [01 课清理](../01-cfn-deploy/)。

## 将完成的内容

1. 创建 **Ensure 关联**（修复/安装 `hc` 健康检查脚本）
2. 创建 **Check 关联**（合规判定，用退出码驱动 Compliant/Non-compliant）
3. 模拟漂移并验证自动纠偏流程
4. 在合规性仪表盘查看状态变化

## 核心概念

采用 **两条关联** 的生产式做法：

* **Ensure（确保/修复）**：下发并保持 `/usr/local/bin/hc` 存在可用（尽量返回 0）。
* **Check（判定/告警）**：只做合规判定，用**退出码**报告状态（非 0 = Non-compliant）。

`hc` 输出 **🟢/🟡/🔴** 与简报；支持 `--brief` 单行与**退出码语义**（绿=0，黄=1，红=2）。

## 系统 / Scope

* 全内联脚本、零外部依赖；聚焦 **保态** 与 **合规可视**。
* Association 计划（Schedule）最短 **30 分钟**；课堂可用 **Run association** 立即触发。
* 默认阈值：**黄 60% / 红 80%**（可用参数调整）。

## Step-by-step（精确控制台导航与命令）

### A. 创建 **Ensure** 关联（确保/修复）— 详细步骤

1. **AWS 控制台 → Systems Manager → 节点工具 → 状态管理器 → 创建关联**
2. **名称**：`InstallHealthcheckHC`
3. **文档**：`AWS-RunShellScript`
4. **参数 → Commands**：粘贴脚本（安装/更新 `hc` 并快速自测）：

```bash
#!/usr/bin/env bash
set -euo pipefail
TARGET="/usr/local/bin/hc"
umask 022

install_hc() {
  cat > "$TARGET" <<'BASH'
#!/usr/bin/env bash
# hc: Host health traffic light (CPU/Mem/Disk) with emoji & exit codes
# - Output: 🟢/🟡/🔴 + 简报；--brief 单行
# - Exit code: green=0, yellow=1, red=2
# - Thresholds: --yellow <60> --red <80>
set -euo pipefail

RED_T=80; YEL_T=60; BRIEF=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --red) RED_T="${2:-80}"; shift 2;;
    --yellow) YEL_T="${2:-60}"; shift 2;;
    --brief) BRIEF=1; shift;;
    -h|--help) cat <<USAGE
Usage: hc [--brief] [--yellow <60>] [--red <80>]
Exit code: green=0, yellow=1, red=2
Applies to CPU used %, Mem used %, Disk used % (max across filesystems)
USAGE
      exit 0;;
    *) shift;;
  esac
done

cpu_sample(){ read -r _ a b c d e f g h i j < /proc/stat; t1=$((a+b+c+d+e+f+g+h+i+j)); i1=$((d+e))
              sleep 1
              read -r _ a b c d e f g h i j < /proc/stat; t2=$((a+b+c+d+e+f+g+h+i+j)); i2=$((d+e))
              dt=$((t2-t1)); di=$((i2-i1))
              ((dt>0)) && awk -v busy="$((dt-di))" -v total="$dt" 'BEGIN{printf "%.1f", busy*100/total}' || echo "0.0"; }
mem_used(){ awk '/^MemTotal:/{t=$2}/^MemAvailable:/{a=$2}END{printf (t>0? "%.1f":"0.0"), (1-a/t)*100}' /proc/meminfo; }
disk_used_max(){ df -P -x tmpfs -x devtmpfs -x squashfs -x overlay 2>/dev/null | awk 'NR>1{gsub(/%/,"",$5);if($5>m)m=$5}END{printf"%.1f",(m+0)}'; }

cpu=$(cpu_sample); mem=$(mem_used); disk=$(disk_used_max)
classify(){ awk -v v="$1" -v y="$2" -v r="$3" 'BEGIN{print (v>=r)?"red":(v>=y)?"yellow":"green"}'; }
c_cpu=$(classify "$cpu" "$YEL_T" "$RED_T"); c_mem=$(classify "$mem" "$YEL_T" "$RED_T"); c_dsk=$(classify "$disk" "$YEL_T" "$RED_T")

overall="green"; for c in "$c_cpu" "$c_mem" "$c_dsk"; do [[ $c == red ]] && { overall=red; break; }; [[ $c == yellow && $overall != red ]] && overall=yellow; done
emoji="🟢"; code=0; [[ $overall == yellow ]] && { emoji="🟡"; code=1; }; [[ $overall == red ]] && { emoji="🔴"; code=2; }

if [[ $BRIEF -eq 1 ]]; then printf "%s cpu:%s%% mem:%s%% disk:%s%%\n" "$emoji" "$cpu" "$mem" "$disk"
else
  printf "%s Overall=%s (Y:%s%% / R:%s%%)\n" "$emoji" "$overall" "$YEL_T" "$RED_T"
  printf " - CPU : %5s%%  [%s]\n" "$cpu"  "$c_cpu"
  printf " - MEM : %5s%%  [%s]\n" "$mem"  "$c_mem"
  printf " - DISK: %5s%%  [%s] (max across filesystems)\n" "$disk" "$c_dsk"
fi
exit "$code"
BASH
  chmod 0755 "$TARGET"
}
install_hc

# Ensure 的关键：不把判定当失败（便于"修复"职责）
"$TARGET" --brief || true
echo "hc installed at $TARGET (version: $(date -u +%Y%m%d))"
```

5. **目标（Targets）**：选择目标 EC2（按标签或直接点选）。
6. **指定计划（Schedule）**：`rate(1 day)`（生产推荐较低频；课堂演示可手动 **Run association**）。
7. **合规性严重性**：`未指定` 或 `低`。
8. **创建关联**。

### B. 创建 **Check** 关联（判定/告警）— 简略步骤

> 只做**合规判定**，让"合规性（Association）"仪表盘出现 **Compliant / Non-compliant** 的真实波动。

1. **状态管理器 → 创建关联**

* **名称**：`CheckHealthHC`
* **文档**：`AWS-RunShellScript`
* **合规性严重性**：建议选 `中等` 或 `高`
* **参数 → Commands**：

```bash
#!/usr/bin/env bash
set -euo pipefail
# 1) 必须存在且可执行
test -x /usr/local/bin/hc || { echo "hc missing"; exit 2; }
# 2) 运行一次；让 hc 的退出码直接成为合规结果（绿=0，黄=1，红=2）
/usr/local/bin/hc --brief
```

* **目标**：与 Ensure 相同的实例集
* **计划**：`rate(30 minutes)`（最短）
* **创建关联**

## 验证 / Verify（会话管理器 + 合规性）— 重点演示"保态/纠偏"

参考第 02 课 [02 · Session Manager 免密登录 EC2（浏览器 Shell）](../02-session-manager/) ，在浏览器登录EC2，执行:

### A. 基线检查

```bash
which hc
hc --brief
echo "exit=$?"    # 0/1/2 = 绿/黄/红
```

### B. 制造"漂移"（破坏目标状态）

```bash
sudo mv /usr/local/bin/hc /usr/local/bin/hc.bak
# （或）sudo chmod 000 /usr/local/bin/hc
# （或）sudo truncate -s 0 /usr/local/bin/hc
```

确认漂移：

```bash
command -v hc || echo "hc: MISSING"
ls -l /usr/local/bin/hc*
```

### C. 先运行 **CheckHealthHC**（应变为 Non-compliant）

* **Console → Systems Manager → 状态管理器 → Associations → `CheckHealthHC` → Run association**
* 在 **Execution history** 查看 **Status / Detailed status / Output**（应失败，合规=Non-compliant）。

### D. 再运行 **InstallHealthcheckHC**（自动纠偏）

* 在 **`InstallHealthcheckHC`** 关联上点击 **Run association**。
* 成功后，回到 **`CheckHealthHC`** 再 **Run association** 一次。

### E. 合规视角（合规性页面）

1. **Systems Manager → 合规性**，筛选 **合规性类型 = Association**；
2. 表格中目标实例应显示 **Compliant**；
3. 点实例 → 查看 **执行历史（Execution history）**，能看到 **CheckHealthHC** 从**上次失败**到**本次成功** 的修复轨迹。

> 注：合规状态仅 **Compliant / Non-compliant** 两类；"已修正"通过历史对比体现。

## 运营模式对比（如何安排 Ensure/Check 的节奏与严重性）

| 模式 | Ensure（修复） | Check（判定/告警） | 适用场景 | 优点 | 注意点 |
|------|---------------|-------------------|---------|------|--------|
| **① 连续保态（推荐）** | **定期**，**较低频**：`rate(1 day)` | **定期**，**较高频**：`rate(30 minutes)` | 配置易被误改，需要"偏了就纠" | 漂移窗口短；人工负担低 | Check 可能先报 Non-compliant，再等下一轮 Ensure 修回 |
| **② 部署一次 + 持续监控** | **一次性**（创建后手动 Run 或临时开 `rate(30 minutes)` 跑完再停） | **定期**：`rate(30 minutes)` | 只想监控，不想自动改机器 | 变更面小、行为可预测 | 发现 Non-compliant 需人工或额外自动化触发修复 |
| **③ 事件驱动修复** | **禁用/不定期**，由事件触发（见下） | **定期**：`rate(30 minutes)` | 需要"发现→立刻修复"闭环 | 修复及时、无固定扰动 | 需配置 **EventBridge** 监听合规事件并触发 Run Command/Automation |

> 事件驱动修复示例：用 **EventBridge** 监听 *SSM Compliance* 变为 `NON_COMPLIANT`，自动触发一次 **Run Command/Automation** 执行 Ensure 脚本；这样 Check 报告后即可即时修复。

**本课推荐默认**：Ensure = `rate(1 day)`、Severity=`未指定/低`；Check = `rate(30 minutes)`、Severity=`中/高`。

## 清理 / Cleanup

```bash
sudo rm -f /usr/local/bin/hc
# Console → 状态管理器 → 勾选 InstallHealthcheckHC / CheckHealthHC → Delete
```

## 生产落地的常见场景（将"外壳"复用）

* **软件/代理基线**：Ensure 安装并确保 `systemd` 运行；Check 判定"在运行/端口就绪"。
* **配置文件保态**：Ensure 落盘并校验权限；Check 做哈希/片段比对。
* **安全加固**：Ensure 精准修改 `sshd_config` 并 reload；Check 用 `sshd -t` 或 grep 关键项判定。
* **清理与留痕**：Ensure 定期清理临时目录；Check 验证目录结构/剩余率是否达标。

> 共同结构：**Association 外壳（目标/调度/合规）** + **幂等脚本内核** → "偏离即纠"的生产基线。
> 需要 **<30 分钟** 巡检：用 **EventBridge（1 分钟）触发 Automation/Run Command** 或 **维护窗口（Maintenance Window）** 编排。

## 为什么这很强大 / Why this is powerful

* **保态（Drift Correction）**：Ensure 周期执行，持续把状态"修回去"。
* **合规可视**：Check 用退出码驱动 **Compliant / Non-compliant**，仪表盘/历史清晰呈现"失败→修复"。
* **可编排**：退出码可被 **Automation / 事件** 消费，形成"发现→修复"的闭环。
* **解耦与扩展**：把"做什么"与"何时/对谁做"分离；按标签自动纳管，低风险增量推广。
* **易回滚**：删除关联即可停用策略，变更可控。

---

## 下一步

- **[07 · Hybrid 托管](../07-hybrid/)**：将本地服务器或 Docker 容器纳入 SSM 托管
- **扩展练习**：用本课模式实现 logrotate 基线、SSH 加固、或服务自愈

## 系列导航 / Series Nav

| 课程 | 主题 |
|------|------|
| [01](../01-cfn-deploy/) | CloudFormation 部署 |
| [02](../02-session-manager/) | Session Manager 登录 |
| [03](../03-run-command/) | Run Command 批量执行 |
| [04](../04-parameter-store/) | Parameter Store |
| [05](../05-session-logging/) | Session Logging |
| **06** | **State Manager（本课）** |
| [07](../07-hybrid/) | Hybrid 托管 |
