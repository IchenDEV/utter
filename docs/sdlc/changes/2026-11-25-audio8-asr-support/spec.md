# Spec: 支持 Audio8-ASR-0.1B 本地语音识别模型

**Status:** approved
**Approved-by:** 用户（本会话明确回复“批准”）
**Approved-date:** 2026-11-25
**Upstream:** [Intent](intent.md)

## Context

Intent 已获批准。该批准同时确认了一个产品边界：Utter 可以提供由终端用户自行下载、仅限非商业用途的 Audio8 功能，但不能把它设为默认模型，也不能绕过 CC BY-NC 4.0。

设计调查发现以下事实：

- 规范仓库是 `Edge0/Audio8-ASR-0.1B`；`AutoArk-AI/Audio8-ASR-0.1B` 当前重定向到同一仓库。当前上游 revision 是 `8487da63d581fa4fc9b5c60444cb57c3a523d7aa`。
- 根仓库是 Transformers checkpoint，`model_type` 为 `arkasr`。它包含一个 Qwen3-ASR 风格音频编码器、4 层 MLP adapter/projector，以及 8 层 Qwen2 风格 causal LM。权重文件是 BF16 `model.safetensors`，大小 648,031,000 字节。
- 推理所需文件合计 663,928,408 字节。仓库还包含约 78 MB 演示视频和上游 Python 源码；这些文件不应进入用户下载。
- 官方示例使用 16 kHz 单声道音频、最长 30 秒、贪心解码、`max_new_tokens=128`。上游明确支持 decode-time hotword logit boosting。
- 已固定的 `mlx-audio-swift` 0.1.3 含 MIT 许可证的 Qwen3-ASR 音频编码器、mel 前端和大部分生成循环模式。已固定的 MLX LM 代码含 MIT 许可证的 Qwen2 decoder 参考实现。
- 上游 iOS/ANE 包体积更小，但它引入 Core ML + ONNX Runtime 两套运行时、量化 KV-cache 契约和 staging 资产格式。当前 `microsoft/onnxruntime` GitHub 仓库不可访问，无法安全审计或固定 Swift package 供应链。
- Utter 现有 `SpeechEngine` 只要求文件级 `transcribe(audioURL:language:)`；`MLXPlugins` 已有 ASR provider 注册、缓存和卸载模式；`ModelCatalog` 已有 Hugging Face 下载、取消、恢复、generation commit 和删除语义。

## Decision

采用 **MLX-native 直接加载官方 checkpoint** 的方案。Audio8 是一个新的 ASR engine/provider，而不是 Qwen3 provider 下的一个模型变体。

选择该方案的原因：

1. 不新增 ONNX Runtime 或 Core ML 包依赖；继续使用已经固定并通过 release build 验证的 MLX 依赖。
2. 不复制上游 CC BY-NC Python 或 Swift 实现。音频编码器和 Qwen2 decoder 的实现基础来自项目已依赖的 MIT 代码；Audio8 特有层按公开配置、权重形状和可观察行为实现。
3. 只下载最终用户选择下载的 NC 权重和 tokenizer/config 文件；Utter 仓库、DMG 和源码不嵌入权重。
4. 可以直接实现 hotword/context boosting、明确取消和明确 30 秒错误；iOS/ANE 资产包不暴露同等热词能力，且上游封装会静默截断长音频。
5. 数值正确性可以用仓库已有中英文音频 fixture 做端到端验收；如果该路径不能通过验证，保留 ONNX/Core ML 作为后续替代设计，而不是在本变更中同时实现两条路径。

被拒绝的方案：

| 方案 | 结论 | 原因 |
|---|---|---|
| vendoring 上游 SpeechKit | 拒绝 | 会把 NC 许可代码复制进 MIT 应用；上游对长音频静默截断；仓库是 staging 包且结构可变 |
| 自写 ONNX Runtime + Core ML adapter | 暂缓/后备 | 内存潜力更好，但新增二进制依赖、两套 runtime 和量化 KV 契约；当前 ONNX Runtime 供应链不可验证 |
| Python subprocess | 拒绝 | 打包、签名、notarization、进程生命周期和内存成本都不符合 Utter 架构 |
| 转换为社区 MLX 模型再分发 | 拒绝 | 不能重新分发 NC 权重；转换质量也无法作为首版可信度基础 |
| 不支持 | 拒绝 | 已存在可验证、无新增 runtime 依赖的实现路径 |

## Design

### 1. Catalog、provider 和用户选择

- 新增 `SpeechEngineType.audio8`（持久化 raw value：`audio8`），加入 `selectableCases`，位置在 Qwen3 之后、其他旧引擎之前；默认选择不变。
- 新增 provider `speech.audio8`、service key、builtin registration 和 composition mapping。provider 只包含一个模型资产：`Edge0/Audio8-ASR-0.1B`。
- `SpeechEngineType.audio8.asrModelID` 返回该固定模型 ID；`SpeechSelection` 按现有 fixed-model 引擎模式解析。
- 模型显示名为 `Audio8-ASR 0.1B`。中英文 hint 都必须在下载按钮可见前直接写明：约 664 MB、本地 MLX 推理、CC BY-NC 4.0、仅限非商业用途。模型区域同时提供指向上游 LICENSE 的链接。
- 模型不在启动时 preload；切换引擎或删除模型时走现有 cache shutdown/unload 路径。
- 修正当前 ASR 行选择逻辑硬编码切到 `.qwen3` 的问题：选择某个 ASR 模型时必须切到拥有该模型的 engine。该修复覆盖 Audio8，也覆盖现有 FireRed/Mega 同类错误路径。
- 因为本设计实现热词增强，provider 的 recognition vocabulary 保持 `.all`。语言参数不改变提示词；Audio8 自动识别语种。UI 不宣称支持流式识别或手动语种约束。

### 2. 下载范围、revision 和完整性

- `ModelArtifact` 增加可选 revision pin 和“只下载 requiredFiles”语义；Audio8 固定到 revision `8487da63d581fa4fc9b5c60444cb57c3a523d7aa`。
- Audio8 required/download files：`config.json`、`model.safetensors`、`tokenizer.json`、`tokenizer_config.json`、`vocab.json`、`merges.txt`、`added_tokens.json`、`special_tokens_map.json`、`preprocessor_config.json`、`processor_config.json`、`generation_config.json`、`LICENSE`。
- 下载使用现有 Hugging Face endpoint/source、进度、取消、恢复、staging 和 generation commit；matching patterns 排除演示视频、Python 源码、示例和评测文件。
- 下载完成后写入内部 revision marker。完整性检查要求 required files 非空且 marker 等于 artifact revision；缺失、损坏或 revision 不匹配时显示未完整/错误，不静默回退到其他 ASR。
- 沿用现有下载体积估计表，Audio8 估计值记录为 663,928,408 字节。下载 staging commit 期间峰值磁盘可能接近 2 倍模型体积，这是现有模型下载语义，不在本变更中重写。

### 3. MLX-native runtime

新增 `Audio8NativeASREngine` 和小的 `Audio8ASRModel` 实现，放在 `UtterMLX`，文件按仓库约定拆分。runtime 生命周期镜像现有 `MLXSTTEngine`/`QwenNativeASREngine`：懒加载、显式 prepare、shutdown 释放、资源访问通过 `ModelResourceAccess`。

推理管线：

1. 用现有 PCM conversion 把输入文件转为 16 kHz mono。转换后样本数大于 480,000（30 秒）时，在推理前抛出本地化错误；不得截断。
2. 用 `MLXAudioCore.computeMelSpectrogram` 计算 Whisper-style log-mel：`sampleRate=16000`、`nFft=400`、`hopLength=160`、`nMels=128`。
3. Audio token 数使用上游公式：`melFrames = sampleCount / 160`（整数除法）、`downsampled = (melFrames + 1) / 2`、`tokenCount = max(downsampled / mergeFactor, 1)`；本模型 `mergeFactor=4`。
4. prompt 精确构造为：`<|user|><|begin_of_audio|>` + N 个 `<|audio|>` + `<|end_of_audio|>Please transcribe this audio.<|assistant|>`；tokenizer 使用 `addSpecialTokens=false`。
5. 音频编码器复用 MIT `Qwen3ASRAudioEncoder` 的结构语义：conv frontend、chunked windows、sinusoidal positions、18 层 encoder、LayerNorm 和 projection。权重 key 与 `audio_encoder.*` 直接对应；conv 权重按 PyTorch 到 MLX 的布局转置。
6. 实现 `audio_mlp_tower`：4 个 residual block，每块为 LayerNorm → Linear → GELU → Linear，最后 LayerNorm。实现 `audio_projector`：LayerNorm → Linear 到 512 维。
7. encoder 输出经 MLP tower 后，用 adaptive average pooling 调整到 prompt 中的 audio token 数，再经 projector，替换连续 `<|audio|>` placeholder embeddings。
8. 实现 Qwen2 风格 decoder：8 层、hidden 512、8 attention heads、8 KV heads、intermediate 1408、RoPE theta 1,000,000、RMSNorm eps 1e-6、tied embeddings。实现基于项目已有 MIT MLX Qwen2 结构，扩展为可接收 `inputsEmbeds`。
9. 生成采用贪心解码，最多 128 个新 token；在 `<|im_end|>`（151645）或 `<|endoftext|>`（151643）停止。decode 后跳过 special tokens 并 trim。
10. 热词使用 decode-time token trie boosting：把 recognition phrases 用同一 tokenizer 以 `addSpecialTokens=false` 编码，first-token boost 6.0、continuation boost 8.0、仅允许当前 top-50 logits 内的候选。每个 decode step 都执行 cancellation check。
11. 日志只记录模型路径、字符数、耗时和内存，不记录音频内容或转写文本。

### 4. 配置和权重验证

- loader 必须解析并验证根 `config.json`：`model_type == "arkasr"`、`audio_token_id == 151646`、decoder/encoder关键维度、`merge_factor == 4`、`tie_word_embeddings == true`。
- loader 必须拒绝缺关键权重的目录，并给出模型资产损坏错误；不得用默认值静默继续。
- `language_model.lm_head.weight` 不存在是预期状态，因为 embeddings tied；不得把它当作缺失错误。
- Tokenizer 优先使用仓库内 `tokenizer.json`；`vocab.json`/`merges.txt` 仍下载，用于完整性、调试和 tokenizer fallback。

## Safety and failure modes

- **许可证**：Utter 不分发模型权重，不复制上游 NC 代码，不执行 `trust_remote_code` Python。UI 在下载前显示“仅限非商业用途”和 LICENSE 链接。商业用户不能使用该功能；这不是技术绕过点。
- **隐私**：推理本地执行。网络访问只发生在用户显式下载模型时访问配置的 Hugging Face endpoint。日志不写音频或转写内容。
- **资产损坏/缺失**：显示明确错误或未完成状态；不自动切换到 Qwen/Apple/其他引擎。
- **长音频**：超过 30 秒在推理前报本地化错误；不截断、不假装完整转写。
- **取消**：下载取消沿用现有状态；推理 cancellation 至少在每个生成 token 边界生效，取消后 unload/retry 不使用半完整结果。
- **内存/性能**：BF16 checkpoint 本身约 648 MB。验收目标是在本机 Apple Silicon 上，热加载后转写 5 秒测试音频不超过 3 秒，峰值内存不超过 1.5 GB。若达不到，停止发布该路径并回到设计评审，而不是改用小数质量未验证的量化。
- **上游变更**：revision pin 防止新下载 silently 跟踪 `main`。已有缓存 revision 不匹配时要求重新下载。
- **数值偏差**：端到端 fixture 必须识别关键内容；如果输出为空、语言错乱或与参考语义明显不符，视为实现错误，不以“模型质量”解释通过。

## Test strategy

| Acceptance criterion | Automated / manual evidence |
|---|---|
| 模型可见、体积和许可证明确 | artifact/catalog unit tests；localization key checks；模型管理真实窗口 light/dark 截图 |
| 可下载、重启后离线识别、可删除 | download unit tests使用 fake/staged repo 验证 matching、revision marker、完整性；本机真实下载后重启应用手动验证离线转写和删除状态 |
| Audio8 能转写中文/英文短音频 | env-gated integration test（仿照 `OPENTYPE_QWEN_NATIVE_INTEGRATION`）使用 `docs/assets/demos/en-sample.m4a` 和 `zh-sample.m4a`，断言关键语义且日志证明 `Audio8` 路径 |
| 长音频、损坏资产、取消路径明确 | unit/integration tests覆盖 >30 秒 WAV、缺权重、坏 config、cancelled transcription/download；断言不静默 fallback |
| 热词能力 | token trie unit tests；env-gated rare-term audio test比较有/无 context 的输出，至少证明 boost 被应用且不产生空输出 |
| runtime 正确性 | config validation、weight-key sanitization/conv transpose、audio token count、prompt token sequence、adaptive pooling参考值、contiguous audio embedding replacement unit tests |
| 性能/内存 | integration test或诊断脚本记录热加载 5 秒音频耗时和峰值内存；结果写入 `verification.md` |
| 标准质量门 | `bash scripts/sdlc-checks.sh`、`bash scripts/ci-basic-checks.sh`、`swift test` |
| dependency/runtime packaging | release-style `bash scripts/build-app.sh`；确认没有新增 ONNX/Python/runtime 依赖 |

## Rollout and rollback

实施顺序：

1. 先加 artifact metadata、revision/matching 下载和 catalog 选择修复，用 fake repo 完成单元验证。
2. 再加 MLX runtime core；先用本地已下载 checkpoint 做 headless integration，不开放 UI。
3. 通过 fixture、性能和内存验证后，才接 provider/UI、许可证文案和 localization。
4. 最后执行标准检查、真实窗口 QA、release-style build，并把证据写入 `verification.md`。

停止条件：

- 权重加载或音频 encoder 数值路径无法使 fixture 达到语义正确的转写；
- 热加载性能或内存超过本 spec 上限且没有不改变模型语义的修复；
- release build 因 MLX/API 边界失败；
- 许可证无法在下载前清晰展示。

回滚：在发布前直接 revert 全部变更。若发布后必须紧急撤回，先隐藏 catalog/provider 注册并保留 `audio8` settings case 的兼容解码；已选择 Audio8 的用户看到明确不可用错误并可手动改选其他引擎，不做静默识别 fallback。
