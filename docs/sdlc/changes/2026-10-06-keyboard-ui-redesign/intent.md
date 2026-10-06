# Intent: iOS 语音键盘界面重设计

**Status:** approved
**Approved-by:** 用户（本对话）
**Approved-date:** 2026-10-06
**Approval evidence:** 用户选择“方向 B · 听写台”，随后明确要求“继续”；记录该决定为 intent 批准及进入 B 设计阶段的授权。后续 spec、plan 各自待批准。
**Upstream:** 用户（本对话，2026-10-06）：“我们那个键盘的那个 UI 实在太丑了，你重新设计一下”。上游为 `2026-10-04-ios-support`：语音待命、五分钟闲置与被视频 PiP 取代后的恢复已在 iPad mini (A17 Pro) 真机全链路通过。

## Problem

当前键盘扩展（`iOS/Keyboard/KeyboardView.swift`）是功能优先的表单式布局，观感与系统键盘不协调：

- 不透明 `systemBackground` 白/黑底，作为键盘表面夹在宿主 App 里显得突兀；
- 状态是一行居中说明文字，无状态点/图标层次，占用大块垂直空间；
- 主体是 88×88 纯黑圆形麦克风按钮，四周散落无边框小图标（删除/取消/空格/换行），视觉零散；
- 录音中除 mic 图标换 stop 外没有任何进行时反馈（无波形/脉动/颜色状态）；
- 结果态只有一行文字 + 系统默认按钮；“打开 Utter 启用语音输入”是 tertiary 文本块，像设置项而不像按键。

## Outcome

与 iOS 系统键盘视觉语言协调、状态一眼可读的语音键盘界面：

- 待命在线 / 录音中 / 结果 / 待命失效四态有清晰克制的视觉区分（状态点、颜色、进行时动画）；
- 浅色/深色自动适配；动态类型最大字号不破坏布局；VoiceOver 用普通按钮完成全部操作；
- 键盘行为、桥接契约与真机测试完全不变。

## Scope

- `iOS/Keyboard/KeyboardView.swift` 的视觉与布局，及 `KeyboardController` 的底色/高度等必要配套；
- 界面新增/调整文案进入 `Sources/UtterContracts/Resources/{en,zh-Hans}.lproj/Localizable.strings`。

非目标：不改桥接协议、录音/租约/代次语义、主 App 界面；不引入新权限或数据；不做 iPhone 布局专案（按 iPad mini 验证，iPad 宽度自适应已有 `maxWidth: 580`）。

## Constraints

- 真机测试依赖的 accessibility 标识符与语义不得变化：`keyboard.status`（含 `.value`）、`keyboard.start/stop/insert/activate/result/space/return/delete/cancel/globe`；
- 三条既有真机流程（KeyboardSpeech / AfterIdle / DisplacedByVideoRecovers）断言不放宽；
- 设计方向由用户在 mockup（`mockup.html`）中选定后才开始实现。

## Acceptance criteria

1. 四态在新设计下视觉可区分，浅色/深色各一份真机截图证据（`verification.md`）；
2. 三条真机键盘流程测试在不改断言的前提下全部通过；
3. 最大动态类型字号下无截断/遮挡；VoiceOver 逐元素可读、可操作（元素清单人工核对）；
4. `scripts/sdlc-checks.sh`、`scripts/ci-basic-checks.sh`、`swift test` 通过。
