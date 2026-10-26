# Verification: 添加国内模型下载源

**Status:** approved
**Approved-by:** 用户（本会话审阅验收记录后明确回复"通过"）
**Approved-date:** 2026-10-25
**Upstream:** [plan.md](plan.md)

## Result: NOT READY

2026-10-25：已实现手动选源、持久化和全部下载入口的来源传递。源码测试、基础检查及签名应用构建通过，Confucius ASR 的镜像入口下载和禁止出站网络后的模型加载通过。
Whisper 与 MLX 的真实镜像下载失败；原生夹具的核心窗口交互已完成，完整 VoiceOver 与文件级切源验证仍未完成。技术证据尚未覆盖全部验收标准，发布就绪状态仍为 NOT READY。
用户审阅本轮验收记录后明确回复"通过"，据此将本阶段记录为 `approved`。本次批准不将失败或未执行项目改记为通过，该次验收批准未包含 push、PR、合并或发布授权。之后用户明确请求 "pr"，授权本次提交、推送和创建 PR；合并与发布仍未授权。

公开证据已去除本机路径和 URL 查询参数，原始日志保留在本地且不提交。去标识规则与原始日志哈希见 [publication-redactions.json](evidence/publication-redactions.json)。

## Source and environment

- 工作区：`<worktree>`。
- 分支：`t3/support-domestic-model-sites`；基线 HEAD：`467e9349e7ec70b452c7330a12e945b0eda8db24`，实现保留为未提交修改。
- 起始工作区仅有本任务的 SDLC 文档；未重置、覆盖或清理其他工作区、用户模型和既有证据。
- 使用 `/Applications/Xcode.app/Contents/Developer` 和 `/private/tmp/utter-domestic-module-cache`。构建前检查磁盘，未因容量删除其他文件。
- 默认沙盒曾阻止 SwiftPM 清单执行；使用获准的本地构建权限后已解决。独立复制本机锁定版本依赖缓存到本工作区，未共享可写 checkout。`Package.swift` 和 `Package.resolved` 无修改。
- 首次 release-style 构建的依赖获取和 Sparkle 产物路径失败已修复；最终构建使用工作区缓存及 `-disableAutomaticPackageResolution`，未换用依赖版本。

## Implementation

- `ModelDownloadSource` 固定官网与 HF-Mirror 两个 HTTPS 端点，默认官网。缺失或未知保存值回到官网。
- 每个下载任务在异步下载前固定来源，传给 Whisper 权重、tokenizer、ASR 多仓库、MLX 和 Confucius。
- MLX 跨模块服务要求必传来源，所有生产调用者及替身同步迁移。Confucius 配套文件与权重共用来源，底层 URL 不再默认官网。
- 镜像显式使用空令牌覆盖，官网沿用依赖的原有认证行为。未修改进程环境，未增加自动跨源重试。
- 设置页和首次引导共用原生菜单式 Picker，绑定同一个设置。来源立即保存，确认文案显示来源。更改只影响新任务。实际交互发现并修复菜单随语言切换不刷新的问题，首次引导另补足底部间距。
- 保留原有缓存路径、模型 ID、代际暂存、取消仲裁、发布检查、Confucius revision、尺寸、Range 与 SHA-256 校验。

## Automated checks

| 检查 | 结果与范围 | 证据 |
| --- | --- | --- |
| 设置往返与投影 | 10 项通过；默认、未知值、重建服务、观察通知和共享投影 | [settings-tests.log](evidence/settings-tests.txt) |
| 生产客户端请求 | 隔离子进程中用合成 HF_TOKEN；两来源五类入口初始请求均被捕获；镜像无合成凭证，官网认证保留 | [request-routing.log](evidence/request-routing.txt) |
| 多仓库任务来源 | 首次 API 响应时改选官网；原任务两个仓库仍请求镜像，下一任务请求官网 | 同上 |
| 集中回归 | OpenTypeTests 50 项，4 项跳过，0 失败；其他命中的 owner 测试也通过 | [focused-tests.log](evidence/focused-tests.txt) |
| 完整 swift test | 15 个测试 bundle 共 1,202 项，23 项跳过，0 失败，退出 0 | [最终 full-tests-ui-final-summary.txt](evidence/full-tests-ui-final-summary.txt) |
| 静态原生布局渲染 | 最后一次测试代码补充模型管理页截图后，单独编译并运行布局测试通过 | [layout-ui-final.log](evidence/layout-ui-final.txt) |
| 基础检查 | 最终 `bash scripts/ci-basic-checks.sh` 通过 | [ci-ui-final.log](evidence/ci-ui-final.txt) |
| SDLC 检查 | 最终 `bash scripts/sdlc-checks.sh` 通过 | [sdlc-ui-final.log](evidence/sdlc-ui-final.txt) |
| 最终差异检查 | `git diff --check`、新增文本空白与末尾换行检查通过 | [final-state.txt](evidence/final-state.txt) |

真实窗口发现并修复来源菜单语言刷新及底部间距后，已再次运行完整测试通过；随后运行最终静态布局测试。
最新完整日志保留在 `/private/tmp/utter-domestic-full-tests-ui-final.log`。运行中出现系统 Contacts 服务 XPC 诊断，但没有 XCTest 失败；未把这些诊断当作通讯录或权限功能的验收。

请求测试对初始请求返回确定的 401，避免依赖网络重试。因此它证明来源和认证接线，不证明完整文件请求、CDN 跳转的认证处理或模型可用性。
多仓库测试返回空 siblings，覆盖仓库查询之间的来源固定，不等同于暂停真实文件响应后切源。
既有取消、代际发布、下载失败和完整性测试通过，但本次尚未完成按来源扩展的全部网络错误矩阵、文件级切源和重定向凭证验证。

## Real download and offline loading

新测试仅使用独立 UserDefaults 和临时模型根目录，关闭启动预载。成功或失败后只清理本测试拥有的目录。

| 路径 | 模型及版本 | 实测结果 |
| --- | --- | --- |
| Whisper | 当前目录中 tiny 变体，入口 `hf-mirror.com` | 失败：Hub 元数据不完整；未获得完整模型，未证明离线加载 |
| MLX | `mlx-community/Qwen2.5-0.5B-Instruct-4bit`，默认 revision | 失败：相同元数据错误；未获得完整模型，未证明离线加载 |
| Confucius ASR | `mlx-community/Confucius4-R2T2-8bit`，revision `2d6d997c3e09c65a65b1b2576b6b9b7728df8eab` | 生产 Catalog 下载、发布后状态及禁止出站网络子进程中的 `Qwen3ASRModel.fromModelDirectory` 均通过 |
| 常规 Hub ASR | 非 Confucius 路径 | 初始请求捕获通过，完整真实下载与加载未执行 |

Confucius 权重为 2,463,307,541 字节，SHA-256 为 `49b41186fbd139d0c9b3ec50f31834e47b93a6617c9271cb7c28793822ac6a98`。
生产下载器继续按固定大小与哈希检查全部配套文件和权重，验证后才允许发布。下载及离线加载测试通过，见 [live-asr.log](evidence/live-asr.txt)。这不是识别准确率、音频体验或性能证明。
单独 Range 探针返回 206，配套文件与权重范围正确，见 [range-probe.txt](evidence/range-probe.txt)。探针的权重跳转经过官网后到 `us.aws.cdn.hf.co`，不能据此声称国内提速或整个生产传输的最终主机均相同。

Whisper/MLX 的初次失败测试在断言后还进入了缺失模型的加载步骤，产生后续失败。测试现已改为下载状态不符时直接抛错。保留的 [Whisper 根因摘要](evidence/live-whisper-failure.txt) 与 [MLX 根因摘要](evidence/live-mlx-failure.txt) 不把这些后续缺失文件错误当成独立根因；修正后的默认门控测试已通过编译，未重复整次失败下载。

## Metadata compatibility blocker

原假设：给现有 SDK 传入镜像端点即可兼容。实测否定了该假设在当前机器网络下的充分性。
可重复运行 `python3 scripts/probe-model-source-headers.py`，结果见 [source-headers.jsonl](evidence/source-headers.jsonl)。

| 负责传输的客户端 | 官网 HEAD | 镜像 HEAD | 影响 |
| --- | --- | --- | --- |
| WhisperKit 使用的 HubApi | 同主机 307 后 200，含 ETag 和 X-Repo-Commit | 308 到 `huggingface.co`，缺少这两项 | 元数据错误，下载不能完成 |
| MLX 使用的 HubApi | 同上 | 同上 | 相同失败 |
| Confucius 直接 Range 下载 | 独立实现 | 可跟随站点重定向并验证实际字节 | 完整下载与离线加载已通过 |

锁定版 `swift-transformers` 的 HEAD delegate 拒绝绝对重定向，以保留跳转前的文件元数据；镜像返回的 308 没有这些元数据，随后抛出 `Invalid metadata: File metadata must have been retrieved from server`。
直连探针、`?download=true` 和推荐 CLI User-Agent 均观察到相同 308。当前证据不支持把问题归因于空 Bearer 拒绝，也不证明国内网络有相同行为或镜像全站不可用。

未绕过哈希/元数据检查、未注册全局生产 URLProtocol、未静默改回官网、未改写依赖 checkout，也未为同一失败反复叠加补丁。
现有 SDK 没有开放所需的 HEAD 重定向配置。若需增加下载适配器或修改依赖，须先按已批准计划记录设计差异并审阅；当前实现不包含该变更。

## Release-style artifact

UI 修复后的最终构建首次在 Developer ID 签名时报 Apple 时间戳服务不可用，保留 [失败日志](evidence/release-ui-timestamp-failure.txt)。沿用原签名配置重试 `scripts/build-app.sh --app-only` 成功，退出 0，产物为当前工作区 `dist/Utter.app`。
使用已有 `Developer ID Application: Chen Li (G9L7H3T3D5)`，没有降级为 ad-hoc。
Metal、CLI、资源、Sparkle 嵌入、hardened runtime、签名及 release artifact verifier 均通过，见 [release-ui-final.log](evidence/release-ui-final.txt)。
此构建未启用更新 feed；没有执行 notarization、DMG 发布、push、PR、合并或部署，也不声称发布准备完成。

## Detailed UI audit

实现前与本次交付前均完整阅读 `<user-home>/.codex/ANTI_SLOP.md` 的全部 1,599 行，逐项检查本次适用要求。
按已批准的原生 macOS 设计，新增控件遵循现有系统表单；营销页的英雄图、定制字体、品牌插画、页脚和动效建议不适用于这个设置项。

生产 SwiftUI View 的静态渲染保留在 [layout 目录](evidence/layout/)。本轮修复后的静态渲染位于 [layout-ui-final 目录](evidence/layout-ui-final/)，设置页 760 × 680 pt、首次引导 480 × 420 pt，均覆盖中英文和 Aqua/Dark Aqua。
真实 CUA 窗口截图与 AX 树保留在本会话，逐步记录见 [native-interactions.md](evidence/native-interactions.md)。不把静态 PNG 当成 CUA 截图。

| 适用审计项 | 结果和边界 |
| --- | --- |
| 原生控件与信息位置 | 两页共用系统菜单式 Picker；实际点击选择，两页双向同步通过。来源位于下载操作前。 |
| 文案与真实信息 | 来源、域名及新任务生效范围可见。两页的真实下载确认均显示镜像；取消后改选官网，重试确认显示官网。未宣称镜像提速或稳定可用。 |
| 字体、层级、颜色 | 复用系统字体及语义颜色，已查看中英文、浅深色实际窗口。未做测量式对比度验收。 |
| 换行、对齐、间距 | 新增来源、域名、说明在最小内容尺寸中完整可见。发现 Skip 贴近分隔线后补 12 pt 底部间距，实窗复查通过。 |
| 语言切换 | 实窗发现原生菜单项缓存旧语言；增加语言 identity 后，重测中文切英文及反向切换，选中值与菜单项正确刷新。夹具中既有模型描述和已存错误文本的语言行为不在该结论内。 |
| 忙碌与错误态 | 实际启动下载时显示进度、取消按钮，来源控件保持可用。取消后可见暂停信息与重试；改选官网可重试并再次取消。 |
| 保存与共享状态 | 正常结束宿主并确认退出后重启，两页保留镜像选择。此为独立设置下的宿主重启，不等于打包 Utter 应用重启。 |
| 键盘与辅助功能 | 实测菜单中的 Up、Return 选择。AX 树显示 Popup button 的名称、当前值及菜单项；完整 VoiceOver 播报和仅用 Tab 的焦点遍历未验证。 |
| 视觉装饰与一致性 | 无新增渐变、发光、阴影、图标容器、徽章或装饰动效。内容不依赖动画出现；保持既有原生表单。 |
| 非强制下载 | 重启后无自动下载；点击 Skip 后 Continue 启用。完整后续引导流程和模型加载不属于夹具的证明范围。 |

用户于本轮明确允许打开 `/private/tmp/UtterSourceQA.app`，此前的自动审批执行阻塞已解除。
临时宿主启动时缺少 XCTestSwiftSupport 的搜索路径，修复后成功打开。全部界面操作均使用 CUA，未绕过原先拒绝。
宿主加载生产 View 和真实 Catalog，但模型生命周期服务刻意不可用。它使用独立设置及临时模型目录，验收后已正常退出。

## Remaining acceptance work

- 解决或在目标网络证明 HF-Mirror 与现有 SDK 的 HEAD 元数据兼容性，完成 Whisper、tokenizer、MLX 和常规 ASR 的完整镜像下载与离线加载。
- 补足文件/重定向级合成凭证检查、暂停文件响应后切源，以及按来源的网络错误覆盖。
- 核心原生窗口交互已完成；补足完整 VoiceOver、Tab 焦点遍历、打包应用中的完整会话，以及在实际传输中改选来源后的文件级请求验证。
- 上述验收完成前保持 NOT READY。用户可继续默认官网；来源切换不会迁移或删除已安装模型。代码回滚和数据兼容边界沿用 spec。
