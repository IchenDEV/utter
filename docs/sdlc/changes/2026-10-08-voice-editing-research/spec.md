# Spec: 桌面纯文本选区语音修改

**Status:** draft
**Approved-by:** —
**Approved-date:** —
**Upstream:** [intent](intent.md)

**Authorization:** 用户整体授权。2026-10-08 根协调线程转达用户“都允许”，覆盖本次桌面与移动设计、计划、实现、验证和既有交付目标跟进；未声称用户已审阅本方案。
**Risk:** high
**Owner:** 本线程负责契约/验收；原生产负责人负责集成与发布。
**Base:** ed4234b41764be8346ae58cdc63011c8f26a0f1e

## 唯一行为契约

捕获单一可编辑宿主的非空纯文本选区，复用既有 Session 录音和 selectionEdit Processing recipe。语音用于修改指令。任何宿主写入前，展示识别指令、精确原文和候选；只有明确点击“应用修改”才能提交。Enter 不隐式提交；Escape/取消保留原文。

应用前重新核对捕获的 PID、AX 元素、完整文档快照、UTF-16 选区和选中文字。审阅面板暂时获取焦点后，必须安全返回原宿主并证明原 lease 一致；不能放松 lease 检查或猜测邻近匹配。焦点、选区或文档改变使候选失效。Unicode、组合字符、emoji 和换行保持精确边界。

目标 readback 确认后，明确 receipt 保存 operationID、originalSelection、replacement 和 resulting anchor。恢复走现有 replaceAnchor(originalSelection, anchor)，不能使用 undoAnchor 的空字符串删除。仅当目标、文档、范围和替换文字仍一致且 anchor 未过期时提供一次恢复；继续输入、换目标、重复确认或 uncertain 都不能再次覆盖。恢复不生成新的恢复机会；不宣称跨宿主全局撤销或富文本保真。

## 状态与失败保护

captured → recording → processing → review → applying → confirmed / uncertain / notCommitted；review 可 expired。取消在写入前丢弃候选；写入已经发出时先按现有事务结算再展示状态。空答、模型/网络错误、超时不产生可应用候选。uncertain 显示“尚未确认是否已应用，请检查原文”，禁止盲重试/恢复，可明确复制候选。

剪贴板继续使用现有 snapshot/changeCount/消费确认；不覆盖用户后来复制的内容。敏感/安全输入在读取选区前排除，包含 AX 直写分支。原文与候选仅临时保留，不新增私密全文上传、截图或历史持久化。尊重现有本地/远程模型选择，远程选区文本披露需在使用前可见。

## 审阅与验收

Cursor 制作 desktop-review-prototype.html 和 ui-design.md，以合成中文样例真实响应点击；本线程逐项点击、真实渲染和 ANTI_SLOP 前后审计。面板清晰显示宿主、指令、原文、候选，长文本可滚动无裁切，状态和按钮支持键盘/可访问性。

- Native 文本框与浏览器 textarea/contenteditable：选择→语音→审阅→取消原文完全不变；应用精确改选区并保留前后文本；一次恢复精确原文。
- 中文、组合音标、家庭 emoji、换行、surrogate pairs；选区/焦点/文档失效、继续输入、重复应用/恢复不能写错或写两次。
- 空答/断网/取消、剪贴板所有权变化、AX/粘贴 uncertain：不盲重试、不破坏原文。
- 准确 SHA/diff/包哈希、完整构建、真实权限/隐私/宿主、独立验收分别记录；SDLC 脚本通过不等于产品通过。

## 移动目标与范围

iPhone/iPad 保留在授权范围。先依赖原负责人 T0 录音→自动返回原宿主/焦点→完整上屏→生命周期；手动返回是未达标。键盘代理 selectedText/context 可选且无全局原子 undo receipt，不能照搬 AX。共享 Session/Processing，单独证明选区一致和替换观察后才能恢复；不支持宿主保留原文。共用 iPad 必须预约，不改变原线无关键盘布局。

首版排除 Action Mode、全篇、富文本、邮件/日历自动执行、新付费注册/安装、认证权限修改。回滚关闭入口，无破坏性迁移。来源与未证实事项见 research.md/platform-evidence.md/source-evidence.md。

## Confirmed selected-entry privacy contract

专用selectionEdit及已有command模式中冻结了非空选区的本次指令，都走选区改写与审阅；识别的自然指令不必重复说“选区”。不启动截图/OCR，不落到任意屏幕Action或自动删除；复用同一Session与已有rewrite helper。未选区command及普通听写原行为保留。此为整体授权内的实现设计收敛，未声称用户已审阅或实际验收通过。
