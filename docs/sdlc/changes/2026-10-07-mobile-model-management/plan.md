# Plan: iOS 模型管理

**Status:** approved
**Approved-by:** 用户（本对话：“全部批准，继续执行。”）
**Approved-date:** 2026-10-07
**Upstream:** [spec.md](spec.md)（已批准）

| # | 内容 | 检查 |
| --- | --- | --- |
| 1 | `DeviceCapability` iOS 可用内存系数 | `swift test` |
| 2 | `MobileModel` 投影与非破坏性选用/下载/取消/删除 | iOS 构建、UI 测试 |
| 3 | 注册文本、FireRed、Mega 提供者；`MobileWorkflow` 引擎路由 | iOS 构建 |
| 4 | `LocalPolisher` 与整形分发、预热 | iOS 构建 |
| 5 | 模型页与行视图、设置页整形模型行、本地化键 | 模拟器截图（iPhone Air、iPad mini） |
| 6 | UI 测试：目录、下载取消重试、选用重启删除 | `UtterSimulatorFlow` 相关用例 |
| 7 | 文档与 `sdlc-checks.sh`、`ci-basic-checks.sh`、`swift test` | 脚本 |

回滚：还原本 bundle 涉及的文件即可；用户数据只有两个 `UserDefaults` 键，旧版本忽略 `mobile.polish.model`。
