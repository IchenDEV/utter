# Intent: Edge0 8B 下载与模型目录接入

**Status:** approved
**Approved-by:** 用户（本会话明确选择 A：Edge0 8B 下载/目录接入，暂不推理）
**Approved-date:** 2026-11-26
**Risk:** medium。新增用户可见的文本模型条目、下载源和模型状态；不新增推理 runtime，不改变默认文本模型。

## Problem

Edge0 8B-A1B-preview 不在 Utter 的文本模型目录中。用户无法在 app 内查看、下载、管理这套权重；`huggingface.co` 当前也不可达。Edge0 的 native engine（`edge0-infer`）尚未支持 8B，因此本阶段不能提供推理。

## Outcome

用户在文本整理的 Edge0 分类中看到 Edge0 8B-A1B，能通过 ModelScope 下载约 4.6 GB 的 required 文件，看到进度、取消、完成和删除状态；UI 明确标注“仅下载，Edge0 推理引擎尚未内置”，不会把它设为当前文本模型，也不会尝试按 MLX 模型加载。

## Scope

In scope:

- `CatalogModelFamily.edge0`、`ModelRuntime.edge0`、`ModelRepositoryHost.modelScope` 元数据。
- Edge0 8B-A1B 的 catalog 条目、required 文件清单、体积估计、许可证链接和“仅下载”提示。
- 一个模型专用的 ModelScope 文件列表/下载路径；复用现有 staging、generation commit、进度、取消和删除语义。
- Edge0 条目的完整性检查使用 required 文件，而不是 MLX 的 `model.safetensors` 单文件检查；下载后不使用 MLX validate。
- 模型管理中禁止选择、benchmark 或把 Edge0 标记为 Active；下载完成后仍可删除。
- 单元测试、真实 ModelScope 小文件测试和完整 4.6 GB 下载测试。

Non-goals:

- 不接入 Edge0 推理；不引入 `edge0-infer`、GGML、C++ 或 Python runtime。
- 不支持 Edge0 35B / 120B / 145B。
- 不把权重转换或打包进 app；不评估模型效果。
- 不改变默认文本模型、Qwen 路径或现有 ASR/Whisper 下载。
- 不把 Edge0 设为可选/默认文本 provider。

## Constraints

- 不新增第三方二进制依赖；下载器只使用 Foundation URLSession。
- 模型权重不进入 app bundle；下载目录只在用户显式操作时写入用户模型存储。
- UI 必须显示 Edge0 Community Model License 1.0 链接和“仅下载”限制。
- 复用现有下载的取消和删除语义；不引入静默 fallback。
- 标准检查：`bash scripts/sdlc-checks.sh`、`bash scripts/ci-basic-checks.sh`、`swift test`、release-style `bash scripts/build-app.sh --app-only --sign=-`。

## Acceptance criteria

1. 文本整理的 Edge0 分类中显示 Edge0 8B-A1B、约 4.6 GB、ModelScope 来源、许可证链接和“仅下载/引擎未内置”提示。
2. 点击下载后从 ModelScope 获取 required 文件，显示进度；取消后回到可恢复/错误状态；完成后状态为已下载。
3. 下载完成后重启 app 仍显示已下载；删除后状态回到未下载，文件被移除。
4. Edge0 条目不能被选择为当前文本模型，不能运行 benchmark，不会被标记 Active；不会调用 MLX validate 或加载其权重。
5. 完整性检查要求全部 required 文件非空；缺文件、HTTP 错误、大小不符和取消失败时给出明确错误，不静默成功。
6. 标准检查、完整测试、UI 渲染和 release build 记录在 `verification.md`。
