# Verification: iOS 模型管理

**Status:** approved
**Approved-by:** 用户（本对话：“全部批准，继续执行。”）
**Approved-date:** 2026-10-07
**Upstream:** [spec.md](spec.md)（已批准）

**结论先说：模拟器上的列表、下载取消重试、选用/重启/删除有证据；本地 MLX 整形模型与新增 MLX 语音引擎路由没有跑过，真机一条都没有。** 验收标准 1–3 有模拟器证据；4 只有代码与截图（模拟器内存是 Mac 的，没有触发“装不下”）；5 如实如下。

## 环境

iPhone Air 与 iPad mini（A17 Pro）模拟器，iOS 27.0，英文界面。模型下载走真实网络（Whisper tiny）。

## 结果

| 检查 | 结果 |
| --- | --- |
| `testModelCatalogIncludesPolishModels`（iPhone Air、iPad mini） | 通过：三个分区、`Qwen3.5-0.8B` 下载按钮、整形模型行、设置页 `settings.polish.model` |
| `testModelDownloadCancelRetry` | 通过：下载、进度环取消、重试、再取消；取消后显示“已暂停”而不是红色错误 |
| `testModelDownloadSelectRestartDelete` | 通过：下载完成不自动选用；点击行选用；重启后仍选中；左滑删除并确认 |
| `testNativeProductRotation`、`testProductNavigationAndPreferences` | 通过 |
| `swift test` | 通过 |
| `scripts/ci-basic-checks.sh`、`scripts/sdlc-checks.sh`、`scripts/check-ios-bridge.sh`、`git diff --check` | 见交付说明（本文件写入后重跑） |
| 截图目检 | 分组列表、云下载图标、进度环、暂停文字、iPad 宽布局均符合预期；MLX 行不再重复显示大小 |

## 没有验证的

- “下载后无法选用”**没有复现**；修复是设计性的（选用不再走关闭语音输入的路径，整行可点）。若用户在真机上仍遇到，需要真机日志。
- 本地 MLX 整形：没有下载过任何文本模型，没有跑过一次整形；模拟器与后台（画中画）下 MLX 是否可用未知；质量与延迟未知。
- FireRed/Mega 经 `MLXSTTEngine` 的听写没有跑过。
- 内存“装不下”的判断依赖真机内存；模拟器上所有模型都显示可下载。
- `LocalPolisher` 是 iOS 专用代码，SwiftPM 的 macOS 单测覆盖不到，没有新增单测。
