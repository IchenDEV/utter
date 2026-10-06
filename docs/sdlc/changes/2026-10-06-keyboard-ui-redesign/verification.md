# Verification: iOS 语音键盘界面重设计

**Status:** approved
**Approved-by:** 用户（线程 b69087ea：“批准 verification”）
**Approved-date:** 2026-10-06
**Approval evidence:** 用户在 16:24、16:24、16:30 连续三次回复“批准 verification”，对应三轮运行（第 29–31 轮）均因调用失败而终止，批准未被及时录入；接力线程确认批准后文件未再修改，然后录入。
**Scope:** 方向 B 键盘实现与验收；原型和规格审阅为前置证据。

## Mockup checks

- T3 HTML preview rendered the self-contained page at 820 px wide. The page reported 26 panels and no browser console errors.
- Collaborative browser showed 26 items: 24 design panels (3 directions × 4 states × 2 appearances) and 2 current-state comparisons.
- The appearance filters were clicked in the browser. Light and dark each show 13 items (12 design panels plus one current comparison), and the selected button exposes `aria-pressed="true"`.
- Browser layout measurement confirmed each design panel's unscaled box is exactly 744 × 300 CSS px; it scales uniformly to fit the available column width. All 26 panels measured 744 × 300 at the desktop preview width, with no content overflow.
- Manual visual review found and fixed the recording indicator inheriting the recommendation-card style, improved contrast for Direction A's unavailable voice key, and separated the B/C status row and keyboard-switch key from the main controls.
- Waveform motion remains visible by default and becomes static when the browser requests reduced motion.

## Repository checks

- `bash scripts/sdlc-checks.sh`: passed.
- `bash scripts/ci-basic-checks.sh`: passed.
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`: passed; the opt-in ANE/MLX fallback integration test was skipped because `OPENTYPE_ANE_MLX_FALLBACK_INTEGRATION` was not enabled.

## Design-stage boundary (historical)

The prototype checks above preceded implementation and did not establish native-app acceptance. Current implementation evidence follows below.

## Direction B specification review (2026-10-06)

- 本轮重新运行 SDLC 与基础 CI 检查，均 exit 0；`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` exit 0。OpenTypeTests 汇总 488 项、18 项按配置跳过、0 失败，其他 package 测试 target 亦通过。日志：`/tmp/utter-keyboard-b-spec-swift-test.log`。
- `git diff --check` 通过；工作区改动仍仅为本次未跟踪的 SDLC 文档目录。
- 用户选择 B 并要求继续，intent 已记录批准依据；spec 为 pending approval，plan 仍为 draft。
- 读取 KeyboardView、KeyboardController、VoicePhase/isBusy 及现有本地化状态，逐项核对显示优先级、按钮条件、结果有效性、编辑与 globe 行为。
- 修正规格中的原型遗漏：录音仍保留删除，结果仍保留换行，额外操作通过布局容纳；不把宿主删除描述成“删除结果重说”。
- 七柱动画定义为录音活动指示，未声称可读取桥接未提供的实时音量；明确 preparing/processing 的显示与禁用规则。
- 本阶段未修改 HTML 或应用界面；上面的浏览器交互证据属于原型阶段，不能视为 SwiftUI 真机验收。

## ANTI_SLOP specification audit

本阶段开始前与交接前均完整重读 ANTI_SLOP，按以下适用项核对规格：

- **一致性与真实内容：** 采用用户选定的听写台布局，系统字体、SF Symbols 与键帽语言一致；状态来自现有数据，结果使用真实文本，不增加假指标或假隐私承诺。
- **形状与色彩：** 蓝/红仅承担开始/停止语义；中性键盘表面适配 appearance；静止状态点，不使用渐变、发光、悬浮卡片或默认营销按钮组合。
- **按钮与图标容器：** 64 pt 圆形是用户选定的可操作语音键；不是装饰性图标底板。采用原生 Button/Link/UIButton，44 pt 点击区域。
- **阴影与层次：** 键帽优先依靠明度；允许的阴影仅为小幅向下，不使用重复盒子模拟阴影、全周光晕或假玻璃。
- **可读性：** 标明文字/图标对比目标，保留错误全文；大字号与长结果使用换行和滚动，不能靠缩字或裁切腾空间。
- **对齐与边界：** 状态/中央/编辑共享轴线，明确间距、横向留白与 globe 独立底行；禁止绝对坐标照搬导致重叠。
- **运动：** 七柱只在 recording 活动，待命静止；Reduce Motion 静态反馈；内容不依赖动画完成才可见。
- **真实交互：** 删除、换行、取消、插入、启用与 globe 均映射既有回调；实现阶段必须实际操作并记录，规格审阅不能代替真机验收。
- **本任务不适用项：** 营销 hero、字体品牌展示、客户 logo、定价、评价、页脚、摄影、背景气氛、滚动叙事等不属于键盘功能界面，未为满足清单增加此类元素。

规格审阅发现的问题已写入 spec；像素居中、实际对比、裁切、VoiceOver 与按键交互仍等待实现后真机验证。

## Plan stage (2026-10-06)

- 用户明确回复“批准 spec”，已记录 spec 的批准人、日期；plan 补齐为 pending approval。
- 核对现有真机脚本与三条测试名称，修正原 draft 的不完整命令。使用正常签名工程重建，避免测试旧产物或替换入口的 probe。
- 本轮 SDLC、基础 CI、Swift 测试均 exit 0；日志为 `/tmp/utter-keyboard-b-plan-{sdlc,basic,swift-test}.log`。`git diff --check` 通过。
- 本轮仅修改审批记录和实施计划；无新增界面或设备测试结果。

## Implementation in progress (2026-10-06)

- 用户明确回复“批准 plan”，已记录批准信息并开始实现。
- KeyboardView 使用 64 pt 圆形语音键、动态表面、状态区、滚动结果和完整编辑行；七柱仅在 recording 活动，Reduce Motion 时静止。
- KeyboardController 仅改变承载视图底色；桥接、录音与租约逻辑保持既有实现。增加两条中英操作说明。
- 既有真机三流程仅增加就绪/录音/结果截图，不改断言。新增的验收流程为真机外观与实际 VoiceOver 遍历，不是单元测试。
- 首次 Debug Apple Development build-for-testing、codesign --verify --deep --strict、devicectl install 均 exit 0；日志 keyboard-b-build.log、keyboard-b-install.json。
- SDLC、基础 CI、Swift 测试均 exit 0；OpenTypeTests 为 488 项、18 跳过、0 失败。日志 keyboard-b-{sdlc,basic,swift}.log。
- 初始语音两流程识别结果过短，未满足固定语音断言；保留 keyboard-b-regression-20261006.xcresult。用户已确认将 iPad 移近 Mac 扬声器，待重新验证。失败不能计为回归通过。
- VoiceOver QA 编译时遇到新版 Swift 导入名称差异，修正为 moveForward() 后 keyboard-b-qa-build2.log build-for-testing 成功。


## Earlier physical-device evidence, 2026-10-06 (historical failures)

- 正常签名 build-for-testing 已通过至 `keyboard-b-qa-build7.log`；本轮未修改音频、ASR、桥接或租约代码。
- `keyboard-b-regression-20261006.xcresult` 三条既有待命测试全部在固定关键词断言失败。`keyboard-b-near-speaker-20261006.xcresult` 移近扬声器后普通待命测试仍返回“我”。原测试调用保持完整关键词断言。
- `keyboard-b-visual-20261006.xcresult` 的前台 Apple 中文语音测试也返回“我”，没有识别出固定句子的关键词。因此不能将问题归结为键盘显示层，也不能宣称后台语音回归通过。
- Mac 默认输出为 Mac mini 扬声器，音量 62%、未静音；用户确认 iPad 已靠近且没有连接蓝牙麦克风。
- 录音过程中通过 devicectl 只取出本次测试的 tmp/UtterRecordings 文件。暂存 CAF 为 7.5 秒、48 kHz 单声道 Float32；解码全部样本为零。源 AIFF 为 5.369 秒，半秒 RMS 约 -16 至 -25 dBFS。此为录制中的副本，仍需确认完成文件及实际输入路由，不能凭此单独断定最终根因。
- 外观验收仅检查实际返回结果的显示/单次插入；它不检查识别准确性。既有三个真实语音回归继续检查“公园”和“水”。
- 外观测试已实际完成两种 appearance 的失效、就绪、录音、结果画面；编辑删除/空格、activate、start/stop、插入及插入后结果消失已有执行证据。结果为“我”，这些截图不能作为完整语音准确性的证据。
- VoiceOver 真实输出顺序：录音、开始提示、删除、空格、换行、切换键盘。原验收脚本错误期待“下一个键盘”，已修正为产品现有“切换键盘”；需以重跑的退出码确认通过。globe 长按列表已出现并截图。
- 最大字号设置探索尚未构成验收；不得将仅打开 Settings 的测试通过视为最大 Dynamic Type 通过。

### 八态截图

目录：`.build-ios/keyboard-b-visual-attachments/`；映射由 manifest.json 保存。

| 外观 | 就绪 | 录音 | 结果 | 失效 |
|---|---|---|---|---|
| 浅色 | 53D27B7A-1A4C-41C8-B74D-3AA8A6DDB7D6.png | ED48AA37-8D4D-4B7C-A584-919039A528F5.png | 515BEF0C-A8D1-4CA9-8A43-FD029F4EA7DB.png | 937B6097-7ABC-43CC-9E1C-59DCABA60C58.png |
| 深色 | 0599E749-0BD1-44AC-BDC9-B2A74C439AE4.png | B84D8FA4-2917-4415-BE52-D46B98D5C738.png | FD952CC6-61E8-4642-8357-4822788DE2FB.png | CD046064-B83A-444D-9F41-5BC1FB50B2EA.png |

### ANTI_SLOP implementation audit

完整重读文件四段（1–400、401–800、801–1200、1201–结束），逐项对照代码及八态真机截图：

- **构图与一致性：** 使用用户批准的听写台中央轴线，原生系统字体、SF Symbols、圆形语音操作和矩形编辑键；不增加营销 hero、品牌字体、定价、虚假评价、logo 墙、装饰插画或模板 section。本任务为功能键盘，这些网站专属项不适用。
- **形状例外：** 状态胶囊、64 pt 蓝/红语音按钮和指定灰色表面来自批准的 B 设计，不是默认装饰 tile、hero eyebrow 或无意义彩色 chip。失效态描边是 disabled 操作语义，非装饰卡片边框。
- **色彩与层次：** 无渐变、光晕、径向背景、伪玻璃、假阴影、偏移复制盒、噪点覆盖文字。色彩只表达 ready/recording/result；文字同时提供状态。白色与实际蓝色填充对比约 6.71:1，与红色约 5.69:1。
- **对齐与居中：** 八态共同中心轴；状态点与文字已改为垂直居中；mic/stop 使用原生符号居中，编辑键与结果共用 580 pt 上限。globe 在独立 UIKit 底行，截图无叠压。不存在并排卡片比较基线问题。
- **间距与边界：** 主体两侧 20 pt、顶部 12 pt，按键至少 44 pt；八态截图没有文字贴边、控件切边或错误全文裁切。大字号/长结果仍需实机验证，不能仅由 ScrollView 推定通过。
- **运动：** 待命静止，活动柱只属于 recording；无 entrance 隐藏、hover 跳动、浮动卡片、默认全局动画。Reduce Motion 分支使用静态柱和 hourglass；系统设置实测仍待完成。
- **内容与诚信：** 所有文案本地化，状态来自现有桥接；七柱是活动指示，不声称音量测量。真实结果截图保留“我”，没有伪造长结果或通过标记。
- **交互：** 已执行启用、录音、停止、删除、空格、插入和 globe 长按；取消、换行的文本效果、VoiceOver 激活操作、Full Access 关闭和最大字号仍需补齐。看见控件或获得朗读不等于该操作验收通过。

此为当时 draft 状态；语音失败和剩余无障碍/权限项解决前，不提交为 verification approved，也不交付 PR/发布。

## Continuation and corrective scope (2026-10-06)

- Device Hub 关闭、VoiceOver 关闭后，正常待命测试 `keyboard-b-acceptance-20261006.xcresult` 通过；固定关键词和单次插入断言通过。此前全零录音与实时查看的关联尚未证明因果。
- 同轮四方向基础编辑测试通过。随后外观测试返回宿主时捕获现有文档代理崩溃，报告 `keyboard-b-crash.ips`；另建 [corrective bundle](../2026-10-06-keyboard-document-lifecycle/intent.md)，intent/spec/plan 均已获用户分别批准。
- 修复仅将 visible/refresh/watchStandby 移到 viewDidAppear。第一轮 `keyboard-b-lifecycle-20261006.xcresult` 通过（265.481 秒）：10 次宿主返回、10 次宿主重启、浅深色交替、真实中文单次插入。
- 回归前后系统崩溃清单相同，仅含旧报告 UtterKeyboard-2026-10-06-151641.ips。此为当前观测，不代表所有 UIKit 生命周期路径已穷尽。
- 测试改正了 VoiceOver 原有标签预期与 teardown 顺序，确保关闭 VoiceOver 后再恢复 appearance；所有固定语音 helper 调用再次严格要求公园/水，不再用短结果作为完整验收。
- 最大字号导航问题来自 Settings 搜索建议层挡住根分类，而非产品键盘；测试改为点按可见建议，完整字体/语音验收正在重跑。
- `keyboard-b-final-qa-build.log` 正常 Apple Development build-for-testing 通过；未修改录音、ASR、桥接消息、租约/消费协议。

- `keyboard-b-final-accessibility-20261006.xcresult`：外观/VoiceOver 145.654 秒通过；Full Access 文案断言失败。最大字号 70.974 秒测试退出成功，但审图发现“更大的无障碍字体”仍关闭，不能算最大 accessibility 尺寸验收。修正系统开关点按为控件右侧并增加值断言，待重跑。Reduce Motion 50.878 秒测试通过，仍需核对开关值及像素帧。首轮 Full Access 关闭截图实际仍为开启，因此此次失败是测试未完成设置，而非已证明产品权限错误。

- `keyboard-b-switch-validation-20261006.xcresult`：Full Access 关闭值为 0、具体错误、基础编辑、恢复值全部通过（50.779 秒）。最大 accessibility 字体已确实开启，固定中文、全文滚动与插入通过，但 teardown 根侧栏在大字号下需滚动，退出失败，不能计整项完成。
- 最大字号审图发现图标 `.title3` 动态扩大后越出 44 pt 键帽；删除/换行/取消改为固定 20 pt 图标，globe 指定 20 pt 符号配置。文字继续 Dynamic Type，点击区域不缩小。
- Settings 根侧栏改为使用已观察到的 `com.apple.settings.sidebar.collectionView` 滚动查找无障碍；字体恢复优先使用当前可见页面，避免重新打开造成导航丢失。
- `keyboard-b-maximum-restored-20261006.xcresult` 最大字号测试通过（84.965 秒），恢复原始更大字体关闭/滑块 50%。本次一次性恢复失败前已记录的基线，不把遗留最大字号当用户原设置；临时恢复分支已从提交代码移除。

## Final ANTI_SLOP audit after fixes

交付前再次完整重读 1–550、551–1100、1101–结束；逐项检查适用项，并把网站专属项与用户指定设计例外明确列出。

| 适用要求 | 结果与证据 |
|---|---|
| 一致构图、避免无决定的套版 | 用户选定 B 的状态、中央语音、底部编辑轴线；580 pt 内容上限，独立 globe 底行，保留正常系统字体与 SF Symbols。没有换用营销 hero 模板。 |
| 图标容器与 status chip 不能装饰泛滥 | 圆形是实际录音操作，胶囊仅承载当前状态；均属批准设计。编辑键为真实输入键，不添加装饰 tile、标签或假指标。 |
| 配色、对比、层次 | 批准的动态灰表面，蓝开始/插入、红停止；白蓝约 6.71:1、白红约 5.69:1；动态 label/secondaryLabel。没有紫色渐变、发光、假玻璃、默认光晕、重复盒阴影、噪点压字或硬色彩接缝。 |
| 可读性与字号 | 正文/状态/结果/文本按钮随 Dynamic Type 放大，全文换行/滚动。发现操作图标放大后越出键帽，已固定其 20 pt 图标尺寸，点击区域仍 44 pt；麦克风保持 28 pt。 |
| 居中、对齐、留白 | 状态 HStack 中心对齐，语音 glyph 在 64 pt circle 中；编辑行与结果同轴，20 pt 两侧留白，12–16 pt 垂直间距。最大字号修复后的图标位于键帽内部，globe 无叠压。 |
| 裁切与边界 | 默认字号整段真实中文完整显示；大字号从顶部/末尾真实滚动阅读，插入固定行可达。滚动视口的移动边缘不作为省略全文的手段，未用缩字或省略号隐藏结果。 |
| 运动与可见默认 | 无 entrance 隐藏、hover boop、默认 underline/卡片漂浮。七柱只有 recording 活动；其他状态静止。Reduce Motion 实测开关值为 1，两张间隔 2 秒录音截图活动柱区域 changedPixels=0，取消仍可用。 |
| 实际控件与无障碍 | 使用原生 Button/Link/UIButton。已真实执行 activate、start/stop、insert、编辑、VoiceOver 遍历与启动/取消、globe 长按；Full Access 关闭值为 0 时具体错误与编辑可用，原权限恢复。最终统一回归仍需以完整退出结果为准。 |
| 真实性、文案与实现范围 | 两条操作说明有中英本地化；七柱不宣称音量；真实 ASR 文本原样记录。只修复经独立批准的生命周期时机，不改协议、ASR或权限设计，不制造通过结果。 |
| 原生基础与复杂度 | 复用现有状态与回调，无新增依赖、通用组件或控制器抽象；全部改动 Swift 文件少于 300 行。 |

不适用项逐类：Google/品牌展示字体、wordmark、logo/客户墙、报价/定价、testimonial、营销 CTA、hero/section/footer、摄影/玻璃/插画、grain/环境背景、鼠标 hover 与网站导航模板。它们不属于系统语音键盘；未为了“独特”引入与原生功能界面无关的视觉或内容。用户批准的 B 灰表面、圆形语音操作、状态胶囊和 SF Symbols 是具体设计约束，优先于网页默认禁用项。


## Current acceptance evidence (2026-10-06 16:15)

- 统一实机批次 `keyboard-b-final-all-20261006.xcresult` 已结束，7 项通过、1 项 fixture 导航失败，整体 exit 65。通过项：八态外观/VoiceOver 146.757 s、10 轮宿主返回/重启及文档变更拒绝旧结果 279.521 s、Full Access 关闭/编辑/恢复 48.093 s、最大 accessibility 字号 100%/滚动/真实语音/恢复 64.735 s、Reduce Motion 53.102 s、普通待命语音 44.314 s、五分钟待命真实语音 344.194 s。关键词“公园/水”和完整单次插入断言均保持。
- 最新八态截图已逐张审阅，目录 `.build-ios/keyboard-b-final-all-attachments/`，以下结果为完整真实中文，不沿用早期短结果：

| 外观 | 就绪 | 录音 | 结果 | 失效 |
|---|---|---|---|---|
| 浅色 | 2F19C07C-3561-4D9C-B3CD-B4FF7BD015B0.png | 389F41E0-D45F-4A9C-AE7D-810CA1614BCE.png | DD1DD7C2-E912-4C58-B0F3-32006F577521.png | CF05BAB8-B72E-4471-B9DB-CBE4137045B3.png |
| 深色 | 64F83D3D-47BA-4A00-942A-4F0609A4700A.png | F2294E59-A947-4F4D-AFC5-1AF70186421A.png | 76F4E543-6DC4-453D-BFA0-6FB690BC475D.png | 934294F8-E35D-4CBD-A933-3295DCA109AB.png |

- 另审阅真正最大字号 `373E8B34…png` 与全文滚动末尾 `29135139…png`、权限错误 `91CE613D…png`、旧结果拒绝 `87697B9E…png`。无操作图标越出键帽，全文末尾可读，固定插入操作可达。停止后的即时截图仍捕获异步 recording 尾帧，不能把它说成 processing 实拍证据；preparing/processing 的布局及禁用状态通过代码核对，缺少稳定的单独真机截图。
- 最新 Reduce Motion 帧 `31D344C3…png` / `EB2DCEE9…png` 间隔 2 秒，原生 CoreGraphics 对比区域 redPixels=1714、changedPixels=0；日志 `keyboard-b-final-all-wave-comparison.log`。设备字号、appearance、VoiceOver、Reduce Motion、Full Access 已由通过测试 teardown 恢复原值。
- PiP 测试的地址键入被 Safari 截掉前缀；改用原生系统 URL 打开后真正到达安全提示。`keyboard-b-pip-native-20261006.xcresult` 32.498 s、exit 65；自动化按规则停止，等待用户手动确认局域网测试页面，尚未进行此流程录音。新增标签已自动清理；前一轮失败留下本测试自己的搜索标签 UUID `1DE84516-0D1B-4D6E-AE07-76E3AC81CF23`，后续仅清理此 ID，不动用户既有标签。
- 最后本地 `keyboard-b-handoff-{sdlc,basic,swift}.log` 均 exit 0；Swift XCTest 488 项、18 跳过、0 失败，Swift Testing 1 项通过。签名严格校验 exit 0。当前设备崩溃清单仍只有修复前旧报告，详见 corrective verification。
- ANTI_SLOP 适用项详细审计见上一节；最新真实截图确认默认字体对齐/留白、最大字体滚动和图标边界、语义配色、静态减弱运动。fixture 安全提示及最后真实 PiP 恢复未完成，状态仍为 draft。


## Final review submission (2026-10-06 16:22)

- 最后一项 `keyboard-b-pip-manual-20261006.xcresult` 通过，96.899 秒，xcodebuild exit 0，实际播放固定中文 1 次。视频 PiP 已真正启动并取代 Utter，键盘 value=standby_off；点启用链接回到 Utter，等待 active；回宿主录音，识别完整中文且含公园/水，验证全文单次插入和结果消费。截图目录 `.build-ios/keyboard-b-pip-manual-attachments/`：失效 `7EA73689-01B9-44F2-B86D-BE1664695FE5.png`、完整结果 `3138CDAB-1352-48DA-B3BB-86D5166D78C3.png`、插入 `4FBE59CE-A725-49B3-B865-6713A91AE112.png`，均已审阅。
- Safari 会复用相同 URL 的既有标签。fixture 使用 UUID 查询参数区分本轮，并用 stdlib urlsplit 解析固定资源路径；新标签必须不属于测试前标签集合，teardown 只关闭本轮 ID。安全提示实际出现，自动化没有点继续；测试留在提示页等待用户，用户手动通过后才加载视频并继续。这是需要人参与的 LAN fixture 验证步骤，不是无人值守通过。
- 保留失败证据：原统一批次 exit 65（7 项通过，fixture 导航失败）；随后 focused run 因安全提示或既有标签保护失败。最后独立 PiP run exit 0。八项现均有实机通过证据，但不把原统一批次改称 exit 0。
- `keyboard-b-pip-handoff-build.log` 正常 Apple Development build-for-testing exit 0，codesign 深度严格校验 exit 0。最终设备清单 `keyboard-b-crashes-final.json` 仍仅有修复前旧 `UtterKeyboard-2026-10-06-151641.ips`，未新增 Utter 崩溃报告。
- `keyboard-b-final-{sdlc,basic,swift}.log` 均 exit 0，Swift XCTest 488 项、18 跳过、0 失败及 Swift Testing 1 项通过；git diff --check 通过。改动 Swift 文件 183/243/258/277/294 行，无新增依赖和单元测试。
- 所有实机使用正常签名 Utter App，无 probe 替代入口；关闭 Device Hub 实时查看。测试恢复原设备权限/字号/appearance/VoiceOver/Reduce Motion；结束待命并停止本轮局域网 fixture 服务。
- 交接前重新完整阅读 ANTI_SLOP 并理解每项，详细审计见 UI verification 的 Final ANTI_SLOP audit 表。最终截图保持批准 B 的轴线、语义色彩、完整长文本与可达输入操作，没有发现需继续修改的产品界面问题。
- 残余限制：未穷尽所有第三方宿主或 iPadOS 生命周期；preparing/processing 的瞬态独立截图缺失，布局/禁用规则已静态核对。修改前对比沿用原型阶段的当前布局对比，没有补造旧版本实机截图。首轮导航失败遗留本测试搜索标签 ID 已记录，用户既有标签没有被清理。真实语音测试需要固定扬声器输入及上述浏览器手动步骤。
- implementation/validation 已完成，此 verification 单独提交人工审批；未经审批不进入下一阶段。

## Approval record (2026-10-06)

- 用户已批准本 verification，批准针对的内容包含上一节声明的残余限制。批准到达时间 16:24:29；批准时文件最后修改为 16:23:54，代码最后修改为 16:19:50，批准后未再改动。
- 批准只覆盖 verification 阶段。push、PR、发布按 plan 的 Human gates 仍需用户另行授权。
