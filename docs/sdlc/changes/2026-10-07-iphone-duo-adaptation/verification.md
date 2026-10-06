# Verification: iPhone Duo 适配

**Status:** pending approval
**Approved-by:** —
**Approved-date:** —
**Upstream:** [plan.md](plan.md)（已批准）

**结论先说：只完成了阶段一（键盘平板键位判定改为尺寸类）。Duo 形态本身一次都没有跑过**：本机 Xcode 是 27.0，没有 Duo 模拟器，也没有 27.1 SDK 的保留区域 API。阶段一的回归证据来自 iPad mini 与 iPhone Air，它们分别代表 Duo 内屏与外屏的尺寸类，不等于 Duo。

## Evidence

| Check | Result | Evidence |
|---|---|---|
| iPad mini（A17 Pro，iOS 27.0）`testProductKeyboardLayoutPortrait` / `Landscape` | Pass | `xcodebuild test`，两项均 passed |
| iPhone Air（iOS 27.0）`testProductKeyboardLayoutPortrait` / `Landscape` | Pass | 同上 |
| 审计：idiom/`UIScreen`/固定屏宽 | 通过 | `rg` 在 `iOS/App`、`iOS/Keyboard`、`Sources/UtterMobile` 中只剩 `KeyboardMetrics.initial`（占位，首次布局后被覆盖）和 `usesTabletGrid` 本身；主 App 只读 `horizontalSizeClass` |
| `bash scripts/sdlc-checks.sh` | Pass | `SDLC checks passed.` |
| `bash scripts/ci-basic-checks.sh` | Pass | `Basic CI checks passed.` |
| `swift test` | Pass | 472 个测试，17 个跳过，0 失败（SwiftPM 不编译 iOS 目标，仅确认未回归） |

## Acceptance criteria

1. 判定只取决于 `UITraitCollection` — 通过（代码审查；`usesTabletGrid`）。regular × compact 的 iPhone Max 横屏走紧凑键位，由条件构成保证，没有 Duo 或 Max 设备上的运行证据。
2. iPad mini 与 iPhone Air 版式测试 — 通过。
3. 无 idiom/`UIScreen`/设备朝向推断 — 通过（审计结果见上；`KeyboardMetrics.initial` 为例外）。
4. 阶段二阻塞原因与完成条件 — 见下。

## 阶段二（未做）

阻塞：需要 Xcode 27.1 beta（Duo 模拟器、`reservedRegions` SDK）。完成条件：
1. 在 Duo 模拟器的外屏、内屏、各姿态下启动主 App，截图确认 Voice、Models、Settings 不被折痕或摄像头遮挡，并接入 `reservedRegions`；
2. 在内屏测量系统键盘，校准 `KeyboardMetrics` 参考值，重跑键盘版式测试；
3. 外屏与内屏切换时（折叠/展开）主 App 保持当前页、键盘重新布局；
4. 评估 27.1 竖向工具栏/标签栏。

## Residual risk

- Duo 内屏系统键盘的真实尺寸未知，当前按“与 iPad 同类”处理，可能与系统键盘不对齐（功能可用，视觉对不齐）。
- 折痕避让缺失：内屏上关键按钮可能落在折痕处。
- 折叠/展开瞬间的状态保持仅靠代码审查。
- 无 Duo 真机。

## Decision

阶段一等待人工审批 verification；阶段二保持开放，不要把本 bundle 视为 Duo 适配全部完成。
