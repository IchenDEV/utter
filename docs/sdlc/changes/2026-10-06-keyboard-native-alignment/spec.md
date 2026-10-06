# Spec: iOS 语音键盘与系统键盘对齐

**Status:** approved
**Approved-by:** 用户（本对话：“全部批准，继续执行。”）
**Approved-date:** 2026-10-07
**Upstream:** [intent.md](intent.md)（已批准，2026-10-07）

## Context

- 现状与实测见 [intent.md](intent.md) 与 [evidence/](evidence/)：系统键盘（iPad mini A17 Pro，iPadOS 27.2）的键是**纯平、无阴影**的圆角矩形，底排所有键（地球、123、听写、空格）同色；底板是系统半透明材质。Utter 现状自绘不透明底板，键小、无网格、地球在右下角。
- 架构不变：`KeyboardController: UIInputViewController` 承载 SwiftUI `KeyboardView`，地球仍是 UIKit 按钮并接 `handleInputModeList(from:with:)`；桥接协议（`SharedVoiceBridge`、租约、代次、`VoiceAction`）不动。
- 对标文档已批准的验收：“点击开始/停止，按住录音松开结束；开始未确认前松手也不能迟到启动”。键盘此前没有按住手势。

## Design

### 1. 表面与键帽

- 不再绘制任何不透明底色（`view`、`UIHostingController.view`、SwiftUI 背景全部清除），由 `UIInputView(.keyboard)` 提供系统键盘底板材质。
- `UIHostingController` 的 `safeAreaRegions` 置空（`KeyboardView` 另加 `ignoresSafeArea()`）：键盘视图底部有 5pt 安全区，不置空时 SwiftUI 把内容整体上提 2.5pt，所有键都比系统键盘偏高（第一次真机对照在这里失败，删除键垂直中心 881.0 对 883.5）。
- 键帽（所有键同一样式）：纯平、无阴影；填充是**半透明白色**：浅色 0.85、深色 0.165（五种背景下与系统键帽逐通道相差 ≤ 5；原先的不透明 `#FFFFFF` / `#464646` 只在单一背景下像系统键帽，已被用户指出并更正）；连续圆角，竖屏 10pt、横屏 12pt（按系统键盘角部轮廓逐行比较后定；横屏 12.5 比系统大约 1pt，故取 12）；按下态深色白 0.27、浅色灰 0.80 × 0.5（按下态未单独测量，只对单一背景做过取样，属估计）。
- 强调色：文字/图标默认 `.primary`；语音键空闲态与激活链接使用蓝色（浅色 `#0057C2`、深色 `#80BDFF`，均 ≥ 4.5:1），录音态键帽为红色 `#C72420` 配白色图标与波形；`插入` 是蓝色实心键（对应系统“搜索/前往”动作键）。

### 2. 网格（iPad）

实测值（iPad mini，pt）。键区高度指系统辅助栏（55）以下部分。

| 量 | 竖屏（宽 744） | 横屏（宽 1133） |
| --- | --- | --- |
| 左右边距 | 6 | 7 |
| 键间距 | 12 | 13.5 |
| 键高 / 行距 | 55 / 64.5 | 73.5 / 85.5 |
| 键区上边距（到第一行键顶） | 8 | 12 |
| 键区下边距 | 28.5 | 31 |
| 键区高度 | 285 | 373 |
| 底排：地球键宽 / 右侧键宽 | 56.5 / 91.5 | 88.5 / 140 |
| 第一行：删除键宽 | 67.5 | 107.5 |
| 圆角 | 10 | 12 |

以上是 iPad mini 的实测值，作为参照网格；其他宽度的 iPad 把整套数值（含键高、行距、圆角）按“屏宽 ÷ 参照宽”线性缩放。这只在 iPad mini 上校准过，其他机型的偏差属于已知限制，不宣称对齐。

**网格的选择按设备类型而不是只看宽度**：`userInterfaceIdiom == .pad` 且宽度 ≥ 600pt 用上面的缩放网格；iPhone 和窄于 600pt 的宽度（iPad 浮动键盘）用紧凑网格，不做对齐承诺：

| 量 | 紧凑 竖屏 | 紧凑 横屏（iPhone） |
| --- | --- | --- |
| 边距 / 间距 | 4 / 6 | 4 / 6 |
| 键高 / 行距 | 44 / 56 | 38 / 46 |
| 键区上 / 下边距 | 8 / 12 | 6 / 8 |
| 键区高度 | 232 | 190 |
| 地球键宽 / 右侧键宽 / 删除键宽 | 44 / 84 / 56 | 56 / 100 / 72 |
| 圆角 | 6 | 6 |

iPhone 横屏时键区按 `view.safeAreaInsets` 的左右值内缩（刘海一侧与系统自带的地球/听写键让位），iPad 左右不内缩。

键盘视图高度 = 键区高度 − 底部留白：iPad 上系统在输入视图下方另加 20pt 底部留白（竖屏 265、横屏 353），这样辅助栏顶边与系统键盘一致（竖屏 793、横屏 316）；紧凑网格没有这 20pt（`bottomSpacer = 0`）——第一版把 20 当成常量，紧凑网格的视图高度（212）小于网格底边（220），底排被裁掉 8pt，地球键不可点（iPhone Air 模拟器上 `testProductGlobe` 失败暴露了它）。方向由 `windowScene.effectiveGeometry.interfaceOrientation` 判定，变化时在 `viewWillTransition` / `viewDidLayoutSubviews` 里重算。无障碍字号下视图再加高 120pt，见第 6 节。

### 3. 布局（键区内，自上而下）

- **第 1 行**：状态胶囊（`keyboard.status`，弹性宽度）· [取消键，仅录音/准备/识别中] · 删除键（系统删除键位置）。
- **第 2–3 行（主区，高 = 2 键高 + 1 行距间隙）**，按状态互斥：
  - 有结果：结果卡片（键帽色，内部可滚动，`keyboard.result`）+ 蓝色 `插入` 键（宽 = 两个右侧键 + 间距，`keyboard.insert`）；
  - 待命未运行且不是“完全访问”问题：整宽链接键“打开 Utter 启用语音输入”（`keyboard.activate`，`Link`）；
  - 其余：整宽语音键（`keyboard.start` / `keyboard.stop`）。准备/识别中显示进度并禁用；不可用（无租约、完全访问关闭）为灰色禁用键，不带标识符。
- **第 4 行（底排）**：地球（最左，系统键盘地球键的位置）· 空格（弹性）· 换行（右侧键宽）。
- 状态胶囊、结果、语音键之外不再有单独提示文字；提示写在语音键里（“点按开始，或按住说话”、录音中“点按结束”/按住时“松开结束”）。

### 4. 地球键

- 仍是 UIKit `UIButton`，标识符 `keyboard.globe`，点按切换下一个键盘、长按弹出输入法列表（`handleInputModeList(from:with:)` 不变）。
- 键帽外观与其他键一致；可见区域位于系统地球键同一位置；点击热区 frame 与系统地球键一致（左 3、上 1、右 9、下 8.5 的外扩，竖屏约 69×64.5）。
- 键盘上只有一个自绘地球键：右下角的旧地球键删除。iPhone（Face ID）上系统会在键盘下方另画一行地球与听写键，iPhone Air 模拟器截图里它与 Utter 底排最左的地球并存（旧布局右下角的地球同样与它并存，不是这次引入的）。是否在 `needsInputModeSwitchKey == false` 时隐藏自带地球，需要真机 iPhone 的证据，本次保持“始终显示自带地球键”，避免回归 `testProductGlobe`。

### 5. 语音键交互

触摸由 UIKit `UIControl`（`PressSurface`，透明叠在 SwiftUI 键帽上）提供 touchDown / touchUp / cancel，并把它作为唯一的 accessibility 元素（button，标识符 `keyboard.start`/`keyboard.stop`）；`accessibilityActivate` = 点按语义，所以 VoiceOver 双击、XCUITest 点按行为不变。

手势到桥接动作的映射是纯逻辑 `VoiceKeyGesture`（`UtterKeyboardBridge`，只依赖 Foundation）：

| 按下时语音状态 | 松开时 | 输出 |
| --- | --- | --- |
| 空闲 | — | 按下即 `start`（按住不丢开头） |
| 空闲后按下，持续 < 0.4 秒 | 松开 | 无（点按语义：继续录音） |
| 空闲后按下，持续 ≥ 0.4 秒，已在录音 | 松开 | `stop`（按住说话） |
| 空闲后按下，持续 ≥ 0.4 秒，仍在启动中 | 松开 | `cancel`（吊销租约，不迟到启动） |
| 录音中按下 | 在键内松开 | `stop`（点按结束） |
| 录音中按下 | 键外松开或触摸被系统取消 | 无 |
| 启动中/识别中按下 | — | 忽略 |

按住期间系统取消触摸等同松手（`stop`/`cancel`）。无障碍激活：空闲 → `start`，录音 → `stop`。`prepare()` 的租约、代次、签名校验、`cancel` 对未确认启动的处理保持原样，桥接协议不变。

### 6. 大字号与无障碍

- 动态类型进入无障碍字号时放弃上述网格（网格里的文字放不下），视图加高 120pt：上部是一个 `ScrollView`（状态胶囊 `status`、主区、`插入`或`取消`），其中 `activate` 通过滚动到达；底部固定一行 地球·删除·空格·换行（均不滚动、高 ≥ 44），位置仍贴系统底排，地球仍在最左。普通字号下没有外层滚动，状态行与键盘行不会被推走。
- 状态胶囊在无障碍字号下不限行数，普通字号限两行；结果卡片随动态类型缩放；减弱动态效果时波形换成静态图形、进度换成沙漏。
- 所有键保留原 accessibility 标签；地球键标签仍为“切换键盘”。

### 7. 文本

`TranscriptionSanitizer.normalizeInput` 做两条规整：删除全角标点（`，。、；：！？（）「」『』【】《》`）之前的空格，以及这些标点之后的空格。Apple SpeechAnalyzer 逐段返回的文本在段落边界带空格，是“见面 ，请”的来源；规整放在共享清理里，macOS 与 iOS 同时受益。引号、撇号和 ASCII 标点不动，所以 `’90s`、`rock ’n’ roll` 这类英文不受影响；括号两侧的空格一并去掉，是全角括号本身已带间距的缘故。

## Safety and failure modes

- 不新增权限、数据或网络行为；桥接协议、租约/代次/单次消费语义不变，隐私与安全回填边界不变。
- 按住手势的失败侧都收敛到“不录音或结束录音”：未确认启动就松手走 `cancel`；触摸被系统取消视为松手；键外松手不会误停点按录音；多指或重入按下被忽略。
- 启动失败（`prepare` 返回 false）时松手无输出，状态不残留 `pending`。
- 视图高度或网格计算错误只影响外观；高度常量在窄宽度（浮动键盘）回退到紧凑网格，不遮挡输入。
- 去掉不透明底板后若系统不提供底板材质，键盘会变透明；这一风险由真机截图（四种组合）核实，若出现则回退为 `UIInputView(.keyboard)` 显式构造。

## Test strategy

| 验收标准 | 手段 |
| --- | --- |
| 1–5 地球位置、总高、表面、键帽、形状与网格 | 真机同一次运行内先测系统键盘、再测 Utter（`UtterDeviceKeyboardReference.swift`）：frame 偏差、取样点颜色、圆角轮廓；四种组合并排截图人工查看 |
| 6 行为不变 | 既有真机键盘用例原样运行：KeyboardSpeech、AfterIdle、DisplacedByVideoRecovers、DocumentLifecycle、AppearanceAndVoiceOver、ReduceMotion、MaximumText |
| iPhone 不回归 | iPhone Air 模拟器：`testProductGlobe`、新增 `testProductKeyboardLayoutPortrait/Landscape`（四个编辑键可点、在屏幕内、地球最左、删除在顶行）、既有键盘传输与编辑流程；最大字号下同一对布局用例（`xcrun simctl ui … content_size`）。模拟器需先卸下硬件键盘：`swift scripts/sim-hardware-keyboard.swift <UDID> off` |
| 模拟器作为 iPad 的补充证据 | iPad mini（A17 Pro）模拟器上同一条 `testDeviceKeyboardNativeAlignment`；它与真机的系统键盘 frame 逐项相同时，才把模拟器结果当作补充证据；同一对布局用例在最大字号下运行 |
| 9 按住说话 | 新真机用例：按住语音键并播放固定语音，松开后出结果、插入一次；脚本支持延迟播放，让语音落在录音开始之后 |
| 10 不迟到启动 | 纯逻辑单元测试（状态机全部分支）+ 新真机用例（短按住松手后 4 秒内不为 recording） |
| 11 标点空格 | `TranscriptionSanitizerTests` 新增用例；真机固定语句结果 |
| 8 门禁 | `sdlc-checks`、`ci-basic-checks`、`swift test`、iOS `build-for-testing` |

## Rollout and rollback

- 单个 PR 内的 iOS 键盘界面与测试改动，无数据迁移、无新权限。回滚 = 还原这些提交，旧布局（右下角地球）随之恢复。
- 不发布；合并与发布仍按既有门禁和人工批准。
