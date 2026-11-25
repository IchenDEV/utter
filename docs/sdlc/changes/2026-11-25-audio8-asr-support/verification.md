# Verification: 支持 Audio8-ASR-0.1B 本地语音识别模型

**Status:** blocked
**Approved-by:** —
**Approved-date:** —
**Upstream:** [Plan](plan.md)

## Evidence

| 检查 | 结果 | 证据 |
|---|---|---|
| `bash scripts/sdlc-checks.sh` | 通过 | [sdlc-checks.txt](evidence/sdlc-checks.txt) |
| `bash scripts/ci-basic-checks.sh`（`DEVELOPER_DIR` 指向 Xcode 27.2） | 通过 | [ci-basic.txt](evidence/ci-basic.txt) |
| `swift test` | 通过：644 个测试、31 个跳过、0 失败；`UtterMLXTests` 12 个测试通过 | [full-tests.txt](evidence/full-tests.txt)、[full-tests-summary.txt](evidence/full-tests-summary.txt) |
| Audio8 集成测试（`OPENTYPE_AUDIO8_INTEGRATION=1`，真实 checkpoint） | 通过：6 个测试、1 个跳过（live download）、0 失败 | [audio8-integration.txt](evidence/audio8-integration.txt) |
| 已安装模型目录：重启后离线识别、删除 | 通过：`testInstalledCatalogReloadsOfflineAndDeletesAudio8` | [audio8-integration.txt](evidence/audio8-integration.txt) |
| release-style `bash scripts/build-app.sh --app-only --sign=-` | 退出 0；ad-hoc 签名、hardened runtime、release artifact 校验通过 | [release-build.txt](evidence/release-build.txt) |
| app bundle 内容 | 63 MB；未包含 `.safetensors`、`.onnx`、`.py`、`.mp4`；包含 `default.metallib` | [release-bundle-check.txt](evidence/release-bundle-check.txt) |
| 真实 HF 下载 | **未完成**：本机到 `huggingface.co` API/根域当前超时，`hf-mirror.com` API 308 重定向回 `huggingface.co`；多次 live 测试在文件列表阶段返回未完成 | [live-download-blocked.txt](evidence/live-download-blocked.txt) |
| 手工完整下载 checkpoint | 12 个 required 文件、`model.safetensors` 648,031,000 字节、SHA-256 `971d17f6…b23ca4`；该目录用于全部真实推理验证 | [manual-model-files.txt](evidence/manual-model-files.txt) |
| 模型管理 UI | 生产视图在 760/560 pt、light/dark、中文/英文共 8 张 PNG；Audio8 tab、模型行、约 664 MB 与 CC BY-NC 4.0 文案、LICENSE 链接均可见且未裁切 | [evidence/layout/](evidence/layout/) |

## Measured runtime (Apple M4, 16 GB)

| 项目 | 结果 | 目标 |
|---|---|---|
| 热加载（`prepare`） | 0.972 s | — |
| 5.19 s 英文音频转写 | 0.291 s | ≤ 3 s |
| 6.34 s 中文音频转写 | 0.210 s | ≤ 3 s |
| 测试进程峰值 RSS | 0.83 GB | ≤ 1.5 GB |

转写内容：

- EN: `Hey, so um, I wanted to. I wanted to follow up on the design doc we talked about.`
- ZH: `那个，我想问一下，这个接口，呃，是不是周五之前能 review一下？`

## Acceptance criteria

| # | 标准 | 结果 |
|---|---|---|
| 1 | 模型管理中可见 Audio8-ASR-0.1B，标注本地体积与非商业许可证；未下载状态准确 | 通过。catalog/unit 测试和 UI 渲染均验证。 |
| 2 | 可下载，重启后离线识别，可删除，删除后状态恢复 | **部分通过**。已安装目录的重启、离线识别、删除、状态恢复通过；真实网络下载被当前 HF 不可达阻塞。下载参数（revision、只下载 required files、marker）由单元测试覆盖。 |
| 3 | 选择后 16 kHz 中英文短音频能完成本地转写，日志证明 Audio8 路径 | 通过。真实 checkpoint、真实 `en-sample.m4a`/`zh-sample.m4a` 集成测试；日志包含 `[Audio8ASR]`。 |
| 4 | 长音频、资产缺失/损坏、取消路径明确且不静默回退 | 通过。`audioTooLong`、`notConfigured`/坏 config、取消传播测试均通过。 |
| 5 | 热词/上下文传递；不支持时明确记录 | 部分通过。decode-time trie、first/continuation boost、top-50 gate 有单元测试；真实音频没有包含稀有热词的 fixture，只验证了配置上下文后输出非空。 |
| 6 | 标准检查、release-style build、真实音频证据记录 | 通过（live 下载除外，已单列）。 |

## Residual risk

1. **真实下载未完成（外部阻塞）**：本机当前无法访问 `huggingface.co` API。`ModelCatalog.downloadASR` 的 revision pin 与 selective matching 参数由 `ConfigurationTests` 覆盖，但尚未在本机跑通一次完整的 `snapshot` 下载、marker 写入、generation commit、重启离线、删除链路。网络恢复后应重跑 `OPENTYPE_AUDIO8_LIVE_DOWNLOAD=1`。
2. **热词真实效果未量化**：没有带稀有词的音频 fixture；已通过 trie/top-k/boost 单元测试验证机制，真实音频只验证不产生空输出。
3. **UI 证据是生产视图 fixture 渲染**：使用真实 `ModelManagementView` 和 AppKit 布局，但不是打包应用内的交互；未在真实打包 app 中点击切换 Audio8。
4. **许可证**：模型为 CC BY-NC 4.0，仅限非商业用途；UI 在下载入口展示限制和 LICENSE 链接，但无法技术性阻止商业使用。
5. **性能**：只在 Apple M4/16 GB 上测量；首次冷加载未单独计时，`prepare` 为热文件加载。
6. **下载看门狗修复**：修复了 sub-threshold fraction 进度被忽略导致大文件被误暂停的问题，新增回归测试；真实慢速下载未能在本次网络条件下验证。

## Decision

Blocked：实现、单元/集成测试、UI 渲染和 release build 已完成；唯一未完成的是真实 Hugging Face 网络下载。需要网络恢复后重跑 live download，或由所有者明确接受该残余风险。
