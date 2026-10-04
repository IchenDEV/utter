# Verification: 语音输入可靠性

**Status:** draft
**Approved-by:** —
**Approved-date:** —
**Upstream:** [plan.md](plan.md)

M1–M8 的实现已接入生产插件图。真实模型质量、本机操作和独立审阅尚未完成，
本文件不作为全部 F1–F11 验收通过的结论。

## 工程检查

| 检查 | 结果与边界 |
| --- | --- |
| Linux Swift 6.2 全套 | 633 tests，0 failures；HUD 中英恢复按钮与无正文性能事件契约通过 |
| Python 评测、资源和模块脚本 | 27 tests，0 failures；缺样本、部分 manifest、未审阅事实、遗漏宣传片用例、对象错配和错误终点不能记为通过 |
| SDLC、模块边界与 diff | `sdlc-checks.sh`、模块/资源检查和 `git diff --check` 通过 |
| `ci-basic-checks.sh` | Linux 运行至 macOS `PlistBuddy` 检查停止；完整结果以 macOS CI 为准 |
| 已通过的原生检查 | [`18a2690` macOS CI](https://github.com/IchenDEV/utter/actions/runs/37229249610)：1117 tests，18 skips，0 failures；release-style app 与 SDLC Gate 通过 |
| 桌面迁移 SDK 构建 | [`e680783` CI](https://github.com/IchenDEV/utter/actions/runs/37232679151)：app 通过，测试因引用已删除的预加载策略而未编译；已迁为模型模块的实际契约 |
| 新入口和窗口渲染 | [`1607b69` CI](https://github.com/IchenDEV/utter/actions/runs/37233704976)：app 和基础检查通过；合成窗口完成渲染，测试随后停在遥控入口用例，已取消 |
| 遥控测试修正 | `23ab9bb` 改为等待正常松键的 `finish` 信号，增加有界等待；原无限等待来自测试错误，无生产采集逻辑改动 |
| HUD 原生审查修正 | `63396d9` 补中英恢复按钮、统一面板按钮配色、长错误换行和等待稳定布局；合成窗口图像从 CI 日志取回，重验待下表最终 CI |
| 最终代码检查点 | [`1165d97` macOS CI](https://github.com/IchenDEV/utter/actions/runs/37235260722)：新词库测试漏传停止时间参数，阻断编译；已补 `at: nil`，下一检查点复验 |
| 与 main 合并 | 已同步 `06a9502`，解决 README 冲突；未创建或合并 PR |

## 用例与自动化证据

路径相对于仓库根目录；同组的硬件和模型部分仍按下一节单独验收。

| 用例 | 主要工程证据 |
| --- | --- |
| F1、F8.1–F8.3 | `Tests/UtterMacServicesTests/HotkeyGestureControllerTests.swift`、`HotkeyActivationControllerTests.swift`、`Tests/UtterIngressTests/HotkeySessionBindingTests.swift`、`Tests/OpenTypeTests/VoiceWorkflowTests.swift`、`RemoteSessionIngressTests.swift`；1000ms、晚切换、先松 Shift、稳定 ID、冷准备中的首段采集及取消 drain |
| F2 | `Tests/UtterContractsTests/SessionPresentationTests.swift`、`HUDRecoveryLocalizationTests.swift`、`Tests/OpenTypeTests/PresentationProjectionTests.swift`、`PresentationRenderingTests.swift`；按 receipt 投影复制、插入、不确定、错误及恢复入口 |
| F3.1–F3.5、F4 | `Tests/UtterProcessingTests/SpokenQuantityFidelityTests.swift`、`TranscriptFidelityGuardTests.swift`、`TranscriptFidelityEdgeCaseTests.swift`、`Tests/OpenTypeTests/TextProcessingProviderTests.swift`；合法数字规范化、改值/单位/对象错配拒绝、清单与叙事边界 |
| F5 | `Tests/OpenTypeTests/VocabularyReplacementEngineTests.swift`、`QwenRecognitionContextTests.swift`、`QwenNativeASREngineTests.swift`、`VoiceWorkflowTests.swift`；术语、明确音译、个人优先、有限上下文、回声重试与共享会话传递 |
| F6 | `Tests/UtterProcessingTests/CustomFactSupportTests.swift`、`Tests/UtterContractsTests/OperationDeadlineTests.swift`、`Tests/OpenTypeTests/PromptAndProcessingTests.swift`；合法删减/重排、严格事实结果、失败/超时回退及取消 |
| F7 | `Tests/OpenTypeTests/VoiceEditingTests.swift`、`VoiceScreenFailureTests.swift`、`ScreenReliabilityTests.swift`、`Tests/UtterContractsTests/SpokenEditEvidenceTests.swift`、`Tests/UtterProcessingTests/CommandOutputCleanerTests.swift`；回复不覆盖、明确编辑对象、中文 OCR、HUD 身份排除和读屏失败拒绝写入 |
| F8.4 | `Tests/UtterContractsTests/TranslationAssessmentTests.swift`、`Tests/OpenTypeTests/TranslationLanguageRecognitionTests.swift`、`VoiceTranslationDeliveryTests.swift`；0.7/0.2 门槛、错误/无法确认语言不交付 |
| F9 | `Tests/UtterMacServicesTests/ClipboardPasteTransactionTests.swift`、`TextDeliveryTransactionTests.swift`、`DeliveryReceiptTests.swift`；慢读取、超时、第三方 changeCount、UTF-16 范围、取消清理和不自动重试 |
| F10 | `Tests/UtterContractsTests/WhisperTokenizerAssetsTests.swift`、`LocalModelReliabilityTests.swift`、`Tests/OpenTypeTests/WhisperOfflineLoadingTests.swift`、`LocalGenerationLoadingTests.swift`；本地 tokenizer、拒绝下载、实际加载配置中的 Gemma EOS 和内存建议 |
| F11 | `Tests/UtterSessionTests/SessionTimingTests.swift`、`SessionMetricsTests.swift`、`Tests/UtterContractsTests/ModelBenchmarkSuiteTests.swift`、`scripts/tests/test_session_performance.py`；默认无正文、真实终点、确认插入分布、冷/热与长度分组 |
| 所有生产入口 | `Tests/UtterSessionTests/SessionDriverTests.swift`、`SessionAPIExecutionTests.swift`、`Tests/UtterIngressTests/IntegrationHTTPTests.swift`、`Tests/OpenTypeTests/IntegrationXPCProtocolTests.swift`、`VoiceWorkflowTests.swift`、`RemoteSessionIngressTests.swift`；共享租约、冻结配置、撤权、旧连接清理和可替换提供者 |
| 批量评测 | `Tests/UtterEvaluationTests/VoiceEvaluationTests.swift`、`scripts/tests/test_voice_quality_acceptance.py`；显式安装资产、预算、完成数和单独事实复核；原生评测 executable 在 `swift test` 编译，真实推理未运行 |

旧 `VoicePipeline`、`InputSessionCoordinator`、`TextInserter` 和生产预热 helper
已移除。App 入口仅启动/停止 `BuiltinApplication`；会话、交付和呈现分别由
唯一契约提供者拥有。OpenType 包名、兼容标识和外部协议保留。

## 未运行的验收

- 真实模型：宣传片示例各 5 次、至少 95% 合法删减、20 条危险候选、逐条事实
  与对象复核；Qwen 的真实上下文收益；Whisper 冷缓存断网；Gemma 4 真实 EOS。
- 本机操作：真实 Fn 系统冲突、多屏 HUD 排除、TCC 拒绝/重新授权、麦克风首尾、
  设备退出、安全输入、目标应用确认、慢粘贴与剪贴板管理器可见性。
- 独立审阅：按 [review-policy.md](../../review-policy.md) 由非实现者核对屏幕
  远端边界、剪贴板残留、取消后的副作用和事实检查。作者测试与 CI 不替代该结论。

已提供[本地评测入口](../../../voice-evaluation.md)、
[Mac 验收表](../../../mac-voice-validation.md)和[插件组合说明](../../../plugin-composition.md)。
无预装模型的 CI、合成窗口及 OCR 图像不能作为上述实际行为通过的证据。

## 回滚

遵循已批准 plan 的回滚契约：停用并 drain 当前会话、模型借用及交付观察，
备份配置和用户数据，恢复上一已验证签名应用/提交。插件组合可从 `plugins.json`
同目录备份恢复。模型补齐为增量，不删除权重、历史或词典；旧数据继续可读。
回滚不能撤销已经写入目标或被第三方剪贴板管理器记录的文本。
