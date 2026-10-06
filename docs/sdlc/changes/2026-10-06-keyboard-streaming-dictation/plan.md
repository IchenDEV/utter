# Plan: iOS 键盘一键听写、流式上屏与结束后整形

**Status:** approved
**Approved-by:** 用户（本对话：“全部批准，继续执行。”）
**Approved-date:** 2026-10-07
**Upstream:** [spec.md](spec.md)（已批准）

按依赖顺序，每步都有可运行的检查。

| # | 内容 | 检查 |
| --- | --- | --- |
| 1 | 桥协议：`PolishState`、`VoiceStatus.polish/polished`、`DictationIntent`；`reset()` 保留意图 | `swift test --filter UtterKeyboardBridgeTests`、`check-ios-bridge.sh` |
| 2 | 纯逻辑 `StreamingInsertion`（公共前缀差异、归属校验、脱离） | 14 个单测 |
| 3 | 主 App：`AppleLiveTranscription`、`MobileLiveSpeech`、草稿投影、`MobilePolisher`、取消/失败清草稿 | `swift build --target UtterMobile`；iOS 构建 |
| 4 | 键盘：流式写入、结算、撤销、意图自动开始（`KeyboardController+Dictation`） | 模拟器流式用例 |
| 5 | 键盘 UI：撤销键、整形中状态、麦克风样式的激活链接；本地化 en/zh-Hans | 模拟器用例 + `ci-basic-checks.sh`（键值一致） |
| 6 | 主 App：返回指引、整理开关 | 模拟器截图 |
| 7 | 键帽半透明：五种背景测量，改 `KeyColors`，新增两端背景对比用例 | `testKeyboardKeysAreTranslucentLikeTheSystemKeys`（iPhone Air、iPad mini） |
| 8 | 真机（iPad mini）：自动开始、`documentIdentifier` 稳定性、返回面包屑、≥3 个宿主、整形质量与延迟 | **未完成**，见 verification |

回滚：还原本分支这批提交。桥字段可选，旧键盘与旧 App 互不破坏。

未做：远程 LLM 整形；iPad Pro 13 模拟器；真机验收。
