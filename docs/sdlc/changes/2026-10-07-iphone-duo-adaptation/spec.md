# Spec: iPhone Duo 适配

**Status:** approved
**Approved-by:** 用户（本对话：“推进 iPhone Duo 适配 并批准”）
**Approved-date:** 2026-10-07
**Upstream:** [intent.md](intent.md)（已批准）

## Context

- 键盘：`KeyboardController.applyMetrics()` 在每次布局和尺寸过渡后运行，调用 `KeyboardMetrics.make(width:landscape:pad:)`。`pad == true` 且宽度 ≥ 600 时使用在 iPad mini 上量到的键位，按宽度缩放；否则使用紧凑键位。`pad` 同时决定是否使用安全区侧边距（iPhone 刘海侧缩进，iPad 无）。
- 主 App：`MobileRootView` 按 `horizontalSizeClass` 在 `NavigationSplitView` 与 `TabView` 间切换，选中页由 `@State selected` 保存。

## Design

阶段一（27.0 SDK 可做）：

1. 新增 `KeyboardMetrics.usesTabletGrid(_ traits:)`：`idiom == .pad || (horizontal == .regular && vertical == .regular)`。`applyMetrics()` 用它代替 idiom 判断。
   - iPad：不变。
   - iPhone 竖屏 / 横屏（含 Max 横屏 regular × compact）：不变，仍紧凑键位。
   - Duo 内屏（regular × regular）：与 iPad 同类键位，宽度仍 ≥ 600 才缩放，否则回退紧凑键位。
   - Duo 外屏：与 iPhone 相同。
2. 朝向仍取自场景几何（`effectiveGeometry.interfaceOrientation`，回退 `window.screen.bounds`），不使用设备朝向；宽高比判定对 Duo 两块屏都适用。
3. 主 App 审计：没有 idiom/`UIScreen.main`/固定屏宽；`@State selected` 位于根视图，折叠与展开切换时保持页面。无需改动。

阶段二（需要 Xcode 27.1 beta SDK 与 Duo 模拟器，本次不做）：

- 用 `UIView.ReservedRegion`/`reservedRegions(kind:)` 让内屏的 Voice、Models、Settings 内容避开折痕与摄像头；
- 评估 27.1 的竖向工具栏/标签栏；
- 在 Duo 模拟器的各姿态上测量系统键盘并校准 `KeyboardMetrics`。

## Safety and failure modes

- `usesTabletGrid` 只改变键位选择；若内屏实际键位与 iPad 不同，最坏情况是键位与系统键盘不对齐，功能仍可用（紧凑与平板网格都可操作）。
- trait 在布局早期为 `.unspecified` 时返回 false，走紧凑键位，随后布局回调覆盖。
- 不触碰权限、App Group、桥协议。

## Test strategy

`UtterSimulatorFlow` 的 `testProductKeyboardLayoutPortrait/Landscape` 在 iPad mini 与 iPhone Air 模拟器运行；Duo 形态因缺少模拟器无法运行，记入残余风险。

## Rollout and rollback

随常规发布；回滚为还原键位判定一处改动。
