# Spec: 键盘宿主文档访问时机

**Status:** approved
**Approved-by:** 用户（本对话：“批准 spec”）
**Approved-date:** 2026-10-06
**Risk:** medium
**Upstream:** [intent.md](intent.md)，用户明确回复“批准 intent”。

## Evidence and callers

实机报告 `.build-ios/keyboard-b-crash.ips` 显示 UIKit 文档代理在 `viewWillAppear` 时无效。`documentID()` 被 `currentSignature()`、`refresh()`、`prepare()`、`insertResult()` 使用；后两者及轮询要求 visible，textDidChange 也检查 visible，refresh 自带 visible 守卫。selectionDidChange 经 refresh 同样受守卫控制。

## Proposed minimum change

- `viewWillAppear` 只完成视觉显示准备，不把键盘视为可访问宿主文档。
- `viewDidAppear` 调用 super 后设置 visible，再执行既有 refresh 和 watchStandby。
- `viewWillDisappear` 继续先将 visible 置 false，再取消观察并使租约失效。
- documentID 的 nil 兼容处理、文档签名内容、轮询、租约代次/过期、单次消费及权限判断均保持原语义。
- 不缓存 UIKit 代理、不固定 document ID、不删除文档校验，也不引入延时猜测或重试定时器。

## Failure handling

- appearance 前到达的 text/selection 回调不能读取文档；appearance 后 refresh 必须正常建立当前 lease。
- 如果宿主没有触发 didAppear，语音保持不可用，不能用过期 lease 继续操作。真机验证必须确认宿主及键盘切换均正常激活。
- 此改动针对已观察到的崩溃调用时机；无法凭静态阅读保证 UIKit 所有生命周期路径无问题，重复实机回归是验收条件。

## Verification and rollback

重复 Utter → Settings 返回、Settings 终止/重新启动和浅深色切换至少各 5 次；检查无新增 UtterKeyboard 崩溃报告。运行三条既有语音回归（普通、五分钟待命、其他视频 PiP 取代后恢复），保留固定关键词与单次插入断言；重跑 B 键盘外观、VoiceOver 操作与最大字号路径。

录音回归时关闭 Device Hub 实时查看，VoiceOver 验收以外保持关闭；此前实时查看开启时观察到全零录音，关闭后固定中文恢复完整识别，该关联仍需复核。

运行 SDLC、基础 CI、Swift 测试和正常签名 iOS build-for-testing。失败时只回退生命周期回调时机这几行，保留验证证据。

spec 批准后编写并单独审批 plan，之后开始修复。
