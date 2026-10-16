# Verification: 首轮研究检查

**Status:** draft
**Approved-by:** —
**Approved-date:** —
**Upstream:** [plan](plan.md)

本轮仅研究与文档，未实现候选功能。官方网页实际浏览、视频抽帧、源码核对与 T3 durable 状态属于研究证据，不是产品 E2E 通过。详细分类见 [source evidence](source-evidence.md)。

检查和子任务回收结果在本文件收尾追加。任何未来实现必须绑定准确源码/包哈希重新执行 SDLC/basic/Swift tests、真实宿主与设备验证。原生产线已有失败与旧包通过范围保留，不平移。

## 首轮收尾结果

- SDLC checks passed。workflow JSON解析、git diff --check通过；git status仅新研究目录未跟踪，产品源码未改。
- basic检查触发swift-run依赖解析，预算内未完成，已用native write_stdin Ctrl-C取消并返回exit130。日志保留，不报通过。
- swift test --skip-build --disable-automatic-resolution仍开始创建依赖working copy，12秒timeout后终止，未执行测试。无缓存测试通过可借用，完整检查留在后续实现验收。产生的ignored .build缓存未删，避免破坏其它证据。
- 唯一T3 Apple子任务completed、hasPendingChildRuns=false；产物和源分类已核对。子任务截止超过13秒，已记录；未再派返工，父预算仍按最初startedAt收尾。
- 完整复读ANTI_SLOP并逐标题审计，详细结果ignored .local/voicecursor-research/anti-slop-audit.json。本轮无自制UI，视觉风格条目不适用；真实交互范围只有官网导航和视频seek，没有把宣传面板作为可操作Utter原型。没有产品界面可修或可验收。
- 14张官方视频/隐私页截图有SHA256映射；没有读取/发布私密宿主内容。未用iPad，不改原工作区，不commit/push/PR/deploy，无watcher或定时器。
- 结论停在intent pending approval。仍缺VoiceCursor客户端实测、Utter新契约宿主E2E、签名Release/移动T0闭合和发布批准。

## Run 2 authorization, budget correction and coordination

用户整体授权已记录，首轮 pending approval 已被取代。上轮父 native startedAt21:09:56.301Z、completedAt21:20:51.594Z，实际超55.293秒；Apple任务 native 超56.6秒，产物+13秒不能证明原生准时。已纠正 workflow，不重复误判。
原线 ordinal24 completed21:59:36.954Z，cursor2617，HEAD ed4234b4，38个tracked改动未复制。iPad空闲但T0未通过；研究不使用设备。
UI首稿 admitted only first400/1599 ANTI_SLOP lines and no render，未完全验收，派一次有界Cursor修正；负责人已完整前读，实际浏览器点击模拟应用/一次恢复/空答/失效。模拟不是产品宿主通过。
apply_patch重复delete/add同路径报invalid patch，未写入；改用一次Update修正，无产品损坏。

## Run 2 retained candidate and final audit

Base ed4234b41764be8346ae58cdc63011c8f26a0f1e; diff SHA256 06424f638677956353ff65fcfef6745fdfa08fa9df7ce93f44be4f242df39d8b. Product increment +55/-7 in6files uncommitted. Swift frontend parse and diff check passed; SDLC passed. basic/swift-test each8s timeout→SIGTERM -15; process-group terminal verified, no pass. No package candidate, Release or real host/device tests.

Browser click checks: recording/recognized instruction, apply state, one-use restore state, empty/error apply disabled, stale blocked, long800-code-unit content scroll without horizontal overflow, cancel clearscandidate, uncertain hides apply/restore. These are simulated state checks only. Before/after screenshots copied ignored ui-r2-before.png/ui-r2-after.png.

Lead full ANTI_SLOP read before and after UI review. Final audit NOT PASSED; concrete pending issues:
- uncertain关闭会reset到captured，丢失未解决警告
- Apply handler只检查stale，缺少phase/empty/replayguard
- Enter文案声称只有点击，实际焦点按钮可Enter激活
- 缺少真实host mutation fixture，应用/恢复只切状态
- filled/outline按钮对、beige、hairline boxes 尚待Cursor修正
- dark/narrow/VoiceOver/完整真实宿主未验收

UI task completed22:00:22.610Z; receipt interrupted22:02:46.245Z (+1.245s child cutoff); Cursor correction interrupted22:02:46.306Z (+1.306s). All hasPendingChildRuns=false, no task active. Native completedAt used, not artifact writes. Task IDs and owners in workflow/raw state. Parent future native terminal time deliberately null until root checks; close artifact time not terminal.

## Run 3 source review and bounded scope

Root复核Run2 native开始21:55:56.728Z、结束22:05:40.154Z，累计583.426s，未超600s。6文件+55/-7与diff哈希已现场确认；只按partial retained接受。Run3 native开始22:08:15.147Z，22:16:15.147Z停止扩展，22:18:15.147Z硬截止。

已重新完整读AGENTS/SDLC/istack路由与委派规则、编排技能、Ponytail full、spec/plan/workflow/verification、Run2原型及失败日志。负责人完整前读并完整后读ANTI_SLOP 1-1599行；原型仍需真实交互和逐项审计，未把阅读当验收。UI纠错为同因第2次，不再派泛泛重审。

Data只读df测10689784KiB(约10.19GiB)，本轮不运行重型构建。原production durable仍ordinal24/cursor2617，无新增活动，HEAD相同，38个tracked改动与多项untracked保留，只读未复制。旧iPad空闲不是当前预约保证，本轮无设备操作。

负责人源码核对观察：direct selectionEdit与spoken replace/rewriteSelection均改为等待当前Session提案；Apply检查session/proposal与单次continuation，原Job再核对lease。目标lease增加整篇AX值比较，需下一轮审查是否不必要影响普通听写、长文性能与全篇内存隐私；既有AX state只保存选区和各500 UTF16周边。真实失焦/焦点返回尚未证明。原生UI仅有状态和动作桥，调用搜索未发现实际审阅按钮消费，不能宣称桌面流程闭合。新增protocol requirement的所有生产与测试conformance需完整typecheck验证。

读取原线程时一次ID拼写错误thread_not_found，已用正确ID重读成功，未推断线程消失；一次猜测VoiceSessionJob+Output.swift路径不存在，未编辑该路径。未重启provider、未注册付费/认证/权限修改。

## Run 3 retained result and final audit

A/B both native interrupted before their deadline: B22:09:50.382Z→22:15:06.263Z (315.881s), A22:12:32.599Z→22:15:06.314Z (153.715s). activeRunId null, pendingRequestCount0, hasPendingChildRuns false. Proactive native stop; no new tasks after expansion cutoff. All task/clientRequest IDs and native state saved run3-state/workflow. A delegated late in parent budget, only153.715s actual; budget did not reset, complete correction/audit was not achieved.

B actual-source synthetic-boundary behavior check passed for pending/no write before Apply, one-use/wrong-ID, Cancel, stale lease, replaced session, empty result, expiry and Unicode preservation. This harness imports production control/review sources but stubs target/mic/callbacks and counts continuation completion; does NOT perform actual host mutation, driver settlement, receipt restoration or model failures. Runtime/Contracts/MediaContracts/Session/PresentationContracts swiftc emit-module probes passed with synthetic Bundle.module shim; initial MainActor anchor.text compiler error was corrected at SessionOutputState owner. Native actions/output/lease parse, localization lint/module boundaries and SDLC passed; full SwiftPM build/basic/Swift test and native UI/host/Release still not run or passed. Raw child commands and compile logs preserved.

A lead pointer checks: fixed-data generation→Apply truly mutates simulated host; Restore recovers exact original once; post-edit disables Restore; uncertain Close/Reopen persists warning and blocks Apply. Source handler checks phase/nonempty/current target/text/range/focus/transaction. NOT ACCEPTED: recapture and close after applied reset/newHost and erase subsequent simulated input; closing changes host without incrementing writes. Restore lacks range check. Cursor final audit not delivered. Lead complete ANTI reread and per-point audit saved anti-slop-audit-r3.json, passed=false; dark/narrow/contrast/VoiceOver and remaining invalid-handler scenarios not measured. No third same-cause generic audit spawned.

HEAD ed4234b41764be8346ae58cdc63011c8f26a0f1e; tracked binary diff SHA256 11b3c4932766a8fdd6cfda1e243193c06afb1ce6b38c686baf94698ec27e8a83; complete changed-source manifest SHA256 f64965163a8c900c3a233dcd9ff6dd3f8133189378c27d4c813afa6f0c36c831. Two new Swift files included in manifest, not in tracked diff. No binary package candidate.

No actual host/device use, no permission/auth/paid/install or production-worktree mutations, no commit/push/PR/release. Next: bounded full compile+necessary fixes, concrete native presentation wiring and its privacy/focus review, independent real-host safety E2E; mobile stays dependent on originalowner real T0/device reservation. Native parent completedAt remains null until externally observed; artifact write time never used as terminal time.


## Run4 — real full compile evidence (2026-10-07T22:30:32.386605+00:00)

Overall user authorization continues; this is not actual acceptance. Result: partial retained, full compile NOT PASSED. The unshimmed complete SwiftPM command and logs are in [build-result-r4.md](build-result-r4.md). Build ran 22:24:35.256062Z–22:25:22.997666Z; minimum Data free 9.997257 GiB triggered the existing 10 GiB guard, own PGID was interrupted/reaped, build exit -2. No compiler error confirmed and no source/test changes made. SDLC and git diff --check passed; basic and swift test not run; no UI/host/device/Release acceptance.

HEAD `ed4234b41764be8346ae58cdc63011c8f26a0f1e`; tracked binary diff SHA256 `11b3c4932766a8fdd6cfda1e243193c06afb1ce6b38c686baf94698ec27e8a83`. Full repository source/script/resource manifest: 846 files, canonical SHA256 `de6b2fe41b205b259748fc91df8dea7189b1a2dc2c8fba4f0e8d232d875efc50`, unchanged=True. Child's narrower 787 compile-source manifest is separately labeled in its report. Build log SHA256 `28023756db0943baae95ad3937460936d3851f3763695b3e74083ec86c7d837c`. Raw: `.local/voicecursor-research/run4-build/` and `Run4-state.json`.

Only child task `node:delegated-task:command%3Amcp%3A67541bea-8eb1-4d26-8f01-933833e33315%3Adelegate-task%3Avoice-editing-full-build-20261008-r4` native started22:22:35.633Z, completed22:28:42.038Z (366.405s); activeRunId null/pendingRequestCount0/hasPendingChildRuns false. It met hard22:28:50, missed target22:28:20 by22.038s. Parent context compaction delayed scheduled22:28:30 proactive cancellation; no cancellation was actually issued and this deviation is retained. Known own command PIDs remaining: []. Parent started22:21:05.508Z; actual parent native completion must be read by root after termination, never inferred from this artifact timestamp.

Next compile unit: verify existing writable APFS `EXTERNAL_VOLUME` (read-only inventory showed about434 GiB free) for isolated scratch/module caches and exact local dependency reuse without new download. No write/build on that volume was performed. Current active developer directory is CommandLineTools; `INSTALLED_XCODE_DEVELOPER_DIR` exists, but Xcode selection/build has not been tested. Complete full compilation/basic/tests first, then authorized native review UI via Cursor and independent real-host verification. Mobile remains original production owner's T0/device-window dependency. No commit/push/PR/release, no other agent/device/production changes.


## Run5 external preparation accepted only

[Executor report](build-preparation-r5.md) SHA256 `3cde7ff845c813e96ec9eb74a0d910f2c02c0e6bba4b01bfeaa3071c5ffce46a`. Seven task-owned directory write/fsync/read/hash probes and volume identity checks passed; local19pins/clean Git checkouts/submodule revisions/local commits verified. All8254 snapshot files,145334442bytes, independently read and compared by owner.164 command-log SHA checks matched. No product source changes: HEAD `ed4234b41764be8346ae58cdc63011c8f26a0f1e`, diff `11b3c4932766a8fdd6cfda1e243193c06afb1ce6b38c686baf94698ec27e8a83`, full846 manifest `de6b2fe41b205b259748fc91df8dea7189b1a2dc2c8fba4f0e8d232d875efc50` unchanged. Device UUID/absolute directory mapping and all raw evidence remain ignored `.local/voicecursor-research/`.

Data was below10GiB initially; daemon blocked and latest cleanup0 at22:37. Later fresh22:39 read showed daemon ok and Data above10GiB; this thread did not clean or change daemon. Final22:42:28 df free 11206709248bytes (10.437061GiB). No build started because remaining supervised expansion window after preparation was below3minutes. Source snapshots lack Git metadata/SwiftPM registration. Real offline initialization, compiler cache/temp/scratch placement, complete build/basic/tests/UI/host/Release remain NOT RUN. Help/file-copy success does not prove these.

Child `node:delegated-task:command%3Amcp%3A67541bea-8eb1-4d26-8f01-933833e33315%3Adelegate-task%3Avoice-editing-external-cache-20261008-r5` native22:36:11.439Z→22:41:54.220Z completed342.781s, activeRunId null/pending0/hasPendingChildRuns false. Target22:41:45 missed9.220s, hard22:42:15 met. Proactive cancellation requested around22:41:54 in completion race; durable completed retained, not falsely recorded interrupted. All known own command processes absent; owner audits returned exit0. Parentnative started22:34:50.880Z, final time left for root durable read.

Retained errors: wrong rule/workflow paths corrected; exact repository name match fixed; Git submodule directory handling fixed; wrong preliminary count corrected to8254. Two prepare-script resumes were distinct fixes, not build/disk cleanup retries. No Data deletion, global configuration, user-data/model/auth/permissions/paid changes; no UI/device/production-worktree edits or commit/push/PR/release.

Next executable unit: Fresh bounded Codex run: revalidate source and Data>=10GiB; create exact local Git working copies or task-specific mirrors from verified repositories with no network/global changes; prove real SwiftPM offline registration; then one complete build with external scratch/module caches/temp and unchanged live10GiB guard. Do not run current configuration draft before registration proof. Complete compile precedes Cursor native review/focus/privacy, then independent actual-host safety; mobile remains original-owner T0 and device reservation, manual return never passes T0. User overall authorization remains active; no new ordinary approval gate.

Owner final SDLC and git diff --check after documentation updates both exit0 at22:43:30Z. Logs and exact hashes in ignored run5-owner-checks.json. Parent native terminal remains externally observable only after this turn ends.


## Run6 精确本地 Git 依赖验收与空间阻塞

[执行报告](offline-registration-r6.md) SHA256 `58af8e3fd7d88ccd6679c24e6deddaee9a3ceb624c54ad398970012c08d6aea2`。19个实际 Git mirrors/working copies 含精确子模块通过 revision、metadata、clean 和源码比较。负责人独立读取19个 HEAD 与全部8254文件，并重新读取1426个原依赖 Git metadata，均一致；9项外盘探针及volume绑定复核通过，362条命令日志哈希无差异。原Git metadata canonical SHA256 `bf5967b0393dd394c7c0b61a14d316ad47281695e25ce5ee15b7e8a0a02c0185`。原依赖、Run5快照和产品源码没有修改。

HEAD `ed4234b41764be8346ae58cdc63011c8f26a0f1e`；tracked diff `11b3c4932766a8fdd6cfda1e243193c06afb1ce6b38c686baf94698ec27e8a83`；846个源/script/resource manifest `de6b2fe41b205b259748fc91df8dea7189b1a2dc2c8fba4f0e8d232d875efc50`前后未变。Package和lock未改。所有设备绝对路径/卷UUID、命令环境、原始日志、失败及哈希仅在ignored `.local/voicecursor-research/run6-offline/`及Run6-state.json。

最新22:57:46.895Z Data 10269753344bytes (9.564453GiB)，低于10737418240bytes；daemon blocked、last_cleanup_freed0、state age23.569s。没有用Run5旧恢复样本启动执行；未清理Data、改daemon/白名单、等待恢复或重试build。SwiftPM离线注册、compiler落点、完整build/basic/tests/Release均NOT RUN，不能把Git准备成功称SwiftPM ready。所有Git clone源是本机绝对路径，process GIT_ALLOW_PROTOCOL=file约束；未调用fetch/远程子模块update/download，无全机网络流量断言。

唯一child `node:delegated-task:command%3Amcp%3A67541bea-8eb1-4d26-8f01-933833e33315%3Adelegate-task%3Avoice-editing-offline-registration-20261008-r6` native22:51:56.717Z→22:56:54.385Z completed297.668s，activeRunId null/pending0/hasPendingfalse，目标57:15与hard57:45均达标，无需取消。同一ordinal1收到一次预算检查点steer，没有新轮。已知命令PID全部终止，owner审查命令已exit0。父native started22:50:25.816Z，终态只由根durable读，artifact写入时间不当terminal。

真实错误：首稿把MLX目录当作submodule名称，使用实际.gitmodules修复一次，原失败保留。早期大输出截断/JSON字段误读纠正，无凭猜测产品代码修改。Run5父native22:34:50.880→22:44:13.345Z562.465s已按根durable纠正；cancel/completion竞态仍记真实completed。

下一执行单元：Do not repeat registration/build while Data is below10GiB. After a fresh adequate-space window, reuse the existing exact task-owned Git mirrors/working copies; bind installed Swift tool version, configure isolated SwiftPM paths and task-local mirrors or validated local state, prove actual offline registration, then one full build with continuous10GiB guard and at least3 supervised minutes. No metadata rebuild, cleanup or threshold reduction. 完整build后才进入Cursor原生review/focus/privacy，再独立真实宿主安全验收；移动仍归原owner T0/预约，不以手动返回通过。整体授权继续，无普通阶段新待批；本轮无UI/宿主/设备/production edits/commit/push/PR/release。


## Run7 实际离线注册失败，外盘manifest产物部分验证

用户整体授权继续有效；无需重复普通阶段许可，实际验收仍未通过。[执行报告](swiftpm-result-r7.md)保留具体命令和错误。真实安装Swift6.2.3配置19个task-local映射通过；一次真实离线resolve于23:27:28.604691→23:27:43.800126Z exit1，实际Package.swift编译/链接输出后嵌套sandbox报`Operation not permitted`，不是产品源码错误。未改权限/transport或重试该错误。manifest输出路径和37个外盘产物由负责人独立读取哈希确认；产品scratch、Swift/Clang完整编译落点未通过。完整build/basic/swift test/UI/真实宿主/设备/Release均NOT RUN。

源码HEAD `ed4234b41764be8346ae58cdc63011c8f26a0f1e`、tracked binary diff `11b3c4932766a8fdd6cfda1e243193c06afb1ce6b38c686baf94698ec27e8a83`、846文件manifest `de6b2fe41b205b259748fc91df8dea7189b1a2dc2c8fba4f0e8d232d875efc50`均前后真实一致。负责人核对全部32日志SHA；32 command exit/ended完整且无已知自有PGID残留。原19Git与1426metadata沿用Run6验收，未重复8254扫描；不将无intentional writes当新全量metadata证明。

128个child磁盘样本最低10767134720bytes，未低于10GiB；owner23:29:27新样本10762665984bytes（10.023514GiB）。无清理、等待恢复、阈值降低、全局配置或原线/设备变化。quota unknown，Standard/default。

唯一child实际native23:25:22.406→23:29:06.424Z interrupted224.018s；比23:28:45截止超21.424s。负责人planned23:28:55取消未准点执行，23:29:06实际cancel后核验activeRunId null/pending0/hasPendingfalse。产物23:28:45不当native终态。父native started23:21:46.161；completedAt只留根durable读。所有详细派工和两次同ordinal监督反馈均在ignored.local文件。

下一步：下一有足够预算且fresh Data>=10GiB的单元，先诊断SwiftPM嵌套sandbox限制；本机help列有--disable-sandbox，可评估仅关闭内层SwiftPM sandbox且保留现有外层deny-network/file-only和相同权限的任务配置，不能声明已验证或绕过权限拒绝。成功后读取真实workspace全部19身份/revision，再保留至少3分钟做一次完整构建；不重建镜像/元数据。原生review/focus/privacy、真实宿主、签名Release与移动原owner T0/预约仍待实际验收。

Owner final SDLC/diff checks: sdlc exit0, diff exit0. Not product acceptance. Exact logs/hashes retained ignored run7-offline.


## Run8 容量阻塞，sandbox安全兼容性未证明

用户整体授权继续，无普通阶段重复待批。[子执行报告](sandbox-registration-r8.md) SHA256 `c3198dd874e5d15937ec6dd4bc4ad40c4b7d8e56008b9eedab12698a1462f1df`。child真实Data assertion10500861952bytes（9.779689789GiB），低于10GiB236556288bytes；durable失败事件updated23:38:19.944Z，实际measurement时间未保存，不能把事件/产物时间写成采样时间。owner稍后fresh样本高于floor不用于本轮重启。无清理/阈值降低/额外依赖下载/权限或transport修改。

Owner独立读匹配Swift6.2.3 Sandbox/ManifestLoader primary：原inner默认deny规则含文件写入/网络/其他操作限制；CLI flag不是安全证明。当前外层仅networkdeny。部署Applepatch与upstreamtagexact equivalence未证明；补偿profile/canary/livehelp/resolve/实际19workspace/fullbuild/basic/tests/UI/宿主/移动T0/Release均NOT RUN/unaccepted。原19Git及19CLI映射沿已验收事实保留，不重建8254/1426/362证据。

846 actualsourcehashes前后全部一致；HEAD `ed4234b41764be8346ae58cdc63011c8f26a0f1e`，trackedbinarydiff `11b3c4932766a8fdd6cfda1e243193c06afb1ce6b38c686baf94698ec27e8a83`，manifest `de6b2fe41b205b259748fc91df8dea7189b1a2dc2c8fba4f0e8d232d875efc50`。child没有自建PGID/longcommand/yieldedexecsession或递归任务；native已completed23:37:11.877→23:40:01.532（169.655s），activeRunId null/pending0/hasPendingfalse，未需cancel且截止通过。父native started23:35:59.034，终态留根durable读，artifact时间不当终态。

偏差保留：guard assert后的预备工具组仍读一次instruction及打开两primary源，违反立即停止后不做新metadata要求；没有config/canary/compile/resolve或外盘写入。子初始两个大输出截断，未完整保存逐命令stdout，不能称完整日志验收。owner一次runLimit0参数错误已改1；初始catalog显示过大；dispatch70.127s未达60saim。所有实际失败和来源文件留ignored.local。

下一可执行单元：本轮关闭，不因稍后空间回升重试。下个独立有界已授权单元先fresh Data>=10GiB；guard先持久化时间/bytes并立即退出，禁止assert后的同一shell/并行工具组继续metadata/source请求。复用19Git和19mirror mappings；从匹配6.2.3 primary和installedhelp核对innerdefault/cache权限，证明任务自有补偿profile保留网络/写入及其他限制，task canary全部通过才一次resolve；读取实际19workspace revision后再安排至少3分钟完整构建。未证明安全则blocked，不切权限/proxy/transport。

Owner final checks: sdlc exit0, diff exit0. Only documentation/diff validation, no product acceptance. Exact logs/hashes retained ignored run8-sandbox.


## Run9 可验证边界单元通过，注册context阻塞

整体授权有效，与实际验收分开。[执行报告](offline-unit-r9.md) SHA256 `47e30aff8db68d8ee6c1cbe0caf50edb80d1a673a4e0bc091f4d7d3e2ecaff4b`。实际Swift6.2.3/help/卷匹配通过；29child容量样本最低11344375808bytes均>=10GiB，未清理/等待/降阈值。默认profile及注册outerprofile批准写入通过，目录外写入/loopbacknetwork/POSIXsharedmemory均EPERM；这是这些操作的实测，不是exhaustiveprofile审核。narrowprofile nested true exit0；registrationprofile+taskenvironment nested true exit71，实际sandbox_apply Operationnotpermitted。inner未禁用；实际resolve0次，19workspace/fullbuild/basic/tests/UI/宿主/移动T0/Release均NOT RUN。无一般OS拒绝、T3approval rejection或需要扩权的结论。

Owner独立核对10日志SHA、两个profile/脚本及已知PGIDs终态无残留；846源码前后重新读取一致，HEAD `ed4234b41764be8346ae58cdc63011c8f26a0f1e`、binarydiff `11b3c4932766a8fdd6cfda1e243193c06afb1ce6b38c686baf94698ec27e8a83`、manifest `de6b2fe41b205b259748fc91df8dea7189b1a2dc2c8fba4f0e8d232d875efc50`。外盘只写2个taskcachecanary文件，19Git/mirror与原source/lock/production/device/globalauthconfig未改。

Child native01:26:52.827→01:32:42.215 completed349.388s；activeRunId null/pending0/hasPendingfalse，hard33:00通过，target32:10超32.215s。planned32:20取消未执行；负责人较晚状态核对发现已completed，不能记准时取消/interrupted。父native started01:24:59.291，结束仅根durable读取，不拿产物时间充当terminal。初始规则/路径读取耗时和旧helper路径猜错保留；不重扫8254/1426/362旧证据。

精确剩余：本次同因纠错单元2/2已用，不自动Run10或重复泛泛审计。精确剩余条件：隔离同一机器上narrowprofile nested exit0与registrationprofile+taskenvironment nested exit71的具体差异，捕获installedSwiftPM实际manifest sandbox argv/环境；保持原inner保护与网络/文件限制，不改权限/proxy/transport。证明支持的完整context后才一个真实offline resolve、读实际19pins，再足够监督预算fullbuild；本轮不重试。现有移动原owner T0/预约、原生review/focus/privacy/真实宿主/Release目标保留，未验收。

Owner finalSDLC/diff: sdlc exit0, diff exit0. These checks do not prove build/registration/product acceptance. Exactlogs retained ignored run9-offline.


## Run10 finite diagnosis and fresh missing cache precondition

[Owner report](context-build-r10.md). Four real cells: narrow baseline/task both0; registration baseline/task both71. Profile correlation only; exact rule/SwiftPM context unproven. Fresh Data~85.94GiB; external volume valid but Run5/Run6 task roots absent. Original19 checkout revisions and clean status pass, not fresh complete submodule/content registration proof. All846 source hashes unchanged and6loghashes match; known own PGIDs absent. No resolve/build/basic/tests/UI/host/Release/mobile validation. One child interrupted31:46.726→35:24.619217.893s; activeRun null/pending0/hasPendingfalse, hardmet but targetmiss14.619s and plannedcancel about9s late. Parent starts00:27:30.405; nativecompletion leftnull untilrootdurable. Initial read-only guard correction and final failed metadata command retained. No source/production/device/globalconfig changes. Overall authorization remains, no ordinary permission gate.

Owner final SDLC and diff checks both exit0 at00:36:43Z; documentation/diff checks only. Logs and hashes retained in run10-context/owner-final-checks.json; all commands reaped.


## Run11 exact rule/context evidence, execution boundary unresolved

[Executor report](rule-context-r11.md). Owner accepted20loghashes/846unchangedsource,9namedprobes and installeddebug-generatedinnerargv/profile. Different-policy reapplication fails evenwithallinnerwritegrantsremoved; actualkernel/individualpathcauseunproven. Currentouter file/network/shm canary passes testedops only;2actualmanifestdiagnostics exit1, resolve0, fullbuild/basic/tests/UI/host/mobile/Release NOTRUN. Onechildcompleted41:28.651→47:26.860358.209s, active/pending0/hasPendingfalse; target/hardmet/no cancellation needed.485capacities min92222947328bytes. No depsreused/copies/external scaffolds or source/permission/globalconfig changes. Parentnative40:17.030, actualterminalrootdurableonly. Raw/state and rootpersistentresult preserve chronology/errors. Next bounded samepolicy+directory/protection compatibility must pass beforeoffline registration/fullcompile; noautonomousRun12.


## Run12 incomplete, no new technical execution

Owner source846 hashes unchanged. Recovery/reads delayed child dispatch383.394s. Child interrupted13:16:55.529→13:18:37.779102.250s; active/pending0/hasPendingfalse, hardmiss7.779s, plannedcancel approximately22s late. No compatibility/canary/manifest/resolve/build/test/UI/device/Release result; failed final preflight retained in durable/raw. Old coordinator checkout/handoff absent; current ignored worktree result retained. Parent nativeordinal16 started13:10:32.135, terminal root durable only. No product changes or autonomous following run.


## Run13 bounded protected rootmanifest PASS

[Report](manifest-compat-r13.md). Realexit0/parsedOpenType41targets owner independently matched native log. Network/file/shm canaries pass testedops; inner retained;10loghashes/846source unchanged. Fullresolve/build/tests/UI/host/mobile/Release NOTRUN. Childcompleted34:38.466; targetmiss28.466s/hardmet, plannedcancel34:20missed. Actualparentterminalrootdurable only.

## Completion execution checkpoint — 2026-10-14

旧轮次证据保留，当前取消10分钟cap不追溯改写历史超时。父started2026-10-14T01:40:10.032Z；实际terminal仍待durable观察。开始HEAD ed4234b41764be8346ae58cdc63011c8f26a0f1e、846源manifest de6b2fe41b205b259748fc91df8dea7189b1a2dc2c8fba4f0e8d232d875efc50；当前runtime源码继续变化，旧hash不证明新候选。

真实offline resolve第一次exit1来自MLX子模块URL前缀映射；task-only映射纠正后本地子模块注册通过，第二次exit1来自yyjson tools5.0旧native sandbox与外层two-write-path不同，sandbox_apply EPERM。原依赖/manifest/lock未改，未关闭保护或扩大写入。完整build/basic/tests尚未通过。具体日志/hash/raw命令在ignored completion目录，尚非产品闭环。

Cursor首任务native01:49:52.803Z→01:51:38.237Z failed，公开错误Provider turn failed，activeRun null/pending0，无UI产物。原配置重试1已经开始01:59:41.586Z并实际读源码；仍待真实终态/原生交互验收。typedrestoreAPI已经写入同一Session/output链，源审查不是行为测试。

根/移动owner确认iPad不可用：不查询/预约/安装/启动设备。原生产Debug Info.plist和旧build目录缺失，旧包hash无效；T0与真机结果仍未验证。origin/main实测f0ef2aa88296da017e29ced2b7bc9271af96e4fb，比研究HEAD多10commits，最终普通merge后重新验证。未commit/push/PR/release。

### History interpretation correction

移动owner指出并现场复核：HEAD/main实际分叉6/10，merge-base c383b25d27d652e8da8fe58f594578b1bb603e5a。早先“只落后10commits/main删除移动代码”的判断错误，已撤回；三点main diff不含Mobile/Bridge/iOS/Package修改。实际共享冲突是SessionJobControl.stop移除与移动duration timer调用，交共享runtime owner给精确支持API。保留历史源代码，无merge/reset/rebase/force操作。

### Explicit build-boundary decision

用户对具体提案回答“允许此构建隔离调整”。仅本任务构建移除自建外层sandbox，保留SwiftPM原生sandbox、准确本地固定依赖、禁止下载和10GiB保护；不改系统权限/认证/全局配置。旧受保护resolve失败事实不改写，后续真实完整build结果另记。

### Native UI child partial retained

Cursor retry taskcompleted，hasPendingfalse、activeRunnull/pending0；最新durable startedAt02:15:00.021Z、completedAt02:22:08.271Z，同ordinal首次观察started01:59:41.586Z，steer后started字段变化，不虚构单一elapsed或旧10分钟合规。源码审阅/恢复面板与双语文案已落盘，isolated swiftc render fixture25pass/0fail/1unverified（VoiceOver），imports stripped且非full product/hostproof。

未验收：handoff前未完整重读ANTI、无真实TextEdit焦点/非keypanelEscape、VoiceOver/增强对比/减少透明、完整产品构建。远程before-upload披露视图与PresentationContext正式回调仍待runtimeAPI，临时downcast未移除。后续只完成这些具体集成和真实native/host审计，不派第三次泛泛HTML审计。当前接受范围仅partial source/render retained，不是功能完成。

### Actual local dependency registration milestone

用户允许边界调整后，真实SwiftPM resolve02:29:38.181Z→02:29:50.386Z exit0、processGroupEndedtrue、无stopReason。logSHA256 e1c9755106ee6e7b0e203913591c6ddc461c135cc0c7c0737febe72efb2b3244。自建外层未启用，原生manifest sandbox仍启用；使用原19pins/localfilemirrors，禁netrc/keychain/update/prefetch/prebuilts，禁止下载。完整编译/basic/test仍待真实结果，不以resolve代替。

PortableSelectionEditRecipe已实际移动共享prompt/instruction/options/normalization，Native和mobile消费同一逻辑；旧ModeServices.edit forwarding未注册建议撤回。当前sharedAPIhashpacket仅SessionControl一处与正在修订源码不一致，尚未向mobile导入旧packet；source review不是build验收。新Cursor具体nativeintegration task仅接remote披露/正式Context回调/live语言和完整审计，不泛泛HTML审计。


### Current 2026-10-14 candidate gates

Actual whole SwiftPM build passed under the user-authorized outer-wrapper adjustment with native sandboxes retained. The intermediate selected-retention build and root suite passed1174XCTest/18skipped/0failure plus1SwiftTesting. These unmerged results do not validate later Models/UI/mobile/main changes or packaged runtime. Build artifacts are now preserved immediately by the execution wrapper; the earlier delayed raw binary copy failed source/binary binding and is explicitly rejected.

Cursor native-integration task completed03:31:02.170Z, no active run/pending child work. Required6PresentationContext callbacks and before-upload disclosure are wired, downcast removed, live-language update implemented.49isolated native-fixture checks passed,3unverified: real non-key Escape, VoiceOver, and contrast/transparency/material over actual content. Compiled-bundle, hold-mode Session/host, TextEdit/browser and actual delivery/restoration remain pending. Source manifest and audits are retained in ignored UI integration evidence.

Original mobile owner's precise checkpoint retains39realBridgeXCTest/16offlineT0/16proxy-stub passes and the latest unsignediOS build-for-testing success; formal and compiled probe sources differ only the temporary Plist, which was restored. These are local compile/logic evidence only. Shared import is held until exact API packet review; MobileJob/UI are not wired. User device constraint remains no query/reservation/install/launch and physical T0 is deferred.

The mobile current complete suite failed:1150XCTest,18skipped,1failure plus1SwiftTesting pass. ConfuciusModelDownloader emitted finalprogress96instead103 while the103byte URLProtocol fixture assembled correctly. Earlier mobile1148green and desktop1174green do not override this current failure. A bounded two-file Models owner correction and deterministic progress check are assigned to the current runtime/build executor, with final candidate suite rerun required. No real model download, device actions, production acceptance, commit or PR has occurred.


### Settled owned build and independent API review

Codex owned build task native completed04:00:27.967Z after01:45:34.534Z start; no active run/pending work. Actual fullbuild/basic/SDLC passed on retained unmerged HEAD; full root suite1175XCTest cases,18skipped,zero failures plus1SwiftTesting pass after Models correction. Parent checked raw log hashes and immediate preserved artifact files. This does not resolve originalmobile redcandidate without import/retest or validate finalmerged/package/host. Task terminal summary included an incomplete trailing sentence; the prior complete result and persistent build report/command records supply actual evidence, not that fragment.

Independent API reviewer native completed03:59:32.947Z, binding stable, no source changes. Complete mobile import was refused. API-01: empty final_text or Action-only JSON can reach a nonempty candidate through metadata text fallback; explicitApply remains required, so this is not observed automatic deletion. API-02: the3hash-bound small patches are building blocks and omit requiredreview/control/typedrestore interfaces; keyboard effect patch also assumes an intermediate receipt baseline. Current import remains held. One scoped corrective task covers strict selection behavior through actualgenerator and upstreamremote response normalization, local controlled regressions, and a complete exact portable base-to-result patch. Ordinarydictation/command behavior is preserved and no live download/remote request is authorized.


### Exact typed-output correction and complete r3 import acceptance

The independent R2 review accepted the complete 38-path shared scope but rejected typed-block fallback. The final scoped correction changes exactly two production lines, retaining typed JSON before final parsing and preventing strict ambiguous fallback at every recursive object. Expanded existing fixtures ran red first, 11 tests/93 assertion failures. After correction actual 125 focused tests passed; whole real SwiftPM build/basic/SDLC/diff passed; whole root suite1182 XCTest,18 skipped,0 failures plus1 Swift Testing passed. Exact source aggregate `75db8c7886a508bfd951356e2c1f19f7263ba375dcdd92f81a6163e53dae7516`. Native child completed04:47:42.724–05:00:27.504Z, no active/pending child. Old ten-minute cap remains superseded. Same-cause correction2/2 ends here.

Parent independently verified869 current/preserved source files,31 preserved binaries/resources, eight command/log hash pairs, real index integrity and isolated base-to-result apply for shared38/Models2. Complete r3 packet SHA256 `35be2da32bf4baca1277ac30fa0ed5bd86cb81bec667439cfb0d99e25b7d0627`; shared patch `a38f07e1100b7e6b5c57949b404392f3246f79ef4c7c375c6c20a27af3088071`. Models patch bytes are unchanged. Parent technical acknowledgement authorizes exact mechanical import to the existing mobile owner under user overall authorization. It is not human spec/UI approval or product acceptance. Prior r1/r2 shared packets are superseded.

Original owner ordinal29 is active in its own workspace. Same MobileJob/real bridge/keyboard review, explicitApply/Cancel, full native readback acknowledgement and typed once-restore remain its owned integration/export. Formal T0 source/config binding and mobile current full-suite rerun remain required. Device query/reservation/install/launch remain forbidden; physical acceptance deferred. Final main/mobile candidate, Release Metal/signature and real host/privacy/accessibility are not yet passed. Full raw witness, failures and exact device paths stay in ignored completion evidence.


### Normal main merge and preliminary signed Release candidate

Normal merge remains pending commit, HEAD `ed4234b41764be8346ae58cdc63011c8f26a0f1e`, MERGE_HEAD/current origin-main `f0ef2aa88296da017e29ced2b7bc9271af96e4fb`; no unmerged index entries. Scoped reversible checkpoint retains original index,100 owned dirty paths and ignored evidence. Three actual overlaps, bilingual localization and VoiceSessionJob+Capture, were reconciled with three-way comparison. No reset/rebase/force or original mobile worktree copy.

Real xcodebuild Release/OpenType/arm64 compiled and assembled existing pipeline, Metal and41-file app. Explicit existing Apple Development signature, hardened runtime, ownedresources/helper and verify-release-artifact passed. Canonical app file-map hash `a734ceb8e3a70866c4d29dc5adbae7b8a4621be2b613566a46856bc7b02b6eee`; Metal hash `0214ad23cc2fa1df961eb7e2118881bd4b2bdb0183546ef537fff1a2a61e2ada`. Not DeveloperID/notarized/distribution or DMG proof. Only executor-owned tracked edit extends existing build-app.sh with optional task cache/derived-data/dist paths; no second pipeline.

Source aggregate `6f4040fd8a58ced9b0747b239291237d2aab11d6d384a8b229057878e82d9558`,880 code paths. Complete SwiftPM build and root1216 XCTest/18skips/0failure+1SwiftTesting, basic/SDLC/bothdiffchecks passed. Parent verified1349 source-state entries including3 deliberate deletions, actual source archive/currentfile hashes,41 appfile hashes,24 command/log hashes and precise pendingmerge. Parent checker metadata assumptions failed on deleted entries, canonical-versus-file JSON digest and empty missing-list type; these validation errors are retained and corrected without product changes.

Xcode emitted an error-like UtterModels diagnostic whose referenced command exited0 with no further output; actual pipeline exit0 and preserved app/resources/signature/fullnativechecks passed. Cause unresolved and raw bytes retained, no speculative sourcefix/buildretry. First executor closure audit failed on raw nonUTF8trace; decode-for-display correction passed, original log/hash retained. Native task05:10:24.011–05:33:06.578Z completed, no active/pending child, all owned commands ended. Lowest Data29.365GiB. Local19pins/native sandbox/no dependency downloads retained.

This is preliminary compile/package proof, not final mobile candidate or real host/UI/capture/privacy/accessibility acceptance. Original mobile owner has now imported accurate sharedr3; its complete owneddelta remains in progress. Devices remain no query/reservation/install/launch. Current SDLC prose updated after the preserved preliminary manifest; product code/package unchanged. Latest user directs results to this thread only; no further root notifications.


### Independent native verifier refuses acceptance with concrete regressions

Verifier native05:43:06.110–06:14:37.688Z completed, no active/pending;13 command/log hash pairs checked. GenuineSwiftPM owner modules/resources compiled; only4 new scoped regression/test-helper files added. Finalfocused4cases have2failures/10assertions; complete current1220 XCTest/18skips/2failedcases plus1SwiftTesting. Prior1216cases have no failedcase, but oldergreen cannotclearnewsecurity failures. Source880 preliminarypaths unchanged byverifier.

NH01: realTextDeliveryTransaction withcontrolledtarget/directwriteadapter accepts when secureinputtruebeforeorafterprepare. AXdirect branch andintegrityre-read lackfreshguard. Noactualexternal/privatewriteperformed. NH02: actualnativeMac target refusal underactualsecureinput is suppressed byfactorytry?; actualDriver/Factory sendsone controlledscreen request/generation/output andhistory. NoactualOCR/network/hostwrite. Parentreviewconfirms bothrootlocations; scopedNativeMac/NativeSessionownerfix assigned, keeprealredtests untilpass. Ordinaryvalid/unselected/integration/explicitcopy policies muststillbechecked. Sharedportable38/API/Models/UI remain separate.

NH03: whole test emitted Contacts persistenceXPC/CoreData connection4097exception. No successfulContactscontentread/mutationproven; injectionalone doesn'tprovehardprivate-store isolation. NoContactsdatabaseinspected orpermissionrequested. Separate task-onlytest-runtime restriction diagnosis usesfrozencompiledartifacts/read-onlyproduct, avoidingincompatibleouterSwiftPMBUILDwrapper. Complete native suitepaused until actualruntimeboundarycanaries andnarrowcompatibilityverified; originalnativeBUILDsandbox retained.

RealSwiftPM nativecomponent reviewrender/Apply/Cancel processlocalNSEventdispatch passed on controlledtarget/output, actualexternaldeliveryblocked. Fourlight/darkownedreviewframes,904UTF16fulloriginal, unchangedgeneralclipboardchangeCount. ExternalAX/systempointer/Escape/VO/contrast/long-scrollend/narrow/actualnativeRestore remainnotrun/blocked. Parentviewedlight/darkframes; revisedcandidateisbelowlongoriginalinouterScrollView initially, notprovenunreachable. Concrete follow-upafterruntimefreeze required; no third genericHTMLaudit.

Userreportedordinaryinput; nonpromptfreshprobe stillsecureInputtrue, AXtrusted, mic/SpeechnotDetermined. Read-onlyOSmetadataidentifies loginwindowascurrentSecureInputowner. UserMacminidesktopunlockclarificationpending; noagentSecureInput/TCC/OS/authchanges. Devicesstillnoquery/reserve/install/launch. Userresultsdirectonly, no rootreports. Both fix/isolationtasksboundedStandardSolXhigh, distinctfileowners/nochildrecursion; no commit/PR orproductionacceptance.

User explicitly confirmed temporarily unable to unlock this Mac mini. Actualexternalhost acceptance is deferred/notpassed; no further unlock request or authentication/SecureInput/TCC change. Authorizedlocalfix/integration/build/review andPR continue, with exact remaininghost/device gates in the review record.


## Combined Draft PR checkpoint, 2026-10-14

The user explicitly changed delivery ordering: publish the combined Draft after exact mobile import and writer settlement, disclose current failures, and continue fixes on the same PR. This is PR creation authorization, not human verification, merge, signing, or production approval. Historical round limits and old green results remain historical.

The runtime child completed natively at 07:35:29.300Z after starting at 06:58:28.476Z. It has no active run, pending request, or pending child run. Parent reread 888 source hashes, 8,940 frozen product files, 23 build-context files, all 34 command records and logs, and all 33 ended PGIDs. The complete real SwiftPM bundle and its resource context match. The retained private-runtime profile passed nine named-boundary canaries. One actual Configuration XCTest and one fixture isolation XCTest passed. Of 70 actual focused XCTest cases, 37 passed and 33 failed before behavior assertions because VoiceWorkflowFixture used the system temporary directory. Swift Testing failed to load twice, executed zero cases, and exhausted this unit's loader retry limit. Full suite readiness is false. No private store contents, real host text, authentication, or devices were inspected.

NH01 and NH02 corrections preserve secure-input admission before AX reads and effects, and propagate local target capture refusal before command processing. Their earlier 70 focused passes are a different execution context; they do not replace the current guarded failures. Remaining work includes the confirmed fixture path, a proven SDK loader context, complete guarded tests, and concrete native review scroll, narrow-height, accessibility, and interaction checks.

Parent imported exactly the independently reviewed mobile owned r3 whitelist: 38 frozen paths, packet SHA256 `6c8b195d4621534639929591d0dcfaa196bf4941ba7d234225b97c2ed4d11841`, patch SHA256 `30059d485a53a50b49a6aa8052af1bba9ebeb9fb9752273b68519d3181b459b0`. All current base, frozen source, isolated applied, and resulting hashes match; 1,340 other repository files and the real index stayed unchanged. Shared r3 and Models2 were not reapplied. Original dirty PiP, layout, scene-return experiments, privacy, icons, Plist, and other unrelated increments were not copied.

The mobile owner's 51 bridge XCTest, 24 selected-method, 15 lifecycle, and 16 native writer checks, independent source review, and unsigned formal-Plist Debug compiler result apply to the pre-integration owned increment. The prior desktop 1,216 XCTest with 18 skips and zero failures, one Swift Testing case, and Apple Development signed Release-style package apply to an earlier source. None validates this combined Draft source. Final combined basic, whole tests, Release-style packaging, and iOS compiler checks are pending. Local SDLC and diff checks are recorded separately and do not certify product behavior.

Actual external macOS host, microphone, recognition, focus, and restoration remain deferred because this Mac mini cannot be unlocked. Physical iPhone/iPad actions remain prohibited by the current device constraint. Mobile formal cold activation still requires manual host return; automatic return and T0 are not passed. Real native UI, VoiceOver, privacy broker coverage, distribution signing, notarization, human verification, protected merge, and production acceptance remain open. The PR stays Draft. Rollback disables selected editing and retires pending proposals and output authority without changing ordinary dictation or stored user data.

Detailed local evidence is retained in ignored completion-20261014/complete-test-runtime and mobile-owned-controlled-import. The public review record intentionally omits device paths and credentials. PR creation will record its URL and exact pushed head in the local combined-pr-result files; PR121 remains untouched.

Draft source binding covers 949 tracked source, test, resource, iOS, and build-script paths, plus Package.swift and Package.resolved. Sorted compact JSON of path-to-SHA256 values is `15551622b259cef2077ae2b39c4d1949f96cb332c966fbe28850b18c670c32f0`. Device paths and the full manifest remain ignored. SDLC passed; staged diff check initially found two whitespace issues, which were corrected without changing behavior, then passed. This draft candidate has no new combined full build or full suite result.


## PR124 fixture and CI crash correction

Draft PR [124](https://github.com/IchenDEV/utter/pull/124) was published at `de895347d5fe4671db90f6c7aa4d3bbe9cb9b1d2`. That exact CI head passed SDLC, basic checks, compilation, the Release-style App Build job, and one Swift Testing case. XCTest aborted after 1,149 passing and 18 skipped cases because the native evidence helper force-unwrapped an absent environment variable. No completed full XCTest suite result exists for that run; SDLC Gate correctly failed its dependency aggregation. Its enforcement remains unchanged.

The next child corrected four test-only files. VoiceWorkflowFixture and the shared PersonalDictionary now use the existing task fixture root. NativeE2EUI uses an optional explicit evidence path, otherwise a unique owned directory, creates logs/screenshots, and throws real IO failures. The regression exercises actual constructors, persistence, missing and explicit overrides, and failed directory IO. It adds no skip or expected failure and changes no production UI, Session, MacServices, package, dependency, mobile source, or workflow.

A fresh complete real SwiftPM test bundle compiled with native build protection and the same private-runtime profile. Final exact canaries passed 9/9, the isolation case passed 1/1 without the evidence override, and the original focused set passed 70/70 with zero skips, including all four SecureSession cases. The first epoch retained a 69/70 result caused by missing evidence/logs; the original 33 system-temporary-directory failures and CI crash remain preserved. Parent independently matched 906 source paths, 8,976 complete frozen product files, 23 build-context files, and all 27 command log hashes. All 27 own PGIDs and the native child ended. Native start was 07:58:41.047Z, completion 08:21:54.864Z; the user had removed the old native time cap. Minimum Data free space was 14.29 GiB, above the unchanged 10 GiB floor.

The final local source witness is `5e112f73ceb81242cf6f6217fbd77458c8cc4fcc0a91a6b75caf7c17f4dbbec9`. Complete frozen product tree is `e507f9870e5ad2afad7be8aeb41b0cfa53299b2ecd5f86e28c5b795fb881bfaa`. Full manifest, delta, literal behavior checks, logs, loader census, and parent acceptance are retained in ignored pr-fixture-fix evidence. The requested delta and terminal records were embedded in result.json; parent read them and extracted a separate review copy.

Full local suite and native window events were not run. Local Swift Testing was not retried: its two-attempt budget remains exhausted. Read-only SDK closure evidence and GitHub's one actual Swift Testing pass are distinct from local dynamic-loader proof. Other temporary-directory consumers, complete privacy broker coverage, native UI scroll/narrow/accessibility, actual external host, physical mobile T0, final iOS compilation and distribution acceptance remain open. This correction requires a new CI head; earlier green checks are not transferred to it.


## Current Codex native UX verification, 2026-10-16

The user authorizes current Codex execution, safe deletion of proven regenerable caches, and updating PR124 while preserving the existing UX. This supersedes the old T3/capacity follow-up blocker; it grants no human acceptance. No product source, Session/output owner, mobile source, dependency, permission, workflow enforcement or signing configuration changed in this increment.

Only two ignored, unopened SwiftPM-generated cache directories were removed after tag/ignore/open-file/frozen-root checks. Their prior allocated size was about175MiB. Data was already above10GiB at this turn's first sample; this cleanup did not recover10GiB. Current available space is about11.2GiB. Source,19 dependency checkouts, models, user data, Agent storage, archives and all verification evidence remain. Every complete build and test used the retained10GiB capacity guard and local-only dependencies; mutable products/module/temp caches stayed on the verified task-owned external volume.

| Check | Exact local result | Scope |
|---|---|---|
| Whole real SwiftPM build-tests | Passed | Native SwiftPM sandbox, real resources/modules,19 pinned local dependencies, no resource shim |
| Basic and SDLC | Passed | Actual repository scripts; isolated SwiftPM paths |
| Runtime canaries |9/9 passed | Same retained private-runtime policy; only the named tested boundaries |
| New native review tests |6/6 passed,0 skipped | Real production views, AX labels/content order/actions, expired/repeated Apply, one-use Restore, failure notice/Close, process-local Escape and no Return default |
| Original output/security/session set |71/71 passed,0 skipped |70 real owner tests plus the compiled Session/native pointer Apply/Cancel test; controlled target/output adapters |
| Native visual inspection |44 native PNGs inspected |36 scroll captures across280/320/420points × English/Chinese × light/dark;4 result/notice captures;4 actual composed-panel captures |

Working-tree source manifest: `a763c64af43c95c62dda84ecc4cb4b6b944fc9b7fddd0217c7f39151be22ae66`. Complete8,984-file frozen product manifest aggregate: `29092913b3777787385ea23859a65f494eb8c42532a3fdde71707ad2861c4267`. Full file maps, exact commands/environments, timestamps, log hashes and volume mappings remain ignored. The final source bytes include the two new native test files; the product source bytes match the prior72dc402 head.

First failures remain retained. The test host needed the public AppKit finishLaunching lifecycle and a bounded own-PID AX query before SwiftUI exposed virtual descendants. Public navigation children require an untyped NSArray bridge because a scroller part does not match Swift's imported concrete array type. Independent review found missing-selector false negatives, stale proxy presses, factory cleanup and process-policy leakage; the final test boundary throws for missing state/action methods, reacquires controls, closes failed factories and performs no activation-policy write. It records navigation provenance and checks the messaging-timeout setter. No permission prompt or external AX target is involved. Only an actual apiDisabled query may skip an AX-dependent test; the accepted local run had no skips.

Long-text acceptance uses the public NSView.scroll method on the actual native scroll document, observes real clip-position changes/return-to-start, and pairs end geometry with inspected original/candidate marker glyphs. Failed CGEvent wheel injection remained windowNumber0 and produced no movement. Native scroller diagnostic calls also did not establish scrolling. These are not accepted physical-wheel or VoiceOver-scroll proof. Component captures include the native window background so a transparent view-cache image is not misread as black-on-black product UI. The real composed-panel light/dark captures were separately inspected.

The complete1,599-line ANTI_SLOP file was reread before handoff; all157 headings have an explicit scoped audit. No new visual design was introduced. Content, gutters, footer containment, full endpoint glyphs, localized controls and notice readability passed within the recorded native render/action scope. Actual desktop-backdrop translucency, physical pointer/wheel input, real VoiceOver speech/cursor/scrolling, external-host focus/voice/delivery, physical mobile T0, full privacy-broker coverage and distribution acceptance remain unverified. No unlocked-host or device operation was attempted.

All46 pre-push command records/log hashes were independently matched; every executed command group ended. One existing native Codex reviewer completed two read-only boundary reviews without T3; findings were closed by the parent against the final source/results. This is technical evidence, not independent human or protected production approval. The exhausted local SwiftTesting-loader attempt limit was unchanged; no local full suite or new Release package was run. New-head GitHub full tests/packaging are a separate gate after push. Earlier72dc402 CI green is historical and is not transferred to a new head. PR124 remains Draft.

Detailed evidence: ignored `.local/voicecursor-research/codex-native-ux-20261016/` contains cleanup, final-result, command-integrity, image-manifest, the157-point audit, reviews, raw first failures, and the sealed iteration7 product/runtime evidence. The existing rollback and real-host/mobile/signing gates remain in force. Current Codex reports directly to the user; no T3 watcher, timer or coordinator notification was created.
