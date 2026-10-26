# Verification: Stop the Xiaomi remote's voice key from triggering macOS Dictation

**Status:** approved
**Approved-by:** User, explicit chat decision (2026-10-26): approve this verification with the hardware checks waived as recorded in "Waiver (2026-10-26)" at the end
**Approved-date:** 2026-10-26
**Upstream:** [plan](plan.md)

Batches 0 to 7 are implemented and committed. Batch 8 (independent hardware verification) was run **only in part**: the code review and the hidutil-based lifecycle checks ran, but every check that needs the user to press the remote (A/B control, stress presses, reconnect, sleep/wake, prompts) produced no data because no remote key presses reached the probe. Those checks were not re-run; the user waived them on 2026-10-26 (see "Waiver (2026-10-26)" at the end), and that waiver, not a pass, is what this approval rests on. Everything under "Implementer's results" was produced by the implementer and does not replace the independent verifier's run.

## Batch 0 — feasibility gate (2026-10-25, spike code only, nothing shipped)

Spike: a throwaway tool outside the repo. It enumerates HID services through `IOHIDEventSystemClient`, merges `UserKeyMapping` F5 (`0x7_0000_003E`) → `0` while preserving other entries, reads the value back, and polls every 0.5 s for new services. A listen-only event tap counts key events to detect leaks.

| Gate item | Result | Evidence |
|---|---|---|
| Compiles under Swift 6.4, language mode 5 | pass | `swiftc` build clean; production code builds with `swift build` |
| Needs no permission Utter does not hold | pass | An ad hoc signed app with no Accessibility and no Input Monitoring grant read, set and restored `UserKeyMapping`. No system prompt appeared in any run, confirmed by the user twice |
| Keep the `IOHIDEventSystemClient` alive while using its services | required | Releasing the client early crashed the first probe with `EXC_BAD_ACCESS`. The production service wrapper retains its client and the provider wraps enumeration in `withExtendedLifetime` |
| Mapping survives a remote disconnect and reconnect | **no, must be re-applied** | Disconnect: service `1000d9eae` disappeared (t = 58 s). Reconnect: new service `1000da8ae` appeared with `hasF5 = false` (t = 60 s) |
| Mapping can be re-applied after reconnect within 30 s | pass | First sighting of the new service and the verified write-back happened in the same poll cycle, so latency is at most one poll interval, far below 30 s |
| Voice key leaked F5 while the mapping was active | none observed | Over the whole 420 s window, including stress presses, the remote-only reconnect and presses right after reconnecting: `f5_down=0 f5_up=0` |
| Other keys still work | pass | `other_key_events=2` (the arrow key down/up). The tap was alive and counting |

Prior control from the spec stage: without the mapping the same real presses produced 17 F5 downs and 2 ups; with it, 0.

Limits: the first measurement round was lost (the watcher was killed when its launching command ended) and redone with a watcher confirmed alive; there was no in-run positive control; volume keys are system-defined events the tap does not count; sleep/wake persistence was not measured.

Gate decision: passed. The user chose to continue with the device-level remap (2026-10-25).

## Implementer's results (Batches 1 to 7)

| Batch | Commit | What it delivers |
|---|---|---|
| 1 | `2348801` | `RemoteKeyRemapState`, diagnostics fields, pure `RemoteKeyMappingPolicy` |
| 2 | `ace9eab` | `RemoteKeyMappingController`: apply, read-back, bounded retry, one re-apply then `conflict`, restore |
| 3 | `4b95ce9` | `RemoteHIDServiceProvider` (public IOKit `hidsystem` API), `RemoteKeyMappingCodec`, `RemoteKeyServiceCatalog` |
| 4 | `4953914` | Setting `remoteKeyRemapEnabled`, default on, stores nothing until changed |
| 5 | `9e71425` | Plugin wiring: start on ready, follow the setting, restore on revoke and dispose, diagnostics overlay, bridge-ready trigger |
| 6 | `9c3758e` | `RemoteKeyRemapRow` on the Remote page, en and zh-Hans strings, render harness, screenshots |
| 7 | `f7f6488` | README (en, zh), release runbook entry, kill switch and manual clear command |

### Automated checks (2026-10-25)

- New tests: 52 plus one render test that only writes screenshots when `UTTER_RENDER_DIR` is set. Policy 14, controller 16, codec 5, service catalog 6, plugin wiring 7, settings 2, localization text 1, read-only hardware smoke 1.
- Full `swift test`: all 15 test bundles passed; `OpenTypeTests` ran 523 tests, 19 skipped, 0 failures. The real remote's mapping was not changed by the run.
- `bash scripts/ci-basic-checks.sh` passed before each of the seven commits; `bash scripts/sdlc-checks.sh` passed.
- Release-style build: `bash scripts/build-app.sh --app-only` succeeded and its release artifact verification passed (2026-10-25). The app is signed ad hoc with the hardened runtime because this Mac has no usable Developer ID or project identity, so the "no extra permission" claim is measured on that build, not on a Developer ID build. The release workflow's signed artifact needs the same check before publishing.
- Read-only hardware smoke: the real provider found the remote's service `4295862446` (`0x1000da8ae`) and decoded its `UserKeyMapping` 20 times without a crash, and wrote nothing.
- Measured cost that shaped Batch 3: this Mac has 244 HID services. Reading vendor and product for all of them took 18.6 ms per poll against 1.65 ms for registry ids only, so the catalog remembers definite verdicts and only reads properties for services it has not judged.

### Deviations from the approved plan and spec

1. **Service-appearance trigger is a 1 s poll.** The public SDK headers declare client creation, `CopyServices`, and service `CopyProperty`/`SetProperty`, but not a device-matching callback; the callback exists only as an undeclared exported symbol. Using it would depend on a private interface, so the public-API poll was chosen (the spec allowed either).
2. **Two small pure files were added in Batch 3** (`RemoteKeyMappingCodec`, `RemoteKeyServiceCatalog`), outside `Native/`, so the decoding rules and the poll-cost cache are unit-tested.
3. **Plugin wiring tests live in `Tests/OpenTypeTests`**, not `UtterRemoteMicTests`, because the plugin fixtures and fake settings are there. The existing plugin fixture now injects a fake provider so no test can touch a real remote.
4. **`waitingForService` is also reported during bounded retries** after a failed write, and `failed` once the attempts are exhausted. The spec's table says `failed` for a set failure; this keeps `failed` meaning "gave up".
5. **State type name** follows the plan (`RemoteKeyRemapState`), not the spec's draft name `RemoteKeyGuardState`.
6. **No separate verify at the start of each remote voice session.** The 1 s poll already reads the mapping and re-applies once on a foreign overwrite, and the bridge ready transition calls `expectRemote()`, which verifies immediately.
7. **A mapping the codec cannot represent** (extra keys in an entry, non-numeric values) is never rewritten: the provider reports it unreadable and the controller ends in `failed` without writing. This was not in the spec and is stricter than it.

### Visual QA (render harness, not the shipped window)

The real `RemoteMicSettingsView` was rendered into an AppKit window through `NSHostingView` in light and dark, English and Chinese, for each state. The first render showed the long conflict and failed sentences squeezing the status row, so the row now shows a short label with the longer explanation as a caption below. Screenshots in [evidence](evidence/): `active-zh-light`, `active-en-dark`, `waiting-en-light`, `no-remote-zh-dark`, `conflict-en-dark`, `failed-zh-light`, `setting-off-en-light`.

Limits: the window is not key, so toggles draw in the inactive grey style (the knob position still shows on or off); this is not the installed app's window. The independent verifier must look at the real Remote page in the release-style build.

## Batch 8 — independent verification

**Verifier:** 独立验证 Agent（与实现者不同上下文；未修改 `Sources/`、`Tests/` 或实现脚本；仅编辑本文件该节、`evidence/batch8-*` 与 `/tmp/f5verify/` 探针。）

**Date:** 2026-10-25 (UTC+8)

**Build:** `/Users/chenli/.cursor/worktrees/opentype/remote-dictation-key/dist/Utter.app` — ad hoc，`com.opentype.voiceinput`，HEAD `0e3096d`（见 `evidence/batch8-baseline-state.txt`）。

**Session limits:** 开始闸门两次（各 600 s）均未检测到遥控器 keycode 126；C/F/G/H 依赖用户的遥控器操作未发生。探针 `CGEvent` tap 创建成功（listen-only）。生命周期与 hidutil 项在 dist 构建上自动执行；已按原始状态恢复（`evidence/batch8-restore-readback.txt`）。

### Results (A–K)

| ID | Result | Key data | Evidence |
|---|---|---|---|
| **A** 独立代码审查 | **通过（有发现）** | `git diff 467e934..HEAD -- Sources Tests` 通读；VID/PID 过滤、仅 F5→0、有界 retry、冲突后停止重写、disable/quit restore 与 spec D1–D5 一致。见下方缺陷表。 | 本表 + 实现 diff |
| **B** 前置记录 | **通过** | 安装版 Utter 运行中；`remoteKeyRemapEnabled` 键不存在；遥控器已有手动 F5→0；dist `codesign` ad hoc。 | `batch8-baseline-state.txt` |
| **C** A/B 对照 | **未运行（阻断）** | 闸门 `gate126Down=0`（两次 ×600 s）。C1 30 s：`f5Down=0 f5Up=0`（设置关、映射空，无法证明对照有效）。C2 150 s：同上 0/0（无法验证 ≥50 次语音键零泄漏）。 | `batch8-gate.txt`, `batch8-gate-retry.txt`, `batch8-C1-measure.txt`, `batch8-C2-measure.txt` |
| **D** 其他设备/按键 | **部分通过** | 内置键盘 `UserKeyMapping (null)`（VendorID 1452）。遥控器在 active 时仅 F5→0 一条（E2 后保留无关 Src `30064771076`）。**未测** 方向键/Return/音量事件（无遥控器按键）。 | `batch8-lifecycle.txt`, C2 映射轮询 |
| **E** 生命周期 hidutil | **部分通过** | **E1** 优雅退出后外来 F5 恢复（Dst `30064771073`），我们的条目不在。**E2** 启动 ~1 s 内写入 F5→0，无关条目保留。**E3** 第一次清空后 ~3 s 仅重应用我们的条目；**第二次清空后映射保持空 ≥12 s**（符合冲突停止重写）；但第一次清空后**丢失**原无关条目（见缺陷）。**E4** 设置关：3 s 内映射仍空、未写入。 | `batch8-lifecycle.txt`, `batch8-lifecycle-raw.txt` |
| **F** 蓝牙重连 | **未运行** | 需用户在系统设置中断开/连接；闸门未通过。 | — |
| **G** 睡眠/唤醒 | **未运行** | 30 s 内无三次方向键上同意（gate 未完成）。 | `batch8-G-sleep-consent.txt` |
| **H** 权限提示 | **部分** | 全程无 Utter 日志中 HID/IOHID/TCC 拒绝行（`log show` 空）。用户弹窗问卷：**未回答**（20 s 内无 key126）。Batch 0 已测 dist 无额外权限；本次未复测弹窗。 | `batch8-H-permission-poll.txt` |
| **I** ATVV 基线 | **未运行** | `remoteMicEnabled` 读回为 `1`（与任务描述“关”不一致）；无安全的前变更会话日志对比，未启用 remote mic 做硬件会话。 | `batch8-baseline-state.txt` |
| **J** 真实 Remote 设置页截图 | **未运行** | 未做无额外权限的 shipped 设置窗口截取（避免 Automation/屏幕录制弹窗）。 | 实现者 render harness 截图仍有效参考 |
| **K** 恢复原始状态 | **通过** | 已退出 dist；`defaults delete remoteKeyRemapEnabled`（键不存在）；遥控器 F5→0 已写回；`/Applications/Utter.app` 运行。 | `batch8-restore-readback.txt` |

### Defects found (verifier)

| Severity | Location | Finding |
|---|---|---|
| **重要** | `RemoteKeyMappingController.swift` `attempt` (~110–124) | 运行中若外部 `hidutil` 将 `UserKeyMapping` **整表清空**，控制器重应用时只对当前 `existing=[]` 调用 `Policy.applying`，**不会从 phase 内 `original` snapshot 恢复无关条目**。实测 E3 第一次清空后无关映射 `30064771076→30064771073` 消失，仅剩 F5→0。与 spec「无关条目 never dropped」在“外部整表清除”场景不符。 |
| **次要** | `RemoteKeyMappingController.swift` `verifyNow()` | 对 spec「每次 remote voice session 开始 verify」无独立 hook；依赖 1 s 轮询 + `expectRemote()`（与实现者偏差 #6 一致，可接受但覆盖略弱）。 |

未发现：无界重试、错误 VID/PID 写入、restore 后仍写、dispose 后泄漏写映射、不可表示条目被静默丢弃（codec nil → failed，偏差 #7）。

### Evaluation of implementer's seven plan/spec deviations

| # | Verifier opinion |
|---|---|
| 1 1 s 轮询 | **合理** — 与 Batch 0 一致，重连延迟 ≤1 s 可接受。 |
| 2 Codec/Catalog 额外文件 | **合理** — 可测、未扩大设备范围。 |
| 3 插件测试在 OpenTypeTests | **合理** — fixture 位置务实。 |
| 4 waitingForService 含 retry 中 | **合理** — UX 与 “failed=放弃” 一致。 |
| 5 RemoteKeyRemapState 命名 | **合理** — 随 plan。 |
| 6 无 per-session verify | **可接受** — 轮询 + bridge ready 基本等价；独立 verify 未测 ATVV 会话。 |
| 7 不可表示条目不写 | **合理且更安全** — 比 spec 更严，符合失败模式表精神。 |

### Uncovered / blocked

- Spec/plan **go/no-go**：≥50 次语音键、长按 5 s+、C1 正对照 F5>0 — **未执行**（用户未按遥控器；闸门 key126=0）。
- 重连空窗 F5 泄漏、睡眠/唤醒 — **未执行**。
- 其他键与音量 systemDefined — **未执行**。
- Developer ID 签名构建上的 D4 — **未测**（本机仅 ad hoc dist）。

### Artifacts

- 探针源码：`evidence/batch8-F5VerifyProbe.swift`
- 日志（原为 `.log`，因仓库 `.gitignore` 忽略 `*.log` 而改名为 `.txt`，内容未改）：`evidence/batch8-gate*.txt`, `batch8-C1-measure.txt`, `batch8-C2-measure.txt`, `batch8-lifecycle.txt`, `batch8-lifecycle-raw.txt`（同一次运行的完整 hidutil 读回，E3 细节以它为准）, `batch8-*-readback.txt`

**Verifier conclusion:** 自动化生命周期（E2/E4/E1 主体）与代码审查支持合并方向，但 **Batch 8 硬件 A/B 与重连/睡眠闸门未满足 spec 高风险签字条件**。建议在用户在场重新跑 C/F/G（或复用本探针 + 同一 dist 构建）后再将 verification 阶段标为 approved。

### Implementer's response to the verifier's report

The verifier's text above is kept unedited. This section is the implementer's reading of it, checked against the raw logs.

**1. The "important" defect is not a defect.** `batch8-lifecycle-raw.txt` shows both entries (the unrelated `30064771076→30064771073` and our F5→0) present at 18:22:42, immediately before the verifier's own `hidutil … --set '{"UserKeyMapping":[]}'`. That command emptied the whole table, so the unrelated entry was removed by the clearer, not by Utter. Utter then read an empty table and wrote only its own entry, which is what the spec requires: unrelated entries that exist are preserved (E2 shows this), and entries another tool deliberately removed are not ours to bring back. Resurrecting them would also contradict the rule that restore never clobbers a newer state. Severity: none. The behavior is now pinned by `testATableClearedByAnotherToolIsReappliedWithOnlyOurEntryAndNothingIsResurrected` (passes).

**2. The minor finding (no per-voice-session verify) stands** and is already recorded as deviation 6. It is covered by the 1 s poll and by `expectRemote()` on bridge-ready.

**3. Why C/F/G/H/D-keys produced no data.** The gate never saw three arrow-up presses, so the verifier correctly did not claim results. The first gate window (18:02–18:12 UTC) recorded Mac keyboard activity (for example 62 events of keycode 51 and 38 of keycode 49, counting key down and key up separately), 4 right-arrow events, 4 Return events and no arrow-up. The tap cannot tell which device sent a key, so whether those 4+4 events came from the remote is unknown. The second window (18:12–18:22 UTC, about 02:00 local) recorded no events at all, so nobody was at the Mac. C1 and C2 then ran their measurement windows without a passed gate, and their 0/0 is meaningless: C1's positive control (F5 > 0 with the setting off) did not occur, so C1 and C2 prove nothing about leaks. These are counted as **not run**, not as passed.

**4. Corrections to the verifier's brief.** I told the verifier that `remoteMicEnabled` was off; the baseline shows it is `1`, so an ATVV-session comparison (item I) may be feasible in the re-run. The verifier's strict gate (keycode 126 only) is fragile; for the re-run it should accept any three arrow-key presses (keycodes 123–126) with the Mac keyboard untouched.

**5. State after the run (checked by the implementer, not only the verifier).** `/Applications/Utter.app` running (new PID 33917; the old PID 44932 was the pre-run process), `remoteKeyRemapEnabled` absent, remote `UserKeyMapping` is exactly F5→0 on `1000da8ae`, working tree has no stray files. A stray `''` file the verifier created by a shell redirect was renamed to `evidence/batch8-lifecycle-raw.txt`. The repository ignores `*.log`, so all `batch8-*.log` evidence was renamed to `.txt` so it can be committed.

**6. Still required before this stage can go to approval:** a re-run with the user at the Mac, covering C1 (positive control F5 > 0), C2 (at least 50 voice-key presses including long presses, F5 = 0, arrows/Return/volume still work), F (reconnect), G (sleep/wake, optional), H (any permission prompt), and ideally I and J. Status stays `draft`.

## Waiver (2026-10-26)

On 2026-10-25 the user said the remaining hardware verification was not needed ("算了，不用验证了，应该没什么大的问题"). On 2026-10-26 the user chose, in answer to an explicit question, to approve this `verification.md` with those checks waived and to merge PR #130 (answer: approve, waive the hardware items). This section is the record. **It is a waiver, not verification.**

Not run, and not claimed:

- the voice-key A/B control (setting off versus on) with real presses, and at least 50 voice-key presses;
- the reconnect leak window and the 1 s re-apply window with real presses;
- sleep and wake;
- arrow keys, Return and volume keys pressed on the remote while the mapping is active;
- the permission and prompt paths on a release-signed build;
- the independent verifier's conclusion above stays as written: its hardware A/B and reconnect/sleep gates did not meet the spec's high-risk sign-off condition.

What this change was verified with instead: the Batch 0 hardware gate (no prompt, mapping lost on reconnect and re-applied within one poll, 0 F5 over 420 s), the independent verifier's code review and hidutil lifecycle checks (E1, E2, E4), unit and fake-device tests, and render harness screenshots.

Merge state recorded at the same time: `main` was merged into the branch on 2026-10-26 (one conflict, `RemoteMicSettingsView.swift`, resolved by keeping the new Settings layout and adding the remap row as its own section; one test updated for the new `RemoteMicSettingsView(platform:)` initializer). `swift test` after the merge: 548 tests, 0 failures, 24 skipped.

Defect found by that merge and fixed before it landed: `main` now builds the page as `RemoteMicSettingsView(platform: platform)` and no longer injects `platform` into the environment, but `RemoteKeyRemapRow` reads `PlatformProjection` with `@EnvironmentObject`. The merged tree would have trapped when the Remote page opened. The existing render test hid it because it injected the environment object itself. Fix: the page injects `platform` into the row. Regression guard: `RemoteKeyRemapRenderTests.testRemotePageBuildsWithOnlyTheSettingsEnvironment` builds the page with only the settings environment (it trapped with signal 5 before the fix and passes after), and it is not skipped in a normal run.

Residual risk accepted by the user with this waiver: a crash or SIGTERM leaves F5 mapped to nothing until the HID service is recreated; the re-apply window after a reconnect is up to about 1 s; the unmeasured items above. Rollback is unchanged (turn the Remote-page row off, `defaults write … remoteKeyRemapEnabled -bool false`, hidutil clear, revert the commits).
