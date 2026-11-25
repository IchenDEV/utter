# Plan: 支持 Audio8-ASR-0.1B 本地语音识别模型

**Status:** approved
**Approved-by:** 用户（本会话明确回复“批准”）
**Approved-date:** 2026-11-25
**Upstream:** [Spec](spec.md)

## Work items

- [x] 1. 扩展模型资产元数据和下载契约：为 `ModelArtifact` 增加可选 revision pin 与 selective-download 语义；保持现有资产默认行为不变。
- [x] 2. 注册 Audio8 资产：`Edge0/Audio8-ASR-0.1B`、revision `8487da63d581fa4fc9b5c60444cb57c3a523d7aa`、12 个 required runtime files、663,928,408 字节估计和中英文非商业许可证 hint。
- [x] 3. 修改 ASR 下载路径：按 artifact revision 调用 Hub snapshot；selective artifact 只下载 required files；写入并校验内部 revision marker；确保演示视频、Python 源码和示例文件不会下载。
- [x] 4. 为下载契约补单元测试：matching 文件列表、revision pin 传递、marker 写入/不匹配、缺文件/空文件、取消后状态和 delete 后状态。
- [x] 5. 新增 `SpeechEngineType.audio8`、labels/picker 文案、`asrModelID`、`SpeechSelection` 映射、`SpeechServices.audio8`、provider registration 和 builtin composition mapping。
- [x] 6. 修复 ASR 模型行选择硬编码到 `.qwen3` 的同类缺陷：按模型归属切换到 `.qwen3`、`.firered`、`.megaASR` 或 `.audio8`；只让 Qwen 变体写入 `qwenASRModel`。
- [x] 7. 在模型管理 UI 中为 Audio8 展示上游 LICENSE 链接和“仅限非商业用途”说明；补齐中英文 localization keys。
- [x] 8. 实现 Audio8 config/schema layer：解析根 config 和 audio config，验证 `arkasr`、audio token id、merge factor、decoder/encoder 维度和 tied embeddings；坏配置抛出明确错误。
- [x] 9. 实现 Audio8 权重加载和 sanitization：读取 `model.safetensors`，验证关键权重存在，转换 conv weight layout，正确处理 tied embedding/无独立 lm-head。
- [x] 10. 实现 MLX adapter 组件：`audio_mlp_tower` 4 个 residual blocks、`audio_projector`、adaptive average pooling 和连续 `<|audio|>` embedding replacement。
- [x] 11. 实现 Qwen2-style Audio8 decoder：bias-enabled q/k/v projections、RoPE、RMSNorm、SwiGLU、tied output embedding、`inputsEmbeds` 输入和 KV cache。
- [x] 12. 实现 Audio8 推理管线：16 kHz mono conversion、30 秒硬限制、mel frontend、audio-token count、精确 prompt、audio encoder + adapter、greedy max-128 generation 和 EOS trimming。
- [x] 13. 实现 decode-time hotword trie：tokenize recognition phrases（`addSpecialTokens=false`），first boost 6.0、continuation boost 8.0、top-50 gate，并在每个 token step 检查 cancellation。
- [x] 14. 实现 `Audio8NativeASREngine` 生命周期：懒加载、prepare、shutdown/unload、`ModelResourceAccess`、取消传播、资产缺失/损坏错误、无音频错误和只记录非内容指标的日志。
- [x] 15. 接入 provider factory/cache，确保切换模型或引擎时释放旧 runtime，且不加入启动 preload。
- [x] 16. 添加 runtime unit tests：config validation、weight key/layout、token count formula、prompt token sequence、adaptive pooling参考值、embedding replacement、hotword trie/top-k/boost 状态。
- [x] 17. 添加 env-gated integration tests：本地 checkpoint + `en-sample.m4a`/`zh-sample.m4a` 语义断言、rare-term hotword 对照、长音频错误、损坏资产错误、取消行为和热加载耗时/内存记录。
- [ ] 18. 用真实 Hugging Face 下载验证 catalog 全流程：下载、重启后离线识别、删除、状态恢复；记录实际下载文件清单，确认无视频/Python 文件。阻塞：本机当前无法访问 `huggingface.co` API；已手工完整下载 12 个 required 文件并完成推理，catalog 下载链路待网络恢复后重跑。
- [x] 19. 做真实窗口 UI QA：模型管理中英文、light/dark、常规和窄宽度下许可证文字/链接、下载/错误/删除状态；保存截图证据。生产视图 fixture 渲染完成（760/560 pt、light/dark、中英文）；打包 app 内的真实点击交互未执行，见 verification 残余风险。
- [x] 20. 更新 `verification.md`，逐项映射 intent acceptance criteria、命令输出、集成日志、性能内存数据、UI 证据和残余风险。

## Verification plan

- [x] `bash scripts/sdlc-checks.sh`
- [x] `bash scripts/ci-basic-checks.sh`
- [x] `swift test`
- [x] 定向测试至少包括：`ConfigurationTests`、catalog artifact/download tests、speech selection tests、Audio8 runtime unit tests、现有 Qwen/FireRed/Mega ASR regression tests
- [x] env-gated Audio8 integration：中文和英文 fixture 均产生语义正确、非空转写；日志证明使用 Audio8 路径
- [x] 热加载 5 秒音频转写不超过 3 秒、峰值内存不超过 1.5 GB；记录机器型号和测量方法
- [x] 长音频、损坏资产、取消、删除和重启离线路径逐项验证，不发生静默 fallback
- [ ] 真实下载文件清单不包含 `assets/`、`examples/`、`hotword/` 或上游 `.py` 文件。手工下载确认清单正确；catalog live 下载被 HF API 不可达阻塞。
- [x] release-style `bash scripts/build-app.sh` 通过，确认未新增 ONNX Runtime、Python runtime 或模型权重进 app bundle
- [x] 模型管理真实窗口 light/dark 与窄宽度截图通过人工检查

## Human gates

- spec 已获用户批准。
- 本 plan 需要用户明确批准后才能开始实现。
- 实现完成后，verification artifact 需要用户明确批准。
- PR/merge 按仓库现有门控执行；发布、签名、notarization 或任何生产动作不在本变更授权范围内。
