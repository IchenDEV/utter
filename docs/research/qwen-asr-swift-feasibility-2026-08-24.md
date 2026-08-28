# Qwen3-ASR 去 Python、原生 Swift/macOS 可行性研究

日期：2026-08-24
范围：Utter 当前使用的 **Qwen3-ASR** 本地转写路径；不把 Qwen-Audio、Qwen2-Audio 等通用音频理解模型当作同一种模型。

## 结论

**可以改，而且不需要从零重写。** 对 Utter 最现实的方案是用 Swift 调用 MLX，在进程内加载现有的 `mlx-community/Qwen3-ASR-1.7B-bf16` 权重，替换当前的 Python 虚拟环境、`qwen3-asr-mlx` 和 JSONL 子进程。推荐先以 [`mlx-audio-swift`](https://github.com/Blaizzy/mlx-audio-swift) 的 `MLXAudioSTT/Qwen3ASR` 为基础做 PoC；它已经明确支持 Utter 当前所用的精确模型，以及 1.7B/0.6B 的 4/6/8-bit 版本。

这里的“原生 Swift”准确含义是：应用层、模型编排、音频预处理和解码均为 Swift，推理由已编译并随 App 签名的 MLX/Metal 原生库完成，**运行时不再下载或执行 Python**。MLX 底层并不是由 Swift 单一语言实现；如果“纯 Swift”被严格解释成连 C/C++/Metal 依赖都不能有，则现有高性能方案均不满足，这也不是 Mac App Store 的要求。

推荐顺序：

1. **首选：MLX Swift + `mlx-audio-swift` 的 Qwen3-ASR 实现。** 最容易复用现有 SafeTensors，和项目已有的 MLX 技术栈一致。
2. **备选：sherpa-onnx 的 Qwen3-ASR。** Swift API 成熟、不需要 Python，但底层是 C++/ONNX Runtime，需更换为 ONNX 拆分模型，不能直接复用当前权重。
3. **中长期备选：Core ML。** 运行时最贴合 Apple 平台，但没有 Qwen 官方 Core ML 包，需要自行转换和验证，当前第三方转换仍有准确率风险。
4. **不建议：自行从头移植或继续在应用内安装 Python。** 前者重复已有实现，后者会增加安装失败面，也破坏应用自包含性。

“现有模型在 Utter 内进程转写、无 Python”的 PoC 已于同日完成；达到完整产品质量，预计仍需 1–2 周。长音频与压力测试、取消行为、准确率基准、下载完整性校验和依赖许可清单是主要剩余工作。

> 证据标记：**[事实]** 可由当前仓库或链接的一手源码复核；**[推断]** 是基于这些事实的工程判断；**[未确认]** 必须由 Utter 自己的 PoC 或真机测试回答。

## 实施与实测更新

- **[事实]** `mlx-audio-swift` 当前固定到正式版本 `0.1.3`，`mlx-swift-lm` 固定到正式版本 `3.31.4`；Qwen 的主录音流水线和 `SpeechEngineProvider` 使用进程内 `QwenNativeASREngine`。Qwen 路径不创建 Python、venv、pip 或子进程。MiMo 正式入口保持关闭，不属于本次改造。
- **[事实]** 测试只使用已经存在的 `/Users/chenli/Library/Application Support/OpenType/huggingface/models/mlx-community/Qwen3-ASR-1.7B-bf16`。测试前后 `model.safetensors` 均为 4,076,186,653 bytes、修改时间保持 `2026-06-02 21:18:41 +0800`，SafeTensors 文件集合未变化，没有下载或复制第二套权重。
- **[事实]** 该模型原先没有 `tokenizer.json`。依赖在首次加载时使用现有的 `vocab.json`、`merges.txt` 和 `tokenizer_config.json` 就地生成了一个 tokenizer 索引；这是派生配置文件，不是新模型或新权重。
- **[事实]** 在 `HF_HUB_OFFLINE=1` 下，Xcode 构建的集成测试使用仓库现有的 5.19 秒英文和 6.34 秒中文音频通过：英文输出 `Hey, so um, I wanted to, I wanted to follow up on the design doc we talked about.`；中文输出 `那个，我想问一下，这个接口呃，是不是周五之前能review一下？`。
- **[事实]** 一次测试中，包含首次模型加载的英文转写为 8.212 秒；复用同一模型实例后的中文转写为 1.114 秒。另一次带系统内存测量的运行受当时负载影响，分别为 10.346 秒和 4.747 秒，因此这些数字只代表当前机器的两次观察，不是性能承诺。
- **[事实]** 带内存测量的测试进程最大 resident set size 为约 1.97 GB，系统报告的 peak memory footprint 为约 5.68 GB。后者包含 Apple Silicon 统一内存/加速器相关占用，更适合当作机器容量规划的保守指标。
- **[事实]** 当前收口版本的完整测试为 557 项 XCTest 通过、8 项按环境跳过，另有 1 项 Swift Testing 通过。未改动的 `scripts/build-app.sh --app-only --sign=-` 生成了 arm64 ad-hoc 签名应用；产物包含 MLX `default.metallib`，通过 `codesign --verify --deep --strict`，且没有 `.py`、`.pyc`、`.so`、旧 runner、pip 或 Python 包标记。本次代码收口不修改原有 GitHub Release、自签名、DMG、Info.plist 或 entitlements 流程。
- **[事实]** 最终原生集成复测仍使用同一现有模型并设置 `HF_HUB_OFFLINE=1`，英文样例耗时 4.635 秒、中文样例 0.375 秒，输出分别为 `Hey, so um, I wanted to, I wanted to follow up on the design doc we talked about.` 与 `那个，我想问一下，这个接口呃，是不是周五之前能review一下？`。
- **[事实]** 本机原托管 Python 环境占用约 288 MB，已从应用支持目录移到废纸篓；3.8 GB 模型目录与权重文件保留在原位置。
- **[未确认]** 两条短样本只能证明方案真实可运行，不能证明产品级 CER/WER、长音频稳定性、100 次连续转写、睡眠唤醒或与旧 Python 路径完全等价。当前同步生成只能在生成前后响应 Task cancellation，尚不能保证模型计算中途 500 ms 内取消。

### 与原版 Python 路径的同条件 A/B

本轮固定同一 1.7B bf16 权重、同一 `QwenAudioPreprocessor`、相同语言参数和三条仓库音频，原版为现有 `qwen3-asr-mlx==0.1.1`，新版为 Release 优化的 Swift/MLX；两边均设置 `HF_HUB_OFFLINE=1`。

| 样本 | 参考口述 | Python 0.1.1 | Swift/MLX |
|---|---|---|---|
| 英文 5.19 秒 | `hey so um i wanted to— i wanted to follow up on the design doc we talked about` | `Hey, so um, I wanted to. I wanted to follow up on the design doc we talked about.` | `Hey, so um, I wanted to, I wanted to follow up on the design doc we talked about.` |
| 中文 6.34 秒 | `那个，我想问一下，这个接口，呃，是不是周五之前能 review 一下` | `那个，我想问一下这个接口呃是不是周五之前能review一下？` | `那个，我想问一下，这个接口呃，是不是周五之前能review一下？` |
| 命令 2.20 秒 | `总结一下屏幕上的内容` | 完全一致 | 完全一致 |

- **[事实] 内容正确性：** 三条样本的词汇内容两边都与参考一致，没有漏词、增词或专有名词错误。区别仅在标点；Swift 对英文自我重启使用逗号而非句号，并保留更多中文停顿，当前小样本上略贴近参考口述。
- **[事实] 低负载热转写：** 第二轮三条总耗时 Python 为 0.777 秒、Swift 为 0.782 秒，基本持平。
- **[事实] 高负载 5 轮中位数：** Python 的英文/中文/命令分别为 2.884/1.950/1.091 秒；Swift 为 2.149/1.694/0.575 秒，三项中位数合计 Swift 约快 25%。这反映当时系统压力下的观察，不代表稳定的产品加速比。
- **[事实] 模型准备：** 低负载观察范围 Python 0.372–0.722 秒、Swift 0.538–0.671 秒；高负载时分别升至 3.813 秒和 8.086 秒。冷启动对机器当前的内存/Metal 调度非常敏感，尚不能断言哪一边恒定更快。
- **[事实] 峰值内存：** Release 单进程测量中，Python 最大 RSS 约 4.22 GB、peak memory footprint 约 5.71 GB；Swift 最大 RSS 约 4.27 GB、footprint 约 5.65 GB，差异约 1%，可视为同一内存等级。
- **[事实] 磁盘：** 原版托管 Python runtime 约 288 MB，现已移出应用支持目录；Swift/MLXAudio 代码计入约 101 MB 的 `.app`。模型权重约 4.08 GB，两种方案完全相同。
- **[推断] 当前结论：** 在这三条短样本上，Swift 版没有可见的识别质量退化，标点略好；Release 性能整体与 Python 同级，热转写没有稳定劣化，内存没有显著变化。去 Python 的主要收益仍是安装可靠性、进程内生命周期和应用自包含性，而不是降低模型内存。

## Utter 改造前实现审计

改造前的链路不是“Python 只做模型转换”，而是每次使用 Qwen3-ASR 时，运行时推理本身依赖 Python：

```text
录音文件
  → QwenAudioPreprocessor（Swift/AVFoundation，16 kHz、单声道、PCM Int16 WAV）
  → LocalASRServer（启动并维持 Python 子进程）
  → local-asr-runner.py
  → qwen3_asr_mlx.Qwen3ASR.from_pretrained(...).transcribe(...)
  → JSONL 返回 transcript
```

关键代码证据：

- **[事实]** 已删除的 `LocalASRRuntime.swift` 曾创建 Python venv、执行 `pip install qwen3-asr-mlx==0.1.1`，并会对下载得到的 `.so`/`.dylib` 去除 quarantine/provenance 后做 ad-hoc 签名。
- **[事实]** 已删除的 `LocalASRServer.swift` 曾用 `Process` 常驻运行 Python，通过 stdin/stdout JSONL 通信；包括 300 秒预热、180 秒请求超时和空闲退出逻辑。
- **[事实]** 已删除的 `local-asr-runner.py` 曾导入 `qwen3_asr_mlx`，加载 `Qwen3ASR` 并执行 `transcribe(audio, language=...)`。
- **[事实]** 已删除的 `LocalASREngine.swift` 曾把预处理后的 WAV 交给 Python server；默认模型是 `mlx-community/Qwen3-ASR-1.7B-bf16`。
- **[事实]** [`QwenAudioPreprocessor.swift`](../../Sources/Speech/QwenAudioPreprocessor.swift) 已经是 Swift/AVFoundation 实现，输出符合 Qwen 要求的 16 kHz 单声道 WAV；它不是去 Python 的难点。
- **[事实]** 本机现有该模型目录约 3.8 GB，核心文件为 `model.safetensors`；仓库的模型管理还要求 `config.json`、tokenizer/vocab 和 preprocessor 配置。
- **[事实]** `Package.swift` 已依赖 Apple MLX Swift 生态中的 `MLXLLM`、`MLXVLM`、`MLXLMCommon`。Utter 的 release 构建已使用 `xcodebuild`，符合 MLX Metal 资源需要 Xcode 参与打包的约束。

据此确定的迁移范围是：保留下载管理和音频采集，增加 Swift Qwen3-ASR 模型/解码器，把 `LocalASRServer` 的职责变成进程内 actor 生命周期管理。无需重做整个语音输入流水线。

## 先澄清：Qwen3-ASR 不是 Qwen-Audio / Qwen2-Audio

| 模型 | 定位 | 与 Utter 当前权重兼容 | 本报告处理方式 |
|---|---|---:|---|
| **Qwen3-ASR-0.6B / 1.7B** | 专用语音识别和语言识别模型，来源于 Qwen3-Omni | 是 | 目标模型 |
| Qwen3-ForcedAligner-0.6B | 文本—音频时间对齐 | 否，需独立模型 | 可选扩展，不是基础转写必需 |
| Qwen2-Audio-7B / Qwen-Audio | 通用音频理解、对话和音频问答模型 | 否 | 不能用其 Swift 示例代替 Qwen3-ASR |
| Qwen3-Omni | 多模态、全模态模型族 | 否 | 架构来源，不是当前可直接替换的模型 |

**[事实]** Qwen 官方的 [Qwen3-ASR 仓库](https://github.com/QwenLM/Qwen3-ASR)、[1.7B 模型卡](https://huggingface.co/Qwen/Qwen3-ASR-1.7B) 和[论文](https://arxiv.org/abs/2601.21337)把它定义为专用 ASR/语言识别模型；官方 [Qwen2-Audio 仓库](https://github.com/QwenLM/Qwen2-Audio)与[模型卡](https://huggingface.co/Qwen/Qwen2-Audio-7B-Instruct)描述的则是 audio-language chat/analysis 模型。两者的模型结构、prompt、processor 和权重键都不同。

## Qwen3-ASR 原生实现实际需要什么

根据官方 [`processing_qwen3_asr.py`](https://github.com/QwenLM/Qwen3-ASR/blob/main/qwen_asr/core/transformers_backend/processing_qwen3_asr.py)、[`modeling_qwen3_asr.py`](https://github.com/QwenLM/Qwen3-ASR/blob/main/qwen_asr/core/transformers_backend/modeling_qwen3_asr.py) 和 [`qwen3_asr.py`](https://github.com/QwenLM/Qwen3-ASR/blob/main/qwen_asr/inference/qwen3_asr.py)：

- **[事实] 音频前端：** 16 kHz 波形，Whisper 风格 log-Mel 特征；当前 1.7B 配置使用 128 个 Mel bins、400 点 FFT、160 sample hop。官方 [`preprocessor_config.json`](https://huggingface.co/Qwen/Qwen3-ASR-1.7B/blob/main/preprocessor_config.json) 可复核参数。
- **[事实] 音频编码器：** 三层 stride-2 Conv2D 前端，加窗口化/分块 self-attention 音频 Transformer；输出投影到文本模型隐空间。
- **[事实] 文本解码器：** Qwen3 自回归 decoder，使用 GQA、RoPE、KV cache 和特殊音频 placeholder tokens；不是把 Mel 特征直接传给通用 `MLXLLM` 就能工作。
- **[事实] tokenizer / prompt：** 必须完全复刻官方 chat template、音频起止 token、语言/上下文约束和输出清理，否则即使网络层数正确，也可能发生截断、重复或语言错误。
- **[事实] 长音频：** 官方实现包含长音频切分和低能量分段逻辑；官方离线 ASR 宣称支持最长 1200 秒，forced aligner 上限不同。

Apple 官方 [`mlx-swift-lm`](https://github.com/ml-explore/mlx-swift-lm) 目前提供的是文本和视觉语言模型框架；其[支持模型清单](https://github.com/ml-explore/mlx-swift-lm/blob/main/skills/mlx-swift-lm/references/supported-models.md)中的 Qwen 是 Qwen2/Qwen3 文本模型族，没有 Qwen3-ASR 音频前端。Hugging Face 官方 [`swift-transformers`](https://github.com/huggingface/swift-transformers)则主要提供 tokenizer 与 Hub 客户端，也不会根据 Python `transformers` 中的自定义模型类自动生成 Swift 网络。

**[推断]** 真正缺失的不是基础矩阵算子。MLX Swift 已有卷积、attention、RoPE、量化线性层和 SafeTensors 读取；缺失的是 Qwen3-ASR 的模型结构绑定、特征提取、权重键映射、tokenizer/prompt、生成和长音频策略。现有第三方库已经覆盖了大部分这层工作。

## 可复用方案

### A. `mlx-audio-swift`：推荐

来源：[`Blaizzy/mlx-audio-swift`](https://github.com/Blaizzy/mlx-audio-swift)，具体实现位于 [`Sources/MLXAudioSTT/Models/Qwen3ASR`](https://github.com/Blaizzy/mlx-audio-swift/tree/main/Sources/MLXAudioSTT/Models/Qwen3ASR)。MIT License。

- **[事实]** README 明确列出 `mlx-community/Qwen3-ASR-1.7B-bf16`，即 Utter 当前模型；同时列出 1.7B/0.6B 的 bf16、8-bit、6-bit、4-bit 版本。
- **[事实]** 提供 Swift Package 产品 `MLXAudioCore`、`MLXAudioSTT`，最低 macOS 14 / iOS 17、Apple Silicon，与 Utter 的 macOS 26 / Apple Silicon 范围兼容。
- **[事实]** `Qwen3ASRModel.fromModelDirectory(_:)` 可以从本地目录直接读 `config.json`、SafeTensors 和 tokenizer；不强制再次下载模型。
- **[事实]** 已实现 Qwen3-ASR config、音频 processor、encoder、decoder、quantization、language alias、context/hotword、长音频切分、生成与测试。仓库也有 Qwen 专用的 config/model/helper 单元测试和模型 smoke test。
- **[事实] 本机独立编译探针：** 最小 SwiftPM executable 同时使用 Utter 已有的 `swift-transformers 1.3.3`、`mlx-swift-lm main`，并将 `mlx-audio-swift` 固定到 `0.1.3`；`swift package resolve` 成功（解析到 `mlx-swift 0.31.6`、`mlx-swift-lm 1441444`），`swift build -c release --target Probe` 冷编译成功，耗时 420.66 秒，链接后的空探针约 49 MB。`0.1.3` tag 已包含 Qwen3-ASR。
- **[事实]** 全量 `MLXAudioSTT` target 还会引入 Codecs、VAD 等能力，构建时间、二进制和依赖审计面明显大于只移植 Qwen 子集。
- **[边界]** 上述探针证明当前工具链和版本解算能编译、链接，不证明 Qwen 权重能正确加载，更不证明转写数值、速度或 Store archive 已通过。
- **[事实]** 截至本报告快照，该项目比其他 Swift Qwen3-ASR 仓库有更活跃的提交和更广的 ASR 模型覆盖，但它仍是第三方项目，不是 Qwen 或 Apple 官方实现。
- **[未确认]** 其生成结果是否与 Utter 当前 `qwen3-asr-mlx==0.1.1` 在真实中文输入上完全等价；必须通过固定语料对测。
- **[未确认]** 它当前暴露的 token 生成 `AsyncStream` 不等于真正的“音频一边进入、一边稳定输出”的 streaming ASR。Utter 当前 Qwen 路径本来就是录完后转写，因此基础迁移不因此退化；若以后要实时 partial result，需要另立验证项目。

集成上可以直接复用现有模型文件，但建议在 Utter 内封装窄接口，而不是把第三方 API 散布到 UI：

```text
Qwen3ASREngine actor
  load(local model directory / pinned revision)
  transcribe([Float], sampleRate: 16_000, language:, context:)
  cancel()
  unload()
```

**[推断]** 最稳的产品化方式是在 PoC 先锁定一个已审查 commit；若依赖树或公开 API 变化过快，再只 vendoring Qwen3-ASR 所需子集。不要长期依赖 `main` 分支。

### B. `ontypehq/mlx-swift-asr`：很接近本项目，但成熟度不足

来源：[`ontypehq/mlx-swift-asr`](https://github.com/ontypehq/mlx-swift-asr)，MIT License。

- **[事实]** 是用 MLX Swift 实现 Qwen3-ASR 的小型 Swift Package，包含 `Qwen3ASRSTT`、模型配置、音频处理、tokenizer 和 actor，目标与 Utter 高度重合。
- **[事实]** 本次本地审计中，`swift test` 能完成库编译；不依赖模型的音频 resample XCTest 通过。模型测试使用 `/server/models/...` 等硬编码外部 fixture，当前 checkout 在没有这些 fixture 时不是一套可独立跑绿的测试。
- **[事实]** 为补充 Xcode/Metal 路径验证，本次将上游测试所需模型目录临时指向 Utter 已下载的 `Qwen3-ASR-1.7B-bf16`，以 `xcodebuild -configuration Debug -only-testing:MLXASRTests/Qwen3ASRTests test` 运行：5 项中 config、模型构建、音频读取、128-bin log-Mel 共 4 项通过；真正的 `testTranscribe` 在加载阶段失败，错误为 `configurationMissing("tokenizer.json")`。现有 MLX community 目录只有 `vocab.json`、`merges.txt` 和 `tokenizer_config.json`，而该库没有像 `mlx-audio-swift` 那样自动合成 `tokenizer.json`。
- **[事实] 实际原生推理：** 随后只在 `/tmp` 审计目录中按上述三个 tokenizer 文件生成 `tokenizer.json`，没有修改 Utter 的模型目录，再以同一 Xcode Debug 命令重跑。测试使用上游 `Tests/MLXASRTests/Resources/test_audio.wav`（7.5839 秒英文），5/5 通过；输出为 `The examination and testimony of the experts enabled the commission to conclude that five shots may have been fired.`。测试报告的模型处理时间为 11.0819 秒，RTF 1.461；包含模型加载的 `testTranscribe` 总计 17.875 秒。
- **[边界]** 这个实测证明 1.7B bf16 SafeTensors、Swift tokenizer、Qwen 音频前端、Swift/MLX decoder 和 Metal 能在本机端到端工作，不证明推荐库 `mlx-audio-swift` 已完成数值验证。它也只有一条干净英文音频，使用 Debug test build，未测中文、量化模型、峰值内存、热启动或 Store archive，因此不能据此评价产品准确率和速度。
- **[事实]** 使用 SwiftPM 命令行运行涉及 MLX 的测试时遇到 `default.metallib` 缺失；这是 MLX Swift 已知的资源打包边界，Apple 项目也建议通过 Xcode 构建。Utter 的 release 流程已经使用 `xcodebuild`。
- **[事实]** 再以 `xcodebuild -configuration Release test` 验证时，上游 package 的测试 target 因 `@testable import` 而要求 `-enable-testing`，构建失败；这不是模型数值失败，但说明其测试/发布工程还不够稳健。
- **[推断]** 适合当作可读、可裁剪的参考实现，暂不适合作为 Utter 的首选上游依赖。

端到端实测命令（第一次暴露 tokenizer 缺口；仅在临时目录补齐数据后第二次 5/5 通过）：

```bash
xcodebuild -scheme mlx-swift-asr \
  -destination 'platform=macOS,arch=arm64' \
  -configuration Debug \
  -only-testing:MLXASRTests/Qwen3ASRTests test
```

### C. `qwen3-asr-swift` / Qwen3Speech：MLX + Core ML 参考

来源：[`ivan-digital/qwen3-asr-swift`](https://github.com/ivan-digital/qwen3-asr-swift)，Apache-2.0。

- **[事实]** 提供原生 Swift 的 MLX 和 Core ML 路径，并有不经过 MLX 的 `transcribeWithoutMLX` Core ML 推理入口。
- **[事实]** Core ML 模型来自第三方 [`aufklarer/Qwen3-ASR-CoreML`](https://huggingface.co/aufklarer/Qwen3-ASR-CoreML)，不是 Qwen 官方发布物；转换阶段可以使用 Python，但安装后的 App 运行时不需要 Python。
- **[事实]** 该实现自身记录了 Core ML 路径的首句截断/准确率问题，并给出作者测试集上的 WER 数字；这些只能作为发现问题的线索，不能替代 Utter 的独立评测。
- **[推断]** 代码和 Core ML 拆模方法值得参考，但 package 产品面和依赖面较大；不应仅因“有 Core ML”就优先于可复用当前 MLX 权重的方案。

### D. sherpa-onnx：成熟的非 Python 备选

来源：k2-fsa 官方 [`sherpa-onnx`](https://github.com/k2-fsa/sherpa-onnx)，Apache-2.0；[Qwen3-ASR Swift 示例](https://github.com/k2-fsa/sherpa-onnx/blob/master/swift-api-examples/qwen3-asr.swift)。

- **[事实]** 已支持 Qwen3-ASR，提供 Swift API 和 macOS XCFramework；运行时是 Swift → sherpa C API/C++ → ONNX Runtime，不需要 Python。
- **[事实]** 官方示例模型使用拆分后的 `conv_frontend.onnx`、`encoder.int8.onnx`、`decoder.int8.onnx` 和 tokenizer；示例默认 CPU provider，并提供 0.6B int8 发布模型。
- **[事实]** 这一路线不能直接加载 Utter 当前的 `model.safetensors`，需要单独下载/发布转换后的 ONNX 模型。
- **[事实]** sherpa 所说的 streaming 路径可由 VAD/分段模拟；不能据此推断 Qwen3-ASR 原生逐帧 streaming 已与 Qwen 官方 vLLM streaming 等价。
- **[推断]** 若 MLX Swift 的稳定性、并发或 Store 构建出现难以解决的问题，sherpa 是最可控的 Plan B；代价是更大的 C++/ONNX 二进制面、两套模型资产，以及在 Apple GPU 上可能不如 MLX。实际性能尚未验证。

### E. 直接 Core ML：可做，但不是最低成本路线

Apple 官方支持在 App 内加载、编译和运行 Core ML 模型，也提供[下载模型以减小 App 体积](https://developer.apple.com/documentation/coreml/reducing-the-size-of-your-core-ml-app)的产品模式。参见 [Core ML 文档](https://developer.apple.com/documentation/coreml)。

但 Qwen 官方没有发布 Qwen3-ASR 的 `.mlpackage` / `.mlmodelc`。自研转换至少要解决：

- 音频 encoder、decoder prefill 和单 token decode 的模型拆分；
- 动态音频长度、mask 和固定/有界 shape；
- decoder KV cache，通常需用 `MLState` 或显式状态张量；
- Mel/STFT、tokenizer、prompt 和长音频切分的一致性；
- bf16/fp16/int8/int4 转换后数值误差、首句截断与重复；
- ANE、GPU、CPU 的算子放置和内存峰值。

**[推断]** Core ML 是有价值的第二阶段优化，而不是第一版去 Python 的最佳路线。先用 MLX Swift建立正确性基线，再评估 Core ML 是否能在目标 Mac 上降低内存或提升能效，风险更可控。

### F. 直接 ONNX Runtime Swift / 从头重写

Microsoft 官方 ONNX Runtime 在 Apple 平台主要暴露 C/Objective-C API与二进制包；若决定走 ONNX，sherpa-onnx 已经封装了 Qwen3-ASR 的 tokenizer、模型拆分和 Swift 示例，重复封装收益不高。

从官方 Python `transformers` 实现逐层自研 MLX Swift 是技术上可行的，但现有多个开源实现已经证明并覆盖这条路径。除非依赖审计迫使 Utter vendoring 一个极小实现，否则不值得先投入。

## 推荐的 Utter 迁移方案

### 第一阶段：已完成的 PoC

已完成固定版本依赖、进程内 actor、本地模型直读、16 kHz 音频预处理、同模型 A/B 和 release/Metal 验证。主应用统一删除 `LocalASRRuntime`、`LocalASRServer`、runner script 和 Python fallback，只保留原生 Swift/MLX 路径。

### 第二阶段：产品化

- 固定 Swift package commit、模型 repo revision 和文件 manifest/SHA-256；禁止 `trust_remote_code` 或任意可执行扩展。
- 评估默认模型。建议产品默认考虑 0.6B 量化模型或 1.7B 4/8-bit，把 1.7B bf16 作为高内存设备可选项，而不是默认下载约 3.8 GB。
- 将模型生命周期串行化：同一模型单实例、可取消、内存压力时可卸载、sleep/wake 可恢复。
- 对长录音、静音、超短片段和错误音频增加确定的上限/分段策略。
- 在 Xcode archive 中验证 `default.metallib`、签名、sandbox、模型下载与离线重启。
- 完成第三方 Notices、模型 Apache-2.0 许可记录、隐私和下载说明。

## Mac App Store 合规性

Apple [App Review Guidelines 2.5.2](https://developer.apple.com/app-store/review/guidelines/)要求 App 自包含，不得下载、安装或执行会引入/改变功能的代码。改造前的 Qwen 路径会下载 Python 包和原生 `.so`/`.dylib`，去除系统来源标记、ad-hoc 签名后执行；该路径现已删除。

改成 Swift/MLX 后：

- **[事实]** Swift 模型代码、MLX native library 和 Metal shader 在构建时被编译、签名并随 App 提交；运行时只下载 SafeTensors、JSON/tokenizer 等固定模型数据。
- **[事实]** Apple 明确支持 Core ML 模型按需下载，因此“可下载的机器学习数据”本身不是禁区。
- **[推断]** 固定结构的 MLX SafeTensors 权重也是数据而不是可执行代码，通常可按同样原则设计；但 Apple 没有针对 Utter/MLX 做预先批准，最终仍以审核结果为准。

Store 版本应满足以下边界：

1. 只允许固定模型 ID、固定 HTTPS host 和固定 revision；下载后校验 manifest、大小和 SHA-256。
2. 权重和 cache 全部写入 App Sandbox container，不改 quarantine，不调用 `codesign`，不生成/加载 `.so`、`.dylib` 或 Python bytecode。
3. Qwen 转写路径不使用 `Process`、shell、venv、pip 或外部解释器。
4. 不允许模型仓库携带 arbitrary remote code；Store 版本不提供任意用户模型仓库执行能力。
5. MLX/Metal 资源在 archive 时已签名；不申请 JIT、禁用 library validation 等与需求无关的 entitlement。
6. App Review Notes 明确说明模型是按需下载的不可执行参数数据、存放位置、大小、删除方式和完全本地推理行为。

**[推断]** 去 Python 会移除当前 Qwen 路径最大的 2.5.2 风险，但不会自动保证过审；屏幕录制、麦克风、辅助功能、网络、隐私标签、付费方式等仍须按整个 App 单独审计。

## 工程量与代价

| 路线 | 首个可用 PoC | 产品化增量 | 资产复用 | 主要代价 |
|---|---:|---:|---|---|
| MLX Swift + `mlx-audio-swift` | 2–4 工程日 | 1–2 周 | 可复用当前 SafeTensors | 第三方依赖审计、内存与准确率验证 |
| 裁剪/维护自有 MLX Qwen 实现 | 1–2 周 | 再 2–4 周 | 可复用 | Utter 自己承担模型实现和上游跟进 |
| sherpa-onnx | 3–7 工程日 | 1–2 周 | 不可复用当前模型 | 新 ONNX 资产、C++ runtime、性能未知 |
| 自研 Core ML 转换与 Swift decoder | 3–6 周 | 合计 4–8+ 周 | 需转换 | 动态 shape、KV cache、数值与准确率风险 |
| 从零 MLX Swift 移植 | 4–8 周 | 合计 6–10+ 周 | 可复用 | 重复已有社区实现，长期维护成本最高 |

以上是假设一名熟悉 Swift/MLX 的工程师、当前 UI 和模型下载框架不重做。若要同一期交付真正 streaming、word timestamp/forced alignment、全模型量化矩阵或 Intel Mac，则不在此估算内。

运行时产品代价同样重要：

- 1.7B bf16 当前磁盘约 3.8 GB，统一内存峰值还需真机测；在 8 GB/16 GB Mac 上可能与应用和系统争抢内存。
- 量化模型显著减小下载和内存，但必须测中英文 CER/WER，不能只看文件体积。
- 首次模型加载会有可感知延迟；换成进程内 Swift 后省掉 venv/pip/子进程，但不会消除权重读取和 Metal 初始化。
- 移除 Python 后安装复杂度和审核风险下降，但 Swift package、MLX、模型 conversion 的版本锁定责任转移到 Utter。

## PoC 验收标准

PoC 不应以“能输出一段文字”为完成，至少满足：

### 正确性

- 固定同一模型 revision、tokenizer 和解码参数，对当前 Python `qwen3-asr-mlx==0.1.1` 与 Swift 实现做逐条 A/B。
- 语料至少 100–300 条，覆盖普通话、英语、粤语、日语/韩语（若产品宣称支持）、中英混说、噪声、远场、专有名词、1 秒以下、纯静音和 5–20 分钟长音频。
- 用中文 CER、英文 WER 和语言识别准确率衡量；建议门槛：相对当前 Python 基线的 CER/WER 绝对退化不超过 0.5 个百分点，语言识别一致率 ≥ 99%。若业务可接受不同阈值，应在开跑前固定。
- 无系统性首句丢失、结尾截断、幻觉、重复 token、标点/空格破坏。

### 性能与稳定性

- 分别测冷启动、热启动、首 token、总耗时和 real-time factor；热转写不慢于当前 Python MLX 基线 10% 以上。
- 在 8 GB、16 GB、24 GB Apple Silicon 至少各一台或等效矩阵测峰值 resident memory 和 memory pressure。0.6B 量化目标可先设峰值 < 2 GB，1.7B 量化目标 < 4 GB；以实测决定是否能承诺，而非当作已知事实。
- 连续转写 100 次、30 分钟空闲、睡眠唤醒、取消、切换/删除/重下模型后无崩溃；取消请求 500 ms 内返回到上层，模型可明确卸载。
- 模型下载完成后断网，转写仍完全可用。

### 构建与 Store 边界

- Archive 使用 `xcodebuild`，检查 `.app` 含所需 `default.metallib`，并通过 `codesign --verify --deep --strict`。
- Qwen Store 路径中没有 venv、pip、`.py` runner、运行时下载的动态库、`Process` 或 ad-hoc re-sign。
- 下载模型按 revision 固定且逐文件 hash 校验，篡改/截断时拒绝加载。
- App Sandbox 中完成下载、加载、转写、删除和重新下载；不依赖容器外可写路径。

## 决策建议

MLX Swift PoC、同模型 A/B 与去 Python 产品切换已经完成，当前应继续沿 `mlx-audio-swift` 路径产品化。下一阶段重点是扩大到 100–300 条核心语料、长音频和压力矩阵，并补齐模型 revision/hash、许可清单与沙盒内模型生命周期验证；是否改默认模型，再由 0.6B/1.7B 量化对测决定。

只有以下情况才切换到 sherpa-onnx：MLX Swift package 无法在 Store archive 中稳定签名/打包，或在目标硬件上的内存与稳定性无法达标。Core ML 应作为后续能效优化项目，不阻塞第一版去 Python。

## 一手来源索引

- Qwen 官方：[Qwen3-ASR repo](https://github.com/QwenLM/Qwen3-ASR) · [1.7B model card](https://huggingface.co/Qwen/Qwen3-ASR-1.7B) · [paper](https://arxiv.org/abs/2601.21337) · [processor](https://github.com/QwenLM/Qwen3-ASR/blob/main/qwen_asr/core/transformers_backend/processing_qwen3_asr.py) · [model](https://github.com/QwenLM/Qwen3-ASR/blob/main/qwen_asr/core/transformers_backend/modeling_qwen3_asr.py)
- Qwen 官方的模型区分：[Qwen2-Audio repo](https://github.com/QwenLM/Qwen2-Audio) · [Qwen2-Audio-7B-Instruct model card](https://huggingface.co/Qwen/Qwen2-Audio-7B-Instruct)
- Apple/MLX：[mlx-swift](https://github.com/ml-explore/mlx-swift) · [mlx-swift-lm](https://github.com/ml-explore/mlx-swift-lm) · [SwiftPM Metal resource issue](https://github.com/ml-explore/mlx-swift/issues/36)
- Hugging Face：[swift-transformers](https://github.com/huggingface/swift-transformers)
- Apple Store/Core ML：[App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/) · [Core ML](https://developer.apple.com/documentation/coreml) · [Reducing the size of your Core ML app](https://developer.apple.com/documentation/coreml/reducing-the-size-of-your-core-ml-app)
- 可复用实现的源码：[mlx-audio-swift Qwen3-ASR](https://github.com/Blaizzy/mlx-audio-swift/tree/main/Sources/MLXAudioSTT/Models/Qwen3ASR) · [ontypehq/mlx-swift-asr](https://github.com/ontypehq/mlx-swift-asr) · [sherpa-onnx Qwen3-ASR Swift example](https://github.com/k2-fsa/sherpa-onnx/blob/master/swift-api-examples/qwen3-asr.swift) · [ivan-digital/qwen3-asr-swift](https://github.com/ivan-digital/qwen3-asr-swift)
