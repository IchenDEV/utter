# Source evidence

获取日期为 2026-10-08 Asia/Singapore，UTC 2026-10-07 21:09:56 起。负责人为本线程。证据分为现场网页/源码观察、官方文档或演示宣称、推断、未证实。没有安装 VoiceCursor 或对其原生客户端做实测。

## 官方产品材料

| ID | 官方链接 | 当前观察与证据等级 | 本机原始证据 |
|---|---|---|---|
| V1 | [官网](https://voicecursor.ai/) | 官网宣称选区语音改写、缩短、翻译、改细节；不能证明所有宿主或移动支持相同契约。 | homepage-dom.json |
| V2 | [原始视频](https://voicecursor.ai/videos/homepage/intelligent-editing.mp4) | 官网实际加载，duration 126.548 秒；现场检查多个时间点。85秒为 Mail 蓝色选区与 Editing 状态；93秒为 Slack 蓝色选区；100秒为移动画面和 Speak to edit、Tap again to finish 面板。剪辑/合成演示，非本轮原生实测。 | demo-085s.png、demo-093s.png、demo-100s.png，全部截图和哈希见 screenshot-map.json |
| V3 | [公开 demo](https://voicecursor.ai/demo) | 实际导航，出现四种写作场景按钮和 Connecting...；未授权麦克风、未登录、未完成语音输入或选区替换。 | public-demo-dom.json |
| V4 | [下载](https://voicecursor.ai/download) | 官方提供 Mac/Windows 与 App Store/Android 分发链接；分发存在不代表平台功能完全一致。 | official-web-results.json |
| V5 | [App Store 开发者页](https://apps.apple.com/us/app/voice-cursor-ai/id6762721421) | 开发者更新记录提及 Voice Edit、PiP/键盘交接、Retry/Recover、应用语气。页面最新 1.0.21，相对日期 5d ago；1.0.18 提及新打字键盘。iPhone iOS17 / iPadOS17 起。描述却有桌面 hotkey/menu bar 文案，不能据此推断 iOS 触发方式。 | 本轮 web 获取，来源链接保留 |
| V6 | [隐私政策](https://voicecursor.ai/privacy-policy) | 生效 2026-01-22。收集输入/输出；未经单独 opt-in 不用于模型训练；可能分享给云托管等服务商；保留期限随账号/服务需要。无本轮证据可确认全本地、零留存、具体推理模型或机房。 | privacy-dom.json、privacy.png |
| V7 | [Action Mode](https://voicecursor.ai/action-mode) | 官方 Beta，示例为查文件、发邮件、约会议，可先审阅步骤。此审阅是动作执行机制，不能说编辑功能也有同一确认或 undo。公开 Notion guide 本轮抓取 Internal Error，未重试绕过。 | official-web-results.json |
| V8 | [官方博客](https://voicecursor.ai/blogs)及[控制权文章](https://voicecursor.ai/blogs/hands-free-writing-with-ai-dictation) | 博客文章强调用户审阅与精确编辑；这是产品理念，不是具体事务保证。未找到可引用的桌面版本 changelog 或完整编辑 API/手册。 | 本轮 web 获取 |

官网当前显示 Free 每周跨设备 2,000 words，14天 Pro 试用，Pro 月付 $20；美区 App Store 内购月 $19.99、年 $143.99。价格来自不同渠道，未结算核实，不用于估算 Utter 成本。App Store 隐私标签列出关联身份的 User Content，含 Audio Data。未将“不训练”解释为“不上传”。

## 重点链路的证据缺口

- 触发：桌面演示 Editing 状态；商店文字提 custom hotkey/menu bar，但本轮未确认编辑专用键。移动演示 Tap again to finish，不清楚入口和系统交接。
- 选区/上下文：官网声称使用选区及周边上下文；没有公开获取长度/裁剪规则。视频显示可见选区，不证明未读全文。
- 跨应用：官网与视频列/显示多个宿主；未实测覆盖率、只读区域、富文本和焦点竞争。
- 替换/追加：宣传目标为修改选择内容；本轮抽帧没有形成连续提交前后链，不能确认每个平台实际替换语义。
- 多轮：无连续演示能证明保留编辑 session 或重新选区规则。
- 审阅/撤销：未确认原生编辑预览、确认、撤销/恢复原文。Action Mode 的审批不可借用为编辑证据。
- 格式、语言、语气：官网有相关宣称；未证实富文本/表格结构保持、中文事实保真、长文本边界。
- 失败：商店更新提录音掉线保存/重试和 Recover。不能证明编辑写入 exactly-once 或失效选区保护。

## 工作区与原执行线

新 branch research/voicecursor-voice-editing-20261008，实际 HEAD ed4234b41764be8346ae58cdc63011c8f26a0f1e，起始 git status 干净。原工作区相同 HEAD，但现场为38个 tracked modified、17个 untracked entries，diff stat 760 insertion/231 deletion。原始状态清单保存于 ignored .local。只读核对未提交内容，没有复制源码或工件。

原线程 0e62fe12-4c97-497b-a4c7-985eea9aa1cd 最新 run ordinal23 completed，started 20:23:49Z、completed 21:01:36Z。读取 afterPosition2500，最后 assistant 游标2601。具体键盘 A 布局 pending approval；04:15设备失败止于开发证书不信任，后续用户可启动不证明 T0成功。自动返回、原焦点/PiP、生产独立验收仍未闭合。原 checkpoint-capture.md 只读用于当前状态，没有取旧成功证明新方案。

原线未提交 BridgeMessages 增加 attach/captureRequestID/captureFromApp，键盘在 captureFromApp 为真时不做 live streaming。这是 Debug 录音附着试验，不是 arbitrary selection voice editing。原线还有隐私清单、MobileController+KeyboardCapture、Standby/VoiceHost、图标与键盘布局变更。未来必须向原负责人整合单一逻辑。

## Utter 本 HEAD 的现场源码

- Sources/UtterSession/Native/VoiceSessionJob.swift:120-150，仅 desktop clientID nil 的 command 路由 performSpokenEdit；remote/client 路径返回文本。
- Sources/UtterSession/Native/VoiceSessionJob+Editing.swift:6-98，有 selection/last insertion 目标判断、rewriteSelection、replaceSelection、deleteSelection 和 undoLastInsertion；直接 deliver，没有用户审阅闸门。
- Sources/UtterProcessing/Native/TextProcessor+SelectionEdit.swift:6，有选区模型处理；失败返回空文本。Prompting 同目录限制新事实与输出结构。提示约束不等于模型质量通过。
- Sources/UtterMacServices/Native/NativeTargetLease.swift:27，有宿主 PID、AX 元素、选区/文档状态校验。
- Sources/UtterMacServices/Native/NativeDeliveryTarget.swift:35-58，复核焦点、文档及 selection，探测 AX selectedText 是否可写。
- Sources/UtterMacServices/Native/NativeOutputBackend.swift:48，undoAnchor 写入空文本；anchor 记录新 text。不能把该路径称为恢复“替换前原文”，需要补回执保存原文及安全恢复。
- Sources/UtterMacServices/ClipboardPasteTransaction.swift:31-62，剪贴板 changeCount 所有权及消费确认后恢复；paste outcome uncertain 不安全重试。存在安全保护不等于每个宿主实测支持。
- iOS/Keyboard/KeyboardController+Dictation.swift:61-80、143，有自写听写 streaming 与 undo；selectedText 用于一致性保护。本轮没找到任意选区语音指令传递/改写/原文恢复闭环。
- iOS/README.md 当前已提交文本仍标记 keyboard recording feasibility gate blocked。原未提交 T0 工作不得通过本分支旧 README 或旧测试翻转为通过。

Apple 官方依据和更精确源码范围由独立任务记录于 platform-evidence.md，负责人核对后引用。

## 路径、预算和错误

environmentId DEVICE_BINDING_IN_IGNORED_LOCAL，darwin Mac mini；所有绝对路径仅本机有效。工作区 .local/voicecursor-research 被 .local/.gitignore 的 * 忽略；源 screenshot 位于 T3 browser-artifacts，副本、对应URL、时间点和 SHA256 留在 .local。未读取原私人设备截图，不披露系统私人区域。

native startedAt 2026-10-07T21:09:56.301Z，hard deadline21:19:56.301Z。账户额度未知；live catalog核对 Codex Sol Xhigh Standard；Claude disabled，Cursor available，未来 UI 从允许路由选。没有启用 Fast/MAX、付费或提高权限。

错误记录：初次混合输出超过预算而截断，按文件分段重读；git check-ignore 当时目录未忽略返回1，中断其后命令，已单独补读；一个源码猜测路径不存在，改用 rg --files 找实际 owner；Notion guide Internal Error 未访问到。公开demo连接中，无原生产品实测。未启动 watcher、scheduler、其他普通线程。

## Native timing erratum and current cursor

首轮父实际completedAt21:20:51.594Z，startedAt21:09:56.301Z，超55.293秒；旧“父deadline intact”等表述撤回。Apple子任务native超56.6秒，不是产物+13秒。Run2原线ordinal24 completed21:59:36.954Z、cursor2617，HEAD ed4234b41764be8346ae58cdc63011c8f26a0f1e，38个tracked改动；读取t0-return并未修改原工作区。本线子任务原生终态/任务ID在workflow与ignored run2-state.json。
