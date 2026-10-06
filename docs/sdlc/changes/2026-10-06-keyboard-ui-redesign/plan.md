# Plan: iOS 语音键盘方向 B「听写台」

**Status:** approved
**Approved-by:** 用户（本对话：“批准 plan”）
**Approved-date:** 2026-10-06
**Upstream:** [spec.md](spec.md)，用户于 2026-10-06 明确回复“批准 spec”。
**Scope:** 按批准的 B 规格实施键盘显示层，并完成本地与真机验证。

## 工作项

- [ ] 核对工作区、设备连接和既有签名配置；保存修改前键盘截图和设备外观/字号/权限设置，供比较与恢复。
- [x] 在 `iOS/Keyboard/KeyboardView.swift` 实现顶部状态、中央 64 pt 语音键、底部编辑键；复用既有状态判断和回调。保留录音时删除/取消、结果时换行/插入，以及所有 accessibility 标识符和值。
- [x] 为 preparing、processing、失效和错误设置对应显示；七柱仅在 recording 运行，Reduce Motion 时静止。长结果和大字号采用换行/滚动，所有操作至少 44 pt 可达。
- [x] 在 `KeyboardController.swift` 仅调整承载视图动态底色与必要视觉约束；globe 保留 UIKit 系统切换/长按处理，独立底行避免重叠。
- [x] 复用现有文案，必要新增开始/停止说明写入 UtterContracts 的 en/zh-Hans 资源；不使用“可删除重说”等与现有行为不符的文案。
- [x] 保持每个 Swift 文件不超过 300 行；只有超出限制或显著影响可读性时拆分键盘视图辅助文件，不引入依赖或通用框架。
- [x] 完成下列验证，把命令、退出码、截图路径、实际交互和未覆盖项写入 [verification.md](verification.md)，提交 verification 待审批。

## 验证顺序与证据

1. 运行 SDLC、基础 CI 和现有 Swift 测试，不新增镜像式单元测试。
2. 使用正常 `UtteriOS` 工程、既有 Development.local.xcconfig 与 Apple Development 身份，重建签名 `build-for-testing` 产物到 `.build-ios/ipad-device`；不使用旧二进制或替换 App 入口的 standby probe。验证签名、App Group 与本轮产物时间，再安装到已连接的 iPad mini。
3. 执行三条既有真机流程，保持断言；固定音频只在脚本捕获标记后播放。保留 `.log` 与 `.xcresult`，分别记录每条结果。
4. 真机取浅/深色 × 就绪/录音/结果/失效八张截图，补查准备、识别、长结果与完整错误显示。逐项检查颜色对比、数学/视觉居中、边缘裁切、globe 与操作行间距。
5. 实际点按 start/stop/cancel/insert/delete/space/return/activate，检查宿主文本、单次插入及状态变化；点按 globe 和长按输入法列表。HTML 原型操作不替代这些证据。
6. 最大 accessibility Dynamic Type 下滚动完整结果并触达每个操作；VoiceOver 逐元素朗读与操作，核对标签、状态 value、顺序与 disabled 语义；Reduce Motion 下确认活动图形静止而状态清晰。
7. Full Access 关闭时检查具体错误与基础编辑键，恢复原权限；恢复设备原有 appearance、字号、VoiceOver 和 Reduce Motion 设置。记录验证期间安装的正常签名 App 版本。
8. 交接前完整重读 ANTI_SLOP，逐条审计适用项；修复发现的界面问题后重跑受影响验证。

## 验证命令

```sh
bash scripts/sdlc-checks.sh
bash scripts/ci-basic-checks.sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
python3 scripts/test-ios-device-audio.py keyboard-b-speech testDeviceStandbyKeyboardSpeech
python3 scripts/test-ios-device-audio.py keyboard-b-idle testDeviceStandbyKeyboardSpeechAfterIdle
python3 scripts/test-ios-device-audio.py keyboard-b-displaced testDeviceStandbyDisplacedByVideoRecovers
```

真机脚本使用 `.build-ios/ipad-device/Build/Products/UtteriOS_iphoneos27.0-arm64.xctestrun`，默认设备为 `00008130-00092D800891401C`；执行前核对实际设备和产物。若结果路径已存在，使用带本轮后缀的新 run 名，不覆盖证据。

## 停止条件与回退

签名配置失败不降级为 ad-hoc；设备不可用、信任未完成或权限无法验证时明确记录阻碍，不能宣称真机验收。
旧结果可插入、编辑键或 globe 失效、大字号不可操作时修复后重新验证，未解决前不交付。
回退仅恢复本次键盘视图、控制器视觉约束和新增本地化项；保留用户既有改动及本轮验证证据。

## Human gates

intent、spec 与本 plan 已分别获用户批准，开始实现。
验证完成后 verification 单独待审批；push、PR、发布按用户另行授权执行。

## 执行偏差

修改前对比沿用原型阶段当前布局对比，未重新获取旧版本实机截图；原设备设置有保存与恢复证据。该首项保留未勾选，缺失已在 verification 明确列出。其余实现/验证完成，verification 待人工批准。
