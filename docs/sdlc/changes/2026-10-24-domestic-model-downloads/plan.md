# Plan: 添加国内模型下载源

**Status:** approved
**Approved-by:** 用户（本会话在执行计划提交后明确回复“批准”）
**Approved-date:** 2026-10-24
**Upstream:** [spec.md](spec.md)

## Work items

用户于 2026-10-24 在本会话明确批准 [spec.md](spec.md)。执行状态见下列勾选项；未勾选事项仍未完成。
本计划已于 2026-10-24 获批。本轮实现与验证记录见 verification.md，整体仍为 NOT READY。

### 1. 确认构建与验证环境

- [x] 记录当前分支、HEAD、已有修改和剩余磁盘空间，保护其他写入者的文件与现有模型。
- [x] 使用完整 Xcode 和工作区或临时目录中的 Swift 模块缓存，处理已记录的嵌套沙盒及依赖获取问题。
- [x] 核对依赖 revision，保持 `Package.swift` 与 `Package.resolved` 的依赖选择。主检出目录的缓存只作只读参考，不在其工作区执行本次构建或测试。
- [x] 若需要复用本机依赖缓存，在当前工作区或临时目录中建立独立副本，避免共享可写 checkout、索引或构建目录。
- [x] 按本次构建和模型暂存需求检查空间。若不足，记录阻塞，不删除用户模型、其他工作区或已有证据。

完成条件：清单可解析、依赖可用，或已准确记录阻止执行的错误。环境问题不阻止无依赖的源码与文档工作，但阻塞项解决前不声明验证完成。

### 2. 添加来源设置

- [x] 在 `UtterContracts` 新增 `ModelDownloadSource`，固定官网与 HF-Mirror 的 raw value 和 HTTPS 端点。
- [x] 在 `SettingsValues` 增加默认官网的 `modelDownloadSource`，在 `SettingsStore+Load.swift` 和 `SettingsStore+Persistence.swift` 增加独立持久化键与未知值回退。
- [x] 复用 `AppSettings` 的动态成员投影，补充默认值、重建设置服务后保留选择、无效值回退和观察通知的行为检查。

完成条件：两个来源可从同一设置字段读取，设置往返测试通过，缺失或无效值稳定回到官网。

### 3. 接通所有下载入口

- [x] 在每个 `ModelCatalog` 下载任务开始时读取一次来源，在后续异步步骤中复用该局部值。
- [x] 在 `ModelCatalogDownloads.swift` 和 `ModelCatalogWhisperTokenizer.swift` 为 Whisper 权重和 tokenizer 传入同一来源。
- [x] 在 `ModelCatalogASR.swift` 为常规 ASR 及全部依赖仓库传入同一来源。
- [x] 在 `ConfuciusModelDownloader.swift` 按来源构造配套文件与权重 URL，移除底层下载的官网 URL 默认值，保留固定 revision、尺寸、Range 和 SHA-256 校验。
- [x] 在 `TextModelDownloadService` 和 `TextModelDownloadOperations` 增加必传来源参数，迁移 `ModelCatalogPlugin`、`MLXModelDownloadPlugin`、`MLXModelDownloads`、`MLXModelLoading` 及所有测试替身。
- [x] 官网沿用既有认证行为，镜像显式使用空令牌覆盖，防止自动读取真实 Hugging Face 凭证。不修改进程环境或增加静默跨源重试。
- [x] 保持既有存储路径、暂存隔离、取消、发布检查、已安装模型识别和离线加载方式。新增代码遵守模块边界与每文件 300 行限制。

完成条件：生产下载入口的请求检查覆盖所有来源传递，包括 tokenizer、ASR 依赖仓库和 Confucius 权重。不存在仍由默认参数决定来源的生产网络调用。

### 4. 添加原生选源控件

- [x] 在 `UtterPresentation` 增加一个小型原生 `Picker` 视图，由模型管理与首次引导的模型准备页复用。
- [x] 绑定同一个设置字段，显示来源名称、镜像域名和“仅影响之后开始的下载”的说明。
- [x] 下载期间保持选源可用，来源变更立即保存，并在下载确认信息中显示来源。
- [x] 在 `en.lproj` 与 `zh-Hans.lproj` 补齐 `L("key")` 文案，保留系统字体、语义颜色、现有间距和说明换行。

完成条件：两个入口的选择同步，控件没有独立的未保存状态。真实窗口的交互和视觉检查在下节执行。

## Verification plan

### 自动化与构建

- [x] 扩展现有设置测试，并增加来源请求与任务切换的集中行为覆盖。测试调用生产入口，不能只断言端点映射或替身收到的参数。
- [ ] 用隔离进程和合成 `HF_TOKEN` 捕获真实客户端构造的元数据、文件及重定向请求，确认镜像不携带该令牌，记录空 Bearer 的实际形式。不得读取或打印真实凭证。
- [ ] 暂停文件响应后切源，验证旧任务后续文件仍用旧源，新任务使用新源；覆盖同模型重复请求、多仓库 ASR、取消后重试和旧代任务迟到。
- [ ] 覆盖超时、连接失败、404、401、无效文件、校验失败与取消，验证可见错误和完整性发布约束。
- [x] 所有测试使用独立设置和临时模型目录。复用现有 fixtures 时，先确认其读写路径。
- [x] 运行集中测试，建议筛选范围为 `swift test --filter 'ModelDownload|ModelCatalog|Confucius|SettingsStore|SettingsProjection|WhisperOffline'`，新增测试名称纳入该范围。
- [x] 运行 `bash scripts/sdlc-checks.sh`。
- [x] 运行 `bash scripts/ci-basic-checks.sh`。
- [x] 运行完整 `swift test`，分别记录执行、失败和跳过结果。集中测试通过不能代替完整结果。
- [x] 在当前工作区运行 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer bash scripts/build-app.sh --app-only`，沿用已有有效签名配置，检查脚本产物校验与 Metal 资源。已有 `dist` 产物先保留，签名失败不降级为 ad-hoc。

### 实际模型下载与加载

- [ ] 从当前模型目录选择代表性 Whisper、常规 ASR 和 MLX 模型，记录 ID、选定来源、revision 或可取得的版本标识，以及所需空间。
- [ ] 经生产 `ModelCatalog` 流程在隔离目录中完成镜像下载，记录初始请求主机和最终 CDN 主机，确认配套文件和 tokenizer 均由同一来源配置发起。
- [x] 单独验证 Confucius 固定 revision 的文件和 Range 响应，完整下载时继续核对尺寸及 SHA-256。部分文件检查不能写成整个模型下载通过。
- [ ] 运行下载取消、切源重试和失败恢复，检查旧代任务不能改变新任务状态或发布目录。
- [ ] 断开测试会话的网络访问后，从发布目录加载所下载模型，验证切源不要求重新下载，不影响现有模型识别。
- [ ] 镜像若拒绝空 Bearer，先调整客户端认证配置并重新验证；不使用真实令牌绕过失败。若需改变已批准的设计，记录差异并重新提交设计审阅。
- [x] 真实网络检查只运行确认使用隔离目录的目标，不整体开启会操作默认模型路径的现有 live suite。

### 真实窗口与交付审查

2026-10-25：独立原生宿主已完成选源、两页同步、确认、取消、切源重试、重启保存和菜单方向键操作。修复语言刷新与底部间距，实窗复查通过。完整 VoiceOver、Tab 遍历和打包应用会话仍未覆盖，详见 verification.md。

- [ ] 使用独立测试设置，在真实 macOS 窗口中验证两个入口选源、即时保存、页面同步、重启后保留、下载确认、取消与切源重试。
- [x] 检查中英文、浅色、深色与最小支持宽度，放大查看标签、说明和菜单边缘，修复截断、间距、对齐与对比度问题。
- [ ] 实测键盘焦点、菜单选择和 VoiceOver 名称。下载期间切源必须有清楚的可见反馈。
- [x] 交付前完整重读 `<user-home>/.codex/ANTI_SLOP.md`，逐项审计适用要求并修复发现的问题，记录截图、实际操作和未覆盖项。
- [x] 将最终源码状态、命令、退出码、测试摘要、真实下载结果、窗口证据和残余阻塞写入 `verification.md`。
- [x] 复查最终差异和工作区状态。源码检查、单元测试、构建、模型下载、模型加载与视觉验收分别报告，不互相代替。

## Human gates

意图、设计和本计划均已获明确批准。本轮实现已完成，验证存在失败和未覆盖项，详细边界见 verification.md。
本次计划批准授权上述本地实现和验证，不包含 push、PR、合并、发布或部署。
实现与验证完成后，将 `verification.md` 提交为 `pending approval`，列出未通过或未执行的项目，等待用户验收决定。
无法实测的路径保持未验证状态，不能因为文档、编译或替身测试通过就宣称功能完成。
