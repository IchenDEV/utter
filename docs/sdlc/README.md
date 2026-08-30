# Utter — AI-Native SDLC

项目变更沿一条固定链路推进，**每个阶段必须显式获得批准后才能进入下一阶段**。本目录是唯一权威来源；`docs/superpowers/` 中的旧 spec/plan 属于历史档案，仅作参考，不再新增。

## 链路与 Gate

```text
Intent -> Spec -> Plan -> Build -> Verification -> Review/Release -> Merge
```

| 阶段 | Artifact | 批准者（Gate） | 批准后触发 |
|---|---|---|---|
| 意图 | `intent.md` | 用户/负责人 | 开始撰写 Spec |
| 规格 | `spec.md` | 用户/负责人 | 开始撰写 Plan |
| 计划 | `plan.md` | 用户/负责人 | 开始 Build |
| 构建 | 代码 + 测试 | — | 自检通过后提交 Verification |
| 验证 | `verification.md` | 用户/负责人（重大变更）或 CI 证据（低风险） | 申请 Review/Release |
| 发布 | `release.md` | 用户/负责人 | 允许合并 PR |

约束：

- **状态是硬性的。** 每个 Artifact 头部的 `Status` 只能是 `draft` / `pending approval` / `approved` / `rejected` / `blocked`。`approved` 必须同时写 `Approved-by` 和 `Approved-date`。
- **顺序不可跳过。** 后一阶段的 Artifact 不得先于前一阶段获得 approved（CI 强制）。
- **驳回与阻塞也是状态。** `rejected` / `blocked` 必须写明原因；问题解决后改回 `draft` 重新提交。
- **权限不随流程扩张。** Agent 只能在已批准的 Plan 范围内行动；创建 PR、合并、发布仍需用户已有授权。
- **一个事实一个来源。** 验收标准写在 Spec，其他位置引用链接。

## 目录结构

```text
docs/sdlc/
  README.md                      # 本文件：流程与规则
  templates/                     # 各阶段模板
  changes/<NNNN>-<slug>/         # 每个变更一个目录
    intent.md spec.md plan.md verification.md release.md
  incidents/                     # 事故记录，回链到新 Intent
```

进行中的变更列在其 `intent.md` 的 Status 上；目录即状态。

## 与现有机制的连接

- `swift build` / `swift test`：Verification 阶段的最低证据，命令与结果必须如实记录在 `verification.md`。
- `scripts/ci-basic-checks.sh` + `.github/workflows/pr.yml`：合并前的确定性检查；SDLC 状态检查由 `scripts/sdlc-checks.sh` 提供并已接入 PR workflow。
- `docs/superpowers/specs|plans`：2026-08 之前的历史文档，只读归档；新变更一律在 `docs/sdlc/changes/` 下。

## 事故与反馈

生产问题或用户反馈先在 `incidents/` 记录事实与影响，确认需要变更时开新的 change 目录，其 Intent 必须链接事故记录，并在 Verification 中补充对应回归用例（`swift test` 可复现/防回归）。
