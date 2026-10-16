# Plan: 后续 build and ship 候选工作流

**Status:** draft
**Approved-by:** —
**Approved-date:** —
**Upstream:** [spec](spec.md)

**Authorization:** 用户整体授权，2026-10-08；普通阶段可继续，未声称用户已审阅本方案。实际验收仍待完成。

## Current delivery plan — 2026-10-14

用户最新明确要求取消时间上限、完成整体功能后提交 PR。旧轮次截止和原型计划以下作为历史证据保留，不是当前执行限制；普通阶段已整体授权，实际通过仍须证据。

1. Codex runtime/build owner独占Contracts/Session/MacServices/AppState与行为测试，闭合一次候选确认/取消、精确receipt恢复、失效/误识别/网络/uncertain及普通听写隐私保护。真实19pinned本地依赖注册、完整SwiftPM/basic/tests；不削弱sandbox或网络/10GiB保护。
2. Cursor独占原生Presentation与双语文案，消费同一Session和typedrestoreAPI；先紧凑交互契约，再真实原生渲染/点击/完整ANTI审计，HTML历史原型不作为产品验收。
3. 原移动owner独占平台glue和per-sceneT0，审阅精确共享API/hash后受控集成。用户确认iPad暂不可用：目前仅本地开发，不查询/预约/安装/启动设备；真机验收延后。根协调者维护设备窗口。
4. 当前HEAD/main分叉6/10，研究侧六提交引入移动代码；两端快照删除形状不代表main删除已集成移动代码。共享API存在SessionJobControl.stop移除冲突。各writer结束后由负责人普通merge并逐项协调冲突，不reset/rebase/force、不复制原工作树。所有完整检查重新绑定整合后的源码与包哈希。
5. 完整构建后独立验收TextEdit和浏览器选区语音编辑、Cancel零写入、一次Apply/恢复、stale/Unicode/剪贴板/失焦/uncertain/模型失败、真实录音与既有权限/隐私。签名与MetalRelease风格构建单独验收，不能以compile通过替代。
6. 合格候选正常commit/push/PR，立即link_pull_request，核对remoteSHA与linkedPR。CI以watch_pull_request原生事件监控；交回用户前unwatch。不以当前整体授权声称未验证版本可发布。

当前父执行无旧10分钟cap，所有自有命令仍有独立timeout/PGID/floor保护，任务持续监督到真实终态。具体taskId与命令证据见ignored completion-state及workflow。


1. 本线程刷新 HEAD/原线 durable 状态，纠正实际 native 时间；只读原工作区，协调移动 T0/设备与单一集成 owner。
2. Cursor Sonnet 5.5 / 300K / High 独占 HTML 交互原型与设计说明，本线程渲染、点击并验收；无 Fast/1M/层层委派。
3. Codex GPT-6.1 Sol / Xhigh / Standard 在既有 owner 内先补明确选区 receipt：originalSelection/replacement/resulting anchor，确认后保留，既有 anchored output 一次恢复。此增量不冒充完整审阅流程已可用。
4. 后续将 pending proposal 接入现有 Session 生命周期与 PresentationContracts；Cursor 实现 native 审阅 UI。精确原宿主焦点返回需证明，不绕过 lease。独立验收者与实现者分离。
5. 对实际 diff 执行 SDLC/basic/swift 检查及 Release 风格构建；真实 TextEdit/浏览器验证 spec 各失败保护。留 UI 前后截图、失败、权限隐私和确切源码/包哈希；有界命令，到时 native 取消并核验终态。
6. 原生产负责人归属核对后受控整合增量，再按集成 SHA/包哈希重验；不复制/提交其未提交工作。
7. 移动先闭合 T0 自动返回、焦点、完整上屏与生命周期，然后预约 iPad 并独立验证 iPhone/键盘选区边界；移动不删除 scope。
8. Release owner 准备配置签名、适用 notarization、权限/隐私、Archive/export/checksum/提交材料；独立验收确切候选后正常 commit/push/PR/既有发布，不 force/reset/rebase/代签法务。PR 立即 link_pull_request，watch_pull_request 后结束轮次。

依赖、负责人、产物、验收与状态见 workflow.json。尚未通过的 native UI、焦点返回、真实宿主、完整测试/签名、独立验收及移动真机都是真实闸门，不以整体授权替代。

Run 2 native start 2026-10-07T21:55:56.728Z；22:03:56.728Z 停止扩展；22:05:56.728Z 前终止本轮。子任务截止22:02:45Z，未完成则 native取消/核验/保留现场；无无人监管后台工作。

## Run 3 bounded implementation and next verification unit

用户整体授权持续有效，普通阶段无需再待同一许可。本轮A仅修既有HTML模拟原型事务防护，Cursor独占原型/ui-design/ui-audit；B由Codex独占Session/Contracts/lease与动作桥，复用同一录音和输出链。负责人只审查与记录，不写产品UI。

候选在当前Session保持busy，snapshot公开originalSelection、recognizedInstruction、candidate及精确session/proposal/target身份；当前实现用processing + selectionEditProposal表示待审，不以returnedText结算成功。候选前释放麦克风，120秒过期或取消结束同一Session；Apply只能一次唤醒原Job，随后重复核对target lease才进入原事务。Cancel不准备输出或动剪贴板。NativeDesktopHost动作桥需要由后续Cursor原生审阅视图真实调用，未接UI时不能作为可用候选发布。

下一单元为有充分预算的完整编译/必要修复，先复核Data可用>=10GiB，运行basic/Swift tests与release-style构建，记录准确源码manifest与包哈希。编译通过后由Cursor接现有presentation原生视图，审阅焦点不能使目标失效或偷换目标；使用非激活面板或经验证的焦点契约，不能绕过lease。随后独立验收真实Mac原生输入框与浏览器可编辑区域、Unicode、无写入Cancel、重复Apply、stale/焦点、剪贴板所有权、uncertain无重试和原文恢复。移动仍由原owner先闭合T0并预约设备，不能以手动返回代替自动返回。签名Release、隐私、独立验收及发布前置仍分别记录。

## Run 4 executable compile unit

唯一目标是真实完整SwiftPM工程编译与确证集成错误修复。一个T3-owned Codex Sol/Xhigh/Standard执行者，禁止再委派；负责人独占编排/验收文档，执行者独占必要源码/失败协议fixture和build-result-r4.md。继承整体授权，未代签任何实际验收。

先核对>=10GiB Data可用和本地依赖；不新下载、不删除证据、不停止其他Agent。真实swift build覆盖产品/依赖/资源；basic脚本作用先读再实际执行，不能用parse或synthetic资源shim替代。明确日志起止/exit/源码manifest，错误修复后重编译。足够预算和空间才运行swift test，否则写未运行。命令与child在22:28:50Z前native结束，22:28:30Z主动取消窗口；父22:29:05.508Z停止扩展，目标22:30:35.508Z前native收尾，硬截止22:31:05.508Z。

不做第三次HTML审计、不改UI/移动T0/设备/原线。现存原型丢输入/范围缺口转为原生review验收用例；后续Cursor原生UI消费和独立真实宿主单元均在授权队列中，不是新human许可闸门。完整编译不证明安全替换、Cancel/恢复、隐私、焦点或生产就绪。


### Run4 next concrete compile unit

Full build remains interrupted by Data disk protection, not a confirmed code defect. Use existing `EXTERNAL_VOLUME` isolated scratch/module caches only after checking safe placement and exact locally pinned dependency reuse; no new download, deletion, daemon/permission change. Run full SwiftPM compilation, then basic and complete tests with sufficient budget. Native review UI and real-host proof stay behind compile completion; mobile original-owner T0/device coordination remains in scope. This queue is authorized, not a new human approval gate.


### Run5 bounded external-cache preparation

Owner: one T3-owned Codex executor; root coordinates acceptance only. Prepare isolated external scratch/Swift and Clang module caches/temp and exact locally pinned dependencies. Verify mounted volume identity and write/read hashes; record device mapping only in ignored raw. Recheck source/dependency hashes. Data >=10 GiB remains mandatory before and during any complete build. Below threshold: retain preparation and precise blocker, no cleanup, no compile probe or wait loop. Only one complete build if threshold recovers and sufficient budget remains. No UI/devices/release. Parent native starts22:34:50.880Z; expansion stops22:42:50.880Z; native target22:44:20.880Z/hard22:44:50.880Z. Child native hard22:42:15Z, proactive stop22:41:55Z.


### After Run5: exact offline registration and full compile

Accepted: seven external file probes and19 exact source snapshots with submodules. Not ready as SwiftPM Git working copies. Next owner is one bounded Codex executor: verify fresh Data floor and source hashes; reconstruct task-owned local Git metadata/mirrors from already verified local repositories, preserving all original files; prove real offline SwiftPM dependency registration without changing Package/lock/global config or downloading. Then run one complete build using configured external scratch/modulecache/temp and10GiB Data supervision. Record real compiler arguments/files and exact logs; do not claim configuration-only drafts suffice. Build success precedes basic/tests and Cursor native review, real-host safety, mobile T0, signed release acceptance.


### Run6 bounded exact Git metadata unit

One T3-owned Codex executor exclusively prepares a new EXTERNAL_TASK_ROOT and real local Git working copies/mirrors with exact pinned and submodule revisions, preserving Run5 snapshots and original dependencies. Source/hash equivalence and Git cleanliness are separate from actual SwiftPM registration. Every SwiftPM/compiler/build action requires fresh Data>=10GiB and continuous floor protection; old recovered sample is stale. Only one complete build after registration and adequate supervision window. No Data cleanup, global settings, network dependency download, UI/devices/production edits/release. Parent starts22:50:25.816Z; stop expansion22:58:25.816Z; native target22:59:55.816Z/hard23:00:25.816Z. Child target22:57:15/hard22:57:45; proactive stop22:57:25; commands stop22:56:50.


### After Run6: space-gated real offline registration

19 task-owned real Git mirrors/working copies and exact submodules now accepted; preserve and reuse them. Actual SwiftPM registration remains not run. Only after a fresh Data>=10GiB window, bind current installed Swift/help evidence and isolated paths, configure task-local package mirrors or carefully validated seed state, prove real SwiftPM acceptance of all exact dependencies without download, then one complete build under live10GiB guard and adequate time. Do not recreate metadata or repeat blocked build runs while space remains below the floor. This is an execution dependency, not a new ordinary approval gate.


### Run10 explicit continuation: exact profile/environment diagnosis

User said 继续 on2026-10-11; overall authorization persists and does not constitute acceptance. Fresh Data is now above10GiB, with no cleanup or settings change by this thread. Preserve source and exact local dependencies. One bounded T3-owned Codex performs a finite2×2 census using the two actual Run9 outer profiles and baseline/task environments, keeping the same inner sandbox. Persist premise and rerunnable matrix before any correction; isolate a single variable only with evidence. No third blind workaround, disabling inner protection, UI/device work or rushed complete build. Actual registration/full compile still follows proven safe context with a separate adequate supervision window; native review/focus/privacy, real-host safety and mobile original-owner T0 remain authorized later units.

Parent native starts00:27:30.405Z; target00:37:00.405Z/hard00:37:30.405Z. Child command stop00:34:55Z, proactive owner cancellation00:35:15Z if active; hard native00:35:25Z. All known command groups and actual child terminal must be collected; artifact closure never stands in for native terminal.


### Run11 specific named-rule unit

Root accepted only Run10 finite diagnosis; user explicitly authorizes this subsequent bounded unit. One supervised T3-owned Standard Codex isolates named file-write/context differences under retained actual inner protection. No permissive profile, global permissions/config, blind third workaround, product/UI/device edits or dependency copies before necessity. Finite rerunnable rule census and file/network canaries precede actual installed manifest argument evidence and at mostone offline resolve. Full compilation/basic/tests is a separate later budgeted unit. Historical external roots are absent, exact original19 checkouts are available; newly reused dependencies need fresh submodule/content proof.

Parent native00:40:17.030Z, stop expansion00:48:17.030Z; native target00:49:47.030Z/hard00:50:17.030Z. Child commandsstop00:47:20Z, native target00:47:50Z, cancellation checkpoint00:48:00Z/hard00:48:20Z. Owner records and verifies actual task/native/process terminal, noartifact timestamp substitution. Scope, dependencies, owner, outputs and acceptance are in workflow.json.


## Current Draft delivery order

Publish the frozen combined source as a Draft after the controlled mobile whitelist import and real writer settlement. Disclose fixture and loader failures, earlier source-specific checks, locked-host and unavailable-device limits. Continue the confirmed fixture repair, SDK loader evidence, concrete native UI follow-up, complete final checks, and independent acceptance on the same PR. Normal commit and push only; link the PR immediately and use native check events. Do not update historical PR121. Human acceptance and protected production gates stay pending.


## Native UX completion in current Codex, 2026-10-16

The user explicitly removes the T3 execution dependency and authorizes safe deletion of proven regenerable caches, retaining source, models, user data and all verification evidence. Current Codex owns this finite completion; no new T3 thread, watcher, timer, credentials or permissions. Existing overall implementation/PR authorization remains, with no fabricated human acceptance. Preserve the existing native UX, localization, materials, action order and nonactivating target policy.

Verify the real production SelectionReviewView in native NSPanel at280/320/420-point widths, English/Chinese and light/dark. Use public native document scrolling to prove both original and candidate ends can be reached, reverse scroll returns, and footer controls remain visible. Preserve failed synthetic-wheel diagnostics separately: a windowNumber0 event is not physical-wheel proof. Verify supplied accessibility order, localized labels, disabled/stale and once-only actions; label structural fallback explicitly and keep all of this separate from spoken VoiceOver navigation. Extend native integrated Apply/Cancel coverage and repair only reproduced defects. No model, microphone, external host, device or global VoiceOver/auth/settings operation.

Use the existing19 pinned local dependencies and native SwiftPM sandbox; fresh mutable build epochs and module/temp caches on the task-owned external volume, with the unchanged10GiB Data floor. Seal complete products before guarded runtime use; do not mutate old sealed bundles or retry the exhausted SwiftTesting-loader workaround. Run relevant native/owner cases, basic/SDLC and meaningful full checks in the supported context, independently inspect actual screenshots and final diff, then commit/push to PR124 and verify remote SHA/CI. Record scoped passes separately from real host/device/signing/production acceptance.

## Current Codex HUD correction, 2026-10-17

1. Compare pre-feature native HUD/source with review. Reuse its surface, circular button renderer and typography; remove the separate review button style and large form treatment.
2. Rebuild the real SwiftPM test bundle with the retained native build sandbox, exact19localpins, external scratch and continuous10GiBDatafloor. Preserve all earlier frozen artifacts.
3. Exercise native Apply/Cancel/expiry/repeat/Restore/remote consent, and compare actual recording/review button geometry and short/long native renders in both languages and appearances. Retain source, binary and image hashes.
4. Complete the applicable ANTI_SLOP audit, independent review, SDLC/basic/diff checks; update the existing DraftPR124. Actual external host, physical wheel, spoken VoiceOver and mobiledevice gates remain open.
