# Intent: Utter iOS 语音输入

**Status:** approved
**Approved-by:** 用户（本对话：“使用这个重构分支，继续开发”）
**Approved-date:** 2026-10-04
**Upstream:** 用户要求为 Utter 支持 iOS；2026-10-04 确认本地优先、云端可选，测试设备为 iPhone Air / iOS 27。

用户随后要求恢复开发，并把 iOS 分支叠在隔壁重构分支之上。用户给出的父 PR 编号 #462 在当前仓库无法解析；用户随后明确选择 `IchenDEV/utter` 的 `t3code/modularize-plugin-architecture` 并要求继续开发。当前 iOS 工作分支 `t3code/ios-voice-input-research` 已接到父分支提交 `6044cef29ee9edff87d9aa843d1893a040e7dd1d`，保留原有 iOS 文档；未改写父分支或发布 PR。

## Problem

Utter 当前只有 macOS 可执行程序。用户希望在 iPhone 的其他 App 中使用 Utter 语音输入，并获得现代 iOS 语音键盘的体验：启用后连续使用时不反复跳转，闲时麦克风关闭，没有需要手动藏起的悬浮窗，并能与视频画中画共存。

当前桌面版通过全局快捷键、AppKit、辅助功能和剪贴板完成输入；这些能力不能直接搬到 iOS。键盘扩展本身不能使用麦克风，即使开启“允许完全访问”也不能改变这一限制。必须验证主 App 的录音与键盘之间如何配合，尤其是停止录音后能否再次从键盘发起录音。

已有豆包、微信输入法的公开体验资料，但未找到能核对其最新完整实现的源码。“不可见 PiP”只能作为待验证线索，不能据此承诺保活、自动锁屏和其他视频 PiP 均已解决。

## Outcome

提供能独立于 Mac 工作的 Utter iPhone App 和语音键盘。用户在支持第三方键盘的输入框中开始说话、查看状态、结束录音并插入文字；默认识别与基础文本处理在设备上完成，云端服务由用户主动开启。

第一版的核心体验目标是：完成必要的首次启用后，在有效会话内可以从键盘再次开始录音，不需要每次切到主 App；闲时不采集声音；启用和使用语音均不挤掉已有的视频 PiP。这些目标必须先取得 iPhone Air / iOS 27 的实测证据。未满足时应回到本阶段调整范围，不把每次跳转的替代流程当作已完成这些目标。

## Scope

用户已确认本意图并要求基于指定重构分支继续开发。接下来完成技术方案，方案和实施计划仍按仓库流程分别提交审批；本次确认不代表尚未完成的方案、计划或验收已获审批。

第一版包括：

- iPhone 主 App：首次设置、按需权限请求、本地识别能力与模型准备状态、语音会话启用和明确的停用入口。
- 系统第三方语音键盘：录音、结束、取消、处理状态，以及删除、空格、换行和切换键盘所需的基本操作。
- 普通话和英语语音输入，并用中英混说样例验证实际能力；语言或本地模型不可用时提供明确状态。
- 本地识别、基础文本处理和个人词典纠错。复用桌面版中适合移动端的规则与数据结构，避免复制整套桌面协调器。
- 可选云端能力：语音识别或文本整理分别显式开启，清楚说明发送的是音频还是文字。未开启时不进行相应上传。
- 键盘与主 App 的会话管理、结果传递、取消、超时和失效恢复；后续技术方案审查具体通信方式及共享数据边界。
- 真机验证免跳转、停止录音后再次唤起、PiP 共存、闲时自动锁屏和资源使用。

第一版不包含完整拼音输入法、Mac 中转、账号或跨设备同步、桌面辅助功能与屏幕 OCR 的移植、全局快捷键，以及 App Store 发布。手机端大型本地 LLM 的整理效果、内存与延迟单独评估，不作为基础语音输入可用的前提；云端整理关闭时仍能完成本地输入。

## Constraints

- **风险等级：High。** 涉及麦克风权限、录音生命周期、键盘扩展、跨进程共享数据及可选外部服务；方案与实施计划须分别审批，交付须有独立验证和明确回滚路径。
- **首台验收设备：iPhone Air / iOS 27。** 最低支持版本在技术方案阶段确定；不以模拟器运行替代此设备的录音、后台和 PiP 验证。
- **本地优先。** 离线可用须在必要的本地模型准备完成后实测。下载模型与上传录音是不同操作；缺少本地能力、识别失败或模型不足时不得悄悄切换到云端。
- **按需录音。** 不以持续录音作为闲时保活手段。结束、取消、停用和中断均须释放音频输入；活跃录音应有明确的状态反馈。
- **后台能力以实测为准。** Live Activity 的显示不等于主 App 仍可执行。不能承诺强制退出、重启或系统终止后永久免跳转；恢复需由用户明确发起。
- **输入边界。** 只在系统允许第三方键盘的字段工作。安全输入框、宿主禁用第三方键盘等系统限制应明确说明。
- **数据边界。** 不迁移桌面已有凭据到手机，不在日志中记录录音、转写正文或密钥；后续方案说明共享容器、凭据存储、缓存删除和结果保留策略。
- **独立运行。** 录音和本地识别不依赖 Mac 在线；键盘扩展不加载桌面版的整套推理运行时。
- **兼容性。** 保留现有 macOS 包、标识、设置和数据格式。iOS 项目组织与共享模块的改动必须通过桌面现有检查。
- **基于重构开发。** 用户确认父分支后，iOS 工作分支叠在该重构分支之上。复用重构提取的模块与服务契约；平台相关录音、键盘输入和权限需要移动端实现。不得复制一套旧桌面协调器，也不把上游尚未完成的重构视为已验收。父分支后续变化与 iOS 自身差异须分别记录。
- **发布边界。** 实验性隐藏 PiP 的设备表现与 App Store 可接受性是两项独立待验证事项；本次不授权发布或绕过平台审核。

## Acceptance criteria

以下均为实施后的验收要求，不代表本阶段已经通过：

1. 在 iPhone Air / iOS 27 安装主 App 和键盘，完成首次设置后，在至少三个允许第三方键盘的宿主中完成普通话、英语和中英混说的“开始 → 结束 → 插入”流程。每次结果只插入一次。
2. 必要模型准备完成、云端能力关闭后，在飞行模式下完成本地语音输入和词典纠错；没有音频或转写上传。无法支持某语言时明确报出本地能力不足。
3. 首次启用后，在有效会话内连续完成十次键盘发起的录音，其中包括至少两次闲置五分钟后的重启录音；过程中不切换到主 App。记录每次触发、首个结果与完成时间。
4. 在未录音和结束录音后的闲置阶段，系统麦克风指示消失，音频输入已停止；正常自动锁屏仍生效。记录三十分钟闲置的 CPU、内存、能耗及热状态，方案阶段确定通过阈值后再验收。
5. 先播放其他 App 的视频 PiP，再进行首次会话启用和后续录音；视频小窗均保留且继续播放。反向顺序也通过。不要求用户拖动、隐藏窗口，屏幕没有残留小窗、边缘把手或触摸遮挡。至少验证系统视频源和一个常用第三方视频源。
6. 切换输入框、切换 App、收起键盘、连续点击、取消和延迟结果返回时，旧结果不能误写到新的输入位置。无法确认当前输入会话时不自动插入，并提供显式恢复或复制途径；保留策略在方案中定义。
7. 覆盖麦克风拒绝或撤销、完全访问未开启或关闭、来电或其他音频中断、蓝牙设备变化、主 App 强制退出、设备重启及模拟会话失效。状态不会永远停在“录音中”；重新启用不会自动恢复旧录音或提交旧结果。
8. 云端功能关闭时不发相关请求；开启后的发送内容与用户选择一致。服务断网、超时或凭据错误后仍能取消，不造成重复输入；凭据不进入共享转写数据或日志。
9. 新增 iOS 构建可复现，现有 `bash scripts/sdlc-checks.sh`、`bash scripts/ci-basic-checks.sh`、`swift test` 和按风险要求的桌面构建通过。iOS 的权限、录音、结果投递与键盘切换有真实设备操作证据；界面交付前逐条执行 ANTI_SLOP 审查。
10. 对第 3–5 项先做真机可行性验证。若无法同时做到闲时麦克风关闭、再次免跳转和视频 PiP 共存，记录失败条件并请求范围调整，不自行降级验收标准。

## Open questions

- 哪种公开机制能在 iOS 27 同时满足第 3–5 项？隐藏 PiP、Live Activity 或 AudioRecordingIntent 都需分别核对能力与真机结果，尚未选定。
- 系统本地 Speech 对 iPhone Air 的目标语言、混说、延迟与热状态是否足够？是否需要第二个可选本地识别引擎？
- 用户反馈 Confucius4-R2T2 的转写效果较好。移动端候选包括其社区 MLX 4-bit（模型包约 1.62 GB）、官方 GGUF Q4_K_M 加 Q8 音频模块（约 1.46 GB），以及较小的 Qwen3-ASR 0.6B；需验证量化后的识别效果、移动端运行时、后台推理和峰值内存，下载大小不作为运行内存估计。
- 最低支持的 iOS 版本、模型下载体积，以及手机端本地 LLM 是否进入后续版本。
- 云端第一版支持哪些提供方；凭据由用户自行配置还是另行提供服务？目前不假定已有手机端凭据或服务端。
- 完全访问关闭时可保留哪些功能，以及输入会话失效后的结果恢复与默认保留时间。
- 签名团队、App Group 标识和真机连接尚未确认，不为本阶段读取私人凭据。

## Inspection and evidence

- 重设基线前的桌面协调器依赖 AppKit、桌面输入目标与 Overlay，不宜整类移植。当前父分支已移动纯逻辑和识别引擎，应以实际模块契约为复用依据。
- 已确认重构分支在本次检查时为 `6044cef29ee9edff87d9aa843d1893a040e7dd1d`。其 `UtterRuntime`、`UtterContracts`、`UtterData`、`UtterProcessing`、`UtterModels` 和 `UtterSession` 已有独立模块与注入契约；Apple Speech 已提取到 `UtterAppleSpeech`。当前工作树使用这些实际源码，iOS 编译与运行验收仍未开始。
- 重构分支的 `Package.swift` 仍仅声明 macOS 平台和桌面可执行产品；`#if os(macOS)` 是清单执行主机条件，不能证明 iOS 目标可构建。`UtterAudio/Native` 仍使用桌面 CoreAudio 设备 API 和 IOKit。其验证记录明确说明功能挂载、统一执行及完整停用验收仍未完成；不能把此次模块提取直接标为已完成的跨平台架构。
- 本机有 Xcode 27.0、iOS 27.0 SDK 和 iOS 27.0 模拟器运行时；系统默认开发目录仍是 Command Line Tools。本阶段只用命令级 `DEVELOPER_DIR` 检查，没有修改系统配置。受限环境首次查询设备服务失败，通过只读查询重试后确认运行时可用；设备清单没有可用的 iPhone Air，真机连接与签名尚待实施阶段准备。
- 本机 iOS 27 SDK 声明 `SpeechAnalyzer` 自 Apple OS 26 起可用，`AudioRecordingIntent` 自 iOS 18 起可用。API 存在不等于键盘能够调用主 App 录音，仍需后续方案与设备验证。
- 原基线 `06a9502` 的准备检查：`bash scripts/sdlc-checks.sh`、`bash scripts/ci-basic-checks.sh` 均通过；使用命令级 Xcode 开发目录运行 `swift test` 通过，XCTest 共 812 项、18 项跳过、0 失败，另有 1 项 Swift Testing 通过。这不是当前重构基线或 iOS 的验收证据；切换后的结果记录于后续方案的准备检查。
- 当前仅修改本变更包文档；没有 iOS 应用实现、依赖修改、签名配置或设备安装。用户已于 2026-10-04 批准技术方案，实施计划进入编写；应用实现与验收尚未开始。
- Apple 平台约束：[自定义键盘的完全访问](https://developer.apple.com/documentation/uikit/configuring-open-access-for-a-custom-keyboard)、[视频通话 PiP](https://developer.apple.com/documentation/avkit/adopting-picture-in-picture-for-video-calls)、[PiP 可用性](https://developer.apple.com/documentation/avkit/avpictureinpicturecontroller/ispictureinpicturepossible)、[Live Activity 生命周期](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities)、[AudioRecordingIntent](https://developer.apple.com/documentation/appintents/audiorecordingintent)。
- 社区线索：[Fndroid 的豆包体验视频](https://x.com/fndroid/status/2093653439175934210)、[V2EX 体验讨论](https://www.v2ex.com/t/1242988)、[公开隐藏 PiP 实验](https://github.com/Yoroin/GlobalRefresh-PiP)及其[PiP 冲突记录](https://github.com/Yoroin/GlobalRefresh-PiP/pull/7)。这些是研究依据，不能证明豆包使用同一实现，也未代替 Utter 真机验证。
- 孔夫子模型来源：[官方 R2T2](https://huggingface.co/netease-youdao/Confucius4-R2T2)、[社区 MLX 4-bit 文件](https://huggingface.co/selcukkubur/Confucius4-R2T2-mlx-4bit/tree/main)、[官方 GGUF 文件](https://huggingface.co/netease-youdao/Confucius4-R2T2-GGUF/tree/main)。未找到官方 0.6B R2T2 参数版本；量化不改变原模型的参数规模。
