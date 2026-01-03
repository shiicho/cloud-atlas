# {Solution Name} — {One-line Description}

<!--
TEMPLATE INSTRUCTIONS (delete this block when using):
1. Replace all {placeholders} with actual content
2. Keep the section structure - it's designed for consistency
3. ASCII diagrams should use box-drawing characters (─│┌┐└┘├┤┬┴┼)
4. Japan IT context is REQUIRED - every recipe must map to a real ops scenario
5. Time estimate should be realistic for a first-time implementer
-->

> **要件 (Requirements):** {What problem does this solve? One sentence.}  
> **サービス (Services):** {Service1, Service2, Service3}  
> **难度:** {初级 | 中级 | 高级}  
> **所需时间:** {~30分钟 | ~1小时 | ~2小时}  
> **Japan IT 场景:** {運用自動化 | 障害対応 | 監査対応 | コスト管理 | etc.}

## 背景与动机 (Why This Matters)

{2-3 paragraphs explaining:}
- What real-world problem this solves
- Why the manual approach is painful
- Japan IT context (if applicable)

**适用场景:**
- {Scenario 1}
- {Scenario 2}
- {Scenario 3}

## 架构设计 (Architecture)

{Architecture diagram showing how services connect}

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│  Service A  │────▶│  Service B  │────▶│  Service C  │
└─────────────┘     └─────────────┘     └─────────────┘
```

### 设计决策 (Design Decisions)

| Decision | Choice | Rationale |
|----------|--------|-----------|
| {Decision 1} | {Choice} | {Why this choice?} |
| {Decision 2} | {Choice} | {Why this choice?} |

### 成本估算 (Cost Estimate)

| Service | Estimated Monthly Cost | Notes |
|---------|----------------------|-------|
| {Service 1} | ${X} | {Usage assumptions} |
| {Service 2} | ${X} | {Usage assumptions} |
| **Total** | **${X}** | |

## 前提条件 (Prerequisites)

- [ ] AWS Account with appropriate permissions
- [ ] AWS CLI configured (`aws configure`)
- [ ] {Optional: Relevant course completed, e.g., "CloudFormation basics"}
- [ ] {Any specific tools needed}

## 实现步骤 (Implementation)

### Step 1 — {First Action}

{Clear instructions with code blocks and screenshots where helpful}

```bash
# Example command
aws cloudformation create-stack --stack-name example ...
```

**验证:** {How to verify this step succeeded}

### Step 2 — {Second Action}

{Instructions}

```yaml
# Example configuration
Key: Value
```

### Step 3 — {Third Action}

{Instructions}

<!-- Add more steps as needed -->

## 验证 (Verification)

{How to test that the complete solution works}

### Test Scenario 1: {Happy Path}

1. {Trigger condition}
2. {Expected behavior}
3. {How to verify}

```bash
# Verification command
aws logs tail /aws/lambda/your-function --follow
```

### Test Scenario 2: {Edge Case}

1. {Trigger condition}
2. {Expected behavior}

## 清理 (Cleanup)

> **Warning:** This will permanently delete all resources created by this recipe.

```bash
# Delete the main stack
aws cloudformation delete-stack --stack-name {stack-name}

# Verify deletion
aws cloudformation wait stack-delete-complete --stack-name {stack-name}
```

**手动清理 (if needed):**
- {Resource 1}: {How to manually delete}
- {Resource 2}: {How to manually delete}

## 扩展思考 (Extensions)

{Ideas for adapting or extending this solution}

- **Alternative A:** {Description}
- **Alternative B:** {Description}
- **Production hardening:** {Tips for production use}

## トラブルシューティング (Troubleshooting)

| Symptom | Cause | Solution |
|---------|-------|----------|
| {Error message} | {Root cause} | {How to fix} |
| {Behavior} | {Root cause} | {How to fix} |

## 相关内容 (Related)

- **Course:** [{Related Course Name}](../../{path}/)
- **Solution:** [{Related Recipe}](../{recipe}/)
- **Glossary:** [{Term}](../../glossary/{term}/)

---

*Part of [cloud-atlas Solutions Gallery](../README.md)*
