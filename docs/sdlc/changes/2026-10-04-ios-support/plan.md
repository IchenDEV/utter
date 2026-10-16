# Plan: Utter iOS 语音输入

**Status:** approved
**Approved-by:** 用户（本对话，针对实施计划回复：“批准”）
**Approved-date:** 2026-10-04
**Upstream:** [spec.md](spec.md)

## Baseline and scope

2026-10-06 继续共存诊断：仅混音音频会话对照通过；不显式操作音频会话的视频通话源、普通 sample-buffer 源均在两种顺序复现共存失败。后启动者播放时先启动的候选停止，或候选启动使外部视频暂停并退出 PiP。详见 [因果隔离证据](ipad-comprehensive-test.md#pip-coexistence-causal-isolation-2026-10-06)。三项门槛未放宽，候选不接入产品；本轮不录音、不播放固定语音。

2026-10-05 执行结果：按用户批准的 `doubao-voice-parity.md` 完成公开 PiP 候选的真实后台录音、精确回填、外部视频两种顺序和 App 切换对照。候选共存失败，不执行有条件的产品接入；保留失败证据并恢复正常 Release。五分钟/十轮三宿主、长期闲时与脱离 XCTest 对照不记通过；完整语音体验、下载/解码取消和辅助功能仍未验收。后续后台设计须以三项门槛不变为前提重新决策，不沿用本候选的局部通过冒充整体可用。

用户已于 2026-10-04 分别批准 [spec.md](spec.md) 与本计划，开始源码实现；真机验证与最终验收仍需实际证据。
工作分支 `t3code/ios-voice-input-research`；父分支 `t3code/modularize-plugin-architecture`，检查点 `6044cef29ee9edff87d9aa843d1893a040e7dd1d`。
复用共享 Runtime、Session、数据和处理模块，移动端只实现录音、权限、键盘桥及原生包装。
第一版为 iPhone / iOS 27；云端默认关闭，历史默认不记录，基础输入不依赖自带大型模型或 Mac。

用户随后明确要求：“现在没有，先在模拟器上开发完成，然后再上实机。”因此先完成可在模拟器验证的实现与检查，再进行第 4 步真机门槛；未验证的后台能力与候选模型不标作可用。Air 组合门槛与最终验收标准保持不变。
每步保留可复现的检查结果，不提前推送半成品或创建 PR。所有 Swift 构建串行运行，避免共用 `.build` 时相互干扰。

## Exploration cleanup scope

2026-10-05 用户指令“移除多余的失败探索方向”授权本次收敛：删除独立 BG/Shortcuts/灵动岛替代入口探针与重复报告；保留 Link 首次激活、standby 候选和正式产品回归门槛。验收为无活动引用指向删除代码，产品源码及保留探针哈希不变，SDLC/basic/Swift 检查通过。此清理不改变已批准的隐私、产品界面或后台能力要求。删除前的源码与报告存于本机 `/private/tmp/utter-retired-wake-explorations-20261005.tar.gz`，可按需解压回滚；不回退父分支。

## Physical iPad test scope

2026-10-05 用户连接 iPad mini (A17 Pro)，要求“先用它测试”“继续”，并亲自完成开发者信任。沿用已批准实现与独立实验范围：先验证真实开发签名、App Group、固定文本会话，再验证保留的 PiP 候选。探针可复制构建到真机，只对实验副本启用 iPad 原生设备族；正式产品仍是 iPhone。第一轮只检查 PiP 支持、真实启动及确认停止，不请求麦克风或键盘完全访问，不把结果外推到 Air。停止必须观测 active/suspended 均为 false，失败不得发布成功状态；需独立复核。设备签名不降级。回滚为重装正常 Utter 并停止探针；不删除用户数据。

## User-directed product expansion (2026-10-05)

用户明确要求原生 iPadOS、模型下载与移动端适用设置、中央大麦克风/右下角地球/取消的产品键盘和触感反馈。这项直接实施指令覆盖此前“仅 iPhone、唤醒门槛前不扩充界面/模型”的范围限制；不改写先前阶段批准，也不代表原生后台调用已经通过。

实现采用 iPhone 底部导航和 iPad 原生侧栏；模型复用桌面目录/下载/取消/校验，优先呈现轻量本地语音模型；设置只呈现已经接入行为的语言、个人词典、录音时长、音频敏感度、键盘反馈及隐私/存储。用户指令未授权云端传输、静默录音、隐藏 PiP 产品化或外部发布。键盘保留真实状态与原生调用失败，不能用假录音动画掩盖系统门槛。触感使用 UIKit 并遵守设备能力，iPad 无震动能力时不伪称实测通过。

验收：iPad 原生设备族与分屏/横竖屏布局；模型真实下载/取消/删除/重启后状态与选择；设置持久化且影响下一次会话；键盘基本编辑、地球切换、中央按钮与取消可达；中英文与大字号截图/交互。用现有合成文本流程验证，不启用真实麦克风；运行仓库检查与独立复核。保留真实语音/后台未验项。回滚仅撤回本次产品扩充，不删除已下载模型或用户词典。

## Work items

### 1. Prepare shared modules and native bundles

- [ ] 开始实施前检查工作树及父分支最新提交；父分支更新时保留 iOS 差异、记录新基线并验证受影响部分，不改写父分支。
- [ ] 在 `Package.swift` 加入 iOS 27 和 `UtterMobile`、`UtterKeyboardBridge` 库产品；移动端门面在同包内调用已有 `package` API。
- [ ] 使 Runtime、Contracts、Data、Processing、Session、MediaContracts、AppleSpeech 能编译到 iOS；按目标平台条件和源文件隔离桌面 API，不复制核心代码或通过清单执行主机判断目标平台。
- [ ] 调整现有模块/资源边界检查的声明，使新增模块接受同样的边界验证；不移除桌面检查或放宽全部导入限制。
- [ ] 创建 `iOS/Utter.xcodeproj` 与共享 `UtteriOS` scheme，包装主 App、`UtterKeyboard` 和 `UtterLiveActivity` 三个生产 bundle，依赖本地根包。
- [ ] 使用签入的原生工程和 xcconfig；不新增 XcodeGen/Tuist 依赖。构建产物写入 `.build-ios/`，确认该目录不被提交。
- [ ] bundle/App Group 标识通过构建配置传入；只申请录音、Live Activity、共享容器所需能力。键盘声明完全访问，不获得麦克风能力。
- [ ] 主 App、键盘、Live Activity 的 Intent 声明使用原生目标共享源文件，并验证各自 Intent 元数据和 `.main` 执行目标；不依赖 SPM 自动发现。
- [ ] 原生包装使用共享的 `L()` 薄封装，引用现有 Contracts 的中英文字符串资源；核心模块保留既有 Loc。扩展不因本地化引入移动运行时或推理依赖。
- [ ] 加入 `scripts/build-ios.sh` 与设备验证说明；区分无签名编译、模拟器运行、已配置开发团队的设备安装。签名失败不降级为 ad-hoc。

退出条件：桌面现有检查保持通过；三个 bundle 可编译到 iOS Simulator 和 iPhoneOS SDK，键盘依赖图中没有推理模型或桌面模块。
尚未完成签名或连接时仍可完成编译与静态检查，不能把这项退出条件记作真机安装成功。

### 2. Implement the bounded keyboard bridge

- [ ] `Sources/UtterKeyboardBridge/` 仅使用 Foundation；实现版本、generation、租约、请求和文档 UUID、到期时间及动作的有界消息。
- [ ] 执行命令 4 KiB、结果 32 KiB 限制；UUID 生成路径，拒绝未知动作/版本、损坏、过期和非当前 generation 消息。
- [ ] 使用原子文件写入和文件协调；共享容器仅保存短时命令、状态和结果，模型、录音、词典及凭据留在主 App 私有目录。
- [ ] 键盘可见期间创建租约，文档、文本、选择、输入模式或可见性变化撤销它；活动状态查询结束后停止，不依赖通知唤醒后台主 App。
- [ ] 插入前重查 `documentIdentifier`、租约、generation 和消费状态；先持久化消费再调用 `insertText`。消费失败不插入，崩溃边界为 uncertain 且不自动重放。
- [ ] 结果只显示在有效会话；失效时提供短时显式恢复或主 App 复制。插入/丢弃清理结果，未处理结果两分钟后在下次访问清理。
- [ ] 验证完全访问关闭、App Group 缺失、锁定后读取失败和主 App 重启时明确失效，基本删除、空格、换行及键盘切换仍可用。

退出条件：使用真实共享文件及模拟宿主的两个输入框，正常结果单次插入，重复动作、延迟结果与字段切换不会误写。
录音尚未接入时明确显示未启用，不用模拟状态充当可用语音入口。

### 3. Implement one local recording workflow

- [ ] `Sources/UtterMobile/` 组合一个 `PluginRuntime`，挂载现有 Session 执行器，提供小范围 App 控制门面；不挂载桌面服务或复制桌面 VoicePipeline。
- [ ] 移动端实现 `CaptureService` / `OwnedRecording`，使用 AVAudioEngine、AVAudioSession 与受保护的主 App 临时音频文件。
- [ ] 用户启用时按需申请麦克风及所选 Speech API 必需的授权；状态明确区分未授权、本地资产未准备、录音、处理与失败。
- [ ] 复用 Apple Speech 引擎并验证 iOS 可用性及本地支持，安装目标语言资产；兼容路径保持 on-device 请求，缺少本地能力不联网兜底。
- [ ] 移动工作实现现有 `SessionWorkflowFactory` / `SessionJob`；冻结设置、提供方与词典，复用处理模块，以 `.returnedText` 返回结果，默认不提交历史记录。
- [ ] 实现 120 秒上限、取消/停用/中断/租约超时处理；先停止 tap 和采集、排空回调，再释放资源。租约失效后五秒内停止录音。
- [ ] 音频会话允许其他播放共存；结束时停用会话并通知其他音频恢复。蓝牙选项使用实际 iOS SDK API。
- [ ] 完成最小主 App 启用/停用、键盘开始/结束/取消/插入和 Live Activity 的真实状态与停止动作；文字使用 `L()` 中英文资源。
- [ ] 开始使用 `AudioRecordingIntent`、`.main` 执行目标与后台偏好，并在录音期间保持 Live Activity。错误执行在扩展时明确失败。
- [ ] 主 App 终止或重新启用创建新 generation；删除残留临时录音和旧结果，不恢复旧工作。

退出条件：主 App 可独立完成本地录音；键盘可通过 Intent 请求同一 Session，录音结束/取消后资源释放，结果不被当作已经写入宿主。
后台运行和再次启动仍待下一步的真机证据。

### 4. Pass the iPhone Air feasibility gate

- [ ] 准备用户指定的开发团队、App Group 和已连接的 iPhone Air / iOS 27；记录系统版本、构建提交及签名方式，不扫描或迁移私人凭据。
- [ ] 首次在前台启用后，在真实宿主从键盘连续完成十次录音，其中两次在闲置五分钟之后。录屏核对没有切到主 App，记录触发、首个结果与结束耗时。
- [ ] 观察结束/取消后麦克风指示消失及 capture/session 已停；录制三十分钟闲置的 CPU、内存、能耗和热状态，确认自动锁屏有效。
- [ ] 验证“其他视频 PiP → 首次启用 → 录音”和“启用 → 其他视频 PiP → 录音”；系统视频源及第三方视频源均保持播放，无残留窗口、把手或遮挡。
- [ ] 验证 Live Activity 权限关闭、键盘收起、主 App 强退/系统终止及重新启用。Live Activity 存在不能单独作为后台存活证据。
- [ ] 对基础界面做真实点按、键盘切换与取消检查，并记录浅深色、Air 尺寸、Dynamic Type 和 VoiceOver 的初步证据。
- [ ] 将逐次记录、录屏路径和 Instruments 结果写入 `verification.md`，标注通过、失败及不可验证项。

通过标准：意图第 3–5 项同时成立，含闲时 CPU 平均低于 1%、无麦克风采集/推理、十轮无 serious/critical 热状态。
任一组合条件不成立时停止后续产品扩充，保留最小复现、失败的系统条件和可选调整，回到 intent 请求范围审批。
真机或签名未准备时记录对应证据缺口；不得用模拟器、每次跳转或持续录音替代通过标准。

### 5. Complete local input and recovery

- [ ] 在至少三个允许第三方键盘的真实宿主验证普通话、英语、中英混说和个人词典；数字、否定、专有名词保真单独留样。
- [ ] 本地资产准备完成后开启飞行模式并关闭 Wi-Fi，完成本地识别和词典纠错；结合运行时服务挂载/请求记录验证云端关闭无上传。
- [ ] 完整覆盖撤销权限、来电/Siri、蓝牙变化、键盘/App/输入框切换、连续点击、迟到结果、取消、设备锁定与重启。
- [ ] 用实际 Session、桥文件和宿主输入完成故障注入：过期/损坏消息、旧 generation、消费写入失败、消费后终止、不再自动投递及资源排空。
- [ ] 故障注入与 E2E 放在测试配置/现有脚本体系；发布构建不包含测试入口。不新增逐函数或镜像实现的单元测试。
- [ ] 验证音频在成功、失败、取消后删除，日志无正文/密钥，历史默认关闭，共享容器不含模型、词典、凭据或原始音频。
- [ ] 完成原生首次设置、词典、模型状态、停用及本机数据清理；Keychain 由显式清理动作删除，不承诺卸载清除。

退出条件：基础离线流程及意图第 1、2、6、7 项有设备证据；失败状态可恢复，不出现永久录音或旧结果误插。

### 6. Admit optional inference and cloud paths

- [ ] 先比较已通过基础场景的 Apple Speech 与孔夫子 MLX 4-bit，再用 Qwen3-ASR 0.6B 对照；沿用已有下载、完整性与取消机制，固定模型版本。
- [ ] 为孔夫子及较小 ASR 记录质量、冷/热加载、主 App 和扩展各自峰值内存、可用内存、后台执行、十轮耗时与热状态。
- [ ] 3–15 秒语音热启动结束至结果目标 P50 ≤ 2 秒、P95 ≤ 5 秒；冷启动单独记录。只有后台键盘实测通过的引擎才成为可选项。
- [ ] 若 MLX 候选不满足后台或资源条件，保持 Apple 基础输入可用并记录缺口，不自动引入 GGUF 第二套运行时。
- [ ] Foundation Models 仅在本地模型可用时启用；处理拒绝、限流及取消，无能力时保留本地转写。Qwen3.5 0.8B 为单独测试候选，2B 不进入默认路径。
- [ ] 自带模型在闲置一分钟或内存压力下排空并释放；验证切换、下载取消、损坏文件与低可用内存，不用下载体积推算 RAM。
- [ ] 主 App 复用现有远端客户端，手机私有 Keychain 实现凭据服务；音频 ASR 和文字整理分别显式开启，冻结每次工作的许可。
- [ ] 用受控传输端验证关闭时零相关请求、开启时只发送选中的音频或文字，以及断网、超时、凭据错误、撤销后可取消且无重复输入。

退出条件：意图第 8 项通过；每个模型的前台/后台可用性及性能单独标注。候选性能不足不影响基础识别，不发布未经验证的键盘选项。

### 7. Verify compatibility and prepare handoff

- [ ] 执行下面的完整自动化与设备矩阵；收集提交、命令、退出码、设备步骤、截图/录屏及 Instruments 证据。
- [ ] 每次修改后先跑受影响检查；冻结实现时执行一轮完整仓库测试、iOS 构建和桌面 release-style 构建，避免无变更的重复全量运行。
- [ ] 界面交付前完整重读 ANTI_SLOP，逐项检查适用字体、色彩、对齐、裁切、真实控件和动画；实测所有动作并修复问题，记录不适用项与证据缺口。
- [ ] 按 [review-policy.md](../../review-policy.md) 安排独立、全新上下文的只读验证，复查权限、隐私、结果消费、取消、云端关闭和 macOS 兼容；修复发现后重验。
- [ ] `verification.md` 完成证据并设为 pending approval，交由用户验收；代理与独立验证者均不能替用户批准。
- [ ] 保留仅撤回 iOS 子分支提交的回滚步骤，不回退父重构或迁移桌面数据。

## Verification plan

所有下列构建命令使用命令级 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`，不修改系统 `xcode-select`。

| Check | Planned command or evidence |
| --- | --- |
| 阶段与模块/资源/本地化检查 | `bash scripts/sdlc-checks.sh`、`bash scripts/ci-basic-checks.sh`。 |
| 现有 Swift 测试 | `swift test`；记录模块结果及硬件/模型跳过项，不把跳过计作通过。 |
| iOS Simulator 编译 | `xcodebuild -project iOS/Utter.xcodeproj -scheme UtteriOS -configuration Debug -destination 'generic/platform=iOS Simulator' -derivedDataPath .build-ios/simulator CODE_SIGNING_ALLOWED=NO build`。 |
| iPhoneOS SDK 编译 | 同工程/scheme，`-destination 'generic/platform=iOS' -derivedDataPath .build-ios/device CODE_SIGNING_ALLOWED=NO build`；此命令不安装真机。 |
| iOS E2E | `xcodebuild test` 使用明确的已启动模拟器 ID、同一 scheme 和独立 DerivedData；模拟宿主多字段、迟到结果及实际桥消费路径。 |
| 设备安装与录音 | 配置用户指定团队后签名构建，在 Air 安装并记录实际步骤；不提交团队凭据或设备标识。 |
| 桌面 release-style 编译 | `xcodebuild -scheme OpenType -configuration Release -destination 'platform=macOS' -derivedDataPath .build-ios/macos-validation ARCHS=arm64 ONLY_ACTIVE_ARCH=NO CODE_SIGNING_ALLOWED=NO build`；检查 Metal 资源，不当作已签名发布。 |
| 原生运行与可视检查 | Air 实际键盘与 Live Activity、主 App 的浅深色/横屏/Dynamic Type/VoiceOver；桌面运行检查仅覆盖受影响组合路径。 |
| 隐私与取消 | 受控服务传输记录、临时/共享文件检查、权限撤销与故障注入；不记录用户实际正文或密钥。 |

以下编号对应 [intent.md](intent.md) 验收标准；各项都须有具体通过证据或明确未通过原因。

| Intent | Execution step | Required evidence |
| --- | --- | --- |
| 1 | 4、5 | Air 安装信息，至少三宿主、三语言流程，单次插入录屏。 |
| 2 | 5 | 飞行模式与 Wi-Fi 关闭、云端关闭、本地资产状态、词典结果及无上传证据。 |
| 3 | 4 | 十次键盘发起的逐次记录、两次五分钟闲置后启动、宿主持续前台录屏。 |
| 4 | 4、6 | 麦克风指示与 capture 停止证据，三十分钟闲时 Instruments、自动锁屏与热状态。 |
| 5 | 4 | 两种先后顺序、系统与第三方 PiP 的持续播放和无遮挡录屏。 |
| 6 | 2、5 | 多字段/宿主切换、键盘隐藏、重复点击、迟到结果与消费后终止的 E2E 记录。 |
| 7 | 3–5 | 权限、来电、蓝牙、强退、重启及 generation 失效矩阵，后续恢复步骤。 |
| 8 | 6 | 分别开启 ASR/整理、关闭零请求、超时/错误/撤销、凭据隔离记录。 |
| 9 | 1、7 | 构建与检查退出码、桌面兼容、真实设备操作、ANTI_SLOP 及独立验证记录。 |
| 10 | 4 | 第 3–5 项的组合结论；失败则停止扩充并提交范围调整。 |

## Human gates and rollback

- 本计划批准后才进入源码实现；批准不代表尚未完成的真机验证或最终验收已通过。
- 用户确认开发团队与 App Group，并连接 Air 后进行设备安装；这属于本地开发验证，不授权 TestFlight/App Store 或外部发布。
- 组合门槛失败或需要改变最低版本、闲时采集、跳转、PiP/私有 API 策略时，回到 intent/spec 审批，不能自行降级原目标。
- 完成实现与独立验证后，提交 verification 审批；推送、PR、合并、签名发布与部署仍需对应明确指令。
- 回滚只撤回本次 iOS 子提交；手机内先停止会话/录音，按用户选择清理模型、结果与 Keychain，再移除 App/键盘；桌面数据不迁移。

## Preparation evidence

- 用户在上一轮明确回复“批准”，本轮仅记录 spec 审批并编写此计划；无应用源码、工程、依赖或签名修改。
- 本轮只读确认当前 HEAD 与已选择父分支均为 `6044cef`；工作树仅有本 SDLC 文档包。
- Xcode 27 的 iPhoneOS / Simulator 27.0 SDK 可用；未修改系统开发目录。本机无 XcodeGen/Tuist，计划使用签入的原生工程。
- 前一阶段在该父提交上已通过 SDLC、basic 与 Swift 测试；本轮 `bash scripts/sdlc-checks.sh` 退出码为 0。四份文档的状态、行数、空白、相对链接及全部十项验收映射检查通过；不重复运行未变化的 Swift 基线测试。
- 尚无 Air 签名安装、后台录音、PiP、延迟或资源证据；本计划的命令与退出条件是待实施要求。

## Implementation checkpoint

2026-10-04：批准后的实施结果详见 [verification.md](verification.md)。原始工作项保留为批准时的要求，以下记录退出条件，不能用“有源码”代替通过。

| Step | Current exit condition |
| --- | --- |
| 1 | 共享模块、三个原生 bundle、Simulator Debug / Release、iPhoneOS 无签名及桌面 release-style 构建通过；真实安装未验证。 |
| 2 | Foundation 桥故障场景、显式前台模拟宿主中的实际单次插入/字段切换/迟到取消隔离通过；原生启动门槛仍失败。 |
| 3 | 共享 Session 的主 App 合成文字流程通过，录音/本地识别源码已编译；键盘调度失败，真实麦克风与本地资产未验证。 |
| 4 | 模拟器已提供当前公开 Intent 路径失败证据；Air 真机组合门槛尚无证据，按批准要求停止扩充并返回入口设计。 |
| 5–6 | 除最小恢复/词典/清理与故障检查外，完整设备恢复矩阵、自带模型、LLM 与云端路径未进入验收。 |
| 7 | 仓库检查、桌面兼容构建、独立只读复核及指定模拟器交互已有证据；继续模拟器后补齐桥恢复、最大字号、岛上结束/取消、正常 Release 可见界面与最终双 SDK 构建。原生键盘调度与一项辅助功能裁切报告仍失败，VoiceOver/锁屏/真实音频矩阵未完成。verification 保持 blocked，没有最终批准或外部交付。 |

## Comprehensive physical iPad verification (2026-10-05)

用户要求“完整的测试一下在 iPad 上的表现”，并明确选择由旁边 Mac 播放固定语音供 iPad 录音。该直接测试指令扩展此前仅合成文字的验证范围；许可仅限明确测试窗口内的本机麦克风与固定中英文样本，不进行用户音频上传。复用已批准产品实现，以 Release 为主验证四向旋转、键盘编辑/切换、设置、词典、模型取消/重试/完整下载/重启/删除、正式页面无障碍、录音/识别/取消/后台恢复。需要额外 UI 测试与可访问性标识时一并实施，测试只删除自己创建的数据；已有模型不得预先删除，清空本机数据只测取消路径。保留真实失败，不把合成宿主、模拟器或未执行项算作设备通过。回滚为恢复原设置、删除本轮测试条目/下载、正常启动现有签名 Release；不降级签名，不发布。

### Physical-test corrective work, 2026-10-05

本次“完整测试 iPad”期间发现并修复录音 category-change 误取消、移动语言设置被共享设置覆盖、大字号侧栏/就绪状态呈现和 iOS 模型目录引用旧绝对沙盒路径。iOS 模型存储按当前 applicationSupport 解析，macOS 自定义目录行为不变；以已有 ModelFiles 回归和真实下载/取消/识别流程验证，不新建单元测试。模型目录修复由独立验证者复核。回滚为撤回该平台条件及本次移动修复后按原开发身份重装，不删用户数据；旧失败日志保留。该纠错属于已授权真机验证范围，不代表门槛或最终验收获批。

### Confucius physical-device test, 2026-10-05

用户针对孔夫子模型明确要求“测试”。复用已授权真机与固定语音流程，测试 Confucius4-R2T2-8bit 的真实下载/完整性校验、选择与重启持久化、真实中文录音识别和仅本轮下载数据的清理；不覆盖预先存在的模型。2.48 GB 下载允许最多 30 分钟，终端错误立即失败；恢复设置且不外部发布。此项补充已有测试范围，不代表此前未通过的产品门槛获批。

首轮网络失败后，补充分离离线/服务器连接/安全连接错误提示，不记录原始 URL、凭据或转写。真机复测确认为安全连接失败；不绕过 TLS。Mac 既有孔夫子 17 个文件通过固定版本的大小及 SHA-256 校验，可复制至设备私有模型目录单独验证识别，不能算设备网络下载成功。

### Doubao voice parity, 2026-10-05

用户确认以语音为核心，并另行回复“批准该方案，三项门槛不变”，批准 [后台方案修订与执行顺序](doubao-voice-parity.md)。先扩展独立探针以真实 VoiceHost/麦克风和外部视频宿主验证；只有免跳转、闲时麦克风关闭及视频 PiP 共存均通过才接入可关闭的产品实现。后续手势、文字整理、质量与辅助功能按修订验收表执行；不改写旧阶段审批或宣称最终验收完成。沿用原开发身份，外部宿主按普通第三方 App 权限运行，不要求访问 Utter 共享容器；探针状态在测试后提取。独立复核要求取消命令不能被转写等待阻塞，已改为有代次边界的任务执行，仍须真机复验。回滚恢复正常 Release，不删除用户数据。

2026-10-06 用户“继续研发”沿此授权继续独立待命诊断：三组无 I/O 与一组前台有限录音后暂停，均在无 XCTest/无调试器的 85 秒观测里出现长执行空档。暂停录音只用既有权限、最多 4 秒、Stop 撤销准备代次；真实失败不进入产品。正常 Release 已恢复，证据及测量限制在 [真机报告](ipad-comprehensive-test.md#debugger-free-standby-research-2026-10-06)。后续不同候选必须先证明独立执行机会，再进入按需音频/视频/键盘组合验收；不重复仅改窗口尺寸或以持续采集替代关麦。
