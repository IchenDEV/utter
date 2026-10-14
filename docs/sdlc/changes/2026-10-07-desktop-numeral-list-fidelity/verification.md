# Verification: 桌面端智能整理的数字规则与口述列表

**Status:** pending approval
**Approved-by:** —
**Approved-date:** —
**Upstream:** [plan.md](plan.md)（已批准）

**结论先说：守卫、分类器、提示词措辞和评测字段有自动化证据；真实模型（0.8B/2B）下规则遵从率和列表质量没有跑过。** 提示词改动只能证明“内容进了提示词”，不能证明模型照做。

## Evidence

| Check | Result | Evidence |
|---|---|---|
| `swift test`（`DEVELOPER_DIR` 指向 Xcode） | Pass | 472 个测试，17 个跳过，0 失败 |
| `ListMarkerFidelityTests`（新增 7 项） | Pass | 单字数字、非数字词仍拒绝、5 种序号说法、丢导语/改事实/编号不从 1 开始仍拒绝、自我纠正时间、分类器、编辑规则措辞 |
| 既有 `SpokenQuantityFidelityTests`、`TranscriptFidelity*Tests`、`TextFormatKindTests` | Pass | 含 `testListFormattingPreservesIntroAndExistingFacts`、`testNarrativeOrdinalsAreNotListEvidence` |
| `PromptBuilderTests` | Pass | 风格句断言随新措辞更新 |
| `xcodebuild -scheme UtterVoiceEval build` | Pass | `BUILD SUCCEEDED`（评测宿主含 `edit_rules` 改动） |
| `bash scripts/sdlc-checks.sh` | Pass | `SDLC checks passed.` |
| `bash scripts/ci-basic-checks.sh` | Pass | `Basic CI checks passed.` |

## Acceptance criteria

1. 单字数字 — 通过：`Windows 七`、`cloud 五系列`、`gpt 六系列`、`d 叉十二` 放行；`统一处理`、`一点意见`、`iPhone 一下子`、`Windows 七 → Windows 8` 拒绝。
2. 序号列表 — 通过：5 种口述序号都放行；丢“三件事”导语、列表里改成 5 点、编号从 2 开始被拒绝。
3. 分类器 — 通过：`第一个…第二个`、`问题一/二`、`一、二、三、` 为 `orderedSteps`；叙事用法仍为 `plainParagraph`。
4. 自我纠正时间 — 通过（`4 点开会` 放行，`5 点开会` 拒绝）。该用例同时需要同步放宽 `removingSelfCorrectionContent`，否则触发 `excessive_deletion`。
5. 编辑规则与评测 — 通过：规则段含“必须逐条遵守”；`edit_rules` 字段与 5 个新语料（共 61 例、93 次运行，在默认 100 次预算内）；语料加载测试通过。
6. 检查脚本 — 通过（见上表）。

## Residual risk

- **未在真实模型上验证。** 守卫不再退回之后，2B/0.8B 是否按编辑规则改数字、是否按序号排列表仍取决于模型。请用 `docs/voice-evaluation.md` 的命令加新语料在本机跑 2B 与 0.8B 对比。
- 守卫放宽使“ASCII 名称后的单字中文数字”可被模型改写，换取规则生效；这是用户批准的取舍。
- 分类器放开“第一个”可能把少数叙述判成列表，靠“第一/第二配对”约束。
- 邮件/聊天语气规则是新行为，未做 A/B。
- 日语、韩语提示词未新增示例。
- 用户截图的实际模型和日志（`rejected formatting output: protected_token_change`）未取得，根因 A/D 仍是“与离线复现高度吻合”而非日志实锤。

## Decision

等待人工审批 verification 阶段。
