# OpenType 语音识别与文本纠错质量调研

> 日期：2026-07-30
> 状态：研究结论 + 第一轮低风险改造，后续仍须用真实语料验收
> 范围：macOS 26+、Apple Silicon、本地优先，兼顾 Apple Speech、WhisperKit、Qwen3-ASR MLX、火山 ASR 和远程 LLM
> 方法：先审计当前实现，再查阅上游源码、官方文档和论文。第三方 benchmark 仅作为候选筛选依据，不把上游自报成绩当成 OpenType 实测结论。
>
> “当前实现”指本轮并行改造开始前的代码基线；本轮已经落地的变化应以最终 diff 和测试结果为准。

## 1. 结论先行

OpenType 和成熟付费听写软件的差距，不是单靠“换一个更大的 ASR 模型”就能消除。改造前基线最明显的损失来自整条链路：

1. 录音只有音量诊断，没有真正的端点检测、语音段切分、前后缓冲、削波/SNR 质量信号。
2. WhisperKit 丢弃了时间戳和置信度，只保留最终字符串；流式预览依赖 15 秒滑窗和文本启发式拼接。
3. 个人词典、屏幕词和最近上下文只主要提供给后处理 LLM，没有充分送入 ASR 解码器；这会直接损失人名、产品名和专业词。
4. Apple Speech 只用了最基础的 `.transcription` 预设，未获取候选、置信度、时间范围和渐进式结果。
5. Qwen3-ASR MLX 固定在 `0.1.1`，运行器只传音频和语言；较新的上下文/热词与重复抑制能力尚未利用。
6. 后处理提示词同时承担“忠实纠错”和“较强润色”，且没有结构化编辑证据、实体/数字保护和自动回退。结果可能更顺，但也更容易改错原意。
7. 没有可重复的音频基准集和 CER/WER、专名召回、数字保真、静音幻觉、延迟等门禁，无法知道某次优化究竟是整体提升还是只改善了个别样例。

最值得优先做的是：**先保留识别证据，再把上下文送到 ASR，随后改造端点/流式稳定器和证据约束的纠错器**。这些工作可以复用现有引擎，不需要先增加一个重量级依赖。

### 1.1 本轮已落地

这次没有把尚未跑过真实录音的变化写成“准确率已经提升”。已完成的是可由代码和自动测试验证的第一轮：

- 修复 Whisper `large-v3` 别名和过期完整 model ID 可能静默落到设备默认小模型的问题；最终离线解码临时恢复上游默认的 5 次温度 fallback，实时预览保持 1 次 fallback，并对长音频启用 WhisperKit VAD chunking。
- 从启用的个人词典生成限量、去重的识别上下文：Apple 的 Dictation fallback 走 `AnalysisContext.contextualStrings`，legacy 走 request `contextualStrings`，Whisper 走有 token 上限的 initial prompt。
- Apple macOS 26 路径继续优先使用新一代 `SpeechTranscriber(.transcription)`；locale 不支持或分析失败时以重新打开的音频文件回退 `DictationTranscriber`，并在回退路径接入词典、按 60 秒选择 short/long preset。legacy `SFSpeechRecognizer` 同样接入词典并强制 `requiresOnDeviceRecognition`；自动语言跟随当前系统 locale，粤语显式使用 `zh-HK`。
- Qwen 入参先用 `AVAudioConverter` 最高质量重采样为 16 kHz、单声道、Int16 WAV，避免第三方运行器中的线性插值；临时文件在成功和失败时都会清理。
- 个人词典改为最长优先、单次扫描、不级联；拉丁词使用词边界，避免把 `api` 错换进 `rapid`，同时保留中文子串匹配。
- 默认纠错提示改为“有原文、词典或上下文证据才改”，不再要求模型猜漏字或补完未说完的句子；纠错/格式化使用 temperature 0，并按输入长度动态扩大输出预算。
- 新增整段忠实度 guard：有序保护显式数字、单位、URL、邮箱、文件路径和引号，保护全部启用词典 canonical term，把否定绑定邻近词，并用短句高阈值、全长均匀采样、内容覆盖率和长度比拦截空输出、无关改写、异常扩写和大段删除。当前只对有确定解析证据的中英文口述数字、日期/范围和韩语序数放行 ITN；口述邮箱、URL、path 仍保持保守拒绝，等待结构化解析器。普通处理的 guard 失败回退本次预处理文本；已有 quick insert 的延迟替换则标记失败，不覆盖已插入文本。
- 同一请求冻结模型、语言、远程端点、自定义 prompt、个人词典和编辑规则；VLM fallback 与延迟纠错复用同一快照，multimodal 截图同时保留 OCR 文本供 VLM 失败后使用。远程兼容端若明确返回 token/context 上限错误，会缩小输出预算重试一次；`finish_reason=length` / `stop_reason=max_tokens` 一律视为失败，不接受截断正文。
- 无效本地 LLM 配置回退到既定 2B 默认模型，而不是列表首个 0.8B 小模型。
- 新增无第三方依赖的 `scripts/evaluate-voice-quality.py`，分别评测 raw ASR 和 processed text 的 CER/WER、术语、数字/URL/email/path 有序 exact 保真（同时惩罚新增、删除和交换）、静音幻觉和 p50/p95 延迟；schema 示例见 `voice-quality-corpus.example.jsonl`。

尚未完成、也不能靠单元测试替代的部分：真实用户录音 baseline、`TranscriptEvidence`、候选/置信度与时间戳、端点 pre/post-roll、LocalAgreement、低置信二次识别，以及由声学候选支持的实体校验、结构化 edits 和按句/segment 回退。本轮 guard 是确定性安全网，不等于已经理解整句语义。这些仍是下一轮决定能否接近付费软件体验的关键。

## 2. 改造前基线审计

| 链路 | 当前行为 | 主要缺口 | 质量影响 |
|---|---|---|---|
| 音频采集 | `AudioCaptureManager` 用 `AVAudioEngine` 录制，流式侧转 16 kHz mono；已有 RMS 诊断 | 无正式 VAD、端点、pre-roll/post-roll、削波率、噪声底、SNR；没有 raw/voice-processing A/B | 开头/结尾音素被切、长静音诱发幻觉、远场和回声恶化 |
| Whisper 模型 | 默认名为 `large-v3`，不支持时做模糊匹配 | 没有锁定具体质量模型构建；模型变化不可审计 | 同名映射或 catalog 变化后结果漂移 |
| Whisper 解码 | `temperatureFallbackCount: 1`、`withoutTimestamps: true`、固定中文 prompt“以下是普通话的句子。” | 上游默认 fallback 次数是 5；时间戳、词概率、segment logprob、no-speech 信号均被浪费；prompt 不含用户词汇 | 难词召回低、无法判定不确定片段、重复/幻觉只能事后猜 |
| Whisper 实时预览 | 0.7 秒调度、至少 1 秒才开始、反复识别最近 15 秒，再按字符串启发式合并 | 没有稳定/不稳定词边界、时间戳对齐和确认策略 | partial 抖动、丢词、重词、长听写接缝不稳 |
| Apple Speech | `SpeechTranscriber(..., preset: .transcription)`，最终只拼字符串 | 未用 AnalysisContext、alternatives、confidence、time range、progressive preset | 没有词典加权，也无法针对低置信片段复核 |
| Qwen3-ASR MLX | 固定 `qwen3-asr-mlx==0.1.1`；只传 `audio` 和 `language` | 未用新版 context/hotwords、重复惩罚、短音频重试 | 中文专名、代码混说和重复文本仍有可用优化空间 |
| 火山 ASR | 已启用 `enable_itn` 和 `enable_punc` | 未接 `boosting_table_id/name` | 个人/团队术语没有进入云端解码器 |
| MiMo | UI/运行时允许用户配置本地 MiMo | 上游官方栈要求 Linux、Python 3.12、CUDA 12+、FlashAttention | 不应作为原生 Mac 的稳定默认方案 |
| 后处理 | 个人词典替换 + 屏幕/历史/词典上下文 + 低温 LLM；有基础尾部清理 | 提示词要求“力度高于轻度润色”；无候选/置信度输入、无严格 JSON 编辑、无实体/数字/URL/path guard | 可读性提升和语义篡改混在一起，难以自动兜底 |
| 评测 | 有提示词和文本清理相关测试 | 无真实音频语料、CER/WER、静音集、专名/数字精确率和延迟基线 | 无法科学选择模型和参数 |

对应代码入口：

- `Sources/Speech/WhisperEngine.swift`
- `Sources/Speech/WhisperStreamingSession.swift`
- `Sources/Speech/AppleSpeechAnalyzer.swift`
- `Sources/Speech/VolcSpeechEngine.swift`
- `Sources/Speech/LocalASRRuntime.swift`
- `Sources/Resources/Scripts/local-asr-runner.py`
- `Sources/Audio/AudioCaptureManager.swift`
- `Sources/Processing/TextProcessor.swift`
- `Sources/Prompts/PromptCatalog.swift`

## 3. 分阶段路线

### 3.1 本轮可直接落地

这里的“本轮”指不更换产品架构、能围绕现有 Swift/WhisperKit/Apple/Qwen 代码完成的改造。

| 优先级 | 改造 | 预期收益 | 工作量 | 风险与验收 |
|---|---|---|---|---|
| P0 | 建立小型音频基准与统一指标 | 后续每个参数变化都有证据 | 中 | 先产出 baseline；没有 baseline 不合入模型/参数变更 |
| P0 | 把引擎返回值从 `String` 升级为 `TranscriptEvidence` | 支撑低置信复核、候选纠错、流式稳定 | 中 | 所有引擎先允许字段为空，避免一次性重写 |
| P0 | Whisper 显式质量档：锁定模型、恢复可调 fallback、保留 timestamps/word probability/no-speech | 直接改善难音频并让异常可检测 | 小到中 | 用短于 1 秒、静音、长句验证；不可只比较几个口述样例 |
| P0 | 将个人词典/屏幕高价值词送入 Apple、Whisper、Qwen、火山各自的 context/hotword 接口 | 人名、产品名、专业词通常是感知质量最大的短板 | 中 | 限量、去重、净化；必须测普通词误吸附和重复 |
| P0 | Apple Speech 使用 alternatives/confidence/time range；实时预览使用 progressive preset | 免费获得第二候选与不确定性 | 中 | 仅 macOS 26 路径；保留 legacy fallback |
| P0 | VAD 先用于端点与切段，保留 200–300 ms 前后缓冲；增加削波/静音/噪声指标 | 减少静音幻觉、丢首尾和超长音频退化 | 中 | VAD 不得直接删掉疑似语音而无回退 |
| P0 | 用时间戳 LocalAgreement 替换字符串式流式拼接 | 大幅降低 partial 抖动、重复和接缝错误 | 中 | 记录 partial churn、确认延迟、最终一致性 |
| P0 | 将纠错拆为“忠实纠错”和“表达润色”，默认忠实；加结构化 edits 和保护项 diff guard | 减少 LLM 自作主张改数字、实体和否定词 | 中到大 | 任何不受支持的实词改动可按句回退到 ASR |
| P1 | Qwen3-ASR MLX canary 升级至 `0.2.0`，接 context、repetition penalty | 中文和混说专名可能明显提升 | 小到中 | 上游较新，先旁路比较；不能直接全量替换 |
| P1 | 对低置信片段才启动第二引擎/第二次解码 | 提升难句但避免全程 2 倍延迟 | 中到大 | 需定义触发阈值和延迟预算 |

推荐依赖顺序：

```text
基准与观测
  → TranscriptEvidence
    → ASR 上下文 + Apple 候选/置信度
      → VAD/LocalAgreement
        → 证据约束纠错
          → 低置信二次识别
```

### 3.2 后续路线

这些方向有价值，但不应挤在第一轮里：

1. **Apple 自定义语言模型**：对稳定的个人/行业短语和特殊发音进行本地适配。编译与管理成本高于 `contextualStrings`，应在后者效果有基线后再做。
2. **FluidAudio/Parakeet 英文引擎**：原生 Swift/Core ML、许可友好，适合作为英文旁路 benchmark；目前不是中文主方案。
3. **确定性 ITN 引擎**：接 `text-processing-rs` 处理数字、日期、金额、单位；必须按语言开启，并保护 URL、代码、路径和用户原始数字格式。
4. **中文多引擎 ensemble**：Qwen/Whisper/Apple 仅在风险片段竞争，用词典、候选和语言模型打分，而不是全程并行。
5. **FunASR/WeNet 架构验证**：它们证明了 VAD + ASR + 标点 + ITN + 热词的生产链路，但 Python/C++、模型许可和包体不适合直接成为当前 macOS 第一选择。
6. **显式用户纠正学习**：用户修改后建议加入个人词典或 spoken-form 映射；必须由用户确认，不能把一次修改静默学习为永久规则。

## 4. 建议的识别证据模型

当前协议 `SpeechEngineProtocol.transcribe(...) -> String` 把后续质量优化所需的信息全部抹平。建议兼容式增加：

```swift
struct TranscriptEvidence: Sendable {
    let text: String
    let language: String?
    let engine: String
    let segments: [TranscriptSegment]
    let alternatives: [TranscriptAlternative]
    let diagnostics: TranscriptDiagnostics
}

struct TranscriptSegment: Sendable {
    let text: String
    let startSeconds: Double?
    let endSeconds: Double?
    let confidence: Double?
    let averageLogProbability: Double?
    let noSpeechProbability: Double?
    let words: [TranscriptWord]
}
```

迁移方式：

1. 保留现有 `transcribe(...) -> String` 作为默认适配器。
2. 新增 `transcribeEvidence(...)`；暂时不支持证据的引擎只填 `text`。
3. Apple 先填 alternatives/confidence/time range；WhisperKit 填 word probabilities、segments、logprob/no-speech；Qwen/火山没有统一置信度时先填诊断与空数组。
4. `TextProcessor` 接收证据对象，但用户选择“不做 AI 后处理”时仍原样输出 `text`。

统一证据后可以实现三个关键策略：

- 高置信、无风险片段跳过昂贵的 LLM 或第二引擎。
- 低置信专名只允许在候选、个人词典、屏幕词中选择。
- 高 no-speech、重复率异常或静音占比高时，不让 LLM 把幻觉润色成看似合理的长句。

## 5. 音频前端：先端点，再谈降噪

### 5.1 应立即加入的音频观测

每次录音仅本地记录聚合指标，不保存隐私音频：

- 总时长、有效语音时长、前/后静音时长。
- RMS、峰值、削波采样比例。
- 噪声底估计、粗略 SNR。
- 输入路由、采样率、声道数。
- VAD 段数、最长静音、丢弃/保留的边界长度。
- ASR real-time factor、首个 partial 延迟、最终延迟。

这些指标可直接解释“麦太小”“蓝牙通话模式”“背景视频”“录音全是静音”等问题，避免所有失败都归因于模型。

### 5.2 VAD/端点策略

第一版优先复用 WhisperKit 已有的 EnergyVAD 或 Apple `SpeechDetector`，不急于引入新的神经网络运行时：

1. 保持一个至少 200–300 ms 的环形 pre-roll。
2. 语音开始后不因一个低能量 frame 就断句。
3. 连续静音达到阈值后关闭一个语音段，但保留 post-roll。
4. 很短的停顿只作为分词线索，不立即提交最终结果。
5. 长听写按已确认的静音边界切成约 15–30 秒段；不能在一个词中间硬切。
6. VAD 判断不确定时保留音频，宁可多送一点静音，也不要不可逆丢音。

[Silero VAD](https://github.com/snakers4/silero-vad)（MIT）的参考实现使用 16 kHz 下 512-sample 窗、双阈值回滞、最短语音/静音、speech padding 和最长段切分；其[精确实现](https://github.com/snakers4/silero-vad/blob/master/src/silero_vad/utils_vad.py)适合作为参数设计参考。它不是第一轮必须引入的依赖。

Apple 明确提醒 VAD 会在某些内容上降低识别质量，因此 `SpeechDetector` 也必须通过语料 A/B，而不是默认认定更“智能”就更准：[SpeechDetector 官方文档](https://developer.apple.com/documentation/speech/speechdetector)。

### 5.3 Apple Voice Processing 只做特性开关

Apple 的 Voice Processing 提供回声消除、噪声抑制和自动增益，官方入口是 [`setVoiceProcessingEnabled`](https://developer.apple.com/documentation/avfaudio/avaudioionode/setvoiceprocessingenabled%28_%3A%29)，背景见 [WWDC23 Optimize voice processing for spatial audio](https://developer.apple.com/videos/play/wwdc2023/10235/)。

但该处理主要面向语音通信。降噪和 AGC 可能同时损伤 ASR 需要的辅音、气声或远场特征。因此建议：

- 仅在 engine stopped 时切换，符合 API 约束。
- `raw` 与 `voiceProcessed` 作为可 A/B 的录音 profile。
- 先按内置麦、AirPods、USB 麦、扬声器回声四类设备测 CER/WER。
- 不在第一轮加入通用 spectral gate；只有基准证明净收益时才启用。

## 6. WhisperKit 优化

### 6.1 锁定模型与解码 profile

WhisperKit 当前源码中的 `DecodingOptions` 默认 fallback 次数为 5，并提供 word timestamps、no-speech、compression ratio、logprob 等阈值。可核查其 [MIT 许可仓库](https://github.com/argmaxinc/argmax-oss-swift)和[当前配置源码](https://github.com/argmaxinc/argmax-oss-swift/blob/8fcbfed028415b0b90f0f10ee7b0303c53b600a0/Sources/WhisperKit/Core/Configurations.swift)。

建议新增显式 profile，而不是散落布尔值：

| Profile | 用途 | 建议 |
|---|---|---|
| `fastPreview` | 实时 partial | 较小模型/较少 fallback，必须有 timestamps |
| `balancedFinal` | 默认最终文本 | 锁定具体模型构建，fallback 2–3 起步，语料调参 |
| `qualityFinal` | 用户主动选择最高质量 | `large-v3` 质量构建，允许更多 fallback 和更长延迟 |

关键改造：

- 模型 catalog 中存确切 model ID，不再用首个模糊匹配。Argmax 当前列出的多语言质量候选包括 `large-v3-v20240930_626MB`；最终仍以本项目语料选择。
- 本轮最终离线识别临时恢复 WhisperKit 上游默认值 5，实时 partial 保持 1，避免每个预览窗最坏执行 6 次解码；这不等于 OpenType 已实测更优，仍须分别测 1、2、3、5 的错误率和 p95 延迟，再决定产品默认值。
- 开启 segment/word timestamps，保留 word probability、segment logprob、no-speech probability。
- 增加静音和音乐样例调 `noSpeechThreshold`、`logProbThreshold`、`compressionRatioThreshold`，不要让 LLM 接管幻觉检测。
- 当前上游 `windowClipTime` 默认是 1 秒；先为 `<1s`、`1–2s` 口令建立回归用例，若确认有跳过风险，再显式降低/关闭该 cutoff。
- `suppressTokens` 需要按实际重复/异常 token 验证，不能复制网上的通用 token 列表。

WhisperKit 的 fallback、语言检测和时间戳生成流程可直接从 [`TranscribeTask.swift`](https://github.com/argmaxinc/argmax-oss-swift/blob/8fcbfed028415b0b90f0f10ee7b0303c53b600a0/Sources/WhisperKit/Core/TranscribeTask.swift)核对。

### 6.2 Prompt 应是词汇提示，不是编辑指令

Whisper prompt 最适合提供“可能出现的前文、专名和拼写样例”，不是要求模型“润色”“不要出错”。whisper.cpp 维护者在[初始 prompt 讨论](https://github.com/ggerganov/whisper.cpp/discussions/348)中也强调 prompt 会强烈影响词汇、标点和风格，因此存在误吸附风险。

推荐生成一个有预算的 `ASRContext`：

1. 个人词典中的 preferred spelling 和 spoken form。
2. 当前窗口 OCR 中高置信、短且稀有的产品名/人名。
3. 已确认的最近一两句，不包含未确认 partial。
4. 语言标签。

禁止送入：

- 完整屏幕 OCR。
- 旧的长篇历史。
- 删除规则、系统指令或“请修正文法”。
- 邮箱、令牌、密钥等敏感内容。

对 Whisper，prompt 长度应很短且每段重新滚动；对 Apple/Qwen/火山则映射到各自原生接口。

### 6.3 使用 VAD chunking

WhisperKit 已有 [EnergyVAD](https://github.com/argmaxinc/argmax-oss-swift/blob/8fcbfed028415b0b90f0f10ee7b0303c53b600a0/Sources/WhisperKit/Core/Audio/EnergyVAD.swift)和 [AudioChunker](https://github.com/argmaxinc/argmax-oss-swift/blob/8fcbfed028415b0b90f0f10ee7b0303c53b600a0/Sources/WhisperKit/Core/Audio/AudioChunker.swift)。第一轮可以先复用其公开能力，避免另带 ONNX/Core ML VAD。

用途应是：

- 切开长静音和长音频。
- 产生 endpoint 候选。
- 给 no-speech 与 hallucination 检测补充信号。

不要用 VAD 把低能量词直接永久删除。

## 7. 流式识别：从字符串拼接改为 LocalAgreement

当前 15 秒尾窗反复解码后按文本合并，无法知道某个词在音频中的位置。更稳妥的开源参考是 [WhisperStreaming](https://github.com/ufal/whisper_streaming)（MIT）的 LocalAgreement 策略，其核心 [`HypothesisBuffer`](https://github.com/ufal/whisper_streaming/blob/6da90b44b7e50d79695e68166d2a2c7609c75abb/whisper_online.py)：

1. 保存上一轮和本轮带时间戳的词。
2. 只提交两轮最长公共词前缀。
3. 新 hypothesis 与已提交边界附近做 n-gram 去重。
4. 未稳定词留在 unstable buffer，下一轮可改写。
5. 约 15 秒或已确认句界处裁剪音频缓存。
6. 只把约 200 字符的已确认前文作为下一窗 prompt。

这套算法可以原生移植成 Swift 数据结构，不需要把 Python 项目嵌入应用。上游论文/README 报告约 3.3 秒延迟属于其环境结果，不代表 OpenType 能直接复现。

建议 UI 同时维护：

- `committedText`：两轮一致、不会再回滚。
- `unstableText`：灰色或次级展示，允许变化。
- `audioCursor`：最后已提交的音频时间。

验收指标不能只看最终文本，还要测：

- partial churn：同一位置被改写的次数。
- rollback characters：用户看见后又消失的字符数。
- commit latency：一个词说完到稳定提交的时间。
- final agreement：流式最终与离线最终的差异。

更新更激进的研究参考可看 [SimulStreaming](https://github.com/ufal/SimulStreaming)（MIT）；它依赖 PyTorch，适合作为算法参考，不适合作为当前 macOS 运行时依赖。

## 8. Apple Speech：利用 macOS 26 已有能力

Apple 的 [SpeechAnalyzer](https://developer.apple.com/documentation/speech/speechanalyzer)正好匹配本项目最低系统版本。本轮保留 `SpeechTranscriber(.transcription)` 作为首选高质量路径，只在 locale 不支持或分析失败时回退 short/long `DictationTranscriber`；`AnalysisContext.contextualStrings` 按 Apple 的支持边界接在 Dictation fallback。下一步仍建议把首选路径拆成：

- 实时预览：[`progressiveTranscription`](https://developer.apple.com/documentation/speech/speechtranscriber/preset/progressivetranscription)。
- 最终识别：[`transcriptionWithAlternatives`](https://developer.apple.com/documentation/speech/speechtranscriber/preset/transcriptionwithalternatives)，或需要时间范围时用 [`timeIndexedTranscriptionWithAlternatives`](https://developer.apple.com/documentation/speech/speechtranscriber/preset/timeindexedtranscriptionwithalternatives)。
- 自定义构造时请求 alternative transcriptions，以及 `audioTimeRange`、[`transcriptionConfidence`](https://developer.apple.com/documentation/speech/speechtranscriber/resultattributeoption/transcriptionconfidence) 属性。

Apple 官方 [WWDC25 Bring advanced speech-to-text to your app with SpeechAnalyzer](https://developer.apple.com/videos/play/wwdc2025/277/)展示了 analyzer、asset 管理与渐进式结果的完整路径。

### 8.1 `AnalysisContext.contextualStrings`

[`AnalysisContext.contextualStrings`](https://developer.apple.com/documentation/speech/analysiscontext/contextualstrings)允许提供最多 100 个短语，官方建议使用一到两个词的短短语，并可按 tag 分组。推荐预算：

| 来源 | 数量建议 | 示例 |
|---|---:|---|
| 用户固定个人词典 | 40 | OpenType、Roleva、人名 |
| 当前屏幕高价值词 | 30 | 当前应用、文档标题、代码符号 |
| 最近确认上下文 | 20 | 当前主题专名 |
| 预留 | 10 | 应用命令、临时词 |

必须去重、按语言过滤、限制长度，并避开普通单字/常用词；否则上下文会把相似声音错误吸向热词。

### 8.2 自定义语言模型放到第二阶段

Apple 的 [`SFCustomLanguageModelData`](https://developer.apple.com/documentation/speech/sfcustomlanguagemodeldata)支持 [`PhraseCount`](https://developer.apple.com/documentation/speech/sfcustomlanguagemodeldata/phrasecount)和 [`CustomPronunciation`](https://developer.apple.com/documentation/speech/sfcustomlanguagemodeldata/custompronunciation)，完整流程见 [WWDC23 Customize on-device speech recognition](https://developer.apple.com/videos/play/wwdc2023/10101/)。

适合：

- 稳定的产品词库。
- 用户反复纠正的人名。
- 非标准读音和缩写。

不适合每次录音动态重建。第一阶段先验证 `contextualStrings`，只有频繁术语仍明显漏识别时再引入模型编译和版本管理。

## 9. Qwen3-ASR、火山和 MiMo

### 9.1 Qwen3-ASR MLX

[Qwen3-ASR 官方仓库](https://github.com/QwenLM/Qwen3-ASR)代码为 Apache-2.0，官方 [`qwen3_asr.py`](https://github.com/QwenLM/Qwen3-ASR/blob/7c6daf77a2421100f5fb066495372c00129d39ff/qwen_asr/inference/qwen3_asr.py)支持 context 和语言控制；模型覆盖和 benchmark 数字是上游自报，应在本项目语料复测。

OpenType 实际依赖社区 [qwen3-asr-mlx](https://github.com/gabrimatic/qwen3-asr-mlx)（MIT）。其 [PyPI `0.2.0`](https://pypi.org/project/qwen3-asr-mlx/) 于 2026-07-24 发布并增加 context/hotword 相关能力；当前项目基线仍固定 `0.1.1`。其[模型实现](https://github.com/gabrimatic/qwen3-asr-mlx/blob/7f8b420ad4188c6a2be038ba8e24d9f00cfedb72/src/qwen3_asr_mlx/model.py)暴露 greedy/temperature、repetition penalty 和 context。

建议用 canary 方式升级：

1. 更新独立运行时版本和 marker，不破坏旧 runtime 回退。
2. 请求协议新增短 `context`，来源只取净化后的个人词典与顶部 OCR 词。
3. 默认确定性解码，测试 `repetition_penalty` 约 1.2 的候选值。
4. 短音频返回空时允许一次低温重试，但不能无限重试。
5. 记录 context 命中、重复率和普通词误吸附。

可直接参考同作者 [local-whisper 的 context builder](https://github.com/gabrimatic/local-whisper/blob/6ff31ffb99cfce6858ddf50f259ac1109010beb5/src/whisper_voice/engines/context.py)（MIT）：长度预算、去重、preferred spelling/spoken form、排除删除规则。其 [Qwen wrapper](https://github.com/gabrimatic/local-whisper/blob/6ff31ffb99cfce6858ddf50f259ac1109010beb5/src/whisper_voice/engines/qwen3_asr.py)还展示了 context 和重复惩罚的调用方式。

风险：Qwen 上游已有[热词导致重复的报告](https://github.com/QwenLM/Qwen3-ASR/issues/140)。因此不能把整页 OCR 或全部历史直接塞给模型。

### 9.2 火山 ASR

火山官方[热词文档](https://www.volcengine.com/docs/6561/155739?lang=zh)支持请求传 `boosting_table_id` 或 `boosting_table_name`。官方约束包括最多 5000 词、单词长度和权重范围，并明确提醒常用单字/短语可能损伤整体准确率；[FAQ](https://www.volcengine.com/docs/6561/155743?lang=zh)说明热词本质是提高解码概率，效果依赖音频和基础模型。

本轮可做：

- 在 provider 配置中增加可选 hotword table ID/name。
- 请求体按用户配置传值。
- 不自动上传/修改云端热词表；这需要额外授权和账号权限设计。
- 文档提示热词表应放专名，不放常用词。

火山是专有云服务，不属于开源依赖。

### 9.3 MiMo

[MiMo-V2.5-ASR 官方仓库](https://github.com/XiaomiMiMo/MiMo-V2.5-ASR)代码为 Apache-2.0，但上游安装要求是 Linux、Python 3.12、CUDA 12+ 和 FlashAttention。当前 macOS Apple Silicon 无官方原生推理路径。

产品上应：

- 标记为“实验性/外部运行时”，不作为推荐的本地 Mac 引擎。
- 不在质量主路线中投入大量兼容修补。
- 如果将来出现经验证的 Metal/Core ML 端口，再单独做许可证、模型权重和质量评估。

## 10. 纠错后文本：从自由改写改为证据约束

### 10.1 拆成两种用户意图

默认模式应为：

**忠实纠错**

- 补标点、断句、大小写、明确的 ITN。
- 清理嗯、啊、重复起句和说话者已完成的自我纠正。
- 不改变否定、时态、数字、实体、术语和因果关系。
- 实词替换必须有候选、词典、屏幕词或高可信上下文支持。

另设显式模式：

**表达润色**

- 允许重排语序、压缩冗余、改变格式。
- 仍保护数字、专名、URL、邮箱、路径、代码 token 和引用。
- 用户清楚知道这是改写，不把它包装成“识别原文”。

改造前中文 system prompt 要求“力度要高于轻度润色”。本轮已把默认提示改为忠实纠错，并为专业风格保留表达整理；产品上仍应进一步拆成两个显式模式，让用户知道何时允许自由改写。

### 10.2 三阶段流水线

```text
ASR evidence
  → deterministic normalization
  → evidence-constrained LLM correction
  → semantic/protected-token validator
      ├─ pass: output
      └─ fail: per-sentence fallback or raw transcript
```

第一阶段只做可审计的确定性操作：

- Unicode/空白规范化。
- 引擎已知占位符清理。
- 有边界的个人词典 exact replacement。
- 语言明确时的 ITN。
- 不处理语义不确定的同音词。

第二阶段要求严格结构化输出，例如：

```json
{
  "final_text": "把 OpenType 2.5 的发布改到 8 月 3 日。",
  "edits": [
    {
      "source": "open type",
      "replacement": "OpenType",
      "reason": "personal_dictionary",
      "evidence_id": "dictionary:42"
    }
  ],
  "uncertain_spans": []
}
```

允许的 `reason` 是枚举，而不是自由发挥：

- `punctuation`
- `filler`
- `self_correction`
- `itn`
- `asr_alternative`
- `personal_dictionary`
- `screen_context`
- `formatting`

第三阶段独立验证：

- 所有 edit 的 source span 必须能在原文对齐。
- 新增/删除的数字、百分比、日期、金额、计量单位必须一致。
- URL、邮箱、文件路径、代码 token、版本号默认逐字符保护。
- 否定词（不、没、未、不要、cannot 等）变化触发回退。
- 未被 evidence 支持的人名/机构/产品实词替换触发回退。
- 输出为空、异常变长、重复 n-gram 或语言突变时回退。

本轮已经落地其中的第一层整段 guard：保护有序数字/单位/URL/email/path、全部启用词典术语和否定邻近词，并检查短句及长文本的内容覆盖率与长度异常；确定性口述数字证据可放行有限 ITN。口述邮箱/URL/path 生成、严格 `edits` schema、声学候选对齐、重复 n-gram/语言突变检测和按句回退尚未实现，因此不能把它描述成完整的语义验证器。

回退粒度优先是句子/segment，不要因为一句风险把整段优质纠错全部丢掉。

### 10.3 N-best 和置信度的正确用途

[HyPoradise/Hypo2Trans](https://github.com/Hypotheses-Paradise/Hypo2Trans)（MIT）及其[论文](https://arxiv.org/abs/2309.15701)研究用 N-best 假设做 ASR 后纠错。其公开结果中也有部分 domain 被 LLM 改差，这正说明“总是让大模型重写一遍”不是安全策略。

后续研究进一步指出 N-best 提供更多声学证据，而不受约束的生成在未知 domain 可能退化：[Towards Robust and Generalizable ASR Error Correction](https://arxiv.org/abs/2409.09554)。

在 OpenType 中应这样用：

1. Apple alternatives、Whisper 候选/低置信词先形成 evidence set。
2. LLM 只在低置信 span 中从候选、词典或发音相近项选择。
3. 高置信文本只补标点/格式，减少无意义改写。
4. 两个引擎分歧很大时标为 uncertain，不要强行“猜一个更顺的”。

### 10.4 ITN 与标点

[text-processing-rs](https://github.com/FluidInference/text-processing-rs)（Apache-2.0）提供 Rust 实现和 Swift XCFramework wrapper，声称兼容 NeMo 的 TN/ITN 规则并覆盖中、英、日等语言。它比 Python/Pynini 更适合原生 macOS，但第一轮仍应做独立 spike：

- 只在明确语言启用。
- 测试中文日期、金额、百分比、电话号码、版本号。
- URL、路径、代码段跳过 ITN。
- 规则错误时允许保留 spoken form。

原始 [NeMo text processing](https://github.com/NVIDIA/NeMo-text-processing)为 Apache-2.0，但 Pynini/Linux 依赖不适合直接嵌入当前应用。

标点优先顺序：

1. ASR 原生标点。
2. 忠实 LLM 断句。
3. 大型独立标点模型仅在前两者基准仍不够时考虑。

## 11. 低置信二次识别

成熟产品常见优势不是“永远运行两个最大模型”，而是只为困难片段花额外算力。

建议风险分：

```text
risk =
  low average logprob
  + high no-speech probability
  + low Apple confidence
  + engine disagreement
  + repeated n-grams
  + expected dictionary term missing
  + poor audio SNR / clipping
```

策略：

- `low risk`：直接确定性规范化，必要时轻量纠错。
- `medium risk`：同一引擎质量 profile 重解码，增加短 context。
- `high risk`：只重识别对应音频 segment；调用第二引擎或 Apple alternatives。
- `silence/hallucination risk`：拒绝生成长文本，提示未检测到清晰语音。

第二引擎候选：

- 中文：Qwen3-ASR MLX 与 Whisper/Apple 互补。
- 英文：[FluidAudio](https://github.com/FluidInference/FluidAudio)（Apache-2.0）的 Core ML Parakeet 可作为旁路 benchmark。其[模型支持表](https://github.com/FluidInference/FluidAudio/blob/main/Documentation/Models.md)显示 Parakeet v2 主要是英文、v3 是多种欧洲语言，不应被误当成中文主引擎。
- 云端：用户已配置火山时可作为高质量候选，但必须遵守隐私和网络设置。

## 12. 评测方案

### 12.1 语料

先做 200–500 条版本化、用户授权、本地保存的短语料；CI 只放可公开/合成的极小子集。至少覆盖：

| 维度 | 必测样例 |
|---|---|
| 语言 | 普通话、英语、粤语（若支持）、中英 code-switch |
| 设备 | 内置麦、AirPods/蓝牙、USB 麦、远场 |
| 环境 | 安静、风扇、咖啡店、键盘声、扬声器回声、背景视频 |
| 时长 | `<1s`、1–10 秒、30–120 秒 |
| 术语 | 人名、公司、产品、缩写、技术词、个人词典命中/不命中 |
| 保真 | 数字、日期、金额、百分比、单位、URL、邮箱、代码、文件路径 |
| 口语 | filler、重复、自我纠正、口述标点、犹豫 |
| 负样例 | 全静音、音乐、环境声、极低音量、削波 |

每条音频需要两份 gold：

1. `faithful_reference`：忠实记录说了什么，用于原始 ASR。
2. `sendable_reference`：用户认可的可直接发送文本，用于纠错后质量。

不能用“sendable 文本”计算原始 ASR CER，否则模型正确保留口语词反而被算错。

### 12.2 指标

[JiWER](https://github.com/jitsi/jiwer)（Apache-2.0）可计算 WER、MER、WIL、WIP、CER；v4 对空 reference 有定义，因此能直接量化静音音频产生的插入幻觉。

最低指标集：

- 中文 CER。
- 英文 WER。
- 中英混合的字符/词混合错误率。
- 专名召回率与 preferred spelling exact match。
- 数字/日期/金额/单位 exact match。
- URL/email/path/code token exact match。
- 静音插入率和 hallucinated characters/minute。
- 重复 n-gram 率。
- 标点 F1。
- 后处理前后 semantic preservation 人审评分。
- 用户最终编辑距离/删除字符数/重新口述率。
- p50/p95 首 partial 延迟、最终延迟、real-time factor。
- partial churn、rollback characters、commit latency。
- 内存峰值、功耗和包体。

仓库中的第一版 evaluator 已实现 raw/processed CER、英文 WER、术语 exact match、空 reference 幻觉、延迟，以及数字/URL/email/path 的逐条有序 exact 比较；多出来、丢失和交换的 token 都计错，同时保留 multiset precision/recall 统计。真实音频、标点 F1、semantic 人审、partial churn、功耗等仍需后续采集。

### 12.3 人审

对至少 50 条难例做匿名、随机顺序、成对对比：

- 语义忠实。
- 可读性。
- 专业词准确。
- 数字和实体保真。
- 格式是否可直接发送。

评审者不能知道引擎/参数。保留“二者相同/都不好”，避免强迫选边。

### 12.4 合入门禁

第一版可采用保守门禁：

- 总体 CER/WER 不得显著退化。
- 专名召回提升不能以普通词误吸附明显上升为代价。
- 数字、URL、路径 exact match 不得因 LLM 纠错下降。
- 静音幻觉必须下降或持平。
- p95 最终延迟和内存必须在产品预算内。
- 所有 `<1s`、空音频、长静音和长听写接缝测试通过。

等 baseline 建立后，再把“显著退化”和延迟预算固化为具体数值。

## 13. 可复用开源代码清单

| 项目 / 精确代码 | 许可证 | 可复用内容 | 对 OpenType 的可移植性 | 建议 |
|---|---|---|---|---|
| [WhisperKit](https://github.com/argmaxinc/argmax-oss-swift) / [`Configurations.swift`](https://github.com/argmaxinc/argmax-oss-swift/blob/8fcbfed028415b0b90f0f10ee7b0303c53b600a0/Sources/WhisperKit/Core/Configurations.swift) | MIT | 解码选项、阈值、timestamps、fallback | 高，已依赖 | 直接使用 |
| WhisperKit / [`EnergyVAD.swift`](https://github.com/argmaxinc/argmax-oss-swift/blob/8fcbfed028415b0b90f0f10ee7b0303c53b600a0/Sources/WhisperKit/Core/Audio/EnergyVAD.swift) / [`AudioChunker.swift`](https://github.com/argmaxinc/argmax-oss-swift/blob/8fcbfed028415b0b90f0f10ee7b0303c53b600a0/Sources/WhisperKit/Core/Audio/AudioChunker.swift) | MIT | 能量 VAD、音频切段 | 高 | 第一轮复用 |
| [whisper.cpp](https://github.com/ggml-org/whisper.cpp) / [stream example](https://github.com/ggml-org/whisper.cpp/blob/master/examples/stream/README.md) | MIT | rolling prompt、VAD、beam/streaming 参数参考 | 中 | 算法参考，不新增第二套 Whisper runtime |
| [WhisperStreaming](https://github.com/ufal/whisper_streaming) / [`HypothesisBuffer`](https://github.com/ufal/whisper_streaming/blob/6da90b44b7e50d79695e68166d2a2c7609c75abb/whisper_online.py) | MIT | LocalAgreement、时间戳去重、buffer trim | 高，算法可重写为 Swift | 第一轮移植 |
| [SimulStreaming](https://github.com/ufal/SimulStreaming) | MIT | AlignAtt/LocalAgreement 新版流式策略 | 低到中，PyTorch-centric | 后续研究 |
| [Silero VAD](https://github.com/snakers4/silero-vad) / [`utils_vad.py`](https://github.com/snakers4/silero-vad/blob/master/src/silero_vad/utils_vad.py) | MIT | 双阈值 VAD、padding、最长段切分 | 中，需 ONNX/Core ML 集成 | 先参考参数，后续 benchmark 决定是否引入 |
| [Qwen3-ASR](https://github.com/QwenLM/Qwen3-ASR) | Apache-2.0 | 官方 context、语言控制、对齐器 | 中，官方 Python 栈 | 用作 API/行为基准 |
| [qwen3-asr-mlx](https://github.com/gabrimatic/qwen3-asr-mlx) | MIT | Apple Silicon MLX 推理、context、重复抑制 | 高，已依赖旧版 | canary 升级 |
| [local-whisper context builder](https://github.com/gabrimatic/local-whisper/blob/6ff31ffb99cfce6858ddf50f259ac1109010beb5/src/whisper_voice/engines/context.py) | MIT | 有预算、净化、去重的术语 context | 高，逻辑可重写为 Swift | 直接借鉴算法并保留许可声明 |
| [FluidAudio](https://github.com/FluidInference/FluidAudio) | Apache-2.0 | Swift/Core ML ASR、VAD、英文 Parakeet | 高，但增加模型与包体 | 英文后续旁路 benchmark |
| [text-processing-rs](https://github.com/FluidInference/text-processing-rs) | Apache-2.0 | 中英日等 TN/ITN、Swift XCFramework | 中到高 | 后续独立 spike |
| [HyPoradise/Hypo2Trans](https://github.com/Hypotheses-Paradise/Hypo2Trans) | MIT | N-best 后纠错数据和方法 | 低，训练栈不嵌入；方法可借鉴 | 作为纠错设计证据 |
| [JiWER](https://github.com/jitsi/jiwer) | Apache-2.0 | WER/CER/空音频指标 | 高，离线测试工具 | 直接用于 benchmark 脚本 |
| [FunASR](https://github.com/modelscope/FunASR) | MIT（模型权重另查） | VAD + ASR + punctuation + hotword + ITN 流水线 | 低到中，Python/Torch | 架构/中文 benchmark |
| [WeNet](https://github.com/wenet-e2e/wenet) | Apache-2.0（模型权重另查） | context graph、WFST、N-best、流式 ASR | 低，C++/libtorch | 架构参考 |
| [MiMo-V2.5-ASR](https://github.com/XiaomiMiMo/MiMo-V2.5-ASR) | Apache-2.0（具体权重另查） | 中英 ASR 研究 | 低，上游要求 Linux/CUDA | 不作为原生 Mac 主路线 |
| [VoiceInk](https://github.com/Beingpax/VoiceInk) | GPL-3.0 | macOS 本地听写产品架构参考 | 代码复制会带来 GPL 义务 | 仅参考，不复制进当前项目 |

许可证注意：

- 表中“代码许可证”不自动覆盖模型权重、训练数据、服务条款。
- 真正复制源码前应保留 copyright/license notice，并核对当前固定 commit 的许可证。
- Apple Speech 和火山 ASR 是平台/服务接口，不是开源代码。
- GPL-3.0 项目只作行为与架构参考，除非项目明确接受 GPL 传播义务。

## 14. 不建议的捷径

1. **只把 LLM prompt 写得更长**：ASR 没提供候选和声学证据时，大模型只能猜，越会写越可能把错误润色得像真的。
2. **所有录音永远双引擎**：功耗、内存、延迟翻倍；应只处理低置信 segment。
3. **把完整 OCR/历史当热词**：会泄露不必要内容，也会造成误吸附和重复。
4. **默认开启强降噪/AGC**：通信音质更“干净”不等于 ASR CER 更低。
5. **VAD 判静音就硬删除**：低音量字、塞音、句尾容易被切掉。
6. **看到上游 benchmark 就更换主引擎**：数据集、语言、设备和量化方式都可能不同。
7. **在没有 gold corpus 时调十几个阈值**：得到的只是不可复现的主观印象。
8. **把 MiMo 当作现成的原生 Mac 引擎**：上游官方运行条件并不支持该结论。

## 15. 建议的首批验收任务

1. 建 30 条最小 corpus：10 条中文专名、5 条中英混说、5 条数字/URL/path、5 条短音频、5 条静音/噪声。
2. 输出当前 Apple、Whisper、Qwen 的 baseline：raw CER/WER、专名、数字、静音幻觉、p95 延迟。
3. 加 `TranscriptEvidence`，但先不改变 UI 输出。
4. Whisper 开 timestamps/word confidence，比较 fallback 1/2/3。
5. Apple 加 20 个 contextual strings，并取 alternatives/confidence。
6. Qwen 0.2.0 走独立 canary runtime，只在 benchmark 开启 context。
7. 用 LocalAgreement 做一个流式 feature flag，测 partial churn。
8. 在现有整段 guard 上增加结构化 edits、声学候选证据和按句回退，再与改造前 prompt 做盲测。
9. 只有上述结果明确后，才决定是否引入 Silero、FluidAudio 或 ITN 新依赖。

这批任务完成后，团队将第一次能回答三个关键问题：

- 错误主要来自音频、ASR，还是后处理？
- 哪个引擎在用户真实中文/英文场景最可靠？
- 额外延迟和算力究竟换来了多少可测的准确率提升？

## 16. 主要一手来源

- Apple: [Speech framework](https://developer.apple.com/documentation/speech/), [SpeechAnalyzer](https://developer.apple.com/documentation/speech/speechanalyzer), [AnalysisContext](https://developer.apple.com/documentation/speech/analysiscontext), [WWDC25 SpeechAnalyzer](https://developer.apple.com/videos/play/wwdc2025/277/), [WWDC23 custom language model](https://developer.apple.com/videos/play/wwdc2023/10101/)
- Argmax: [WhisperKit source](https://github.com/argmaxinc/argmax-oss-swift)
- OpenAI-compatible Whisper runtime reference: [whisper.cpp source](https://github.com/ggml-org/whisper.cpp)
- UFAL: [WhisperStreaming source](https://github.com/ufal/whisper_streaming), [SimulStreaming source](https://github.com/ufal/SimulStreaming)
- Qwen: [Qwen3-ASR source](https://github.com/QwenLM/Qwen3-ASR), [Qwen3-ASR paper](https://arxiv.org/abs/2601.21337)
- Xiaomi: [MiMo-V2.5-ASR source](https://github.com/XiaomiMiMo/MiMo-V2.5-ASR)
- Volcano Engine: [hotword documentation](https://www.volcengine.com/docs/6561/155739?lang=zh), [hotword FAQ](https://www.volcengine.com/docs/6561/155743?lang=zh)
- ModelScope: [FunASR source](https://github.com/modelscope/FunASR)
- WeNet: [WeNet source](https://github.com/wenet-e2e/wenet)
- ASR correction: [HyPoradise/Hypo2Trans](https://github.com/Hypotheses-Paradise/Hypo2Trans), [Towards Robust and Generalizable ASR Error Correction](https://arxiv.org/abs/2409.09554)
