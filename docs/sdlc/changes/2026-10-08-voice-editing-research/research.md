# VoiceCursor 与 Utter 语音编辑首轮研究

本轮结论是先把 macOS 现有选区编辑补成“有审阅、只替换当前原选区、能安全恢复原文”的候选流程。移动端先关闭现有原位录音与焦点返回 T0 闸门，不能照搬桌面或以手动切回宿主达标。此为待批准的范围建议，未制作 UI、未修改产品。

## 产品证据与值得借鉴的内容

VoiceCursor 官网把语音用于修改已写文本，原始视频实际可见 Mail/Slack 选择态和编辑状态。这支持研究该交互方向，不能证明通用可靠性、原文恢复或跨平台同等体验。官网公开 [视频](https://voicecursor.ai/videos/homepage/intelligent-editing.mp4)、[官网](https://voicecursor.ai/)和[更新记录](https://apps.apple.com/us/app/voice-cursor-ai/id6762721421)详见 source-evidence。

只保留四项有依据的借鉴：
1. 按应用选择默认语气，减少每次口令的重复。Utter 需先核对既有 style/inputContext，选区编辑默认保留原文语种和事实，语气只能显式变更。
2. 自定义词典和 snippets，保护人名/产品术语。Utter 已有字典 owner，应优先复用；snippet 展开要由明确指令触发，避免改写新增事实。
3. 先形成清晰文本、再按明确要求转为邮件或要点。纯文本/显式 Markdown 可作为有限范围，不承诺 Notion 表格或任意富文本无损。
4. 可恢复的处理状态。商店更新有 Retry/Recover 和掉线录音恢复宣称。Utter 建议仅重算候选文本，不在 outcome uncertain 时重复写宿主；本轮不照搬其存音频政策。

Action Mode 的跨服务执行超出本轮最小范围。只借鉴“先看再执行”的理念，不新增邮件/日历/文件自动化。

## 桌面与移动的能力对照

| 能力 | macOS 当前证据 | iPhone/iPad 当前证据与限制 |
|---|---|---|
| 获取选择 | AX选区、目标lease代码已存在；宿主必须暴露属性并授权辅助功能 | UITextDocumentProxy selectedText与有限前后文，不是全篇或任意应用读取权 |
| 语音指令改写 | shared Session/Processing已有 selected edit recipe 与 command resolver | 键盘现有App Group语音bridge不提供任意选区编辑闭环；clientID返回文本，不经过desktop spoken-edit输出 |
| 原位录音 | 当前Mac录音owner可复用，具体宿主新流程未测 | 键盘扩展不能直接使用麦克风；全访问不能解除此限制。原生产线app capture/返回/生命周期闸门未闭合 |
| 写回 | AX可写性、精确选区/文档复核；剪贴板降级有 uncertain边界 | insertText/deleteBackward受宿主焦点与proxy行为约束，无任意范围事务保证；不可盲删context或扫全文 |
| 撤销 | current undoAnchor将新锚点改为空，不保存原选区全文恢复契约 | current undo仅负责自身近期听写，不是宿主全局undo，也不证明选择替换恢复 |
| 格式 | 当前文本字符串输出，不能推断富文本保持 | proxy字符串和插入接口不提供跨宿主富文本事务；第一版限纯文本 |
| 隐私/模型 | 现有本地Whisper/MLX与可选remote provider，具体路由要用户已有设置决定 | main app可本地模型，键盘/桥接留存和remote范围必须审查，不能新增静默云fallback |

平台事实依据见 platform-evidence。源码存在、API文档、真实宿主通过是三个不同等级。

## 唯一候选行为契约

第一版只接受非空、可编辑纯文本选区。用户明确进入“编辑选区”，从原宿主捕获 selection text、精确范围和 target lease。只把选区与语音指令交给现有 Processing；默认不加 OCR、全文、屏幕图或历史记忆。按用户已有模型配置运行，远端前需明确知道选区和指令会发送到何处。

候选文本先在 Utter 的审阅区域显示原文、识别口令与结果。用户可重新说口令或取消；宿主原文在确认前保持不变。具体面板形态和是否可编辑口令由下一阶段 UI负责人制作可审阅方案后决定。绝不把低置信口令自动当听写追加。

点击应用前重新核对原PID、AX对象、文本、选择范围和文档状态。任一变化则停止写回，保留候选，要求重新选择并发起新事务。拒绝空结果、失败、超时、取消和失效lease；网络错误允许重算候选，不能自动写入或切云。一次确认对应一个operationID和一个receipt，uncertain需读取可验证结果或由用户处理，不重放按键。

Apple公共SDK把AXSelectedText标为不可写，现有实现仍做逐元素settable探测。先以自建非私密fixture验证能力，不能先承诺直接AX替换普遍可用。若目标拒绝该属性而只有paste可行，则该宿主在另行确认clipboard安全证据前不支持首版替换。取消不得改剪贴板；用paste时必须保留当前owner校验/恢复机制，不覆盖用户期间复制的新内容。

撤销不是删除新文字。回执需在内存保存 originalSelection和replacement，并绑定提交后精确目标/范围/周边状态。只有目标仍一致且该范围仍等于replacement时，才把范围恢复成originalSelection；用户之后输入、换焦点、移动选择或应用关闭就禁用直接恢复。首版只承诺本次事务的一次恢复，不承诺任意宿主全局undo或跨会话多级undo。现有undoLastInsertion/undoAnchor不能直接冒充该契约。

多轮通过重新选择当前结果、重新捕获新lease发起下一笔编辑。先不做隐藏连续session。富文本、表格、全文编辑、无选区“智能猜目标”、自动发送和语音命令删除全部不在首版范围。

## 可复现中文验收例子

以下是固定测试材料与目标，非本轮模型运行结果。每例选择完整给定文本，语音口令在审阅中应可看到；确认前宿主字节不变，确认后仅选择范围变。

| 类别 | 原文 | 口令 | 可检查结果 |
|---|---|---|---|
| 纠错 | 下周三下午三点和张珊开会。 | 只把张珊改成张山，其他不变。 | 下周三下午三点和张山开会。 |
| 语气 | 你今天必须把报告给我。 | 改得礼貌一点，仍然要求今天给报告。 | 保留今天/报告/请求，无新增期限或原因；允许不同礼貌表述 |
| 缩短 | 我们计划在本周五下午两点召开会议，主要讨论新版本发布前的测试结果。 | 缩短到一句，保留星期五、两点和讨论测试结果。 | 保留时间和主题，无额外事实 |
| 结构 | 小王负责界面，周三完成。小李负责测试，周五完成。 | 按负责人、任务、截止时间，整理成两条纯文本要点。 | 两人/两任务/两日期匹配，范围外文本不变 |

保护性验收至少包含：处理期间选择变化/同值另位置/宿主切换/文档变化、中文与emoji范围、取消、没有语音、误识别口令、模型空答/超时、断网、剪贴板被用户修改、提交结果不确定、重复确认和修改后撤销。没有安全恢复原文证据就不启用替换发布。

## 延迟、离线与成本

没有本轮延迟或推理成本测量。将capture、ASR、edit generation、确认、write/observe分别计时，不把官网4x或near-instant当Utter目标已达成。给每阶段明确超时与取消，先测短中文选区再确定产品预算。本地路径取决于已可用模型与质量；不新增下载或承诺移动端全部离线。远端费用跟语音时长、文本token、所选provider有关，VoiceCursor订阅价格无法推出Utter成本。

隐私建议为选区/口令仅存当前内存事务，失败日志记状态与operationID，不记私密原文；崩溃日志、History、App Group文件留存、字典/记忆拼接都要做显式审计。VoiceCursor不训练承诺并不消除其上传与留存，Utter不能直接宣称同等隐私。

## 剩余风险与下一步

未完成VoiceCursor客户端安装实测；未确认专用hotkey、连续替换、编辑undo、网络故障或iPad原位行为。未测试Utter新流程，未操作iPad/原工作区。独立Apple文档核对完成后由负责人验收来源和边界。

下一真实决定是 intent 范围批准；之后才进入Claude/Cursor交互设计。未来实现回到当前shared Session/Processing/Mac output所有者，与原生产负责人协调移动bridge与设备资源。不会建立平行编辑或录音逻辑。阶段与验收见workflow.json。

## 2026-10-08 continuation

用户整体授权已取代首轮待批推进限制，见spec/plan/workflow。桌面先补可审阅候选和恢复原文receipt；移动目标保留，原生产负责人ordinal24/cursor2617明确T0未通过，负责移动/设备/整合。实际原型与6文件增量均未通过最终验收，见verification与implementation-result；无版本生产就绪结论。
