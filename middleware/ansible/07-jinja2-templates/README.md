# 07 · Jinja2 模板引擎详解（Template Engine Mastery）

> **目标**：掌握 Jinja2 模板技术  
> **前置**：[06 · Roles 与 Galaxy](../06-roles-galaxy/)  
> **时间**：35 分钟  
> **实战项目**：模板化 Nginx 配置

---

## 将学到的内容

1. Jinja2 语法：变量、过滤器、测试
2. 控制结构：for、if
3. 常用过滤器
4. template 模块使用

---

## 准备环境

```bash
# 1. 切换到 ansible 用户（如果当前不是 ansible 用户）
[ "$(whoami)" != "ansible" ] && sudo su - ansible

# 2. 更新课程仓库（获取最新内容）
cd ~/repo && git pull

# 3. 进入本课目录
cd ~/07-jinja2-templates

# 4. 确认 Managed Nodes 可连接
ansible all -m ping
```

---

## Step 1 — Jinja2 基础语法

```jinja2
{{ variable }}         {# 变量输出 #}
{% if condition %}     {# 控制语句 #}
{# 这是注释 #}         {# 注释 #}
{{ var | filter }}     {# 过滤器 #}
```

```bash
# 查看基础模板示例
cat templates/app.conf.j2
```

---

## Step 2 — 常用过滤器

| 过滤器 | 说明 | 示例 |
|--------|------|------|
| `default` | 默认值 | `{{ var \| default('none') }}` |
| `upper/lower` | 大小写 | `{{ name \| upper }}` |
| `join` | 连接列表 | `{{ list \| join(',') }}` |
| `int/float` | 类型转换 | `{{ '80' \| int }}` |

```bash
# 查看过滤器示例
cat templates/filters-demo.txt.j2
cat exercises/04-template-filters.yaml

# 执行
ansible-playbook exercises/04-template-filters.yaml
```

---

## Step 3 — 条件和循环

```bash
# 查看条件语句示例
cat exercises/02-template-conditionals.yaml

# 查看循环示例
cat exercises/03-template-loops.yaml
cat templates/nginx.conf.j2
```

**核心语法**：

```jinja2
{# 条件 #}
{% if debug_mode %}
LogLevel debug
{% endif %}

{# 循环 #}
{% for server in servers %}
server {{ server.host }}:{{ server.port }};
{% endfor %}
```

```bash
# 执行
ansible-playbook exercises/02-template-conditionals.yaml
ansible-playbook exercises/03-template-loops.yaml
```

---

## Step 4 — Template 模块

**核心语法**：

```yaml
- name: Deploy config
  ansible.builtin.template:
    src: nginx.conf.j2
    dest: /etc/nginx/nginx.conf
    mode: '0644'
    backup: yes           # 备份原文件
    validate: nginx -t -c %s  # 部署前验证
  notify: Reload nginx
```

```bash
# 查看基础模板部署
cat exercises/01-template-basics.yaml

# 执行
ansible-playbook exercises/01-template-basics.yaml
```

---

## Step 5 — 实战：Nginx 配置

```bash
# 查看变量定义
cat vars/nginx.yaml

# 查看 Nginx 模板
cat templates/nginx.conf.j2

# 查看 /etc/hosts 模板
cat templates/hosts.j2
cat exercises/05-hosts-template.yaml

# 执行
ansible-playbook exercises/05-hosts-template.yaml

# 验证
ansible all -a "cat /etc/hosts"
```

---

## 动手前检查清单

| # | 检查项 | 验证命令 |
|---|--------|----------|
| 1 | 模板文件存在 | `ls templates/*.j2` |
| 2 | 语法正确 | `ansible-playbook site.yaml --syntax-check` |
| 3 | 干运行验证 | `ansible-playbook site.yaml -C -D` |

---

## 日本企業現場ノート

> 💼 **模板管理的企业实践**

| 要点 | 说明 |
|------|------|
| **管理者コメント** | 模板开头添加 `# Managed by Ansible` |
| **validate 必須** | 配置文件必须使用 `validate` 参数验证语法 |
| **backup 推奨** | 使用 `backup: yes` 保留变更前备份 |

> 💡 **面试要点**：template は変数展開、copy はそのままコピー

---

## 本课小结

| 概念 | 要点 |
|------|------|
| `{{ }}` | 变量输出 |
| `{% %}` | 控制语句 |
| `{# #}` | 注释 |
| 过滤器 | `\| default()`, `\| join()` |
| template 模块 | 部署 Jinja2 模板 |

---

## 清理资源

> **保留 Managed Nodes** - 后续课程都需要使用。
>
> 学完所有课程后，请参考 [课程首页的清理资源](../#清理资源) 删除所有节点。

---

## 系列导航

← [06 · Roles](../06-roles-galaxy/) | [Home](../) | [Next →](../08-error-handling/)
