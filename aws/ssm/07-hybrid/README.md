# 07 · Hybrid 托管 On-Prem / Docker 主机

> **目标**：把自管主机（on-prem 或 Docker 容器）注册为托管节点，纳入 SSM 统一管理。  
> **前置**：已完成 [01 · CloudFormation 部署](../01-cfn-deploy/)。  
> **状态**：*Placeholder - 内容待补充*

## 你将完成

- 创建 Hybrid Activation（混合激活）
- 在 on-prem 主机或 Docker 容器中安装 SSM Agent
- 使用激活码注册到 SSM
- 验证托管节点出现在 Fleet Manager

## 为什么需要 Hybrid 托管？

* **统一管理**：无论 EC2、本地服务器、还是其他云的 VM，都可以用同一套 SSM 工具管理
* **无需 VPN**：SSM Agent 主动出站连接，无需开放入站端口
* **合规审计**：所有操作通过 SSM 记录，便于审计

---

*内容开发中...*

## 系列导航 / Series Nav

* 返回：[SSM 系列首页](../)
* 上一课：[06 · State Manager](../06-state-manager/)
