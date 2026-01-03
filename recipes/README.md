# Solutions Gallery | 解决方案集

> **生产级多服务集成方案** — 每个 recipe 独立可用，解决真实运维需求。

## What is This?

Unlike sequential courses that teach concepts step-by-step, **Solutions** are standalone, production-ready implementations that combine 2-4 services to solve real operational requirements.

| Courses | Solutions |
|---------|-----------|
| Sequential (01→02→03) | Standalone (any order) |
| Teach concepts | Solve problems |
| Single service focus | Multi-service integration |
| Learning-oriented | Production-oriented |

## Recipe Index

### AWS Solutions

| Recipe | Difficulty | Time | Japan Scenario |
|--------|------------|------|----------------|
| [Drift Auto-Remediation](./aws/drift-remediation/) | Intermediate | ~1h | 運用自動化 / 構成管理 |
| [Cost Anomaly Alert](./aws/cost-anomaly-alert/) | Beginner | ~30min | コスト管理 / FinOps |

### Cross-Platform Solutions

| Recipe | Difficulty | Time | Japan Scenario |
|--------|------------|------|----------------|
| [Log Archive + Search](./cross-platform/log-archive-search/) | Intermediate | ~1.5h | 監査対応 / ログ保管義務 |

## Recipe Workflow

Every recipe follows the same structure:

```
要件定義 (Requirements)  → What problem? Why does it matter?
      ↓
設計 (Design)           → Architecture diagram, service selection
      ↓
実装 (Implementation)   → Step-by-step with IaC/scripts
      ↓
検証 (Verification)     → Test the solution works
      ↓
清理 (Cleanup)          → Remove all created resources
```

## How to Use

1. **Pick a recipe** that matches your operational need
2. **Check prerequisites** (soft recommendations, not hard requirements)
3. **Follow the steps** — each recipe is self-contained
4. **Adapt as needed** — these are starting points, not rigid templates

## Japan IT Context

Each recipe includes a Japan IT scenario mapping:

- **運用自動化** (Ops Automation) — Reducing manual toil
- **障害対応** (Incident Response) — Faster recovery
- **監査対応** (Audit Compliance) — Meeting regulatory requirements
- **コスト管理** (Cost Management) — FinOps practices
- **構成管理** (Configuration Management) — Preventing drift

## Contributing Ideas

Have a recipe idea? Add it to the backlog in `context/solutions.yaml`:

```yaml
backlog:
  - id: your-idea
    title: "Your Solution Name"
    services: [Service1, Service2]
    japan_scenario: "運用シナリオ"
```

---

*Part of [cloud-atlas](https://github.com/shiicho/cloud-atlas) — Bilingual cloud tutorials for Chinese engineers in Japan IT.*
