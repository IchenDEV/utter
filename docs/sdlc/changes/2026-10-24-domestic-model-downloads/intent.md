# Intent: 添加国内模型下载源

**Status:** approved
**Approved-by:** 用户（本会话明确回复“批准”）
**Approved-date:** 2026-10-24
**Upstream:** 用户请求：添加国内模型下载站支持
**Risk:** medium

## Problem

Utter 的本地模型下载目前依赖 Hugging Face 官网，没有面向国内网络的下载源选项。
用户遇到官网不可达或传输中断时，只能重试同一个来源，或另行下载后导入。

当前下载分布在几个入口：

- Whisper 权重通过 `WhisperKit.download` 下载，tokenizer 通过 `HubApi` 下载。
- 常规 ASR 模型通过 `HubApi.snapshot` 下载。
- Confucius 文件通过 `ConfuciusModelDownloader` 的官网地址下载，并验证固定版本和 SHA-256。
- MLX 文本模型通过 `MLXModelDownloads` 和 `MLXModelLoading` 下载。

仅修改其中一个入口，会使选了国内源的用户仍在其他下载步骤访问官网。

## Outcome

用户能在 Utter 中选择国内下载源，在官网访问受限时完成本地模型准备。
用户能看到当前选择的来源，重启后继续使用该选择，也能切回官网。

## Scope

首版建议提供 Hugging Face 和 HF-Mirror 两个选项，保留 Hugging Face 为默认值。
HF-Mirror 的服务说明提供了兼容 Hugging Face 的镜像用法，适合先验证现有模型目录的覆盖情况。
来源：[HF-Mirror 使用说明](https://hf-mirror.com/)，查阅日期为 2026-10-24。

覆盖设置中的模型管理、首次引导、Whisper、ASR、MLX 文本模型、自定义 Hugging Face 模型 ID，以及它们需要的 tokenizer 和配套文件。

首版不包含 ModelScope 的独立仓库映射、自定义站点 URL、地区自动识别或自动跨站切换。
这些能力需要额外的产品选择和兼容性验证。

## Constraints

- 复用现有 Swift 依赖、模型目录和下载恢复机制。
- 选择国内源是用户的明确操作。下载失败时保留可理解的错误和重试入口。
- 新增来源仅用于公开模型资源，不把已有 Hugging Face 凭证自动发送给镜像站。
- 保持模型 ID、缓存位置、已下载模型识别、离线加载和本地导入行为兼容。
- 保留固定版本、文件完整性检查，以及 Confucius 的文件尺寸、Range 响应和 SHA-256 校验。
- 一次下载使用同一来源。用户在下载期间改选来源，只影响后续新任务。
- 新增用户文案同时提供中文和英文，并通过 `L("key")` 使用。
- 仅完成意图阶段。后续设计、计划和实现分别等待明确批准。

## Acceptance criteria

- 设置中的模型管理和首次引导均能选择官网或 HF-Mirror，选择在重启后保留。
- 没有保存过来源的用户仍使用官网，未知或失效的设置值不会导致应用无法启动。
- 新建 Whisper、常规 ASR、Confucius 和 MLX 下载任务时，仓库查询和初始文件请求均使用选中的来源。
- Whisper tokenizer、ASR 依赖仓库和 MLX 配套文件遵循同一选择，不遗漏辅助下载。
- 任务开始后切换来源不会混用该任务的初始请求地址。源站返回的 CDN 重定向另行记录和验证。
- 切换来源后，已完成模型仍可识别和离线加载，不要求重新下载。
- 国内源不可达、缺失模型或返回不完整文件时，应用报告失败，不发布不完整模型，也不静默切换来源。
- 下载取消、失败重试、进度显示和代际隔离通过现有回归检查。固定版本和校验约束继续生效。
- 自动化验证覆盖设置持久化、各下载入口的来源传递、任务内来源固定和失败路径。
- 实际完成国内源的代表性 Whisper、ASR 和 MLX 模型下载及加载检查，并记录模型、版本、来源与结果。未实测的类型明确列为未验证。
- 对新增选择控件进行真实 macOS 窗口的中英文、浅色、深色、窄窗口和键盘操作检查。
- 运行 `bash scripts/sdlc-checks.sh`、`bash scripts/ci-basic-checks.sh`、`swift test` 和符合本次运行时变更范围的 release-style 构建，记录结果与阻塞。

## Open questions

意图批准项：首版按“官网默认，HF-Mirror 可选，设置与首次引导可选择”的范围推进。
若需要首版直接接入 ModelScope，应在批准本阶段时调整范围。

当前仅检查了源代码和 HF-Mirror 的公开说明，尚未验证各模型在镜像站的实际文件覆盖、CDN 路径或国内网络速度。
