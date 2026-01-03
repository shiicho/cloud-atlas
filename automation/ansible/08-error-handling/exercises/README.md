# Lesson 08 - 错误处理与调试 练习

本目录包含 5 个错误处理实战练习。

## 练习清单

### 01-block-rescue.yaml - Block/Rescue/Always
**学习目标**: 理解 block/rescue/always 结构

```bash
# 正常执行（不触发 rescue）
ansible-playbook 01-block-rescue.yaml

# 强制失败（触发 rescue）
ansible-playbook 01-block-rescue.yaml -e "force_failure=true"
```

**知识点**:
- `block:` - 分组任务
- `rescue:` - 错误处理
- `always:` - 无论成功失败都执行

---

### 02-ignore-errors.yaml - 错误控制
**学习目标**: 控制任务失败行为

```bash
ansible-playbook 02-ignore-errors.yaml
```

**知识点**:
- `ignore_errors: true` - 忽略错误
- `failed_when:` - 自定义失败条件
- `changed_when:` - 控制 changed 状态

---

### 03-retry-until.yaml - 重试机制
**学习目标**: 使用 retries 和 until

```bash
ansible-playbook 03-retry-until.yaml
```

**知识点**:
- `until:` - 重试条件
- `retries:` - 最大重试次数
- `delay:` - 重试间隔（秒）
- `.attempts` - 实际尝试次数

---

### 04-assert-validation.yaml - 前置条件验证
**学习目标**: 使用 assert 模块

```bash
ansible-playbook 04-assert-validation.yaml
```

**知识点**:
- `assert:` - 断言验证
- `that:` - 条件列表
- `fail_msg:` / `success_msg:` - 自定义消息

---

### 05-deployment-rollback.yaml - 生产级部署
**学习目标**: 实现带回滚机制的部署

```bash
# 预览
ansible-playbook 05-deployment-rollback.yaml --check

# 执行
ansible-playbook 05-deployment-rollback.yaml
```

**知识点**:
- 完整的 block/rescue/always 模式
- 备份和回滚策略
- 健康检查
- `serial: 1` 滚动部署
- 日志记录

---

## 调试技巧

```bash
# 详细输出
ansible-playbook playbook.yaml -v      # 基本
ansible-playbook playbook.yaml -vv     # 更多
ansible-playbook playbook.yaml -vvv    # 连接详情

# 逐步执行
ansible-playbook playbook.yaml --step

# 从特定任务开始
ansible-playbook playbook.yaml --start-at-task="Task Name"

# 列出所有任务
ansible-playbook playbook.yaml --list-tasks
```

## 常见调试场景

| 问题 | 调试方法 |
|------|----------|
| 变量值不对 | `debug` 模块输出 |
| SSH 连接失败 | `-vvv` 查看详情 |
| 模块参数错误 | `--check` 模式 |
| 条件不生效 | 输出 `when` 中的变量 |
