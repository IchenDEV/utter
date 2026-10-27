# Run4 真实 SwiftPM 构建证据

**Status:** draft
**Authorization:** 本轮整体授权持续；仅完整编译与确证错误修复，不代表产品验收。
**Result:** interrupted，完整构建未通过。磁盘触发既有 10 GiB 保护后停止自身构建。没有编译错误证据，因此本轮没有源码或测试 fixture 修改。

工作目录 `RESEARCH_WORKTREE`，环境 Mac mini `DEVICE_BINDING_IN_IGNORED_LOCAL`。HEAD `ed4234b41764be8346ae58cdc63011c8f26a0f1e`。未委派、未下载工具/模型、未改 dependency/lockfile/权限/签名，未使用 production 未提交源码或缓存，未停止维护 daemon 或其他 Agent，未删除证据。无 commit/push/PR/release。

## 前置阅读与边界

已读仓库 AGENTS、SDLC README、istack AGENTS/agent-routing/t3-delegation、Ponytail FULL、spec/plan/verification/workflow、Run3 状态/清单与 b-r3 日志。使用 Unslop 与 explain-clearly 整理证据；用户禁止委派，直接完成报告。无 UI 制作或视觉 QA，本轮不启动 ANTI/原型审计。

Run3 的真实错误是 `DeliveryServices.swift:101:59` 在非隔离 autoclosure 引用 MainActor `OutputAnchor.text`。Run3 已将该校验移入 MainActor `SessionOutputState.remember`；其最终 emit-module 日志为空且通过，但使用 synthetic Bundle.module。这里保留该历史分类，不将它当作本轮真实 SwiftPM 通过。

已查相关 git 历史和实际契约/调用路径。单一 SessionDriver/SessionControl/VoiceSessionJob 持有同一 Session；selectionEdit 与 spoken selection replacement 复用 recipe 和 review，再走同一 deliver。review 保持 busy，停止/释放录音，Apply 绑定 session/proposal 身份并只唤醒一次，随后再核对 PID/target/lease/原文；Cancel/expiry 结束候选。lease 依赖 focus、AX identity、UTF-16 范围/选区和全文快照；现有 confirmed targetValue receipt 才保留原文/replacement/anchor；restore 消费一次 receipt 并 replaceAnchor 原文。编译不能证明这些不变量在真实宿主、普通听写、权限/隐私或焦点返回成立。本轮没有据此修改架构。

## 工具链、缓存与命令

Apple Swift 6.2.3，swift-driver 1.127.14.1，swiftlang-6.2.3.3.21，clang-1700.6.3.2，工具报告 target `arm64-apple-macosx28.0`。macOS SDK 26.2，路径 `/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk`。`xcodebuild -version` exit 1，活动 developer directory 为 `/Library/Developer/CommandLineTools`，需要完整 Xcode；没有修改 developer directory。`DEVELOPER_DIR/SDKROOT/SWIFT_EXEC/CLANG_MODULE_CACHE_PATH/SWIFTPM_MODULECACHE_OVERRIDE` 均未覆盖。

读了 Package.swift、ci-basic-checks.sh、test-industry-lexicons.sh、build-and-run.sh 与 build-app.sh。禁止的 build-and-run 未执行，其 pkill/签名/启动行为仍未触发；release 打包未执行。19 个依赖 checkout 及锁定 revision 均已在本地。无 binary target 下载声明，artifacts/prebuilts cache 初始为空；关闭 SwiftSyntax experimental prebuilts，避免其默认下载。mlx-swift 0.31.4 checkout/repository 已存在，但 workspace-state 尚未登记，真实 SwiftPM 由本地 repository 创建工作副本并登记。没有观察到 fetch/download 日志。依赖 checkout revision/状态、锁定 pins、工具 exit、资源 SHA 在 raw 环境证据中。

原 ci-basic-checks.sh 使用无离线参数的 `swift package describe`，行业词典脚本使用 `swift run UtterLexiconCheck`。不能对其默认解析/预编译下载行为提供所需约束，因此原脚本 not-run；没有替换 swift、改脚本或制造通过。Swift test not-run，完整 build 因空间保护中止，不能继续重型检查。

完整构建命令没有 target/product 限制，不用 parse、emit-module 或 Bundle.module shim 替代：

```sh
swift build --skip-update --disable-automatic-resolution --disable-prefetching --disable-experimental-prebuilts --disable-index-store --jobs 2
```

使用默认 debug、arm64 与 .build 缓存，关闭 index store 并限制 jobs 为 2。真实构建编译了 GenerateManual/GenerateDoccReference plugin、_NumericsShims、yyjson、_NIOBase64、_AtomicsShims，并复制 tokenizer JSON/PrivacyInfo.xcprivacy。停止时最后日志为 `[17/308] Write sources`。没有完成全部模块/产品链接或全部 Utter resource bundles，未生成可验收 OpenType 包。

构建开始 `2026-10-07T22:24:35.256062+00:00`，结束 `2026-10-07T22:25:22.997666+00:00`，子进程 PID/PGID `7166/7166`，supervisor PID `7163`。构建 exit `-2`，status `interrupted`；native tool session `49408` supervisor exit 0，仅表示监督/回收完成。

实际 preflight df 可用 `10832539648` bytes，约 `10.088589` GiB。每约 0.5 秒在自身普通命令内读取 df。最低 `10734473216` bytes，约 `9.997257` GiB，低于 `10737418240` bytes 保护线。`2026-10-07T22:25:22.901850+00:00` 对自身 PGID 发 SIGINT，返回 -2，remainingGroupProcesses 空。未重试同一空间阻塞；未删除或迁移缓存来扩预算。

构建日志 SHA256 `28023756db0943baae95ad3937460936d3851f3763695b3e74083ec86c7d837c`。

- `bash scripts/sdlc-checks.sh` pass，`2026-10-07T22:25:20.214662+00:00` 到 `2026-10-07T22:25:22.327098+00:00`，exit 0，PID/PGID `10037/10037`，日志 SHA256 `5ed5fb27bb8a18b455bb5c10b900d0e0b602a1b7dc598eecbd736cacdc07bfc0`。
- 首次受同一空间保护的 diff 命令 not-run；轻量只读 `git diff --check` 后续 pass，`2026-10-07T22:26:07.943952+00:00` 到 `2026-10-07T22:26:07.975197+00:00`，exit 0，空日志 SHA256 `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855`。
- `bash scripts/ci-basic-checks.sh` not-run，原命令缺少离线约束；行业词典未执行，不能声称 basic pass。
- `swift test` not-run，空间不足且完整构建未完成。测试 conformance 没有真实 compiler 证据，不预修。
- release、签名、native UI、权限/隐私、真实宿主/设备、普通听写/焦点、安全恢复、独立验收均 not-run。

## 精确源码与产物

Tracked binary diff SHA256 保持 `11b3c4932766a8fdd6cfda1e243193c06afb1ce6b38c686baf94698ec27e8a83`。18 文件 sorted compact JSON 清单 SHA256 保持 `f64965163a8c900c3a233dcd9ff6dd3f8133189378c27d4c813afa6f0c36c831`，包括两个未跟踪新 Swift 文件。before/after 内容逐文件相同。

完整 root source/resource/test manifest 覆盖 `Sources/`、`SourcesCLI/`、`Tests/`、Package 中行业词典/eval target 的脚本源码、`Package.swift`、`Package.resolved` 与 `scripts/resource-bundles.json`，共 787 文件，before/after 均为 SHA256 `4c5cf71ff0508d0d11a40e0aa5e3456239c81f31afb5960bc2e481115cb8f9f2`。完整逐文件哈希在 raw `full-source-manifest-before.json` 与 `full-source-manifest-after.json`，并非仅 tracked diff。19 个依赖 checkout 的 revision、Package manifest SHA 和工作树状态在 environment/status JSON；不将未完成依赖编译当通过。

18 文件本体 SHA256：

- `Sources/UtterContracts/DeliveryServices.swift`: `e1d03e2882914048c6fef51538d4a029825c2e9e5618abac85cdb0e904657f33`
- `Sources/UtterContracts/Resources/en.lproj/Localizable.strings`: `c60b316ca09ec908196a2f265f02de290894a743bcf179ff71e0f97cb1244954`
- `Sources/UtterContracts/Resources/zh-Hans.lproj/Localizable.strings`: `52776c17de4a52d1f84d9cd2eb83dfcdf803d0fe9c806c3597b2b471df625410`
- `Sources/UtterContracts/SelectionEditProposal.swift`: `c742db8328f3df4b0a68fa4567fc8c8f606e46e2727cf545f10299be86fa9d76`
- `Sources/UtterContracts/SessionExecutionService.swift`: `ef3d80f03d6e86cc03aadda77bf25e6355abce81975eefc9b4726c6ade96c95b`
- `Sources/UtterContracts/SessionOutputStateService.swift`: `48582261ab50beadb8f5f356205992991bb117a10158d4509a4aed2b21b14fd1`
- `Sources/UtterContracts/SessionPresentation.swift`: `60fb70c1376733df9a3ed54c745c43a705881b1e4155007024852f36f01e23fc`
- `Sources/UtterMacServices/Native/NativeOutputBackend.swift`: `c658a8053b162b06fd4e82315f3bdb68b94807780950bcb4ddcbff3ce20698c2`
- `Sources/UtterMacServices/Native/NativeTargetLease.swift`: `7d1b9ce1c84e114cdd7f9fa4a6907ff43b3f03c332b04b997a3880f1e35654f1`
- `Sources/UtterMacServices/ScopedOutputService.swift`: `d80a1248368671b0c8478308527a4a1acffb7722793c0a27520eb7d761b2400d`
- `Sources/UtterPresentation/NativeDesktopHost+Actions.swift`: `09c8e7fa6b77a9f54b5b9656356f7f03875829b74196ebb6e618d5caf8c68012`
- `Sources/UtterPresentationContracts/AppState.swift`: `f7a1315564f04fbf2df3dbd55d894b52869b614ceed2fc80674b5176e932e86f`
- `Sources/UtterSession/Native/VoiceSessionJob+Editing.swift`: `5d4b835cf3e49b32a3cc153e098a9525bae0fa23a2db0d673414bad0c78f5ced`
- `Sources/UtterSession/Native/VoiceSessionJob+Review.swift`: `e15b4251e7d32c8f29e540797f0fbf122727ddae85b2f91f41b6ef76ecf1b118`
- `Sources/UtterSession/Native/VoiceSessionJob.swift`: `6a79230b9f8049989ea1b2e0bd4abe98bdbe1ba4d7567b2d69dc0eddff6ba9ab`
- `Sources/UtterSession/SessionControl.swift`: `6f952e846d6922af0e87e66908daa015fd240af0eda0bfaf4e091e816dc213c9`
- `Sources/UtterSession/SessionDriver.swift`: `5cbd15ee425e6dd15bc4fd27b03932226b8e7a93c39751843644d53536da64a1`
- `Sources/UtterSession/SessionOutputState.swift`: `21c5a6b1f0a4a5cccefe34ca7c99bcf13aeedaeb9c361e0f37dd71f37a265776`

Raw ignored 证据统一在 `.local/voicecursor-research/run4-build/`：`build.log`、`build-result.json`、`sdlc.log`、`sdlc-result.json`、`diff-final.log`、`diff-final-result.json`、两套 before/after manifests、`environment-cache-resources.json`、`dependency-checkout-status.json`、`partial-build-artifacts.json`、`process-terminal.json` 与普通监督脚本 `supervise.py`。部分 build artifacts 保留于本 worktree `.build/arm64-apple-macosx/debug/`，不是 app/package 候选。未复制 production artifacts。

## 终态与后续

已核验已知 supervisor/build/SDLC PID 和进程组均不存在，同 worktree 无 swift/clang/linker 构建进程残留。单次 native 调用均 <=30 秒，没有 watcher/daemon/timer 或新增子 Agent。command 监督截止设为 22:27:40Z，早于本执行者目标 22:28:20Z、负责人预取消 22:28:30Z 与 hard native 截止 22:28:50Z。本报告不是 agent native completedAt，后者由负责人通过宿主核验；未写其独占 Run4-state/plan/workflow/verification。

下一轮在负责人解决真实可用空间后，从保留的真实 .build 缓存继续同一完整 build，只修真实 compiler 错误，再完整重编译及 swift test。原 basic 脚本须有明确的离线执行约束，不能以替代检查冒充。release 风格仍需完整 Xcode、既有签名 owner 和独立验证，不能据本轮 CLI SDK 证据放行。原生 UI 与 focus/privacy/普通听写、安全取消/恢复宿主用例及既有 HTML recapture/Close/Restore 缺口保留给后续负责人，本轮没有修原型。
