# Verification: 键盘文档代理生命周期

**Status:** approved
**Approved-by:** 用户（线程 b69087ea：“批准 verification”）
**Approved-date:** 2026-10-06
**Approval evidence:** 用户在 16:24、16:24、16:30 连续三次回复“批准 verification”，同时覆盖 [听写台验收](../2026-10-06-keyboard-ui-redesign/verification.md) 与本文；对应三轮运行（第 29–31 轮）均因调用失败而终止，批准未被及时录入；接力线程确认批准后文件未再修改，然后录入。

## Implementation

- intent、spec、plan 均由用户逐阶段明确批准（2026-10-06）。
- `viewWillAppear` 保留 super/globe 显示；visible 与原 refresh/watchStandby 移至 `viewDidAppear` 的 super 之后。
- `viewWillDisappear`、签名、documentID 的 nil 兼容、租约、轮询、消费校验未改变。
- 追踪 currentSignature/documentID 全部调用：refresh/textDidChange/prepare/insertResult/poll/observeResult 受 visible 守卫；selectionDidChange 经 refresh 守卫。
- 加入真实 iPad 10 轮浅深色宿主返回/重启 E2E，最后固定中文、单次插入和编辑后拒绝旧结果；没有新增单元测试。

## Initial evidence (historical)

- `keyboard-b-lifecycle-build.log`：正常 Apple Development build-for-testing exit 0。
- `codesign --verify --deep --strict .build-ios/ipad-device/Build/Products/Debug-iphoneos/Utter.app`：exit 0。
- `keyboard-b-lifecycle-sdlc.log`、`keyboard-b-lifecycle-basic.log`：通过；`keyboard-b-lifecycle-swift.log`：既有 Swift 测试通过。
- 实机回归仍在执行，不能宣称验收完成。
- 回归前设备崩溃清单只有旧的 `UtterKeyboard-2026-10-06-151641.ips`；清单 `keyboard-b-lifecycle-crashes-before.json`。

## Rollback

仅恢复 viewWillAppear 的旧时机并移除新增 viewDidAppear；UI 与取证保留。

## Current runtime evidence

正常最终构建 `keyboard-b-final-build2.log` 通过；签名校验 exit 0。统一实机 `keyboard-b-final-all-20261006.xcresult` 已结束：7 项通过、1 项 fixture 导航失败，整体 exit 65。不能报告整批通过：

- 外观/VoiceOver：146.757 秒通过。
- 10 轮返回/重启、真实单次插入、文档编辑后拒绝旧结果：279.521 秒通过。
- Full Access 关闭错误/编辑/恢复：48.093 秒通过。
- 真正 accessibility 最大字号（滑块 100% 断言）、滚动、语音与恢复：64.735 秒通过。
- Reduce Motion 开关值、录音/取消/恢复：53.102 秒通过。
- 普通待命语音：44.314 秒通过。
- 五分钟待命语音：344.194 秒通过（Safari 前台等待 300 秒），固定关键词及单次插入断言通过。
- 视频 fixture 地址自动键入丢失前缀，变成 Safari 搜索；失败发生在 Play video 出现前，没有进行该流程的语音断言。
- 改用 XCTest 原生系统 URL 打开，新增“必须新标签”守卫及失败也执行的标签清理。`keyboard-b-pip-navigation-build.log` build-for-testing exit 0；focused `keyboard-b-pip-native-20261006.xcresult` 32.498 秒失败、exit 65，确认实际 Safari “此连接不安全”提示。测试明确报错要求用户处理，没有自动绕过提示；等待用户在本机局域网 fixture 页面手动确认后继续。
- 最新 `keyboard-b-crashes-current.json` 仍只有旧报告 `UtterKeyboard-2026-10-06-151641.ips`，测试期间没有新增 Utter 崩溃报告。
- `keyboard-b-handoff-{sdlc,basic,swift}.log` 全部 exit 0；既有 XCTest 488 项、18 跳过、0 失败，Swift Testing 1 项通过；正常产物 codesign 深度严格校验 exit 0。
- PiP 恢复真实语音仍未完成，本 verification 保持 draft，不提交为完成验收。


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
