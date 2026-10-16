# Plan: iPhone Duo 适配

**Status:** approved
**Approved-by:** 用户（本对话：“推进 iPhone Duo 适配 并批准”）
**Approved-date:** 2026-10-07
**Upstream:** [spec.md](spec.md)（已批准）

| # | 内容 | 检查 |
| --- | --- | --- |
| 1 | `KeyboardMetrics.usesTabletGrid`，`applyMetrics()` 改用尺寸类 | iOS 构建 |
| 2 | 审计主 App 与键盘中 idiom/`UIScreen`/固定屏宽用法 | `rg` 审计结果记入 verification |
| 3 | iPad mini 与 iPhone Air 键盘版式回归 | UI 测试（竖/横） |
| 4 | 记录阶段二的阻塞原因与完成条件 | verification |

## Verification plan

- [ ] `bash scripts/sdlc-checks.sh`
- [ ] `bash scripts/ci-basic-checks.sh`
- [ ] `swift test`
- [ ] iPad mini、iPhone Air 键盘版式测试

## Human gates

阶段二在 Xcode 27.1 beta 与 Duo 模拟器可用后另行确认；Duo 真机验证由用户在发售后进行。
