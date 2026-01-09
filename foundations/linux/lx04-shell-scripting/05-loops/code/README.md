# Lesson 05 - 循环结构 代码示例

本目录包含 Lesson 05 的所有代码示例。

## 文件结构

```
code/
├── for_loop.sh       # for 循环各种用法演示
├── while_read.sh     # 正确读取文件的方法
├── bad/
│   └── for_ls.sh     # 反模式：for in $(ls) 的问题
└── good/
    └── for_glob.sh   # 最佳实践：正确遍历文件
```

## 运行方式

```bash
# 赋予执行权限
chmod +x *.sh bad/*.sh good/*.sh

# 运行示例
./for_loop.sh
./while_read.sh

# 观察反模式问题
./bad/for_ls.sh

# 学习正确做法
./good/for_glob.sh
```

## 要点总结

1. **遍历文件**：使用 `for file in *.txt` 而不是 `for file in $(ls)`
2. **读取文件**：使用 `while IFS= read -r line` 保留原始内容
3. **子 shell 问题**：管道后面是子 shell，用进程替换 `< <()` 解决
4. **引用变量**：循环中始终引用文件名变量 `"$file"`
