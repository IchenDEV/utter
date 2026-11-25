# Verification: Edge0 8B 下载与模型目录接入

**Status:** pending approval
**Approved-by:** —
**Approved-date:** —
**Upstream:** [Plan](plan.md)

## Evidence

| 检查 | 结果 | 证据 |
|---|---|---|
| `swift test` | 通过：651 个测试、34 个跳过、0 失败 | [full-tests.txt](evidence/full-tests.txt) |
| 真实 ModelScope 小文件 catalog 下载、重启、删除 | 通过（`OPENTYPE_EDGE0_LIVE_DOWNLOAD=1`，约 1.4 s） | `Edge0DownloadTests/testLiveModelScopeCatalogDownloadOfSmallAssets` |
| 真实 4.6 GB Edge0 required 文件下载、完整性、重启、删除 | 通过（`OPENTYPE_EDGE0_FULL_DOWNLOAD=1`，202.2 s） | [full-download.txt](evidence/full-download.txt) |
| Edge0 UI 下载-only 渲染 | 8 张 PNG：中英文、light/dark、760/560 pt | [evidence/layout/](evidence/layout/) |
| 下载器进度/大小/URL 单元测试 | 通过 | `ConfigurationTests`、`Edge0DownloadTests` |
| release-style `bash scripts/build-app.sh --app-only --sign=-` | 未重跑：Xcode 的 SwiftPM 在清理缓存后卡在 Sparkle binary artifact 解析；`swift build -c release` 通过（120.09 s） | [release-compile.txt](evidence/release-compile.txt)、[release-build-status.txt](evidence/release-build-status.txt) |
| `bash scripts/ci-basic-checks.sh` | 通过 | [ci-basic.txt](evidence/ci-basic.txt) |
| `bash scripts/sdlc-checks.sh` | 通过 | [sdlc-checks.txt](evidence/sdlc-checks.txt) |

## Acceptance criteria

| # | 标准 | 结果 |
|---|---|---|
| 1 | Edge0 分类显示 8B-A1B、约 4.6 GB、ModelScope、许可证和仅下载提示 | 通过。UI 渲染可见；unit test 固定 required files/runtime/host。 |
| 2 | 点击下载可获取 required 文件、显示进度；取消语义保留 | 通过。真实 4.6 GB 下载 202.2 s，进度通过流式 URLSessionDataDelegate 更新；取消沿用现有 staging/error 状态。 |
| 3 | 重启后仍显示已下载；删除后回到未下载 | 通过。小文件与 full 下载测试均覆盖重启和删除。 |
| 4 | 不能选择/benchmark/Active；不调用 MLX validate | 通过。`runtime == .edge0` 隐藏 Use/benchmark；isActive 强制 false；下载后只调用 required-file validate。 |
| 5 | required 文件全部非空；错误明确 | 通过。`ModelAssets.filesAreComplete`、文件列表缺失、HTTP/大小校验和测试覆盖。 |
| 6 | 标准检查、完整测试、UI 渲染、release build | 通过（release app 装配被 Xcode/Sparkle 缓存解析阻塞，已用 release Swift 编译替代并记录）。 |

## Notes

- Edge0 8B 下载使用 ModelScope；全局 Download source 仍显示 Hugging Face，但 Edge0 条目提示和实际请求走 ModelScope。
- 下载后的模型会显示“仅下载”，没有 Use、benchmark 或 Active；本阶段不接推理。
- `model.safetensors` 4.5 GB 单文件下载使用流式 data delegate；进度按约 0.1% 节流，避免每个 chunk 投递 MainActor。
- 已存在的同大小文件会跳过；部分文件会重新下载，完整 staging 取消语义不变。
- revision 当前为 ModelScope `master`，尚未 pin commit；这是残余风险。

## Residual risk

1. **尚未接入推理**：Edge0 8B 目前只能下载/管理，选中、benchmark 和文本处理都不可用；这是本阶段明确的 non-goal。
2. **revision 未 pin commit**：ModelScope 只返回 `master`；上游更新会导致后续下载内容变化。后续应固定 commit/revision。
3. **partial-file resume**：已完成文件会跳过，但单文件中断后从头下载；与现有 staging 取消语义一致。
4. **UI 证据为生产视图 fixture 渲染**：没有在打包 app 中点击下载；下载链路由真实 catalog 测试覆盖。
5. **许可证**：Edge0 Community Model License 1.0；本阶段只下载、不推理、不再分发权重。商业使用边界需要所有者/法律确认。
6. **磁盘**：完整下载需要约 9.2 GB（4.6 GB staging + 4.6 GB 发布）；低于此空间的用户会看到现有磁盘错误。
7. **release app 装配**：清理 Xcode DerivedData 后，`xcodebuild` 在 Sparkle binary artifact 解析阶段卡住；`swift build -c release` 通过，但完整 `.app` 装配未在本次重跑。PR CI 的 release-style build 仍是最终门槛。

## Decision

Pending approval：下载、目录、完整性、删除、UI 和 release build 证据完成后，由所有者批准 verification；推理引擎接入另立变更。
