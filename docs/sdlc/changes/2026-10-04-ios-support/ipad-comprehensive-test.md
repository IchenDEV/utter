# iPad mini comprehensive physical-device validation — 2026-10-05


## Debugger-free standby research (2026-10-06)

用户“继续研发”授权沿既有三门槛继续独立实验。外部 devicectl 命令安装签名探针，新脚本 `scripts/test-ios-session-idle.py` 负责启动与读取日志，不启动 XCTest、不 attach LLDB、不禁用自动锁屏；前台确认 PID、类别、准备状态后切同一 Safari，15/45/85 秒读取 App Group 日志，85 秒读完才激活探针。源代码仍为 Debug 探针；这不是脱离开发连接的发行版/长期功耗测试。

| 无采集、无 PiP 对照 | PID | 实际后台时长 | 单调时钟最大执行空档 | 第 15 / 45 / 85 秒最后 ticks |
| --- | --- | --- | --- | --- |
| 无音频激活，SoloAmbient | 2508 | 85.064 秒 | 77.934 秒 | 18 / 18 / 18 |
| playback + mixWithOthers，激活调用成功 | 2512 | 84.812 秒 | 78.006 秒 | 19 / 19 / 19 |
| playAndRecord + mixWithOthers，激活调用成功 | 2517 | 85.206 秒 | 78.366 秒 | 19 / 19 / 19 |

三组恢复前后 PID 相同，恢复后的 in-memory ticks 为 25/25/24，长空档来自 serve 循环的单调时钟，不仅是文件写入间隙。初始 PID/前台/flags/category 与 launch.json、后台 appState=2 已离线复核。`summary.json` 中 observedSeconds 与 backgroundTailAge 在恢复后计算，不当作第 85 秒值；Mac/iPad 时钟未校准，journalAge 仅辅证。锁状态快照仅报告 passcodeRequired=false、unlockedSinceBoot=true，不宣称全程屏幕状态验证。

证据为 `.build-ios/session-idle/{control,playback,record}-launch.json`、`-initial.json`、`-background-{15,45,85}.json`、`-resumed.json` 和 `summary.json`，驱动输出在 `session-idle-run.log`。本轮三组没有音频引擎、tap、Recorder 或播放；capture 默认诊断值不证明系统全局麦克风状态。结论是这些具体无 I/O 会话没有保持连续执行，不能将旧 XCTest 内普通后台 75 秒也持续执行的结果外推为日常可用待命，也不能指名系统暂停原因。

独立验证者发现 continuous ticks 字段绕过 journal 指纹节流，已排除 ticks/gap/seconds（后加 recorderTime），保留状态变化即时写与 5 秒周期。并修正 session-only + no-audio 组合的停用：根据成功激活记录仍尝试 deactivate，不遗漏会话。驱动补 PID/类别/前台/后台断言并保留原始异常与清理失败。

### Source cross-check

- Apple [playAndRecord 文档](https://developer.apple.com/documentation/avfaudio/avaudiosession/category-swift.struct/playandrecord)说明类别与混音，不承诺无采集待命。
- [Dictus 的 UnifiedAudioEngine](https://github.com/getdictus/dictus-ios/blob/main/DictusApp/Audio/UnifiedAudioEngine.swift)将 idle 描述为引擎继续处理缓冲但丢弃数据；[VocaPhone 的 AudioRecorder](https://github.com/VocaHQ/vocaphone/blob/main/ios/VocaPhoneApp/Audio/AudioRecorder.swift)的 startStandby 仍启动带输入 tap 的 engine。[VivaDicta 的作者说明](https://github.com/n0an/VivaDicta/blob/main/documentation/Hot-Mic-Audio-Prewarm-Architecture.md)同样采用持续输入。源码读取记录在 `.build-ios/session-idle-research/`；没有复制这些实现或引入依赖。不能用“不保存”代替“麦克风关闭”。
- [Apple DTS 对后台激活的答复](https://developer.apple.com/forums/thread/816408)限定普通录音 API，并说明通话 API 属于通信架构，不能移作其他用途。本项目不建设伪通话保活。

### Paused-recorder follow-up

无 I/O 三组失败后，测前台约 3 秒录音 → [AVAudioRecorder.pause](https://developer.apple.com/documentation/avfaudio/avaudiorecorder/pause()) → 后台 85 秒。只用已授予权限，录音文件 complete 保护；录音器最多 4 秒，开始/暂停须前台，若提前进入后台且仍采集立即停止。按实例及准备代次清理，Stop 在等待前台时也立即撤销准备，旧任务不能之后开麦或删除新录音；Mac 在当前 PID 正在录音的日志窗口确认后才播固定样本。暂停后 isRecording=false/currentTime 不推进只是录音器状态，不能独自满足系统闲时麦克风门槛。

**实测候选失败，未接入产品。** `.build-ios/session-paused-run.log` 与 `session-idle/summary-paused.json`：PID 2548 从 launch、初始前台、三个后台采样到恢复均一致；录音器前台暂停成功，currentTime=3.149625 秒。实际后台 84.782553 秒，恢复时测得最大单调执行空档 82.762131 秒；第 15/45/85 秒最后 ticks 都是 1，恢复后为 8。三个后台快照 appState=2、isRecording=false、录音时间完全不变。脚本 exit 0 表示观测与断言完成，不表示待命通过；没有把 suspended/停止原因归为某个系统机制。

Mac 播放开始 1791222390.537，录音状态快照 1791222390.228，暂停状态快照 1791222393.344；跨设备时钟未校准，不据此宣称精确同步或固定内容完整录入。暂停期间只复制了探针自己的 CAF 到 `session-idle/paused-recorder.caf`；afinfo 为 49843 帧、约 3.115 秒，ffmpeg 非零信号 mean=-31.8/max=-16.4 dB，但未 finalise 的副本有末包警告（`paused-audio-inspection.log`）。没有做 ASR/识别质量通过声明。`completedFrames=0` 仅指现有 MobileCapture 引擎诊断，本轮确实有 AVAudioRecorder 前台录音与 1 段 Mac 播放，不能记成零录音。

首轮 journal 尚未创建，copy 返回指定文件的 CoreDevice 7000；驱动只重试这个精确错误，其他错误仍失败。第二轮准备任务发生在 UIKit inactive，前台 guard 中止；增加最多 2 秒可撤销的 active 等待后成功运行。两次前置失败都未播放固定语音，不计待命失败/通过；证据保留 `session-paused-startup-race.log`、`session-idle/paused-startup-race-priming-0.log` 与 `session-paused-inactive-start/`。独立复核在新增等待中找出 Stop 未撤销准备的缺陷，先补 token 再构建安装，未运行那份有缺陷的中间构建。

### Research closure and applicable visual audit (2026-10-06 01:50)

- 四组均未证明连续后台待命；paused 组无需为了否定候选再跑长时、视频或键盘矩阵。没有改变原定免跳转、闲时麦克风关闭、外部视频 PiP 共存三项接入门槛，也没有宣称所有公开实现不可能。
- `--standby-cleanup` 后，`session-idle-final-group-files.json/.log` 确认设备上三个指定诊断文件不存在；`session-idle-final-tmp-files.json/.log` 确认设备上的 `standby-paused-recorder.caf` 不存在，本地证据副本仍保留。保留其余既有临时文件、模型和设置，没有删除整个 tmp/共享目录。进程终止释放旧录音器，本轮不把新进程的 cleanup 记录当作旧录音器正常 stop 的完整 API 轨迹；没有对系统全局麦克风查询的声明。
- `session-idle-restored-signature.log` deep/strict 验签退出 0；01:49:56 `session-idle-restored-install.json` 覆盖恢复正常 Release，未卸载；随后 01:50:20–37 XCTest 按 `UtteriOS_iphoneos27.0-arm64.xctestrun` 的 `__TESTROOT__/Release-iphoneos/Utter.app` 再部署执行回归；01:51:26 `session-idle-restored-launch.json` 无参数正常启动成功。中间 XCTest 再部署导致安装目录 CE54… → 1186… 变化，不将 install/最终 launch 当成完全相同的安装实例。未新建 Safari 标签或 LAN 服务，仅激活既有 Safari。
- `session-idle-restored-release.log/.xcresult`：最大字号侧栏与正常启动 16.779 秒通过，0 段语音。实际查看 `session-idle-restored-release-attachments/manifest.json` 对应两张新截图；正常中文语音关闭、无可见 PiP 或橙色麦克风指示，最大字号三个侧栏标签完整。后一张主内容处于侧栏遮罩下，不能证明完整 Dynamic Type、裁切或辅助功能通过。
- 独立只读验证确认 PID/暂停/后台空档结论，明确脚本成功不等于候选成功、非零信号不等于固定内容识别通过。产物仍为原正常 Release，键盘录音继续禁用；未提交、推送或发布。
- `session-idle-final-sdlc.log`、`session-idle-final-basic.log` 均通过，diff 空白检查与当前 Python 编译通过。`session-idle-swift.log` 为 488 XCTest、18 跳过、0 失败，另 1 Swift Testing 通过；这些 macOS 测试不编译独立 iOS 探针。暂停组最终修正后的 `session-paused-cancellable-build.log` TEST BUILD SUCCEEDED，随后用该签名 Debug 执行真机观测；未运行缺少等待撤销保护的中间构建。

本轮开始与收尾已完整重读 ANTI_SLOP；适用项审计如下，既有产品辅助功能问题继续保留：

| 适用项 | 本轮实际检查及边界 |
| --- | --- |
| 原生布局、层级、对齐与留白 | 探针沿用系统 Form，无新增产品布局；恢复截图的中文主操作、说明及侧栏可读。最大字号真实打开侧栏，三个标签均可达；遮罩后的主内容不计完整视觉通过。 |
| 字体、语言、颜色与图标 | 沿用系统语义字体/颜色与 SF Symbols；诊断文字区分有限前台采集和无采集对照，不把 paused 说成全程无麦克风。正常 Release 无实验文案，恢复中文界面已查看。 |
| 真实交互、状态与退出 | 真机 CLI 激活/切换/同 PID 恢复及日志断言实际执行；没有声称点按了探针的每个按钮。Release 的侧栏打开与无参数启动有 XCTest 实际交互；失败候选、前置失败及退出清理分别记录。 |
| 音频、隐私与数据归属 | 仅前台约 3 秒、硬上限 4 秒；暂停后台日志不推进录音时间，未把录音器状态替代全局麦克风证明。设备上自己的音频和三份诊断已删，本地证据副本保留；保留用户既有文件，无私有 API、静音循环、持续闲时采集或强制常亮。 |
| 辅助功能与产品完整性 | 只复验大字号侧栏/正常启动。此前 11 条产品辅助功能发现、完整 VoiceOver/锁屏/功耗矩阵及探针 delegate 隔离警告仍是未通过项；未隐藏或以本轮通过替代。 |
| 不适用项 | 未改网页、营销/定价/评价、字体资源、插画、动画、悬停、品牌或完整产品导航；未引入依赖，不为清单增添无关界面。 |

## PiP coexistence causal isolation (2026-10-06)

用户要求继续解决共存，三项门槛不变。本轮只运行独立状态探针，不请求麦克风，不播放固定语音，不修改产品 Release。

| 实验 | iPad 真实结果 | 原始证据（`.build-ios/`） |
| --- | --- | --- |
| 只激活 playback + mixWithOthers，没有 Utter PiP | 52.563 秒通过；Safari PiP 7.5 → 19.6 秒，paused=false。 | `pip-coexist-audio-control.log/.xcresult/.json` |
| 视频先开；Utter video-call PiP 不显式操作音频会话 | 48.403 秒失败；Safari 7.1 秒 PiP 播放变为 8.1 秒 inline、paused=true。Utter journal noAudioSession=true、active=true、engineRunning=false。 | `pip-coexist-noaudio-before.log/.xcresult/.json` |
| Utter video-call PiP 先开，不显式操作音频会话；再开视频 | 48.603 秒失败；Safari 7.1 → 17.2 秒继续播放，但 Utter 返回时 resumedPiP=inactive、phase=stopped。journal 在后台先记录 did-stop-before-cleanup（stopping=false、active=false、suspended=false、voice=ready），随后才是 stop-requested。这不是应用先主动关掉仍可用的 PiP。 | `pip-coexist-noaudio-after.log/.xcresult/.json` |
| 普通 sample-buffer 内容源，视频先开 | 48.623 秒失败；普通 Utter PiP 确实启动，Safari 7.6 秒 PiP 播放变为 8.3 秒 inline、paused=true。该组使用原基线播放会话，非 NoAudio 模式。 | `pip-coexist-sample-before.log/.xcresult/.json` |
| 普通 sample-buffer 内容源，Utter 先开 | 49.757 秒失败；修正按钮遮挡后先确认 inline 2.8 秒播放，再确认 PiP 6.9 → 17.4 秒持续播放；回到 Utter 为 inactive / stopped。 | `pip-coexist-sample-after-clear.log/.xcresult`；不使用本轮重置后的 JSON 作因果证据。 |

已经排除“只删除我们显式音频激活就能共存”这一修复。这个结论不表示 AVKit 内部没有音频会话行为，也不能泛化为所有公开 API 绝无可行方案。普通内容源的冲突说明现象不只出现在 0.1pt 视频通话窗口。没有自动重抢 PiP、恢复外部播放器来掩盖暂停，或放宽三项门槛。

Apple 的 [suspended 文档](https://developer.apple.com/documentation/avkit/avpictureinpicturecontroller/ispictureinpicturesuspended)只描述暂停、屏幕外和可能自动恢复，不保证后台执行。本轮反向实际观察到的是 stopped；不能沿用“可能 suspended 仍可服务”的假设。公开 [sample-buffer 内容源](https://developer.apple.com/documentation/avkit/avpictureinpicturecontroller/contentsource-swift.class/init(samplebufferdisplaylayer:playbackdelegate:)) 是不同内容源，不是多 PiP 权限。

`pip-coexist-sample-after` 首次因 PiP 遮挡播放按钮而未实际播放（inline 0.0、paused=true），不能计为共存失败。已将固定测试页按钮放在输入框下方，加入先确认播放再开启 PiP 的断言；重跑截图确认按钮不再遮挡。`sample-after-clear` 清理阶段未先激活 Safari，误点探针使 journal 重置；该 JSON 不证明事件顺序，清理前截图和 AX 状态仍有效。已修正 host.activate、前台状态及目标 UUID 核对，独立复核要求关闭后以 TabBarTab/TabDocument 两种 AX 形态检查残留。

独立只读复核已修正两个观测缺陷：didStop 先核对控制器实例再记录；用真实 resumedPiP 区分 suspended/inactive，不只读取 phase。普通源停止成功后会清除画面、停止时间基准并移除 layer；探针的 delegate MainActor 编译警告仍保留为生产接入限制，没有通过 preconcurrency 隐藏。


### Final isolation rerun and applicable visual audit

`pip-coexist-cleanup-retest` 在 50.969 秒再次复现普通源反向失败：inline 2.9 秒 → PiP 7.0 → 17.5 秒，paused=false；Utter inactive/stopped。该组随后运行清理测试，会覆盖 journal，故只使用 log/xcresult 的清理前状态证明本次失败，不拿最后 JSON 推导 didStop 时序。系统先停止的时序证据仍来自独立 `pip-coexist-noaudio-after.json`。

本轮开始和收尾均完整重读 ANTI_SLOP。适用项逐项审计：

| 适用项 | 实际检查与限制 |
| --- | --- |
| 原生结构、层级与留白 | 独立探针沿用 Form；测试页使用明确的视频状态、文本框和原生按钮。实际 PiP 遮挡播放按钮已修正，重跑截图确认三个按钮可见，真实点按后时间推进。未新增产品布局或装饰。 |
| 字体、颜色、图标、可读性 | 系统字体/语义颜色；检查最新普通源状态截图，inactive 与停止状态可读。外部 PiP 按系统规则遮住探针顶部，不把顶部遮挡视作整屏视觉通过；诊断英文不进入产品。 |
| 交互与反馈真实性 | 先证明播放，再检查 PiP、paused 与 currentTime；返回读取真实 active/suspended/inactive。失败明确保留，遮挡未播放轮次不算共存证据；没有伪造恢复或成功反馈。 |
| 数据、隐私与退出 | 本轮 0 段固定语音、无录音动作。清理仅按已记录 UUID，并先确认目标活动标签；无批量关闭、无用户数据删除。停止清除普通源 timebase/layer；临时服务和探针诊断需以收尾日志确认。 |
| 辅助功能与完整产品验收 | 本轮不是 VoiceOver/Dynamic Type 全量验证。此前产品 11 条辅助功能发现仍未解决；候选 delegate MainActor 警告仍是生产接入限制。不能将诊断 UI 检查或正常启动回归写作完整产品通过。 |
| 不适用项 | 未改产品导航、营销网页、字体资源、动画、品牌、定价/评价、插画、悬停或响应式站点；没有为测试引入新依赖。 |

已查看证据：`pip-coexist-sample-after-clear-attachments/406A6884-2097-44C5-A48F-2C1BB9DEB2F6.png`（按钮与视频状态）、`A89BFC03-794C-411B-8060-D6BD4571E093.png`（返回 Utter，外部 PiP 与 inactive）。独立复核认可候选不接入结论；测试工具收尾问题及修复单独保留，不掩盖失败。


### Isolation closure and restored Release (2026-10-06 01:07)

- `pip-coexist-final-tabs-all.log/.xcresult`：15.354 秒通过，0 段语音；最新 async 清理先确认 Safari 前台并等待过渡，核对活动 UUID 后才停止视频和关闭标签，覆盖本轮两个残留 UUID，双 AX 形态确认不存在。
- 执行 `--standby-cleanup` 后，`pip-coexist-final-group-files.json/.log` 的 App Group 递归结果只有目录与原有 preferences，三份指定诊断均不存在；不读取或清空用户私有模型。已核对 PID 83795 的命令后停止本轮服务器，`pip-coexist-final-server-state.log` 无 TCP 8766 监听。
- `pip-coexist-restore-signature.log`：正常 Release deep/strict 验签退出 0。沙盒内第一次签名检查因信任链访问失败；系统环境复核通过，未重新签名、未降级。
- `pip-coexist-restored-install.json` 与 `pip-coexist-restored-launch.json`：覆盖恢复原 Release 并无参数启动成功，无卸载。`pip-coexist-restored-release.log/.xcresult`：最大字号侧栏及正常启动 16.922 秒通过，0 段语音。
- 已实际查看两张恢复截图（`pip-coexist-restored-release-attachments/manifest.json`）：正常中文主界面显示语音关闭、无可见 PiP/橙色点；最大字号三个侧栏标签完整。后者主内容被侧栏覆盖，不能证明完整 Dynamic Type/辅助功能通过。截图只是该时刻观察，不替代长期麦克风验证。
- `pip-coexist-final-sdlc.log`、`pip-coexist-final-basic.log` 均通过，diff 空白检查通过。`pip-coexist-swift.log` 为 488 XCTest、18 跳过、0 失败，另 1 Swift Testing 通过；macOS 套件不替代 iOS-only 真机测试。部分失败实验的附加诊断收集出现 devicectl/结果导入警告，不宣称诊断包完整。
- 独立验证者复核本轮失败证据、清理和 Release 回归，无实验收尾阻断。共存问题仍未解决；本轮候选不接入产品，完整语音对标仍 blocked。未提交、推送或发布。

## Candidate closure and Release restoration (2026-10-05 23:15)

- `doubao-parity-restoration-build.log`：正常签名 Release TEST BUILD SUCCEEDED；`doubao-parity-restoration-signature.log` deep/strict 验签退出 0。主二进制无 Standby experiment 标记，设备族为 iPhone/iPad；未集成后台候选。
- `doubao-parity-restoration-install.json` / `-launch.json`：原 App 覆盖安装、无参数正常启动成功，没有卸载或清空数据。`confucius-restored-release-files.json` 确认孔夫子 17 个文件仍在私有模型目录。
- `ipad-doubao-parity-restored-release.log` / `.xcresult`：两项真机测试全部通过，18.013 秒大字号侧栏及正常启动、42.696 秒四方向空格/删除/Return/地球可达与 Release 无录音操作；0 段语音播放。测试后的无参数启动恢复正常中文界面。
- `ipad-standby-final-cleanup-tabs`：11.167 秒通过。仅在核对本轮已知标签 UUID 且恰好一个关闭按钮后关闭测试残留，确认两个记录的测试标签不再存在；不按标题或全选关闭用户标签。之前失败的清理运行保留。
- 执行 probe 的 `--standby-cleanup` 后，`standby-cleanup-group-library-final.json` 和 `standby-cleanup-group-root-final.json` 确认 App Group 中三个指定诊断文件均不存在。正常产品随后替换探针。`standby-server-final-state.log` 确认临时 TCP 8766 无监听。
- `standby-final-sdlc.log`、`standby-final-basic.log` 通过；Python 编译、shell 语法和 diff 空白检查通过。Swift 既有套件 `doubao-voice-swift.log` 为 488 XCTest、18 跳过、0 失败，另 1 Swift Testing 通过；这份 macOS 套件不替代 iOS-only 路径的真机验证。
- Xcode 部分附加诊断收集仍报告找不到 devicectl；具体用例日志、xcresult 和截图已取得，不宣称附加诊断全部成功。未提交、推送、发 PR 或发布。

### Final applicable visual audit

收尾重新完整阅读 ANTI_SLOP 1–1599 行；按适用项检查实际点按及新截图。完整对标继续 blocked，未将局部交互通过作为全部视觉/辅助功能通过。

| 适用项 | 本轮审计与边界 |
| --- | --- |
| 原生布局、对齐、留白、旋转 | 恢复后的四方向输入交互通过；已查看横屏键盘，当前输入框可见，状态、空格、删除、Return、地球完整，无新增固定避让空白。沿用原生 Form/侧栏，没有新装饰布局。 |
| 字体、本地化、层级 | 已查看最大字号侧栏，三个导航标签完整可达；这不证明覆盖后的主内容或所有 Dynamic Type 通过。正常中文主界面已查看，截图顶部有系统通知，故不据此宣称完整顶栏视觉检查。主 App 英文启动不覆盖键盘自身中文语言。 |
| 颜色、图标、命中、交互真实性 | 语义系统颜色/SF Symbols，键盘真实编辑已点按；Release 麦克风禁用且说明不支持键盘启动。9 个未定位对比度和 2 个字号报告仍保留，未过滤或以测试通过掩盖。 |
| 状态、录音与回填 | 已查看精确回填截图，真实设置宿主中的本次识别结果已插入；录音后截图无可见橙色麦克风点，journal 对应 engine stopped 与 capture-owned deactivation。单张截图不证明所有闲置/异常状态。 |
| 外部视频与退出 | 两种顺序真实共存失败，候选不接入；已记录其中一次 PiP 停用失败。后续正常 stop、已知标签清理、共享诊断删除和 Release 替换均有独立证据。未以隐藏窗口截图替代播放时间/状态。 |
| 隐私、用户数据、动效与装饰 | 保留用户模型及设置，仅关闭归属明确的测试标签、删除本探针三份诊断；没有音频云端回退、强制常亮、循环静音或新增依赖/装饰。营销 hero、定价/评价、网页字体、CSS 效果、悬停、插画等项不适用。 |

截图证据：`ipad-doubao-parity-restored-release-attachments/manifest.json`；真实精确回填为 `ipad-standby-settings-exact-attachments/152BB48B-7B50-42E6-A44B-F0F17E935BDA.png`。

## Final exact insertion checkpoint (2026-10-05 23:03)

- `ipad-standby-settings-exact.log` / `.xcresult`：49.697 秒通过，播放 1 段固定中文。系统设置保持前台，Utter 后台真实录音完成 667200 帧；读取本轮 `keyboard.result`，断言最终输入框严格等于录音前内容加本次识别文本，排除已有关键词造成假阳性。
- `ipad-standby-settings-exact.json` 的最终记录为 phase=disabled、voice=disabled、active=false、suspended=false、engineRunning=false、sessionDeactivated=true、idleDisabled=false。本轮正常 stop 已确认；不能覆盖视频先启动轮的 stop 失败。
- sessionDeactivated 仅表示 capture 拥有的音频会话停用调用成功，不是系统麦克风实时查询。识别结果包含固定样本及额外环境内容，不作为逐字质量通过。未运行五分钟/十轮三宿主或脱离 XCTest 的长期验证。
- 独立验证者复核实际日志、journal、键盘 AX 与视频对照，确认共存门槛失败，候选不能进入产品。完整语音对标继续 blocked。

## Public PiP video coexistence failure (2026-10-05 22:55)

**结论：候选不满足产品接入门槛，不接入 Release。**

- `ipad-standby-video-switch-control`：未启用待命，仅从 Safari 切 Utter 再回 Safari，视频 PiP 7.5 → 24.6 秒、paused=false；54.215 秒通过。排除普通 App 切换本身导致暂停。
- `ipad-standby-video-after-causal`：先启用 Utter 待命，再启动 Safari 视频，Safari PiP 成功；随后 Utter journal 记录 active=false、phase=stopped、voice=disabled，实际键盘显示“语音输入已关闭”，开始键缺失。反向顺序同样不能共存，0 段录音/播放。
- 两种顺序分别由后启动的 PiP 替换先启动者。五分钟、十轮/三宿主和脱离 XCTest 的长期保留验证不作通过；因共存和停用已暴露失败，本候选不再进入产品验收。

- `ipad-standby-safari-control`：单独 Safari 视频 PiP 对照通过（46.542 秒），currentTime 7.5 → 22.6、paused=false。临时页使用 [Apple 文档的公开 WebKit PiP API](https://developer.apple.com/documentation/webkitjs/adding_picture_in_picture_to_your_safari_media_controls)。
- `ipad-standby-video-before-tab`：视频先启动时 picture-in-picture、7.1 秒、paused=false；随后启用 Utter 压缩视频通话 PiP，再回 Safari，视频变为 inline、8.0 秒、paused=true，共存断言真实失败，未开始麦克风、未播放测试语音。`.json` journal 显示 Utter 的 PiP active=true；不能接入正式产品。后续对照及反向顺序见下。
- 同轮 stop 未在五秒内确认：journal 最后 phase=failed、voice=disabled、active=true；测试等待 disabled 也未成功。退出测试最终终止探针，不把它记为正常 PiP 停用通过。
- 此前 Safari 外部链接受 HTTPS-only 阻挡、地址编辑元素替换及测试残留弹层导致的失败，均未进入共存阶段，不能混作候选失败。已按真机截图修正地址输入与弹层收尾，加入新标签 UUID 保护；后续标签清理先核对本轮 UUID，不按标题批量关闭用户标签。

## Public PiP real keyboard checkpoint (2026-10-05 22:30)

用户已批准公开 PiP 候选，三项组合门槛保持不变，详见 `doubao-voice-parity.md`。目前探针独立，未接入 Release。

- `ipad-standby-real-settings-fixed`：真实键盘在系统设置前台进入录音、停止并插入，但识别内容未匹配固定样本，整项失败。不能将它表述为插入动作未执行。
- 用户再次确认 iPad 在 Mac mini 旁且能听到固定语音；Mac 内置扬声器音量 62%、未静音。`ipad-standby-journal` 以 12 秒窗口复测，49.455 秒通过。截图确认设置前台、真实键盘和插入结果。旧用例仅检查关键词，后续已按独立复核意见改为精确验证本次新增识别文本，待重跑。
- `.build-ios/ipad-standby-journal.json` 内容无关记录：背景状态 appState=2，录音 engineRunning=true；672000 帧结束后 processing/result/ready 均 engineRunning=false、sessionDeactivated=true。该标志表示本次 capture 的停用调用成功，不是系统麦克风实时查询，不覆盖首次待命、异常或锁屏。首次 teardown 未等待异步 stop，记录没有 disabled 尾项；已补等待，待复测。
- 外部原生测试宿主签名安装受三 App 上限阻挡，未卸载其他应用。临时 LAN 服务只开放固定 HTML 和视频，Safari Range 请求已验证 206；首轮 `ipad-standby-safari` 停在系统 HTTP 提示，0 段语音，未进入 PiP 共存断言。保留失败，不能写成共存通过或失败。
- 独立验证要求同时断言播放 currentTime 推进、精确本轮新增回填、停止完成；均已加入下一轮。五分钟闲置、两种视频顺序、十轮三宿主及脱离 XCTest 对照尚未通过。


Status: blocked

## Confucius follow-up and voice parity (2026-10-05)

- `ipad-confucius-first`: download reached a network error after 18.65 seconds. No audio played.
- `ipad-confucius-network`: after adding safe offline/host/TLS error categories, device reported a secure-connection failure after 20.88 seconds. No TLS bypass or voice upload; the device download remains failed.
- All 17 files of the Mac's existing pinned Confucius4-R2T2-8bit repository matched the downloader's exact sizes and SHA-256 values, including the 2,463,307,541-byte weight. `confucius-copy.json` records copying the model to the iPad's private model directory. This is a local transfer, not proof of the in-app network downloader.
- `ipad-confucius-installed`: model selection and restart persistence succeeded; actual fixed Chinese speech was played, but no result arrived within the 100-second limit. The recording showed the home screen. `confucius-jetsam.ips` confirms Utter pid 1900 was killed at 22:03:38 for `per-process-limit`, active/frontmost, 216,152 resident pages of 16,384 bytes (about 3.30 GiB). The failure is not merely a slow-result timeout.
- The iOS Qwen runtime now caps the reusable MLX buffer cache at 16 MiB before loading; active model tensors remain unconstrained by this cache setting. macOS is unchanged. Independent review confirmed the change runs within the existing model resource access boundary; no added entitlement or signing fallback.
- `ipad-confucius-memory`: signed Release, 1 test passed in 93.115 seconds; one real fixed Chinese recording, model selection/restart and configuration restoration. Stop-to-result observed 7.255 seconds including test interaction overhead. The main test sentence was recognized but an extra short phrase appeared at the end. Keyword assertions passed; exact transcription quality and the warm-latency target did **not** pass on that basis. The copied model remains installed, original selection/settings restored. No deletion of a preexisting model.
- Independent review also identified that synchronous Qwen generation does not check cancellation within its token loop, and each mobile session reloads then unloads the model. These are unresolved cancellation/latency issues, not claims of a complete model implementation.

The user selected full voice experience parity with Doubao and approved the [public PiP design amendment](doubao-voice-parity.md), retaining all three combined gates. The independent host builds with real Apple Development signing, but physical installation is blocked by the free-profile three-App limit (Utter, test runner, Idea Box). No existing app was removed. The first Settings-search host attempt successfully activated PiP but stopped at the localized keyboard selector; its hierarchy identified the actual Chinese “下一个键盘” label. No audio was played in that attempt. This is a test-navigation failure, not a background recording result. Product integration remains gated.

Current checks: `doubao-voice-swift.log` passed 488 XCTest cases (18 skipped), plus one Swift Testing case, before the iOS-only cache cap; `doubao-voice-sdlc.log` passed. Device memory-cap Release build passed. Final basic checks and updated high-risk runtime verification remain pending.

The expanded physical-device test round exercised the signed Release product on
an iPad mini (A17 Pro), iPadOS 27.2, UDID `00008130-00092D800891401C`.
The user explicitly authorized fixed speech from the adjacent Mac speaker into
the iPad microphone, then unlocked the device and kept it awake. The initial
20:37 locked attempt started no cases; subsequent results below are real-device
runs. Build/install success is not used as a substitute for interactions.

## Outcome by capability

All artifact names below are relative to `.build-ios/`. Each test-run stem has
its original `.log` and `.xcresult`; exported screenshots have an
`-attachments/manifest.json` mapping human-readable names to files. Failed runs
are retained; this is not an all-green acceptance report.

| Capability | Physical result | Evidence |
| --- | --- | --- |
| Chinese Apple speech | Passed; actual microphone transcript contains the fixed sentence, with 三点 normalized to 3:00. | `ipad-comprehensive-speech-final`, 87.382 s including setup/restoration. |
| Copy/paste and discard | Passed; Copy followed by the native Paste action reproduced the actual recognized result exactly in a text field. Discard returned to ready. | Same Chinese case. This is not voice-keyboard insertion. |
| English speech while backgrounded | Passed; recording began in the foreground, Home brought SpringBoard forward, Mac played English, and returning to Utter and stopping produced the full sentence. | `ipad-comprehensive-speech-final`, 64.739 s; also passed in the preceding `speech-fixed` run. |
| Cancel actual recording | Passed; Cancel produced cancelled state with no result. | `ipad-comprehensive-speech-final`, cancellation/limit case. |
| 30-second automatic finish | Passed on repeat; no manual stop, actual fixed Chinese sentence returned at the limit. | Same case, 107.689 s including preparation/cancel/restore. Earlier incorrect recognition is retained below. |
| Four orientation keyboard editing | Passed; portrait, both landscapes and upside-down portrait: space, delete, Return and reachable globe. Release record/stop actions remain absent. | `ipad-comprehensive-ui-final`, 38.720 s. |
| Globe switch and return | Passed; tapping Utter globe switched to the real system keyboard; native keyboard selector returned to Utter. | `ipad-comprehensive-review`, 18.075 s. Does not prove a persistent menu after long-pressing Utter globe. |
| Native navigation and rotation | Passed; Models/Settings landscape and Voice portrait. | `ipad-comprehensive-review`, 12.692 s. |
| Chinese/English, maximum main-app text | Interactions passed; main page, focused field with keyboard and dictionary screenshots inspected. | `ipad-comprehensive-review`, 35.779 s. Launch font override is not a system-wide keyboard font setting. |
| Settings persistence | Passed; language, duration and key sound changed, survived restart and were restored. Clear-data confirmation was opened and cancelled. | `ipad-comprehensive-ui-unlocked`, 90.090 s. |
| Dictionary and haptics preference | Passed; unique test entry added/deleted; haptics preference survived restart and was restored. | `ipad-comprehensive-ui-unlocked`, 34.036 s. No hardware vibration claim. |
| Microphone permission denied/recovery | Passed; actual Settings switch off blocked recording with the English denial message, switching on allowed preparation, then voice was disabled and original permission restored. | `ipad-comprehensive-review`, 49.619 s. |
| Model download cancel/retry | Passed; real download started, cancelled, retried and cancelled again; wireless permission restored. | `ipad-comprehensive-ui-final`, 35.233 s. |
| Complete model lifecycle / Whisper speech | Not passed. The storage fix removed the immediate folder-permission failure; the corrected run still failed later with a generic download error. | `ipad-comprehensive-speech-final`, `ipad-comprehensive-model-retry`, and `ipad-comprehensive-storage-fixed`; see details below. |
| Native accessibility audit | Not passed: Models 3, Settings 3 and Voice 5 issues; 9 unresolved-element contrast reports plus 2 Dynamic Type reports (Voice Open settings and Personal dictionary). | `ipad-comprehensive-review`, unfiltered `performAccessibilityAudit`; no issues suppressed. |
| Launch performance | Three measured launches: 0.412403, 0.418966, 0.440543 s; mean 0.424 s, relative SD 2.835%. | `ipad-comprehensive-ui-unlocked`. This is a small XCTest launch sample, not a responsiveness/energy benchmark. |
| Voice keyboard without app switching | Existing gate remains failed; production keyboard recording is intentionally unavailable. | Release UI explicitly says this version cannot start recording from the keyboard. |

## Audio method and actual output

`scripts/test-ios-device-audio.py` runs only whitelisted named device cases and
plays a fixed local file after the test emits `UTTER_AUDIO_READY`, which is sent
only after the real UI reaches recording. This is acoustic playback/capture,
not injected PCM or synthesized recognition output.

- Chinese: 今天下午三点，我们在公园见面。请记得带一瓶水。
  Tingting, rate 165, 5.369 seconds, `ipad-speech-zh.aiff`.
- English: Tomorrow morning at nine, we will meet in the library. Please bring a notebook.
  Samantha, rate 155, 4.516 seconds, `ipad-speech-en.aiff`.
- Mac output was unmuted at volume 48; no volume setting was changed.
- Final Apple round played four samples (Chinese, English, cancel, auto-stop).
  Host playback began 75–82 ms after the recording-ready marker.
- Chinese result: `今天下午 3:00，我们在公园见面 ，请记得带一瓶水。`
- English result: `Tomorrow morning at nine, we will meet in the library. Please bring a notebook.`
- Observed manual-stop-to-result waits: 4.166 s Chinese and 4.472 s English,
  including XCTest interaction/observation overhead. These are not isolated ASR
  inference benchmarks.
- Auto-stop waited another 18.155 s after the initial 12-second capture interval,
  consistent with the configured 30-second limit and result observation.
- An earlier auto-stop run returned unrelated text and failed keyword checks.
  Its `ipad-comprehensive-speech-fixed` result is retained. The successful repeat
  establishes one working trial; it does not establish a broad accuracy rate.
- `ipad-comprehensive-speech-final` contains 4 cases, 3 passed and 1 model-download
  failure; its exit 65 must not be described as a full suite pass.

Actual result screenshots inspected: `speech-final-attachments/` files
`10185C4C-7808-4F45-ABC1-F028DCAFD7DC.png` (Chinese),
`76E14D33-17A7-42A8-82B3-1C56BB2DD91A.png` (English background), and
`8C8A8D7A-8E3B-4282-B029-B4C0C034684F.png` (automatic finish), with the full
`ipad-comprehensive-` prefix on that directory.

## Findings and repairs

1. **Immediate recording cancellation.** The first real recording reached
   Cancelled before any playback marker. `MobileCapture` treated every route
   notification as an interruption, including category activation. It now
   ignores a category-change notification only while the session has the
   configured `.playAndRecord` category; other route changes and interruptions
   still cancel. Real Chinese, English and limit trials then completed. This
   condition does not uniquely prove who initiated the category change.
2. **Wrong error language.** Setting localization before runtime startup was
   overwritten by SettingsStore load, and direct localization assignment was
   subsequently overwritten by preference updates. Mobile runtime now sets the
   persisted UI language from the main bundle after startup. The real microphone
   denial path and download errors now follow the English test launch.
3. **Large sidebar truncation and dim readiness status.** The sidebar reserves
   more room at accessibility sizes and omits redundant icons there. Apple
   language-model readiness is now primary status text instead of a disabled
   gray button. The two readiness-specific audit reports disappeared; final
   sidebar screenshots confirm complete Voice / Models / Settings labels without ellipsis.
4. **Model path across iOS installations.** The last pre-fix download screenshot
   explicitly reports a model-folder permission failure. Stored preferences
   contained an absolute iOS application-container path; the shared resolver
   reused it. iOS now resolves its model root from the current application
   support directory on every access; macOS custom-directory behavior is
   unchanged. No model files or preferences are deleted by this repair. The
   exact earlier container transition was not captured, so the stale-path
   diagnosis is an inference. The corrected run could create current-container staging directories and no longer produced the immediate permission error, but its later generic transfer failure remains unresolved.
5. **Harness corrections.** Wait for the keyboard extension to load, accept
   normal time formatting, target the system switch's actual control position,
   disambiguate Wi-Fi rows, detect terminal download failure promptly, and use
   the observed Show Sidebar accessibility label. None substitutes synthetic
   success for a failed product action.

The first full model attempt timed out with a generic download failure. The
next bounded attempt failed within about two seconds of tapping Download and
showed the folder-permission error; zero audio samples were played. It restored
Wi-Fi access to the original off selection. The copied app preferences and
read-only Library listing are `ipad-final-preferences.plist` and
`ipad-final-library.json`; do not infer model success from empty directories.

## State preservation and remaining boundaries

Tests restored model/language/duration, sound/haptics preferences and microphone
permission (on). Runs that temporarily changed wireless data restored it to off,
as confirmed in their screenshots. On entry to the last storage-fixed run, the
actual Settings screenshot already showed Wi-Fi and cellular selected; that run
left this observed setting unchanged. Its origin was not captured, so the final
wireless setting must not be described as off. They deleted only the unique
owned dictionary test entry and registered model cleanup only after positively
starting an absent model download. Clear all local data was never confirmed.
No user model was removed. The copied fixed speech may remain in the Mac test
artifacts and the fixed recognized sentence may remain in the iPad clipboard;
no pre-existing clipboard content was read or archived for restoration.

Before recording, the app temporary directory had zero files. After the real
Apple round its recursive listing contained only an empty TemporaryItems
directory, no recording files (`ipad-recordings-final.log/json`). This proves
that checkpoint's cleanup, not continuous microphone-indicator or power tracing.

Not established by this round: keyboard-triggered background wake after
suspension, keyboard voice insertion into third-party hosts, PiP/video
coexistence, long standby, calls/Siri/Bluetooth interruptions, locked recording,
VoiceOver navigation, Stage Manager/split-screen resizing, a new physical light
mode pass, large-model speed/RAM, power/thermal behavior, or first-time Apple
asset installation/removal. The background English case proves continuity of
an already-started recording only. Previous standalone PiP results do not close
these gaps. Larger models remain explicitly unverified.

## Visual and interaction audit

ANTI_SLOP was read completely before acting and reread completely before the
final visual audit (all 1–1599 lines). Applicable points were reviewed against
real interactions and exported physical-device images; non-app marketing,
hero imagery, webpage typography and scroll-reveal defaults are inapplicable.

- **Layout and navigation:** native Form/List/NavigationSplitView, system spacing
  and safe-area behavior. Normal portrait/landscape Models, Settings and Voice
  screenshots were inspected. Four-orientation keyboard snapshots retain the
  input field and reachable space/delete/Return/globe without an artificial
  fixed blank strip above the keyboard.
- **Type and localization:** semantic text sizes; English and Chinese maximum
  main-app font snapshots show wrapping and a reachable dictionary/input field.
  No full Dynamic Type acceptance is claimed: Voice's two reported controls
  remain open. Main-app launch language/font overrides are scoped to that
  process; the installed keyboard can retain the user's Chinese language.
- **Color and contrast:** semantic foreground/background and native control
  states. Readiness text's visibly poor disabled contrast was repaired and
  inspected. Nine remaining unresolved contrast reports are preserved as
  failures, not dismissed as system false positives.
- **Controls and truthfulness:** real action wiring for model retry/cancel,
  settings persistence, clipboard, dictionary, keyboard edits and permission
  recovery. The disabled Release keyboard microphone truthfully reflects the
  failed background-wake gate. No decorative clickable placeholders or fake
  successful recording states were added.
- **Privacy and destructive actions:** denial blocks microphone work; cancel
  yields no result; tests restore permission/settings; deletion confirmation
  was cancelled. Model test ownership prevents deleting pre-existing models.
- **Restraint:** no added gradients, decorative panels, shadows, animation,
  fonts, assets or UI dependencies. Existing native grouping remains functional.
- **Unresolved UX:** model-folder error currently inherits desktop advice to
  choose another storage location, although iOS has no such picker. Another
  generic download error says Resume while the mobile action says Retry.
  These are retained findings, not successful copy review.

## Local validation and independent review

- Signed Release `build-for-testing` succeeded with the configured Apple
  Development identity; no ad-hoc fallback. xctestrun app/host paths were checked
  as Release-iphoneos, and the tested production UI has no diagnostic controls.
- `ipad-comprehensive-final-basic.log`: passed.
- `ipad-comprehensive-final-swift.log`: 1010 XCTest cases, 18 skipped, zero
  failures, plus one Swift Testing case passed. Hardware/model skips remain
  skips, not device evidence.
- SDLC validation, Python syntax, project plist lint and whitespace checks passed
  earlier; final post-report checks are recorded below.
- Independent reviewer `ipad_test_review` found no blockers in capture category
  handling, settings-language synchronization, readiness text, test ownership or
  cleanup. Follow-up review found the iOS storage-root fix covers managed download, staging, publication, scanning, deletion and Whisper loading; macOS behavior is unchanged. Custom imported-path mappings are outside this repair, and iOS has no import UI.
- Xcode emitted an ancillary diagnostics-collection warning that its subprocess
  could not find devicectl. Test case logs and xcresults exist; this warning is
  not ignored as evidence that ancillary collection succeeded.

No commit, push, PR, publication or approval was performed. Verification remains
blocked by the unresolved product gates and audit failures.

## Final checkpoint, 21:32–21:34

- `ipad-comprehensive-storage-fix-build.log`: Release TEST BUILD SUCCEEDED.
  `ipad-comprehensive-close-signature.log`: deep/strict signature verification
  exited 0. The test bundle still targets the real Release app.
- `ipad-comprehensive-storage-fixed`: one failed model-lifecycle case,
  106.927 seconds. About 61 seconds after the real Download tap, the UI returned
  the generic incomplete-download error. Zero playback markers and zero audio
  samples occurred. Model recognition, selection/restart and completed-model
  deletion therefore remain unverified on this device. New writable staging
  directories were observed, but zero model-file bytes were present in the
  read-only snapshot (`ipad-storage-fixed-during.json`).
- `ipad-comprehensive-restored-final`: one passed case, 17.879 seconds, zero
  failures. The actual Show Sidebar control opened the maximum-font sidebar;
  all three labels were reachable and visibly complete. Then the app relaunched
  without test arguments in normal Chinese, default text size, portrait and
  disabled voice state. Both screenshots were inspected. The earlier
  `ipad-comprehensive-restored` failure was an incorrect test selector, retained.
- Final images: `ipad-comprehensive-restored-final-attachments/`
  `5FEBA9E9-E000-44FD-A370-BDA35A6244FD.png` (maximum sidebar) and
  `1D785CA9-ABCC-484A-AEEA-EDFF79A47337.png` (normal Chinese Release).
- `ipad-comprehensive-close-basic.log`: passed. It includes SDLC checks.
  `ipad-comprehensive-storage-swift.log`: eight existing ModelFiles tests passed
  (six model-plugin/file tests plus two frozen-session tests), zero failures.
  The preceding full 1010-case regression remains separately recorded above.
- Final whitespace, Python syntax and project plist lint passed. The post-report
  SDLC result is `ipad-comprehensive-close-sdlc.log`.
- `ipad-comprehensive-close-tmp.log/json`: temporary directory contains only an
  empty TemporaryItems directory, no recording files. Normal devicectl launch
  succeeded (`ipad-comprehensive-close-launch.json`); no diagnostic arguments.

The shared test navigation helper still recognizes Toggle Sidebar; this last
collapsed-sidebar case explicitly uses the observed Show Sidebar label. Extending
the shared helper is a remaining harness cleanup, not evidence of another
successful product interaction. The native accessibility reports, generic model
transfer failure and original no-switch voice-keyboard gate remain open.
