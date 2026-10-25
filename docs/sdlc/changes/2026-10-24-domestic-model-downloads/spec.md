# Spec: 添加国内模型下载源

**Status:** approved
**Approved-by:** 用户（本会话在设计提交后明确回复“批准”）
**Approved-date:** 2026-10-24
**Upstream:** [intent.md](intent.md)

## Context

用户于 2026-10-24 在本会话明确批准 [intent.md](intent.md)。首版提供官网和 HF-Mirror，官网仍为默认源。

设置通过 `SettingsValues`、`SettingsStore` 和 `AppSettings` 持久化并通知界面。
`ModelCatalog` 管理下载生命周期，`ModelDownloadTasks` 按模型仲裁任务，下载写入独立的代际暂存目录，完整性检查后才发布。
MLX 下载通过 `TextModelDownloadService` 跨模块调用。Whisper 权重、Whisper tokenizer、常规 ASR 和 Confucius 各有下载入口。

已只读核对主检出目录中缓存的依赖源码，其 HEAD 与本工作区 `Package.resolved` 一致，所查文件无本地修改：

- `argmax-oss-swift` 1.0.0，`25c62997041c134b03ca82731ce2f6fd2cae1eb9`。`WhisperKit.download` 接受 `endpoint` 和 `token`，`HubApiWrapper` 将参数传给内部客户端。[锁定版本源码](https://github.com/argmaxinc/argmax-oss-swift/blob/25c62997041c134b03ca82731ce2f6fd2cae1eb9/Sources/WhisperKit/Core/WhisperKit.swift)
- `swift-transformers` 1.3.3，`2fa33e1f5e7131a7fc64c28e6d161dcec0d24820`。`HubApi` 接受 `endpoint` 和 `hfToken`，`hfToken: nil` 会启用环境认证。[锁定版本源码](https://github.com/huggingface/swift-transformers/blob/2fa33e1f5e7131a7fc64c28e6d161dcec0d24820/Sources/Hub/HubApi.swift)
- `swift-huggingface` 0.9.0，`b721959445b617d0bf03910b2b4aced345fd93bf`。固定空令牌不读取环境，但 HTTP 客户端可能仍生成空的 Bearer 头。这需要请求级检查和镜像实测。[令牌提供器](https://github.com/huggingface/swift-huggingface/blob/b721959445b617d0bf03910b2b4aced345fd93bf/Sources/HuggingFace/Shared/TokenProvider.swift)、[HTTP 客户端](https://github.com/huggingface/swift-huggingface/blob/b721959445b617d0bf03910b2b4aced345fd93bf/Sources/HuggingFace/Shared/HTTPClient.swift)

## Design

### 来源与持久化

`UtterContracts` 增加 `ModelDownloadSource` 值类型，提供两个固定来源及对应 HTTPS 端点：

```swift
package enum ModelDownloadSource: String, CaseIterable, Sendable {
	case huggingFace = "huggingface"
	case hfMirror = "hf-mirror"

	package var endpoint: String { /* 固定端点映射 */ }
}
```

两个端点分别为 `https://huggingface.co` 和 `https://hf-mirror.com`。
`SettingsValues.modelDownloadSource` 默认取 `.huggingFace`。
`SettingsStore` 用独立键 `modelDownloadSource` 保存 raw value。缺失或无法识别的值在读取时回到 `.huggingFace`。
`AppSettings` 复用现有动态成员投影，无需增加第二套观察或设置服务。

应用设置显式决定端点，优先于依赖的 `HF_ENDPOINT` 自动检测。
不修改进程环境变量，不根据语言、IP 或地区自动选源。

### 下载任务固定来源

`ModelCatalog.downloadWhisper`、`downloadASR` 和 `downloadLLM` 的外部签名保持现状。
新一代任务获准执行后，在第一次异步下载前读取一次来源，保存为局部不可变值。
该值传给任务中的仓库查询、所有文件下载和 tokenizer 安装。ASR 的多个依赖仓库使用同一个值。

同模型的重复请求仍加入正在运行的任务。改选来源不会取消或改变正在运行的任务。
取消后重试会创建新一代任务，使用届时的选择。暂存目录、任务 token 和发布检查继续沿用现有机制。
来源不写入 `ModelDownloadStaging`，后者继续只描述存储与缓存。

跨模块边界增加必传的类型化参数，避免 MLX 自行回读可变设置：

```swift
// TextModelDownloadService 的目标签名
func download(
	_ id: String, source: ModelDownloadSource,
	downloadBase: URL, cacheDirectory: URL,
	progress: @escaping @Sendable (Progress) -> Void
) async throws
```

`TextModelDownloadOperations.download` 同样传入来源。
`ModelCatalogPlugin`、`MLXModelDownloadPlugin`、`MLXModelDownloads` 和 `MLXModelLoading.downloader` 逐层传递该值。
所有生产调用者和测试替身在同一实现阶段迁移，不保留会静默选择默认源的旧重载。

### 各下载入口

- Whisper 权重调用现有 `WhisperKit.download`，显式传入来源端点和认证覆盖值。
- Whisper tokenizer 的 `HubApi` 使用同一个来源，仍只安装所需 tokenizer 文件并验证 manifest。
- 常规 ASR 的 `HubApi.snapshot` 使用选定端点，多个仓库逐个处理。
- MLX 的 `HubApi` 使用跨模块传来的端点，现有解析、下载文件模式和发布后的加载验证继续生效。
- `ConfuciusModelDownloader.downloadRepository` 接收必传来源，用它构造固定仓库和固定 revision 的 URL，包含配套文件和权重。底层 Range 下载的 URL 改为必传，防止权重遗漏后再次使用写死的官网默认地址。

不增加下载框架或依赖，不另建镜像专属模型目录。
`ModelStorage.hubModelRepoDir` 中用于计算本地路径的 `HubApi.localRepoLocation` 无网络请求，不需要添加来源参数。
已安装模型、本地导入和离线推理按原有路径工作。

### 原生设置控件

新增一个小型 SwiftUI 来源选择视图，由模型管理页和首次引导的模型准备页复用，绑定同一个 `AppSettings` 字段。
使用原生菜单式 `Picker`，选项为 `Hugging Face（官网）` 和 `HF-Mirror（国内镜像）`，英文提供对应翻译。
模型管理页把控件放在模型下载配置之前；首次引导放在下载按钮之前。

控件始终显示当前选择，下载期间仍可操作。
说明文字写明“更改仅影响之后开始的下载”，镜像选中时说明公开模型从 `hf-mirror.com` 下载。
来源变更立即持久化，不增加保存按钮，也不触发模型下载或卸载。
保持现有下载确认步骤，确认信息同时显示将使用的来源。

新增文案均用 `L("key")`，补齐中英文条目。
控件采用系统字体、系统语义颜色和现有表单间距，保持可见标签、键盘焦点和 VoiceOver 可读名称。
说明文字允许换行；不对内容增加固定高度或裁切，也不加入装饰动画、徽章、图标容器或自定义阴影。

## Safety and failure modes

### 镜像认证

镜像仅用于公开模型。Whisper 的 `token` 和 Hub 的 `hfToken` 显式传 `""`，禁止依赖自动读取环境或本地保存的 Hugging Face 凭证。
官网继续传 `nil`，保留原有官网认证行为。
Confucius 的直接 URL 请求使用现有临时会话，不添加认证信息。
应用的远程推理密钥不参与模型下载。

空令牌不等同于所有请求都没有 `Authorization` 头。
锁定依赖的部分请求会携带空 Bearer 值，必须验证其中不含真实凭证，并验证镜像接受这些请求。
如果镜像拒绝空 Bearer，停止交付并调整客户端认证配置，不能改回自动读取真实令牌来绕过失败。
认证测试用隔离进程中的合成令牌检查请求，不读取或打印用户真实凭证。

### 下载失败与重定向

源站返回的 CDN 重定向可由现有下载器处理。记录实际文件的最终主机，区分选择的入口和 CDN。
固定来源约束适用于应用和依赖构造的初始请求，不承诺所有字节都由同一个域名提供。
不自动跨源重试，不把官网和镜像的内容拼接成一次下载。

连接失败、超时、镜像缺失仓库、鉴权失败和无效文件沿用现有错误状态与重试入口。
用户可以切换来源后重试。来源选项与错误状态同时可见，不宣称镜像始终可用或更快。
继续执行现有文件完整性检查、取消仲裁与发布检查。
Confucius 的固定 revision、尺寸、Range 响应及 SHA-256 校验不降低要求。
镜像失败不能发布不完整模型，也不能覆盖已安装的有效模型。

## Test strategy

实现后的验证要覆盖以下可观察行为：

- 设置：默认值、保存后重建 `SettingsStore`、未知 raw value 回退、`AppSettings` 的观察通知。
- 端点：从生产下载入口捕获 Whisper、tokenizer、常规 ASR、MLX 及 Confucius 的初始请求，断言来源、仓库、revision 和文件路径。仅测试端点映射函数不足以证明接线完成。
- 任务：暂停文件响应后切换设置，旧任务的后续文件继续使用旧源，新任务使用新源。同模型重复请求、取消后重试和多仓库 ASR 均需覆盖。
- 认证：隔离进程预置合成 `HF_TOKEN`，验证镜像的元数据、文件和重定向请求均不携带该值；检查空 Bearer 的实际行为。官网认证回归另测。
- 失败：捕获连接错误、超时、404、401、无效内容、取消和校验失败，断言错误可见，且发布目录不出现新的不完整模型。
- 缓存：切换来源不改变已安装目录；已下载的代表性模型可在禁用网络后加载。
- 真实下载：分别完成镜像的代表性 Whisper、ASR 和 MLX 模型下载与加载，记录模型 ID、版本、初始端点、重定向主机和结果。Confucius 的 Range 及固定版本另行检查，未覆盖的模型类型明确记为未验证。
- 界面：真实窗口中完成选源、切换页面、重启、下载确认、取消、切源重试；检查中英文、浅色、深色、最小支持宽度、键盘和 VoiceOver。记录裁切、对齐、对比度与说明换行的检查结果。
- 仓库：运行 SDLC、基础检查、完整 `swift test` 和 release-style 构建。相关日志与真实窗口证据写入 `verification.md`。

自动化测试使用隔离的设置与临时模型目录，不删除或覆盖用户现有模型。
依赖调用的替身测试、真实网络下载和真实模型加载分别报告，不能互相代替。
当前沙盒、依赖获取等工作区阻塞见 [verification.md](verification.md)，不把未执行的测试计为通过。

## Rollout and rollback

设计批准后编写执行计划，计划批准后才实施代码和测试。
首版使用手动选源，既有用户继续默认官网；切换来源不迁移或删除缓存。
镜像覆盖、认证行为、完整性、任务取消或离线加载任何一项不满足验收标准时，停止交付并记录原因。

用户层面可以改回官网，新任务立即使用官网。
代码回滚可移除本次来源字段、参数与控件，恢复既有下载调用。保留已下载模型和文件结构，无需数据回滚。
旧版本忽略新增设置键，重新升级后仍能读取该选择。
本设计不包含发布、签名配置、更新服务或生产部署授权。
