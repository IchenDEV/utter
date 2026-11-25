# Plan: Edge0 8B 下载与模型目录接入

**Status:** approved
**Approved-by:** 用户（本会话选择 A：Edge0 8B 下载/目录接入，暂不推理）
**Approved-date:** 2026-11-26
**Upstream:** [Spec](spec.md)

## Work items

- [x] 1. 扩展 `CatalogModelFamily`、`ModelRuntime`、`ModelRepositoryHost` 和 `ModelArtifact` / `CatalogModelEntry` 元数据。
- [x] 2. 新增 `Edge0Model` 常量、required 文件、体积、许可证链接和 `Edge0ModelArtifacts` 注册。
- [x] 3. 在 `BuiltinPlugins` 和测试 fixture 中注册 Edge0 artifacts，不加入 MLX text provider。
- [x] 4. 实现 `ModelScopeDownloads`：文件列表、URL 编码、流式下载、进度节流、大小校验、取消。
- [x] 5. 扩展 `TextModelDownloadOperations` 和 `ModelCatalogPlugin`，为 ModelScope 提供下载/required-file 校验。
- [x] 6. 在 `ModelCatalog.performLLMDownload` 按 repository host 分支；Edge0 完整性使用 required files，下载后不走 MLX validate。
- [x] 7. 更新状态/兼容性/删除逻辑，Edge0 不 Active、不 benchmark、不可选择。
- [x] 8. 增加 Edge0 family tab、提示、许可证链接和“仅下载”UI。
- [x] 9. 补中英文 localization keys 和 family 文案。
- [x] 10. 添加单元测试、真实 ModelScope 小文件测试、完整 4.6 GB 下载/重启/删除测试和 UI 渲染证据。
- [x] 11. 运行标准检查、完整测试并填写 `verification.md`；release app 装配被 Xcode/Sparkle 缓存解析阻塞，已用 `swift build -c release` 替代并记录。

## Verification plan

- [x] `bash scripts/sdlc-checks.sh`
- [x] `bash scripts/ci-basic-checks.sh`
- [x] `swift test`
- [x] `OPENTYPE_EDGE0_LIVE_DOWNLOAD=1`：真实 ModelScope 小文件 catalog 下载、重启、删除
- [x] `OPENTYPE_EDGE0_FULL_DOWNLOAD=1`：真实 4.6 GB required 文件下载、完整性、重启、删除
- [x] `UTTER_EDGE0_LAYOUT_OUTPUT=...`：Edge0 中英文/light-dark/760-560 渲染
- [ ] release-style `bash scripts/build-app.sh --app-only --sign=-`。阻塞：Xcode SwiftPM 在清理缓存后卡在 Sparkle binary artifact 解析；`swift build -c release` 通过。
- [x] 确认 app bundle 不包含 Edge0 权重或新增 runtime 依赖

## Human gates

- 用户已在本会话选择 A，确认“先下载/目录接入，暂不推理”。
- verification artifact 需要用户明确批准后才能进入 PR/merge。
