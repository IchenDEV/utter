# Intent: 支持 Audio8-ASR-0.1B 本地语音识别模型

**Status:** approved
**Approved-by:** 用户（本会话明确回复“批准”）
**Approved-date:** 2026-11-25
**Upstream:** 用户请求：<https://huggingface.co/Edge0/Audio8-ASR-0.1B>「支持一下这个模型」
**Risk:** medium。该变更影响用户可见的模型/runtime 行为，并可能引入新的推理依赖或模型资产格式；不改变麦克风、隐私或发布签名边界。

## Problem

Utter 当前的本地 ASR 模型目录不包含 `Edge0/Audio8-ASR-0.1B`。用户无法下载、选择或用它完成本地语音输入。

2026-11-25 查阅模型卡得到的事实：

- 该模型是多语种 ASR 模型，覆盖中文、英语、法语、德语、日语、韩语和粤语。
- 链接仓库是 Hugging Face Transformers checkpoint，架构为自定义 `arkasr`，需要 `trust_remote_code=True`；它不是 Utter 现有 MLX ASR 模型目录中的现成 MLX 模型。
- 同一模型卡提供部署包：`Audio8-ASR-0.1B-onnx-runtime` 和 `Audio8-ASR-0.1B-iOS-ANE`。
- `Audio8-ASR-0.1B-iOS-ANE` 声称其 Swift package 支持 iOS 18+ / macOS 15+，并可在 macOS 上用文件转写做端到端验证。
- 模型及部署包的许可证是 CC BY-NC 4.0，含非商业限制。

## Outcome

用户能在 Utter 的模型管理中发现、下载并选择 Audio8-ASR-0.1B；选择后，本地录音可通过该模型完成识别。用户能在下载前看到该模型的非商业许可证限制，并能删除已下载资产。

## Scope

In scope:

- 一种可在 macOS Apple Silicon 上运行的 Audio8 本地推理路径。
- 模型目录、下载、完整性识别、选择、删除和错误展示。
- 与现有语音识别会话、取消、热词/上下文传递方式的集成；能实现到什么程度由 spec 依据上游能力决定。
- 中文和英文用户文案，包括许可证/非商业限制提示。
- 单元测试和至少一次真实音频文件的端到端转写验证。

Non-goals:

- 不承诺支持 Hugging Face 的 `trust_remote_code` Python 运行时。
- 不实现流式识别或 VAD；上游 ANE 包明确不包含这些能力。
- 不改变现有 Qwen3、FireRed、Mega、Whisper、Apple 或 Volc 引擎的默认选择。
- 不绕过 CC BY-NC 4.0 的非商业限制，不把该模型设为默认模型。
- 本次不处理其他新 ASR 模型。

## Constraints

- 保持音频处理本地完成；新增依赖不得把录音发送到网络服务。
- 模型资产必须可离线复用，缺失或损坏时给出明确错误，不得静默回退到另一个 ASR 引擎。
- 若引入第三方推理依赖，必须固定版本，并通过现有 release-style build 验证。
- 模型下载必须复用现有下载源、进度、取消、恢复和磁盘缓存语义；如上游资产格式不适配，spec 必须说明原因和替代方案。
- 许可证文案必须在用户下载前可见，并链接上游许可证。
- 任何复制或改写的上游代码都必须保留适用的许可证和署名；若许可证不允许所需用法，则不能复制。
- 标准检查：`bash scripts/sdlc-checks.sh`、`bash scripts/ci-basic-checks.sh`、`swift test`；因属于 runtime/dependency 变更，还需要 release-style app build。
- 仅完成 intent 阶段。spec、plan、实现和验证分别等待明确批准。

## Acceptance criteria

1. 模型管理中可见 Audio8-ASR-0.1B，标注本地下载体积/需求和非商业许可证限制；未下载时状态准确。
2. 用户能下载该模型，下载完成后重启应用仍可离线识别；用户能删除它，删除后状态回到未下载。
3. 用户选择该模型后，一段不超过 30 秒的 16 kHz 中文或英文测试音频能完成本地转写，结果非空，日志或诊断能证明使用了 Audio8 路径。
4. 超过上游支持时长、资产缺失/损坏、用户取消这三类失败路径都有明确、可理解的错误或取消状态；不会静默改用其他引擎。
5. 若上游能力支持，识别上下文/热词会传入 Audio8；若不支持，spec 明确记录限制，UI 不暗示该能力存在。
6. 上述标准检查、release-style build 和真实音频端到端证据记录在 `verification.md`。

## Open questions

1. 集成路径：使用上游 Swift/Core ML/ONNX 部署包、直接接入 ONNX Runtime 资产，还是转换/适配到现有 MLX ASR 路径。由 spec 比较许可证、维护成本、体积、性能和可验证性后决定。
2. 资产来源：使用 `Audio8-ASR-0.1B-iOS-ANE`、`Audio8-ASR-0.1B-onnx-runtime`，还是从 base checkpoint 转换。由 spec 决定。
3. 该模型以新的 ASR engine/provider 呈现，还是作为现有本地 ASR 目录中的一个模型条目。由 spec 依据架构边界决定。
