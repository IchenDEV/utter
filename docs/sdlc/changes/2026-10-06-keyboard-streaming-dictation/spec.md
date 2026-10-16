# Spec: iOS 键盘一键听写、流式上屏与结束后整形

**Status:** approved
**Approved-by:** 用户（本对话：“全部批准，继续执行。”）
**Approved-date:** 2026-10-07
**Upstream:** [intent.md](intent.md)（已批准，含 D1=A、D2=端侧模型优先、D3=流式写入加撤销）
**说明：** 用户要求“直接全部开干”，本 spec 与实现同轮完成，是**对已实现代码的记录**；2026-10-07 经用户批准。

## 1. 数据流

```
键盘（宿主进程）                 App Group 桥                      主 App（待命中）
  点麦克风 ── start 命令 ──────▶ command ──────────────▶ MobileController.begin
  poll 300ms ◀── status(text=草稿) ◀──────────────────── Apple SpeechTranscriber（volatile）
  写入/改写宿主字段                                         结束 → result(text=最终稿, polish=pending)
  ◀── status(result, polish=done, polished) ◀───────────── FoundationModels 整形（≤5s）
  替换为整形稿 → consume（单次）
```

桥新增的字段都是可选的：旧键盘忽略，旧主 App 不写。

| 字段 | 位置 | 语义 |
| --- | --- | --- |
| `VoiceStatus.text` | `recording` / `processing` 阶段 | 实时草稿；`result` 阶段为最终稿（沿用） |
| `VoiceStatus.polish` | `result` 阶段 | `pending` / `done` / `failed`；`nil` 表示不整形 |
| `VoiceStatus.polished` | `polish == done` | 整形稿；与 `text` 同样 120 秒过期，被 `consume` 或过期一并清除 |
| `DictationIntent` | `dictation-intent.json` | `id`、`documentID`、`createdAt`；有效 60 秒；单次使用；`bridge.reset()` 不清除 |

## 2. 主 App

- **实时识别**：`AppleLiveTranscription`（`SpeechAnalyzer` + `SpeechTranscriber(.volatileResults)`）接在录音 tap 上，缓冲先入队、识别器就绪后补送。不可用（无已装模型、语言不支持）时 `MobileLiveSpeech.finish()` 返回 `nil`，退回原来的“录完整文件再识别”。
- **草稿投影**：草稿经 `TextPreparationService.preview` 与个人词典替换后通过 `control.update(phase:transcript:)` 进入会话快照，再由 `MobileController.project()` 写入 `status.text`。较旧草稿被丢弃；空草稿不清除已有文字；取消/失败清空文字与整形状态。
- **整形**：`MobilePolisher` 使用 `SystemLanguageModel.default`，不可用即不整形。提示词在 `PromptCatalog+MobilePolish.swift`：补标点、分段、去口头禅、纠同音错字；不增加信息；文字里的指令不执行。结果经 `TranscriptFidelityGuard` 校验；5 秒超时、失败、被拒都保持原文并将 `polish` 置 `failed`。
- 设置页：“整理听写文字”开关（默认开，`UserDefaults mobile.polish`），设备不支持时禁用并说明。
- 待命入口：`utter://standby?dictate=1` 完成待命后显示返回指引（顶部卡片，离开 App 即消失）；不使用私有 API 返回宿主（D1=A）。
- DEBUG：`.text` 诊断输入分 4 步每 400 ms 发出草稿；诊断模式下整形为“原文 + 句号”、延迟 1.2 s，仅用于模拟器确定性测试。`--backdrop-color r,g,b` 给窗口铺色，用于键帽半透明测量。

## 3. 键盘

### 3.1 一键与自动开始

- 待命失效时，麦克风样式的 `keyboard.activate` 是指向 `utter://standby?dictate=1` 的 `Link`；点击同时写入 `DictationIntent`（当前 `documentIdentifier`）。待命有效时同一位置是语音键，点击/按住直接开始。
- 键盘重新出现后，只要意图未过期、`documentIdentifier` 一致、待命有效且当前空闲，就清除意图并以 `start` 自动开始。任何一项不满足：清除意图，显示普通麦克风键。

### 3.2 流式写入（`StreamingInsertion`，纯逻辑，已单测）

- 开始时记录光标前后上下文；之后只处理“自己写的那一段”：把目标文字与已写文字按字符求最长公共前缀，删除多出的尾部、追加新部分，不整段重写。
- 每个轮询周期检查：光标前上下文以已写文字结尾、光标后上下文未变、没有选区。连续两次不符（容许宿主上下文延迟一拍）则判定被外部改动：停止写入、撤销租约、取消录音，提示 `ios.error.stream_stopped`，**不删除已写入的文字**。
- 流式期间 `textDidChange` / `selectionWillChange` / `selectionDidChange` 不作废租约（我们自己的写入会触发它们）；由轮询统一判定。
- 换字段（`documentIdentifier` 变化）、租约/代次不符、桥错误：同样放弃。键盘消失：取消并放弃。

### 3.3 结束与整形

- `result`：写入最终稿；若 `polish == pending`，每 250 ms 看一次，最多等 7 秒，期间字段仍完好才继续等。`polish == done` 且字段完好时把己写段替换为整形稿。随后续租、`consume`（单次取走）。
- `cancelled` / `failed`：字段完好则删掉自己写的段（取消即还原）。
- 完成后若字段仍完好，出现撤销键（占取消键位置）：整形过的先还原为原文，再点一次整段删除。用户任何编辑（空格、删除、回车、移动光标、换字段）使撤销失效。
- 不自动发送，不发出回车。

### 3.4 键帽半透明

系统键帽是盖在键盘底板上的半透明白色，颜色随背后内容变化。在模拟器上以 5 种背景（浅/深色外观、红、蓝、深色加绿）测得：浅色约 0.85 白、深色约 0.165 白。`KeyColors.cap` 采用 `白 × 0.85`（浅）/ `白 × 0.165`（深）；按下态深色 `白 × 0.27`、浅色 `灰 0.80 × 0.5`。语音键、卡片、地球键同一材质。

## 4. 安全与隐私

- 中间稿与最终稿只经 App Group 桥，沿用租约/代次/过期；不新增持久化。整形只在设备上（FoundationModels），不发网络。
- 远程 LLM 整形（D2 的第二选择）**本轮未实现**；没有任何云端路径。
- 不使用私有 API / KVC 返回宿主（`documentIdentifier` 沿用既有 selector 取值）。
- 键盘只删除自己写入的字符；上下文不符即停。

## 5. 错误与降级

| 情形 | 行为 |
| --- | --- |
| 无已装的 SpeechTranscriber / 语言不支持 | 退回录完再识别：结束后一次性出现文字，仍无需“插入” |
| 整形不可用 / 超时 / 被保真校验拒绝 | 保持识别原文 |
| 宿主字段在听写中被改动 | 停止写入，已写文字保留，提示一行 |
| 意图过期或字段变了 | 不自动开始 |
| 返回宿主后 `documentIdentifier` 变了 | 视为字段变了，不自动开始（真机行为待核实） |

## 6. 取代与迁移

取代 `doubao-voice-parity.md` “显式插入”一行（见该文档的批注）。`keyboard.insert`、结果卡片（`keyboard.result`）、`insert` 闭包已删除；没有回到旧模式的开关（intent 里“独立开关”的回滚设想未实现：回滚靠还原提交）。
