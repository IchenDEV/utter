# Spec: Edge0 8B 下载与模型目录接入

**Status:** approved
**Approved-by:** 用户（本会话选择 A：Edge0 8B 下载/目录接入，暂不推理）
**Approved-date:** 2026-11-26
**Upstream:** [Intent](intent.md)

## Decision

只接入 **Edge0 8B-A1B-preview** 的下载、目录、完整性、删除和 UI 状态，不接入推理。模型走 ModelScope，使用新的 `ModelRepositoryHost.modelScope` 和 `ModelRuntime.edge0` 元数据。

被拒绝的方案：

| 方案 | 结论 | 原因 |
|---|---|---|
| 用 MLX 加载 Edge0 8B | 拒绝 | Edge0 8B 是 Bailing hybrid MoE，`mlx-swift-lm` 不支持；`edge0-infer` 的 8B 支持尚未发布 |
| 把 Edge0 放进 `MLXModelArtifacts.text` | 拒绝 | 会被 MLX text provider 注册和加载，形成不可用路径 |
| 先接 Edge0 35B | 拒绝/延后 | 原始权重约 19.5 GB，转换约 20 GB；当前磁盘和引擎条件不满足 |
| 只加一个不可下载的说明 | 拒绝 | 不满足“下载支持”的目标 |
| 引入 Python/转换器 | 拒绝 | 违反现有打包和签名边界；下载阶段只保存原始资产 |

## Data model

- `CatalogModelFamily.edge0`（显示名 Edge0）。
- `ModelRuntime`：`.mlx`（默认）、`.edge0`。
- `ModelRepositoryHost`：`.huggingFace`（默认）、`.modelScope`。
- `ModelArtifact` 增加 `runtime`、`repositoryHost`；默认值保持现有模型不变。
- `CatalogModelEntry` 增加 `runtime`、`repositoryHost`，从 artifact 映射。
- `Edge0Model` 固定：
  - id `Edge0/Edge0-8B-A1B-preview`
  - revision `master`（ModelScope 当前可解析的 revision；尚未 pin commit）
  - required files：`config.json`、`model.safetensors`、`lora_edge0_8b.safetensors`、`prerouter_edge0_8b.safetensors`、`tokenizer.json`、`tokenizer_config.json`、`special_tokens_map.json`、`chat_template.jinja`、`generation_config.json`
  - 估计 4,576,178,437 字节
  - 许可证链接到 Edge0 Community Model License 1.0。

## Download

`ModelCatalog.performLLMDownload` 根据 artifact 的 `repositoryHost` 分支：

- `.huggingFace`：保持现有 `TextModelDownloadOperations.download`。
- `.modelScope`：调用 `downloadModelScope(id, requiredFiles, revision, staging, progress)`。

ModelScope 下载器：

1. `GET https://www.modelscope.cn/api/v1/models/<id>/repo/files?Revision=<rev>&Root=` 获取文件列表；缺少 required 文件时抛出 `missingFiles`。
2. 文件 URL 为 `/repo?Revision=<rev>&FilePath=<path>`；路径用 `URLComponents.queryItems` 编码。
3. 每个文件通过自定义 `URLSessionDataDelegate` 流式写入目标文件；按每 0.1% 或文件块报告 `Progress`，避免每个 chunk 都投递 MainActor。
4. 完成后校验 HTTP 状态和文件字节数与列表一致；不一致抛 `sizeMismatch`。
5. 已存在且大小相等的文件跳过（用于重试）；部分文件重新下载；取消沿用 staging 清理语义。
6. 完整性：`ModelAssets.filesAreComplete` 要求全部 required 文件非空；不使用 MLX 的 `llmRepoIsComplete` 单文件判断。
7. 下载后仍走现有 `prepareGenerationCommitOffMainActor` 和 `publish`；发布后调用 `validateRequiredFiles`，不调用 MLX `validate`。

进度看门狗继续使用 `DownloadProgressSignal`；每次文件进度和总 fraction 增长都会刷新。

## UI

- 文本整理的 family picker 增加 Edge0 tab。
- 模型行显示 Edge0 8B-A1B、约 4.6 GB、ModelScope、许可证链接和“仅下载”。
- `runtime == .edge0` 的模型：
  - 不显示 Use；
  - 不显示 benchmark；
  - `isActive` 永远为 false；
  - 下载完成后显示“仅下载”，仍可删除；
  - `select` 入口直接拒绝。
- 选择 Edge0 tab 只切换列表，不改变 `speechEngine`、`localLLMBackend`、`llmModel` 或当前加载的文本模型。
- 提示文案中英文都包含“下载”和“引擎尚未内置”。

## Failure modes

- ModelScope 列表不可达/格式错误：错误状态，不创建空的“已下载”。
- required 文件缺失、HTTP 非 2xx、大小不符、取消：明确错误或暂停状态；不静默回退到 MLX/Qwen。
- 磁盘不足：沿用现有下载错误；下载前不做额外静默删除。
- 用户手动把 `llmModel` 设为 Edge0：UI 不可达；本阶段不实现迁移，保留为残余风险。
- 推理尝试：不会发生，因为 Edge0 不在 MLX provider 的 artifacts 中，且 UI 禁止选择。

## Licensing

- 框架代码 Apache-2.0；GGML/Strata 等第三方组件保留各自许可证。
- Edge0 模型权重适用 Edge0 Community Model License 1.0；UI 提供链接。Utter 本阶段只下载、不推理、不重新分发权重。
- 商业使用/独立 coding/office assistant 等限制需要所有者确认；本变更不提供法律结论。

## Test strategy

| 标准 | 证据 |
|---|---|
| 目录/元数据/完整性 | `ConfigurationTests`：family/runtime/host/required files、`decodeFileList`、`filesAreComplete` |
| 下载参数和 URL | `Edge0DownloadTests`：ModelScope URL 编码、小文件 catalog 下载、full 4.6 GB 下载 |
| 状态/删除 | 小文件和 full 测试：下载 → 重启 → 删除 → notDownloaded |
| UI | `Edge0ModelWindowRenderTests` 中英文/light-dark/760-560 渲染；代码断言 runtime 禁止 Use/benchmark |
| 标准门 | `sdlc-checks`、`ci-basic-checks`、`swift test`、release build |
