# Apple 平台边界与 Utter 现有所有者

Status: pending approval
Date: 2026-10-08 Asia/Singapore
Evidence-acquired: 2026-10-07 UTC, 21:11–21:16
Baseline: ed4234b41764be8346ae58cdc63011c8f26a0f1e
Scope: 独立只读调研；父线程验收；没有实现或批准后续阶段。

## 结论

macOS 已有可复用的目标租约与交付事务，但 AX 属性存在不等于宿主支持原位替换。特别是本机 Apple SDK 的公共头文件将 `AXSelectedText` 标为不可写，选区范围标为可写。现有直接写选中文本路径依赖运行时探测，仍需逐宿主验证。iOS/iPadOS 提供当前输入对象的代理编辑能力，不能据此承诺任意全文范围、完整上下文、原子替换或系统撤销。全访问不会授予键盘扩展麦克风能力。

## 证据分类与获取

- **D-current**：本次获取的 Apple 当前在线 API/文章。公开浏览器实际打开文本交互文章、AX 头文件集合和可写性探测文档，并读取渲染正文。原始 DOM 文本在 `.local/voicecursor-research/platform/browser-*.json`。
- **D-archive**：Apple 明示不再更新的归档资料，仅作补充，不能代表当前版本全部行为。
- **D-sdk**：本机 Xcode 随附公共 SDK 头文件，证明头文件定义，不证明宿主表现。摘录在 `sdk-ax-attributes.txt`。
- **S**：上述 HEAD 的源码静态追踪。**R**：真实宿主/设备运行证据，本次没有。
- 公开文档副本与 HTTP 获取清单在 ignored `.local/voicecursor-research/platform/`。获取日期均为 **2026-10-08 Asia/Singapore / 2026-10-07 UTC**；`fetch-manifest.json` 含首批精确 UTC 时间。以下链接是原始 Apple 来源。

## 平台事实

### macOS

- **D-current**：AX 是客户端与宿主间的消息 API；属性可缺失、元素可失效，宿主可不响应或未实现。可信辅助功能客户端并不等于每个文本控件可读写。[AXUIElement.h](https://developer.apple.com/documentation/applicationservices/axuielement_h)、[AXUIElementCopyAttributeValue](https://developer.apple.com/documentation/applicationservices/1462085-axuielementcopyattributevalue)。
- **D-sdk**：`AXSelectedText` 是选中的字符串，头文件注明不可写；`AXSelectedTextRange` 是字符范围而非字节范围，值是承载 CFRange 的 AXValue，注明可写。还存在多段选区属性，Utter 当前只处理单段。公共头文件 `AXAttributeConstants.h:684–723`，完整绝对来源路径见本地摘录。线上符号入口为 [kAXSelectedTextAttribute](https://developer.apple.com/documentation/applicationservices/kaxselectedtextattribute)、[kAXSelectedTextRangeAttribute](https://developer.apple.com/documentation/applicationservices/kaxselectedtextrangeattribute)。线上符号仅有声明，详细可写性证据来自 SDK，不能混称网页实测。
- **D-current**：`AXUIElementIsAttributeSettable` 返回具体元素/属性是否可改；写入还可能返回 unsupported、invalid、cannotComplete 等错误。探测成功与写后结果是不同证据。[可写性探测](https://developer.apple.com/documentation/applicationservices/1459972-axuielementisattributesettable)、[属性写入](https://developer.apple.com/documentation/applicationservices/1460434-axuielementsetattributevalue)。没有在已读文档中找到跨宿主原子性或撤销事务保证。
- **D-current + S**：Utter 以 frontmost PID、focused AX element、选区与上下文绑定目标，而不是仅保存 app 名称。焦点变化必须重验，AX 引用存在不能保证用户还在同一个字段。`AXTargetState.swift:14–40`、`NativeTargetLease.swift:28–35`。
- **D-current**：`NSPasteboard.changeCount` 随所有权变化递增，可比较是否仍拥有剪贴板；它不是目标已粘贴的回执。[changeCount](https://developer.apple.com/documentation/appkit/nspasteboard/changecount)。**推断**：剪贴板临时暴露文本，保存/恢复不能当成保密通道或无损事务；写入后有其他所有者时，不应覆盖其内容。
- **D-archive**：Secure Event Input 防止键盘事件被其他进程截获；Apple 给出 `IsSecureEventInputEnabled` 检查，但该文档不承诺 AX 值、合成按键或剪贴板的一切行为。[TN2150，2007，归档](https://developer.apple.com/library/archive/technotes/tn2150/_index.html)。因此不能把 secure-event 状态当成完整的敏感字段识别。

### iOS / iPadOS

- **D-current**：键盘在独立进程中，没有宿主编辑器直接引用。`selectedText` 是只读可选字符串；before/after 是插入点附近的可选上下文。已读 API 没给完整全文、固定长度、可读全部选区或稳定位置范围的保证。不能把文章示例的 `fullText` 变量理解为全文读取保证。[文本交互](https://developer.apple.com/documentation/uikit/handling-text-interactions-in-custom-keyboards)、[selectedText](https://developer.apple.com/documentation/uikit/uitextdocumentproxy/selectedtext)、[before](https://developer.apple.com/documentation/uikit/uitextdocumentproxy/documentcontextbeforeinput)、[after](https://developer.apple.com/documentation/uikit/uitextdocumentproxy/documentcontextafterinput)。
- **D-current**：`insertText` 向当前输入对象插入字符串；`deleteBackward` 删除插入点前的字符；`adjustTextPosition` 按正负字符偏移移动插入点，正方向随当前语言的文本存储方向。这些方法返回 Void，不带目标版本、成功回执或批量事务。[insertText](https://developer.apple.com/documentation/uikit/uikeyinput/inserttext(_:))、[deleteBackward](https://developer.apple.com/documentation/uikit/uikeyinput/deletebackward())、[adjustTextPosition](https://developer.apple.com/documentation/uikit/uitextdocumentproxy/adjusttextposition(bycharacteroffset:))。
- **D-current**：文章明确描述 `setMarkedText` 给出的 selectedRange 后续插入会替换该段。它不能证明任意宿主里的用户选区替换、跨段编辑及多次 delete/insert 是原子的；这些仍需 R。已读代理文档没有任意文档绝对选区 setter，也没有系统 undo 栈或一次撤销保证。**D-archive** 还说明一般文本选择由宿主管理，但其旧限制不能覆盖当前 marked-text API。[当前文本交互](https://developer.apple.com/documentation/uikit/handling-text-interactions-in-custom-keyboards)、[旧键盘指南](https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/CustomKeyboard.html)。
- **D-current**：默认沙箱禁止网络与共享容器写入，但当前文档允许共享容器只读。`RequestsOpenAccess=true` 还须用户在设置允许全访问，之后能写共享容器、使用网络；当前全访问能力列表继承前述限制，没有麦克风与扬声器访问能力。全访问不是录音授权。[配置全访问](https://developer.apple.com/documentation/uikit/configuring-open-access-for-a-custom-keyboard)。旧指南说无共享容器，与当前只读能力不同，采用当前文档。
- **D-current**：安全文本输入暂时换回系统键盘；phonePad/namePhonePad 也用系统键盘。宿主可通过 delegate 拒绝 `com.apple.keyboard-service`，全访问不能覆盖这些限制。[配置键盘界面](https://developer.apple.com/documentation/uikit/configuring-a-custom-keyboard-interface)。Apple 安全文档也确认安全输入排除键盘、宿主可禁用、MDM 可限制托管 app 键盘。[平台安全：扩展](https://support.apple.com/guide/security/supporting-extensions-secabd3504cd/web)。

## 当前调用链与可复用所有者，均为 S

路径以下均相对仓库根目录。

- **macOS 捕获**：`Sources/UtterSession/Native/VoiceWorkflowFactory.swift:61` 捕获租约与 InputContext；`Sources/UtterMacServices/Native/NativeTargetLease.swift:53` 实现 TargetCaptureService；`Native/AXTargetState.swift:14` 从 AX value 与单段范围截取上下各 500 个 NSString 单位。另一路 `Native/InputContext+Capture.swift:63` 在 value 不可读时可仅读 selectedText，不能据此推断可交付替换。
- **macOS 编辑**：`Sources/UtterSession/Native/VoiceSessionJob.swift:128` 进入 `VoiceSessionJob+Editing.swift:6`，先判断选区/最近插入可用性，解析命令，再构造 replaceSelection/deleteSelection/replaceAnchor/undoAnchor；`VoiceSessionJob+Editing.swift:76` 重新检查当前租约。共享 `UtterContracts` 的 DeliveryCommand/OutputTargetLease/OutputAnchor 与 `UtterSession` 应继续承担命令和会话，不把它们移入 UI。
- **macOS 交付**：`Sources/UtterMacServices/Native/NativeOutputBackend.swift:41` 分派命令；`Native/NativeDeliveryTarget.swift:35` 核对身份、原 value 与范围，`:45` 探测 AXSelectedText 是否可写，`:60` 直接写。`TextDeliveryTransaction.swift:20` 先准备选区，`:31` AX 优先，`:44` 后才检查 secure-event 并选择按键/剪贴板。**静态风险**：AX 读取/直接写分支并没有同一 secure-event 门；这不是本次发现的可利用漏洞，需另做敏感字段策略和宿主验证。
- **macOS 确认与剪贴板**：`Native/NativeDeliveryTarget.swift:64` 预计算完整目标 value 并回读；`DeliveryTextObservation.swift:19` 最长 3 秒、间隔最多 25ms，这是代码预算而非已测延迟。`ClipboardPasteTransaction.swift:23` 保存内容，比较 changeCount 与 payload，发起粘贴后必须确认目标消费且仍拥有剪贴板才恢复。未确认可能留下临时 payload；恢复 API 没有返回错误回执。`Native/NativeDeliveryPasteboard.swift:10–28` 物化所有 data 表示，不能推定保留所有延迟提供者语义。
- **macOS 撤销**：`Native/NativeOutputBackend.swift:48` 将 undoAnchor 实现为空字符串替换已验证的 Utter 插入范围；这不是调用宿主系统 undo，不能承诺恢复原先被替换的任意选区或格式。
- **iOS 控制与录音**：`iOS/Keyboard/KeyboardController.swift:127–145` 要求 hasFullAccess、桥接状态、documentIdentifier 与租约；`:172–193` 发共享桥命令。`iOS/App/VoiceHost.swift:30–47` 由包含 app 执行 MobileController；`Sources/UtterMobile/MobileController.swift:79` 请求麦克风权限，`MobileCapture.swift:42–62` 在 app 侧设置 AVAudioSession/AVAudioEngine。`iOS/Configuration/Keyboard-Info.plist:39` 声明 RequestsOpenAccess，声明不等于用户已授予。
- **iOS 写入与撤销**：`iOS/Keyboard/KeyboardController+Dictation.swift:61–80` 经 `Sources/UtterKeyboardBridge/StreamingInsertion.swift:26–48` 保存上下文、计算差异，用多次 deleteBackward 加 insertText 写本次听写；`:143–151` 先恢复 raw，再删除自有片段。没有调用 adjustTextPosition，也没有保存原用户选区以支持任意选区回滚。StreamingInsertion 将 nil 上下文视为空，并接受截短 suffix；**推断**：这不是可靠的全文身份/位置证明，需要 nil、重复文本、长文、emoji/组合字符及宿主规范化验证。
- **iOS 返回宿主**：`iOS/Keyboard/KeyboardView.swift:125` 是打开 `utter://standby?dictate=1` 的 Link；`KeyboardController+Dictation.swift:158–169` 用 documentID 匹配返回后的意图。源码注释声称返回后开始听写，不是 R；本次没有切换宿主，不能宣称顺畅原位编辑。包含 app 的 standby/PiP 实现也不能由“代码存在”证明可持续后台唤醒或 App Store 接受。

## 隐私、推断与成本

- **S**：macOS `VoiceWorkflowFactory.swift:49` 可选远端 LLM，`:63–74` 把捕获上下文传入会话；`VoiceSessionJob+Editing.swift:93` 在选区改写请求中传入 InputContext、memory、screenContext。`Sources/UtterProcessing/PromptBuilder.swift:11` 接收 InputContext；`Sources/UtterRemoteInference/RemoteLLMClient+HTTP.swift:24–44` 把 prompt 放入远端 HTTP 请求。应审阅完整 prompt 路径和用户选择，不能将本地语音识别称为整个流程都本地。
- **S**：移动端本次看到 Apple/下载模型识别所有者与 system/LocalPolisher 两种润色路径，`Sources/UtterMobile/MobileController+Runtime.swift:100–113`。没有验证所有分支的数据流、模型下载网络、缓存/日志/历史保留及远端 fallback，不能据静态局部追踪作零外传承诺。
- **D-current + 建议**：Apple 全访问文档要求保护共享数据、安全传输并只为清楚说明的输入用途处理数据。新增上下文应最小化，远端处理应明确告知选区及邻文发送范围。
- **未测**：ASR/命令解析/改写/交付端到端延迟，冷热启动、内存、电耗、网络与 token 费用。远端 HTTP 的 60 秒 timeout、macOS 3 秒确认、iOS 7 秒润色等待与 250ms 轮询都是预算或实现参数，不能写成测得性能。后两项见 `KeyboardController+Dictation.swift:119–124`。

## 建议，与平台事实分开

1. 先限定已选文本及最近 Utter 插入，复用现有租约、anchor、事务与桥接所有者；不以反复移动 iOS 光标读取全文作为默认方案。
2. macOS 按控件探测读范围、写范围、写选中文本，保存确认等级；拒绝失焦、不可识别范围及未确认重试。将敏感字段策略覆盖捕获、AX 写、按键和剪贴板全部路径。
3. iOS 对缺失上下文采取保守策略；把一次替换和撤销结果按宿主实测记录。系统撤销、自有片段删除、恢复 raw、恢复被替换原文分别定义，不能合并宣传。
4. 下一阶段使用自建公开测试文本，覆盖原生文本控件、浏览器字段、富文本、只读和安全字段、焦点/选区变化、长文与 Unicode。分别记录无切宿主与需切回路径。本次没有执行这些实验。

## 固定交付记录

- **产物位置**：`docs/sdlc/changes/2026-10-08-voice-editing-research/platform-evidence.md`；原始资料 `.local/voicecursor-research/platform/`，由目录内 `.gitignore` 排除。
- **验证证据**：启动及交付时 HEAD 与指定值一致；本次 Apple 页面渲染正文、官方 Markdown HTTP 200 与公共 SDK 摘录。源码 path:line 是静态事实，R=0。最终 `git diff --check` 通过，`git check-ignore` 确认原始资料被忽略。未运行构建或行为测试。
- **假设**：运行环境提供文档版本与 Apple 当前线上页面一致；没有锁定某一 macOS/iPadOS 小版本。未来宿主允许的实现差异需实测，已读资料中的无保证不等于证明永远不可能。
- **未做的事**：不改代码，不运行 app/测试/构建，不用 iPad，不读取私人宿主文本、剪贴板内容或认证，不安装/注册，不改权限，不调用付费推断，不派子任务，不建线程/定时器/watcher/后台服务，不手动切宿主。不把过去设备记忆当成当前 R；未进入实现 SDLC 阶段。
- **错误**：网页读取器最初只给 JS 占位，Markdown 抓取器不支持 text/markdown，部分 AX Markdown 返回 404；改用官方渲染正文及公开 HTTP 获取，停止重复同因尝试。一次旧 QA URL 实际为 debugger 页面，已排除，采用正确 TN2150。一次 zsh 未匹配源码 glob 导致命令 exit 1，随后用已发现的具体文件恢复；未产生改动。一次 browser snapshot 包含大图片导致输出截断，改用正文提取并保存。没有因此推定平台 API 成功。产物写入于 21:17:03Z，晚于子任务 21:16:50Z 截止；立即交付，不继续扩展研究。
