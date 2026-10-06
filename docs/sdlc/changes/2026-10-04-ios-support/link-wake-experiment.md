# SwiftUI Link wake experiment

**Status:** blocked
**Approved-by:** —
**Approved-date:** —
**Upstream:** [native-wake-research.md](native-wake-research.md)

## Result and scope

用户“ok，尝试”授权的独立零录音实验已完成。**指定 iPhone Air / iOS 27.0 模拟器中，真实 Utter 键盘的 SwiftUI Link 可以可见地冷启动主 App，也可以把已运行的后台主 App 带到前台。** 两条路径均收到匹配的 `onOpenURL` nonce；实际点按系统左上角返回入口后，原第一输入框保持焦点和原文，Utter 键盘重新出现。

这关闭了本模拟器的“首次可见激活”技术验证门槛。它没有修复普通键盘 `Button(intent:)` 的跨进程调度，也没有证明无跳转录音、自动返回、长时间待命、挂起后的隐式唤醒或豆包的实现。整个 iOS 产品 verification 继续 blocked；本文件不是修改产品 spec 或最终验收批准。

使用设备 `D0E3FAA3-2961-4263-ACDA-BC5BD65BCC05`、Xcode 27。没有真机、Team ID、发布、推送或 PR 操作。键盘完全访问沿用用户仅对此模拟器的授权，麦克风维持拒绝。

## Isolation and execution

- `scripts/build-ios-wake-probe.sh` 复制 `iOS/` 到被忽略的 `.build-ios/wake-probe/iOS`，只在副本覆盖主 App、键盘 View 与 UI 测试，注册 `utter-wake-probe` 诊断 URL；正式 `iOS/` 文件集合与所有 SHA-256 完全不变。
- 主 App 副本去掉 background modes，独立入口不调用 `VoiceHost`、`MobileController`、音频捕获、识别服务或资产下载。App 和键盘探针编译期只允许 Debug simulator。宿主 `com.ichendev.utter.wakehost` 也没有 background modes 或 App Group entitlement。
- 键盘保留现有 `KeyboardController`，呈现真实 SwiftUI `Link`，没有 responder/runtime 绕行、包装的 Intent 按钮或预先调用 `app.activate()`。URL 只含随机 UUID，不带输入正文、字段标识或录音命令。
- App 仅保存诊断 nonce、回调次数、进程 UUID、PID、回调时间及 scene 状态到自身 Documents 的 `wake-probe.json`。固定测试文字始终为 `Wake sample` / `Other sample`。
- 冷启动 tap 前必须 `app.state == .notRunning`；热启动先记录进程 UUID/PID，离开前台后 tap，回调后必须仍是同一进程。测试不强制挂起，不能把热启动通过解读为 suspension 证明。
- foreground 与回调分别等待。只有 `wake.nonce` 精确等于 Link 的 UUID、count 为 1、scene 为 active、PID 非零且保存无错误才通过；界面出现或 openURL accepted 都不足以通过。
- 返回使用实际系统 breadcrumb 点按，没有 `host.activate()` 代替用户操作。该入口可见于真实截图，但不在主 App AX 树中，因此测试使用此 Air 固定坐标 `(55, 50)`；这不是其他机型、字号或 VoiceOver 的通用定位方案。
- 返回后同时检查 `@FocusState` 暴露的 content-free `host.focus == first`、两字段原文未变及真实键盘 Link 存在。没有自动插入或复用旧录音租约。

## Final runtime evidence

最终 `.build-ios/wake-link-verified.log` / `.build-ios/wake-link-verified.xcresult`：**3 tests，0 failures，0 skips，46.916 秒，退出码 0**。附件已导出至 `.build-ios/wake-link-verified-attachments/`，manifest 关联测试、设备与截图。

| Scenario | Actual assertions | Observed process |
| --- | --- | --- |
| `testColdKeyboardLink` | terminated → actual keyboard Link → matching URL / active foreground → system return / first focus / unchanged fields / keyboard | PID `93899`，process `9C6C17BD-CFFF-4568-BC32-84D7AB5D257B` |
| `testWarmKeyboardLink` | background → actual keyboard Link → matching URL / active foreground / original PID and process → same return checks | PID `93985`，process `446132CF-6237-4BE1-9CDD-C13087BF36CC` |
| `testContainingAppURLControl` | terminated → ordinary host Link with same scheme → matching URL / active foreground | PID `93976`，process `D3DCF339-1302-4471-B041-73F1AFD7F999` |

已实际查看的截图：

- `C1A5EEFC-9C01-456C-A6CF-2C09D696B0C9.png`：冷启动前，外部宿主第一字段与真实 Utter Link。
- `0679CA88-AB34-4DBC-9FA0-869F1C748C76.png`：冷启动后 nonce、PID、active 与系统 Wake Host breadcrumb。
- `25691953-E92A-4412-BFEC-15801C7F7B31.png`：系统返回后 first 焦点、原文字和键盘。
- `0126A731-64DF-4BCB-B4FE-2B501F9389A7.png`：后台可见激活后的回调与进程。
- `3530F2B1-AA01-4BBB-886B-CDDA953F9FE6.png`：普通宿主 URL 正对照。

每项另有 `Observed URL callback and main process` 文本附件。`.build-ios/wake-verified-receipt.json` 是最后热启动后保存的原始文件；用户返回宿主后其最终 scene 为 inactive，不能用这个晚采样状态覆盖回调时截图和断言中的 active。

## Failed runs retained

第一轮 `.build-ios/wake-link-initial.*` 整体失败：冷启动前未显式安装实验主 App，实际显示旧 Release 键盘；普通宿主链接未能打开诊断 App。热启动 `app.launch()` 后真实新键盘 Link / URL / 进程断言通过，但返回测试错误地在主 App AX 树查找系统 breadcrumb 而失败。该轮没有冷启动证据，不能记成机制通过或否定证据。

第二轮 `.build-ios/wake-link-final.*` 冷、热启动含真实系统返回分别通过（15.964 / 19.096 秒）。普通 URL 对照失败在初始界面已有 nonce 控件、值仍为空的时刻；teardown 真实截图随后显示已收到正确 nonce。测试修为等待精确 nonce，而非只等待控件出现；未放宽回调/进程断言。最终整套复跑通过。

三个结果包和已导出附件均保留，没有把失败轮删掉或用 skip 绕开。

## Reproduction

先准备原有正常 Release，确保指定 Air 已安装 Utter 键盘并按用户授权开启完全访问。以下 resultBundlePath 必须尚不存在。

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
simulator_id=D0E3FAA3-2961-4263-ACDA-BC5BD65BCC05
bash scripts/build-ios-wake-probe.sh
xcrun simctl install "$simulator_id" .build-ios/wake-probe/build/Build/Products/Debug-iphonesimulator/Utter.app
xcrun simctl install "$simulator_id" .build-ios/wake-probe/WakeHost.app
xcodebuild test-without-building \
  -xctestrun .build-ios/wake-probe/build/Build/Products/UtteriOS_iphonesimulator27.0-arm64-x86_64.xctestrun \
  -destination "platform=iOS Simulator,id=$simulator_id" \
  -parallel-testing-enabled NO \
  -resultBundlePath .build-ios/wake-link-repro.xcresult
```

测试结束必须按下面恢复步骤移除临时宿主和诊断文件，重新安装正常 Release；不要将副本当成产品构建。

## Checks, independent review and restoration

三个 Debug simulator 构建均通过，最新为 `.build-ios/wake-probe-build-verified.log`。本轮 `sdlc-checks.sh`、`ci-basic-checks.sh` 与 `swift test` 通过；Swift 共 1010 XCTest，18 skips，0 failures，另有 1 Swift Testing 通过。第一次默认 CommandLineTools / 沙箱缓存检查失败后，明确使用命令级 Xcode DEVELOPER_DIR 重跑通过，没有修改全局 xcode-select。日志为 `.build-ios/wake-sdlc-checks.log`、`wake-basic-checks.log`、`wake-swift-test.log`。

独立验证者发现“只证明返回宿主，没有证明原字段焦点”的缺口，已加入 FocusState 实测断言并通过；另独立核对了真实截图、隔离哈希、复制版与正式 plist、脚本与项目 lint。最终只读复核已查看第三轮全套截图/日志及恢复记录，结论为本实验无剩余可操作发现，文档与证据一致；完整语音、真机和辅助功能证据缺口保持公开。这不是阶段批准。

实际恢复证据 `.build-ios/wake-restore.log` / `.build-ios/wake-restored-release.png`：

1. 保存最后诊断文件到被忽略的本地证据目录，仅删除主 App 自身的 `Documents/wake-probe.json`。
2. 卸载 `com.ichendev.utter.wakehost`，重新安装并启动原正常 Release。没有移除 Utter 或清空 App Group、词典及其他用户数据。
3. 正常 Release 二进制无 `utter-wake-probe` / `wake.link` / `WakeProbeApp`，Info.plist 没有诊断 URLTypes。安装的主 App 和键盘二进制 SHA-256 均与正常 Release 完全匹配。
4. 只读检查此模拟器 Utter 麦克风 `auth_value = 0`（拒绝）；恢复截图已查看，正常中文主页为“语音输入已关闭”。没有后台日志进程或临时宿主仍在运行。

## Final interface audit

本轮开始前和交付前完整阅读 `/Users/chenli/.codex/ANTI_SLOP.md`，按所有适用项复核。批准的原生 UI 与本次诊断用途决定组件选择；营销页面规则不用于给实验添加装饰。

| Applicable rules | Evidence and disposition |
| --- | --- |
| Native components, cohesion and typography | 真实 SwiftUI Form、NavigationStack、TextField、Link 与系统 inline 标题；保留已有 UIKit 键盘控制器和系统 globe，没有手造浏览器或假 App 图。系统语义字体/颜色一致，没有换 Google 字体、另造图标包或品牌拼贴。 |
| Contrast and legible content | 初审发现 LabeledContent 的 secondary 值较浅，改为 primary Text；最终五张截图已查看，说明、Link、nonce、PID、active 与固定文字清楚可读。正式 Release 的既有禁用控件与空输入提示沿用系统样式，本轮没有重新验收正式产品的全部辅助功能。 |
| Spacing, centering, edges and clipping | Form 与键盘保留系统 safe area，键盘 16 pt padding，Link 有 12 pt 垂直触控 padding；UUID 自然换行，不用固定行数裁断。截图中的说明和动作完整，无手造 notch、全页网格、溢出的阴影、拼接图或正文贴边。返回截图包含系统键盘过渡背景，不把它当新的产品装饰。 |
| Default visibility and honest state | 文字/Link 默认可见，回调状态由真实 onOpenURL 更新；PID 是实际进程，输入明确固定样例。没有透明模块、入口显现动画、虚假录音状态或将测试回执当识别结果。 |
| Real interactions and recovery | 实际点按第一字段、系统 globe 选 Utter、键盘 Link、普通宿主 Link和系统 breadcrumb；nonce/进程/前台/焦点/原文字均有断言。初轮返回定位错误已修复并复跑。没有用 automation activate 冒充用户返回。 |
| Copy, implementation details and localization scope | 明确标注模拟器实验、可见打开、不录音。nonce/PID/focus 只出现在隔离诊断版，不进入正式用户流程或正式本地化资源；中文夹带诊断术语适用于本次实验，不宣称英语 UI 验收。 |
| Motion, shadows, color and geometry | 仅系统导航/键盘反馈，无装饰浮动、glow、渐变、pill CTA 组合、hover 跳动、伪玻璃或噪声覆盖内容；没有必须执行才显现的内容。 |
| Accessibility and device limits | 标识与匹配 nonce、focus 标签实际可读取；普通字号/浅色/竖屏的指定 Air 交互已运行。未做最大字号、深色、横屏、VoiceOver、第二字段主动编辑或真机矩阵；坐标返回只适用于该测试 fixture，不宣称完整 UI 验收。 |
| Inapplicable page/brand rules | 本次未创建 hero、定价列、testimonial、logo wall、邮箱表单、营销页脚、图片/插画场景或网站主题。签名字体、背景氛围、全页分层与网站动效没有诊断价值，未为套用清单增加这些元素。 |

## Product implication

可将真实 Link 作为首次准备或失活后的显式激活候选。正式接入仍要分阶段：主 App 准备 → 用户返回 → 校验新的 generation/document/context 并创建新 lease；不能用短时旧 Start 命令等初始化，也不能取消 `viewWillDisappear` 的租约失效保护。

“此后免跳转”仍取决于实际后台执行机制、闲时不采集、真机 PiP 能力及用户可见的会话生命周期，本实验未尝试放宽这些批准约束。
