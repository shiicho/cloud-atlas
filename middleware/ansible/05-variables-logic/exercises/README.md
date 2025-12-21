# Lesson 05 - 变量・Facts・条件・循环 练习

本目录包含 7 个实战练习，帮助你掌握 Ansible 的变量系统和控制流。

## 练习清单

### 01-facts-explore.yaml - 探索 Facts
**学习目标**: 理解 Facts 的结构和使用方法

```bash
# 基本执行
ansible-playbook 01-facts-explore.yaml

# 显示所有 facts（输出很长！）
ansible-playbook 01-facts-explore.yaml -e "show_all_facts=true"
```

**知识点**:
- `gather_facts: true` 收集系统信息
- `ansible_hostname`, `ansible_distribution` 等常用 Facts
- `ansible_mounts` 循环显示挂载点

---

### 02-register-output.yaml - Register 捕获输出
**学习目标**: 理解如何使用 register 捕获命令输出

```bash
ansible-playbook 02-register-output.yaml
```

**知识点**:
- `register:` 保存任务输出
- `.stdout`, `.stdout_lines`, `.rc` 属性
- `changed_when: false` 标记信息收集任务

---

### 03-conditionals.yaml - 条件判断
**学习目标**: 掌握各种条件判断模式

```bash
# 默认执行
ansible-playbook 03-conditionals.yaml

# 传入可选变量
ansible-playbook 03-conditionals.yaml -e "optional_var=hello"
```

**知识点**:
- `when:` 基本条件
- Facts 条件: `ansible_distribution == "Amazon"`
- AND 条件（列表形式）
- OR 条件
- `is defined` / `is not defined`

---

### 04-loops-basic.yaml - 基本循环
**学习目标**: 掌握 loop 的使用

```bash
ansible-playbook 04-loops-basic.yaml
```

**知识点**:
- `loop:` 遍历列表
- 字典循环 `{{ item.name }}`
- `loop_control:` 控制输出

---

### 05-loops-advanced.yaml - 高级循环
**学习目标**: 掌握高级循环模式

```bash
# 执行
ansible-playbook 05-loops-advanced.yaml

# 仅清理
ansible-playbook 05-loops-advanced.yaml --tags cleanup
```

**知识点**:
- `with_sequence:` 数字序列
- `with_dict:` 字典遍历
- `with_subelements:` 嵌套循环
- `until:` 重试模式
- `with_random_choice:` 随机选择

---

### 06-vars-files.yaml - 外部变量文件
**学习目标**: 使用 vars_files 加载外部变量

```bash
ansible-playbook 06-vars-files.yaml
```

**知识点**:
- `vars_files:` 加载外部 YAML
- 变量文件组织（group_vars/）

---

### 07-multi-os.yaml - 多操作系统支持
**学习目标**: 使用 Facts + When 实现跨平台 Playbook

```bash
ansible-playbook 07-multi-os.yaml --check --diff
```

**知识点**:
- `set_fact:` 动态设置变量
- 字典查找 `{{ dict[key] }}`
- 跨平台包管理（dnf vs apt）

---

## 变量文件结构

```
05-variables-logic/
├── exercises/
│   ├── 01-facts-explore.yaml
│   ├── 02-register-output.yaml
│   ├── 03-conditionals.yaml
│   ├── 04-loops-basic.yaml
│   ├── 05-loops-advanced.yaml
│   ├── 06-vars-files.yaml
│   ├── 07-multi-os.yaml
│   └── README.md
├── group_vars/
│   └── common.yaml
└── host_vars/
    └── (host specific vars)
```

## 验证命令

```bash
# 查看主机变量
ansible-inventory --host web-1.ans.local --yaml

# 验证变量加载
ansible all -m debug -a "var=hostvars[inventory_hostname]"

# 查看特定 Fact
ansible all -m setup -a "filter=ansible_distribution*"
```

## 清理环境

```bash
# 删除创建的用户
ansible all -m user -a "name=alice state=absent remove=yes" --become
ansible all -m user -a "name=bob state=absent remove=yes" --become
ansible all -m user -a "name=charlie state=absent remove=yes" --become

# 删除临时目录
ansible all -m file -a "path=/tmp/dir_01 state=absent" --become
```
