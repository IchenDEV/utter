# Spec: iOS 模型管理

**Status:** approved
**Approved-by:** 用户（本对话：“全部批准，继续执行。”）
**Approved-date:** 2026-10-07
**Upstream:** [intent.md](intent.md)（已批准）
**说明：** 与实现同轮完成，是对已实现代码的记录；2026-10-07 经用户批准。

## 1. 数据

`MobileModel`（`UtterMobile/MobileModels.swift`）由 `ModelCatalogSnapshot` 投影而来（`MobileModelCatalog.swift`）：

| 字段 | 来源 |
| --- | --- |
| `kind` | `.speech`（Whisper、MLX 语音）、`.polish`（MLX 文本） |
| `tier` | 桌面的 recommended / standard / legacy；带“推荐”提示的 Whisper 档归入 recommended |
| `fit` | `.ok` / `.marginal(原因)` / `.blocked(原因)`；文本模型用目录自带兼容性，其余用 `DeviceCapability.check` |
| `state` | `notDownloaded / downloading / preparing / downloaded / paused / failed(原因)`；“下载已暂停”从错误中单独识别 |
| `bytes` | 已安装大小，否则为预估下载大小 |

`DeviceCapability` 在 iOS 上只把 70% 物理内存当作可用（`usableMemoryFraction`），macOS 不变。

## 2. 选用

- `selectedModel`（语音，`mobile.model`）：`apple` 或已下载模型 id。
- `polishModel`（整形，`mobile.polish.model`）：`system` 或已下载文本模型 id。
- `selectModel(_:)` 只更新这两个值，不调用 `disable()`；`MobileWorkflowFactory.modelID` 在每次 `begin()` 读取。
- 删除所选模型：语音回退 `apple`，整形回退 `system`，并卸载本地整形模型。
- 系统整形不可用时，第一个下载完成的文本模型自动成为整形模型。

## 3. 引擎路由（`MobileWorkflow`）

`apple` → Apple SpeechAnalyzer；Qwen3-ASR/Confucius → `QwenNativeASREngine`；FireRed/Mega → `MLXSTTEngine`；其余 → `WhisperEngine`。

## 4. 本地整形

`LocalPolisher`（`@MainActor`，包装 `MLXGenerationService`）：开始听写时若所选整形模型已下载则预热；整形有 6 秒超时；空闲 60 秒卸载；输出经 `MobilePolisher.accept` 与同一 `TranscriptFidelityGuard`，不通过或失败则保留原文。

## 5. 界面（`iOS/App/MobileModelsView.swift`、`MobileModelRow.swift`）

- 分区：语音识别（系统识别 + Whisper）、更多识别模型（MLX，附“实验”说明）、文字整形（系统语言模型 + 文本模型，旧型号折叠）、占用空间页脚。
- 行：已下载 → 整行为按钮（`model.use.<id>`，`isSelected` 特征，右侧对勾）；未下载 → 云图标按钮（`model.download.<id>`）；下载中 → 进度环（`model.cancel.<id>`，读出百分比）；失败/暂停 → 原因文字（`model.error.<id>` 仅失败）与重试/继续；本机装不下 → 警示图标，无下载按钮。
- 删除：左滑或长按菜单 → 确认框（`model.delete.<id>`、`model.delete.confirm`）。
- 排序：推荐在前，装不下的在后。
- 设置页整形开关下增加“整形模型”一行。

## 6. 本地化

新增键同时写入 en 与 zh-Hans。`Loc.use(...)` 在安装时按系统语言设置，使目录名称与简介不再固定为中文。

## 7. 模拟器

MLX 在 iOS 模拟器上无法启动：加载模型时 `mlx/backend/metal/device.cpp` 读取 Metal 架构名得到空指针，libc++ 加固断言使 App 直接退出。因此在模拟器上 MLX 语音与文本模型一律标为“本机装不下”（`ios.models.simulator_unsupported`），不可选用；所选整形模型还要求 `fit` 不是 `blocked` 才算可用，避免遗留的偏好值触发加载。Whisper 与系统识别不受影响。

调试构建带 `--polish-probe <模型 id>`（`iOS/App/ModelProbe.swift`）：在真机上下载、选用并真实运行三条整形样例，进度与结果写入 `Documents/polish-probe.json`。

## 8. 已知限制

- MLX 在模拟器与后台（画中画待命）下是否可靠未验证；整形失败保留原文。
- iPad 与 iPhone 共用同一列表，没有单独的 iPad 布局。
