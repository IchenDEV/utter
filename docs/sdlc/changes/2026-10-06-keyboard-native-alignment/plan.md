# Plan: iOS 语音键盘与系统键盘对齐

**Status:** approved
**Approved-by:** 用户（本对话：“全部批准，继续执行。”）
**Approved-date:** 2026-10-07
**Upstream:** [spec.md](spec.md)（已批准，2026-10-07）

## Work items

- [x] `VoiceKeyGesture` 状态机（`UtterKeyboardBridge`）与 `UtterKeyboardBridgeTests`，含全部分支
- [x] `TranscriptionSanitizer` 全角标点空格规整与测试
- [x] 键盘网格 `KeyboardMetrics`、键帽样式、去掉不透明底板
- [x] 重排 `KeyboardView`：状态行、主区、底排；地球键移到最左并统一键帽；高度随方向
- [x] `PressSurface` 与语音键的点按/按住交互，控制器接入状态机
- [x] 大字号滚动布局、减弱动态效果、文案（en / zh-Hans）
- [x] 工程登记新文件（`iOS/Utter.xcodeproj/project.pbxproj`）
- [x] iPhone 不回归：按设备类型选网格、紧凑网格去掉 iPad 专用的 20pt 底部留白、横屏紧凑网格、横屏按安全区内缩；新增 `scripts/sim-hardware-keyboard.swift` 与 `UtterSimulatorKeyboardLayout.swift`
- [x] 真机对照测试升级：同一次运行内比较地球位置、总高、取样点颜色、圆角与网格
- [x] 真机按住说话与“不迟到启动”用例；音频脚本支持延迟播放
- [x] 校准高度与圆角常量；把最终数值回填 spec
- [ ] 既有真机键盘用例全量回归；记录证据到 `verification.md`（7 条中 4 条已在最终构建上重跑通过；`AppearanceAndVoiceOver`、`MaximumText`、`DocumentLifecycle`、`AfterIdle`、`DisplacedByVideoRecovers` 因 iPad 弹出“Enable UI Automation”的触控 ID 授权而未能重跑，见 `verification.md`）

## Verification plan

- [x] `bash scripts/sdlc-checks.sh`
- [x] `bash scripts/ci-basic-checks.sh`
- [x] `swift test`（含新增的两处单元测试）
- [x] iOS `build-for-testing`（真机）
- [x] 浅/深 × 竖/横四组并排截图，逐张查看
- [x] iPhone Air 模拟器：`testProductGlobe`、`testProductKeyboardLayoutPortrait/Landscape`、键盘传输与编辑三条流程；最大字号下的布局用例
- [x] iPad mini 模拟器：`testDeviceKeyboardNativeAlignment`（系统键盘 frame 与真机逐项相同）；最大字号下的布局用例
- [ ] 真机：对照 ✓、按住说话 ✓、不迟到启动 ✓、既有键盘用例（部分，见上）；最终代码（含本轮 iPhone 相关改动）还没有在真机上重跑对照

## Human gates

- 批准 intent、spec、plan 与最终 verification；本轮没有替用户批准任何阶段。
- 在 iPad 上通过“Enable UI Automation”的触控 ID 提示后，重跑 `verification.md` 列出的未重跑用例。
- 是否把本改动提交并推到 PR #121，由用户决定。
