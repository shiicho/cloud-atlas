# Lesson 07 - Jinja2 模板练习

本目录包含 5 个 Jinja2 模板实战练习。

## 练习清单

### 01-template-basics.yaml - 基础模板
**学习目标**: 理解 template 模块和变量引用

```bash
ansible-playbook 01-template-basics.yaml
```

**知识点**:
- `ansible.builtin.template` 模块
- `{{ variable }}` 语法
- `{{ ansible_managed }}` 标记

---

### 02-template-conditionals.yaml - 条件语句
**学习目标**: 在模板中使用 if/else/elif

```bash
# 开发环境
ansible-playbook 02-template-conditionals.yaml

# 生产环境
ansible-playbook 02-template-conditionals.yaml -e "environment=production"
```

**知识点**:
- `{% if %} ... {% elif %} ... {% else %} ... {% endif %}`
- 布尔值处理 `| lower`

---

### 03-template-loops.yaml - 循环语句
**学习目标**: 在模板中使用 for 循环

```bash
ansible-playbook 03-template-loops.yaml
```

**知识点**:
- `{% for item in list %} ... {% endfor %}`
- `loop.index`, `loop.first`, `loop.last`
- 嵌套循环

---

### 04-template-filters.yaml - 常用过滤器
**学习目标**: 掌握 Jinja2 过滤器

```bash
ansible-playbook 04-template-filters.yaml
```

**知识点**:
- 字符串: `upper`, `lower`, `replace`, `regex_replace`
- 列表: `join`, `first`, `last`, `sort`
- 默认值: `default`
- 转换: `int`, `string`, `from_json`, `to_yaml`

---

### 05-hosts-template.yaml - 动态 /etc/hosts
**学习目标**: 使用 hostvars 和 groups

```bash
ansible-playbook 05-hosts-template.yaml
```

**知识点**:
- `groups['all']` 访问所有主机
- `hostvars[host]` 访问其他主机变量
- 动态生成配置文件

---

## 模板文件结构

```
07-jinja2-templates/
├── exercises/
│   ├── 01-template-basics.yaml
│   ├── 02-template-conditionals.yaml
│   ├── 03-template-loops.yaml
│   ├── 04-template-filters.yaml
│   ├── 05-hosts-template.yaml
│   └── README.md
├── templates/
│   ├── app.conf.j2
│   ├── env.conf.j2
│   ├── nginx.conf.j2
│   ├── filters-demo.txt.j2
│   └── hosts.j2
└── vars/
```

## 验证命令

```bash
# 查看生成的配置
ansible all -a "cat /etc/myapp/app.conf" --become

# 对比 Diff
ansible-playbook 01-template-basics.yaml --check --diff
```

## 清理

```bash
# 删除测试配置
ansible all -m file -a "path=/etc/myapp state=absent" --become

# 恢复原始 hosts
ansible all -m copy -a "src=/etc/hosts.bak dest=/etc/hosts remote_src=yes" --become
```
