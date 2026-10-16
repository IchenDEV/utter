# Spec: iOS 语音键盘方向 B「听写台」

**Status:** approved
**Approved-by:** 用户（本对话：“批准 spec”）
**Approved-date:** 2026-10-06
**Upstream:** [intent.md](intent.md)，用户选择 B 并要求继续（本对话，2026-10-06）。
**Reference:** [mockup.html](mockup.html) 中 B1–B4 的浅色与深色方案。

## Context

`KeyboardView` 读取 `KeyboardState`，通过既有 `prepare`、`insert`、`edit` 回调操作。
`KeyboardController` 管理桥接、租约、结果消费、宿主输入与 UIKit globe 按钮。
本次调整显示层，以及控制器承载视图的底色与布局约束。
原型四态表达视觉方向；实现须覆盖全部 phase、pending 与错误组合。
桥接没有音量采样，七柱动画表示录音活动，不能冒充实时音量。

## Design

### 布局与尺寸

- 基准为 iPad mini 的 744 × 300 pt；实际宽度由宿主决定，保持现有最小高度 300 pt。
- 主体居中，最大内容宽度 580 pt，两侧至少 20 pt；采用 SwiftUI 流式布局，不照搬 HTML 绝对定位。
- 顶部状态、中央听写、底部编辑保持共同中心轴；垂直间距 12–16 pt，状态与中央操作至少相隔 12 pt。
- 中央语音按钮直径 64 pt，图标 28 pt；状态用 subheadline，操作说明用 body，辅助说明用 footnote。
- 编辑键最小点击区域 44 × 44 pt，圆角 10 pt；空格宽度随空间伸展。
- globe 继续由 UIKit 承载，右下安全区域 44 × 44 pt；SwiftUI 内容在 globe 上方结束，保留独立底行，避免叠压。
- 300 pt 是高度下限，不是裁切边界。大字号时主内容可纵向滚动，编辑区与 globe 可达；结果全文可滚动阅读。
- 窄宽度或大字号时编辑键可分两行，不缩小点击区域、压缩字号或省略操作。

### 色彩与形状

- 系统字体与现有 SF Symbols，保持同一视觉语言。
- 键盘底色用 UIKit 动态色，承载视图与 SwiftUI 底色一致；原型浅色 `#d1d4da`、深色 `#3f434a` 为表面参考。
- 文字用动态 label / secondaryLabel；编辑键用有明度区分的中性表面。
- 就绪键为系统蓝，录音停止键为系统红；状态同时用文字与图形，不只依靠颜色。
- 白色操作图标至少 3:1 非文本对比，文字标签至少 4.5:1；必要时加深按钮填色。
- 状态容器仅用于录音/连接状态；状态点静止，无光晕、渐变或悬浮缩放。
- 键帽通过明度形成层次，阴影最多为小幅向下的定向阴影；失效麦克风为中性描边和灰色图标，明确 disabled。

### 状态与操作

状态文案沿用当前优先级：`state.errorKey ?? status.errorKey` → `pending` → 待命失效 → phase。
按钮可用性、结果有效性与 accessibility value 保持现有条件，不能由显示文案推断。

| 状态 | 中央听写区 | 操作 |
|---|---|---|
| 就绪 | 64 pt 蓝色麦克风，简短开始说明 | 现有条件允许时 start；删除、空格、换行、globe |
| preparing / pending | 进度指示与现有准备文案 | 主语音键沿用禁用条件；busy 且有 lease 时取消；编辑键保留 |
| recording | 七柱活动动画、录音文案、64 pt 红色停止键 | stop、取消、删除、空格、换行、globe |
| processing | 进度指示与现有识别文案 | 主语音键沿用禁用条件；busy 且有 lease 时取消；编辑键保留 |
| result 且 hasResult | 居中结果预览，长文本全文可滚动 | insert、删除、空格、换行、globe |
| 待命失效 / disabled | 失效麦克风与现有原因说明 | 主语音键沿用禁用条件；编辑键保留；满足现有条件时 activate |
| cancelled / failed / error | 当前具体状态或错误 | 是否可重试沿用现有条件；编辑键与 activate 条件保持 |

原型 B2 将删除替换为取消，B3 将换行替换为插入；实现通过扩展操作行保留所有既有操作。
`hasResult` 仍要求 result phase、leaseID 匹配且文本非空。
结果失效或消费完成由控制器刷新决定，不增加缓存或插入重试逻辑。

### 动画与无障碍

- 七柱仅在真实 recording phase 运行，离开时立即停止；不新增音频采样。
- 待命不脉动，不制造“正在监听”的暗示；Reduce Motion 下七柱固定，准备/识别保留文字和静态图形。
- 所有操作为标准 Button / Link / UIKit UIButton，带本地化标签；禁用麦克风保留启用提示。
- 动画、状态点和装饰图标对 VoiceOver 隐藏；状态、结果及操作独立可访问。
- 朗读顺序为状态、中央操作或结果、附加操作、编辑键、globe；实际验证 SwiftUI/UIKit 混合顺序。
- 最大 accessibility Dynamic Type 下文字换行，结果全文可读，滚动后每个操作可触达。

| 标识符 | 保持的职责 |
|---|---|
| `keyboard.status` | 现有本地化状态；value 为 pending → `preparing`，否则 standbyLive → phase 或 `disabled`，否则 `standby_off` |
| `keyboard.start` / `keyboard.stop` | 现有 start / stop 命令与可用性 |
| `keyboard.cancel` | 现有 cancel 命令，按原有 busy 与 lease 条件出现 |
| `keyboard.result` / `keyboard.insert` | 有效结果全文 / 单次消费插入 |
| `keyboard.activate` | 现有 `utter://standby` 链接，full access 错误时不出现 |
| `keyboard.delete` / `keyboard.space` / `keyboard.return` | 现有宿主编辑操作 |
| `keyboard.globe` | 系统输入法切换与长按列表 |

### 文案与代码边界

复用 `ios.phase.*`、`ios.error.*`、`ios.standby.*`、`ios.action.*`。
确需新增的开始/停止说明进入 UtterContracts 的 en 与 zh-Hans 资源。
“语音在本机识别”只描述既有本地识别路径，不新增未经验证的隐私承诺。
原型“可删除重说”不作为实现文案：当前删除编辑宿主文本并使结果失效。

不修改桥接消息、轮询、租约/代次、full access 判断、结果过期/消费、反馈设置或音频生命周期。
复用回调和最少视图辅助方法，不新增依赖或通用设计框架；必要拆分遵守单文件 300 行限制。

## Safety and failure modes

- 全访问未允许：保留具体错误，基础编辑可用；启用入口不能伪装成权限授权。
- 待命被其他 PiP 取代：沿用检测刷新并显示恢复入口，不自动启动麦克风或主 App。
- 会话/文档/租约变更、旧结果或空结果：遵循现有校验，不使旧结果重新可插入。
- 长错误、英文、长结果、大字号：换行与滚动容纳，禁止固定高度裁切。
- preparing / processing：停止键按现有规则禁用，保留取消，不能把识别显示成录音。

## Test strategy

- plan 批准后的实现阶段执行既有 KeyboardSpeech / AfterIdle / DisplacedByVideoRecovers 真机流程，不改或放宽断言。
- iPad mini 浅/深色 × 就绪/录音/结果/失效至少八张截图；补查准备、识别、full access 错误与长文本。
- 最大 Dynamic Type 下检查滚动、所有操作可达、globe 不重叠；VoiceOver 实际逐元素朗读并操作。
- Reduce Motion 下录音图形静止但状态清晰；点按启用入口和 globe 长按菜单。
- 检查对比、居中、点击区域、裁切、状态切换，无重复动画或看似可点击的死控件。
- 运行 `bash scripts/sdlc-checks.sh`、`bash scripts/ci-basic-checks.sh`、`swift test`；安装前完成所需 iOS build。

## Rollout and rollback

规格等待用户批准后进入 plan，plan 单独批准后实现；本地与真机验证完成后，按用户另行授权交付。
出现旧结果插入、globe 不可用、编辑失效或大字号不可操作时停止交付。
回退范围为键盘视图、控制器视觉约束及新增本地化项。
