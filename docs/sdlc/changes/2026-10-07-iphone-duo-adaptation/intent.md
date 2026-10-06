# Intent: 适配 iPhone Duo（折叠屏 iPhone）

**Status:** approved
**Approved-by:** 用户（本对话：“推进 iPhone Duo 适配 并批准”）
**Approved-date:** 2026-10-07
**Risk:** medium（键盘版式判定与主 App 自适应；不改权限、数据与桥协议）
**Upstream:** 用户（本对话，2026-10-07）：“后面不要忘记完成 iPhone Duo 的设计兼容。”，以及“推进 iPhone Duo 适配 并批准”。
上游 bundle：`2026-10-06-keyboard-native-alignment`、`2026-10-07-mobile-model-management`。

## Problem

iPhone Duo（Apple 2026-09-09 公布，预计 2026-10-23 发售，iOS 27.1）外屏约 5.4 英寸、内屏约 7.6 英寸，两块屏幅宽高比相近。按 Apple 公布的适配规则：

- 内屏的尺寸类是 regular × regular，设备 idiom 仍是 iPhone，且不遵守 `UISupportedInterfaceOrientations`。
- 应用不能再用 idiom、`UIScreen.main` 或设备朝向推断版式，要用尺寸类和场景几何。
- 折痕和摄像头是系统保留区域（`reservedRegions`，27.1 SDK）。

现状：

1. 键盘用 `traitCollection.userInterfaceIdiom == .pad` 决定是否使用平板键位网格与侧边安全区：Duo 内屏会被当成手机，使用紧凑网格拉伸到 7.6 英寸宽，和系统键盘对不齐。
2. 主 App 已按水平尺寸类在 `NavigationSplitView` 与 `TabView` 间切换，方向正确，但没有在 Duo 形态下验证过。
3. 本机是 Xcode 27.0，没有 Duo 模拟器（Duo 模拟器随 Xcode 27.1 beta 提供），`reservedRegions` 也不在 27.0 SDK 中。

## Outcome

- 键盘的平板键位判定改为尺寸类（regular × regular），Duo 内屏与 iPad 走同一套键位，外屏与 iPhone 走紧凑键位；iPad 与 iPhone 的现有行为不变。
- 主 App 不依赖 idiom/朝向/`UIScreen`，在窄（外屏）与宽（内屏）两种形态间切换时保持当前页面。
- 折痕/摄像头保留区域的避让与 Duo 模拟器姿态验证，作为第二阶段，在 27.1 SDK 可用后完成；在那之前如实标注“未验证”。

## Scope

范围内：`iOS/Keyboard` 键位判定、主 App 自适应审计、UI 测试回归、文档与验证记录。
非目标：不引入私有 API；不在 27.0 SDK 上猜测 27.1 的 API 名称；不改 Duo 之外设备的版式；不改 `Info.plist` 的朝向声明（Duo 内屏不遵守它，iPhone 现有声明保持）。

## Constraints

- 只用公开 API；27.1 SDK 的 API 在可用前不写进代码。
- iPad mini 与 iPhone Air 模拟器上的键盘版式测试必须保持通过。
- 文件 < 300 行。

## Acceptance criteria

1. 平板键位判定只取决于 `UITraitCollection`（idiom 为 pad，或水平与垂直尺寸类均为 regular）；iPhone Max 横屏（regular × compact）仍用紧凑键位。
2. 键盘版式测试在 iPad mini 与 iPhone Air 模拟器的竖屏与横屏全部通过。
3. 代码中不存在用 `UIScreen.main`、`UIDevice` idiom 或设备朝向推断主 App 或键盘版式的地方（初始占位值除外，并在首次布局被覆盖）。
4. verification 明确列出第二阶段（保留区域、竖向工具栏、Duo 模拟器姿态）的阻塞原因与完成条件。

## Open questions

- Duo 内屏上系统键盘的真实键位尺寸未知；本次按“与 iPad 同类”处理，需在 Duo 模拟器或真机上测量后校准 `KeyboardMetrics` 参考值（第二阶段）。
