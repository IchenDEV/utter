# Isolated standby experiment

**Status:** blocked
**Approved-by:** —
**Approved-date:** —
**Upstream:** [verification.md](verification.md)

## Result and authorization

2026-10-06 01:50 独立进程新对照：不启动 XCTest/调试器，不禁用自动锁屏，control / playback+mix / playAndRecord+mix 三组无录音无播放均未保持连续后台执行；前台有界录音后 pause 同样出现 82.762 秒执行空档。暂停组不是零录音，也未测成系统闲时麦克风门槛通过。报告 [最新待命研究](ipad-comprehensive-test.md#debugger-free-standby-research-2026-10-06) 保留日志、前置失败、清理、正常 Release 恢复和视觉审计。下方模拟器/短时 XCTest 为历史证据，不外推日常待命成功。

2026-10-06 继续共存诊断：仅混音音频会话对照通过；不显式操作音频会话的视频通话源、普通 sample-buffer 源均在两种顺序复现共存失败。后启动者播放时先启动的候选停止，或候选启动使外部视频暂停并退出 PiP。详见 [因果隔离证据](ipad-comprehensive-test.md#pip-coexistence-causal-isolation-2026-10-06)。三项门槛未放宽，候选不接入产品；本轮不录音、不播放固定语音。

2026-10-04，用户“试一下”授权了独立模拟器研究实验。批准的产品 spec 仍排除隐藏 PiP；本次没有修改该设计，也没有把研究授权记为产品阶段批准。

**当前 Air / iOS 27.0 模拟器不支持 PiP，不能判断这个候选能否保活。** 视频通话 PiP 和普通视频 PiP 的公开能力查询均返回 false。普通后台对照完成了固定文字 Start → Stop → 单次插入，但对照进程没有被挂起，因此不能归因于 PiP，更不能关闭原生键盘系统调度门槛。

实验使用指定模拟器 `D0E3FAA3-2961-4263-ACDA-BC5BD65BCC05`，延续仅此模拟器的完全访问授权。没有请求麦克风、采集音频、下载识别资产或调用云端。输入为 `Utter bridge sample`，不是语音识别结果。

## Candidate and isolation

候选使用公开的 `AVPictureInPictureVideoCallViewController` 与 `ContentSource(activeVideoCallSourceView:contentViewController:)`。只有收到真实 didStart 后才请求 `preferredContentSize = 300 × 0.1`，同时撤销临时 playback 音频会话；请求尺寸不保证系统实际隐藏窗口。没有私有 KVC、静音音轨、持续麦克风或高刷驱动。

线索来自 [GlobalRefresh-PiP 源码](https://github.com/Yoroin/GlobalRefresh-PiP)。参考项目含有私有 KVC，本实验没有采用；其 [PR #7](https://github.com/Yoroin/GlobalRefresh-PiP/pull/7)讨论被其他 PiP 抢占后的处理，不能当双 PiP 共存证据。[Apple 视频通话 PiP 文档](https://developer.apple.com/documentation/avkit/adopting-picture-in-picture-for-video-calls)说明公开接口，不承诺上述压缩尺寸能长期保活。

豆包最新官方宣传与使用反馈是调查线索：[官方 App Store 版本历史](https://apps.apple.com/cn/app/id6752316550)、[官方微博说明](https://weibo.com/2/detail/5338370634943887)、[V2EX 使用反馈](https://www.v2ex.com/t/1242988)。本实验没有反编译豆包，不能确认豆包采用了这个候选。

`scripts/build-ios-standby-probe.sh` 复制工程到被忽略的 `.build-ios/standby-probe/iOS`，只覆盖副本的入口与测试。正式 `iOS/`、`Sources/` 没有实验引用。独立入口限定 Debug；默认构建 Simulator，`--device` 路径复制到 `.build-ios/standby-device-probe/iOS` 并使用真实开发签名。只有探针副本支持 iPad 原生尺寸，外部视频宿主仍只构建到模拟器。临时外部宿主是原生 SwiftUI App，播放本地无音轨测试视频；不是正式产品界面。

固定输入经过真实 MobileController、Session、App Group 命令、字段租约和 `UITextDocumentProxy.insertText`。诊断循环直接调用 `controller.perform`，**绕过系统 AppIntent 调度**，没有验证扩展能原生唤醒主 App。循环限制 600 秒/128 条命令，逐命令重验取消和期限；停止、失败及 PiP 被抢占都会撤销服务，不允许退回普通后台后冒充 PiP 成功。

## Actual checks

完整对照套件 `.build-ios/standby-handoff.log` / `.build-ios/standby-handoff.xcresult`：3 项，2 项跳过，0 失败，115.920 秒。跳过项不计功能通过。

独立复核指出外部视频等待期间 Stop 可能被旧启动覆盖，以及音频撤销日志没有区分成功/失败。已增加启动代次失效与逐轮检查，Stop 立即显示停止；音频撤销失败会撤销实验服务。修复后独立副本再次构建成功（`standby-probe-build-review.log`），两项能力门槛复验为 2 项全部跳过、0 失败、20.184 秒（`standby-gates-review.log` / `.xcresult`）。完整插入代码未变，没有重复计为一次新通过；上述支持设备上的支路仍未动态执行。

| Check | Observed result | Limit |
| --- | --- | --- |
| 普通后台对照 | 通过，96.917 秒。切换外部宿主，等待 75 秒后点按真实 Utter 键盘开始、停止、插入；字段恰好增加一次固定文字，插入动作随后消失。 | 普通对照持续执行，不能证明防止挂起。 |
| 视频通话 PiP | 明确跳过。能力查询 false；来源视图已在 window 中，尺寸 340 × 60。 | 没有产生 PiP，0.1pt 外观和持续保活均未执行。 |
| 普通视频 PiP 对照 | 明确跳过。能力查询也为 false。 | 排除了仅视频通话 source 搭建失败的解释；不能测双 PiP。 |
| 五分钟闲置及视频共存 | 未执行，被上述能力门槛挡住。 | 测试代码要求双方持续 active、视频时间推进及 rate > 0；不能用代码存在代替运行证据。 |
| 正常 Release 构建/隔离 | 通过。App、键盘、Live Activity 三个二进制均无实验入口/状态文件字符串，正式 Swift/pbx 无引用。 | 实验代码未接入产品，原生调度缺口保留。 |
| 仓库检查 | SDLC、basic checks、Swift 测试通过；1010 项 XCTest 中 18 项跳过，0 失败，另 1 项 Swift Testing 通过。 | 不代表 iOS 完整门槛套件或真机验收通过。 |

内容无关的运行日志 `.build-ios/standby-probe-runtime.log`：22:26:48.919 普通视频 supported=false；22:26:56.856 Utter PiP supported=false；22:27:13–22:28:34 普通对照 heartbeat 为 state=2、pip=false、idleDisabled=false；22:28:30.638 Start、22:28:31.937 Stop 均在 state=2、pip=false 下消费。原生 AVKit 日志 `.build-ios/standby-avkit.log` 另记录 `isPictureInPictureSupported NO`。

最终截图已从 xcresult 导出并实际查看，位于 `.build-ios/standby-handoff-attachments/`：

- `CE3D3DE5-4343-4763-9F0C-9ED70F482CD3.png`：外部原生宿主字段含一次固定文字，键盘恢复开始状态。
- `9DB1549A-ED4D-4390-A9EF-8455C7B1A9BE.png`：视频通话 PiP unsupported，明确合成输入说明。
- `A2DEBA6B-6295-4A86-A3E1-3F44A73F9DBF.png`：普通视频 PiP unsupported，播放时间与 rate 为零。

## Physical iPad observation (2026-10-05)

用户连接 iPad mini (A17 Pro) / iPadOS 27.2 后，公开视频通话 PiP 已真实启动并确认停止。空内容视图在无浮窗遮挡的重跑中停在 starting；补充单个本地固定帧的 AVSampleBufferDisplayLayer 和启动前 100 ms 让步后，启停测试通过。两项修改未单独隔离归因；固定帧不是摄像头、麦克风或循环播放。最终样本使用 DisplayImmediately 附件，didStart 后请求 300 × 0.1 并撤销 playback 会话。实际采样截图没有可见 PiP 小窗。

最终后台两组在 `pip-boundary.xcresult` 均通过（2 项、172.796 秒）：

| Group | UIKit background seconds | Loop ticks | Maximum gap | Actual PiP on return |
| --- | --- | --- | --- | --- |
| PiP | 74.98 | 276 | 0.28 s | active |
| Plain | 74.82 | 274 | 0.28 s | inactive |

边界采用系统单调时钟，从 didEnterBackground 到 willEnterForeground，首尾空档均计入并在返回时冻结。XCTest Home 后 state=4 不能作为后台判据；实际主屏截图与 UIKit 生命周期计数另行核实。**普通对照同样持续执行，不能证明 PiP 带来额外保活。** 结果仅覆盖连接设备/XCTest 下约 75 秒；没有排除测试环境影响，没有验证独立运行、五分钟、锁屏、音频重新激活、键盘调用或外部视频共存，也不能认定豆包采用此实现。

完整证据及本轮独立复核、截图限制见 [verification.md](verification.md#physical-ipad-preflight-2026-10-05)。原始日志、xcresult 和截图均在 `.build-ios/ipad-preflight/`。正常签名 Debug 已恢复安装（`restore-after-pip.json`），未修改麦克风权限或自动锁屏。设备组根目录诊断 JSON 暂留，不能声称已经删除。下方模拟器恢复记录是先前独立运行，不代表设备清理完成。

## Reproduction and rollback

仅在已获授权、启用 Utter 完全访问的测试模拟器执行。需要 Xcode 27、iOS 27 Simulator runtime、ffmpeg 和已解析的根依赖缓存。

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
bash scripts/build-ios-standby-probe.sh
xcrun simctl install SIMULATOR_UUID .build-ios/standby-probe/StandbyHost.app
xcodebuild \
  -xctestrun .build-ios/standby-probe/build/Build/Products/UtteriOS_iphonesimulator27.0-arm64-x86_64.xctestrun \
  -destination 'platform=iOS Simulator,id=SIMULATOR_UUID' \
  -parallel-testing-enabled NO test-without-building
```

实验测试会临时替换同 bundle 的 Utter 安装。结束后必须重新构建/安装正常 Release，卸载临时宿主，并仅删除 App Group 中本实验的 `standby-probe.json`，不要重置共享数据或权限。

本次已完成恢复：正常 Release 无诊断参数启动；临时 `com.ichendev.utter.standbyhost` 已卸载，`standby-probe.json` 已删除，实验日志流已结束。证据 `.build-ios/standby-release.log`、`standby-isolation.log`、`standby-restore.log` 和实际查看的 `standby-restored-release.png`。恢复截图为中文正常首页、语音输入关闭。未更改完全访问或麦克风权限。

## Final UI audit

实施前与交付前完整阅读 ANTI_SLOP 1–1599 行。以下覆盖本实验适用项；不把未执行的 PiP/设备交互列为通过。

| Applicable rules | Audit |
| --- | --- |
| 原生组件、字体和视觉一致性 | 诊断 App 使用系统 Form、NavigationStack、语义字号/颜色；宿主使用原生字段/按钮。没有新增主题、字体依赖、图标包、营销结构或品牌拼贴。正式产品视觉保持既有原生方案。 |
| 内容真实性、默认可见与文案 | 合成输入和无麦克风说明实际可见；unsupported 明确呈现，不做成功兜底。彩条为本地测试视频首帧，零播放进度真实显示，未称外部视频正在播放。技术标签只存在临时诊断宿主。 |
| 对比、边缘、裁切、对齐与留白 | 三张最终实验截图及恢复截图实际检查：正文、字段、动作标签完整，保留系统边距和安全区，没有文字/按钮重叠或纹理覆盖。空白来源区域服务于 PiP API 实验，不是装饰模块。 |
| 实际交互与反馈 | 实际点按普通/PiP 准备与外部视频动作，unsupported 分支给出反馈；外部字段、系统键盘切换、Start/Stop/Insert 有断言和截图。测试 teardown 终止进程，最终安装恢复及诊断状态删除有独立证据；不宣称 PiP 停止路径已在支持设备执行。 |
| 动效、图像和装饰 | 无揭幕、hover 跳动、循环浮动、光晕、装饰网格或自制玻璃。唯一视频是测量播放器推进的明确 fixture；没有静音保活播放。 |
| 动态字号、语言和辅助功能 | 当前实际字号下实验截图可读；正常中文 Release 已恢复。临时诊断英文标签没有进入产品资源。实验没有单独完成最大字号、横屏、VoiceOver、AA 或锁屏审计；正式 verification 已有的缺口保留。 |
| 不适用的网站规则 | hero、定价、testimonial、邮件表单、logo wall、页脚、CSS/SVG 营销插画未创建，没有为清单加入无关装饰或依赖。 |

## Remaining gate

2026-10-05 只读复核补充：现有测试把双方持续 active 作为共存必要条件，但 [Apple 的 suspended 状态](https://developer.apple.com/documentation/avkit/avpictureinpicturecontroller/ispictureinpicturesuspended)意味着另一种屏幕外暂停状态；此状态不等于 didStop，也不保证进程执行。现有 `StandbyHost.observeProbe` 只把布尔 active 映射为 active/inactive，尚不能区分它们。支持环境上的下一轮应先补齐状态观测，再以外部视频持续推进、真实新命令、按需音频及原字段插入判定体验，不能直接放宽断言后宣布共存通过。本轮没有修改或重跑该测试，既有 unsupported 结果不变。

此外，合成探针绕过了正式 `VoiceHost.perform` 的 Live Activity 创建，且没有运行 `MobileCapture` 的后台音频重新激活。两项都是独立未验门槛，详见 [新版豆包研究与复核](native-wake-research.md#2026-10-05-doubao-default-mode-and-remaining-gates)。

正式 [verification.md](verification.md) 继续 blocked。iPad 已补齐公开 PiP 启停及采样时刻无可见小窗的证据。下一次仍需确认 Air 灵动岛占用、独立运行时普通对照是否挂起、两种启动顺序的视频 PiP 共存、五分钟闲置/锁屏、真实录音停止以及热量/耗电；还需独立验证系统调度入口。外部视频宿主复用同一 PiP controller，快速 Stop → Start 的迟到 delegate 回调隔离还没有支持设备上的证据，需纳入生命周期复验。当前模拟器及 iPad 短时观察均未完成这些门槛，也不能认定这是豆包的实现。
