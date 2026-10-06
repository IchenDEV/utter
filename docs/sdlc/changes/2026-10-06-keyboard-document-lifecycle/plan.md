# Plan: 键盘文档代理生命周期修复

**Status:** approved
**Approved-by:** 用户（本对话：“批准 plan”）
**Approved-date:** 2026-10-06
**Upstream:** [spec.md](spec.md)，用户明确回复“批准 spec”。

## Implementation

- [x] KeyboardController.viewWillAppear 不读取文档、不将 visible 设为 true；保留 super 与 globe 显示。
- [x] 增加 viewDidAppear，在 super 后设置 visible，再调用原 refresh/watchStandby。消失、文档签名、租约和结果消费保持既有实现。
- [x] 加一条真实设备 E2E：浅深色交替 10 次，每次 Utter 返回 Settings，并终止/重启 Settings 宿主；每次检查 ready/start 和编辑键，最后录制固定中文并验证单次插入。保留未修改的三个语音断言，不新增单元测试。

## Validation

- [x] 正常 Apple Development 签名 build-for-testing、codesign 校验；设备仍为已连接 iPad mini。
- [x] 新 lifecycle E2E、B 八态外观、VoiceOver 朗读/录音/取消、最大字号滚动和编辑；关闭实时屏幕查看后执行固定语音。
- [x] 原三条流程：普通待命、五分钟待命、外部视频 PiP 取代后恢复；严格关键词及单次插入。
- [x] 对比设备 UtterKeyboard 崩溃报告，确认测试期间没有新增报告；检查文档变更后仍拒绝旧结果。
- [x] SDLC、基础 CI、Swift 测试与差异检查，复审 ANTI_SLOP；记录结果和残余风险，verification 单独提交待审批。

## Rollback and gates

仅回退生命周期回调时机这几行，保留 UI 改动和设备证据。真实文档访问/旧结果校验失败时不交付。plan 获明确批准后实施；push、PR、发布仍需单独授权。
