# Verification: Utter iOS 语音输入

**Status:** blocked
**Approved-by:** —
**Approved-date:** —
**Upstream:** [plan.md](plan.md)

2026-10-06 01:50 独立待命研究：无 XCTest/无调试器的三组无 I/O 音频会话对照均有约 78 秒后台执行空档；前台录音约 3.15 秒后暂停的第四组在 84.783 秒后台出现 82.762 秒空档，同 PID 恢复，录音时间未推进。四组均未证明连续待命，脚本 exit 0 不是候选通过。前台录音只使用既有授权，硬上限 4 秒；设备上自己的 CAF 与三份诊断已确认清理，本地证据副本保留，正常 Release 覆盖恢复、验签及 16.779 秒启动/最大字号侧栏回归通过。详见 [新研究、测量边界及适用项审计](ipad-comprehensive-test.md#debugger-free-standby-research-2026-10-06)。键盘录音仍禁用，三门槛及产品 blocked 状态不变。

2026-10-06 继续共存诊断：仅混音音频会话对照通过；不显式操作音频会话的视频通话源、普通 sample-buffer 源均在两种顺序复现共存失败。后启动者播放时先启动的候选停止，或候选启动使外部视频暂停并退出 PiP。详见 [因果隔离证据](ipad-comprehensive-test.md#pip-coexistence-causal-isolation-2026-10-06)。三项门槛未放宽，候选不接入产品；本轮不录音、不播放固定语音。

2026-10-06 01:07 收尾：最新已知标签清理 15.354 秒、恢复正常 Release 启动回归 16.922 秒通过；App Group 三诊断无残留，临时服务已停止，签名与最终 SDLC/basic 通过。适用项视觉审计及完整证据见报告顶部；共存仍 blocked。

Latest expanded iPad test checkpoint: [comprehensive physical-device matrix](ipad-comprehensive-test.md).
23:15 收尾：正常签名 Release 已恢复安装并无参数启动；四方向键盘编辑与大字号侧栏/正常启动两项真机回归通过。仅清理已知测试标签与探针诊断，LAN 视频服务已停止，孔夫子 17 文件仍保留。最终 SDLC/basic 通过；详细适用项视觉审计、日志和限制见完整报告顶部。
2026-10-05 最后候选验证：用户批准的公开压缩视频通话 PiP 在系统设置宿主完成真实后台录音和本次结果精确回填（49.697 秒、667200 帧），该轮正常停止并释放 capture。外部 Safari 视频 PiP 两种启动顺序均失败：视频先开时被暂停并退出 PiP，Utter 先开时被后启动的视频替换，键盘显示关闭；普通 App 切换对照保持视频播放。三项组合门槛未通过，候选不接入产品，不宣称完整豆包语音对标完成。孔夫子 17 文件本地传入已校验，修复 iOS MLX 缓存峰值后一次真录音通过；设备内 TLS 下载、解码取消和质量/延迟矩阵仍未完成。旧检查点中的“孔夫子未测试”由上述新证据取代。
用户解锁后已完成真实 Release 交互和 Mac 固定语音录音：Apple 中文、英文后台持续录音、复制后实际粘贴、取消、30 秒自动结束、四方向键盘编辑、地球切换、设置持久化和麦克风撤销/恢复通过。最新原生审计仍有 11 条报告（9 条未定位对比度、语音页 2 条字号），不算验收通过。完整模型下载暴露 iOS 持久化绝对沙盒路径问题；修复后目录权限错误不再出现，但后续下载仍失败，不能宣称 Whisper 真机识别通过。最终大字号侧栏与正常中文启动通过。详见完整报告。Release 键盘录音仍禁用，免跳转语音门槛未关闭。
以下各节为此前检查点；涉及麦克风权限、未开始录音和最终构建的旧描述，以这份扩展报告的最新证据为准。

2026-10-05 [快捷指令入口实验](native-wake-research.md#retired-experiments)：真实系统 Shortcuts 可后台冷启动 main；键盘原生 Button / callAsFunction 冷暖仍执行在扩展。键盘 URL 在无返回值重跑也能冷启动 main，但视频确认切入并停留 Shortcuts，免跳转门槛失败。正常 Release 已恢复，22 个正式 iOS 文件未改动、麦克风仍拒绝；保留一条不可运行诊断动作的测试快捷指令，未执行系统要求确认的永久删除。产品仍 blocked。


## Product expansion: native iPad, models and keyboard (2026-10-05)

用户直接要求补齐原生 iPadOS、模型下载、移动端适用设置、中央麦克风/右下地球键盘和触感。扩充范围已记入 plan，不更改原有隐私与免跳转门槛；下方较早记录是历史检查点，以本节为产品扩充的最新证据。

- 原生工程设备族为 `1,2`，iPad 四向旋转；宽布局用 NavigationSplitView，窄布局用 TabView，共享选择状态避免旋转丢页。`.build-ios/product-ipad.log` / `.xcresult` 中原生横竖屏导航、设置重启持久化、无需麦克风的词典增删共两项真机测试通过；对应完整屏幕截图已查看。
- 模型页复用共享目录、下载/取消、完整性校验和删除；包含 Apple 语言资产、Whisper tiny/base/small 和标明设备表现待验证的 Qwen 候选。`.build-ios/product-ui-second.log` 验证取消/重试与键盘编辑；`.build-ios/product-final-simulator.log` 的真实 Whisper tiny 下载、选择、重启保留、删除测试通过。该次整轮另有旋转失败，不能称整轮通过；旋转后续在 `product-accessibility.log` 和真机 `product-ipad.log` 通过。
- 设置接入识别语言、时长上限、音频敏感度、行业词库、个人词典、触感、按键声音及本机数据清理。配置按会话冻结，选择/删除模型先排空旧会话，清理等待初始化与下载停止；无云端开关占位。键盘中央麦克风按状态切换停止，取消仅在工作中出现；删除/空格/换行和右下地球菜单已有实际交互证据。
- 独立复核发现录音时长到期错误地走取消，已改为 SessionJobControl 的幂等 stop，真实与合成录音共用限时等待。`product-a11y-fix2.log` 的 `testRecordingLimitFinishesWithResult` 通过：实际等待 30 秒自动返回文字，随后手动取消不返回文字，最后恢复 120 秒。未使用真实麦克风。
- Apple 资产准备状态现在读取系统 AssetInventory，不持久化猜测；查询 revision 在准备与清理时失效，避免旧异步结果覆盖新状态。独立验证者已复核竞态修复；真实设备上的 Apple 资产安装/移除仍待专项验证。
- 触感使用 UIKit UIImpactFeedbackGenerator，声音使用输入点击 API，由用户设置及完全访问控制。iPad 硬件上的实际震动不作通过声明；无声音模拟震动。

本轮完整辅助功能审计仍未通过。`product-native-final.log` 曾在主内容固定底部避让 76 pt 时整轮通过审计、旋转和地球菜单，但截图复查发现键盘上方出现固定空白，因此该布局未作为最终实现。随后键盘通知控制留白、滚动内容留白两种尝试均有审计回归，已撤回。最终保留原生 Form/TabView；PhoneView 通过 FocusState 和 ScrollViewReader 在键盘展示后将当前输入框滚入可见区域，不动态缩放整个页面。

最终源码的 `product-focus-final.log` / `.xcresult` 审计报告 4 条对比度、3 条 Dynamic Type、1 条裁切问题：主页面 Open settings 位于浮动标签栏覆盖区域；键盘展示后的审计还包含诊断按钮、Open settings、Personal dictionary 和无法解析的 element。系统审计过程中实际会收起键盘，因此不能把对主 App 的这次审计写作键盘扩展的完整审计。未知元素和部分可见内容不直接归为系统误报；没有过滤或忽略任何 issue。标题/页脚使用语义字号和颜色的多行 UILabel，键盘图标按钮保留明确 44 pt 命中区域。交互通过不等同完整辅助功能验收。

| Final local check | Result / evidence |
| --- | --- |
| SDLC | 通过，末次 `product-delivery-sdlc.log`。 |
| 基础检查 | 通过，末次 `product-delivery-basic-final.log`。限制沙盒/默认 CommandLineTools 首跑因模块缓存权限失败；使用已验证 Xcode 工具链与系统缓存重跑成功。中英文文案另通过 plutil。 |
| 键盘桥确定性检查 | 通过，`product-resume-bridge.log`，覆盖重复、旧字段、消费失败、重启、过期/损坏/限制等。 |
| Swift 测试 | 通过，`product-resume-swift.log`：共 1010 项 XCTest，18 项跳过、0 失败；另 1 项 Swift Testing 通过。跳过不代表硬件/模型验证。 |
| 关键产品交互 | 设置/词典见 `product-a11y-final.log`（该整轮因审计失败退出 65）。最终 `product-final-dark-input.log` 的合成文字、单次插入、删除/空格/换行通过；与大字号导航组成两项完整通过，退出 0。 |
| 深色/最大辅助字号 | 最终 `product-final-dark-input.log` 两项、0 失败，158.158 秒。`product-final-dark-input-attachments` 主控件、词典与键盘截图已查看：全部文案可滚动，当前输入框可见，键盘状态/停止/取消/删除/空格/Return/地球完整。词典文案明确本机保存与识别后纠正；未宣称完整 VoiceOver 通过。模拟器已恢复 light / large。 |
| 最终 Release 真机界面 | `product-ipad-unlocked-release.log` 两项、0 失败，56.018 秒；已查看原生横竖屏及词典/键盘截图。锁屏阻断已解除。 |
| 完整自动辅助功能审计 | 未通过，`product-focus-final.log` 有 8 条报告；此前固定留白布局的通过不算最终通过。见上文，不忽略。 |



独立只读复核按仓库要求执行，覆盖模型/设置/键盘真实源码；录音上限、Apple 资产状态及 revision 修复后无剩余可操作的代码阻断。验证者明确指出辅助功能失败必须保留；未代替用户审批或操作设备。

最终设备产物：`product-release-delivery-build.log` 的 Release build-for-testing 成功，沿用既有 Apple Development 身份，没有签名降级。`codesign --verify --deep --strict` 在可访问系统信任服务的环境下通过（限制沙盒中首先返回 CSSMERR_TP_NOT_TRUSTED，不将其当成证书失效）；最终主文件修改时间早于对应已重编译对象。UIDeviceFamily 为 `[1,2]`，三个 Release 程序经 strings 检查没有诊断/模拟宿主标记，安装包中中英文字典提示与录音时长文案已核对。`product-release-delivery-install.json` outcome=success，最终 Release 已安装到原 iPad，未卸载或清除数据。

2026-10-05 20:17 用户回复 unlocked 后，最终 Release 真机运行已补验通过：`product-ipad-unlocked-release.log` / `.xcresult` 两项、0 失败，56.018 秒，退出 0。xctestrun 的 TestHostPath 和 UITargetAppPath 均为 Release-iphoneos。覆盖原生横竖屏导航、模型页呈现、设置开关重启持久化并恢复原值，以及固定测试词条增删。没有点按录音、申请麦克风或下载新模型。此前 `product-release-delivery-launch.log` 的 Locked 仅为已解除的环境阻断，不再列作待验。

`product-ipad-unlocked-release-attachments` 的最终竖屏语音页、横屏模型/设置与词典完成截图已实际查看：系统侧栏、分组内容、字号、主操作与键盘布局清楚；词典截图显示 Utter 键盘、中央禁用麦克风、空格/Return 和右下地球，明确提示当前版本不支持从键盘启动录音。截图只能证明呈现，不能扩展为键盘语音、Full Access 切换或触感测试通过。已删除测试词条，设置恢复原值；未提交、推送或发布。

最终布局的旋转测试在 `product-focus-final.log` 通过（193.279 秒），截图确认返回 Voice 页；该过程三次等不到系统动画完成通知，随后下一项测试又等待 idle，因此主动停止整轮（退出 75）。不将整轮算作成功。原始审计与旋转截图已导出到 `product-focus-final-attachments`；`8DA4607F-6A5B-4EB0-A1AD-D72E3D42EACB.png` 确认键盘展示时光标及两个输入框可见，固定底部空白已撤回。随后仅重启指定模拟器，未抹除内容；`product-final-dark-input.log` 两项导航/输入在深色最大字号下全部通过，具体见上方表格。

最终模拟器 Release：`product-final-release-simulator.log` 构建成功；安装并以无参数正常启动，进程 47595。`product-release-final-visible.png` 已查看，无诊断入口、语音关闭；light / large 已恢复。测试宿主已随测试退出，终止命令返回 nothing to terminate；未清除数据、变更完全访问或开启麦克风。

### Product UI audit

开始与收尾均完整读取 ANTI_SLOP（1–1599 行），逐条判断适用性，按同一问题合并如下。原生 UI 的批准方向优先于营销网页默认。

| Rule group | Findings and evidence |
| --- | --- |
| 一致性、布局与主操作 | iPhone 原生标签、iPad 原生侧栏共享选中页；中央 88 pt 麦克风为明确主操作，取消与编辑退居旁侧，系统地球固定右下。真实 iPad 横竖屏和模拟器地球菜单均经过点按，不是效果图。 |
| 字体、颜色与图标 | 单一系统字体、语义黑白颜色、SF Symbols；没有下载字体、额外图标库或自绘假系统控件。分组标题用多行 UILabel 保证全部辅助字号，字体/颜色审计修复有前后日志。 |
| 对齐、留白、裁切与命中 | 麦克风水平中心由等宽左右控件保持；44 pt 图标按钮明确 contentShape，消除原生命中区域失败。真实键盘截图中状态、麦克风、空格、回车及地球可达；大字号允许滚动。浮动标签栏附近的审计报告按原始失败保留；撤回为通过审计加入的固定底部留白，未靠过滤通过。 |
| 内容真实性与交互 | 实际下载进度、取消/重试、校验、选择与删除；设置开关重启持久，词典增删无需麦克风；Synthetic 诊断显式开启并保留说明。Release 不把未通过的原生语音调度呈现为可用动作。 |
| 文案与本地化 | 所有新状态和控件使用共享 L 的中英文键；中文“录音时长上限”与自动结束语义一致。模型错误仍来自现有共享服务，设备/系统语言差异不伪装为完整双语测试。 |
| 动效、玻璃与装饰 | 仅使用系统导航/菜单/进度反馈；无自制毛玻璃、发光/悬浮卡片、渐变文字、背景网格、装饰线或入口透明动画。系统标签栏遮挡独立记录，不用装饰掩盖失败。 |
| 辅助功能与设备差异 | 部分字号和点击区域问题已修；最终仍有对比度、字号与裁切报告，未豁免。VoiceOver 全程朗读、iPad 分屏、多设备触感和实际音频仍无完整证据；不因标签存在或模拟器通过宣称验证完成。 |
| 不适用条目 | 本次不创建网页 hero、定价、testimonial、客户 logo、页脚、图片拼接、营销字体/签名、CSS/SVG 插画、悬停动画；逐项标为不适用，没有为了清单引入装饰或依赖。 |

原生键盘到主 App 的免跳转调度、真实录音、本地识别质量/性能、长期后台与视频 PiP 共存仍未通过。本轮没有改变上述结论，没有开启麦克风、上传用户音频或进行外部发布；verification 继续 blocked。

## Physical iPad preflight (2026-10-05)

用户指定的 iPad mini (A17 Pro) / iPadOS 27.2 已连接，Developer Mode 开启。真实 Apple Development 签名构建成功；主 App、键盘、Live Activity 的描述文件均包含同一 App Group 和指定设备，`codesign --verify --deep --strict` 通过。先前空 App Group 的描述文件在自动签名重试后得到更新；未应用临时能力声明补丁，未移除 entitlement 或降级签名。团队配置只在忽略的 `iOS/Development.local.xcconfig`。

`devicectl` 安装成功。首次启动被系统开发者信任检查拒绝，用户亲自信任后启动成功。既有 `testSessionFinishCancelAndDisable` 在真机通过：1 项、0 失败、45.773 秒；仅固定文字，未采集麦克风。证据为 `.build-ios/ipad-preflight/session-flow.xcresult`、安装/启动 JSON 和构建日志。该测试的 `app.screenshot()` 导出在 iPhone 兼容窗口下裁切，不能作为整屏视觉通过证据。

保留的 standby 探针新增真实开发签名构建入口和单次启停门槛；仅独立副本支持 iPad 原生尺寸，正式产品入口未改。独立复核发现“清空 controller 后立即显示 disabled”会误报停止，已修为最多 5 秒确认实际 active/suspended 均为 false，并保留音频撤销失败及迟到回调身份检查。复核确认本轮静态范围无剩余阻断。

第一轮 PiP 测试受快速备忘录、系统无线数据提示和无效点按坐标干扰，不能作为能力结论（`pip-gate.xcresult`）。用户收起浮窗后，空内容视图仍停在 starting（`pip-gate-final.xcresult`）。在独立探针加入 AVSampleBufferDisplayLayer、单个本地固定帧和启动前 100 ms 让步后，`testPiPStartAndStop` 通过：1 项、0 失败、14.135 秒（`pip-frame.xcresult`）。此组合修改没有逐项隔离归因，也未证明首帧实际呈现。真实 didStart 后请求高度 0.1，并成功撤销临时 playback 音频会话；停止确认 active/suspended 均为 false。最终样本使用 DisplayImmediately 附件避免零时间戳的显示歧义。没有持续视频、静音音轨、麦克风或禁止自动锁屏。

最终两组后台对照 `pip-boundary.xcresult` / `pip-boundary.log`：2 项、0 失败、172.796 秒。PiP 组后台 74.98 秒，276 次循环，最大执行空档 0.28 秒，恢复时实际 PiP 为 active；普通组 74.82 秒，274 次，最大空档同为 0.28 秒，PiP inactive。计时覆盖 didEnterBackground 到 willEnterForeground，包括首次/末次循环与边界的空档；使用单调时钟并在返回时冻结。较早 `pip-background.xcresult` 有失败且遗漏边界空档，已被最终判据取代，不能当作通过。独立复核确认边界及实际 PiP 状态判据已修复。

**普通组同样持续执行，因此没有证明 PiP 的额外保活效果。** 本轮是连接设备、XCTest 环境下约 75 秒的观察，不是独立运行、长期/锁屏或功耗证据。两组 Home 后 XCTest 均曾报告 state=4；后台结论依据 UIKit 生命周期计时与实际主屏截图，不依赖该枚举。`pip-boundary-attachments/ECAF8A61-2859-480A-9F19-C7C378B162D6.png` 与 `939F3A9D-A3A1-4A12-B7FB-598AEC3FA45F.png` 已实际查看，分别为两组约 75 秒后的主屏，没有可见的 PiP 小窗。恢复计数截图抓到系统切换模糊帧，不能作为可读标签证据；数字来自实际 accessibility label 和 XCTest 日志。截图只说明这些采样时刻的外观，不等于全程不可见，也不证明视频共存。

本轮最终 `sdlc-checks`、`ci-basic-checks`、`swift test` 均通过（`ipad-preflight/sdlc-pip.log`、`basic-pip.log`、`swift-pip.log`）；最终探针签名 build-for-testing 及上述设备运行通过。Xcode 收尾诊断采集另报默认工具链找不到 devicectl，测试断言、退出码 0 和 xcresult 仍存在；不将该附加诊断记为成功。实验进程经 teardown 停止，正常签名 Debug Utter 已重新安装恢复（`restore-after-pip.json`）。App Group 中仅探针状态 JSON 暂留，未宣称清理完成。

测试前及收尾完整复读 ANTI_SLOP 1–1599 行：沿用原生 Form、语义字号/颜色和安全区，没有新增视觉依赖、装饰、动画或营销结构。PiP 启停及两组准备/停止由实际点按验证；已检查启停整屏截图和后台主屏。合成文字/无麦克风说明保留，技术计数仅属独立诊断，不进入正式界面。恢复切换模糊帧及早期兼容窗口裁切不列为视觉通过；最大字号、深色、VoiceOver、视频共存与录音隐私路径尚未在 iPad 完成。网站 hero/定价/页脚等条目不适用。产品设计与既有辅助功能缺口保持原样，不将本轮研究通过当作完整产品验收。

用户已明确批准“仅此 iPad 测试”的键盘完全访问，正在自行添加键盘并开启；尚未收到“已开启”，故未运行真机键盘调用测试。仅使用固定文字，不使用麦克风。原生键盘调用、后台实际录音、五分钟待命、视频共存和 Air 组合门槛仍 blocked。

## Exploration cleanup

2026-10-05 用户明确要求移除多余失败方向。删除 BG/Shortcuts/灵动岛替代入口的共用构建器、11 个隔离探针文件及两份冗长报告，结果集中保留于 [退役记录](native-wake-research.md#retired-experiments)。保留已验证首次激活的 Link、尚待支持环境验证的 standby，以及正式 Debug 失败门槛测试；不删除负面证据来伪装产品通过。产品状态继续 blocked。

清理前后对 `iOS/`、`Sources/` 及保留的 Link/standby 探针全文件集合和 SHA-256 比较一致；已删除路径仅在明确的退役说明中出现，没有构建/运行代码引用。文档本地链接检查通过。证据位于 `.build-ios/exploration-cleanup/`，删除清单为 `removed-manifest.json`。

本轮 `bash scripts/sdlc-checks.sh`、`bash scripts/ci-basic-checks.sh`、`swift test` 均退出 0，日志分别为上述目录内 `sdlc.log`、`basic.log`、`swift-test.log`。没有新增测试；删除文件不在正式编译目标内，且正式源码哈希不变，因此未重复构建/安装 iOS 或重跑已知失败的唤醒套件。

清理前与交付前完整阅读 ANTI_SLOP 1–1599 行，并按以下适用范围复核：

| Audit | Result and boundary |
| --- | --- |
| 字体、颜色、布局、对齐、裁切、动效、图标及原生控件 | 产品与保留探针源码哈希不变；本次仅删除未接入产品的诊断界面，不引入新视觉元素或依赖。 |
| 内容真实性与实际功能 | 退役原因区分失败、环境不支持及不符合目标；未将删除失败实验写作录音功能通过。首次激活和待命的证据边界保留。 |
| 交互与辅助功能 | 没有新增或修改产品交互，本次不重新操作模拟器；既有 Text clipped、VoiceOver、真实录音/PiP 缺口继续保留，不宣称视觉验收通过。 |
| 网页布局、营销、装饰与图像规则 | 本次未创建网页、图片、营销组件或装饰；这些条目不适用。 |

## Scope and baseline

用户已分别批准 intent、spec、plan，并要求先在模拟器开发，再上实机。本文件记录实际实施证据；尚未达到完整第一版验收，不请求最终验收批准。
父分支检查点 `6044cef29ee9edff87d9aa843d1893a040e7dd1d`，子分支 `t3code/ios-voice-input-research`。当前改动未提交、推送或发布。
Xcode 27 / iOS 27 SDK，Air 模拟器 iOS 27.0。只使用命令级 DEVELOPER_DIR，未修改 xcode-select。

## Blocking feasibility result

用户“继续攻克”授权的 [系统入口独立实验](native-wake-research.md#retired-experiments)验证了已有 Live Activity 的真实系统按钮可冷/暖后台启动主 App，以及主进程终止后闲置五分钟再启动；三项通过，唤醒后固定文字实际插入原字段。已有活动时，直接点键盘里的同一 `LiveActivityIntent` 仍在扩展执行，冷/暖两项均失败。另一条 BG continued processing 在键盘中返回模拟器平台 unavailable；前台探针曾因注册失败后提交触发断言，修正为当前进程注册保护后显式 skip。正式 Release 已恢复、22 个正式 iOS 文件哈希不变、麦克风仍拒绝。系统岛需要预先创建活动和用户长按/点按，零录音实验不是完整语音闭环；批准产品方案和本文件 blocked 状态不变。

后续 [原生唤醒研究](native-wake-research.md)核对了构建元数据与 iOS 27 新 API：`.main` 已被提取，键盘路径实际仍在扩展执行；`isDiscoverable=false` 的内部 Intent 不能直接作为 Shortcut；`RunSystemShortcutIntent` 只支持 Widget 上下文。

用户授权的 [SwiftUI Link 独立实验](link-wake-experiment.md)现已完成：指定 Air 模拟器的真实键盘 Link 冷启动、后台可见激活和普通宿主 URL 对照 3 项全部通过，含匹配回调、真实进程/前台状态与系统手动返回原字段。实验零录音、只覆盖被忽略的项目副本，正常 Release 已恢复。它关闭首次可见激活的实验门槛，不能替代下面仍失败的普通键盘 Intent 路径，或证明后台免跳转、挂起恢复与长期保活；整个产品验证仍 blocked。

批准方案把 `Button(intent:)` 从键盘调度主 App 列为待验证假设。现在这条路径已在指定 Air 模拟器实际失败：系统选择 Utter 键盘成功，开始/结束按钮均被点击，命令写入真实 App Group；主 App 状态仍为 ready，命令没有被 take，键盘没有录音或结果。
进一步使用不带自定义按钮样式的纯原生 Intent 按钮作临时探针，结果相同。`.build-ios/intent-probe-runtime.log` 三条固定事件都为 `UtterKeyboard ... VoiceControlIntent entered extension`，没有 main app 事件。已有 `.main` / background / AudioRecording 元数据不改变这个实际调用上下文。扩展分支明确报错，没有在扩展偷偷录音。

可重复的完整门槛测试：`bash scripts/test-ios.sh D0E3FAA3-2961-4263-ACDA-BC5BD65BCC05 -only-testing:UtterSimulatorFlow/UtterSimulatorFlow/testKeyboardEndToEnd`。旧测试失败在结果插入；修正后必须先观察真实 recording 阶段才允许结束。最终测试退出码 65，失败在 recording 等待，见 `.build-ios/keyboard-gate-final.log` 和 `Test-UtteriOS-2026.10.04_17-44-51-+0800.xcresult`。探针 xcresult 为 `Test-UtteriOS-2026.10.04_17-24-10-+0800.xcresult`。临时探针按钮已删除，Debug 保留失败路径及不含输入内容的事件记录；Release 不显示未经验证的键盘录音按钮。

这是对当前实现/模拟器路径的否定证据，不能扩大为所有真机或所有公开机制都不可能。[Apple 的运行模式说明](https://developer.apple.com/documentation/appintents/configuring-the-runtime-behavior-of-your-app-intents)与[Widget/Live Activity 交互说明](https://developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities)介绍系统调度入口，并没有保证普通键盘中的按钮可调度包含 App。[开发者论坛的同类问题](https://developer.apple.com/forums/thread/843118)也没有 Apple 官方解法回复，只能作为其他开发者遇到此限制的线索。
按批准 spec 的“公开机制失败时提交失败证据并回到 intent 调整范围”，停止扩充模型/云端与产品发布。下一步需要重新设计启动入口并评审；不能把每次跳转、闲时持续录音、隐藏 PiP 或模拟状态当作原目标通过。

## Simulator continuation

用户“试一下”授权的独立待命候选实验已记录在 [standby-experiment.md](standby-experiment.md)。最终普通后台固定文字 Start/Stop/单次插入通过；视频通话与普通视频 PiP 均因指定 Air 模拟器的能力查询 false 而跳过。没有修改批准的产品方案，正常 Release 已恢复，系统调度与真机保活门槛继续 blocked。

用户随后明确要求“继续在模拟器完成”。本轮补齐批准计划内可以独立验证的模拟宿主、桥协议和原生交互，保留上面的系统调度失败结论。
显式 `--bridge-diagnostic --simulator-bridge-host` 在 Debug 模拟器中启用前台命令宿主；真实 App Group 文件、租约、Session、词典、消费回执与 `insertText` 均运行实际代码，只有输入是固定 synthetic text。宿主只在 active scene 任务中运行，每次最多 600 秒/128 条命令；外层及每条命令前重验取消和边界。设备和 Release 编译不包含这个宿主。它绕过了系统 Intent 调度，不能作为无需跳转或后台唤醒的解决方案。

`.build-ios/simulator-flows-final.log` 的 9 项独立 UI 流程全部通过（0 失败，455.982 秒，原 xcresult `Test-UtteriOS-2026.10.04_19-14-49-+0800.xcresult`）。新增覆盖：键盘单次插入、删除/空格/Return 提交、插入后主 App 结果卡清除、录音期间字段切换取消、完成后旧字段结果拒绝、词典替换和删除、真实复制粘贴、系统 Settings 入口。失败的原生键盘门槛被显式排除，不能称完整验收套件通过。

独立验证者发现两项实际问题并完成修复：主 App 的旧结果缓存现在检查消费/到期，每秒监测，恢复前台及复制前重验；每次键盘 Start 先撤销旧租约，再创建新 UUID，旧 Stop/Cancel 无法控制同字段的下一次会话。未确认的 pending Start 取消会本地撤销租约。
修复后的传输与字段切换在 `.build-ios/lease-isolation-tests.log` 再次通过，但同轮新 async fault 测试因 XCTest 要求主线程而中断，该轮整体退出码 65。修正测试的 `@MainActor` 后单项 `.build-ios/delayed-cancel-final.log` 退出码 0，47.210 秒；归档 `.build-ios/evidence/delayed-cancel.xcresult`。
故障宿主在 8 秒后用新命令 ID/到期时间、旧 lease 重发 Cancel。`.build-ios/lease-fault-runtime.log` 的投递事件是 19:28:13.808；第二次会话 recording 断言为 19:28:09.336，停止点按为 19:28:19.466。确实在第二次录音期间投递，状态仍 recording，随后实际插入成功。日志不含输入正文。

Xcode 后续测试会自动清理旧 xcresult；文字日志与已导出截图保留，新的关键结果另存到 `.build-ios/evidence/`。旧 xcresult 名称用于对应原始运行，不能保证仍在 DerivedData 中。

`.build-ios/settings-flows-final.log` 的完全访问关闭编辑、语言切换失效/重新启用、中文 Session 三项通过（85.964 秒，0 失败、无 skip）。关闭权限时开始动作不可用，实际空格、删除和 Return 仍工作；随后通过系统 Settings 恢复原来的完全访问 ON，再跑键盘传输通过。授权范围仍只限指定模拟器，麦克风保持拒绝。

稳定主屏截图 `accessibility-activity-attachments/FC4B52E5-25C6-49BD-898C-D1A52266F56A.png` 已确认 compact 灵动岛的麦克风与 Utter。`native-ui-final.log` 的 `testLiveActivityStopAndCancel` 单项通过（48.241 秒）：在 Springboard 长按展开，实际点按结束/取消，主 App 分别到 result/cancelled，结束后的两张主屏截图都没有活动。`native-ui-final-attachments/3E71C311-37BB-48E7-B2BB-F894ABEE4F82.png` 展开态与 `DDDE1529-93AD-4278-9E50-48941C2EAA0A.png` 取消后画面已检查。会话输入仍是合成文字；这些结果证明系统 Live Activity 的呈现/停止入口，不证明普通键盘能唤醒主 App。主屏现已显示复用的真实 Utter Icon Composer 图标。

最大字号 `max-toolbar-final.log` 的原生标题/词典导航通过（73.194 秒），短 inline “Dictionary” 标题完整，没有之前的 “Personal dic…” 截短；`max-keyboard-final.log` 的真实键盘传输/删除/空格/Return 通过（101.042 秒）。键盘状态、动作与编辑标签在最大字号实际可见、换行。所有文字都是固定测试输入，不把它当识别质量证据。随后继续针对原生辅助功能审计修复，最终代码的复验另列如下。


## Final simulator UI checks

真实 UI 审计发现并修复了键盘上缘模糊、词典导航标题截短、低对比度文案，以及三个标签的字号支持问题。最终使用可缩放原生 UILabel，明确 UIFont 语义字号与 SwiftUI 字号环境、按可用整行宽度计算多行高度；导航标题统一 inline，图标复用父分支的真实品牌资源。没有屏蔽 audit type 或忽略问题。

`native-label-max-final.log` 的原生标签/导航最大字号测试通过（73.086 秒）；截图目录 `native-label-max-final-attachments` 已检查标题、词典两行入口和完整导航。随后缩短最大字号下贴近右沿的英文输入框提示，最终 `short-field-max-final.log` 再次通过（73.126 秒）；归档 `.build-ios/evidence/short-field-max-final.xcresult`，`short-field-max-final-attachments/CAA063A8-F5F0-4FE2-9590-250EC946F83F.png` 中两个提示与词典/清理多行标签完整。字号已恢复 large。`frozen-ui-regression.log` 的词典替换/删除、丢弃/清理、键盘插入/编辑三项均通过；`short-field-audit.log` 的字段切换取消/旧结果拒绝单项通过（56.826 秒）。

**完整辅助功能审计仍未通过。** `short-field-audit.log` 中审计本身失败（26.522 秒），只剩主表单一项 `Text clipped`，没有对应 element；键盘展开后的第二次审计没有报告。该整轮退出码仍为 65，不能把同轮字段测试通过算成全轮通过。无过滤最终原始报告归档 `.build-ios/evidence/short-field-audit.xcresult`，说明与截图在 `short-field-audit-attachments`，截图 `09ACAE7F-FC66-4B6A-97D1-515F74F28862.png` 已确认属于短提示最终源码。旧 `accessibility-final` 归档属于之前 label-width 那轮，不是最终短提示报告。实际最大字号可滚动/可操作不替代这一未解决报告；未归因为 SDK，也未模拟 VoiceOver 朗读通过。

最终 Release 在同一 Air 模拟器正常安装、无参数启动，未启用合成宿主。实际主页面和键盘截图 `.build-ios/release-main-visible.png`、`.build-ios/release-keyboard-visible.png` 已检查：标题/说明可读，诊断入口不存在，未启用时键盘显示真实关闭状态和基本编辑，没有实验开始/结束按钮；实际点按换行后键盘收起。没有点按启用或授予麦克风。最终保留正常 Release、light / large、完全访问 ON 与麦克风拒绝状态，仅限此前批准的模拟器。此项是发布界面与隔离检查，不是语音闭环通过。

## Completed evidence

| Check | Result | Reproducible evidence |
| --- | --- | --- |
| 共享架构与原生 bundle | Simulator Debug / Release 构建通过 | `bash scripts/build-ios.sh --simulator` 与 `bash scripts/build-ios.sh --simulator Release`，App、键盘、Live Activity；键盘只链接 Foundation bridge，不挂载推理图。最终 Release `.build-ios/simulator-release-handoff.log` 退出码 0；共享原生 Icon Composer 资源已实际编译。Debug 最终源码由最后两轮 UI 测试重新编译。 |
| iPhoneOS SDK | 无签名编译通过 | `bash scripts/build-ios.sh --device`，`.build-ios/device-handoff.log` 退出码 0；不是签名安装或 Air 运行证据。 |
| App Group 实际容器 | 本地签名模拟器可用 | 无签名包首先明确报错；标准模拟器本地签名后主 App 取得真实容器，无伪造沙盒替代。 |
| 完全访问授权 | 仅指定测试模拟器已开启 | 用户明确批准“仅此测试模拟器”；通过系统 Settings 为上述 Air 模拟器中的 Utter 键盘开启，没有扩展到真机或其他设备。麦克风保持拒绝，未采集真实音频。 |
| 独立模拟器 UI E2E | 9 项整轮通过，新增故障单项通过 | `.build-ios/simulator-flows-final.log` 与 `.build-ios/delayed-cancel-final.log`；主 App、真实自定义键盘和两个输入框、词典替换/删除、复制粘贴和 Settings。仅固定 synthetic input；不包含失败的原生键盘门槛。 |
| 深色 / 最大辅助字号 | 指定交互通过，非完整矩阵 | `.build-ios/dark-large-session-tests.log` 的 Session 流程退出码 0，xcresult `Test-UtteriOS-2026.10.04_18-00-51-+0800.xcresult`。清除流程通过于 `.build-ios/dark-large-ui-tests.log`；该次整体退出码 65，因为结果预览尚未滚入 lazy Form 的测试查询，补充真实滚动后单独重跑 Session 通过。麦克风拒绝流程通过于 `.build-ios/dark-large-ui-before-scroll-fix.log`，该早期整轮后续失败并中止，不能称整轮通过。模拟器外观与字号已恢复原来的 light / large。 |
| 桥协议故障场景 | 通过 | `bash scripts/check-ios-bridge.sh`，最终 `.build-ios/bridge-handoff.log` 退出码 0：真实共享文件的双实例，重复命令、目标切换、消费去重、物理清理、过期、generation、损坏及消息大小；消费目录写入失败不产生消费回执，恢复后可正常消费，新实例不重放已消费结果。 |
| SDLC 与 basic | 通过 | `bash scripts/sdlc-checks.sh`；使用 Xcode 工具链执行 `bash scripts/ci-basic-checks.sh`，最终日志 `.build-ios/sdlc-handoff.log`、`.build-ios/basic-handoff.log` 均退出码 0。首次 basic 默认 Command Line Tools SDK 与编译器不匹配，切换命令级工具链后通过。 |
| 现有 Swift 测试 | 通过，硬件/模型项跳过 | `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`，最终 `.build-ios/swift-handoff.log` 退出码 0；XCTest 合计 1010 项、18 项跳过、0 失败，其中 OpenType 488 项；另有 1 项 SwiftTesting Model upgrade policy 通过。跳过项不能作为设备能力证据。 |
| 桌面 release-style App | 构建与产物检查通过 | `bash scripts/build-app.sh --app-only --sign=-`，`.build-ios/macos-release-build.log`，Metal 资源和产物验证通过。仅工作区内开发验证包，明确主动采用本地 ad-hoc 身份，不是配置签名失败后的降级；未安装、分发或 Apple 公证。 |
| Intent 元数据 | 静态复核通过 | 主 App 和键盘含 VoiceControlIntent / StopVoiceIntent；AudioRecording / SessionStarting 协议、后台模式、main 执行目标及不主动打开 App 元数据。不能单靠元数据证明执行成功。 |
| Release / 设备测试宿主隔离 | 最终构建与二进制检查通过 | `.build-ios/handoff-binary-isolation.log`：Release 的三个 Mach-O 不含诊断入口、固定样例、Intent 探针、模拟宿主或延迟取消事件；iPhoneOS Debug 的九个 Mach-O 不含模拟宿主/故障入口，设备 Debug 仍允许显式合成诊断。源码分别由 DEBUG 与 targetEnvironment(simulator) 隔离；本地化说明仍是资源，资源存在不等于入口可用。 |

构建和检查原始日志保留在未跟踪的 `.build-ios/`。根 Package.resolved 保持父分支锁定版本。模拟器开发不需要团队、证书或账号密码；iPhoneOS 无签名编译与真机安装分开记录。

## Independent review

按 review-policy 的 High 风险要求，使用全新上下文的独立只读验证者。验证者阅读批准文档、实际未跟踪源码与差异，独立执行桥故障检查（退出码 0），未修改源码或批准阶段。
已发现并修复：字段切换后旧 busy 状态无恢复、跨 await 的并发开始遗留 Live Activity、SpeechAnalyzer 取消继续 fallback、词典规范化拒绝添加却清空用户输入。验证者复核这些修复后无剩余可操作代码发现。
第二轮关闭诊断/正常启用并发覆盖 Runtime 的问题：两个入口共用 activation 互斥、取消和排空。实际词典输入测试还复现 UIKit 文档关闭后非空声明返回 nil 的 UUID 桥接崩溃；使用公开 getter 的可空对象读取，失效时拒绝租约，真实回归已通过。独立复核的 SDLC、脚本语法、plist/strings/pbx lint 和模块边界回归全部通过。
本轮新的全新上下文只读复核发现主 App 旧结果缓存、旧取消指令及模拟宿主批次边界，均已修复；故障投递的实际时间另行核对。模拟器测试宿主不改变产品调度结论。
最终只读复核独立检查 UILabel 的公开字号 API、原生导航与权限动作、最大字号/岛上操作截图，未新增可操作代码发现；指出旧辅助功能附件与最终日志不对应，已分别归档并更正文档。最终 Release 三个及 iPhoneOS Debug 九个 Mach-O 均经验证者独立扫描，测试入口隔离与新构建时间匹配。辅助功能剩余失败没有被豁免。
最终复核结论已收到：没有新增可操作代码或工程发现，已修复项维持关闭；确认最终构建、1010 项 XCTest / 1 项 SwiftTesting、basic、桥检查、SDLC 与 lint 的真实证据，并保留 blocked。验证者也完整复读 ANTI_SLOP；没有修改源码、控制模拟器、运行构建或代替用户批准。
静态数据图确认移动 workflow 使用 returnedText，不提交历史；无远端客户端/凭据服务挂载；共享容器不包含录音、词典或模型。录音成功/取消/失败清理仍需实际麦克风验证。

## Current evidence gaps

- 键盘到主 App 原生调度门槛失败；前台模拟宿主已验证实际插入、字段切换与结果清理，但不能代替系统调度或真实录音闭环。
- 真机安装、本地语言/混说/飞行模式、后台十次启动、麦克风停止、五分钟闲置、PiP 两种顺序、自动锁屏与资源/热状态没有 Air 证据。
- 权限撤销、来电/Siri、蓝牙、锁定和真实扩展崩溃消费边界仍需完整矩阵；消费写入失败与新进程实例去重已用真实文件故障注入验证。
- 孔夫子/Qwen 候选、Foundation Models 与云端可选路径属于门槛之后的阶段，尚未挂载；当前模拟器里不展示未经验证的模型入口。
- Live Activity compact、展开态、岛上结束/取消及结束后移除已有截图与实际点按证据。锁屏呈现/操作、权限关闭和真实录音中的生命周期仍待验证。旧 activity UUID 的 descriptor 日志保留，但不能用旧孤立错误否定本轮实际显示，也未将其根因归于系统。
- 语言切换、中文 Session、完全访问关闭编辑/恢复、复制粘贴、词典添加/删除、Settings 入口和正常 Release 可见界面已有实际交互证据。VoiceOver 朗读/焦点仍需检查。完整原生辅助功能审计的最终结果单独记录；字号实际增长不能自动推定审计通过。

## UI audit and rollback

实施前及本次收尾已完整复读 ANTI_SLOP（1–1599 行）。逐项检查后，按适用规则分组记录如下；“通过”只覆盖所列源码/运行证据，尚有缺口的项不作最终 UI 验收。

| Applicable rule | Audit and evidence |
| --- | --- |
| 原生组件与一致的视觉语言 | 批准 spec 明确使用原生表单与系统控件，优先于营销页面的签名字体/hero 默认。实际采用 Form、NavigationStack、系统字体与语义颜色；系统 globe 表达键盘切换；复用既有 Utter 原生图标，无引入图标包、品牌拼贴或另造主题。少量 UILabel 包装只负责明确的字号/多行布局，不重写原生表单与按钮。 |
| 字体、对比与颜色连续性 | 浅深色早期截图及最终 `native-ui-final-attachments`、`short-field-max-final-attachments`、`max-keyboard-final-attachments` 和正常 Release 两张截图已检查。字体使用系统语义字号，header/footer/按钮使用可读的系统 label 颜色；岛上白字与灰色动作实际清楚。停用 Picker/按钮及空输入提示采用系统样式；未增加紫蓝渐变、奶油底、彩色光晕、纹理覆盖正文、按钮阴影或背景网格。最大字号截图的 recording 是明确测试模式中的合成 Session，不是麦克风录音证据。 |
| 默认可见、无假内容 | 无依赖动画显现的文字、透明模块、假视频、浮动装饰、计时促销、虚构客户或 UI 模型图。只按真实状态显示动作；准备中不提供可用的结束按钮，结果状态只表示生成。Debug 样例由显式参数与说明开启，Release 排除入口。 |
| 边缘、裁切、对齐与留白 | 原生 Form 保留系统安全区域与边距；键盘采用 16 pt padding 和 ScrollView，移除结果的行数截断，globe 44 pt。浅深色截图未发现所检查正文/按钮被固定高度切掉；最大字号和横屏通过实际滚动执行结束/取消/停用。最大字号键盘的状态/动作/编辑标签实际可见并可点按；词典长导航标题已缩短并采用 inline。长结果/锁屏矩阵仍缺证据，原生自动审计报告逐项保留。 |
| 交互必须真实可用 | 已实际点按并验证 Session 结束、结果预览、再次开始、取消、停用、丢弃、清理确认、词典导航/输入与未启用禁用状态。键盘调度失败有断言和固定事件证据，Release 隐藏该实验动作；基本编辑、复制/原生粘贴、词典增删与设置入口均已实际执行。compact/展开态、岛上结束/取消和移除已验证，锁屏操作仍未验证。 |
| 文案与本地化 | iOS 状态/操作/错误走共享 L 与中英文资源，录音系统提示有 InfoPlist.strings。错误明确指出麦克风关闭、当前后台路径失败等用户可理解的状态；未把 App Group 文件名、Runtime 或实现细节放入正常用户流程。词典添加拒绝时保留输入。英文交互及中文 Session/取消已运行；键盘与 Live Activity 的系统 locale 为中文，并有真实截图。不是完整双语言验收矩阵。 |
| 动态字号、横屏及辅助功能 | 深色最大辅助字号 Session/清除、浅色横屏取消、最终最大字号导航及键盘编辑通过；有明确 header trait、按钮标签与阶段 accessibilityValue。字号/对比度报告已修复，但完整原生审计仍有一项未定位裁切；不能列为完整辅助功能通过。VoiceOver 尚未实际遍历，不能以标签存在代替验证。 |
| 动效与静态内容 | 未加循环浮动、hover 跳动、揭幕、装饰填充动画或自制玻璃效果。使用系统导航与控件反馈，内容不依赖动画结束才存在；没有自定义动效需要 reduced-motion 分支。 |
| 不适用的页面规则 | hero、定价/比较列、testimonial、邮件表单、logo wall、页脚大字、网站导航、图像拼接、CSS/SVG 插画与营销签名场景本次均未创建；没有为满足清单而加入品牌装饰或新依赖。原生 App/键盘/Live Activity 的可用性、可读性与交互要求仍适用。 |

当前结论为独立模拟器桥交互、恢复流程与灵动岛操作已有通过证据；完整语音键盘仍被原生启动门槛阻挡，辅助功能/设备证据的未通过项没有转成最终 UI 验收。

回滚仅撤回本次 iOS 子分支改动，不回退父重构或迁移桌面数据。手机内先停用会话，按用户选择清理本机数据后移除键盘/App；当前没有云端凭据或服务需要撤销。没有 TestFlight、App Store、PR 或生产发布。

## 2026-10-05 iPad mini handoff: installed, launch awaiting device trust

User authorized continuing thread `3bb37002-358c-4526-b0d1-0efc5dac8e70` on the connected iPad mini (A17 Pro). This is preliminary iPad validation, not acceptance of the iPhone Air matrix.

- The device is connected. The configured Apple Development identity is valid outside the restricted shell sandbox.
- Re-running the existing signed Debug build with Xcode provisioning updates succeeded. The app and both extensions passed embedded validation; the app signature includes the required `group.com.ichendev.utter.ios` entitlement. `codesign --verify --deep --strict` passed. No ad-hoc fallback was used.
- `devicectl device install app` succeeded for `com.ichendev.utter.ios`. The subsequent launch was denied by SpringBoard with Security / FBSOpenApplicationErrorDomain code 3: invalid signature, inadequate entitlements, or profile not explicitly trusted. Local signature verification passed; the user was asked to complete developer trust on the iPad before retrying.
- Existing device UI-test runner `build-for-testing` succeeded. No UI tests have run on this iPad yet. No microphone was requested or audio captured in this handoff.
- Product source and project semantics were not changed. A temporary capability declaration was removed because the build had already succeeded without it. Xcode-only project reformatting was restored after semantic plist equality verification.
- SDLC check passed. `swift test` passed: 488 XCTest cases, 18 skipped, zero failures; one Swift Testing case also passed. The initial basic check used the default command-line toolchain and failed on sandbox cache access; it was rerun with the required Xcode developer directory outside the sandbox and passed.
- Evidence: `.build-ios/ipad-preflight/handoff-signed-build.log`, `handoff-build-tests.log`, `handoff-sdlc.log`, `handoff-basic.log`, and `handoff-swift-test.log`.

Runtime and visual audit remain unexecuted: app launch, actual controls, layouts, PiP support/coexistence, background microphone reactivation, recognition and keyboard insertion all require the trust step and actual device execution. ANTI_SLOP was read completely before work; no interface edits were made and no visual acceptance is claimed. Verification remains blocked, not approved. The installed development app is retained for continuation; nothing was pushed or published.
