# SSM 会话为什么不自动显示 MOTD？（以及可选解决方案）

[MOTD（Message of the Day）](../linux/motd.md)，登录后显示的「登录横幅」。

本页解释：

① 为什么用 Session Manager 登录 EC2 时看不到 MOTD；

② 想要显示的话，有哪些做法（待补充）。

## TL;DR

SSM 默认启动的是 交互式、非登录 的 sh，且 不走 PAM。

因此 不会读取 /etc/profile / /etc/profile.d/*.sh，也不会触发常见的 pam_motd 打印。

所以我们在 [04 · Parameter Store（创建/读取/在脚本中使用）](../../cloud/aws-ssm/04-parameter-store/) 已经存在的 /etc/motd.d/10-cloud-atlas 不会自动被打印。

你仍可手动查看或切到登录 bash 来看到 MOTD；也可以配置 SSM shell profile 让每次会话自动显示。

## 现象复现（你很可能看到过）
```bash
echo "shell:$0 flags:$-"
# 输出常见为：shell:sh  flags:himBHs  （说明是交互式 sh，但不是登录壳）

getent passwd ssm-user
# ssm-user ... /bin/bash  （默认登录壳是 bash，但 SSM 仍以 sh 启动）

bash -l
# 这时会自动打印 MOTD（/etc/motd 与 /etc/motd.d/*）
```

## 为什么？

非登录 shell 不会读取 /etc/profile 与 /etc/profile.d/*.sh。

SSM 会话也不经过 PAM，因此不会有 pam_motd 的自动打印。

当你手动执行 bash -l（登录风格）或 cat /etc/motd.d/… 时，才会看到 MOTD 内容。

## 怎么做？

*待补充：配置 SSM shell profile 自动显示 MOTD 的方法。*