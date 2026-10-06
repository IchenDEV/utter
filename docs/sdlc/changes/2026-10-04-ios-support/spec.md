# Spec: Utter iOS 语音输入

**Status:** approved
**Approved-by:** 用户（本对话，针对本方案回复：“批准”）
**Approved-date:** 2026-10-04
**Upstream:** [intent.md](intent.md)

## Baseline and approval boundary

用户已确认 [intent.md](intent.md)，并明确要求使用 `t3code/modularize-plugin-architecture` 继续开发。
当前工作分支为 `t3code/ios-voice-input-research`，父分支检查点为 `6044cef29ee9edff87d9aa843d1893a040e7dd1d`。
此前编号 #462 无法在本仓库解析，后续以用户明确确认的分支为准，不创建或链接不存在的 PR。

本方案风险为 High，涉及录音权限、键盘扩展和跨进程结果交付。
用户已批准本方案。当前完成方案及父分支验证，进入实施计划；计划审批后才开始应用实现。
父分支的插件挂载和完整停用验收仍在进行；iOS 不承担完成整项桌面重构的职责。

## Decisions for review

| Decision | Proposed behavior |
| --- | --- |
| 第一版系统版本 | iOS 27，仅 iPhone；使用其主 App Intent 执行目标能力，暂不增加旧系统兼容分支。 |
| 构建组织 | 根 Swift Package 保留桌面产品；增加移动端 Swift 库。`iOS/Utter.xcodeproj` 只负责 App、键盘和 Live Activity 扩展的原生打包、资源与签名。 |
| 免跳转路径 | 先验证 `AudioRecordingIntent`、主 App 执行目标及 Live Activity。可行性未通过前不扩充完整设置或大量模型。 |
| 初始识别 | 系统本地 Apple Speech；独立评估孔夫子 MLX 4-bit 与 Qwen3-ASR 0.6B，合格后才提供对应键盘选项。 |
| 文本整理 | 基础输入不依赖 LLM。可用时提供系统本地 Foundation Models；自带 Qwen3.5 0.8B 4-bit 为候选，2B 只作后续性能对照。 |
| 结果投递 | 初版结束后显示结果，用户点击“插入”。字段或键盘会话变化时阻止旧结果自动进入新位置，保留短时显式恢复。 |
| 云端 | 默认关闭；音频识别与文字整理分别选择，沿用已有服务契约与远端客户端。 |

原生 Xcode 工程是 iOS 多 bundle 包装的新增组织方式，不替代 macOS 的 Swift Package 构建。
这是相对于现有“无 xcodeproj”组织方式的明确方案选择，须由本方案审批确认。

## Shared architecture

主 App 运行一次现有 `PluginRuntime`；键盘和 Live Activity 扩展不运行插件图。
移动端组合仅挂载所需服务，不包含桌面 HTTP/XPC、远程麦克风、快捷键、辅助功能、屏幕 OCR 或桌面展示。

| Module | iOS use and boundary |
| --- | --- |
| `UtterRuntime` / `UtterContracts` | 复用插件生命周期、服务键、冻结设置、提供方选择、结果和取消契约。 |
| `UtterData` | 复用词典、行业词库、设置及历史服务；注入手机沙盒目录，不读取 Mac 路径或凭据。 |
| `UtterProcessing` | 复用词典替换、清理、转写保真与提示词逻辑，不新增硬编码口头禅删除。 |
| `UtterSession` | 复用 `SessionPlugins.execution()` 和 `SessionDriver`；移动端工作实现现有 `SessionWorkflowFactory` / `SessionJob`，不复制桌面状态机。 |
| `UtterMediaContracts` | 复用录音、语音识别与处理接口；不挂载屏幕或图像功能。 |
| `UtterAppleSpeech` | 复用引擎、权限等待、模型准备与兼容路径；适配 iOS 可用性并验证本地识别边界。 |
| `UtterModels` / `UtterMLX` | 在系统识别闭环后按需接入主 App；先分离仍依赖桌面展示的目录和依赖，不能直接移入键盘。 |
| `UtterRemoteInference` | 在明确启用云端后由主 App 使用，键盘没有网络客户端或密钥。 |

新增 `UtterMobile` 库在同一 Swift Package 内使用已有 `package` API；对原生 App 只公开控制与状态所需的小门面。
新增 `UtterKeyboardBridge` 库只依赖 Foundation，承载有界消息与共享文件读写。键盘只依赖此库及系统 UI/App Intents。
App Intent 声明作为原生目标共享源文件，确保每个 bundle 有所需元数据；不假定源代码 Swift Package 自动导出 Intent 元数据。
扩展侧如果意外执行录音 Intent，应明确报错，不在键盘中录音或返回伪成功。

根包增加 `.iOS("27.0")` 和移动端库产品。平台相关依赖使用目标平台条件，源文件中的桌面 API 采用目标平台隔离。
清单的 `#if os(macOS)` 在 Mac 上执行，不能用它判断正在构建的是 iOS；移动端目标不得间接引入 AppKit、IOKit 或桌面 CoreAudio 设备 API。
同一个共享 Swift 文件保持一个模块所有者，不通过复制源文件或第二套“便携核心”绕过模块检查。

现有桌面 `voiceWorkflows()` 依赖 `MacServices.target/output` 和桌面权限观察；iOS 不通过伪造 PID、目标租约或桌面授权来接入。
移动端工作只编排实际录音、选中识别器、词典处理及结果返回，执行归属、取消和资源排空仍由共享 Session 驱动承担。
主 App 使用 `.returnedText` 表示结果已产生，不能把它展示为已经写入其他 App。

## First device feasibility gate

先实现最小主 App、键盘、共享结果及真实录音状态，而后才扩充完整产品。
主路径为用户首次在主 App 启用，键盘使用 `Button(intent:)` 提交开始/结束/取消动作。
录音 Intent 采用 `AudioRecordingIntent`，设置 iOS 27 `allowedExecutionTargets = [.main]` 和后台运行偏好。
这些配置是否能由第三方键盘触发、是否保持宿主在前台，均属于实测假设，不属于 Apple 对此键盘场景的保证。

执行时核对请求令牌，初始化或取得同一移动端 Runtime，并按需创建 Live Activity。
Apple 要求 AudioRecordingIntent 开始录音时启动 Live Activity，并在录音期间保持它活跃。
若需要额外 LiveActivityIntent 能力，先记录实际执行模式；不能因 Intent 类型名便认定不会前台跳转。
Live Activity 只展示录音/处理状态与停止、取消入口，不包含转写正文。

初次启用可以进入主 App；后续必须完成十次键盘发起的录音，其中两次在闲置五分钟之后。
结束或取消后移除输入 tap、关闭捕获并停用录音音频会话；闲时不读取麦克风、不播放静音音频或视频保活。
闲时 Live Activity 的存在不当作进程仍在执行的证据；再次启动必须验证系统重新调度主 App 的实际能力。
无 Live Activity 权限、模型未准备、主 App 被强制退出或能力不足时显示明确状态，不无限重试。

顺序验证视频 PiP → 首次启用 → 录音，以及启用 → 视频 PiP → 录音；同时验证闲置后自动锁屏。
本方案不加入透明/隐藏 PiP、不调用私有 API、不通过 responder 链调用扩展禁止的 UIApplication 方法。
公开机制失败时提交失败证据并回到 intent 调整范围；不能把每次跳转或闲时持续录音当作原目标通过。

## Recording and inference

移动端捕获实现现有 `CaptureService` / `OwnedRecording`，使用 AVAudioSession 和 AVAudioEngine。
麦克风权限在用户开始启用录音时申请；所选 Speech API 要求的授权单独按需请求，不在应用启动时统一索取。
音频会话允许与其他播放共存，结束时通知其他音频恢复；系统仍可能改变输出路由或音质，须实测视频 PiP 和蓝牙。
蓝牙输入输出能力按 iOS 27 SDK 实际可用选项设置，不复用桌面设备 ID 或默认麦克风监听。

一次只允许一个录音或推理工作。设置、词典、语言、提供方和云端许可在开始时冻结。
切换模型、撤销许可、取消或中断时，先拒绝新工作、停止采集并排空旧回调，之后才卸载模型或释放资源。
初版单次最长 120 秒，超时结束并显示已取得的结果或错误；恢复不自动重新录音。
键盘只在可见且会话活跃时维持租约；隐藏/失效立即撤销，主 App 在录音期间检测租约超时并在五秒内取消。
闲时不存在租约轮询或模型预热循环。处理期间取消必须可用，错误不得遗留“录音中”状态。

Apple Speech 先按目标语言安装系统管理的本地模型；缺少语言或本地能力时显示不可用。
兼容识别请求保持 `requiresOnDeviceRecognition`，不能因系统兼容路径悄悄联网。
普通话、英语和混说分别评价，不能以模型宣称支持多语言代替混说效果验证。

| Self-contained candidate | Download size | Admission requirement |
| --- | --- | --- |
| Confucius4-R2T2 MLX 4-bit | 约 1.62 GB | 优先比较当前桌面 8-bit 的中文、专有名词和弱语音效果，再测后台延迟/热状态。 |
| Confucius4-R2T2 官方 GGUF Q4_K_M + Q8 音频模块 | 约 1.46 GB | 与 MLX 路线的质量或后台可用性出现实质差异时再评估，初版不同时维护两种推理运行时。 |
| Qwen3-ASR 0.6B MLX 8-bit / 4-bit | 约 1.01 GB / 713 MB | 作为较小模型对照；采用实际兼容的配置与冻结版本，不把它当作孔夫子的蒸馏版。 |
| Qwen3.5 0.8B MLX 4-bit | 约 652 MB | 文本整理候选；非思考模式，上下文上限先设 2–4K，验证不改写数字、否定和专有名词。 |

自带模型下载由用户主动发起，使用已有文件完整性、取消和发布机制；不在键盘或首次启动时自动下载。
下载大小不是峰值运行内存。只显示已有测试证据支持的模式；无法在键盘后台场景完成的模型不列为可用键盘引擎。
MLX/Metal 前台可运行不代表后台可运行；iOS 后台 GPU/Neural Engine 权限和任务启动条件必须分别验证。
`BGContinuedProcessingTaskRequest` 需要前台用户操作提交，不能作为后台键盘每次唤起的默认解释。
系统 Foundation Models 只请求明确的本地模型，检查可用性、拒绝及后台限流；不可用时返回本地转写，不自动切云端。

拟定体验目标：3–15 秒语音，热启动结束到结果 P50 ≤ 2 秒、P95 ≤ 5 秒；记录冷启动及模型加载时间，不混入热启动指标。
连续十轮不崩溃、不丢失取消、不出现 serious/critical 热状态；三十分钟闲时麦克风关闭、CPU 平均低于 1%、没有推理工作。
记录主 App 和扩展各自峰值内存、内存警告及系统可用内存，不把整机 12 GB 当作应用预算。
自带模型在闲置一分钟或内存压力下排空后释放，重新使用时按冷启动指标评价；系统模型不承诺其资产由 App 立即卸载。
阈值是本方案提出的验收目标，尚无 iPhone Air 性能测量。

## Keyboard and message boundary

键盘为 `UIInputViewController`，使用 `UITextDocumentProxy` 插入、删除、空格和换行，并提供系统要求的切换键盘入口。
未开启完全访问时仅保留基本键盘操作和明确说明；主 App 仍可独立本地录音，键盘语音桥不假装已连接。
使用一个配置的 App Group 共享临时命令、状态与结果；模型、录音、个人词典和云端凭据留在主 App 私有沙盒。
App Group 和 bundle 标识采用构建配置注入，开发团队由用户指定，不扫描或修改现有签名凭据。

消息包含协议版本、Runtime generation、键盘实例/租约 UUID、请求 UUID、文档 UUID、动作、到期时间和有界结果。
文档 UUID 使用 `textDocumentProxy.documentIdentifier`，只用于当前输入目标核对，不持久化用于跟踪用户或 App。
键盘在文档、选择、文本、输入模式或可见性变化时撤销录音租约；前后文只在扩展本地校验，不默认发往主 App 或云端。
文档标识不等于跨进程原子输入事务，不能单独保证宿主字段和光标始终未变。

命令最大 4 KiB，单次结果最大 32 KiB；拒绝未知版本/动作、过期、重复或非当前 generation 的请求。
文件名由内部 UUID 构造，不采用请求携带的路径；使用原子写入与 Foundation 文件协调，单 writer 对应单个租约目录。
通知只表示“重新读取状态”，不是唯一事实来源或唤醒后台进程的保证；暂停的主 App 必须依靠经验证的 Intent 路径调度。
活动键盘可短时读取状态以补偿丢通知；离开键盘或结束工作立即停止，没有后台常驻轮询。

结果到达后只显示在原会话。用户点击插入时重新检查可见性、文档 UUID、租约、generation 和消费状态。
无效会话不自动投递；用户可显式确认向当前字段插入短时待恢复结果，或在主 App 显式复制。
先写入一次性消费状态，再调用 `insertText`；若扩展在调用前后终止，标记 uncertain，禁止自动重放。
`insertText` 没有事务提交回执，不能声称可在崩溃边界证明 exactly-once；验收要求正常流程仅一次，异常流程不自动重复。
消费失败先显示错误，不调用输入 API；一次结果的重复通知或连续点击不得导致第二次提交。
主 App 的完成状态和键盘投递状态分别展示，不把结果已产生当成宿主已经接受。

## Privacy and recovery

原始音频使用受保护的主 App 临时文件，成功、取消、失败后均关闭并删除；启动时清理中断遗留。
共享结果在插入、丢弃后清除，未处理结果最多保留两分钟；过期清理在下次访问或启动执行，不承诺暂停进程定时删除。
结果文件采用设备锁定时不可读取的文件保护，重启/锁定后不能投递旧结果；模型文件与敏感文件分开配置保护级别。
原始转写、处理文本、输入前后文和密钥不进入诊断日志；日志只记录非内容的阶段、耗时和错误类别。
历史默认不记录：移动工作不提交 `InputRecord`；用户主动开启后复用现有 HistoryStore，并提供清空入口。
云端凭据由手机用户配置，使用主 App 专用 Keychain 服务实现现有 CredentialsService，不采用共享 UserDefaults 存储密钥。
用户可分别开启云端 ASR 和云端文本整理；动作说明发送音频还是文字，关闭或撤销后当前工作取消且旧凭据观察被移除。
完全访问仅授权键盘桥能力，不自动启用上传、历史、学习或周边文本采集。

首次设置包含启用键盘、完全访问、本地能力准备和会话状态；设置使用原生表单与系统控件。
键盘只显示当前录音/处理/结果和必要动作；主 App 有明确停用、删除结果、模型删除和词典入口。
录音期间 Live Activity 显示可读状态和停止/取消，无透明模块、假按钮或装饰性录音指示。
所有文字走现有本地化，补充中英文；验证 VoiceOver、Dynamic Type、浅深色、横屏和 Air 实际尺寸。
按 ANTI_SLOP 逐项审查最终原生界面及真实交互；本方案阶段尚无界面或视觉验收结果。

| Failure | Required response |
| --- | --- |
| 麦克风/完全访问被拒绝或撤销 | 显示具体缺少的能力，取消当前捕获，保留基本键盘，不循环弹权限。 |
| Live Activity 不可用或后台启动失败 | 显示失效状态并停止录音；不创建隐藏 PiP 或自动打开主 App 掩盖失败。 |
| 主 App 强退、系统终止、重启 | 旧 generation 无效；用户重新启用，取消和结果不跨 generation 自动恢复。 |
| 来电、Siri、输入路由丢失、蓝牙变化 | 结束/取消并排空；恢复后需要用户新的开始动作。 |
| 键盘隐藏、字段改变、旧结果迟到 | 撤销原租约，阻止自动插入，仅保留短时显式恢复。 |
| 本地模型/后台推理失败 | 显示具体能力限制，返回可保留的本地转写；不隐式上传。 |
| 云端断网、超时、错误凭据 | 显示错误且可取消，不重试录音或重复投递，保持后续本地模式可选。 |
| 超限或损坏共享消息 | 拒绝读取/执行，清理当前消息，不影响其他租约或私有模型文件。 |

## Verification and rollback

实施计划须链接意图的十项验收要求，并列出可重复的真机步骤、录屏和 Instruments 证据。
先通过免跳转、闲时麦克风关闭和 PiP 共存这一组合门槛；随后才进行模型对照、完整 UI 和云端测试。
自动化覆盖实际 Session 的取消/排空、过期租约、旧结果、重复消费、未授权网络与消息边界；优先端到端和故障注入，不新增镜像实现的单元测试。
使用模拟宿主测试延迟结果和输入框切换；再在真机至少三个真实宿主、系统和第三方视频 PiP 中验证。
模拟器只证明构建、UI 和部分 IPC，不能证明 Air 的麦克风、后台唤起、能耗、蓝牙或 PiP 能力。
执行仓库 SDLC/basic 检查、完整 Swift 测试、桌面 release-style 构建和 iOS 模拟器/设备构建。
独立验证者审查权限、结果消费、取消、关闭云端无请求与父分支兼容性；按仓库 review policy 执行，记录结论而非自行批准。

回滚采用撤回仅属于 iOS 子分支的提交；不反向撤销父分支重构，不迁移或重写桌面设置。
手机 App 与扩展卸载可停止录音并清除共享容器；Keychain 残留由 App 内“清除本机数据”动作显式删除，卸载不承诺清除 Keychain。
本次不授权发布 App Store、推送、创建 PR 或部署。后续子 PR 的 base 使用重构分支，父 PR 合并后再按实际历史调整。
父分支更新后先同步到 iOS 分支并重跑受影响检查；记录新父提交和子分支差异，不能沿用旧提交验收结果。

## Preparation evidence

- 2026-10-04：当前分支已叠在父提交 `6044cef`；原六个宣传网站提交未被带入 iOS 子分支，原 iOS 文档保留。
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`：退出码 0。多个模块测试通过；OpenType 目标 488 项、18 项硬件/模型测试跳过。未将跳过项计作设备验收。
- 本机 SDK 中 `allowedExecutionTargets` 自 Apple OS 27 可用，主 App 目标实际枚举值为 `.main`；AudioRecordingIntent 自 iOS 18 可用。API 声明不证明键盘执行上下文可行。
- `bash scripts/sdlc-checks.sh` 与 `bash scripts/ci-basic-checks.sh`：退出码均为 0。方案文档的行数、结尾换行、空白与相对链接检查通过。
- ANTI_SLOP 已完整复读。当前设计要求包括真实状态与可操作的录音入口、精简原生控件、中英文本与辅助功能；没有伪交互或装饰性保活模块。字体、配色、对齐、裁切、动画与真实交互尚无界面可验收，实施时逐项检查并修复，不把本次文档审查计作视觉 QA。
- 当前没有 iOS 工程、应用源码、真机录音或上述性能数据；上述检查仅证明设计文档与重构基线通过现有检查。

## Primary references

- [自定义键盘完全访问](https://developer.apple.com/documentation/uikit/configuring-open-access-for-a-custom-keyboard)、[文本交互](https://developer.apple.com/documentation/uikit/handling-text-interactions-in-custom-keyboards)、[文档标识](https://developer.apple.com/documentation/uikit/uitextdocumentproxy/documentidentifier)。
- [AudioRecordingIntent](https://developer.apple.com/documentation/appintents/audiorecordingintent)、[Intent 运行模式与 bundle 元数据](https://developer.apple.com/documentation/appintents/configuring-the-runtime-behavior-of-your-app-intents)、[Intent 按钮](https://developer.apple.com/documentation/swiftui/button/init(intent:label:))。
- [SpeechAnalyzer](https://developer.apple.com/videos/play/wwdc2025/277/)、[本地 Foundation Models](https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel)、[后台任务条件](https://developer.apple.com/documentation/backgroundtasks/bgcontinuedprocessingtaskrequest)、[后台 GPU](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.background-tasks.continued-processing.gpu)、[后台 Neural Engine](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.background-tasks.continued-processing.inference)。
- [孔夫子 MLX 4-bit](https://huggingface.co/selcukkubur/Confucius4-R2T2-mlx-4bit/tree/main)、[孔夫子官方 GGUF](https://huggingface.co/netease-youdao/Confucius4-R2T2-GGUF/tree/main)、[Qwen3-ASR 0.6B 8-bit](https://huggingface.co/mlx-community/Qwen3-ASR-0.6B-8bit/tree/main)、[Qwen3.5 0.8B 4-bit](https://huggingface.co/mlx-community/Qwen3.5-0.8B-MLX-4bit/tree/main)。
