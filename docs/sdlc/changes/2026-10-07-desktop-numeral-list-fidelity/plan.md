# Plan: 桌面端智能整理的数字规则与口述列表

**Status:** approved
**Approved-by:** 用户（本对话：“批准并执行”）
**Approved-date:** 2026-10-07
**Upstream:** [spec.md](spec.md)（已批准）

| # | 内容 | 检查 |
| --- | --- | --- |
| 1 | 单字数字证据、列表标记剥离、自我纠正数字 | `ListMarkerFidelityTests`、既有保真测试 |
| 2 | 分类器放开“第一个”并新增序号说法 | `ListMarkerFidelityTests`、`TextFormatKindTests` |
| 3 | 提示词：编辑规则措辞、示例、风格、邮件/聊天语气 | 提示词相关测试 |
| 4 | 评测语料 `edit_rules` 与 5 个新用例，更新文档 | `VoiceEvaluationTests`、sdlc/ci-basic 检查 |

## Verification plan

- [ ] `bash scripts/sdlc-checks.sh`
- [ ] `bash scripts/ci-basic-checks.sh`
- [ ] `swift test`
- [ ] 评测语料加载通过（`VoiceEvaluationTests`）

## Human gates

PR 审批；真实模型评测（2B/0.8B）结果由用户在本机运行后判断是否合入发布。
