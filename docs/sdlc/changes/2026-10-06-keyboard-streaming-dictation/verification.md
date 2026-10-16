# Verification: iOS 键盘一键听写、流式上屏与结束后整形

**Status:** approved
**Approved-by:** 用户（本对话：“全部批准，继续执行。”）
**Approved-date:** 2026-10-07
**Upstream:** [spec.md](spec.md)（已批准）

**结论先说：模拟器上的流式、整形、撤销、安全停写和半透明键帽有证据；真机一条都没有跑。** 验收标准 2、3（真机计时）、4、6（真模型质量与延迟）因此**未通过验证**，不能据此宣称完成。

## 环境与做法

- 模拟器：iPhone Air（已开 Full Access，硬件键盘已用 `scripts/sim-hardware-keyboard.swift` 关闭）。iPad mini 模拟器未开 Full Access，只跑了不需要它的用例。
- 真机：iPad mini 此刻没有连接（`devicectl` 只列出一台不可用的旧 iPhone），所以没有真机运行。
- 模拟器没有麦克风与端侧语言模型，用 DEBUG 替身：`.text` 诊断输入分 4 步发出“Utter bridge sample”的草稿；诊断模式下整形固定为“原文 + 句号”。这些只证明**键盘端与桥的行为**，不证明 Apple 实时识别或 FoundationModels 的真实表现。
- 构建注意：`iOS/Utter.xcodeproj` 上的 `xcodebuild` 曾因系统文件协调锁卡住，改用 `iOS/UtterAlt.xcodeproj` 副本（含 scheme 里的容器名替换）跑；依赖包因网络不稳，用 `GIT_CONFIG_GLOBAL` 把 GitHub 地址映射到本地 `.build/repositories` 镜像。副本和临时配置不入库。

## 验收标准对照

| # | 标准 | 状态 | 证据 / 缺口 |
| --- | --- | --- | --- |
| 1 | 待命失效点麦克风一次进主 App | **部分** | 键盘上只剩一个麦克风样式的 `Link`（`keyboard.activate`，截图可见），没有第二个激活控件；真机跳转未跑 |
| 2 | 返回后 ≤1.5 秒自动录音，意图 60 秒单次 | **未验证** | 桥层意图的单次/过期/`reset` 保留由 `check-ios-bridge.sh` 与单测覆盖；“真的跳出去再回来”和 `documentIdentifier` 是否保持不变，只有真机能回答，未跑 |
| 3 | 固定语音播放中上屏、≥2 次更新、结束后唯一一份 | **部分** | 模拟器：`testKeyboardStreamsPolishesAndUndoes` 在 `recording` 仍未结束时宿主字段已以 “Utt” 开头，结束后等于最终稿且只有一份；真实语音与计时未测 |
| 4 | 三个宿主各一轮，含自动更正 | **未验证** | 只在本 App 自己的文本框跑过；设置搜索框、备忘录、Safari 未跑 |
| 5 | 改光标/打字/换字段立即停写，不删他人文字 | **部分** | 换字段：`testKeyboardLeavesWrittenTextWhenTheFieldChangesMidDictation` 通过（已写文字保留，另一字段未被写，无撤销键）。改光标、打字两种在 `StreamingInsertion` 单测中覆盖了判定，没有 UI 用例 |
| 6 | 结束后 ≤N 秒整形替换，失败保留原文 | **部分** | 替身整形：1.2 秒后原地替换为“原文.”；关闭整理开关保持原文；真模型的可用性、质量、延迟、保真校验在真实文字上的表现**未测**，`MobilePolisher.isAvailable` 在模拟器恒为 false |
| 7 | 一次撤销还原/删除，宿主文本与听写前一致 | **通过（模拟器）** | 整形过的两步撤销（先还原原文再删除）、未整形的一步撤销，字段回到听写前；编辑（删除、空格、回车）后撤销键消失 |
| 8 | 隐私：只经桥、不持久化、云端默认关 | **部分** | 没有新增持久化，没有云端路径（远程 LLM 整形没做）；这是静态结论，未做抓包 |
| 9 | 既有门禁与用例不放宽断言 | **部分** | 见下 |

## 已运行的检查

| 检查 | 结果 |
| --- | --- |
| `swift test` | 472 个用例，0 失败，17 个跳过 |
| `bash scripts/sdlc-checks.sh` | 通过 |
| `bash scripts/ci-basic-checks.sh` | 通过（含本地化键一致） |
| `bash scripts/check-ios-bridge.sh` | 通过 |
| `git diff --check` | 无输出 |
| `StreamingInsertion` 单测 | 14 个全部通过（含 emoji 计一个字符、外部编辑脱离、上下文延迟容忍） |
| iPhone Air 流式用例（5 个） | 全部通过：流式+整形+两步撤销、关整形一步撤销、编辑后撤销失效、换字段停写、延迟取消不误伤下一次听写 |
| iPhone Air 键帽用例 `testKeyboardKeysAreTranslucentLikeTheSystemKeys` | 通过：5 种背景（浅、深、红、蓝、深+绿）下 Utter 键帽与系统键帽逐通道相差 ≤ 5（阈值 6）；同一用例要求系统键帽跨背景变化 > 20，证明测试有区分力 |
| iPad mini 同一键帽用例 | 通过，数值与 iPhone Air 相同量级 |
| iPad mini 键盘布局用例（竖/横） | 通过 |
| iPhone Air 回归：`testDiscardAndClearLocalData`、`testDictionaryReplacementAndDeletion`、`testLandscapeCanFinishAndCancel`、`testLanguageChangeDisablesCurrentRuntime`、`testNativeProductRotation`、`testProductGlobe`、`testProductKeyboardLayout*`、`testProductNavigationAndPreferences`、`testChineseInterfaceSession`、`testSessionFinishCancelAndDisable`、`testRecordingLimitFinishesWithResult` | 通过 |

### 过程中发现并修掉的问题

- 草稿文字在取消/失败后残留在主 App 状态里（`testSessionFinishCancelAndDisable`、`testRecordingLimitFinishesWithResult` 先失败）：取消与失败现在清空文字与整形状态，复测通过。
- 键盘放弃听写后状态标签停在 `recording`：放弃时补一次 `refresh()`，换字段用例复测通过。
- 启动参数 `-mobile.polish NO` 被当成字符串，`as? Bool` 失败而仍开着整理：改用 `bool(forKey:)`。
- 键帽此前用不透明填充，只在单一背景下像系统键帽，被用户指出；现已用半透明并加了两端背景对比用例。

### 仍然失败或没跑

- `testNativeAccessibilityAudit`：对比度、动态字号、裁切报告，**此前就已记录为未通过**（见 `2026-10-04-ios-support/verification.md`），本轮未新增也未修复；未豁免。
- `testCopyResultAndOpenSettings`：模拟器上粘贴菜单未出现，断言失败。它只涉及复制/粘贴，不经过本次改动的代码；但我没有在改动前的提交上复跑，所以不能证明它此前是通过的。
- 所有 `testDevice*` 真机用例：本次改了其中读取 `keyboard.insert` / `keyboard.result` 的几处（改为流式字段与撤销键），**未运行**，改动本身未被验证。
- iPad Pro 13 模拟器、`testKeyboardEditsWithoutFullAccess`（需要 Full Access 关闭的模拟器）未跑。

## 需要真机回答的问题（未回答）

1. 点麦克风跳到主 App 再切回后，`documentIdentifier` 是否仍等于跳出前的值？不等则自动开始永远不触发。
2. iPad 上是否出现系统左上角的“返回”面包屑？我的返回指引文案假设有或用户手动切回。
3. `insertText` / `deleteBackward` 在带联想/自动更正的宿主里，上下文回读是否延迟超过一个轮询周期（两次容忍是否够）。
4. FoundationModels 在 iPad mini A17 Pro 上是否可用，中英混说的整形质量、延迟，保真校验是否误拒。
5. Apple 实时识别（`volatileResults`）在后台待命的音频会话下是否稳定出草稿；不稳时是否正确退回“录完再识别”。
6. 键盘出现到录音首帧的耗时。

## 残余风险

- 向宿主字段写入、删除是最大风险，已有的防护是“只删自己写的、两次不符即停”；真机多宿主行为未知。
- 没有独立验证者复核（高风险项要求）。
- 远程 LLM 整形（D2 第二选择）没有实现；设备不支持端侧模型时只有原文。
