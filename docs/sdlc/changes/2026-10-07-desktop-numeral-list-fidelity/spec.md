# Spec: 桌面端智能整理的数字规则与口述列表

**Status:** approved
**Approved-by:** 用户（本对话：“批准并执行”，针对排查报告的方案与取舍）
**Approved-date:** 2026-10-07
**Upstream:** [intent.md](intent.md)（已批准）
**说明：** 设计取自 2026-10-07 排查报告，经用户批准后实现。

## Context

`TextProcessor.process` 对 LLM 输出调用 `TranscriptFidelityGuard.violation`；任何违规都使整段回退原文。守卫比较原文与候选的“受保护语义序列”，数字证据要求量词或“第/到/周”等上下文。

## Design

1. **单字数字证据**（`TranscriptNumberEvidence.swift`）：单个中文数字紧跟 ASCII 字母/数字（可隔一个空格）时算数字证据；紧接“下/直/起/些/切/样/般/定/旦/共/边/面/同/致/律/方/旁”时不算。
2. **列表标记剥离**（新增 `TranscriptListMarkers.swift`）：候选里行首 `1. `/`1、`/`1)` 形成从 1 开始连续递增、至少 2 项时，两边对称比较——候选剥离行首序号，原文剥离口述序号线索（`第N(个|条|点|项|件|步)`、`一、`、`问题一`、`一是`、`其一`），再走原有序列比较。先走原路径，失败才走剥离路径，所以现有通过项不受影响。
3. **自我纠正数字**：`removingCorrectedNumberEvidence` 与 `removingSelfCorrectionContent` 允许数字后带“点/号/天/个”。
4. **分类器**：序号排除表去掉“个/件/条/项”，保留“次/天/年/月/周/名/人”；新增 `问题一/二`、`一、二、`、`其一/其二`；仍要求第一与第二配对出现。
5. **提示词**：
   - 编辑规则段前加“必须逐条遵守，优先于风格默认写法”（四种语言）；段落与围栏不变，规则仍在 user turn，稳定前缀缓存不受影响。这是对报告“移入 system”方案的取舍：取遵从度的小幅损失换缓存稳定。
   - 中文基础提示词：声明编辑规则必须遵守；数字规则覆盖单字数字；列出序号线索；补充 4 个示例（序号列表、单字数字、口头禅/重复）。
   - 专业风格（auto/中文/粤语）：保持用户用词，序号线索触发编号。
   - 邮件契约加“正式、礼貌”，聊天契约加“随意”（中英）。
6. **评测**：`VoiceEvaluationCase.edit_rules: [String]?`，`EvaluationRequest` 转为 `EditRule`；语料新增 5 例。

## Safety and failure modes

- 守卫放宽只在两个窄场景生效（ASCII 前缀的单字数字；严格递增的行首序号）。丢导语、改数字、乱序、未从 1 开始仍违规；`统一`、`一点意见` 等不变。
- 分类器放开“第一个”会增加把叙述误判为列表的风险，由“第一与第二配对”约束，且列表仍需模型输出并过守卫。
- 语气规则是新增行为，仅影响邮件/聊天判定的输出，不涉及数据与权限。
- 日语、韩语提示词未新增示例（本次问题为中文）。

## Test strategy

`Tests/UtterProcessingTests/ListMarkerFidelityTests.swift` 覆盖验收 1–5；既有 `SpokenQuantityFidelityTests`、`TranscriptFidelity*Tests`、`TextFormatKindTests`、提示词测试保持通过；全量 `swift test`。真实模型遵从率通过评测语料人工运行，不进 CI。

## Rollout and rollback

随常规发布；回滚为还原本变更提交。无数据迁移。
