# Ansible Inventory 渐进式示例
# Progressive Ansible Inventory Examples

本目录包含 7 个渐进式 Ansible Inventory 示例，从最简单到较复杂，每个示例都引入新概念。

This directory contains 7 progressive Ansible inventory examples, from simplest to more complex, with each example introducing new concepts.

---

## 学习路径 / Learning Path

### 01-basic-hosts - 最基础的清单
**新概念**: 主机列表

- 最简单的 inventory 文件
- 仅列出主机名，没有分组
- 所有主机自动属于 `all` 组

**测试命令**:
```bash
ansible -i 01-basic-hosts all --list-hosts
ansible -i 01-basic-hosts all -m ping
```

---

### 02-with-groups - 引入分组
**新概念**: 功能性分组 (webservers, dbservers)

- 按角色组织主机
- 可以针对特定组执行命令
- 基础的基础设施逻辑划分

**测试命令**:
```bash
ansible -i 02-with-groups webservers --list-hosts
ansible -i 02-with-groups dbservers -m ping
```

---

### 03-host-ranges - 范围表示法
**新概念**: `[START:END]` 主机范围语法

- 使用范围表示法简化大规模主机列表
- 语法: `hostname-[1:10].domain.com`
- 适用于统一命名的基础设施

**测试命令**:
```bash
ansible -i 03-host-ranges amazon_linux --list-hosts
```

**扩展说明**:
- `al2023-[1:2].ans.local` → 扩展为 2 台主机
- `al2023-[1:10].ans.local` → 可扩展到 10 台主机
- `server-[a:z].example.com` → 也支持字母范围

---

### 04-group-vars - 组变量
**新概念**: `[groupname:vars]` 和 `[all:vars]` 变量作用域

- 为组定义变量
- 集中配置管理（端口、路径、设置）
- 避免在 playbook 中硬编码值

**测试命令**:
```bash
ansible -i 04-group-vars webservers -m debug -a "var=http_port"
ansible -i 04-group-vars dbservers -m debug -a "var=db_port"
ansible -i 04-group-vars all -m debug -a "var=ansible_python_interpreter"
```

**变量优先级**:
1. 主机变量 (host_vars)
2. 组变量 (group_vars)
3. all 组变量

---

### 05-children-groups - 层级分组
**新概念**: `[parent:children]` 父子组关系

- 创建组的组 (group of groups)
- 按环境组织 (production, staging, dev)
- 对多个组同时应用设置

**测试命令**:
```bash
ansible -i 05-children-groups production --list-hosts
ansible -i 05-children-groups all -m debug -a "var=env"
```

**层级示例**:
```
production
├── webservers
│   └── al2023-1.ans.local
└── dbservers
    └── al2023-2.ans.local
```

---

### 06-yaml-format - YAML 格式
**新概念**: YAML inventory 格式 (与 INI 等效)

- 更结构化的 inventory 格式
- 原生数据类型 (列表、字典、布尔值)
- 适合复杂层级和版本控制

**测试命令**:
```bash
ansible -i 06-yaml-format/hosts.yaml all --list-hosts
ansible -i 06-yaml-format/hosts.yaml production -m debug -a "var=env"
```

**INI vs YAML 对比**:
| INI 格式 | YAML 格式 |
|---------|----------|
| `[webservers]` | `webservers:` |
| `[webservers:vars]` | `webservers: vars:` |
| `[production:children]` | `production: children:` |
| `http_port=80` | `http_port: 80` |

---

### 07-control-local - 包含控制节点
**新概念**: `ansible_connection=local` 本地连接

- 将控制节点本身加入 inventory
- 使用本地连接跳过 SSH
- 逻辑分离：控制节点 vs 被管理节点

**测试命令**:
```bash
ansible -i 07-control-local control -m ping
ansible -i 07-control-local managed --list-hosts
ansible -i 07-control-local all --list-hosts
```

**使用场景**:
- 控制节点自我配置 (安装工具、配置 git 等)
- 部署前在本地测试 playbook
- 运行本地预检查

---

## 推荐学习顺序 / Recommended Learning Order

1. **基础** (01-02): 了解 inventory 基本概念
2. **扩展** (03-04): 学习规模化和变量管理
3. **进阶** (05-07): 掌握层级结构和特殊连接方式

## 实验环境 / Lab Environment

本示例使用的主机名基于 Route 53 Private Hosted Zone:
- `al2023-1.ans.local` (webserver)
- `al2023-2.ans.local` (dbserver)
- `control.ans.local` (control node)

## 进一步学习 / Further Learning

- **动态 Inventory**: AWS EC2, Azure, GCP 插件
- **Inventory 插件**: 自定义数据源
- **host_vars/ 和 group_vars/ 目录**: 将变量分离到独立文件
- **Ansible Vault**: 加密敏感变量

## 参考资料 / References

- [Ansible Inventory 官方文档](https://docs.ansible.com/ansible/latest/user_guide/intro_inventory.html)
- [YAML Inventory 格式](https://docs.ansible.com/ansible/latest/user_guide/intro_inventory.html#inventory-basics-formats-hosts-and-groups)
- [变量优先级](https://docs.ansible.com/ansible/latest/user_guide/playbooks_variables.html#variable-precedence-where-should-i-put-a-variable)
