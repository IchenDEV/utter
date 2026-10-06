# Intent: 键盘回到宿主时的文档代理崩溃

**Status:** approved
**Approved-by:** 用户（本对话：“批准 intent”）
**Approved-date:** 2026-10-06
**Risk:** medium
**Origin:** 方向 B 键盘真机验收发现，非生产事故报告。

## Evidence

`.build-ios/keyboard-b-acceptance-20261006.xcresult` 在深色外观下由 Utter 返回 Settings，键盘进程崩溃。设备原始报告 `.build-ios/keyboard-b-crash.ips`：EXC_BAD_ACCESS / SIGSEGV，调用链为 UIKit `_UITextDocumentInterface.documentIdentifier` → `KeyboardController.documentID()` → `currentSignature()` → `refresh()` → `viewWillAppear`。

## Outcome and acceptance

- 键盘显现和宿主切换时安全取得当前文档，不访问尚未有效或已失效的 UIKit 文档代理。
- 真机重复 Utter → Settings 返回、宿主终止/重建、浅深色切换，键盘不崩溃；保留原关键词和单次插入断言。
- 会话与文档变化仍立即使旧结果/租约失效；不得通过固定文档 ID、跳过校验或吞掉错误获得通过。
- 重跑方向 B 外观/无障碍及三条既有待命流程，保存日志和截图。

## Scope

允许最小调整 KeyboardController 的文档访问时机/生命周期，并增加相应真机回归路径。音频、识别、权限、桥接协议、租约规则和结果消费语义不变。

本意图扩大了原 B 规格仅修改控制器底色/视觉约束的范围。根据 AGENTS.md 与 docs/sdlc/README.md 的逐阶段审批要求，意图批准后才编写 spec；spec 与 plan 另行审批后实施。此处尚未授权或实施修复。
