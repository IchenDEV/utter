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
| Linux Swift 6.2 全套 | 635 tests，0 failures；包含关闭剪贴板、失效延后替换、HUD 中英恢复按钮与无正文性能事件契约 |
| Python 评测、资源和模块脚本 | 27 tests，0 failures；缺样本、部分 manifest、未审阅事实、遗漏宣传片用例、对象错配和错误终点不能记为通过 |
| SDLC、模块边界与 diff | `sdlc-checks.sh`、模块/资源检查和 `git diff --check` 通过 |
| `ci-basic-checks.sh` | Linux 运行至 macOS `PlistBuddy` 检查停止；完整结果以 macOS CI 为准 |
| 原生测试与应用构建 | [`e3871cf` macOS CI](https://github.com/IchenDEV/utter/actions/runs/37237728434)：1109 tests，18 skips，0 failures；基础检查、release-style app 与 SDLC Gate 全部通过。跳过项与真实模型、设备验收分别保留 |
| 剪贴板关闭策略 | 新回归在修复前产生 10 项断言失败；修复后 10 项受影响测试全部通过。直接写入保留，普通/快速输出由后端执行冻结策略，失效延后替换保留候选，显式复制单独授权 |
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
| F9 | `Tests/UtterMacServicesTests/ClipboardPasteTransactionTests.swift`、`TextDeliveryTransactionTests.swift`、`NativeOutputBackendClipboardTests.swift`、`DeliveryReceiptTests.swift`、`Tests/UtterSessionTests/DeferredReplacementExecutionTests.swift`、`Tests/OpenTypeTests/VoiceTextInputTests.swift`；慢读取、超时、第三方 changeCount、UTF-16 范围、取消清理、不自动重试及关闭自动剪贴板策略 |
| F10 | `Tests/UtterContractsTests/WhisperTokenizerAssetsTests.swift`、`LocalModelReliabilityTests.swift`、`Tests/OpenTypeTests/WhisperOfflineLoadingTests.swift`、`LocalGenerationLoadingTests.swift`；本地 tokenizer、拒绝下载、实际加载配置中的 Gemma EOS 和内存建议 |
| F11 | `Tests/UtterSessionTests/SessionTimingTests.swift`、`SessionMetricsTests.swift`、`Tests/UtterContractsTests/ModelBenchmarkSuiteTests.swift`、`scripts/tests/test_session_performance.py`；默认无正文、真实终点、确认插入分布、冷/热与长度分组 |
| 所有生产入口 | `Tests/UtterSessionTests/SessionDriverTests.swift`、`SessionAPIExecutionTests.swift`、`Tests/UtterIngressTests/IntegrationHTTPTests.swift`、`Tests/OpenTypeTests/IntegrationXPCProtocolTests.swift`、`VoiceWorkflowTests.swift`、`RemoteSessionIngressTests.swift`；共享租约、冻结配置、撤权、旧连接清理和可替换提供者 |
| 批量评测 | `Tests/UtterEvaluationTests/VoiceEvaluationTests.swift`、`scripts/tests/test_voice_quality_acceptance.py`；显式安装资产、预算、完成数和单独事实复核；原生评测 executable 在 `swift test` 编译，真实推理未运行 |

旧 `VoicePipeline`、`InputSessionCoordinator`、`TextInserter` 和生产预热 helper
已移除。App 入口仅启动/停止 `BuiltinApplication`；会话、交付和呈现分别由
唯一契约提供者拥有。OpenType 包名、兼容标识和外部协议保留。

## 原生窗口证据

以下 PNG 来自 `e3871cf5a062a1eb006114b6ffb2248983b640c2` 的上述 CI，
由 `PresentationRenderingTests` 在实际 `NSWindow` 中渲染并从日志取回。
作者检查了浅/深色设置页、中英文恢复按钮、长错误换行、复制及不确定状态。
HUD 使用统一深色面板，在两种系统外观下的内容相同。

| 范围 | 图像 |
| --- | --- |
| 通用设置 760×680 | [浅色](evidence/settings-light.png)、[深色](evidence/settings-dark.png) |
| 录音预览 304×80 | [浅色](evidence/hud-recording-light.png)、[深色](evidence/hud-recording-dark.png) |
| 已复制 192×40 | [浅色](evidence/hud-copied-light.png)、[深色](evidence/hud-copied-dark.png) |
| 写入不确定 360×96 | [浅色](evidence/hud-uncertain-light.png)、[深色](evidence/hud-uncertain-dark.png) |
| 模型恢复 360×96 | [中文浅色](evidence/hud-models-light.png)、[中文深色](evidence/hud-models-dark.png)、[英文](evidence/hud-models-english.png) |

渲染测试还包含 148px 紧凑录音、屏幕权限恢复和关闭剪贴板的候选复制状态。
图像使用合成状态，不代表完整设置窗口、TCC 提示、真实麦克风或多屏采集验收。
可在 Mac 用以下命令生成全部状态图像：

```bash
UTTER_UI_SNAPSHOTS=/tmp/utter-ui swift test --filter PresentationRenderingTests
```

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
