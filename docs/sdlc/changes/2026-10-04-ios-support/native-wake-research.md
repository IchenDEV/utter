# Native keyboard wake research

**Status:** blocked
**Approved-by:** —
**Approved-date:** —
**Upstream:** [verification.md](verification.md)

## Current direction

2026-10-06 最新真机证据：公开视频通话和普通 sample-buffer PiP 均可启动，但外部 Safari 视频的两种启动顺序均不能共存；删除显式音频会话操作也未修复。三个不录音、不播放、无 PiP 的独立进程对照在后台 85 秒出现约 78 秒执行空档。详见 [最新设备研究](ipad-comprehensive-test.md#debugger-free-standby-research-2026-10-06)与 [共存因果隔离](ipad-comprehensive-test.md#pip-coexistence-causal-isolation-2026-10-06)。产品接入仍 blocked，不再用模拟器 unsupported 描述真机候选现状。

2026-10-05 用户要求“移除多余的失败探索方向”。保留首次可见激活的 [Link 最小实验](link-wake-experiment.md)与 [后台待命探针](standby-experiment.md)，后续只围绕激活后的按需录音、后台再启动及视频共存推进。Link 已验证可见激活；下文模拟器证据为历史检查点，不替代后续真机结果。

## Retired experiments

已删除 `scripts/build-ios-bg-wake-probe.sh` 及 `scripts/tests/ios-bg-wake/` 的 11 个文件，移除 BGTask、快捷指令中转和灵动岛替代入口的诊断实现。两份重复的逐轮实验报告合并为下表；日志与截图仍在本地忽略目录，避免再次踩同一条路。

| Direction | Recorded outcome | Local evidence |
| --- | --- | --- |
| 键盘直接 Intent / callAsFunction | 普通键盘中执行于扩展，系统入口的成功不能转移给键盘。保留正式 Debug 的最小失败门槛测试，不再维护额外按钮变体。 | `.build-ios/bg-keyboard-intent-final.log/.xcresult`、`.build-ios/shortcut-final.log` |
| Shortcuts URL 中转 | 主 App 可后台启动，但前台切入并停留 Shortcuts，原字段免跳转目标失败。 | `.build-ios/shortcut-restore-verification.json`、`.build-ios/shortcut-keyboard-url-no-output.log` |
| 灵动岛系统按钮作为键盘替代入口 | 冷/暖/终止后五分钟调用通过，但需预建活动及用户额外操作，不作为当前产品方向。正式录音 Live Activity 的 Stop/Cancel 不属于被移除内容。 | `.build-ios/bg-system-idle.log/.xcresult`，3 项通过 |
| BG continued processing | 当前模拟器平台 unavailable；不推导真机失败，但不再维护当前环境无法验证的平行路线。 | `.build-ios/bg-wake-errors.log/.xcresult`、`bg-system-handoff.log/.xcresult` |

本次清理只移除独立研究文件；产品 iOS/共享模块、正式构建、桥通信与现有 E2E 保留。先前已恢复正常 Release；本次不操作模拟器及其系统快捷指令。历史遗留的 `Utter Wake Probe` 快捷指令仍无可运行的诊断动作，未因删除源码而宣称它已从系统移除。

## Finding

2026-10-04 用户要求继续研究原生唤醒。本轮核对当前代码、实际构建元数据、已有失败日志、iOS 27 SDK 和最新一手资料；没有修改产品代码或模拟器安装，没有录音。

**当前失败发生在键盘触发 Intent 的调度入口。首次启动与后续免跳转必须分开验证。** 尚未找到一个有证据保证普通键盘能在 App 未运行/已挂起时，完全无跳转地启动它并录音的公开机制。这个结论是研究边界，不是证明所有实现都不可能。

最有根据的工作解释是：当前普通 UIHostingController 中的 `Button(intent:)` 在键盘扩展的执行上下文中调用 Intent，没有形成 Widget/Live Activity 那样的系统跨进程调度。它也可能涉及 iOS 27 的实现缺陷；仅凭文档和一次路径失败不能定为系统通用限制。

## Current implementation evidence

- `iOS/Keyboard/KeyboardView.swift` 的动作是 `Button(intent: VoiceControlIntent(...))`；`KeyboardController` 用普通 `UIHostingController` 呈现，未承载 WidgetKit 系统入口。
- `VoiceControlIntent` 已采用 `AudioRecordingIntent`、`.background`、`allowedExecutionTargets = [.main]`。它在键盘目标中明确抛 unavailable，防止在扩展内捕获音频。
- `.build-ios/intent-probe-runtime.log` 有三次 `VoiceControlIntent entered extension`，没有对应 main app 事件。原生无自定义样式按钮的对照结果相同，因此不能把失败归咎于租约按钮样式。
- 当前 Debug 构建的 App、键盘、Live Activity 均有 `Metadata.appintents/extract.actionsdata`。三份 VoiceControlIntent 均包含 allowedTargets、AudioRecording system protocol、supportedModes，以及 `isDiscoverable = false`。内容无关摘要已保存为 `.build-ios/wake-research/intent-metadata-summary.json`；数值枚举没有被额外解读为运行保证。
- [Apple 对 `.main` 的说明](https://developer.apple.com/documentation/appintents/intentexecutiontargets/main)表达系统执行时的目标；它没有声明任意扩展内调用都会被转发。不能把它当作主动唤醒 API。
- [Apple Widget/Live Activity 文档](https://developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities)的跨进程说明针对系统呈现和调度的界面。既有 Live Activity Stop/Cancel 已通过，但发生在活动存在的会话里，不能证明普通键盘的首次启动。

## Public routes and limits

| Route | Primary evidence | Implication for Utter |
| --- | --- | --- |
| SwiftUI `Link` / URL | [KeyboardKit 作者的 iOS 18 修复](https://keyboardkit.com/blog/2024/09/11/ios18-breaks-selector-based-url-opening)改用真实 `Link`，代替 responder selector。 | 当前 Air 模拟器首次可见激活已通过，保留最小实验；不保证后台无界面启动或自动返回。 |
| `NSExtensionContext.open` | [Apple API 文档](https://developer.apple.com/documentation/foundation/nsextensioncontext/open(_:completionhandler:))明确由 extension point 决定支持范围，列出 Today/iMessage。 | API 公开不等于键盘获得授权；不能当已验证的 keyboard launch。 |
| `UIApplication` responder/runtime 绕行 | [Apple DTS 回答](https://developer.apple.com/forums/thread/764570)说明 UIApplication 在扩展不可用，runtime 绕过不可靠。 | 不采用 selector 换名、runtime 绕行或私有 API。该回答针对 Share Extension，不能据此概括所有键盘 `Link` 都失败。 |
| 系统 Shortcuts / 控件 / Action Button | [Apple App Intents 运行机制](https://developer.apple.com/documentation/appintents/configuring-the-runtime-behavior-of-your-app-intents)及[可发现性说明](https://developer.apple.com/documentation/appintents/appintent/isdiscoverable)。 | Shortcuts 系统入口对照已完成，不能把成功转移给普通键盘；中转方向已退役，不再扩展新的控件/Action Button 替代入口。 |
| `callAsFunction(donate:)` / `donate()` | [Apple 调用说明](https://developer.apple.com/documentation/appintents/appintent/callasfunction(donate:)-7v1om)描述参数解析、perform 和可选 donation。 | 函数调用变体在本机仍执行于扩展，实验已退役。Donation 不等于跨进程调度。 |
| iOS 27 `RunSystemShortcutIntent` | [Apple 文档](https://developer.apple.com/documentation/appintents/runsystemshortcutintent)及 [perform 限制](https://developer.apple.com/documentation/appintents/runsystemshortcutintent/perform())明确只在 Widget 的按钮有效，其他上下文无效果。 | 排除它作为普通键盘唤醒中转。 |
| App Group / Darwin notification | [Apple DTS](https://developer.apple.com/forums/thread/69333)明确 Darwin 通知不恢复挂起进程、不重启终止进程。 | 通信与唤醒是两层；通知可以优化活跃进程的响应，不能替代启动/保活。落盘命令本身也不是执行授权。 |
| `LongRunningIntent` | [iOS 27 App Intents 更新](https://developer.apple.com/documentation/updates/appintents/)支持延长已调度 Intent 的后台任务。 | 解决任务执行时间，不授予普通键盘一个新的调度入口，也不是无限待命的保证。 |

Apple 的 [AudioRecordingIntent 文档](https://developer.apple.com/documentation/appintents/audiorecordingintent)要求实际音频录制期间有 Live Activity。这个条件不能反过来推导“只创建 Activity 就能让 App 闲置时长期执行”，也不能以合成 Session 代替录音生命周期证据。

[App Review 4.4.1](https://developer.apple.com/app-store/review/guidelines/#extensions)另有限制键盘启动其他 App 的条款。[近期同类开发者问题](https://developer.apple.com/forums/thread/843118)正在追问 containing app 听写入口，未找到 Apple 书面解法。该提问不是官方结论；供应商的 Link 方案也不能自动视为本产品在当前系统/审核下的保证。本轮只研究机制，不推送、投稿或请求第三方回复。

## How modern continuous dictation differs

### 2026-10-05: Doubao default mode and remaining gates

用户再次确认目前只能使用模拟器。继续保留正常 Release 安装；本轮是公开资料与源码核查，没有安装新探针、改变权限或录音。

- [豆包 9 月 1 日官方说明](https://weibo.com/2/detail/5338370634943887)将 v1.5.3 默认模式描述为首次跳转后免悬浮窗、不占灵动岛、可与视频小窗共存。该来源已在 standby 报告中收录；它不是内部实现披露。不能用旧版“持续麦克风”或旧悬浮窗模式解释新版全部行为。
- 实际打开了 [Fndroid 8 月 29 日 X 原帖](https://x.com/fndroid/status/2093653439175934210)。作者称最新 TestFlight 不再弹 PiP，也不会被别的 PiP 挤掉，并附键盘切换演示。视频裁切范围不能证明整屏没有窗口、灵动岛或麦克风指示；帖子也没有提供 API 或代码。此前“未找到实现证据”的结论保留，不等于没有找到使用演示。
- [9 月 18 日 V2EX 作者的复测](https://www.v2ex.com/t/1242988)称仅语音期间显示麦克风状态，且划掉豆包主进程后仍需跳转。**工作假设**应优先研究首次激活后的后台待命与按需录音；不能把“无条件冷启动免跳转”当作豆包已经做到的前提。指示灯观察也不是音频会话内部状态的测量。

独立只读复核找出三道不能合并的门槛：

1. **执行机会：** 键盘新命令是否被主进程及时消费。现有合成文字实验只覆盖这一层及插入链路，且普通后台对照未挂起。
2. **活动创建：** `iOS/App/VoiceHost.swift` 的 Start 先 `Activity.request` 再执行 controller；standby 探针直接调用 controller，绕过了这一步。[Apple 文档](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities)说明通常须前台创建，后台可通过 `LiveActivityIntent` 创建。当前 Start 的 `VoiceControlIntent` 仅采用 `AudioRecordingIntent`；双协议可以作为隔离实验候选，不能仅改声明就视为修复系统调度。
3. **音频重新激活：** `MobileCapture` 每轮重新 `setActive(true)`，Stop 完全 deactivate。[Apple DTS 对 BLE 触发录音的答复](https://developer.apple.com/forums/thread/816408)确认通用音频 API 的后台激活存在隐私限制。该答复不证明所有系统入口/PiP 情况都失败，但足以否定“保活成功自然就能开麦”的推理。

另外，[Apple 对 `isPictureInPictureSuspended` 的说明](https://developer.apple.com/documentation/avkit/avpictureinpicturecontroller/ispictureinpicturesuspended)区分屏幕外暂停与会话结束。别的 App 使用 PiP 时，原会话可能被挂起，之后恢复。**这既不是后台执行保证，也不是后台录音授权。** 后续共存实验要同时记录 supported/possible/active/suspended、停止回调、主进程 PID/状态和新命令回执；不能只凭两个 active 布尔值判断成败。

只读参考了 [GlobalRefresh-PiP](https://github.com/Yoroin/GlobalRefresh-PiP) 的透明视频通话 PiP 及 0.1pt 尺寸思路；其私有 KVC、可选静音循环和高刷行为不属于当前探针，也未复制到产品。其 [PR #7](https://github.com/Yoroin/GlobalRefresh-PiP/pull/7)修复抢占后的处理，不证明双 PiP 共存，更不能确认豆包采用同一机制。

本轮官方 DocC 原文保存在被忽略的 `.build-ios/doubao-research/apple-pip-suspended.md` 与 `apple-live-activities.md`。尚无豆包内部实现或当前模拟器支持 PiP 的新证据；产品仍 blocked。

独立复核确认上述来源边界及三道门槛无实质问题。文档更新后 SDLC、basic checks 与 Swift 测试通过，日志在 `.build-ios/doubao-research/`；首轮受限沙箱检查遇到缓存/工具链问题，改用当前 Xcode 与正常缓存权限重跑通过。本轮没有重新执行 iOS 唤醒、PiP 或录音测试。

KeyboardKit 作者在 [2026-01-03 的连续听写说明](https://keyboardkit.com/blog/2026/01/03/a-brand-new-keyboard-dictation-experience)描述：必要时先打开主 App，随后保持引擎连接；提交结果时切到 idle 而不结束听写。[2026-08-28 的预览说明](https://keyboardkit.com/blog/2026/08/28/keyboardkit-11-developer-preview)要求主 App 支持 background audio。

据此可确定其公开描述并非每次在键盘中冷启动一个新进程。idle 被描述为停止写入观察到的结果，不能据此推定麦克风已关闭；持续采集、音频指示与电量必须另测。这不是 Utter 已批准的“闲时不采集”方案。

[2026-10-01 的正式发布](https://keyboardkit.com/blog/2026/10/01/keyboardkit-11-is-out)进一步把听写/宿主识别移到插件。没有取得这些插件的实现与设备测量，不能把“键盘内听写”的产品表述解释为扩展直接拥有麦克风，或认定 iOS 27 已取消限制。宿主 App 识别和自动返回也不能与 containing app 启动混为一谈。

X 检索没有找到足以确认豆包最新启动实现的作者代码、系统调用或可复现轨迹。现有豆包官方功能宣传和用户体验反馈仍只是线索，不能证明其使用 AppIntent、隐藏 PiP 或某个新系统 entitlement。

## Proposed verification order

这里是后续独立诊断的可审查路线，不是改写已批准产品 spec，也不是实现或验收批准。

1. **首次可见激活：** 已有 Link 冷/暖启动证据，保留最小复现，不再重复扩展启动入口。
2. **按需录音：** 尽早分开验证正式 `VoiceHost.perform` 的活动创建、`MobileCapture` 的 setActive 结果、真实首帧、Stop 后停止采集/撤销会话及第二次启动；合成回执不能代替这些门槛，完整 ASR 排在之后。
3. **后台待命与视频共存：** 真机已排除本轮视频通话、压缩窗口和普通 sample-buffer 源的共存修复，不继续仅调尺寸或自动重抢。后续不同候选仍须记录 PID、单调时钟执行空档、active/suspended/停止回调、外部播放推进及真实新命令；先用无 XCTest/无调试器的独立运行作短时对照，再决定是否进入五分钟、锁屏和完整录音矩阵。模拟器音频结果不能外推真机权限行为，闲时不保存也不能代替麦克风关闭。

## Integration constraints found in current code

仅加 Link 还不能复用现有 Start 命令：

- `MobileController.init` 生成新 generation 并发布 disabled。冷启动必须先进行主 App 准备与新 generation 握手，不能执行上次进程的旧 lease。
- `KeyboardController.viewWillDisappear` 撤销 lease。切换到主 App 会使原字段会话失效；返回后应重新验证 documentIdentifier/字段上下文并创建新 lease，不能降低失效保护来追求自动插入。
- 当前 lease 为 5 秒、command 为 10 秒；语言准备/授权可能超过它们。启动回执与字段录音命令应分阶段，不能把一条短租约 Start 留着等初始化结束。
- 主 App 的正式路径只有准备与真实录音服务，尚无 URL 路由或公开激活 Shortcut。系统初始化成功之前不能把结果消费/模型优化当作唤醒修复。

这些限制与父分支的 Runtime / Session 架构相容：继续由主 App 持有音频与执行服务，键盘只持有短租约、发送动作和插入结果。无需再建一套识别 pipeline 或将模型装进扩展。

## Research verification

公开网页在本轮实时读取；Apple 的 JS 文档同时下载官方 DocC JSON，证据保存在被忽略的 `.build-ios/wake-research/`（Button、OpenURLAction、main target、extension open、RunSystemShortcutIntent）。本轮只增加研究文档和链接，没有重新运行语音/UI 套件，没有改变模拟器状态；既有失败/通过报告仍按原运行记录引用。正式 verification 保持 blocked。
